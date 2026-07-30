-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- Lightroom side of the background bridge (see bridge/sdcbridge.go).
--
-- WHAT THIS DOES
--
-- A small local HTTP server serves the editor page under
-- http://127.0.0.1:PORT/. Because the page then has a real origin, it can
-- use fetch and Server-Sent-Events without CORS and without running into
-- the Private-Network block that killed the earlier loopback attempt.
--
-- Lightroom itself never listens. It only calls out, once a second:
--
--	POST /sync  – push the current photo's data (only when the selection
--	              actually changed) and pick up any pending result in the
--	              same response. Doubles as the heartbeat that keeps the
--	              helper alive.
--
-- PAUSING CALLS – the single most important rule in this file. In Lua 5.1
-- a coroutine cannot yield across a C function, and pcall IS a C function.
-- Anything that waits (LrTasks.sleep, LrTasks.execute, LrHttp.get/post,
-- getTargetPhoto, getPropertyForPlugin, withWriteAccessDo) therefore must
-- NOT sit inside a pcall, not even an outer one several levels up. Only
-- non-pausing work (io.*, json, LrPathUtils, LrFileUtils.exists/delete,
-- LrPrefs) is wrapped below.
--
-- UNVERIFIED, flagged deliberately:
--	* the detached launch line, especially the Windows variant – it is
--	  built as a .bat file precisely because quoting through cmd is
--	  fragile. If the helper does not come up, the log file named in
--	  bridgeLogPath() is the first place to look.
--	* whether a process started this way outlives Lightroom. It does not
--	  matter much: the helper shuts itself down once the heartbeats stop.

local LrApplication = import 'LrApplication'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local MediaWikiUtils = require 'MediaWikiUtils'
local MediaWikiSdcData = require 'MediaWikiSdcData'
local json = require 'JSON'

local MediaWikiSdcBridge = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- How often Lightroom talks to the helper. Also the granularity at which
-- a photo change reaches the open page.
local SYNC_SECONDS = 1

-- The helper shuts itself down after this long without a heartbeat. Must
-- be comfortably longer than SYNC_SECONDS.
local IDLE_TIMEOUT = '3m'

-- How long to wait for the helper to write its port file after launch.
local START_TIMEOUT = 10

-- Budget for every candidate except the last one, so that a build for the
-- wrong architecture is not felt as a hang.
local FAST_TIMEOUT = 3

--------------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------------

MediaWikiSdcBridge.running = false   -- is our sync loop active?
MediaWikiSdcBridge.port = nil
MediaWikiSdcBridge.token = nil
MediaWikiSdcBridge.lastError = nil
MediaWikiSdcBridge.subscribers = 0   -- open editor pages, as reported by /sync
MediaWikiSdcBridge.lastSync = nil

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

local function tempDir()
	local dir
	pcall(function() dir = LrPathUtils.getStandardFilePath('temp') end)
	if not dir then
		pcall(function() dir = LrPathUtils.getStandardFilePath('desktop') end)
	end
	return dir
end

-- Architektur des Macs, einmal ermittelt und gemerkt.
--
-- Es gibt keinen dokumentierten SDK-Aufruf dafuer, also `uname -m`. Das
-- PAUSIERT (LrTasks.execute) und darf deshalb nicht in einem pcall stehen -
-- start() ist ohnehin pausierend, dort ist es richtig aufgehoben.
local macArch = nil
local function detectMacArch()
	if macArch ~= nil then return macArch end
	local out = LrPathUtils.child(tempDir(), 'lrmediawiki-sdc-arch.txt')
	LrTasks.execute('/usr/bin/uname -m > "' .. out .. '" 2>/dev/null')
	-- Bewusst mit io.* statt mit readFile(): readFile wird weiter unten in
	-- dieser Datei definiert und waere hier oben noch nicht sichtbar. Ein
	-- `local function` gilt erst ab seiner Definition - der Aufruf waere ein
	-- Griff nach einer globalen Variablen und damit ein Laufzeitabbruch, den
	-- `luac -p` nicht findet. io.* pausiert nicht.
	local text = nil
	pcall(function()
		local fh = io.open(out, 'r')
		if fh then text = fh:read('*a'); fh:close() end
	end)
	pcall(function() LrFileUtils.delete(out) end)
	macArch = type(text) == 'string' and (text:match('([%w_]+)') or '') or ''
	MediaWikiUtils.trace('SDC bridge: uname -m -> "' .. tostring(macArch) .. '"')
	return macArch
end

-- Jede mitgelieferte Programmdatei, die es wirklich gibt, in der Reihenfolge,
-- in der sie versucht werden soll.
--
-- Bis 2.0.42 wurden auf dem Mac BEIDE Scheiben hintereinander gestartet, weil
-- die Architektur nicht erkannt wurde. Das ist Unsinn: eine Fassung fuer die
-- falsche Architektur kann nicht laufen, und der Fehlversuch kostet nur Zeit.
-- Jetzt entscheidet `uname -m`, und wenn `baue-bruecke.sh` mit lipo eine
-- universelle Fassung erzeugt hat, gibt es ohnehin nur eine Datei.
--
-- PAUSIEREND auf dem Mac (wegen detectMacArch) - nicht in einem pcall aufrufen.
local function binaryCandidates()
	local binDir = LrPathUtils.child(_PLUGIN.path, 'bin')
	local names
	if WIN_ENV == true then
		names = { 'sdcbridge-win-amd64.exe' }
	else
		names = MediaWikiSdcData.macOrder(detectMacArch())
	end
	local found = {}
	for _, name in ipairs(names) do
		local p = LrPathUtils.child(binDir, name)
		if LrFileUtils.exists(p) then found[#found + 1] = p end
	end
	return found
end

local function portFilePath()
	return LrPathUtils.child(tempDir(), 'lrmediawiki-sdc-bridge-port.json')
end

local function pagePath()
	return LrPathUtils.child(tempDir(), 'lrmediawiki-sdc-editor.html')
end

function MediaWikiSdcBridge.bridgeLogPath()
	return LrPathUtils.child(tempDir(), 'lrmediawiki-sdc-bridge.log')
end

--------------------------------------------------------------------------------
-- Small non-pausing helpers
--------------------------------------------------------------------------------

local function readFile(path)
	local content
	local ok = pcall(function()
		local fh = assert(io.open(path, 'r'))
		content = fh:read('*a')
		fh:close()
	end)
	if ok then return content end
	return nil
end

local function writeFile(path, text)
	local ok, err = pcall(function()
		local fh = assert(io.open(path, 'w'))
		fh:write(text)
		fh:close()
	end)
	return ok, err
end

local function decode(text)
	if type(text) ~= 'string' or text == '' then return nil end
	local ok, value = pcall(function() return json:decode(text) end)
	if ok and type(value) == 'table' then return value end
	return nil
end

local function encode(value)
	local ok, text = pcall(function() return json:encode(value) end)
	if ok and type(text) == 'string' then return text end
	return nil
end

function MediaWikiSdcBridge.baseUrl()
	if not MediaWikiSdcBridge.port then return nil end
	return 'http://127.0.0.1:' .. tostring(MediaWikiSdcBridge.port)
end

-- The URL to open in the browser.
function MediaWikiSdcBridge.editorUrl()
	local base = MediaWikiSdcBridge.baseUrl()
	if not base or not MediaWikiSdcBridge.token then return nil end
	return base .. '/?t=' .. MediaWikiSdcBridge.token
end

--------------------------------------------------------------------------------
-- Writing the editor page
--------------------------------------------------------------------------------

-- The helper reads the page from disk on every request, so the page only
-- has to be written once per session – and a change to the template shows
-- up after a browser reload without rebuilding anything.
--
-- Note that NO payload is injected here: in bridge mode the page fetches
-- its data from /state. The sample payload baked into the template stays,
-- which is what makes the file still usable when opened on its own.
local function writeEditorPage()
	local okTemplate, templateMod = pcall(function() return require 'SdcEditorTemplate' end)
	if not okTemplate or type(templateMod) ~= 'table' or type(templateMod.html) ~= 'string' then
		return nil, 'Die Editorseite (SdcEditorTemplate.lua) fehlt oder lässt sich nicht laden.'
	end
	local path = pagePath()
	local ok, err = writeFile(path, templateMod.html)
	if not ok then
		return nil, 'Die Editorseite ließ sich nicht schreiben: ' .. tostring(err)
	end
	return path
end

--------------------------------------------------------------------------------
-- Talking to the helper – PAUSING
--------------------------------------------------------------------------------

local function httpJson(url, body)
	local headers = {
		{ field = 'Content-Type', value = 'application/json' },
		{ field = 'User-Agent', value = 'LrMediaWiki2-bridge' },
	}
	-- NOT inside a pcall: LrHttp pauses.
	local resultBody, resultHeaders = LrHttp.post(url, body or '{}', headers)
	local status = resultHeaders and resultHeaders.status or nil
	return resultBody, status
end

-- Is a helper answering on this port? Uses /health, which needs no token.
local function probe(port)
	-- ACHTUNG, hier lag bis 2.0.37 ein Fehler: LrHttp.get gibt (body, headers)
	-- zurueck, NICHT (body, status). Der zweite Rueckgabewert ist eine Tabelle,
	-- ein Vergleich mit 200 ist deshalb IMMER wahr-ungleich und die Pruefung
	-- schlug immer fehl, obwohl der Server sauber antwortete. Der Status steht
	-- in headers.status - genau so macht es MediaWikiApi.lua seit Jahren.
	local body, headers = LrHttp.get('http://127.0.0.1:' .. tostring(port) .. '/health')
	local status = headers and headers.status or nil
	if status ~= 200 then
		MediaWikiUtils.trace('SDC bridge probe: port ' .. tostring(port)
			.. ' -> status ' .. tostring(status))
		return false
	end
	local data = decode(body)
	if not (type(data) == 'table' and data.app == 'sdcbridge') then
		MediaWikiUtils.trace('SDC bridge probe: port ' .. tostring(port)
			.. ' answered 200, but not with sdcbridge JSON: ' .. tostring(body))
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Starting the helper – PAUSING (LrTasks.execute)
--------------------------------------------------------------------------------

-- Builds the detached launch command. On macOS a trailing "&" is enough.
-- On Windows the command goes through cmd, where quoting an executable
-- path that contains spaces AND passing arguments is notoriously
-- error-prone, so a one-line .bat is written and that is executed instead.
local function launch(bin, token, page, portFile, logFile)
	local args = ' --token=' .. token
		.. ' --page="' .. page .. '"'
		.. ' --portfile="' .. portFile .. '"'
		.. ' --log="' .. logFile .. '"'
		.. ' --idle=' .. IDLE_TIMEOUT

	if WIN_ENV == true then
		local batPath = LrPathUtils.child(tempDir(), 'lrmediawiki-sdc-bridge-start.bat')
		local bat = '@echo off\r\n'
			.. 'start "" /B "' .. bin .. '"' .. args .. '\r\n'
		local ok, err = writeFile(batPath, bat)
		if not ok then
			return false, 'Startdatei ließ sich nicht schreiben: ' .. tostring(err)
		end
		-- LrTasks.execute pauses – no pcall around it.
		local code = LrTasks.execute('""' .. batPath .. '""')
		return true, nil, code
	end

	local cmd = '"' .. bin .. '"' .. args .. ' >/dev/null 2>&1 &'
	local code = LrTasks.execute(cmd)
	return true, nil, code
end

-- Starts the helper if it is not already up. Returns true on success.
-- PAUSING – call from an async task, never inside a pcall.
function MediaWikiSdcBridge.start()
	MediaWikiSdcBridge.lastError = nil

	-- Already up in this session?
	if MediaWikiSdcBridge.port and probe(MediaWikiSdcBridge.port) then
		return true
	end

	local dir = tempDir()
	if not dir then
		MediaWikiSdcBridge.lastError = 'Kein temporäres Verzeichnis gefunden.'
		return false
	end

	local candidates = binaryCandidates()
	if #candidates == 0 then
		MediaWikiSdcBridge.lastError = 'Die Hintergrund-App fehlt im Ordner "bin"\n'
			.. 'des Zusatzmoduls (' .. tostring(LrPathUtils.child(_PLUGIN.path, 'bin')) .. ').'
		return false
	end

	local page, pageErr = writeEditorPage()
	if not page then
		MediaWikiSdcBridge.lastError = pageErr
		return false
	end

	local token = MediaWikiSdcData.makeToken(tostring(page))
	local logFile = MediaWikiSdcBridge.bridgeLogPath()
	local portFile = portFilePath()

	-- Try each shipped build until one reports a port. A build for the wrong
	-- architecture simply never writes the port file, so the loop is also the
	-- architecture check. Only the LAST candidate gets the full timeout; the
	-- earlier ones fail fast so a wrong guess is not felt as a hang.
	local info, lastLaunchErr = nil, nil
	for index, bin in ipairs(candidates) do
		-- A leftover port file from a crashed helper would be read as if a
		-- helper were running, so it goes first – before every attempt.
		if LrFileUtils.exists(portFile) then
			pcall(function() LrFileUtils.delete(portFile) end)
		end

		local launched, launchErr = launch(bin, token, page, portFile, logFile)
		if not launched then
			lastLaunchErr = launchErr
		else
			local budget = (index == #candidates) and START_TIMEOUT or FAST_TIMEOUT
			-- Wait for the port file. LrTasks.sleep pauses – no pcall.
			local waited = 0
			while waited < budget do
				LrTasks.sleep(0.25)
				waited = waited + 0.25
				if LrFileUtils.exists(portFile) then
					local candidateInfo = decode(readFile(portFile))
					if candidateInfo and tonumber(candidateInfo.port) then
						info = candidateInfo
						break
					end
				end
			end
			if info then
				MediaWikiUtils.trace('SDC bridge: started ' .. tostring(bin))
				break
			end
			MediaWikiUtils.trace('SDC bridge: no port file from ' .. tostring(bin))
		end
	end

	if not info and lastLaunchErr then
		MediaWikiSdcBridge.lastError = lastLaunchErr
		return false
	end

	if not info then
		MediaWikiSdcBridge.lastError =
			'Die Hintergrund-App hat sich nicht gemeldet.\n\n'
			.. 'Protokoll: ' .. tostring(logFile)
		MediaWikiUtils.trace('SDC bridge: no port file after ' .. tostring(START_TIMEOUT) .. ' s')
		return false
	end

	if not probe(tonumber(info.port)) then
		MediaWikiSdcBridge.lastError =
			'Die Hintergrund-App läuft, antwortet aber nicht auf Port '
			.. tostring(info.port) .. '.'
		return false
	end

	MediaWikiSdcBridge.port = tonumber(info.port)
	MediaWikiSdcBridge.token = token
	MediaWikiUtils.trace('SDC bridge: up on port ' .. tostring(MediaWikiSdcBridge.port))
	return true
end

--------------------------------------------------------------------------------
-- The sync loop – PAUSING throughout
--------------------------------------------------------------------------------

-- Applies a result that came back from the page. Refuses to write if the
-- photo key no longer matches: between opening the page and pressing save
-- the user may have moved on in Lightroom, and silently writing to the
-- wrong photo would be the worst possible outcome.
local function applyIncoming(catalog, result, currentPhoto, currentKey)
	if type(result) ~= 'table' then return end

	local key = MediaWikiSdcData.trim(result.photoKey or '')
	if key ~= '' and currentKey ~= '' and key ~= currentKey then
		MediaWikiUtils.trace('SDC bridge: result for ' .. key
			.. ' but Lightroom is on ' .. currentKey .. ' – not applied')
		local LrDialogs = import 'LrDialogs'
		LrDialogs.message('LrMediaWiki – SDC-Brücke',
			'Das Ergebnis gehört zu einem anderen Foto als dem gerade '
			.. 'ausgewählten. Es wurde nichts geändert.\n\n'
			.. 'Bitte im Editor das richtige Foto wählen und noch einmal speichern.',
			'warning')
		return
	end

	if not currentPhoto then return end

	MediaWikiSdcData.applyResult(catalog, currentPhoto, result)
	MediaWikiUtils.trace('SDC bridge: result applied')

	local LrDialogs = import 'LrDialogs'
	LrDialogs.showBezel('SDC übernommen: ' .. MediaWikiSdcData.describeResult(result), 2)
end

-- The permanent loop. Runs until MediaWikiSdcBridge.running goes false.
-- PAUSING – must run in its own async task with no pcall above it.
function MediaWikiSdcBridge.loop()
	local catalog = LrApplication.activeCatalog()
	local lastKey = ''
	local currentPhoto = nil
	local failures = 0

	while MediaWikiSdcBridge.running do
		LrTasks.sleep(SYNC_SECONDS)
		if not MediaWikiSdcBridge.running then break end

		local url = MediaWikiSdcBridge.baseUrl()
		if not url then break end
		url = url .. '/sync?t=' .. MediaWikiSdcBridge.token

		-- Has the selection changed? getTargetPhoto pauses.
		local photo = catalog:getTargetPhoto()
		local key = MediaWikiSdcData.photoKey(photo)

		local statePart = 'null'
		if photo and key ~= lastKey then
			local targets = catalog:getTargetPhotos()
			local count = targets and #targets or 1
			-- collectPayload pauses (catalog reads) – no pcall.
			local payload = MediaWikiSdcData.collectPayload(photo, count)
			local text = encode(payload)
			if text then
				statePart = text
				lastKey = key
				currentPhoto = photo
				MediaWikiUtils.trace('SDC bridge: pushing ' .. tostring(payload.fileName))
			end
		elseif photo then
			currentPhoto = photo
		end

		local body, status = httpJson(url, '{"state":' .. statePart .. '}')

		if status ~= 200 then
			failures = failures + 1
			-- Three misses in a row means the helper is gone (crashed, or
			-- shut itself down). Stop quietly rather than hammering it.
			if failures >= 3 then
				MediaWikiUtils.trace('SDC bridge: helper unreachable, stopping loop')
				MediaWikiSdcBridge.running = false
				MediaWikiSdcBridge.port = nil
				break
			end
		else
			failures = 0
			MediaWikiSdcBridge.lastSync = os.time()
			local data = decode(body)
			if data then
				MediaWikiSdcBridge.subscribers = tonumber(data.subs) or 0
				if data.result ~= nil and type(data.result) == 'table' then
					applyIncoming(catalog, data.result, currentPhoto, key)
					-- Force a fresh push so the page sees the stored values.
					lastKey = ''
				end
			end
		end
	end

	MediaWikiUtils.trace('SDC bridge: loop ended')
end

--------------------------------------------------------------------------------
-- Public control
--------------------------------------------------------------------------------

-- Starts helper and loop. PAUSING – call from an async task.
function MediaWikiSdcBridge.ensureRunning()
	if MediaWikiSdcBridge.running and MediaWikiSdcBridge.port then
		return true
	end
	if not MediaWikiSdcBridge.start() then
		return false
	end
	MediaWikiSdcBridge.running = true
	LrTasks.startAsyncTask(function()
		MediaWikiSdcBridge.loop()
	end)
	return true
end

-- Stops the loop. The helper notices the missing heartbeats and shuts
-- itself down; there is no need to kill a process from here.
function MediaWikiSdcBridge.stop()
	MediaWikiSdcBridge.running = false
	MediaWikiSdcBridge.port = nil
	MediaWikiSdcBridge.token = nil
	MediaWikiSdcBridge.subscribers = 0
end

function MediaWikiSdcBridge.isEnabled()
	local p = MediaWikiSdcData.prefs()
	-- Opt-in: nothing is launched behind the user's back on first install.
	return p.sdcBridgeEnabled == true
end

function MediaWikiSdcBridge.setEnabled(value)
	pcall(function() MediaWikiSdcData.prefs().sdcBridgeEnabled = (value == true) end)
end

return MediaWikiSdcBridge

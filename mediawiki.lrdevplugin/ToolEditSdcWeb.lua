-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- Opens the structured data of the active photo in a browser page.
--
-- TWO ROUTES, in this order:
--
-- 1. THE BRIDGE (MediaWikiSdcBridge.lua + bridge/sdcbridge.go). A small
--    local HTTP server serves the page, so the page has a real origin and
--    can talk back with fetch and Server-Sent-Events. The page then stays
--    open and follows the photo selection in Lightroom. This is the good
--    one, and it is what runs when the bridge is switched on.
--
-- 2. THE FILE FALLBACK, unchanged since 2.0.31. The page is written to the
--    temp folder and opened as file://; saving triggers a download of
--    lrmediawiki2-sdc-result.json, and a background watcher picks that file
--    up. No ports, no fetch, no firewall rules - it works everywhere, it
--    just cannot follow the selection.
--
-- The fallback is deliberately kept. It is the route that works when the
-- helper binary is missing, when it cannot be launched, or when someone
-- simply does not want a background process.
--
-- PAUSING CALLS: everything that waits (LrTasks.sleep/execute, LrHttp,
-- catalog reads and writes) must stay OUT of pcall - in Lua 5.1 a
-- coroutine cannot yield across a C function, and pcall is one.

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local MediaWikiUtils = require 'MediaWikiUtils'
local MediaWikiSdcData = require 'MediaWikiSdcData'
local MediaWikiSdcBridge = require 'MediaWikiSdcBridge'
local json = require 'JSON'

--------------------------------------------------------------------------------
-- Configuration (file fallback only)
--------------------------------------------------------------------------------

-- The file the browser page downloads and the watcher looks for. Must match
-- the RESULT_FILENAME constant in sdc-editor.html exactly.
local RESULT_FILENAME = 'lrmediawiki2-sdc-result.json'

-- How often the watcher checks (seconds).
local POLL_SECONDS = 2

-- Give up after this many seconds without a file (about 4 hours - long
-- enough for a lunch break, short enough to not run forever if the page was
-- closed without saving).
local MAX_WAIT = 14400

local TITLE = 'LrMediaWiki2 – SDC im Browser'

--------------------------------------------------------------------------------
-- Downloads folder (file fallback only)
--------------------------------------------------------------------------------

-- The standard download folder on each platform. There is no
-- LrPathUtils.getStandardFilePath('downloads'), so we build it from 'home'.
local function getDownloadsFolder()
	local home = LrPathUtils.getStandardFilePath('home')
	if not home then return nil end
	local downloads = LrPathUtils.child(home, 'Downloads')
	if LrFileUtils.exists(downloads) == 'directory' then
		return downloads
	end
	-- German Windows localisation sometimes uses "Downloads" anyway, but
	-- try the English name too just in case.
	downloads = LrPathUtils.child(home, 'Download')
	if LrFileUtils.exists(downloads) == 'directory' then
		return downloads
	end
	return nil
end

local function editorPagePath()
	local dir
	pcall(function() dir = LrPathUtils.getStandardFilePath('temp') end)
	if not dir then dir = LrPathUtils.getStandardFilePath('desktop') end
	return LrPathUtils.child(dir, 'lrmediawiki2-sdc-editor.html')
end

--------------------------------------------------------------------------------
-- Route 2: the file fallback
--------------------------------------------------------------------------------

local function runFileRoute(catalog, photo, photoCount)
	local downloads = getDownloadsFolder()
	if not downloads then
		LrDialogs.message(TITLE,
			'Der Downloads-Ordner konnte nicht ermittelt werden.', 'critical')
		return
	end
	local resultPath = LrPathUtils.child(downloads, RESULT_FILENAME)
	MediaWikiUtils.trace('SDC web editor: result file expected at ' .. resultPath)

	-- If a stale result from an earlier run is still there, remove it so the
	-- watcher does not pick it up immediately.
	if LrFileUtils.exists(resultPath) then
		pcall(function() LrFileUtils.delete(resultPath) end)
		LrTasks.sleep(0.2)
	end

	-- collectPayload pauses (catalog reads) - no pcall around it.
	local payload = MediaWikiSdcData.collectPayload(photo, photoCount)
	local okEncode, jsonText = pcall(function() return json:encode(payload) end)
	if not okEncode then
		LrDialogs.message(TITLE,
			'Die Daten des Fotos ließen sich nicht aufbereiten:\n' .. tostring(jsonText),
			'critical')
		return
	end

	local okTemplate, templateMod = pcall(function() return require 'SdcEditorTemplate' end)
	if not okTemplate or type(templateMod) ~= 'table' or type(templateMod.html) ~= 'string' then
		LrDialogs.message(TITLE,
			'Die Editorseite (SdcEditorTemplate.lua) fehlt oder lässt sich nicht laden.',
			'critical')
		return
	end

	local html, injectErr = MediaWikiSdcData.injectPayload(templateMod.html, jsonText)
	if not html then
		LrDialogs.message(TITLE, injectErr, 'critical')
		return
	end

	local pagePath = editorPagePath()
	local okWrite, writeErr = pcall(function()
		local fh = assert(io.open(pagePath, 'w'))
		fh:write(html)
		fh:close()
	end)
	if not okWrite then
		LrDialogs.message(TITLE,
			'Die Editorseite ließ sich nicht anlegen:\n' .. tostring(writeErr), 'critical')
		return
	end
	MediaWikiUtils.trace('SDC web editor: page written to ' .. pagePath)

	local url = MediaWikiSdcData.pathToFileUrl(pagePath)
	pcall(function() LrHttp.openUrlInBrowser(url) end)
	MediaWikiUtils.trace('SDC web editor: browser opened, now watching for ' .. resultPath)

	-- Watch for the result file in a SEPARATE async task, so Lightroom keeps
	-- running normally. Invisible until the file arrives.
	LrTasks.startAsyncTask(function()
		local waited = 0
		while waited < MAX_WAIT do
			LrTasks.sleep(POLL_SECONDS)
			waited = waited + POLL_SECONDS

			if LrFileUtils.exists(resultPath) then
				-- Give the browser a moment to finish writing
				LrTasks.sleep(0.5)

				local content
				local okRead, readErr = pcall(function()
					local fh = assert(io.open(resultPath, 'r'))
					content = fh:read('*a')
					fh:close()
				end)
				if not okRead or not content or content == '' then
					MediaWikiUtils.trace('SDC web editor: result file unreadable: '
						.. tostring(readErr))
					break
				end

				-- Delete BEFORE applying, so a crash does not reapply on restart
				pcall(function() LrFileUtils.delete(resultPath) end)

				local okDecode, result = pcall(function() return json:decode(content) end)
				if not okDecode or type(result) ~= 'table' then
					LrDialogs.message(TITLE,
						'Die heruntergeladene Datei war kein gültiges JSON. '
						.. 'Es wurde nichts geändert.', 'critical')
					MediaWikiUtils.trace('SDC web editor: invalid JSON, '
						.. tostring(#content) .. ' bytes')
					break
				end

				local targets = catalog:getTargetPhotos()
				local nowCount = targets and #targets or 1
				local scope = MediaWikiSdcData.applyScope(
					result.applyToAll, result.photoCount, nowCount)
				if scope == 'mismatch' then
					MediaWikiUtils.trace('SDC web editor: selection changed ('
						.. tostring(result.photoCount) .. ' -> '
						.. tostring(nowCount) .. ') – not applied')
					LrDialogs.message(TITLE,
						'Beim Öffnen des Editors waren '
						.. tostring(result.photoCount) .. ' Fotos markiert, '
						.. 'jetzt sind es ' .. tostring(nowCount)
						.. '. Es wurde nichts geändert.', 'warning')
					break
				end
				local written = MediaWikiSdcData.applyResult(catalog,
					scope == 'all' and targets or photo, result)
				MediaWikiUtils.trace('SDC web editor: applied to '
					.. tostring(written) .. ' photo(s) from downloaded file')
				local wo = written and written > 1
					and ('Auf ' .. tostring(written) .. ' Fotos übernommen: ')
					or 'Übernommen: '
				LrDialogs.message(TITLE,
					wo .. MediaWikiSdcData.describeResult(result), 'info')
				break
			end
		end

		-- Clean up the editor page (best effort)
		pcall(function()
			local p = editorPagePath()
			if LrFileUtils.exists(p) then LrFileUtils.delete(p) end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('lrMediaWikiSdcWeb', function(context)

	local catalog = LrApplication.activeCatalog()
	local photo = catalog:getTargetPhoto()
	if not photo then
		LrDialogs.message(TITLE, 'Kein Foto ausgewählt.', 'info')
		return
	end
	local targets = catalog:getTargetPhotos()
	local photoCount = targets and #targets or 1

	-- Route 1: the bridge, if the user has switched it on. ensureRunning
	-- pauses (it launches a process and waits for it), so it stays out of
	-- any pcall.
	if MediaWikiSdcBridge.isEnabled() then
		if MediaWikiSdcBridge.ensureRunning() then
			local url = MediaWikiSdcBridge.editorUrl()
			if url then
				pcall(function() LrHttp.openUrlInBrowser(url) end)
				MediaWikiUtils.trace('SDC web editor: opened via bridge on port '
					.. tostring(MediaWikiSdcBridge.port))
				return
			end
		end
		-- Starting failed. Say why, then carry on with the file route
		-- rather than leaving the user with nothing.
		LrDialogs.message(TITLE,
			'Die Hintergrund-App ließ sich nicht starten, daher wird der '
			.. 'Dateiweg benutzt.\n\n'
			.. tostring(MediaWikiSdcBridge.lastError or 'Grund unbekannt.'),
			'warning')
	end

	-- Route 2
	runFileRoute(catalog, photo, photoCount)

end)
end)

-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- Browser-based SDC editor. Opens the structured data of the active photo in
-- a browser page and picks up the result as a FILE: the page triggers a
-- download, and a background watcher polls for that file every few seconds.
--
-- WHY A FILE AND NOT A NETWORK CALLBACK: the loopback approach (LrSocket on
-- 127.0.0.1) failed on Harald's Windows machine – the browser sent, but
-- nothing arrived (port conflict, protection software, or a Private Network
-- block). A downloaded file has none of these failure modes: no port, no
-- fetch, no firewall rule, and it works from file:// pages on every browser.
-- The only assumption is that the browser downloads files to a known folder
-- without asking – if it does ask, the user picks the same folder and it
-- still works.
--
-- Lightroom is NOT blocked while the page is open. The watcher runs in its
-- own async task and checks every POLL_SECONDS whether the result file has
-- appeared. The user can keep working in Lightroom normally; when the file
-- arrives, a confirmation dialog pops up.

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'

local MediaWikiUtils = require 'MediaWikiUtils'
local json = require 'JSON'

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- The file the browser page downloads and the watcher looks for. Must match
-- the RESULT_FILENAME constant in sdc-editor.html exactly.
local RESULT_FILENAME = 'lrmediawiki-sdc-result.json'

-- How often the watcher checks (seconds).
local POLL_SECONDS = 2

-- Give up after this many seconds without a file (≈ 4 hours – long enough
-- for a lunch break, short enough to not run forever if the page was closed
-- without saving).
local MAX_WAIT = 14400

--------------------------------------------------------------------------------
-- Pure helpers (no SDK use)
--------------------------------------------------------------------------------

local function trim(s)
	return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

-- Preferences of this plug-in. Fetched on demand rather than at load time, so
-- that a problem here can never keep the whole file from loading.
local function prefs()
	local ok, p = pcall(function() return LrPrefs.prefsForPlugin(nil) end)
	if ok and type(p) == 'table' then return p end
	return {}
end

local function filled(s)
	return trim(s) ~= ''
end

local function normalizeQid(v)
	local head = tostring(v or ''):match('^([^#]+)') or ''
	local qid = trim(head):match('^[Qq](%d+)$')
	return qid and ('Q' .. qid) or ''
end

local function effectiveSdcValue(sidebarValue, descAllValue)
	if filled(sidebarValue) then return sidebarValue end
	return descAllValue or ''
end

local function parseDescriptionAll(text)
	text = text or ''
	text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
	local captions, depicts, createdDuring = {}, '', ''
	local freeLines = {}
	for line in (text .. '\n'):gmatch('(.-)\n') do
		local handled = false
		local lang, val = line:match('^caption_([%a][%w%-]*)=(.*)$')
		if lang then captions[lang:lower()] = val; handled = true end
		if not handled then
			local dv = line:match('^depicts=(.*)$')
			if dv then
				dv = trim(dv)
				if dv ~= '' then depicts = (depicts == '') and dv or (depicts .. '; ' .. dv) end
				handled = true
			end
		end
		if not handled then
			local cv = line:match('^created_during=(.*)$')
			if cv then
				cv = trim(cv)
				if cv ~= '' then createdDuring = (createdDuring == '') and cv or (createdDuring .. '; ' .. cv) end
				handled = true
			end
		end
		if not handled then freeLines[#freeLines + 1] = line end
	end
	while #freeLines > 0 and trim(freeLines[#freeLines]) == '' do table.remove(freeLines) end
	while #freeLines > 0 and trim(freeLines[1]) == '' do table.remove(freeLines, 1) end
	return captions, depicts, createdDuring, table.concat(freeLines, '\n')
end

local function injectPayload(html, jsonText)
	local startMark = '/*__PAYLOAD_START__*/'
	local endMark = '/*__PAYLOAD_END__*/'
	local a = html:find(startMark, 1, true)
	local b = html:find(endMark, 1, true)
	if not a or not b or b < a then
		return nil, 'Die Vorlage enthält keine Platzhalter-Markierungen.'
	end
	jsonText = jsonText:gsub('<', '\\u003C')
	return html:sub(1, a - 1)
		.. startMark .. '\nvar PAYLOAD = ' .. jsonText .. ';\n'
		.. html:sub(b)
end

local function pathToFileUrl(path)
	local p = tostring(path or ''):gsub('\\', '/')
	if not p:match('^/') then p = '/' .. p end
	p = p:gsub('[%%%s"<>|^`{}%[%]]', function(ch)
		return string.format('%%%02X', string.byte(ch))
	end)
	return 'file://' .. p
end

--------------------------------------------------------------------------------
-- Downloads folder
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

--------------------------------------------------------------------------------
-- Catalog side
--------------------------------------------------------------------------------

local function collectPayload(photo, photoCount)
	local descAll = photo:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
	local categories = photo:getPropertyForPlugin(_PLUGIN, 'categories') or ''
	local depictsField = photo:getPropertyForPlugin(_PLUGIN, 'depicts') or ''
	local createdField = photo:getPropertyForPlugin(_PLUGIN, 'created_during') or ''
	local captions, depicts, createdDuring, freetext = parseDescriptionAll(descAll)
	local captionEn = photo:getPropertyForPlugin(_PLUGIN, 'caption_en') or ''
	if filled(captionEn) and not filled(captions.en) then captions.en = captionEn end
	return {
		fileName = photo:getFormattedMetadata('fileName') or '',
		photoCount = photoCount,
		returnPort = 0,  -- no network callback; the page triggers a download
		token = '',
		-- Interface language of the editor page. Empty means "let the page
		-- decide from the browser"; once the user picks one in the page it
		-- comes back with the result and is remembered from then on.
		uiLang = prefs().sdcEditorLang or '',
		depicts = effectiveSdcValue(depictsField, depicts),
		createdDuring = effectiveSdcValue(createdField, createdDuring),
		categories = categories,
		captions = captions,
		freetext = freetext,
	}
end

local function applyResult(catalog, photo, result)
	-- Remember the interface language the user worked in, so the next call
	-- opens in the same one.
	local lang = trim(result.uiLang or '')
	if lang ~= '' and lang:match('^%a%a[%w%-]*$') then
		pcall(function() prefs().sdcEditorLang = lang end)
	end
	catalog:withWriteAccessDo('LrMediaWiki: SDC aus dem Browser', function()
		photo:setPropertyForPlugin(_PLUGIN, 'description_all', trim(result.wikitext or ''))
		photo:setPropertyForPlugin(_PLUGIN, 'categories', trim(result.categories or ''))
		photo:setPropertyForPlugin(_PLUGIN, 'depicts', trim(result.depicts or ''))
		photo:setPropertyForPlugin(_PLUGIN, 'created_during', trim(result.createdDuring or ''))
		local caps = result.captions
		if type(caps) == 'table' then
			photo:setPropertyForPlugin(_PLUGIN, 'caption_en', trim(caps.en or ''))
		end
	end)
end

local function describeResult(result)
	local qids = 0
	for token in tostring(result.depicts or ''):gmatch('[^,;]+') do
		if normalizeQid(token) ~= '' then qids = qids + 1 end
	end
	local caps = 0
	if type(result.captions) == 'table' then
		for _ in pairs(result.captions) do caps = caps + 1 end
	end
	local cats = 0
	for token in tostring(result.categories or ''):gmatch('[^;]+') do
		if trim(token) ~= '' then cats = cats + 1 end
	end
	return tostring(qids) .. ' Nummer(n) bei Depicts, '
		.. tostring(caps) .. ' Bildunterschrift(en), '
		.. tostring(cats) .. ' Kategorie(n).'
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('lrMediaWikiSdcWeb', function(context)

	local catalog = LrApplication.activeCatalog()
	local photo = catalog:getTargetPhoto()
	if not photo then
		LrDialogs.message('LrMediaWiki – SDC im Browser',
			'Kein Foto ausgewählt.', 'info')
		return
	end
	local targets = catalog:getTargetPhotos()
	local photoCount = targets and #targets or 1

	-- 1. Find the downloads folder
	local downloads = getDownloadsFolder()
	if not downloads then
		LrDialogs.message('LrMediaWiki – SDC im Browser',
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

	-- 2. Build the page
	local payload = collectPayload(photo, photoCount)
	local okEncode, jsonText = pcall(function() return json:encode(payload) end)
	if not okEncode then
		LrDialogs.message('LrMediaWiki – SDC im Browser',
			'Die Daten des Fotos ließen sich nicht aufbereiten:\n' .. tostring(jsonText),
			'critical')
		return
	end

	local okTemplate, templateMod = pcall(function() return require 'SdcEditorTemplate' end)
	if not okTemplate or type(templateMod) ~= 'table' or type(templateMod.html) ~= 'string' then
		LrDialogs.message('LrMediaWiki – SDC im Browser',
			'Die Editorseite (SdcEditorTemplate.lua) fehlt oder lässt sich nicht laden.',
			'critical')
		return
	end

	local html, injectErr = injectPayload(templateMod.html, jsonText)
	if not html then
		LrDialogs.message('LrMediaWiki – SDC im Browser', injectErr, 'critical')
		return
	end

	-- 3. Write the page to the temp folder
	local dir
	pcall(function() dir = LrPathUtils.getStandardFilePath('temp') end)
	if not dir then dir = LrPathUtils.getStandardFilePath('desktop') end
	local pagePath = LrPathUtils.child(dir, 'lrmediawiki-sdc-editor.html')
	local okWrite, writeErr = pcall(function()
		local fh = assert(io.open(pagePath, 'w'))
		fh:write(html)
		fh:close()
	end)
	if not okWrite then
		LrDialogs.message('LrMediaWiki – SDC im Browser',
			'Die Editorseite ließ sich nicht anlegen:\n' .. tostring(writeErr), 'critical')
		return
	end
	MediaWikiUtils.trace('SDC web editor: page written to ' .. pagePath)

	-- 4. Open the browser – and return immediately. Lightroom is free.
	local url = pathToFileUrl(pagePath)
	pcall(function() LrHttp.openUrlInBrowser(url) end)
	MediaWikiUtils.trace('SDC web editor: browser opened, now watching for ' .. resultPath)

end)  -- context ends here; Lightroom is unblocked

-- 5. Watch for the result file in a SEPARATE async task, so Lightroom keeps
-- running normally. This task has no function context and no progress bar –
-- it is invisible until the file arrives.
LrTasks.startAsyncTask(function()
	local catalog = LrApplication.activeCatalog()
	local photo = catalog:getTargetPhoto()
	if not photo then return end

	local downloads = getDownloadsFolder()
	if not downloads then return end
	local resultPath = LrPathUtils.child(downloads, RESULT_FILENAME)

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
				LrDialogs.message('LrMediaWiki – SDC im Browser',
					'Die heruntergeladene Datei war kein gültiges JSON. '
					.. 'Es wurde nichts geändert.', 'critical')
				MediaWikiUtils.trace('SDC web editor: invalid JSON, '
					.. tostring(#content) .. ' bytes')
				break
			end

			applyResult(catalog, photo, result)
			MediaWikiUtils.trace('SDC web editor: applied from downloaded file')
			LrDialogs.message('LrMediaWiki – SDC im Browser',
				'Übernommen: ' .. describeResult(result), 'info')
			break
		end
	end

	-- Clean up the editor page (best effort)
	pcall(function()
		local dir
		pcall(function() dir = LrPathUtils.getStandardFilePath('temp') end)
		if not dir then dir = LrPathUtils.getStandardFilePath('desktop') end
		local pagePath = LrPathUtils.child(dir, 'lrmediawiki-sdc-editor.html')
		if LrFileUtils.exists(pagePath) then
			LrFileUtils.delete(pagePath)
		end
	end)
end)
end)

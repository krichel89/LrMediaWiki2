-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- Shared data logic for both routes into the browser-based SDC editor:
-- the background bridge (MediaWikiSdcBridge.lua) and the file fallback
-- (ToolEditSdcWeb.lua). Both used to carry their own copy; they are one
-- module now so that a change to the data model cannot land in only one
-- of them.
--
-- PAUSING CALLS: collectPayload and applyResult touch the catalog and
-- therefore PAUSE. They must never be called from inside a pcall – see
-- the note in MediaWikiOAuth.lua and the SDK findings in the project
-- notes. Everything above the "Catalog side" divider is pure Lua and
-- safe anywhere; the standalone tests extract exactly that part.

local LrPrefs = import 'LrPrefs'

local MediaWikiSdcData = {}

--------------------------------------------------------------------------------
-- Pure helpers (no SDK use, no pausing – extracted verbatim by the tests)
--------------------------------------------------------------------------------

local function trim(s)
	return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
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

-- Describes a result in one German sentence, for the confirmation dialog.
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

-- A 32 character hexadecimal session token. Deliberately built from
-- math.random rather than LrDigest: this needs no SDK feature at all, so
-- there is nothing here that could behave differently in a future
-- Lightroom version. It is not a cryptographic secret – it only has to be
-- unguessable for a local process during one Lightroom session.
local function makeToken(seedExtra)
	-- NOTE the extra parentheses around the gsub: gsub returns TWO values,
	-- and tonumber's second argument is the number base. Without them,
	-- tonumber would be handed a base and return nil (or worse, misparse).
	local extra = tonumber((tostring(seedExtra or ''):gsub('%D', ''))) or 0
	local seed = (os.time() + extra + math.floor((os.clock() or 0) * 1000000)) % 2147483647
	math.randomseed(seed)
	-- Throw the first few away: some Lua 5.1 builds return a very
	-- predictable first value after seeding.
	for _ = 1, 5 do math.random() end
	local hex = {}
	for i = 1, 32 do
		hex[i] = string.format('%x', math.random(0, 15))
	end
	return table.concat(hex)
end

-- Gelernte Fuegungen ("Q123|de" -> "bei der") werden als flache Tabelle in
-- den Voreinstellungen gehalten. Zwei getrennte Tabellen (Schluessel und
-- Werte) statt JSON, weil LrPrefs verschachtelte Tabellen nicht zuverlaessig
-- ueber Sitzungsgrenzen traegt und wir hier keinen JSON-Kodierer brauchen.
-- mergeConnectors ist REIN: es nimmt alt und neu und gibt das Ergebnis
-- zurueck, ohne irgendetwas zu schreiben.
local function mergeConnectors(old, incoming)
	local out = {}
	if type(old) == 'table' then
		for k, v in pairs(old) do
			if type(k) == 'string' and type(v) == 'string' then out[k] = v end
		end
	end
	if type(incoming) == 'table' then
		for k, v in pairs(incoming) do
			-- Nur plausible Schluessel uebernehmen: Qzahl|sprachcode.
			if type(k) == 'string' and k:match('^Q%d+|%a%a[%w%-]*$')
			   and type(v) == 'string' then
				local value = trim(v)
				if value == '' then
					out[k] = nil  -- geleert heisst: wieder vergessen
				else
					out[k] = value
				end
			end
		end
	end
	return out
end

-- Welche Mac-Programmdatei in welcher Reihenfolge? Bei BEKANNTER Architektur
-- genau eine Scheibe, damit nicht zwei Fassungen hintereinander gestartet
-- werden - das war der Fehler bis 2.0.42. "sdcbridge-mac" ist die universelle
-- Fassung (lipo), die auf beiden Architekturen laeuft; gibt es sie, braucht es
-- gar keine Erkennung. REIN, damit pruefbar.
local function macOrder(arch)
	local a = tostring(arch or ''):lower()
	if a:match('x86_64') or a:match('i386') then
		return { 'sdcbridge-mac', 'sdcbridge-mac-x86_64' }
	end
	if a:match('arm64') or a:match('aarch64') then
		return { 'sdcbridge-mac', 'sdcbridge-mac-arm64' }
	end
	-- Architektur unbekannt: universelle Fassung, dann beide Scheiben. Nur in
	-- diesem Fall wird ueberhaupt mehr als eine ausprobiert.
	return { 'sdcbridge-mac', 'sdcbridge-mac-arm64', 'sdcbridge-mac-x86_64' }
end

MediaWikiSdcData.trim = trim
MediaWikiSdcData.filled = filled
MediaWikiSdcData.normalizeQid = normalizeQid
MediaWikiSdcData.effectiveSdcValue = effectiveSdcValue
MediaWikiSdcData.parseDescriptionAll = parseDescriptionAll
MediaWikiSdcData.injectPayload = injectPayload
MediaWikiSdcData.pathToFileUrl = pathToFileUrl
MediaWikiSdcData.describeResult = describeResult
MediaWikiSdcData.makeToken = makeToken
MediaWikiSdcData.mergeConnectors = mergeConnectors
MediaWikiSdcData.macOrder = macOrder

--------------------------------------------------------------------------------
-- Preferences
--------------------------------------------------------------------------------

-- Fetched on demand rather than at load time, so that a problem here can
-- never keep the whole file from loading. LrPrefs does not pause, so the
-- pcall is safe.
function MediaWikiSdcData.prefs()
	local ok, p = pcall(function() return LrPrefs.prefsForPlugin(nil) end)
	if ok and type(p) == 'table' then return p end
	return {}
end

--------------------------------------------------------------------------------
-- Catalog side – PAUSING, never call from inside a pcall
--------------------------------------------------------------------------------

function MediaWikiSdcData.collectPayload(photo, photoCount)
	local descAll = photo:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
	local categories = photo:getPropertyForPlugin(_PLUGIN, 'categories') or ''
	local depictsField = photo:getPropertyForPlugin(_PLUGIN, 'depicts') or ''
	local createdField = photo:getPropertyForPlugin(_PLUGIN, 'created_during') or ''
	local captions, depicts, createdDuring, freetext = parseDescriptionAll(descAll)
	local captionEn = photo:getPropertyForPlugin(_PLUGIN, 'caption_en') or ''
	if filled(captionEn) and not filled(captions.en) then captions.en = captionEn end
	return {
		fileName = photo:getFormattedMetadata('fileName') or '',
		photoCount = photoCount or 1,
		-- Travels to the page and comes back with the result. The bridge
		-- refuses to write a result whose key no longer matches the photo
		-- Lightroom is on, so a result can never land on the wrong photo
		-- after the user has moved on.
		photoKey = MediaWikiSdcData.photoKey(photo),
		returnPort = 0,  -- unused; kept so an older page still loads
		token = '',
		-- Interface language of the editor page. Empty means "let the page
		-- decide from the browser"; once the user picks one in the page it
		-- comes back with the result and is remembered from then on.
		uiLang = MediaWikiSdcData.prefs().sdcEditorLang or '',
		depicts = effectiveSdcValue(depictsField, depicts),
		createdDuring = effectiveSdcValue(createdField, createdDuring),
		categories = categories,
		captions = captions,
		freetext = freetext,
		-- Gelernte Fuegungen fuer den Satzbau. Gehen mit und kommen mit dem
		-- Ergebnis zurueck; die Seite darf sie nicht selbst dauerhaft halten,
		-- weil ihre Herkunft bei jedem Start der Bruecke einen neuen Port
		-- bekommt und der Browserspeicher damit jedes Mal leer waere.
		connectors = MediaWikiSdcData.prefs().sdcConnectors or {},
	}
end

function MediaWikiSdcData.applyResult(catalog, photo, result)
	-- Remember the interface language the user worked in, so the next call
	-- opens in the same one.
	local lang = trim(result.uiLang or '')
	if lang ~= '' and lang:match('^%a%a[%w%-]*$') then
		pcall(function() MediaWikiSdcData.prefs().sdcEditorLang = lang end)
	end
	-- Fuegungen zusammenfuehren, bevor der Katalog angefasst wird: das sind
	-- Voreinstellungen, kein Katalogschreibzugriff.
	if type(result.connectors) == 'table' then
		local merged = MediaWikiSdcData.mergeConnectors(
			MediaWikiSdcData.prefs().sdcConnectors, result.connectors)
		pcall(function() MediaWikiSdcData.prefs().sdcConnectors = merged end)
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

-- Identifies a photo for "has the selection changed?". localIdentifier is
-- documented but not used anywhere else in this plug-in, so there is a
-- fallback: tostring(photo) is unique per photo object as well. VERIFY on
-- a real catalog that the first branch is the one that runs.
function MediaWikiSdcData.photoKey(photo)
	if photo == nil then return '' end
	local ok, id = pcall(function() return photo.localIdentifier end)
	if ok and id ~= nil then return 'id:' .. tostring(id) end
	return 'obj:' .. tostring(photo)
end

return MediaWikiSdcData

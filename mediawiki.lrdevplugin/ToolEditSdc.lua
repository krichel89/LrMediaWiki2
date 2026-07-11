-- This file is part of the LrMediaWiki2 project.
--
-- ToolEditSdc.lua – per-photo Structured Data (SDC) editor.
--
-- Edits the per-file "description_all" (label: Wikitext) metadata field of the
-- active photo with a structured UI:
--   * multilingual captions: slots with a free-text ISO language code field
--     (first four pre-filled with en/de/fr/it; "➕ Sprache" reveals an empty
--     slot where the user types the code by hand)
--   * depicts (P180), semicolon-separated QIDs with optional "# comment"
--     annotations, plus a live Wikidata name search: results appear in a
--     dropdown (first hit preselected); "⬅ Übernehmen" appends
--     "QID # Label" to the depicts field
--   * created during (P10408) with the same live search (single QID)
--   * categories (the per-photo 'categories' field, semicolon-separated;
--     lives in its own metadata field, NOT inside description_all)
--   * a free wikitext field, plus "⬇ Captions → Wikitext"
--
-- The result is written back into "description_all" as caption_XX= /
-- depicts= / created_during= lines plus the free wikitext – the exact format
-- the export parses. "# comments" after QIDs are kept in the field (and in
-- description_all) for readability; the export strips them before building
-- SDC claims.
--
-- Binding notes (learned from runtime testing in this Lightroom install):
--   * bound `visible` on ROW containers does NOT work (containers have no
--     non-layout properties of their own) – `visible` is therefore bound on
--     the individual CONTROLS of the caption rows (untested there, VERIFY)
--   * push_button with a bound title does NOT update – search results are
--     shown in a popup_menu with bound items (proven to update here) and
--     taken over with a static-title button; the first hit is preselected,
--     so the common case is still a single click

-- Lightroom SDK namespaces
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

-- Project libraries (for the Wikidata name search)
local MediaWikiApi = require 'MediaWikiApi'   -- used only for urlEncode
local json = require 'JSON'                   -- used as json:decode(...)

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Number of caption slots. The first DEFAULT_VISIBLE are visible initially,
-- pre-filled with DEFAULT_SLOT_LANGS; "➕ Sprache" reveals the next (empty)
-- slot. Any language code can be typed by hand.
local MAX_LANGS = 12
local DEFAULT_VISIBLE = 4
local DEFAULT_SLOT_LANGS = { 'en', 'de', 'fr', 'it' }

-- Live search: debounce and number of clickable result rows.
local DEBOUNCE_SECONDS = 0.6
local RESULT_SLOTS = 5

--------------------------------------------------------------------------------
-- Small pure helpers
--------------------------------------------------------------------------------

local function trim(s)
	s = s or ''
	s = s:gsub('^%s+', '')
	s = s:gsub('%s+$', '')
	return s
end

local function filled(s)
	return s ~= nil and trim(s) ~= ''
end

-- Normalize a single QID: trim, strip an inline "# comment", upper-case a
-- leading "q" (q640 -> Q640). Returns '' if no valid QID is contained.
local function normalizeQid(v)
	v = trim(v or '')
	local qidPart = v:match('^([^#]+)') or v
	qidPart = trim(qidPart)
	qidPart = qidPart:gsub('^[qQ](%d+)$', 'Q%1')
	if qidPart:match('^Q%d+$') then
		return qidPart
	end
	return ''
end

-- Format a QID with its label as a readable comment: "Q640 # Harald Krichel".
local function qidWithComment(qid, label)
	qid = normalizeQid(qid)
	if qid == '' then return '' end
	if label and label ~= '' then
		return qid .. ' # ' .. label
	end
	return qid
end

-- Append a (possibly commented) QID to a semicolon-separated depicts string.
-- The duplicate check compares bare QIDs and splits on BOTH separators
-- (legacy comma lists and the current semicolon format).
local function appendQid(depicts, qid)
	local bare = normalizeQid(qid)
	if bare == '' then
		return depicts or ''
	end
	depicts = depicts or ''
	for token in depicts:gmatch('[^,;]+') do
		if normalizeQid(token) == bare then
			return depicts
		end
	end
	if trim(depicts) == '' then
		return qid
	end
	return trim(depicts) .. '; ' .. qid
end

-- Merge two depicts lists: every QID from `toApply` that is missing in
-- `existing` is appended (comments preserved); existing entries are kept.
local function mergeDepicts(existing, toApply)
	local result = existing or ''
	for token in (toApply or ''):gmatch('[^,;]+') do
		result = appendQid(result, trim(token))
	end
	return result
end

--------------------------------------------------------------------------------
-- Wikidata name search (wbsearchentities, public/unauthenticated)
--------------------------------------------------------------------------------

-- Runs one wbsearchentities query. Must run inside an async task because
-- LrHttp.get yields. Network/parse errors return an empty list.
local function searchWikidata(query, lang)
	lang = lang or 'de'
	local url = 'https://www.wikidata.org/w/api.php?action=wbsearchentities'
		.. '&search=' .. MediaWikiApi.urlEncode(query)
		.. '&language=' .. lang
		.. '&uselang=' .. lang
		.. '&type=item&limit=' .. tostring(RESULT_SLOTS) .. '&format=json'
	local headers = {
		{ field = 'User-Agent', value = 'LrMediaWiki2 SDC tool (https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)' },
	}
	local body, respHeaders = LrHttp.get(url, headers)
	if not body or not respHeaders or respHeaders.status ~= 200 then
		return {}
	end
	local ok, data = pcall(function()
		return json:decode(body)
	end)
	if not ok or type(data) ~= 'table' or type(data.search) ~= 'table' then
		return {}
	end
	local out = {}
	for _, e in ipairs(data.search) do
		out[#out + 1] = {
			id = e.id or '',
			label = e.label or '',
			description = e.description or '',
		}
	end
	return out
end

-- Format wbsearchentities results as LrView popup_menu items.
local function formatResultsAsItems(results)
	local items = {}
	for _, r in ipairs(results) do
		local label = (r.label ~= '' and r.label) or r.id
		local desc = (r.description ~= '' and (' – ' .. r.description)) or ''
		items[#items + 1] = { value = r.id, title = label .. desc .. '  (' .. r.id .. ')' }
	end
	return items
end

-- Sequential counter per search field: each keystroke increments it; the
-- async task only fires if the counter is unchanged after the debounce.
local searchGeneration = { depicts = 0, createdDuring = 0 }

--------------------------------------------------------------------------------
-- description_all parsing / assembly (pure)
--------------------------------------------------------------------------------

-- Parse a description_all block. ALL caption_XX= lines (any language code)
-- are extracted; depicts= and created_during= likewise. Every other line
-- (including per-file creator=/copyright=/license= lines and the real
-- wikitext) is preserved verbatim as "freetext".
local function parseDescriptionAll(text)
	text = text or ''
	text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
	local captions, depicts, createdDuring = {}, '', ''
	local freeLines = {}
	for line in (text .. '\n'):gmatch('(.-)\n') do
		local handled = false
		local lang, val = line:match('^caption_([%a][%w%-]*)=(.*)$')
		if lang then
			captions[lang:lower()] = val
			handled = true
		end
		if not handled then
			local dv = line:match('^depicts=(.*)$')
			if dv then
				depicts = dv
				handled = true
			end
		end
		if not handled then
			local cv = line:match('^created_during=(.*)$')
			if cv then
				createdDuring = cv
				handled = true
			end
		end
		if not handled then
			freeLines[#freeLines + 1] = line
		end
	end
	while #freeLines > 0 and trim(freeLines[#freeLines]) == '' do
		table.remove(freeLines)
	end
	while #freeLines > 0 and trim(freeLines[1]) == '' do
		table.remove(freeLines, 1)
	end
	return captions, depicts, createdDuring, table.concat(freeLines, '\n')
end

-- Distribute parsed captions onto the MAX_LANGS slots:
--   * slots 1..4 get their default language (en/de/fr/it) and its caption
--   * remaining parsed languages fill the following slots (alphabetical)
--   * if there are more languages than slots, the overflow is returned as a
--     table so the caller can keep those lines losslessly
-- Returns: slots (array of {lang, text}), visibleCount, overflow (dict)
local function assignCaptionSlots(captions)
	local slots = {}
	local used = {}
	for i = 1, MAX_LANGS do
		slots[i] = { lang = '', text = '' }
	end
	for i, lang in ipairs(DEFAULT_SLOT_LANGS) do
		slots[i].lang = lang
		slots[i].text = captions[lang] or ''
		used[lang] = true
	end
	-- Collect remaining parsed languages, alphabetically for determinism
	local rest = {}
	for lang in pairs(captions) do
		if not used[lang] then
			rest[#rest + 1] = lang
		end
	end
	table.sort(rest)
	local nextSlot = #DEFAULT_SLOT_LANGS + 1
	local overflow = {}
	for _, lang in ipairs(rest) do
		if nextSlot <= MAX_LANGS then
			slots[nextSlot].lang = lang
			slots[nextSlot].text = captions[lang]
			nextSlot = nextSlot + 1
		else
			overflow[lang] = captions[lang]
		end
	end
	-- Visible: at least the defaults, plus every filled extra slot
	local visibleCount = DEFAULT_VISIBLE
	for i = 1, MAX_LANGS do
		if filled(slots[i].text) and i > visibleCount then
			visibleCount = i
		end
	end
	return slots, visibleCount, overflow
end

-- Reassemble a description_all block. rows is an ordered list of
-- { lang = 'xx', value = '...' }; duplicate languages are dropped (first
-- wins). overflow captions (languages that had no slot) are written back
-- as caption lines so nothing is lost.
local function assembleDescriptionAll(rows, depicts, createdDuring, freetext, overflow)
	local parts = {}
	local seen = {}
	for _, r in ipairs(rows) do
		local lang = trim(r.lang or ''):lower()
		local val = trim(r.value or '')
		if lang:match('^%a%a[%w%-]*$') and val ~= '' and not seen[lang] then
			seen[lang] = true
			parts[#parts + 1] = 'caption_' .. lang .. '=' .. val
		end
	end
	if overflow then
		local keys = {}
		for lang in pairs(overflow) do keys[#keys + 1] = lang end
		table.sort(keys)
		for _, lang in ipairs(keys) do
			if not seen[lang] then
				seen[lang] = true
				parts[#parts + 1] = 'caption_' .. lang .. '=' .. overflow[lang]
			end
		end
	end
	if filled(depicts) then
		parts[#parts + 1] = 'depicts=' .. trim(depicts)
	end
	if filled(createdDuring) then
		parts[#parts + 1] = 'created_during=' .. trim(createdDuring)
	end
	local ft = trim(freetext or '')
	if ft ~= '' then
		parts[#parts + 1] = ft
	end
	return table.concat(parts, '\n')
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

-- The whole flow runs inside one async task: reading photo properties
-- (getPropertyForPlugin) yields and would otherwise fail with
-- "We can only wait from within a task" when started from the menu.
LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('LrMediaWikiEditSdc', function(context)
	local catalog = LrApplication.activeCatalog()
	local activePhoto = catalog:getTargetPhoto()
	if not activePhoto then
		LrDialogs.message('LrMediaWiki – SDC', 'Kein aktives Foto ausgewählt.', 'warning')
		return
	end

	local props = LrBinding.makePropertyTable(context)

	-- Read and parse the current per-file metadata.
	local descAll = activePhoto:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
	local capEnField = activePhoto:getPropertyForPlugin(_PLUGIN, 'caption_en') or ''
	local categoriesField = activePhoto:getPropertyForPlugin(_PLUGIN, 'categories') or ''
	local captions, depicts, createdDuring, freetext = parseDescriptionAll(descAll)
	if not filled(captions.en) and filled(capEnField) then
		captions.en = capEnField
	end

	local slots, visibleCount, overflow = assignCaptionSlots(captions)
	for i = 1, MAX_LANGS do
		props['capLang' .. i] = slots[i].lang
		props['capText' .. i] = slots[i].text
	end
	props.visibleCount = visibleCount
	for i = 1, MAX_LANGS do
		props['capVisible' .. i] = (i <= props.visibleCount)
	end

	props.depicts = depicts or ''
	props.createdDuring = createdDuring or ''
	props.freetext = freetext or ''
	props.wdQuery = ''
	props.wdResults = {}
	props.wdChoice = ''
	props.cdQuery = ''
	props.cdResults = {}
	props.cdChoice = ''
	props.categories = categoriesField
	props.applyDepictsToAll = true

	local f = LrView.osFactory()
	local bind = LrView.bind

	-- QID -> label lookups for the current result sets (for "# comments").
	local wdLabelLookup, cdLabelLookup = {}, {}

	-- Debounced live search; fills the result dropdown and preselects the
	-- first hit (so "⬅ Übernehmen" is usually a single click).
	local function liveSearch(key, queryProp, resultsProp, choiceProp, labelLookup)
		searchGeneration[key] = searchGeneration[key] + 1
		local myGen = searchGeneration[key]
		local q = trim(props[queryProp] or '')
		if not filled(q) or #q < 2 then
			props[resultsProp] = {}
			props[choiceProp] = ''
			return
		end
		LrTasks.startAsyncTask(function()
			LrTasks.sleep(DEBOUNCE_SECONDS)
			if searchGeneration[key] ~= myGen then return end
			local results = searchWikidata(q, 'de')
			if searchGeneration[key] ~= myGen then return end
			for k in pairs(labelLookup) do labelLookup[k] = nil end
			for _, r in ipairs(results) do
				labelLookup[r.id] = r.label
			end
			local items = formatResultsAsItems(results)
			props[resultsProp] = items
			if #items > 0 then
				props[choiceProp] = items[1].value
			else
				props[choiceProp] = ''
			end
		end)
	end

	props:addObserver('wdQuery', function()
		liveSearch('depicts', 'wdQuery', 'wdResults', 'wdChoice', wdLabelLookup)
	end)
	props:addObserver('cdQuery', function()
		liveSearch('createdDuring', 'cdQuery', 'cdResults', 'cdChoice', cdLabelLookup)
	end)

	-- Caption slot rows: free ISO code field + text field. `visible` is bound
	-- on the CONTROLS (row-level visible is ignored by Lightroom).
	local captionRows = {}
	for i = 1, MAX_LANGS do
		captionRows[i] = f:row {
			visible = bind('capVisible' .. i),
			f:edit_field {
				value = bind('capLang' .. i),
				visible = bind('capVisible' .. i),
				immediate = true,
				width_in_chars = 4,
				placeholder_string = 'ISO',
			},
			f:edit_field {
				value = bind('capText' .. i),
				visible = bind('capVisible' .. i),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 40,
			},
		}
	end

	local contents = f:view {
		bind_to_object = props,

		f:static_text {
			title = 'Depicts (P180) – QIDs mit Semikolon getrennt, Kommentar nach #:',
		},
		f:row {
			f:edit_field {
				value = bind('depicts'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 28,
				placeholder_string = 'z. B. Q640 # Harald Krichel; Q42',
			},
			f:edit_field {
				value = bind('wdQuery'),
				immediate = true,
				width_in_chars = 18,
				placeholder_string = 'Name suchen…',
			},
		},
		f:row {
			f:popup_menu {
				value = bind('wdChoice'),
				items = bind('wdResults'),
				fill_horizontal = 1,
			},
			f:push_button {
				title = '⬅ Übernehmen',
				action = function()
					if filled(props.wdChoice) then
						props.depicts = appendQid(props.depicts,
							qidWithComment(props.wdChoice, wdLabelLookup[props.wdChoice] or ''))
					end
				end,
			},
		},

		f:spacer { height = 10 },

		f:static_text { title = 'Bildunterschriften (SDC-Captions):' },
		f:column(captionRows),
		f:row {
			f:push_button {
				title = '➕ Sprache',
				action = function()
					if props.visibleCount < MAX_LANGS then
						props.visibleCount = props.visibleCount + 1
						-- New slot is empty: the user types the ISO code by hand.
						props['capVisible' .. props.visibleCount] = true
					else
						LrDialogs.message('Sprachen',
							'Es sind bereits alle ' .. tostring(MAX_LANGS) .. ' Felder eingeblendet.', 'info')
					end
				end,
			},
			f:push_button {
				title = '⬇ Captions → Wikitext',
				action = function()
					local blocks = {}
					local seen = {}
					for i = 1, MAX_LANGS do
						local lang = trim(props['capLang' .. i] or ''):lower()
						local text = trim(props['capText' .. i] or '')
						if props['capVisible' .. i] and lang:match('^%a%a[%w%-]*$')
							and text ~= '' and not seen[lang] then
							seen[lang] = true
							local block = '{{' .. lang .. '|1=' .. text .. '}}'
							if not (props.freetext or ''):find(block, 1, true) then
								blocks[#blocks + 1] = block
							end
						end
					end
					if #blocks > 0 then
						local blockText = table.concat(blocks, '\n')
						if trim(props.freetext or '') == '' then
							props.freetext = blockText
						else
							props.freetext = blockText .. '\n' .. props.freetext
						end
					end
				end,
			},
		},

		f:spacer { height = 10 },

		f:static_text {
			title = 'Created during (P10408) – Kommentar nach # möglich:',
		},
		f:row {
			f:edit_field {
				value = bind('createdDuring'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 28,
				placeholder_string = 'z. B. Q124692383 # Berlinale 2026',
			},
			f:edit_field {
				value = bind('cdQuery'),
				immediate = true,
				width_in_chars = 18,
				placeholder_string = 'Ereignis suchen…',
			},
		},
		f:row {
			f:popup_menu {
				value = bind('cdChoice'),
				items = bind('cdResults'),
				fill_horizontal = 1,
			},
			f:push_button {
				title = '⬅ Übernehmen',
				action = function()
					if filled(props.cdChoice) then
						props.createdDuring = qidWithComment(props.cdChoice, cdLabelLookup[props.cdChoice] or '')
					end
				end,
			},
		},

		f:spacer { height = 10 },

		f:static_text {
			title = 'Kategorien (mit Semikolon getrennt, ohne [[Category:]]):',
		},
		f:row {
			f:edit_field {
				value = bind('categories'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
			},
			f:push_button {
				title = 'Kategorien -> Wikitext',
				-- Appends the categories as [[Category:...]] lines to the end of
				-- the wikitext field. Idempotent (a line already present is not
				-- added twice). The export deduplicates categories from the
				-- 'categories' field and from manual [[Category:]] lines anyway,
				-- so this never produces duplicates on Commons.
				action = function()
					local lines = {}
					local ft = props.freetext or ''
					for cat in (props.categories or ''):gmatch('[^;]+') do
						cat = trim(cat)
						-- Tolerate a pasted-in "[[Category:X]]" as well as a bare "X"
						cat = cat:match('^%[%[Category:(.-)%]%]$') or cat
						cat = trim(cat)
						if cat ~= '' then
							local line = '[[Category:' .. cat .. ']]'
							if not ft:find(line, 1, true) then
								lines[#lines + 1] = line
							end
						end
					end
					if #lines > 0 then
						local block = table.concat(lines, '\n')
						if trim(ft) == '' then
							props.freetext = block
						else
							props.freetext = ft .. '\n' .. block
						end
					end
				end,
			},
		},

		f:spacer { height = 10 },

		f:static_text {
			title = 'Weiterer Wikitext / Kommentare:',
		},
		f:row {
			f:edit_field {
				value = bind('freetext'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
				height_in_lines = 5,
				wraps = true,
			},
		},

		f:spacer { height = 6 },

		f:row {
			f:checkbox {
				title = 'Depicts auf alle ausgewählten Fotos übertragen (fehlende QIDs ergänzen)',
				value = bind('applyDepictsToAll'),
				checked_value = true,
				unchecked_value = false,
			},
		},
	}

	local action = LrDialogs.presentModalDialog {
		resizable = true,
		title = 'LrMediaWiki – Structured Data (SDC) bearbeiten',
		contents = contents,
		actionVerb = 'Speichern',
	}
	if action == 'cancel' then
		return
	end

	-- Collect visible, non-empty caption slots (dedupe by language; the ISO
	-- code is normalized to lowercase and must look like a language code).
	local rows = {}
	local seen = {}
	for i = 1, MAX_LANGS do
		local lang = trim(props['capLang' .. i] or ''):lower()
		local text = props['capText' .. i] or ''
		if props['capVisible' .. i] and filled(text)
			and lang:match('^%a%a[%w%-]*$') and not seen[lang] then
			seen[lang] = true
			rows[#rows + 1] = { lang = lang, value = text }
		end
	end

	-- Capture plain values before writing.
	local newDescAll = assembleDescriptionAll(rows, props.depicts, props.createdDuring, props.freetext, overflow)
	local newCapEn = ''
	for _, r in ipairs(rows) do
		if r.lang == 'en' then
			newCapEn = trim(r.value)
		end
	end
	local applyAll = props.applyDepictsToAll and filled(props.depicts)
	local depictsToApply = props.depicts

	-- Already inside the outer async task – write directly.
	local newCategories = trim(props.categories or '')

	catalog:withWriteAccessDo('LrMediaWiki: SDC bearbeiten', function()
		activePhoto:setPropertyForPlugin(_PLUGIN, 'description_all', newDescAll)
		activePhoto:setPropertyForPlugin(_PLUGIN, 'caption_en', newCapEn)
		activePhoto:setPropertyForPlugin(_PLUGIN, 'categories', newCategories)

		if applyAll then
			local targets = catalog:getTargetPhotos()
			for _, p in ipairs(targets) do
				if p ~= activePhoto then
					local d = p:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
					local caps2, dep2, cd2, ft2 = parseDescriptionAll(d)
					local slots2, _vc2, overflow2 = assignCaptionSlots(caps2)
					local rows2 = {}
					for _, s in ipairs(slots2) do
						if filled(s.text) and s.lang ~= '' then
							rows2[#rows2 + 1] = { lang = s.lang, value = s.text }
						end
					end
					-- MERGE the shared depicts into that photo's own list
					-- (missing QIDs are appended; existing ones are kept),
					-- keeping its own captions / created_during / freetext.
					local merged = assembleDescriptionAll(rows2,
						mergeDepicts(dep2, depictsToApply), cd2, ft2, overflow2)
					p:setPropertyForPlugin(_PLUGIN, 'description_all', merged)
				end
			end
		end
	end)
end)
end)

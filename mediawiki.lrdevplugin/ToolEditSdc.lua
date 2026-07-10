-- This file is part of the LrMediaWiki2 project.
--
-- ToolEditSdc.lua – per-photo Structured Data (SDC) editor.
--
-- Edits the per-file "description_all" metadata field of the active photo with
-- a structured UI, mirroring the Cammello desktop tool:
--   * multilingual captions (pseudo-dynamic language slots: 4 shown by default,
--     "+ language" reveals the next hidden slot up to MAX_LANGS)
--   * depicts (P180), comma-separated QIDs (manual entry)
--   * created during (P10408) as an optional per-file override
--   * a free "extra wikitext" field for everything else
--
-- The result is written back into "description_all" as key=value lines
-- (caption_XX=…, depicts=…, created_during=…) plus the free wikitext, exactly
-- the format that MediaWikiInterface parses on export. The English caption is
-- additionally mirrored into the "caption_en" metadata field.
--
-- NOTE (verify in Lightroom): three runtime behaviours could not be tested
-- outside Lightroom and should be checked on first run – see the comments
-- marked "VERIFY" below.

-- Lightroom SDK namespaces
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Languages offered in the caption dropdowns. This is a curated convenience
-- list only: the export now publishes ANY caption_XX language dynamically
-- (MediaWikiInterface iterates all caption_ keys), so you can add more entries
-- here freely. A caption in a language that is not in this list still round-trips
-- losslessly – it is kept in the free "extra wikitext" field and is published on
-- export like any other caption_XX= line.
local LANGUAGES = {
	{ 'en', 'English' },
	{ 'de', 'German' },
	{ 'fr', 'French' },
	{ 'it', 'Italian' },
	{ 'es', 'Spanish' },
	{ 'nl', 'Dutch' },
	{ 'pl', 'Polish' },
	{ 'ru', 'Russian' },
	{ 'zh', 'Chinese' },
	{ 'pt', 'Portuguese' },
	{ 'ja', 'Japanese' },
	{ 'ar', 'Arabic' },
	{ 'uk', 'Ukrainian' },
	{ 'cs', 'Czech' },
	{ 'sv', 'Swedish' },
	{ 'fi', 'Finnish' },
}

-- Default language per slot (index i). MAX_LANGS is derived from this list.
local DEFAULT_LANG_ORDER = { 'en', 'de', 'fr', 'it', 'es', 'nl', 'pl', 'ru', 'zh',
	'pt', 'ja', 'ar', 'uk', 'cs', 'sv', 'fi' }
local MAX_LANGS = #DEFAULT_LANG_ORDER
local DEFAULT_VISIBLE = 4

local supportedSet = {}
for _, lang in ipairs(DEFAULT_LANG_ORDER) do
	supportedSet[lang] = true
end

--------------------------------------------------------------------------------
-- Small pure helpers (self-contained; no dependency on utils.lua quirks)
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



-- Parse a description_all block into structured parts. Only caption codes that
-- are in supportedSet, plus depicts= and created_during=, are extracted; every
-- other line (including any per-file creator=/copyright=/license= lines and the
-- real wikitext) is preserved verbatim as "freetext".
local function parseDescriptionAll(text)
	text = text or ''
	text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
	local captions, depicts, createdDuring = {}, '', ''
	local freeLines = {}
	for line in (text .. '\n'):gmatch('(.-)\n') do
		local handled = false
		local lang, val = line:match('^caption_([%a][%w%-]*)=(.*)$')
		if lang and supportedSet[lang:lower()] then
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

-- Reassemble a description_all block. rows is an ordered list of
-- { lang = 'xx', value = '...' }; duplicate languages are dropped (first wins).
local function assembleDescriptionAll(rows, depicts, createdDuring, freetext)
	local parts = {}
	local seen = {}
	for _, r in ipairs(rows) do
		local lang = trim(r.lang or '')
		local val = trim(r.value or '')
		if lang ~= '' and val ~= '' and not seen[lang] then
			seen[lang] = true
			parts[#parts + 1] = 'caption_' .. lang .. '=' .. val
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

local function languagePopupItems()
	local items = {}
	for _, entry in ipairs(LANGUAGES) do
		items[#items + 1] = { value = entry[1], title = entry[1] .. ' – ' .. entry[2] }
	end
	return items
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

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
	local captions, depicts, createdDuring, freetext = parseDescriptionAll(descAll)
	if not filled(captions.en) and filled(capEnField) then
		captions.en = capEnField
	end

	-- Populate caption slots. Each slot i defaults to DEFAULT_LANG_ORDER[i]; any
	-- parsed caption is placed in the slot whose default language matches it.
	local highest = DEFAULT_VISIBLE
	for i, lang in ipairs(DEFAULT_LANG_ORDER) do
		props['capLang' .. i] = lang
		props['capText' .. i] = captions[lang] or ''
		if filled(captions[lang]) and i > highest then
			highest = i
		end
	end
	props.visibleCount = highest
	for i = 1, MAX_LANGS do
		props['capVisible' .. i] = (i <= props.visibleCount)
	end

	props.depicts = depicts or ''
	props.createdDuring = createdDuring or ''
	props.freetext = freetext or ''
	props.applyDepictsToAll = false

	local f = LrView.osFactory()
	local bind = LrView.bind
	local langItems = languagePopupItems()
	local labelWidth = LrView.share('sdc_label_width')

	-- Pre-build all caption rows; visibility is bound so "+ language" can reveal
	-- hidden ones. VERIFY: that binding a row's `visible` property reflows the
	-- column cleanly in your Lightroom version. If it does not, the fallback is
	-- to show all MAX_LANGS rows unconditionally (remove the `visible` line).
	local captionRows = {}
	for i = 1, MAX_LANGS do
		captionRows[i] = f:row {
			visible = bind('capVisible' .. i),
			f:popup_menu {
				value = bind('capLang' .. i),
				items = langItems,
				width = 150,
			},
			f:edit_field {
				value = bind('capText' .. i),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 40,
			},
		}
	end

	local contents = f:view {
		bind_to_object = props,

		f:static_text {
			title = 'Depicts (P180) – Wikidata-QIDs, mit Komma getrennt:',
		},
		f:row {
			f:edit_field {
				value = bind('depicts'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
				placeholder_string = 'z. B. Q640, Q42',
			},
		},

		f:spacer { height = 10 },

		f:static_text {
			title = 'Bildunterschriften (SDC-Captions):',
		},
		f:column(captionRows),
		f:row {
			f:push_button {
				title = '➕ Sprache',
				action = function()
					if props.visibleCount < MAX_LANGS then
						props.visibleCount = props.visibleCount + 1
						props['capVisible' .. props.visibleCount] = true
					else
						LrDialogs.message('Sprachen',
							'Alle unterstützten Sprachen sind bereits eingeblendet.', 'info')
					end
				end,
			},
		},

		f:spacer { height = 10 },

		f:row {
			f:static_text {
				title = 'Created during (P10408):',
				alignment = 'right',
				width = labelWidth,
			},
			f:edit_field {
				value = bind('createdDuring'),
				immediate = true,
				width_in_chars = 20,
				placeholder_string = 'QID, optional (überschreibt Batch), z. B. Q124692383',
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
				title = 'Depicts zusätzlich auf alle ausgewählten Fotos schreiben',
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

	-- Collect visible, non-empty caption slots (dedupe by language).
	local rows = {}
	local seen = {}
	for i = 1, MAX_LANGS do
		local lang = trim(props['capLang' .. i] or '')
		local text = props['capText' .. i] or ''
		if props['capVisible' .. i] and filled(text) and lang ~= '' and not seen[lang] then
			seen[lang] = true
			rows[#rows + 1] = { lang = lang, value = text }
		end
	end

	-- Capture plain values before the async task (do not rely on the bound
	-- property table / context staying alive inside the task).
	local newDescAll = assembleDescriptionAll(rows, props.depicts, props.createdDuring, props.freetext)
	local newCapEn = ''
	for _, r in ipairs(rows) do
		if r.lang == 'en' then
			newCapEn = trim(r.value)
		end
	end
	local applyAll = props.applyDepictsToAll and filled(props.depicts)
	local depictsToApply = props.depicts

	LrTasks.startAsyncTask(function()
		catalog:withWriteAccessDo('LrMediaWiki: SDC bearbeiten', function()
			activePhoto:setPropertyForPlugin(_PLUGIN, 'description_all', newDescAll)
			activePhoto:setPropertyForPlugin(_PLUGIN, 'caption_en', newCapEn)

			if applyAll then
				local targets = catalog:getTargetPhotos()
				for _, p in ipairs(targets) do
					if p ~= activePhoto then
						local d = p:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
						local caps2, _dep2, cd2, ft2 = parseDescriptionAll(d)
						local rows2 = {}
						for _, lang in ipairs(DEFAULT_LANG_ORDER) do
							if filled(caps2[lang]) then
								rows2[#rows2 + 1] = { lang = lang, value = caps2[lang] }
							end
						end
						-- Overwrite that photo's depicts with the shared value,
						-- keeping its own captions / created_during / freetext.
						local merged = assembleDescriptionAll(rows2, depictsToApply, cd2, ft2)
						p:setPropertyForPlugin(_PLUGIN, 'description_all', merged)
					end
				end
			end
		end)
	end)
end)

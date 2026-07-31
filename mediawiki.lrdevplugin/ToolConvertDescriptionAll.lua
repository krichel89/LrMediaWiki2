-- This file is part of the LrMediaWiki2 project.
--
-- ToolConvertDescriptionAll.lua – converts between the two description
-- representations, for all selected photos:
--
--   Direction A ("fields → all"):
--     The single-line fields "Description (en)" / "Description (de)" are
--     wrapped as {{en|1=…}} / {{de|1=…}}, prepended to "Raw Metadata",
--     and the single-line fields are cleared (move semantics).
--
--   Direction B ("all → fields"):
--     Top-level {{en|…}} / {{de|…}} blocks are extracted from
--     "Raw Metadata" into the single-line fields and removed from the
--     wikitext; everything else stays in "Raw Metadata".
--
-- Conflict rule (both directions): if the target already holds a DIFFERENT
-- value, that photo/language is skipped and counted as a conflict – nothing
-- is overwritten and nothing is lost. Identical values are deduplicated.
--
-- Background: the Lightroom SDK offers no notification when the user switches
-- the Metadata panel set, so this conversion cannot run automatically on
-- switching – it is an explicit menu action. The EXPORT merges both
-- representations automatically either way (see fillFieldsByFile), so photos
-- export correctly even without running this tool.

-- Lightroom SDK namespaces
local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

--------------------------------------------------------------------------------
-- Pure helpers
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

-- Scan `text` for top-level, brace-balanced {{lang|…}} blocks (lang: en/de,
-- case-insensitive; nested templates such as {{w|…}} inside the block are
-- handled correctly via %b{}).
-- Returns:
--   found      – { en = { inner1, … }, de = { … } } (inner text, "1=" stripped)
--   newText    – text with the blocks whose language is in removeSet removed
-- removeSet    – e.g. { en = true }; pass {} for a pure scan.
local function scanLanguageBlocks(text, removeSet)
	local found = { en = {}, de = {} }
	local out = {}
	local pos = 1
	local len = #text
	while pos <= len do
		local s, e = text:find('%b{}', pos)
		if not s then
			out[#out + 1] = text:sub(pos)
			break
		end
		out[#out + 1] = text:sub(pos, s - 1)
		local block = text:sub(s, e)
		local code = block:match('^{{%s*(%a+)%s*|')
		local key = code and code:lower()
		if key == 'en' or key == 'de' then
			local inner = block:sub(1, -3) -- strip trailing }}
			inner = inner:gsub('^{{%s*%a+%s*|', '', 1)
			inner = inner:gsub('^%s*', '', 1)
			inner = inner:gsub('^1%s*=', '', 1)
			found[key][#found[key] + 1] = trim(inner)
			if not removeSet[key] then
				out[#out + 1] = block
			end
		else
			out[#out + 1] = block
		end
		pos = e + 1
	end
	local newText = table.concat(out)
	-- tidy up gaps left by removed blocks
	newText = newText:gsub('\n%s*\n%s*\n+', '\n\n')
	newText = trim(newText)
	return found, newText
end

local function languageBlock(lang, value)
	return '{{' .. lang .. '|1=' .. value .. '}}'
end

--------------------------------------------------------------------------------
-- Per-photo conversion (pure decision logic; returns what to write)
--------------------------------------------------------------------------------

-- Direction A: fields → all.
-- Input: current field values and description_all.
-- Output table: { descAll = ..., fieldEn = ..., fieldDe = ..., changed = bool,
--                 conflicts = n }
local function convertFieldsToAll(fieldEn, fieldDe, descAll)
	fieldEn = trim(fieldEn or '')
	fieldDe = trim(fieldDe or '')
	descAll = descAll or ''
	local result = { descAll = descAll, fieldEn = fieldEn, fieldDe = fieldDe,
		changed = false, conflicts = 0 }
	if fieldEn == '' and fieldDe == '' then
		return result
	end
	local existing = scanLanguageBlocks(descAll, {})
	local newBlocks = {}
	for _, lang in ipairs({ 'en', 'de' }) do
		local value = (lang == 'en') and fieldEn or fieldDe
		if value ~= '' then
			local present = existing[lang]
			if #present == 0 then
				newBlocks[#newBlocks + 1] = languageBlock(lang, value)
				result['field' .. (lang == 'en' and 'En' or 'De')] = ''
				result.changed = true
			elseif #present == 1 and present[1] == value then
				-- identical block already there: just clear the field
				result['field' .. (lang == 'en' and 'En' or 'De')] = ''
				result.changed = true
			else
				-- a different {{lang|…}} block already exists: conflict, keep both as-is
				result.conflicts = result.conflicts + 1
			end
		end
	end
	if #newBlocks > 0 then
		local blockText = table.concat(newBlocks, '\n')
		if trim(result.descAll) == '' then
			result.descAll = blockText
		else
			result.descAll = blockText .. '\n' .. result.descAll
		end
	end
	return result
end

-- Direction B: all → fields.
local function convertAllToFields(fieldEn, fieldDe, descAll)
	fieldEn = trim(fieldEn or '')
	fieldDe = trim(fieldDe or '')
	descAll = descAll or ''
	local result = { descAll = descAll, fieldEn = fieldEn, fieldDe = fieldDe,
		changed = false, conflicts = 0 }
	local found = scanLanguageBlocks(descAll, {})
	local removeSet = {}
	for _, lang in ipairs({ 'en', 'de' }) do
		local joined = table.concat(found[lang], '\n')
		local fieldKey = (lang == 'en') and 'fieldEn' or 'fieldDe'
		if joined ~= '' then
			if result[fieldKey] == '' then
				result[fieldKey] = joined
				removeSet[lang] = true
				result.changed = true
			elseif result[fieldKey] == joined then
				removeSet[lang] = true -- duplicate; field already holds the value
				result.changed = true
			else
				result.conflicts = result.conflicts + 1
			end
		end
	end
	if next(removeSet) ~= nil then
		local _, newText = scanLanguageBlocks(descAll, removeSet)
		result.descAll = newText
	end
	return result
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

LrFunctionContext.callWithContext('LrMediaWikiConvertDescriptionAll', function(context)
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()
	if #photos == 0 then
		LrDialogs.message('LrMediaWiki', 'Keine Fotos ausgewählt.', 'warning')
		return
	end

	local props = LrBinding.makePropertyTable(context)
	props.direction = 'toAll'

	local f = LrView.osFactory()
	local bind = LrView.bind
	local contents = f:column {
		bind_to_object = props,
		f:static_text {
			title = 'Richtung wählen (' .. tostring(#photos) .. ' ausgewählte Fotos):',
		},
		f:radio_button {
			title = 'Einzelfelder (en/de) → Wikitext',
			value = bind('direction'),
			checked_value = 'toAll',
		},
		f:radio_button {
			title = 'Wikitext → Einzelfelder (en/de)',
			value = bind('direction'),
			checked_value = 'toFields',
		},
		f:static_text {
			title = 'Bereits anders belegte Ziele werden übersprungen (Konflikt),\nnichts wird überschrieben oder gelöscht.',
		},
	}

	local action = LrDialogs.presentModalDialog {
		title = 'LrMediaWiki2 – Beschreibung konvertieren',
		contents = contents,
		actionVerb = 'Konvertieren',
	}
	if action == 'cancel' then
		return
	end
	local toAll = (props.direction == 'toAll')

	LrTasks.startAsyncTask(function()
		local changedCount, conflictCount = 0, 0
		catalog:withWriteAccessDo('LrMediaWiki: Beschreibung konvertieren', function()
			for _, photo in ipairs(photos) do
				local fieldEn = photo:getPropertyForPlugin(_PLUGIN, 'description_en') or ''
				local fieldDe = photo:getPropertyForPlugin(_PLUGIN, 'description_de') or ''
				local descAll = photo:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
				local r
				if toAll then
					r = convertFieldsToAll(fieldEn, fieldDe, descAll)
				else
					r = convertAllToFields(fieldEn, fieldDe, descAll)
				end
				if r.changed then
					photo:setPropertyForPlugin(_PLUGIN, 'description_en', r.fieldEn)
					photo:setPropertyForPlugin(_PLUGIN, 'description_de', r.fieldDe)
					photo:setPropertyForPlugin(_PLUGIN, 'description_all', r.descAll)
					changedCount = changedCount + 1
				end
				conflictCount = conflictCount + r.conflicts
			end
		end)
		local msg = tostring(changedCount) .. ' Foto(s) konvertiert.'
		if conflictCount > 0 then
			msg = msg .. '\n' .. tostring(conflictCount)
				.. ' Konflikt(e) übersprungen (Ziel war bereits anders belegt).'
		end
		LrDialogs.message('LrMediaWiki2 – Beschreibung konvertieren', msg, 'info')
	end)
end)

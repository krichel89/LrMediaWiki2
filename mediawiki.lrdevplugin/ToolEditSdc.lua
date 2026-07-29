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
--     lives in its own metadata field, NOT inside description_all), with a
--     "Vorschlagen (P373)" button that suggests Commons categories from the
--     depicts / created_during QIDs (P373 claim, fallback English label)
--   * the live search is fuzzy since 2.0.13 (ported from Cammello 0.11.7):
--     when the wbsearchentities prefix search returns fewer than RESULT_SLOTS
--     hits, a CirrusSearch full-text query fills the result list up – tolerant
--     of word order and ordinals ("78th Cannes Film Festival"). Since 2.0.21
--     the hits are shown in always-visible rows instead of a dropdown: the
--     SDK offers no way to open a popup_menu or combo_box programmatically,
--     so any dropdown always cost an extra click before the results could
--     even be seen. Since 2.0.24 the hit TEXT itself is the click target
--     (mouse_down on static_text was measured to work here), and applied
--     entries are listed below the field with a "✕" each.
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
local MediaWikiUtils = require 'MediaWikiUtils' -- trace()
local json = require 'JSON'                   -- used as json:decode(...)

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Number of caption slots. All of them are visible from the start and freely
-- assignable – any language code can be typed into the ISO field, the
-- pre-filled DEFAULT_SLOT_LANGS are only a suggestion. Captions in languages
-- beyond these slots are NOT lost: they are carried through as overflow and
-- written back unchanged (see assignCaptionSlots / assembleDescriptionAll).
local MAX_LANGS = 4
local DEFAULT_VISIBLE = 4
local DEFAULT_SLOT_LANGS = { 'en', 'de', 'fr', 'it' }

-- Live search: debounce and number of clickable result rows.
-- Live search timing. The search starts at MIN_QUERY_CHARS characters; up to
-- that point nothing is sent at all. From there on the debounce is short, so
-- results arrive almost while typing, and it only exists to avoid firing one
-- request per keystroke during fast typing. The generation counter still
-- discards any answer that a newer keystroke has overtaken.
local MIN_QUERY_CHARS = 3
local DEBOUNCE_SECONDS = 0.25
local RESULT_SLOTS = 5
-- Number of always-visible result rows in the dialog. The search may return
-- up to MERGED_MAX hits; anything beyond this many rows is dropped, so keep
-- the two in mind together.
local VISIBLE_RESULT_ROWS = 5

-- Number of rows showing the ALREADY APPLIED depicts entries, each with an
-- "✕" to take it back out again. Entries beyond this many are still stored
-- and uploaded – they are just not individually removable by click; the
-- text field above remains the full, editable truth.
-- Both counts are kept modest on purpose: every row costs dialog height, and
-- the dialog has to fit on the screen.
local APPLIED_ROWS = 6

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

-- The sidebar metadata field and the corresponding line inside
-- description_all are two separate stores for the same value. The export
-- gives the sidebar field priority, so "effective" means: the sidebar value
-- if it holds anything, otherwise the description_all line. Inline comments
-- and whitespace are preserved – only emptiness decides.
local function effectiveSdcValue(sidebarValue, descAllValue)
	if filled(sidebarValue) then
		return sidebarValue
	end
	return descAllValue or ''
end

-- True if the two stores would upload different things. Compared on the bare
-- QIDs, so "Q640 # Harald Krichel" and "Q640" count as equal, as do differing
-- separators and ordering-insensitive whitespace.
local function sdcStoresDiffer(sidebarValue, descAllValue)
	local function key(v)
		local ids = {}
		for token in tostring(v or ''):gmatch('[^,;]+') do
			local qid = normalizeQid(token)
			if qid ~= '' then
				ids[#ids + 1] = qid
			end
		end
		return table.concat(ids, ';')
	end
	-- An empty sidebar field is not a conflict: the description_all line is
	-- simply the only value there is.
	if not filled(sidebarValue) then
		return false
	end
	return key(sidebarValue) ~= key(descAllValue)
end

--------------------------------------------------------------------------------
-- Wikidata search – pure helpers (kept free of any SDK reference so they can
-- be copied verbatim into a standalone Lua 5.1 test)
--------------------------------------------------------------------------------

-- Collapse all runs of whitespace to a single space and trim. CirrusSearch
-- and wbsearchentities both behave better on normalized queries.
local function normalizeQuery(q)
	q = (q or ''):gsub('%s+', ' ')
	return trim(q)
end

-- Merge two result lists ({id,label,description} each): primary order wins,
-- secondary entries are appended unless their id is already present.
-- The merged list is capped at maxCount entries.
local function mergeSearchResults(primary, secondary, maxCount)
	local out, seen = {}, {}
	for _, r in ipairs(primary or {}) do
		if r.id and r.id ~= '' and not seen[r.id] and #out < maxCount then
			seen[r.id] = true
			out[#out + 1] = r
		end
	end
	for _, r in ipairs(secondary or {}) do
		if r.id and r.id ~= '' and not seen[r.id] and #out < maxCount then
			seen[r.id] = true
			out[#out + 1] = r
		end
	end
	return out
end

-- Extract item QIDs from a decoded action=query&list=search response
-- (CirrusSearch full text on wikidata.org; titles in namespace 0 ARE QIDs).
-- Order is preserved, non-QID titles are skipped, the list is capped.
local function extractCirrusQids(decoded, maxCount)
	local out = {}
	if type(decoded) ~= 'table' or type(decoded.query) ~= 'table'
		or type(decoded.query.search) ~= 'table' then
		return out
	end
	for _, e in ipairs(decoded.query.search) do
		local qid = tostring(e.title or ''):match('^Q%d+$')
		if qid and #out < maxCount then
			out[#out + 1] = qid
		end
	end
	return out
end

-- Build {id,label,description} rows from a decoded wbgetentities response,
-- in the order given by orderedQids. Label/description prefer `lang`, then
-- English, then stay empty. Missing entities are skipped.
local function resultsFromEntities(decoded, orderedQids, lang)
	local out = {}
	if type(decoded) ~= 'table' or type(decoded.entities) ~= 'table' then
		return out
	end
	local function pick(tbl)
		if type(tbl) ~= 'table' then return '' end
		local e = tbl[lang] or tbl.en
		if type(e) == 'table' and type(e.value) == 'string' then
			return e.value
		end
		return ''
	end
	for _, qid in ipairs(orderedQids or {}) do
		local ent = decoded.entities[qid]
		if type(ent) == 'table' and not ent.missing then
			out[#out + 1] = {
				id = qid,
				label = pick(ent.labels),
				description = pick(ent.descriptions),
			}
		end
	end
	return out
end

-- Collect the bare QIDs from any number of semicolon/comma separated
-- QID lists (inline "# comments" tolerated), deduplicated, order kept.
local function collectBareQids(...)
	local out, seen = {}, {}
	for i = 1, select('#', ...) do
		local field = select(i, ...) or ''
		for token in field:gmatch('[^,;]+') do
			local qid = normalizeQid(token)
			if qid ~= '' and not seen[qid] then
				seen[qid] = true
				out[#out + 1] = qid
			end
		end
	end
	return out
end

-- Extract one Commons category name per QID from a decoded wbgetentities
-- response (props=claims|labels): P373 value if present (skipping deprecated
-- and non-value snaks), otherwise the English label as a fallback (Commons
-- category names are conventionally English). Deduplicated case-insensitively,
-- order of orderedQids kept; QIDs without either are skipped.
local function extractCommonsCategories(decoded, orderedQids)
	local out, seen = {}, {}
	if type(decoded) ~= 'table' or type(decoded.entities) ~= 'table' then
		return out
	end
	for _, qid in ipairs(orderedQids or {}) do
		local ent = decoded.entities[qid]
		local cat = ''
		if type(ent) == 'table' and not ent.missing then
			local claims = type(ent.claims) == 'table' and ent.claims.P373 or nil
			if type(claims) == 'table' then
				for _, c in ipairs(claims) do
					if type(c) == 'table' and c.rank ~= 'deprecated'
						and type(c.mainsnak) == 'table'
						and c.mainsnak.snaktype == 'value'
						and type(c.mainsnak.datavalue) == 'table'
						and type(c.mainsnak.datavalue.value) == 'string' then
						cat = trim(c.mainsnak.datavalue.value)
						break
					end
				end
			end
			if cat == '' and type(ent.labels) == 'table'
				and type(ent.labels.en) == 'table'
				and type(ent.labels.en.value) == 'string' then
				cat = trim(ent.labels.en.value)
			end
		end
		if cat ~= '' and not seen[cat:lower()] then
			seen[cat:lower()] = true
			out[#out + 1] = cat
		end
	end
	return out
end

-- Merge new category names into an existing semicolon-separated categories
-- string: case-insensitive dedupe, existing entries and their formatting are
-- kept, additions are appended as "; Name". Returns merged string + number
-- of categories actually added.
local function mergeCategories(existing, newList)
	existing = existing or ''
	local seen = {}
	for token in existing:gmatch('[^;]+') do
		local t = trim(token)
		if t ~= '' then
			seen[t:lower()] = true
		end
	end
	local merged = trim(existing)
	local added = 0
	for _, cat in ipairs(newList or {}) do
		local c = trim(cat)
		if c ~= '' and not seen[c:lower()] then
			seen[c:lower()] = true
			if merged == '' then
				merged = c
			else
				merged = merged .. '; ' .. c
			end
			added = added + 1
		end
	end
	return merged, added
end

--------------------------------------------------------------------------------
-- Wikidata search (HTTP; public/unauthenticated)
--------------------------------------------------------------------------------

-- Fuzzy fallback configuration: when the prefix search returns fewer than
-- RESULT_SLOTS hits, a CirrusSearch full-text query fills the list up (finds
-- word-order and ordinal variants like "78th Cannes Film Festival"). The
-- combined result list is capped at MERGED_MAX rows.
local CIRRUS_LIMIT = 8
local MERGED_MAX = 8

local SEARCH_HEADERS = {
	{ field = 'User-Agent', value = 'LrMediaWiki2 SDC tool (https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)' },
}

-- GET + JSON decode. Must run inside an async task because LrHttp.get
-- yields. Network/parse errors return nil.
local function httpGetJson(url)
	local body, respHeaders = LrHttp.get(url, SEARCH_HEADERS)
	if not body or not respHeaders or respHeaders.status ~= 200 then
		return nil
	end
	local ok, data = pcall(function()
		return json:decode(body)
	end)
	if not ok or type(data) ~= 'table' then
		return nil
	end
	return data
end

-- Prefix search via wbsearchentities (fast, but strict about word order).
local function searchEntitiesPrefix(query, lang)
	local url = 'https://www.wikidata.org/w/api.php?action=wbsearchentities'
		.. '&search=' .. MediaWikiApi.urlEncode(query)
		.. '&language=' .. lang
		.. '&uselang=' .. lang
		.. '&type=item&limit=' .. tostring(RESULT_SLOTS) .. '&format=json'
	local data = httpGetJson(url)
	if not data or type(data.search) ~= 'table' then
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

-- Fetch label/description rows for a list of QIDs via wbgetentities.
local function fetchEntityResults(qids, lang)
	if #qids == 0 then return {} end
	local url = 'https://www.wikidata.org/w/api.php?action=wbgetentities'
		.. '&ids=' .. MediaWikiApi.urlEncode(table.concat(qids, '|'))
		.. '&props=labels%7Cdescriptions'
		.. '&languages=' .. lang .. '%7Cen&format=json'
	return resultsFromEntities(httpGetJson(url), qids, lang)
end

-- Combined search: wbsearchentities first; if that yields fewer than
-- RESULT_SLOTS hits, CirrusSearch full text fills the list up (ported from
-- Cammello 0.11.7). Network/parse errors degrade to whatever list exists.
local function searchWikidata(query, lang)
	lang = lang or 'de'
	query = normalizeQuery(query)
	if query == '' then return {} end
	local primary = searchEntitiesPrefix(query, lang)
	if #primary >= RESULT_SLOTS then
		return primary
	end
	local cirrusUrl = 'https://www.wikidata.org/w/api.php?action=query&list=search'
		.. '&srsearch=' .. MediaWikiApi.urlEncode(query)
		.. '&srnamespace=0&srlimit=' .. tostring(CIRRUS_LIMIT) .. '&format=json'
	local qids = extractCirrusQids(httpGetJson(cirrusUrl), CIRRUS_LIMIT)
	local secondary = fetchEntityResults(qids, lang)
	return mergeSearchResults(primary, secondary, MERGED_MAX)
end

-- Fetch Commons category suggestions (P373, fallback: English label) for a
-- list of QIDs. Returns an ordered, deduplicated list of category names.
local function fetchCommonsCategories(qids)
	if #qids == 0 then return {} end
	-- wbgetentities accepts at most 50 ids; more than enough here, but cap
	-- defensively instead of producing an API error.
	local capped = {}
	for i = 1, math.min(#qids, 50) do
		capped[i] = qids[i]
	end
	local url = 'https://www.wikidata.org/w/api.php?action=wbgetentities'
		.. '&ids=' .. MediaWikiApi.urlEncode(table.concat(capped, '|'))
		.. '&props=claims%7Clabels&languages=en&format=json'
	return extractCommonsCategories(httpGetJson(url), capped)
end

-- Split a semicolon/comma separated QID list into its raw tokens (trimmed,
-- empties dropped, inline "# comments" kept as typed). The index of a token
-- here is what the "✕" buttons address.
local function splitQidTokens(list)
	local out = {}
	for token in tostring(list or ''):gmatch('[^,;]+') do
		local t = trim(token)
		if t ~= '' then
			out[#out + 1] = t
		end
	end
	return out
end

-- Rebuild the list without the token at `index`. Out-of-range indices leave
-- the list untouched, so a click on an empty row does nothing.
local function removeQidToken(list, index)
	local tokens = splitQidTokens(list)
	if type(index) ~= 'number' or index < 1 or index > #tokens then
		return trim(list or '')
	end
	table.remove(tokens, index)
	return table.concat(tokens, '; ')
end

-- Display text for one applied entry: "Q640 – Harald Krichel" (the raw token
-- uses "#", which is the storage format; the row shows it more readably).
-- Tokens without a comment are shown as the bare QID.
local function formatAppliedRow(token)
	token = trim(token or '')
	if token == '' then
		return ''
	end
	local qid = token:match('^([^#]+)')
	local comment = token:match('#%s*(.*)$')
	qid = trim(qid or token)
	if comment and trim(comment) ~= '' then
		return qid .. ' – ' .. trim(comment)
	end
	return qid
end

-- Format search results as the text of the always-visible result rows.
-- Returns a list of at most maxRows display strings, in order.
local function formatResultsAsRows(results, maxRows)
	local rows = {}
	for _, r in ipairs(results or {}) do
		if #rows >= maxRows then
			break
		end
		local label = (r.label ~= '' and r.label) or r.id
		local desc = (r.description ~= '' and (' – ' .. r.description)) or ''
		rows[#rows + 1] = label .. desc .. '  (' .. r.id .. ')'
	end
	return rows
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
				-- Since 2.0.26 the editor writes ONE LINE PER QID, so all of
				-- them are collected and merged instead of the last winning.
				dv = trim(dv)
				if dv ~= '' then
					depicts = (depicts == '') and dv or (depicts .. '; ' .. dv)
				end
				handled = true
			end
		end
		if not handled then
			local cv = line:match('^created_during=(.*)$')
			if cv then
				cv = trim(cv)
				if cv ~= '' then
					createdDuring = (createdDuring == '') and cv or (createdDuring .. '; ' .. cv)
				end
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
	-- One "depicts=" line PER QID: with inline comments a single long line was
	-- barely readable. The export side collects all such lines (see
	-- MediaWikiInterface), so this round-trips without loss.
	for _, token in ipairs(splitQidTokens(depicts)) do
		parts[#parts + 1] = 'depicts=' .. token
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
	-- The sidebar (Metadata panel) fields are a SECOND store for the same two
	-- values. At export time the sidebar field wins over the depicts= /
	-- created_during= line in description_all, so the tool has to show that
	-- same effective value – otherwise the user edits one store while the
	-- other one is silently uploaded. On save both stores are written, which
	-- makes them converge after one pass through this dialog.
	local depictsField = activePhoto:getPropertyForPlugin(_PLUGIN, 'depicts') or ''
	local createdDuringField = activePhoto:getPropertyForPlugin(_PLUGIN, 'created_during') or ''
	local captions, depicts, createdDuring, freetext = parseDescriptionAll(descAll)
	-- Keep the raw description_all values for the conflict check below,
	-- BEFORE they are overridden by the sidebar precedence.
	local descAllDepicts = depicts
	local descAllCreatedDuring = createdDuring
	depicts = effectiveSdcValue(depictsField, depicts)
	createdDuring = effectiveSdcValue(createdDuringField, createdDuring)

	-- If the two stores disagree, say so once instead of silently discarding
	-- one of them. The sidebar value is what an export would have used, so
	-- that is what the dialog is prefilled with.
	local conflicts = {}
	if sdcStoresDiffer(depictsField, descAllDepicts) then
		conflicts[#conflicts + 1] = 'Depicts'
	end
	if sdcStoresDiffer(createdDuringField, descAllCreatedDuring) then
		conflicts[#conflicts + 1] = 'Created during'
	end
	if #conflicts > 0 then
		LrDialogs.message('LrMediaWiki – SDC',
			'Die Metadaten-Seitenleiste und der Wikitext enthielten unterschiedliche Werte für: '
			.. table.concat(conflicts, ', ') .. '.\n\n'
			.. 'Angezeigt wird der Wert aus der Seitenleiste – den hätte auch der Upload verwendet. '
			.. 'Beim Speichern werden beide Stellen auf denselben Stand gebracht.',
			'info')
	end
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
	for i = 1, VISIBLE_RESULT_ROWS do
		props['wdRow' .. i] = ''
		props['cdRow' .. i] = ''
	end
	for i = 1, APPLIED_ROWS do
		props['depRow' .. i] = ''
	end
	props.depMore = ''
	props.cdApplied = ''
	props.cdQuery = ''
	props.categories = categoriesField
	props.catStatus = ''
	props.applyDepictsToAll = true

	local f = LrView.osFactory()
	local bind = LrView.bind

	-- Per-section store for the current hits, so the row buttons know which
	-- QID and label they carry. Plain Lua tables – not bound properties.
	local resultData = { depicts = {}, createdDuring = {} }

	-- Debounced live search. Fills the result rows: the bound
	-- static_text titles update (proven in this SDK), so the hits simply
	-- APPEAR – nothing has to be opened or clicked to see them.
	local function liveSearch(key, queryProp, rowPrefix)
		searchGeneration[key] = searchGeneration[key] + 1
		local myGen = searchGeneration[key]
		local q = trim(props[queryProp] or '')

		local function clearRows()
			for i = 1, VISIBLE_RESULT_ROWS do
				props[rowPrefix .. i] = ''
			end
			resultData[key] = {}
		end

		if not filled(q) or #q < MIN_QUERY_CHARS then
			clearRows()
			return
		end
		props[rowPrefix .. 1] = 'Suche…'
		for i = 2, VISIBLE_RESULT_ROWS do
			props[rowPrefix .. i] = ''
		end

		LrTasks.startAsyncTask(function()
			LrTasks.sleep(DEBOUNCE_SECONDS)
			if searchGeneration[key] ~= myGen then return end
			local results = searchWikidata(q, 'de')
			if searchGeneration[key] ~= myGen then return end

			resultData[key] = results
			local labels = formatResultsAsRows(results, VISIBLE_RESULT_ROWS)
			for i = 1, VISIBLE_RESULT_ROWS do
				props[rowPrefix .. i] = labels[i] or ''
			end
			if #results == 0 then
				props[rowPrefix .. 1] = 'Keine Treffer.'
			end
		end)
	end

	-- Applies the hit shown in row `index` of `key` via applyFn. A no-op for
	-- empty rows, so clicking a blank row does nothing.
	local function applyResultRow(key, index, applyFn)
		local hit = (resultData[key] or {})[index]
		if not hit or not hit.id then
			return
		end
		applyFn(qidWithComment(hit.id, hit.label or ''))
	end

	-- Applies a QID typed straight into the search field ("Q640",
	-- "q640 # Kommentar"), for when the number is already known.
	local function applyTypedQid(queryProp, applyFn)
		local qid = normalizeQid(props[queryProp] or '')
		if qid == '' then
			return false
		end
		applyFn(qid)
		props[queryProp] = ''
		return true
	end

	-- Keeps the "applied entries" rows in step with the depicts text field.
	-- The text field stays the single source of truth; these rows are only a
	-- view of it, so editing the text by hand keeps working unchanged.
	local function refreshAppliedRows()
		local tokens = splitQidTokens(props.depicts)
		for i = 1, APPLIED_ROWS do
			props['depRow' .. i] = formatAppliedRow(tokens[i])
		end
		local extra = #tokens - APPLIED_ROWS
		if extra > 0 then
			props.depMore = '… und ' .. tostring(extra) .. ' weitere (im Feld oben)'
		else
			props.depMore = ''
		end
		props.cdApplied = formatAppliedRow(props.createdDuring)
	end

	props:addObserver('depicts', refreshAppliedRows)
	props:addObserver('createdDuring', refreshAppliedRows)
	-- Fill them once for the values loaded from the catalog; the observers
	-- only fire on later changes.
	refreshAppliedRows()

	props:addObserver('wdQuery', function()
		liveSearch('depicts', 'wdQuery', 'wdRow')
	end)
	props:addObserver('cdQuery', function()
		liveSearch('createdDuring', 'cdQuery', 'cdRow')
	end)

	-- Help texts, shown by the "?" buttons next to each section heading.
	-- LrDialogs.message is used deliberately: the SDK has no tooltip
	-- attribute for metadata fields (established in 2.0.12), and whether
	-- LrView dialog controls accept one is UNVERIFIED – a button that opens
	-- a dialog works on every Lightroom version without any such assumption.
	local HELP = {
		depicts = 'Depicts (P180) – was auf dem Bild zu sehen ist.\n\n'
			.. 'In das obere Feld kommen Wikidata-QIDs, mehrere mit Semikolon '
			.. 'getrennt, zum Beispiel:\n\n'
			.. '    Q640; Q42\n\n'
			.. 'Hinter jede QID darf nach einem # ein Kommentar stehen. Der '
			.. 'dient nur der Lesbarkeit in Lightroom und wird vor dem Hochladen '
			.. 'entfernt:\n\n'
			.. '    Q640 # Harald Krichel; Q42 # Douglas Adams\n\n'
			.. 'Im unteren Feld suchst du nach einem Namen. Ab drei Buchstaben '
			.. 'erscheinen die Treffer von selbst darunter; ein Klick auf den '
			.. 'Treffertext übernimmt ihn samt Kommentar. Kennst du die Nummer '
			.. 'schon, tippe sie direkt ein und klicke auf „⬅ QID“.\n\n'
			.. 'Übernommene Einträge stehen als Zeilen unter dem Feld. Das ✕ '
			.. 'am Ende einer Zeile entfernt genau diesen Eintrag wieder.\n\n'
			.. 'Beim Hochladen wird für jede QID eine eigene P180-Aussage '
			.. 'angelegt.',
		createdDuring = 'Created during (P10408) – die Veranstaltung, bei der '
			.. 'das Bild entstanden ist, etwa ein Filmfestival.\n\n'
			.. 'Anders als bei Depicts ist hier nur EINE QID vorgesehen. '
			.. 'Kommentar nach # ist ebenso möglich:\n\n'
			.. '    Q124692383 # Berlinale 2026\n\n'
			.. 'Die Suche funktioniert wie bei Depicts: ab drei Buchstaben '
			.. 'erscheinen die Treffer darunter, ein Klick auf den Treffertext '
			.. 'übernimmt ihn, das ✕ darunter entfernt ihn wieder. Die Suche '
			.. 'findet auch umgestellte Wortfolgen und Ordnungszahlen, etwa '
			.. '„78th Cannes Film Festival“.',
		captions = 'Bildunterschriften (SDC-Captions) – kurze Beschriftungen '
			.. 'je Sprache, die auf Commons als strukturierte Daten liegen.\n\n'
			.. 'Links steht der Sprachcode (ISO, zum Beispiel de, en, fr), '
			.. 'rechts der Text. Leere Zeilen werden ignoriert. Mit „➕ Sprache“ '
			.. 'blendest du eine weitere Zeile ein.\n\n'
			.. '„⬇ Captions → Wikitext“ schreibt die Texte zusätzlich als '
			.. '{{de|1=…}}-Blöcke in den Wikitext. Das lässt sich gefahrlos '
			.. 'mehrfach anklicken – vorhandene Blöcke werden nicht verdoppelt.',
		categories = 'Kategorien – eine Zeile, mehrere mit Semikolon getrennt, '
			.. 'ohne das Präfix „Category:“:\n\n'
			.. '    Berlinale 2026; Harald Krichel\n\n'
			.. '„Vorschlagen (P373)“ sieht bei jeder QID aus Depicts und '
			.. 'Created during nach, welche Commons-Kategorie dort hinterlegt '
			.. 'ist, und ergänzt sie hier. Vorhandene Einträge bleiben '
			.. 'unangetastet; Vorschläge sind Vorschläge und werden erst mit '
			.. 'dem Speichern übernommen.',
	}

	local function helpButton(key)
		return f:push_button {
			title = '?',
			action = function()
				LrDialogs.message('LrMediaWiki – Hilfe', HELP[key], 'info')
			end,
		}
	end

	-- Rows for the already applied depicts entries: label plus a fixed-caption
	-- "✕" that removes exactly this entry. Same proven pattern as the result
	-- rows – bound static_text updates, bound button titles do not.
	local appliedRows = {}
	for i = 1, APPLIED_ROWS do
		appliedRows[i] = f:row {
			f:static_text {
				title = bind('depRow' .. i),
				fill_horizontal = 1,
				width_in_chars = 46,
			},
			f:push_button {
				title = '✕',
				action = function()
					props.depicts = removeQidToken(props.depicts, i)
				end,
			},
		}
	end
	appliedRows[#appliedRows + 1] = f:row {
		f:static_text {
			title = bind('depMore'),
			fill_horizontal = 1,
			width_in_chars = 46,
		},
	}
	local depictsAppliedRows = f:column(appliedRows)

	-- Build the always-visible result rows for both search sections. Each row
	-- is a bound static_text carrying the hit, plus a fixed-caption button
	-- that applies exactly that row.
	local function buildResultRows(rowPrefix, applyFn)
		local rows = {}
		for i = 1, VISIBLE_RESULT_ROWS do
			-- The hit text itself is the click target (mouse_down on
			-- static_text was measured to fire on this installation, and
			-- bound static_text titles are proven to update – so this is the
			-- one control that can do both). The former "⬅" button next to
			-- each row is gone: it did the same thing with an extra target
			-- to aim at.
			rows[i] = f:row {
				f:static_text {
					title = bind(rowPrefix .. i),
					fill_horizontal = 1,
					width_in_chars = 52,
					mouse_down = applyFn(i),
				},
			}
		end
		return f:column(rows)
	end

	local depictsResultRows = buildResultRows('wdRow', function(i)
		return function()
			applyResultRow('depicts', i, function(qidComment)
				props.depicts = appendQid(props.depicts, qidComment)
			end)
		end
	end)
	local createdDuringResultRows = buildResultRows('cdRow', function(i)
		return function()
			applyResultRow('createdDuring', i, function(qidComment)
				props.createdDuring = qidComment
			end)
		end
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

		f:row {
			f:static_text {
				title = 'Depicts (P180)',
				fill_horizontal = 1,
			},
			helpButton('depicts'),
		},
		f:row {
			f:edit_field {
				value = bind('depicts'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
				placeholder_string = 'Q1234567',
			},
		},
		depictsAppliedRows,
		f:row {
			f:edit_field {
				value = bind('wdQuery'),
				immediate = true,
				fill_horizontal = 1,
				placeholder_string = 'Suchen',
			},
			f:push_button {
				title = '⬅ QID',
				action = function()
					applyTypedQid('wdQuery', function(qid)
						props.depicts = appendQid(props.depicts, qid)
					end)
				end,
			},
		},
		-- Result rows are ALWAYS present: the hits appear by themselves as
		-- soon as the search returns, with nothing to open. Bound static_text
		-- titles are proven to update in this SDK; bound push_button titles
		-- are not, which is why the label sits in the text and the button
		-- keeps a fixed caption.
		depictsResultRows,

		f:spacer { height = 10 },

		f:row {
			f:static_text {
				title = 'Kategorien',
				fill_horizontal = 1,
			},
			helpButton('categories'),
		},
		f:row {
			f:edit_field {
				value = bind('categories'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
			},
			f:push_button {
				title = 'Vorschlagen (P373)',
				-- Suggest Commons categories from the QIDs in the depicts and
				-- created_during fields (P373 claim, fallback: English label –
				-- ported from Cammello). Runs async; feedback goes into the
				-- bound status static_text below (bound static_text titles are
				-- proven to update; a modal LrDialogs.message from inside an
				-- async task under presentModalDialog is NOT – VERIFY avoided).
				action = function()
					local qids = collectBareQids(props.depicts, props.createdDuring)
					if #qids == 0 then
						props.catStatus = 'Keine QIDs in Depicts/Created during gefunden.'
						return
					end
					props.catStatus = 'Suche Commons-Kategorien (P373) für '
						.. tostring(#qids) .. ' QID(s)…'
					LrTasks.startAsyncTask(function()
						local cats = fetchCommonsCategories(qids)
						if #cats == 0 then
							props.catStatus = 'Keine Kategorien gefunden (weder P373 noch Label).'
							return
						end
						local merged, added = mergeCategories(props.categories, cats)
						props.categories = merged
						if added == 0 then
							props.catStatus = 'Alle vorgeschlagenen Kategorien sind bereits eingetragen.'
						else
							props.catStatus = tostring(added) .. ' Kategorie(n) ergänzt – bitte prüfen.'
						end
					end)
				end,
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

		f:row {
			f:static_text {
				title = bind('catStatus'),
				fill_horizontal = 1,
				width_in_chars = 60,
			},
		},

		f:spacer { height = 10 },

		f:row {
			f:static_text {
				title = 'Created during (P10408)',
				fill_horizontal = 1,
			},
			helpButton('createdDuring'),
		},
		f:row {
			f:edit_field {
				value = bind('createdDuring'),
				immediate = true,
				fill_horizontal = 1,
				width_in_chars = 44,
				placeholder_string = 'Q1234567',
			},
		},
		f:row {
			f:static_text {
				title = bind('cdApplied'),
				fill_horizontal = 1,
				width_in_chars = 46,
			},
			f:push_button {
				title = '✕',
				action = function()
					props.createdDuring = ''
				end,
			},
		},
		f:row {
			f:edit_field {
				value = bind('cdQuery'),
				immediate = true,
				fill_horizontal = 1,
				placeholder_string = 'Suchen',
			},
			f:push_button {
				title = '⬅ QID',
				action = function()
					applyTypedQid('cdQuery', function(qid)
						props.createdDuring = qid
					end)
				end,
			},
		},
		createdDuringResultRows,

		f:spacer { height = 10 },

		f:row {
			f:static_text {
				title = 'Bildunterschriften (SDC-Captions)',
				fill_horizontal = 1,
			},
			helpButton('captions'),
		},
		f:column(captionRows),
		-- No "➕ Sprache" button any more: all four slots are shown from the
		-- start and their ISO codes are freely editable, so there is nothing
		-- left to reveal.
		f:row {
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

	-- The dialog had grown taller than the screen, with no way to scroll and
	-- the lower sections simply out of reach. Wrap the whole thing in a
	-- scrolled_view with a bounded height. VERIFY-safe: if this SDK version
	-- has no f:scrolled_view (or rejects these attributes), the pcall falls
	-- back to the plain view, i.e. exactly the previous behaviour.
	local scrollable = contents
	local okScroll, scrolled = pcall(function()
		return f:scrolled_view {
			width = 760,
			height = 620,
			horizontal_scroller = false,
			contents,
		}
	end)
	if okScroll and scrolled ~= nil then
		scrollable = scrolled
	else
		MediaWikiUtils.trace('SDC editor: f:scrolled_view unavailable, using plain view')
	end

	local action = LrDialogs.presentModalDialog {
		resizable = true,
		title = 'LrMediaWiki – Structured Data (SDC) bearbeiten',
		contents = scrollable,
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
		-- Keep the sidebar fields in step with the description_all lines, so
		-- the two stores cannot drift apart again (see effectiveSdcValue).
		activePhoto:setPropertyForPlugin(_PLUGIN, 'depicts', trim(props.depicts or ''))
		activePhoto:setPropertyForPlugin(_PLUGIN, 'created_during', trim(props.createdDuring or ''))

		if applyAll then
			local targets = catalog:getTargetPhotos()
			for _, p in ipairs(targets) do
				if p ~= activePhoto then
					local d = p:getPropertyForPlugin(_PLUGIN, 'description_all') or ''
					local caps2, dep2, cd2, ft2 = parseDescriptionAll(d)
					-- Same precedence as when loading: a filled sidebar field
					-- is what that photo would upload today.
					local dep2Field = p:getPropertyForPlugin(_PLUGIN, 'depicts') or ''
					dep2 = effectiveSdcValue(dep2Field, dep2)
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
					local mergedDepicts = mergeDepicts(dep2, depictsToApply)
					local merged = assembleDescriptionAll(rows2,
						mergedDepicts, cd2, ft2, overflow2)
					p:setPropertyForPlugin(_PLUGIN, 'description_all', merged)
					p:setPropertyForPlugin(_PLUGIN, 'depicts', trim(mergedDepicts))
				end
			end
		end
	end)
end)
end)

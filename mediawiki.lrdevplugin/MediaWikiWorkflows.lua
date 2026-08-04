--[==[
MediaWikiWorkflows.lua – liest ~/LrMediaWiki2/workflows.toml auf der
Lightroom-Seite.

Warum ueberhaupt ein zweiter Leser? Der Editor im Browser hat seinen eigenen
Parser in JavaScript. Die Metadatensaetze entstehen aber in Lua, beim Laden
des Zusatzmoduls – und sie sollen dieselben Namen und dieselben Felder
zeigen wie der Editor. Beide muessen deshalb dieselbe Datei gleich lesen.

Damit die beiden nicht auseinanderlaufen, gibt es eine Pruefstufe, die
BEIDE Leser auf dieselbe Datei ansetzt und die Ergebnisse vergleicht.

Absichtlich derselbe TOML-Ausschnitt wie im Browser: Kommentare ausserhalb
von Anfuehrungszeichen, [[workflow]], [workflow.vorbelegung],
[workflow.beispiel], Zeichenketten mit Escapes, Zeichenketten-Listen.
Anders als der Browser-Parser bricht dieser Leser NICHT ab: er ueberspringt,
was er nicht versteht, und sammelt die Stellen in `warnungen`. Ein
Metadatensatz, der beim Laden des Zusatzmoduls stirbt, waere fuer den
Nutzer viel schlimmer als eine ausgelassene Zeile – die Fehlermeldung mit
Zeilennummer bekommt er ohnehin im Editor.

Nichts hier pausiert (LrPathUtils, io.*), pcall ist also unbedenklich.
]==]


local MediaWikiSdcData = require 'MediaWikiSdcData'

local MediaWikiWorkflows = {}

local FELDER_AUS = {
	depicts = true, kategorien = true, veranstaltung = true,
	unterschriften = true, satzbau = true, wikitext = true,
}

-- Jede Feld-ID, die MediaWikiMetadataProvider.lua deklariert. Steht in der
-- Datei des Nutzers etwas anderes, wird es UEBERSPRUNGEN und gemeldet – ein
-- Metadatensatz soll nicht an einem Tippfehler haengen.
local ERLAUBTE_FELDER = {}
for w in string.gmatch([[
	accessionNumber artist author caption_en categories created_during
	creditLine date department depicts description_all description_de
	description_en description_other detail detailPosition dimensions
	exhibitionHistory inscriptions institution medium notes object
	objectHistory otherFields otherVersions placeOfCreation placeOfDiscovery
	references source templates title wikidata
]], '%S+') do
	ERLAUBTE_FELDER[w] = true
end

MediaWikiWorkflows.ERLAUBTE_FELDER = ERLAUBTE_FELDER

local function trim(s)
	return (string.gsub(tostring(s or ''), '^%s*(.-)%s*$', '%1'))
end

-- Kommentar abschneiden, aber nur ausserhalb von Anfuehrungszeichen.
local function stripComment(line)
	local inStr, esc = false, false
	for i = 1, #line do
		local c = string.sub(line, i, i)
		if esc then
			esc = false
		elseif c == '\\' and inStr then
			esc = true
		elseif c == '"' then
			inStr = not inStr
		elseif c == '#' and not inStr then
			return string.sub(line, 1, i - 1)
		end
	end
	return line
end

-- "…" mit denselben Escapes wie im Browser-Parser. Rueckgabe: Wert oder nil.
local function parseString(raw)
	raw = trim(raw)
	if string.sub(raw, 1, 1) ~= '"' then return nil end
	local out, i = {}, 2
	while i <= #raw do
		local c = string.sub(raw, i, i)
		if c == '"' then
			if trim(string.sub(raw, i + 1)) ~= '' then return nil end
			return table.concat(out)
		elseif c == '\\' then
			local n = string.sub(raw, i + 1, i + 1)
			if n == '"' or n == '\\' then
				out[#out + 1] = n
				i = i + 2
			elseif n == 'n' then
				out[#out + 1] = '\n'
				i = i + 2
			elseif n == 't' then
				out[#out + 1] = '\t'
				i = i + 2
			elseif n == 'u' then
				local hex = string.sub(raw, i + 2, i + 5)
				if not string.match(hex, '^%x%x%x%x$') then return nil end
				local cp = tonumber(hex, 16)
				-- UTF-8 von Hand: Lua 5.1 hat kein utf8.char.
				if cp < 0x80 then
					out[#out + 1] = string.char(cp)
				elseif cp < 0x800 then
					out[#out + 1] = string.char(
						192 + math.floor(cp / 64), 128 + (cp % 64))
				else
					out[#out + 1] = string.char(
						224 + math.floor(cp / 4096),
						128 + (math.floor(cp / 64) % 64),
						128 + (cp % 64))
				end
				i = i + 6
			else
				return nil
			end
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return nil
end

-- ["a", "b"] – Trennung an Kommata ausserhalb von Anfuehrungszeichen.
local function parseArray(raw)
	raw = trim(raw)
	if string.sub(raw, 1, 1) ~= '[' or string.sub(raw, -1) ~= ']' then
		return nil
	end
	local inner = trim(string.sub(raw, 2, -2))
	if inner == '' then return {} end
	local teile, cur, inStr, esc = {}, {}, false, false
	for i = 1, #inner do
		local c = string.sub(inner, i, i)
		if esc then
			cur[#cur + 1] = c
			esc = false
		elseif c == '\\' and inStr then
			cur[#cur + 1] = c
			esc = true
		elseif c == '"' then
			inStr = not inStr
			cur[#cur + 1] = c
		elseif c == ',' and not inStr then
			teile[#teile + 1] = table.concat(cur)
			cur = {}
		else
			cur[#cur + 1] = c
		end
	end
	teile[#teile + 1] = table.concat(cur)
	local out = {}
	for i = 1, #teile do
		local v = parseString(teile[i])
		if v == nil then return nil end
		out[#out + 1] = v
	end
	return out
end

-- Zerlegt den Text. Rueckgabe: Liste, Tabelle nach Schluessel, Warnungen.
function MediaWikiWorkflows.parse(text)
	local list, byKey, warn = {}, {}, {}
	local cur, ziel = nil, nil
	local no = 0
	for line in string.gmatch(tostring(text or '') .. '\n', '([^\r\n]*)\r?\n') do
		no = no + 1
		local l = trim(stripComment(line))
		if l ~= '' then
			if l == '[[workflow]]' then
				cur = { schluessel = '', name = '', name_en = '',
				        felder_aus = {}, felder = {},
				        vorbelegung = {}, beispiel = {} }
				list[#list + 1] = cur
				ziel = 'kopf'
			elseif l == '[workflow.vorbelegung]' then
				ziel = 'vorbelegung'
			elseif l == '[workflow.beispiel]' then
				ziel = 'beispiel'
			elseif string.sub(l, 1, 1) == '[' then
				warn[#warn + 1] = 'Zeile ' .. no .. ': unbekannter Abschnitt'
			elseif cur == nil then
				warn[#warn + 1] = 'Zeile ' .. no .. ': vor dem ersten Block'
			else
				local key, raw = string.match(l, '^([%w_]+)%s*=%s*(.+)$')
				if key == nil then
					warn[#warn + 1] = 'Zeile ' .. no .. ': kein Schluessel = Wert'
				elseif ziel == 'kopf' then
					if key == 'schluessel' or key == 'name'
					   or key == 'name_en' then
						local v = parseString(raw)
						if v == nil then
							warn[#warn + 1] = 'Zeile ' .. no .. ': keine Zeichenkette'
						elseif key == 'schluessel' then
							if string.match(v, '^[%w_%-]+$') then
								-- Ein schon bekannter Schluessel ERSETZT den
								-- frueheren Block an dessen Stelle: so wirkt
								-- die eigene Datei des Nutzers, die hinter
								-- der mitgelieferten steht.
								-- `cur` haengt seit [[workflow]] hinten an
								-- der Liste. Bei einem bekannten Schluessel
								-- tritt es an die Stelle des frueheren Blocks
								-- und verschwindet vom Ende.
								local vorher = byKey[v]
								if vorher then
									for i = 1, #list do
										if list[i] == vorher then
											list[i] = cur
											break
										end
									end
									if list[#list] == cur then
										table.remove(list)
									end
								end
								cur.schluessel = v
								byKey[v] = cur
							else
								warn[#warn + 1] = 'Zeile ' .. no
									.. ': schluessel ungueltig'
							end
						else
							cur[key] = v
						end
					elseif key == 'felder_aus' or key == 'felder' then
						local a = parseArray(raw)
						if a == nil then
							warn[#warn + 1] = 'Zeile ' .. no .. ': keine Liste'
						elseif key == 'felder_aus' then
							local ok = {}
							for i = 1, #a do
								if FELDER_AUS[a[i]] then
									ok[#ok + 1] = a[i]
								else
									warn[#warn + 1] = 'Zeile ' .. no
										.. ': unbekannter Abschnitt ' .. a[i]
								end
							end
							cur.felder_aus = ok
						else
							local ok = {}
							for i = 1, #a do
								if ERLAUBTE_FELDER[a[i]] then
									ok[#ok + 1] = a[i]
								else
									warn[#warn + 1] = 'Zeile ' .. no
										.. ': unbekanntes Feld ' .. a[i]
								end
							end
							cur.felder = ok
						end
					else
						warn[#warn + 1] = 'Zeile ' .. no
							.. ': unbekannter Schluessel ' .. key
					end
				else
					local v = parseString(raw)
					if v == nil then
						warn[#warn + 1] = 'Zeile ' .. no .. ': keine Zeichenkette'
					else
						cur[ziel][key] = v
					end
				end
			end
		end
	end

	-- Bloecke ohne Schluessel sind unbrauchbar und fliegen raus.
	local sauber = {}
	for i = 1, #list do
		local w = list[i]
		if w.schluessel ~= '' then
			if w.name == '' then w.name = w.name_en end
			if w.name == '' then w.name = w.schluessel end
			if w.name_en == '' then w.name_en = w.name end
			sauber[#sauber + 1] = w
		else
			warn[#warn + 1] = 'Ein Block ohne schluessel wurde ausgelassen'
		end
	end
	return sauber, byKey, warn
end

-- Liest die Datei und gibt die Liste zurueck. Fehlt sie, ist die Liste leer –
-- die Metadatensaetze fallen dann auf ihre Ersatzbeschriftung zurueck.
-- Alte Fassung: las allein ~/LrMediaWiki2/workflows.toml. Das war schon vor
-- 2.0.61 der falsche Ort fuer die mitgelieferte Datei und kannte die eigene
-- Datei des Nutzers gar nicht - die sechs Metadatensaetze bekamen damit voellig
-- andere Workflows als der Editor. Bleibt als duenne Huelle fuer Altaufrufer.
function MediaWikiWorkflows.load()
	return MediaWikiWorkflows.loadMerged()
end

-- Genau die Quelle, die auch der Editor sieht: mitgelieferte + eigene Datei,
-- zusammengefuehrt. Ergebnis wird kurz zwischengespeichert, weil beim Laden
-- des Zusatzmoduls SECHS Tagset-Plaetze nacheinander bauen und sonst sechsmal
-- dieselbe Datei gelesen und geparst wuerde.
local _cache = nil        -- { list, byKey, warn }
local _cacheZeit = 0
local CACHE_S = 1

function MediaWikiWorkflows.loadMerged()
	local jetzt = os.time()
	if _cache and (jetzt - _cacheZeit) < CACHE_S then
		return _cache[1], _cache[2], _cache[3]
	end
	local text = MediaWikiSdcData.readWorkflowsToml()
	local list, byKey, warn = MediaWikiWorkflows.parse(text or '')
	_cache = { list, byKey, warn }
	_cacheZeit = jetzt
	return list, byKey, warn
end

return MediaWikiWorkflows

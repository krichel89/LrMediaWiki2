#!/usr/bin/env lua5.1
-- Erzeugt mediawiki.lrdevplugin/SdcEditorTemplate.lua aus editor/sdc-editor.html.
--
-- SdcEditorTemplate.lua wird NIE von Hand bearbeitet. Wer die Editorseite
-- ändern will, ändert sdc-editor.html und ruft dieses Skript auf.
--
-- Warum jede Zeile eine gewöhnliche Zeichenkette in Anführungszeichen wird
-- und nicht eine einzige lange Klammerzeichenkette: die Seite enthält "[["
-- und "]]" (Wikitext-Kategorielinks). Eine lange Klammerzeichenkette ist der
-- naheliegende Weg und wird von Lua 5.1 auch korrekt gelesen -- der erste Bau
-- auf diese Art ließ sich in Lightroom aber nicht laden. Zeichenketten in
-- Anführungszeichen haben überhaupt keine Klammersemantik und können in diese
-- Klasse von Problemen gar nicht erst geraten.
--
-- Aufruf (aus dem Wurzelverzeichnis des Projekts):
--   lua5.1 tools/gen-template.lua
--
-- Prüfen lässt sich das Ergebnis, indem man die erzeugte Datei lädt und
-- .html byteweise mit sdc-editor.html vergleicht -- genau das macht
-- tools/check-template.lua.

local IN = arg[1] or 'editor/sdc-editor.html'
local OUT = arg[2] or 'mediawiki.lrdevplugin/SdcEditorTemplate.lua'

local HEADER = [==[
-- This file is part of the LrMediaWiki2 project and distributed under the
-- terms of the MIT license (see LICENSE.txt file in the project root
-- directory).
--
-- HTML template for the browser-based SDC editor (see ToolEditSdcWeb.lua).
--
-- WHY THE PAGE IS BUILT FROM ORDINARY QUOTED STRINGS, one per line, instead
-- of one readable long-bracket string: the page contains "[[" and "]]"
-- (wikitext category links). A long-bracket string is the obvious way to
-- embed it, and it parses correctly in Lua 5.1 -- but the first build that
-- did so failed to load in Lightroom. Quoted strings have no bracket
-- semantics whatsoever, so this form cannot run into that class of problem
-- at all. It is harder to read; that is the price.
--
-- To change the page, edit sdc-editor.html and regenerate this file rather
-- than editing the strings below by hand.
--
-- The placeholder block between the PAYLOAD markers is replaced at runtime
-- with the values of the current photo. Opened directly in a browser, the
-- page still works and shows the sample data -- handy for trying out layout
-- changes without going through Lightroom.

local SdcEditorTemplate = {}

local L = {}

]==]

-- Wandelt eine Zeile in ein Lua-Zeichenkettenliteral. Nur Rückstrich und
-- Anführungszeichen brauchen eine Behandlung; Zeilenumbrüche kommen nicht
-- vor, weil zeilenweise gearbeitet wird.
local function quote(line)
	local s = line:gsub('\\', '\\\\'):gsub('"', '\\"')
	-- Wagenrücklauf und Tabulator sichtbar machen, damit sie eine Änderung
	-- der Datei nicht unsichtbar überleben.
	s = s:gsub('\r', '\\r'):gsub('\t', '\\t')
	return '"' .. s .. '"'
end

local fh = assert(io.open(IN, 'r'), 'Eingabedatei nicht lesbar: ' .. IN)
local html = fh:read('*a')
fh:close()

-- Zeilenweise zerlegen -- so, dass table.concat(lines, "\n") die Datei
-- wieder exakt ergibt. Das ist genau dann der Fall, wenn ein abschließender
-- Zeilenumbruch eine letzte LEERE Zeile hinterlässt: "a\nb\n" zerfällt in
-- {"a", "b", ""}. Der naheliegende gmatch('(.-)\n') über html .. '\n' macht
-- das falsch (er verschluckt die leere Schlusszeile oder erfindet eine),
-- deshalb hier von Hand.
local lines = {}
local pos = 1
while true do
	local i = html:find('\n', pos, true)
	if not i then
		lines[#lines + 1] = html:sub(pos)
		break
	end
	lines[#lines + 1] = html:sub(pos, i - 1)
	pos = i + 1
end

local out = assert(io.open(OUT, 'w'), 'Ausgabedatei nicht schreibbar: ' .. OUT)
out:write(HEADER)
for _, line in ipairs(lines) do
	out:write('L[#L+1] = ', quote(line), '\n')
end
out:write('\nSdcEditorTemplate.html = table.concat(L, "\\n")\n')
out:write('\nreturn SdcEditorTemplate\n')
out:close()

print(string.format('%s erzeugt: %d Zeilen aus %s', OUT, #lines, IN))

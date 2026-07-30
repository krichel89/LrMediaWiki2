#!/usr/bin/env lua5.1
-- Prüft, dass SdcEditorTemplate.lua byteweise dieselbe Seite enthält wie
-- editor/sdc-editor.html. Nach jedem Lauf von gen-template.lua aufrufen.
local htmlPath = arg[1] or 'editor/sdc-editor.html'
local luaPath = arg[2] or 'mediawiki.lrdevplugin/SdcEditorTemplate.lua'

local fh = assert(io.open(htmlPath, 'r'), 'nicht lesbar: ' .. htmlPath)
local html = fh:read('*a')
fh:close()

local mod = assert(loadfile(luaPath))()
assert(type(mod) == 'table', luaPath .. ' liefert keine Tabelle')
assert(type(mod.html) == 'string', luaPath .. ' hat kein Feld .html')

if mod.html == html then
	print(string.format('OK – Vorlage und HTML sind bytegleich (%d Zeichen)', #html))
	os.exit(0)
end

print('FEHLGESCHLAGEN – Vorlage und HTML weichen ab')
print(string.format('  HTML:    %d Zeichen', #html))
print(string.format('  Vorlage: %d Zeichen', #mod.html))
for i = 1, math.min(#html, #mod.html) do
	if html:sub(i, i) ~= mod.html:sub(i, i) then
		print(string.format('  erste Abweichung bei Zeichen %d', i))
		print('  HTML:    ' .. html:sub(math.max(1, i - 40), i + 40):gsub('\n', '\\n'))
		print('  Vorlage: ' .. mod.html:sub(math.max(1, i - 40), i + 40):gsub('\n', '\\n'))
		break
	end
end
os.exit(1)

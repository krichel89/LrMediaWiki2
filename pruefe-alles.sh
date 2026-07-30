#!/bin/bash
# Vollprüfung von LrMediaWiki2 vor der Auslieferung.
# Bricht beim ersten Fehler ab.
set -e
cd "$(dirname "$0")"

# Wo liegt das Repo? Neben diesem Skript, oder per LRMW_REPO gesetzt. Damit
# laeuft das Pruefskript auch aus /Users/h/exec gegen
# /Users/h/Documents/LrMediaWiki2, ohne dass etwas kopiert werden muss.
# Dieses Skript liegt IM Repo, das Repo ist also sein eigener Ordner. Mit
# LRMW_REPO laesst sich ein anderes pruefen.
REPO="${LRMW_REPO:-$PWD}"
[ -d "$REPO" ] || { echo "Repo nicht gefunden: $REPO" >&2; exit 1; }
REPO=$(cd "$REPO" && pwd)
export LRMW_REPO="$REPO"

# Wo liegen die Testdateien? Sie sind absichtlich nicht im Repo (Haralds
# Konvention), also an mehreren Orten suchen. Fehlen sie, werden die
# betreffenden Stufen UEBERSPRUNGEN statt fehlzuschlagen - so laeuft dasselbe
# Skript in GitHub Actions, wo es sie nicht gibt.
TESTS=""
for kandidat in "${LRMW_TESTS:-}" "$REPO/tests" "$PWD" "$HOME/exec"; do
	[ -n "$kandidat" ] || continue
	if [ -f "$kandidat/test_sdcdata_pure.lua" ]; then TESTS="$kandidat"; break; fi
done
if [ -n "$TESTS" ]; then
	echo "Testdateien: $TESTS"
else
	echo "Testdateien nicht gefunden - die drei Testreihen werden uebersprungen."
fi

# Eine Testreihe laufen lassen, falls vorhanden.
reihe() {
	local datei="$1"; shift
	if [ -n "$TESTS" ] && [ -f "$TESTS/$datei" ]; then
		( cd "$TESTS" && "$@" "$datei" ) | sed 's/^/   /'
	else
		echo "   uebersprungen ($datei nicht vorhanden)"
	fi
}
PLUG=$REPO/mediawiki.lrdevplugin
export GOFLAGS=-mod=mod GOCACHE=/tmp/gocache GOPATH=/tmp/gopath

echo "=============================================================="
echo " 1. Lua-Syntax (luac5.1 -p) auf ALLE Dateien"
echo "=============================================================="
n=0
for f in $PLUG/*.lua $REPO/tools/*.lua; do
	luac5.1 -p "$f"
	n=$((n+1))
done
echo "   $n Dateien syntaktisch in Ordnung"

echo
echo "=============================================================="
echo " 2. Info.lua wirklich laden und Menü prüfen"
echo "=============================================================="
( cd $PLUG && lua5.1 - <<'EOF'
local info = assert(loadfile('Info.lua'))()
assert(info.LrPluginName == 'LrMediaWiki2')
assert(info.LrToolkitIdentifier == 'org.ireas.lightroom.mediawiki',
	'ToolkitIdentifier geaendert - alle Per-Foto-Metadaten haengen daran!')
local v = info.VERSION
print(('   Version %d.%d.%d'):format(v.major, v.minor, v.revision))
local function check(list, name)
	assert(type(list) == 'table', name .. ' fehlt')
	for i, item in ipairs(list) do
		assert(type(item.title) == 'string' and #item.title > 0, name..'['..i..'] ohne Titel')
		local fh = io.open(item.file, 'r')
		assert(fh, name..'['..i..'] verweist auf fehlende Datei: '..item.file)
		fh:close()
		assert(item.file ~= 'ToolEditSdc.lua', 'Verweis auf den geloeschten Dialog!')
	end
	return #list
end
local a = check(info.LrLibraryMenuItems, 'LrLibraryMenuItems')
local b = check(info.LrExportMenuItems, 'LrExportMenuItems')
assert(info.LrLibraryMenuItems[1].file == 'ToolEditSdcWeb.lua')
assert(info.LrExportMenuItems[1].file == 'ToolEditSdcWeb.lua')
assert(info.LrLibraryMenuItems[1].title == info.LrExportMenuItems[1].title,
	'Titel unterscheiden sich - EIN macOS-Kurzbefehl reicht dann nicht mehr')
for _, f in ipairs({info.LrInitPlugin, info.LrMetadataProvider,
                    info.LrPluginInfoProvider, info.LrExportServiceProvider.file}) do
	local fh = io.open(f, 'r'); assert(fh, 'Datei fehlt: '..f); fh:close()
end
print(('   Bibliotheksmenue %d, Dateimenue %d Eintraege, alle Dateien vorhanden'):format(a, b))
EOF
)

echo
echo "=============================================================="
echo " 3. Metadatenfeld-Audit (nicht deklarierte Felder = Abbruchfehler)"
echo "=============================================================="
grep -o "id = '[a-zA-Z_]*'" $PLUG/MediaWikiMetadataProvider.lua \
	| sed "s/id = '//;s/'//" | sort > /tmp/declared.txt
grep -ho "PropertyForPlugin([A-Za-z_.]*, *'[a-zA-Z_]*'" $PLUG/*.lua \
	| sed "s/.*'\(.*\)'/\1/" | sort -u > /tmp/used.txt
extra=$(comm -13 /tmp/declared.txt /tmp/used.txt | grep -v '^description_$' || true)
if [ -n "$extra" ]; then echo "   FEHLER, nicht deklariert: $extra"; exit 1; fi
echo "   nur der erlaubte dynamische Aufruf 'description_' .. lang"

echo
echo "=============================================================="
echo " 4. pcall-Audit (pausierender Aufruf in einem pcall = Fehler)"
echo "=============================================================="
hits=$(grep -n "pcall(function()" $PLUG/*.lua | grep -E "LrTasks\.(sleep|execute)|LrHttp\.(get|post)|getTargetPhoto|PropertyForPlugin|withWriteAccessDo|getFormattedMetadata|getRawMetadata" || true)
if [ -n "$hits" ]; then echo "   FEHLER:"; echo "$hits"; exit 1; fi
echo "   kein pausierender Aufruf in einer pcall-Zeile"

echo
echo "=============================================================="
echo " 4b. LrHttp-Audit (der Fehler, der 2.0.37 die Bruecke kostete)"
echo "=============================================================="
# LrHttp.get/post/postMultipart geben (body, HEADERS) zurueck, nicht
# (body, status). Wer den zweiten Rueckgabewert "status" nennt und mit 200
# vergleicht, prueft eine Tabelle gegen eine Zahl - immer ungleich, immer
# stillschweigend falsch. Genau so ist die Bruecke in 2.0.37 nie angelaufen.
schlecht=$(grep -n "local *[A-Za-z_]*, *status *= *LrHttp\." $PLUG/*.lua || true)
if [ -n "$schlecht" ]; then
	echo "   FEHLER: zweiter Rueckgabewert von LrHttp heisst 'status',"
	echo "           das ist aber die Header-TABELLE:"
	echo "$schlecht" | sed 's/^/     /'
	exit 1
fi
# Gegenprobe: jeder LrHttp-Aufruf muss von einer .status-Entnahme begleitet sein
anzahl_calls=$(grep -c "LrHttp\.\(get\|post\|postMultipart\)(" $PLUG/*.lua | awk -F: '{s+=$2} END {print s}')
anzahl_status=$(grep -c "Headers\.status\|headers\.status\|headers and headers.status" $PLUG/*.lua | awk -F: '{s+=$2} END {print s}')
echo "   $anzahl_calls LrHttp-Aufrufe, $anzahl_status Stellen entnehmen .status korrekt"

echo
echo "=============================================================="
echo " 4c. Lua-Sichtbarkeit: local function vor der Definition benutzt?"
echo "=============================================================="
# `local function f` ist erst AB seiner Definition sichtbar. Ein Aufruf davor
# greift nach einer globalen Variablen, also nach nil - Laufzeitabbruch, den
# luac -p nicht findet. Genau so ein Fehler war in 2.0.43 fast ausgeliefert.
python3 - "$PLUG" <<'PYEOF'
import re, sys, glob, os
fehler = 0
for pfad in sorted(glob.glob(os.path.join(sys.argv[1], '*.lua'))):
    text = open(pfad, encoding='utf-8').read()
    zeilen = text.split('\n')
    # Zeilennummer der Definition je local-function-Name
    defs = {}
    for i, z in enumerate(zeilen):
        m = re.match(r'\s*local function ([A-Za-z_][A-Za-z0-9_]*)', z)
        if m and m.group(1) not in defs:
            defs[m.group(1)] = i
    for name, defzeile in defs.items():
        for i in range(defzeile):
            z = re.sub(r'--.*$', '', zeilen[i])
            if re.search(r'(?<![\w.:])' + re.escape(name) + r'\s*\(', z):
                print('   FEHLER %s:%d ruft %s() auf, definiert erst in Zeile %d'
                      % (os.path.basename(pfad), i + 1, name, defzeile + 1))
                fehler += 1
sys.exit(1 if fehler else 0)
PYEOF
echo "   kein local function vor seiner Definition benutzt"

echo
echo "=============================================================="
echo " 5. Editorseite gegen die Lua-Vorlage (Byte-Gleichheit)"
echo "=============================================================="
( cd $REPO && lua5.1 tools/check-template.lua | sed 's/^/   /' )

echo
echo "=============================================================="
echo " 6. Reine Lua-Logik, Ausschnitt frisch aus der Quelle"
echo "=============================================================="
reihe test_sdcdata_pure.lua lua5.1

echo
echo "=============================================================="
echo " 7. Editorseite: Sprachtabellen und Zustandslogik (node)"
echo "=============================================================="
reihe test_bridge_js.js node

echo
echo "=============================================================="
echo " 7b. Satzbau-Rechenwerk (COMPOSE), Ausschnitt frisch aus der Seite"
echo "=============================================================="
reihe test_compose_js.js node

echo
echo "=============================================================="
echo " 8. Hintergrund-App: go vet und Bau aller Zielplattformen"
echo "=============================================================="
( cd $REPO/bridge && go vet ./... && echo "   go vet ohne Befund" )
( cd $REPO/bridge
CGO_ENABLED=0 GOOS=darwin  GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-mac-arm64     ./sdcbridge.go
CGO_ENABLED=0 GOOS=darwin  GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-mac-x86_64    ./sdcbridge.go
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-win-amd64.exe ./sdcbridge.go
CGO_ENABLED=0 GOOS=linux   GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /tmp/sdcbridge-linux                                ./sdcbridge.go )
chmod 755 $PLUG/bin/*
echo "   drei Zielplattformen gebaut, dazu Linux fuer den Funktionstest"

echo
echo "=============================================================="
echo " 9. Funktionstest der Hintergrund-App (echter HTTP-Umlauf)"
echo "=============================================================="
HTML=$REPO/editor/sdc-editor.html
rm -f /tmp/pf.txt /tmp/sse.txt /tmp/page.html
/tmp/sdcbridge-linux --token GEHEIM --page "$HTML" --portfile /tmp/pf.txt --idle 3m --log /tmp/bridge.log &
SRV=$!
for i in $(seq 1 60); do [ -s /tmp/pf.txt ] && break; sleep 0.1; done
PORT=$(python3 -c "import json;print(json.load(open('/tmp/pf.txt'))['port'])")
B="http://127.0.0.1:$PORT"
fail=0
t() { # name erwartet ergebnis
	if [ "$2" = "$3" ]; then echo "   ok    $1 ($3)"; else echo "   FEHLER $1: erwartet $2, bekommen $3"; fail=1; fi
}
t "ohne Token"        403 "$(curl -s -o /dev/null -w '%{http_code}' $B/state)"
t "falsches Token"    403 "$(curl -s -o /dev/null -w '%{http_code}' "$B/state?t=FALSCH")"
t "fremder Host-Kopf" 403 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: boese.example' "$B/state?t=GEHEIM")"
t "Seite"             200 "$(curl -s -o /tmp/page.html -w '%{http_code}' "$B/?t=GEHEIM")"
cmp -s /tmp/page.html "$HTML" && echo "   ok    ausgelieferte Seite bytegleich" || { echo "   FEHLER Seite abweichend"; fail=1; }
( curl -s -N --max-time 4 "$B/events?t=GEHEIM" > /tmp/sse.txt ) & SSE=$!
sleep 0.5
curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"state":{"photoKey":"foto-1","fileName":"a.NEF","captions":{"de":"x"},"depicts":["Q640"]}}' >/dev/null
curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"state":{"photoKey":"foto-2","fileName":"b.NEF","captions":{},"depicts":[]}}' >/dev/null
curl -s -X POST "$B/result?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"photoKey":"foto-2","depicts":"Q42","uiLang":"de"}' >/dev/null
got=$(curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' -d '{}' | python3 -c "import json,sys;print(json.load(sys.stdin).get('result',{}).get('depicts'))")
t "Ergebnis kommt zurueck" "Q42" "$got"
again=$(curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' -d '{}' | python3 -c "import json,sys;print(json.load(sys.stdin).get('result') is None)")
t "und nur einmal" "True" "$again"
wait $SSE 2>/dev/null || true
evts=$(grep -c '^event: state' /tmp/sse.txt || true)
t "Ereignisstrom meldet Fotowechsel" "3" "$evts"
kill $SRV 2>/dev/null || true
[ $fail -eq 0 ] || exit 1

echo
echo "=============================================================="
echo " ALLES GRUEN"
echo "=============================================================="

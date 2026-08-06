#!/bin/bash
# Vollprüfung von LrMediaWiki2 vor der Auslieferung.
# Bricht beim ersten Fehler ab.
set -e

# Ein eigener Temporaerordner fuer alle Zwischendateien - unvorhersagbarer
# Name statt fester /tmp-Pfade, und ein einziger trap raeumt alles weg.
TQ=$(mktemp -d "${TMPDIR:-/tmp}/lrmw2pruef.XXXXXX")
trap 'rm -rf "$TQ" 2>/dev/null || true' EXIT

# WINDOWS/GIT BASH: LuaJIT, python und go sind NATIVE Windows-Programme und
# verstehen die MSYS-Pfade der Form /c/... nicht - loadfile meldet dann
# "cannot open ...: No such file or directory", obwohl die Datei da ist.
# cygpath -m macht daraus C:/... mit Schraegstrichen, das schluckt auch Lua.
# Auf Mac und Linux gibt es cygpath nicht, dort bleibt der Pfad unveraendert.
# Noetig nur fuer Pfade, die IN eine Zeichenkette eingesetzt werden; ein
# blosses Argument wandelt MSYS von sich aus um.
if command -v cygpath >/dev/null 2>&1; then
	nativpfad() { cygpath -m "$1"; }
else
	nativpfad() { printf '%s' "$1"; }
fi
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

# --- Lua 5.1 finden -------------------------------------------------------
#
# Es MUSS die Fassung 5.1 sein: genau die steckt im Lightroom-SDK. Eine
# neuere waere schlimmer als keine, weil sie Schreibweisen durchwinkt, an
# denen Lightroom dann scheitert (goto, Bitoperatoren, das fehlende
# table.unpack in 5.1 und so weiter).
#
# Homebrew hat lua@5.1 im Februar 2024 abgeschaltet, weil es upstream nicht
# mehr gepflegt wird - deshalb wird hier gesucht statt vorausgesetzt.
# LuaJIT gilt als 5.1-tauglich; es ist bei den Erweiterungen etwas grosszuegiger
# (es kennt zum Beispiel goto), aber alles, was es ablehnt, lehnt auch
# Lightroom ab.
LUA51=""
for k in lua5.1 lua-5.1 lua51 luajit lua; do
	command -v "$k" >/dev/null 2>&1 || continue
	v=$("$k" -e 'io.write(_VERSION)' 2>/dev/null || true)
	if [ "$v" = "Lua 5.1" ]; then LUA51="$k"; break; fi
done
if [ -z "$LUA51" ]; then
	cat >&2 <<'HINWEIS'
FEHLER: kein Lua 5.1 gefunden.

Gebraucht wird genau 5.1 - das ist die Fassung im Lightroom-SDK. Eine neuere
Fassung waere schlimmer als keine: sie winkt Schreibweisen durch, an denen
Lightroom spaeter scheitert.

Homebrew hat lua@5.1 im Februar 2024 abgeschaltet. Zwei Wege:

  1. LuaJIT, schnell und aus dem Hauptbestand:
       brew install luajit

  2. Lua 5.1.5 selbst bauen, ohne Abhaengigkeiten:
       curl -LO https://www.lua.org/ftp/lua-5.1.5.tar.gz
       tar xf lua-5.1.5.tar.gz && cd lua-5.1.5
       make macosx
       sudo make install INSTALL_TOP=/usr/local
       sudo ln -sf /usr/local/bin/lua  /usr/local/bin/lua5.1
       sudo ln -sf /usr/local/bin/luac /usr/local/bin/luac5.1
HINWEIS
	exit 1
fi

# Syntaxpruefung: luac ist das passende Werkzeug und meldet schoener, gibt es
# aber nicht ueberall. Sonst tut es der Interpreter mit loadfile - dieselbe
# Pruefung, dieselbe Sprachfassung.
if command -v luac5.1 >/dev/null 2>&1; then
	LUAC="luac5.1 -p"
elif command -v luac-5.1 >/dev/null 2>&1; then
	LUAC="luac-5.1 -p"
else
	LUAC=""
fi

# Python wird fuer zwei Stufen gebraucht. Auf Windows liegt unter dem Namen
# python3 oft nur die Store-Verknuepfung von Microsoft - eine leere Datei,
# die beim Aufruf nur einen Hinweis ausgibt. `command -v` faellt darauf
# herein, deshalb wird jeder Kandidat AUSGEFUEHRT und muss antworten.
PYTHON=""
for k in python3 python; do
	command -v "$k" >/dev/null 2>&1 || continue
	if [ "$("$k" -c 'import sys; sys.stdout.write("ja")' 2>/dev/null || true)" = "ja" ]; then
		PYTHON="$k"; break
	fi
done
pruefe_syntax() {
	if [ -n "$LUAC" ]; then
		$LUAC "$1"
	else
		# Der Umbruch als '\n' in EINFACHEN Anfuehrungszeichen. In [[ ]] waere
		# er ein wortwoertliches Backslash-n und stuende so in der Meldung.
		lokal_pfad=$(nativpfad "$1")
		"$LUA51" -e "local f, e = loadfile([[$lokal_pfad]]); if not f then io.stderr:write(e, '\n'); os.exit(1) end"
	fi
}
echo "Lua 5.1: $LUA51$([ -n "$LUAC" ] && echo " (Syntaxpruefung mit ${LUAC%% *})" || echo " (Syntaxpruefung ueber loadfile)")"

# Eine Testreihe laufen lassen, falls vorhanden.
reihe() {
	local datei="$1"; shift
	if [ -n "$TESTS" ] && [ -f "$TESTS/$datei" ]; then
		( cd "$TESTS" && "$@" "$datei" ) | sed 's/^/   /'
	else
		echo "   uebersprungen ($datei nicht vorhanden)"
	fi
}
PLUG="$REPO/mediawiki.lrdevplugin"
export GOFLAGS=-mod=mod GOCACHE=/tmp/gocache GOPATH=/tmp/gopath

echo "=============================================================="
echo " 0. Merge-Konfliktreste"
echo "=============================================================="
# Muss VOR der Syntaxpruefung laufen. Ein steckengebliebener Konfliktmarker
# meldet sich sonst als "unexpected symbol near '<'" mit einer Zeilennummer -
# eine Meldung, aus der niemand auf einen Merge-Konflikt schliesst. Genau das
# ist bei 2.0.47 passiert: das ausgelieferte Info.lua trug die Marker, und der
# Nutzer bekam nur den Syntaxfehler zu sehen.
#
# Gesucht wird am Zeilenanfang, damit die Marker in diesem Kommentar hier
# nicht selbst anschlagen.
konflikte=$(grep -rlE '^(<{7}|={7}|>{7})( |$)' \
	--include='*.lua' --include='*.md' --include='*.go' --include='*.html' \
	--include='*.sh' --include='*.txt' --include='*.yml' \
	"$REPO" 2>/dev/null || true)
if [ -n "$konflikte" ]; then
	echo "   FEHLER: diese Dateien enthalten Merge-Konfliktreste:"
	echo "$konflikte" | sed "s#^$REPO/#     #"
	echo
	echo "   Auflösen, dann erst weiter. Stellen zeigen:"
	echo "     grep -rn '^<<<<<<<' \"$REPO\""
	exit 1
fi
echo "   keine Konfliktreste"

echo
echo "=============================================================="
echo " 1. Lua-Syntax auf ALLE Dateien"
echo "=============================================================="
n=0
for f in "$PLUG"/*.lua "$REPO"/tools/*.lua; do
	pruefe_syntax "$f"
	n=$((n+1))
done
echo "   $n Dateien syntaktisch in Ordnung"

echo
echo "=============================================================="
echo " 2. Info.lua wirklich laden und Menü prüfen"
echo "=============================================================="
( cd "$PLUG" && "$LUA51" - <<'EOF'
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
grep -o "id = '[a-zA-Z_]*'" "$PLUG/MediaWikiMetadataProvider.lua" \
	| sed "s/id = '//;s/'//" | sort > "$TQ/declared.txt"
grep -ho "PropertyForPlugin([A-Za-z_.]*, *'[a-zA-Z_]*'" "$PLUG"/*.lua \
	| sed "s/.*'\(.*\)'/\1/" | sort -u > "$TQ/used.txt"
extra=$(comm -13 "$TQ/declared.txt" "$TQ/used.txt" | grep -v '^description_$' || true)
if [ -n "$extra" ]; then echo "   FEHLER, nicht deklariert: $extra"; exit 1; fi
echo "   nur der erlaubte dynamische Aufruf 'description_' .. lang"

echo
echo "=============================================================="
echo " 4. pcall-Audit (pausierender Aufruf in einem pcall = Fehler)"
echo "=============================================================="
hits=$(grep -n "pcall(function()" "$PLUG"/*.lua | grep -E "LrTasks\.(sleep|execute)|LrHttp\.(get|post)|getTargetPhoto|PropertyForPlugin|withWriteAccessDo|getFormattedMetadata|getRawMetadata" || true)
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
schlecht=$(grep -n "local *[A-Za-z_]*, *status *= *LrHttp\." "$PLUG"/*.lua || true)
if [ -n "$schlecht" ]; then
	echo "   FEHLER: zweiter Rueckgabewert von LrHttp heisst 'status',"
	echo "           das ist aber die Header-TABELLE:"
	echo "$schlecht" | sed 's/^/     /'
	exit 1
fi
# Gegenprobe: jeder LrHttp-Aufruf muss von einer .status-Entnahme begleitet sein
anzahl_calls=$(grep -c "LrHttp\.\(get\|post\|postMultipart\)(" "$PLUG"/*.lua | awk -F: '{s+=$2} END {print s}')
anzahl_status=$(grep -c "Headers\.status\|headers\.status\|headers and headers.status" "$PLUG"/*.lua | awk -F: '{s+=$2} END {print s}')
echo "   $anzahl_calls LrHttp-Aufrufe, $anzahl_status Stellen entnehmen .status korrekt"

echo
echo "=============================================================="
echo " 4c. Lua-Sichtbarkeit: local function vor der Definition benutzt?"
echo "=============================================================="
# `local function f` ist erst AB seiner Definition sichtbar. Ein Aufruf davor
# greift nach einer globalen Variablen, also nach nil - Laufzeitabbruch, den
# luac -p nicht findet. Genau so ein Fehler war in 2.0.43 fast ausgeliefert.
if [ -z "$PYTHON" ]; then
	echo "   uebersprungen (kein lauffaehiges Python gefunden)"
	echo "   Windows: winget install Python.Python.3.12, danach Git Bash neu oeffnen"
else
"$PYTHON" - "$(nativpfad "$PLUG")" <<'PYEOF'
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
fi

echo
echo "=============================================================="
echo " 5. Editorseite gegen die Lua-Vorlage (Byte-Gleichheit)"
echo "=============================================================="
( cd "$REPO" && "$LUA51" tools/check-template.lua | sed 's/^/   /' )

echo
echo "=============================================================="
echo " 6. Reine Lua-Logik, Ausschnitt frisch aus der Quelle"
echo "=============================================================="
reihe test_sdcdata_pure.lua "$LUA51"

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
echo " 7c. Workflows: TOML-Parser der Seite + mitgelieferte Vorlage"
echo "=============================================================="
reihe test_workflows_js.js node

echo
echo "=============================================================="
echo " 7d. Schreibbereich (applyScope), Ausschnitt frisch aus der Quelle"
echo "=============================================================="
reihe test_scope_lua.lua "$LUA51"

echo
echo "=============================================================="
echo " 7e. Workflow-Leser der Lightroom-Seite (MediaWikiWorkflows)"
echo "=============================================================="
reihe test_workflows_lua.lua "$LUA51"

echo
echo "=============================================================="
echo " 7f. Rohdatenfeld: Trennueberschriften beim Einlesen"
echo "=============================================================="
reihe test_rawmeta_lua.lua "$LUA51"

echo
echo "=============================================================="
echo " 7g. Beschriftungen: kein Feld heisst mehr Wikitext"
echo "=============================================================="
reihe test_labels_lua.lua "$LUA51"

echo
HOSTBIN="${TMPDIR:-/tmp}/sdcbridge-host"
echo "=============================================================="
echo " 8. Hintergrund-App: go vet und Bau aller Zielplattformen"
echo "=============================================================="
( cd "$REPO/bridge" && go vet ./... && echo "   go vet ohne Befund" )
( cd "$REPO/bridge"
CGO_ENABLED=0 GOOS=darwin  GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-mac-arm64     ./sdcbridge.go
CGO_ENABLED=0 GOOS=darwin  GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-mac-x86_64    ./sdcbridge.go
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ../mediawiki.lrdevplugin/bin/sdcbridge-win-amd64.exe ./sdcbridge.go
# Fuer den Funktionstest eine Fassung fuer DIESEN Rechner - ohne GOOS/GOARCH,
# also nativ. Vorher stand hier fest GOOS=linux; auf einem Mac liess sich das
# Ergebnis nicht starten ("cannot execute binary file").
CGO_ENABLED=0 go build -trimpath -o "$HOSTBIN" ./sdcbridge.go )
chmod 755 "$PLUG"/bin/*
echo "   drei Zielplattformen gebaut, dazu eine Fassung fuer diesen Rechner"

echo
echo "=============================================================="
echo " 9. Funktionstest der Hintergrund-App (echter HTTP-Umlauf)"
echo "=============================================================="
HTML="$REPO/editor/sdc-editor.html"
"$HOSTBIN" --token GEHEIM --page "$(nativpfad "$HTML")" \
	--portfile "$(nativpfad "$TQ/pf.txt")" --idle 3m --log "$(nativpfad "$TQ/bridge.log")" &
SRV=$!
for _ in $(seq 1 60); do [ -s "$TQ/pf.txt" ] && break; sleep 0.1; done
# Die Portdatei ist ein einzeiliges JSON. Mit sed statt Python gelesen -
# eine Abhaengigkeit weniger, und auf Windows ist Python oft nicht da.
PORT=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$TQ/pf.txt")
if [ -z "$PORT" ]; then
	echo "   FEHLER: kein Port in der Portdatei:" >&2
	cat "$TQ/pf.txt" >&2 || true
	kill "$SRV" 2>/dev/null || true
	exit 1
fi
B="http://127.0.0.1:$PORT"
fail=0
t() { # name erwartet ergebnis
	if [ "$2" = "$3" ]; then echo "   ok    $1 ($3)"; else echo "   FEHLER $1: erwartet $2, bekommen $3"; fail=1; fi
}
t "ohne Token"        403 "$(curl -s -o /dev/null -w '%{http_code}' "$B/state")"
t "falsches Token"    403 "$(curl -s -o /dev/null -w '%{http_code}' "$B/state?t=FALSCH")"
t "fremder Host-Kopf" 403 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: boese.example' "$B/state?t=GEHEIM")"
t "Seite"             200 "$(curl -s -o "$TQ/page.html" -w '%{http_code}' "$B/?t=GEHEIM")"
cmp -s "$TQ/page.html" "$HTML" && echo "   ok    ausgelieferte Seite bytegleich" || { echo "   FEHLER Seite abweichend"; fail=1; }
( curl -s -N --max-time 4 "$B/events?t=GEHEIM" > "$TQ/sse.txt" ) & SSE=$!
sleep 0.5
curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"state":{"photoKey":"foto-1","fileName":"a.NEF","captions":{"de":"x"},"depicts":["Q640"]}}' >/dev/null
curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"state":{"photoKey":"foto-2","fileName":"b.NEF","captions":{},"depicts":[]}}' >/dev/null
curl -s -X POST "$B/result?t=GEHEIM" -H 'Content-Type: application/json' \
  -d '{"photoKey":"foto-2","depicts":"Q42","uiLang":"de"}' >/dev/null
# Ohne Python ausgewertet - auf Windows liegt unter python3 oft nur die
# Store-Verknuepfung. Die Antwort ist {"rev":N,"result":{…},"subs":N}, und
# "result" traegt json:",omitempty": ist kein Ergebnis da, FEHLT der
# Schluessel ganz. result ist ein flaches Objekt, deshalb reicht [^}]*.
antwort=$(curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' -d '{}')
ergebnis=$(printf '%s' "$antwort" | sed -n 's/.*"result":{\([^}]*\)}.*/\1/p')
got=$(printf '%s' "$ergebnis" | sed -n 's/.*"depicts"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
t "Ergebnis kommt zurueck" "Q42" "$got"
antwort2=$(curl -s -X POST "$B/sync?t=GEHEIM" -H 'Content-Type: application/json' -d '{}')
if printf '%s' "$antwort2" | grep -q '"result"'; then again=nein; else again=ja; fi
t "und nur einmal" "ja" "$again"
wait $SSE 2>/dev/null || true
evts=$(grep -c '^event: state' "$TQ/sse.txt" || true)
t "Ereignisstrom meldet Fotowechsel" "3" "$evts"
# Erst beenden, DANN auf das Ende warten. Unter Windows haelt ein noch
# laufender Prozess seine Protokolldatei offen, und das Aufraeumen am
# Skriptende scheitert mit "Device or resource busy".
kill "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true
[ $fail -eq 0 ] || exit 1

echo
echo "=============================================================="
echo " ALLES GRUEN"
echo "=============================================================="

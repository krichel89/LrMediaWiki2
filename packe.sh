#!/bin/bash
#
# packe.sh - baut die Auslieferungspakete.
#
# EINE Stelle fuer das Packen, damit lokal und in GitHub Actions genau dasselbe
# entsteht. Zwei Pakete, weil zwei sehr verschiedene Leute sie brauchen:
#
#   LrMediaWiki2-<version>.zip
#       Fuer NUTZER. Enthaelt genau einen Ordner: mediawiki.lrdevplugin.
#       Entpacken, in Lightroom hinzufuegen, fertig. Kein Quelltext der
#       Bruecke, keine Bauskripte, keine Entwicklerdokumente - das war der
#       Hauptgrund, warum die Installation unnoetig kompliziert aussah.
#
#   LrMediaWiki2-complete-<version>.zip
#       Alles, wie bisher: Go-Quelltext, editor/, tools/, Dokumente.
#
# Aufruf:  ./packe.sh [Zielverzeichnis]
# Ohne Angabe landet beides in dist/.

set -euo pipefail
cd "$(dirname "$0")"

ZIEL="${1:-dist}"
PLUG="mediawiki.lrdevplugin"

[ -d "$PLUG" ] || { echo "FEHLER: $PLUG nicht gefunden." >&2; exit 1; }

# Version aus Info.lua - eine Quelle, nie von Hand nachziehen.
MA=$(sed -n 's/.*major *= *\([0-9]*\).*/\1/p' "$PLUG/Info.lua" | head -1)
MI=$(sed -n 's/.*minor *= *\([0-9]*\).*/\1/p' "$PLUG/Info.lua" | head -1)
RE=$(sed -n 's/.*revision *= *\([0-9]*\).*/\1/p' "$PLUG/Info.lua" | head -1)
if [ -z "$MA" ] || [ -z "$MI" ] || [ -z "$RE" ]; then
	echo "FEHLER: Version aus Info.lua nicht lesbar." >&2; exit 1
fi
# zip und unzip gehoeren NICHT zum Lieferumfang von Git fuer Windows - dort
# fehlen beide. Lieber hier klar sagen was fehlt als spaeter ein nacktes
# "command not found" mitten im Lauf.
fehlt=""
for w in zip unzip; do command -v "$w" >/dev/null 2>&1 || fehlt="$fehlt $w"; done
if [ -n "$fehlt" ]; then
	cat >&2 <<HINWEIS
FEHLER: es fehlt:$fehlt

Git Bash unter Windows bringt zip und unzip nicht mit. Zwei Wege:

  1. Auf dem Windows-Rechner braucht es die Pakete gar nicht - das Release
     baut der macOS-Laeufer aus release.yml. Dann:
         ./release.sh --skip-pack

  2. Wenn du sie doch lokal willst, zip und unzip nachinstallieren und
     dafuer sorgen, dass beide im PATH von Git Bash liegen.
HINWEIS
	exit 1
fi

VERSION="$MA.$MI.$RE"

if [ ! -d "$PLUG/bin" ] || [ -z "$(ls -A "$PLUG/bin" 2>/dev/null)" ]; then
	echo "WARNUNG: $PLUG/bin ist leer - die Hintergrund-App fehlt in den Paketen."
	echo "         Vorher ./baue-bruecke.sh aufrufen."
fi

# Letzte Sperre vor dem Packen. packe.sh ist die einzige Stelle, durch die
# jedes Paket geht - lokal wie in CI. Ein Konfliktrest darf hier nicht
# vorbeikommen, auch wenn jemand das Pruefskript uebersprungen hat.
konflikte=$(grep -rlE '^(<{7}|={7}|>{7})( |$)' "$PLUG" 2>/dev/null || true)
if [ -n "$konflikte" ]; then
	echo "FEHLER: Merge-Konfliktreste im Zusatzmodul-Ordner:" >&2
	echo "$konflikte" | sed 's/^/  /' >&2
	echo "Erst aufloesen, dann packen." >&2
	exit 1
fi

mkdir -p "$ZIEL"
# Den Zielpfad absolut machen: das Vollpaket wird aus dem ELTERNverzeichnis
# gepackt, ein relatives Ziel zeigte von dort ins Leere (mit "dist" fiel das
# nie auf, mit einem absoluten oder anderen Ziel brach zip ab).
ZIEL=$(cd "$ZIEL" && pwd)
NUTZER="$ZIEL/LrMediaWiki2-$VERSION.zip"
VOLL="$ZIEL/LrMediaWiki2-complete-$VERSION.zip"
rm -f "$NUTZER" "$VOLL"

AUS=(-x '*/.git/*' -x '*.DS_Store' -x '*/._*' -x '*/dist/*')

# --- Nutzerpaket: der Zusatzmodul-Ordner plus Lizenz ----------------------
# LICENSE.txt und CREDITS.txt MUESSEN mit: die X11-Lizenz verlangt den
# Vermerk in allen Kopien, und das Nutzerpaket ist eine Kopie. Sie liegen
# im Wurzelverzeichnis und kaemen sonst nur ins Vollpaket.
for f in LICENSE.txt CREDITS.txt; do
	[ -f "$f" ] || { echo "FEHLER: $f fehlt - ohne Lizenz wird nicht gepackt." >&2; exit 1; }
done
zip -q -r -y "$NUTZER" "$PLUG" LICENSE.txt CREDITS.txt "${AUS[@]}"

# --- Vollpaket: alles, mit Deckel-Ordner wie bisher ----------------------
# Aus dem Elternverzeichnis packen, damit "LrMediaWiki2/" im Archiv steht.
NAME=$(basename "$PWD")
( cd .. && zip -q -r -y "$VOLL" "$NAME" "${AUS[@]}" -x "*/dist/*" )

printf 'Version %s\n' "$VERSION"
printf '  %-44s %s\n' "$(basename "$NUTZER")" "$(du -h "$NUTZER" | cut -f1)"
printf '  %-44s %s\n' "$(basename "$VOLL")" "$(du -h "$VOLL" | cut -f1)"

# --- Gegenproben ---------------------------------------------------------
# Das Nutzerpaket muss GENAU einen Ordner auf oberster Ebene haben, sonst ist
# die Anleitung "entpacken und diesen Ordner hinzufuegen" falsch.
# Erwartet oben: der Zusatzmodul-Ordner, LICENSE.txt, CREDITS.txt - sonst nichts.
OBEN=$(unzip -Z1 "$NUTZER" | cut -d/ -f1 | sort -u \
	| grep -v -x -e "$PLUG" -e LICENSE.txt -e CREDITS.txt || true)
if [ -n "$OBEN" ]; then
	echo "FEHLER: Unerwartetes auf oberster Ebene im Nutzerpaket:" >&2
	printf '%s\n' "$OBEN" | sed 's/^/  /' >&2
	exit 1
fi
INHALT=$(mktemp "${TMPDIR:-/tmp}/packe-inhalt.XXXXXX")
unzip -Z1 "$NUTZER" > "$INHALT" 2>/dev/null || true
if grep -q "$PLUG/Info.lua" "$INHALT"; then
	echo "  ok  Nutzerpaket: oberste Ebene sauber, Info.lua enthalten"
else
	echo "FEHLER: Info.lua fehlt im Nutzerpaket." >&2; rm -f "$INHALT"; exit 1
fi
if grep -q "bin/sdcbridge" "$INHALT"; then
	echo "  ok  Nutzerpaket: Hintergrund-App enthalten"
else
	echo "  Hinweis: Nutzerpaket ohne Hintergrund-App (Dateiweg funktioniert trotzdem)"
fi
# Und der Quelltext der Bruecke darf NICHT im Nutzerpaket sein.
if grep -q 'sdcbridge.go' "$INHALT"; then
	echo "FEHLER: Go-Quelltext im Nutzerpaket - das sollte nur im Vollpaket sein." >&2
	rm -f "$INHALT"; exit 1
fi
# Die mitgelieferte Workflow-Datei MUSS dabei sein - ohne sie hat der Nutzer
# nach der Installation keine Workflows.
if grep -qE 'workflows\.toml$' "$INHALT"; then
	echo "  ok  Nutzerpaket: workflows.toml enthalten"
else
	echo "FEHLER: workflows.toml fehlt im Nutzerpaket." >&2
	rm -f "$INHALT"; exit 1
fi
# Die eigene Datei des Nutzers darf NIEMALS mitgeliefert werden - sie wuerde
# beim Auspacken seine Anpassungen ueberschreiben.
# Genau der Dateiname, nicht die Beispieldatei daneben (…​.toml.beispiel).
if grep -qE 'workflows-eigene\.toml$' "$INHALT"; then
	echo "FEHLER: workflows-eigene.toml im Paket - die gehoert dem Nutzer." >&2
	rm -f "$INHALT"; exit 1
fi
if grep -q -x 'LICENSE.txt' "$INHALT" && grep -q -x 'CREDITS.txt' "$INHALT"; then
	echo "  ok  Nutzerpaket: LICENSE.txt und CREDITS.txt enthalten"
else
	echo "FEHLER: LICENSE.txt oder CREDITS.txt fehlt im Nutzerpaket." >&2
	rm -f "$INHALT"; exit 1
fi
rm -f "$INHALT"
echo "  ok  Nutzerpaket ohne Entwicklerdateien"

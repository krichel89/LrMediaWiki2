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
VERSION="$MA.$MI.$RE"

if [ ! -d "$PLUG/bin" ] || [ -z "$(ls -A "$PLUG/bin" 2>/dev/null)" ]; then
	echo "WARNUNG: $PLUG/bin ist leer - die Hintergrund-App fehlt in den Paketen."
	echo "         Vorher ./baue-bruecke.sh aufrufen."
fi

mkdir -p "$ZIEL"
NUTZER="$ZIEL/LrMediaWiki2-$VERSION.zip"
VOLL="$ZIEL/LrMediaWiki2-complete-$VERSION.zip"
rm -f "$NUTZER" "$VOLL"

AUS=(-x '*/.git/*' -x '*.DS_Store' -x '*/._*' -x '*/dist/*')

# --- Nutzerpaket: nur der Zusatzmodul-Ordner ------------------------------
zip -q -r -y "$NUTZER" "$PLUG" "${AUS[@]}"

# --- Vollpaket: alles, mit Deckel-Ordner wie bisher ----------------------
# Aus dem Elternverzeichnis packen, damit "LrMediaWiki2/" im Archiv steht.
NAME=$(basename "$PWD")
( cd .. && zip -q -r -y "$OLDPWD/$VOLL" "$NAME" "${AUS[@]}" -x "*/dist/*" )

printf 'Version %s\n' "$VERSION"
printf '  %-44s %s\n' "$(basename "$NUTZER")" "$(du -h "$NUTZER" | cut -f1)"
printf '  %-44s %s\n' "$(basename "$VOLL")" "$(du -h "$VOLL" | cut -f1)"

# --- Gegenproben ---------------------------------------------------------
# Das Nutzerpaket muss GENAU einen Ordner auf oberster Ebene haben, sonst ist
# die Anleitung "entpacken und diesen Ordner hinzufuegen" falsch.
OBEN=$(unzip -Z1 "$NUTZER" | cut -d/ -f1 | sort -u | grep -c . || true)
if [ "$OBEN" != "1" ]; then
	echo "FEHLER: Nutzerpaket hat $OBEN Einträge auf oberster Ebene, erwartet 1." >&2
	exit 1
fi
unzip -Z1 "$NUTZER" > /tmp/packe-inhalt.$$ 2>/dev/null || true
if grep -q "$PLUG/Info.lua" /tmp/packe-inhalt.$$; then
	echo "  ok  Nutzerpaket: genau ein Ordner, Info.lua enthalten"
else
	echo "FEHLER: Info.lua fehlt im Nutzerpaket." >&2; rm -f /tmp/packe-inhalt.$$; exit 1
fi
if grep -q "bin/sdcbridge" /tmp/packe-inhalt.$$; then
	echo "  ok  Nutzerpaket: Hintergrund-App enthalten"
else
	echo "  Hinweis: Nutzerpaket ohne Hintergrund-App (Dateiweg funktioniert trotzdem)"
fi
# Und der Quelltext der Bruecke darf NICHT im Nutzerpaket sein.
if grep -q 'sdcbridge.go' /tmp/packe-inhalt.$$; then
	echo "FEHLER: Go-Quelltext im Nutzerpaket - das sollte nur im Vollpaket sein." >&2
	rm -f /tmp/packe-inhalt.$$; exit 1
fi
rm -f /tmp/packe-inhalt.$$
echo "  ok  Nutzerpaket ohne Entwicklerdateien"

#!/bin/bash
#
# Baut die Hintergrund-App (SDC-Bruecke) fuer alle Zielplattformen nach
# mediawiki.lrdevplugin/bin/.
#
# Diese Dateien sind absichtlich nicht versioniert, siehe .gitignore. Sie
# entstehen hier vor dem Packen und werden nur mit dem Release-ZIP verteilt.
# Vor jedem Release also einmal aufrufen:
#
#     ./baue-bruecke.sh
#
# Gebraucht wird nur die Go-Werkzeugkette (brew install go). Die App hat
# keine Abhaengigkeiten ausser der Standardbibliothek, es wird nichts
# heruntergeladen.
#
# HINWEIS ZUR SIGNIERUNG: dieses Skript signiert nicht. Die frisch gebauten
# Programme sind unsigniert, macOS fragt beim ersten Start nach. Zum eigenen
# Testen genuegt
#
#     xattr -dr com.apple.quarantine mediawiki.lrdevplugin/bin
#
# Fuer die Verteilung an Dritte muessen die beiden Mac-Fassungen signiert und
# notarisiert werden. Das bewusst nicht hier, weil dabei Zertifikate und
# Kennwoerter im Spiel sind.

set -euo pipefail
cd "$(dirname "$0")"

OUT="mediawiki.lrdevplugin/bin"
SRC="sdcbridge.go"

if ! command -v go >/dev/null 2>&1; then
	echo "FEHLER: go nicht gefunden. Mit 'brew install go' nachinstallieren." >&2
	exit 1
fi

mkdir -p "$OUT"

# -trimpath nimmt die absoluten Pfade des Bauverzeichnisses aus der Datei,
# -s -w laesst Symboltabelle und DWARF weg. Beides macht die Datei kleiner
# und den Bau besser wiederholbar. CGO aus, damit nichts von der lokalen
# Systembibliothek abhaengt.
build() {
	local goos="$1" goarch="$2" name="$3"
	printf '  %-24s' "$name"
	( cd bridge && CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
		go build -trimpath -ldflags="-s -w" -o "../$OUT/$name" "./$SRC" )
	printf '%8d Bytes\n' "$(wc -c < "$OUT/$name")"
}

echo "Baue die Hintergrund-App aus bridge/$SRC:"
build darwin  arm64 sdcbridge-mac-arm64
build darwin  amd64 sdcbridge-mac-x86_64
build windows amd64 sdcbridge-win-amd64.exe

chmod 755 "$OUT"/sdcbridge-mac-* 2>/dev/null || true

echo
echo "Fertig. Die Dateien liegen in $OUT und sind nicht versioniert."
echo "Kurzer Rauchtest der Fassung fuer diesen Rechner:"

# Auf dem Mac laesst sich die passende Fassung gleich anfassen. Schlaegt das
# fehl, liegt es fast immer an der Gatekeeper-Sperre (siehe Kopf).
case "$(uname -s)-$(uname -m)" in
	Darwin-arm64)  probe="$OUT/sdcbridge-mac-arm64" ;;
	Darwin-x86_64) probe="$OUT/sdcbridge-mac-x86_64" ;;
	*)             probe="" ;;
esac

if [ -n "$probe" ] && [ -x "$probe" ]; then
	if version="$("$probe" --version 2>&1)"; then
		echo "  $version"
	else
		echo "  liess sich nicht starten. Bei Gatekeeper-Sperre:"
		echo "  xattr -dr com.apple.quarantine $OUT"
		exit 1
	fi
else
	echo "  (auf dieser Plattform nicht moeglich, uebersprungen)"
fi

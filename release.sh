#!/bin/bash
#
# release.sh - veroeffentlicht den Stand, der in diesem Repo liegt.
#
# Liegt IM Repo, damit es den Abgleich durch verteile-lrmediawiki.sh
# ueberlebt: das Verteilskript spiegelt mit --delete, alles was nicht im
# Paket steckt, waere danach weg.
#
# Ablauf, jeder Schritt mit Rueckfrage:
#   1. pruefen        ./pruefe-alles.sh
#   2. bauen          ./baue-bruecke.sh
#   2b. signieren     nur wenn die Umgebungsvariablen gesetzt sind
#   3. packen         ./packe.sh dist
#   4. committen, taggen, pushen
#   5. GitHub-Release mit beiden Paketen und den Notizen aus SDC-CHANGES.md
#
#   ./release.sh                normaler Lauf
#   ./release.sh --dry-run      nur zeigen, nichts aendern
#   ./release.sh --skip-tests   ohne Pruefung (nicht empfohlen)
#   ./release.sh --skip-sign    ohne Signierung, auch wenn Schluessel da sind
#   ./release.sh --skip-pack    ohne Pakete (dann auch ohne GitHub-Release).
#                               Fuer Windows gedacht, wo zip fehlt und das
#                               Release ohnehin der macOS-Laeufer baut.
#
# SIGNIEREN, macOS (alles optional, fehlt etwas, bleibt das Programm unsigniert):
#   LRMW_MACOS_IDENTITY    Name des Zertifikats, z. B.
#                          "Developer ID Application: Vorname Name (TEAMID)"
#   LRMW_NOTARY_PROFILE    Name eines notarytool-Schluesselbundprofils, angelegt mit
#                          xcrun notarytool store-credentials <name> --apple-id … \
#                              --team-id … --password <app-spezifisches-Kennwort>
#   ODER die drei Einzelwerte:
#   LRMW_NOTARY_APPLE_ID   LRMW_NOTARY_PASSWORD   LRMW_NOTARY_TEAM_ID
#   Ohne Notarisierungsdaten wird nur signiert - das reicht Gatekeeper NICHT.
#
# SIGNIEREN, Windows (einer der drei Wege):
#   LRMW_WIN_SIGN_CMD      eigener Signierbefehl; der Dateiname wird als
#                          Argument angehaengt. Damit laesst sich jedes
#                          Cloud-HSM einbinden, ohne dieses Skript zu aendern.
#   LRMW_WIN_PFX           Pfad zu einer PFX/P12-Datei
#   LRMW_WIN_PFX_PASSWORD  deren Kennwort (wird in eine 0600-Datei geschrieben
#                          und per -readpass uebergeben, nicht auf die
#                          Kommandozeile)
#   LRMW_WIN_TS            Zeitstempeldienst, Vorgabe http://timestamp.digicert.com
#   Benutzt wird osslsigncode, falls vorhanden, sonst signtool. Diese
#   Reihenfolge mit Absicht: auf Unix-Systemen liegt unter dem Namen
#   signtool teils ein voellig anderes Programm.
#
# ACHTUNG ZUR REIHENFOLGE: signiert wird NACH dem Bauen und VOR dem Packen.
# Ein spaeterer Aufruf von baue-bruecke.sh ueberschreibt die Signaturen.
#

set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

DRYRUN=0
SKIPTEST=0
SKIPSIGN=0
SKIPPACK=0
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run|-n) DRYRUN=1 ;;
		--skip-tests) SKIPTEST=1 ;;
		--skip-sign)  SKIPSIGN=1 ;;
		--skip-pack)  SKIPPACK=1 ;;
		--help|-h)    sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unbekannte Option: $1" >&2; exit 2 ;;
	esac
	shift
done

if [ -t 1 ]; then
	C_T=$'\033[36m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
	C_T=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi
schritt() { printf '\n%s== %s%s\n' "$C_T" "$1" "$C_0"; }
info()    { printf '   %s\n' "$1"; }
gut()     { printf '   %s%s%s\n' "$C_G" "$1" "$C_0"; }
warn()    { printf '   %s%s%s\n' "$C_Y" "$1" "$C_0"; }
ende()    { printf '\n%sABBRUCH: %s%s\n' "$C_R" "$1" "$C_0" >&2; exit 1; }
frage() {
	[ "$DRYRUN" = 1 ] && { info "[trocken] Rueckfrage uebersprungen"; return 1; }
	printf '   %s [j/N] ' "$1"
	read -r a
	# j wie ja, y wie yes - je nach Tastaturbelegung tippt sich das eine
	# leichter als das andere.
	case "$a" in j|J|y|Y) return 0 ;; *) return 1 ;; esac
}

LOG=$(mktemp "${TMPDIR:-/tmp}/lrmw2rel.XXXXXX")
NOTIZ=$(mktemp "${TMPDIR:-/tmp}/lrmw2notes.XXXXXX")
PASSDATEI=""
NOTARDIR=""
NOTARZIP=""
aufraeumen() {
	rm -f "$LOG" "$NOTIZ"
	[ -n "$PASSDATEI" ] && rm -f "$PASSDATEI"
	[ -n "$NOTARDIR" ] && rm -rf "$NOTARDIR"
	return 0
}
trap aufraeumen EXIT

# --- 0. Vorpruefungen ------------------------------------------------------
schritt "Vorpruefungen"
[ "$DRYRUN" = 1 ] && warn "TROCKENLAUF - es wird nichts geaendert."
[ -f mediawiki.lrdevplugin/Info.lua ] || ende "Info.lua fehlt - falscher Ordner?"
[ -d .git ] || ende "Hier liegt kein .git. release.sh gehoert in den Klon."
command -v git >/dev/null || ende "git nicht gefunden."
command -v gh  >/dev/null || warn "gh nicht gefunden - das Release entfaellt."

BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "Repo:   $REPO"
info "Branch: $BRANCH"
if [ "$BRANCH" != master ]; then
	warn "Erwartet war master."
	frage "Trotzdem weiter?" || ende "auf Zuruf"
fi

REMOTE=$(git remote get-url origin 2>/dev/null || true)
GHREPO=""
if [ -n "$REMOTE" ]; then
	GHREPO=$(printf '%s' "$REMOTE" \
		| sed -n 's#.*[:/]\([^/:]*\)/\([^/]*\)$#\1/\2#p' | sed 's/\.git$//')
	info "origin: $REMOTE  ->  $GHREPO"
else
	warn "Kein origin - push und Release entfallen."
fi

# --- 0b. Abgleich mit origin ----------------------------------------------
#
# MUSS vor Bauen, Commit und Tag laufen. Faellt die Divergenz erst beim Push
# auf, sind Commit und Tag schon gesetzt und muessen wieder aufgedroeselt
# werden - genau so ist es einmal passiert. Ursache ist die Arbeit an zwei
# Klonen desselben Repos (Mac und Windows).
if [ -n "$REMOTE" ] && [ "$DRYRUN" = 0 ]; then
	schritt "Abgleich mit origin"
	if git fetch origin "$BRANCH" >/dev/null 2>&1; then
		VOR=$(git rev-list --count "origin/$BRANCH..$BRANCH" 2>/dev/null || echo 0)
		ZURUECK=$(git rev-list --count "$BRANCH..origin/$BRANCH" 2>/dev/null || echo 0)
		info "lokal voraus: $VOR    origin voraus: $ZURUECK"
		if [ "$ZURUECK" != "0" ]; then
			warn "Auf origin liegen $ZURUECK Commit(s), die hier fehlen:"
			git log --oneline "$BRANCH..origin/$BRANCH" | head -10 | sed 's/^/     /' || true
			echo
			if [ "$VOR" = "0" ]; then
				warn "Lokal ist nichts Eigenes offen. Vorschlag:"
				warn "    git merge --ff-only origin/$BRANCH"
			else
				warn "Beide Seiten haben etwas. Vorschlag:"
				warn "    git pull --rebase origin $BRANCH"
				warn "ACHTUNG: ein schon gesetzter Tag zeigt nach einem Rebase"
				warn "weiter auf den ALTEN Commit und muss neu gesetzt werden."
			fi
			warn "Niemals mit --force pushen. Wenn es sein muss:"
			warn "    git push --force-with-lease origin $BRANCH"
			ende "Erst den Abgleich klaeren, dann erneut starten."
		fi
		gut "origin ist nicht voraus - der Push wird durchgehen"
	else
		warn "git fetch ist fehlgeschlagen - der Abgleich konnte nicht geprueft werden."
		frage "Trotzdem weiter?" || ende "auf Zuruf"
	fi
fi

# --- 1. Pruefen ------------------------------------------------------------
schritt "Pruefen"
if [ "$SKIPTEST" = 1 ]; then
	warn "auf Zuruf uebersprungen (--skip-tests)"
elif [ ! -x ./pruefe-alles.sh ]; then
	warn "pruefe-alles.sh fehlt oder ist nicht ausfuehrbar."
	frage "Ungeprueft weiter?" || ende "auf Zuruf"
elif [ "$DRYRUN" = 1 ]; then
	info "[trocken] wuerde ./pruefe-alles.sh aufrufen"
else
	# MITLAUFEND anzeigen, nicht stumm in eine Datei. Stufe 8 baut vier
	# Binaerdateien und Stufe 9 startet einen Server - ohne Ausgabe sieht das
	# minutenlang wie ein Haenger aus. tee behaelt die Datei fuer den Fall,
	# dass man hinterher nachlesen will; pipefail sorgt dafuer, dass der
	# Rueckgabewert des Pruefskripts zaehlt und nicht der von tee.
	if LRMW_REPO="$REPO" ./pruefe-alles.sh 2>&1 | tee "$LOG" | sed 's/^/   /'; then
		gut "alle Stufen gruen"
	else
		cp "$LOG" "$REPO/pruefung-fehler.log" 2>/dev/null \
			&& warn "Protokoll: $REPO/pruefung-fehler.log"
		ende "Das Pruefskript ist fehlgeschlagen (siehe oben). Mit --skip-tests umgehen."
	fi
fi

# --- 2. Bauen --------------------------------------------------------------
schritt "Hintergrund-App bauen"
if [ ! -x ./baue-bruecke.sh ]; then
	warn "baue-bruecke.sh fehlt - ohne Binaerdateien kein brauchbares Paket."
	frage "Trotzdem weiter?" || ende "auf Zuruf"
elif [ "$DRYRUN" = 1 ]; then
	info "[trocken] wuerde ./baue-bruecke.sh aufrufen"
else
	./baue-bruecke.sh | sed 's/^/   /'
fi

# --- 2b. Signieren ---------------------------------------------------------
#
# Hier, nicht spaeter: packe.sh legt die Binaerdateien ins ZIP, was danach
# signiert wuerde, kaeme nie beim Nutzer an. Und nicht frueher: ein erneutes
# baue-bruecke.sh wuerde die Signatur ueberschreiben.
#
# Alles ist optional. Fehlt ein Schluessel, wird gewarnt und weitergemacht -
# das Ergebnis ist dann genau der heutige Stand, unsignierte Programme.
BINORDNER="mediawiki.lrdevplugin/bin"
MACBIN="$BINORDNER/sdcbridge-mac"
SIG_MAC=nein
SIG_WIN=nein
NOTAR=nein

signiere_mac() {
	if [ -z "${LRMW_MACOS_IDENTITY:-}" ]; then
		warn "LRMW_MACOS_IDENTITY nicht gesetzt - Mac-Programm bleibt unsigniert."
		return 0
	fi
	if [ ! -f "$MACBIN" ]; then
		warn "$MACBIN fehlt - nichts zu signieren."
		return 0
	fi
	if ! command -v codesign >/dev/null; then
		warn "codesign nicht gefunden - laeuft das hier ueberhaupt auf macOS?"
		return 0
	fi
	# --options runtime ist ZWINGEND: die Notarisierung lehnt ein
	# Kommandozeilenprogramm ohne Hardened Runtime ab.
	if codesign --force --options runtime --timestamp \
	            --sign "$LRMW_MACOS_IDENTITY" "$MACBIN" > "$LOG" 2>&1; then
		gut "signiert: $(basename "$MACBIN")"
		SIG_MAC=ja
	else
		sed 's/^/     /' < "$LOG" || true
		ende "codesign ist fehlgeschlagen."
	fi
	if codesign --verify --strict --verbose=2 "$MACBIN" > "$LOG" 2>&1; then
		gut "Signatur geprueft (codesign --verify --strict)"
	else
		sed 's/^/     /' < "$LOG" || true
		ende "Die eigene Signatur haelt der Pruefung nicht stand."
	fi
	# lipo -info zeigt, ob beide Architekturen die Signatur tragen; codesign
	# signiert beide Scheiben in einem Zug, das ist nur die Gegenprobe.
	if command -v lipo >/dev/null; then
		LIPOZEILE=$(lipo -info "$MACBIN" 2>&1 || true)
		info "$(printf '%s' "$LIPOZEILE" | tr '\n' ' ')"
	fi
}

notarisiere_mac() {
	[ "$SIG_MAC" = ja ] || return 0
	if ! command -v xcrun >/dev/null; then
		warn "xcrun nicht gefunden - keine Notarisierung."
		return 0
	fi
	if [ -z "${LRMW_NOTARY_PROFILE:-}" ] \
	   && { [ -z "${LRMW_NOTARY_APPLE_ID:-}" ] || [ -z "${LRMW_NOTARY_PASSWORD:-}" ] \
	     || [ -z "${LRMW_NOTARY_TEAM_ID:-}" ]; }; then
		warn "Keine Notarisierungsdaten - das Programm ist signiert, aber NICHT"
		warn "notarisiert. Gatekeeper blockt den ersten Start weiterhin."
		return 0
	fi
	# Notarisiert wird ein ZIP mit der Binaerdatei. An eine einzelne
	# Binaerdatei laesst sich KEIN Ticket heften (stapler kann nur Bundles,
	# DMG und PKG) - Gatekeeper fragt beim ersten Start online nach.
	NOTARDIR=$(mktemp -d "${TMPDIR:-/tmp}/lrmw2notar.XXXXXX")
	NOTARZIP="$NOTARDIR/sdcbridge-mac.zip"
	if command -v ditto >/dev/null; then
		ditto -c -k "$MACBIN" "$NOTARZIP"
	else
		zip -j -q "$NOTARZIP" "$MACBIN"
	fi
	info "Notarisierung laeuft - das dauert ueblicherweise einige Minuten."
	if [ -n "${LRMW_NOTARY_PROFILE:-}" ]; then
		xcrun notarytool submit "$NOTARZIP" \
			--keychain-profile "$LRMW_NOTARY_PROFILE" --wait > "$LOG" 2>&1 \
			&& NOTAR=ja || NOTAR=nein
	else
		xcrun notarytool submit "$NOTARZIP" \
			--apple-id "$LRMW_NOTARY_APPLE_ID" \
			--password "$LRMW_NOTARY_PASSWORD" \
			--team-id  "$LRMW_NOTARY_TEAM_ID" --wait > "$LOG" 2>&1 \
			&& NOTAR=ja || NOTAR=nein
	fi
	# notarytool meldet auch bei Status "Invalid" den Rueckgabewert 0, wenn
	# die Einreichung als solche geklappt hat - deshalb zusaetzlich auf das
	# Wort Accepted sehen.
	if [ "$NOTAR" = ja ] && grep -qi 'status: *Accepted' "$LOG"; then
		gut "notarisiert (Ticket liegt bei Apple, kein Heften moeglich)"
	else
		NOTAR=nein
		tail -20 "$LOG" | sed 's/^/     /' || true
		warn "Die Notarisierung ist nicht durchgegangen."
		warn "Protokoll holen: xcrun notarytool log <id> --keychain-profile <profil>"
		frage "Trotzdem weiter (das Paket ist dann nicht notarisiert)?" \
			|| ende "auf Zuruf"
	fi
	rm -rf "$NOTARDIR"; NOTARZIP=""; NOTARDIR=""
	# Gegenprobe. Bei einem reinen Kommandozeilenprogramm ist die Aussage von
	# spctl erfahrungsgemaess nicht immer eindeutig, deshalb nur zur Ansicht.
	if command -v spctl >/dev/null; then
		SPCTL=$(spctl -a -vv -t exec "$MACBIN" 2>&1 || true)
		info "spctl: $(printf '%s' "$SPCTL" | tr '\n' ' ')"
	fi
}

signiere_win() {
	TS="${LRMW_WIN_TS:-http://timestamp.digicert.com}"
	GEFUNDEN=0
	for EXE in "$BINORDNER"/*.exe; do
		[ -f "$EXE" ] || continue
		GEFUNDEN=1
		if [ -n "${LRMW_WIN_SIGN_CMD:-}" ]; then
			# Eigener Befehl. Der Dateiname geht als $1 hinein, nicht in die
			# Zeichenkette - sonst waere ein Leerzeichen im Pfad eine Luecke.
			if sh -c "$LRMW_WIN_SIGN_CMD \"\$1\"" _ "$EXE" > "$LOG" 2>&1; then
				gut "signiert: $(basename "$EXE") (eigener Befehl)"
				SIG_WIN=ja
			else
				sed 's/^/     /' < "$LOG" || true
				ende "LRMW_WIN_SIGN_CMD ist fehlgeschlagen."
			fi
			continue
		fi
		if [ -z "${LRMW_WIN_PFX:-}" ]; then
			warn "Weder LRMW_WIN_SIGN_CMD noch LRMW_WIN_PFX gesetzt -"
			warn "$(basename "$EXE") bleibt unsigniert."
			return 0
		fi
		[ -f "$LRMW_WIN_PFX" ] || ende "LRMW_WIN_PFX zeigt auf nichts: $LRMW_WIN_PFX"
		if command -v osslsigncode >/dev/null; then
			# Kennwort ueber eine Datei, nicht ueber die Kommandozeile: dort
			# stuende es fuer jeden sichtbar in der Prozessliste.
			if [ -n "${LRMW_WIN_PFX_PASSWORD:-}" ]; then
				PASSDATEI=$(mktemp "${TMPDIR:-/tmp}/lrmw2pass.XXXXXX")
				chmod 600 "$PASSDATEI"
				printf '%s' "$LRMW_WIN_PFX_PASSWORD" > "$PASSDATEI"
			fi
			ZIEL="$EXE.signiert"
			if [ -n "$PASSDATEI" ]; then
				osslsigncode sign -pkcs12 "$LRMW_WIN_PFX" -readpass "$PASSDATEI" \
					-h sha256 -ts "$TS" \
					-n "LrMediaWiki2 SDC-Bruecke" \
					-i "https://github.com/krichel89/LrMediaWiki2" \
					-in "$EXE" -out "$ZIEL" > "$LOG" 2>&1 || ZIEL=""
			else
				osslsigncode sign -pkcs12 "$LRMW_WIN_PFX" \
					-h sha256 -ts "$TS" \
					-n "LrMediaWiki2 SDC-Bruecke" \
					-i "https://github.com/krichel89/LrMediaWiki2" \
					-in "$EXE" -out "$ZIEL" > "$LOG" 2>&1 || ZIEL=""
			fi
			if [ -n "$ZIEL" ] && [ -s "$ZIEL" ]; then
				mv "$ZIEL" "$EXE"
				gut "signiert: $(basename "$EXE") (osslsigncode)"
				SIG_WIN=ja
				if osslsigncode verify -in "$EXE" > "$LOG" 2>&1; then
					gut "Signatur geprueft (osslsigncode verify)"
				else
					warn "osslsigncode verify meldet etwas - bitte ansehen:"
					tail -10 "$LOG" | sed 's/^/     /' || true
				fi
			else
				sed 's/^/     /' < "$LOG" || true
				rm -f "$EXE.signiert"
				ende "osslsigncode ist fehlgeschlagen."
			fi
			if [ -n "$PASSDATEI" ]; then rm -f "$PASSDATEI"; PASSDATEI=""; fi
		elif command -v signtool >/dev/null; then
			if signtool sign /fd sha256 /tr "$TS" /td sha256 \
			            /f "$LRMW_WIN_PFX" /p "${LRMW_WIN_PFX_PASSWORD:-}" \
			            "$EXE" > "$LOG" 2>&1; then
				gut "signiert: $(basename "$EXE") (signtool)"
				SIG_WIN=ja
			else
				sed 's/^/     /' < "$LOG" || true
				ende "signtool ist fehlgeschlagen."
			fi
		else
			warn "Weder osslsigncode noch signtool gefunden -"
			warn "$(basename "$EXE") bleibt unsigniert."
			warn "Auf dem Mac:  brew install osslsigncode"
			return 0
		fi
	done
	[ "$GEFUNDEN" = 0 ] && warn "Keine .exe in $BINORDNER gefunden."
	return 0
}

schritt "Signieren"
if [ "$SKIPSIGN" = 1 ]; then
	warn "auf Zuruf uebersprungen (--skip-sign)"
elif [ "$DRYRUN" = 1 ]; then
	info "[trocken] wuerde signieren, sofern die Schluessel gesetzt sind"
else
	signiere_mac
	notarisiere_mac
	signiere_win
	if [ "$SIG_MAC" = nein ] && [ "$SIG_WIN" = nein ]; then
		warn "Nichts signiert. Das ist der bisherige Zustand, kein Fehler -"
		warn "die Anleitung muss dann weiter den xattr-Schritt nennen."
	fi
fi

# --- 3. Version ------------------------------------------------------------
schritt "Version"
IL=mediawiki.lrdevplugin/Info.lua
MA=$(sed -n 's/.*major *= *\([0-9]*\).*/\1/p' "$IL" | head -1)
MI=$(sed -n 's/.*minor *= *\([0-9]*\).*/\1/p' "$IL" | head -1)
RE=$(sed -n 's/.*revision *= *\([0-9]*\).*/\1/p' "$IL" | head -1)
[ -n "$MA" ] && [ -n "$MI" ] && [ -n "$RE" ] || ende "Version nicht lesbar."
VERSION="$MA.$MI.$RE"
TAG="v$VERSION"
gut "$VERSION  (Tag $TAG)"

TAGDA=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
	warn "Tag $TAG existiert schon."
	frage "Weiter ohne neuen Tag und ohne Release?" || ende "auf Zuruf"
	TAGDA=1
fi

# --- 4. Packen -------------------------------------------------------------
schritt "Pakete bauen"
PAKETE=1
if [ "$SKIPPACK" = 1 ]; then
	PAKETE=0
	warn "auf Zuruf uebersprungen (--skip-pack)"
	warn "Ohne Pakete entfaellt auch das GitHub-Release - das baut dann der"
	warn "Workflow release.yml, sobald der Tag gepusht ist."
elif [ "$DRYRUN" = 1 ]; then
	info "[trocken] wuerde ./packe.sh dist aufrufen"
else
	./packe.sh dist | sed 's/^/   /'
fi
NUTZER="dist/LrMediaWiki2-$VERSION.zip"
VOLL="dist/LrMediaWiki2-complete-$VERSION.zip"

# --- 5. Git ---------------------------------------------------------------
schritt "git"
git add -A
KURZ=$(git status --short || true)
if [ -z "$KURZ" ]; then
	warn "Keine Aenderungen - der Stand ist schon committet."
else
	printf '%s\n' "$KURZ" | head -40 | sed 's/^/     /' || true
fi

VERFOLGT=$(git ls-files 'mediawiki.lrdevplugin/bin/' || true)
if [ -n "$VERFOLGT" ]; then
	warn "Die Binaerdateien sind versioniert - das widerspricht der Konvention:"
	printf '%s\n' "$VERFOLGT" | sed 's/^/     /' || true
	warn "Herausnehmen: git rm --cached -r mediawiki.lrdevplugin/bin/"
	frage "Trotzdem committen?" || ende "auf Zuruf"
else
	gut "bin/ ist nicht versioniert - passt"
fi

if [ -n "$KURZ" ] && [ "$DRYRUN" = 0 ]; then
	if frage "Committen als \"LrMediaWiki2 $VERSION\"?"; then
		git commit -m "LrMediaWiki2 $VERSION"
		gut "committet"
	else
		warn "nicht committet - Tag und Release entfallen"
		TAGDA=1
	fi
fi

if [ "$TAGDA" = 0 ] && [ "$DRYRUN" = 0 ]; then
	if frage "Tag $TAG setzen?"; then
		git tag -a "$TAG" -m "LrMediaWiki2 $VERSION"
		gut "Tag gesetzt"
	else
		TAGDA=1
	fi
fi

if [ -n "$REMOTE" ] && [ "$DRYRUN" = 0 ]; then
	if frage "$BRANCH und Tags nach origin pushen?"; then
		# Nicht stumm unter set -e sterben: bei einer Ablehnung soll der
		# Zustand dastehen, nicht nur ein Abbruch.
		if ! git push origin "$BRANCH"; then
			warn "Der Push wurde abgelehnt. Commit und Tag sind lokal gesetzt."
			warn "Lage ansehen:  git log --oneline --graph --all | head -20"
			ende "Push abgelehnt."
		fi
		git push origin --tags || warn "Die Tags gingen nicht durch."
		gut "gepusht"
		info "Ist der Workflow release.yml eingerichtet, baut GitHub jetzt selbst."
		if [ "$SIG_MAC" = ja ] || [ "$SIG_WIN" = ja ]; then
			warn "ACHTUNG: der Workflow baut und packt ebenfalls. Sind dort die"
			warn "Geheimnisse NICHT gesetzt, kann er die hier signierten Pakete"
			warn "durch unsignierte ersetzen."
		fi
	fi
fi

# --- 6. Release ----------------------------------------------------------
if command -v gh >/dev/null && [ -n "$GHREPO" ] && [ "$TAGDA" = 0 ] \
   && [ "$DRYRUN" = 0 ] && [ "$PAKETE" = 1 ]; then
	schritt "GitHub-Release"
	# Den Abschnitt "## Version X.Y.Z" aus SDC-CHANGES.md schneiden, bis zur
	# naechsten Ueberschrift derselben Ebene.
	if [ -f SDC-CHANGES.md ]; then
		awk -v v="## Version $VERSION" '
			index($0, v) == 1 { drin = 1; print; next }
			drin && /^## / { exit }
			drin { print }
		' SDC-CHANGES.md > "$NOTIZ"
	fi
	if [ ! -s "$NOTIZ" ]; then
		warn "Kein Abschnitt \"## Version $VERSION\" in SDC-CHANGES.md."
		printf 'LrMediaWiki2 %s\n' "$VERSION" > "$NOTIZ"
	else
		info "Notizen: $(wc -c < "$NOTIZ" | tr -d ' ') Zeichen"
	fi

	if [ ! -f "$NUTZER" ] || [ ! -f "$VOLL" ]; then
		ende "Die Pakete fehlen in dist/ - lief ./packe.sh durch?"
	fi

	info "Release $TAG in $GHREPO"
	# Derselbe Tag-Push hat oben schon den Workflow gestartet, der ebenfalls
	# ein Release anlegt. Wer zuerst fertig ist, ist Zufall - deshalb hier
	# genauso anlegen ODER ergaenzen statt blind zu erzeugen.
	if frage "Release jetzt anlegen?"; then
		if gh release view "$TAG" --repo "$GHREPO" >/dev/null 2>&1; then
			info "Release $TAG gibt es schon (vermutlich vom Workflow)."
			if frage "Die hier gebauten Pakete trotzdem anhaengen?"; then
				gh release upload "$TAG" --repo "$GHREPO" --clobber \
					"$NUTZER#LrMediaWiki2-$VERSION.zip" \
					"$VOLL#LrMediaWiki2-complete-$VERSION.zip mit Quelltext"
				gut "Pakete ersetzt"
			else
				info "Unveraendert gelassen."
			fi
		else
			gh release create "$TAG" --repo "$GHREPO" \
				--title "LrMediaWiki2 $VERSION" --notes-file "$NOTIZ" \
				"$NUTZER#LrMediaWiki2-$VERSION.zip" \
				"$VOLL#LrMediaWiki2-complete-$VERSION.zip mit Quelltext"
			gut "Release angelegt"
		fi
		# Ein Entwurf waere unsichtbar - siehe 2.0.50.
		if [ "$(gh release view "$TAG" --repo "$GHREPO" --json isDraft -q .isDraft 2>/dev/null)" = "true" ]; then
			warn "Release lag als Entwurf vor - wird veroeffentlicht."
			gh release edit "$TAG" --repo "$GHREPO" --draft=false
		fi
	fi
elif [ "$DRYRUN" = 0 ]; then
	schritt "GitHub-Release"
	warn "uebersprungen"
fi

# Die Pakete zusaetzlich in den Download-Ordner legen - von dort holt sie
# verteile-lrmediawiki.sh auf dem anderen Rechner.
DOWNLOADS="${LRMW_DOWNLOADS:-$HOME/Downloads}"
if [ "$DRYRUN" = 0 ] && [ "$PAKETE" = 1 ] && [ -d "$DOWNLOADS" ]; then
	for f in "$NUTZER" "$VOLL"; do
		[ -f "$f" ] && cp "$f" "$DOWNLOADS/" 2>/dev/null \
			&& info "Kopie: $DOWNLOADS/$(basename "$f")"
	done
fi

schritt "Fertig"
gut "LrMediaWiki2 $VERSION"
info "Signatur Mac: $SIG_MAC   notarisiert: $NOTAR   Signatur Windows: $SIG_WIN"
if [ "$PAKETE" = 1 ] && [ -f "$NUTZER" ]; then
	info "Pakete liegen in $REPO/dist"
elif [ "$SKIPPACK" = 1 ]; then
	info "Keine Pakete gebaut - der Workflow release.yml macht das."
fi
exit 0

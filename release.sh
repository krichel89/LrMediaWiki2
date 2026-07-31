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
#   3. packen         ./packe.sh dist
#   4. committen, taggen, pushen
#   5. GitHub-Release mit beiden Paketen und den Notizen aus SDC-CHANGES.md
#
#   ./release.sh                normaler Lauf
#   ./release.sh --dry-run      nur zeigen, nichts aendern
#   ./release.sh --skip-tests   ohne Pruefung (nicht empfohlen)
#

set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

DRYRUN=0
SKIPTEST=0
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run|-n) DRYRUN=1 ;;
		--skip-tests) SKIPTEST=1 ;;
		--help|-h)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
aufraeumen() { rm -f "$LOG" "$NOTIZ"; return 0; }
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
	if ./pruefe-alles.sh > "$LOG" 2>&1; then
		gut "alle Stufen gruen"
	else
		tail -25 "$LOG" | sed 's/^/     /' || true
		ende "Das Pruefskript ist fehlgeschlagen. Mit --skip-tests umgehen."
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
if [ "$DRYRUN" = 1 ]; then
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
	fi
fi

# --- 6. Release ----------------------------------------------------------
if command -v gh >/dev/null && [ -n "$GHREPO" ] && [ "$TAGDA" = 0 ] \
   && [ "$DRYRUN" = 0 ]; then
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
	if frage "Release jetzt anlegen?"; then
		gh release create "$TAG" --repo "$GHREPO" \
			--title "LrMediaWiki2 $VERSION" --notes-file "$NOTIZ" \
			"$NUTZER#LrMediaWiki2-$VERSION.zip" \
			"$VOLL#LrMediaWiki2-complete-$VERSION.zip mit Quelltext"
		gut "Release angelegt"
	fi
elif [ "$DRYRUN" = 0 ]; then
	schritt "GitHub-Release"
	warn "uebersprungen"
fi

# Die Pakete zusaetzlich in den Download-Ordner legen - von dort holt sie
# verteile-lrmediawiki.sh auf dem anderen Rechner.
DOWNLOADS="${LRMW_DOWNLOADS:-$HOME/Downloads}"
if [ "$DRYRUN" = 0 ] && [ -d "$DOWNLOADS" ]; then
	for f in "$NUTZER" "$VOLL"; do
		[ -f "$f" ] && cp "$f" "$DOWNLOADS/" 2>/dev/null \
			&& info "Kopie: $DOWNLOADS/$(basename "$f")"
	done
fi

schritt "Fertig"
gut "LrMediaWiki2 $VERSION"
[ -f "$NUTZER" ] && info "Pakete liegen in $REPO/dist"
exit 0

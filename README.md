# LrMediaWiki2

**MediaWiki-Plugin für Adobe Lightroom Classic** mit Unterstützung für **Wikimedia Commons Structured Data (SDC)** und mehrsprachige Beschreibungen.

LrMediaWiki2 ist ein Fork der ursprünglichen [LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)-Codebasis, ausgerichtet auf Commons-Workflows mit Wikidata-Integration.

---

## Hauptmerkmale

### Structured Data (SDC) über das Wikitext-Feld

SDC-Aussagen werden als einfache `key=value`-Zeilen im Feld **Wikitext** (Feld-ID `description_all`) geschrieben:

- `caption_xx` – mehrsprachige Bildunterschriften (P2096), beliebige ISO-Codes
- `depicts` – dargestellte Objekte/Personen (P180), eine Zeile je QID
- `created_during` – Ereignis (P10408)
- `creator` – Urheber (P170)
- `copyright` – Urheberrechtsstatus (P6216)
- `license` – Lizenz (P275)

Hinter jeder QID kann ein Kommentar zur Lesbarkeit stehen; er wird beim Upload abgeschnitten:

```
depicts=Q640 # Harald Krichel
depicts=Q42 # Douglas Adams
```

Alle Aussagen und Captions werden in einem einzigen `wbeditentity`-Aufruf publiziert, mit einer eigenen P180-Aussage je QID.

### SDC-Editor im Browser

Bibliothek → Zusatzmoduloptionen → **Edit Structured Data in browser**. Die strukturierten Daten des aktiven Fotos werden in einer Seite im Standardbrowser geöffnet:

- Live-Suche auf Wikidata, Treffer erscheinen von selbst und lassen sich mit den Pfeiltasten durchgehen und per Klick auf den Text übernehmen
- Übernommene Einträge stehen als Etiketten da (Nummer, Klartext, ✕ zum Entfernen)
- beliebig viele Sprachzeilen für Bildunterschriften, Sprachcodes frei überschreibbar
- Kategorien als Etiketten, mit Vorschlägen aus den P373-Angaben der eingetragenen Nummern
- rechts läuft eine Vorschau des Wikitexts mit, genau so, wie er gespeichert wird

Lightroom ist währenddessen **nicht blockiert** – die Bearbeitung darf beliebig lange dauern. Ein Klick auf „Speichern und zu Lightroom“ lädt eine kleine Datei herunter; Lightroom holt sie sich automatisch aus dem Downloads-Ordner und bestätigt die Übernahme.

Voraussetzung: Der Browser muss Dateien ohne Rückfrage in den Standard-Downloads-Ordner laden. Fragt er nach dem Speicherort, funktioniert es ebenfalls – dann muss dieser Ordner gewählt werden.

### Hintergrund-App (SDC-Brücke)

Der Editor im Browser kann auch dauerhaft offen bleiben und dem Fotowechsel in
Lightroom folgen. Dazu läuft eine kleine Hintergrund-App, die die Editorseite
unter `http://127.0.0.1:PORT/` ausliefert. Weil die Seite damit eine echte
Herkunft hat, kann sie ohne Umwege mit Lightroom sprechen; der frühere Weg über
eine `file://`-Seite war daran gescheitert.

Ein- und ausgeschaltet wird die Brücke über Bibliothek oder Datei,
Zusatzmoduloptionen, Eintrag "Hintergrund-App (SDC-Brücke)". Ist sie an, wird
die Seite beim Fotowechsel ohne Neuladen aktualisiert, und Speichern schreibt
direkt in den Katalog. Ist sie aus, bleibt alles beim Dateiweg über den
Download-Ordner.

Lightroom selbst lauscht dabei auf keinem Port, sondern ruft nur ausgehend an
(einmal pro Sekunde). Die App bindet ausschließlich an 127.0.0.1, verlangt zu
jeder Anfrage ein Sitzungstoken, prüft den Host-Kopf gegen DNS-Rebinding und
beendet sich selbst, wenn drei Minuten lang kein Lebenszeichen aus Lightroom
kommt.

Der Quelltext der App ist `bridge/sdcbridge.go` (eine Datei, Go, nur
Standardbibliothek). Die fertigen Programme fuer macOS arm64, macOS x86_64 und
Windows x86_64 liegen im Ordner `mediawiki.lrdevplugin/bin` und sind Teil des
Release-ZIPs, aber **absichtlich nicht versioniert**. Wer aus dem Quelltext
arbeitet, erzeugt sie mit

```
./baue-bruecke.sh
```

Dafuer wird nur die Go-Werkzeugkette gebraucht; heruntergeladen wird nichts.
Fehlt der Ordner `bin`, meldet das Zusatzmodul das verstaendlich und der
Dateiweg funktioniert unveraendert weiter.

Die Programme sind **nicht signiert**: unter macOS muss die Freigabe beim
ersten Start einmal erteilt werden, unter Windows kann SmartScreen anspringen.

### Suche auf Wikidata

Der Editor sucht zuerst über die Präfixsuche. Liefert die zu wenig, wird zusätzlich die Volltextsuche befragt – dadurch werden auch umgestellte Wortfolgen und Ordnungszahlen gefunden, etwa „78th Cannes Film Festival“.

### Mehrsprachige Wikitext-Beschreibungen

```wikitext
{{en|1=Description in English with [[links]]}}
{{de|1=Beschreibung auf Deutsch mit [[Links]]}}
```

### Templates und Kategorien

Kategorien stammen aus dem Kategorien-Feld (semikolongetrennt), aus `#Hashtag`-Stichwörtern und aus manuell im Wikitext geschriebenen `[[Category:...]]`-Zeilen. Sie werden dedupliziert und ans Ende der Dateibeschreibung gestellt.

### Metadaten-Sets

Spezialisierte Sets für verschiedene Inhaltstypen: Wikitext, All Fields, Information, Information (DE), Artwork, Object Photo.

### Weitere Werkzeuge

- **Search and Replace Metadata** – Massenbearbeitung von Metadaten
- **Search and Replace Filename** – Dateinamen-Anpassung
- **Generate from Persons** – Beschreibungen aus Gesichtsregionen
- **Set Title** – Titelformatierung
- **Description fields ↔ Wikitext** – Konvertierung zwischen Einzelfeldern und Wikitext-Blöcken

---

## Installation

### Anforderungen

- **Adobe Lightroom Classic** (entwickelt und getestet gegen die aktuelle Version; `LrSdkVersion = 6.0`)
- **Ein Benutzerkonto auf Wikimedia Commons** (oder einem anderen MediaWiki mit aktivierter Structured-Data-Erweiterung). Für den Upload werden lediglich die normalen Upload-Rechte eines angemeldeten Benutzers benötigt – **keine Administratorrechte**.
- Zur Anmeldung gibt es zwei Wege: die **Anmeldung über den Browser** (OAuth 2.0, siehe unten) oder Benutzername und Passwort, wofür ein [BotPassword](https://commons.wikimedia.org/wiki/Special:BotPasswords) statt des Hauptpassworts empfohlen wird.
- **Grundkenntnisse zu Wikidata-QIDs**, wenn SDC-Aussagen gesetzt werden sollen (die eingebaute Suche nimmt einem das Nachschlagen weitgehend ab)

### Schritt für Schritt

1. **Download** der neuesten Version von [GitHub Releases](https://github.com/krichel89/LrMediaWiki2/releases) und entpacken.

2. **Plugin-Ordner** (`mediawiki.lrdevplugin`) in das Lightroom-Plugin-Verzeichnis kopieren:

   **Windows:**
   ```
   C:\Users\[Benutzername]\AppData\Roaming\Adobe\Lightroom\Plugins\
   ```

   **macOS:**
   ```
   ~/Library/Application Support/Adobe/Lightroom/Plugins/
   ```

   Alternativ kann der Ordner an beliebiger Stelle liegen und im Zusatzmodul-Manager per „Hinzufügen" eingebunden werden.

3. **Lightroom Classic neu starten** (nötig, damit neue Metadatenfelder und Metadaten-Sets registriert werden).

4. **Anmelden:** Im Export-Dialog im Abschnitt „LrMediaWiki Login Information“ entweder auf **„Mit Browser anmelden“** klicken – dann wird die Anmeldung einmalig im Browser bestätigt und Benutzername und Passwort werden nicht mehr gebraucht – oder Benutzername und BotPassword eintragen.

   Nach dem Bestätigen zeigt der Browser eine Seite, auf der mehrfach „ok“ steht. Das ist normal und bedeutet, dass es geklappt hat; einfach zurück zu Lightroom wechseln.

   Die Zugangsdaten liegen im Schlüsselbund des Betriebssystems, nie in den Voreinstellungen oder in Export-Vorgaben.

5. **Metadaten-Set wählen:** Im Metadaten-Bedienfeld oben das Set „LrMediaWiki – Wikitext" (oder „All Fields") auswählen. Plugin-Felder erscheinen in der Standardansicht nicht automatisch; das ist normales Lightroom-Verhalten.

### Hinweis zum Katalog-Schema

Das Plugin registriert eigene Metadatenfelder mit einer `schemaVersion`. Lightroom hebt den Katalog beim ersten Start automatisch auf diese Version an. Ein **Downgrade ist nicht möglich**: Wird nach einer neueren Plugin-Version wieder eine ältere installiert, meldet Lightroom „Could not upgrade your catalog for plug-in metadata". In dem Fall die neuere Plugin-Version installieren – die Katalogdaten bleiben erhalten.

---

## Verwendung

### Basis-Workflow

1. Fotos in Lightroom auswählen.
2. Metadaten eingeben – entweder direkt im Metadaten-Bedienfeld oder komfortabler über den **SDC-Editor** (Bibliothek → Zusatzmoduloptionen).
3. Export → MediaWiki: Zielwiki, Lizenz und Batch-Vorgaben setzen, Upload starten.

### Format des Wikitext-Felds (Beispiel)

```
caption_en=Isaach de Bankolé at the 2026 Cannes Film Festival
caption_de=Isaach de Bankolé bei den Internationalen Filmfestspielen von Cannes 2026
caption_fr=Isaach de Bankolé au Festival de Cannes 2026
depicts=Q1342843 # Isaach de Bankolé
created_during=Q124692383 # Cannes 2026
creator=Q640 # Harald Krichel
copyright=Q73566113 # copyrighted
license=Q18199165 # CC BY-SA 4.0
{{en|1=[[:en:Isaach de Bankolé|Isaach de Bankolé]] at a photo call at the [[:en:2026 Cannes Film Festival|2026 Cannes Film Festival]]}}
{{de|1=[[:de:Isaach de Bankolé|Isaach de Bankolé]] bei einem Photo-Call bei den [[:de:Internationale Filmfestspiele von Cannes 2026|Internationalen Filmfestspielen von Cannes 2026]]}}
{{WikiPortraits Cannes Film Festival 2026}}
[[Category:Isaach de Bankolé]]
[[Category:2026 Cannes Film Festival]]
```

Das Plugin trennt beim Export automatisch:

- `key=value`-Zeilen → SDC via `wbeditentity`
- `{{lang|1=...}}`-Blöcke, Templates und Kategorien → Wikitext der Dateibeschreibungsseite

---

## SDC-Schlüssel

| Schlüssel | Property | Beispiel | Bemerkung |
|-----------|----------|----------|-----------|
| `caption_xx` | P2096 | `caption_en=...` | Bildunterschrift, beliebiger ISO-Code |
| `depicts` | P180 | `depicts=Q640` | Eine Zeile je QID; je QID eine eigene Aussage. Eine ältere Zeile mit Semikolons wird weiterhin gelesen |
| `created_during` | P10408 | `Q124692383` | Ereignis, eine QID |
| `creator` | P170 | `Q640` | Urheber |
| `copyright` | P6216 | `Q73566113` | Urheberrechtsstatus |
| `license` | P275 | `Q18199165` | Lizenz |

Kommentare hinter einer QID (`Q640 # Harald Krichel`) sind erlaubt und werden vor dem Upload entfernt.

Weitere Hintergründe: [Commons:Structured data](https://commons.wikimedia.org/wiki/Commons:Structured_data)

---

## Code-Architektur

```
mediawiki.lrdevplugin/
├── Info.lua                           # Plugin-Metadaten, Version, Menüeinträge
├── MediaWikiExportServiceProvider.lua # Export-Dialog und Export-Ablauf
├── MediaWikiInterface.lua             # Aufbau der Dateibeschreibung, SDC-Extraktion
├── MediaWikiApi.lua                   # API-Aufrufe (Login, Upload, wbeditentity)
├── MediaWikiOAuth.lua                 # Anmeldung über den Browser (OAuth 2.0, PKCE)
├── MediaWikiMetadataProvider.lua      # Definition der Metadatenfelder
├── MediaWikiMetadataSet*.lua          # Metadaten-Sets für das Bedienfeld
├── MediaWikiUtils.lua                 # Hilfsfunktionen
├── ToolEditSdcWeb.lua                 # SDC-Editor im Browser (Dateiweg)
├── SdcEditorTemplate.lua              # die Editorseite (maschinell erzeugt)
├── MediaWikiSdcData.lua               # gemeinsame Datenlogik beider Wege
├── MediaWikiSdcBridge.lua             # Lightroom-Seite der Hintergrund-App
├── ToolSdcBridge.lua                  # Hintergrund-App ein- und ausschalten
├── bin/                               # die gebauten Programme (nicht versioniert)
│   ├── sdcbridge-mac-arm64
│   ├── sdcbridge-mac-x86_64
│   └── sdcbridge-win-amd64.exe
├── ToolConvertDescriptionAll.lua      # Konverter Einzelfelder ↔ Wikitext
└── Tool*.lua                          # weitere Batch-Werkzeuge
```

Außerhalb des Zusatzmodul-Ordners:

```
baue-bruecke.sh         # baut die Hintergrund-App für alle Zielplattformen
bridge/sdcbridge.go     # Quelltext der Hintergrund-App (Go, keine Abhängigkeiten)
editor/sdc-editor.html  # Quelle der Editorseite
tools/gen-template.lua  # erzeugt SdcEditorTemplate.lua aus der HTML-Datei
tools/check-template.lua# prüft beide auf Byte-Gleichheit
```

---

## Weiterführende Dokumentation

- [SDC-CHANGES.md](./SDC-CHANGES.md) – vollständiger Änderungsbericht (Versionshistorie, Sicherheits-Fixes)
- [Installation.md](./Installation.md) – ausführliche Setup-Anleitung
- [SDC-Workflow.md](./SDC-Workflow.md) – Workflows mit SDC-Integration
- [Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki) – Dokumentation des Ursprungs-Plugins

---

## Issues und Support

- **GitHub Issues:** [Fehler melden](https://github.com/krichel89/LrMediaWiki2/issues)
- **Commons:** [Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)

---

## Lizenz

LrMediaWiki2 steht unter der **MIT License** – siehe [LICENSE.txt](LICENSE.txt)

**Basierend auf:**
- Original: [robinkrahl/LrMediaWiki](https://github.com/robinkrahl/LrMediaWiki)
- Fork: [Hasenlaeufer/LrMediaWiki](https://github.com/Hasenlaeufer/LrMediaWiki)

---

## Credits

**LrMediaWiki2:** Harald Krichel ([@Seewolf](https://commons.wikimedia.org/wiki/User:Seewolf))
**Ursprüngliches Plugin:** Robin Krahl und Mitwirkende

Vollständige Credits: [CREDITS.txt](CREDITS.txt)

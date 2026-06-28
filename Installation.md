# Installation Guide – LrMediaWiki2 v2.0.0

Vollständige Schritt-für-Schritt-Anleitung zur Installation und Konfiguration von LrMediaWiki2 in Adobe Lightroom Classic.

---

## 📋 Anforderungen

### Software
- **Adobe Lightroom Classic** 4.0 oder höher
  - Windows: 32-bit oder 64-bit
  - macOS: 10.7+
- **Administrator-Rechte** für Plugin-Installation

### Online-Zugang
- **Wikimedia Commons Benutzerkonto** (Uploads)
- **Bot-Passwort** (empfohlen) oder reguläres Wikimedia-Passwort

### Wissen
- Grundkenntnisse in **Wikitext** (Templates, Kategorien)
- Grundkenntnisse in **Wikidata Q-IDs** (für SDC-Felder)
- (Optional) Lightroom Metadata & Export Grundlagen

---

## 🔧 Installation

### Step 1: Download

1. Gehe zu [GitHub Releases](https://github.com/krichel89/LrMediaWiki2/releases)
2. Download die neueste Release (v2.0.0 oder höher)
3. Entpacke `LrMediaWiki2-v2.0.0.zip` → `mediawiki.lrdevplugin`

### Step 2: Plugin-Dateien kopieren

**Windows:**
```powershell
# Öffne den Plugin-Ordner:
C:\Users\[DeinUsername]\AppData\Roaming\Adobe\Lightroom\Plugins\
```

**macOS:**
```bash
# Terminal:
~/Library/Application\ Support/Adobe/Lightroom/Plugins/
```

Kopiere die **`mediawiki.lrdevplugin`**-Datei in diesen Ordner.

### Step 3: Lightroom neu starten

Schließe Lightroom komplett und starte es neu.

### Step 4: Plugin aktivieren

1. **Edit → Preferences** (Windows) / **Lightroom → Preferences** (macOS)
2. Gehe zu **Plugins**
3. Suche **"LrMediaWiki"** in der Liste
4. Klick auf **"Show Plugin Manager"** → **"Enable"**
5. Bestätige

**Nach dem Enable sollte das Plugin aktiv sein.** Falls nicht: Lightroom erneut neustarten.

---

## ⚙️ Konfiguration

### Wikimedia Commons API-Zugangsdaten

1. **Lightroom öffnen** → **File → Plugin Manager**
2. Suche **"LrMediaWiki"** und klick auf **"Edit"** oder **"Configure"**
3. Trage ein:
   - **MediaWiki URL:** `https://commons.wikimedia.org/w/api.php`
   - **Username:** Dein Wikimedia-Benutzername
   - **Password:** Dein Wikimedia-Passwort ODER Bot-Token

#### Bot-Passwort (empfohlen)

Statt deinem echten Passwort kannst du ein **Bot-Passwort** verwenden:

1. Gehe zu [Special:BotPasswords](https://commons.wikimedia.org/wiki/Special:BotPasswords)
2. Erstelle ein neues Bot-Passwort mit Rechten:
   - ✅ Upload files (via API)
   - ✅ Edit pages (for SDC metadata)
3. Kopiere den **Bot-Benutzer** und **Bot-Passwort**
4. Trage in LrMediaWiki2 ein:
   - **Username:** `YourUsername@YourBotName`
   - **Password:** Das generierte Bot-Passwort

**Vorteile:**
- Dein echtes Passwort bleibt geschützt
- Bot-Passwort kann jederzeit gelöscht werden
- Separate Aktivitätsprotokollierung

### Metadaten-Tagsets aktivieren

Das Plugin enthält mehrere spezialisierte Metadaten-Tagsets:

1. **Lightroom → Library** (oben rechts)
2. **Metadata Panel** (rechts) → **Metadaten-Menü**
3. Wähle ein Tagset:
   - **"LrMediaWiki – All"** (universal)
   - **"LrMediaWiki – Information"** (standard)
   - **"LrMediaWiki – Artwork"** (für Kunstwerke)
   - **"LrMediaWiki – Object Photo"** (für Objektfotografie)

---

## 📝 Erste Nutzung

### Metadaten für ein Foto eingeben

1. **Foto in Lightroom auswählen** (Library view)
2. **Rechts: Metadata Panel** → Wähle dein Tagset
3. Fülle die wichtigsten Felder:

#### Basis-Felder

| Feld | Beispiel | Notwendig? |
|------|----------|----------|
| **File caption (en)** | "Cannes 2026" | ✅ (für SDC) |
| **Description All** | Siehe unten | ✅ (für Datei-Beschreibung) |
| **Categories** | `Cannes 2026\nFestival` | ⚠️ (empfohlen) |

#### Description All Format

Das ist das **wichtigste Feld**. Hier kommt alles rein:

```
caption_en=Isaach de Bankolé at Cannes 2026
caption_de=Isaach de Bankolé bei Cannes 2026
creator=Q640
depicts=Q1342843
{{en|1=[[:en:Isaach de Bankolé|Isaach de Bankolé]] at photo call}}
{{de|1=Isaach de Bankolé bei einem Photo-Call}}
[[Category:Cannes 2026]]
```

**Struktur:**
1. **Key=Value-Zeilen** (für SDC-Upload)
2. **Leerzeile**
3. **Wikitext-Blöcke** (`{{lang|...}}`, Templates, Kategorien)

**Wichtig:** Jede Zeile muss eine neue Zeile sein – keine Leerzeichen am Anfang!

### Export zu Wikimedia Commons

1. **Foto auswählen** → **File → Export Photos**
2. **Export Location:** Wähle "MediaWiki"
3. **Export Dialog:**
   - **Target Wiki:** `Wikimedia Commons`
   - **License:** Wähle deine Lizenz (z.B. CC-BY-SA-4.0)
   - **Filename:** Der Name, unter dem die Datei auf Commons hochgeladen wird
4. **Export** klicken

**Das Plugin wird:**
1. ✅ Deine `description_all` Key=Value-Paare extrahieren
2. ✅ SDC-Felder hochladen (caption, creator, depicts, license, copyright)
3. ✅ Wikitext-Inhalte in die Datei-Beschreibung schreiben
4. ✅ Kategorien & Templates hinzufügen

---

## 🔍 Wikidata Q-IDs finden

Für SDC-Felder brauchst du Wikidata Q-IDs. So findest du sie:

### Person (depicts)
1. Gehe zu [Wikidata.org](https://www.wikidata.org)
2. Suche den Namen (z.B. "Isaach de Bankolé")
3. Kopiere die **Q-ID** aus der URL: `wikidata.org/wiki/Q1342843`
4. Trage in `description_all` ein: `depicts=Q1342843`

### Lizenz (license)
1. Gehe zu [Wikidata:Creative Commons Licenses](https://www.wikidata.org/wiki/Wikidata:Creative_Commons_licenses)
2. Suche deine Lizenz (z.B. CC-BY-SA-4.0 = Q18199165)
3. Trage ein: `license=Q18199165`

### Urheberrecht (copyright)
1. Suche in Wikidata: "CC-BY-SA"
2. Q-ID kopieren: `copyright=Q73566113` (z.B. für Public Domain)

### Fotograf/Künstler (creator)
1. Dein eigener Wikimedia-Account als Creator: `creator=Q[deine-ID]`
   - Finde deine Q-ID: Gehe zu [Wikidata](https://www.wikidata.org), suche deinen Namen
2. Oder lass das Feld leer – Commons setzt automatisch den Uploader

---

## 🐛 Troubleshooting

### Plugin wird nicht angezeigt

**Problem:** Plugin ist nicht in der Plugin-Liste sichtbar

**Lösung:**
1. Überprüfe den Pfad: `AppData/Roaming/Adobe/Lightroom/Plugins/` (Windows) oder `~/Library/Application Support/Adobe/Lightroom/Plugins/` (macOS)
2. Datei heißt exakt `mediawiki.lrdevplugin` (Groß-/Kleinschreibung beachten)
3. Lightroom komplett neustarten (nicht nur Fenster)
4. Im Plugin Manager: "Show Plugin Manager" → "Check for Updates"

### Upload schlägt fehl / "Authentication Error"

**Problem:** Fehler beim Upload zu Commons

**Lösung:**
1. **API-Zugangsdaten überprüfen:**
   - Username korrekt? (Case-sensitive!)
   - Bot-Passwort oder echtes Passwort verwendet?
   - Wenn Bot: Format `username@botname` korrekt?
2. **Netzwerk checken:** Kannst du auf commons.wikimedia.org zugreifen?
3. **Logs anschauen:** Lightroom-Console (Window → Panels → Alerts) hat Error-Details

### SDC-Felder werden nicht hochgeladen

**Problem:** `caption_en`, `creator` usw. erscheinen nicht auf Commons

**Lösung:**
1. **Syntax überprüfen:** 
   - Kein Leerzeichen nach `=` erlaubt: `caption_en=Text` (nicht `caption_en = Text`)
   - Zeilenumbruch nach jedem Key: `caption_en=...\ncaption_de=...`
2. **Q-IDs validieren:** Ist z.B. `creator=Q640` eine gültige Wikidata-ID?
3. **Logs checken:** Wurden die Keys erkannt/extrahiert?

### Multilingual Captions funktionieren nicht

**Problem:** Nur Englisch wird angezeigt

**Lösung:**
1. **Alle caption-Keys nutzen:**
   ```
   caption_en=English title
   caption_de=Deutscher Titel
   caption_fr=Titre français
   ```
2. **Format überprüfen:** Jeder `caption_xx=` auf eigener Zeile
3. **Commons SDC überprüfen:** Datei auf Commons öffnen → "Structured Data" Panel

---

## 📖 Weiterführende Ressourcen

- **[SDC-Workflow.md](../docs/SDC-Workflow.md)** – Praktische Workflow-Beispiele
- **[Refactoring-Details.md](../docs/Refactoring-Details.md)** – Technische Dokumentation
- **[Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)** – Offizielle Commons-Seite
- **[Wikidata:Commons Structured Data](https://www.wikidata.org/wiki/Wikidata:Commons_Structured_Data)** – SDC-Dokumentation
- **[MediaWiki API](https://www.mediawiki.org/wiki/API:Main_page)** – MediaWiki API-Docs

---

## ✉️ Support

- **Probleme melden:** [GitHub Issues](https://github.com/krichel89/LrMediaWiki2/issues)
- **Wikimedia Commons Talk:** [Talk:Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Talk:Commons:LrMediaWiki)
- **Wikidata Community:** [Wikidata Project Chat](https://www.wikidata.org/wiki/Wikidata:Project_chat)

---

**Viel Erfolg bei der Nutzung von LrMediaWiki2!** 📸🎉

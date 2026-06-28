# LrMediaWiki2

**MediaWiki Plugin für Adobe Lightroom Classic** mit umfassender Unterstützung für **Wikimedia Commons Structured Data (SDC)** und multisprachigen Beschreibungen.

LrMediaWiki2 ist ein Fork mit vollständiger Refaktorierung der ursprünglichen [LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)-Codebase, optimiert für moderne Commons-Workflows mit Wikidata-Integration.

---

## ✨ Hauptmerkmale (v2.0.0)

### **Structured Data (SDC) Fields via `description_all`**

**Neu in v2.0:** Die meisten SDC-Felder können direkt über einfache Key=Value-Paare im `description_all`-Feld beschrieben werden:

- `caption_en`, `caption_de`, `caption_fr`, `caption_it` – Multilingual Captions (P2096)
- `creator` – Quelle/Urheber (P170, Wikidata Q-ID)
- `depicts` – Porträt/Dargestellte Person (P180, Wikidata Q-ID)
- `copyright` – Urheberrecht (P6216, Wikidata Q-ID)
- `license` – Lizenz (P275, Wikidata Q-ID)

Diese werden automatisch extrahiert und via **Single-Call `wbeditentity`-API** in Commons SDC hochgeladen.

### **Multilingual Wikitext Descriptions**

Vollständige Wikitext-Dateibeschreibungen mit Sprachvarianten:

```wikitext
{{en|1=Description in English with [[links]]}}
{{de|1=Beschreibung auf Deutsch mit [[Links]]}}
{{fr|1=Description en français avec [[liens]]}}
```

### **Templates & Categories**

Automatische Integration von Custom Templates und Kategorien:

```wikitext
{{WikiPortraits Cannes Film Festival 2026}}
[[Category:2026 Cannes Film Festival]]
```

### **Multi-Metadataset Support**

Spezialisierte Metadatasets für verschiedene Inhaltstypen:
- **General** – Universelle Dateien
- **Artwork** – Kunstwerke (Artwork-Infobox)
- **Object Photo** – Objektfotografie
- **Information** + **Information (DE)** – Sprachvarianten

### **Erweiterte Tools**

Batch-Tools für komplexe Workflows:
- 🔍 **Search and Replace Metadata** – Massenbearbeitung von Metadaten
- 🔎 **Search and Replace Filename** – Dateinamen-Anpassung
- 🚀 **Generate from Persons** – Auto-generierte Beschreibungen aus Wikimedia-Daten
- 📄 **Set Title** – Automatische Titelformatierung

---

## 🚀 Installation

### Anforderungen

- **Adobe Lightroom Classic** 4.0 oder höher (Windows & macOS)
- **Administrator-Zugang** zu einem MediaWiki-Installation (Standard: Wikimedia Commons)
- **Wikidata-Kenntnisse** (für die Nutzung der Q-IDs in `description_all`)

### Schritt-für-Schritt

1. **Download** der neuesten Release (v2.0.0) von [GitHub Releases](https://github.com/krichel89/LrMediaWiki2/releases)

2. **Plugin-Datei** in dein Lightroom-Plugin-Verzeichnis kopieren:
   
   **Windows:**
   ```
   C:\Users\[YourUsername]\AppData\Roaming\Adobe\Lightroom\Plugins\
   ```
   
   **macOS:**
   ```
   ~/Library/Application Support/Adobe/Lightroom/Plugins/
   ```

3. **Lightroom Classic neu starten**

4. **Plugin aktivieren:**
   - Edit → Preferences → Plugins
   - "LrMediaWiki" aktivieren

5. **API-Zugangsdaten konfigurieren:**
   - File → Plugin Manager → LrMediaWiki → MediaWiki/Commons credentials eingeben
   - Bot- oder Benutzername und Passwort für Commons

---

## 📖 Verwendung

### Basis-Workflow

1. **Foto in Lightroom auswählen**

2. **Metadaten eingeben** (Plugin Metadata Panel):
   - **File caption (en)**: `Isaach de Bankolé at the 2026 Cannes Film Festival`
   - **Description All**: Siehe Beispiel unten

3. **Export → MediaWiki** (Export-Dialog)
   - Zielwiki: Wikimedia Commons
   - Lizenz: Auswählen
   - **Dateiname & Upload starten**

### `description_all`-Format (Praktisches Beispiel)

```
caption_en=Isaach de Bankolé at the 2026 Cannes Film Festival
caption_de=Isaach de Bankolé bei den Internationalen Filmfestspielen von Cannes 2026
caption_fr=Isaach de Bankolé au Festival de Cannes 2026
caption_it=Isaach de Bankolé al Festival di Cannes 2026
creator=Q640
depicts=Q1342843
copyright=Q73566113
license=Q18199165
{{en|1=[[:en:Isaach de Bankolé|Isaach de Bankolé]] at a photo call for Kering Women in Motion at the [[:en:79th Cannes Film Festival|2026 Cannes Film Festival]]
}}
{{de|1=[[:de:Isaac de Bankolé|Isaach de Bankolé]] bei einem Photo-Call für Kering Women in Motion bei den [[:de:Internationale Filmfestspiele von Cannes 2026|Internationalen Filmfestspielen von Cannes 2026]]
}}
{{WikiPortraits Cannes Film Festival 2026}}
[[Category:Isaach de Bankolé]]
[[Category:2026 Cannes Film Festival]]
```

**Das Plugin verarbeitet automatisch:**
- ✅ Key=Value-Paare → SDC via `wbeditentity`
- ✅ `{{lang|...}}` → Multilingual Wikitext
- ✅ Templates & Kategorien → Datei-Wikitext
- ✅ Single Upload Call

---

## 🔧 SDC Key Reference

| Key | SDC Property | Beispiel | Bemerkung |
|-----|---------|----------|-----------|
| `caption_en` | P2096 (caption) | `Cannes Film Festival 2026` | Englischer Bildtitel |
| `caption_de` | P2096 | `Filmfestspiele von Cannes 2026` | Deutscher Titel |
| `caption_fr` | P2096 | `Festival de Cannes 2026` | Französischer Titel |
| `caption_it` | P2096 | `Festival di Cannes 2026` | Italienischer Titel |
| `creator` | P170 | `Q640` (Isaac Asimov) | Wikimedia-ID des Schöpfers |
| `depicts` | P180 | `Q1342843` (Person) | Porträt/dargestellte Person |
| `copyright` | P6216 | `Q73566113` (CC-BY-SA-4.0) | Urheberrechtstatus |
| `license` | P275 | `Q18199165` (CC-BY-SA-4.0) | Lizenz-Wikidata-ID |

**Weitere Felder möglich** – siehe [Wikidata:Commons Structured Data](https://www.wikidata.org/wiki/Wikidata:Commons_Structured_Data)

---

## 🛠️ Technische Details zur v2.0.0 Refaktorierung

### Was ist neu?

**v1.8 → v2.0:**

1. **SDC-Field-Extraktion** – Alle Key=Value-Paare werden aus `description_all` geparst und strukturiert
2. **Single-Call Upload** – `wbeditentity`-API statt mehrfacher API-Aufrufe
3. **Multilingual Support** – Automatische Verarbeitung von `{{lang|...}}`-Blöcken
4. **Robuste Key-Validierung** – Nur unterstützte Keys werden hochgeladen

### Code-Architektur

```
mediawiki.lrdevplugin/
├── Info.lua                          # Plugin-Metadaten & Version
├── MediaWikiExportServiceProvider.lua # UI & Export-Dialog
├── MediaWikiInterface.lua             # Verarbeitung & Validierung
├── MediaWikiApi.lua                   # API-Aufrufe (wbeditentity)
├── MediaWikiMetadataProvider.lua      # Metadataset-Definitionen
├── MediaWikiUtils.lua                 # Hilfsfunktionen
└── Tools/                             # Batch-Tools
```

**Key-Extraktion in `MediaWikiInterface.lua`:**
- Regex-basierte Extraktion von `key=value`-Paaren
- Validierung gegen SDC-Schema
- Strukturierte `wbeditentity`-Payload

---

## 📚 Weiterführende Dokumentation

- **[Installation.md](./docs/Installation.md)** – Detaillierte Setup-Anleitung
- **[SDC-Workflow.md](./docs/SDC-Workflow.md)** – Praktische Workflows mit SDC-Integration
- **[Refactoring-Details.md](./docs/Refactoring-Details.md)** – Technische Tiefe der v2.0-Refaktorierung
- **[Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)** – Offizielle Commons-Dokumentation

---

## 🐛 Issues & Support

- **GitHub Issues:** [Report a bug](https://github.com/krichel89/LrMediaWiki2/issues)
- **Commons Talk Page:** [Commons:Talk:LrMediaWiki](https://commons.wikimedia.org/wiki/Talk:Commons:LrMediaWiki)
- **Wikidata:** [Wikidata:Commons Structured Data](https://www.wikidata.org/wiki/Wikidata:Commons_Structured_Data)

---

## 📝 Lizenz

LrMediaWiki2 ist unter der **MIT License** lizenziert – siehe [LICENSE.txt](LICENSE.txt)

**Basierend auf:**
- Original: [robinkrahl/LrMediaWiki](https://github.com/robinkrahl/LrMediaWiki)
- Fork: [Hasenlaeufer/LrMediaWiki](https://github.com/Hasenlaeufer/LrMediaWiki)

---

## 👤 Credits

**LrMediaWiki2 v2.0 Refactoring:** Harald Krichel ([@Seewolf](https://commons.wikimedia.org/wiki/User:Seewolf))  
**Original Plugin:** Robin Krahl & Contributors

Für vollständige Credits siehe [CREDITS.txt](CREDITS.txt)

---

## 🌍 Community

- Wikimedia Commons: [@Seewolf](https://commons.wikimedia.org/wiki/User:Seewolf)
- German Wikipedia: [Administrator since 2003](https://de.wikipedia.org/wiki/Benutzer:Seewolf)
- Wikidata contributions: [Wikidata profile](https://www.wikidata.org/wiki/User:Seewolf)

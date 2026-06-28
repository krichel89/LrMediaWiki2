# CHANGELOG – LrMediaWiki2

## [2.0.0] – 2026-06-28

### 🎯 Major: Structured Data (SDC) Field Support

**Die bedeutendste Änderung in v2.0:** Vollständige Unterstützung für die meisten Wikimedia Commons Structured Data (SDC)-Felder direkt via `description_all` Key=Value-Extraktion.

#### ✨ Neue Features

**SDC Key=Value-Felder in `description_all`**
- Added `caption_en`, `caption_de`, `caption_fr`, `caption_it` für multilingual SDC Captions (P2096)
- Added `creator` für SDC Creator (P170) – Wikidata Q-ID Format
- Added `depicts` für SDC Depicts (P180) – Porträt/Person-Referenzen
- Added `copyright` für SDC Copyright Status (P6216)
- Added `license` für SDC License (P275)
- Automatische Extraktion aller Key=Value-Paare aus `description_all`
- Validierung gegen SDC-Schema vor Upload

**Single-Call API Upload**
- Refactored MediaWikiApi.lua für Single-Call `wbeditentity`-Uploads
- Alle SDC-Felder werden in einer API-Anfrage hochgeladen (statt mehrfacher Calls)
- Reduzierte Netzwerk-Latenz und verbesserte Zuverlässigkeit

**Refactored Metadata Field**
- Unified `description_all` Feld ersetzt fragmentierte Beschreibungs-/Metadaten-Felder
- Freetext Wikitext Format mit strukturierter Key=Value-Extraktion
- Unterstützt Wikitext-Blöcke (`{{lang|...}}`), Templates und Kategorien im selben Feld

**Multilingual Caption Support**
- Automatische Verarbeitung von `{{en|...}}`, `{{de|...}}`, `{{fr|...}}`-Blöcken
- Mapping zu SDC Captions in verschiedenen Sprachen
- Vollständige Wikitext-Inhalte werden erhalten (Links, Formatierung)

#### 🔄 Breaking Changes

- **`description_all` ersetzt separate Felder** – Alte separate Beschreibungsfelder werden nicht länger verwendet
- **Key=Value-Format ist case-sensitive** – `creator=Q640` nicht `Creator=Q640`
- **Wikidata Q-IDs erforderlich** – `creator`, `depicts`, `copyright`, `license` benötigen Valid Q-IDs

#### 🐛 Bug Fixes & Improvements

- Improved error handling für ungültige SDC Keys
- Better logging für Key-Extraktion während Export
- Fixed: Multilingual captions werden nun korrekt in SDC gemappt
- Fixed: Templates und Kategorien wurden in v1.8 teilweise falsch verarbeitet
- Improved: Location-Template wird weiterhin korrekt prepended zu `description_all`

#### 📚 Dokumentation

- NEW: [SDC-Workflow.md](./docs/SDC-Workflow.md) – Praktische Workflow-Beispiele
- NEW: [Refactoring-Details.md](./docs/Refactoring-Details.md) – Technische Dokumentation
- Updated: README.md mit v2.0 Features & SDC Reference Table
- Updated: Installation.md mit neuen Metadataset-Erklärungen

#### 📊 Version Info

```lua
VERSION = {
    major = 2,
    minor = 0,
    revision = 0,
}
```

---

## [1.8.0] – (Vorgänger)

> Diese Version war die Basis für den v2.0-Fork. Detaillierte Änderungen siehe Original [LrMediaWiki CHANGELOG](https://github.com/robinkrahl/LrMediaWiki/blob/master/CHANGELOG.md)

### Features (aus 1.8)
- Basic MediaWiki/Commons upload support
- Artwork & Object Photo infobox templates
- Multiple metadata tagsets (DE, IT, etc.)
- Batch tools (Search & Replace, Generate from Persons, etc.)
- Location template support
- File caption (en) field for basic SDC support

---

## Migration Guide: 1.8 → 2.0

### ✅ Automatisch kompatibel
- Alte Dateien & Workflows funktionieren weiterhin
- Location-Template wird automatisch prepended
- Bestehende Kategorien & Templates werden verarbeitet

### ⚠️ Empfohlene Anpassungen
- **Migrieren zu `description_all`-Format** – Neue SDC-Felder können nur via Key=Value genutzt werden
- **Wikidata Q-IDs sammeln** – Für Porträts: `depicts=Q...`, für Urheber: `creator=Q...`
- **Sprachvarianten nutzen** – Statt nur `caption_en`, auch `caption_de`, `caption_fr` adden

### Beispiel: Alt vs. Neu

**v1.8 (alt):**
```
File Caption (en): "Photo at Cannes 2026"
[separate fields für Beschreibung, Quelle, etc.]
```

**v2.0 (neu):**
```
Description All:
caption_en=Photo at Cannes 2026
caption_de=Foto bei Cannes 2026
creator=Q640
depicts=Q1342843
{{en|1=Detailed description in English...}}
{{de|1=Detaillierte Beschreibung auf Deutsch...}}
[[Category:2026 Cannes Film Festival]]
```

---

## Future Roadmap

### Geplant (v2.1+)
- [ ] Batch-Upload mehrerer Dateien mit SDC-Feldern
- [ ] SDC-Feld-Vorschau vor Upload
- [ ] Integration mit Wikidata-Such-API für Q-ID-Autocomplete
- [ ] Unterstützung weiterer SDC-Felder (z.B. P625 für Koordinaten)
- [ ] Template-Validierung vor Upload

### In Diskussion
- [ ] Dark mode für UI
- [ ] Mobile Lightroom App Support
- [ ] GraphQL API Migration (falls MediaWiki in Zukunft verfügbar)

---

## Versionierungsschema

LrMediaWiki2 folgt **Semantic Versioning**:
- **MAJOR** – Breaking Changes (z.B. neue `description_all`-Format)
- **MINOR** – Neue Features (z.B. zusätzliche SDC-Felder)
- **PATCH** – Bug Fixes & Verbesserungen

---

## Kontakt & Support

- **GitHub Issues:** [Report bugs](https://github.com/krichel89/LrMediaWiki2/issues)
- **Wikimedia Commons:** [@Seewolf](https://commons.wikimedia.org/wiki/User:Seewolf)
- **German Wikipedia:** [Administrator](https://de.wikipedia.org/wiki/Benutzer:Seewolf)

Danke für die Nutzung von LrMediaWiki2! 🎉

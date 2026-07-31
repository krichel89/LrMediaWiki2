# SDC Workflow Guide – LrMediaWiki2 v2.0.0

Praktische Workflows für verschiedene Foto-Typen mit Structured Data (SDC)-Integration.

---

## Workflow 1: Porträt bei Film Festival

**Szenario:** Du hast ein Porträt von Isaach de Bankolé beim Cannes Film Festival 2026 fotografiert.

### Metadaten in Lightroom eingeben

**File caption (en):**
```
Isaach de Bankolé at the 2026 Cannes Film Festival
```

**Description All:**
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
{{fr|1=[[:fr:Isaach de Bankolé|Isaach de Bankolé]] lors d'un photo call pour Kering Women in Motion au [[:fr:Festival de Cannes 2026|Festival de Cannes 2026]]
}}
{{it|1=Isaach de Bankolé a un photo call per Kering Women in Motion al [[:it:Festival di Cannes 2026|Festival di Cannes 2026]]
}}
{{WikiPortraits Cannes Film Festival 2026}}
[[Category:Isaach de Bankolé]]
[[Category:2026 Cannes Film Festival]]
[[Category:Photographs by Harald Krichel at the Cannes Film Festival 2026]]
```

### Was passiert beim Upload?

1. **SDC wird mit diesen Daten gefüllt:**
   - Caption (P2096): Alle 4 Sprachversionen
   - Creator (P170): Q640 (Info: Isaach de Bankolé selbst, wenn der Uploader der Künstler ist)
   - Depicts (P180): Q1342843 (die fotografierte Person)
   - Copyright (P6216): Q73566113
   - License (P275): Q18199165

2. **Datei-Wikitext erhält:**
   ```wikitext
   {{en|1=...}}
   {{de|1=...}}
   {{fr|1=...}}
   {{it|1=...}}
   {{WikiPortraits Cannes Film Festival 2026}}
   [[Category:Isaach de Bankolé]]
   [[Category:2026 Cannes Film Festival]]
   [[Category:Photographs by Harald Krichel at the Cannes Film Festival 2026]]
   ```

3. **Commons-Datei-Ansicht zeigt:**
   - Dateiname mit allen Metadaten
   - "Structured Data" Panel mit Captions in 4 Sprachen
   - "Creator", "Depicts Person", "License", "Copyright"
   - Wikitext-Beschreibung in allen Sprachen
   - Kategorien zum Durchsuchen

---

## Workflow 2: Kunstwerk/Gemälde

**Szenario:** Du hast ein Foto eines Gemäldes vom Louvre gemacht (z.B. Leonardos "Mona Lisa").

### Wichtige Wikidata-IDs vorher sammeln

- **Kunstwerk:** Q7218 (Mona Lisa)
- **Künstler:** Q762 (Leonardo da Vinci)
- **Museum:** Q7275 (Louvre)
- **Künstler des Fotos:** Q... (deine Q-ID, wenn vorhanden)

### Metadaten eingeben

**File caption (en):**
```
Mona Lisa by Leonardo da Vinci, Louvre Museum
```

**Description All:**
```
caption_en=Mona Lisa by Leonardo da Vinci at the Louvre
caption_de=Mona Lisa von Leonardo da Vinci im Louvre
depicts=Q7218
creator=Q762
copyright=Q19652
license=Q6938433
depicts_artist=Q762
{{en|1=[[:en:Mona Lisa|Mona Lisa]], oil on poplar wood panel, by [[:en:Leonardo da Vinci|Leonardo da Vinci]], on display at the [[:en:Louvre|Louvre Museum]] in Paris.
}}
{{de|1=Öl auf Holz, [[:de:Leonardo da Vinci|Leonardo da Vinci]], ausgestellt im [[:de:Louvre|Louvre-Museum]] in Paris.
}}
[[Category:Paintings in the Louvre]]
[[Category:Mona Lisa by Leonardo da Vinci]]
```

### Artwork Infobox (optional, über Metadataset)

Falls du das "LrMediaWiki – Artwork" Metadataset nutzt:
- **Artist:** Q762
- **Title:** Mona Lisa
- **Medium:** oil on poplar wood
- **Dimensions:** [aus Museum-Daten]
- **Institution:** Louvre
- **Wikidata:** Q7218

---

## Workflow 3: Gruppenbild / Event Foto

**Szenario:** Ein Foto mehrerer Personen beim Event (z.B. Berlinale 2026).

### Mehrere Personen (depicts)

**Hinweis:** Ein Feld `depicts` kann nur eine Q-ID pro Zeile haben. Für mehrere Personen:

```
caption_en=Left to right: Jane Smith, John Doe, Lisa Brown at Berlinale 2026
depicts=Q...jane_smith
depicts=Q...john_doe
depicts=Q...lisa_brown
{{en|1=Left to right: 
* [[:en:Jane Smith|Jane Smith]]
* [[:en:John Doe|John Doe]]
* [[:en:Lisa Brown|Lisa Brown]]
at the Berlinale 2026
}}
[[Category:Berlinale 2026]]
[[Category:Jane Smith]]
[[Category:John Doe]]
[[Category:Lisa Brown]]
```

**Wichtig:** Nutze mehrere `depicts=Q...`-Zeilen, nicht alle in einer Zeile!

---

## Workflow 4: Landschafts- / Ortsfoto

**Szenario:** Foto eines Ortes, z.B. der Eiffel Tower mit Standort-Koordinaten.

### Standort automatisch hinzufügt

Das Plugin **automatisch** einen `{{Location}}` Template bei GPS-Daten:
- Wenn GPS in Lightroom vorhanden: Breitengrad, Längengrad (automatisch prepended)
- Falls Kamera-Kompass: auch `heading` wird hinzugefügt

**Description All:**
```
caption_en=Eiffel Tower at dusk
caption_de=Eiffelturm in der Abenddämmerung
depicts=Q243
{{en|1=The [[:en:Eiffel Tower|Eiffel Tower]] in Paris at dusk.
}}
{{de|1=Der [[:de:Eiffelturm|Eiffelturm]] in Paris in der Abenddämmerung.
}}
[[Category:Eiffel Tower]]
[[Category:Paris]]
```

**Das Plugin fügt automatisch hinzu:**
```wikitext
{{Location|48.858|2.295|heading:90}}
[rest of description]
```

---

## Workflow 5: Museum / Archive Photo

**Szenario:** Historisches Foto aus einem Archiv (Public Domain).

### Public Domain als Copyright

```
caption_en=Photograph from the State Library of Berlin, 1923
copyright=Q6662
license=Q19911
depicts=Q...
{{en|1=Historical photograph from the [[:en:State Library of Berlin|State Library of Berlin]], dated 1923. This photograph is in the public domain.
[Source information]
}}
[[Category:Public domain photographs]]
[[Category:State Library of Berlin]]
[[Category:1923 in Berlin]]
```

**Key Points:**
- `copyright=Q6662` (Public Domain Mark 1.0)
- `license=Q19911` (Public Domain / No Copyright)
- Multiple language captions möglich
- Kategorien für Archiv + Ort

---

## Quick Reference: Häufige Wikidata Q-IDs

### Lizenzen & Copyright

| Name | Q-ID | Verwendung |
|------|------|-----------|
| CC-BY-SA 4.0 | Q18199165 | license |
| CC-BY 4.0 | Q20007257 | license |
| CC0 1.0 | Q6938433 | license |
| Public Domain | Q19911 | license |
| Public Domain Mark 1.0 | Q6662 | copyright |
| CC-BY-SA 3.0 | Q14947546 | license |
| GNU FDL 1.2+ | Q14434633 | license |

### Events

| Name | Q-ID |
|------|------|
| Cannes Film Festival | Q220411 |
| Berlinale | Q47148 |
| Venice Film Festival | Q35516 |
| Sundance Film Festival | Q193163 |
| SXSW | Q644976 |

### Länder / Orte

| Name | Q-ID |
|------|------|
| France | Q142 |
| Germany | Q183 |
| Italy | Q38 |
| Paris | Q90 |
| Berlin | Q64 |
| Rome | Q220 |

**Andere IDs findest du auf [Wikidata.org](https://www.wikidata.org) durch Suche!**

---

## Troubleshooting: SDC-Felder funktionieren nicht

### Szenario 1: Nur `caption_en` wird hochgeladen, andere Sprachen nicht

**Ursache:** Syntax-Fehler in anderen caption-Zeilen

**Lösung:**
```
❌ Falsch:
caption_en=Title
caption_de = German Title  (Leerzeichen um =)
caption_fr=French

✅ Richtig:
caption_en=Title
caption_de=German Title
caption_fr=French
```

### Szenario 2: `creator` oder `depicts` funktioniert nicht

**Ursache:** Q-ID ist ungültig oder existiert nicht

**Lösung:**
1. Überprüfe die Q-ID auf [Wikidata.org](https://www.wikidata.org)
2. Format überprüfen: `creator=Q640` (keine Leerzeichen)
3. Q-ID muss existieren: z.B. Q640 = Kermit the Frog (valide)

### Szenario 3: Templates / Kategorien werden ignoriert

**Ursache:** Syntax-Fehler oder falsch platziert

**Lösung:**
```
❌ Falsch:
caption_en=Title
{{en|1=...}}[[Category:...]]  (alles in einer Zeile)

✅ Richtig:
caption_en=Title
{{en|1=...}}
[[Category:...]]

(jedes Template/Kategorie auf eigener Zeile)
```

---

## Pro-Tipps

### 1. Template für eigene Workflows

Erstelle dir ein **Standard-Template** in Lightroom:
1. Ein Foto mit vollständigen Metadaten speichern
2. Metadata Panel → Metadata Presets → "New Preset"
3. Für zukünftige Fotos: Preset anwenden + nur Unterschiede editieren

### 2. Batch-Workflow mit mehreren Fotos

1. Mehrere Fotos auswählen (Ctrl+Click / Cmd+Click)
2. **Library → Photo → Edit Photos** → "Sync Settings"
3. Caption & Description All synchronisieren
4. **Batch-Export** zu Commons starten

### 3. Lokale Anmerkungen vor Upload

Nutze Lightroom's **Notes** (oben in Metadaten):
- Notiere Q-IDs für Personen
- Merke, welche Sprachen du noch hinzufügen musst
- Checkliste: caption_en ✓ caption_de ✓ depicts ✓

### 4. Wikidata Q-ID Finder Bookmarklet

Erstelle einen Browser-Bookmarklet zur schnellen Q-ID-Suche:
```javascript
javascript:window.open('https://www.wikidata.org/w/api.php?action=query&titles='+prompt('Search:')+' | Format=json', '_blank')
```

---

## Weiterführende Docs

- **[Installation.md](./Installation.md)** – Setup & Konfiguration
- **[Refactoring-Details.md](./Refactoring-Details.md)** – Technische Architektur
- **[Wikidata:Commons Structured Data](https://www.wikidata.org/wiki/Wikidata:Commons_Structured_Data)** – Offizielle SDC-Docs
- **[Commons:LrMediaWiki](https://commons.wikimedia.org/wiki/Commons:LrMediaWiki)** – Commons-Seite

---

**Happy uploading!** 📸✨

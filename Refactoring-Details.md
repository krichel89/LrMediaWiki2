# Technical Refactoring Details – LrMediaWiki2 v2.0.0

Technische Architektur, Code-Änderungen und Implementierungsdetails der Refaktorierung von v1.8 → v2.0.

**Zielgruppe:** Entwickler, Power-User, Forks

---

## 🏗️ Architektur-Überblick

### Komponenten (v2.0)

```
mediawiki.lrdevplugin/
│
├── Info.lua
│   └─ Plugin-Metadaten, Version, Tagsets
│
├── MediaWikiExportServiceProvider.lua
│   └─ UI, Export-Dialog, Field-Handling
│
├── MediaWikiInterface.lua
│   ├─ description_all Parsing
│   ├─ Key=Value Extraktion
│   └─ Datei-Vorbereitung
│
├── MediaWikiApi.lua
│   ├─ wbeditentity API-Calls
│   ├─ SDC-Payload-Konstruktion
│   └─ Error-Handling
│
├── MediaWikiMetadataProvider.lua
│   └─ Metadata-Tagsets (All, Information, Artwork, etc.)
│
├── MediaWikiUtils.lua
│   ├─ String-Utilities
│   ├─ Validation-Funktionen
│   └─ Logging
│
└── Tools/
    ├─ ToolSearchAndReplaceMetadata.lua
    ├─ ToolGenerateFromPersons.lua
    └─ [weitere Batch-Tools]
```

---

## 🔄 Data Flow: Von Lightroom zu Commons

### Workflow v2.0

```
[Lightroom Metadaten]
  ↓
  └─ File Caption (en) + Description All + Categories
     ↓
     [MediaWikiExportServiceProvider.lua → fillFieldsByFile]
     ↓
     └─ exportFields = {
          caption_en: "...",
          description_all: "key1=val1\nkey2=val2\n{{...}}\n[[Category:...]]",
          categories: "...",
          ...
        }
     ↓
     [MediaWikiInterface.lua → parseDescriptionAll]
     ↓
     └─ sdcFields = {
          caption_en: "...",
          caption_de: "...",
          creator: "Q...",
          depicts: "Q...",
          license: "Q...",
          ...
        }
        wikitext = "{{en|1=...}}\n{{de|1=...}}\n[[Category:...]]"
     ↓
     [MediaWikiApi.lua → constructWbeditentityPayload]
     ↓
     └─ payload = {
          action: "wbeditentity",
          entity: "M[FileID]",
          data: {
            labels: { en: { language: "en", value: "..." } },
            descriptions: { en: { language: "en", value: "..." } },
            statements: {
              P2096: [ { mainsnak: { snaktype: "value", property: "P2096", datavalue: { ... } } } ],
              P170: [ { mainsnak: { ... } } ],
              ...
            }
          }
        }
     ↓
     [MediaWiki API]
     ↓
     └─ ✅ Commons Datei mit SDC-Felder & Wikitext
```

---

## 🔑 Key=Value Extraktion (Core Refactoring)

### Algorithmus in `MediaWikiInterface.lua`

```lua
local function parseDescriptionAll(descriptionAllString)
    local sdcFields = {}
    local wikitext = {}
    
    -- Split by lines
    for line in string.gmatch(descriptionAllString .. "\n", "[^\n]*\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim
        
        -- Match: key=value pattern
        local key, value = string.match(line, "^([a-z_]+)=(.*)$")
        
        if key and isValidSdcKey(key) then
            -- SDC Key erkannt
            sdcFields[key] = value
        else
            -- Kein Key=Value → Wikitext-Zeile
            table.insert(wikitext, line)
        end
    end
    
    return sdcFields, table.concat(wikitext, "\n")
end
```

### Unterstützte Keys (v2.0)

| Key | Typ | SDC Property | Beispiel |
|-----|-----|--------------|----------|
| `caption_en` | string | P2096 | "Title in English" |
| `caption_de` | string | P2096 | "Titel auf Deutsch" |
| `caption_fr` | string | P2096 | "Titre en français" |
| `caption_it` | string | P2096 | "Titolo in italiano" |
| `creator` | Q-ID | P170 | "Q640" |
| `depicts` | Q-ID | P180 | "Q1342843" |
| `copyright` | Q-ID | P6216 | "Q73566113" |
| `license` | Q-ID | P275 | "Q18199165" |

**Validierung:**
- Keys case-sensitive (nur lowercase)
- Caption-Values beliebige Strings
- Q-ID Keys: `^Q\d+$` Regex
- Unbekannte Keys werden ignoriert (nicht hochgeladen)

---

## 🚀 Single-Call wbeditentity Upload

### v1.8 vs v2.0

**v1.8 (Multiple API Calls):**
```
1. Upload Datei
2. API Call 1: setPropertyForFile(file, caption_en)
3. API Call 2: setPropertyForFile(file, caption_de)
4. API Call 3: setPropertyForFile(file, creator)
5. ... (mehrere Calls)
→ Zeitverschwendung, höhere Fehlerrate
```

**v2.0 (Single Call):**
```
1. Upload Datei
2. API Call 1: wbeditentity with all SDC fields
   {
     action: "wbeditentity",
     entity: "M[FileID]",
     data: {
       statements: {
         P2096: [...],  // alle captions
         P170: [...],   // creator
         P180: [...],   // depicts
         P6216: [...],  // copyright
         P275: [...]    // license
       }
     }
   }
→ Single atomic transaction
```

### Implementation in `MediaWikiApi.lua`

```lua
local function uploadSdcFields(fileEntityId, sdcFields)
    local statements = {}
    
    -- Build P2096 (captions) for each language
    for lang, caption in pairs({
        en = sdcFields.caption_en,
        de = sdcFields.caption_de,
        fr = sdcFields.caption_fr,
        it = sdcFields.caption_it,
    }) do
        if caption then
            table.insert(statements.P2096, {
                mainsnak = {
                    snaktype = "value",
                    property = "P2096",
                    datavalue = {
                        value = caption,
                        type = "monolingualtext",
                        language = lang
                    }
                }
            })
        end
    end
    
    -- Build P170 (creator)
    if sdcFields.creator then
        table.insert(statements.P170, {
            mainsnak = {
                snaktype = "value",
                property = "P170",
                datavalue = {
                    value = { entity_id = sdcFields.creator },
                    type = "wikibase-entityid"
                }
            }
        })
    end
    
    -- ... etc für P180, P6216, P275
    
    -- Single API Call
    local response = mediawiki:post({
        action = "wbeditentity",
        format = "json",
        id = fileEntityId,
        data = cjson.encode({
            statements = statements
        })
    })
    
    return response
end
```

---

## 📋 Metadaten-Tagsets (v2.0)

### Neue Struktur in `Info.lua`

```lua
LrMetadataTagsetFactory = {
    'MediaWikiMetadataSetAll.lua',              -- Alle Felder
    'MediaWikiMetadataSetInformation.lua',      -- Standard Info
    'MediaWikiMetadataSetInformationDe.lua',    -- German
    'MediaWikiMetadataSetArtwork.lua',          -- Kunstwerke
    'MediaWikiMetadataSetObjectPhoto.lua',      -- Objektfotos
},
```

### Inhalte pro Tagset

**MediaWikiMetadataSetAll.lua:**
```lua
return {
    id = 'LrMediaWikiAll',
    name = 'LrMediaWiki – All',
    fields = {
        'com.adobe.lightroom.caption',  -- Standard Lightroom
        'org.ireas.lightroom.mediawiki:caption_en',
        'org.ireas.lightroom.mediawiki:description_all',  -- NEW v2.0
        'org.ireas.lightroom.mediawiki:categories',
        'org.ireas.lightroom.mediawiki:artist',
        'org.ireas.lightroom.mediawiki:title',
        -- ... weitere custom fields
    },
    viewOrder = 'depth',  -- Verschachtelte Anordnung
}
```

**MediaWikiMetadataSetArtwork.lua:**
```lua
return {
    id = 'LrMediaWikiArtwork',
    name = 'LrMediaWiki – Artwork',
    fields = {
        'org.ireas.lightroom.mediawiki:description_all',
        'org.ireas.lightroom.mediawiki:artist',
        'org.ireas.lightroom.mediawiki:title',
        'org.ireas.lightroom.mediawiki:medium',
        'org.ireas.lightroom.mediawiki:dimensions',
        -- ... Artwork-spezifische Felder
    },
}
```

---

## 🔗 Metadata Provider Updates

### `MediaWikiMetadataProvider.lua` (v2.0)

```lua
return {
    metadataFieldsForPhotos = function(propertyTable)
        return {
            {
                id = 'caption_en',
                namespace = 'org.ireas.lightroom.mediawiki',
                title = LOC '$$$/LrMediaWiki/Metadata/CaptionEn=File caption (en)',
                description = 'SDC Caption in English (P2096)',
                dataType = 'string',
                readOnly = false,
                editable = 'always',
            },
            {
                id = 'description_all',
                namespace = 'org.ireas.lightroom.mediawiki',
                title = LOC '$$$/LrMediaWiki/Metadata/DescriptionAll=Description All',
                description = 'Complete Wikitext description with SDC key=value + templates',
                dataType = 'string',
                readOnly = false,
                editable = 'always',
            },
            -- ... weitere Felder
        }
    end,
}
```

---

## 🧪 Validierung & Error Handling

### Key-Validierung

```lua
local VALID_SDC_KEYS = {
    caption_en = true,
    caption_de = true,
    caption_fr = true,
    caption_it = true,
    creator = true,
    depicts = true,
    copyright = true,
    license = true,
}

local function isValidSdcKey(key)
    return VALID_SDC_KEYS[key] == true
end

local function validateSdcValue(key, value)
    if key:match('^caption_') then
        -- Captions können beliebig sein
        return true, nil
    elseif key == 'creator' or key == 'depicts' or key == 'copyright' or key == 'license' then
        -- Q-IDs validieren
        if value:match('^Q%d+$') then
            return true, nil
        else
            return false, "Invalid Q-ID format: " .. value
        end
    end
    return false, "Unknown SDC key: " .. key
end
```

### Error-Handling beim Upload

```lua
local function uploadWithErrorHandling(sdcFields, wikitext)
    -- Pre-flight checks
    if not sdcFields or (#sdcFields == 0 and wikitext == '') then
        return false, "No metadata to upload"
    end
    
    -- Validate all SDC keys
    for key, value in pairs(sdcFields) do
        local valid, err = validateSdcValue(key, value)
        if not valid then
            LrLogger:log(err)
            -- Fehlerhafte Keys überspringen, nicht crashen
            sdcFields[key] = nil
        end
    end
    
    -- Try upload
    local success, result = pcall(function()
        return uploadSdcFields(fileEntityId, sdcFields)
    end)
    
    if not success then
        return false, "API error: " .. tostring(result)
    end
    
    return true, result
end
```

---

## 📝 Logging & Debugging

### Log Output bei `description_all` Parse

```
[INFO] Parsing description_all
[DEBUG] Found 4 captions: en, de, fr, it
[DEBUG] Found 3 Q-ID fields: creator, depicts, license
[DEBUG] Found wikitext block: 24 lines
[INFO] SDC Fields extracted: 7
[INFO] Wikitext payload: 24 lines
[DEBUG] Uploading via wbeditentity
[INFO] Upload successful: M123456789
```

### Debug-Modus aktivieren

In `MediaWikiUtils.lua`:
```lua
LOCAL_DEBUG = true  -- Set für verbose logging
```

---

## 🔮 Future Improvements (v2.1+)

### Geplante Erweiterungen

1. **Weitere SDC-Felder**
   - P625 (coordinates) – Direktes Hochladen von GPS
   - P6731 (file type) – automatisch erkannt
   - P7482 (stated in) – Quelle des Bildes

2. **Batch-Processing**
   - Multiple files gleichzeitig verarbeiten
   - Parallel uploads

3. **SDC-Vorschau**
   - Preview der hochgeladenen Felder vor Upload
   - Validierungsreport

4. **Wikidata-Integration**
   - Q-ID Autocomplete in Lightroom
   - Direkte Suche nach Personen/Werken

---

## 🔧 Development Setup

### Lokale Entwicklung

1. **Fork & Clone:**
   ```bash
   git clone https://github.com/krichel89/LrMediaWiki2.git
   cd LrMediaWiki2
   ```

2. **Development Plugin Setup:**
   - Link `mediawiki.lrdevplugin` zu Lightroom-Plugin-Ordner
   - Oder: Kopiere bei jedem Test

3. **Testing:**
   - Test-Wikimedia Account erstellen
   - Dummy-Fotos mit verschiedenen Metadaten
   - Nach Upload: SDC auf Commons überprüfen

4. **Debugging:**
   - Lightroom Console (Window → Panels → Alerts)
   - `LrLogger` nutzen für Ausgaben
   - Break Points in Lua-Debugger (falls verfügbar)

---

## 📚 Literatur & Ressourcen

- **[Lightroom SDK](https://www.adobe.io/apis/creativecloud/lightroomclassic.htm)** – Offizielle API-Doku
- **[MediaWiki API](https://www.mediawiki.org/wiki/API:Main_page)** – MediaWiki API
- **[wbeditentity Docs](https://www.mediawiki.org/wiki/Wikibase/API#wbeditentity)** – Wikibase Edit API
- **[Wikidata:Commons Structured Data](https://www.wikidata.org/wiki/Wikidata:Commons_Structured_Data)** – SDC Reference
- **[Lua 5.1](https://www.lua.org/manual/5.1/)** – Lua Language Reference

---

## 🤝 Contributing

Patches & Improvements willkommen! Bitte:
1. Fork the repo
2. Feature branch erstellen: `git checkout -b feature/your-feature`
3. Commit deine Änderungen
4. Tests durchlaufen (manuell auf Lightroom + Commons)
5. Pull Request öffnen

---

**Questions? Issues? Reach out on GitHub!** 🚀

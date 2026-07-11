# LrMediaWiki2 – SDC extensions (Cammello alignment) + security/robustness fixes

## Version 2.0.10 (July 2026)

1. **New export dialog row "Other fields"** (batch default, its own row below
   "Other Templates"), with NO hard-coded example value (default is empty).
   Its content is inserted after the infobox, at the same position as
   "Other Templates". **Side finding:** the per-photo "Other fields" field of
   the Artwork / Object photo metadata sets (`otherFields`) had NEVER been
   wired into the export – a dead field since the beginning of this fork.
   It is active now: a value there overrides the batch default for that one
   photo.
2. **Depicts extraction hardened (CRLF/whitespace):** The reported case
   "depicts=Q2579483 # Lies Van Gasse was not written" could not be
   reproduced with clean `\n` text – the core logic was already correct in
   tests. Plausible gap found and closed: the line-anchored extraction
   (`^depicts=` / `\ndepicts=`) previously required exactly `\n` right
   before the key and NO leading whitespace. With Windows line endings
   (`\r\n`, e.g. from pasting out of a Windows editor) or an accidentally
   indented line, the line was NOT recognized – it stayed visible as plain
   text in the wikitext (which is why it could be seen in the field) but was
   never turned into a P180 claim. Now: CRLF/CR is normalized to `\n` at the
   start of `buildFileDescription`, and all line anchors tolerate optional
   leading whitespace (`%s*`). Covered by test cases for CRLF, CR, indented
   key, and a no-anomaly regression.

   **If the problem persists:** enable logging in the Plug-in Manager
   (plug-in author tools), repeat the export once, and check whether the
   diagnostic log shows a `P180` claim in the `wbeditentity` call for the
   affected file (the log has masked passwords/tokens since 2.0.x, so it is
   safe to share). This distinguishes "extraction from description_all
   fails" from "extraction OK, but publishing fails".
3. **SDC editor: new "Categories" row.** Reads and writes the per-photo
   'categories' field (semicolon-separated, without `[[Category:]]`
   brackets). Placed between "Created during" and the free wikitext field.
   The "apply depicts to all selected photos" checkbox does NOT touch
   categories – they remain strictly per photo.
4. **Windows: "Wikitext" missing from the Metadata panel dropdown.** No code
   cause found: the tagset file is valid Lua (luac-checked), clean UTF-8
   without BOM, LF line endings, and its title uses the same en dash as the
   base sets that do show up on Windows. The strongest hypothesis is the
   same as the earlier identical macOS incident: the file
   `MediaWikiMetadataSetDescriptionAll.lua` is missing (or outdated) in the
   Windows plug-in folder. To verify on the Windows machine: check that the
   file exists in `mediawiki.lrdevplugin/`, and look at the Plug-in Manager
   diagnostics ("last message") – a missing tagset file produces a message
   like "No script by the name …". Recommended sync path for the Windows
   machine: `git pull` from the repository instead of copying single files.
5. README rewritten in English (this file).

## Version 2.0.9 (July 2026)

Corrections after field-testing 2.0.8 – rebuilt on top of ONLY bindings that
demonstrably work in this Lightroom installation:

1. **Search results visible again.** Finding: push_buttons with a BOUND
   title do not update (in the base plug-in, bound titles exist only on
   static_text), and `visible` on row containers is ignored – which is why
   the result buttons stayed invisible. New: results appear in a **dropdown
   with bound items** (this mechanism demonstrably worked in 2.0.7), the
   first hit is **preselected**, and "⬅ Übernehmen" (static title, proven)
   takes it over – the common case remains a SINGLE click. A direct click
   on a list entry cannot be implemented reliably in the LrView SDK: there
   is no list control, the selection observer was demonstrably unreliable
   (2.0.7), and bound button titles demonstrably invisible (2.0.8).
2. **Empty language rows hidden:** `visible` is now bound on the FIELDS of
   the caption rows instead of (only) the row – row containers have no
   non-layout properties of their own according to the SDK docs. VERIFY:
   control-level visible is still untested in this installation; if the
   empty rows are still visible, the fallback is to show all 12 rows
   permanently and remove ➕ – please report back.

## Version 2.0.8 (July 2026)

1. **Search results as a clickable list in the dialog** (instead of a
   dropdown): after 0.6 s of typing rest, up to 5 hits appear as buttons
   directly below the search field ("Label – description (QID)"); **one
   click takes it over**. No ✚ button, no dropdown, no selection observer –
   the unreliable click observer from 2.0.7 was replaced. (A popup_menu
   cannot be opened programmatically via the SDK; the open button list is
   the desired behavior.) — superseded by 2.0.9, see above.
2. **Comments now visible:** clicking a search result enters
   `Q640 # Harald Krichel` into the field; the line lands 1:1 as
   `depicts=…` in the wikitext field. In the **export dialog** the defaults
   are now annotated (`Q73566113 # copyrighted`, `Q18199165 # CC BY-SA 4.0`)
   and the license picker shows `Q18199165 # CC BY-SA 4.0` /
   `Q6938433 # CC0`. The export still strips `# …` before uploading.
3. **Color highlighting removed** (LrColor/text_color gone).
4. **Languages as free ISO code fields:** the first 4 slots are pre-filled
   with en/de/fr/it; "➕ Sprache" reveals an **empty** slot, the code is
   typed by hand (12 slots total). Parsed captions in further languages are
   distributed onto the slots automatically (alphabetically); with more
   than 12 languages, surplus caption_XX= lines are preserved losslessly
   (overflow logic, tested). Invalid codes (< 2 letters, whitespace) are
   discarded on save instead of uploading broken labels.

ToolEditSdc.lua was rewritten from scratch in this version.

## Version 2.0.7 (July 2026)

1. **QID labels in soft blue.** Per-field background colors are not
   possible in the Lightroom SDK (`background_color` exists only on
   `scrolled_view`, min. 80 px height + scroll bars). Instead the **label
   texts** of the QID fields were colored – removed again in 2.0.8 on
   request.
2. **➕ Sprache adds up to 12 languages** beyond the initial 4
   (en/de/fr/it/es/nl/pl/ru/zh/pt/ja/uk) – replaced by free ISO code
   fields in 2.0.8.
3. **Click on a search result takes it over directly** (no ✚ button) via an
   observer on the dropdown selection with a guard flag – proved unreliable
   in practice, replaced in 2.0.8/2.0.9.
4. **QID comments:** a search result is entered as `Q640 # Harald Krichel`;
   manual entries like `Q18199165 # CC BY-SA 4.0` also work. The export
   strips the `# …` part cleanly when splitting/normalizing (depicts loop,
   normalizeSdcQid for batch fields). Comments are stored in
   `description_all` and round-trip losslessly. The export dialog fields
   (creator, copyright, license, created during) also accept `Q640 # name`.

## Version 2.0.6 (July 2026)

1. **Distribute checkbox: merge instead of replace, checked by default.**
   When applying to the selection, missing QIDs are appended; each photo's
   own depicts are kept. Duplicate detection also works across legacy
   comma lists (edge case caught by a test: previously `Q1, Q2` + `Q2`
   would have produced a duplicate).
2. **Upload format verified:** the export already creates **one separate
   P180 statement per QID** (confirmed by a test against the JSON
   assembly); the semicolon/comma list is only the input format and is
   split before uploading. No change needed.
3. **Layout:** QID field and search field on one row each; the result
   dropdown uses the full width below (depicts and created during).
4. **Only 5 languages** in the caption dropdown (en, de, fr, it, es; 4
   visible, ➕ reveals the fifth) – superseded in 2.0.7/2.0.8.
5. **New button "⬇ Captions → Wikitext":** takes all filled captions as
   `{{lang|1=…}}` blocks to the beginning of the wikitext field
   (idempotent: identical blocks and duplicate languages are skipped); the
   captions themselves remain untouched as SDC labels.
6. **Rename: "Description (all)" is now called "Wikitext" everywhere** –
   set title "LrMediaWiki – Wikitext", field label, menu entry
   ("🔁 Description fields ↔ Wikitext"), tooltips, translation. The field
   ID `description_all` is unchanged (no schema bump, no data migration).

## Version 2.0.5 (July 2026)

1. **Live search while typing:** search fields for depicts AND created
   during – the Wikidata search starts automatically after 0.6 s of typing
   rest (debounce via a generation counter; a new keystroke invalidates
   older queries, including ones whose HTTP response is still pending);
   minimum 2 characters.
2. **Semicolon instead of comma** as the depicts separator (clearer with
   person names containing commas). The export (`MediaWikiInterface.lua`)
   accepts **both** – comma and semicolon – so existing lines keep working.
3. **Created during with its own search row** – same live search as
   depicts, writes a single QID.

## Version 2.0.4 (July 2026)

- Tools registered under Library > Plug-in Extras (LrLibraryMenuItems), so
  the SDC editor and the converter are reachable from the Library module
  (e.g. for a macOS Shortcuts app command; exact menu title:
  "🏷️ Edit Structured Data (SDC)").

## Version 2.0.3 (July 2026)

- Wikidata name search reinstated in the SDC editor (wbsearchentities,
  public/unauthenticated, `language=de`).

## Version 2.0.2 (July 2026)

1. Duplicate "color label on export" row removed (combo_box duplicate with a
   nil item crashed the export dialog).
2. Color-label setting additionally available in the export dialog itself
   (global preference via startDialog/endDialog).
3. Wikitext metadata set slimmed to the single field (25 lines).
4. ~28 German translations added, 3 trailing-comma defects in
   TranslatedStrings_de.txt repaired.
5. ToolEditSdc task fix ("We can only wait from within a task") – the whole
   flow runs inside one async task.

## Version 2.0.1 (July 2026)

1. depicts/created_during visible in the metadata sets (the sets determine
   visibility, not the provider).
2. New single-line fields description_en/description_de (schema 11 → 12) and
   a dedicated tagset for the all-in-one wikitext field.
3. Converter tool `ToolConvertDescriptionAll.lua`: moves content between the
   single-language fields and `{{en|1=…}}`/`{{de|1=…}}` blocks (move
   semantics, conflict protection: differently filled targets are skipped
   instead of overwritten, identical content is deduplicated; balanced
   `%b{}` parsing because of nested templates like `{{w|…}}`).
4. On export, filled single-language fields are merged into the wikitext as
   blocks automatically (duplicate protection via plain find).
5. SDK fact: there is no hook when the user switches tagsets – content
   cannot be moved automatically on switching; hence the explicit converter
   tool.

## Audit fixes (security/robustness, July 2026)

1. **Passwords/tokens no longer in the log file** (MediaWikiApi):
   request-body and response traces mask `password`/`lgpassword`/`token`/
   `logintoken`/`lgtoken` as well as `…token="…"` values. Previously the
   clear-text password was written to `Documents/LrMediaWikiLogger.log`
   whenever logging was enabled (upstream even documented it that way).
   **Delete old log files!**
2. **wbeditentity JSON via JSON:encode** instead of string concatenation:
   captions containing `"`, `\` or control characters could break the JSON
   or inject structure. Empty parts are omitted (no `[]` for `labels`).
3. **Gallery overwrite protection:** a read error (e.g. HTTP 429 right
   after the batch) used to be treated as "page does not exist" → the
   existing gallery page was replaced wholesale. Now a page is only created
   on 404; anything else is skipped (bezel notice + trace).
4. **Password no longer in export presets:** `password` is no longer an
   exportPresetField; saving a preset used to write it to disk in clear
   text. **Re-save or delete old presets.**
5. **HTTPS enforced:** `http://` API paths are rejected before login.
6. **badtoken retry for the multipart upload** (prevents batch abort on an
   expired CSRF token).
7. **Rename-upload errors no longer swallowed** (the recursion's return
   value is propagated).
8. **Placeholder check:** whitelist of common tags (`<sub>`, `<ref>`,
   `<gallery>` …), checks all occurrences; previously a legitimate `<sub>`
   aborted the whole export.
9. **Artwork/Object-photo placeholders repaired** (`<artArtist>` etc. were
   dropped by a table reassignment).
10. **Gallery name extraction:** the French " à " mangled to `\x01 95p` was
    replaced with the correct UTF-8 sequence (`\195\160`).
11. **Search & Replace tools: user input is now treated literally**
    (`ToolSearchAndReplaceMetadata.lua`, `ToolSearchAndReplaceFilename.lua`).
    Previously the input was interpreted as a Lua pattern: search texts
    ending in `%` (e.g. "50%") or containing an unbalanced `[` threw a
    runtime error mid-batch; `( ) . * + - ? ^ $` silently changed the
    semantics (e.g. "(Test)" never matched the literal). Additionally: a
    guard against an empty search string (which would have inserted the
    replacement between every character).
12. **Further fixes in the S&R tools:** metadata tool: dead, doubly broken
    helper function removed. Filename tool: binding typo `replacStr`
    corrected; the file extension is now split off correctly (previously a
    fixed last-4-characters cut – wrong for `.jpeg`/`.tiff`/no extension);
    one catalog write transaction for the whole batch instead of one per
    photo (faster, single undo step).

## Installation

Copy the files into `mediawiki.lrdevplugin/` (overwrite existing ones), then
restart Lightroom or reload the plug-in in the Plug-in Manager.

Because `MediaWikiMetadataProvider.lua` now has `schemaVersion = 12`,
Lightroom registers the new fields on reload. **The new fields appear in the
Metadata panel when you select the corresponding "LrMediaWiki" metadata set
at the top of the panel.** Plug-in fields do not show up in the default view
automatically – that is normal Lightroom behavior.

## Changed files (overview)

- **MediaWikiMetadataProvider.lua** – per-photo sidebar fields, including
  Depicts (P180) and Created during (P10408); schemaVersion 12.
- **MediaWikiExportServiceProvider.lua** – batch SDC section
  (creator/copyright/license/created during, annotated QID defaults),
  "Other fields" row, per-photo overrides, priority order:
  sidebar field → `description_all` line → batch default.
- **MediaWikiInterface.lua** – dynamic caption_XX extraction, depicts/
  created_during claims (one statement per QID, comments stripped),
  CRLF/whitespace-robust line anchors, gallery overwrite protection,
  other_fields block assembly.
- **MediaWikiApi.lua** – JSON-encoded wbeditentity, credential masking in
  traces, badtoken retry, QID normalization (skip invalid values instead of
  aborting the request).
- **ToolEditSdc.lua** – the SDC editor (see version history).
- **ToolConvertDescriptionAll.lua** – single-language fields ↔ wikitext
  blocks converter.
- **MediaWikiMetadataSet\*.lua / TranslatedStrings_de.txt / Info.lua** –
  tagsets, German translations, registration/version.

## Open question (deliberately not changed without asking)

`depicts` and `created_during` now exist **both** in the sidebar **and** in
the modal tool. On export, the sidebar field wins. Whether the two fields
should be removed from the modal tool entirely (leaving it a pure
captions/wikitext tool) is still open.

## Please verify in Lightroom (not testable remotely)

1. That the metadata fields appear correctly after the schemaVersion bump
   (select the "LrMediaWiki" metadata set). Existing data should be
   preserved.
2. Hiding/revealing the caption rows via control-level bound `visible`
   (fallback: remove the `visible` lines, then all slots are permanently
   visible).
3. That label language codes used are valid Wikibase codes – an invalid
   code would make the `wbeditentity` call fail.
4. **Password field after fix 4:** when the export dialog opens, the saved
   password (from LrPasswords via startDialog) must reappear in the field
   and the export must work.
5. **Claims-only upload** (photo without captions, only
   depicts/created_during): verify once live that `wbeditentity` accepts
   the `data` JSON without a `labels` part.
6. **Windows:** that `MediaWikiMetadataSetDescriptionAll.lua` exists in the
   plug-in folder and the "Wikitext" metadata set appears (see 2.0.10,
   item 4).

## Not independently verified

- `Q18199165 = CC BY-SA 4.0`, `Q6938433 = CC0`, `Q73566113` (copyright
  default) come from the Cammello code base, not from independent checking.
  `P10408 = created during` has been verified against Wikidata.

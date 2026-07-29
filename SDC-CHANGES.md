# LrMediaWiki2 – SDC extensions (Cammello alignment) + security/robustness fixes

## Version 2.0.36 (July 2026)

**The built-in SDC dialog is gone.** `ToolEditSdc.lua` has been removed and
with it both menu entries ("Edit Structured Data (SDC)"). The browser editor
is now the only SDC editor. The dialog had been kept as a no-browser
fallback, but it duplicated a growing amount of behaviour - two search
implementations, two ways of writing the same two stores - and the browser
editor has overtaken it in every respect except one (see below). Nothing
else referenced the file: it was reachable only from `Info.lua`, so the
removal touches no shared code and no metadata field definition.
`schemaVersion` is unchanged.

**Known regression.** The dialog had a checkbox that copied `depicts` to the
entire selection; the browser editor works on the active photo only and has
no equivalent. Until that is rebuilt, distributing a QID across many photos
has to be done photo by photo, or through the export dialog's batch
defaults.

**Menu order.** The browser editor is now the first entry in both the
Library and the File plug-in menus, so it sits at the top of the submenu.
The titles in the two menus remain identical, so a single macOS app shortcut
bound to the title still reaches it from either menu.

## Version 2.0.35 (July 2026)

**Tracking category on every upload.** Every uploaded file now gets
`[[Category:Uploaded with LrMediaWiki2]]`, the way upload tools on Commons
conventionally mark their work. It is added last, so it sits at the bottom
of the category list, and never twice - if it is already in the category
field or written by hand in the wikitext, nothing is added. The name lives
in a single constant, `MediaWikiInterface.trackingCategory`; emptying it
switches the feature off.

**The browser editor speaks English as well, and is prepared for more
languages.** All interface texts moved into one table with `de` and `en`;
a picker in the header switches between them, and the choice is remembered
in the plug-in preferences for the next call. Adding a language means
adding one more table and nothing else - it appears in the picker by
itself. A missing key falls back to English and then to the key name, so
an incomplete translation cannot break the page.

**The search now covers several languages at once.** For people this
rarely matters - a name reads the same everywhere - but for things it
does: "Kamera", "camera" and "appareil photo" are three different strings,
and Wikidata's prefix search only finds what exists in the language it is
asked about. The editor now queries the interface language, English, and
every language this photo already has a caption in (up to four), plus the
cross-language full-text search - all in PARALLEL, so the broader search
costs barely more time than the old single-language one. Labels are shown
in the interface language, then English, then whatever exists, so a row
stays readable either way.

## Version 2.0.34 (July 2026)

The two "anhängen" buttons in the browser editor are now one, labelled
"SDC zu Wikitext". It appends both at once - captions as
{{language|1=…}} blocks and categories as [[Category:…]] lines - and
reports how many lines were added. Clicking it repeatedly is still
harmless: whatever is already in the wikitext is not added again.

## Version 2.0.33 (July 2026)

Wording: the button in the browser editor now reads "Bildunterschriften
als Vorlagen anhängen" instead of "Unterschriften" - a signature is not a
caption. No other changes.

## Version 2.0.32 (July 2026)

Documentation only, in preparation for the release. README.md now covers
the browser editor, the browser login (OAuth 2.0) including the "ok" page
users will see, the one-line-per-QID depicts format, and the two new
files in the architecture listing. No code changes.

## Version 2.0.31 (July 2026)

**Completely new return path: a file download instead of a network
callback.** The loopback approach (LrSocket on 127.0.0.1) failed on this
machine - the browser sent, but nothing arrived. A downloaded file has
none of these failure modes: no port, no fetch, no firewall rule.

"Speichern" in the browser triggers a download of
`lrmediawiki-sdc-result.json`. A background watcher in Lightroom polls
the Downloads folder every two seconds, picks up the file, applies the
changes and deletes it. Lightroom is NOT blocked while the page is open -
the watcher runs in its own async task. Stale result files from earlier
runs are removed before the browser opens.

The entire LrSocket / port / chunk machinery is gone from this tool.
The old built-in SDC dialog is unchanged and still in the menu.

## Version 2.0.30 (July 2026)

Diagnostics and a second delivery path, after a save that the browser
reported as sent never arrived in Lightroom.

The browser cannot tell whether its request was delivered (see 2.0.29),
so "sent" from the page means nothing on its own. Lightroom now shows
what it actually sees, live in the progress bar: how many request lines
reached the port and how many chunks were accepted. A transfer that goes
nowhere is visible within seconds instead of after the timeout, and the
two failure modes - nothing arrives at all, versus something arrives and
is rejected - are distinguishable while it happens.

The page sends each request twice, as a `fetch` and as an image load.
Either can be blocked independently depending on the browser; a chunk
that arrives twice is harmless, because the receiving side files chunks
by index. A "Verbindung testen" button sends a bare ping, which shows up
in the request counter without touching any data - the quickest way to
tell a blocked port from a problem with the payload.

The timeout is down from 600 to 180 seconds, so a failure reports itself
promptly; the page can simply send again.

Also fixed, before it could bite: a `</script>` anywhere in the wikitext
would have ended the page's script block early and broken the whole
editor. The injected JSON now escapes `<`.

## Version 2.0.29 (July 2026)

Fixes the browser reporting "Lightroom hat nicht geantwortet" on save.

The page treated a rejected `fetch()` as a failed transfer. It is not:
LrSocket answers every received line with "ok" and no HTTP status line, so
a browser accepts that as a response for a navigation (which is why the
OAuth callback works and shows a page full of "ok") but rejects it for a
`fetch()`. The request itself is delivered either way - the browser simply
cannot tell. Because the requests were chained on `.then()`, the first
rejection also stopped everything after it.

The page now ignores the rejection as the expected case and no longer
claims success: it reports how many requests went out and that Lightroom
confirms the outcome, which is where the real confirmation has always
been. The finished wikitext stays on screen, and a "Nochmal an Lightroom
senden" button sits next to the copy button.

Two changes reduce the number of moving parts in that transfer:

- A short payload - the normal case - now goes out as ONE request, which
  is exactly the shape the loopback probe verified. Splitting only starts
  above 3000 encoded characters, and the Lua side treats a request
  without `i`/`n` as a complete single chunk.
- The port moved to 8129, the one the probe demonstrably got through on.
  (8128 stays reserved for the OAuth callback.)

`POST` is accepted alongside `GET`, so a different sending method in the
browser cannot fail at this point.

Lightroom's side now reports precisely instead of "nothing arrived". It
counts request lines separately from accepted chunks and so tells three
cases apart: nothing reached the port at all, something arrived but
belonged to another run (usually an older editor page still open), or the
transfer started and broke off. Every request line goes to the log.

## Version 2.0.28 (July 2026)

Fixes a plug-in that would not load after 2.0.27.

The page template was embedded as one long-bracket string
(`[==[ … ]==]`). That parses correctly in Lua 5.1 and passed every check
here, but the page contains `[[` and `]]` from wikitext category links,
and a parser that treats those as bracket syntax inside the string would
reject the file - which would make Lightroom refuse the whole plug-in.

`SdcEditorTemplate.lua` is now generated as ordinary quoted strings, one
per line, joined at the end. Quoted strings have no bracket semantics at
all, so this class of problem cannot occur. The result is verified
byte-identical to `sdc-editor.html`; the file is machine-generated and
should be regenerated from the HTML rather than edited by hand.

`ToolEditSdcWeb.lua` now loads the template lazily and inside a pcall, so
even a broken template can only produce a clear message in that one tool
instead of taking anything else with it.

NOTE: this is a fix for the most plausible cause, not a confirmed one -
the failure could not be reproduced outside Lightroom, where all files
parse and load cleanly. If the plug-in still refuses to load, the error
text in the Plug-in Manager will name the file responsible.

## Version 2.0.27 (July 2026)

**New: the structured data can be edited in a browser.** New menu entry
"Edit Structured Data in browser" next to the existing dialog, which
stays exactly as it was and remains the fallback.

Why: LrView cannot show or hide rows, cannot open a dropdown from code,
has no tooltips, and needs a fixed number of rows built up front - all
measured on this installation over the past releases, not assumed. A
browser page has none of those limits. What that buys: a result list that
simply appears and is steerable with the arrow keys, applied entries as
wrapping chips instead of a fixed block of rows, freely addable caption
languages, and a live preview of the wikitext exactly as it will be
stored.

How it works: the tool writes the photo's values into a copy of the page
template (`SdcEditorTemplate.lua`, the HTML embedded as a long string so
that nothing has to be located on disk at runtime), opens it with
`LrHttp.openUrlInBrowser`, and listens on port 8130. "Speichern und zu
Lightroom" sends the result back in percent-encoded chunks, which the
tool reassembles, decodes and writes to the catalog - description_all,
categories, caption_en and the two sidebar fields, so both stores stay in
step. A per-run token means a browser tab left open from an earlier run
cannot overwrite the photo being edited now, and the temporary page is
deleted afterwards.

All of this rests on measurements, not documentation: of four ways to
open a local file, `LrHttp.openUrlInBrowser('file:///…')` is the only one
that works here (`LrShell.openFilesInApp` throws nothing but opens
nothing; `LrTasks.execute` and `LrShell.openPathsViaCommandLine` raise
"Yielding is not allowed within a C or metamethod call"), and a fetch()
from a file:// page to 127.0.0.1 does reach the listening socket.

Port 8130 is deliberately not 8128: that one belongs to the OAuth
callback registered with Wikimedia and has to stay free.

Known limits of this first version: it edits the ACTIVE photo only -
there is no equivalent of the "distribute depicts" checkbox yet - and
while the page is open Lightroom waits, showing a progress bar that can
be cancelled where the SDK provides one.

## Version 2.0.26 (July 2026)

**depicts is written one line per QID.** With inline comments a single
semicolon-separated line had become unreadable; the wikitext now holds

    depicts=Q640 # Harald Krichel
    depicts=Q42 # Douglas Adams

This required a change on the EXPORT side as well: the extractor in
MediaWikiInterface took only the first line for each key, so multiple
lines would have uploaded one QID and silently dropped the rest. It now
collects every occurrence of a key and joins them. Both formats are
read: an existing single semicolon line still works and is rewritten to
the new layout on the next save.

**Four caption slots instead of twelve, no "➕ Sprache" button.** All four
are shown from the start and their ISO codes are freely editable, so
there was nothing left to reveal. Captions in other languages are still
NOT lost - they are carried through as overflow and written back
unchanged, which the tests cover with six languages through four slots.

**Sections reordered:** depicts, categories, created during, captions,
free wikitext.

**The `visible` bindings added in 2.0.25 are gone again.** They were
measured not to reclaim the rows' vertical space on this installation,
so they were dead weight; the row counts do the work instead.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.25 (July 2026)

**The dialog fits on the screen again.** It had grown taller than the
display, with no way to scroll and the lower sections simply out of
reach. The whole content is now wrapped in an `f:scrolled_view` with a
bounded height. If this SDK version has no such view or rejects the
attributes, a pcall falls back to the plain view - i.e. exactly the
previous behaviour, noted in the log.

**Unused rows no longer sit there empty.** Result rows and applied-entry
rows carry a bound `visible` that is false while the row has no text, on
the row AND on its controls. Row-level `visible` was measured as ignored
on this installation, so this may only blank the rows rather than
reclaim their space - in which case nothing is worse than before, and
the row counts below do the actual work.

**Fewer rows.** Result rows drop from six to five per search section,
applied-entry rows from eight to six. Entries beyond the sixth are still
stored and uploaded and are counted underneath ("… und n weitere"); the
text field above stays the full, hand-editable truth.

Both row counts are constants (`VISIBLE_RESULT_ROWS`, `APPLIED_ROWS`) and
the scroll area's height is one number, so all three are easy to retune
once it has been seen on a real screen.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.24 (July 2026)

**A search hit is applied by clicking its text.** The probe shipped with
2.0.23 showed that a `mouse_down` handler on `static_text` fires on this
installation - and bound static_text titles were already proven to
update, so that control is the one that can do both. The result rows now
carry the handler on the text itself, and the "⬅" button next to each row
is gone: it did the same job with a smaller target to aim at.

"⬅ QID" next to the search field stays, for applying a QID typed straight
in. The "✕" buttons on the applied-entry rows stay as buttons on purpose:
removing an entry should need a deliberate click on its own target, not
the same gesture that adds one.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.23 (July 2026)

**Applied entries are listed individually and can be taken back out with
one click.** Under the depicts field, every entry now has its own row -
"Q640 – Harald Krichel", so the comment finally serves as the explanation
it was meant to be - with a "✕" at the end that removes exactly that
entry. Created during has the same, for its single value. Up to eight
rows are shown; anything beyond that is counted ("… und n weitere"), and
the text field above stays the full, hand-editable truth. The rows are
only a view of it, so typing in the field keeps working and updates the
rows immediately.

An accidental apply is now one click to undo instead of hunting for the
right semicolon.

Note on clicking the RESULT text itself to apply it: not shipped, because
it cannot be done reliably with what has been measured so far. A
push_button is clickable but its bound title provably does not update in
this SDK, and static_text updates but is not documented as clickable. A
separate throwaway probe plug-in ships alongside this version to settle
which control, if any, can do both.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.22 (July 2026)

**Faster search.** The live search now starts at three characters instead
of two, and the debounce between the last keystroke and the request drops
from 0.6 to 0.25 seconds, so hits appear almost while typing. The
debounce is not removed entirely - that would fire one request per
keystroke - and the generation counter still discards any answer a newer
keystroke has overtaken.

**Shorter labels, shorter placeholders.** The section headings are now
just "Depicts (P180)", "Created during (P10408)", "Bildunterschriften
(SDC-Captions)" and "Kategorien". The value fields show "Q1234567" as
their placeholder and the search fields "Suchen", instead of the long
commented examples.

**Help behind "?" buttons.** Each of the four sections has a "?" button
next to its heading that opens the explanation the headings and
placeholders used to carry: syntax with examples, what the "#" comments
do, how the search and the "⬅" buttons work, and what "Vorschlagen
(P373)" actually does. Implemented as a dialog rather than a tooltip: the
SDK has no tooltip attribute for metadata fields (established in 2.0.12),
and whether LrView dialog controls accept one is unverified - a button
that opens a dialog needs no such assumption.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.21 (July 2026)

**The search hits are simply visible now - no dropdown to open.**

Both dropdown designs shared the same flaw: the SDK offers no way to open
a popup_menu or combo_box from code, so the results existed but stayed
hidden behind an arrow that had to be clicked before anything could be
seen. That cost a click on every single search, in 2.0.18 as much as in
2.0.19.

The dropdown is gone. Each search section now has a plain search field
plus six ALWAYS-VISIBLE result rows: a bound static_text carrying the hit
("Label – description  (Q123)") and a fixed-caption "⬅" button that
applies exactly that row. Bound static_text titles are proven to update
in this SDK, and the buttons keep fixed captions because bound button
titles are proven NOT to update - so the design relies only on measured
behaviour, with nothing left to open, select, or confirm. Typing shows
"Suche…" in the first row and "Keine Treffer." when the search comes back
empty, so the state is always readable.

The search field additionally accepts a QID typed straight in ("Q640",
"q640 # Kommentar"), applied with the "⬅ QID" button next to it.

Removed with the dropdown: the combo item formatter, its selection parser
and membership test, and the result/choice properties. What survives is
the fuzzy search itself, unchanged.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.20 (July 2026)

The registered OAuth 2.0 client ID is now built in, so "Log in with
browser…" is enabled out of the box and no longer has to be filled in by
hand after every update. The consumer is a PUBLIC client: the ID is not
confidential (it travels in the query string of every authorisation URL
the browser opens), and `clientSecret` stays empty on purpose - PKCE
replaces it. No secret is shipped in this plug-in.

Note for other users: until the consumer is approved by the Wikimedia
OAuth admins, only its owner can authorise it. Everyone else keeps using
username and password until then.

## Version 2.0.19 (July 2026)

**Search box and result list merged into one control.**

The depicts and created-during searches each used a separate query field
plus a result popup. Both are now a single editable `combo_box`: typing
runs the debounced live search (with the CirrusSearch fallback), the
dropdown holds the current hits, and PICKING a hit applies it to the
target field immediately - selection is detected by exact match against
the current item strings, which typed text cannot collide with because
of the trailing "(Q123)" marker. "⬅ Übernehmen" stays as a fallback that
never depends on dropdown events, and additionally accepts a hand-typed
bare QID ("Q640", "q640 # Kommentar") - pasting a known QID is now a
two-keystroke operation. The obsolete popup formatter, the choice
properties and the label lookup tables are gone; combo items are plain
strings, and QID + label are recovered from the selected string itself
(round-trip covered by tests, including labels that contain parentheses).

UNVERIFIED on a live Lightroom (combo_box behaviour is not measurable
headless): that bound `items` update while typing, and that picking an
item sets `value` and fires the observer. If either fails, the fallback
button still works off whatever the box holds. The dropdown also cannot
be OPENED programmatically - the SDK offers no such call - so the list
sits behind the arrow until clicked; what the merge saves is the second
field, the extra click on it, and the pick-then-confirm step.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.18 (July 2026)

Closes the two remaining audit items: the raw-pattern use in
ToolGenerateFromPersons and the broken utils.lua helpers.

**ToolGenerateFromPersons.lua.** The caption was built with
`des:gsub(fname.preName, '')`, feeding the FILE NAME into gsub as a
pattern. Measured with real names: parentheses or a '-' (as in
"Krichel (Cannes) 2026-1234") make the pattern silently miss its own
text, so the caption keeps the prefix it was supposed to lose; a name
ending in '%' raises "malformed pattern". The name now goes through the
new `u.escapePattern`. A second, unrelated crash sat a few lines up:
the pattern `"^(Benutzerin:"` had an unclosed capture and raised
"unfinished capture" for every parenthesized region name that was not
"User:…" (demonstrated in Lua 5.1). Now closed. A file-wide sweep found
no further variable-as-pattern uses; both search-and-replace tools
already escape their input correctly.

**utils.lua.** `u.join` could never have worked: it indexed `a[0]`
(Lua lists start at 1), called `table.unpack` (Lua 5.2+, nil on the 5.1
this plug-in runs on), removed the wrong element for the last delimiter
and concatenated an undefined global. It has no callers today; it is
rewritten to the semantics its documentation always promised, in 5.1.
`u.copyProps` crashed on a nil source (`prefs.generator` on a fresh
installation) and copied table values BY REFERENCE, silently aliasing
dialog state with stored preferences; it now guards nil and deep-copies
tables. `u.getNameParts` crashed on file names without digits or without
an extension; its parsing lives in the new pure `u.parseFileNameParts`
(nil-safe, standalone-tested), and the number is escaped via
`u.escapePattern` instead of a hand-rolled substitute. The dead
`u.searchAndReplaceTitle` (raw pattern, blind 4-character cut that
mangled ".jpeg") was brought in line with the corrected local version in
ToolSearchAndReplaceFilename.lua.

New standalone test file covering escapePattern, join, copyProps (deep
copy, nil source, stringsOnly, excludeKeys) and parseFileNameParts,
including the crash inputs above.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.17 (July 2026)

Code review pass (performance, security, aesthetics) over the recently
added code. Behaviour changes:

**OAuth loopback listener no longer trips over stray browser requests.**
The listener used to accept the FIRST GET request line arriving on the
port. A favicon.ico request or a speculative preconnect would have
aborted the login with "no authorisation code" while the real redirect
arrived a moment later. `parseRequestLine` now also returns the request
path, and the new `isCallbackRequest` helper only accepts a request to
the registered callback path that actually carries a code, error, or
state parameter - everything else is ignored and the listener keeps
waiting.

Smaller items from the same pass: the PKCE random source is seeded once
per module load instead of on every call (re-seeding twice within the
same second would restart the identical sequence); the three OAuth dialog
functions in the export service provider are proper locals instead of
globals; `require 'MediaWikiOAuth'` is hoisted to the file heads instead
of being repeated inside five functions; the SDC editor parses
description_all once instead of three times when opening; the
tests-only export hook in MediaWikiInit was dropped (the standalone tests
copy the functions verbatim and never needed it). Checked and found
clean: no token, secret, or Authorization header ever reaches the log;
the bearer header goes only to the configured wiki, never to the GitHub
version check; the metadata field audit (both call forms) passes.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.16 (July 2026)

**The two stores for depicts / created during are kept in step.**

These two values live in two places: the sidebar metadata fields in the
Metadata panel, and the `depicts=` / `created_during=` lines inside
`description_all`. At export time the sidebar field wins. The SDC editor,
however, only ever read and wrote `description_all`, so editing in the
tool after having filled in the sidebar meant the older sidebar value was
uploaded silently.

The editor now reads the same effective value the export would use (the
sidebar field if it holds anything, otherwise the wikitext line), says so
once in a dialog if the two disagreed, and on save writes BOTH stores -
including for every photo touched by the "distribute depicts" checkbox,
where the merged list goes to the sidebar field as well. After one pass
through the dialog the two representations cannot drift apart again.

**Version check no longer misses updates from revision 10 onwards.**

`MediaWikiInit.lua` compared version STRINGS with ">", so "v2.0.9" counted
as newer than "v2.0.15" - the '9' sorts after the '1'. Every update notice
was suppressed once a version part reached two digits. The comparison is
now numeric, part by part, with missing parts counting as zero, so "0.5"
and "0.5.0" still compare as equal (which is what the original comment
was worried about).

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.15 (July 2026)

Optional support for a CONFIDENTIAL OAuth consumer: the new constant
`MediaWikiOAuth.clientSecret` is sent as `client_secret` on both the
authorization-code exchange and the refresh request whenever it is
filled in. It stays empty for the intended public-client setup, where
PKCE replaces the secret. The token request body is never written to the
log.

## Version 2.0.14 (July 2026)

**Log in with a Wikimedia account (OAuth 2.0), no BotPassword needed.**

New module `MediaWikiOAuth.lua` implementing the OAuth 2.0 authorization
code flow with PKCE and a loopback redirect. The export dialog gained a
"Log in with browser…" button; while a token is stored for the wiki in
question, the username and password fields are ignored and no longer
required for export.

The plug-in is registered as a PUBLIC client - an installed application
cannot keep a client secret, so there is none, and PKCE (S256) takes its
place. The redirect URI is matched exactly by Wikimedia (unlike OAuth
1.0a there is no prefix mode), so the port is fixed at 8128 and the
spelling in `MediaWikiOAuth.redirectUri` must match the registration
character for character.

Tokens (access and refresh) are stored in the OS keychain via
LrPasswords, never in preferences and never in export presets. The access
token is refreshed automatically five minutes before it expires; the
`Authorization: Bearer` header is added only to requests aimed at the
configured API path, never to the GitHub version check.

Implementation notes from the empirical loopback probe (these are
measured, not assumed): LrSocket delivers a real TCP stream line by line,
one `onMessage` per line without CRLF, terminated by an empty string for
the blank line after the headers. In `receive` mode LrSocket acknowledges
every received line with "ok" on the same connection, which is what the
browser ends up displaying - the response page cannot be styled from the
plug-in. The login dialog therefore warns about the "ok" page beforehand
and reports success inside Lightroom instead.

`MediaWikiApi` gained `setAccessToken`, `addAuthHeader` and
`getLoggedInUser`. `MediaWikiInterface.prepareUpload` prefers a stored
token over username/password and verifies it against `meta=userinfo`
before the first upload, so an expired login fails with a clear message
rather than a wall of permission errors.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.13 (July 2026)

**Fuzzy Wikidata search in the SDC editor (ported from Cammello 0.11.7).**

The live search (depicts and created-during) used `wbsearchentities` only,
which is a prefix search and fails on word-order or ordinal variants
("78th Cannes Film Festival"). Now, whenever the prefix search returns fewer
than 5 hits, a CirrusSearch full-text query on wikidata.org fills the
dropdown up: `action=query&list=search` (namespace 0, titles ARE QIDs),
followed by one `wbgetentities` call for labels/descriptions (German
preferred, English fallback). Results are merged (prefix hits first,
deduplicated by QID, capped at 8) and the query is whitespace-normalized
before searching. All list/merge/extract logic is pure Lua and covered by
standalone Lua 5.1 tests; network or parse errors degrade gracefully to
whatever partial list exists.

**Commons category suggestions from depicts/created-during (P373).**

New button "Vorschlagen (P373)" next to the categories field in the SDC
editor: collects the bare QIDs from the depicts AND created_during fields
(inline "# comments" tolerated), fetches their P373 (Commons category)
claims in a single `wbgetentities` call - skipping deprecated and
non-value snaks, falling back to the English label where P373 is missing -
and merges the resulting names into the semicolon-separated categories
field (case-insensitive dedupe, existing entries untouched). Feedback
("n categories added", "nothing found", ...) is shown in a bound
static_text status line under the row - deliberately NOT via
LrDialogs.message from inside the async task, and NOT via a bound button
title (proven not to update). The suggestion is a suggestion: nothing is
written to the catalog until the dialog is saved.

No metadata field definitions changed; schemaVersion stays at 13.

## Version 2.0.12 (July 2026)

**Fixes: created_during (and creator/copyright/license) from the Wikitext
field were silently dropped when they carried an inline comment.**

Cause: the "# comment" stripping added in 2.0.7 was only applied to `depicts`,
not to the other four QID fields. A value like
`created_during=Q124692383 # Berlinale 2026` therefore reached
MediaWikiApi.wbEditEntity unstripped, failed its `^Q%d+$` validation, and the
claim was skipped without an error message - which is exactly why depicts
worked and created_during did not. All four QID fields (P170, P6216, P275,
P10408) now go through the same comment-stripping helper. Covered by tests,
including a regression test proving the old behaviour failed validation.

**Consistency/security review (same delivery):**

- Second crash candidate of the otherFields class found and defused:
  ToolGenerateFromPersons wrote image notes for multi-person photos into the
  undeclared 'otherFields' field - the tool would have aborted with the same
  "not declared" error as the export. The write was removed; the image-notes
  feature is disabled until the field is declared again (noted in the code).
- Full audit re-run: every get/setPropertyForPlugin call now targets a
  declared field; password masking, JSON-encoded wbeditentity, HTTPS
  enforcement and the removal of 'password' from export presets are all
  verified intact.
- .bak/.orig leftovers removed from the distributed package.
- 31 now-unused tooltip LOC keys remain in TranslatedStrings_de.txt on
  purpose - they are harmless and would be needed again if field tooltips
  ever return.

**Fixes the cluttered Synchronize Metadata dialog** (an extra, field-less
text line under every field).

Cause: 25 of the 26 fields packed BOTH the label and the help text into the
`title`, separated by `^n^n` ("Caption (en)^n^nA short description in
English"). That is a known Lightroom workaround - the SDK has no separate
tooltip attribute for metadata fields, so the long string in the provider
serves as the tooltip while the plug-in's own metadata sets supply the short
label. The Synchronize dialog does not use those sets, so it rendered the
whole string, producing a second line with no input field.

Fix: all 26 field titles are now the short label only (reusing the label keys
the metadata sets already define, so all German translations are in place -
verified). Trade-off, stated plainly: the long help texts in the Metadata
panel are gone. Keeping both is not possible in the SDK. No `version` bump was
needed - Lightroom refreshes the title from the provider (proven: "Wikitext"
already showed up correctly under the old label in the catalogue), so no field
values are at risk.

Also repaired: a broken indentation in the 'categories' field block.

**Fixes the export abort "Attempt to access property otherFields not declared
in Info.lua"** - a regression introduced in 2.0.10.

Cause: 2.0.10 added a per-file override that read the 'otherFields' property.
That field exists in the ORIGINAL LrMediaWiki (and therefore in old catalogs),
but this fork does not declare it in MediaWikiMetadataProvider.lua - the
Artwork / Object photo metadata sets were dropped along the way. Reading an
undeclared property is a hard error and aborts the whole export.

Fix: the per-file override was removed. "Other fields" is now purely a
batch-level field of the export dialog (as originally requested); its tooltip
and the German translation no longer promise a per-file override.

Audited at the same time: every get/setPropertyForPlugin call in the plug-in
was checked against the declared field list. No other access to an undeclared
field remains (the dynamic 'description_' .. lang access only ever resolves to
description_en / description_de, both declared).

## Version 2.0.11 (July 2026)

**Fixes the Windows catalog error "Could not upgrade your catalog for plug-in
metadata".**

Root cause (found by dumping the catalog's AgPhotoPropertySpec table): the
per-field `version` of `description_en` and `description_de` was declared as
`1` in MediaWikiMetadataProvider.lua, but the original LrMediaWiki already
registered these two fields with `version = 2`. Any catalog that had ever
seen the original plug-in therefore stores them at version 2 - and a plug-in
declaring version 1 is a DOWNGRADE, which Lightroom refuses with exactly that
message. It is NOT the `schemaVersion` and NOT the toolkit identifier: raising
schemaVersion to 22/23/500 changed nothing, and an empty catalog worked fine,
because it had no version-2 fields to conflict with.

Fix: `description_en` and `description_de` now declare `version = 2`,
matching the original. `schemaVersion` bumped 12 -> 13.

Side observation: the catalog also holds seven orphaned fields from the
original plug-in that this fork no longer defines (`source`, `author`,
`date`, `templates`, `otherFields`, `otherVersions`, `description_other`).
Orphaned fields are harmless - Lightroom ignores them.

**IMPORTANT before updating on a machine where the fields still hold data:**
per the Lightroom SDK, raising a field's `version` causes Lightroom to
discard that field's existing values. On the Mac these two fields are still
at version 1, so the bump to 2 may clear them. If you have content in
"Description (en)" / "Description (de)", run the converter tool
(Library > Plug-in Extras > Description fields <-> Wikitext) FIRST, so the
content is moved into the Wikitext field, which is unaffected.

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
   first hit is **preselected**, and "Übernehmen" (static title, proven)
   takes it over – the common case remains a SINGLE click. A direct click
   on a list entry cannot be implemented reliably in the LrView SDK: there
   is no list control, the selection observer was demonstrably unreliable
   (2.0.7), and bound button titles demonstrably invisible (2.0.8).
2. **Empty language rows hidden:** `visible` is now bound on the FIELDS of
   the caption rows instead of (only) the row – row containers have no
   non-layout properties of their own according to the SDK docs. VERIFY:
   control-level visible is still untested in this installation; if the
   empty rows are still visible, the fallback is to show all 12 rows
   permanently and remove + – please report back.

## Version 2.0.8 (July 2026)

1. **Search results as a clickable list in the dialog** (instead of a
   dropdown): after 0.6 s of typing rest, up to 5 hits appear as buttons
   directly below the search field ("Label – description (QID)"); **one
   click takes it over**. No "plus" button, no dropdown, no selection observer –
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
   with en/de/fr/it; "+ Sprache" reveals an **empty** slot, the code is
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
2. **+ Sprache adds up to 12 languages** beyond the initial 4
   (en/de/fr/it/es/nl/pl/ru/zh/pt/ja/uk) – replaced by free ISO code
   fields in 2.0.8.
3. **Click on a search result takes it over directly** (no "plus" button) via an
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
   visible, + reveals the fifth) – superseded in 2.0.7/2.0.8.
5. **New button "Captions -> Wikitext":** takes all filled captions as
   `{{lang|1=…}}` blocks to the beginning of the wikitext field
   (idempotent: identical blocks and duplicate languages are skipped); the
   captions themselves remain untouched as SDC labels.
6. **Rename: "Description (all)" is now called "Wikitext" everywhere** –
   set title "LrMediaWiki – Wikitext", field label, menu entry
   ("Description fields ↔ Wikitext"), tooltips, translation. The field
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
  "Edit Structured Data (SDC)").

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

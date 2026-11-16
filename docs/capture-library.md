# Saved capture Library

Save to Library stores the captured PNG and becomes Saved to Library; toggling it
off removes that saved item. Editing a saved capture replaces its immutable image
revision only after image/catalog commits succeed. Retake creates a new capture
identity and leaves the previous save intact. Closing the palette does not erase
committed saves.

Archive → View Saved Captures, command search or the Library's Media rail opens
a two-column collection combining Profile-owned captures and accessible OS media,
newest first. Search matches title, source address and original Space name.
Saved-capture previews expose navigation, title/date, Copy Image, Save, source
page/address and Delete. They export original PNG bytes, not thumbnails or a
recreated page.

## Storage and ownership

`CaptureLibraryStore` shares one owner per standardized directory/Profile. Its disk
actor serializes mutations and decoding away from the main actor. The catalog is
`Profiles/<UUID>/Captures/Captures.json`; immutable assets are
`Images/<revision UUID>.png`. Logical identity survives edits. Metadata retains
original Profile/Space, title/address, date, kind and actual pixel dimensions.

Write the PNG first, then atomically replace the catalog. Failure preserves the
old revision; stale save/delete tokens refuse. Corrupt/future catalogs are
preserved and block writes. Delete commits removal, removes the asset and attempts
catalog rollback if removal fails, reporting failure. Cleanup targets only
unreferenced UUID assets in the capture-owned Images directory after a valid load.

Delete revalidates after confirmation and synchronously reserves the original
normal Profile before disk work. Capture save/toggle uses the same reservation.
Profile removal cannot stage until that operation settles, and staged removal
refuses new writes. Reservations survive window/view retirement.

Explicit save transfers captured immutable bytes to durable storage; later page
navigation does not undo it. Renderer acquisition still uses exact native
document/window/Profile/geometry cancellation. Profile switch/closure retires the
view, owned sheets and previews; stale reads cannot update replacement views.
Saved capture files remain local after Profile removal, as stated in that dialog,
but another Profile cannot browse them.

## Scope and checks

Arrow selection, Return/Space preview, Command-C/Delete/Command-F/Escape and
preview left/right/Command-W operate on immutable IDs/revisions. Errors reflect
actual output results. Shared motion/focus lives in [capture motion](capture-motion.md);
context payloads and Messages/AirDrop actions live in
[capture editing](capture-editing.md).

`tests/CaptureLibraryTests.swift` covers real disposable PNG persistence, shared
ownership, revision replacement, stale/wrong-Profile refusal, exact-byte exports,
asset deletion and corrupt-data preservation.

## OS media discovery and access — CAP23

`ExternalMediaLibrary` shallowly discovers images/movies in Desktop, Downloads,
Documents, the configured macOS screenshot directory and user-added folders.
Overlapping roots are deduplicated. Hidden files, directories, packages, symlinks
and incomplete downloads are omitted. Files remain references to their originals;
they are not imported, moved, deleted or relabeled as saved captures.

Filesystem modification dates order files. Screen-capture attributes identify
screenshots; movie/download-origin heuristics do not establish a recording's
producer, so the UI says video. [Capabilities](capture-capabilities.md) separates
existing recordings from screenshot production and website live streams.

The empty-grid context menu, Shift-F10/Control-Return, accessibility Show Menu
and Manage Media Folders expose availability and folder management. Native folder
selection creates a read-only security-scoped bookmark only after actual readable
selection. Cancellation is not a grant; stale bookmarks need renewed selection.
Stop Showing This Folder removes its retained bookmark/items for this Profile;
OS-level revocation remains in macOS Settings. This is file access, not Screen
Recording permission.

Only visible clients keep observation active. One file-level FSEvents stream
covers every shown folder, including missing or unreadable ones, so a file that
appears, is written in place, gains the screenshot marker, is renamed or is removed
reaches Media within about a third of a second. Each event rereads just that file;
events for subfolders, hidden files and non-media names are dropped on the stream's
own queue. The stream replays from the moment its scan began, so nothing that
happens during a scan is lost. Media rescans everything only when macOS reports
dropped events, a shown folder itself appears, moves, disappears or changes
permissions, a volume holding one mounts or unmounts, or a person refreshes;
requests that arrive during a rescan fold into one more afterwards.

Nothing polls files on a local disk. App activation and a once-a-minute check
reread the screenshot location and whether each folder can still be opened, and
rescan only when one of those changed. Network folders are the one case events
miss, because macOS reports only changes made on this Mac; while one is shown, that
check rescans all folders once a minute. It does the same if the stream cannot
start. Last-client retirement cancels work, releases the stream and scopes and
clears results. Owned sheets, previews and thumbnail requests carry
window/generation. Cancellation settles once even if Quick Look never answers, and
late callbacks cannot restore retired work.

Folder size never costs the main thread. The disk actor keeps the sorted list, a
lookup index and a version; a rescan or event that changes nothing publishes
nothing, and a change hands Media the list and index together, so membership checks
are lookups. The grid compares that version instead of the list, then merges,
filters, sorts and diffs against what it shows on a background task. The main
thread applies only the difference as one batch of tile removals and insertions; a
file changed in place is removed and reinserted at its new position, and more than
200 changed tiles reload the grid instead. Selection follows its file, the scroll
position stays put, tiles under a still pointer resample hover, finished thumbnails
find their tile among the visible ones and preview navigation reads the planned
positions. Typing a search still rebuilds the grid immediately. Loading,
folder-access and error changes update only the message and status line.
**Loading Media…** appears for the first load and for refreshes a person starts
(Refresh, folder access and visibility); hiding a file removes just its tile, and
event, activation and once-a-minute rescans stay quiet.

File revisions include device/inode, size, nanosecond modification/change times,
kind and local-file state. Reads validate source/catalog/revision; no-follow file
reads verify before/after. Image clipboard bytes are bounded to 256 MiB. Save a
Copy streams to an exclusive sibling and renames after revalidation; source and
hard-link aliases refuse, preserving existing destinations on failure.

Quick Look, Open in Default App, Finder, Copy File/Image, Save a Copy and Hide
operate on the original file. Hide persists a path and never deletes. Cloud/dataless
entries stay visible but do not download automatically; unavailable actions report
why. Corrupt `MediaFolders.json` is preserved and refuses writes.

### Grid tile and hover

Cells have a radius-12 primary plate inset four points at rest, 5% fill and a
centered thumbnail capped at 120 points (cell width minus 20 in narrower grids).
Thumbnails rest at 95% scale. Files use white radius-2 paper and a subtle downward
shadow; captures use a two-point dashed white outline. Videos add a centered play
badge. Missing images use a radius-8 blank placeholder.

Hover/selection expands plate to the cell edge at 15%, grows the thumbnail to
100%, deepens the shadow and advances capture dash phase. One 0.18/0.8 spring
handles both directions; Reduce Motion snaps. A live scroll preserves existing
hover until pointer exit but refuses new hover until scrolling ends. Loss of key
status clears hover. Arrival of a thumbnail updates in place without losing state.
Only the drawn plate is interactive; its outer ring is grid space. Preview opens
from the drawn thumbnail rectangle. Increase Contrast adds the selected focus edge.

### Checks

`tests/ExternalMediaLibraryTests.swift` covers disposable shallow enumeration,
classification, aliases, same-path replacement, disappearance, hiding, source
configuration, bookmarks, unreadable/missing folders and corrupt preferences.
Its disk checks reread only the file an update names, ignore nested and outside
paths, and apply renames and removals. Native client checks cover event-driven
arrival, in-place writes, a later screenshot marker, renames and removals, shutdown,
a quiet rescan that publishes nothing and a new file that publishes the list exactly
once without a loading flip. Library view checks cover thumbnail geometry, hover,
scrolling, selection, source rectangles, mixed capture/file navigation, a loading
flip that leaves the grid alone, and arrivals, in-place changes, renames and
removals that make at most two tiles while selection, scroll position and hover
stay correct. `tests/CaptureLibraryCatalogSkip` pins the skip, off-main planning
and event structure; `scripts/test.sh` runs both Media checks.

## Private Media ownership

Private Media opens the originating normal parent's existing catalog only when
selected. Source-page actions still use the actual private tab and off-the-record
window. The view validates its original parent/private context and closes on
parent removal.

Each private window keeps an independent in-memory folder configuration seeded
from the parent. Grants, visibility and hidden-file changes last only in that
window and never write the parent's preferences. Explicit private capture save
writes its immutable PNG/source metadata into the original parent's Library,
using neutral Space identity and Incognito label. The capture retains its original
private native lease and the same removal reservation described above.

Private windows deliberately have no documents. They do not create, open or
browse Notes and Easels, the private Library shows no documents, and a private
capture is never sent to a new or existing Easel. A private document store could
write private-browsing traces to disk, and an Easel's embedded pages could mix
private and normal sessions. Private captures still copy, share and save to the
Library, labelled Incognito, as described above.
Library/document commands retain the exact focused browser and native security
admission rather than redirecting auxiliary-window actions to another browser.

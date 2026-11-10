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

Only visible clients keep observation active. Vnode events coalesce directory
writes/deletes/renames; app activation and a five-second active-view refresh catch
content-only changes, permissions and screenshot-location changes. Last-client
retirement cancels work, releases watchers/scopes and clears results. Owned sheets,
previews and thumbnail requests carry window/generation. Cancellation settles once
even if Quick Look never answers, and late callbacks cannot restore retired work.

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
Native client checks cover vnode arrival/removal and shutdown. Library view checks
cover thumbnail geometry, hover, scrolling, selection, source rectangles and
mixed capture/file navigation.

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

Private windows cannot create or open Notes/Easels, browse the document Library,
or send a capture to a new or existing Easel. Those commands are disabled; the
backend’s off-the-record page support does not provide a private document store.
This remaining document workflow is tracked under WIN11 in [the backlog](backlog.md).
Library/document commands retain the exact focused browser and native security
admission rather than redirecting auxiliary-window actions to another browser.

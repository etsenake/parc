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

Media keeps observing while its Library is open, even while another Library page
shows, so coming back needs no rescan and the grid never empties and refills.
Closing the Library or its window stops it. One file-level FSEvents stream
covers every shown folder, including missing or unreadable ones, so a file that
appears, is renamed or is removed reaches Media within about a third of a second,
and so does a file's first in-place write or screenshot marker after a quiet second.
Each event rereads just that file; events for subfolders, hidden files and non-media
names are dropped on the stream's own queue. The stream replays from the moment its
scan began, so nothing that happens during a scan is lost. Further changes to a file
that changed within the last second wait until it has been quiet for a second, so a
file still being copied settles into one or two tile updates instead of several a
second; a change in iCloud availability never waits. Media rescans everything only when
macOS reports dropped events, a shown folder itself appears, moves, disappears or
changes permissions, a volume holding one mounts or unmounts, or a person
refreshes; requests that arrive during a rescan fold into one more afterwards.

Nothing polls files on a local disk. While Media is shown it observes the macOS
screenshot location setting, so a new location chosen in the Screenshot app is
picked up at once. App activation and a once-a-minute check reread that location
and whether each folder can still be opened, and rescan only when one of those
changed. Network folders are the one case events
miss, because macOS reports only changes made on this Mac; while one is shown, that
check rescans all folders once a minute. It does the same if the stream cannot
start. Last-client retirement cancels work, releases the stream and scopes and
clears results. Owned sheets and previews carry window/generation; leaving Media
closes them. Cancellation settles once even if Quick Look never answers, and
late callbacks cannot restore retired work.

iCloud download status has its own source. While Media is shown, each shown folder
that iCloud syncs (usually Desktop and Documents) gets one folder-level file
presenter, however many files it holds. macOS tells that presenter when a file
inside is evicted or finishes downloading, and by then the file is already in its
new state, so Media rereads just that file and its tile changes at once without
waiting to settle. Reports for subfolders, non-media names and files Media isn't
showing are dropped, and new arrivals are covered without registering anything.
Presenters are released when Media closes or a folder stops being shown or synced.
A presenter on a single file would make Remove Download fail for that file with
"in use by an application", while a folder presenter lets both a file and the whole
folder be evicted. If macOS ever asks the folder presenter to step aside for an
eviction, it unregisters and returns with the next rescan or catalog change, while
the folder's file events keep reporting its files. A Spotlight metadata query
cannot do this for Parc: download status appears only in iCloud query scopes,
which need an iCloud container entitlement Parc does not carry.

Folder size never costs the main thread. The disk actor keeps the sorted list, a
lookup index and a version; a rescan or event that changes nothing publishes
nothing, and a change hands Media the list and index together, so membership checks
are lookups. The grid compares that version instead of the list, then merges,
filters, sorts and diffs against what it shows on a background task. A newer change
cancels a calculation still in flight and plans again from the newest lists. The main
thread applies only the difference as one batch of tile removals and insertions; a
file changed in place is removed and reinserted at its new position, and more than
200 changed tiles reload the grid instead. Selection follows its file, the scroll
position stays put, tiles under a still pointer resample hover, finished thumbnails
find their tile among the visible ones and preview navigation reads the planned
positions. Typing a search still rebuilds the grid immediately. Loading,
folder-access and error changes update only the message and status line.
**Loading Media…** shows on opening until both saved captures and the first folder
scan are in, so the grid appears whole instead of files popping in around
captures, and for refreshes a person starts (Refresh, folder access and
visibility); hiding a file removes just its tile, and event, activation and
once-a-minute rescans stay quiet.

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

The grid's own layout sizes its two square columns from the width it is laid out
at, so narrowing from the wider Spaces page resizes the tiles instead of stacking
one tall column. Tiles never outgrow the visible width, and an always-shown scroll
bar has its width reserved whenever the grid is taller than the page, so tiles
never jump as it comes and goes. Cells have a radius-12 primary plate inset four
points at rest, 5% fill and a
centered thumbnail capped at 120 points (cell width minus 20 in narrower grids).
Thumbnails rest at 95% scale. Files use white radius-2 paper and a subtle downward
shadow; captures use a two-point dashed white outline. Videos add a centered play
badge. Missing images use a radius-8 blank placeholder.

Hover/selection expands plate to the cell edge at 15%, grows the thumbnail to
100%, deepens the shadow and advances capture dash phase. One 0.18/0.8 spring
handles both directions; Reduce Motion snaps. A live scroll preserves existing
hover until pointer exit but refuses new hover until scrolling ends. Loss of key
status clears hover. Arrival of a thumbnail updates in place without losing state.
The 128 most recently shown thumbnails stay cached while another Library page
shows, and opening a preview never drops loads in flight. A tile filled while Media
was hidden, or whose load was cut short, loads when Media shows again; closing the
Library releases them all.
Only the drawn plate is interactive; its outer ring is grid space. Preview opens
from the drawn thumbnail rectangle. Increase Contrast adds the selected focus edge.

### Checks

`tests/ExternalMediaLibraryTests.swift` covers disposable shallow enumeration,
classification, aliases, same-path replacement, disappearance, hiding, source
configuration, bookmarks, unreadable/missing folders and corrupt preferences.
Its disk checks reread only the file an update names, ignore nested and outside
paths, apply renames and removals, and hold a growing file until it settles while
arrivals, removals and changes after a quiet spell apply at once. Native client
checks cover event-driven arrival, in-place writes, a later screenshot marker,
renames and removals, a slowly copied file landing in at most two updates, shutdown,
a quiet rescan that publishes nothing, a new file that publishes the list exactly
once without a loading flip, and a screenshot location change picked up without
activation. An injected iCloud source checks that download status is watched with
one presenter per shown iCloud folder, even for a folder of 3,000 files, that
evictions and downloads reread just that file and publish once, that arrivals add no
presenters and are still covered, that a rescan finding nothing new still
re-presents the folder, that reports for files Media doesn't show change nothing,
and that closing Media or hiding the folder stops watching and ignores late
reports. The real presenter is checked with coordinated writes: it registers once
per registered folder path however many files it holds, reports a direct media
child under the spelling its folder was registered with, ignores nested and
non-media files, and releases everything when the source is dropped; asked to make
way for an eviction, it unregisters and comes back with the next present. The
latest-wins planner checks that a newer or forced rebuild cancels the calculation
in flight. Library view checks cover thumbnail geometry, hover, scrolling,
selection, source rectangles, mixed capture/file navigation, a loading flip that
leaves the grid alone, and arrivals, in-place changes, renames, removals and iCloud
status changes that make at most two tiles while selection, scroll position and
hover stay correct. `tests/MediaLibraryGridTests.swift` checks, without a window,
that the grid keeps two columns sized to its width as it widens, narrows, gains
items past the page height or switches scroll bar style, and that thumbnails filled
while hidden load on return while loads answering after the Library closed cannot
land. `tests/CaptureLibraryCatalogSkip` pins the skip,
off-main and cancellable planning, settling, iCloud status, event structure and
how pages suspend and resume; `scripts/test.sh` runs these Media checks.

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

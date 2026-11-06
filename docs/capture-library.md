# Saved capture Library

After capturing a page, **Save to Library** stores the real captured PNG and changes to **Saved to Library**. The toggle removes that saved item when turned off. An edited, already-saved capture updates the same logical item only after the replacement PNG and catalog commit succeed. Retake starts a new capture identity and leaves the previous saved item intact. Closing the capture palette does not erase a committed save.

Open **Archive → View Saved Captures**, use command search for that registered command, or choose **Media** in the Library rail. Media combines saved captures from the window's current profile and actual media files in accessible OS folders, newest first, in a two-column image grid beside the live page. Search matches title, source address and original Space name. Selecting a saved-capture thumbnail opens a larger preview with previous/next controls, date/title, Copy Image, Save, Open Source Page, Copy Source Address and Delete. Saved-capture copy and export use the original PNG; the displayed thumbnails and fitted preview are downsampled from those bytes. Opening the source is a separate user action and never recreates the screenshot from a URL.

The collection supports ordinary arrow selection, Return/Space preview, Command-C, Delete, Command-F and Escape. The preview supports left/right, Escape, standard Command-W and Command-C. Menus and controls operate on the selected item ID and immutable revision. The normal Save sheet and confirmed Delete report actual failures. CAP24 supplies source-thumbnail transitions, interrupted-close/Reduce Motion handling and guarded native focus return through the [shared capture motion contract](capture-motion.md).

## Storage and ownership

`CaptureLibraryStore` shares one owner per exact standardized directory path/profile. Its key stays stable when the first save creates the directory and Foundation adds a directory hint to its URL. Its disk actor serializes mutations and image decoding away from the main actor. The catalog is `Profiles/<profile UUID>/Captures/Captures.json`; original PNG revisions are `Images/<revision UUID>.png`. A logical UUID survives crop replacement. Metadata includes original profile and Space identity/name, original page title/address, capture date, region/viewport/full-page kind and actual pixel dimensions. No thumbnails, page requests or cloud placeholders are persisted in place of the image.

The immutable PNG is written first; atomic catalog replacement commits the revision. A failed save preserves the old catalog/image. Replacement and confirmed deletion reject stale revision tokens. Corrupt or unsupported catalogs are preserved and refuse writes. Deletion commits removal, removes the actual asset, and attempts catalog rollback if removal fails; failure is reported. Unreferenced UUID-named assets from interrupted writes are cleaned after a valid catalog load or mutation. Only the capture-owned Images directory is eligible. A catalog load failure never starts cleanup.

Media preview and Library flyout deletion recheck the original item and owner after confirmation, then reserve that exact normal Profile synchronously before starting disk work. Private Media uses its original parent store; window or view teardown does not release an in-flight reservation. Profile removal cannot stage until deletion succeeds or fails, and a pending removal refuses a new deletion. This protects saved-capture deletion, not external media files, which Media does not delete.

The capture's native lease is checked at the explicit save action. That action transfers immutable captured bytes into durable storage; a subsequently closed/navigated page does not silently undo the user's save. In-flight renderer capture still follows the native original document/profile/window/geometry cancellation contract. The Library itself never creates a native page. Profile switches/window closure remove its view and cancel its preview and exact owned output sheets; stale image reads cannot update a replacement view. Source-page navigation goes through the existing same-profile Library opening callback. Saved files remain on this Mac when a profile is removed, matching the existing treatment of user-created Easels; the profile removal sheet states this. They are no longer browsable under a different profile.






## Scope and checks

The original slice implements saved browser captures. CAP23 adds broader OS-media discovery and permissions below; richer editing/context and motion remain their fixed family rows. Excluded cloud sharing stays excluded. The [CAP22 capability contract](capture-capabilities.md) establishes that existing filesystem movie classification is separate from the screenshot producer and website recording indicators; CAP23 owns the external-media consumer. This slice does not implement recording, Portrait framing, an element-target lens, iMessage or cloud sharing.

`tests/CaptureLibraryTests.swift` exercises the real store with generated PNG pixels and a disposable directory: persistence/reopen, shared ownership, immutable revision replacement, stale save/delete refusal, wrong-profile refusal, invalid-image preservation, exact-byte export, real asset deletion and corrupt-catalog preservation. It is a reusable component check, not a browser or appearance test. The production-store check passes, including shared ownership before and after first directory creation and explicit directory URL hints. The combined 55-file app compiler check passes with zero diagnostics after source review. No functional browser test, integrated engine build or appearance acceptance is claimed for this slice.

## OS media discovery and access — CAP23

Media also includes actual image and movie files directly in Desktop, Downloads,
Documents and macOS's configured screenshot folder (`com.apple.screencapture`
`location`, expanding `~`, with Desktop as the fallback). Overlapping source
paths are deduplicated. Enumeration is deliberately shallow: hidden files,
directories, packages, symlinks and unfinished download filenames are not media
items. Browser captures retain their separate profile-owned PNG catalog and
immutable revision model. Files are references to the originals, never imported
into that catalog, moved, deleted or relabeled as captures.

The common two-column grid combines captures and files newest first, with stable
path/UUID tie-breaking and search over their real metadata. File dates use the
filesystem modification date. Screenshot classification uses the OS screen-capture
screen-recording heuristic; that does **not** prove which application produced
it, so the interface calls these files videos. See the separate
[recording capability contract](capture-capabilities.md).

Regular Media uses the shared Library search header at the measured 8-point
and no “Files remain in their original folders.” line, so neither is shown. A
bottom status line appears only when a folder needs access or a file action
fails. A failure stays until the next search edit, menu or item command, or the
Media presentation closes, rather than disappearing with the refresh that follows
it. The folder-source menu opens
from a right-click on empty grid space or on the empty-state message. From the
keyboard, Shift-F10 or Control-Return opens it (Option forces it while an item
is selected), as do accessibility Show Menu and the "Manage Media Folders"
action. It shows each source's actual availability, permits a genuine native
folder selection to grant access, and provides Refresh, Add Media Folder, Stop
Showing This Folder, Show This Folder, Show Hidden Files Again and the macOS
Files and Folders privacy settings route. The application never treats opening
Settings or closing the picker as a grant. A selected readable directory gets a
read-only security-scoped bookmark. Cancel leaves preferences unchanged. A stale
or unusable bookmark requests renewed selection; unavailable folders stay
explicit while other sources continue. Disabling a source removes its retained
bookmark and visible items for this profile; system-wide revocation belongs to
macOS Settings. The package supplies Desktop/Documents/Downloads usage text.
This is file access, not Screen Recording permission.

### Grid tile and hover

(continuous radius 12, 5% fill) sits 4 points inside the cell. The thumbnail is
scaled to fit inside a 4-point border within a centered 120-point frame, drawn at
95% at rest. Image and video files sit on white paper (continuous radius 2) with
a black shadow: 10%, radius 1, 1 point down. Saved captures have no paper; a
dashed white 50% outline (2 points, round caps, 5-point dashes) runs inside the
border. Videos add a centered `play.fill` badge: 22-point bold, white 95%, with a
black 20% radius-1 shadow 1 point down. A missing or unreadable thumbnail shows a
blank placeholder (continuous radius 8, `primary` 5%). It fills the whole
thumbnail frame, at the same cap as the frame and never scaled to 95%.

A tile is highlighted while hovered or selected. Highlighting moves the plate to
the cell edge at 15% and grows the thumbnail frame to 100%. The paper shadow
deepens to 20%, radius 5 and 3 points down, and the capture outline's dash phase
moves one dash. Every change runs on one `spring(response: 0.18,
dampingFraction: 0.8)`, entering and leaving; it settles in about 0.2 seconds. A
reversal starts from the current presentation value. A live scroll keeps a
highlight that is already shown until the pointer leaves the tile, but refuses
new hovers. When the scroll ends, the tile under the pointer highlights. Hover
and clicks land only on the plate's current shape. At rest that is its rounded
rectangle inset 4 points, so the cell's outer ring and corners belong to the
effect, rotation, offset or z-order change here. The highlighted tile, with its
shadow, never leaves its cell, so neighbors never overlap or clip it. The preview
opens from the tile's drawn thumbnail, excluding the paper border.


  configuration with `renderAs` thumbnail and `imageSize` 120×120 (global
  movie-conforming file is video, an image-conforming file is image, otherwise
  unknown. It passes `isSelected` and `isScrolling` to `ContentCell`'s
- `ContentCell` keeps `_isHovered`/`_shouldHighlight` state. Highlight

  It has no `contentShape`, so hover and taps follow the drawn plate. The hover
  hover value, or to false while scrolling, so leaving during a scroll clears it.
  re-highlights a still-hovered cell when it ends.
  120×120. For a video, the badge is the top layer. Its `ShadowStyle`
  `Image(nsImage:)`, resizable, low interpolation, `scaledToFit`
  highlighted. It ends in the same spring keyed on `isHighlighted`. Predicate
  with `ShadowStyleViewModifier` black 0.2/0.1, radius 5/1, offset height
  downward. A capture gets `strokeBorder` white 0.5, line width 2, round cap,
  filled `primary` 0.05. It is not animated.

Adaptations: Parc keeps its flexible two-column grid. The 304-point Media page
state instantly under Reduce Motion, following its own convention for motion
selection border is removed. A 1-point focus border remains on the selected plate
only under Increase Contrast, like the Downloads rows. Shadow offsets follow the
backing layer's real orientation, so they fall downward however AppKit flips the
tile's layer. Hover tracking is limited to the key window, as in the Downloads
rows, so losing key status clears hover. The page owns the live-scroll state, as
configured and on each scroll start or end, so a tile laid out mid-scroll still
refuses hover. Leaving its window clears that state, because a scroll
interrupted by removal may never post its end. A tile resamples the real
pointer when it is configured, when it
enters a window, when a scroll ends and when key status changes. An arriving
thumbnail updates its visible tile in place, so selection and hover survive. The
play badge's shadow is drawn into its image with an `NSShadow`: black 20%, blur
2, 1 point down. A measured `NSShadow` blur of 2r matches a `CALayer` shadow
radius of r, so this equals the layer shadow without an offscreen pass. A click
or right-click on a cell's ring is treated as grid space: no selection, and the
folder menu.

The Media tile checks in `tests/DownloadLibrary/ViewTests.swift` (run by
`check-view.py`) drive the real grid with generated files and a saved capture.
They cover:

- resting and highlighted plate, paper, shadow, outline and aspect-fit geometry;
- the video badge and the placeholder;
  on hidden layers;
- the plate-shaped hover and click area, and ring clicks and menus;
- scroll keeping and clearing a hover, tiles laid out mid-scroll, and
  re-highlight after scrolling;
- key-window loss and selection;
- a thumbnail arrival keeping the selection and the hover;
- the preview's open-from rectangle;
- the search placeholder surviving a theme change.

`ExternalMediaLibrary` shares one source owner per exact profile capture-directory
path, independent of `CaptureLibraryStore`. Only visible Media clients keep its
observation active. Native vnode events coalesce directory writes/deletes/renames;
app activation and a five-second active-view refresh also catch content-only
changes, OS permission changes and screenshot-folder preference changes. The last
client leaving cancels work, releases watchers/security scopes and clears results.
Folder selection and save sheets belong to the exact Library window and generation.
Profile change, window closure and section retirement cancel those owned sheets,
previews and thumbnail requests. Cancellation resolves its own Swift continuation
once, even if Quick Look never returns a cancellation callback; late callbacks
cannot restore retired items or scopes. Mixed capture/file previews use one grid
order, and arrivals/removals refresh both owners’ navigation. Clipboard commits
revalidate the originating generation after their asynchronous read; other windows keep their own client and output ownership.

External file identity is its standardized path. Each offered revision includes
actual device/inode, size, nanosecond modification/change times, media kind and
local-file state. Reads validate the current catalog, configured source and actual
file revision; original-byte reads use a no-follow descriptor and verify before
and after. Image clipboard data is bounded to 256 MiB. Save a Copy streams the
original revision to an exclusive temporary sibling and renames only after the
source still matches, preserving an existing destination if the source changes.
It refuses the source and hard-link aliases. These guards do not pretend external
files are immutable after control passes to another application.

Files use the existing native Quick Look preview owner, with a default-preserving
`itemName` argument for Media labels. Open in Default App, Show in Finder, Copy
File, Copy Image, Save a Copy and Hide from Media operate on that original file.
Hide is persisted by path and never removes the file. Cloud/dataless entries stay
visible but do not automatically materialize: Show in Finder permits the user to
download them; preview/copy/export report unavailability until local. Thumbnail
failure remains an unavailable image, never substituted screenshot pixels.
Corrupt `MediaFolders.json` is preserved and refuses writes. Scoped grants and
hidden paths are profile preferences; ordinary saved captures stay intact.

### Retained reference and adaptations

via the recovered-component, type, xref and annotated-function helpers. No heavy
decompilation or second-version recheck was necessary.

  contain Downloads, Desktop, Documents and screenshots/recordings. Resolver
  package-descendant and subdirectory-descendant skip options. Item builder
  `kMDItemWhereFroms`, then movie type conformance. Parc's public xattr reads are
  delete/write/rename events, separate no-permission/no-descriptor failures and
  permissions from an empty media collection.
  setup/teardown, subscription reconfiguration, file reveal/copy/open/hide and
  capture-specific delegates. `LibraryDataClientImpl` retains independent
  file-query and capture clients. Those ownership boundaries remain separate.

Profile-specific permission preferences, native bookmark-grant controls, the
five-second content refresh, revision guards, exact-byte export, conservative
symlink/cloud handling and current Quick Look reuse are explicit Parc adaptations.
pixel-matched; CAP24 owns shared motion/focus/AX integration, and CAP21 retains
richer editing/context variants. The shared Quick Look API defaults remain
unchanged for Downloads.

### Checks

`tests/ExternalMediaLibraryTests.swift` uses only generated disposable files. It
covers shallow enumeration and overlapping roots, xattr/type classification,
real exact-byte export, source/hard-link overwrite refusal, same-path replacement,
file disappearance, persistent hiding without deletion, source disable/re-enable,
bookmark encode/reopen, unreadable/missing sources and corrupt-preference
preservation. Its active-client checks exercise real vnode arrival/removal and
last-client shutdown, without a browser or real home-folder scan. Shared preview
order covers interleaved captures/files and live neighbors; action-generation
refusal and thumbnail cancellation without native callbacks are covered too. Existing saved
capture persistence/revision checks also pass. The offline packaging fixture's ten
checks pass with the three folder usage descriptions. Final whole-module SIL
passes in 32 seconds with zero diagnostics. Receipts and annotated helper output
are in `work/capture-coordination/cap23-*` and
`work/claude-split-checks/cap23-source-final.{json,log}`. Native OS prompt acceptance,
Quick Look movie playback, cloud downloading and browser runtime were not executed
or claimed by these permitted component/compiler checks.

Independent exact-source review cleared the complete CAP23 implementation after
fixing mixed-order navigation/live neighbors, post-read clipboard generation and
explicit thumbnail cancellation. No runtime acceptance is inferred from that
code review or the compiler/component results.


CAP21 adds the captured-item iMessage/AirDrop and source-action variants to both
the grid context menu and preview More menu, with immutable revision and view
generation guards. [Capture editing and contexts](capture-editing.md) records the
distinct recovered payloads, cancellation and lifetime boundaries. External-file
contexts and permissions remain under the CAP23 owner described above.

## Private Media ownership

per-window Home registry before the incognito exclusions for Spaces and
on-disk profile partitioning.

Parc lazily opens the originating normal parent profile's existing Media
catalog only on Media selection. Its private tab model and off-the-record
native window remain the source of any Open Source Page action. The view
revalidates the original parent and private context before actions and closes
when the parent is removed. Parent-profile directory partitioning is a Parc
adaptation. Each private window seeds a separate in-memory folder configuration
from the parent; folder grants, visibility and hidden-file changes survive
reopening Media in that window but never write the parent configuration or
affect other windows. Private Easels and Notes and capture-to-Easel remain
unfinished WIN11 work. No browser functional test
or private appearance comparison is implied by this source change.

The private Media increment passed 440 actual Library-view, 39 selection, 44
entry/provider and 230 Library-entry inert assertions. A stale sidebar source
assertion was corrected and all component source assertions then passed on the
reconciled tree. The independent reviewer cleared the final source; these checks
are not browser-runtime acceptance.

The private preference projection passes the disposable external-media component,
including independent window configurations, parent-byte preservation, folder
grants and a missing manifest. No browser functional test was run.

A private capture can explicitly save its captured PNG to the originating
parent profile's existing Library. The original off-the-record page, window,
profile and capture lease remain the source, and the original parent must still
be available at admission. Since the private window has no persistent Space,
the saved capture uses a neutral Space ID and the label “Incognito” instead of
persisting its ephemeral Space identity. This metadata mapping is a Parc
adaptation; the explicit Save transfers the image and its source metadata to
the normal local catalog. Private capture-to-Easel remains unfinished.
The parent store reserves each capture save or toggle deletion before the disk
actor starts. Single and bulk profile removal cannot be staged until that
operation finishes; a staged removal cannot acquire a new reservation. The
operation retains its reservation across capture/window teardown and releases
it after success or failure.
The production destination was exercised with disposable parent/private stores
and known PNG bytes, including wrong-parent refusal and no private Easel
provider call. The profile-removal model passes 44 assertions, including held
write, bulk staging, completion and failure ordering; capture destinations pass
55 and the inert capture overlay passes 45. The whole-module Swift typecheck
passed with zero diagnostics; browser behavior was not tested.

Library and document menu actions now resolve the focused browser or its exact
owned command/history child and require the original native window's security
admission. Child dismissal rechecks that window and Profile before dispatch.
Easel menu entries retain their originating window and Profile; an auxiliary
window cannot redirect an old selection. The explicit New Note action can still
corresponding Library and document selectors are implemented by its main
window controller. No browser or native-input acceptance is claimed.

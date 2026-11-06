# Sidebar split groups and original-tab drops

A split is a persistent container with an opaque ID, ordered original tab IDs, orientation, pane proportions and a sidebar anchor. The sidebar presents one split cell ([SP30](#split-cell-container--sp30)), retaining each child's title, original page selection, close/capture controls, context menu and accessibility actions; the whole cell is the split's one drag source. Selecting a child activates the complete available group and focuses that original child. Native selection callbacks and positional keyboard traversal use the same membership.


## Reference contract


- `SidebarItemData.splitView` is a genuine typed item. `SidebarSplitViewData` holds member proportions, orientation, last activity, optional custom information and focused item ID. `SidebarUI.SplitViewCellState.LayoutStyle` distinguishes `childItems` and `customInfo`.


## Ownership and cancellation

The pasteboard contains an opaque drag ID. Authority remains in the original `SidebarTabRow` source object and its one-shot `SidebarSplitDrag`; arbitrary text or another window's drag cannot authorize a page change. Admission and commit require the exact window, active profile and Space, current selected group/focus, saved group state, original pane/wrapper/native page identities and normal native security availability. Closing, transferring, retiring, Peek, popup, modal/fullscreen and unavailable page contexts are refused. A profile pending removal cannot commit.


An already materialized child keeps its same wrapper and page. A saved child without a live wrapper follows normal saved-tab materialization only after a successful selection transaction; this is not replaying a live navigation or copying an existing document. A replaced or separated page is kept alive. No drag action supplies consent to unload a page.

## Persistence and explicit adaptations

Parc previously cached overlapping arrays of pane IDs. Typed sidebar containers require exclusive membership: an ordinary tab belongs to one split per Space and a Favorite to one split per Profile, because a Favorite split is one topApps item with one `SidebarSplitViewData` layout ([split containers](#split-containers-and-saved-home-membership--sp21)). On migration, the selected group wins, then the most recently stored non-overlapping membership; surviving multi-child groups keep their relative weights. Original tabs are retained. Legacy groups receive IDs and anchors that are immediately persisted; ordinary group IDs survive pane replacement, reorder, resizing, archive provenance and restart.




Source compilation and model/window/keyboard component checks are recorded independently from browser behavior. No functional browser test or matched runtime appearance claim is made for this batch.


## Split containers and saved-home membership — SP21

container: Today, a pinned root or folder, or the profile's Favorites (topApps).
layoutOrientation, timeLastActiveAt, customInfo, focusItemID) is the split's only
geometry. Parc stores the container on every child record, so every child of a
group now shares its anchor's placement, and `SplitMembership`
(`Sources/ParcCore/OriginalSplitDrop.swift`) is the one owner of joining,
leaving and migration.

**Favorite splits are Profile-wide.** A Favorite split is one topApps item, so it
has one layout in every Space of its Profile. Resizing or reorienting it from any
Space edits that one record; a Favorite belongs to at most one split per Profile
(`reconcileSplitLayouts`). Commit `1d18351` made Favorite groups Profile-wide but
left `testSavedSplitLayoutsAcrossSpacesAndRestart` expecting per-Space layouts,
which aborted BrowserStoreTests at line 990 from then on; the test now asserts
the one layout across Spaces and restart.


- Saved members newly joining the split leave a fresh copy in their exact parent
  Note/Easel editor join the split. A saved child taken from another split
  leaves its home in that split.
  at +0x4a and +0x4b are `isItemBeingAdded` and `moveFromOriginalLocation`
  (after the 9-byte `windowContentSetupOptions` at +0x40 and
  `allowReparentingWindowContent` at +0x49). The first exempts the item a
  creation just added; the second skips every copy. The sidebar drop
  `WindowAction.openItemsInSplitView` (case 104) carries a caller-chosen
- An existing split keeps its container: the existing children are subtracted
  added to a Favorite split becomes a Favorite child; one added to a pinned split
  enters its folder.
  remains, the strategy is `relative(targetID: first, .after)` (tag 1, location 1
  anchors the new Today split at that first ordinary member, which is the same
  slot once the member moves in, or places it at the top of Today.

**Leaving a split** follows the sidebar side of
the removed children from the split's child list. With two or more left,
`relative(targetID: split, .after)` (w4 = 1, w5 = 1) and prunes the split data
to Separate, pane Close, Close Split, replacement of a pane and a member taken by
another split (`SplitMembership.preservingSlots`): the split keeps its slot even
when its anchor leaves, a departing child follows it, and a dissolving split is
replaced by its children in child order. A child separated from a Favorite split
becomes a Favorite tile right after the split.

**Routes.** The sidebar and folder-preview Open in Split View, Favorite Option
release (including the focused-Favorite duplicate, placed at the top of Today
Add Split results (Favorites are now admitted), sidebar-tab drops, external URL
drops and Peek promotion all use the one transaction. App routes fix fresh home
IDs, validate typed Note/Easel homes as aliases of the same live document
(`resolveSidebarCopyDestinations`) and open fresh web homes in the background
after the durable commit, as the shouldOpen option requires. Created tabs are

item. Pin/Unpin on a split pane therefore moves the whole split; `setKind`
changes every child together. A window re-forming its own split that the shared
model no longer holds, and a divider change on a selection without its split,
form it through the same membership owner; a remembered selection that a split
change made stale shows the split holding its first page instead of forming a
new split that takes members from others.

**Favorite splits from any Space.** Readers resolve a split by identity among
the splits visible from the current Space (closing a pane, the split cell's
Close, Undo/Reopen regrouping, the recent-item switcher and folder-removal
return), so a Favorite split behaves the same from every Space of its Profile.
When the Space that stores a Favorite split moves to another Profile, the split
moves to another Space of its own Profile first and survives.

**Migration.** Restored sessions take the one-container form without losing a
page or saved item. A Favorite that several splits held keeps one split: a
split in the Favorites container first (so no Favorite leaves a topApps split
and the tray gains no root), then the displayed split, then the most recent;
the others keep their remaining children, layout and appearance. Overlapping
groups then resolve as before (active, then most recent; Favorites per Profile,
so per-Space copies of the same Favorites become one split). Each remaining group keeps its anchor's container, so it stays where the
sidebar showed it; a child from another container enters it, and a saved child
keeps a fresh home in its exact former slot, the existing-container branch of
remembered selections, and the active selection when it is another Space's, to
its home. The result is written back at load.

**Removed adaptations.** The per-child anchor policy (children kept their own
section and folder and separation "revealed" it), per-Space layouts for the same
Favorites, the refusal of mixed Favorite/ordinary groups and of Favorite Add
results, and an existing pinned split admitting Today children without moving
them are gone.

**Parc adaptations kept.** Fixed fresh home IDs, typed-alias validation, one
atomic publication, other Spaces' selection repair and the twelve-root tray cap
(refusing only growth past twelve) remain Parc ownership rules. A new split whose
first ordinary member was itself inside another split goes to the top of Today
instead of inside that split. Closing a saved pane still removes it from its
split; it then follows the split like any departing child.

sidebar items onto a sidebar tab: the hover labels "Create Split View" and "Add
(case 104: targetDropItem, newItems, disposition, moveFromOriginalLocation)
has no such sidebar drop; whether that gesture sets moveFromOriginalLocation was
not traced.

`ev_ca365f6329223b9c6a197474ec5b0539eedc83206b2e38b0700e00ff88a259ed`, read with the
annotated full-image disassembly of the other functions named here and the Swift
type table (`SelectItemParameters`, `SidebarInsertionStrategy`,
callers is retained outside Git with that evidence.

Checks: whole-module warnings-as-errors typecheck; BrowserStoreTests (including
`testSplitMembershipContainers`, `testLegacyMixedSplitContainerMigration` and the
rewritten Favorite layout test), FavoriteSplit, SplitPaneControls,
SplitSeparation, ExternalSplitDrop, OriginalSplitDrop, command-bar split and the
`scripts/test.sh` units. No browser ran and no on-screen comparison was made.

## Original group name and icon

Ordinary and whole-Favorite split groups retain their own optional name and icon.
They never borrow the focused child's custom title or change a page's URL. The
ordinary group uses the existing inline field; a whole Favorite uses the native
required-name Rename dialog after activating its original group. Context menus,
accessibility actions and the existing current-split Rename command share those
same original targets. A Favorite's stored home Space may differ from the active
Space: its complete group remains visible and editable throughout the same
Profile, without being moved or copied merely to edit it.

row's icon container. A choice commits at once and the picker stays open with
the new icon marked; Remove (shown only while an icon is set) commits no icon.
Dismissal and Escape never change the model. **Reset Name and Icon** atomically
clears both overrides. A non-empty name or any icon selects the custom-info
count badge stands in ([SP30](#split-cell-container--sp30)). Children retain their original context,
capture, close and reset owners through the custom-info row. Favorite tiles
display the chosen icon or emoji.

Edits capture the original group ID, exact Profile, physical window, active
Space, selected/focused items and original live page/Note/Easel editor identities.
A moved/replaced group, changed selection, retirement, pending transfer,
conflicting security surface or closing window expires that editor. Its own
popover or Rename sheet can take focus. Native failure preserves the current
editor and old stored state for retry. Successful persistence updates the shared
model atomically. Existing group copying, divider changes, Favorite conversion,
window restoration and same-Profile original-group moves preserve both fields;
an older per-window geometry cache cannot overwrite their current shared values.

The original window's Undo stack registers **Customize Tab**, **Rename Item**
and **Reset Name and Icon** only after a successful change. Each inverse guards
its own original fields. An icon inverse preserves an independent later name
change; a title inverse preserves the icon. The combined reset guards/restores
both. Undo retains current geometry, child identity and selection and refuses
retired/replaced originals. Failed durable Undo remains retryable. Because the
picker stays open, each successful choice renews its editor lease against the
group it just wrote; a failed write keeps the picker, shows the error on the
window and leaves the previous icon marked for retry. The lease also counts a
key window the picker owns: the skin-tone popover takes key focus when it

### Appearance reference and adaptations

`SidebarItemData.splitView` (tag 6) and preserves the other group fields. Context
"Undo prompt for customizing a tab's icon") and **Reset Name and Icon**
`ev_a540c81da942d761347d62e18c9a3e30c8141bae2548227cf028aa526c7b7594`
is cross-checked against original full-image assembly and field descriptors;
raw-slice external symbol names are not treated as recovered identities.

The top-app menu chooses the separate `renameFavorite` action. Its generic
original `SidebarItemID` consumer activates that item, then presents the required
name reducer. It is not a focused-child rename. Existing ordinary split title
and Favorite dialog evidence is retained in [saved-tab ownership](saved-tabs.md).

## Original icon catalog and picker

bundled `emojis.json` and the linear/figma images now live in

**Catalog.** `BaseModels.SidebarIconType` has 61 cases whose raw value is the
constant per case, each initializer storing one private-use code point; linear
glyph in black at the requested size, centered by its measured size, into a
square template image. The picker offers BaseModels static arrays:
because the row presenter's `isFolderLike` test is true only for lists and tab
decode and render, and an unknown stored icon decodes as absent.

columns, `canRemoveIcon = selectedIcon != nil` and the icon set, and sizes itself
rows · 30 + 8 · 2 + rows · 2 + 20 + 6 · 2 (272 for split views, 144 for folders).
anchors the hard-coded row rect {14, 8, 24, 24} at the minY edge of the
unflipped cell, below the icon container; Favorites tiles use their bounds
open after each choice. Parc anchors the custom-info icon container and the
tile bounds the same way; because a commit rebuilds the split row, the row's
icon rect is expressed in the stable sidebar list it scrolls with. Space
creation is different: its `TextAndIconPicker` builds `CustomInfoPickerView`
forwarding the icon, so every choice, Remove included, closes it. The fonts
load from the bundled files' own descriptors, never by name.

the current page, padded 4 horizontally and 6 vertically. The header
button: a 15-point Feather trash glyph in a 22-point-wide button with
`HoverableButtonStyle` (radius 5; clear, GrayA4 hovered, GrayA5 pressed). Remove
appears and disappears with `.easeOut(0.12)` on `canRemoveIcon`. A tab/Space
picker opens on Emoji when the icon is an emoji or absent and on Icon for an icon
`.easeOut(0.2)`: the icon page moves to and from the trailing edge, the emoji
page the leading edge, each by its own width.

draws the 14-point glyph white in the dark appearance and BrandGray otherwise.
Its background is clear, that colour at 0.1 while hovered and 0.25 while
selected, clipped to a continuous 4-point radius, and never animated. Pressing
scales the label to 0.9 at 0.75 opacity with a spring (response 0.2, damping
is the raw case name. Before macOS 14 the grid is focusable and the arrow keys
key handling.

(13 points, 2 from the top, 7 from each side), a flat flow-layout grid 6 below
it, and the category bar (7 from each side, 5 above the bottom). Cells are
28 × 28 with ten-point side insets, line spacing 5 and interitem spacing 2. A
17-point emoji image sits in each cell; the current emoji (or the base of a toned
choice) fills with CustomizationBackground, a hovered cell with
SidebarItemBackground, radius 5, without animation. The query is deduplicated
and debounced 0.2 seconds, then matched as the unescaped pattern `.*query.*`
(spaces become `.*`), case-insensitively, against the description and keywords,
or by the emoji itself. The "Search" placeholder appears only once the text has
been emptied. The eight category buttons (Feather glyphs, 14 points, tinted
ForegroundSecondary; GrayA4 hover, radius 6) scroll the first entry of a
category to the top; a hairline in ForegroundTertiary at 0.25 tops the bar.
Skin-tone emoji (except twelve multi-person ones) open a 198 × 38 transient,
unanimated popover above the cell with the base and five Fitzpatrick variants
(28-point buttons, four apart, 17-point text); the modifier replaces any existing
Apple Color Emoji has its glyphs and orders categories smileys/people, animals,

**Sidebar row.** The custom-info cell is SP30's ([custom info](#split-cell-container--sp30)).
SP26 supplies its 16-point icon through `SidebarCustomIcon.image(withSize:)`
colours, an SF Symbol, or the EmojiIcon image fitted to 16 points and never
tinted. Its 24-point icon slot is the picker's anchor.

Parc-owned remainders, recorded rather than claimed: the segmented control fills
the header width and sits eight points from Remove (SwiftUI's own sizing and
default spacing, inferred); the folder title is centered; Remove and the
runs on the main thread after its debounce instead of a background queue; the
pre-macOS 14 grid draws no focus ring. Space creation keeps its existing anchor
and shares the picker, closing it after each choice; the whole-split menu now
[SP33 inventory](#split-gesture-and-context-inventory--sp33)). The reusable component checks cover the catalog,
copied fonts, picker geometry, states, publication, failure and the custom-info
row. No populated on-screen comparison was made; no browser functional test ran.

## Split cell container — SP30

over `SplitViewCellState`, implemented by `SidebarSplitGroupView`
(`SplitDragView.swift`) with its geometry and producers in

**Selection states.** The cell draws the same `CellSelectionStateView` as an
ordinary row ([TAB19](parity.md#ordinary-row-presentation--tab19)): the current
split (`isCurrentItem`) takes TabCellBackgroundCurrent with its shadow, the key
item of a sidebar drag the current fill without it, a multi-selected split
TabCellBackgroundMutiselected, a hovered split SidebarItemBackground
the keyboard highlight the 2-point maxContrastColor ring and a window that is
neither key nor main half opacity. `SidebarSplitGroupView` reuses
`SidebarRowBackgroundView` for these, replacing the earlier 1-point accent
border. List-stop Tab focus uses that same HighlightRingView rather than a
1-point accent border on the cell layer, which rounded the split and clipped
TabCellShadowSelected plus the children's TabCellChildBackground pills. The
group's accessibility exposure is unchanged.


- The default inset is `SplitViewItem.Container.insets` 0 / 12 / 0 / 12
- Children share the width equally with `ChildItem.padding` 4 between them
  (`backingAlignedRect` with all edges nearest).
- While the cell's Close shows, the container gets an extended inset whose
  child width is more than `minimumWidthToCollapseForExtendedInset` 60
  ends at the extended inset; otherwise all children take the extended equal
  white at 15%), and it is hidden while the split is selected (`isGroupSelected`,
- Each child is TAB19's `SplitViewCellChildItemView` cell; its 28-point frame is
  now the row's own frame.

**Close.** The cell owns its own Close (`_closeButton`, a 24-point
and a child's Close follows group hover as TAB19 draws it. Otherwise the
children have none. The action is `SidebarSpaceState.closeButtonAction(for:in:)`
`presentedItemIDs` (`SidebarSpaceState` + 0xd8, children filtered by
deselects (Favorites are tiles here, not rows). The builder maps close to
`SplitViewCellStrings.archiveTooltip` "Archive this item" and deselect to
(`SplitViewCellState.closeItemShortcut`, field 10), as the reset shortcut
follows Reset Tab. Parc counts a child as presented when it has a live page or
local document editor in this window, and reads the action when Close is
deletion path with Undo and Reopen; deselect closes its pages and keeps its
saved items (`BrowserWindowController.prepareSidebarRootsClose`, shared with
keyboard Close). That path checks ordinary row Close's window and per-tab
conditions (without its key-window check), the hierarchy, selection and focus
rather than the window-move lease, so a private window, which never archives,
closes the split's pages and says "Close this item". The button enables with
those conditions and prepares the close transaction only when pressed. While
`SidebarCellButton` is; the split carries no close custom action, since
`SplitViewCellView` defines none (SP32).

0 / 14 / 0 / 18, spacing 6, a 24-point image container and
`SidebarCellConstants.Title.font` 14 in the palette's title color
the row. The stack places the label by its alignment rect, which AppKit insets 2
points inside each edge of the frame where it bounds the text, so Parc's label
spans 34 to 2 past the title's trailing edge and the text runs from 36 to that
edge (October 31: first ink 37.0 points in for "U", 39.0 before);
the children's manually framed titles keep their frames and already match the
cutoutColor at 0.8 and a bold 10-point maxContrastColor count
on the image view's layer is unmasked, so it draws nothing and Parc omits it. The split's title is its tooltip
`_isHovered` publisher are never read outside initialization in 1.122, so hover
changes only the cell fill and Close.

**Move affordance.** There is no handle and no child drag source:
control-click to `rightMouseDown:`, sends the child's action only while the
split is selected, and then calls `super`, so the outline drags the split item
split drag are removed. A press in the cell outside a child activates the
split's last focused pane; dragging from there, from the custom-info title or
from a child starts the whole-split sidebar move with a snapshot of the whole
cell, and the cell takes the key-dragged fill until the drag ends, also across
row rebuilds. Members reorder through the pane menu's Move entries.

Adaptations and limits: the emoji image is drawn from the system font;
`presentedItemIDs` is read as live content in this window; Parc has no content-visible
state (TAB19). The cell's `dropTargetRegion` drop highlight is default-off in
[SP33 inventory](#split-gesture-and-context-inventory--sp33). Before its case switch, closeButtonAction deselects an item
no peeked folders, so that branch is owed only if they are built. Evidence came from bounded annotated
disassembly of the 1.122 executable (`arcfn.py`, retained outside Git in
`work/claude-split-rea/sp30/asm`), Swift field metadata and installed 1.170
not claimed. Component checks: `scripts/test-split-appearance.sh` (container
geometry, producers, colors and custom-info presentation),
`scripts/test-split-titles.sh` and `scripts/test-sidebar-rows.sh`.

## Whole-split copy and external drags — SP23

alone (bounded `arcfn.py` disassembly and REA raw-slice decompiles, retained
outside Git in `work/claude-split-rea/sp23`).

`NSPasteboardItem` holding the ID string under the private type

proposal whose mask has neither copy nor move, then reads
Option is held — or when every dragged item is a Live Folder tab
not item containers, Instant Links or tab groups); otherwise it moves. A split
with its tab, Note and Easel children is copyable, so **Option-dragging a split
copies it**; no other modifier changes the operation, and AppKit's cursor shows
tile copies too. The accepted drop
precedes both branches, so a copy into another Profile's Space asks first. A copy does not
animate to its destination: the data source sets `animatesToDestination` only

copy inside Parc for a whole-split session, copy outside — and a Favorite split
tile (`FavoriteTile`) declares the tray's, starting an Option drag only for a
whole split. A session admits copy only when every dragged item is a whole
split, ordinary or Favorite (`SidebarSplitCopy`); loose tabs, single Favorites
and folders stay move-only (their copy is FOLD17's). A drop copies while Option
asks the destination window to prepare the copy (`prepareSidebarCopyDrop`):
same store, both windows able to take a sidebar window move (no private window,
command bar, Peek, full screen, closing or retiring page), a valid source
session, the children's current URLs and validated Note/Easel aliases
(`resolveSidebarCopyDestinations`), and a placement proposal that saves nothing
(`BrowserStore.canCopySidebarSplits`). The drop then reports copy with the usual
insertion, folder or dock cue. On release `BrowserStore.copySidebarSplits`
duplicates each split next to its original (fresh group and child IDs; name,
icon, orientation and proportions kept; originals, their pages, owners and
selection untouched) and places the copy with the ordinary move
(`SidebarWindowMove`) — before or after a row, into a folder, Pinned or Today,
the App Tray (as a Favorite split, within the twelve-root cap), a dock Space,
or another window's Space — in one durable save. A copy into another Profile
first shows SP20's inter-Profile sheet ("Move it", Cancel, "Don’t ask again",
the remembered preference) and its children then belong to that Profile. A copy
placed in this window's Space opens every web child of every copied split in
the background (a Favorite copy whatever its home Space) and the last is selected
at the source's focused child. An Option drop that cannot copy shows no drop; it
never becomes a move, and a move-only source held with Option (a single Favorite,
whose tile ignores modifiers) is refused rather than moved. The gesture binds the
splits' placement — group identity and geometry, child IDs and each child's
Profile, Space, section and folder — so a title, URL or activity change, or an
unrelated tab opened in the source Space while the inter-Profile sheet is up,
still copies the current records (`SidebarSplitCopy.matchesPlacement`); a
remembered decision reports the copy's own result and a later refusal beeps.
Dragging updates reuse one proposal per target until the store's state changes
(`BrowserStore.stateRevision`), so Note/Easel stores are not revalidated on every
tick.

**Outside the sidebar.** No other app reads the private type, so Finder, the
desktop, other apps and other browsers refuse the split, and AppKit slides the
`SidebarItemID` type is registered by the tablist, the Space header, the sidebar
and its forwarding view, the App Tray, the split view controller (which refuses
Easels and the command bar do not register it. Parc's pasteboard likewise holds
only its private session type: Chromium pages, Note and Easel editors register
no such type, the URL receiver refuses it explicitly and the page-area overlay
takes only a single tab's split drag, so only the sidebar accepts a split.

`acceptTabListDrop` targeting the `pinnedTabsHeader` accessory
(`TablistItemID.accessory`, raw 0) with drop type after, operation move and no
the Space's Pinned container at index 0: the top of Pinned. A dock Space item
Space; a Favorite is in none, so it stays), picks the Space's Pinned list when
every remaining item is pinned or a Favorite, otherwise its Today list
tablist reducer with that list as an `.on` target, which the resolver turns
the list. The inter-Profile decision and the copy branch apply, and in the
Spaces layout the reducer then focuses the drop's Space (`focusSpace`,
another window moves the items into that Space alike.

Parc's sidebar takes item drags on both through the same session. The shown
header moves the items before the first Pinned root (from another window
through SP19/SP20's window transfer) and refuses an Option drop. A dock Space
item moves the items not already in that Space — Favorites included; none left
refuses, so a window showing the same Space never pulls items out of their
folders — to the top of its Pinned or Today list with the ordinary placement
(`SidebarWindowMove`; another Profile after SP20's decision, the moved pages
reloading there) and then shows that Space; with Option it copies the whole splits
not already there to the same place, under the same list rule, and selects the
copy there. A drag from another window first
makes this window show the dock's Space, then receives the items by SP19's
window transfer. This covers the Sidebar's "Drops on the header" contract
([sidebar resizing](sidebar-resize.md#space-header)) for every item kind.
top; Parc's folder drop still appends (a Folders contract,
[folder moves](folder-moves.md)).

model's selection state without the hover fill or the cell's Close. Parc's
`SidebarSplitGroupView.dragImage()` captures the cell with hover cleared and then
restores it; Parc's row is the cell's visible background, so its frame holds the
Parc's existing count overlay.

**Drag-to-combine.** The cell's `dropTargetRegion` highlight and
`draggedToCombineSplitCompatibleItems` sit behind

`deleteAndReloadWindowContentsFor` the dragged originals, and the copy branch
keeps that effect, so a copy into another Profile reloads the original pages.
Parc retires the originals' live pages through the real leave-page consent
(`BrowserStore.copySidebarSplitsReloadingOriginals`, the whole-set retirement
owner), then saves the copy; a window that showed the originals shows them
again, which loads them afresh in their own Profile. A refusal publishes
original identifier into the new item ([folder commands](folder-commands.md)) —
so its copy references the same document rather than duplicating it. Parc
keeps documents per Profile and one document cannot live in two Profiles'
stores (SP20's rule for a document still referenced in the source Profile), so
a split with a Note or Easel child is not copied into another Profile; within

Adaptations: Live Folder auto-copy has no Parc counterpart (Live Folders are
excluded); mixed selections with tabs or folders stay move-only until FOLD17;
the pasteboard token is the session ID, not the item ID (the existing authority
rule); the copy's focused child follows the source's focus, as Parc's layout
`tests/SidebarSplitCopyTests.swift` (`scripts/test.sh`; placement, fresh
identities, folder/Today/Space/App Tray/other-Profile destinations, Favorite
splits, document refusal, durable reload), `tests/SidebarRows/SidebarMoveCopyTests.swift`
and `tests/SidebarRows/split_copy_drag_check.py` (`scripts/test-split-appearance.sh`).

## External URL drops into ordinary split panes

A single public HTTP(S) URL dragged over an ordinary browser pane can create a
new Today tab at an edge or replace the visible pane at its center. The exact
URL is a new navigation value; it is never used to recreate an existing dragged
tab or document. Replacement keeps the displaced original tab and page alive.
The existing group ID, name, icon and proportions survive replacement. Insertion
retains the other original members and uses the existing split geometry rule.
New tab, selection and group arrangement save in one atomic model publication;
a failed save leaves no orphan tab or changed arrangement.

tries `NSPasteboardTypeString` with Foundation URL parsing. Prepare
constructs `SplitViewAction.onDropURL` (tag 3). Its actual reducer branch
index/replace flag and layout orientation into `TabCreationOptions`, then the
navigating the displaced page. Fresh REA
`ev_289de06d8d206c3b5c348c2f7d4b789d02280f07815ed320685968db1cbd1fc6`
is paired with the complete original assembly and field metadata; raw-slice
external/global identities are attributed from the full image, not guessed from
pseudocode.

Chromium's real `WebContentsViewCocoa` receives the native drag. The source-owned
`PCNativeContentDropRouter` offers it to a typed ancestor destination before
renderer delivery. Unclaimed drags use the unchanged renderer route. A claimed
gesture remains claimed after its recipient expires, preventing a canceled split
drop from turning into an unexpected webpage navigation. Original native view,
physical window, pasteboard object/change count and drag sequence bind the lease;
each pane's receiver can only update, commit or end its own shell session.
Exit, canceled/ended drag, host teardown, focus loss, changed selection, native
navigation/crash, geometry change, close/transfer or security refusal remove the
preview. The original page/Profile/native selection owners authorize creation,
including the existing isolated private-window store. No renderer reparenting or
page close occurs for preview. Existing tab creation and native focus execute
after a successful model commit.

This bounded route accepts one explicit HTTP(S) URL without URL credentials.
File, internal/custom-scheme and plural payloads remain with the renderer;
authenticated sidebar-item drags keep their original move owner. It starts from native browser content and the original Note title/body/background
or Easel canvas/text receivers. Local receivers use the same native ancestor
router and exact session; no transparent overlay steals their native drag input.
The original editor, typed document/Profile and physical window must still match.
Marked text, active canvas gestures and a live Easel address editor refuse split
admission. Rich text/images and drags from within the same local document retain
their editor import behavior. A claimed-but-canceled or detached gesture cannot
fall back into text insertion. Replacing a pane parks its original editor/session
without closing or discarding a failed draft; other shared document
windows and original embedded pages remain intact. These composition/import
preservation rules are explicit Parc adaptations.

webpage class condition (fresh REA
`ev_17689fcc9e09907c6d3507e16159b7119f52e8095f49dca1bebaed10f425c918`, exact full-image
assembly/metadata retained). The policy behind the source flag is not fully
attributed. Standalone and whole-Favorite targets now use the separately traced
saved-home/group policy below. A whole-split drag never reaches this route: it
carries only the private sidebar type and the page area refuses a split
([whole-split copy and external drags](#whole-split-copy-and-external-drags--sp23)).
Legacy mixed Favorite/Today groups, Start/error-pane targets and other source
surfaces remain separate contracts. Edge regions now use the recovered classifier described below. The four-pane cap and immediate
preview tint/text remain explicit Parc adaptations. Immediate preview
also has no motion to suppress under Reduce Motion.

external drag, split creation or navigation was performed; populated drag preview
appearance and exact original threshold/motion/haptics remain unobserved. Actual
compiler and temporary model/native AppKit component checks are separate from
browser functional verification. Reusable checks live in
`tests/NativeContentDrop` and `scripts/test-external-split-drop.sh`.


### Favorite targets and saved-home ownership

A standalone Favorite now accepts one external HTTP(S) URL through the same
original-content drag session. An edge insertion preserves the Favorite's saved
home as a fresh reference in its original Profile-wide tray slot. The original
live tab ID, URL/history and Note/Easel editor enter the new Today split in the
active Space; they are not recreated or reloaded. The fresh home uses savedURL,
saved title and custom name, retains its original home Space, and uses the
existing background duplicate opener after successful persistence. Typed homes
are validated aliases of the same existing local document and assets.

An existing whole-Favorite split accepts the URL as another Favorite child in
its original group/home Space, including when viewed from another Space of that
Profile. Replacement preserves the displaced original item/page and the original
group ID, name, icon and proportions. Its tray slot remains stable; any displaced
Favorite becomes a separate root, and exceeding the existing twelve-root cap
refuses atomically. Center replacement of a standalone Favorite leaves that
Favorite intact outside the new single-page selection.

The native drag/session owns all previews, cancellation and final publication.
Source window/Profile/Space, exact selection/panes, original hierarchy/saved
metadata, geometry and typed document leases are rechecked. One atomic save
publishes the new URL, home reference and split placement together. Failed saves
retain the exact original model; native/local editors are not retired. Persisted
return selections in other Spaces follow the fresh home reference, an explicit
Parc cache adaptation. Rich/image/self-document and composition behavior remain
with the existing local editor route.

Arc1.122's actual URL action reaches TabCreationOptions and common selection
parent-list ID with a fresh UUID and duplicates with savedURL/shouldOpen options
`0x101`; the original displayed IDs become the split. The existing-group branch
excludes its original children before that saved-home filter. Fresh REA evidence
`ev_6497cd23063ad3cf0c77eeb867ca0b3d6ac0e9afd4c40f255113d9c0140e5dd4`,
`ev_5e986427ad91080e4a85b7ed7053d2adef76ef8bee438e602d94bd90d753854d` and
`ev_2f27d8b381e9745217b4cc6934449e5db8cfde3bdd2c8d68c0a7bc48416006d9`
is cross-checked with original full-image assembly and field metadata.

The mapping to per-child saved kind, atomic persistence, root cap and cache
repair are Parc ownership adaptations. The predicate also covers standalone
pinned items and every other split route; SP21 applies it everywhere through one
see [split containers](#split-containers-and-saved-home-membership--sp21).
Whole-group copy and external drags are [SP23](#whole-split-copy-and-external-drags--sp23); URL drops from another
Profile's window are covered by [cross-Profile moves](#cross-profile-moves).
Exact hover/pressed geometry, motion and haptics remain unobserved. No functional
browser tests or actual personal URL drops were performed.


The fixed 148-source Swift cohort passes with warnings treated as errors and zero
diagnostics. Actual temporary-store components pass 62 URL/split/Favorite checks,
including same-Profile cross-Space tray order, saved-home identity, whole-group
appearance/geometry, the twelve-root refusal, disk failure and real Note/Easel
alias validation. Existing native session and actual local editor/router
components pass 20 and 29 assertions with exact unchanged inputs. These checks
do not establish populated browser drag appearance or runtime parity.

### Pinned saved-home placement

A standalone pinned edge drop follows the same recovered saved-item branch as a Favorite: the fresh home uses the original saved URL/title and custom title, preserving its original folder and mixed sibling position. The original live ID, current URL, local editor and native page join the new Today split. Center replacement leaves that saved item intact; adding to an existing pinned group preserves that original group and does not duplicate its existing children. The current source folder must still exist. One durable transaction publishes the saved home and split together, with fixed gesture identities and actual typed-document validation. Existing background opening handles only the fresh web home; Note/Easel homes are aliases to the same original documents and shared sessions.



### Public router boundary

Local Note/Easel receivers now acquire `PCNativeContentDropRouting` through the
CEF-exported `PCCreateNativeContentDropRouter` factory. The sole implementation
remains in Chromium ui/base, shared with the original WebContents container.
The factory changes no gesture, pasteboard, ancestor or window lease behavior.
This is a current-engine linkage adaptation of the previously recovered drag
contract. The app no longer directly instantiates a class exported only by a
transitive component library. A focused two-library compile/link check reproduces
that former undefined-class failure and verifies every protocol method through
the public engine boundary, without launching a browser. Packaging also requires
the factory export when sealing the engine. No dependency-copy or runtime-load
path workaround was introduced.

## Separate Page and original focus

Separate Page from Split View keeps the focused original page displayed alone.
The surviving siblings retain their original saved group, order, orientation,
normalized proportions, name and icon. Separating a different displayed child
keeps the original focus among its siblings; a background sidebar/AX target
changes only that saved group. A one-child container dissolves. None of these
actions closes a page, recreates a live navigation or replaces a Note/Easel
session. The separated child stays in its split's container and moves directly
after the split; a dissolving split is replaced by its children in child order
([split containers](#split-containers-and-saved-home-membership--sp21)).

The original window's command receipt and sidebar action bind the exact group,
selection, focus, Profile/Space, native page/wrapper, local editor and ownership
claims. Stale or unavailable actions refuse. Selection and saved-group mutation
commit atomically; a real save failure retains the original state for retry.
Native/local focus uses the existing selected-page route only after success.

requested set. It then emits containerDelegate.onDidRemoveItemsFromContainers.
The exact State/SplitViewState field-offset vectors prove the focus at
State+0x40 and original content/sidebar map at State+0x68. Fresh REA
`ev_dc342b803d45830de08128893f8ee82cef6a38bcb9e4da5bdbac94c2755caa50`
and `ev_fd09a39056607bf23d882d18af29ae6dd157117f5c4742b6c43357b3b44843d2`
are cross-checked with original assembly/metadata. This corrects the previous
first-surviving-sibling focus adaptation. The sidebar-side relocation that
see [command-driven split choreography](#command-driven-split-choreography).

## Divider pair sizing

Double-clicking an original divider equalizes only its two adjacent panes. Their
combined proportion and every other pane's share remain unchanged in either
orientation. A divider drag captures the actual group, original pane/page owners,
window, selection and host bounds before AppKit begins tracking. A changed owner,
security surface, selection or geometry rejects the old completion. Rejection
restores the latest authoritative frames. A successful resize persists the
geometry before publication; a storage failure leaves the saved group and original
pages untouched.

sum to each original pane by ID. Fresh REA
`ev_99f00f188156434d5bd0d701fc90bf0609360a91ceacec237cb2edaec928c9c5`
command, so Parc no longer offers one
([command-driven split choreography](#command-driven-split-choreography)). Native AppKit tracking and immediate layout remain Parc adaptations; the
browser divider spacing and expanded-pane minimum are now recovered below. The
separately recovered center-snap/haptic and pane drag-source flows are not claimed
by this increment; exact source gesture and populated motion remain in the active
Split family. Isolated real AppKit/store checks and the full application compiler
pass; no browser execution or matched optical comparison is claimed.

## Original sidebar-tab drop placement

Dragging an original sidebar tab onto a pane keeps its actual live page, request
history, Note/Easel editor and navigation provenance. When a newly grouped member
is pinned or a standalone Favorite, a fresh saved-home reference replaces its
exact original parent slot and the live original enters the Today split. The
home uses savedURL, saved title and custom name. A saved child taken from another
split through Add (split children are not drag sources) leaves its fresh home in that original child position, preserving the old
container's identity, proportions, orientation and custom appearance. Existing
destination-group children are excluded from the saved-home copy step. A new
group anchors at an existing ordinary member when one is present.

Center replacement preserves the displaced original, which follows the split in
its container. An existing destination keeps its container: a whole-Favorite
split converts the incoming original into a Favorite child, a pinned split takes
it into its folder; tray-capacity refusal publishes nothing. Source Favorite
gestures remain separate from this original ordinary-tab source; the whole-group
gesture is the split cell's ([SP23](#whole-split-copy-and-external-drags--sp23)).

The drag receipt captures the original window/Profile/Space, selection/group,
hierarchy, saved destinations, native ownership claims, page/wrapper and local
editor/embedded-page identities. Preview and commit revalidate those same owners.
One synchronous durable transaction publishes homes and split placement together;
save failure leaves the original state intact. Only newly created web homes use
the existing background opener; typed homes are validated aliases to the same
local document/session. No original page is copied, reloaded or retired.

constructs original item-selection options with the drop index/replacement and
replacement/duplicate (savedURL, shouldOpen options0x101). Fresh REA
`ev_5ab6afee5ffb808c5c9f032929d98d3c3f52ff9516c842d936024ccf65286061`
is paired with the full-image dispatch and the retained saved-home evidence.

Atomic publication, flat-record anchor mapping, cached return-selection repair
and fixed gesture-local home IDs are Parc ownership adaptations. The actual original-item drag decoder explicitly excludes a whole split before
producing a sidebar-item pane drop. A generic URL fallback is a distinct URL
[cross-Profile moves](#cross-profile-moves); populated drop geometry/motion and final optical
comparison remain in the active Split family; saved-parent relocation is SP21's. Existing native preview/cancellation

The final fixed cohort passes a 156-source Swift check with warnings as errors and
zero diagnostics, 42 real placement/store/typed-alias assertions, and 27 existing
split transaction assertions. The standard explicit model runners include the
new production helper; all eight affected runner syntaxes pass. No browser was
launched. These checks cover persistence, retry and identity, not historical optics.

## Cross-Profile moves

decision, then reloads its contents in the destination Profile. Parc now does
the same for every split route that can reach another Profile.

**Decision.** `SplitViewAction.onDropSidebarItem` carries
`maybeMoveDecision: ProfilesUI.ProfileDialogUtils.ConfirmInterProfileMoveDecision?`
`WindowData+WebContentFrame.swift`), which returns `WindowDataMaybeMoveResult`
app preference `shouldBypassConfirmInterProfileMoveDialog` (preference case 0x28;
re-sends `onDropSidebarItem` with the chosen decision. `abort` cancels.
`proceed` continues; `alwaysProceed` first stores the preference. Proceeding
returns an effect emitting `WindowAction.deleteAndReloadWindowContentsFor`
also gates `beginMoveItems(configuration:maybeMoveDecision:)`
several source Profiles (`MoveItemsError.multipleSourceProfiles`).
Fresh REA: `ev_9f0dd28c0d50f7011d860549ee5df90465334e21e8b742b08645f6ef2e499205`

you might get logged out or lose your progress in this tab.\n\nThis can't be
`proceed`, the checked box `alwaysProceed`, Cancel `abort`; the dialog width is
with a transparent titlebar) begun as a sheet on the browser window
`InterProfileMoveDialog` is likewise a 455-point sheet on the window that
[Export as Image](easels.md#export-as-image)): title and message with the
Space name in bold, the "Don’t ask again" checkbox, Cancel (Escape) and
"Move it" (Return).
`InterProfileMoveGate`, `InterProfileMovePrompt` and
`BrowserSettings.shouldBypassConfirmInterProfileMoveDialog` hold the decision,
copy and preference.

**What moves.** Proceeding moves the original records with the same IDs, group
identity, name, icon, orientation and proportions; each moved tab takes the
destination Space and Profile. A saved (pinned) original dropped on a pane
leaves a fresh saved-home copy in its exact parent slot in the source Space, as
the ordinary drop does; a child leaving a source split keeps the surviving
group (a two-child group dissolves). The dialog's "lose your progress" is the
keeps its native consent path: `BrowserStore.moveAcrossProfiles` reserves the
tabs, every live page in every physical window runs its real beforeunload
through the whole-set retirement owner (`requestPageRetirement`), and only
after every page is destroyed does one durable save publish the records. The
destination then creates fresh pages from each tab's current URL in its own
Profile. A refused leave-page prompt, a changed original or a failed save
changes nothing. History, page state and sign-in do not move; saved homes and
Favorites tray slots follow the rules above.

Notes and Easels move too. Neither decision function filters by item type, and
item. Parc keeps documents per Profile, so after page consent every original
editor closes with its draft flushed, the exact Note file or Easel document
moves into the destination Profile's store (an Easel's referenced image assets
are copied; the source keeps its assets as it does after delete), and then the
records save. A failed save moves the documents back. A document that a record
staying in the source Profile still references (for example the fresh saved
home of a pinned Note) cannot live in both stores, so that move refuses.

**Routes.**

  or window-gated: the SharedWindows reducer forwards `onDropSidebarItem` from
  targets in every other window (the original row and its pasteboard
  identifier remain the only authority). The destination keeps the
  reserved-layout preview and region rules and requires only the
  drag-destination gate (`canParticipateInPageTransfer`). The same Profile
  needs no decision: SP19's collection owner moves the actual page, Note or
  Easel editor (with its embedded pages) into this window, then one save
  publishes the placement; a pinned original leaves its home, as on a local
  drop. Another Profile shows the dialog after the drop and reloads.
- *Move to.* The Move to submenu lists every Space; another Profile's Space
  runs the decision and moves the selected tabs, folders and whole splits.
  Favorites stay outside Move to, as before.
- *Physical windows.* A sidebar collection or whole split dropped into another
  empty destination selects the first moved item's whole group.
- *External URLs.* `onDropURL` carries no Profile and has no decision. A URL
  dragged from another Parc window, including another Profile's, now targets
  the pane under the pointer even though that window is not key; the new tab
  is created in the destination pane's Profile.
- *Add Split.* None of the nine `maybeMove` callers or the two
  `confirmInterProfileMove` callers is a command-bar route (they are the split
  drop, same- and cross-window sidebar drags, New Folder, the Space action that
  carries the decision (`turnSpaceIntoFolder`), Space Profile change, app tray
  own tabs and creates navigations in its Profile, so no cross-Profile Add
  destination exists.

**Exclusion and adaptation.** The Archie illustration (`icon-archie-move`) is
per-Profile document storage is the reason a document still referenced in the

asked: no bypass key). SPACE18 now connects Header, manager and Settings Profile
assignment to that distinct confirmation and the genuine retirement/typed-document
also shares the real cross-Profile transaction and its non-Undo policy; same-Profile
conversion retains the original native pages and supports original-window Undo.
See [Space management](space-management.md). This resolves those required
management dependencies without additional Settings or Folders ledger credit.

Checks: `tests/SidebarRows/InterProfileMoveTests.swift`
(`scripts/test-inter-profile-move.sh`) covers the gate, copy, preference,
split-drop placement in both Profiles, collection moves, the retirement
ordering, real Note/Easel relocation with assets and failure paths, plus the
existing move, split, window, Note and Easel store tests. No browser was launched

## Divider center snapping

Dragging an original divider now uses a native pan recognizer. Recognition starts
only for the actual divider hit, leaving page/editor input on its existing route.
It captures the original group before recognition, records the handle offset when
the pan begins and resizes only that original adjacent pair. Native cancellation,
detachment, changed bounds/orientation or stale original owner restore the current
authoritative layout; only an accepted end persists geometry.

The recovered state initially does not snap. Moving at least 14 points from the
pair center arms snapping. A subsequent approach inside that band snaps when the
absolute x component of native pan velocity is at most 120 points per second and
its direction approaches center. An already snapped divider stays snapped within
the band; crossing its boundary releases it. Engaging and releasing each issue one
native generic/now haptic. The x-component use, including vertical layout, follows
the actual retained consumer. This is separate from tab-reordering haptics; no
unattributed preference connection is added.

14/120 gates and state transitions, then calls `NSHapticFeedbackManager` at
`ev_2713f1c8c52d07d2568ec3e0e692b87904a700c8d12a7c45b790cdb58d614fc9`
is paired with full-image selector/instruction attribution. Parc uses its existing
pane minimums and source-owned AppKit layout; exact historical curve, haptic strength
and populated visual comparison remain unmeasured. The native view/state checks
exercise real admission, original pair geometry, cancellation/detachment and single
completion without a browser.

## Pane-drop target regions

Original-tab and external-URL drops share one classifier over the captured
whole original pane frames, header included. A link drag reaches the split
through the page's own receiver, and the host continues it over the reserved
region and over pane headers, so a header keeps its pane's top zone. A single pane offers horizontal insertion within
40% of either edge and vertical insertion within one-quarter of its height, capped
at 50 points. Vertical edges take precedence at corners. Multiple horizontal
panes use one-third of their width capped at 80 points; vertical panes use
one-third of their height capped at 50 points. Exact threshold equality belongs
to the center. Divider gaps remain outside the captured panes; each pane's

If the original owner refuses edge insertion, the proposal tries replacement of
that same pane. If that is also unavailable, no target is shown or committed.
This allows a full split to offer a valid replacement without weakening capacity,
identity, typed-document, native ownership or security validation. Preview and final
commit share the same target and existing gesture lease.

and the strict comparisons are established by full-image instructions and data,
with REA `ev_75d9c67fba1dec82a00d00769bbb6cd86533d6f04998efe4c0edb956275b34d3`
and `ev_895a32467ad505feae0552a0e4388c574587485267c2d588779e2be04a0de69f`.
The original owner uses native unflipped coordinates; Parc maps top/bottom to its
existing flipped content frames. The existing single-pane vertical eligibility
policy is retained. The proposal reports the classified pane's exact content
frame; insertion is presented by the reserved region and replacement by the
target pane's highlight border ([replacement highlight](#replacement-highlight-pending-pane-and-proposal-feedback)).

`SidebarItemData.splitView` case 6 before constructing the original-sidebar-item
drag. REA `ev_53c7b8a69a55593e24df42d716764ba66c2e1dcefdb050e4f6f362e92cd3b335`
is paired with its actual enum metadata and annotated full-image branch. Whole
group physical-window and sidebar moves retain their separate authentic owners.
([pane-snapshot drag source](#pane-snapshot-drag-source)); Parc binds no pane
handle. Favorite mouse-down selection remains
unchanged, so a prior split is not restored merely to accept a Favorite drag.

Focused geometry and native AppKit session checks use disposable windows and
pasteboards, without a browser or a live drag. Full application compilation
checks the two production callers. Populated historical appearance and transition
measurements remain unavailable from the existing reference window.

The fixed 157-source Swift application passes with warnings as errors and zero
diagnostics. Focused components pass 35 geometry assertions and 23 actual native
AppKit session assertions, including refusal-to-replacement through the original
commit owner. All 29 actual local Note/Easel native-drop checks also pass. Both
component runners link the real public router factory.

## Original pane menu and Add Split

Each displayed pane now exposes **Split View Options** through its original native
header or visible toolbar, with the original Move Left/Right or Up/Down, Add
Left/Right or Top/Bottom, Separate Tab from Split, Convert to the other
orientation, and Copy Link actions. The native menu holds the original group, ordered
page IDs, focused page, layout and window; changing any owner refuses the action.
Unavailable neighbors and a fifth pane are disabled. Menu copy uses the original
visible page's policy-checked native clipboard operation; local documents retain
their actual local address. Pane reorder moves the original IDs and proportions
in one durable transaction, without navigation or page/editor replacement.

webpage. Fresh REA records are `ev_2557fc2f43c3073af2b5386dfdc1f8b818a7b09eb0efa98c1f41c12bb2db49c8`
and `ev_ad6fef04cffc44b11f2aa15fd0e5588924d3451e800d9e87676e2f1b4acb8ef8`,
supplemented by original full-image assembly and type metadata.

Parc now uses a temporary window-owned blank-pane view for Add Split, including
the existing keyboard/menu/command-bar entry. Original pages remain attached to
the same pane owners. Cancelling removes only that view and restores the original
focus. Choosing a native navigation retains its complete request token through
commit and actual loading; choosing an existing ordinary tab or local document
moves its original ID. New Note, New Note in Split View and New Easel occupy that
has no New Easel in Split View menu; Add Split is the recovered create-in-pane
route). A Today Note or Easel does not leave a saved home. File → New Easel
outside Add Split still replaces the current selection, matching `newEasel:`
(tag 20). The chosen pane, saved homes and group publish atomically;
failed storage leaves the original state. Native destination refusal, owner loss,
or dismissal followed by invalidity retires only the original draft and cannot
leave an orphan placeholder. All-child page/editor/claim checks remain active
through asynchronous input resolution. Already selected rows are not silently
retargeted; the command bar offers no other Profile's destination (see
[cross-Profile moves](#cross-profile-moves)).

`WindowContentViewController.State.contentPanelSplitViewMenuItems`, which the
its static list is Add Left/Right, separator, Add Top/Bottom. For multiple panes,
the original orientation selects Move, separator, Add, separator, Separate and
Convert, then separator and Copy Link. Parc now follows these lists, including
all four directions from the single-page toolbar; each entry uses the same
original-page admission and insertion receipt as an existing split. Empty and
out-of-range content counts produce no menu. The exact static arrays and
constructor/caller chain supplement fresh REA
`ev_32e74fcbc8458f7382842e940d026b9bbd2bd9351e262fcefa90c67cc179e499`;
the raw decompiler's external tail is not used to infer the single-content list.

immediate add/remove ([pending pane](#replacement-highlight-pending-pane-and-proposal-feedback)).
generic Add entry and SF Symbol substitutions remain explicit adaptations. Exact glyph pixels,
control placement and hover visibility still require attribution/comparison. Saved-home
normalization and same-Profile results, Favorites included, reuse the original-item split
transaction ([SP21](#split-containers-and-saved-home-membership--sp21)); cross-Space
command-bar choices remain separate contracts (SP33). This increment does not claim completion of
the complete Split family. Its isolated actual model and native-menu checks plus
the complete Swift compiler run do not execute browser functionality.


### Divider grip appearance and native cursor

Each actual divider now has a centered grip with a one-point corner radius. The
horizontal pane arrangement uses the recovered two-by-24-point grip; the vertical
arrangement uses the separately recovered 24-by-two-point bottom-handle grip
described below. A tracking area belongs to that original divider's draggable
region in the key window, and its cursor follows the actual resize direction. The grip is a passive layer, so it neither becomes a
pane nor intercepts the original page or local editor's input. Resizing updates
its actual geometry without changing the existing captured-owner transaction.
Window deactivation, detachment, hidden/clipped geometry and retired panes clear
stale hover. Appearance changes preserve the current valid target and resolve its
color immediately.

0.16-second implicit color animation. Its own tracking-area enter/exit handlers
actual named-color loader. Fresh REA
`ev_43462da5217351cd12d6f4d95ebcb0075cfce643e7b6d0b0a730b851ccd1b90f`
supply black in light appearance and white in dark appearance, at 0.2 opacity when
idle and 0.5 on hover; their values are separately attributed from the 1.122
consumer. Parc animates only that color for 0.16 seconds. Neither handle reads
Reduce Motion (no `accessibilityDisplayShouldReduceMotion` reference in the handle,
split controller or window-container code), so neither does Parc. CALayer delivery
and clipped per-divider tracking are explicit AppKit adaptations; historical
timing-curve and pixel equality are not claimed.

Stacked panes are divided by each pane's separate `SplitViewBottomDraggerHandleView`
(the delegate's second handle factory, ContentPane field `bottomDraggerHandle`).
already had that geometry; it is now attributed rather than a rotation.

The browser-specific mapper now establishes the spacing, rather than relying on
that generic default. `WindowContentsContainerViewController` construction
inset and sets its handle width. Parc now uses this ten-point divider.

remaining axis by the original width factor, rounds at the backing scale and
clamps expanded panes to `minimumPaneWidth`; both horizontal and vertical
expanded minimum in either orientation and rounds actual pane bounds, preserving
the ten-point gap and original page/editor identities during layout and dragging.
Ratios are still saved only by the accepted original-owner resize transaction.
Fresh REA records are `ev_41345bf295f090cfa3732deeff903e5bd6019444d058f64c1fd681e68d78923b`
for the browser mapper and `ev_423c2815a943235e803d64cfb76504fd24ac4295ca2099d7ed396d81d9020e99`
for pane geometry, bound to the original full-image assembly and metadata.

the sum of expanded 220-point panes and their ten-point handles. The width sum
of 382; trailing/bottom anchors have priority 750. Parc uses actual native
constraints on the original split and lets those softer edges yield when the
content area is smaller, without resizing the window or changing its minimum.

The native container now directly subclasses `NSView`, as the original
`DraggingDestinationForwardingView` does. An isolated actual AppKit component
established that `NSSplitView` repairs child frames extending past its bounds;
that would erase the recovered vertical expanded minima. Parc retains its
original arranged-pane API, gesture recognizer, exact resize receipt and native
page/editor views while removing that competing layout owner.

earlier split-group element with numeric splitter children was a Parc
adaptation and is removed ([SP32](#split-keyboard-accessibility-and-focus--sp32)).
No key gesture or fixed resize step resizes panes.

minimum deficits in ascending original factor order. Expanded panes now retain
220 points when available surplus is exhausted instead of shrinking every pane
to fit. Original ratios return as room becomes available. BWC retains its
existing sidebar/panel insets in the page host, flushes that host's native
layout, and no longer overwrites the constrained split frame. Detachment retires
the exact constraints and geometry changes cancel a captured divider.

Fresh REA records are
`ev_f379941a1232a73d12f0a2f4f2d165bbe832f24f7d9efd93ccc17a5cc17d81ac`
and `ev_61933dc0d05243cf6f583a9641e9ff8f8f5e8073c65694995793f16192526c9f`.
The Split-only integration leaves single-page/popup/global-window sizing at its
existing policy. Collapsed/fixed transition types are attributed in
[Collapsed and fixed pane transitions](#collapsed-and-fixed-pane-transitions);
command-driven layout is in
[command-driven split choreography](#command-driven-split-choreography). Native AppKit/store components cover actual priority resolution, undersized
hosts, original pane/window identity, restoration and resize cancellation; no
functional browser test ran.


## Original backing-scale pane geometry

Each pane now rounds its own expanded length at the actual owning window's
backing scale before the final integer-point frame-edge rounding. Preceding
rounded lengths plus the original ten-point handles determine its position.
The final pane does not stretch to consume a rounding remainder: a detached
1× container with 980 available points and three equal panes has three
327-point panes, while the same original 2× window produces displayed widths
327, 326 and 327. The original controller reads `view.window.backingScaleFactor`
length × scale, divides by scale and clamps the expanded minimum. Position

The live divider path now uses this same geometry. Its mutation divides the
proposed length by the entire layout's available axis, clamps against the two
original minimum fractions, and preserves the pair's combined source factor.
The snap center also uses that source share rather than the displayed pair's
already-rounded extent. Each pointer update is relative to the live original
pane, retaining its captured handle offset even when minimum redistribution
third pane can legitimately receive a new displayed frame when the full layout
normalizes the factor sum and then lays out all original panes. Fresh REA
`ev_d1fccb4db5804278b8204e4be3e6ec56066fee2959e4323f2bde08d110b957f1`
factors with the expanded-minimum redistribution.

Parc retains its accepted original-owner durable transaction: live movement
only previews these factors; refusal or cancellation restores the latest saved
geometry. A backing-scale change cancels an outstanding original receipt, and
ordinary layout reuses the actual window's new scale without recreating panes.
Defensive
nonfinite/nonpositive scales fall back to 1, and a degenerate pair that would
produce a nonpositive saved factor refuses under the existing storage invariant.
These are explicit Parc safeguards. Isolated native components cover concrete
1×/2× frames, same-scale notification, changed-scale cancellation before and
after notification, accepted-preview equality and retained original identities.
No browser functional or populated optical comparison ran. Collapsed/fixed
transition types are attributed below, and command-driven layout in
[command-driven split choreography](#command-driven-split-choreography).


## Adjacent-pane equalization motion

An accepted divider double click now eases the same live pane and grip surfaces
to their equalized frames over 0.2 seconds. Final geometry and durable ratios are
published synchronously by the existing original-pair transaction; the animation
has no delayed selection, focus or save callback. A refused transaction, changed
pane identity, orientation or bounds does not animate a replacement owner.
Ordinary resizing, a new drag, owner deactivation and detachment clear only this
that setting is.

animated update flags after modifying the original pair. The layout owner
with 0.2-second duration, ease-out and implicit animation. Ordinary
Parc uses an explicit native layer group on its existing NSView surfaces to keep
logical frames and native ownership synchronous; this delivery mechanism is an
[command-driven split choreography](#command-driven-split-choreography).


## Command-driven split choreography

and top bars take their new frames in the same layout pass, with no fade, slide or
double click (above) and the drop regions ([reserved-region pane
motion](#reserved-region-pane-motion)). Parc matches this for every command,

**One owner, one immediate path.** The window container
(`WindowContentsContainerViewController`) subscribes to the window's contents
`layoutSubtreeIfNeeded`. The container's code range has no `runAnimationGroup`,
`animator`, `allowsImplicitAnimation`, CATransaction, CAAnimation or SwiftUI
`withAnimation`/`withTransaction` reference.

0.2-second group only when its caller asks. The divider double click
the value changes, so conversion lays out in the next immediate `viewWillLayout`.
view-hosted layers. Within `WindowContentViewController`'s range, the only
`TopBarPanelViewModel.isHovered`) and the Ask-on-Page and first-responder layer
change in split shape.

Per command:

- **Separate Page/Tab from Split View** (SP06). MainMenuAction36
  through the window's contents. The container removes the departing contents
  through `0x1e0`, immediately. Parc's `separateSplitTab` publishes once, and `render`
  diffs arranged views in place so surviving pages stay attached.
  content leaves through `0x1e0`. Parc keeps its original close transaction and
  re-renders immediately. The pane chrome X uses that same one-page close: it
  does not focus the pane first, because focusing posts native selection of one
  page and can unload the rest of the split. Sidebar child Close already skipped
  that focus step.
- **A split reduced to one child.** The surviving content keeps its pane, which
  takes the whole host in the same layout. Parc likewise hides the header and
  restores the single-page backing without layer actions.
- **Convert to the other orientation** (SP03). The difference pass sets `0x150`
  and `configure` lays out immediately.
  addPaneLeft/Right/Top/Bottom, separate, copyLink and flipLayoutOrientation.
  equalizes, and there is no menu selector, string or shortcut for one. Parc's
  former page-menu Equal Sizes command is therefore gone. The only equalization
- **Move Left/Right/Up/Down.** A reorder is `0x1d8`, which is immediate. Parc's
  `moveSplitPane` plus `render` are immediate.
  handles to alpha 0 and expands them in the same immediate layout
  the pane can reach the split only through the same difference pass, which is
  immediate. Of the container functions that reach the controller through its
  a mutating vtable slot; the rest only read it. Parc inserts, replaces and removes its temporary pane
  in the immediate render without detaching surviving pages (`pageWillDetach` is
  only for panes that actually leave).
- **Switching between a split and a single tab** changes the contents through
  the same difference pass, immediately. Parc's `render` diffs arranged views in
  place and resizes survivors in the same pass.
  to the content whose ID matches the focused content and weight 0 to every other
  and sends `onDidEndWindowContentsSplitViewPaneResize`) and lays out
  immediately. Later difference passes reapply those saved weights
  expanded field. A zero-weight pane keeps the 220-point expanded minimum, so
  every pane stays displayed.

  sender and no queue, so every browser window's container reweights its own
  focused pane. Parc does the same. Expand posts one notification, and each
  browser window that displays a saved split commits `expandedFactors(focusing:)`
  for its own focused pane through the resize-end transaction a divider drag
  uses. A window skips unchanged weights and lays out immediately. A window that
  is closing, creating a Space, holding a pending Add Split pane, in native
  fullscreen or transferring a tab leaves its split alone. The earlier presentation-only mode, which
  parked the other panes and offered "Show All Split Panes", is removed. The
  item keeps the title "Expand Current Split", and divider editing, drops and
  expanded-minimum redistribution resolves that weight to 220 points at any
  window width.

  Expanded weights can leave a divider whose saved pair cannot hold two
  expanded panes, even though the minimum redistribution displays the pair
  Parc then resizes from every pane's displayed length: a drag or double click
  moves only the space the two panes occupy, and every other pane keeps its size.
  A pair displayed at its two minimums stays put, as before.

REA records for this section: container difference pass
`ev_90405c7975c8d5c8b209d76b9a4902ff4c0e04ab682d594887481cdf623e3837`; weight
reapplication `ev_fb1a1ca96ded15ba18fe2e30b9b83106666c66bb283981943d284609f8d42baf`;
resize-end report `ev_9a06c5dbef31c78d36f3b6d918e52ffe3f8a35970762b309bfeda3f3fa281e96`;
Add helper `ev_19709968c3153cc20df4083fa591d03481def1dac222cfe41d1c5ece959443a9`;
top-bar hover owner `ev_164cc707908f7ffa13255b6e759a4ba25902184b526a84e2d313d4aed5439248`.
Each is paired with full-image instructions and the split controller's vtable
`ParcSplitView` and store. They cover Expand's persisted weights, its
220-point minimum at two widths and its unchanged-weight skip; conversion,
saved weight changes, removal, one-child dissolution and pending-pane insertion
and cancellation, all laid out with no layer animation; adding or filling a pane
keeps the original child in the same hierarchy; and drags and double
clicks of a pair displayed beyond its saved share, which move only that pair. The whole application


## Divider regions, pane input and content-resize reasons

is its handle minus the top 53 points of that `FlippedView`
(`(0, 53, width, height − 53)`; 53 = 40 + 8 + 5 from lazy globals
A stacked divider's region is its bottom handle inset 8 points at each end
recognizer only when `CGRectContainsPoint(draggableRegion, location)`. Parc
now uses the same regions for hover, cursor, pan admission and double-click
equalization; grips stay centered on the whole ten-point handle
`0x421` (entered/exited, key window, enabled during mouse drag), which Parc now
also uses. The last pane's trailing handle (the window margin) has its own
44-point region, described with the [right-margin handle](#right-margin-handle-sp33).

`userInteractionEnabled` false on every `SplitViewContentPaneView` when the pan
returns nil while it is false, so the point falls to the split container. Parc's
`ParcSplitView.hitTest` returns the container for any point inside a pane while
its divider pan is active, and restores ordinary hit testing when the resize
finishes for any reason.

**Content-resize reasons (Sidebar round 4).** The window container's
reasons of `contentSizeThrottleFlags`:

  `onDidBeginWindowContentsSplitViewPaneResize` and sets the bit
  sets nothing. The double click reaches slot 9 only through the update wrapper
  sends `onDidBeginSplitViewInteractivePaneEditingWith(.dragAndDrop)` and sets the
  when a delegate-admitted drag first creates the destination state. Slot 7
  `draggingExited:` keeps it.

Every mutator recomputes the mode from the remaining bits (`0x4` locked, any
other throttle, none intrinsic) and pushes it to each window content
`beginDividerPan` on the recognizer's `.began`, cleared by
`finishDividerResize`, which also covers owner, geometry, scale, detachment and
`onInteractivePaneEditing`. The edit is a `ParcSplitView.InteractivePaneEdit`
owned by the drag's route, not by any preview, session or `DropReservation`:
it begins on the drag's first admitted entry and ends only at the drag's
destination state does. A new drag's edit replaces an unterminated older one
without a gap; a split leaving its window ends it.

- Sidebar tab: `SplitDropView` (one overlay per drag) begins it in
  `draggingEntered` for its authenticated drag and ends it in `draggingEnded`
  or when the drag's finish removes the overlay.
- External URL: `ExternalSplitDropHost` begins it with the drag's first
  admitted session and keeps it per drag sequence. Leaving a page ends that
  page's preview and lease but accepts the router's handoff as a terminal
  witness, so the router stays claimed and the page view's own terminal
  `draggingEnded`/`concludeDragOperation` (the engine view calls the router's
  `end`) reaches `contentViewDidEndDrop` and ends the edit. Leaving the host's
  handoff area likewise keeps the handed-off router. The host's own
  `draggingEnded`/`concludeDragOperation`, a completed perform, an invalid
  recipient and detachment also end it; the host's own router releases do not.
  Re-entering the same page restarts its router, whose end and new `beginDrop`
  run in one synchronous AppKit callback: the edit ends and begins again
  before any layout, so pages keep the same lock.
- Guaranteed end: AppKit's terminal message to a destination the drag already
  left is not verified for drags from other apps, across windows or onto other
  controls. Each route therefore reports whether one of its receivers has the
  drag (`InteractivePaneEdit.isDragInside`). While none has it, a 50 ms
  common-modes check ends that drag's edit once the primary mouse button is
  up (`NSEvent.pressedMouseButtons`). A re-entry before release marks it inside
  again, the normal terminal callbacks end it first when they arrive, and the
  check ends only its own drag's edit, never a newer drag's. This is a Parc
  safeguard for a missed terminal callback; it does not end an edit while the
  drag continues.

BrowserWindowController maps both callbacks to `setContentResizeReason(_:active:)`,
whose existing `PageContentResizer` model throttles or locks the displayed
pages.

**Margins.** The container pins the split's trailing and bottom edges to the
`shouldDisplayDraggerPaneForSecondaryAxis` is set (initializer default true,
last pane, when `displayInteractivePaneInsertionDraggerHandle` is set (from the
indicator (contract below). Parc's page host keeps
ten-point margins and the split lays out n − 1 gaps; pane lengths, positions
and the 220-point minimum come out the same whenever the last pane carries its
that hides every scrim edge) outside ordinary split windows.

The window-state flags these actions also set (`isResizingPanes`,
`activePaneEditStyles`) have no field in the container's, pane's or handles'
view states; no visual consumer is attributed to them.

## Collapsed and fixed pane transitions

`ContentPane.DisplayState` (collapsed/expanded, byte `+0x41`) and `ResizeStyle`
(flexible/fixed, byte `+0x40`) feed the effective-factor algorithm
panes in proportion to their factors, a fixed pane receives none of it, and the
minimum-deficit redistribution covers every expanded pane. Collapsed panes have
`StateTransition.draggerHandleWidth`, when present, overrides the handle length.
expands it with style `animated(removePaneOnCompletion:)` (0/1) or `immediate`
implicit; no Reduce Motion read).

passes animated false, resize style flexible and immediate expansion; `remove`
those and the reorder/bulk updates with immediate layout. Drop regions: the
those as the reserved-region and border transitions above. `.fixed` is written
to the dormant pane drag (SP22); a collapsing view-controller pane's
none of that path, so no fixed or collapsing real pane exists to animate.

Native checks drive the actual `ParcSplitView`: draggable-region hover, pan
admission and double click inside and outside both region shapes; tracking-area
rects and options; reason 0x2 on pan begin only, clearing on end and on an
owner-change cancellation, with pane hit testing locked in between; reason 0x4
from the drag's first admitted entry, kept across exit, lease end and owner
invalidation, replaced without a gap by a new drag, and cleared by the drag's
terminal end; through the production external-URL host, kept across page and
host exits with the page router as terminal witness and across same-page and
other-page re-entry, cleared by perform, the page view's terminal callback and
the host's `draggingEnded`, and, with no terminal callback, by button release
while outside every receiver, with later terminals ignored; detachment and a
backing-scale change mid-pan clear 0x2 and the pane lock;
and the equalization, reserved-layout and border transitions with no Reduce
Motion gate. The whole application typechecks with the BrowserWindowController

### Right-margin handle (SP33)

The last pane's trailing handle (the page's right margin) is not a
for a page outside any split, and nothing drags it. Parc's implementation and
evidence are in the [SP33 inventory](#split-gesture-and-context-inventory--sp33).

### Contract for General navigation: bottom-handle loading indicator

Each pane's bottom handle (`SplitViewBottomDraggerHandleView`, the ten-point
strip under a pane, which in a side-by-side layout is the bottom page margin)
shows either the stacked-pane grip or a page-loading indicator:
`ViewState.handle` is `Handle?` with cases `dragger` and `scrimLoader`, beside
General navigation owner (NAV16 loading states), not divider resizing. The
Split views owner will keep the bottom handle region and grip unchanged and
add the indicator's surface on request. Status: open; no reply needed.

## Original split backing and pane corners

Split gaps now expose the existing window surface. The split host draws no fixed
separator band and does not clip its children as one large rounded rectangle.
Each original pane instead retains its own content backing inside a six-point
continuous rounded clip and casts its own content shadow outside it
([page card shadow](window-appearance.md#page-card-shadow)). An opaque webpage and a translucent Note can therefore
share a split without a white gap behind the Note. Returning to one pane restores
the existing ordinary/Note host policy. No native page, editor, focus, frame or
persistent split identity is replaced by this presentation update.

native NSView subclass with a weak drag delegate and no drawing override. It
sets `wantsLayer` and clears `masksToBounds`. Its browser parent
actual rounded content host and its content layer, using continuous corners.
background. Fresh REA consumer evidence is
`ev_4167b2ebd1d800ebdb4c3f4563a9bcf9fb1963d23544ffd42f83a60032fae8f0`;
full-image instructions and native type metadata establish these owners.

Parc implements this composition on its existing AppKit pane and page-host layers.
It retains the current window surface, so a full historical window-theme match
is not claimed. The reference's separate zero-radius conditional and its complete
fullscreen applicability are not yet attributed; this bounded change applies to
the displayed split and preserves the current single-page policy. Corner and
([command-driven split choreography](#command-driven-split-choreography)).
Native component checks cover the actual divider drawing, original pane identities
and geometry, both content backings, individual clips and single-page restoration.
No browser functional test was run.

## Original insertion-region border and ordinary pane updates

The original-tab and external-URL drag sessions always reserve an insertion
region, and that region's passive view draws the insertion border: transparent,
two points wide with a six-point corner radius, using the original window's
`maxContrastColor` with alpha replaced by 0.5. Appearance/theme changes resolve
the semantic color again in the view's actual appearance. The region adds no
event, focus or accessibility owner; proposal expiry and original session
cancellation remove its presentation. The former separate overlay
(`SplitDropPreview`) became unreachable once every admitted drag reserves, and is
removed.
Replacement is presented on the target pane's highlight border instead
([replacement highlight](#replacement-highlight-pending-pane-and-proposal-feedback)).

0.5. The metadata-backed palette field at offset 0x70 is `maxContrastColor`.
REA `ev_ec32bb36f6bb7a344920a83a1fc2ec8c7b15c8479f5277da5f39ed1256e0b823`
is paired with the full-image instructions, delegate witness and field metadata.
The placeholder constructor's four doubles are edge insets, not radii, as its
`WindowContentsContainerViewController.ViewState.contentInsets.top` (key path
controller's vtable `+0x148` flag is set. The panes' own inset witness
lines up with the neighbouring cards. Parc's panes have no window-level inset,
so the border spans the whole pane slot, header included
([drop placeholder card](#split-drop-placeholder-card-and-full-height-region)).
`colorWithName:dynamicProvider:` over the theme's light and dark palettes.
Incoming original sidebar tabs now reserve actual pane layout as described below.
External URLs use the exact native receiver handoff below. A split's own children are not drag sources ([SP30](#split-cell-container--sp30)), so no same-group source reaches this preview.

The bounded transition trace also distinguishes ordinary browser updates from
the original pane ID plus transition UUID before removal. Fresh REA
`ev_bd4ee3545ceffdc5bfd3c129acf49da7839aa311197f48fdc0dbbde72cd219e5`
and the actual caller instructions establish this distinction. Ordinary add/remove
therefore retain immediate publication; a generic insertion fade would not match
this recovered caller. Reserved-region transitions are covered below; command
choreography, including Expand, is in
[command-driven split choreography](#command-driven-split-choreography).

Focused native checks cover exact border geometry, semantic color refresh,
alpha replacement, passive input/AX, invalid/canceled proposal retirement and
existing single-use drag-session admission. The full application compiler also
browser functional acceptance. No retired surface or browser drag was exercised.

## Incoming-tab reserved layout

Dragging an original sidebar tab into a displayed group now reserves an actual
native region between the same original pane views. The incoming region receives
`1 / (original pane count + 1)`; existing panes preserve their relative factors
through the normal expanded minimum and backing-scale layout. The region's border
spans the whole slot, aligned with the neighbouring panes' tops (headers included).
Moving the pointer to a different insertion position reuses the same region;
remaining inside the reserved region retains that original target.

This is presentation state only. It creates no WebContents, local editor, saved
record or selection. A lease binds the original window, host, scale, pane/content
views, saved orientation and factors. Only its synchronous geometry publication
may differ from the captured frames. Outside geometry/owner changes retire it;
exit restores the saved layout. Before a drop commits, the region is cleared and
the existing original-page/local-document transaction validates the original
owners again. A failed save cannot leave an empty pane. Retained old divider AX
elements are unavailable while the reservation changes their geometry.

`ev_c7ef47033f2c2107423b29a4a8e01e4c763571d235f788ffe2e1223b91c161f8`
is paired with the full-image instructions. The factor map
filters the exact drop regions and requests their collapse/removal (REA
`ev_cdf198e047602598382a57a83cfe8d63b5473a306e82cad80b0924b24eff8bd0`).
Parc maps those ephemeral content entries onto passive native views separate from
its saved group and original arranged-view list.

The reference also animates collapse/expand and checks a transition UUID before
removal. Original live-pane expansion/restoration follows the layout timing
below, and the incoming border now uses the attributed transition described at
the end of this guide. Source-pane collapse and the source snapshot drag image
behavior ([pane-snapshot drag source](#pane-snapshot-drag-source)). The separate
source-factor and collapse branch therefore does not apply to sidebar children;
Parc's same-group sidebar preview remains SP29 work. External URLs now use the exact native-to-host
handoff described below, retaining
the original content receiver's authority while the pointer enters the region.

Actual native component checks exercise proportional geometry, region reuse,
original identities, exit/reentry, precommit restoration, stale layout/host
refusal, passive input and the absence of divider accessibility elements. Existing divider and
snap checks plus the whole-app compiler cover the shared layout owner. No browser
motion acceptance is implied.

## External URL reservation and native receiver handoff

An accepted external URL now reserves the same proportional insertion region as
an incoming sidebar tab. The original webpage or local editor stays alive and
retains its view, selection and document. When its shrinking native rectangle
releases the pointer into that region, the actual content-drop router explicitly
hands the same gesture to its existing ancestor. The ancestor cannot begin a
fresh URL drag over an empty gap or the empty content. It can continue only the
captured native view, window, pasteboard object/change count and drag sequence,
with the existing page/Profile/editor admission still valid.

Leaving the reserved region, original native `draggingEnded`, host teardown,
payload/owner changes and all existing security/focus gates retire the same
session. The region is cleared before the real durable drop transaction; failed
commit reports failure and leaves no empty pane. Local Note/Easel receivers use
the same router exit path, retaining their existing marked-text and rich-content
refusals. Browser requests, typed aliases and saved-home policy are unchanged.
The shared engine factory still returns its public protocol; the app does not
link directly to the ui/base implementation.

Arc1.122's `DraggingDestinationForwardingView` forwards entered/updated
distinguishes the internal pane payload from delegate-admitted external content,
retains the operation and dispatches subsequent updates through its subject;
fresh REA `ev_1750b5d90dd2cb0763a6076fbc170b860e3f13a97fed3b671ead23d4d0396200`
is paired with full-image instructions and the previously attributed URL delegate.
view exit ends the complete drag.

The explicit ancestor handoff is Parc's adaptation to independent Chromium's
[separate destination enter/exit sequence](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Concepts/dragdestination.html)
and [terminal notification even when a drag ends elsewhere](https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingended(_:)).
The only timer is the split drag routes' 50 ms button-release fallback, which runs
only while an interactive pane edit is live and no receiver has the drag, and
ends that drag's edit once the primary button is up
([guaranteed end](#divider-regions-pane-input-and-content-resize-reasons)). No
global monitor, URL re-admission or substituted native owner is used.
Component checks drive the production native router, host, local forwarder and
reservation on inert AppKit views, including terminal/cancel/reentry, stale
sequence/detachment, commit failure and precommit geometry restoration. Pinned
native and whole-app compilation are separate from browser or populated drag
acceptance. Replacement presentation is now the target pane's highlight border
([replacement highlight](#replacement-highlight-pending-pane-and-proposal-feedback)).

The actual local-view terminal component also exposed AppKit’s optional
`draggingEnded` selector: `NSView` declares it without an implementation.
Local forwarding now calls a superclass terminal handler only when that actual
superclass implements it, while always retiring the original drop router.
The inert native components cover both local views and text views, accepted
handoff, final cancellation, and exact original geometry restoration.

## Reserved-region pane motion

Incoming original-tab and external-URL reservations now move the same live pane
surfaces during expansion, retargeting and normal exit. The authoritative native
frames are published synchronously; their existing layers interpolate from the
current presentation to those exact frames over 0.2 seconds with ease-out.
Retargeting starts from the in-flight presentation. Before commit, stale geometry,
window/scale changes, detachment or key-window loss, the transition is discarded.
The existing reservation and transaction owners remain authoritative for geometry
A normal terminal callback revokes its session before external validation, so
reentrant retirement cannot validate or finish it twice.

removal. REA `ev_bd4ee3545ceffdc5bfd3c129acf49da7839aa311197f48fdc0dbbde72cd219e5`
is paired with the full-image instructions (artifact hash above).

Parc retains synchronous geometry and drag-authority restoration. The later
incoming-region border transition below now keeps only a passive retiring view,
with no delayed model, selection, focus or drop callback. This remains an explicit
([pane-snapshot drag source](#pane-snapshot-drag-source)).

Actual inert native checks cover animation endpoints/timing, immediate precommit
restoration, terminal reentry, ownership changes and key-loss cancellation;
existing divider/snap checks and whole-app compilation cover the shared layout

## Sidebar transition grip backgrounds

clears it. The retained REA consumer/finisher evidence is
`ev_6ab12b6f429c4fd3a98567be70678562b7ac415d94524cb332d73513de83c003` and
`ev_f4592a41ca8a97b4684fb64cca440edb3af58705dde83f423a4b292dfb324474`;
the source artifact is the same retained ARM64 executable identified above.
This is a passive background state, not a new pane or input owner.

The flag's only handle consumer is the handle's window-background view, not its
grip. `SplitViewDraggerHandleView` (a `FlippedView`) owns a lazy grip view and a
creates that background when `displayBackgroundView` is set, adds it below the
grip with `isHidden` = `_forceBackgroundHidden`, and pins it to the handle; the
where the bottom handle carries it). The window's handle view-state producer
background is a theme fill in the gap between panes.

Parc's gaps are already transparent onto the window's theme surface (see the
original split backing above) and draw no separate fill, so the anchored
transition has nothing to hide. An earlier increment hid the grip layers here
SP10 removed the flag with its Sidebar transition hooks (it had no remaining
during the transition. Renderer-acknowledged live resize throttling remains the
separate Sidebar engine contract.

## Incoming-region border transition

The real incoming reserved region now owns its two-point, six-radius,
max-contrast half-opacity border. Original-tab and external-URL receivers hide
their separate insertion overlay when this region is present. Every
original-tab drag reserves its region, since split children are not drag
`DragSourceState`.

`+0x41`: collapsed maps to zero and expanded to one. The actual three-view
These are retained full-image instructions paired with REA
`ev_bd4ee3545ceffdc5bfd3c129acf49da7839aa311197f48fdc0dbbde72cd219e5`,
from the reference artifact identified above.

Parc uses the same native region for expansion, retargeting, exit and reentry.
It publishes the logical slot frame immediately, the whole pane height with no
header inset. Its existing layer animates from current
presentation geometry and alpha. Exit restores original pane frames and removes
the drop region from admission synchronously, then contracts only the passive
border to a zero-axis frame at the restored insertion boundary. Completion is
limited to removing that same region under its current transition token;
reentry or a new reservation revokes it. Commit, invalid ownership, changed
geometry, window resignation, hiding and detachment discard the presentation
the transition nor an in-flight one depends on it.

The native layer representation and restored-container boundary mapping are
cross-pane source collapse is inferred. Actual native components exercise border
geometry/alpha endpoints, semantic ink, reentry over old completion, precommit
removal and original-window retirement. Compiler/component checks do not prove
populated optical or in-use motion parity.

## Split drop placeholder card and full-height region

split) showed two differences: Parc's region started below the pane-header band,
decompilation was needed.

the whole `WindowContentViewController` with its own top bar
([top-bar placement](#original-top-bar-container-placement)). Its
`SplitViewContentPlaceholderView` border is inset only by the window-level
`contentInsets.top`, the same inset the panes get, and zero beside side-by-side
panes ([insertion border](#original-insertion-region-border-and-ordinary-pane-updates)).
the border's top sits on the neighbouring pane's top row (y 30 px), the
interior is the window surface (213/194/196 inside, 207/197/195 outside), and
the 2-point border reads lighter than the surface. Parc's reservation now
classifies over the whole pane frames and lays the region over the whole slot.
(`ThemeChromePalette.appearanceBasedMaxContrast`): the theme's dark palette
appearance and its light entry otherwise; a single-value configuration ignores
the appearance. Which form a theme with a forced appearance builds is decided in
light or dark palette by the view's appearance for every theme; a private
window's theme is the incognito theme's palette (`ThemeRendererView.paletteTheme`,
[private window theme](window-appearance.md#private-window-theme)). Parc's page
host takes the application appearance (private windows force dark Aqua), as

pane's size: `view.bounds.width / (contentPanes.count + 1)` by
(options none, `forView:` the split's unflipped `DraggingDestinationForwardingView`)
origin and the image's size. The card therefore grows up and right from the row
image's bottom-left corner and follows the pointer like any drag image; AppKit's
between insertion slots does not rebuild it. `draggingExited:`
`NSDraggingItemEnumerationClearNonenumeratedImages` (0x10000). Prepare
(destination-state bit 8, written by `draggingEntered:` when the pasteboard
dropped tab's card disappears and the new pane takes the reserved region; a
cancelled drag slides back as the outline's default.

an infinite side) and builds `SidebarUI.SidebarContentDragPlaceholderView(icon:title:)`
URL its link glyph and `absoluteString`. It sets the
page snapshot is taken. The view (an `NSView` subclass) has
bold via `convertFont:toHaveTrait:` 2, centred, three lines, word wrapping,
truncating its last line). The stack is centred and at least 8 points
measures 123.5 × 250 points with the icon centre 105.5 and title centre 145.0
points below its top; Parc's render gives 104.3 and 145.0.

**Link card icon.** The URL case draws the three-byte string U+E98A
square image of side `ceil(max(width, height) × 1.1)` from
character. Parc already ships that font byte for byte
(`Resources/CustomInfoPicker/icomoon.ttf`, provenance and SHA-256 in that
folder's README), and `SidebarIconCatalog.emojiImage(_:size:)` already draws
this icon kind exactly so. Nothing sets a colour or template flag, so the glyph
The link card uses that image at 22 points (25 × 25).

**Parc.** `SplitDropPlaceholderCard` is that view, sizing and bitmap.
`SplitDropView` (now its own file, driven by `SplitDropCardSource`) presents the
card on each accepted entry for the session's own item, with the source row's
favicon and title (`SidebarTabRow.splitDropCardContent`) and the reservation's
`incomingPaneSize`, only while the reservation is current. A link drag's
session presents the link card when the page admits it. Explicit adaptations:

  image changes only from entry and update, and Parc's sidebar sets no images
  of its own, so a cleared image is not guaranteed to come back. Parc instead
  puts the item's own image back at the same bottom-left: the row's
  `splitDragImage` for a tab, and the link's own image as its source provided
  it for a link. A link from another app may keep its image to itself
  (`contents` nil); its own image then relies on AppKit's documented automatic
  restore. Only a drag that showed a card is touched; the drop and the drag's
  end forget it.
  hovered, taken before the row takes the key-dragged state, at the row's
  split cell's drag image already is. Several dragged items keep Parc's count
  pill.
  bitmap shows the fill), and items are updated in screen coordinates, which,
  `bitmapImageRepForCachingDisplayInRect:` on a view that never joins a window,
  and AppKit gives that a 1× rep. It takes the application's appearance for the
  same reason, not the destination window's.

Josh's reference card also shows the background faintly through its black
(green-tinted at its top, pink at its bottom), so the system composites drag
images slightly translucent; an offscreen render cannot show that.

**Open.** A link dragged straight onto a pane header from outside the window
starts its split preview only when it reaches a page, because the page's own
header. Not traced: the `+0x148` flag and the window `contentInsets` producer
(Parc has no window-level content inset) and the forced-appearance palette form
above.

Checks: `scripts/test-split-drop-card.sh` (sizing, 1× bitmap, structure, a long
title's three lines, fill in both appearances, the link icon, item updates
and restores through a recording dragging session, the ink under both
appearances for every forced theme appearance, and the real `SplitDropView`:
card only for an accepted drag, the row's own image and size back on exit, no
enumeration for a refused drag), the native drop session
(`tests/NativeContentDrop/run_components.py session`: whole-slot region,
incoming size, header targets, link-drag header handoff into a single pane's top
zone, link card and its restore), local document drops, drop geometry,
dividers, divider snap, split context, Space Manager and the whole-app
typecheck. No browser or live drag was run.


## Original pane symbol controls

The split menu and close controls in the existing pane header and ordinary
medium and `xmark` at 15-point medium, and applies `TopBarButtonStyle`'s symbol
consumer, not a generic toolbar-style guess.

rounded background. `FullOpacityForegroundPrimary` is black in light appearance
and white in dark appearance. Enabled glyph opacity is 0.55/0.675, respectively;
disabled is 0.25. Background opacity is zero at rest or while disabled, 0.05/0.09
while hovered, and 0.09/0.13 while pressed. Press takes precedence. Hover uses
0.18-second ease-in-out; press uses 0.16-second ease-in-out. The original named

AppKit `NSButton` retains native input, keyboard focus and a single named button
AX element. Its cell's actual highlight drives the passive press surface; its
glyph has no hit-test or AX owner. Original page/menu callbacks are unchanged.
Obsolete tracking events cannot change current hover; disabling, hiding,
detaching or original-window key loss clears decoration. Appearance changes and
Reduce Motion retire in-flight decoration. These lifetime guards, native focus
ring and Cocoa tooltip timing are explicit AppKit adaptations of the SwiftUI
button. The surrounding row now follows the attributed container below;
ordinary and modal visibility follow the attributed state below ([modal obstruction](#modal-obstruction-and-reveal-transitions)). This does not
establish genuine pane-drag initiation or alter Developer Mode's separate owner.

REA evidence is `ev_f4314ef1b7475af9d9fc2466e13b6f56619ed6b9d721bd8bb99986ecce16c114`
and `ev_5434376870becda597862a92029a41238209220359f978a66f429e25eac44bd9`, from
bounded original slices with configured Ghidra and full-image callee/global
attribution. Original ARM64 SHA256 is
`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Appearance-only inspection exposed the installed single-pane Split View Menu and
restored the original toolbar/window state; it did not execute a split action.
Focused native components cover action admission, exact tracking, real cell
highlight, light/dark states, hidden/key/detach cleanup and toolbar containment.
No functional browser test or final populated optical comparison is claimed.


## Original top-bar container placement

The split header and ordinary Toolbar share the original 32-point row height
through `PaneTopBarLayout`; the 32×24 split controls sit four points from its
top and bottom. The row has five-point leading/trailing padding and centered
vertical alignment. Its content inset uses the row height independently of the
button hit surface. Original native content, title action, menu/close owner and
Developer Mode's separate strip remain unchanged. Peek's existing outer-card
layout uses the same ordinary Toolbar metric without changing that card owner.

with vertical-center alignment, then explicit five-point leading and trailing
padding. This establishes the parent size and placement independently of a
screenshot or the button style.

REA records `ev_8b8bb5ae0b4583e3f0e24faf4240914639fae50fa84764678bfee22e3174f49c`
and `ev_468b221c841a1d85f26dd1b1027558403b068feb49985055e40507ec56e2f734`
are paired with full-image calls, imports, actual class ivars and constants.
The raw-slice decompiler does not recover the Swift aggregate ABI by itself.

The title's attributed presentation is connected below. Its parent allocation,
non-split control glyph sizes remain separate; edge room and modal visibility are connected below
comparison work. The
original helper's optional Peek overlap and older content-panel branch are
recorded rather than applied as a guessed general split rule. SP27 remains
LEFT. Native components check actual Toolbar frames at six widths, centered
controls, trailing padding and original action/retirement behavior; full app
browser test was run.


## Ordinary pane control visibility

Ordinary split pane menus now retain opacity one for the original focused pane,
for a pointer inside the expanded top-bar region, or while their actual menu is
tracking. The background pane otherwise reserves the same control frame at
opacity zero. Close is independent. Every pane's bar shares it, and the same
value also drives Reload, Site Control Center and the extensions control
([modal obstruction](#modal-obstruction-and-reveal-transitions)); it neither
selects a page nor changes the existing native button, accessibility or
exact-page action owner.

`!isObstructedByModal && (!onlyShowEssentialControls || isHovered ||
visibilities.isPopoverShowing)`. Actual class ivars, Published keypaths and
applies that predicate to menu opacity; its Close branch does not. The parent
`onlyShowEssentialControls = !isFocused`.

The native parent installs a weak window-bound `HoverRegionTracker` at
`isHovered = state != .none`. `HoverState` is `none`, `inside`, `hasLingered`,
`hasStopped`: the region's registered 0.15-second linger duration does not delay
active and original-window key state and their notifications.

Parc registers a passive tracking area on the original window content view so
the region can extend above and below its pane bar. Pointer sampling still uses
the actual flipped pane coordinates. It intersects registration with the native
window content bounds; out-of-window tracking is not claimed. Obsolete area
identity, hidden/detached panes, changed original geometry, application
resignation and window key loss revoke hover. Reattachment/key activation
resamples the original pointer. Synchronous `NSMenu` tracking is the explicit
AppKit substitute for the retained popover flag; it does not extend an action
lease. The original modal/Peek state mapping and reveal transition timing remain
separate open comparison work; this change preserves their previous behavior.

Fresh configured-Ghidra records
`ev_d900cf1a677542f3abb34a072756607c5c5427d27b9d6b1a85b383e033127a87`
and `ev_55db4ec8e249659de86366b4ae6539f0fc4884cb94581dd8f410fdbee408251b`,
plus hover callback records
`ev_e14d78b06ae8fb10d9fc91a5c1d874ebba1db98ab364c74d6724ebbc8aeb73f0`
and `ev_c7be9643c2891aeffa591c464fdbc1c1a074f08c99c311a7c055936077c5b0df`,
are paired with original-image metadata, constructor arguments, delegate witness
and native layout instructions. Reference artifact/hash are as above. These
SP27 remains LEFT.


## Original pane title presentation

The compact ordinary pane header and ordinary Toolbar now share the native
`PaneTitleControl`. It preserves the actual original button action and uses
passive text/layers for presentation: 13-point medium primary text, 13-point
regular suffix, centered text with four-point vertical/six-point horizontal
padding, and a continuous six-point background. The padded native hit surface
fits its text inside the parent's available title slot rather than stretching
its highlight across that slot. Local Note/Easel authored titles remain titles;
ordinary live web panes receive their exact native page URL.

appearance and white in dark appearance. Primary alpha is 0.6/0.75; secondary
alpha is five-sixths of primary. The native `NSFont` calls specify the two
13-point weights. Padding, continuous corner and the state-animation values are
and standing highlight: light/dark alpha is 0.11/0.15 pressed, 0.07/0.11 hovered,
0.05/0.09 standing, and zero otherwise. The ordinary constructor passes standing
highlight false. Press changes use 0.16-second ease-in-out and hover changes
0.18-second ease-in-out. Native button-cell highlight owns the press state;
passive text has no separate hit target or accessibility node.

The latter removes one trailing `?`, then one trailing `/`, then one leading
`https://` or `http://`, then one leading `www.`, and lowercases when its actual
returns a distinct suffix only when full URLs are requested and the long display
an ordinary HTTP(S) title without a visible suffix, and tail truncation with a
suffix; other title kinds use tail truncation. The body omits the suffix when
its original `urlDomainHasRoom` visibility is false. The full attributed pair's
measured width now owns that decision, as traced below; parent center-stack
allocation remains distinct from this title measurement. Copy/navigation and accessibility retain the unmodified
service's separate title branch is not copied into generic web behavior.

Fresh configured-Ghidra evidence is
`ev_8cfc00e862ae3d5b15a9a2064e4f4e737a89c4c61c7d087c6aaa8bb5900ba5dc`,
`ev_336789b9d685b90b038fb8385f0e6743ceaa3e03185c4f89e741c4b521acfb31`,
`ev_e77b0b2cc133dba5c96424f5c7c8a49309a2ea860b3d3706039494073b3f2220` and
`ev_7a7b93387ce8988b02ef603bfb79a0031916cabe6ee70f52698624d1de8a35bd`.
Original function boundaries, class fields, keypaths, named-color initializer,
SwiftUI imports and scalar constants are retained alongside those records;
raw-slice pseudocode alone does not name Swift aggregate fields. Artifact/hash

### Complete-title fit and frame publication

The original `TopBarPanelViewModel` subscribes to its `framesSubject` with

`measuredPair + 16 + 10 <= urlFrame.width + 2 * min(leadingSpace.width, trailingSpace.width)`.

This is a full-pair measurement; fitting only the host is insufficient. Parc's
native title occupies the center of its allocated slot, so the right-hand side
reduces to that slot's width. Narrowing below the boundary omits the suffix and
retains head truncation for the original web host. Expansion restores the same
retained suffix. The native button still hugs its text with twelve points of
horizontal padding; the extra fit allowance is not part of its hit surface.
The parent allocation is retained separately from the smaller button frame,
so appearance/hover/native layout cannot oscillate this decision. New original
content is measured again; the URL, authored document title and action are not
reconstructed from the visible text.

Fresh configured-Ghidra records are
`ev_3c7f4b57a14e6bb8c539e38692c767aa50b06ad62e3c342d3bc02420aaaf5bb7`,
`ev_661c753a9c6bb063319783c22f142febd9cca80700a86411d2c6001726da39f5`
and `ev_d617f82aef63e6fa553e8c457a61b9c8167b1181e0ac7e3b479ebb481d1d00c2`.
They are paired with the original frame field offsets, imported native calls,
subscription and padding initializers. The separate center-width consumer
subtracts twice the larger essential-side occupancy plus four, with a 150-point
floor. Its actual caller applies that limit to the complete seven-child center
HStack, including spacers and balancing controls. It is not a minimum title
button width. Mapping that whole stack, its modal/action state and the populated
appearance remains SP27 work; this delivery does not force the floor onto the
native title or change existing control placement.

AppKit text measurement, existing parent width allocation, Cocoa focus ring,
Reduce Motion and obsolete-tracking/key/hide/detach cancellation are explicit
native adaptations. Existing compact-header activation and Toolbar address-entry
owners now follow the original title click and URL menu ([title actions](#title-click-and-url-menu)); modal
visibility and full populated optical comparison are still SP27/SP32 work.
Focused native components exercise actual attributed runs, width changes,
light/dark states, original cell press, passive AX/hit testing and lifetime;
whole-app compilation is not a browser functional test or a final optical match.


## Center stack and edge collisions

The title now centers on its original pane rather than the unused gap between
zero-spacing center HStack independently of the outer navigation/accessory row.
Link, an optional insecure indicator, URL text and disabled balancing slugs.
24-point surfaces with trailing −5 padding, not extra actions. The existing
Copy owner now occupies the corresponding leading 19-point footprint.

The measured left navigation group publishes `Frames.leftEssential` through
uses the larger original edge reservation on both sides, subtracts four points,
and applies the recovered 150-point **whole-stack** floor before allocating the
title. Contents without a page use the same bar and allocation
([below](#essential-edge-groups-and-room)). Actual frame comparisons hide colliding
Copy/Reload/site controls and bound pinned extension room. Their frames remain
stable for the calculation, so hiding an optional control does not oscillate
the title. Existing action, page, selection and native focus owners remain in
place.

Fresh bounded REA records are `ev_08f07655e8316ffa3a33b5d6d8d3f137006970bf90f1eb41b2a89d6d34e1ddbe`
(center builder), `ev_fd5cc2214f6ed14dad46fe2c54e6ff2de57cc0559b0dbf626ca29cac8a69e321`
(left publication), `ev_2aaed7c680f904dfba897dd0466d300cf1fc6389f3b698e910aae0cde10b908b`
(right publication), and `ev_e298ded19aa4434a85227a5fb8ea5e46451f4eaa7668d8bfd8834c446c13e908`
(extension-room reducer), against the retained Arc1.122 ARM64 artifact.

The existing non-Split native glyph sizes and Copy glyph remain presentation
adaptations; the invented width thresholds are replaced by the original
[essential groups and room rules](#essential-edge-groups-and-room). At
unusually narrow allocations, the real title is contained between still-visible
essential controls even when that constrains the reference stack floor. The
insecure lock, modal visibility and title actions are connected in the sections
that follow. These component/compiler checks are not browser functional or full
visual-parity acceptance.


## Insecure lock and secure-context carrier

the URL whenever the page's visible security level is neither neutral nor
secure. A second clear slug balances it on the trailing side, so the title stays
centered on its pane.

- **Carrier.** `TopBarPanelViewState.secureContext` is `ADK.SecureContext?`
  `-[WebContentChromium webContents:didChangeVisibleSecurityState:]` converts
  Chromium level it reads: `NONE` → 0, `SECURE` (3) → 1, every other level →
  2. Parc's engine overlay adds `PCNativePage (SecureContext).secureContextState`
  with the same mapping over `chrome_security_state::GetSecurityLevel`, so HTTP
  (`WARNING`) and broken HTTPS (`DANGEROUS`) are insecure while file and
  localhost pages stay neutral. `DidChangeVisibleSecurityState` already notifies
  the page observer, which reaches `updateNavigation` and the Toolbar.
  The Swift side checks `responds(to:)`, so an engine without the overlay shows
  no lock. Overlay: `Engine/ParcNative/native_appkit_bridge.h`,
  `native_appkit_page.mm` and their `Engine/ParcHost/overlay.json` hashes,
  pending the engine owner's apply and build.
  .insecureLock)` (enum payload 4 / tag 5), `.disabled(!controlsAreEnabled)`
  with the foreground-opacity flag off, so the red stays at full opacity,
  0.16 s) still applies. A second slug follows the URL only while insecure
  `SplitPaneControl(.insecure)` reuses the native symbol control: a 24-point
  slot and surface, `NSColor.systemRed`, the symbol hover/press opacities, one
  AX button. Its 24-point surface sits 19 points before the title and overhangs
  it by five; the title stays above it for hit testing.
- **Action.** The button sends `TopBarPanelAction.delegateAction
  that is, opens or closes its Site Control Center. The top bar presents that
  anchors it at `Frames.siteControlCenterButtonFrame` (offset 0x28) with
  button was clicked. Parc therefore sends the lock click to the same owner as
  the Site Control Center button, `showPageMenu(from:)`, anchored at that
  button (its frame is kept even when the button yields room), after the same
  pane admission.
- **Adaptation.** Parc's Site Control Center remains its existing page menu.
  Contents without a page have no secure context, so their bar has no lock.

## Modal obstruction and reveal transitions

(`ModalContent.PresentationState?`, enum byte at +8: `awaitingDismissConfirmation`
0–1, `initial` 2, `presented` 3, `dismissing` 4, nil 5) and passes the

- `isObstructedByModal` (state field 14) = initial or presented;
- `onlyShowEssentialControls` (field 12) = false when focused or dismissing,
  otherwise true;
- `dividerBehavior` = `.onHover` for the modally presented content, else
  `.always`.

ease-in-out; focus and menu changes carry no animation.

Parc's `PeekController.modalPhase` reports presented, awaiting dismissal
confirmation or dismissing; the window refreshes when a confirmation arms or
expires. Each pane's `controlsObstructed` and `controlsFocused` follow the
mapping above, `PaneControlVisibility` publishes
`!obstructed && (focused || hovered || menu)` with the original duration, and
`BrowserToolbarView.setControlsRevealed` applies it through `PaneTopBarFade`
(immediately under Reduce Motion) to the menu, Reload, Site Control Center, the
pinned extensions (the Site Control Center holds the rest, WEB14); room still hides a control. The ordinary
bar, with Close still shown for a split pane; its actions remain refused by the
existing page admission while the Peek owns input, and the obstructed bar offers
no URL menu, so its preference items are not reachable underneath either. A
Developer Mode page has no top bar (see below). The Peek's own Toolbar is
unchanged.

## Title click and URL menu

- **Click.** `URLTextView.onClickURL` → `TopBarPanelView.onClickURL` → the
  `WindowContentAction.onDidClickTopBarURL` (case 27). The window reducer branch
  pane's bar does the same: it focuses its pane, then `focusAddress()`.
  `menuProvider()` and pops the menu at `NSEvent.mouseLocation` with no
  `commandBarToolbarContextMenuActions` (State field 41). The list builder
  second call, with its placeholder flag off, feeds field 41. For a content with
  a URL it yields: Copy URL; for a tab, Share, Capture…, Capture Full Page and
  Capture in Portrait Mode; when the extension predicate holds, a separator and
  Manage Extensions…; then a separator before Show/Hide Full URL (tab only,
  toolbar list only), the Toolbar toggle (“Show as Toolbar”/“Hide Toolbar”) and
  Enable/Disable Shared Quotes (tab only). The toggle is omitted only when
  Toolbar; with the shipped default it is always present.
  Portrait Mode an Option alternate (`setAlternate:`, mask `0x80000`) and Share a
  Toolbar toggle to MainMenuAction 56 and the full-URL and Shared Quotes toggles
  to preference keys 76 and 126.
  services from `+[NSSharingService sharingServicesForItems:]`; the model is
  …” items only for pasteboard items, so for a URL every service sits directly
  in the submenu as a callback item titled `menuItemTitle` with the service's
  `PaneShareMenu` builds the same submenu for the pane's original page URL. It
  macOS 13 SDK marks it deprecated (warnings are errors), so Parc reaches that
  class method through `NSSelectorFromString` as an SDK-deprecation workaround
  rather than substituting the picker's standard item, which adds its own
  entries.
- **Parc.** `PaneTitleControl.menuProvider` asks its owner for a fresh menu on
  right-click (and the AX show-menu action); `BrowserWindowController
  .paneTitleMenu` builds the list above. Page actions re-admit their original
  pane through the Toolbar's existing page admission (which focuses that pane)
  and then reach `copyCurrentURL`, `capturePage(.region/.fullPage/.portrait)` and
  `BrowserToolbarPreferences` and `SharedQuotePreferences`. The Toolbar toggle
  is omitted in popup windows, which have no Toolbar. While a Peek is presented,
  no other pane's bar returns a menu.
- **Content classes.** The list builder returns no actions without a content
  2–5 and 7 keep the section only when the content or its blueprint is absent
  maps Parc's panes onto these classes: a live page (including a navigation
  error, a renderer crash and Parc's own web pages) or an ordinary tab whose
  page is not created yet is web content and gets the whole list; a Note or
  Easel is a document and gets Copy URL and the Toolbar toggle; a blank start
  page has no URL and no menu. The captures stay disabled until the tab has a

## Essential edge groups and room

The Toolbar's invented 300- and 340-point thresholds are gone. Sidebar, Back,
(`Frames.leftEssential`/`rightEssential`) and always lay out; the left
Reload's maxX before Copy's minX while copying is available, else before the
element — Copy, else the insecure lock, else the URL — so it cannot cover the
Room hides a control; the reveal predicate above sets its opacity. Very narrow panes still contain the title between the essentials (the
pane minimum is 220 points), an existing adaptation of the 150-point stack
floor.

**When a pane has a top bar.** `WindowContentViewController.State
.topBarDisplayedPreference` (field 81, the Toolbar preference toggled by
default, then, a hidden Toolbar leaves every pane, split or not, without a top
bar; the split menu, Close and Add stay reachable from the sidebar split
reads the web content's `developerModeContextFlags` (`WebContentState` field
16): Developer Mode content has no top bar, its panel being a separate owner.
When the Toolbar is shown, each content's top bar is the whole
TopBarPanelView, whose builders gate nothing else on the split or the content
`shouldShowSidebarButton` only for the hidden-sidebar (`noChrome`) style and the
`shouldShowWindowControls` or `shouldShowExpandButton`, `shouldShowSplitViewClose`
for a split pane, and back/forward availability from the content's own

Parc shows that bar when the Toolbar preference is on **or** the window is
displaying a split of two or more panes (not in a popup, the Library or tab
shown the per-pane chrome on splits; there is no Settings row or menu item
that turns `show-toolbar-in-split-view-enabled` on, so treating the recovered
binary fallback as "leave it off" hid the bar. Show Toolbar remains the
single-pane toggle. Every content kind uses the same `BrowserToolbarView`: a live page
through its existing page owners, including while a navigation failure or a
web content's top bar, not by the page view's visibility); a Note, an Easel, a native page or the start
page through `configureDocumentToolbar`, with its authored title, the
navigation group disabled (no history or reload), no Copy, lock, Site Control
Center or extension controls, and the split menu, Close (split panes only) and
the same title click and URL menu. The sidebar button appears only on the
leading displayed pane while the sidebar is not locked. The populated pane
menu is Move, Add Right/Left (or Top/Bottom), Separate, Convert and Share
Split View… (system share of the split's page URLs). The URL menu omits the
Toolbar toggle while a split is showing, because that bar no longer depends
on the Toolbar preference.

`WindowViewController.ViewState.isCommandBarPlaceholderVisible` (field 17,
with the YouTube pane focused), with Back, Forward and Reload left to the pane
bars. Parc follows the installed app: `PaneTopBarAdmission.sidebarAddressBarShown`
hides the URL bar only for the Toolbar preference, and
`SidebarView.navigationInContentToolbar` moves Back, Forward and Reload to the
focused pane's bar. The URL bar's text, click (command bar for the focused
pane), Site Control Center and pinned extensions stay on the focused pane as
before. Extension popups anchor at the URL bar whenever it is visible, as
content view, so in a split they now open from the sidebar rather than the
pane. Commit `aabe63c5` (October 30, "Keep live split
pages attached when adding a pane") made splits always show pane bars, and the
sidebar's existing `usesContentToolbar = selectedBrowserToolbar != nil` then hid
the URL bar in every split; this restores it.

Every pane's bar shows Copy when its page can copy a link, focused or not, as
November 1 reference shows it on both panes). Clicking it focuses that pane
first and then copies its link. The empty URL bar reads "Search or Enter URL…"
(`CommandBarIconView`, `IconType.searchOutline`) beside `CommandBarTextField`'s
window. The constraints were not recovered: `SidebarAddressSearchIcon` places
the glyph's centre 16 points and the text 34 points inside the field, measured

## Top-bar page colour

for contrast (Josh's November 1 references: the 1Password extension page's bar
blue, ChatGPT's black, YouTube's #0F0F0F, each with white ink). Recovered from

- **Fill.** `TopBarPanelViewModel` publishes `backgroundColor: CGColor?` and
  content without a blueprint, otherwise `Color(cgColor: backgroundColor)` or
  frame of that fill with `.animation(canAnimate && blueprint != nil ?
  `emptyWindowContentBackgroundColor` (white at 0.666 in Aqua, 0.1 in Dark
  Aqua, over the window surface; see [window appearance](window-appearance.md)).
- **Source.** `TopBarPanelContainerView` conforms to
  `canAnimateBackgroundColor = true` and `backgroundColor = color.CGColor`.
  {colorToDisplay, currentColorSample, numConvergenceAttempts,
  requireConvergence, lastUpdated}`, a `domainCache: [String: Entry(color,
  lastUpdated)]` persisted under the `TopBarColorCache` default
  listeners and an access queue. Its update method (vtable slot 36,
  follow-up check with `asyncAfter` on main. `ADK.WebContentFeatures` publishes
  `themeColor`, `sampledPageTopBandColor` and `rootBackgroundColor`.
  renderer `arc::TopBandColorTracker` (`arc/blink/core/top_band_color_tracker.cc`;
  `ScheduleDetection` `0x4683ecc`/`0x46876a0`, `FireDetection` `0x46849d0`,
  detection `0x4684c40`) behind `kTopBandColorSampling` /
  `enableTopBandColorSampling`, reported through
  `webContents:didSampleTopBandColor:shouldCrossfade:`. The detection works
  on layout boxes (LayoutUnit ÷ 64 conversions, a 255 channel scale) and has a
  YouTube special case for `ytd-masthead`; it is not a pixel copy. That is
  why the 1Password bar is blue while the visible top of that page is dark
  navy.
  0.0722, (L1 + 0.05) / (L2 + 0.05)). White wins ties (`fcmp`/`cset pl`) and
  gives `.dark` (`_$s7SwiftUI11ColorSchemeO4darkyA2CmFWC`). The composites drop
  without a blueprint the same choice runs on the theme background under white
  client's vtable) returns at once for a nil colour, so the displayed colour
  stays until the next sample. With `requireConvergence` it re-samples up to
  empty result while the frame has no layout yet (`0x4684b10` →
  `0x4687028`). The detection starts from a default colour and keeps a
  resolved one only when its alpha is at least 1 (`0x4684dd0`–`0x4684e50`);
  what it reads there was not traced.

Parc: `PaneTopBarColor` implements the contrast choice and the 0.18-second
crossfade, and takes its backing from `SplitPanePlaceholder.emptyContentBackground`.
`BrowserToolbarView.setPageColor(_:for:holdingWhileUnknown:)` fills the bar,
applies a newly shown content's colour at once and crossfades a later change
for the same page, and gives its controls the scheme while the bar itself keeps
the window's appearance for the backing. `BrowserPane` paints its white page
backing only under its content, and the page host turns clear while a pane shows
Notes, Easels and blank pages stay clear, as `TopBarColorClient` tracks web
contents only. A bar is clear while a navigation failure or renderer crash
covers its page, and a hidden bar forgets its colour.

**Colour source.** `PCNativePage.topBarColor` (`PaneTopBarPageColor.swift`) is
the page's declared theme colour (Chromium `GetThemeColor`, read through the
existing `developerModeTint`, which is always opaque), then
`pageBackgroundColor` (overlay 293, `WebContents::GetBackgroundColor`), checked
with `responds(to:)` so older engines use the theme colour alone. Chromium's
background is the root CSS background composited over the base background,
white or the dark canvas for `color-scheme: dark` (`local_frame_view.cc`), so it
is opaque in Parc; it is nil only until the renderer first reports it for the
current document. A page declaring neither therefore shows white (or the dark
top band and a page painting nothing there shows its canvas, but the
tracker's fallback is not recovered.

**Delivery.** Chromium resets both colours for each committed primary
document and notifies the background only after the first visually non-empty
paint (`web_contents_impl.cc` `OnBackgroundColorChanged`). The page observer
notifies on `DidChangeThemeColor` and `OnBackgroundColorChanged` when the
colour the bar shows changes: `NativePageShellNotifyState.top_bar_color` holds
`TopBarPageColor(theme, background)`, so a background animating under a winning
theme colour does not notify. `PCBrowserView.nativePageDidChange` compares the
published `developerModeTint` and `pageBackgroundColor` (`isEqual:`) and calls
the optional `browserViewDidChangePageColor:`. The window repaints only that
page's visible pane bar and `PeekController` only its Peek bar, through
`BrowserToolbarView.showPageColor(of:failing:)`, never the window's chrome,
because background transitions can notify per frame. Full configuration uses
the same call. While the same page is loading without a colour, the bar keeps
its last one, so a full navigation does not blink colourless; a page that
finishes loading without one clears it. From overlay 294 the engine reports
notify and delegate path, and `TopBarColorClient` chooses the colour: the
page's latest sample, else its site's cached colour, else white, with the
engine's `shouldCrossfade` deciding whether a change animates; see
[top-band colour](top-band-color.md). The theme colour and background remain
for engines without it.

included. Without a page colour Parc picks the ink from the backing over the
light theme in Dark Mode keeps readable ink; there the composites are decoded
a dark theme in a light window. A Peek's colourless bar sits over Peek's own
popover material, so its ink follows the window's appearance, as the material
does.

Adaptations and gaps: until overlay 294 is built, Parc's engine has no
`TopBandColorTracker`, so a page's declared theme colour and composited
differs from both shows the wrong colour (the 1Password onboarding page takes
client's convergence, timing and domain cache ([top-band colour](top-band-color.md)).
window-scheme branch rarely shows. `ContentPanelViewState.webContentTintColor`
(the content backing's tint) was not traced. The split menu's artwork is
described [below](#split-menu-artwork). Offscreen renders (`build/split-chrome-renders`) match the reference bars'
sampled blue in by hand. The theme's behind-window material and Metal canvas
are a painted stand-in there. No browser was run.

## Split menu artwork

and `.flipToHorizontal`). Every item gets its own image, loaded by name from
`icon-split-move-left`/`-right`/`-top`/`-bottom`,
`icon-split-add-left`/`-right`/`-top`/`-bottom`, `icon-separate-from-split`
(type 5) or `icon-separate-from-split-menu-bottom` (6),
`icon-split-share-horizontal` (7) or `icon-split-share-vertical` (8), and
`icon-split-vertical` for Convert to Vertical (9) or `icon-split-horizontal`
(10). That the odd types belong to a horizontal split and the even ones to a
vertical split is read from the asset names and the Convert pair; the caller
that builds the type list was not traced.

The images are not templates: each has a light and a Dark Aqua rendition, the
frame in a lighter tone than its arrow or plus, and Separate's arrow blue.
Parc copies them into `Resources/SplitPaneMenu` (provenance and hashes in its
README), and `SplitPaneMenuArtwork` draws the light or dark rendition for the
appearance the menu draws in. The menu takes its pane bar's scheme, so it is
dark over a dark page colour. Order, titles, separators and disabled rows are

Parc's earlier SF Symbols were never drawn because macOS 27 hides menu item
images unless an item asks for them: the 27.2 SDK's `NSMenuItem.h` says AppKit
"will typically hide images" and adds `preferredImageVisibility`, and Parc
builds against that SDK. An offscreen `NSMenu` grew to fit its image only with
older SDK, keeps its images.

`tests/SidebarRows/SplitPaneMenuTests.swift` checks each item's artwork pixel
for pixel against both renditions in both orientations, its size and its
visibility. Offscreen renders of the real items, light and dark, sit beside
and disabled dimming there are drawn stand-ins, as AppKit's menu window cannot
render offscreen.

REA records: `ev_454013c4f097199b67a1f1f2a6dd651400540a589357f7029f29ece1d713ec8d`
(`4e452201…9547`); the rest is annotated disassembly and the type, string
detection's start were read with bounded `llvm-objdump`.

## ⌘S slide pinning (Sidebar round 3)

Delivered for the Sidebar's round-3 contract ([sidebar motion](sidebar-motion.md)):
`PaneTitleControl` pins its label with
`SidebarMotionController.pinDrawnContent(label, to: .center)`, and assigns its
surface frame with actions enabled only inside an implicit-animation group, so
the ⌘S group moves it with the group's 0.08-second timing and nothing animates
it elsewhere. `BrowserToolbarView` pins its drawn one-point rule with
`.scaleAxesIndependently`. `tests/SidebarMotion/check.py` guards both pins.

Checks: the inert Toolbar component (`tests/BrowserToolbar/check.py`), the
split control presentation/menu/model checks (`scripts/test-split-pane-controls.sh`),
the pinned-flag native syntax check of the overlay units and the whole-module
Swift typecheck. Receipts are under `work/claude-split-checks` (`sp27-*`). No

## Pane-snapshot drag source

pane-drag gesture, grip or top-bar drag. Panes in a split are reordered through
the pane menu's Move entries; a split's sidebar children are not drag sources,
since the cell's one outline row drags the whole split
([SP30](#split-cell-container--sp30)).

`allowInteractivePaneInsertion`, no current `dragSourceState` and no
`dragDestinationState`, and finds the `ContentPane` for a given content view
controller. It then stores `DragSourceState` (pane ID, index, `widthFactor`,
nil snapshot and the pane view's frame size) and writes the pane ID to an
`NSPasteboardItem` under the `SplitViewController.ContentPane` type (global
asks delegate witness slot 19 for a snapshot. In the window conformance
uses it as the dragging frame contents and calls
`beginDraggingSessionWithItems:event:source:` on the controller's view. It
sets `animatesToStartingPositionsOnCancelOrFail` to false. A nil snapshot
clears the source state without starting a session.

The rest of the lifecycle hangs off that source state:

  through `enumerateDraggingItemsWithOptions`.
  controller has a source state, and admits ordinary content only while it has
  `1 / count` when the source state exists.
  restores the source pane's factor and expanded state. It makes no delegate
  call, so a drop outside the split restores the pane; it does not tear it out.

`adrp` pair, relative pointer, chained-fixup pointer or vtable entry for
(the same pasteboard item and `initWithPasteboardWriter:` sequence) is
equally unreferenced. Only the starter creates a non-nil `DragSourceState`;
the completion only fills its snapshot or clears it through the surviving modify
Each version has only two `beginDraggingSessionWithItems:event:source:` senders:
`onDrag` are used only by `HomeBadging.ConditionalDragModifier` and
`HomeButton.OptionallyDraggable`. `WindowContentGrabber` moves the window
(`performWindowDragWithEvent`) and is not a pasteboard source. Chromium
web-content drags carry page content, not split panes. Both versions have the
same drag-source set.

Consequences for the remaining Split rows:

- Source-pane collapse, the source snapshot drag image, `movePanel` and the
  restore on ended exist only behind this dormant source state. They are not
- The earlier SP29 lead on a same-group sidebar child is closed as moot: a
  same-group `reservesInsertion` path with it (SP30).

`ev_d1ca36a29da409adbd95b1bf630dbe347a2fa63005baddc80381eb34a31d2128`
(starter), `ev_2c0527acaaa7193d96c49e609717f4087f831b76ed2320300525d25086d75b51`
(snapshot completion) and
`ev_5f17f649e39e20c1526f0b4f07b3796a01d7b11965b8e2424e39faa38eff5a4c`
(window snapshot provider), paired with full-image instructions, field
opened, and no source change was needed for this behavior.

## Replacement highlight, pending pane and proposal feedback

When an admitted drag proposes `replaceContent(index)`, each displayed pane's
own highlight border shows on the target at three points; the focused pane of a
multi-pane split shows the same border at two points whenever no drag-and-drop
pane edit is active. Parc now draws that border on each original pane (and the
pending Add Split pane) and drives it from the window's drag state. The
adapted "Replace Split Pane" tint and label and the half-pane insertion preview
are removed.

the proposed `DropTarget` changes. It calls window delegate slot 12 (witness
`WindowAction.SplitViewAction.onDidUpdateSplitViewProposedDropTarget` (case 5)
with the pane's `WindowContentID` for a replacement and nil for an insertion or
no target. That writes `SplitViewState.InteractionState.proposedWindowContentDropTarget`.
`onDidBeginSplitViewInteractivePaneEditingWith(.dragAndDrop)`); the terminal

the proposed target and the focused content with each content ID:
`displayHighlightBorder` = proposed ∨ (focused ∧ the split holds more than one
= 3 when proposed, otherwise 2. "Focused" also requires that no command bar
creating a new tab is presented: the producer treats the focused content as
unfocused when window state +0x298 is set and the byte at +0x2b9 is 2. The
`commandBarIntegrationPresentationInfo` (field 33): +0x298 is its instance ID's
second word (non-nil) and +0x2b9 its `destinationType`, where 2 is
animates only when the displayed flag differs from the previous state; the sink
NSAnimationContext group with implicit animation and duration 0.11
view bounds and strokes `CGPathCreateWithRoundedRect(bounds, cornerRadius)`, so
copies the view layer's bounds animation for `path`. The color sink
`WindowTheme.PrimaryColorPalette.shaded` (offset 0x40) when dark and

**Pending pane.** Add Split creates a content with a nil blueprint
previousFocusedWindowContent:)` in the command-bar presentation info
content. Its command bar is presented with entry `splitViewPaneCreated` and
tag 2, destination 2), so the exception above shows no focus border on any
pane while that bar is open; after a choice the content keeps focus and shows
page or label. The browser diff owner adds and removes contents with immediate
layout (see [ordinary pane updates](#original-insertion-region-border-and-ordinary-pane-updates)),
so the pending pane appears and cancels without a transition. Its width: the
proportionally. Stored pane widths reach the controller only through the
no entry for a content beyond the stored list. Parc's preview inserts `1 / n`
and normalizes, which is the same `1 / (n + 1)` share with the others rescaled.
While the pane is pending the window has no active item, so a hidden sidebar
floats ([Add Split's pending pane](sidebar-motion.md#add-splits-pending-pane)),
and its bar makes the sidebar's New Tab the current item
([New Tab selected look](parity.md#today-divider-clear-and-new-tab)).

`NSHapticFeedbackManager.defaultPerformer performFeedbackPattern:.generic
performanceTime:.now` if `isDragDropHapticFeedbackEnabled`. The initializer
changes it (its vtable setter offset 0x1a8 is not called there).

**Parc mapping.** `SplitPaneHighlight` owns the layer on `BrowserPane` and
`SplitPanePlaceholder`; `SplitPaneHighlightState.resolve` is the state rule.
The window records whether its presented command bar creates a new tab (the
general bar with `newTab`, and Add Split's bar), which suppresses the focus
border.
`SplitDropTargetTracker` (in both the sidebar-tab and external-URL routes)
publishes changed targets and performs the haptic; exit and the terminal clear
its target. The drag-and-drop pane edit that hides the focus border is SP10's
`ParcSplitView.InteractivePaneEdit`: it begins on the drag's first admitted
entry and ends only at its terminal (or SP10's release fallback), and the window
refreshes the borders from `onInteractivePaneEditing`, so the focus border
returns exactly when the edit ends. `DropReservation.reusedRegion` reports the
existing region: the held region, or the still-collapsing region at the same
slot. `ParcSplitView` hands each pane-layer transition to the pane highlight
(`SplitLayoutFollowing`) so the border follows the moving edge, and cancels it
with the transition. `ThemeChromePalette` now exposes `shaded`/`shadedDark`
from the same luminance bands the semantic palette uses. The pending pane is
treated as the focused content while it exists.

**Adaptations and limits.** The opacity fade is kept under Reduce Motion, as in
system-color fallback theme has no primary palette, so it maps `shaded` and
whose Boosts editor state is 3. Parc has no Boosts editor, so that case has no
owner to drive it.

Fresh REA records: proposal owner
`ev_44836af48375c646c47288336eb904bc68378248c45292cd23757decf59ccca9`, classifier
caller `ev_2f5cd914d64548afbf3ab5d92d1ae676a95eb552815baaa27601d824180f0000`,
region producer `ev_88a88be59cbd2118848e03063b5a6c28f3717ca819bed586257f2c206aff9894`,
perform `ev_b07d717fdb2bb29fcf269a9a8dbd35e2e94b1b378e66671d32bac2c118459bb3`,
content state `ev_70b6f10e06e7059fd3c5c89f362f124ecb221c08997c7853571c62be189c6ccc`,
delegate insert/replace/prepare/perform
`ev_a3499c6e4ae73e4ed7fa825d11eb6235aab0305b572c49b30f52ab5f3b21d8c4`,
`ev_9dcc514d9eccaeb477a6c843c5fcd5ba7062461e981fcf83486f64f162aafb11`,
`ev_982a613d0479626df46dcc124bbcbf82d6fd9cc1e800d8741af4e463f86f62bc`,
`ev_4bb8aab96a869f2c28f277799f3c5e6b95678fbd016ab18bc0bfddbc62999e3d`, paired

Checks: the whole-module typecheck passes with warnings as errors. Inert
components cover the tracker (feedback, publication, begin/finish), the layer
properties, width doubling, the 0.11-second transition only on display
changes, path following and cancellation, the pending pane's colors, and the
comparison was run.

The Add Split model check `scripts/test-command-bar-split.sh` now compiles the
whole ParcCore module; its fixed list predated `ClosedItems.swift` and
`SplitPaneControls.swift`. A bounded bisect over the 83 ParcCore commits
between `ae44b38` (assertion added, passing) and `2e3072a` found `8ca010e`
(exclusive split containers) as the first failure of "The split transaction
publishes once": `insertCommandBarSplit` published its appended container
while the replaced one still overlapped it, and `changed()` then published the
exclusive-membership repair. The store now applies the same normalization
(`BrowserStore.reconciledSplitLayouts(in:activeSpaceID:)`, shared with
`reconcileSplitLayouts()`) before publishing, so the transaction publishes once
with its final containers. `tests/BrowserStoreTests.swift:990` ("independent
layouts in different Spaces") fails identically before and after this change.

## Split keyboard, accessibility and focus — SP32

Evidence is bounded annotated disassembly (`arcfn.py`) and lookup-index

**Commands.** The View menu and the hidden numbered/adjacent items are the
existing [split navigation](split-navigation.md) commands (constructor
responder of the newly focused content. Parc's `focusSelectedContent` is that
request (page through the focus manager, else Note/Easel editor or Start
search). Next/previous wrap at the ends; a numbered position past the pane count
in focus."), Separate ("Separate Page from Split View."), the four numbered
jumps and next/previous; Expand has none. The Shortcuts detail now shows all
nine (it had only Add).

**Pane focus follows the pointer, not the keyboard.** `BrowserWindow.sendEvent:`
`WindowContentAction.onDidFocus` (case 26); the other case-26 sites are
case-path and decoding helpers. The content's responder is registered without
nil responder, so Tab into another pane moves the first responder but not the
focused pane, and the [focus border](#replacement-highlight-pending-pane-and-proposal-feedback)
stays on the focused content. Parc matches: its window mouse-down monitor
focuses the pressed pane and its key-view loop changes no focused pane.
writes `focusedContentID` only, without a responder request), as Parc's toolbar
dividers are not views, so the page-side key-view loop crosses panes and their
top bars only, under the gates in
[window key-view loop](sidebar-accessibility.md#window-key-view-loop-delivered-with-side17-window-owner-informed).
The top-bar controls are AppKit buttons with focus rings, reachable with Full


  the pane-menu move/convert helpers are not posters either. Parc now leaves
  focus alone after Separate and Move unless the change took it away (nothing,
  the window, or a hidden, parked or unpresented view holds it:
  `ContentFocusRequest.lostByPresentation`, through `SavedFocus.mayReturn`),
  and only then requests the focused content
  (`reclaimFocusAfterSplitPresentation`). Previously they always focused local
  content, taking focus from the sidebar. A separated page that leaves the
- *Close.* The split removal in
  focuses `windowContentIDs[min(removedIndex, count − 1)]`: the pane that takes
  the removed one's place, else the new last. `BrowserSplitLayout.focusSuccessor`
  is that rule (previously the first remaining pane). It decides
  `FolderRemovalSelection.resolve` when the focused pane does not survive, which
  covers user-initiated closes (the pane's Close, Close this Split Pane, ⌘W and
  a sidebar child's Close), and `WindowPresentation.remove`'s per-Space focus
  record when a page is closed or transferred to another window; the close
  completion, `releaseClosedTab` and both transfer sides then read
  `preferredFocusedTabID` instead of taking the first pane. The closed page's
  responder leaves with it, and the focus manager's nil fallback focuses the new
- *Add Split cancel.* The pending content is removed and the previous focused
  else the content. Parc's cancel now does the same.
- *Command-bar dismiss* keeps its documented restore-first adaptation
  ([navigation](navigation.md#focus-traversal-across-page-controls-and-auxiliary-contexts)).

object, tab, Easel and dock cells, App Tray items, `TranslucentButton`,
accessibility selector: `DraggingDestinationForwardingView` (container),
`SplitViewContentPaneView` (only `hitTest:`), both dragger handle views, the
`SplitViewCellView` and its child items. The executable never sends
`setAccessibilityRole:` or `setAccessibilityElement:` and imports no
accessibility notification post. AppKit therefore ignores the split's views:
each pane's content appears directly in the window's tree, there is no split
group, no splitter with value, increment or decrement, and no announcement on
split changes. Parc's earlier "Split pages" split group with numeric splitter
children, its AX resize route and its value-changed posts are removed.
"Close Split View Pane" with help "Remove Tab from Split View"; Parc's close
Close/Archive custom action is removed; its visible Close button stays one of
the cell's accessibility children.

**Contract notes for other owners.**

- Keyboard/Settings: `scripts/test-shortcut-cue.sh` omits
  `ShortcutKeycapView.swift` and does not compile on main.
- Window presentation (resolved): `scripts/test-window-presentation.sh`'s
  fixed ParcCore list missed newer sources (`SplitPaneInsertion` and others);
  it now lists them and `SettingsPrettyJSONPersistSkip.swift`, and passes.

**Checks.** Whole-module typecheck with warnings as errors;
`scripts/test-split-dividers.sh` (the container is ignored by accessibility and
exposes its panes directly), `scripts/test-split-pane-controls.sh`,
`scripts/test-split-divider-snap.sh`, `tests/BrowserToolbar/check.py`,
`tests/ContentFocusRequest/check.py` (`lostByPresentation` and the new wiring),
`scripts/test-shortcut-detail.sh` (a split description),
`tests/WindowPresentationTests.swift` and `tests/SameContainerFocusTests.swift`
(focus successor),
`tests/NativeContentDrop/run_components.py session` and `run_local.py`, whose
file list now includes `ParcSplitView`, `SplitPaneHighlight` and
`WebpageEditCommands` and whose test passes the required insertion color. No
browser, VoiceOver, Full Keyboard Access or populated on-screen comparison ran.

## Split gesture and context inventory — SP33


**Right-margin handle.** A page outside any split shows a grip in its right
page margin. The last pane's trailing `SplitViewDraggerHandleView` keeps its
grip while `ViewState.isHandleVisible` (field offset `0x114`, keypath
`SplitViewState.windowContentIDs` (so false for every split's last pane), and
false in a stacked arrangement. Only a page outside a split (an empty
`windowContentIDs`), side by side, keeps it. The region provider
double click begins inside the band, but `handleDraggerDoubleClickGesture:`'s
container flags around it are unrelated: `isDraggingToCreateSplitView` is
Parc: `SplitMarginHandleView` sits in the ten-point margin beside the page
host, shows the two-by-24 grip with the divider colours and 0.16-second
hover, and puts the cursor rect and tracking area on the 44-point band. The
window admits it for one displayed page with no split, draft or expanded
split and outside popups; the split view withdraws it while it has a second
pane or an incoming reserved pane; full screen and the extension panel leave
no margin. It takes no mouse events, so the margin keeps its existing
behaviour.

`ev_ffbe4c3f1304d84479fcf1e95ef05800613e2b4f3716373528acd33b6eeaef92`). A
child's control-click goes to `rightMouseDown:` and on to the split's one
Its items, in append order, with their `SidebarContextMenuItemAction` cases:

- Share Split View… (`createSharedArcObject`, 22), not in incognito windows
  Share Space….
- Separate All Tabs (`splitView(.separateAllItems)`) and Add Tab…
  (`splitView(.addPanel)`).
- For one selected item: Convert to Vertical Split View or Convert to
  offers Vertical for a side-by-side split and Horizontal for a stacked one),
  then a separator, a "Tab Options" header and one submenu per child
  .separateFromSplitView))`, then the child's tab items).
- A separator, Reset Name and Icon (`resetTitleAndIcon`, appended without a
- A separator, Duplicate (`tab(.duplicate)`, with its shortcut) and, outside
  selection count), then, while every selected item is unpinned
  Tabs Below / Archive Tabs Above (`archiveUnselectedItems`,
  `archiveItemsBelow`, `archiveItemsAbove`), and Close (`close`,
  omitted only for a top app (`SidebarItemContextType` 0), so a sidebar
  split always has it.

displayed split keeps its focused content and drops the others
window's displayed page or split whichever cell was clicked. Convert

Parc's `SidebarSplitCellMenu` builds this order when the menu opens, for the
split cell and for each child. Separate All Tabs dissolves the split in one
transaction (`BrowserStore.separateAllTabsFromSplit`), keeping a displayed
split's focused page and each child's saved placement, under Separate Page's
window lease. Dissolution replaces the split's sidebar slot with its children
in pane order, including after a whole-split move; focus returns to content
only if presentation removed the previous responder, as for Separate Page. Add Tab… runs the window's Add Split View command and is
enabled exactly when that command is. Convert flips any split of the Space
(`BrowserStore.flipSplitOrientation`), keeping its proportions and the
selection. Tab Options submenus lead with Separate from Split View, followed
by the child's existing tab items. Reset Name and Icon is always present and
enabled when the reset can be prepared. Duplicate uses the sidebar's
whole-split duplicate, Move to the existing move items, Archive Item and
Close the split cell Close's archive and close owners. A private window, which
never archives, omits Archive Item and words the group Close Other Tabs /
Below / Above, as the tab menu does. A Today split adds the archive group
through the tab menu's Today archive owner, measured from the split's children
and anchored at the split's anchor tab; that owner now checks the sidebar's
Today order (`SidebarTodayArchive`), not the model's array order. Multi-selection keeps the
selection menu.

New Folder with *n* Items (`createFolderFromSelectionInCurrentSpace`, case 20;
count + " Items", so one split reads "1 Items"). The context menu passes no
Undo step is registered through witness `+0x660` with the name "New Folder…"
is `SidebarFolderFromItems` with `BrowserStore.createFolder(containing:)` and
`revertFolderCreation`: one durable write publishes the folder, named "New
Folder" and appended to its parent, with the moved items, and expands the
folder's ancestors; the window registers one "New Folder…" Undo/Redo step that
restores the moved tabs' placement, the new folder and the order lists it
rewrote, compared record by record, so unrelated edits (a page title, another
folder's name, other Spaces' splits) keep it available; Undo also refuses
while the folder holds anything else. The returned Undo receipt captures the
folder's current metadata, so Redo retains the name entered after creation. The store transaction names its own
Space, so a window can create the folder while another window's Space is the
store's active one.
A Parc folder lives in the pinned section, so a Today item's folder goes to
the Space's pinned root. The split cell menu uses it; the tab and
multi-selection menus can use the same owner (Folders family).

What follows creation is traced too. The folder's index is −1, which
0.1 seconds later, send `WindowAction.setEditingItem(itemID:)` for it: the
row into view (`SidebarView.scrollItemToVisible`) and, after 0.1 seconds, opens
its folder title editor, the existing Rename prompt, while the window is still
key and on that Space; inline folder title editing is a Folders-family
contract (parity.md).

**Drop highlight and attention.** `SplitViewCellState.dropTargetRegion`
(`SidebarDropTargetRegion` left/right) comes from the sidebar drag's
`WindowSidebarItemDragState.dropTargetRegion`, the drag-to-combine-tabs
feature. Its flag `drag-to-combine-tabs-into-split-enabled` registers with
pass wider values), so it stays off and Parc
builds neither the left/right highlight nor the drop. `shouldPerformUser
AttentionAnimation` comes from `WindowState.sidebarItemUserAttentionRequest`
(item ID, animated) and is drawn by the shared cell, not the split cell; Parc's
shared reveal (`SidebarView.revealItem`) already applies to `.split` rows.

**Child double click and other flags.** The child press's double-click branch
The other split flags also register default false and stay off:
The recovered `show-toolbar-in-split-view-enabled` string has no user-facing
toggle; Parc shows the per-pane top bar on every split.

`performFeedbackPattern:performanceTime:` sites. Two are split code and both

**Other entry points.** Already delivered and unchanged: sidebar tab drops
on panes (SP11/SP13), external URL drops (SP15/SP17), whole-split sidebar,
Space and window moves (SP18/SP19), the pane menu and single-pane Add
(SP27/SP28), command-bar Option-Return (command-bar.md), divider drag,
double click and snap (SP07–SP10) and the split cell Close (SP30). The tab
Split View are existing Parc routes this row did not re-examine. The
pane-snapshot drag is dormant (below) and children have no drag.

**Cross-Space Add results.** Add Split's command bar lists the Profile's
tabs. A chosen tab is `CommandBarSelectionOptions.Action.openTab`; the
`targetWindowContent`, which is Add Split's pending pane
`visibilityBehavior` ensureVisible (`+0x10` = 1) and
`ev_384b0cbed0cb859989d9638d7bad77a4b35d2cb6acdf1ef2abfb6411b4386b55`). That
window's. Because the item is by then a child of the split in the window's
Space, the window stays: the result joins this split as a same-Space one
does. Parc's Add Split now offers the Profile's ordinary tabs in every Space.
`SplitCrossSpaceAdd` moves the tab into this Space before SP21's membership
transaction admits it. A pinned tab leaves a fresh saved home at its original
slot or split position in its own Space (`SplitMembership.makeHome`), and that
Space's remembered selection follows the home. A Today tab leaving a split
there follows SP21's removal (`SplitMembership.preservingSlots`): the split
keeps its slot under a new anchor, or dissolves in place. The moved tab takes
the target pane's slot in this Space's Today order, so the displayed split
stays put. Typed (Note/Easel) homes are planned and validated before the move,
so a pinned Note from another Space joins with its home preloaded. The window
keeps its Space. Option-Return split submission chooses from the same command bar tab
rows (the ASE2 `sidebar` source's `Archetype.tab` results): the factory
`0x43`, `splitView(.newPane(.afterFocusedPane))`, with no Space filter, so the
same `selectItem` order applies. Parc's command bar already lists the
Profile's tabs in every Space; `insertCommandBarSplit` now relocates a chosen
tab from another Space through `SplitCrossSpaceAdd` before joining it, instead
of refusing it.

**Sidebar Create/Add to Split View.** `WindowAction.openItemsInSplitView`
(case 104) carries `targetDropItem` and the dragged items: the
drop-onto-a-tab split. The sidebar drag's drop-target computation
drop stays off with the cell's left/right highlight. The "Create Split View"
modal's own `onAddToSplit` button, which Parc's Peek menu (Add Peek to Split
View) covers. This trace did not find the instruction that builds case 104,
so the drop route rests on the payload names and the flag argument.

Checks: `scripts/test-split-context.sh` (Separate All Tabs, Convert and
cross-Space Add model transactions, the menu order, archive group and
actions, the margin handle's admission, band, grip, tracking and hit test), the existing split component scripts and the
whole-module SIL compilation. Recovery also checks moved-split dissolution
order and retained folder names on Redo; `tests/ContentFocusRequest/check.py`
checks the shared focus-reclaim helper in inert windows and the Separate All
wiring. Receipts are under `work/claude-split-checks` (`sp33-*` and
`codex-sp33-review-fixes-*`). No functional browser tests were run.

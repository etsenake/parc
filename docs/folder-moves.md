# Folder and sidebar moves

Moves preserve original typed tab, folder and split identities. Row edges reorder;
a folder's middle nests the item. A folder carries its hierarchy and a whole split
keeps every child, orientation and width. These operations do not reconstruct
pages from URLs. Move Up/Down/Out and accessibility actions use the same validated
transaction; separate split-child actions retain their own explicit scope.

## Parc implementation and ownership

`SidebarHierarchy` projects mixed order from `BrowserState.sidebarItemOrder`.
Older sessions preserve their direct-tabs-then-folders order until an explicit
move establishes ordering. Split anchors preserve their established slots.
Rendering, keyboard traversal, previews and link export consume that projection.

`SidebarMoveSession` is a process-local one-use capability. Pasteboard text only
identifies it; source/destination must validate its original window, Profile,
Space, hierarchy, selection/focus and actual pane/page/editor identities at
commit. External text or a forged UUID cannot authorize an internal transfer.

The model rejects self/descendant nesting, missing/stale destinations, cycles,
retiring owners and partial split membership. Proposals are pure. A successful
transaction atomically replaces the session file before publishing all changes;
a write failure publishes nothing. URLs, history, native wrappers, capture leases
and split geometry survive. Today/pinned conversion follows saved-destination
policy on the same original tab.

## Drag presentation and scope

Before/after use row edges; folder-middle drops nest at the folder's top.
Insertion feedback and edge scrolling use the existing sidebar presenter.
Collapsed folders spring open after the system delay. Accepted drops keep them
open; leaving/abandoning closes temporarily expanded folders. A disclosure-only
change updates the move lease's expected hierarchy so expansion does not cancel
its own drag.

Dragging an original selected row moves the ordered
[multi-selection](sidebar-selection.md), suppressing selected descendants beneath
an ancestor and saving once. Holding Option drops a copy instead; see
[Option-drag copies](#option-drag-copies). External pasteboard payloads never
authorize either.

## Option-drag copies

Holding Option while dragging drops a copy and leaves the original, as in Finder.
Tabs, folders with everything nested in them, whole splits, Favorite tiles and
mixed selections copy to any spot a move could reach in the same window: Pinned,
Today, a folder's edges or middle, the Favorites tray, the collapsed Pinned
header, the Space header (top of Pinned) and a dock Space that shares data with
the source. Folders still cannot become Favorites or Today items, and the tray's
twelve-root limit refuses an overfull copy as a whole.

Copies come from Duplicate's copier: fresh folder, tab and split IDs with saved
titles, mute state, split names, orientation, proportions, folder disclosure
and each page's current address. They are built beside the originals and then
placed by the ordinary move transaction, so Today/pinned conversion and Space
changes follow the move rules; one save publishes everything after the source,
destination, document references and native owners revalidate. A Note or Easel
copy is a new sidebar entry for the same document, exactly as Duplicate makes;
document contents are never duplicated. Copies leave the window's selection
alone, except a whole-split copy, which still selects the copied split. Only the
first five copied top-level items open background pages, a split's panes
counting with their split; folder contents and later items stay saved until
selected, so a large copy loads little.

While Option is held over a valid target the drop reports a copy, so the pointer
shows the standard green-plus copy badge. Each drag update rereads Option, so
pressing or releasing it mid-drag switches between copy and move on the spot. An
invalid target shows no badge or insertion line, and the drag image slides back.
Tabs, folders and mixed selections never copy into another window or into a
Space that keeps separate data; whole splits keep their own cross-window and
separate-data copy in [split groups](split-groups.md#whole-split-copy-and-external-drags--sp23).
An Option drag never falls back to a move.

Each Option-drag copy, whole splits and tray copies included, records one
**Copy** step on the receiving window's Undo stack through the
[Duplicate Undo](folder-commands.md#duplicate-undo-and-redo) machinery.

Notes and Easels are deliberately never duplicated into a Space that keeps
separate data, by Option-drag or any other copy: Parc never copies a document's
contents, and an entry cannot point into another Space's document store. Moving
the document is the supported path; see
[cross-Profile moves](split-groups.md#cross-profile-moves).

## Move to another Space

Move To captures source/destination hierarchies and complete group membership.
Same-Profile moves retain IDs, mixed order, group geometry, URLs, saved targets,
unread/mute state, timestamps and document references. Source selection removes
moved IDs; destination remembered selection is not replaced. Archived records
are unchanged.

A complete split can originate across folders or Pinned/Today. Its destination
normalizes every child to the projected container while preserving group identity,
order and widths; dormant old order entries are removed. A selected ancestor
that includes only part of a hidden group refuses rather than breaking it.

Every affected window contributes its actual page/editor lease. Pending creation,
retirement, transfer, close, fullscreen and affected Peek ownership gate the move.
Same-Profile model relocation does not itself detach WebContents; original
physical owners remain until the real transfer path runs.

Cross-Profile moves use their separate consent, storage and reload path in
[split groups](split-groups.md#cross-profile-moves). They cannot reuse an
in-process same-Profile transfer by changing a directory or identifier.

### Notes and Easels still used in the source Space

A Note or Easel moves into a Space that keeps separate data only when nothing
left in its current data still uses the document: a second entry made by
Duplicate or an Option-drag copy, the saved spot a pinned Note keeps when it
joins a split (including the one a split drop would leave behind), an entry in a
Space sharing that data, a Favorite, or an archived entry, which the Archive keeps
for 60 days. The refusal is deliberate. A document lives in one data store, so
moving it would leave those entries pointing at nothing. Removing or moving the
other entries first lets the move go ahead.

The refusal explains itself. Every move route checks for these entries before
the "uses different data" warning, and when it finds any the warning never
appears; Don't ask again does not skip the check. A window notice beside the move notice
says "Can’t move to Office" and, underneath, where the document is still used,
for example "This Note is still used elsewhere in Home: in the folder “Research”
and in the Archive." A notice fits because nothing needs deciding and nothing
moved. A multi-item move names the first item that blocks it and counts the rest.
New Space with Keep separate shows the same sentence in its own form. If the
entries appear after the warning was confirmed, the same notice replaces the
refusal beep; other late refusals still beep. `InterProfileDocumentBlock` builds
the text from the same check the store applies, and every other move rule and the
document rollback are unchanged.

Changing what data a Space uses moves its open Notes and Easels with it, so a
Favorite, an archived entry or an entry in another Space still on the old data
refuses it the same way. Share data with and Keep separate check before their
warning and skip it when they find any. Settings answers in a line under its
Share data with row, for example "The Note “Plans” is still used elsewhere on
Home’s current data: in Favorites and in the Archive.", which stays while it is
true for the Space shown and clears on the next choice. The Space menus show it
as a window notice titled "Can’t keep Home separate" or "Can’t share Work’s data
with Home". A change refused after its warning explains itself the same way;
other refusals stay silent, as before.

### Reveal after moving

The completion toast says Tab moved! Click to go there. Its action checks the
original moved item and destination, focuses that Space in the same window,
expands ancestors and scrolls/highlights the row. Revealing differs from
activating the page; a split remains whole. `SidebarItemReveal` and the store/
view helpers share this path. Disclosure still saves before publication.
Expired notices cannot target a different window/item.

## Create a Space with original items

New Space and Move To → New Space share a window-owned draft: name,
what data it shares (an existing Space, or Keep separate), optional icon and
theme. Keep separate creates its data only when the Space is committed, so
cancelling leaves nothing behind. The nonempty draft retains its original move
admission, with the cross-data confirmation when the data differs.

The window snapshots presentation, focus and actual native/editor claims before
parking selected panes. Cancel, Escape/Exit or footer navigation restore those
same owners. New native content or stale ownership ends the draft. Child pickers
bind to their exact draft; IME composition prevents submission.

`SidebarNewSpaceDraft` commits the new Space and supported original moves in one
atomic replacement, without first saving an empty destination. Failure keeps the
draft for retry. Success focuses the destination without placeholder tabs or
URL replay. See [Space management](space-management.md) for creation behavior.

## Move a collection to another physical window

Same-Profile transfers stage the whole original collection, including nested and
empty folders, splits, local documents and Easel embedded pages. Both windows
retain selection/focus/hierarchy and genuine native ownership reservations.
Sheets, security reservations, fullscreen, Peek, competing transfers, pending
creation/retirement or a third live owner refuse the complete drop.

`SidebarWindowMove` produces one model proposal. `NativePageOwnership.CollectionTransfer`
reserves all original IDs, including unmaterialized items. Native `TransferLiveTabs`
holds both Chromium unload-controller reservations, detaches/inserts the same
TabModel/WebContents and attaches every original before durable commit. Reentrant
callbacks must revalidate actual ownership. Attachment/save failure rolls surviving
originals back, including order, pin state, openers and selection.

Only the posted native result allows the same `PCBrowserView` wrappers into the
destination panes. Notes keep their original editor/session with composition and
failed-save barriers. Easels keep their canvas, session, pool and child wrappers;
only the admitted transfer may rebind their native lease. Creation and shared
mutation remain gated until all claims settle. Rollback rebinds the originals.
See [embedded pages](embedded-pages.md#physical-window-collection-transfer).

A nonempty destination preserves its selected/focused page; an empty one may
adopt the first original item through ordinary split selection. Empty native
strips do not authorize closing shell windows that still own local/unmaterialized
content. Existing window-close owners remain authoritative.

Unexpected native destruction/ownership loss retains the transaction for recovery.
Retry reconnects to the committed owner. Close Affected Tabs uses genuine whole-set
consent and does not delete sidebar/document data. Keep Open retains reservations;
a later close returns to recovery. No failure fabricates replacement pages.

## Favorite / app-tray moves

Favorites use the same original-item move transaction. Tabs and complete splits
can enter the tray; Favorites can move to Pinned, Today or folders. Folders cannot
be Favorites. The twelve-root capacity counts a complete split once, and excess
plural admission fails atomically.

Tray order is shared across a Profile's Spaces. A split Favorite remains one tile
with original children/geometry even when its stored home Space differs. Moving
it out assigns the complete group to the destination. Positional navigation,
Control-Space and Reset All consume the same projection. Same-Profile physical
moves retain original documents, pages and rollback behavior.

Tiles capture a move lease after down; dragging cancels release actions. Stale
selection/membership/Profile/native ownership or retirement refuses. Detach,
hide, disable and deactivation cancel pending sources. Existing Command reset,
Shift activation and Option-click Open in Split stay with the tile's pointer
owner, separate from outline multi-selection; an Option drag copies the tile.
A refused copy never silently becomes a move.

## Checks and limits

Store/ownership tests cover nested and mixed placements, original document IDs,
complete-group admission, capacities, stale/foreign/cycle refusal, real disk-write
failure, reload, competing claims and rollback. The sidebar copy tests cover
Option-drag copies of each item kind into every target, separate-data refusals,
the bounded page rule and Undo/Redo; a source check covers the copy pointer and
drop routing.

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
an ancestor and saving once. A whole split has its separate Option-copy/external
drag support in [split groups](split-groups.md). Do not generalize that support
to every row or external pasteboard payload.

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
See [embedded pages](easel-embedded-pages.md#physical-window-collection-transfer).

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
Shift activation and Option behavior stay with the tile's pointer owner, separate
from outline multi-selection. Unsupported copy intent never silently becomes move.

## Checks and limits

Store/ownership tests cover nested and mixed placements, original document IDs,
complete-group admission, capacities, stale/foreign/cycle refusal, real disk-write
failure, reload, competing claims and rollback. Ordinary-tab and folder drags
remain move-only, including mixed selections with splits. The supported
whole-split copy path and document restrictions are in [split groups](split-groups.md#whole-split-copy-and-external-drags--sp23).

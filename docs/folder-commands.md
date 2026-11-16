# Folder commands

Folder commands retain the original window, Space/Profile, hierarchy, selection
and native owners. A delayed action cannot target whichever tab later becomes
active. Durable tree mutations save atomically before publication.

## Folder row, creation and rename

Folder rows have a 17-point themed folder icon in a 24-point slot, 14-point
semibold title and the tab row's selection/hover treatment. The icon opens with
disclosure; retained rows animate rather than being recreated for each click.
New Folder inserts an untitled folder at the end of Pinned or its parent, opens
the parent and edits in place with **Folder Title** placeholder. New Folder from
Selection uses the same transaction. Double-click or Rename edits; Escape keeps
the old name and empty names display **Untitled**. Library cards use a prompt.

## Folder context menu and icon

The menu includes Preview folder, New Nested Folder, Turn into Space, Copy All
Links (Option: Markdown), Change Icon, Rename, Duplicate, moves and Delete.
Service sharing remains excluded. Change Icon uses the shared picker, starts on
icons, saves each choice immediately and stays open. The stored `customIcon`
decodes unknown values as none; emoji keep their colors.

## Peeked folders

Each window can keep its active tab/split visible through collapsed ancestors.
A peeked folder shows an ellipsis, and Close This Folder hides those peeked rows.
Expansion or closing a peeked tab ends the peek. These rows remain keyboard-
reachable. Peek state lasts for the window's lifetime and is not persisted.

## Duplicate and command-bar collection copies

Duplicate accepts one folder subtree or a same-Space/Profile selected collection
of ordinary tabs, nested/empty folders, whole splits and valid Note/Easel aliases.
Selected ancestors own their selected descendants once. Favorites, foreign roots,
pending retirement and malformed/partial splits refuse the whole collection.
Changing selection, hierarchy, native owners or document capability expires it.

Copies receive fresh folder/tab/split IDs and retain mixed order, names, saved
mute state, split titles/anchors/orientation/ratios and disclosure. They are
inserted adjacent after the originals without changing current selection.
A materialized page supplies its actual current URL; otherwise its saved URL
is used. No POST/history clone or original-page transplant is implied.

All records save together before any page creation. Every copied web split child
requests a fresh background page; the first five ordinary top-level roots do too.
Ordinary descendants inside folders remain saved-only. The native factory binds
the real Profile/window, creates a first Browser without showing it and retains
pending-close handling across asynchronous creation. A failed creation leaves
the durable copied item and its normal failure/Retry owner; it does not undo the
saved tree or claim that a page opened.

Command–Option–Return on **Pin to [folder]** copies the eligible original
collection into that captured same-profile folder through the same fresh-ID
transaction. See [command bar](command-bar.md). Option-drag places the same
copies at the drop point and opens pages only for its first five items; see
[Option-drag copies](folder-moves.md#option-drag-copies).

### Duplicate Undo and Redo

Duplicate, the Pin to [folder] copy and an Option-drag copy each record one
step, **Duplicate**, **Copy to Folder** or **Copy**, on the originating window's
Undo stack; an Option-drag copy belongs to the window it landed in. Undo removes exactly
the copied folders, tabs, splits and Note/Easel aliases. Copies are not archived,
originals stay untouched and document contents never change. Copied pages close
through Delete's native consent, and a selected copy hands selection to a
survivor using Delete's replacement rules. Undo waits while a copy's page is
still opening or already closing.

Undo binds the copies' identities and placement. Each root must stay in its
original container, copied folders must hold exactly their copied children, and
splits keep their members. A moved, archived or regrouped copy, or a new child
inside a copied folder, retires the step instead of removing anything. Renames,
navigation and other edits do not: Undo records the copies as they are, and Redo
restores those records with the same IDs beside their surviving neighbors. It
then reopens the background pages the copy opened if the window still shows the
originating Space. Redo waits while a copied document cannot validate, or while
the Favorites tray has no room for a copy dropped on it, and refuses if a copied
ID returned or the parent folder is gone.

## Typed Note and Easel reference copies

Copies create new sidebar aliases to the same original-Profile document ID,
never duplicate document contents or image assets. Open aliases share the actual
`NoteSession`/`EaselSession`. Copying neither flushes composition nor replaces
embedded pages. The original document store, file, tombstone/session and assets
must validate both before and immediately before publication. Bare internal URLs,
wrong Profiles, corrupt/missing files or changed capabilities refuse the whole
copy. Document stores remain read-only during sidebar persistence.

Document deletion is separate: it gathers every same-Profile alias and native
owner, retires them with consent, removes aliases, then deletes the document.
Failed sidebar persistence preserves the document; a later document-write failure
leaves the Library record retryable. Ordinary saved-tab Close is not deletion.

## Delete and plural selected-item Archive

Delete asks **Delete your “name” folder?** and explains that its tabs will be
archived, or that a folder without tabs archives none. The original subtree,
mixed order, native pages, splits and typed aliases remain bound through
confirmation and whole-set retirement, including owners in other windows, Peek
children and embedded Easel pages. Cancellation, stale ownership, pending
creation or invalid typed data refuses the operation.

After consent, one save deletes folder records and archives original sidebar
records as manual entries in their original Profile/Space. Complete splits keep
IDs, order, orientation and ratios. No child is reparented into the live sidebar,
no folder archive entity is fabricated and unrelated siblings keep their order.
A save failure preserves the saved tree even if approved live pages have closed.

Plural **Delete** (when folders are selected), **Archive Tabs**, and the matching
accessibility action generalize this to one captured same-Space collection,
one retirement transaction and one Undo group. A set of folders without tabs asks
**Delete the selected folders?** instead. Ancestors suppress duplicate
descendants. Favorites/foreign/malformed items cannot partially participate.
Keyboard Close remains distinct: saved-only roots unload content; a collection
with a Today root takes the archive/removal path. Folder-bearing keyboard actions
confirm, while tab-only ones add no extra Parc warning. See [sidebar selection](sidebar-selection.md).

Notes use the real editor's composition/save barrier before unload and again
before final commit. The exact editor objects stay retained across asynchronous
consent. Late failed saves preserve original drafts and saved hierarchy. Folder
Delete never invokes document writers/deletion APIs; surviving aliases and shared
edits/assets remain valid.

## Selection after ordinary Delete

The originating physical window captures selected IDs, focus, previous item and
creation-referrer pool. Background deletion preserves selection/focus. Surviving
panes retain focus. Otherwise replacement prefers an adjacent actual child of the
closing tab, a later pooled sibling with its referrer, or the actual item active
before creation; then the remembered same-container item, previous/next whole
sidebar item and descending activity date. Traversal includes collapsed folders
and treats a split as one item. Closing/unavailable owners cannot be substitutes.

Native consent revalidates hierarchy, pool and selection. Only the original
window consumes the decision; later selection/Space changes cannot be overwritten.
When the shown page goes, the engine picks a next page of its own, often one
parked in another Space; unless that page is already on screen, the window
ignores the pick until it has pushed its own choice back. A page that closes
itself is replaced by these same rules.
Folder deletion commits archives/removal/replacement durably together; ordinary
tab Close retains its existing deferred persistence schedule.

### Original creation and window-local referrer pool

`BrowserTab.referrerID` and `activeTabBeforeCreationID` identify actual saved
items; older records decode nil. Native receipts bind the real source page,
primary document, Browser/Profile and physical owner. Expired, subframe and
cross-profile sources do not borrow a later selected tab. Peek-created pages
resolve to their original live parent. Copies clear inherited referrers and
record the initiating window's creation-active item.

### Same-Profile routed creation across physical windows

A matched route preserves its complete original navigation request and binds
source/destination Browsers before callbacks can expose the new page. Same-
profile matched links record the source as active-before; already-created routed
contents retain their creation referrer. Cross-profile routes retain Chromium's
source/opener stripping and record neither identity. No already-created page
changes Profile. A new URL-only window starts without a referrer.

### Today placement and modal-source creation

Without a referrer, a new Today root takes index 0. With one, it follows the
referring Today item and consecutive tabs with that referrer; a split ends that
run. A pinned/Favorite referrer starts the scan at the top. Matched routes
explicitly use the top. Destination-Space ownership remains authoritative;
created local documents and saved/folder copies keep their separate placement.

## Ordinary Delete Undo and Redo

Successful Delete records **Archive Tab / Archive Tabs** on the originating
window's typed Undo stack. Undo restores original folder/tab/split identities,
mixed order and geometry from exact archived afterimages, not a browser snapshot
or destroyed WebContents. It restores focus only when the item was focused at
close; other windows keep their own selection. Surviving sibling edits remain.

The original Profile/Space/parent must exist, restored IDs must be absent, and
archive afterimages and native ownership must still match. Independent restore,
delete, changed shared state or missing parents invalidate the group. Temporarily
missing typed assets suspend availability without destroying an otherwise valid
group. Persistence failure remains retryable.

Redo validates the same current tree/member IDs and asks fresh native beforeunload
consent, without repeating the already accepted folder confirmation. New children
or moved roots refuse it. Only successful completion advances history and records
new afterimages; pending work blocks both directions. Entry/revision checks reject
stale invocations. Window closure discards its process-local history.

`PCNativePage.canUseWindowUndo` and the shortcut router admit window Undo only
for an original noneditable page or sidebar, under active/key/security/IME gates.
Native fields, Notes/Easels and editable web content keep their own Undo owners.

### Turn “name” into Space

The command creates a draft from the folder's direct items, names it after the
folder, copies the current theme and inserts it after the current Space. One
save moves the ordered nested folders/splits/collapsed state into the new Pinned
section and removes the emptied root; the window then selects the new Space.
It uses Move to New Space ownership checks and is unavailable in private windows.

## Checks and limits

BrowserStore, document-alias, copy-to-folder, close/Undo, duplicate Undo and window-presentation
components cover atomic persistence, genuine asynchronous refusal, exact IDs,
shared edits/assets and stale-owner cancellation using disposable data.

Folder deletion keeps its exact restoration data in the window's Undo/Reopen
record. Each archived tab also records its deleted folder path, so Library Put
Back rebuilds missing folders around it one tab or split at a time; see
[deleted folder paths](archive.md#deleted-folder-paths).
Collection Duplicate stays within the source Profile; whole-split cross-Profile
copies have the separate [copy contract](split-groups.md#whole-split-copy-and-external-drags--sp23).

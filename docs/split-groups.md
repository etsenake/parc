# Split views and sidebar groups

A split is a persistent container with an opaque ID, ordered original tab IDs,
orientation, pane proportions, optional name/icon and a sidebar anchor. Parc
supports up to four panes, and a slot can hold a perpendicular stack; see
[stacked panes](split-stacks.md). Selecting a child displays its group and focuses that
original child. Split operations preserve live pages and local document editors
unless an explicit close or cross-Profile move requires native retirement.

This guide describes the model, gesture and lifetime contracts. Menu/keyboard
entry points also appear in [split navigation](split-navigation.md), while the
[product guide](product.md) keeps split decisions and the [backlog](backlog.md)
holds unfinished work.

## Ownership and cancellation

Sidebar drags carry an opaque session token; authority remains with the original
source object and one-shot transaction. Text resembling an item ID cannot move a
tab. Admission and commit validate the window, Profile/Space, selected group,
focus, ordered membership, saved state, native pages/wrappers and security state.
Closing, retirement, transfer, modal/Peek/fullscreen restrictions and pending
Profile removal can refuse the operation.

Previews do not reparent a renderer or create substitute pages. Geometry or
ownership changes revoke the proposal; exit, Escape and drag termination clear
it. Final commit repeats validation and executes once. A canceled preview never
changes the model or supplies unload consent.

An existing child retains its page and editor. A saved child materializes through
normal selection only after a successful transaction. Replacement and separation
keep the displaced page alive. Storage failure retains the previous model and
provides a truthful refusal or retry.

## Split containers and saved-home membership — SP21

`SplitMembership` owns joining, leaving and migration. Every group occupies one
container: Today, a pinned root/folder, or Profile Favorites. Each child stores
that same placement, while the sidebar displays the group once at its anchor.
An ordinary tab belongs to one split per Space; a Favorite belongs to one split
per Profile.

**Favorite groups are Profile-wide.** Every Space in that Profile sees the same
membership, orientation and proportions. Moving the Space that stores such a
group to another Profile first relocates the group to a surviving Space of its
original Profile.

When saved tabs newly join a split, fresh saved-home references remain in their
exact former slots, while original IDs, pages, history and editors join the
split. A child taken from another saved split leaves its home there. Creation
and explicit move paths can omit the copy when their transaction requires it.
Typed Note/Easel homes are validated aliases of the same local document.

An existing split keeps its destination container; new members adopt it. A new
split uses the first ordinary candidate's Today position, or the top of Today
when no such candidate exists. A new split cannot nest inside another split.
Fresh web homes open in the background only after durable publication.

Leaving a group puts the departing child immediately after it. Two or more
survivors retain the group, relative weights and appearance; one survivor
dissolves it in place. Dissolution replaces the sidebar slot with children in
pane order. The rule applies to Separate, Close, replacement and membership
transfer. Pin/Unpin on a split pane moves the entire group together.

Migration resolves overlapping groups deterministically: a Favorite's Favorite
container first, then the displayed group, then recent groups. Surviving children
retain their relative weights and original records. Legacy mixed containers
normalize without losing saved homes. Favorite return selections in other Spaces
follow the fresh home reference. Migration persists stable IDs and anchors.

Whole-group moves, including ancestor-folder and physical-window moves, normalize
all children to their destination container atomically. The twelve-root Favorites
tray limit refuses only growth beyond the limit; it does not erase existing items.

## Original group name and icon

A group name/icon belongs to the group, not its focused child or URL. Ordinary
rows use their existing rename owner; Favorite groups use the required-name
sheet. Reset, context-menu rename, accessibility and current-split Rename share
validated group identity. Renaming one window's stale group cannot overwrite a
newer edit. The icon picker accepts the bundled catalog; unknown stored icons
fall back safely. Name/icon changes preserve child identity and geometry.

## Split cell container — SP30

`SidebarSplitGroupView` and `SidebarSplitCellLayout` render one sidebar row for the
whole group. Untitled groups show a horizontal child strip regardless of page
orientation. Custom-titled groups show group information. Children share width,
with 28-point height, four-point gaps and backing-aligned frames; separators hide
for a selected group. The shared row background owns current, multiselect,
hover, keyboard-highlight and inactive-window appearance.

The cell Close appears on hover unless the current Today group exposes child
Close controls instead. Closing/deselecting follows saved-versus-Today policy
through the existing native consent owner. Tooltips include current bindings.
A child right-click uses the group menu; Tab Options contains its individual
commands. Children are not independent drag sources: the entire row is one
split drag source.

## Separate Page and original focus

Separating the focused child displays that original page alone; siblings retain
their saved group. Separating another displayed child leaves the current focus
among the survivors. A background group changes only its saved state. Selection
and membership save together before focus publication.

Separate All dissolves one group in a single transaction and preserves the
displayed group's focused page. Neither action closes pages, reloads navigation
or replaces Notes/Easels. Native focus returns only if presentation removed the
previous responder; an existing sidebar responder is not stolen.

## Original pane menu and Add Split

A single page offers Add Left/Right and Add Top/Bottom. Multiple panes offer
orientation-appropriate Move and Add commands, the [stacked](split-stacks.md#starting-a-stack)
Add and Move items, Separate, Convert orientation and Copy Links. Each menu
retains the exact original window, group, ordered pages,
focus and geometry. A missing neighbor or fifth pane is disabled. Reorder moves
original IDs and proportions without navigating.

Copy Links copies every web page in the split in pane order, through the link
formatter the sidebar's [link copies](sidebar-selection.md#select-all-and-plural-commands)
use: one address per line as plain text, plus a rich-text version that links
each page under the title its sidebar row shows, so Notes, Mail or a document
paste titled links. Notes, Easels, Parc's own pages and blank tabs are
skipped, a page appears once, and the item is disabled when no pane has a web
address. A Copied Links notice with Share confirms it. Each pane's page menu
keeps its own Copy URL and Share.

Add creates a window-owned pending pane and opens the command bar; it does not
load an empty webpage. Cancel removes only the pending pane and restores the
previous content/Find focus. URL submission retains its complete native request.
Existing tab, Note and Easel results keep their original owners. New Note/New
Easel can fill the pending pane through the same draft index/orientation.

Admission remains live during asynchronous resolution. Failed persistence,
destination refusal or stale ownership retires that draft without an orphan
placeholder. Favorites and ordinary tabs from other Spaces of the same Profile
can join; the window stays in its own Space. `SplitCrossSpaceAdd` preserves a
pinned item's original home and repairs its former Space's remembered selection.
The command bar offers no cross-Profile destination for Add.

## Divider pair sizing

Dragging a divider changes only its original adjacent pair while preserving the
pair's combined share. Double-click equalizes that pair, leaving other source
weights intact; Make All Split Panes Equal evens every pane. The resize receipt
binds page owners, window, selection, orientation, host bounds and backing scale.
Changes invalidate it; rejection restores current authoritative geometry.

Expanded panes honor the 220-point minimum. Layout redistributes minimum deficits,
rounds lengths at the owning window's scale, then aligns final edges. The last
pane does not absorb all rounding remainder. Live resize uses the same geometry
as committed layout. Nonfinite/invalid scale falls back safely; nonpositive
persisted weights refuse.

## Keyboard and VoiceOver resizing

Each divider is a VoiceOver splitter, so VoiceOver walks pane, splitter, pane.
Its value is the divider's position as a percentage of the split, with limits
that keep both neighbours at the 220-point minimum. VoiceOver's increment and
decrement move it one step and change only that pair. The container itself
stays ignored, and dividers are not Tab stops, so there is no focus ring.

The [split navigation](split-navigation.md) commands Widen Current Split and
Narrow Current Split step the focused pane. Widen takes room from the other
panes in proportion to what each has above the minimum, and Narrow hands it
back in proportion to their size. Make All Split Panes Equal is the one-step
way back after Expand. Each command is disabled when it would change nothing.

A step is a tenth of the split. One that crosses the even point, half the pair
or an equal share for a pane, stops on it. Steps start from the saved weights,
or from the displayed sizes while the minimum overrides those weights, as after
Expand. Splitter steps and all three commands commit through the same window
receipt as a finished drag, so the minimum, window validation and persistence
apply. They refuse during a live divider drag, a drop preview or a tab drag
into the split, and lay out at once without the drag's haptics or motion.

VoiceOver hears a divider's new value once whenever its reported percentage
changes, whatever moved it: a step or command, a finished drag, a double-click,
Expand, a pane arriving or leaving, or a window or sidebar resize. Nothing is
posted while a divider drag, drop preview or live window resize is under way;
the split compares values when it ends. A change that comes only from the
split's size waits until the size has held still for 0.3 seconds, so a sidebar
drag posts once it stops. A pane arriving or leaving also announces its
splitter as created or destroyed, with a layout change on the split's parent.

## Divider center snapping

A native pan starts only within the actual divider region. Snapping arms after
moving at least 14 points away from the pair center. Approaching within that band
snaps when the absolute native x velocity is at most 120 points per second and
points toward the center, including for vertical layouts. Crossing the band
releases an existing snap. Engage/release each emit one generic native haptic,
independent of the tab-reordering preference.

## Command-driven split choreography

Add/remove, Separate, orientation changes, reorder and Expand publish immediate
logical geometry. Expand gives the focused pane the available share after other
expanded minimums; it is not a maximize/restore toggle and does not move focus.
Accepted adjacent equalization animates the existing surfaces over 0.2 seconds
with ease-out, without delayed selection or save callbacks. New gestures, owner
loss or incompatible geometry clear only that owned transition.

## Divider regions, pane input and content-resize reasons

Side-by-side divider input excludes the top 53 points of its ten-point handle.
Stacked dividers inset their interactive region eight points at each end. Hover,
cursor, pan and double-click use the same region. Grips remain centered on the
whole handle, and tracking is active for the key window during a drag.

A divider pan temporarily makes pane hit tests fall through to the split owner.
Input resumes before final proportions publish; every cancellation restores it.
The `.splitDividerResize` reason exists only during a real pan. The separate
`.splitInteractiveEditing` reason locks content size from first admitted drag
entry until its terminal callback, surviving exit/reentry and preview replacement.
A new drag replaces an unterminated old edit without a gap. Detachment ends it.

Resize reasons compose with sidebar reasons: clearing one cannot release a lock
held by another. The content-resizer recomputes intrinsic/throttled/locked mode
from the remaining reasons. External URL routing retains a terminal witness and
can end an abandoned outside-window gesture on mouse release.

## Pane-drop target regions

Original-tab and external-URL drops classify the entire pane, including its
header and Developer Mode strip. One pane offers horizontal insertion within
40% of each side and vertical insertion within one-quarter of height, capped at
50 points. Vertical edges win at corners. Multiple horizontal panes use one-third
width capped at 80 points; stacked panes use one-third height capped at 50 points.
Threshold equality belongs to the center; gaps are not pane targets.

An unavailable edge insertion can fall back to replacement of the same pane.
A full split can therefore replace a child without exceeding capacity. Preview
and commit share the classifier and original lease.

## Replacement highlight, pending pane and proposal feedback

Replacement draws a highlight on the existing pane, preserving its content.
Insertion reserves real layout space and presents a placeholder card across the
whole pane region. Original panes and their pages retain identity while their
frames adjust. The proposal retains its intended target while the pointer remains
inside the reservation; reclassification cannot bounce against its own layout.

Reserved-region expansion/collapse and border changes own their 0.2-second
transitions. Transition identities prevent an old completion from removing a
new reservation. Drag proposal changes and divider snaps have separate haptics.
Pending Add panes use the empty-content backing/highlight and immediate logical
insertion/removal. No real pane uses the dormant fixed/collapsing drag-source path.

## External URL drops into ordinary split panes

One explicit HTTP(S) URL without embedded credentials can insert a new Today tab
at an edge or replace the visible pane at its center. This creates a new
navigation; it never reconstructs an existing dragged page. Replacement keeps
the displaced original alive and preserves group identity/name/icon/weights.
New tab, selection, home references and group placement save atomically.

`PCNativeContentDropRouter` offers the native gesture to a typed ancestor before
renderer delivery. Unclaimed drags keep their ordinary renderer/editor route.
Once claimed, an expired/canceled recipient cannot turn the same gesture into
unexpected webpage navigation or text insertion. The lease binds native view,
window, pasteboard/change count and drag sequence.

Files, internal/custom schemes and plural URLs remain with ordinary receivers.
Authenticated sidebar-item drags keep their item-move owner. Native page,
Note and Easel receivers share the router. Local composition, canvas gestures,
address editing, self-document drags and rich text/images retain their editor
routes. Replacing a local pane parks its original editor without discarding drafts.

An external URL on a standalone Favorite/pinned page preserves its saved home
before the original page enters a new Today split. An existing Favorite group
keeps its Profile-wide container; a displaced Favorite becomes a root. Capacity
and tray-limit refusal are atomic. A URL dragged from another Profile creates a
new navigation in the destination Profile; it does not move an authenticated page.

## Whole-split copy and external drags — SP23

A whole split moves through its private sidebar session. Option copies whole
splits with fresh item/group IDs and preserved saved placement/geometry. Within
one Profile, Note/Easel copies reference the same documents. The original window
and complete ordered membership remain validated through commit. Each copy
records one **Copy** Undo step in the window that received it.

The visible Space header moves items to the top of Pinned, or copies them there
with Option. A dock Space target moves/copies eligible items not already there to its
Pinned list when all are saved, otherwise Today, then selects that Space. Another
window uses the collection transfer owner. Folder-target placement follows
[folder moves](folder-moves.md).

The drag image omits transient hover/Close state. Private split tokens are not
URLs: pages, local editors, Finder and other applications cannot consume them.
A whole split does not tear off into a new window or become a page-area drop.
A failed external destination returns the drag image to its source.

Tabs, folders and mixed selections copy through the same session within one
window and shared data; see [Option-drag copies](folder-moves.md#option-drag-copies).
Only whole splits copy into another window or a Space that keeps separate data.
Those separate-data copies retire/reload original web pages through native
consent before saving the copy. A split holding a Note or Easel deliberately
never copies into a separate-data Space: Parc never duplicates a document's
contents, so moving the document is the supported path.

## Cross-Profile moves

Moving original items into another Profile asks once by default and warns that
reload can lose sign-in/progress. Cancel aborts; Move proceeds; Don't ask again
persists that choice. Space Profile reassignment has its own always-confirmed
operation. The prompt belongs to the destination gesture's actual window.

`moveAcrossProfiles` reserves the original set and requests real beforeunload
consent for every live page in every window. After retirement, one durable save
moves the same records/IDs and group geometry to the destination Space/Profile.
New pages load their current URLs in that Profile. Browser history, page state
and credentials do not transfer. Changed originals, refusal or write failure
cannot publish a partial item move.

Notes/Easels flush and close their editors, then relocate the exact documents.
Easel image assets copy to the destination store; record-save failure rolls the
documents back. A document still referenced in the source Profile refuses the
move, including a pinned document whose saved home would remain there; the
refusal explains where, as [folder moves](folder-moves.md#notes-and-easels-still-used-in-the-source-space) describes.

Same-Profile cross-window moves transfer actual pages/editors and embedded pages
without reload. Cross-Profile sidebar-to-pane, collection/window and Move to
routes share the explicit decision and retirement transaction. External URLs are
new navigations and need no Profile-move decision. See [Space management](space-management.md)
for assignment/conversion and [folder moves](folder-moves.md) for collections.

## Original pane title presentation

Pane titles format display text without rewriting navigation URLs. Copy,
accessibility, command entry and document ownership retain the complete original
URL. The title combines actual host and suffix styling, handles no-title and
insecure-context states, and publishes the frame only for the current pane owner.
Click/URL-menu actions revalidate that original pane before dispatch.

## Original top-bar container placement

Each split pane owns its top bar. The centered row is 32 points high with
five-point side padding, reserving actual leading/trailing controls before title
layout. Complete-title fit, edge collision and truncation are measured from real
control bounds. Per-pane Back/Forward/Reload remain tied to that pane.

## Essential edge groups and room

The sidebar address row follows the focused split pane unless the content Toolbar
replaces it. Split panes keep their own navigation/menu/close controls. Visibility,
modal obstruction and focus use current owner state rather than snapshots taken
when a menu opened. Controls displaced by narrow width retain their real menu
and keyboard routes; they do not manufacture alternate navigation.

## Top-bar page colour

The page-derived top band and title controls use the current pane's valid color
and appearance, preserving Space-theme fallback. The [top-band guide](top-band-color.md)
owns projection and transitions. Theme/selection changes cannot repaint a stale
or transferred pane through an old callback.

## Sidebar transition grip backgrounds

Split grip backing follows the sidebar/page transition state without borrowing
another pane's ownership. Logical geometry, native content-resize reasons and
paint transitions remain separate. See [sidebar motion](sidebar-motion.md).

<a id="s-slide-pinning-sidebar-round-3"></a>

Command-S sidebar transitions pin the split's relevant visual geometry for the
transition and release that state on completion/cancellation. They do not create
new page identities or become an additional split-resize transaction.

## Split keyboard, accessibility and focus — SP32

Numbered commands reject nonexistent panes; next/previous wrap. Commands focus
the registered page, Note/Easel editor or Start search through the existing owner.
Pointer presses select a pane after native event dispatch; ordinary Tab movement
does not change focused-pane selection. Toolbar actions focus their own pane.

Closing a focused pane selects the surviving pane at its old index, or the new
last pane. Closing another pane keeps focus. The same successor rule applies to
folder removal, saved selection and transfer. Expand does not take focus;
Separate/Move reclaim it only if presentation removed the previous responder.
Canceling Add restores the prior content's open Find field, otherwise the content.

The split container exposes its panes directly to accessibility, with a
splitter between neighbours; see
[keyboard and VoiceOver resizing](#keyboard-and-voiceover-resizing). Top-bar
buttons retain native roles, labels and focus behavior;
Close is labeled **Close Split View Pane**. The sidebar group exposes its actual
child/buttons, including visible Close, without inventing another close owner.

## Split gesture and context inventory — SP33

The group context menu offers Separate All Tabs, Add Tab…, orientation conversion,
Tab Options, Reset Name and Icon, Change Icon…, Rename…, Duplicate, Move to,
New Folder with n Items, and appropriate archive/close actions. Private windows
omit archival and use close wording. Multi-selection uses its selection menu.
There is no whole-split Share; the pane menu's Copy Links copies the split's
addresses. Add Tab targets the window's displayed content;
conversion can update a background group without changing selection.

New Folder uses the shared atomic collection transaction and one Undo/Redo step.
Undo compares affected records and refuses while the new folder contains unrelated
items; Redo preserves a name entered after creation. Ancestors expand, the row
scrolls into view and its inline title editor opens after a guarded delay. A
prompt is the fallback when the original row cannot host that editor. See
[folder commands](folder-commands.md#folder-row-creation-and-rename).

A standalone ordinary page shows the two-by-24 right-margin grip, with its resize
cursor/hover band 44 points high. It is decorative: no trailing pane exists to
resize. Split, pending-pane, popup and no-margin/fullscreen contexts hide it.
Page-loading indicators belong to [navigation](navigation.md), not divider state.

Four gestures are deliberately not offered: dragging that grip to open a split,
double-clicking a sidebar child to separate it, Option-clicking Close to unsplit,
and dropping one sidebar tab onto another to combine them. Arc built all four
and shipped them switched off, and each repeats Add Split View, Separate,
Separate All Tabs or Open in Split View. Double-click means rename on ordinary
sidebar rows, so on a split child it would give one gesture two meanings.
Option-click Close means close the other tabs in Safari, and an onto-tab drop
target would crowd reordering and folder drops in the busiest drag code.

## Source and validation

Core owners include `SplitMembership`, `BrowserSplitLayout`, `SplitPaneResize`,
`SplitCrossSpaceAdd`, `SidebarWindowMove`, `SidebarFolderFromItems` and
`BrowserStore` transactions.
Presentation owners include `ParcSplitView`, `SplitDropView`, `SplitDragView`,
`SidebarSplitCellMenu`, `SplitPaneMenu` and the native content-drop router.

Relevant existing checks are `test-split-context.sh`, `test-split-dividers.sh`,
`test-split-divider-snap.sh`, `test-split-pane-controls.sh`,
`test-split-appearance.sh`, `test-external-split-drop.sh`,
`test-inter-profile-move.sh`, the model/store suites and `tests/NativeContentDrop`.
Inspect their entry points and obey [AGENTS.md](../AGENTS.md) before running them.

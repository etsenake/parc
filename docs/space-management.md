# Space management

Space management includes native header editing, Library cards/order, original-
target menus, Profile assignment, deletion/Undo and Turn into Folder. Space
navigation, global app appearance and theme Undo retain their separate owners.

## Header, title and icon

`BrowserSpace.title` stores optional authored text separately from its positional
**Space N** name. Legacy matching placeholders migrate to nil once; explicitly
authored identical text survives later decoding. Insertion refreshes positional
names. Assigning the compatibility `name` interface authors a title.

The focused header edits natively with Return, Escape, Done and marked-text
protection. Untitled headers remain visible while editing. Another Space's menu
opens a target-specific sheet without selecting it. Save rechecks original
Space/Profile/title and persists before publication; unrelated theme changes do
not invalidate naming. Failed writes and competing renames preserve authoritative
state. Icon changes use the original Space/Profile/icon lease, renewing it after
each accepted choice; Remove writes nil and failure preserves the draft.

With multiple Profiles the header shows the actual assignment. Set Profile and
its accessibility actions share original-target callbacks; retiring Profiles
cannot be chosen. New Profile opens the real Settings owner for that Space
without first switching the browser selection.

## Complete manager and original-content transactions

**Manage Spaces…** is an unbound command opening Library's remembered Spaces
category. Every `SpaceManagerView` card owns a real `SidebarView` and shared
`ThemeRendererView` for its original Space. Cards omit address bar, profile-wide
Favorites and dock, but retain the header and ordered Pinned/Today contents.

Rename, icon/Profile choice, background theme editing, folder creation and
row actions bind original Space/Profile/window. Tab activation uses the real
page, Close uses native retirement and disclosure uses the original model
transaction. A background theme editor survives ordinary renders; target
removal/reassignment, originating active-Space change or Library teardown retires
it. Folder rename keeps original name/parent/Space/Profile while allowing unrelated
disclosure changes.

Native horizontal dragging shares the same atomic order transaction as Move
Space Left/Right and accessibility alternatives. Stale menus cannot silently adopt
another order. The key loop reaches real sidebar controls, Space Options and the
next card; Return enters the sidebar, row arrows use original-tab activation,
and Escape clears selection before exiting Library. Only real callbacks appear
in accessibility. Category changes/closure retire editors and popovers.

### Delete Space

`SpaceDeletionTarget` binds original tabs, folders, whole splits and order. It
refuses the last Space, stale membership, pending Profile removal, unavailable
typed documents or unsafe native ownership. After the originating confirmation,
all affected pages must accept whole-set retirement before one save removes the
Space/folders and archives original tab/document references with provenance.
Refusal or failed persistence publishes no partial model. Deleting a Space never
deletes the underlying Note/Easel document.

Profile-wide Favorites survive even when that Profile loses its last Space.
Their storage anchor moves without changing Profile, navigation or split geometry;
later Profile assignment reattaches complete groups. Fallback uses a surviving
same-profile Space, otherwise the clamped original neighbor position.

Window-owned **Delete Space** Undo restores original position, hierarchy, archives
and originating focus; it does not rewind Favorites or other windows. Redo checks
original membership and asks fresh close consent. Added children invalidate it;
successful Redo renews the focus snapshot. Unsafe inverse conflicts are refused.

### Turn into Folder

`SpaceFolderConversion` moves original ordinary tabs, folders, splits and mixed
order into a source-named folder. Today becomes pinned in a nested **Today**
folder; Favorites stay separate. Source shell/storage anchors disappear in the
same save. Same-profile conversion obtains every physical-window lease and keeps
live pages/editors. Its Undo/Redo reverses placements while retaining live
navigation/title updates and refuses added descendants.

Cross-profile conversion uses confirmation, retirement and document relocation;
it does not offer this same Undo path or reparent a live page across Profiles.
Stored-alias restrictions remain authoritative.

### Profile assignment dependency

Assignment always asks its own confirmation, independently of move-confirmation
suppression. Header, card and Settings use the same transaction. `assignProfile`
relocates exact Note/Easel storage and rolls it back if persistence fails; it
never just changes their Profile IDs after closing pages. Original membership
and ownership remain valid through retirement. New Profile creation authorizes
its original assignment context and saves the Profile atomically.

## Library Spaces page presentation

| Element | Current layout |
|---|---|
| Cards | 240-point width, 24-point gaps, 48-point vertical/24-point horizontal collection insets. |
| Card surface | 12-point corners; themed canvas over opaque local backing, with no behind-window material. |
| Sidebar | 5 points below top and 44 above bottom; no New Tab row or Favorites drop band. |
| Controls | 34-point strip; grabber and More at opposite edges, 28-point targets. |
| Add Space | 48-point item containing a 30-point circle and 16-point plus, themed from the owning window. |
| Page inset | 4 points between the collection and its page-column edges. |

More has a 6-point rounded hover/focus shape and anchors theme/icon popovers
when the header is hidden. The header hides for one untitled/iconless Space,
appears with multiple Spaces and remains visible during Rename.

The divider exists only with Today items; card Clear is visible without sidebar
hover. It archives that card's owned Today items through shared retirement,
without switching the active Space; foreign-window owners are left alone. Hover/
key entry rereads eligibility before tinting or dispatch. VoiceOver can press it;
the ordinary Clear Today command still targets the window's active Space.

An empty Today has no divider/Clear but retains an invisible Today drop region
below its final pinned row. An entirely empty, headerless card has only a 2.5-point
Pinned drop band; the rest is Today. The drag-time expanded divider target is
not implemented. This is a known narrow target, not an absent drop transaction.

### Library width on the Spaces page

The page reports `216 + 264 × spaceCount`; other Library pages report 417.
Window layout uses `max(min(windowWidth − 56, contentWidth), 417)`.
Opening applies the first width directly. Later page changes animate Library,
page host, side panel, Find and loading host together over 0.2 seconds with cubic
(0.25,0.46,0.45,0.94). Close/disposal/bounds changes cancel; hidden, minimized or
live-resizing windows lay out immediately. This width transition currently also
runs under Reduce Motion.

Width is sampled on page change, not every Space mutation. Adding/removing a
Space while on this page retains that width and uses horizontal scrolling;
leaving and returning reports the new count. Native trees are laid out once
at completion, and closed windows reject stale completions.

## Complete-row checks and independent review

Space-management/store/inter-Profile components cover title migration, exact
leases, failed saves, deletion/Undo, document relocation and owner preservation.
`tests/SpaceManager/check.py` exercises real inert cards/sidebar controls and
accessibility wiring. `tests/LibraryWidth/check.py` and sidebar motion/layout
checks cover page-change reporting, clamps, cancellation and geometry.
Compiler/component checks are distinct from live keyboard, VoiceOver, browser
or complete visual acceptance. Current remaining product work is in
[the backlog](backlog.md), not an accumulating delivery history here.

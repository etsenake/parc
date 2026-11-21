# Space management

Space management includes native header editing, Library cards/order, original-
target menus, data sharing, deletion/Undo and Turn into Folder. Space
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

The header shows only the Space's icon, name and the ellipsis or Done button,
plus the Incognito indicator in a private window. It never names a Profile, and
the Spaces menu and File menu have no Change Profile or New Profile items. The
Space menu (header ellipsis, sidebar and dock context menus, Library cards) has
**Share data with**, a submenu listing each other Space with a checkmark on the
Spaces that already share data with this one, a separator and **Keep separate**,
checked when no other Space shares. VoiceOver gets the same choices as "Share data
with <Space>" and "Keep separate". The menu and its accessibility actions share
original-target callbacks; a Space whose data is being removed cannot be chosen.
Each choice goes through the confirmation described under
[Sharing data between Spaces](#sharing-data-between-spaces).

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

Delete is available from the Space menu and from Edit Space in Settings (the
confirmation then appears over Settings). `unusedProfile(ifDeletingSpace:)` tells
beforehand whether the Space is the last one using its data. In that case the
confirmation adds "This also deletes its logins, saved passwords and history. This
can’t be undone.", no Undo is registered, and after the deletion succeeds the data's
removal is handed to `ProfileRemovalController`, which stages it and removes the data
in the background. If the data's users changed while the dialog was open the delete
is refused. Deleting a Space that shares data is unchanged and keeps its Undo; Redo
is refused if it would now delete the last copy of the data.

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

Changing sharing asks its own confirmation when something consequential happens,
independently of move-confirmation suppression. Menu, card and Settings use the
same transaction. `assignProfile` relocates exact Note/Easel storage and rolls it
back if persistence fails; it never just changes their Profile IDs after closing
pages. Original membership and ownership remain valid through retirement.

### Moving tabs between Spaces

Moving tabs to a Space that shares the same data never warns and keeps the live
pages. Moving to a Space with different data asks first: "<Space> uses different
data, so you might get logged out or lose your progress in these tabs."

## Sharing data between Spaces

Every Space points at exactly one underlying Profile. Spaces on the same Profile
**share data**: logins, saved passwords, history, extensions and Favorites. The
model offers only two choices, "Share data with <Space>" (`SpaceDataSharing.share`)
and "Keep separate" (`.separate`); Profiles are an implementation detail.

**Upgrade.** The first load of an older session file gives every Profile that has
no Space and no pending removal a new Space named after it, with the active
Space's theme and the `circle.fill` symbol. Spaces that already share keep sharing
and nothing is deleted. Saved Links routes that point at a Profile become the
first Space in sidebar order on that Profile, or the most recent Space if none.
`BrowserState.spaceSharingVersion` records the upgrade, so it runs and saves once.
After it, a Profile without a Space exists only while its removal is pending; new
code never leaves one behind.

**Auto-Archive per Space.** `BrowserSpace.autoArchiveHours` is optional (older
files decode it as nil) and the upgrade seeds it from the Profile. The archive
sweep uses the Space's interval, falling back to the Profile's. New Spaces take
the creating Space's interval. Settings changes only the edited Space through
`setAutoArchiveInterval(_:forSpace:)`.

**Create.** `createSpace(name:sharing:)` and the sidebar's `SidebarNewSpaceDraft`
(`shareData(withSpace:in:)` / `keepSeparate()`) add the Space and, for Keep
separate, its new Profile named after the Space in one save. Nothing exists before
commit, so cancelling the form leaves no Profile behind. When the draft moves
items onto another Profile, `createSpace(_:completion:)` runs the ordinary
inter-Profile move: page retirement and Note/Easel relocation.

**The creation form.** The sidebar's "Create a Space" form has a **Share data
with** popup instead of a Profile picker. It lists every Space by name, with its
icon when it has one, then a separator and **Keep separate**. A small line under
the row says "Logins, passwords, history, extensions and Favorites." The popup
starts on the Space the window is in, and carried tabs may go to any choice; a
different-data choice asks the move confirmation first. Spaces whose data is
being removed are not listed. Create commits through `createSpace(_:completion:)`
and a failure or cancelled confirmation keeps the form open for another try.

**New Space from anywhere.** File → New Space…, the command bar's Create New Space
and the sidebar and Library entries run one app action. It uses the frontmost
regular window (never a private window or popup), first closing whatever is in the
way there: Library, the command bar, a Peek, a page capture, Find, the Site
Control Center, pending renames and pickers. It then opens the sidebar form,
or focuses it if it is already open. A Peek whose page has the camera or
microphone live asks to be confirmed first: New Space shows the Peek's own Hang up
button and, once the person confirms and the Peek closes, goes straight on to the
form; if they let the confirmation lapse or the window closes, nothing more
happens and no capture is ever cut off. Pressing New Space again while Hang up is
showing only brings the window forward; only Hang up ends the call, and one wait
runs at a time. Other blockers are retried for about two
seconds before New Space quietly gives up. With only private windows or none, it opens
a regular window first. It works while Settings is the key window, so Settings
closes itself and sends the same action. `NewSpaceWindowChoice` makes the window
decision and `NewSpaceBlockerWait` the wait-or-give-up decision.

**Change sharing** moves a Space, never merges Profiles. `changeSharing(ofSpace:to:)`
reuses the [assignment](#profile-assignment-dependency) transaction; Keep separate
creates the new Profile in the same save and does nothing for a Space that already
keeps separate. The result names the previous Profile when no Space uses it any
more. `SpaceSharingConfirmation` shows one of these, only when something consequential
happens, and re-checks the Space, its tabs and the target before and after the
confirmation:

- **Share data, previous data becomes unused:** "Share <Target>'s data with
  <Space>?" with a red **Share Data**; the Space's pages reload signed in as the
  target and its own logins, saved passwords and history are deleted for good.
- **Share data, previous data still used by another Space:** the same title with a
  plain **Share Data**; pages reload with the target's logins, history, extensions
  and Favorites.
- **Keep separate** for a Space that shares: "Keep <Space> separate?" with **Keep
  Separate**; it starts fresh, signed out everywhere with no history, extensions or
  Favorites.
- Choosing what the Space already has, or keeping separate a Space that already is,
  shows nothing and changes nothing.

Before any of these, a change that would strand one of the Space's Notes or Easels
on the old data is refused and explained instead, as
[folder moves](folder-moves.md#notes-and-easels-still-used-in-the-source-space)
describes; `sharingDocumentBlock` previews the store's own assignment for it.

The wording and the choice live in `SpaceSharingWarning`. When the change leaves
data unused, the confirmation hands it to `ProfileRemovalController.remove`, which
stages the removal record and prepares it natively in one step. Failures use the
standard error dialog.

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
below its final pinned row. An entirely empty card shows a plain Pinned label at
the top of its list. The whole label takes a Pinned drop, highlighted like the
sidebar's Pinned header, and the rest of the card is Today.

### Library width on the Spaces page

The page reports `216 + 264 × spaceCount`; other Library pages report 417.
Window layout uses `max(min(windowWidth − 56, contentWidth), 417)`.
Opening applies the first width directly. Later page changes and Space-count
changes animate Library, page host, side panel, Find and loading host together
over 0.2 seconds with cubic (0.25,0.46,0.45,0.94). Close/disposal/bounds changes
cancel; hidden, minimized or live-resizing windows lay out immediately, and so
does every width change while Reduce Motion is on. Turning Reduce Motion on
mid-transition settles Library at its final width along with the sidebar.

Every applied Library reload recomputes the width and reports only a different
value. While this page shows, a Space deleted or turned into a folder, either
one's Undo or Redo, and a Space created or deleted in another window resize
Library, so no empty strip remains and a restored card stays in view. Theme,
name, order and tab changes, choosing the shown page again and moving between
417-point pages report nothing. Native trees are laid out once at completion,
and closed windows reject stale completions.

## Checks

`SpaceSharingTests` (run by `swift test`) covers the upgrade, Links conversion, per-Space
Auto-Archive, atomic creation, change sharing, which warning each situation gets,
unused-Profile reporting and the Note and Easel refusal explained before the warning.
Space-management/store/inter-Profile components cover title migration, exact
leases, failed saves, deletion/Undo, document relocation and owner preservation.
`tests/SpaceManager/check.py` exercises real inert cards/sidebar controls and
accessibility wiring. `tests/LibraryWidth/check.py` and sidebar motion/layout
checks cover page-change and Space-count reporting, clamps, cancellation, Reduce
Motion and geometry.

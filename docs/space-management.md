# Space management

SPACE18 implements the finite Space/profile management experience described
below: header editing, Library cards/order, original-target menus, Profile
assignment, deletion/Undo and Turn into Folder. Completed Space navigation,
global application appearance and original-window theme Undo keep their
existing owners. Reference facts and explicit native/schema adaptations are
recorded separately from live interaction acceptance.

## Retained and new reference

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The [Sidebar header contract](sidebar-resize.md#space-header) already establishes
the optional title, positional “Space N” placeholder, editing visibility, Done
button, icon picker and shared original-Space menus. SPACE18 reused that work.
The local recovered-components, Swift-type, cross-reference and annotated
function helpers supplied the following additional evidence; no direct REA
provider or decompilation slot was used for the first increment.

  (case 0), `focusSpace` (1), `presentStyleEditor` (6), `updateIcon` (8),
  `updateTitle` with an optional String (9), and `acceptSpaceDrop` with an
  index/indexing style (10). A background Space's rename dialog does not imply
  focusing that Space. The focused dock's closure enters the header directly
  and left/right layout. `ProfileIndicatorConfig.Icon` has profile/incognito;
  builds `ProfilesUI.ProfileIndicatorHostingView` with full size and no chevron
  inset, 5-point and 6-point shape constants. Precise color, font, icon and
  compression were compared in the complete-manager increment below.
- MainMenu record 554 is `openSpaceManager`, unbound by default, and opens
  `LibraryCategory.spaceManager`. Record 84 is Change Profile with no binding
  ID. The [keyboard inventory](keyboard-navigation.md#complete-command-inventory-reconciliation--kb03)
  retained these feature dependencies.
- `SpaceManagementViewControllerSpacesPage` has one horizontal-scroll item.
  `SpaceManagementHScrollCollectionViewItem` owns real window stores, selectable
  Space cards and native drag/drop callbacks. Its layout direction is horizontal
  `SpaceManagementCollectionViewItem` owns a real `SidebarSpaceViewController`,
  a theme background, shadow and `SpaceControlsView`. This requires a Library
  category containing original Space contents, not an unrelated settings list.
  source, optional Undo information and skipConfirmation. Sources distinguish
  context menu, Undo Add Space, Turn Space into Folder and excluded account
  deletion. Undo retains index, original items/custom info and focused state.
  `CloseContentAction.beginDeleteSpace` and
  `WindowsCloseContentAction.completeDeleteSpace` place actual content teardown
  ‘name’ Space?” and explains that its tabs and folders are archived. Completion
  questions for the deletion implementation. A raw array removal is insufficient.

Annotated helper receipts are local under

## Current implementation increment

`BrowserSpace.title` now stores the optional authored title separately from
its positional display name. Legacy names equal to their original “Space N”
placeholder migrate to no title once; explicit titles equal to that string are
encoded with their title and survive subsequent decoding. Creation and existing
insertion paths refresh positional names. Ordinary naming callers retain the
`name` interface; assigning it is an explicit title change.

The real header enters a native field editor for the focused Space, including
Return, Escape, Done and marked-text protection. An otherwise hidden untitled
header remains visible for its editing session. Another Space's menu opens its
original-target sheet without selecting it. Original Space/Profile/title values
are rechecked on save, and atomic persistence precedes publication. A competing
rename or a failed write cannot overwrite authoritative state. Theme changes do
not invalidate an unrelated title lease.

Change Space Icon uses the existing shared icon/emoji picker with the original
Space/Profile/icon lease. Each successful choice renews that lease; Remove
writes nil, failure retains the previous icon and picker draft, and original
window/key ownership controls the lifetime. A transient picker never turns into
a page or URL action.

Set Profile uses actual profiles and the existing `BrowserStore.assignProfile`
page-retirement path. Header, dock and empty-sidebar menus share the original
Space target; retiring profiles cannot be chosen. Native submenu checks and
VoiceOver custom actions expose the same choices. The profile indicator appears
only with multiple profiles and names the actual assigned profile. Its present
AppKit button/glyph/compression are explicit adapters; the full-size label,
font and native hover/pressed comparison is recorded below.

No engine source changed and no functional browser tests were run. Inert model
and native-control checks cover title migration, distinct authored placeholders,
original identity, concurrent theme edits, failed persistence, icon races, native
editor completion/cancellation, menu actions and accessibility exposure. A
compiler pass is source validation, not live FKA/VoiceOver acceptance. The first
increment passes 31 focused management assertions, all 90 existing header
assertions and 796 BrowserStore assertions. Finished-source whole-module SIL
(`space18-increment1-cleared-final`) passes with zero diagnostics; clean reconciliation
with `e88ca92f` preserves the exact intended source. Fresh independent `increment1_review` cleared the exact source after floating
sidebar/picker ownership, hidden-anchor reveal, marked-text preservation and
profile key-loop/AX-cell corrections. Its final SIL pass has zero diagnostics.
Native page tests remain prohibited and were not run.

## Complete manager and original-content transactions

The full implementation closes the original finite checklist: Library cards,
ordering and item contexts; confirmed deletion and typed/native lifetime;
original-window Undo/Redo; Turn into Folder; background theme/folder dispatch;
and Profile presentation. The finished-source checks and independent review
below clear the complete row for publication.

`SpaceManagementHScrollCollectionViewItem.ItemType` distinguishes original
`space(ID)` and `addSpace`; collection selection alone does not establish that
clicking an existing card selects that Space. Each real sidebar card receives
its window store and menu provider. `SpaceManagementView.userInteractionEnabled`
adaptation. Full-size padding and rounded native hover/pressed presentation
retain their semantic color owner and native input/accessibility behavior.

The Library now has a real Spaces category and remembers it through the existing
entry preferences. The unbound **Manage Spaces…** command opens that category.
`SpaceManagerView` retains a shared `ThemeRendererView` and actual `SidebarView`
for each original Space. Its Space-only presentation removes the address bar,
Profile-wide Favorites tray and dock, while retaining the actual header and
ordered pinned/Today contents. Header menus, inline rename, icon choice, Profile
choice, background theme editing and folder creation retain the original
Space/Profile/window. Tab activation reaches the original page; closing uses the
existing page retirement owner, and folder disclosure uses the atomic original
folder transaction. Native horizontal scrolling and drag ordering share the same
original-order model transaction as Move Space Left/Right and accessibility
alternatives. Menu snapshots cannot silently adopt a newer order. The card's
keyboard loop reaches its real sidebar controls, Space Options and the next
card; Return enters its sidebar, row arrows and modifier singleton selection
use its prepared original-tab activation, and Escape clears an existing
selection before leaving the Library. AX advertises only implemented callbacks. Category changes
and closing retire its editor and popovers. These are source/inert guarantees,
not a claim of live VoiceOver or full keyboard-access observation. Background
card and dock theme editors retain a separate originating active-Space context,
so ordinary model renders do not dismiss a valid editor. An actual context
change, target removal/reassignment or Library teardown retires it. Folder
rename retains the original name, parent, Space and Profile through its sheet
and saves atomically; an independent disclosure change is preserved.

Reduced row menus, explicit card keyboard stops and the system Profile glyph
remain Parc-owned presentation choices. They do not create fake service
controls or new browser endpoints. The Library's width on the Spaces page
[Library Spaces page presentation](#library-spaces-page-presentation)).
Existing whole-product polish remains separate from this finite
exclusions are unchanged.

### Delete Space

The remaining specific deletion question required one reserved-slot decompile
the producer but did not resolve its Undo payload. Receipt
`ev_e60a14935f9a9401726edd661835f2dcefc4b5c1953be84d60c3dd92133f3fc4`
shows the original Space, index, items and focused state retained by
between begin and completion.

`SpaceDeletionTarget` binds the original live ordinary tabs, folders, whole
splits and order. Delete refuses the last Space, a stale target, pending Profile
removal, unavailable typed document or unsafe original native lifetime. The
originating window presents the real confirmation. All affected ordinary pages
must agree to the existing retirement transaction before one atomic session
write removes the Space/folders and archives their original tab/document
references with source and whole-split provenance. A failed write or refused
close changes no published model. Archive and local-document identities are
preserved; no document is deleted by deleting its Space.

Favorites belong to a Profile and are retained even after that Profile loses its
last Space. Their stored Space anchor moves without changing Profile, navigation
or group geometry; normalization preserves those orphan-Profile Favorite splits,
including after a second storage-anchor deletion. A later Profile assignment
reattaches their whole groups. This is a necessary storage adaptation for Parc's
session schema. The surviving same-Profile Space, otherwise the clamped original
ranking was not inferred from the Undo payload.

Original-window **Delete Space** Undo restores the original position, hierarchy,
archive records and actual window selection/focus. It does not rewind live
Favorites or unrelated windows. Redo revalidates original membership and uses
actual native close consent again; new children invalidate it. Each successful
Redo renews the actual originating window's focus snapshot. Competing changes
that make inverse restoration unsafe disable the entry without overwriting
those changes.

### Turn into Folder

The retained cross-Profile contract already named Space action 3 at
Space custom info and focus/index are retained in
`SpaceDeletionConfiguration.UndoInfo`.

`SpaceFolderConversion` moves original ordinary tabs, nested folders, splits and
mixed order into that source-named folder. Today items become pinned inside its
Today subfolder; Profile-wide Favorites remain separate. The source Space shell
and dormant storage anchors are removed in the same durable write. Same-Profile
conversion obtains all actual physical-window ownership leases and preserves
native pages and local editors. Original-window **Turn into Folder** Undo/Redo
reverses only the original placements and safely refuses newly added descendants;
live navigation/title updates are retained. Another Profile uses the existing
confirmation and page-retirement/document-relocation transaction, with its
recovered non-Undo policy and existing stored-alias restrictions. It never
reparents a live page into another Profile in place.

### Profile assignment dependency

The existing Settings contract identified `didSetProfileForSpaceIDs`
asks and does not use the move-confirmation suppression preference. Its
title and button are Parc adapters; the underlying original-target choice and
consequences are retained. Header, card and Settings assignment share this
confirmation. New Profile opens the real Settings owner for the original card's
Space without switching the browser's selected Space.

The required storage dependency was completed in this row: `assignProfile` now
uses the real cross-Profile transaction, including exact Note/Easel relocation
and rollback if persistence fails. Previously it only changed Profile IDs after
retirement, leaving a typed document in its old Profile's storage. Original
window/Space/Profile/membership validity is checked through retirement. Native
retirement flags are not mistaken for owner loss. The creation sheet already
explicitly authorizes assignment to its original Space; it persists a new
Profile atomically and validates that original assignment context. This closes
a necessary dependency and does not grant additional Settings or Folder ledger
credit.

## Complete-row checks and independent review

The finished implementation passes 62 management transaction assertions,
including stale name/placement/Profile and disk-failure folder rename cases;
14 inert actual `SpaceManagerView`/`SidebarView` responder and AX assertions;
31 native header/menu assertions; 798 BrowserStore assertions; and 99 inter-Profile
assertions including disposable Note/Easel relocation. The responder fixture uses
an undisplayed native window with a local key-state accessor and direct methods,
not OS event dispatch or a browser. It verifies real row arrows, modifier
singleton activation, expired owners, supported AX names, and selection-first
Escape. The final whole-module warnings-as-errors SIL (`space18-review-final4`)
passes with zero diagnostics. Earlier failed harness receipts are not acceptance
evidence; receipt scopes are retained in `spaces-profiles-checks/space18`.

Fresh independent `fullrow_review` cleared all tracked and new source after
correcting background theme context lifetime, manager responder/AX wiring, and
original-target durable folder rename. The actual responder fixture also caught
the singleton-folder Escape distinction, which is fixed and covered in the
cleared source. The final review input manifest and author receipts are retained
beside the check logs. Reconciliation with `cbc09a1e` changes only upstream
ledger documentation and preserves every reviewed input hash. SPACE18 closes
its original finite checklist; separate Settings, Folder and whole-product polish
rows receive no added credit from the dependent fixes here.

## Library Spaces page presentation

type, cross-reference and annotated-function helpers; no decompilation slot was
used. Assets were read from the reference 1.170 bundle only.

- **Collection.** `SpaceManagementCollectionViewLayout.prepareLayout`
  more gap, centred on the collection's height. `SpaceManagementLayout` holds
  these values. The strip sits 4 points inside the page column on each side
  ([Library width](#library-width-on-the-spaces-page)).
  view, a `WindowBackgroundViewLegacy` theme view, a clipped container, the
  real `SidebarSpaceViewController` and `SpaceControlsView`. The shadow view
  0.5 in Dark Aqua) under a black 0.15 shadow of radius 12, offset (0, 1). The
  paints over that fill without the window's behind-window material
  (`ThemeRendererView.drawsMaterial`). That material made Parc's card a
  saturated panel showing whatever was behind the window.
  unflipped container 34 + 10 points above the card's bottom and 5 below its
  card's bottom in the flipped item view. The screenshot confirms both.
  centre-aligned, with insets 4/8/4/8: the grabber at the leading edge and More
  is the 16-point Feather move glyph U+E9A7 (small-string `0xa7a6ee`), with the
  is Feather more-horizontal U+E9A4 in a 28-point hoverable button with the
  tooltip "More options". Both glyphs use ForegroundSecondary over one hover
  pressed. Parc keeps "Space Options" as the accessible name and the existing
  menu. When the card's header is hidden, Edit Theme… and Change Icon…
  popovers attach to More instead of the whole card sidebar.
  30-point circle. The symbol is "plus" at 16 points medium, described as "New
  Space-icon tint). Parc reads the owning window's current Space, not the
  store's active Space, which can belong to another window. The colours are
  resolved under the palette's appearance and again when the appearance
  changes.
- **Card sidebar.** The card shows no New Tab cell. Drops below the divider
  land in Today, because Today begins at the divider. With an empty Today no
  divider is listed, so the card keeps an invisible Today drop region below its
  last row and drops on its rows stay pinned. The Space header
  follows the window sidebar's `displayHeaderView` rule: hidden for a single
  untitled Space without a custom icon, shown with two or more Spaces, and shown
  while renaming. An ended rename hides it again without a catalog change. A
  shown header sits 8 points below the page's top with the list after it.
  before a shown Clear. Clear's `downArrowImage` is "arrow.down" in bold at
  measured from the reference, because its FontSet was not recovered. The
  window sidebar uses the same row but shows Clear only while the sidebar is
  hovered ([Today divider, Clear and New Tab](parity.md#today-divider-clear-and-new-tab)). In a card,
  (reached through TablistViewController's `SidebarSnapshotViewState` scope
  `exploreSectionDivider`) only while the Space's Today list is non-empty
  (`SpaceContainerType`), so a Library card with an empty Today lists no
  divider and no Clear, exactly as the window sidebar does. `context` gates
  Parc uses the one `SidebarChromeLayout.tablistSlots` rule for both. Gap: with
  `BrowserState` alone and resolves a sidebar drag per drop callback from the
  AppKit dragging session, so no drag state rebuilds the list and neither the
  card nor the window sidebar shows that exception. The visible cost is in an
  entirely empty card: it lists only the 2-point pinned header, so its Pinned
  drop band is 2.5 points rather than the divider's 15, and everything below
  is Today. Only a single untitled Space's card, whose header is hidden, is
  affected (a shown header is itself a Pinned drop target), and that is the
- **Clear's colours.** `SidebarClearButton` colours itself, so a card's Clear
  and the window sidebar's are the same. Its image view is tinted
  pointer is elsewhere and ForegroundPrimary while it is over Clear. The
  divider cell sets no colour on it; it only hides and fades it. So 0.3 is the
  colour of a shown Clear that is not hovered, not a resting state of the
  window sidebar, where Clear is hidden at rest. SidebarForegroundDarker
  background, as Parc's ForegroundTertiary measures.
- **Tidy is excluded.** The divider's `Buttons.tidyAndClear` case and
  out. Library cards show Clear only.
- **Clear in cards.** `UnpinnedSectionDividerState` carries the card's own
  Space ID. A card's Clear archives that Space's unarchived Today tabs in its
  Profile (`SpaceClearToday`), through the window's shared page-retirement
  archive, while the active Space is unchanged. As with the card's Close Tab,
  pages that another window owns are left alone. When another window owns
  every Today page, the card's Clear is disabled, as the window sidebar's is
  without Today tabs. Ownership changes without a card render, so the sidebar
  re-reads `canClearToday` as the pointer enters it or Clear (before Clear's
  hover reads its enabled state) and as its window becomes key; a flip
  re-reads Clear's hover, so a disabled Clear drops its ForegroundPrimary
  tint. A press that still finds nothing to clear beeps. A card's Clear is no
  press; the Clear Today command acts on the window's own Space.
- **More's keyboard ring.** More draws an exterior ring over its bounds with
  the hover fill's 6-point corners.

36-point inset to the trailing edge (the label extends its 2-point alignment
black or white close glyph ([ordinary row presentation](parity.md#ordinary-row-presentation--tab19)).

Checks: `tests/SpaceManager/check.py` runs 169 assertions over actual cards and
window sidebars. They cover the layout model and frames, the controls and
their tooltips, More's ring mask and its 6-point corners, the popover anchor,
the add circle, the header rule including a rename, the divider row, Clear shown
without hover and no New Tab. A card with an empty Today has no divider and no
Clear; a drop below its last row lands in Today and one on its last pinned row
stays pinned. An entirely empty card lists only the pinned header, with its
2.5-point Pinned band and Today below. They cover Clear's tints away from and under the pointer, and its availability re-read
as the pointer enters the card or Clear and as the window becomes key,
including a release that re-enables it and a disable that drops its hover.
They cover the tab row's title label spanning 2 points past the inset and the
trailing edge, idle and hovered (ending at the ×), its rename field and its
text ink, and the window sidebar's divider row and New Tab cell
([Today divider, Clear and New Tab](parity.md#today-divider-clear-and-new-tab)). They also cover
Today and Pinned drops through `performDragOperation` with an inert drag
session, a card with no Favorites taking no Favorites drop above its shown
header, Clear targets, and the add circle's own-window theme across two
windows and an appearance change. Negative controls fail as expected: no Today start at the
divider, a card that keeps its divider with an empty Today, no Today region
below the last row, a Favorites drop band in cards, the store's active Space
for the add circle, and no appearance refresh. Source assertions cover the window controller's card Clear,
ownership and window-Space wiring. `scripts/test-theme-rendering.sh` covers `drawsMaterial`. No browser,
on-screen window or application activation is involved.

### Library width on the Spaces page

The Library used to stay 417 points wide on every page, so the Spaces page's
annotated-function helpers; no decompilation was available. The coordinator
October 31.

- **Stored width [D].** `WindowLayoutController.homeWidth` (field offset global
  when it appears and on every page change: an `onChange(of:)` with an initial
  the width to 0.
  `SpacesPage.Configuration.ViewState.spacesCount`: 3 × (leading + trailing
  inset) + count × (card + gap) + the add item + one gap, so
  **216 + 264 × count** with the collection's constants above.
  `SpaceManagementLayout.libraryWidth(count:)` holds it.
  Library max(min(container width − 56, homeWidth), 417). 417 is a floor, not a
  cap, and the window contents frame starts at that width. `SidebarChromeFrames`
  applies it from `libraryContentWidth`; the earlier `min(417, width − 56)`
  reading was wrong. With Parc's 760-point minimum window, the floor only
  matters before a page reports. Many Spaces follow the same rule, with no
  extra limit: two Spaces in the narrowest window take 704 points, and five in a
  1470-point window take 1414.
  with implicit animation, 0.2 seconds and the anchored timing accessor
  `setNeedsLayout` and `layoutSubtreeIfNeeded`. The Library edge and the page
  card move together. It reads no Reduce Motion. While
  `isTrackingOrAnimatingSidebarPages` is set it only marks layout
  `trackingStateUpdateHandler` of the window's lazy
  `sidebarPage(SidebarPage) | home`, so opening the Library is itself one of
  its transitions (below). Parc opens the Library without pager motion, so it
  has no such gate.
- **Parc.** `LibraryView.contentWidth` is the width read at the last page
  change: the Spaces width or 417. `onContentWidthChange` fires only when a
  reload shows a different page from the one last reported, once the new
  `libraryContentWidth`. Opening sets it before the first layout, without a
  group. A later change runs `SidebarMotionController`'s `libraryWidth` style
  over the Library, page host, extension side panel, find host and loading
  indicator. The flush lays the new page out at the old width
  first. The geometry pass moves the Library, the page and the side panel
  inside the group, and the completion lays out their native trees once.
  Closing the Library, closing or disposing of the window, and any change of
  window bounds (the sidebar-motion layout key) cancel the group; a bounds
  change still flushes the page's native layout, and a closed window's
  completion does nothing. An invisible, miniaturised or live-resizing window
  screenshot (one Space, about 1.22 pixels per point) the card starts at 140
  points, the add circle's centre at about 428.7 and the page at about 480.7.
  The strip therefore sits 4 points in from each side of the page column, not
  and HomePageView's HStack has spacing 0. `SpaceManagementLayout.pageInset`
  keeps the screenshot's 4 points on the Spaces page only.
  group for the first report. Every open creates a new HomeViewController (the
  rebuilding the pager's pages and scrolling the pager to it, animated unless
  the transition kind is 2. While that spring runs, `setHomeWidth` (its only
  `isTrackingOrAnimatingSidebarPages` and only marks layout, so the next layout
  pass applies the Spaces width as the Library slides in. The group would run
  only for a report while the pager is idle: a non-animated page change (kind
  2, whose producer was not traced) or a report after the spring settles.
  Neither was observed, and that the first SwiftUI report lands inside the
  spring is [I]. Parc opens the Library with no pager motion, at the final
  loads the optional page value and passes it to `getContentWidth`
  matches: `LibraryView` keeps the width read at the page change, and the
  strip's horizontal scroller keeps the add item reachable. Choosing another
  page and returning reads the current count.

Checks: `tests/LibraryWidth/check.py` runs 31 assertions over the actual
LibraryView, `SpaceManagementLayout` and `SidebarChromeFrames`, with the
Library never in a window and activation prohibited. They cover 216 + 264 ×
count and the 4-point strip for one to six Spaces, the 480-point Library, the
window − 56 clamp, 417 on every other page, the strip's frame and the add
item's 28 points before the page, and a report for each page change. An added
Space, an unrelated reload and a deleted Space on the Spaces page keep the
page-change width (480) and report nothing, while the strip scrolls
horizontally to the add item; returning to Spaces reads the current count
(744), and choosing the shown page again reports nothing. Negative control
fails as expected: re-reporting the width on every Spaces reload fails the
added-Space assertion.
`tests/SidebarMotion/check.py` covers the frame rule (one, two and five Spaces,
the floor, the clamp, full screen and the extension panel at a wide Library's
edge), the group's 0.2-second duration and cubic, and a cancel that removes
the group's animations, keeps the settling layout and never completes. Its
source assertions cover the window's open, change, close, disposal and resize
wiring, the closed-window completion guard and the side panel in the geometry
pass.
`tests/LayoutChromeGeometrySkip` checks that a page-width change still runs
`layoutChrome`.

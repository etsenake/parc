# Saved tab reset and Today archive actions

Pinned tabs and Favorites retain `savedURL`/`savedTitle` independently of their live page. Ordinary navigation updates the live URL/title. Moving an existing saved item between Pinned and Favorites preserves that saved destination; pinning Today captures its current destination, and unpinning releases that anchor. Closing a saved tab retains the item and restores its saved destination after the original native close succeeds. Closing Today archives it with existing provenance.

## Production actions

- A navigated-away saved tab has **Reset Tab to Original URL** in its context menu and accessibility actions. A navigated-away pinned row also resets from its icon slot, and Command-clicking that slot separates its live page into a new Today tab. The Tabs menu exposes current-tab reset and **Reset all tabs in this Space**. Unavailable reset remains disabled in menus.
- Each prepared row/menu action captures weak references to the original native page and wrapper, the original model/profile/saved/current URLs, and a one-use flag. Transfer, replacement, close, navigation to a different URL, retirement, competing sheet, Space/profile change or an active child Peek refuses the stale action. The current menu command operates the focused split pane; it does not reset the page underneath an active Peek.
- Live reset calls the existing native `LoadURL` on that actual page. Chromium retains navigation, history and beforeunload authority. The model is not changed optimistically: the genuine URL callback commits the resulting destination. A refusal therefore preserves the page and saved anchor. Dormant reset only updates an unclaimed item; it never creates a background page. Authentication-flow unlock state clears through the existing genuine URL update, with no synthetic reset flag.
- Today exposes **Archive Tab**, **Archive Other Tabs**, **Archive Tabs Below**, and **Archive Tabs Above**. Menu groups capture the original row order and identity; changed ordering/profile/Space refuses an old group. The existing shared page-retirement coordinator validates the original IDs and all affected native pages, including child Peeks and other windows, before committing one model update. Any refused close preserves the group. Remaining selection follows the initiating window's existing adjacent-selection rule and does not overwrite an intervening selection.
- The File close command distinguishes **Archive Tab**, **Close Tab**, **Close Peek** and **Close Window**. Restore Last Closed Tab is enabled only when the current profile has an archived entry; it reuses the existing provenance-aware restore path, including complete original splits and compatible original Spaces.
- Hover controls disappear during row drag or removal and reconcile when rows rebuild beneath a stationary pointer. Equivalent accessibility actions remain available without pointer hover. Ordinary controls use the recovered press animation described below; Reduce Motion settles immediately and no additional haptic is introduced.

## Reference and limits






## Saved-home URL comparison

`BrowserTab.resetDestination` and the focused-Favorite split-copy title decision share `SavedTabURLComparison`. Reset is unavailable for equivalent home/current URLs; otherwise its result remains the **original saved URL**, including its original scheme, case, query and fragment. The comparison is not used for navigation, security, profile identity, transfers or request/session validation. Those owners continue comparing their exact original values. Exact Command-click Favorite reset remains a separate forced action.

The recovered full-URL predicate first compares actual Foundation URLs, then compares normalized Foundation URLs. Normalization lowercases the complete absolute string, supplies HTTPS for a missing or HTTP scheme, removes one `www.` host prefix, drops an ordinary fragment, and removes one final path slash when there is no hashbang. A `!`-prefixed fragment is retained, with one final slash removed from that fragment instead of the path. Empty-valued query items and `utm_` items are removed in original order; other parameters, order, duplicate items, ports and user information remain significant. An unchanged query array is not reassigned, preserving its encoded representation. URL/component conversion failure retains the original URL. The scheme-less repair helper preserves its original-path fallback behavior; production saved destinations still require an actual scheme.



## Reset all tabs in this Space

`SavedTabResetTargets` collects the active profile’s visible Favorites first, then the current Space’s mixed pinned hierarchy in sidebar order. Only expanded folders contribute descendants; a visible whole split contributes its original child order. Today roots, archived items, other-profile items, local documents and equivalent-home URLs do not become reset targets. A Favorite represented by a split follows that visible split rather than its hidden App Tray slot. Original identities are deduplicated defensively, with no selection, folder disclosure, destination or stored-order mutation.



## Favorite App Tray interaction owner


Every primary activation and Close action asks the originating `BrowserWindowController` for a one-use lease. The lease rechecks the exact saved record, active profile/Space, physical window, original wrapper/page, transfer/recovery/retirement, sheet and shutdown state before dispatch. Closing uses the existing asynchronous retirement/beforeunload transaction; the action's Boolean means dispatch was accepted, not that close consent succeeded. Reset continues through `prepareSavedTabReset` on the original native page. Context menus and accessibility actions are created on demand instead of caching page actions at tile construction. Control-click invokes the same context-menu provider. A removed tile cannot request a menu or activate an item.

The tile's pressed transform uses the recovered scale `0.99`, spring damping ratio `0.5` and response `0.2`, interpolating from the current presentation. Removal, hiding, disabling and window deactivation cancel the press. Reduce Motion suppresses animation and the button uses a native keyboard focus ring as explicit Parc accessibility adaptations. Existing Space palette, capture controls and recent-page preview eligibility remain with their original owners. No Favorite hover Close/Reset glyph is inferred from an ordinary tab row, and no haptic is added.



### Favorite tile presentation

`FavoriteGridLayout` reproduces the App Tray collection layout: 8-point insets
and gaps, at most four columns of at least 47 points, row-balanced, 47-point
rows on a 55-point pitch. `FavoriteTile` draws the recovered tile layers: a
selected-only shadow, the selected white background with its icon wash, one
page cell per original page, and the selection ring. Cells request icons
through `SidebarView.requestTabFavicon`, the same original-page / exact-profile
owner used by sidebar rows; a reply is ignored once the cell or tile is
replaced, and the previous icon stays until the reply so redraws do not
flicker. Split Favorites lay out their pages with `FavoriteChildLayouts`; a
container's own emoji or symbol replaces the page icons. Hover uses a
key-window tracking area and cross-fades only the cell fill (0.12 s ease-out)
and, when selected, the wash opacity. Selection changes are immediate.

listed in the [parity evidence](parity.md#favorite-tile-presentation--tab16).
embeds the values, not the catalog. Parc adaptations: a monogram when no
timing is assumed.

Overlays and dim. On each navigation update,
`BrowserWindowController.favoriteOverlayStates` builds a
`FavoriteTileOverlayState` for every single-page Favorite whose own page is
live in the window: a recording flag (camera, microphone or mirroring, from the
existing capture producer); the favicon of a live Peek opened from that page,
until its dismissal starts; whether Developer Mode is on for the page's host;
`mediaSessionStatus`, read only when the engine provides it).
`SidebarView.updateFavoriteOverlays` passes each tile its state, and
`FavoriteTileOverlays` compares it with the previous value, so repeated renders
never restart motion. Overlays are lazily created subviews that never take the
badge, music particles. The dot's core pulses. The badge springs in and out
(damping ratio 0.6, response 0.4) and swaps a new image instantly. The particle
emitter runs while the Favorite is eligible and Reduce Motion is off, and is
rebuilt on appearance changes. `FavoriteWindowActivity` dims a selected tile
while its window is neither key nor main. The ring shows the sidebar keyboard
developer-tab ring on a selected Developer Mode page. Tiles no longer carry
clickable capture buttons; Stop for a Favorite's captures is the tile menu's
“Camera, Microphone and Sharing…” item, shown while the page captures (the
them only behind a default-off remote flag. Adaptations: Parc's own globe glyph
for a Peek without a favicon, Parc-drawn note sprites, Peek `closePending` as
split Favorites.

### Favorite pointer phase and saved-home reset

Favorite primary/Shift clicks in the key window activate on first mouse down,
without a second release activation. Exact Command-click resets the original
saved home and selects that same item; repeated down events use reset eligibility
and do not open Rename. Control-click remains the original context provider.
Favorites remain separate from the ordinary outline's Command/Shift multi-set.

flags, click count and phase. The Command-only first-down branch calls the saved
multiSelectedItems/key-window witnesses and Option bit. Double-click
the same reset owner, separate from the ordinary inline editing-ID path. Fresh
REA records `ev_69ba05effa6257f31622165ea517c619f6fc93c67262102b70d3b36983d81daf`,
`ev_04db318ea9a7f01f9a3e06a6fde8fc09704990d87c38c5a5e365a493a3bb5a0d` and
`ev_42c37805997e7bb33b60970f492a6816bda01bb62091b1925947393f0601535b`
are corroborated by complete original-image metadata/assembly.

The native tile is retained by original ID during redraw and receives fresh
presentation/action factories. Pending release leases are one-shot and are
revoked by Space/incarnation replacement, detachment, drag, disable/hide or
window deactivation. Reset retains the original WebContents and beforeunload
navigation; a dormant metadata reset resolves the subsequent selection against
the same incarnation. Outside-release cancellation and strict invalidation are
Parc adaptations. Option release follows the separately traced route below.
No current populated Favorite appearance or inactive first-mouse policy is
inferred from the available empty App Tray reference.


### Favorite Option split and focused duplication

Exact Option on first release places the original Favorite immediately after the
focused pane. An already-visible different Favorite receives focus in its
existing pane. If the Favorite itself is focused, the operation creates a fresh
same-profile Today item from its actual materialized current URL, with its saved
URL as dormant fallback. Away from home it uses the live title without the saved
custom name; at home it preserves that presentation. It does not reset, close,
clone native history or mutate the original Favorite's saved destination.

The release event owns modifier classification. Non-low-four flags are ignored
here, unlike exact Command-down reset. Leases are prepared after synchronous
down selection, retain exact original window/Space/selection/focus/layout and
native wrapper/page/Profile/URL revision, and expire on owner or state changes.
The shared model transaction saves before publication, preserves original IDs
and surviving group geometry, and opens only the new copy through the existing
native page factory. Storage failure reports an error without exposing the copy.
Other Option combinations retain ordinary activation. Exact Option–Command is

TabDuplicationOptions `0x100`: copySavedURL=false, shouldOpen=true. The tab helper
`ev_4ead7a4ca4c19a72b50e4c6a9d81b56f0dd53aaadd8d3c27fa614541f745aa99`.

constructs the genuine LittleBrowserSession and WindowCreationOptions.Style
little0 before creating the window. REA:
`ev_d9390888d80710f57dac4219d6b0fc1e16f5ed96c093ff9fd0de2011b27d687e`.
No alternative normal-window activation is substituted for this excluded route.

Current-Space Today placement, split weight normalization and strict stale-input
refusal adapt Parc's model. The boundary fallbacks below replace the earlier
blanket refusal of empty selections and fifth panes. The existing press spring,
AX/context provider, keyboard outline and native text/IME retain their owners. No
additional hover glyph or haptic is inferred from this contract.

### App Tray selection and modifier corner cases

The App Tray has no multi-selection. Its collection view is single-select, and
its native selection callback forwards only pinned-extension clicks before
deselecting. Favorite presses reach the same `didSelectItem` reducer, which never
builds a set. Shift therefore selects like a plain click, exact Command resets
and selects, and Command–Shift selects. The ordinary outline multi-set reconciles
to outline rows (`SidebarItemSelection.reconcile`), so a Favorite never joins it.
Activating a Favorite clears that set through the existing sidebar owner.

`FavoritePointerPolicy` follows the reference phase predicate. A first click
selects on down only in the key window and without Option. Any other first click
is resolved by its release. In Parc that is only the Option click: every Favorite
lease requires the key window, so the tile's activation gate refuses a non-key
press before the policy sees it, and the policy's non-key branch is never reached.
Release drops
numeric-pad, Caps Lock, help and function flags. Exact Option opens in a split,
combination selects normally. A repeated down takes the double-click reset branch
whatever the key state or modifiers; the reset owner keeps its own window gate.
The tile does not accept first mouse, so the click that activates an inactive
window neither presses, selects nor starts a drag.

`FavoriteOptionRoute` decides each Option release from the window's selection
and focused pane:

- **Split:** below four panes, insert the Favorite after the focused pane. If it
  is already shown, focus its pane. If it is the focused pane, duplicate it. If
  another window displays it, move its page here first (below).
- **Present:** with no presentation or no focused pane, the Favorite is selected
  normally.
  toast ([toasts](toasts.md)).
- **Unchanged:** the focused Favorite at capacity stays focused and is not
  duplicated.

(`reparentWindowContent`, below). Parc does too, with no prompt, through the
existing window transfer ([the same tab in two windows](windows-lifecycle.md#the-same-tab-in-two-windows)):

- **Primary selection:** the moved Favorite is selected and joins the
  destination window's current Space (`WindowPresentation.adopt`), as an
  existing-page selection does, rather than the Space it was created in.
- **Option release:** the page moves in the background, then
  `prepareFavoriteSplit` inserts it after the focused pane. This requires the
  window's Space, panes and focus to be those of the release; otherwise the moved
  page is selected.
- **Split Favorite:** selecting a split Favorite, or a Favorite in a split, moves
  each page that another window holds in turn, one transfer at a time, then
  selects the whole split. A refused transfer ends the chain and leaves the
  pages already moved here.

The transfer carries an optional placement from `onRequestTabTransfer` through
`transferTab` to its resolution. The placement runs on the next main-queue turn
after the page is attached, because it may start the next transfer.

Only the focused pane's Favorite, or the split Favorite containing it, is the
a tile is selected when the render's focused page is its tab or, for a split
Favorite, one of its group's members.

outline multi-set: they are no longer outline rows. Parc matches. Dragging a row
outside the set clears the set first, and any hierarchy change clears it at the
next render, so a moved row never remains selected or makes a Favorite press
wait for release.

sends AppTrayAction case 0 `didClickExtension` and then `deselectAll:`. In the
click count is not 1. Otherwise it empties `multiSelectedItems` through witness
return the focused item and it must equal the clicked one before the duplicate

`ReparentingTrigger` distinguishes `targeted(itemSelected | itemMoved)` from
Each split child having its own reparented content is inferred from the
per-item key.



(`AppTrayItemWrapperView` → `FlippedView` → `NSView`) and the tile chain
(`AppTrayItemViewAppKit` → `HoverableView` → `TaggableView` → `NSView`) are not
among them. An inert AppKit probe returns false for `NSView` and `NSImageView`
but true for `NSButton`, so Parc's button-based tile overrides it.

Adaptations:

  other Parc toast ([toasts](toasts.md)).
- **Clearing the outline set:** Parc clears it only after the action succeeds.


## Ordinary row action ownership

Today and pinned row activation, Close/Archive, context menus and accessibility
commands resolve through one original-tab lease. Pointer activation captures the
lease on mouse down; native button tracking captures a close/reset lease before
tracking and consumes it on release. An original model, Space, split group,
wrapper/page or physical ownership change refuses the old command. Context and
accessibility queries prepare fresh actions; accessibility reports the actual
accepted/refused result. A close result means accepted dispatch to the existing
asynchronous consent owner, not completed page destruction. Private Today uses
Close without introducing archive persistence. Saved Close and saved-URL Reset
retain their existing distinct owners.

The keyboard sidebar cursor, whole-split identity and modifier selection remain
separate from webpage focus. Rows expose native row semantics and preserve both
current-page and explicit multi-selection selected state. Dynamic row actions
remain available through accessibility without requiring pointer hover. Control
click and the controls' secondary action use the original row context provider.
A row leaving its window, hiding, beginning a drag or losing key-window ownership
cancels its pending pointer action and clears control presentation.

reversal from the current presentation transform. Close draws the recovered two
14×2 rounded bars at ±π/4; it does not reuse App Tray tile motion. Focused REA
`ev_7199a94378d66f4480cde2b52296f60ed4df1d7f0dc11e506d29101f61f394c2`
is a bounded raw-function analysis supplemented by full-image assembly and
constant/import resolution. Installed 1.170's original Today row and Archive
context entries were inspected without executing an action. The available
above-divider item was an Easel, so it supplies no pinned-browser hover evidence.

Reset is no longer a trailing button. A resettable row's icon slot is its reset
target, `SidebarRowResetRegion` (see [Ordinary row presentation](#ordinary-row-presentation)).
On mouse down it captures a one-use lease from
`BrowserWindowController.prepareSavedTabIconReset`: the reset lease, or with
Command the separation lease, which shares Reset's checks. It consumes the
lease on a release inside, then selects the pinned item unless it is already
the original mouse-down to the row, so the row still moves. While no command is
current for the held modifiers (another window or a Peek holds the page, or a
sheet is open) the region takes no click, so the row keeps its own activation.
Keyboard and accessibility presses prepare a fresh reset lease. The native
keyboard focus ring and settled Reduce Motion behavior are adaptations. Full unread treatment is not claimed
recovered. No additional haptic or row-level key interception is added.

## Item keyboard and accessibility

Each Favorite tile and each Today/pinned row is one accessible button with a
keep the plain button description. A row speaks its visible title. A Favorite
speaks its page title; a split Favorite speaks its own name, or each page title
joined by ", " when it has none, and "Favorite item" if it has no title at all.
The title is no longer repeated as a description. The exact URL stays as help.
Selected means the current item, plus explicit multi-selection on rows.

The original activation lease, context menu, Close/Archive/Reset/Rename and move
actions are unchanged. Press reaches the same activation as a click and Show Menu
opens the same fresh context menu. A split container row and its page rows keep
their existing names and actions.

responder, and no sidebar cell, App Tray or tablist class handles key events.
The App Tray collection view is selectable, but a native selection only acts for
pinned extensions and is then cleared, so it never activates or keeps a Favorite
selected. The outline's own double action does nothing (`outlineViewDoubleAction:`
press ([tooltips](tooltips.md#tab-rows)). Keyboard access to items
therefore goes through the Control–Space sidebar session and the menu commands
(Close/Archive, Rename, Copy), which Parc already provides through the same
original-item owners. Parc adds no new item key bindings.

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`, read with
bounded `llvm-objdump` ranges and Mach-O metadata helpers (the shared Ghidra
corpus was still importing). Generated disassembly is evidence, not source.

  button, role description "Favorite", title = `accessibilityTitles` joined by
  ", " or the "Favorite item" placeholder. No press, value or custom actions.
  case 6) with its own title gives `[title]`; without one, each child's title
- `TabCellView` (a `SelectableCellView<TabCellState>`) AX extension category,
  title = visible title label, one custom action "press" that sends `mouseDown:`
  reads `TabCellState.isCurrentItem` (offset 41). `EaselCellView` category
  method list finds no `keyDown:`, `insertNewline:`, `deleteBackward:` or
  `performKeyEquivalent:` on sidebar, cell, tablist or App Tray classes;
  `performClick:` and menu events.
  extension only, then `deselectAll:`.

Adaptations: Parc uses the native press action instead of a custom action
named "press"; both reach the same activation. Tiles and rows also report
selected state and offer their existing named actions, menus and URL help, which
Keyboard Access, and the focused sidebar keeps its Up/Down/Delete multi-selection
keys; both are existing Parc adaptations. Note rows follow the Easel row
treatment. The sidebar-wide AX tree and focus order belong to the Sidebar
owner's SIDE17. The values were checked in-process only; the AX server view of

## Ordinary row image ownership

`SidebarTabRow` keeps its original title, actions, split identity and selection owner while `SidebarFaviconView` presents the real page artwork. A live row reads the exact original `PCNativePage.favicon` after model/profile/URL/retirement validation. The native page observes its Chromium favicon driver and publishes changes through an image-only callback on its existing original-page observer; each display reads the current last-committed NavigationEntry image. The facade refreshes presentation without emitting a URL/title callback or creating a history visit. Destruction removes the observer before releasing the original contents. OTR uses its actual page image without consulting a persistent parent profile.



### Ordinary row presentation

non-interactive view below the row content. It mirrors
`SidebarUI.CellSelectionStateView`, with the fill/shadow layer and the highlight
ring as siblings. `SidebarRowAppearance` holds:

- the fill order: current or key dragged → content visible → multi-selected →
  hovered → clear, and a split child's own background;
- 12-point continuous corners and the current item's one-point shadow;
- the 2-point maxContrastColor highlight ring and half-opacity dimming;
- geometry: 24-point icon slot, 16-point favicon, 36-point title, and a
  24-point Close 6 points inside the trailing edge;
- the reset-region, slash and hover-subtitle constants, and the split child
  layout.

`SidebarView` supplies the original current, multi-selection and selected-split
state, and maps its keyboard highlight to the ring. The row keeps hover, title,
actions and AX, and derives dimming from its window being neither key nor
until the drag ends. `SidebarView` keeps that item's ID, so a row rebuilt
during the drag keeps the fill.

current, as behind its command-bar new-tab placeholder. Parc has no such state,
so no row uses it. Reusing AppItem's key/main rule for the row's `shouldDim`,
and the split cell's key-dragged producer for rows, are inferences. Fills
neutral GrayA4/GrayA5 control fills.


- `SidebarRowResetRegion` covers the icon slot up to the slash.
  `SidebarRowBodyRegionView` covers the rest of the row while the row has no
  fill or ring. Each region has its own hover and pressed fill, and the row
  itself gets no hover fill.
- The 4 × 15 TabCellSlash slash fades out while a region is hovered.
- The title starts at 38 points.
- The icon region's tooltip is "Reset Tab" with the bound reset shortcut.
- Hovering the icon fades in "Back to Pinned URL" below the title, in the
  11-point system font and the theme's title color at half alpha, and lifts
  the title stack 7 points over 0.1 seconds. Meanwhile the icon shows the
  saved destination's cached icon. With Command held the subtitle reads
  "Separate From Pinned Tab" and the page icon stays.
- `BrowserWindowController.requestSidebarSavedFavicon` reads that icon from
  the exact profile's existing native favicon service. It applies the same
  original-item guards as the page icon, and never reads a private window's
  parent history.

Separate From Pinned Tab moves the live page out of the pinned item.
`BrowserStore.separateFromPinnedTab` adds a Today tab with the page's URL and
title at the top of Today, through `placingCreatedTab(.top)`, and returns the
pinned record to its saved URL and title in the same publication. The pinned
item keeps its ID, position, folder and custom title.
`BrowserWindowController.separateFromPinnedTab` then moves the page's wrapper,
pane, claim and per-page state to the new tab, as Peek promotion moves a Peek
into one, and renders. The new tab stays in the background, and "New Tab
does; clicking it selects the tab ([toasts](toasts.md)). When the pinned item
is next presented it opens its saved destination in a new page. A resettable
window content. Reset's existing lease still refuses while a Peek, another

`SidebarRowAppearance.splitChildLayout`. They have no reset target, slash or
subtitle, and leave selection, hover and the ring to their split. Each child of
the selected split shows TabCellChildBackground in a 28-point cell centered in
the row. The icon slot sits 2 points in, the 14-point title 6 points after it,
and Close 2 points inside the trailing edge. Close shows while the split is
hovered (the row tracks its container) and only when it clears the icon. Parc's

Addresses, adaptations and catalog hashes are in
[the TAB19 ledger entry](parity.md#ordinary-row-presentation--tab19).

## Sidebar title and inline Rename

Ordinary rows resolve a manual `customTitle` before the nonempty saved title and
then the source-owned saved URL. The page's live `title` remains independent.
Today's existing metadata path updates its saved source; pinned/Favorite anchors
retain their separate lifetime. An empty Rename removes the manual override.
Old sessions decode with no override. Reclassification and original-item moves
retain that field; renaming does not navigate, reset, change page history or
replace an original tab ID.

The ordinary-row **Rename…** context entry and **Rename Tab** accessibility action
start one native field editor in the original row. Its displayed label is
selected in full, its icon remains, and trailing row controls are hidden during
editing. Caret movement, composition, selection and text Undo remain AppKit's.
Return or ordinary focus loss completes the edit; Escape, row removal and window
loss cancel it. Marked text retains native Return handling. The edit captures the
original Space/profile/group/wrapper/page; a replacement or stale ownership
refuses completion. The session write is atomic and precedes model publication;
private stores retain the name only in memory. A failed write presents its actual
error. An unchanged edit does not create a manual override.

Parc defers rebuilding that original row while it owns the native editor and
reads the latest state when editing ends. AppKit sends its end-edit notification
before removal callbacks; ordinary focus-loss completion therefore waits one main
queue turn with an editor-generation/window guard so removal can cancel first.
Return completion stays immediate. These are explicit adaptations to Parc's
rebuild-based sidebar, along with its existing row geometry/native colors and
absolute-URL fallback formatting.

renaming; the user approved them on October 26 and sidebar previews use them
with Parc-authored rules. Whether ordinary row titles should also use them is a
separate Today/pinned decision.
`ev_0e6b5d516cfe6bbd528b5bcdf4fd0d0243873e56bd11bed826d5a7609ca8e41c`
is bounded raw-function analysis supplemented by full-image metadata/imports.
select-all editor; Escape restored the original label without a content change.
Favorite/whole-split renaming and regional hover-title/subtitle/shortcut
presentation are distinct owners from this ordinary-row editor. No haptic or
unread policy is inferred from title metadata.


## Global Rename ownership

**Rename Current Tab…** is an attached, hidden native-menu command exposed by
command search and the existing customizable-shortcut registry. It has no default
key. Dispatch resolves the originating window's current ordinary sidebar item or whole split container,
not the shared store's last selection, the hovered row, or keyboard highlight.
A split container is not replaced with its focused child. Local document naming,
Favorite editing retains its separate, unestablished owner. Whole splits use the
container editor described below.

The command dismisses its original command panel, revalidates the real window,
profile, item and native presentation gate, expands original ancestors through
the existing disclosure transaction, and exposes the row for the same inline
editor used by its context menu. No page is selected, loaded or recreated.
Closing/transfer/removal, changed selection, replaced native page and stale edit
identities retain the original refusal/cancellation path. Private tab names stay
in their memory-only store. Native editing/IME and website shortcut priority
continue through their existing owners.

that dictionary to offset `0x68`; no keyboard-highlight or focused-child lookup
is substituted. Fresh REA evidence
`ev_2a518d7e6e6e3f75d92adcdee5a3eba7534013d1e5b4360836753574075c4d6c`
shows Rename Current Tab… in command search; the inspected Tabs/Edit menus omit
a visible Rename row. Parc's hidden menu registration and pre-edit disclosure
are explicit adaptations to its registry and rebuild-based sidebar. The generic
item ID route alone does not establish Favorite/whole-split editor rules.


## Split-container Rename ownership

The whole split has an optional custom title independent of every child's saved,
custom and live page title. Global Rename resolves the originating window's
original selected group with its ordered children; it never substitutes the
focused pane. The container context and **Rename Split View** accessibility
action enter that same native editor. It selects the current container name,
retains the child-count label and uses the recovered **Title** placeholder.
Return or ordinary native focus loss completes once; empty text clears the name.
Escape, owner removal, changed selection/membership/placement/profile or replaced
page/editor cancels or refuses completion. Native IME, caret movement, selection
and text Undo retain AppKit ownership.

The saved name selects the custom-info row in place of compact child rows.
Clearing it restores the child-items presentation. Activation still uses an
original child's existing page-selection lease; original child actions remain
available through named-group context submenus, and real active-capture controls
retain their native session owner. Hidden child fields are not offered as rename
targets. The edit captures the original group, children, Space/profile, wrappers,
native pages and any Note/Easel editors. Atomic model publication changes only
the container title; regular stores persist it and private stores keep it in
memory. Remembered window geometry cannot overwrite a newer shared name.

`ev_32582de2467abbddc0fb8d13c8d922b266f0d20c9b01f6c952705312a485c026`
is supplemented by original full-image metadata/assembly. Layout consumer
adding a header. The installed 1.170 sidebar had no existing applicable split,
so its named-editor appearance was not observed or manufactured.

Parc's title-present/editing layout condition, native typography/count-label
geometry, child-action submenus and rebuild deferral are explicit adaptations.
The complete custom-info producer's custom-icon/hover conditions, exact named-row
hover controls/subtitle/keycap/motion are separate contracts; Favorite context Rename uses the distinct dialog described below. No haptic or unread
policy is inferred from these title fields.


## Container-name Undo and Redo

A completed split-name edit registers **Rename Item** on the originating browser
window's existing typed Undo stack. It shares chronology with ordinary close
operations; it does not register the same action in every window observing the
shared store. Native Edit-menu and Cmd–Z/Shift–Cmd–Z routing retain the actual
renderer editable/IME/security checks. The active title field, Notes/Easels and
other native editors keep their own text Undo managers.

Undo and Redo resolve the original container ID and profile, then atomically
replace only its optional name. Current geometry, ordered children, live pages,
saved destinations and selection are not restored from an old snapshot. A
same-profile Space move retains that container identity. Normal stores save
before publishing; actual OTR stores keep both the name and history in memory.
A no-op or cancelled edit does not register or discard Redo. Failed writes leave
the name and stack position retryable; native retirement, modal/security and
original-window transfer interruptions suspend availability. Window closure
clears its stack. A missing/replaced container, changed profile or conflicting
shared name invalidates the operation instead of renaming a focused child.

item ID, constructs `WindowAction.UndoAction.undoUpdateItemTitle` (case 4), and
registers localized **Rename Item** through `WindowData` witness `+0x660`.
(`WindowState+Undo.swift`): it resolves the manager with that original WindowID.
`ev_9647c0ed7f42b68ab40954d9b23601184bd9ba17e2b27cf7d948a6caba31c9e0`
is paired with the original full-image metadata and annotated call paths.

(**Undo Archive Tab**) and Redo; no Rename/Undo action was executed. The exact
modern Rename menu state and conflict/deletion/private-window behavior were not
observed. Parc's shared-name afterimage validation, current-profile availability
focus/effect choreography and invalidation policy remain untraced; this delivery
changes the name without requesting a new page selection, animation or haptic.


## Ordinary-tab name Undo and Redo

A changed manual Today or pinned-tab name enters the same original-window
**Rename Item** chronology as container names and close actions. The committed
record contains the original tab ID, profile and before/after optional custom
title. It never snapshots the page, saved destination, folder, Space, split or
selection. Undo/Redo resolves that original item and atomically changes only its
custom title, so live metadata and same-profile moves or pin/Favorite membership
changes survive. A prior name inverse can follow an item into Favorites; this
does not itself choose a Favorite editor or alter membership; the distinct context dialog is described below.

A no-op or cancelled edit leaves Redo intact. Another shared name, archive,
deletion or changed profile rejects the stale inverse. Pending native retirement
and the original window/profile context suspend availability; cancellation
restores it. A failed write leaves the title and stack retryable. Shared model
observers see the committed name while other windows keep their own Undo
chronology. The adapter weakly owns the store, and real private stores keep both
name and history in memory. Native field/editor Undo and the existing renderer
editing/IME/security arbitration are unchanged.

reaches the same original-item title updater, WindowID-owned Undo registration
and inverse reducer described above. Fresh bounded REA evidence is
`ev_4580370308cfa2814f80d4fbb224dd5d59ec2b1e95d56c59b4ef635fab6d107e`.
selection and Escape cancellation; its Edit menu has dynamic action naming.
current-name/profile checks and title-only inverse are explicit local ownership
adaptations, without a new selection, animation or haptic.

## Favorite Rename dialog

Favorite context **Rename…** uses a separate dialog, not the ordinary sidebar
inline field. The original Favorite is selected through its existing page owner;
**Rename Tab…** presents its display title and **Keep it short and sweet!**
placeholder with Rename / Cancel. The single-line native editor owns text,
selection, composition and local Undo. Empty input cannot confirm; confirmation
preserves the supplied literal name. Cancel does not write, and focus loss alone
does not commit. The model saves only the original custom title atomically and
registers **Rename Item** on that window's existing Undo stack. No-op retains
Redo; failed storage keeps the draft for explicit retry.

The dialog captures original tab/profile/Space and page/local-editor identity.
A changed name/membership, profile retirement, native closure/transfer, changed
selection or replaced owner refuses the commit. Other normal windows receive the
same shared name; original saved/current URLs, page and Favorite membership stay
with their existing owners. Accessibility exposes the same owned Rename action.
The global Rename command retains its separately recovered ordinary/container
route; it does not implicitly substitute this Favorite dialog.

SidebarContextMenuItemAction12 `renameFavorite`, versus ordinary case9. Reducer
Fresh bounded REA evidence is
`ev_5513d611767e04b87e098d7d5d2ab798d4095f9723f2dade709045ccc2849cb9`
and `ev_6c50e7bfd1ab6fed423d3b17f53acd7d416da3ea4b1c7edce208834a54e4f936`.

sheet styling/width, initial select-all, Return/Escape/IME policy, AX equivalence
and stale-owner cancellation are explicit Parc adaptations. Literal whitespace
handling and detailed dialog focus/motion/haptics are not claimed as recovered.


### Favorite Rename in command search

Type Travel's **Rename Current Tab…** has a separate owner from the global menu's
inline editing command. Its immutable action captures the originating window's
current Favorite, Space and Profile, independently of sidebar highlight or
multi-selection. The result revalidates that same original item, native binding,
page and local editor before dismissal and dialog entry. Live page metadata may
advance; a competing manual name, membership, saved anchor, incarnation,
selection, profile retirement or owner replacement expires the action.

Dispatch opens the existing Favorite dialog without the context action's
activation step. Required literal text, explicit Rename/Cancel, storage failure
retry, native composition/caret/local Undo and shared original-window Rename Item
Undo all remain with their established owners. No page is recreated or navigated.
The identical-looking ordinary menu alias is omitted from this Favorite result
set only; the registered menu command and its custom shortcut stay unchanged.

`0xcb` admits tab/list/easel/split/sharedObject, with no topApp membership test.
established by this evidence. Fresh REA
`ev_d1ee8ab1850d1775fd1351cab67af69ea045779cd77a832d62675920e8b31251`
corroborates the original-item helper; full-image metadata supplies external
attribution. Arc1.170's nonexecuting query shows the title and insert-text icon,
but the inspected sidebar has no Favorite. The native result symbol, word ranking
and stale-owner conflict policy are deliberate Parc adaptations.

## Unread state and badge ownership

returns no badge for read items. Its unread result is the `mobile` case except
when `SidebarSpaceState.gitHubLiveFoldersEnabled` and the actual ancestor query
find an automatic live folder; that branch returns `dot`. Predicate
`automaticLiveFolderData`. The retained 6-point dot geometry is therefore not
evidence for a generic ordinary-background-tab badge. Dedicated live service
integrations remain excluded.

The generic tab constructor accepts an unread argument; false initialization
in other container constructors does not establish the ordinary tab producer.

**Producer search (October 26, SIDE15).** All 46 call sites of the item
the local `Dependency<MachineID>` as originating device
(`ev_339313994d5c219ef9dbb1f7b5267af16851fdf06fbef34ce6a521c588f15e4d`,
`ev_7fd80f159afd45b3e86ed4706481550b7cc6ef8ee59c414f4b907285c8bd9276`). They
cover new tabs, duplicates, split children, reopen, modal content, folders,
documents and default sidebars; the `WindowState+InstantLinks` site belongs to
remaining unread-taking constructors have no references. Only two paths yield
argument is `!PullRequest.createdByMe` for GitHub items and constant `false` on
(`SidebarItemUnreadBadgeView`, created lazily in `TabCellView`) is 24 × 24 after
the title, shows the `SidebarMobileIcon`/`SidebarMobileIconFill` template pair
for `mobile` or a centred 6-point dot for `dot`, has no motion or accessibility
therefore never shows an unread badge for a locally created item: the badge

Parc's existing local background/copy `isUnread` flag protects unseen items
from automatic archiving and is persisted until existing selection owners clear
it. It is an explicit independent policy kept under the user's October 25
(`AppTrayBadgingProvider`, driven by title, URL and badging-disabled hosts), not
subtitle from `Inputs.keyboardShortcutToShow` (`+0x28`), computed only when the
remote flag `show-top-app-shortcuts-when-holding-cmd` is on (default false), and
`Previews.PreviewData` (`UnreadEmail`, `GoogleCalendarPreviewData`,
`CalendarEvent`, `PreviewMetadata`), which feeds the Twitter, Gmail and WhatsApp
count dots and calendar subtitles of the excluded live providers. The AppItem
dim, Peek badge icon, titles, children, orientation) carry no unread value.
included scope; this closes TAB18. REA dossiers `ev_ff946fa77fd244dc050ff020bd67542f481f5f44c0efdc41e28157c5c770fd2d`
and `ev_b7d1eb7cc4936e6ab5584dc86943c6363cb9bdece7843d243bafc8c242bb5a57`
are bounded by original full-image metadata and assembly.

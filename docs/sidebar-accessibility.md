# Sidebar accessibility and focus

This inventory covers the sidebar's own interactive elements and states:
toolbar, address region, item list, bottom bar, container states, the resize
strip and keyboard focus. Favorites tiles, row visual states, Split View,
Downloads and Onboarding keep their owners and are listed only where the
sidebar exposes them. `SidebarAccessibility` holds the recovered strings and
Space semantics that `SidebarView` applies; `SidebarOutline` gives the item list
that is not presented; `WindowKeyViewLoop` links the window's page side to the
sidebar's Tab chain. The last section is the runtime acceptance that closes
SIDE17.

## Reference

(SHA256 `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`);
addresses belong only to it. Appearance evidence is a read-only capture of the
the resize strip; traffic lights as `AXCloseButton`/`AXMinimizeButton`/
`AXFullScreenButton`; 32-point toolbar buttons labelled "Hide sidebar", "Go
back", "Go forward" and "Reload this page", each an unlabelled container plus a
labelled button; an `AXOutline` printed as `sidebarAllTabList` of
`AXRow`/`AXOutlineRow` + `AXCell` rows whose first row, the pinned header, is
listed collapsed with an Expand action. The string is the outline's
`AXIdentifier` in both 1.122 and 1.170 (outline identifier below) [D]; the
capture prints other identifiers as `ID:` fields beside a title or
description, so it shows this one, on an element with neither, as the name
[I]. Its frames are screenshot pixels at the capture's 0.9905 scale:
the outline at 0,86 226 × 687 (≈ 0,87 228 × 694 points), 41-pixel rows
(≈ 41.4 points) with separator rows 3 and 25 pixels (≈ 3.0 and 25.2 points),
and item cells holding a 226 × 40-pixel (≈ 228 × 40.4-point) `AXButton` titled
with the page, an `AXImage` and an `AXStaticText`. Parc's 41-, 3- and 25-point
rows match within that rounding; a
"Home" button at the bottom left; and dock items such as `Space Space 1`
(`SidebarDockItem-Space 1`) and, while a Space is created, `Space Create Space`
(`SidebarDockItem-Create Space`). Recovered pseudocode is evidence, not
original source.

Each fact below carries its basis:

- **[D]** bounded disassembly (`llvm-objdump -d` with start/stop addresses),
  with ObjC method lists, ivar names, selector refs, GOT entries and Swift
  small-string immediates resolved from the Mach-O tables;
- **[R]** a REA/Ghidra 12.1.4 raw-slice decompile that agrees with that
  disassembly (evidence ID given);
- **[O]** the 1.170 AX observation;
- **[C]** an inert AppKit component check in Parc's own process on this
  machine (off-screen windows, never key, no browser; AppKit behaviour, not
- **[I]** an inference, not a recovered fact.

An evidence ID cited for a fact whose decompile failed or was wrong is only a
run reference; that fact rests on the disassembly named beside it.

### Recovered facts

  `sidebarToggleButton`, `goBackButton`, `goForwardButton`, `reloadButton`,
  `reloadOptionsButton`, `forceReloadButton`, `thinReloadButton` and
  `NSButton`). The reload-options button is a separate symbol-image control
- **Toolbar labels [D].** `NSLocalizedString` globals, decoded from Swift
  comment "A button which will hide the sidebar when pressed"), **Lock
  the binary.
  `ev_b429ca4f36ebbee3d0878c27ade43a7494fcbd40e24f623446cba8bee92b2d0e`),
  `ev_9b9e3c9ae40667aad36aa632274919e958d06f74fb080e993646fdca35087f0c`)/
  (`ev_e40262c71d20a9ac1f0af96646c1679a743d1086847423df916780590eeb9cdf`)
  labels the hosted SwiftUI root view, leaving the container unlabelled,
  unless `sendActionOnMouseDown` is set, when it labels `super`. That matches
  the 1.170 "unlabelled container + labelled button" pairs [O].
  (`ev_ac38987fcbf409892fff4da86bd383dd2b4a26f74ae65df9074548649e78cfd7`)
  picks **Hide sidebar** when its Boolean input is set and **Lock sidebar**
  otherwise, passes that text with shortcut arguments to a presentation
  (`ev_e5222b560356ddac9bf2060453bfc775e87dc03a0369f995a4ca13d5f1e31809`)
  passes the back/forward/reload labels and shortcut getters to the same
  configuration.
- **TranslucentButton accessibility [D].** It overrides only
  [R], which runs the hosted action). It overrides neither
  `acceptsFirstResponder` nor any focus-ring method.
- **Space buttons.** `SidebarDock.SidebarDockItemView`'s chained-fixup
  superclass is `NSControl` [D]; it has no focus-ring methods [D].
    (run reference
    `ev_fba6c091eb09e09900d9a224c4e3cb05331fad3d9af0286393b7ddfe11080ffa`).
    a tail call of the `objc_retainAutoreleaseReturnValue` stub. The decompile
    (`ev_a98c0e64988395b01dffdceb31b196f137124f4ca66e2d033723e1bfaeaefa59`,
    reproduced by review) is only `halt_baddata`, so it is a run reference.
  - `accessibilityRoleDescription` is `NSLocalizedString("Space")`
    (`ev_5c148e74e1b1dc51f76684360cadf3171ecbb68620beacbce9308dba240e3685`)
    is truncated but shows "Space".
    (`cmp x20,#0`) it substitutes the immediate **Untitled Space**; it then
    grows a string to 18, starts from the literal `SidebarDockItem-`
    and then `setAccessibilityTitle:` with the title. The Ghidra pseudocode
    (`ev_e47aecbe5622e820f6339ba00a2e81cba70ea17c006104fd3479f8ae0fa3f857`)
    misorders the identifier construction (a bare literal, append before it),
    so it is a run reference only.
    Space context menu for the item's Space, or nil while a Space is created
    [D] ([Dock Space menu](sidebar-resize.md#dock-space-menu)); the class has
    no `accessibilityPerformShowMenu` of its own [D], so its Show Menu is
    AppKit's for that menu [I].
- **Sidebar Space menu.** `SidebarView`, `SidebarViewController`'s root view,
  for a right-click that reaches it, such as on the list's empty area, and
  has no accessibility override [D]
  ([Sidebar Space menu](sidebar-resize.md#sidebar-space-menu)); as a plain
  `NSView` it is no accessibility element, so that menu has no Show Menu
  action [C]. Parc's `SidebarView` is the same (`SidebarSpaceMenuSurface`):
  the outline, its rows and cells keep their roles and actions unchanged,
  and VoiceOver reaches the menu's items through the Space header's custom
  actions and the dock items' Show Menu.
  `bezierPathWithRoundedRect:xRadius:yRadius:` over its bounds with its
  [R]: `ev_417cdc9006d894d638be6c4cc60f8a426dc19e6f245eb7f94984ee30a9656912`
  matches the disassembly (a review rerun ended in REA execution_failure).
  evidence.
  `TaggableView` → `NSView`) implements only init, layout, layer and
  `cursorUpdate:` methods. No class in its chain overrides an accessibility
  method.
- **Tablist outline [D].** Classes whose superclass is a generic Swift class
  (`TablistOutlineView`, `SplitViewCellView`, `TabCellView`) are instantiated at
  run time and absent from the 1953-entry class list; their `class_ro`
  `__objc_data` like that of every listed Swift class, such as `TablistView`
    `So13NSOutlineViewC`), so it is an `NSOutlineView`. Its method list
    super's frame by a constant), `shouldCollapseAutoExpandedItemsForDeposited:`,
    so AppKit draws no disclosure triangle), `setFrameSize:`, five drag methods,
    `_dropHighlightColor`, the initializers and `.cxx_destruct`.
    (`NSTableRowView`) with no accessibility override.
  - Across every method list a scan of `__objc_methlist` and the data sections
    parses (1811 relative, 40 absolute), the only accessibility implementations
    are the `TabCellView` category
    `TranslucentButton`, the menu item view, the Easel canvas, `BrowserApp` and
    `AccessibilityObserver`. None belongs to the outline, its rows or the folder,
    split and section cells.
    AppKit's `NSEvent`) and returns YES. Neither tests the window, the
    sidebar's presentation or the cell's visibility, so an off-screen hidden
    [R] (`ev_28ed3a47f15ba4d6b05542059f04d194a8a3cc54b012c2f9c5376eb6e00b23dd`,
    `ev_e380c87a7ed11a86c2fc1c073c812d3fc527b33449e6b78d5e89278808fda373`).
    What the cell's `mouseDown:` does with that empty event was not traced.
  - Folder cell: `ListHeaderCellView` (`HoverableView`) holds `_iconView:
    title fields. The delegate implements `outlineView:shouldExpandItem:`
  - Split cell: `SplitViewCellView` (`SelectableCellView<SplitViewCellState>`)
    holds an optional `childContainerView` (`SplitViewCellChildrenContainerView`,
    whose `childItemViews` map each child item to a `SplitViewCellChildItemView`)
    and an optional `customInfoView`. `SplitViewCellState.LayoutStyle`
    `customInfo`. A split is therefore one outline row whose cell holds its
    children, or only its custom title and icon.
  - Section cells: `UnpinnedSectionDividerCellView` holds the `tidyButton`,
    `clearButton`, `downArrowImage`, `borderView` and `squiggleView`, so Clear sits
    in the divider row; `UnpinnedSectionHeaderCellView` holds a `contentView`.
  [R] `ev_7e59ba67c335bcfdb5dde8cd14c14a409fb64a9a3f545ee86ce02f1bc0a9c617`)
  creates the controller, takes its `TablistView`'s lazy `outlineView`
  `ev_c769a2d3eeb52ee2dacefb44490b3d5cd8abd80a00ceff7818d20d44f35116d9`, a
  and the suffix when one is given and sends `setAccessibilityIdentifier:`
  (`ev_5ca4ef3166f23c3b83f323fba23729a3ad484c311d9e63fae1196b40e64be216`) is
  truncated before the send, so it is a run reference. An `adrp`/`add` scan of
  all of `__text` finds no other reference to the literal. Installed 1.170
  calls that switch, sends `setAccessibilityIdentifier:` through the selector
  identifier reports it as its accessibility identifier, with no title or label
  [C], so AX clients read it as `AXIdentifier`, not `AXTitle` or `AXDescription`
  (`setAccessibilityLabel:` would be `AXDescription`).
- **Pinned header disclosure.** `TablistOutlineView`'s superclass is
  `DiffableDataSourceOutlineView<BaseModels.TablistItem>` (its mangled superclass
  `ev_e768257dd3b6f47daf8e7416eb257d3a6bd24e30e99f5c8f4cbe64774d7988d5`) finds the
  slot 3 (YES for an item it cannot find). `TablistItem` is
  `sidebarItem(id:type:)` or `accessory(TablistAccessoryViewType)`; its witness
  YES for `type` `.list` and for `accessory(.pinnedTabsHeader)` (raw 0), NO
  otherwise [D]: the witness reads the tag byte at offset 16, whose sign bit
  marks the accessory case, then compares the accessory's raw value with 0 or
  the item type with 1, and the enums' field descriptors give
  `TablistAccessoryViewType` = `pinnedTabsHeader`, `pinnedTabsFooter`,
  `unpinnedTabsHeader`, `newTabButton`, `exploreSectionDivider` and the item
  type = `tab`, `list`, … in that order [D]. The witness is slot 3 of the
  `ev_06c894c5908e2dd5f9daabea4c335f09f9e0f790c2a24d7018650d2145b09875`) returns
  YES at once when bit 0 of the cast item's tag byte is set (`tbnz` at
  `outlineViewItemDidExpand:` and
  `outlineView:shouldCollapseItem:` [D]. The header is therefore an expandable
  outline item. The 1.170 tree lists it collapsed while its pinned tab is a
  visible sibling row [O], so the pinned items are not its children and it has
  none [I]. AppKit's outline asks the delegate when such an item's
- **AppKit outline semantics [C].** A stock view-based `NSOutlineView` in an
  cell frame), exposes: `AXScrollArea` → `AXOutline`, whose children are the
  rows and then one `AXColumn` (`AXIndex` 0, `AXRows`); each row is an `AXRow` /
  `AXOutlineRow` spanning the outline with `AXIndex`, `AXDisclosing`,
  `AXDisclosureLevel`, `AXDisclosedRows` (direct children), `AXDisclosedByRow` and
  `AXSelected` (`AXSelected` reports settable on every row, `AXDisclosing` only on
  expandable rows) and no actions; its only child is an `AXCell` with
  `AXRowIndexRange`, `AXColumnIndexRange` and `AXSelected` around the cell view;
  `AXSelectedRows` follows `selectedRowIndexes` and reports settable. Expanding or
  collapsing a folder, by `expandItem:`/`collapseItem:` or the row's
  `AXDisclosing`, keeps the selected rows; a collapse drops only the rows it
  hides. No disclosure triangle is added. An expandable item with no children,
  read and set through the attribute methods remote clients reach
  (`accessibilityAttributeValue:`, `accessibilityIsAttributeSettable:`,
  `accessibilitySetValue:forAttribute:`), lists `AXDisclosing` false and settable
  with no disclosed rows, while a plain item's is not settable; setting it asks
  `outlineView:shouldExpandItem:` and leaves the item collapsed with no rows
  added (`expandItem:` itself would expand it). In-process, the legacy
  `accessibilityAttributeValue` reads `AXUnknown` as the role of a custom `NSView`
  element, whether the role is set (`setAccessibilityRole`) or overridden, while
  stock AppKit table elements read correctly, so Parc's checks read the protocol
  methods; what a remote client such as VoiceOver reads from Parc's custom
  elements is part of the runtime acceptance below.
  `canBecomeKeyView`, `nextKeyView`/`setNextKeyView:`, `previousKeyView`,
  `recalculateKeyViewLoop`, `setAutorecalculatesKeyViewLoop:`,
  `refusesFirstResponder`/`setRefusesFirstResponder:`, `accessibilityHidden`/
  or category overrides or calls these AppKit selectors. It does hold
  with `setMessageText:`, `setInformativeText:`, `addButtonWithTitle:`,
  `setAccessoryView:` and `beginSheetModalForWindow:completionHandler:`; the field is
  to the next key view. None of these sets a key-view loop on the browser window.
  `drawFocusRingMask`/`focusRingMaskBounds`
  are implemented only by `HoverableButton` among the realized classes. None of the
  (`0x1002ad…`–`0x1002f6…`, `0x1003ae…`–`0x1003b8…`), `HoverableButton`
  `SidebarDock` (`0x102408…`–`0x102425…`) code. `acceptsFirstResponder` is
  `ev_5af178efedd36b387a8a6d275d8074e150e7fd7f29a6d134dbf0d56cf2334557`),
  `FindInPageView`, a private `TextFieldContainer`, the window content view and
  non-sidebar views, never by `TaggableView`, `TranslucentButton`, `HoverableView`,
  `HoverableButton`, `SidebarDockItemView`, `DragEventCollectionView`,
  `SidebarView`, `SidebarHeaderView` or `CommandBarPlaceholderView`. Installed
  1.170's main executable has neither `setNextKeyView:`/`nextKeyView` nor
  `recalculateKeyViewLoop` in its strings either (only `selectNextKeyView:` and
  `69276adaca785a46f2554e7fd18926e7fcdd6aba44ba64400a337427817db3dd`) holds
  both, each loaded from its selref once in `__text` [D]: `setNextKeyView:`
  (selref `0xe28ea08`) at `0x3051518`, sent to the receiver of the
  `addSubview:positioned:relativeTo:` just before it (`0x30514f4`, below its
  other subviews, relative to nil) with the view it added, a container linking
  to the view it has just put under the others, the shape of Chromium's link
  from a page's contents view to its renderer [I]; `recalculateKeyViewLoop`
  (selref `0xe2926a8`) at `0x96065a0`, sent to an `alert`'s `window` after
  `setAccessoryView:` and `setInitialFirstResponder:` (`0x96063c4`) and before
  `beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:`, a page
  `selectNextKeyView:` sender (its stub `0xc4aab40` is called only at
  `0x6839a30`) is `0x6839a00`, which sends `selectNextKeyView:`, or for a
  nonzero second argument `selectPreviousKeyView:` (stub `0xc4aab20`), to its
  view's `window` with that view: Chromium's `TakeFocus(reverse)` hand-off [I],
  delegate handles `TakeFocus` before that view was not traced.
  module: `MediaControlsHostingView` (class, `NSView`; ObjC methods only
  `initWithCoder:`, `updateLayer`, `initWithFrame:` and `.cxx_destruct`; ivars
  `store`, `heightConstraint`, `contentView`) hosts the SwiftUI structs
  holds the hosting view's methods and `MiniPlayerView`'s metadata reference at
  `focusEffectDisabled(_:)` stub. The hosting view, which holds the whole
  `MiniPlayerView`, whose keyboard behaviour was not recovered: SwiftUI's
  `focusable(_:)` and `focusEffectDisabled(_:)` are both called from the
  below), so a shared modifier could make the player's controls take or refuse
  focus [I either way]. Parc's player stops are the media owner's (row and mini
  player contract below).
  `onClick` field each), so the card's plus and gear take SwiftUI's focus
  effect [I].
- **Pane top bar [D].** The content toolbar is `TopBarPanelContainerView` (ivars
  `store`, `viewStore`, `viewModel`, `subscriptions`, `backButtonView`,
  `forwardButtonView`, `hoverTracker`, `hostingController`, `popover`,
  `barHoverRegionID`) hosting the SwiftUI `TopBarPanelView`, whose buttons use
  the SwiftUI `TopBarButtonStyle` (`buttonType`, view model, colour scheme,
  enabled, hovered) over `TopBarButtonType` (`image`, `systemImage`, `copyLink`,
  `siteControlCenter`, `slug`, `sidebar`, `back`, `forward`, `reload`,
  `insecureLock`). Its Back, Forward and Reload are therefore SwiftUI buttons
  too [I for their focus effect].
- **Header structure [D].** Swift field descriptors: `SidebarHeaderView`
  `commandBarPlaceholderView` and a stack view. `CommandBarPlaceholderView`
  CommandBarIconView`, the text view, `statusButton:
  CommandBarPlaceholderStatusButton` and `hoverButtonsContainer:
  CommandBarPlaceholderButtonsView`, whose `buttons` map
  `CommandBarPlaceholderButtonID` (a pinned extension, or the static copy link,
  copy quote link, share split and site control centre buttons) to `NSView`s.
  `CommandBarIconView` and `CommandBarPlaceholderStatusButton` subclass
  `HoverableButton` (class list). The concrete class of the `buttons` views was
- **TranslucentButton [D].** Its Swift fields are `buttonAccessibilityLabel`,
  `isEnabled` and `accessibilityLabel`. Its methods are init, the two
  accessibility methods above, `mouseDown:`, `layout` and `hitTest:`. SwiftUI's
  is in `TranslucentButton` code.
  `ev_c5c21ba78259ea15b3543cc6a509d5f5a69e17dbe75f5fb433725ee99ff4f77f`)
  `ev_034e1ac93ec4c5647e44760113f3aadf20b6db239d16a5a49fdf7fbc1cd3b9cc`). No class
  implements `collectionView:didSelectItemsAtIndexPaths:` for it (the only
  and the App Tray). `HomeBadging.HomeButton` (inferred to fill the dock's bottom-left placeholder,
  whose 1.122 content is unrecovered [I]) and the list's
  `SidebarClearButton`/`SidebarTidyButton` are an `NSView` and `HoverableView`s
  with no responder or focus override.
- **Accessibility notifications [D].** The executable's 7658 undefined symbols
  (`nm -u`) include, of AppKit's accessibility API, only
  `_NSAccessibilityButtonRole` and `NSAccessibilityCustomAction`: no
  `NSAccessibilityPostNotification(WithUserInfo)`, notification constant or
  announcement key, and no Swift `NSAccessibility.post` overlay import. SwiftUI's
  explicit posts and SwiftUI accessibility focus only; implicit AppKit or SwiftUI
  notifications (a value or selection change of the first-responder
  `CommandBarTextField`, or of the SwiftUI command-bar output) are not excluded.
- **SwiftUI accessibility hiding [D].** SwiftUI's `View.accessibilityHidden(_:)`
  modifiers inside SwiftUI bodies; none was traced to the sidebar container.
  is sent at 18 sites in `WindowLayoutController`'s transition code
  - The sidebar-presentation paths never hide the sidebar view. Their sites
    `shadowView`, `blurView`, `behindWindowBlurView`, `themeView`,
    setter below writes on `floatingSidebarContainer`), a subclass of
    `initWithFrame:` and `.cxx_destruct`; `NonClippingView` adds only
    `clipsToBounds`/`setClipsToBounds:` and initializers. Neither overrides an
    accessibility, hit-test or hidden method. The `sidebarView` setter
    y + 5, the sidebar width and height − 10, the inset 5 from the
    container lies wholly left of the window's content, 10 points clear of it.
    sends `removeFromSuperview` to the old value, `sidebar.view`
    presentation path hides `sidebar.view`, and the controller's setup
    ⌘S hide or a floating dismissal this unhide changes nothing; the one hide it
    can undo is the `.home` applier's below.
    `.home`, 1 otherwise, except 1 − min(2p, 1) when its first argument is 0 and
    the state is `.transitioning` with progress p. A ⌘S-hidden sidebar in
    `.spaces` therefore keeps alpha 1. How AppKit exposes an alpha-0 view was
    not probed.
    `transitioning` (payload), `home`, `spaces`). It runs only when the state
    tag through the payload type's `getEnumTagSinglePayload` witness with two
    which captures the controller and that view weakly. That closure,
    `.home` or still the `.transitioning` it captured (tag 0 branches to
    view. Whether a ⌘S reveal can start while `layoutState` is `.home` was not
    traced. Parc has no Home view.
  - None of the 66 `makeFirstResponder:` sites falls in the transition code.
    [R] `ev_1978ae3175b2562ce3dd6b7d8ea17030e6c7111e9a39fb382bb5cc4ac78c1513`);
    whether sidebar previews use that window was not traced.
- **AppKit defaults [C].** A cell-less
  `NSControl` accepts first responder and has an empty focus-ring mask; a plain
  `NSView` does not accept it; a selectable `NSCollectionView` accepts it and can
  become key, an unselectable one does not. In an unshown window no view has a
  `nextKeyView` until a loop is computed, and a view added later is not in a
  computed loop. A computed loop links each container before its children
  (content view → sidebar → its first child), so it enters the sidebar at the
  sidebar view itself. Hidden views and views in hidden containers cannot become
  key. AppKit's window widgets (`standardWindowButton:forStyleMask:`) come with
  `refusesFirstResponder` set, so they answer `acceptsFirstResponder` and
  `canBecomeKeyView` false where a plain `NSButton` accepts first responder
  (Full Keyboard Access off on this machine; that the refusal keeps them out
  with it on is [I]).
- **Off-screen subtrees [C].** A container placed wholly left of its window's
  controls in the window's `accessibilityChildren` and
  `accessibilityChildrenInNavigationOrder` (the order VoiceOver walks) with
  their labels and with accessibility frames left of the window. Accessibility
  hit testing at the window's leading edge returns the window and view hit
  testing returns nil, so no pointer reaches them. Its views keep
  `canBecomeKeyView`: explicit links and AppKit's computed loop pass through them
  with `nextValidKeyView`, and a text field there becomes first responder and
  keeps focus while it moves off-screen. Hiding the container removes the
  controls from both and gives focus inside it to the window.
  `makeFirstResponder:` ignores `acceptsFirstResponder`: it reports success
  for a view whose `becomeFirstResponder` refuses, and leaves the window first
  responder. An accessibility focus request (`setAccessibilityFocused:`, what
  VoiceOver sends when keyboard focus follows its cursor) makes an off-screen
  button or text field first responder, taking focus from the page (inert
  probe, not asserted). The same field placed at the locked frame is reached by both hit
  tests. On this OS a non-clipping view's `visibleRect` is its clipping
  ancestors' visible region in its coordinates, not intersected with its own
  bounds, so an off-screen or scrolled-out view still reports a non-empty
  `visibleRect`; a view that clips itself (`clipsToBounds`) reports its bounds.
  A key view's back pointer (`previousKeyView`) records only the last view
  linked to it and is not cleared when that view links elsewhere, so two
  outside views linked to one member cannot both be found from it.
  `tests/SidebarAccessibility` asserts, in a window never ordered in: the
  window's children and navigation order, the frames left of the window, that
  neither hit test reaches the controls, the Tab paths, focus off-screen and on
  hiding, the refused focus, `visibleRect` and the back pointer. Inert probes
  only, not asserted: that the same holds for an ordered-in window, that the
  listed controls keep their labels, and that accessibility hit testing returns
  the window itself. On macOS 27 an `NSButton` or `NSTextField` holds an
  internal `_NSCoreHostingView` subview that AppKit's computed loop links after
  the control, so the loop leaves a container from such a subview of its last
  control, which is no chain member (inert probe; the check asserts that the
  chain's end still keeps that way on).

### Inferences and unresolved points

  ([tooltips](tooltips.md)). The toggle shows it as Parc's tooltip and keeps
  its former help tag's text ("Hide sidebar ⌘S", live binding) as
  accessibility help on the button and its exposed cell. Every other control
  (`LiveShortcutToolTip`, [accessibility help](tooltips.md#accessibility-help)):
  the title and the command's current valid binding, refreshed on every
  binding change, none for an unbound Reset Tab.
  sidebar** from the 1.170 locked observation [O]; floating → **Lock sidebar**
  is [I], and so is hidden → **Lock sidebar**: pressing the hidden sidebar's
  sink closure whose publisher was not traced.
  [D]), as the 1.170 tree shows; its row attributes are those of the AppKit
  probe [C]. That `ListHeaderCellView` shows folders rests on its folder icon
  field. Its AX tree was not observed (the 1.170 Space had no folder): the
  chevron would be an `AXButton` inside the folder row's cell.
  item. Recovered [D]: the proposal filter adds the visible current item to a
  outline's `selectedRowIndexes` hold after an activation by shortcut or a new
  tab was not traced. A custom-titled split's cell holds only its custom info, so
- [I] A `TranslucentButton`'s hosted SwiftUI button joins Full Keyboard Access
  with SwiftUI's own focus effect; its container never takes focus.
  traffic lights are AppKit's refusing widgets [C], so the loop passes them),
  the pill's `HoverableButton`s, then the dock. The outline is no stop: it
  Access a `SidebarDockItemView` accepts first responder but draws no ring, and
  the selectable dock collection view is a stop whose keyboard selection switches
  no Space (no selection delegate). None of this was observed at runtime.
  recovered (the unhidden sidebar in the unhidden floating container at
  x − width − 10, at alpha 1, with no accessibility override [D]) and AppKit
  exposes such a subtree to accessibility and the key-view loop [C]. Not
  observed: that VoiceOver's cursor lands on the off-screen elements, and that
  hand-off sends `selectNextKeyView:` or `selectPreviousKeyView:` to the page
  first is untraced). Parc
  builds the same unhidden, off-screen, non-overriding subtree for
  or its z-priority sort; where the subtree falls among the window's
  accessibility children was not compared. It takes the subtree out of Tab (an
  adaptation, inventory below). That the show preparation's unhide, which
  changes nothing after a ⌘S hide [D], is defensive is [I].
  moves: no explicit post exists [D], but implicit notifications from the
  command field or SwiftUI output were not excluded, and nothing was observed.
- Unresolved: the concrete classes of the pill's static buttons (Parc's page
  actions; `CommandBarPlaceholderButtonsView` stores them as `NSView`s, and
  its copy-link view models are SwiftUI observable
  objects [D]), whether Parc's payment and pop-up entries have
  to. These are recorded unknowns that runtime acceptance item 3 compares.

## Inventory

| --- | --- | --- | --- |
| Site Control Center (WEB14; formerly "Page actions"), payment, pop-ups, extension pins, quote | Labelled buttons; extension items use their own labels; quote affordances take no keyboard focus | Not in the 1.170 still; pill button IDs [D], classes untraced | DONE for the labels; runtime acceptance item 1 reads them in the running tree |
| Resize strip | Plain view: not an element, absent from children and hit tests | 1.170 nothing exposed [O]; 1.122 no AX overrides [D] | DONE (component check) |


| --- | --- | --- | --- |
| Site Control Center, payment, pop-ups | Site control centre entry of `CommandBarPlaceholderButtonsView` (`NSView`, class untraced) [D]; payment and pop-ups untraced | Unknown | Parc ring, radius 5, so the stop is marked; the concrete class is untraced, a recorded unknown (runtime acceptance item 3) |
| Quote affordances | `copyQuoteLink` entry [D] | Unknown | Refuse focus (existing; the menu command stays) |
| Library entry | `HomeBadging.HomeButton` `NSView`, no stop [D] | None | No stop and no ring (DL33) |
| Preview card plus and gear | `PreviewPlusButton`, `PreviewGearButton`: SwiftUI structs [D] | SwiftUI's own focus effect [I] | Keyboard stop with the radius-5 ring, the same stand-in as the toggle's |
| Mini player buttons and "Show All" | SwiftUI buttons in that view [D for the structs, I for the buttons] | Unknown, as above | "Show All" and the title draw the radius-5 ring; the transport buttons keep their exterior ring and the volume slider AppKit's own |
| Resize strip, keyboard highlight | `SidebarResizeRegionView` (`HoverableView`) [D] | No stop | No responder (unchanged) |

## Contracts for other owners

### Item list outline (delivered; row, folder and Split View owners)

An earlier increment made the list `NSStackView` an `AXOutline` with every
hierarchy view in `AXRows`; it was reverted because the tab buttons, folder
triangles and split groups it listed were no `AXRow`s. The delivered outline
(`SidebarOutline.swift`) instead wraps every visible list entry in a genuine row
and keeps each item's element unchanged inside that row's cell, as AppKit does

1. **Rows and cells (sidebar).** `SidebarView.render` hands the list one
   `SidebarOutlineEntry` per tablist slot (`SidebarChromeLayout.tablistSlots`),
   in order: the empty pinned header, pinned tabs, Split Views and folders, the
   divider cell holding Parc's line and Clear, listed only while Today has
   items (private windows show the Incognito heading in place of these), New
   Tab, then Today's tabs, Split Views and folders. Items are built by `SidebarOutlineEntry.item`
   and `.folder` (keyed by their `SidebarItemReference`, with folder level,
   disclosing folder and, for folders, expanded state and toggle); the list's
   own rows are keyed by `SidebarListRow` and take their slot's row, the header
   through `SidebarOutlineEntry.pinnedHeader`. Each
   becomes a `SidebarOutlineRow` (`AXRow` / `AXOutlineRow`) holding one
   (`SidebarChromeLayout.tablist`, [sidebar chrome spacing](sidebar-resize.md#sidebar-chrome-spacing)):
   a row is its cell plus the 1-point intercell gap below it, a level-n cell
   starts 16n points in and reaches the trailing edge, and the cell lays the
   entry's view out in it (an item's 36-point visible row 2 points down, any
   other view filling it, short of its trailing inset). The item is the cell's
   child and names the cell as its parent through the view hierarchy, so no
   other owner's view changes its role, title, actions or parent code. A hidden
   entry would keep a hidden row that is no element; `SidebarView` builds none.
2. **Row attributes.** `AXIndex` counts visible rows in visual order;
   `AXDisclosureLevel` is the folder depth; folder rows report `AXDisclosing` and
   `AXDisclosedRows` (visible direct children), child rows `AXDisclosedByRow`.
   Setting `AXDisclosing` on a folder row expands or collapses the folder
   (`onToggleFolder`) without the triangle click's selection reset, and the
   render keeps the selection across a disclosure change (reconcile drops the
   rows a collapse hides). The pinned header row is an expandable row with no
   children: it reports `AXDisclosing` false and settable, with no disclosed
   rows; setting it changes nothing and runs nothing, so the row stays
   collapsed, as AppKit leaves a childless expandable item. Other rows refuse
   it. Rows and cells report `AXSelected`.
3. **Outline (sidebar).** `AXIdentifier` `sidebarAllTabList`. Children are the
   rows, then one `AXColumn`; `AXRows`, `AXVisibleRows`, `AXSelectedRows` (multi-selection or single selection plus
   follows a change of the visible rows, `selectedRowsChanged` every change of
   the selected rows (Select All's former `selectedChildrenChanged` post on the
   sidebar is gone), `rowExpanded`/`rowCollapsed` a folder's disclosure change;
   that AppKit's outline posts the same is [I] and none was observed. A row keeps
   its element across renders while its key stays. The outline is the focused
   element only while `SidebarView` is first responder and its
   `canBecomeKeyView` holds (which needs `isPresented`), the list is shown and an
   item row is visible.
4. **Folder rows (folder owner).** Nothing required. `SidebarFolderRow` stays an
   a chevron `HoverableButton` and title fields instead [D] (their exposure is
   [I]); either way the row's `AXDisclosing` and the cell's control both reach
   expand and collapse.
5. **Split groups (Split owner).** Nothing required. A split is one row, as
   case shows no children either [D for the layout enum, I for its AX], so the
   earlier request to keep those tabs reachable inside the outline is withdrawn.
   The group's menu still reaches each child's actions. The split cell's own
   none (SP30, SP32).
6. **Open.** Rows' `AXSelected` and the outline's `AXSelectedRows` are
   a change through its selection proposal [I]. Parc's 41-point item rows and
   3- and 25-point header and divider rows (component-checked [C]) have the
   sidebar-wide outline (the list's 8-point side inset), and an item's element
   Acceptance still needs a runtime AX inspection of Parc compared with the
   1.170 tree and VoiceOver navigation over tabs, nested folders and splits;
   neither ran.

### Navigation buttons (navigation owner)

- Landed (NAV16): `NavigationControlButton.setLoading(_:enabled:idleLabel:forceReload:)`
  pill, with the live binding as keycaps and as accessibility help) and the
  accessibility label; **Stop Loading** while loading stays a Parc adaptation.
  The caller-side overwrites are gone, and `SidebarView.updateNavigation` applies
  the label to the exposed cell through `SidebarAccessibility.label`. The popup
  toolbar's Reload now uses the same default label.
  popup toolbar wording was not recovered; matching the sidebar would use
  **Go back**, **Go forward** and **Reload this page** [I].
  implemented (NAV16, [navigation](navigation.md#loading-stop-and-refresh-feedback));
  it follows Reload in the header order and Tab chain. `moreButton` (**More
  options**) still has no Parc equivalent.
- `NavigationControlButton.focusRingCornerRadius` is opt-in; the sidebar sets
  radius 5 on its Back, Forward and Reload (`TranslucentButton`s [D]).
  bar draws its Back, Forward and Reload as SwiftUI buttons styled by
  `TopBarButtonStyle` inside `TopBarPanelContainerView` [D] (pane top bar
  above), the same class as the sidebar's hosted buttons, so the pane toolbar
  owner (Split views) should set `focusRingCornerRadius = 5` on
  `BrowserToolbar`'s three navigation buttons to match the sidebar's stand-in;

### Window key-view loop (delivered with SIDE17; window owner informed)

The sidebar's chain starts at a gate (`SidebarView.keyViewEntry`, a plain view
that never takes focus), continues at its first header control (the toggle, or
Back in a narrow row) and ends at the dock's "+". Its way out is
`SidebarView.keyViewExit` (weak; setting it relinks). While that is nil, "+"
keeps the first link out of the sidebar that the chain already holds and that
stays in the sidebar's window, else one another view inside the sidebar holds:
AppKit's computed loop leaves the sidebar from its last descendant, on macOS 27
a control's own hosting subview [C]. A view removed from the sidebar is never
taken. A link from outside into `sidebar` itself, which is where AppKit's
computed loop enters [C], or into any other member, moves to the gate on the
next link, and the gate keeps the way back of an outside link already there
(the page side's end). While the sidebar is not presented the gate leads
straight to the way out, linked at once when the presentation changes.

just added while its one `recalculateKeyViewLoop` is a page dialog's own window
[D, purpose I] (keyboard-focus API surface above). AppKit computes the loop when
the window is first shown and later views (pages, find, Library) are in none
[C]; Tab from a page's last element, which both engines turn into
`selectNextKeyView:` on the page view's window (Parc's `rotateFocusForward`,
delegate takes the hand-off first (untraced). `WindowKeyViewLoop` (owned by
`BrowserWindowController`, its wiring there) links the page side, Parc's
stays in the page, the link is a divergence and comes out:

1. the page side is every key view outside the sidebar's container and the
   parked panes, in AppKit's geometric order (`SidebarAccessibility.keyViews`),
   leaving out (`WindowKeyViewLoop.windowExcludes`) sidebar preview cards, root
   subviews whose controls a keyboard-owned card keeps among themselves and
   which, while animating out after a dismissal, would take a Tab and drop focus
   to the window when removed, and, while a Peek is up, the page host's other
   subviews (the panes it dims, other Peeks); inside a page (`PCBrowserView`,
   the extension side panel) a view that takes focus and holds another that does
   is the engine's forwarding page host, so its renderer is the stop
   (`page_host.mm`); the Peek's host (`PeekHostView`), which accepts first
   responder only for Escape, is no stop and its controls and page are;
2. its last key view leads to `sidebar.keyViewEntry` and `sidebar.keyViewExit`
   is its first, in every presentation; with the sidebar hidden or absent
   (Library, popup, page full screen) the gate leads straight back, so the page
   side loops on itself;
3. the whole window loop is never recalculated: a view below the root that holds
   a closed loop of its own (page capture's overlay, its portrait card) keeps
   it, and its subtree stays off the page side;
4. it relinks after every full chrome layout (presentation, pane, Library,
   find, panel and full-screen changes end there), when the window becomes key
   (a window's first show replaces earlier links with AppKit's computed loop
   [C]) and when focus reaches a page-side view the last link left out (a
   renderer the engine swapped in), never for a field editor.

`tests/SidebarWindowKeyLoop` checks it with the production linker and
observed; that it stays in the page is [I]. Peek owner (unowned, informational):
if the Peek's host itself holds focus, Tab from it still goes nowhere, as
before; linking it into the Peek's controls would be the Peek owner's.

### Page controls opened from the sidebar (page-actions owner)

A hidden sidebar stays unhidden off-screen, its controls in the accessibility
tree, so VoiceOver can still press them and their `visibleRect` is not empty
[C]. Whether the sidebar shows is `SidebarView.isPresented`, never
`isHiddenOrHasHiddenAncestor` or `visibleRect`. While it is false, the page
controls that the sidebar's buttons or the default anchors open go to the page
(`currentBrowser`, else the page host) instead of an off-screen anchor:

- the extension-controls popover without a toolbar anchor shows from a point
  square in the page's top leading corner (`hiddenSidebarAnchor`), and its
  page-actions entry opens the page menu from the toolbar anchor the popover came
  from, or that corner;
- the page menu without a toolbar anchor pops up at that corner; its Site
  Settings and Pop-ups items anchor to the page;
- blocked pop-ups opened from the sidebar's button anchor to the page, and the
  payment menu opened from it pops up at the page's corner.

[I]; anchoring to the page is a Parc adaptation. A new page popover or menu
anchored to a sidebar control must follow the same rule. The sidebar's own menus
are not moved: the dock's "+" menu (`showPlusMenu`) and the Show Menu action of
rows, Favorites tiles and the dock's Space items still pop up at their control, left of the window (where

### Focus restored after a panel (every owner that restores focus)

A panel or session that saves the window's first responder and restores it
later must not restore it into a sidebar that is no longer presented: the
off-screen sidebar's views still take focus [C]. Every such restore asks one
test, `SavedFocus.mayReturn(to:in:)`: the view must be in that window, not
hidden, and inside no `OffscreenPresenting` container (`SidebarView`) that is
not presented, at any depth (a field editor inside a sidebar field included).
When it refuses, each owner keeps its own fallback. Delivered for every stored
saved responder in `Sources/ParcApp`:

- both command bars (`CommandBar.dismiss`; else the owner's page focus);
- Space creation's cancel (else the page or local content);
- navigation history's deferred restore (`NavigationHistoryController`; else
  focus stays where it is);
- Easel web input's cancel (`EaselWebInput`);
- sidebar previews' dismissal (`SidebarPreviewController`; the card then still
  gives up any focus it holds);
- the sidebar window move's restore when the move does not start.

Reviewed and exempt: `OnboardingPasswordHelp` restores within the onboarding
window, which holds no sidebar, and `PeekFocusReturn` keeps only a responder
inside the page or Peek it came from. `tests/SidebarAccessibility` fails when a
new file declares a stored `weak var …Responder: NSResponder?`, the only shape
its pattern matches: a responder held otherwise (not weak, named differently, or
a captured local, as the window move's is) passes unnoticed, so a new restore
path must still be reviewed against this test. During a hide's slide the sidebar
is still presented, so a restore may land in it then; the window takes that
focus when the hide settles (above).

The window takes it, not the page: the release is in `layoutChrome`, which a
motion's completion calls and which also runs inside the root view's layout
pass (`rootView.onLayout`), and neither requests page focus
(`requestNativeSelection` renders and synchronizes native layout). The release
is safe in both: it runs once per transition (the sidebar is no longer
presented when it does, so a nested layout does not repeat it), the list stop's
resignation only redraws its selection, and a rename field's end of editing
completes on the next turn (`SidebarTitleField`). Because the field is no longer
hidden, the rename then completes with its text, as a click away does, where
editing off-screen [I].

VoiceOver's own focus requests are left alone: AppKit moves focus to an
subtree would take them the same way [I], and refusing them would leave the
exposed elements unusable from VoiceOver. Parc keeps only automatic and
restored focus out of the hidden sidebar.

### Downloads entry (Downloads owner)

**Delivered by the Downloads owner (DL33, October 27).**
`HomeBadging.HomeButton` is an `NSView` with no responder override: no stop and
no ring [D]. The Downloads owner traced the dock's `leftButtonPlaceholder` to it
entry, tooltip "View Library", accessibility label "Home". Parc's former
Downloads button is replaced by `SidebarLibraryEntry` in that 32 × 32 slot at
x 8 (the Space strip is 40…width − 40). It refuses first responder, draws no
ring and is out of `linkKeyViews`' trailing list, which is now `[footerMore]`.
It exposes "Home" with no value; each expanded flyout cell is its own button
([entry details](download-library.md#original-library-entry)).

### Row and mini player key views (rings delivered with SIDE17; media owner: MEDIA16)

The chain includes every control that takes keyboard focus inside the Favorites
grid, the list and the mini player deck, in visual order (disabled controls keep
their place), and each such stop draws a ring or refuses focus. The sidebar's
the exterior ring. The mini player's three unmarked stops now draw one, the
sidebar's minimal hook in `MiniPlayerView.swift` (Media's file, shared scope,
behaviour unchanged): `MiniPlayerRow` keeps accepting first responder (Return
reveals its page, Space plays or pauses, focusing it expands the deck) and draws
an exterior ring around its card (radius 9, the card's corner); the deck's "Show
All" and each row's title draw the radius-5 ring; the transport buttons keep
their exterior ring and the volume slider AppKit's own. The sidebar relinks after
every render and whenever `updateMiniPlayers` receives a different list of
players.

`NSView` that takes no focus, hosting SwiftUI per-player `MiniPlayerView`s [D];
whether those or their buttons take focus is unrecovered, because SwiftUI's
`focusable(_:)` and `focusEffectDisabled(_:)` are both called from the
player to no stop, matching it would drop the row's stop and its focus-driven
expansion; without Full Keyboard Access an `NSButton` cannot become a key view
[C], so the player would then have no Tab stop at all and Return-to-reveal and
Space play/pause would need another keyboard path. That choice, and
`media-mini-player.md`'s keyboard sentence, stay with the media owner.

### Control-Space announcements (command-bar owner)

moves [D], and neither does Parc; implicit AppKit or SwiftUI notifications were
not excluded, and neither app was observed with VoiceOver [I]. Spoken feedback
would be a Parc adaptation and belongs to the command field, which keeps
focus: for example its accessibility value or an `announcementRequested` post
naming the highlighted item when the cursor changes, never when the list is only
reconciled. Not implemented.

## Checks and open questions

`tests/SidebarAccessibility/check.py` builds `SidebarAccessibility`, the
production `ActionButton`, `NavigationControlButton`, `WindowStandardButtons` and
`SidebarResizeRegionView` into an off-screen window that is never made key,
without a browser or input. Source assertions (string matches, not behaviour)
confirm that `SidebarView` orders its header and Tab chain through the checked
helpers and that its presentation reaches the lights, the dock, the payment
entry, its list stop and the bypassed link. It verifies:

- the labels, and that `configureSpace` replaces an `ActionButton`'s default role
  name adaptation) and removes the Space's keyboard stop and ring;
- the rounded focus masks of `ActionButton` and of the sidebar's
  `NavigationControlButton` ring (whose default stays exterior);
- key-view ordering: rows, leading edge, an unflipped host, a disabled control
  kept, labels (also disabled ones) and Spaces excluded;
- `keyViewChain`: leading controls, Favorites, the list stop, the list controls by
  frames a region sets only in its own layout, then the dock;
- linking: chain order with the list stop, hidden members skipped by
  `nextValidKeyView`, the preserved window-loop exit and relinking, an explicit
  exit replacing it, a removed former member never taken as the exit, an outside
  link into the list stop's view moved to the chain's start, an outside link
  into a former first member moved to the new start, a hidden container;
- the header: the traffic lights first in the accessibility children with
  `AXCloseButton`/`AXMinimizeButton` subroles, then the toggle, Back, Forward and
  Reload; the toggle leading without the lights; a narrow row ordered by its
  frames (Back, Forward, toggle); the lights refusing first responder and
  absent from the key views;
- that the resize strip has no element;
- the hidden presentation: at `SidebarPresentationFrame.locked` both pointer
  and accessibility hit tests reach the address (the positive control); at
  `.hidden` the container stays unhidden and wholly outside the content, its
  controls stay in the window's accessibility children and navigation order
  with frames left of the window, and neither hit test reaches them where they
  were or where they are; an off-screen field's `visibleRect` is not empty while
  a self-clipping view's is its bounds; AppKit's default keeps the off-screen
  chain a Tab stop (a field there takes focus, the computed loop and the linked
  chain pass through it); without an exit the chain's end keeps the computed
  loop's way on, which leaves from the field's own subview, and bypassed then
  Tab and Shift-Tab pass it; bypassed, with both the computed loop's way in and
  the window owner's at the gate, Tab and Shift-Tab pass it, a bypassed relink
  keeps that, and an unbypassed relink restores the chain and the way back to
  its end; a key view's back pointer keeps only the last view linked to it,
  also after that view links elsewhere; an off-screen field keeps focus, a
  list stop that is not presented takes none (the window keeps it), and hiding
  the container gives its focus to the window;
  hiding the container removes the controls from both. `check.py` also
  asserts, as source shapes only, what keeps focus out of a sidebar that is not
  presented: the list stop's `becomeFirstResponder` and selection guards,
  `SidebarView`'s calls of the two helpers below (the selection action and both
  rename paths), the window's rename reveal, the window owner's release of focus
  when the sidebar stops being presented, the chain's bypass linked at once when
  it does, every saved-focus owner's use of `SavedFocus.mayReturn` and the files
  declaring a `weak var …Responder: NSResponder?` (the only shape it matches). It
  runs the production `SavedFocus` against the off-screen sidebar: a presented
  sidebar's views may take restored focus, one that is not presented, its field
  editor and a hidden container may not, and the page may. It runs the
  production `OffscreenPresenting` helpers on the stand-in list stop:
  `focusIfPresented` (a row's selection action) leaves the page's focus while
  hidden and takes focus while presented; `presentsForEditing(reveal:)` (a row's
  Rename) reveals nothing outside a key window, and in a window that only
  answers key (never ordered in) runs the owner's reveal while still presented
  (a hide in motion), lets a hidden sidebar the reveal floats in edit, and
  refuses when the reveal leaves it hidden or no owner exists.

`tests/SidebarChrome/check.py` asserts the dock's accessibility order and the
creation item's Space values, and that the dock drops its hover when the
sidebar leaves unhidden; its return re-tests only in a key window, which the
inert check never has, so that half shows only that nothing stays lit.
`tests/SidebarWindowButtons/check.py` checks the lights' drop and, in a window
never ordered in and placed under the pointer, that their return hovers them
presentation frames, the frame each pass of every transition places
(`SidebarPresentationFrame(_:inMotion:floatingSurface:revealsAnchored:)`) and
when `SidebarPresentation.presents(inMotion:)` holds; its source assertions
confirm that `BrowserWindowController` hides the container only without a
sidebar, places and presents through those helpers, sets the presentation after
the frames and re-tests the pointer when a reveal completes.

`tests/SidebarOutline/check.py` builds the production `SidebarOutlineView`,
configured as `SidebarView` configures its list, in a scroll view in an
off-screen window that is never made key, with items exposed as TAB22's tab
buttons, `SidebarFolderRow`'s triangles and `SidebarSplitGroupView`'s groups are,
keyed by the production `SidebarItemReference` and built by the production
`SidebarOutlineEntry.item` and `.folder` helpers, the production `ActionButton`
for Clear and a bare `ActionButton` standing in for New Tab, a line with Clear in the divider cell (an `NSBox` stands
in for `SidebarView`'s hairline), the empty
pinned header, the list's own rows taking their production
tablist slots' rows. It asserts the outline's own stacking and bottom inset,
the helpers (an item's key, item row, `AXDisclosureLevel` and disclosing
folder; a folder's expanded state and toggle; a control's entry being no item;
the pinned header's empty control row, expandable without children and with
nothing else, the only such entry) and, through the NSAccessibility protocol:
the outline role, its `AXIdentifier` `sidebarAllTabList` with no label or title,
children (rows then the column), `AXRows`, `AXColumns` and the scroll-area
parent; every row's role, subrole, index, parent, single cell child and
screen frame across the list; cells' role, parent, index ranges and frame (16
points in per level, the 1-point gap below); each item, or a control's exposed
cell, as its cell's only child with that cell as parent, Clear in the divider's
row and nothing in the header's; the views' spans and insets (also after the
list narrows), the 3-, 41- and 25-point rows abutting and the 120-point
bottom inset; folder disclosure
(level, `AXDisclosing`, disclosed rows both ways, a collapsed subfolder,
settable only on folders, the toggle run once and only on a change, the
selected rows left alone); the pinned header row (collapsed at level 0, settable,
disclosing nothing, the pinned items its siblings; setting it leaves it collapsed,
adds no rows and runs no toggle, and the row survives a rebuild collapsed and
settable), matched against a stock `NSOutlineView` read through the legacy
attribute methods (the childless expandable header collapsed and settable, a tab
row not settable, and setting it asking the delegate and leaving it collapsed);
selected rows as the multi-selection or single
selection plus the active item, filtered to visible rows; visible rows before
and after scrolling; each element exposed exactly once; rows kept by key across
a rebuild, removed rows leaving the window, indices renumbered and selection
carried over; a hidden entry's row being no element and taking no space;
duplicate keys getting separate rows; and the outline focused only while its
stop is first responder and can become key (not once it cannot, as a hidden
sidebar's), the list is shown and an item row is visible (not for a list of
controls only, as a Space without items has). Without compiling
`SidebarView`, it guards that the list is fed only through the outline: no
direct arranged-subview use, no `selectedChildrenChanged` post, no hand-built
item entry (only `SidebarListRow` controls use the plain initializer), the
header built by `SidebarOutlineEntry.pinnedHeader` and no
folder click (`activate`, which clears the selection) behind a row's
`AXDisclosing`. `SidebarView.render`'s
calls (the depth, folder and active item it passes) and its selection keeping
across a disclosure change are not exercised. Posted notifications are not
observable in process and remain unverified.

`tests/SidebarWindowKeyLoop/check.py` builds the production `WindowKeyViewLoop`
and `SidebarAccessibility` with a stand-in sidebar linked by the production
helper, in a window never made key, over a stand-in page side: two split panes
with engine-like forwarding page hosts (one with an infobar), page capture's
closed loop, find, an extension panel, parked panes, Library and a popup bar.
Tab and Shift-Tab go through the window's own `selectNextKeyView:` and
`selectPreviousKeyView:`, as Parc's engine sends them. It asserts that AppKit's
computed loop leaves a later page without a way out (the negative control);
the page side's geometric order with renderers in place of their hosts and
without the closed loops, parked panes or sidebar; both directions of the
locked loop; leaving a page from its renderer; that becoming key restores the
loop after AppKit recomputes it; that a capture and a portrait card opened later
keep their loops; the hidden and the absent sidebar (the page side loops on
itself); removed and added panes; a renderer swapped in relinking when it takes
focus (not for a field editor); Library's and a popup bar's controls leading
the page side; and that no page-side view ever links into a sidebar member
other than the gate. In a second window it runs the window's production
exclusions (`windowExcludes`, with a pass-through stand-in for the Peek's
host): a production `SidebarPreviewSurface` with controls, live and retired,
stays off the page side, Tab from the page's end reaches the gate and
Shift-Tab from the sidebar's first control the page's end, no card control is
linked and focus inside the card relinks nothing; a Peek over the page host
makes its close button and page the page side, without the pane it dims,
another Peek or its own host, in both directions between the sidebar's ends,
and the pane returns when it closes. Each rule has an in-test control that
shows the card's controls, the dimmed pane or the Peek's host joining without
it. Its source assertions confirm the window controller's wiring (exclusions,
page rule and pass-through), where the card and the Peek are hosted, and that
it never recalculates the window's loop.

`tests/SidebarMiniPlayerFocus/check.py` builds the production `MiniPlayerDeck`
(with `ActionButton` and `LayoutView` from `SidebarView.swift`) over stand-in
engine media types: two players make two rows, each a keyboard stop with an
exterior ring over its bounds whose mask follows the rounded card; "Show All"
and each row's title draw the radius-5 rounded ring over their bounds and the
other eight buttons keep their exterior ring; the deck's key views start at
"Show All" and hold each row ahead of its title; focusing a row expands the
deck; Return on a focused row reveals its page and Space pauses it; and Return
on a focused control still reaches its row.

Negative controls run for this round: the mini player check fails on the
`MiniPlayerView.swift` before SIDE17 (the row draws no ring) and on the first
SIDE17 version (a row is no stop); the window loop check fails with the
previous loop test, which missed the portrait card's sibling loop, without the
preview-card exclusion, without the Peek exclusion and without the pass-through;
the outline check fails without the identifier, with a header row that is not
settable and with one that expands; the accessibility check fails when
`SavedFocus` ignores an unpresented sidebar, when the rename reveal runs only
for a sidebar that already reports hidden, and when the selection action
focuses the list stop whatever the presentation.

In-process AppKit reports an `NSButton`'s `NSButtonCell` as the unignored
accessibility element, and attributes set only on the button do not read back
from the cell; the cell describes itself from its image. Parc's sidebar labels
and Space values are therefore set on the button, its cell and (for labels) the
image description, and the focused check asserts them on
`NSAccessibility.unignoredDescendant(of:)`. These checks do not run
`SidebarView` itself (`linkKeyViews`' composition, the focus seeding, the hidden
list's key handling, the render that feeds the outline), what a remote client
reads, or Tab in a shown window with Full Keyboard Access: the runtime
acceptance below covers them. Tooltip shortcut chips stay with the navigation
owner.

## Runtime acceptance (SIDE17)

**Not run.** At the user's direction (October 27) this check was skipped and the row is DONE on its verified code; the procedure is kept for reference.

The row's component work is complete; this inspection of the running apps
it (appearance, AX and focus inspection only: no browsing beyond the setup
pages, no form input, no bug hunt). Record every capture and result outside
Git (`work/claude-sidebar-rea/appearance/side17-acceptance/`), with the app
versions, the Parc commit and the window size, and summarize the outcome here
and in the ledger.

read-only on its existing profile. Both windows 1470 × 831 points on the same
display as the 1.170 capture (`arc170-create-space.txt`, frames in screenshot
pixels at 0.9905). In each app: one Space named "Space 1", one pinned tab, one
folder holding one tab, one split of two tabs, one Today tab, and for the mini
player step one page playing media. The user turns on Full Keyboard Access
(System Settings → Keyboard → Keyboard navigation) and VoiceOver (⌘F5) when a
step needs them; no agent changes system settings. Read trees with Xcode's
Accessibility Inspector or the computer-use AX listing; take the focused
element from the same tool after each key press.

### 1. AX tree (locked sidebar, VoiceOver off)

Capture the window's tree in both apps and compare it with the 1.170 capture.
Pass when all of these hold in Parc:

1. Window children lead with `AXCloseButton`, `AXMinimizeButton` and
   `AXFullScreenButton` (16 × 16 at x 12, 35, 58, y 16), then the toggle
   **Hide sidebar**, **Go back**, **Go forward** and **Reload this page**, then
   the address, then the list's scroll area, then the dock.
   Today tab with no history, Go back and Go forward disabled and Reload this
   page enabled; with Space creation open from "+" (the capture's state), where
   the capture lists all three disabled [O].
2. The list is an `AXOutline` with `AXIdentifier` `sidebarAllTabList` and no
   `AXTitle` or `AXDescription`; the tool prints it as `outline
3. The outline's children are `AXRow`/`AXOutlineRow` rows in visual order, then
   one `AXColumn`. Row 1 is the pinned header: 3 points tall, listed collapsed
   with an Expand action (`AXDisclosing` false and settable, no disclosed rows,
   level 0). Then the pinned tab's row (41 points), the 25-point divider row,
   New Tab, the folder row (`AXDisclosing` true, its child row naming it as
   `AXDisclosedByRow`, level 1, 16 points in), the split's row and the Today
   tab's row. Each item row holds one `AXCell` around the item's own element: a
   tab is an `AXButton` described as **Tab** and titled with the page title.
4. The dock's scroll area lists `Space Space 1` with identifier
   `SidebarDockItem-Space 1` (role description **Space**); during Space creation
   also `Space Create Space` (`SidebarDockItem-Create Space`) last.
5. No element exists for the resize strip.

pager, a scroll area (Scroll Left, Scroll Right) holding a disabled collection
and a disabled section around the list's scroll area [O], where Parc's outline
are listed selectable [O], where Parc's rows keep `AXSelected` read-only (the
the dock [O], whose source is untraced and which Parc has no counterpart for
(a recorded unknown); Parc's address is an `AXButton`
cell). A third light reading `AXZoomButton` fails item 1 (the inert check
process reads it so because its window is not full-screen eligible).

Then, with VoiceOver on, open the actions of row 1 and choose Expand: pass when
note what it does). Collapse and expand the folder row with VoiceOver: pass when
its child row leaves and returns and the selection is unchanged.

### 2. Hidden and floating trees

Press ⌘S. Pass when the sidebar's subtree is still in Parc's tree with frames
wholly left of the window (x − width − 10), the toggle reads **Lock sidebar**,
and no element answers a hit test at the window's leading edge. Hover the
its hidden subtree is listed.

### 3. Tab and Shift-Tab (Full Keyboard Access on, VoiceOver off)

Locked sidebar, focus in the page (click its body once), then press Tab past the
page's last element and keep pressing Tab, noting the focused element and its
ring each time. Pass when Parc's stops are exactly, skipping hidden and
disabled controls: the toggle → Back → Forward → Reload → the address pill →
pinned extension buttons → pop-ups → payment → page actions → Favorites'
controls → the list stop (the active tab or split shows HighlightRingView and
the outline is the focused element) → the list's controls top to bottom (folder
triangle, row close buttons, New Tab) → the mini player's controls (step
4) → "+" → back into the page. Shift-Tab from the page's first
element walks the same stops in reverse. Every stop draws a ring: radius 5 on
the toggle, navigation buttons, "+", page actions, payment, pop-ups and
Downloads, radius 12 on the pill (7 in shared-quote mode) and on New Tab. The traffic lights, the Space
buttons and the quote affordances are never stops.

Hidden: press ⌘S and repeat. Pass when Tab from the page's last element returns
to the page's first and Shift-Tab from its first to its last, never focusing a
sidebar control. Floating: reveal it by hovering and repeat: pass when the chain
is walked as when locked.

Panes, Library and popups: with a split view, Tab passes each pane's page in
turn before the sidebar; with Library open, Library's controls lead the page
side; in a popup window, its bar's controls do; in each, Tab never stops in
the hidden sidebar. Pass when no Tab leaves a stop with no way on.

differences, Parc's adaptations: the list stop and Tab passing a hidden
focus goes; Parc's link from the page side into the sidebar is then a
divergence, item 3 fails, and the fix removes that link (`WindowKeyViewLoop`'s
link from the page side's end to the gate and the sidebar's exit into the page
link matches and stays. For the recorded unknowns (New Tab, page actions,
ring it draws; Parc keeps its ring on each as a recorded difference until their

### 4. Mini player

Play media in a background tab so the deck shows (two players for "Show All").
Pass when Tab reaches "Show All" (radius-5 ring), then each shown player row
with an exterior ring around its card (a ring the card's clipping hides fails
this item), its title (radius 5) and its transport buttons (exterior ring);
focusing a row expands the deck; Return on a focused row reveals its page and
owner (MEDIA16): a difference there is that owner's contract, not a failure of
this row.

### 5. Focus never lands in an unpresented sidebar

1. Tab to the address pill, press ⌘S: focus goes to the page (key window).
2. Hidden, open the command bar from the keyboard and press Escape: focus
   returns to the page, not to an off-screen control.
3. Hidden, in VoiceOver choose **Rename Tab** on an off-screen row: the sidebar
   floats in and the rename field edits on screen. Repeat it from the row's
   menu while a ⌘S hide is still sliding: the sidebar floats back and the field
   keeps editing once the motion settles.
4. Hidden, choose **Add or Remove from Selection** on an off-screen row: the
   selection changes and keyboard focus stays where it was.
5. Press ⌘S and keep pressing Tab while the sidebar slides away: once it settles,
   focus is not inside the sidebar.

VoiceOver may still move keyboard focus onto an off-screen control it
selects; that is accepted (focus restored after a panel, above).

The row is DONE when items 1–5 pass, or each failure is fixed or recorded here

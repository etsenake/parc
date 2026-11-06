# Sidebar motion ownership

`BrowserWindowController` owns locked, floating and hidden presentation. It
changes the actual native view frames and synchronizes the existing renderer
host. `SidebarMotionController` owns the AppKit animation context around that
layout, including the original content subtree. It does not take ownership of
page selection, native focus, renderer contents or a second window.

## Dock plus HUD

The dock + opens `SidebarPlusMenuController`'s borderless, key-but-not-main
Return and Escape belong to the HUD and a click outside causes it to resign key
and close. Its tail stays near the card's trailing edge over the dock +. Open
scales 0.95 → 1 about the tail over 0.1 s with a 0.05 s opacity fade; close

`SidebarPlusMenuController.onVisibilityChange` is the open/close hook. The
controller records the open HUD and fires `true` before the child window
becomes key, so the parent still sees it when that window resigns key, and
fires `false` when every close path starts. The window then ignores input
until its close animation removes it. The parent
window's close, miniaturize and sheet presentation close immediately, while
outside click, Escape, item choice, dock-toggle, resize, menu routing and app
deactivation use the exit animation. `BrowserWindowController` defers a
hover-revealed sidebar while this HUD is shown and refreshes its pointer state
when it closes.

### Colours and type

window theme's `WindowTheme.semanticColorPalette` (`theme+0x100`) as a live
their own appearance, not the Space's content appearance: a forced-dark Space in
`ThemeChromePalette(theme:isDark:)` for the window's live theme
(`applyChromeTheme` → `SidebarView.plusMenuTheme`), and an open HUD recolours
when that theme changes. The Back/Forward history chooser shares

own appearance from the theme's optional `windowAppearance` (`theme+0x7c`),
resolved against the app's appearance, or nil to inherit the app
window is therefore dark while its + HUD and history chooser show the incognito
palette's light half.

Parc matches this. Ordinary browser windows set no appearance, so they match the
incognito theme does. The HUD and history chooser windows set neither an
appearance nor an `appearanceSource`, so they keep AppKit's default, the app,
even as children of a Dark Aqua window. `tests/SidebarPlusMenu` checks that a
HUD over a Dark Aqua parent in a light app resolves Aqua and draws the light
window's HUD and history chooser take that palette
(`IncognitoWindowTheme.paletteTheme`), not its Space's. The incognito
theme's opaque background and palette are in
[window appearance](window-appearance.md#private-window-theme).

| --- | --- | --- |

Titles use the configuration's `menuItemFont`, system 13 medium, and shortcuts
The shortcut string appends the key text to the joined modifier symbols with no
separator, uppercases the result and builds one attributed string with a single
character is kerned, including multi-character keys such as F12. Parc kerns its
keyboard-navigation.md "Shortcut key text"). Separators sit in
bands of 8 + 1 + 8 points (`separatorInsets` 8, 4, 8, 4), so the six-row card
is 290 points tall.

colourless case was not recovered; Parc uses `ThemeChromePalette`'s system
fallback (`controlBackgroundColor`, `quaternaryLabelColor`,
`secondaryLabelColor`), as its tooltips and history menu do.

bytes), a P3 primary of hue 144.7° and saturation 0.90 reproduces the card
(0, 15, 6) exactly, the highlight and separators (34, 76, 50) within 1 and the
shortcut (97, 128, 110) within 2. Title and shortcut glyph extents, separator
rows and highlight bounds match the screenshot to the pixel at 2x.

## Dock plus button

`TranslucentButton` whose item is `.animatedIcon(.plusMenu(isOpen:))` at
style colours do not change with the menu.

  symbol: two continuous rounded rectangles framed round(14.4) × 2 (size table
  rotates the pair π/4 clockwise about its centre into an ×, with
  `.animation(.spring(response: 0.2, dampingFraction: 0.5), value: isOpen)`. It
  overshoots to about 52° and settles in roughly 0.4 s; there is no crossfade
  or scale.
  padding 8, a radius-6 continuous plate that is clear at rest, GrayA4 hovered
  and GrayA5 pressed; a GrayA11 glyph at rest, hovered and open, GrayA12
  pressed; a 0.95 press scale on spring(0.3, 0.6) and a 0.1 s ease-in on hover.
  theme, one coverage at the crossing.
- **Hover while the menu is open.** The style's `MouseInsideModifier` gets
  `mouseEnteredAndExited | inVisibleRect | enabledDuringMouseDrag` plus
  `activeInKeyWindow` (`0x601 | 0x20`). Its coordinator has only the entered,
  exited and moved handlers, with no key-window observer. While the key HUD
  is open, the plate therefore follows AppKit's tracking events alone, as
  shows no plate under the ×.

Parc renders this as `SidebarPlusButtonFace`, a SwiftUI view in the Library
entry's non-interactive hosting view over `footerMore`, which keeps the
pointer, keyboard focus ring, tooltip and accessibility. `SidebarView` feeds it
`ActionButton`'s hover, NSButton's press highlight (`ActionButton.onHighlight`),
the HUD's `onVisibilityChange` and the theme's light/dark GrayA set. When the
HUD closes, `ActionButton.refreshHover()` re-reads the pointer, because the
tracking area sent no exit while the HUD held key. Nothing is hovered while
dragging it off the + clears the plate and dragging it back on restores the
hover. NSButton's press tracking holds back those exit and entry events, so
`ActionButton.highlight(_:)` re-reads the pointer on both edges: pressing or
dragging back onto the + re-hovers it, a press dragged off drops both the
GrayA5 and the GrayA4 plate, and a release inside keeps the hover. The sidebar
toggle's TranslucentButton face shares this. Parc fills both bars as
screenshots show. Reduce Motion switches the +/× change without animation (a
Parc adaptation; `PlusMenuIcon` does not read it); hover and press animate as
the Library entry's do.

## Today divider Clear and New Tab press

has items ([Today divider](parity.md#today-divider-clear-and-new-tab)). Its

  sibling in the same stack, shortens at once on a reveal and lengthens only
  after the fade-out. Parc's `SidebarView.updateClearReveal` does the same
  fade's completion hides Clear, so leaving during the fade-in still fades it
  read Reduce Motion here, and neither does Parc.
- **New Tab.** `NewTabCellView` is a `SidebarBouncyClickCell`. `mouseDown:`
  action. The bounce sets the layer's anchor to its centre and adds a
  `CASpringAnimation` on `transform` under the key `press_bounce`. It springs
  from the presented transform to a 0.992 scale while pressed, kept on
  completion with fill-forwards, or to identity on release, removed on
  0.2: stiffness (2π / 0.2)², damping 4π × 0.5 / 0.2 at unit mass, and a
  duration of its settling time (0.469 s). `performBounceAnimation` has four
  callers, the two `mouseDown`s (press in) and the two `performClick` bodies
  (press out); `NewTabCellView` and its `SelectableCellView` superclass
  the release point through a vtable slot, inferred to be `performClick` [I].
  So a press dragged off and released elsewhere leaves the row at 0.992 until
  the next completed click on it, and moving out and back during the press
  changes nothing. `SidebarNewTabRow` matches: NSButton's highlight springs it
  in unless a press is already held, other highlight changes are ignored, and
  its action springs it back before sending New Tab. It scales about the
  centre with AppKit's anchor in place, and a held press is re-centred without
  held press is dropped without animation when the sidebar shows another
  Space is unresolved.
- **New Tab as the current item.** While a new-tab command bar is open the
  cell is the current item ([New Tab selected look](parity.md#today-divider-clear-and-new-tab)).
  layer's animations and sets the title, hint and plus colours directly, and
  shadow without a transition. The rows that stop being current switch the
  same way. Parc's `SidebarNewTabRow.current` and `SidebarRowBackgroundView`
  do the same.

## Reference mechanism

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
These addresses belong to that artifact, not the later installed reference.

  container, window contents container, layout state and
  `currentSidebarAnimationUUID`. `SidebarPresentation` has locked, floating and
  and reads `accessibilityDisplayShouldReduceMotion` before anchored animation.
  `NSAnimationContext`, implicit animation and a **0.08 second** duration. They
  move the sidebar and set the window contents frame, then lay out its subtree.
  Animation transaction before entering the animated group.
  `SplitViewDraggerHandleView` children and invokes that same inset helper;
  these calls do not establish a new renderer snapshot or resize-throttle owner.
  points **(0.25, 0.46, 0.45, 0.94)**.
  frame origin/bounds. Preset 5 loads response **0.18** and damping ratio **0.8**
  stiffness `(2π / response)² × mass`, damping
  `4π × dampingRatio × mass / response`, and uses `settlingDuration`.
- The Library's width change is a separate group of the same controller:
  animation, **0.2 seconds** and the same timing accessor, then lays out the
  container, moving the Library edge and the page together. Parc runs it as
  `SidebarMotionController.Style.libraryWidth`
  ([Library width](space-management.md#library-width-on-the-spaces-page)).
  and compare the captured UUID to the current UUID before completing hidden
  separate transform animation. The complete reference reversal/velocity
  algorithm is not recovered.

REA raw-slice evidence
`ev_c9ce84858edd449ebebbf22a7dbc2aa141f889e4f3648bced34e907dd981162a`
Raw analysis cannot resolve its out-of-slice data/imports; the retained original
Mach-O instructions, selectors and constant tables establish the parameters
by REA/Ghidra 12.1.4, evidence
`ev_85f7b84cb0fe5f972ee83358ca9adde08d426052660bb572c27b5800fab3cdf3`;
its original selectors establish the constraint ownership. Recovered
disassembly/pseudocode is not original source.

### Transition participants and content sizing

A second bounded pass over the same artifact settles what the anchored groups
contain. Annotated llvm-objdump with Swift field metadata and ObjC ivar lists
was verified by REA/Ghidra 12.1.4 decompilation of exact raw function slices,
annotated with the binary's own selector-reference and ivar tables: groups
`ev_e70336b4a6ddbf1fc2839e7e94df74f25d98044235107fc41690c82e3c5c7087` and
`ev_db587c6051f452c1b52198f94198bdac49d5ea27879fc131744d23552e22ae64`,
preparations `ev_7b05eccf862e76fa3d5c8a52017a9b91e0c40c3056e893c974fa28374c1c7d64`
and `ev_cbd8fa0d6a39e6a862dd6c97d22335077efa4384fffe1330fb0a6a99ffa4b0f4`,
finisher `ev_f4592a41ca8a97b4684fb64cca440edb3af58705dde83f423a4b292dfb324474`,
animation-state consumer `ev_6ab12b6f429c4fd3a98567be70678562b7ac415d94524cb332d73513de83c003`
and content-resize flags `ev_84af23dcc971c2745d12e205d09c1cbab73a81f1a9d5e2a9ab1625f58137d454`.
Raw slices truncate where a branch leaves the slice; the instructions establish
the remainder.

  view frame with origin.x replaced, force the contents leading constraint
  call `layoutSubtreeIfNeeded`. They contain no hidden, background, corner,
  alpha or window-button selectors.
  `currentSidebarAnimationUUID`, publishes `isSidebarAnimating = true`, hides
  the resize region, updates the contents constraint, sets the container's
  sidebar out of the floating container, unhides it, makes the same state
  changes, lays out and flushes a CATransaction, then enters the group.
  still matches, clears the UUID, `isSidebarAnimating`, the transition state
  remove in-flight animations, read presentation values or reconstruct
  velocity on reversal; a new UUID only makes the predecessor's completion a
  no-op. The floating spring sets no initial velocity.
- `isSidebarAnimating` has one consumer: WindowViewController's
  the sidebar animates, resizes or pages. `isAnimatingResize` hides split
  divider handle backgrounds (the handle's window-background view, not its
  grip) and defers the contents-constraint update.
  frozen zero-duration transform hold used only while Home/Spaces paging is in
  progress. It is not part of Cmd-S motion.
- `WindowContentViewController.contentResizeMode` (intrinsic, throttle,
  locked) follows `contentSizeThrottleFlags`: fullscreen/live window resize,
  split divider drags, split interactive editing and the sidebar-width drag
  final web-content frame once inside the group, exactly as Parc does. Throttle
  mode is renderer-acknowledged backpressure, not a timer; Parc applies it to
  the width drag ([page size during a width drag](sidebar-resize.md#page-size-during-a-width-drag)),
  and ⌘S keeps its panes intrinsic.

⌘S presses on the same existing page, returning to its original locked state.
The settled 1470×831 window showed a page origin of approximately 228 points
when locked and 9 points when hidden, with the same top/right/bottom inset and
rounded page corners. Still captures do not measure a duration, curve, frame
pacing or interruption. Hidden-sidebar hover timing and geometry are
recovered separately below; the earlier 150/300 ms delays, 8-point hover strip and
6-point exit buffer were Parc choices and are gone.

## Parc adaptation

Parc uses the two recovered motion definitions inside `NSAnimationContext` and
the presentation (`SidebarView.isPresented`), floating surface and tracking
state at the old geometry, without native, payment, Easel or command-bar
refreshes. Only a reveal from hidden then lays out and flushes that state,
Inside the group a geometry-only pass moves the sidebar origin, the Library,
the page host and its [card shadow](window-appearance.md#page-card-shadow),
extension side panel, capture indicator, loading bar, Peek and find frames,
followed by one `layoutSubtreeIfNeeded`. The same pass serves ⌘S,
sidebar-width drags and the Library width group
([Library width](space-management.md#library-width-on-the-spaces-page)); hidden drawing views are held off AppKit's
per-frame resize for the group and the floating surface's theme canvas is
pinned, so the main thread stays idle while the slide runs, except for the
blur, and while docking the behind-window material, in floating ↔ locked,
([frame pacing](#frame-pacing)). The header's traffic lights
so they move with the sidebar and need no geometry input of their own; which
set of lights shows is decided before the group and never at completion. The
newest generation's completion runs the single full pass that settles the
presentation and performs the native layout synchronization, payment refresh
and other side effects. AppKit
owns interpolation of the real native hierarchy. The renderer still receives
the final native layout once; there is no display-link loop sending
interpolated viewport sizes to Chromium, no copied screenshot and no second
page owner.

in its floating container off-screen ([accessibility](sidebar-accessibility.md),
height − 10; and, hidden, x − width − 10 at the floating y and height once
settled or during a floating transition, x − width − 10 at the locked height
`CGRectGetMinX(bounds) − width` when it is set and `layoutState == .spaces`
started, because only the preparation, while the presentation is still hidden,
places by it. `SidebarPresentationFrame(_:inMotion:floatingSurface:revealsAnchored:)`
makes that choice for every pass and `SidebarPresentation.presents(inMotion:)`
decides `SidebarView.isPresented`; `tests/SidebarMotion` tables both. Settling
therefore moves a ⌘S-hidden sidebar into the floating geometry off-screen, as
sidebar (Library, popup, page full screen) hides the container. Because no hide
or unhide reaches the sidebar's views, `SidebarView.isPresented` turns false in
the full pass that settles a hide and true in a reveal's preparation, each
after the sidebar's frames are set, and the header lights and the dock drop or
re-test the pointer there. A reveal's preparation still has the sidebar
off-screen, so its completion re-tests them once more where the sidebar
arrived.

A floating surface ([floating surface](#floating-surface)) stays drawn through
its whole transition, including floating→locked. Inside that group its shadow
and blur fade out and the window's behind-window material, prepared before the
its model frame when it draws, so a sliding surface is not re-sampled until
the transition settles.

Floating requests temporarily install the recovered spring on the participating
view definitions, then restore each exact animation dictionary after the group.
`NSView` uses AppKit's public `frameSize` key. This key mapping is an explicit
adaptation. Unchanged page geometry does not acquire a floating resize.

A request advances its generation before preparation, so a predecessor that
finishes during the flush cannot finalize the new request. AppKit receives the
current presentation when a transition reverses; the controller does not cancel
reversal. Only the newest generation may finalize the presentation. Floating
dismissal keeps the floating background until the current animation finishes.
(see [sidebar resizing](sidebar-resize.md#sidebar-chrome-spacing)); popup and
Archive geometry remain independently owned.

Chromium's resized frame arrives at an unsynchronized moment in both
browsers; its timing against the 80 ms curve is left to the
[runtime acceptance](#runtime-acceptance-side10). Drawn
views whose width follows the page are pinned so they join the group's single
animation (see [drawn content](#drawn-content-inside-the-group)). The Split
handle's window-background view, Parc's split gaps draw none, and grips stay
transition hooks. See the
[Split background contract](split-groups.md#sidebar-transition-grip-backgrounds).
Disabling item-preview hover during the transition is wired with the preview
controller.

The controller retains the actual AppKit geometry-animation objects on existing
view backing layers. Cancellation removes an animation only while the same
object still owns that key. A replacement by another component survives. This
walk does not change layer backing or inspect Chromium's compositor-layer tree.
It also preserves unrelated properties and the existing responder.

A resize, Archive/fullscreen or shelf/panel geometry change settles the current
transition at the authoritative model geometry. Explicit mouse-down input also
settles before native hit testing; no event is consumed, replayed or retargeted.
This deliberate hit-testing adaptation avoids acting on a different logical
control behind an in-flight layer. Keyboard toggles can still reverse directly.

Hover has no timers of its own in the presentation owner: the region tracker
publishes state changes and the controller applies the recovered activation
(below). Menus, sheets, pointer presses, popovers, the command bar, a focused
sidebar control, previews holding the sidebar open and resizing defer only a
dismissal; each of them refreshes the pointer when it ends, and the activation
is then recomputed from the current states. A theme or extension popover that
took key is still key while it closes, so its end waits for this window to
become key again, when the tracker re-tests with the floating zones. Hiding a focused
sidebar in the key window explicitly returns selection/focus through the
existing native path; in a window that is not key it makes the window the first
responder, since the hidden sidebar stays unhidden and would otherwise keep a
focused control off-screen. Focus that entered the sidebar while it slid away
goes to the window when the hide settles, as hiding the container did (not to
the page, as below); no saved-focus restore puts
focus back into it (`SavedFocus.mayReturn`), and a row's Rename floats it in
first ([accessibility](sidebar-accessibility.md)).
An animation’s completion never requests page focus or changes selection.

Reduce Motion skips both motion definitions. Enabling it during an animation
settles immediately, and shutdown removes only this controller’s animations and

## Floating surface

This section covers the look of the floating sidebar's own surface: its
corners, edge, shadow and material. When the sidebar floats is covered
elsewhere; a window with no tab floats it too (the empty-state increment).

(annotated disassembly, the cross-reference index and Swift field metadata,
plus witness tables and constants read from the binary), with no new
screenshot, at about 0.8 pixels per point.


- [D] Its fields are `shadowView` (`NSImageView`), `blurView`,
  `behindWindowBlurView` (`NSVisualEffectView`), `themeView`
  (`WindowBackgroundContainerView`), `fakeTitlebarView` and `sidebarView`.
  pinned to the edges, except the shadow, which is pinned 10 points outside on
  scaled axes independently, at alpha 0.2. The image is 40 points with cap
  insets 19, 19, 20, 20: a black ring, a 10-point ramp up to about 0.37 alpha
  around a clear, 10-point-radius hole. It is copied unchanged into
  `Resources/FloatingSidebar`.
  `NSVisualEffectView` with the given blending mode and material,
  square 2r + 1 points wide, stretched from its r-point caps, with r = 10 − 2
  popover (blending 1, material 6). `behindWindowBlurView` is behind-window
  window background (0, 12) and starts hidden.
- [D] The initializer sets `themeView`'s `contentFillMode` to 1,
  Each setter forwards to the container's renderer through its
  `WindowBackgroundViewType` witness; `canDisplayTranslucency` is at `+0x40`.
  hides its `translucencyView`. The legacy renderer stores the flag in its
  view model. So the theme adds no translucent material of its own and shows
  the first.
  border width 1 and border color `SidebarBorderColor`. In the catalog that
  color is sRGB white at 0.3 in both Aqua and DarkAqua. A layer's border
  draws over its sublayers.
  at 1, the shadow at 0.2, `behindWindowBlurView` hidden. Locked look:
  `blurView` and the shadow at 0, `behindWindowBlurView` at 1. For a floating
  transition: redraw policy 2, `behindWindowBlurView` unhidden at 0 with a
  theme-chosen material.
  0.08 s and the cubic. It then sets the container frame, `blurView` alpha 0,
  shadow alpha 0 and `behindWindowBlurView` alpha 1, forces the contents
  constraint, sets the contents frame and lays out. It makes no border or
  corner-radius call.
  sets `blurView` to 1 and the shadow to 0.2 and hides `behindWindowBlurView`.
  Only four functions call the `shadowView` getter: the initializer, the style
  group fades the shadow in: a sidebar that starts floating, from hidden or
  from locked, shows it at 0.2 before its slide.
  back over about 9 points. The 1-pixel edge is about 15 levels brighter than
  darker than its locked sidebar at the same heights.

**Parc.** `ThemeRendererView.floatingCornerRadius` is the floating surface
(`FloatingSidebarSurface` holds the recovered values). Setting it to 8 does
the following:

- The material becomes `blurView`: within-window popover, masked by the same
  rounded image.
- The theme canvas rounds and clips to 8.
- The view's own layer gets the 8-point corner and the 1-point
  `SidebarBorderColor` edge.
- A `FloatingSidebarShadowView` is added under the material. It shows
  `CellDropShadow` at 0.2, autoresized 10 points outside the view, passing
  clicks through and hidden from accessibility. It is created on the first
  draws the same image as layer contents stretched from its cap insets
  instead: with the real artwork, an `NSImageView`'s internal image view was
  resized and redrawn on every display frame of the dock (7 per slide in
  `tests/SidebarPacing`) [C]. The layer version gets one bounds animation, and
  it renders identically, with no differing pixels in the visual harness [C].
- [C] AppKit turns `clipsToBounds` on once a view's layer has a corner
  radius, so the surface turns it off again, or the shadow would be clipped.
  Its content therefore clips itself: `layoutChrome` gives the sidebar the
  same radius and `clipsToBounds` while floating, which keeps a Space swipe's
  neighbouring theme inside the corners. A locked sidebar is unclipped, as
  before.
- A Space swipe on the floating surface is drawn by the surface's one canvas
    `WindowThemeBackgroundContainerView.Configuration`: `single(_:)` or
    `transitioning(from:to:progress:)`, which comes from
    `WindowThemeBackgroundConfiguration.transitioning(from:to:progress:shouldCrossfade:)`
    (Swift field metadata). Space paging builds the transitioning case in
    to the window's background
    ([Space paging](space-theme-rendering.md#space-paging)).
    second theme view.
  - [D] Its Metal renderer mixes the two themes' inputs by the progress: the
    straight layer colours in the gradient pass and the two textures in the
    overlay pass. `shouldCrossfade` (set when the sidebar mode is
    `noChrome`) is read only by the SwiftUI renderer.
    It drives the end-of-pages edge feedback (`EdgeFeedbackView`, lazy getter
    [navigation](navigation.md) cited it as the theme handoff.

  Parc's canvas is translucent: its gradient alpha is 0.2 + 0.55 ×
  intensity over an underlay. So a neighbouring canvas stacked over the
  current one did not crossfade the two. The pager's commit swaps current
  and neighbour mid-swipe, so the old stack jumped (29 levels in the check
  below).

  Now `SidebarView` hands the window's surfaces (`onPagingTheme` →
  `ThemeRendererView.pagingTransition` on the root and on the sidebar's
  surface), locked or floating, the themes of the pages either side of the
  pager's offset on the new Space but not the strip's position, so the
  transition, and the picture, stay the same. That holds past one page
  too: a long drag, or a second page during the first one's spring. A
  locked sidebar has no surface of its own, so the window's surface pages
  behind it. The transition's pipelines
  are built on the first draw that pages. Earlier the canvas drew the
  premultiplied sum (1 − p) × current + p × neighbour while floating, and a
  locked sidebar faded the neighbour's own view and material in over the
  window's. The window's surface stayed on the current Space until the
  commit, so its margins jumped to the new theme there.
- The floating blur stays as it is through a swipe between coloured Spaces,
  commit included, even between a light-style and a dark-style Space.
  - [D] A theme view's translucency (`WindowBackgroundTranslucencyViewAppKit`,
    Only when the `to` style differs does it add a foreground material, once,
    with the `to` style at alpha = progress; otherwise it hides that
    foreground. The light, dark and auto styles are materials 1, 2 and 12
    not read there.
  - [D] The floating `themeView` hides that translucency (above), so its
    second material never shows.
  - [D] `blurView`'s material is set only by its factory. Only the
    initializer, style setter, dock group and finisher reach its getter, and
    none of them sends `setAppearance:`.
  - [D] The cross-reference index lists 25 `setAppearance:` selector
    references and 4 direct sends, 29 sites in all. The 13 whose targets
    were identified are in nine functions (each send's address follows its
    function):
      for private windows);
      makes on the view itself;
    - each `SidebarSpaceViewController`'s view, from the same appearance:
      both above the blur;
    - a view in the tab-overflow indicator's code, copied from the window's
  - The other 16 sites' targets were not traced. They are one selector
    appearance in every Space, and a swipe changes only the theme drawn
    over it. Ruling out a view between the window's content and the floating
    container needs those 16 targets.

  Parc used to give the floating popover its theme's light or dark side.
  Editor themes are automatic, so their side already matched the window's
  appearance, though not its Increase Contrast variant. Only a stored forced
  Light or Dark appearance could differ, so only a swipe to or from such a
  Space flipped the blur's tint at the commit. Now, while the canvas draws
  the theme's colour, the floating material takes the window's effective
  appearance (`updateMaterialAppearance`) and keeps it through the swipe,
  with no second material view. Where the blur is the whole backdrop (an
  uncoloured Space, or no Metal), it keeps the theme's side, which the
  palette's text was chosen for (`ThemeSurfaceStyle`). It takes the window's
  own appearance whenever the window is on that side. So an automatic
  Space's blur keeps the window's Increase Contrast variant, coloured or
  not, and a swipe between coloured and uncoloured automatic Spaces leaves
  it unchanged. At rest the theme's side also still sets the window's own
  swipe that surface's base takes the left page's style and a second
  material the right page's ([Space paging](space-theme-rendering.md#space-paging)).
- Nil restores the window's own surface: behind-window material, no mask,
  edge or corners, and the shadow hidden at 0.2, ready for the next float.
  Each property is written only when it changes.

Earlier, the floating surface was the window's behind-window material and
theme with a 10-point clip. It read as the window background, with no shadow
or edge.


- Preparation. `SidebarTransition.docksFloatingSurface` holds only for
  floating → locked, and the preparation pass sets
  `ThemeRendererView.preparesFloatingDock` from it. The surface then unhides
  blur and below the theme canvas. That material is created on the first
  dock: behind-window, emphasized, masked by the same rounded image, and in
  the window surface's own material and side (`ThemeSurfaceStyle`). The
  blur and shadow are untouched.
- Group. The geometry pass sets `docksFloatingSurface`. The blur and the
  all three on the group's 0.08 s cubic [C: one opacity animation each, with
  the group's duration].
- Settle. The settled pass ends the floating surface
  (`floatingCornerRadius = nil`) and clears both inputs. The blur returns to
  alpha 1 as the window's material, the dock material hides at 0, and the
  shadow hides at 0.2, ready for the next float. The dock ends on the
  window surface's own material under the same theme, so the settle no
  longer changes the fill. Only the corners and edge go there: Parc used to
  completion moves the sidebar out of its floating container at that point.
- A full pass during the slide, such as a theme or chrome refresh, keeps
  the dock: it sets `docksFloatingSurface` while the surface is still drawn
  for a locked presentation, and ends the preparation. The cross-faded
  materials stay.
- Any other pass clears the dock. The settled pass and a new transition's
  preparation, including a dock reversed into floating by the empty-window
  rule, show the shadow at 0.2 and the blur at 1 and hide the dock material.
  Clearing the dock also removes the three fades, so a reversed dock floats
  again at once instead of finishing them.
  (above). Undocking has no material fade [D]. Both blur views are
  thunks over it), which only the dock group and the finisher call. The
  cross-reference index).

Adaptations in the dock:

  (policy 2) for the transition. Parc keeps the container's own policy:
  and re-render the pinned theme canvas ([frame pacing](#frame-pacing)) [I].
  creates it on the first dock and gives it its layer at once. A material
  view added in the preparation's turn otherwise has no layer until the next
  commit, and the group cannot fade it in [C].
  gives 1, 1 gives 2, anything else 12, and so does the theme
  surface's own style, which uses only 1 and 2, so the dock ends on the
  Parc's uncoloured and automatic themes is not decoded [I], so Parc never
  shows 12 here.

**Checks.** `python3 tests/FloatingSidebarSurface/check.py` (in
`scripts/test.sh`) covers the following:

- the constants and the copied artwork with its provenance hashes;
- the mask's shape;
- every floating, docking and settled property of the production
  `ThemeRendererView`. The dock material is absent before the first dock.
  The preparation places it over the blur, unhidden at 0, in the window
  surface's behind-window material and side, masked to 8. The group gives
  the blur, shadow and dock material one 0.08 s fade each. A reversed dock
  leaves no fade in flight, and the dock material is hidden at 0 after the
  settle and on the next float;
- a layer-tree render showing the shadow outside an unclipped surface and the
  edge just inside it. Removing the unclip line makes this assertion fail;
- the sidebar clip toggling;
- a swipe's commit, rendered by the real canvas of the floating surface and
  of the window's own, in a window parked off-screen. At p = 0.37 the
  picture before and after the swap differs by 0 levels (at most 1 allowed).
  from the old crossfade; built against the previous renderer, this check
  fails. The surface is not square, so the gradient's line matters. The ends
  are each theme alone. A swipe into a coloured Space shows even from an
  uncoloured one and ends on that Space's gradient as it rests. One towards
  an uncoloured Space fades the theme as a whole, the same from either side,
  and a commit with an uncoloured Space on either side changes at most 1
  level. Past one page, with neither page the surface's own theme, the
  picture is the same. A swipe's end
  in an uncoloured Space clears the canvas rather than keeping its last
  frame. A control composites the old stacked canvas over the same
  backdrop: it jumps 29 levels;
- the floating blur, in an off-screen window that is never ordered in:
  - In an uncoloured dark-style Space, where the blur is the whole backdrop,
    it stays dark in an Aqua window.
  - Through a swipe between coloured light-style and dark-style Spaces,
    commit included, the surface has one blur. Its material, blending,
    alpha, visibility and appearance (the window's) stay as at rest, and
    the palette still gives the dark Space's text Dark Aqua.
  - The blur follows a change of the window's own appearance. With none
    set, it follows an app appearance change the window inherits, and back.
  - A locked surface keeps its theme's side.
  - With no window appearance set, a swipe between coloured and uncoloured
    automatic Spaces keeps the blur's appearance name equal to the
    window's. This only tells the variants apart when the system's Increase
    Contrast is on: AppKit returns plain Aqua when that variant is named [C].
  - Other appearances compare by their Aqua or Dark Aqua match, so Increase
    Contrast passes.
  - Built against a renderer that gives the floating blur its theme's
    side, the swipe fails at the first step after the commit. With the
    window's appearance in every floating state, the uncoloured Space
    fails;
- the controller and `SidebarView` lines;
- that the packager copies all of `Resources`.

`tests/SidebarPacing` mirrors the passes and draws the shadow with its real
artwork. Its budget holds: no per-frame view work, and the shadow laid out
at most once per pass. In floating → locked it gets one opacity and at most
one bounds animation (asserted), and the blur and dock material one 0.08 s
fade each. Only shown materials stay outside the per-frame budget. A
locked → floating run after a dock keeps the hidden behind-window material
in the budget, so the hidden-view hold must keep it off AppKit's per-frame
resize. A further
check covers four states. A full pass mid-dock keeps the faded shadow, the
corners and the cross-faded materials. The settled dock is square, with the
blur at 1 and the dock material hidden. The next float has its shadow, and
so does a dock reversed into floating, which leaves no fade in flight.

**Gaps.**

  What it looks like live (the page behind, blurred under the popover tint and
  then the theme) cannot be captured off-screen, and neither can the dock's
  cross-fade into the behind-window material. The visual harnesses
  approximated both, so the fill must be judged in the running app. The
  confirm it.
- *Forced coloured Spaces' legibility.* Under a stored forced Light or Dark
  Space's colour, the floating blur follows the window, while the palette
  keeps the forced side's text. A forced-Dark Space's light text in an Aqua
  window therefore sits mostly on a light popover. Review estimated that its
  contrast falls from about 10:1 to about 4:1 at intensity 0.8, and under
  so a dark colour's light text would sit on a light blur there too.
- *A swipe to or from an uncoloured forced Space.* That Space's blur keeps
  its stored side for its text. So when that side differs from the
  window's, a swipe between it and a coloured Space still changes the blur
  at the commit. The blur reads the current Space's theme, not the
  transition's `from`, so a drag past one page changes it at the commit
  window there too [I],
  forced appearance keeps its text on its own side.
  Parc's canvas samples the window gradient at its own position and draws
  no material of its own.

## Hidden-sidebar hover regions

annotated disassembly, Swift field metadata and ObjC method lists. A function
cited with an evidence ID was also decompiled from an REA/Ghidra 12.1.4 raw
slice; raw slices truncate where a branch leaves the slice, and the
instructions establish the remainder. A claim cited by address alone rests on
bounded disassembly only (Ghidra timed out or was not run for it); an
independent review re-read most of those listings.

  over the controller's view, with its `windowBounds` set from the view bounds
  (`ev_b0ef20e232c6740dbc2152b345d74c06d5900445f519c129242ab25eac8e9f7a`)
  lingerRequirement, trackingFidelity}`: `WindowTrafficLightRegion`,
  `InnerLeftEdge`, `InnerTopLeftEdge` (fidelity `hasStopped`, linger 0.15 s),
  hasLingered, hasStopped.
- Geometry, in the unflipped view with the uniform 10-point
  `WindowHoverTracker.State.contentInsets` (`L = 10`; the state mapping closure
  inset fields):
  `InnerLeftEdge` is x 0, width 0.6·L while the pointer is in the window but
  `ev_eaa45672257a2d30d48eb4fe7b3cbc08d3217d6863c5464c1335018e214804d0`,
  `OuterLeftEdge` is 50 points left of the window, 250 while the pointer is in
  `ev_59d2ce0fd8d53bf62d3dea07cef99953424a9d03696f49c1a78a0ba5dfeb3106`;
  `ev_c857845f3700c6da28c8aeec31c10f9524896cdde10324c1c82b3fcc730630bd`,
  Both left edges are H − 16 tall while `showingToolbar`
  `ev_de87394f111d797cdae3a6371a7d6a13444eec5aeb23f793a7175f4d47d24f0c`).
  `ev_ee86f925ef41ab1a50059bf2ce899770a7bead6df3a8c7c121e820fd474d5efe`;
  `ev_e805451b2f358c44c9ff4bc1e38b8fed241b1785a486bf03f0e744043f082b3f`;
  min(window maxY + 50, menu-bar minY), or nothing when that is 10 points or
  `ev_29eb985b83a3f880cba1eccc03c903121fbff1dec22c9da9615c00a582ce2bbb`).
  The menu bar is placed at screen-frame height − `menuBarHeight`
  `ev_5113afda704276827e900529f40d252588e1e09cfc33e03b4d93049e8edf6cd2`),
  without the screen origin.
- Disassembly only unless an ID is given: `HoverRegionTracker` tests each
  region's rect, converted through its view and window to screen, against
  `NSEvent.mouseLocation` on every event of a local `.mouseMoved` monitor
  sets inside and leaving sets none immediately; moving inside keeps the state
  `asyncAfter(lingerRequirement)`; when it fires, a region still inside
  app is active and the window key (`appDidResignActive` /
  `ev_83c0e4ac6c10a7f0ab05c0fafe0f0b9b06a53953a5ee1b12402fff09e3c472c5`)
  clears the flag at +0x19 and the tracking flag at +0x18 and, when it was
  (`ev_ba0353edebd4e123b960b41bd550662afb471305b2c928a872b83d47ac6be1f2`),
  whose stop branch drops the listener (+0x20). The instructions after the
  (`ev_55287555b91548b454ad40ea014db2410803a56022b676faceaaca1f097cb7ff`: a
  new UUID and state none for each record; `strb wzr, [x20, #0x41]` at
  resignation reports every region as none, the activation becomes false and a
  hover-floating sidebar hides. Dropping the tracker for a resize is silent:
  vtable +0x100 setter (read as its delegate) before clearing +0x20. After each
  change the delegate sends `WindowAction.updateHoverInfo(offLeftEdge:,
  windowTrafficLightRegion:, innerLeftEdge:, innerTopLeftEdge:, sidebar:,
- Disassembly only unless an ID is given: `WindowState.sidebarHoverRegionActive`
  the region stays active while the sidebar, outer-left or inner-left zone is
  traffic-light and top-left zones count unless both of these hold:
  (`ev_e8af67835987d2b2be4db85b0be0b837c561d08ec177a2c357730693d9af0562`),
  which is
  value was not recovered. The stored input is written by a dedicated reducer
  dispatches that action was not recovered. The presentation getter
  delay or debounce constant appears in this path.

Parc's `SidebarHoverTracker` reproduces the tracker, listener and timers with
these values, including the all-none report when the app resigns active or the
window resigns key and the silent drop while resizing. `SidebarHoverZones` and
`SidebarHoverActivation` reproduce the geometry and activation
(`Sources/ParcCore/SidebarHover.swift`). Zones refresh as soon as the bounds,
presentation, width or toolbar change, so a floating zone widens with the
request rather than after the spring.

`SidebarHoverPresentationRule` is Parc's controller rule, and its update of the
recomputes the activation from the tracker's current states on every
application: each tracker report, each guard's end, the end of a floating
transition and a resignation. The stored input counts only while the sidebar
floats and is cleared when it leaves floating, so a hidden sidebar always
needs the reveal threshold. A hidden sidebar becomes floating when the
activation holds in the key window; a floating one hides when it ends.
Owner guards (sheet, popover, command bar, navigation history) always defer
that dismissal. Interaction guards (focused sidebar control, pointer press,
holding preview, menu) defer it only in the key window, so a resignation still
dismisses past them as Parc did before. A deferred dismissal holds the stored
input, and the guard's end then applies the keep-zone threshold to the current
pointer.

Adaptations and open points:
- Parc treats its browser toolbar preference as `showingToolbar` and as the
  +0x70 nil condition are not reproduced.
- Fullscreen is the window's fullscreen style.
- The tracker sets `acceptsMouseMovedEvents` so moves beyond the frame arrive;
- A non-hover reveal (theme editor, rename, reveal item, keyboard session, the
  8-point click) marks the region active, so the sidebar stays while the
  pointer remains in a keep zone or a guard holds it.
- Containment settles in several passes: Parc re-tests containment against the
  that rect update (vtable +0x130, last argument 1) re-tests at once was not
  recovered. Extra passes run only while `tracking.info` is still changing.
  conversions on every local mouse-moved event. Parc caches converted screen
  rects until hover info, `window.frame`, `view.bounds`, screen frame or menu-bar
  height change, or `setNeedsRefresh` runs, so a pointer that stays in the same
  zones does not rebuild or convert. Linger, stop, edge sizes, reveal/dismiss
  and the all-none resignation report are unchanged.
  and schedules `asyncAfter(0.08)` on every move; only the firing whose captured
  time still matches promotes. Parc keeps one pending stop work item and re-arms
  it to 0.08 s after the latest move. The observable stop is the same; the extra
  cancelled-by-token work items are not.
- When resizing ends, the new tracker's first report waits for the next
  main-queue turn, or for the gesture's closing pointer refresh after its
  commit layout. It therefore never changes the presentation inside the
  gesture's commit.
  a listener restart does not cancel a pending linger.
  zone is held. Its action was not identified, and Parc does not reproduce it.

No functional browser test ran.

## A window with no tab keeps its sidebar

meanings recovered for [saved tabs](saved-tabs.md) and [Peek](peek.md):

  `SidebarPresentation` (locked, floating or hidden) in the getter
  +0x21 and +0x22 are `isKey` and `isMain` in WindowState's `==`
  return floating; their meanings were not traced. Next it calls
  content, else the split's focused content, looked up in
  `windowContentSidebarItemMap`. When that is nil it reads the presented
  that path, and no branch before it can hide.
  floating sidebar over the full-width empty content, and it stays.
- [I] Once an item is active, the same getter's later checks and the hover
  activation decide again, so the sidebar hides once the pointer leaves it.

presentation, so `EmptyWindowSidebarRule` applies the getter's no-item branch
to requests and renders:

- `BrowserWindowController.setSidebarPresentation` passes every request
  through `EmptyWindowSidebarRule.presentation(for:noActiveItem:)` before
  anything else. In a window with no tab, ⌘S, the drag collapse below 82
  points, a click outside the floating sidebar and every hover dismissal
  (pointer away, key or app resignation) therefore float instead of hiding.
  The hide-only side effects (+ menu dismissal, sidebar command bar
  dismissal, focus return) do not run. Hiding during Space creation still
  cancels it, and the rule is applied again afterwards, since the cancel can
  return the window to having no tab.
- Each render ends with `refreshEmptyWindowSidebar`, as does closing the
  Library: a hidden sidebar in a window with no tab floats (the restored
  hidden record, the last tab closed or archived, a Space without tabs), and
  the render that gives the window a tab again re-applies the hover rule to
  the floating sidebar, which then hides when the pointer is away.
- "No active item" is `EmptyWindowSidebarRule.holdsSidebar`: no current tab,
  or Add Split's pending pane (below), outside Space creation, popups and the
  covered. The floating request sets the stored hover input as any non-hover
  reveal does, so the first tab keeps the sidebar while the pointer is still
  on it.

### Add Split's pending pane

  presentation info, so the pending content is the split's focused content
  ([pending pane](split-groups.md#replacement-highlight-pending-pane-and-proposal-feedback)).
  entry until a result fills it. It has no blueprint and no item, but the
  it has none, the active-item helper returns nil while it is focused and,
  with no modal, the getter returns floating for a hidden sidebar, whatever
  the pointer does. Filling or cancelling the pane focuses an item again and
  the hover activation decides. Parc's floating sidebar during Add Split
  rests on this inference.
- Parc keeps the current tab focused behind its window-owned pending pane,
  so `holdsSidebar` also holds while `splitInsertion` is set. Opening the
  pane renders, which floats a hidden sidebar; every hide while it is
  pending floats; filling it (result, New Note or New Easel) or cancelling
  it clears `splitInsertion` and renders, which hands the floating sidebar
  back to the hover rule. A typed result keeps the pane pending through its

`python3 tests/EmptyWindow/check.py` covers the rule's tables, the active-item
predicate with and without a pending pane, its composition with the hover
rule's dismissals and hand-off, and source assertions that every hide path
reaches the rule and that the pending pane's start and each of its three ends
render, with negative controls (one removes the pending-pane term).

## Traffic lights

address is marked 1.170. **[D]** marks bounded annotated disassembly with Swift
field metadata, ObjC ivar/method lists and selector references resolved from
the Mach-O tables (including `bl` and `adrp`/`ldr` scans of `__text`);
read statically from an arm64 copy thinned with `lipo` (SHA-256
`77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`; its
addresses belong only to it); **[R]** a REA/Ghidra 12.1.4 raw-slice decompile
that agrees with the 1.122 disassembly (evidence ID given); **[A]** a static
**[E]** an inert AppKit experiment on this machine (OS 27.0, build 26A428;
off-screen windows, never key, no browser); **[I]** an inference.

**Host.** The traffic lights are sidebar header content.

- [D] Swift field metadata: `WindowLayoutController.sidebar` and
  `WindowViewController.sidebar` are the only `SidebarViewController` fields;
  `SidebarViewController.sidebarHeader` is the only `SidebarHeaderView` field,
  `SidebarHeaderView.buttons` the only `BrowserNavigationButtons` field and
  `BrowserNavigationButtons.windowStandardButtons` the only
- [D] The only direct call of the `BrowserNavigationButtons` initializer
  [buttons, commandBarContainer]. The only direct call of the
  `ev_b3ff985352075ef8648574da7816a049df96496a6543322f8b562e225fc823b4`),
  which passes the default button set for both enabled and visible buttons and
  no zoom action.
  container with leading, trailing and top constraints through the helper
  that sidebar view's frame (above), and the floating transitions reparent it.
  So the lights slide with ⌘S, ride the floating container and leave with a
  hidden sidebar; no runtime capture of that motion was made.

**Which set shows.**

- [D, R] `BrowserNavigationButtonState` is built only by the header's scope
  (`ev_c7c773557e88519dca408cd64c52133e07e25dd253b663f4e1f94426d6dbb8c5`),
  `.windowStandardButtons` (raw value 2) when `WindowState.fullscreen` is nil
  or 2). `SharedWindowFeature.FullscreenState` has the cases entering,
  webContent or window mode. The field identity follows from WindowState's
  field order and its accessor witnesses: the 18-byte value at +0x278…+0x289
  (`ev_bcbc88822190b72fa6c98937e32a4cfa7e8210bddca5a4030e131ff7d8a394cc`)
  button unless fullscreen is `.expanded`.
- Exactly one set shows, except while entering full screen, when neither does.

**`WindowStandardButtons`.**

  (`ev_7ff0d98ef4209a1815e65ef46dc6ab4e046abba240c191e4ed51a079fe12290a`):
  `buttonDimension` 14, `buttonSpace` 6, `shouldDimControlsWhenNotHovered`
  true, `mouseInside` false; HoverableView tracking options 0x283
  (entered/exited, moved, active always, in visible rect); a horizontal stack,
  spacing 6, fill distribution, pinned to the view's edges.
  (`ev_7c61af3ad94fa4646c2a268ba1b52301a9748d5c07dbe1872ea2dff58e89c3f7`)
  creates the buttons once (only while the stack is empty) with
  if one is nil; sets `isEnabled` from `enabledButtons`; targets the zoom
  button at its own `zoom:` only when a zoom action exists; and arranges them
  on the next main-queue turn.
  only on macOS 26 and later (`_stdlib_isOSVersionAtLeast(26, 0, 0)`), and a
  `DimmedOverlayButton` 2 points narrower and shorter, centred on it, is added
  to the view. The intrinsic size is n × 14 + max(0, (n − 1) × 6) by 14
  `ev_a1f417466cde8f4b336738bb64936bf4a7c0a98405afd3bac10e79220abf7af2`).
  `ev_1fb7d46f209ba42f1c46bc661b8d472627dfe51427ea1a57536d55129683ad10`). A
  `ev_d0599533f5ef110d35088cafe48bf866f6528be0a49f3eed54ae8dce886a5974`:
  hidden = dimming ? hovered : true), redraws each button (and relayouts it on
  `ev_3772ed5b559900136b6bae3dc89c8cf9e10d25bd40370346ab0b9a4e2b42b3d4`) sets
  alpha 1 when hovered or not dimming, otherwise 0.33 when the drawing
  `updateLayer` to set its background to the named colour
  colour as sRGB (0, 0, 0, 1) and, for Dark Aqua, (0.953, 0.953, 0.918, 1);
  [I] 1.122 used the same values.
  the dimming functions). Its setter is reachable only through the class's
  `BrowserNavigationButtons` calls, and the only instance keeps the default.
  [I] No other code reaches it: the `ldr #0x240`/`blr` pairs elsewhere were not
  traced to their receivers. [O] The 1.170 still shows low-contrast grey
  circles at the lights while the pointer is elsewhere, consistent with dimming.
  through a vtable query and republishes the hover state; [I] it runs on
  miniaturize.


  against 1.122's 14 and 138: `buttonSpace` is gone from the ivar list and the
  Swift field names (`$__lazy_storage_$_stackView`, `subscriptions`,
  `buttonDimension`, `shouldDimControlsWhenNotHovered`, `mouseInside`).
  `_stdlib_isOSVersionAtLeast(26, 0, 0)` holds and 6 otherwise
  spacing) by 14 with the same gate, so three buttons measure 60 × 14 on macOS
  26 and later and 54 × 14 before.
  `+standardWindowButton:forStyleMask:` and `setEnabled:`; arranging them
  `setTranslatesAutoresizingMaskIntoConstraints:`, `widthAnchor`,
  `constraintEqualToConstant:`), and the hover refresh still sends
  `setNeedsDisplay:` and, on 26 and later, `setNeedsLayout:` to each button
- The 1.170 store of `windowButtonMargin` was not located. [I] It is still 4:
  the captured toggle (76.7) is 13 + 60 + 4 = 77 within a point.

**AppKit behaviour [E]** (inert component checks in
`tests/SidebarWindowButtons`, plus scratch probes):

- `+standardWindowButton:forStyleMask:` returns 14 × 14
  `_NSThemeCloseWidget`, `_NSThemeWidget` and `_NSThemeZoomWidget` buttons
  with nil targets and AppKit's own actions (`_close:`, `miniaturize:`,
  `_setNeedsZoom:`). A click closes the window that holds the widget even when
  no window is key.
- The widgets ask an ancestor for `_mouseInGroup:` when they first display
  and, on this OS, whenever they lay out, not on a redraw alone ([I] the
  counts those queries on `WindowStandardButtons` itself.
- Each exposed cell reports the subrole of the window's own button of the same
  type, and follows the window's full-screen eligibility live:
  `AXZoomButton` with `.fullScreenNone`, `AXFullScreenButton` with
  `.fullScreenPrimary`. Under AppKit's default behaviour this inert process
  (prohibited or accessory activation) gets `AXZoomButton`. 1.170's tree shows
  `AXFullScreenButton` [O]. So that subrole depends on AppKit treating the
  browser window as full-screen primary in a regular app, which Parc does not
  set explicitly and which was not checked at runtime.
- A widget's accessibility frame is 16 × 16, 1 point outside its 14 × 14
  bounds. So 1.170's "16 × 16" lights are 14-point widgets.
- Once the window's own buttons are hidden, `-[NSWindow standardWindowButton:]`
  answers with a content widget of the same type, and keeps doing so after
- The window's own buttons on this OS are 14 × 14 at x 9, 32 and 55 (ending
  at 69), y 9 in the titlebar: the same 23-point pitch as 1.170's 14 + 9.

**Parc.** `WindowStandardButtons` (`Sources/ParcApp/WindowStandardButtons.swift`)
on this machine: AppKit's own widgets made once for the window, 14-point slots
9 apart on macOS 26 and later and 6 before, the 14-point width only on 26 and
later, and the formula size whatever the widgets' own. It also carries the 0x283
tracking area, `_mouseInGroup:` answering the shared hover state, the overlays
and the 0.1/0.33 dimming. `SidebarView` hosts it as the first header control
and `SidebarChromeLayout.toolbar` places it at x 13, centred in the 40-point
row, with the toggle 4 points after it. On this OS that is 13…73 with the
widgets at 13, 36 and 59, and the toggle at 77, all centred at y 24. Their
accessibility frames (16 × 16 at x 12, 35 and 58, y 16) and the toggle land
within a point of 1.170's capture (12.1/35.3/57.5, y 16.2; toggle 76.7), which
the component check asserts. Before macOS 26 it is 13…67 with the toggle at
71, as in 1.122.

`BrowserWindowController` stores the window's own three buttons before the
sidebar joins the window and tracks `WindowFullscreenPhase` from its will/did
enter/exit (and failure) delegate callbacks. `refreshWindowButtons()`
reconciles that phase with the window's style mask (`WindowFullscreenPhase.current`)
and applies `WindowFullscreenPhase.apply`, which the component check runs on a
real window's buttons: the window's own show only while expanded, the header's
outside full screen and while exiting. The rule runs in the preparation and
full passes, so nothing changes visibility when ⌘S starts or settles; the
header's lights move inside the geometry group as sidebar content. In expanded
native full screen the header drops them and the toggle leads at 13. The
toolbar toggle no longer follows AppKit's fixed lights, so the resting-origin
input of the geometry group is gone.

Adaptations and open points:

- Buttons are created synchronously in `viewDidMoveToWindow`, so the first
- They are direct subviews with frames instead of an `NSStackView`; the
  geometry is the same and the widgets find `_mouseInGroup:` either way.
  all-enabled set, so a native request's maximize capability stays truthful.
  The engine's maximize guard (`native_browser_window.mm:637`) reads
  `-standardWindowButton:NSWindowZoomButton`, which now finds the header's
  zoom widget; its copied state keeps that guard's answer unchanged.
  configurable in Parc: its only instance uses their defaults.
- [I] The dimming appearance follows the theme's darkness
  (`SidebarView.applyPalette`), not the window's appearance.
- Popups have no sidebar header and keep the window's own buttons outside
  full screen. The Library hides them and lists its own dimmed group in the
  rail, where the sidebar's header sits, under the same full-screen rule.
- A header that leaves, hidden or (after ⌘S) unhidden off-screen as
  `SidebarView.isPresented` reports, drops its hover, and its return or
  (de)miniaturizing re-tests the pointer, so glyphs never stay lit without an
  exit event.
- Spacing follows 1.170 (9 points on macOS 26 and later) rather than 1.122
  intrinsic width was not recovered. Parc keeps the formula size and centres
  each widget on its 14-point slot. No pre-26 machine was available to compare.
- A regular row narrower than 217 cannot hold 60-point lights, the toggle and
  three 32-point buttons. Parc keeps all four controls at the narrow 28-point
  was not captured.
- A window that reaches or leaves full screen without its delegate callbacks
  (a native tab joining or leaving a full-screen window, for example) is
  reconciled from `styleMask.contains(.fullScreen)`; browser windows keep
  AppKit's native tabbing.
- Accessibility order: 1.170's tree lists the lights before the toolbar, the
  address and the list [O]. `SidebarView` keeps its header above
  `contentSurface` for drawing and hit testing and reorders only its
  accessibility children (`SidebarAccessibility.headerFirst`): lights, toggle,
  Back, Forward, Reload, then the rest in subview order.
- Not checked at runtime: the zoom widget's hover tiling menu, Option-click
  zoom and the full-screen titlebar reveal with the window's own buttons are
  AppKit's own widget behaviour and were not exercised. Neither was the
  `AXFullScreenButton` subrole in Parc's regular app (above).

## Drawn content inside the group

An earlier static review inferred that drawn views whose width follows the
page stretch during the 0.08 s group. An inert experiment [E] refines that:

- AppKit's default `layerContentsRedrawPolicy` is `.duringViewResize` for
  `drawRect` views, `NSTextField` labels and `NSProgressIndicator`, and
  `.onSetNeedsDisplay` for non-drawing views, `updateLayer` views and
  `NSButton`.
- Inside an implicit `NSAnimationContext` group, a `.duringViewResize` view
  whose size changes gets no Core Animation geometry: AppKit drives its frame
  every display frame (a test label received widths 341, 397, 508, 580 and 600
  over 80 ms), laying out and redrawing on the main thread, outside
  `SidebarMotionController.cancel()`. The other policies get one position and
  bounds animation, and the default `.scaleAxesIndependently` placement
  (`contentsGravity` resize) scales their drawn contents: the stretch, which
  applies to `NSButton`-based views such as `ActionButton`.
  reference, so Parc's placement choice is its own.

`SidebarMotionController.pinDrawnContent` gives a view `.beforeViewResize` and
an unscaled placement, so it is drawn once at its final size, held at its
alignment, and moves with the group's single animation, which `cancel()` can
settle. Applied to the loading bar (left, clipped, since it sits outside the
page's rounded mask) and the capture indicator's button (left; nothing is
drawn past its text). A window with no tab draws nothing that needs a pin: its
[empty content](window-appearance.md#a-window-with-no-tab) is a layer color. `python3 tests/SidebarMotion/check.py` shows the default
label's per-frame resizing and the default button's scaling beside the pinned
views' single unscaled animation, and checks that those production views stay
pinned.

Not changed here. These are visible views; while hidden, the motion
controller already keeps them off the per-frame path
([frame pacing](#frame-pacing)), so each costs a frame only while it shows:

- **Contract for the Split views and Toolbar owners:** `BrowserPane.header`
  and `BrowserToolbarView.address` are `PaneTitleControl`s
  (`Sources/ParcApp/PaneTitleControl.swift`). Each is an `NSButton` that draws
  nothing itself and holds a centred `PaneTitleLabel` (`NSTextField`) and a
  `surface` `CALayer`. `place(in:)` centres the button on its slot at the
  text's width, capped by the slot, and `layout()` sizes the label to the
  button's bounds less its inset and sets `surface.frame = bounds`.
  - The label keeps AppKit's `.duringViewResize`. So whenever `place(in:)`
    changes the button's width inside the ⌘S group (a title wider than the narrower
    slot), AppKit resizes and redraws that label every display frame, outside
    `cancel()`. Either pin it in `PaneTitleControl.init` with
    `SidebarMotionController.pinDrawnContent(label, to: .center)`, or keep the
    button's width fixed for the group's duration, so that `place(in:)` only
    moves it there.
  - Assign the surface's frame inside the group, through the same
    `layoutSubtreeIfNeeded` pass that applies the target geometry. It then
    shares the group's 0.08 s timing instead of Core Animation's implicit
    default or a snap after the group [I].
  - `BrowserToolbarView` itself draws (a 1-point bottom rule, `draw(_:)`), so a
    shown toolbar is resized and redrawn every frame of a ⌘S slide: give it
    `.beforeViewResize` with `.scaleAxesIndependently` (a horizontal stretch of
    a 1-point rule is invisible) or move the rule to a layer. Its other drawn
    subviews whose width follows the pane need the same pinning, with the
    placement of their alignment.
  - Status: delivered by Split views SP27 (October 27). The label is pinned
    `.center`, the surface frame animates only inside an implicit group, and
    the toolbar is pinned `.scaleAxesIndependently`; its other subviews keep
    fixed widths. `tests/SidebarMotion/check.py` checks both pins
    ([split views](split-groups.md#s-slide-pinning-sidebar-round-3)).
- `DeveloperToolbarView` draws its tint and stripes across its full width, so a
  non-scaling placement would leave a gap while it narrows; a shown toolbar
  keeps AppKit's per-frame redraw. Moving its tint to the layer background
  would let it be pinned.
- `PageFailureView` draws (`draw(_:)`) and its title and detail labels
  (centred) are candidates for `.center`; a shown failure page is redrawn every
  frame. That component is also compiled alone by
  `tests/RendererCrashPresentation`, so it was left to its owner.

No functional browser test ran.

## Frame pacing

0.08 second cubic and preset-5 spring. Labels follow
[traffic lights](#traffic-lights): [D] bounded disassembly with Mach-O
(SHA-256 `77be289e…d39c52d`), [C] an inert AppKit probe on this machine
(OS 27.0; off-screen windows, never key, no browser), [I] inference.


  0.46, `0x3ee66666` 0.45, `0x3f70a3d7` 0.94, `fmov s0, #0.25`), exactly as
  implicit animation and a duration, then the timing function. Three, the
  same cubic that sends `setNeedsLayout:` and `layoutSubtreeIfNeeded` to
  not a sidebar presentation group. The spring preset table is
  byte-identical (responses 0.25, 0.35, 1.25, 0.15, 0.28, 0.18, 0.08 and
  damping ratios 0.9, 0.9, 0.9, 0.95, 0.63, 0.8, 0.8 at file offset
  `0x3656830`; 1.122 `0x33f79c8`); which preset the 1.170 floating
  transitions load was not traced [I: preset 5, as in 1.122].
  only geometry calls: the sidebar's origin, the contents constraint
  their content panes are `.beforeViewResize`
  ([drawn content](#drawn-content-inside-the-group)). [I] Whether AppKit then
  subtree depends on the redraw policy of every drawing view in it, which was
  not recovered (the pane's policy does not carry to its subviews), nor
  Animation Hitches comparison ([runtime acceptance](#runtime-acceptance-side10))
  decides it.
  view frame before `layoutSubtreeIfNeeded`. FloatingSidebarBackgroundView
- [D] Its `themeView` (field descriptor: `shadowView` `NSImageView`, `blurView`
  `NSView`, `behindWindowBlurView` `NSVisualEffectView`, `themeView`,
  `fakeTitlebarView`, `sidebarView`) is a `WindowBackground`
  `WindowBackgroundContainerView` (fields `preferredRenderer` and
  `activeRenderer`, both `WindowBackgroundViewRendererType` with cases
  `swiftUI` and `metal`, and `view`, an `any WindowBackgroundViewType &
  NSView`), created in the initializer through its metadata accessor
  `layout`. The Metal renderer's
  view, `WindowThemeBackgroundViewMetal`, overrides `displayLayer:` and
  bounds with actions disabled and, when it is in a window, its stored state
  not empty, marks that layer for display. None of the eight
  `WindowBackground` or `WindowThemeUI` code. Which renderer the floating
  background uses was not traced.
- [C] Views shaped like these, in an off-screen window: a plain `NSView`, an
  `NSImageView`, a layout-only container and a view overriding `displayLayer:`
  and `layout` report `.onSetNeedsDisplay` by default; `NSVisualEffectView`
  and a `draw(_:)` view report `.duringViewResize`. With their parent at
  `.duringViewResize`, a 0.08 s group that grows the parent by 10 points
  resized and laid out the constraint-pinned container and its Metal-shaped
  view on each frame AppKit drove (4–6 per slide in three runs at 144 Hz),
  and the Metal layer displayed each time; with the parent at
  `.onSetNeedsDisplay`, once.
- So [I], with the floating background at `.duringViewResize`, AppKit
  resizes it, its blur views and its theme view every frame of floating →
  locked, and with the Metal renderer re-renders the theme each time: the
  same per-frame cost Parc's theme canvas had (below).

**What AppKit does per frame [C].** Inside an implicit `NSAnimationContext`
group, a `.duringViewResize` view whose size changes gets no Core Animation
geometry: AppKit sets its frame, lays it out and requests its redraw on the
main thread on each display frame of the group (up to 11–12 times in 80 ms at
144 Hz), and the window's theme frame lays out each time. (An off-screen
window is occluded, so AppKit then skips the display itself; [I] an on-screen
window redraws the view each time.) This holds for a hidden view and for
a view hidden by an ancestor. A hidden view at `.beforeViewResize` instead gets
one bounds animation, and restoring its policy right after the group starts no
per-frame work.

**What the harness found in Parc [C].**

- Every pane carries a hidden `DeveloperToolbarView`, `BrowserToolbarView`
  and `PageFailureView` (each a drawing view) laid out at the pane's full
  width with zero height, their labels and fields, and a hidden header label
  whenever its slot narrows. All followed the page's width, so every ⌘S slide
  resized them every frame. In the pacing harness one pane cost 66
  layout passes, 88 frame changes, 110 layer property changes and 22 text
  relayouts per hide (11 frames); production panes carry more subviews, and
  recovered (above); this is Parc's own cost, removed below.
- A floating → locked slide resized the floating surface's Metal theme canvas
  every frame and rendered the theme each time (6–7 resizes and renders per

**Parc now.** `SidebarMotionController.animate` collects, in the walk it
already makes over the participants, every hidden `.duringViewResize` view and
holds it at `.beforeViewResize` for the group, restoring AppKit's policy when
the group returns. The materials, the blur and the dock's behind-window
floating background and blur views do.
`SidebarTransition` and `SidebarChromeFrames` now hold the transition plan and
the chrome frames that `setSidebarPresentation`, `layoutChrome` and its
geometry pass used to compute inline (the geometry pass duplicated the full
pass's frame arithmetic); the pacing harness lays a window out with them.
Curves, durations, end states, the three-pass order and the participants are
unchanged.

**Parc adaptation: the pinned theme canvas.** `SidebarMotionController.pinSurface`
pins the sidebar container's theme canvas (every drawn surface but the
material and the sidebar) at `.beforeViewResize`, so it renders once at its
final size and Core Animation scales it with the container. The floating
shadow is added after pinning, on the first float. It is layer contents
stretched from its caps at `.onSetNeedsDisplay`, so it too gets one bounds
animation ([floating surface](#floating-surface)). This does less
[I]. It is kept because it only removes per-frame work, and the scaled canvas,
drawn at its final size, is at most 10 points larger than its frame in either
dimension (under 5 % of the sidebar's width, about 1 % of its height) at the
start of an 80 ms slide. The runtime comparison checks the theme during item 5
([runtime acceptance](#runtime-acceptance-side10)); a visible difference there
is SIDE10's and would mean dropping the pin.

**The budget (`python3 tests/SidebarPacing/check.py`).** An off-screen window,
never key, built like BrowserWindowController's: production
`ThemeRendererView` root and sidebar container (themed, with the pinned
surface), `WindowStandardButtons` and `SidebarChromeLayout` in the sidebar,
the page host with its corner mask and a constraint-filled split, the
production page-card shadow below the host, a pane with BrowserPane's hidden
strips and labels and a Chromium-shaped page view (WebContentsViewCocoa's
`setFrameSize` relayout and a renderer view that counts its sizes), or, for a
window with no tab, the empty content's layer-only stand-in, and the pinned
loading bar. Its driver
runs `setSidebarPresentation`'s three passes through `SidebarTransition`,
`SidebarChromeFrames` and the production `SidebarMotionController`; the check
asserts that BrowserWindowController's source still runs those lines. Swizzled
`layout`, `setFrameSize:`, `setFrameOrigin:`, `setNeedsDisplayInRect:`, cell
drawing, `CALayer` setters, `display` and `addAnimation:forKey:` count work
per view in the window's content view; a run-loop observer times the main
thread. Scenarios: ⌘S hide and reveal on a web page, ⌘S floating the sidebar
with no tab and its reversal, the hover reveal (also a last tab closing), ⌘S
locking a floating sidebar, and reversals 30 ms in (hide → reveal, reveal →
hide). Hiding, revealing and dismissing over the empty content, which a window
with no tab never does, stay as content-cost cases.
For each:

- per display frame in flight, from the commit to the newest completion: no
  layout pass, frame change, layer property change, text relayout, redraw or
  redraw request in any view, and no main-thread time in view work, except
  the blur, and while docking the behind-window material, in floating ↔
  locked (locked → floating is ⌘S with no tab), which are outside the budget
  while shown and
  floating background has);
- per pass (preparation; group with its flush and the display cycle that ends
  the turn): each view laid out at most once (AppKit's own window widgets lay
  out once per sidebar origin change and are reported), each label relaid out
  at most once, the renderer view sized at most once;
- the settled frames equal `SidebarChromeFrames` and no geometry animation
  outlives the transition;
- no snapping: sampled every millisecond, the sidebar origin and the page's
  origin and width never step more than 20 points (sampling jitter of up to
  2 ms at the peak speed is about 11) beyond what 1.3 × the recovered
  curve's peak speed for the longest move allows between two samples (the
  cubic's peak slope is 1.88 × its average; the spring is integrated from
  rest).

On this machine (144 Hz) every production scenario is idle in flight within
the budget: 0.000 ms of view work per frame, with 11–48 frames per slide. The
exception the budget leaves out is real work: in floating ↔ locked AppKit
resizes the material on each frame it drives (6–12 per slide; a dock resizes
the blur and the behind-window material, 14 in one run), so the run loop
there is usually busier than idle (for example 0.65 against 0.49 ms per frame
in one run, 3.9 against 1.6 under load; the idle baseline is noisy, and one
run under load measured 0.72 against an idle 1.12). That cost is the one [I]
largest step beyond
the curve's speed stayed under 10 points in every run (0–3.4 in most), and
millisecond samples around each reversal show the slide turning from its
on-screen position without a step. In-harness controls each break the budget:
an unpinned theme canvas (6–7 per-frame resizes and renders), a visible
unpinned drawing strip (an owner's view: a layout, resize and redraw request
on each frame AppKit drives, 3–11 per hide), a settle 10 ms into a hide (a
160–180-point snap, 80–170 points beyond the curve), and a second geometry
pass (views and labels laid out twice, the
renderer sized twice). Source-mutation controls rebuild the harness without
the hidden-view hold and without the canvas pin and expect it to fail;
`tests/SidebarMotion` adds the hold's component assertion with the same
control.

What the harness cannot show: Chromium's frame timing against the 80 ms curve
produces its frame at an unsynchronized moment in both browsers), render
server compositing, the sidebar's own list (SidebarView is not compiled alone;
views while shown (contracts above). The running-app comparison below covers
them.

## Runtime acceptance (SIDE10)

**Not run.** At the user's direction (October 27) this check was skipped and the row is DONE on its verified code; the procedure is kept for reference.

setup in both browsers. No lane runs it.

**Setup.** One display at its native refresh rate (note it: 60 or 120 Hz);
Reduce Motion off; each browser frontmost in turn with one window of 1470 ×
831 points (the size of the 1.170 observation above), the sidebar locked at
its default width, a Space without a theme
change pending, browser toolbar off, Developer Mode off, no split, no capture
indicator, one ordinary tab showing a loaded static page; then repeat ⌘S in a
window with no tab in both browsers, where it floats the sidebar over the empty
content and a second ⌘S locks it again. Record each browser
with a screen recording at the display rate (QuickTime Player ▸ New Screen
Recording of the window region, 60/120 fps) and, separately, with Instruments'
Animation Hitches template attached to the browser process.

**Observe, five times each, in both browsers:**

1. ⌘S hide from locked: the sidebar, with its traffic lights and header,
   slides off the leading edge while the page's leading edge moves from the
   sidebar's width to its hidden inset (see End states below).
2. ⌘S reveal from hidden: the reverse; the sidebar starts at x − width.
3. Reversal: ⌘S twice within about two frames (key repeat off; press, then
   press again before the slide ends), from locked and from hidden.
4. Floating reveal: with the sidebar hidden, move the pointer to the window's
   left edge and stop; then move it away for the dismissal.
5. ⌘S while floating: the floating sidebar locks. Repeat it in a Space with
   its theme view on every frame [I], while Parc scales its theme canvas,
   drawn once at its final size ([frame pacing](#frame-pacing)).


- Duration and curve: anchored slides (1, 2, 5) take 0.08 s from the first
  moved frame to the last; at 120 Hz the sidebar's travel per frame follows
  the cubic (0.25, 0.46, 0.45, 0.94): about 0, 20, 38, 55, 69, 79, 87, 93, 97,
  99, 100 % (at 60 Hz: 0, 38, 69, 87, 97, 100 %). Floating slides (4) follow
  the spring (response 0.18 s, damping ratio 0.8, from rest): settled within
  0.28 s with an overshoot of about 1.5 % (about 4 points) and no second
  bounce.
- No snapping: no frame in which the sidebar or the page edge jumps further
  than the curve's largest step (its first: about 46 points at 120 Hz and 91
  at 60 Hz for the 238-point hide of a 228-point sidebar), at the start, the
  end or a reversal; a reversal turns
  from the position on screen, restarting the cubic without carried velocity,
- Frame pacing: Animation Hitches reports no hitch during Parc's slides beyond
  longer than one frame between the key press and the slide's end), and no
  reflow once to its final width at one moment in both browsers; Parc must
  show no repeated reflow, no stretched or squashed text, and the loading bar
  holds its alignment.
- Theme during item 5 (themed Space): Parc's floating background shows no
  theme canvas pin.
  9 points; Parc settles at 10, SIDE16's recovered hidden inset (1.122's
  SIDE16. A difference of up to 1 point is SIDE16's open chrome-spacing
  question, not a SIDE10 fail. SIDE10 fails if the slide does not end where
  Parc settles (a jump at completion) or if the difference is larger. The
  floating sidebar sits 5 points from the window's edges with 10-point
  outside full screen.

Report pass or fail per item with the recording timestamps. A failure in a
shown toolbar, Developer Mode toolbar, split header or failure page is that
family's contract above, not SIDE10's.

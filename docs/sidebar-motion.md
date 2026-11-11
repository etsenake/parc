# Sidebar motion and presentation

`BrowserWindowController` owns locked, floating and hidden presentation.
`SidebarMotionController` animates the existing AppKit hierarchy around that
layout. It does not own page selection, renderer contents, native focus or a
second browser window.

Related guides: [resizing and geometry](sidebar-resize.md),
[accessibility and focus](sidebar-accessibility.md),
[Space theme rendering](space-theme-rendering.md), and
[window appearance](window-appearance.md).

## Source map

| Responsibility | Source |
|---|---|
| Transitions, frames and redraw policy | `Sources/ParcApp/SidebarMotionController.swift` |
| Window integration | `Sources/ParcApp/BrowserWindowController.swift` |
| Hover model and event ownership | `Sources/ParcCore/SidebarHover.swift`, `Sources/ParcApp/SidebarHoverTracker.swift` |
| Floating material and theme canvas | `Sources/ParcApp/ThemeRenderer.swift` |
| Space paging | `Sources/ParcApp/SidebarSpacePaging.swift`, `Sources/ParcApp/SidebarView.swift` |
| Traffic lights | `Sources/ParcApp/WindowStandardButtons.swift` |
| Dock menu and plus face | `Sources/ParcApp/SidebarPlusMenu.swift`, `Sources/ParcApp/SidebarPlusButtonFace.swift` |

## Presentation transitions

| Transition | Timing |
|---|---|
| To or from locked | 0.08-second cubic, control points `(0.25, 0.46, 0.45, 0.94)` |
| Floating ↔ hidden | Spring with 0.18-second response and 0.8 damping ratio |
| Library width | 0.2-second cubic with the same control points |

A transition has three passes:

1. Prepare presentation, floating surface and pointer tracking at the old
   geometry. A hidden reveal places its initial offscreen frame and flushes
   prior layout only when pending layout or geometry requires it.
2. Change geometry inside one animation group and flush layout once. The
   sidebar, Library, page host, page shadow, extension panel, loading bar,
   capture indicator, Peek and find UI follow their actual native frames.
3. Only the newest generation runs the full settling pass, including native
   layout synchronization and non-geometric refreshes.

The generation advances before preparation, so a predecessor completing during
that pass cannot settle the new request. Reversals retarget the presented
position without first cancelling the previous group. Cancellation removes
only animations still owned by that request; it cannot remove a renderer's
replacement animation under the same key.

Floating animation definitions temporarily replace each participating view's
`frameOrigin` and `frameSize` definitions, then restore its exact dictionary.
The renderer receives the final native geometry; no display-link loop streams
interpolated viewport sizes into Chromium.

`SidebarChromeFrames` provides geometry to both full and animated layout.
`LayoutChromeGeometryFingerprint` allows a clean unchanged layout to skip work
while retaining state that affects page ownership, Peek, the command bar,
closing and transfers.

## Presentation frames

For a root rectangle at `(x, y)` with height `h` and sidebar width `w`:

| State | Frame |
|---|---|
| Locked | `(x, y, w, h)` |
| Floating | `(x + 5, y + 5, w, h − 10)` |
| Settled hidden | `(x − w − 10, y + 5, w, h − 10)` |
| Anchored hide's endpoint | `(x − w − 10, y, w, h)` |
| Anchored reveal's start | `(x − w, y, w, h)` |

A hidden sidebar remains an unhidden view offscreen. Only presentations with
no sidebar, such as Library, popups or page fullscreen, hide the container.
`SidebarView.isPresented` is the visibility contract: true during a reveal's
preparation, false when a hide settles. Pointer state is cleared on dismissal
and retested after the sidebar arrives. Focus code must use this contract,
not merely `isHidden` or `visibleRect`.

## Floating surface

The floating surface has 8-point corners, a 1-point white edge at 0.3 opacity,
a within-window popover material, a clipped theme canvas, and a stretchable
shadow extending 10 points beyond the container at 0.2 opacity. The outer
container remains unclipped so it does not cut off the shadow; sidebar content
clips itself during a floating Space swipe.

The shadow is layer contents stretched from image caps, avoiding per-frame
image-view layout during docking. Its artwork remains documented with the
[resource](../Resources/FloatingSidebar/README.md).

During floating → locked, the popover blur and shadow fade out while a
behind-window material fades in. Corners and the edge remain until settling.
A full layout during that group preserves the material crossfade. Reversing
back to floating clears the old fades and restores the floating shadow and
blur. The dock material is created lazily and hidden after settling.

A Space swipe updates one theme canvas with the two adjacent themes and their
fractional position. It does not stack a translucent neighboring canvas over
the current canvas. Re-basing the selected Space preserves the strip position
and therefore the rendered mix, including drags through multiple pages.
Locked and floating surfaces use the same transition input.

Dragging past the final Space presents the create-Space edge over 15 strip
points, fills its ring over 22.5 points and creates after the ring stays full
for more than 0.1 seconds before release. The gesture works when the sidebar
has one Space as well as when it has several; a release that does not create
springs the current Space back into place. Private and Space-management
sidebars do not offer this creation gesture.

For a colored floating Space, the blur follows the window's appearance while
text follows the Space palette. Where material is the whole background, its
appearance follows the palette's light/dark side. A saved forced-dark colored
Space can therefore use light text over the light window's blur. Crossing
between a forced uncolored Space and a colored Space changes that blur's
appearance at the selection commit rather than blending both appearances.

## Hidden-sidebar hover regions

The hover tracker owns mouse events and timers only while the application is
active and the window is key. Losing either reports all regions inactive.
Resizing suspends the tracker silently until the drag ends.

| Region | Relevant behavior |
|---|---|
| Inner left edge | Starts narrow inside the window, then expands around the edge while occupied |
| Outer left edge | 50-point reach, expanding to 250 while occupied or while the pointer is in the window |
| Top left | 40-point width; geometry depends on window containment and toolbar state |
| Floating sidebar | Sidebar width plus an 80-point reach |
| Traffic-light region | Limited by screen/menu-bar clearance |

Entry records `inside`; the normal linger threshold is 0.15 seconds, or 0.16
for the outer edge. Stopping is detected 0.08 seconds after the last movement.
An inactive reveal requires linger, or a stopped pointer in fullscreen.
Once active, remaining inside a keep region is sufficient. Bounds, width,
presentation and toolbar changes update zones immediately.

`SidebarHoverPresentationRule` recomputes from current tracker state whenever a
guard ends or a transition settles. Owner guards, including sheets, popovers,
the command bar and navigation history, defer dismissal. Interaction guards,
including a focused sidebar control, pointer press, held preview or menu,
defer dismissal only while the window is key. A non-hover reveal for editing,
keyboard navigation or an item reveal seeds the active region.

Containment can be reevaluated several times as region geometry changes, but
reports once. Timer work is bounded and stale movement cannot promote an old
stop. The toolbar preference supplies Parc's top-left exclusion rule.

## A window with no tab keeps its sidebar

`EmptyWindowSidebarRule` prevents an empty ordinary window from losing its
navigation. A request to hide its sidebar yields floating presentation instead.
Closing its last tab can float a hidden sidebar, independently of hover.
Creating a Space, Library and popup windows are excluded from this rule.
When an active item returns, a floating sidebar goes back to the hover rule.

### Add Split's pending pane

The pending pane for Add Split also counts as having no active item. The
sidebar remains available while a result is being chosen, including a typed
result awaiting creation. Filling the pane, creating a Note or Easel there,
or cancelling ends that hold. The existing tab remains owned by the window
throughout; the pending pane does not steal or duplicate it.

## Traffic lights

`WindowStandardButtons` places AppKit's native close, minimize and zoom
controls in the sidebar header. They move with locked and floating sidebars
and leave with hidden presentation. Their enabled state remains the window's
actual capability. Fullscreen and presentations without a sidebar select the
appropriate window controls before the transition.

Each slot is 14 points wide. Slot spacing is 9 points on macOS 26 and newer,
6 on older systems. The group shares hover state, dims when not hovered, and
retests the pointer after miniaturization and presentation changes. AppKit
continues to own close, minimize, zoom/fullscreen actions and accessibility.

## Dock plus HUD

The plus menu uses a borderless child window that can become key but not main.
Arrow keys, Return and Escape belong to the HUD; clicking outside closes it.
The tail anchors near the dock plus. Opening scales 0.95 → 1 over 0.1 seconds
with a 0.05-second opacity fade; closing reverses over 0.07 seconds.

`onVisibilityChange` fires before opening takes key status and when every
close path starts. Closing animation ignores further input. Parent close,
miniaturization and sheet presentation close it immediately. Other dismissal
paths animate, then remove the window. The browser holds a hover-revealed
sidebar while the menu owns it and refreshes pointer state afterward.

The menu uses a live light/dark theme palette, resolved against the HUD's own
application appearance. Private windows supply their private palette. A
colorless Space uses system color fallbacks. Titles and icons use readable
primary colors; disabled rows and shortcuts use their dedicated secondary
colors. Theme changes update an already open menu.

## Dock plus button

`SidebarPlusButtonFace` draws two bars as one path so their translucent crossing
has one coverage. Opening rotates the plus 45 degrees into a close glyph,
using a spring with response 0.2 and damping 0.5; Reduce Motion changes it
without animation. The underlying button retains pointer handling, keyboard
focus, tooltip and accessibility.

The plate is clear at rest and responds to hover and press. Press scale is
0.95. Dragging off clears both states, dragging back restores them, and menu
dismissal rechecks the pointer. Hidden or inactive controls cannot stay hovered.

## Today divider Clear and New Tab press

Clear appears only when the sidebar is hovered and Today contains items. It
fades over 0.1 seconds; the latest completion alone may hide it. The divider
shortens when Clear appears and lengthens after it disappears. Hidden Clear
cannot receive clicks or appear as an accessibility child.

New Tab presses to scale 0.992 with a spring and returns to identity when its
action completes. A press released outside can remain held until a completed
click; changing Spaces clears that held state. Its selected look changes
without animation while a new-tab command session is active. Clear retains
its keyboard command and accessibility action; it is not a Tab stop.

## Drawn content inside the group

Drawing views need an explicit resize policy. `pinDrawnContent` preserves a
view's chosen layer placement; use centering for fixed-size centered content
and independent-axis scaling for surfaces intended to stretch. Do not apply
one policy indiscriminately to labels, custom drawing and native materials.

Hidden drawing views are temporarily held at `.beforeViewResize` during a
group and receive their prior policy afterward. The floating theme canvas is
also pinned, so it renders at the final size once and Core Animation scales
it through the short transition. Native blur materials keep their per-frame
resize behavior.

Shown developer-tool strips, failure views and other custom drawing can still
perform per-frame work. Those views are outside the hidden-view optimization;
changes to them must be checked in their own layout context.

## Frame pacing

`tests/SidebarPacing/check.py` exercises production transition and frame models
in an offscreen AppKit harness. It checks bounded preparation/settle work,
geometry continuity and reversals, renderer sizing, animation lifetime, and
that hidden drawing views and the pinned canvas do not acquire per-frame
layout work. Shown material views are measured separately from that budget.
Negative controls remove the optimizations or introduce extra layout and
require the budget to fail.

## Checks

| Check | Scope |
|---|---|
| `tests/SidebarMotion/check.py` | Transition frames, generation ownership, animation definitions and redraw policies |
| `tests/SidebarHover/check.py` | Region geometry, timers, hysteresis and dismissal guards |
| `tests/FloatingSidebarSurface/check.py` | Surface properties, material transitions and theme mixing |
| `tests/SidebarWindowButtons/check.py` | Native button layout and pointer-state reconciliation |
| `tests/SidebarPlusMenu/check.py` | HUD geometry, palette and dismissal behavior |
| `tests/SidebarPacing/check.py` | Bounded AppKit layout work and continuity |
| `tests/SidebarSpacePaging/check.py` | Phased, discrete and legacy paging plus the trailing create-Space gesture |
| `tests/SidebarSpaceSwipe/check.py` | Space-switch lifecycle and frame-budget regressions |

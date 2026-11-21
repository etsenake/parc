# Sidebar motion and presentation

`BrowserWindowController` owns locked, floating and hidden presentation.
`SidebarMotionController` animates the existing AppKit hierarchy around that
layout. It does not own page selection, renderer contents, native focus or a
second browser window.

Related guides: [resizing and geometry](sidebar-resize.md),
[accessibility and focus](sidebar-accessibility.md),
[Space theme rendering](space-theme-rendering.md),
[window appearance](window-appearance.md), and
[preview cards](sidebar-previews.md#presentation), which grow out of their row
or, with Reduce Motion on, only fade.

## Source map

| Responsibility | Source |
|---|---|
| Transitions, frames and redraw policy | `Sources/ParcApp/SidebarMotionController.swift` |
| Window integration | `Sources/ParcApp/BrowserWindowController+Sidebar.swift` |
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

With Reduce Motion on, presentation and Library width changes apply at once
without a group, and turning it on mid-transition settles both at their
destination.

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
behind-window material fades in; mid-swipe, the swipe's second blur fades out
with the first. Corners and the edge remain until settling. A full layout
during that group preserves the material crossfade. Reversing back to floating
clears the old fades and restores the floating shadow, blur and swipe blend.
The dock material is created lazily, above both blurs, and hidden after settling.
Mid-swipe it takes the left page's style, and a second dock material on the right
page's style fades in to the swipe's progress, exactly as the window's own
crossfade does, so the window behind takes over without a jump when the dock
settles, even while the swipe is still settling.

A Space swipe updates one theme canvas with the two adjacent themes and their
fractional position. It does not stack a translucent neighboring canvas over
the current canvas. Re-basing the selected Space preserves the strip position
and therefore the rendered mix, including a second page started during the
first one's spring. Locked and floating surfaces use the same transition input.

A two-finger swipe follows at half the finger's distance between its starting
Space and the Space either side. Past that neighbor, or backward from the first
Space, the strip stretches by `0.55·L·x / (0.55·x + L)`, where `x` is how far
the unresisted strip would have gone past the edge and `L` is a tenth of the
sidebar's width. At the edge the strip slows to 0.55 of its pace rather than
stopping dead, grows stiffer the further it is pulled, and never shows more
than a tenth of a page of empty strip. A swipe picked up while the strip is
still past an edge, settling or springing from a click or wheel switch, starts
from where the strip and color already are: pushing back follows the fingers,
and pulling further out only spends what is left of that tenth of a page, so
nothing jumps and repeated pulls never stretch it further. Pull beyond
nineteen-twentieths of an edge's give is not banked, so even an edge with no
give left answers as soon as the fingers turn back. The release still
chooses its target from the unresisted drag, so it lands where it always did,
at most one Space away, and springs back from wherever the strip was stretched
to. A brisk release that would overshoot the landed Space toward a Space
outside the swipe stretches along the same curve.

A click that jumps more than one Space slides the new page in beside the page
it left, which stands in for the neighbor on that side. A swipe that catches the
slide keeps that page and the color between the two, and treats its side as an
edge the strip is already past: toward the page it left the strip only spends
what is left of that tenth of a page, and a release on that side springs on to
the clicked Space rather than landing next door on a Space that was never on
screen. Pushed past the clicked Space, the strip shows the real neighbor on the
other side, and a release lands there as usual; a swipe caught while the page it
left is off screen is an ordinary swipe. After a click to the Space next door
the page it left is the real neighbor, so a swipe that catches that slide can
still land back on it.

Dragging past the final Space presents the create-Space edge over 15 strip
points, fills its ring over 22.5 points and creates after the ring stays full
for more than 0.1 seconds before release. The gesture works when the sidebar
has one Space as well as when it has several; a release that does not create
springs the current Space back into place. Past the last Space the strip follows
the drag without resistance whenever the sidebar offers creation, so these
distances are unchanged. Private and Space-management sidebars do not offer this
creation gesture, and their last Space resists like any other edge. The ring
arms with a tap on the trackpad when it fills, and taps again as it empties, but
it arms only while the fingers pull. When a release selects a Space, the sidebar
sees the strip's position from the Space being selected rather than the one it
is leaving, and the settle of a brisk swipe that swings past the last Space
fills the ring without arming it, so landing on the last Space never taps. A ring
the fingers armed stays armed through the release.

The floating blur takes the side the Space resolves to: a forced Space's own
light or dark, or the window's for an automatic Space, reusing the window's
appearance object when the sides match. Forced text and blur therefore agree.
When a swipe joins Spaces on different sides, a second masked popover blur on
the right page's side lies just above the first and under the canvas. It is
fully shown at 90% of the swipe, and the first blur fades out beneath it over
the rest. Stacked within-window blurs each blur what lies beneath them, so this
keeps the page from showing through and makes the swipe's end and every page
boundary match the settled single blur. The second blur shows only while the
two sides differ; the commit leaves both blurs unchanged.

## Hidden-sidebar hover regions

The hover tracker owns mouse events and timers only while the application is
active and the window is key. Losing either reports all regions inactive.
Resizing suspends the tracker silently until the drag ends. Page capture
suspends it for the whole session and dismisses a hover-revealed sidebar.

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

## Add Split's pending pane keeps its sidebar

`PendingSplitPaneSidebarRule` keeps navigation available while Add Split's
pending pane waits for a result, including a typed result awaiting creation.
A request to hide the sidebar yields floating presentation, and opening the
pane floats a hidden sidebar, independently of hover. Filling the pane,
creating a Note or Easel there, or cancelling ends the hold, and a floating
sidebar goes back to the hover rule. Creating a Space, the Library and popup
windows are excluded. The existing tab remains owned by the window throughout;
the pending pane does not steal or duplicate it.

An empty Space has no hold. Command-S docks and hides the sidebar there like
anywhere else, closing the last tab leaves the sidebar where it was, and the
left edge reveals the floating sidebar on hover. With the sidebar hidden, the
[start page](start-page.md#sidebar) shows the window buttons and a sidebar
button.

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

New Tab presses to scale 0.992 with a spring and follows the button's highlight
like the dock plus: dragging off springs it back to full size, dragging back
presses it again, and a click released outside always ends at full size. A
completed click springs it back as the button lets go; the action and the
render for the new tab leave that spring running. Changing Spaces drops a held
press. Its selected look changes without animation while a new-tab command
session is active. Clear retains its keyboard command and accessibility
action; it is not a Tab stop.

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

`SidebarPacingTests` drive production transition and frame models in a window
that is never shown, with the motion controller's completions and the layer
clock under the test's control. For every transition and reversal, the
preparation and the group lay each view and label out at most once and size the
renderer at most once; every geometry change in the group rides a Core
Animation animation, so AppKit has nothing left to resize or redraw frame by
frame, and nothing awaits layout; each request starts where the presentation
is; the settled frames are the chrome frames and no geometry animation outlives
the transition. Shown material views are exempt from that check. A dock during
a swipe blend fades the shadow, both blurs and both dock materials once each on
the group's timing. A swipe that keeps settling during a dock adds no layout or
geometry work, the window's crossfade follows it, and the dock materials match
the window's blend they hand over to. Negative controls remove the
optimizations or add a second geometry pass and require the checks to fail.

## Checks

| Check | Scope |
|---|---|
| `SidebarPresentationFrameTests`, `SidebarChromeFramesTests`, `SidebarMotionControllerTests`, `SidebarMotionSurfaceTests` | Transition frames, generation ownership, animation definitions and redraw policies |
| `SidebarHoverModelTests`, `SidebarHoverTrackerTests` | Region geometry, timers, hysteresis and dismissal guards |
| `FloatingSidebarArtworkTests`, `FloatingSidebarSurfaceTests`, `FloatingSidebarSwipeTests`, `FloatingSidebarSwipeDockTests`, `FloatingSidebarSwipeCommitTests` | Surface properties, material transitions and theme mixing |
| `SidebarWindowButtonsTests` | Native button layout and pointer-state reconciliation |
| `tests/SidebarPlusMenu/check.py` | HUD geometry, palette and dismissal behavior |
| `SidebarPacingTests` | Bounded AppKit layout work and continuity |
| `SidebarSpacePagingModelTests`, `SidebarSpacePagerTests`, `SidebarSpaceStandInTests`, `SidebarSpaceCreationPullTests` | Phased, discrete and legacy paging, edge resistance, swipes that catch a click's slide and the trailing create-Space gesture and its haptics |
| `SidebarSpaceSwipeTests` | Space swipes and jumps that build no rows and come to rest, and spring-loaded folders |

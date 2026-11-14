# Window frame

The window frame is the band of Space color between a browser window's edge and
its page card. This guide records its current geometry and the planned setting
that lets people make it thinner or thicker. The open item is indexed in the
[backlog](backlog.md#planned-interface-work).

## Geometry today

- Standard and private windows keep 10 points between the window edge and the
  page card on the top, right and bottom, and on the left when the sidebar is
  hidden or floating. A docked sidebar forms the left edge. The value is
  `SidebarChromeFrames.pageInset` in
  [SidebarMotionController.swift](../Sources/ParcApp/SidebarMotionController.swift).
- The extension side panel shares the right margin.
- The page card has a six-point continuous corner and a shadow with a ten-point
  outset; see [page card shadow](window-appearance.md#page-card-shadow).
- Divided splits leave 10-point gutters between panes (the split view's divider
  thickness), and each pane draws its own card corner and shadow.
- The floating sidebar sits 5 points in from the window's left, top and bottom
  edges; hidden, it moves its own width plus 10 to 15 points off the left edge.
- A standalone page shows the decorative two-by-24-point split grip in the right
  margin, with a 44-point hover band; see [split groups](split-groups.md).
- The hidden-sidebar reveal zones are sized from the same 10 points
  (`SidebarHoverZones.contentInset` in `ParcCore`).
- Popup windows use an 8-point left and chrome inset. Full screen has no frame.
- The toolbar, when shown, sits inside the page card and is unaffected.


## Planned: adjustable thickness


- One app-wide value applies live to every standard and private window. Popup
  windows keep their compact chrome, and full screen stays frameless.
- The range is 3 to 13 points, and the default stays today's 10, so no one's
  window changes until they choose.
- The 3-point floor is thin, but the Space color still reads as a frame; it
  never reaches zero.
- Store it like the other app-wide preferences: a versioned Codable record in
  user defaults that keeps malformed or future records instead of overwriting them.
- It is not per Space. A frame that changed as you swiped between Spaces would
  move every page under you.

People reach it in three places:

- **Onboarding**, as the step after Theme, where most people set it once.
- **Settings → General.** Choosing it puts the Settings window away and brings
  the crank onto the front browser window, so the real frame changes in front of
  you; Settings returns when you finish.
- **Right-click** on the frame or the empty part of the sidebar: Adjust Frame….
  It stays out of the Space menu, which would suggest a per-Space value.

## The crank

The control is a car window crank that sits on the window itself.

- **Object.** One-piece matte satin metal: a wide, waisted paddle arm with a
  gentle bend up to the knob, PARC etched into the arm, a short ribbed knob, and
  soft-touch caps on the knob and hub in the Space's color, over a round
  escutcheon. It is about 105 points long and its knob sweeps an 87-point
  radius. It is drawn live in 3D with SceneKit so the metal lights correctly
  and turns exactly with your hand; RealityKit's SwiftUI view needs macOS 15,
  and Parc supports macOS 13.
- **Placement.** The base sits 125 points in from the window's left and bottom
  edges. With the sidebar docked, it sits on the seam between sidebar and page
  at that height. With the sidebar hidden it sits over the page's lower-left;
  a floating sidebar slides away while the crank is out. The whole swing and the
  lights stay inside the window, including a window that fills the screen. The
  hidden-sidebar reveal zones are off while the crank is out.
- **Turning.** A two-finger scroll over it or a drag on the knob turns it, a
  third of a turn per point. It follows your hand 1:1, eases through a soft notch
  at each point, and at 3 and 13 gives slightly past the end with a faint tremble,
  then springs back when you let go.
- **Lights.** Eleven small pills, one per point, sit on an arc around the crank
  with a gap at the bottom. They fill in order as the frame thickens, like a
  meter: lit pills glow in the Space's accent with a thin bright core, unlit ones
  are faint dashes, and 10 is slightly larger with a dot beside it. Each pill
  pops with a small burst of sparkles as you reach its point, and at 3 and 13
  the lit pills flash. There is no backdrop behind the lights.
- **Readout.** A small capsule under the arc shows the value and its name:
  3 Hairline, 4 Whisker, 5 Pinstripe, 6 Ribbon, 7 Piping, 8 Snug, 9 Comfy,
  10 Classic, 11 Roomy, 12 Salon, 13 Gallery.
- **Window.** Every open window's frame follows as you turn. At 3 and 13 the page
  card shudders a few points sideways with the crank's give.
- **Sound.** A metallic notch click with a little body at each point, a deeper
  two-stage click at 10, and a thunk with a short creak at 3 and 13. A very soft
  wind, generated live, swells gently as the frame opens, like air through a
  cracked window rather than a hiss, and a faint seal whistle fades in above
  about 11.5 points. Everything sits well below normal listening levels, and
  sounds follow the system setting for interface sound effects.
- **Haptics.** A light trackpad tick at each notch, and a firmer one at 10 and at
  the ends, through `NSHapticFeedbackManager`. These only reach Force Touch
  trackpads, and macOS offers a few fixed strengths.
- **Reduce Motion.** No shudder, sparkles or overshoot; the lights and the frame
  crossfade to each value.
- **Keyboard and VoiceOver.** Arrow keys move one point, Return keeps the value
  and Escape restores the previous one. VoiceOver reads it as a slider:
  "Window frame, 10 points, Classic".

## Building it

What follows the value:

- `SidebarChromeFrames` takes the thickness as a parameter instead of reading
  the static `pageInset`; it sets the page margins on every side that has one and
  the side panel's right edge.
- Split gutters: `splitMarginFrame` in `BrowserWindowController` and
  `dividerThickness` in `ParcSplitView`, both hard-coded to 10 today.
- The floating sidebar's 5-to-15-point inset and hide offsets (the review
  decides whether they scale or stay fixed).
- The page and pane corner radius. Six points was chosen for a 10-point frame,
  so the review decides whether the corner scales to stay concentric with the
  window's rounded corner.
- `LayoutChromeGeometryFingerprint` must include the thickness, or open windows
  skip the relayout. Leave it out of the sidebar motion key, which settles running
  sidebar animations whenever it changes.
- Nothing calls `layoutChrome()` when only the thickness changes, so the
  controller asks every window for a layout pass.

These keep today's sizes, so no thickness makes anything harder to hit:

- the hidden-sidebar reveal zones, which get their own constant;
- split divider drag targets and the split grip's hover band. Below some
  thickness the grip overlaps the page edge or hides, as the review decides;
- window resize edges, which belong to macOS.

The page shadow stays; check how it looks at both ends of the range in review.

**Resizing pages while you turn.** Pages follow every frame change immediately
today, and each change sends a new size to the page's renderer. Turning the crank
would do that on every display frame in every window. The sidebar-width and
split-divider drags already avoid this with a page resize reason that switches
visible pages to throttle mode: a page keeps at most one size waiting for its
renderer and stays clipped at that size until the renderer catches up. Add a
frame-adjust reason that is active while the crank is held, run the lighter
geometry layout pass at most once per display frame, and finish with a full pass
when you let go.

**The shudder.** The window's view tree has no container around the page card,
so the shudder applies the same temporary, additive sideways translation to the
page card, its shadow and the side panel. Nothing resizes, the window itself
stays put, and the sidebar and Space background stay still. Sidebar motion
animates position, bounds and corner radius, so a transform animation does not
collide with it.

## Visual review is required

Design and build this through the [interface review](visual-review.md)
workflow, renders first. Renders have settled the crank's look, its placement in
each sidebar mode, the swing staying inside the window, the lights and readout,
and the turning motion. Still to render before building:

- the onboarding step and the Settings hand-off;
- 3, about 5, 10 and 13 points with the sidebar docked, floating and hidden, a
  divided split, the side panel open, and light, dark and private themes;
- Reduce Motion.

The sound needs a listening pass on the generated clicks, wind and whistle before
they are final. The live look-and-feel pass in Parc follows that guide's runtime
boundary. After visual approval, write tests and docs, then hand it to a fresh
reviewer.

## Checks

- Geometry model tests of the chrome frames at 3, 10 and 13 points for
  every sidebar presentation, split, side panel, Library, popup and full screen.
- Preference tests for persistence and malformed or future records.
- A layout-skip test proving a thickness change relayouts open windows.
- Model tests for turning: scroll and drag to angle to value, the notches, the
  give at both ends, and the crank's swing staying inside the window for every
  sidebar presentation and window size.
- A resize-reason test proving pages throttle while the crank is held and
  return to following layout when it is released.
- Swift typecheck and whole-module SIL. No engine change is needed.

# Window frame

The window frame is the band of Space color between a browser window's edge and
its page card. People set its thickness from 3 to 13 points by turning a window
crank on the window itself.

## Geometry

- One app-wide thickness, 10 points by default, frames the page card on the top,
  right and bottom of every standard and private window, and on the left when
  the sidebar is hidden or floating. A docked sidebar forms the left edge.
  `SidebarChromeFrames` takes the thickness as a parameter;
  `SidebarChromeFrames.pageInset` remains the 10-point default and the popup
  inset.
- The extension side panel shares the right margin.
- The page card's continuous corner stays concentric with the window's rounded
  corner: `WindowFrameThickness.cornerRadius(for:)` gives 12 points at 3, 6 at
  10 and 4 at 13. `PageCard.cornerRadius` follows the current thickness, and
  `ContentShadowImage` caches its stretchable shadow per scale and radius; see
  [page card shadow](window-appearance.md#page-card-shadow).
- Divided splits use the frame thickness for their gutters, and each pane draws
  its own card corner and shadow.
- The floating sidebar sits 5 points in from the window's left, top and bottom
  edges at every thickness; hidden, it moves its own width plus 10 to 15 points
  off the left edge.
- A standalone page shows the decorative two-by-24-point split grip in the right
  margin, with a 44-point hover band; see [split groups](split-groups.md). The
  grip hides when the frame is thinner than 6 points.
- The hidden-sidebar reveal zones keep their own 10-point constant
  (`SidebarHoverZones.contentInset` in `ParcCore`), as do split divider drag
  targets, so no thickness makes anything harder to hit.
- Popup windows keep their 8-point left and 10-point chrome inset, six-point
  corner and matching shadow at every thickness. Full screen has no frame.
- The toolbar, when shown, sits inside the page card and is unaffected.

## The setting

- `WindowFramePreferences` stores the value as a versioned Codable record in
  user defaults (`parc.windowFrame.v1`). A malformed, future or out-of-range
  record is preserved, the frame stays at 10, and saving is refused.
- It is not per Space: a frame that changed as you swiped between Spaces would
  move every page under you.
- While the crank turns, `preview` carries the live, fractional thickness to
  every window; `state` changes only when the crank finishes with a kept value.
- `LayoutChromeGeometryFingerprint` includes the thickness, so open windows
  relayout when it changes. The sidebar motion key does not, so adjusting never
  settles a running sidebar animation.

People reach it in four places:

- **Onboarding**, as the **Find your frame** step after Theme; see
  [onboarding](onboarding.md).
- **Settings → General**, as the Window row showing the value and its name, for
  example 10 · Classic, with an **Adjust** button. Adjust fades the Settings
  window out, brings a browser window forward (opening one if none is open) and
  presents the crank. When the crank leaves, or if it cannot appear, Settings
  fades back with the row updated.
- **View → Adjust Window Frame…**, which the command bar also offers.
- **Right-click** on the frame or the empty part of the sidebar: Adjust Window
  Frame…. Controls, the page, the Library and the side panel keep their own
  right-click behaviour. It stays out of the Space menu, which would suggest a
  per-Space value.

## The crank

`WindowFrameCrankView` presents a car window crank on the window.
`WindowFrameCrankModel` builds it in SceneKit, `WindowFrameCrankFeedback` plays
its sound and haptics, and `WindowFrameCrank` in `ParcCore` owns the turning model.

- **Object.** One-piece matte satin metal: a wide, waisted paddle arm with a
  gentle bend up to the knob, PARC etched into the arm, a short ribbed knob, and
  soft-touch caps on the knob and hub in the Space's color, over a round
  escutcheon. It is about 105 points long and its knob sweeps an 87-point
  radius. SceneKit draws it live so the metal lights correctly and turns exactly
  with your hand; RealityKit's SwiftUI view needs macOS 15, and Parc supports
  macOS 13. A soft shadow is drawn from flattened copies of the crank.
- **Placement.** `WindowFrameCrankPlacement` puts the hub 125 points in from the
  window's left and bottom edges. With the sidebar docked it sits on the seam
  between sidebar and page at that height; with the sidebar hidden it sits over
  the page's lower-left, and a floating sidebar slides away first. The swing and
  the lights stay inside the window, including a window that fills the screen; a
  window too small for that centres the crank. The hidden-sidebar reveal zones
  are off while the crank is out, and only one window shows a crank at a time:
  opening it in another window keeps the first window's value and moves it.
  Opening the Library or full screen puts the crank away, keeping its value.
- **Coming and going.** The crank slides in from the lower-left with a small
  spring and stays until you click anywhere else in the window or press Return
  or Escape, then slides back out. There is no timeout. Escape restores the
  thickness you had when the crank appeared; every other way out keeps the new
  value, and closing the window keeps the value too.
- **Turning.** A two-finger scroll over it or a drag around the hub turns it, a
  third of a turn per point. It follows your hand 1:1, eases through a soft notch
  at each point, and at 3 and 13 gives slightly past the end with a faint tremble,
  then springs back when you let go. Momentum scrolling is ignored; a wheel
  mouse settles after a short pause.
- **Lights.** Eleven small pills, one per point, sit on an arc around the crank
  with a gap at the bottom. They fill in order as the frame thickens: lit pills
  glow in the Space's accent with a thin bright core, unlit ones are faint
  dashes, and 10 is slightly larger with a dot beside it. Each pill pops with a
  small burst of sparkles as you reach its point, and at 3 and 13 the lit pills
  flash. There is no backdrop behind the lights.
- **Readout.** A capsule under the arc shows the value and its name:
  3 Hairline, 4 Whisker, 5 Pinstripe, 6 Ribbon, 7 Piping, 8 Snug, 9 Comfy,
  10 Classic, 11 Roomy, 12 Salon, 13 Gallery.
- **Window.** Every open window's frame follows as you turn. At 3 and 13 the
  page card, its shadow and the side panel shudder a few points sideways.
- **Sound.** Clicks only, synthesized once and played through AVAudioEngine.
  Each point has a metallic notch click with a little body, pitched one semitone
  higher per point, so the clicks rise as the frame opens and fall as it closes.
  The click at 10 is deeper and seats twice, like a detent dropping in. A soft
  thunk with a short creak marks the give at 3 and 13. Everything sits well below
  normal listening levels, and sounds play only while Parc is active and its
  interface sound effects are on.
- **Haptics.** A light trackpad tick at each notch, and a firmer one at 10 and at
  the ends. These only reach Force Touch trackpads.
- **Reduce Motion.** The crank fades instead of sliding; there is no shudder,
  sparkle, pop or tremble.
- **Keyboard and VoiceOver.** Arrow keys move one point, Return keeps the value
  and Escape restores the previous one. VoiceOver reads it as a slider:
  "Window frame, 10 points, Classic".

## Resizing pages while you turn

Pages normally follow every frame change immediately, and each change sends a
new size to the page's renderer. While a preview is active, every window adds
the `frameAdjust` page resize reason, which switches visible pages to throttle
mode: a page keeps at most one size waiting for its renderer and stays clipped at
that size until the renderer catches up. Windows coalesce preference changes to
one layout per run-loop turn, use the lighter geometry pass while adjusting, and
finish with a full pass when the preview ends. A window in the middle of a
sidebar or Library animation catches up in that animation's final pass.

The shudder applies a temporary, additive sideways translation to the page card's
layers; nothing resizes and the window stays put. Sidebar motion animates
position, bounds and corner radius, so the transform does not collide with it.

## Checks

- `tests/WindowFrame/check.py`: the turning, placement and naming model, the
  click and thunk synthesis and feedback gating, and the crank view's input,
  lights, dismissal, Reduce Motion and accessibility.
- `tests/WindowFrameIntegration/check.py`: chrome frames at 3, 10 and 13 points
  for every sidebar presentation, side panel, Library, popup and full screen;
  preference persistence and preserved records; and the window controller's
  wiring.
- `tests/LayoutChromeGeometrySkipTests.swift` proves a thickness change relayouts
  open windows; `tests/SidebarResize` covers the `frameAdjust` throttle reason.

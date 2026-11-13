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

These follow the value:

- page margins on every side that has one, and the side panel's right edge;
- split gutters, so panes stay spaced like the frame;
- the floating sidebar's inset and hide offsets (the review decides whether
  they scale or stay fixed);
- the page and pane corner radius. Six points was chosen for a 10-point frame,
  so the review decides whether the corner changes with the thickness to stay
  concentric with the window's rounded corner;
- the layout fingerprint that lets a window skip relayout. It must include the
  thickness, or open windows won't move when the value changes.

These keep today's sizes, so no thickness makes anything harder to hit:

- the hidden-sidebar reveal zones, which get their own constant;
- split divider drag targets and the split grip's hover band. Below some
  thickness the grip overlaps the page edge or hides, as the review decides;
- window resize edges, which belong to macOS.

The page shadow stays; check how it looks at both ends of the range in review.

Changing the value resizes every visible page. While someone is adjusting it,
coalesce relayout to one pass per display frame through the existing layout
path, so pages follow smoothly without a resize storm in each window.

## Design brief

tasteful. Principles:

- **Direct manipulation.** You shape the frame itself, or a faithful live
  miniature of your window, not a number field.
- **Live.** Every open window follows with a soft spring as you adjust.
- **Tactile.** Trackpad haptic detents at each point, a firmer tick at the
  default, and rubber-band resistance at 3 and 13 points instead of a dead stop.
- **Theme-true.** The control shows your current Space's gradient and texture;
  private windows show the private palette.
- **Calm.** One control and no extra chrome. Reduce Motion settles instantly.
  Keyboard and VoiceOver adjust it like a slider, with spoken values.

Candidate directions for the review:

1. **Settings miniature.** In Settings → General, a live miniature of your own
   window: Space theme, sidebar state and page card. Grab the frame edge and pull
   it in or out while the open windows breathe along. A playful label names the
   feel beside the point value.
2. **On-window adjust mode.** A command bar action lights up the real frame;
   a two-finger scroll or a drag on the frame changes it, a small capsule shows
   the value, Return keeps it and Escape restores the previous value.
3. **Theme editor companion.** The control sits with the theme editor's own
   controls, since the frame is where the Space color shows. The value still
   applies to every window.

The recommended home is direction 1, with direction 2 as a shortcut if the
review likes it.

## Visual review is required

Design and build this through the [interface review](visual-review.md)
workflow, renders first:

1. Gather references: Dia's thin frame and the current Parc frame.
2. Render or animate each direction before building it, at 3, about 5, 10 and
   13 points, with the sidebar docked, floating and hidden, a
   divided split, the side panel open, light, dark and private themes, and
   Reduce Motion. Mockups need no app launch.
3. Review one render at a time and choose the direction from them, judged by
   the interface review standard.
4. Build the chosen direction. The live look-and-feel pass in Parc follows that
   guide's runtime boundary.
5. After visual approval, write tests and docs, then hand it to a fresh reviewer.

## Checks

- Geometry model tests of the chrome frames at 3, 10 and 13 points for
  every sidebar presentation, split, side panel, Library, popup and full screen.
- Preference tests for persistence and malformed or future records.
- A layout-skip test proving a thickness change relayouts open windows.
- Swift typecheck and whole-module SIL. No engine change is needed.

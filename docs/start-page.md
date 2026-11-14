# Start page

A Space with no open tab shows a start page: the Parc mark above a resident
command bar, on a page of Note paper over the Space's own colors. It replaced the "No tab open"
placeholder, and the sidebar no longer refuses to hide in an empty window, so
Command-S works there like anywhere else. Open review decisions are in the
[backlog](backlog.md#planned-interface-work).

## When it shows

The start page shows when an ordinary or private window's current Space has no
selected tab, Note, Easel or split, including in full screen. Closing the last
open tab in a Space opens it in that window with the command bar focused; the
window stays open. Switching to a Space with no open tab, or creating one,
lands there too. Popup windows, an open Library and Space creation keep their
own content. Add Split's pending pane keeps its placeholder and sidebar hold
while a result is being chosen; see [sidebar motion](sidebar-motion.md#add-splits-pending-pane-keeps-its-sidebar).

`BrowserWindowController` places one `StartPageView` per window as the page
card's only content and builds it the first time a window needs it, so windows
with tabs never pay for it. Every render refreshes it: a new Space or Profile
rebuilds the resident bar, and leaving the start page dismisses it.

## Sidebar

- Command-S toggles docked and hidden in an empty Space, closing the last tab
  leaves the sidebar where it was, and the left edge reveals the floating
  sidebar on hover as usual.
- While the sidebar isn't docked, the start page shows the window buttons and a
  Show Sidebar button in the top-left corner, exactly where the floating
  sidebar's own controls land, so nothing jumps when it slides in. In full
  screen the window buttons follow the sidebar's own full-screen rule.
- The background drags the window with the sidebar background's single-click
  rule. The page is one accessibility group, "Start page": window buttons, then
  the sidebar button, then the bar.

## Command bar

The input is the command bar itself, not a new search box: the same native
suggestions, open-tab switching, application commands, Type Travel, website
scopes and Tab-to-search as Command-T. See the
[command bar guide](command-bar.md#entry-points-and-source-owners) for its
resident presentation and lifetime.

- It sits flat on the page at the mark's level: the sidebar address field's soft
  fill (ink at 5% in light, white at 10% in dark), 12-point corners, no border
  or shadow. Results list on the same fill below a divider.
- At rest only the 64-point field shows. Typing grows results downward with the
  top edge fixed, up to five rows, once the first suggestions arrive.
- Submitting a navigation opens a new tab in this Space, as Command-T does.
  Switch-to-tab rows and commands behave as in the palette, and a submission
  resets the bar rather than dismissing it.
- Escape leaves a scope, then clears the query and collapses the results; it
  never dismisses the page.
- Command-T and Command-L, and a click on the sidebar's address field, focus the
  resident bar instead of stacking a palette over it.
- The field takes focus when the start page appears or its bar is rebuilt in
  the key window, unless another control already holds focus. After a command
  that leaves the start page in place, focus returns to the field on the same
  terms.
- The bar lives in its own window-controller slot, not the palette's, so
  closing or toggling the palette never dismisses it. The window returns its
  field editor and delivers top domains to it like the palette.

## Background

The page reads as a page, the way a Note does in the same card: Note paper
(`NotePaper`, white at 85% in light, black at 50% in dark, in the Space's
content appearance) over the Space's theme. Light themes come out near-white
with a faint tint of every theme color; dark themes as a dim tinted surface.

- Under the paper, the existing theme renderer draws the Space's full theme
  exactly as the window gradient does, with the theme's intensity and without
  texture: the page hands its renderer the theme with noise set to zero,
  leaving every other theme surface unchanged.
- It shares the window's gradient coordinate space, so it lines up with the
  frame and the floating sidebar; the window refreshes those coordinates when
  the page card moves. Space paging reaches it, so swiping between an empty
  Space and a busy one blends both themes.
- Private windows use the private palette. Themes without color fall back to
  material like every other theme surface, under the same paper.
- The page card stays: the [window frame](window-frame.md) setting still
  applies, and the textured frame reads as a border around the paper.

## The mark

- `StartPageMarkView` draws Parc's monochrome mark, 65 points wide, 24 points
  above the bar, with the pair centered at 45% of the page height.
- In a colored theme the mark's shape is filled with the Space gradient in the
  window's coordinates and keeps the theme's texture, so it is the one textured
  thing on the page. A 25% wash of the palette's high-contrast color keeps it
  visible: the same gradient alone would vanish into the background.
- Colorless themes fill it with the secondary label color; private windows with
  the private palette's blue. Its `style` switches to the color mark.
- It is decorative for accessibility, and dragging on it never moves the window.

## Easter eggs

Three Easter eggs share the mark, each with its own deliberate gesture, through
one recognizer (`StartPageMarkGesture`):

- **Taffy:** press and drag more than four points. The mark stretches toward
  the pointer on a spring, thinning as it lengthens up to about 36 points, and
  on release snaps home with a wobble that settles in about a second.
- **Charge-up:** press and hold still for 0.35 seconds. The mark squishes and
  glows through the theme's colors, filling over the next 0.65 seconds with a
  slight buzz once full. Released past 60% charge it loops the loop and dusts
  the page with 90 pieces of theme-colored confetti; released earlier it just
  springs back. A wobble up to eight points is fine; more cancels the charge
  quietly, and that press does nothing else.
  interval and eight points of the first. The mark flies an arc across the
  page with a full turn, trailing a striped ribbon in the Space's colors, and
  lands with a squash and a wobble.

Rules they share:

- One or two clicks do nothing. A press during an animation is ignored for its
  whole gesture and resets the click count, so eggs never stack.
- Nothing animates or polls at rest; the hold threshold is the only one-shot
  timer. A hidden, occluded or miniaturized window, the page leaving, a lost
  mouse-up or the window losing key sends the mark straight home and removes
  ribbon and confetti.
- Ribbon and confetti are fixed sets of layers in a pass-through effects view
  covering the page; the ribbon is cut where it passes under the mark so it
  trails from behind.
  through the theme's colors; Charge-up keeps its glow while held, since it is
  light rather than motion, and shimmers on a charged release.
- A haptic tick marks Taffy's release, each landing and the Reduce Motion
  shimmer, through the system haptic call the theme editor uses; the
  tab-reordering haptic switch doesn't apply. There is no sound.
- During a Space swipe the mark's textured gradient and tint blend between the
  two Spaces, toward the label color when one side has no color.

## Transitions

The start page fades in over 0.2 seconds when it arrives and fades out over 0.2
seconds above the new page when a tab opens. Both are opacity only, so Reduce
Motion needs no separate path. The closing tab's page is removed at once rather
than fading out first.

## Visual review

Visual changes here go through the [interface review](visual-review.md):
render the options first, then build the approved direction. Two rounds
settled the current design. The first compared themes, sidebar states, frame
thickness, page card against edge-to-edge fill, texture, mark treatments and
the Easter egg candidates; the card and the three Easter eggs were approved.
The second replaced the lifted card with the flat soft-fill bar and the
translucent empty-card look with Note paper. The build scripts and pages live
in ignored `work/start-page/review/`.

## Source and checks

- `Sources/ParcApp/StartPageView.swift`: layout, background, chrome, dragging.
- `Sources/ParcApp/StartPageMarkView.swift` and `StartPageMarkStage.swift`: the
  mark, its layers and cleanup; `StartPageMarkGesture.swift`,
  `StartPageMarkEasterEgg.swift`, `StartPageMarkMotion.swift`,
  `StartPageMarkTaffy.swift`, `StartPageMarkSwoop.swift` and
  `StartPageMarkCharge.swift`: the Easter eggs.
- `Sources/ParcApp/NotePaper.swift`: the paper shared with Notes.
- `Sources/ParcApp/CommandBarResidentLayout.swift` and
  `CommandBarResidentLifetime.swift`: the resident bar.

```sh
python3 tests/StartPage/check.py
python3 tests/StartPageMark/check.py
python3 tests/CommandBar/resident_check.py
python3 tests/EmptyWindow/check.py
```

The first renders the page and the window's surface offscreen and compares
their gradients. The empty-window check covers the sidebar rule, Command-T and
Command-L routing and the start page's focus conditions.

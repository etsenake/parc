# Start page

A Space with no open tab shows a start page: the multi-colour Parc mark above a
resident command bar, on solid paper tinted from the Space's own colors. It
replaced the "No tab open" placeholder, and the sidebar no longer refuses to hide in an empty window, so
Command-S works there like anywhere else.

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
- Like the page, it follows the light or dark appearance the window has, which
  View → Appearance sets for websites, Easels and Notes; it takes no light or
  dark override from the Space's theme. Its selection color still comes from
  the theme.
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

The page is solid paper tinted from the Space's theme, with each theme color
glowing in from its own corner, so it reads as a page rather than colored glass
(`StartPagePaper.swift`).

- The tint is the average of the theme's colors mixed 84% toward white in a
  light appearance, or 82% toward near-black in a dark one.
- Each color glows from its corner: the first from the top left, the second
  from the right edge, the third from the bottom. A glow's radius is 62% of the
  page's long side, fading from 55% opacity at its centre (42% in dark) to
  nothing. A single-color theme has one glow; a colorless theme is plain solid
  paper.
- The theme's grain texture at its usual 100-point pitch and a fine paper
  noise sit over everything, lighter in dark.
- Light or dark follows the window's appearance, which View → Appearance sets,
  not the Space theme's own light or dark choice. Private windows use the
  private palette on dark paper.
- Everything is static layers: nothing redraws at rest. A Space swipe
  cross-fades the two Spaces' glows and blends their tints.
- The page card stays: the [window frame](window-frame.md) setting still
  applies, and the textured frame reads as a border around the paper.

## The mark

- `StartPageMarkView` shows Parc's multi-colour mark, 65 points wide, 24 points
  above the bar, with the pair centered at 45% of the page height.
- It is decorative for accessibility, and dragging on it never moves the window.
- Its `style` can still switch to the monochrome mark filled with the Space's
  textured gradient; nothing uses that today.

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
- **Swoop:** three quick clicks, each within the system double-click
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
- Reduce Motion keeps the mark still: Taffy and Swoop play a short shimmer
  through the theme's colors; Charge-up keeps its glow while held, since it is
  light rather than motion, and shimmers on a charged release.
- A haptic tick marks Taffy's release, each landing and the Reduce Motion
  shimmer, through the system haptic call the theme editor uses; the
  tab-reordering haptic switch doesn't apply. There is no sound.

## Transitions

The start page fades in over 0.2 seconds when it arrives and fades out over 0.2
seconds above the new page when a tab opens.

Closing the last open tab in a Space with Command-W, its close button or Close
Tab crossfades: the page fades out while the start page fades in beneath it,
both over the Space's own color, so a wash of that color glows through mid-way.

- The fade reuses the [Peek close fade's](peek.md#swiping-and-closing) order,
  timing and curve: 0.2 seconds, eased out. The start page's opacity is locked
  to the page's, so the two move as one.
- The engine destroys a page's picture before Parc learns its close went
  through, so the live page fades first and the real close starts once it is
  invisible, about 0.2 seconds after the request. The tab's sidebar row leaves
  then.
- During the fade the page takes no clicks or typing. When the close lands the
  start page is already showing, so only its command bar fades in, over 0.15
  seconds, and takes focus by the usual rule.
- If the page asks "Leave site?", it fades back in under the question. Stay
  brings it back with its focus; Leave removes it at once.
- Undo and Reopen Closed Tab wait until the close lands, so they bring back
  this tab rather than an older one.
- Switching tab or Space mid-fade hides the page at once and still closes it.
  Closing several tabs together, such as clearing Today, and a page closing
  itself still swap at once.

Every transition here is opacity only, so Reduce Motion keeps them; a refused
close comes back in Peek's 0.15-second Reduce Motion fade. `TabCloseFade` runs
the close fade, and `BrowserWindowController+CloseFade.swift` places the start
page beneath the closing page and hands it over when the close lands.

## Visual review

Visual changes here go through the [interface review](visual-review.md):
render the options first, then build the approved direction. Two rounds
settled the current design. The first compared themes, sidebar states, frame
thickness, page card against edge-to-edge fill, texture, mark treatments and
the Easter egg candidates; the card and the three Easter eggs were approved.
The second replaced the lifted card with the flat soft-fill bar. Image renders
of the theme's own blend made solid, a frosted panel and tinted paper with
glows then settled the background on tinted paper, the multi-colour mark, and a
page and bar that follow View → Appearance. A later round compared ways to close
the last tab (a cut, fade out then in, a crossfade over the start page, and
both fading over the Space color) and chose both fading. The render scripts and
images live in ignored `work/start-page/`.

## Source and checks

- `Sources/ParcApp/StartPageView.swift`: layout, background, chrome, dragging.
- `Sources/ParcApp/StartPageMarkView.swift` and `StartPageMarkStage.swift`: the
  mark, its layers and cleanup; `StartPageMarkGesture.swift`,
  `StartPageMarkEasterEgg.swift`, `StartPageMarkMotion.swift`,
  `StartPageMarkTaffy.swift`, `StartPageMarkSwoop.swift` and
  `StartPageMarkCharge.swift`: the Easter eggs.
- `Sources/ParcApp/StartPagePaper.swift`: the tinted paper and its glows.
- `Sources/ParcApp/CommandBarResidentLayout.swift` and
  `CommandBarResidentLifetime.swift`: the resident bar.
- `Sources/ParcApp/TabCloseFade.swift` and
  `BrowserWindowController+CloseFade.swift`: the close fade.

```sh
python3 tests/StartPage/check.py
python3 tests/StartPageMark/check.py
python3 tests/CommandBar/resident_check.py
python3 tests/EmptyWindow/check.py
```

The first checks the paper's tint, glows, appearance and swipe hand-off, and
runs the close fade on a pretend clock: its curve and lock, when the real close
starts, "Leave site?", refusal, interruption and Reduce Motion. The
empty-window check covers the sidebar rule, Command-T and Command-L routing,
the start page's focus conditions and how the window wires the close fade.

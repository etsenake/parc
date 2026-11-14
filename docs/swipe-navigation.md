# Swipe navigation

A two-finger horizontal swipe on a trackpad, or a one-finger swipe on a Magic
Mouse, moves a page Back or Forward. Parc recognizes the gesture itself. This
guide covers how that works, including in windows that aren't in focus, the
indicator's look and the swipe-and-hold history list.

## How it works today

Parc supplies each page's renderer-view delegate, `PCNativeHistorySwipeDelegate`
in [native_history_swipe.mm](../Engine/ParcNative/native_history_swipe.mm). It
is a thin forwarder: it hands Parc's recognizer what Chromium's public delegate
protocol provides (touches, every scroll event, the page's answer to the first
scroll and its overscroll behavior) and cancels the gesture when the page's
renderer view goes away. The Swift half,
[HistorySwipeForwarder.swift](../Sources/ParcApp/HistorySwipeForwarder.swift)
and [HistorySwipeDriver.swift](../Sources/ParcApp/HistorySwipeDriver.swift),
runs one recognizer per renderer view and applies each answer: consume the
scroll event, start or stop AppKit's tracked swipe, warm a likely Back
navigation and schedule the next clock tick. Chromium's history swiper and grey
arrow never run, and Parc patches no Chromium file for swipes.

The page gets the gesture first: Back or Forward can begin only when the page
leaves the first scroll unconsumed and its CSS overscroll behavior lets
horizontal overscroll through, so carousels, maps and editors keep their own
horizontal scrolling. Developer Tools pages, which Chromium marks as never
swiping, don't swipe, and neither do pages in a Profile Parc doesn't host.

When a swipe begins, a session records the page's own history. The indicator,
`HistorySwipeOverlayView`, goes in the page host's click-through history
container, above the pane's compositor and clipped to the gesture's own pane,
so Split and Peek stay correct. It takes the window's palette (private windows
use the private palette) and the session's history rows, adjacent entry first,
receives every recognizer output, and is removed once its commit or cancel
animation ends.

A commit moves the page Back or Forward with Chromium's per-page navigation,
the call the page's own Back and Forward make; a pick from the history list goes
to that entry with Chromium's index navigation, as the Back/Forward chooser
does. Both first check that the page's history is unchanged since the swipe
began, so history and POST state behave as they do for the page's own
Back/Forward. A cancelled swipe never navigates late: a cancelled session
refuses every commit, an AppKit tracker that ends after a cancel is stopped by
its generation, and the session ends with the page's renderer view. The
indicator follows Reduce Motion ([the look](#planned-the-new-look)).

## Windows that aren't in focus

A swipe belongs to the page under the gesture whenever that page can go that
way and nothing covers it. macOS delivers scroll gestures to the window under
the pointer whatever has focus, and Parc's recognizer never asks about focus.
Swiping works while another app is frontmost, over a Parc window behind another
one, with keyboard focus in the address field, the sidebar or another control,

- `nativeBrowser(_:allowsHistorySwipeFor:)` in
  [BrowserWindowController.swift](../Sources/ParcApp/BrowserWindowController.swift)
  accepts any visible split pane, an Easel's selected page or the active Peek.
  An open Peek covers every pane, so only the Peek swipes then. It refuses
  while a sheet is attached, a menu is tracking, the command bar, Library, tab
  switcher, Back/Forward chooser, capture, theme popover or a deferring Site
  Control Center covers the window, or the window or a tab is closing,
  transferring or retiring.
- `CanNativePageHistorySwipe` in
  [native_appkit_page.mm](../Engine/ParcNative/native_appkit_page.mm) requires a
  live, attached page in a visible, unminiaturized window with no sheet or
  security reservation. It doesn't ask whether Parc is active, the window is
  key or the page has keyboard focus.
- The swipe session records the page's own history when the swipe begins,
  checks at commit that it is unchanged, and then moves that page Back or
  Forward, or to the picked entry, with Chromium's per-page navigation. The
  page's Back/Forward actions and the history chooser reach only the selected
  page of the key window, so an unselected pane never borrows them. Navigation,
  page change, visibility loss, destruction, close, miniaturize, sheet,
  security change, tab deactivation and detach cancel it; the window resigning
  key or Parc resigning active don't.

A background swipe never activates Parc, raises the window, changes the
selected pane or moves keyboard focus. `python3 tests/HistorySwipeTargets/check.py`
runs model tests of which panes can swipe, checks that the shell, engine and
session rules keep each refusal and commit through the per-page path, and
checks that those rules and both halves of the forwarder call none of the
focus, key-window or activation APIs.

## How Dia does it

Dia replaced Chromium's arrow with its own gesture module:

- A Swift port of Chromium's recognizer, fed by the web view's touch, scroll and
  renderer-acknowledgement callbacks, with the same Magic Mouse fallback and no
  focus checks.
- An overlay controller that is asked whether a gesture may begin, follows its
  position, and on release commits either the adjacent navigation or the
  selected row of a destination list.
- A frosted circle with a chevron that rides the gesture. Armed, it grows and a
  confirmation wash fills it: white at 40% in light appearance, none in dark.
  The chevron grows and brightens but never moves.
- One exit for commit and cancel: the circle collapses in place with a blur and
  fade. A cancel doesn't spring back to the edge.
- A destination list of favicon-and-title rows that opens once the fingers rest
  0.3 seconds past the commit point, highlighting the current page. For Back it
  sits at the left edge, the current page at the bottom and older pages above.
  A long history grows the card past the pane; Dia doesn't scroll it.
- An event interceptor view that takes over the gesture once it belongs to
  navigation, so the page stops scrolling underneath.

Dia ignores Reduce Motion. Its sizes, springs, timings and colors were read
from its gesture module without running it; Parc's look below uses them.

## The recognizer

The state machine is the `ParcCore` model
[HistorySwipeRecognizer.swift](../Sources/ParcCore/HistorySwipeRecognizer.swift),
with its inputs, outputs and protocols in
[HistorySwipeInterface.swift](../Sources/ParcCore/HistorySwipeInterface.swift).

- States: waiting for the page, possible, tracking, armed past the commit point,
  holding, then completed or cancelled. Reversing below the commit point
  disarms, and closes the list if it is open; vertical drift cancels while the
  list is closed, and lifting a touch-driven swipe before the commit point
  navigates nowhere.
- Chromium's page-first rule holds: a swipe begins only after the page leaves
  this gesture's first scroll unconsumed and its overscroll behavior lets
  horizontal overscroll through, with the system's swipe-between-pages setting
  on. Direction follows Chromium's handling of natural scrolling.
- Finger positions drive progress, reversal and hold selection. A gesture
  without touches (a Magic Mouse, or a swipe that arrives without them) asks
  the forwarder to start AppKit's tracked swipe and follows its progress for
  adjacent Back/Forward only.
- Armed, the fingers must rest: every position update restarts the hold
  delay, so the list opens only once they stay put that long past the commit
  point. It opens on the current page. Vertical travel steps the selection one
  row at a time, away from the current page, with a detent, and fingers held
  near the trackpad's top or bottom edge keep stepping through a long history.
  Sliding back below the commit point closes the list and disarms, and the
  swipe carries on; rearming and resting reopens it. Lifting picks the
  selected entry; lifting on the current page, or sliding back past where the
  swipe began once the list has opened, cancels.
- Its environment answers only the system setting, whether anything covers the
  page and how many entries lie each way. Focus, the key window and the active
  app never enter it.

Each input (touches, scroll events, the page's scroll answers, its overscroll
behavior, AppKit tracked-swipe updates, clock ticks and cancels) answers
whether to consume the event, start or stop AppKit tracking, hint a likely Back
navigation, and when the next clock tick is due, for the hold and for edge
stepping. The hold's tick is a wake-up, not a deadline that moves with every
touch: a tick that finds the fingers moved since only books the next one, so
the forwarder doesn't reschedule a timer per touch. The outputs are begin with
the direction, progress (clamped and rubber-banded), armed, hold, selection,
the row remainder (how far the fingers sit past the selected row, in rows),
detent, commit (the adjacent page or an entry some rows away) and cancel.

Distances are fractions of the trackpad. Chromium's history swiper sets the
gesture rules: commit at 0.08, take the events at 0.01, and cancel when
vertical travel exceeds twice the horizontal, when 1.3 times the vertical travel
exceeds the horizontal once it passes 0.01, or when it passes 0.24 in total.
While an armed swipe waits for the list, vertical travel counts from the armed
point as net movement, so a resting hand's tremor can't cancel it. A tracked
swipe looks armed at 0.3 of AppKit's gesture amount, but AppKit's own end of the
swipe decides the commit, as in Chromium. Dia's feel sets the rest: a 0.15
rubber band past the commit point, a 0.3-second hold counted from the last
finger movement, a 0.08 row step, and edge stepping every 0.1 seconds within
0.15 of the edge. Parc adds a 0.03 edge margin: stepping waits for that much
travel toward the edge since the list opened, and stops only that far outside
the zone, so tremor at the zone's boundary neither starts nor stops it.

## Planned: the new look

[HistorySwipeOverlayView.swift](../Sources/ParcApp/HistorySwipeOverlayView.swift)
draws the indicator and the list to Dia's values, with the geometry and motion
as pure functions in
[HistorySwipeOverlayMotion.swift](../Sources/ParcApp/HistorySwipeOverlayMotion.swift).
It is made for the forwarder to place over the swiping pane's page and feed
every recognizer output. It is click-through, hidden from accessibility and
clipped to that pane, so Split and Peek stay correct.

- **Circle:** 72 points across on the system popover material, with a 1-point
  ring (white 15% in dark, black 12.5% in light) and a soft black shadow (25%
  in dark, 20% in light). A bold 28-point chevron points the way in the label
  color at half opacity.
- **Tracking:** the circle starts fully hidden past the pane's edge on the
  swipe side, vertically centered, and follows the fingers with no lag. At the
  commit point its edge sits 14 points inside the pane. Beyond it the
  recognizer's 0.15 rubber band resists, so twice the commit distance carries an
  armed circle about 26 points in.
- **Armed:** the circle springs to 82 points and the chevron to 34 (damping
  0.70, response 0.18 s); the chevron reaches full opacity and the light wash
  fills the circle over 0.18 seconds on an ease-out. The trackpad plays one
  level-change haptic. Backing off reverses it silently.
- **Commit and cancel:** both collapse in place over 0.2 seconds, easing in to
  1% scale with a 10-point blur and a fade. Cancel just doesn't navigate.
- **Appearance:** the overlay takes the Space palette's content appearance, as
  the page loading indicator does, so a light or dark Space and private windows
  (always dark) pick the matching ring, shadow, wash and highlight. There is no
  Space accent.
- **Reduce Motion:** nothing slides, grows, blurs or morphs. The circle stays
  hidden for the first 20% of travel, then a static 72-point circle crossfades
  in at its resting spot, 14 points inside the edge, over 0.12 seconds. Arming
  crossfades the wash and chevron; the list replaces the circle with a
  0.15-second crossfade, rows step without sliding, and the exit is a
  0.15-second fade. Haptics stay.

The page itself doesn't slide: that would need a picture of the destination
page on every swipe.

## Swipe and hold for history

Swipe past the commit point and rest your fingers there: once they have stayed
put for 0.3 seconds, the circle morphs into that direction's history, Back at
the left edge and Forward at the right. As in Dia, every movement while armed
restarts the wait, and a resting hand's tremor can't cancel it.

- The card springs out of the circle (damping 0.77, response 0.22 s) while the
  chevron and list swap over 0.22 seconds with a 10-point blur and a 0.9 scale.
  A generic haptic marks the opening.
- The card is 200 points wide with 38-point rows inside 8-point insets, an
  18-point radius and the circle's material, ring and shadow. Rows show a
  16-point favicon (a globe when there is none) and a 13-point title. A
  10-point-radius highlight at 10% white or black marks the choice. Back keeps
  the card's left edge on the circle's, Forward its right.
- Rows come from the swipe's own per-page history snapshot, adjacent entry
  first. Back puts the current page at the bottom and older pages above;
  Forward puts it at the top and newer pages below.
- The list opens with the current page highlighted, its row centred where the
  circle was, so lifting at once navigates nowhere.
- Two fingers moving up step a Back list, and moving down a Forward list, one
  row per 8% of trackpad height with an alignment haptic each. The other way
  heads back to the current page. The card slides on a spring (damping 0.9,
  response 0.27 s) so the highlight stays under the fingers, and between rows
  it leans a few points toward the next one, on Dia's 0.1 rubber band over a
  row's height.
- Long histories scroll: the card stays 14 points inside the pane and shows a
  window onto its rows. Fingers within 15% of the trackpad's top or bottom
  edge keep stepping ten rows a second toward that end, a selection and detent
  per row, so every entry is reachable. The steps start only after the fingers
  move 3% of the trackpad toward that edge since the list opened, and stop
  only once they move 3% back out of the zone, so a list that opens near an
  edge waits and tremor at the boundary does nothing.
- Sliding back below the commit point folds the card back into the circle on
  the same spring and swap and disarms it; the swipe carries on. Swiping out
  again and resting another 0.3 seconds reopens the list on the current page,
  picking up mid-animation if the fold hasn't finished. Sliding on past where
  the swipe began cancels.
- Lifting navigates to the selected entry; lifting on the current page
  cancels.
- With Reduce Motion the card and circle replace each other with a
  0.15-second fade both ways, rows step without sliding or leaning, and an open
  list never fades with short travel: it closes first, and the circle then
  hides below 20% of travel.
- It works in background windows, like the plain swipe. The Back/Forward
  chooser remains the keyboard and VoiceOver path to the same history.

`python3 tests/HistorySwipeOverlay/check.py` model-tests the overlay's geometry
and motion, including the fold back into the circle and the reopen, the lean,
Reduce Motion, narrow panes, long lists and runs through the real recognizer,
then compiles the view itself to check its pane clip, click-through,
accessibility, material, shadow and ring.

## Review and checks

Changes to the look follow the [interface review](visual-review.md) workflow:
approve renders or animated mockups of tracking, armed, commit, cancel and
hold, in light, dark and private themes and under Reduce Motion, before tests
or review. A live look-and-feel pass in Parc follows that guide's runtime
boundary.

- `python3 tests/HistorySwipe/check.py` runs the recognizer over recorded event
  sequences: trackpad, Magic Mouse, page-consumed scroll,
  `overscroll-behavior: none`, vertical cancel, reversal, hold and selection,
  and background windows.
- `python3 tests/HistorySwipeDriver/check.py` drives the forwarder's Swift half:
  sessions, commits and list picks, refused and late navigation, engine
  cancels, clock ticks and AppKit tracking.
- `python3 tests/HistorySwipeTargets/check.py` covers which panes can swipe and
  the focus-free rules above.
- Swift typecheck and whole-module SIL cover the app; the engine build compiles
  the forwarder's engine half.

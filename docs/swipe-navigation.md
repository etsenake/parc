# Swipe navigation

A two-finger horizontal swipe on a trackpad, or a one-finger swipe on a Magic
Mouse, moves a page Back or Forward. This guide covers how that works today,
including in windows that aren't in focus, and the planned Parc-owned gesture
with a new look and a swipe-and-hold history list. The open items are indexed
in the [backlog](backlog.md#planned-interface-work).

## How it works today

Page history gestures use Chromium's history swiper. The page gets the gesture
first: Back or Forward can begin only when the page leaves the first scroll
unconsumed and its CSS overscroll behavior lets horizontal overscroll through,
so carousels, maps and editors keep their own horizontal scrolling. The shell
adds no competing recognizer.

Parc supplies the renderer view's delegate, `PCNativeHistorySwipeDelegate` in
[native_history_swipe.mm](../Engine/ParcNative/native_history_swipe.mm). It
wraps Chromium's recognizer with Parc's eligibility check and moves the
gesture's own page Back or Forward with Chromium's per-page navigation. A
gesture keeps its original page, document, window and pane; navigation,
transfer, a security change, or the window closing, miniaturizing or showing a
sheet cancels it. Delayed Magic Mouse work checks the same generation.

Chromium's grey semicircle arrow is drawn inside the original page's clipped
pane, including Split and Peek. Reduce Motion keeps static edge feedback, and no
extra haptic is played. The kept Chromium patch
[`native-history-swipe-direct`](chromium-hooks-browser.md) stops a cancelled
same Chromium arrow.

## Windows that aren't in focus

A swipe belongs to the page under the gesture whenever that page can go that
way and nothing covers it. macOS delivers scroll gestures to the window under
the pointer whatever has focus, and Chromium's recognizer never asks about
focus, so Parc doesn't either. Swiping works while another app is frontmost,
over a Parc window behind another one, with keyboard focus in the address
field, the sidebar or another control, and over any visible split pane, as it

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
- The swipe session records the page's own history when it starts, checks at
  commit that it is unchanged, and then moves that page Back or Forward with
  Chromium's per-page navigation, so an unselected pane never borrows the
  selected page's commands. Navigation, page change, visibility loss,
  destruction, close, miniaturize, sheet, security change, tab deactivation and
  detach cancel it; the window resigning key or Parc resigning active don't.

A background swipe never activates Parc, raises the window, changes the
selected pane or moves keyboard focus. `python3 tests/HistorySwipeTargets/check.py`
runs model tests of which panes can swipe, checks that the shell, engine and
session rules keep each refusal, and checks that those rules call none of the
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

## Planned: a Parc-owned gesture

Replace Chromium's recognizer and arrow for Parc pages with Parc code, reached
through the delegate Parc already supplies. Chromium's public renderer-view
delegate protocol already hands that object everything a recognizer needs:
every scroll event (with the power to consume it), touch began, moved, ended
and cancelled, the page's answer to the first scroll, and its overscroll
behavior. No Chromium change is needed.

The state machine exists as a `ParcCore` model,
[HistorySwipeRecognizer.swift](../Sources/ParcCore/HistorySwipeRecognizer.swift),
with its inputs, outputs and protocols in
[HistorySwipeInterface.swift](../Sources/ParcCore/HistorySwipeInterface.swift).
Nothing feeds it yet, so Chromium's recognizer still runs every swipe.

- States: waiting for the page, possible, tracking, armed past the commit point,
  holding, then completed or cancelled. Reversing below the commit point
  disarms, vertical drift cancels before the hold, and lifting a touch-driven
  swipe before the commit point navigates nowhere.
- Chromium's page-first rule holds: a swipe begins only after the page leaves
  this gesture's first scroll unconsumed and its overscroll behavior lets
  horizontal overscroll through, with the system's swipe-between-pages setting
  on. Direction follows Chromium's handling of natural scrolling.
- Finger positions drive progress, reversal and hold selection. A gesture
  without touches (a Magic Mouse, or a swipe that arrives without them) asks
  the forwarder to start AppKit's tracked swipe and follows its progress for
  adjacent Back/Forward only.
- Armed for the hold delay, the list opens on the adjacent entry. Each row step
  of vertical travel moves one row, upward away from the current page, with a
  detent. Lifting picks the selected entry; lifting on the current page, or
  sliding back out past where the swipe began, cancels.
- Its environment answers only the system setting, whether anything covers the
  page and how many entries lie each way. Focus, the key window and the active
  app never enter it.

The forwarder feeds touches, scroll events, the page's scroll answers, its
overscroll behavior, AppKit tracked-swipe updates, a clock tick for the hold
and lifecycle cancels. Each input answers whether to consume the event, start
or stop AppKit tracking or hint a likely Back navigation, and when the hold is
due. The shell receives begin with the direction, progress (clamped and
rubber-banded), armed, hold, selection, detent, commit (the adjacent page or an
entry some rows away) and cancel, and adds the pane, title and favicon from the
history snapshot.

Defaults come from Chromium's history swiper, as fractions of the trackpad:
commit at 0.08, take the events at 0.01, and cancel when vertical travel exceeds
twice the horizontal, when 1.3 times the vertical travel exceeds the horizontal
once it passes 0.01, or when it passes 0.24 in total. While an armed swipe waits
for the list, vertical travel counts from the armed point as net movement, so
a resting hand's tremor can't cancel it. A tracked swipe looks armed at 0.3 of
AppKit's gesture amount, but AppKit's own end of the swipe decides the commit,
as in Chromium. Chromium has no rubber band, so progress stops at the
commit point. The hold delay is 0.5 seconds, Chromium's press-and-hold delay for
the Back button's menu, and the row step is 0.05. All are parameters for Dia's
values to replace. `python3 tests/HistorySwipe/check.py` runs the model tests.

Next, the forwarder feeds the model through the existing AppKit bridge client.
Commits and list picks go through the per-page history path background swipes
already use in `native_history_swipe.mm`, because the page's Back/Forward
actions and the history chooser reach only the selected page of the key window.
History and POST state must behave as they do for the page's own Back/Forward. Once no context uses Chromium's recognizer, remove
`native-history-swipe-direct` and update the [hooks reference](chromium-hooks.md)
in the same change. Removing a patch while preserving behavior needs no approval.

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

## Planned: swipe and hold for history

Swipe past the commit point and keep your fingers down: 0.3 seconds after
arming, the circle morphs into that direction's history, Back at the left edge
and Forward at the right.

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
- The list opens on the adjacent entry under the fingers, so lifting at once
  still goes one page, and the dwell counts from arming, so a resting hand's
  tremor can't hold it off. Both differ from Dia.
- Two fingers moving up step a Back list, and moving down a Forward list, one
  row per 8% of trackpad height with an alignment haptic each. The other way
  heads back to the current page. The card slides on a spring (damping 0.9,
  response 0.27 s) so the highlight stays under the fingers.
- Long histories scroll: the card stays 14 points inside the pane and shows a
  window onto its rows. Fingers resting within 15% of the trackpad's top or
  bottom edge keep stepping ten rows a second toward that end, a selection and
  detent per row, so every entry is reachable. The steps start only after the
  fingers move into that zone, so a list that opens near an edge waits.
- Lifting navigates to the selected entry. Lifting on the current page, or
  sliding back out past where the swipe began, cancels.
- It works in background windows, like the plain swipe. The Back/Forward
  chooser remains the keyboard and VoiceOver path to the same history.

`python3 tests/HistorySwipeOverlay/check.py` model-tests the overlay's geometry
and motion, including Reduce Motion, narrow panes, long lists and a run through
the real recognizer.

## Build order and review

1. Parc-owned recognizer with the new look, then retire the Chromium patch.
2. Swipe and hold.

Both steps follow the [interface review](visual-review.md) workflow. Start
from a Dia reference recording, and approve renders or animated mockups of
tracking, armed, commit, cancel and hold, in light, dark and private themes and
under Reduce Motion, before tests or review. A live look-and-feel pass in Parc
follows that guide's runtime boundary.

Checks: recognizer model tests over recorded event sequences (trackpad, Magic
Mouse, page-consumed scroll, `overscroll-behavior: none`, vertical cancel,
reversal, hold and selection, background window), Swift typecheck and SIL, and
an authorized engine build for the forwarder.

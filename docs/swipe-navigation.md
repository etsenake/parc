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
wraps Chromium's recognizer with Parc's eligibility check and navigates through
the page's own Back/Forward actions. A gesture keeps its original page, document,
window and pane; navigation, transfer, selection, security or window changes
cancel it. Delayed Magic Mouse work checks the same generation.

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
checks these rules.

## How Dia does it

Dia replaced Chromium's arrow with its own gesture module:

- A Swift port of Chromium's recognizer, fed by the web view's touch, scroll and
  renderer-acknowledgement callbacks, with the same Magic Mouse fallback and no
  focus checks.
- An overlay controller that is asked whether a gesture may begin, follows its
  position, and on release commits either the adjacent navigation or the
  selected row of a destination list.
- A capsule view that rides the gesture, an animated Gaussian blur, and a
  confirmation wash at commit: white at 40% in light appearance, none in dark.
- A destination list of favicon-and-title rows shown when you swipe and hold.
  For Back it sits at the left edge, the current page at the bottom and older
  pages above, with a rounded highlight on the chosen row.
- An event interceptor view that takes over the gesture once it belongs to
  navigation, so the page stops scrolling underneath.

Dia's binary is stripped, so its timings, distances, springs, blur radius and
hold delay come from a targeted decompile of that module or a reference screen
recording of Dia's swipe.

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
  disarms, vertical drift cancels before the hold, and lifting before the
  commit point navigates nowhere.
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
twice the horizontal, 1.3 times it beyond 0.01, or 0.24 in total. A tracked
swipe commits at 0.3. Chromium has no rubber band, so progress stops at the
commit point. The hold delay is 0.5 seconds, Chromium's press-and-hold delay for
the Back button's menu, and the row step is 0.05. All are parameters for Dia's
values to replace. `python3 tests/HistorySwipe/check.py` runs the model tests.

Next, the forwarder feeds the model through the existing AppKit bridge client.
Commits use the page's existing Back/Forward actions, and list picks use the
same index navigation as the Back/Forward history chooser, so history and POST
state behave identically. Once no context uses Chromium's recognizer, remove
`native-history-swipe-direct` and update the [hooks reference](chromium-hooks.md)
in the same change. Removing a patch while preserving behavior needs no approval.

## Planned: the new look

Dia's motion is the starting reference, made Parc's own:

- A capsule grows out of the pane's edge on the swipe side and follows the
  fingers with rubber-band resistance. It carries the direction arrow and can
  show the destination's favicon.
- At the commit point the capsule fills with the Space's accent, the arrow
  nudges forward and a trackpad haptic ticks once. Backing off reverses all three.
- Releasing armed commits: the capsule leaves and the light-appearance wash
  flashes over the pane. Releasing early springs it back.
- Colors come from the Space palette, private windows use the private palette,
  and nothing draws outside the pane, so Split and Peek stay correct.
- Reduce Motion: no stretch, blur or morph. A static capsule appears when
  armed, and the wash becomes a short fade.

Whether the page itself slides is open for the visual review. The default is
no: a sliding page needs a picture of the destination page, which costs
capture work on every swipe.

## Planned: swipe and hold for history

Swipe, keep your fingers down past the commit point, and the capsule morphs into
a list of that direction's history. It works in both directions: Back at the
left edge, Forward at the right.

- The list opens after a short dwell. Dia's delay is the reference, with the
  value tuned in review.
- Rows show favicon and title from the same history snapshot as the Back/Forward
  chooser, with the current page at the inner end. Reuse the chooser's row and
  card styling ([navigation](navigation.md#history-chooser-presentation)) unless
  the review wants Dia's denser rows.
- Moving two fingers vertically steps the selection one row at a time, with a
  haptic detent per row. Long histories scroll with the selection.
- Lifting navigates to the selected entry. Lifting on the current page, or
  sliding back out past the edge, cancels.
- It works in background windows, like the plain swipe. The Back/Forward
  chooser remains the keyboard and VoiceOver path to the same history.

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

# Swipe navigation

A two-finger horizontal swipe on a trackpad, or a one-finger swipe on a Magic
Mouse, moves a page Back or Forward. This guide covers how that works today,
the defect with windows that aren't in focus, and the planned Parc-owned gesture
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

Swiping over a page does nothing when:

- another app is frontmost, even though the pointer is over a Parc window;
- the Parc window under the pointer is not the frontmost Parc window;
- keyboard focus sits in the address field, the sidebar or another control
  instead of the page;
- in a split, the pointer is over a pane other than the selected one.

bringing the window forward; Dia even shows its swipe history list in a
background window while another app is frontmost. macOS delivers scroll
gestures to the window under the pointer whatever has focus, and Chromium's
recognizer never asks about focus. The restriction is Parc's own, in three places:

- `CanNativePageHistorySwipe` in
  [native_appkit_page.mm](../Engine/ParcNative/native_appkit_page.mm) requires
  Parc to be the active app and the window's first responder to be inside the page.
- `nativeBrowser(_:allowsHistorySwipeFor:)` in
  [BrowserWindowController.swift](../Sources/ParcApp/BrowserWindowController.swift)
  requires the key window and the window's selected page.
- The swipe session cancels when its window resigns key or Parc resigns active.

**Fix.** A swipe belongs to the page under the gesture whenever that page can go
that way and nothing covers it.

- Keep refusing when a sheet is attached, a menu is tracking, the command bar,
  Library, tab switcher, capture, theme popover or a deferring Site Control
  Center covers the window, the window or tab is closing, transferring or
  retiring, or the window holds a security reservation. Keep checking at commit
  that the history snapshot is unchanged.
- Stop requiring an active app, a key window, keyboard focus in the page or the
  selected pane. Any visible split pane, or the active Peek, can swipe.
- Keep cancelling on navigation, page change, visibility loss, destruction,
  close, miniaturize, sheet, security change, tab deactivation and detach.
  Stop cancelling on resign key and resign active.
- A background swipe never activates Parc, raises the window, changes the
  selected pane or moves keyboard focus.

This touches only Parc-owned engine files and Swift, needs no Chromium change and
can ship before the new look. The engine half needs an authorized engine build.

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

- Keep the delegate a thin forwarder. Put the state machine in `ParcCore` Swift,
  so it is checked with model tests and iterates without engine builds; the
  forwarder needs one engine build.
- States: waiting for the page, possible, tracking, armed past the commit point,
  holding, then completed or cancelled. Reversing below the commit point
  disarms. Vertical drift cancels before the hold, as Chromium does.
- Keep Chromium's page-first rule and its direction handling for natural
  scrolling.
- With touch callbacks, finger positions drive progress, reversal and hold
  selection. Without them (a Magic Mouse, or any gesture that arrives without
  touches), AppKit's tracked swipe reports progress; adjacent Back/Forward works
  there, while the hold list needs finger positions.
- The shell gets begin (direction, pane, destination title and favicon from the
  history snapshot), progress, armed, hold, selection, commit and cancel through
  the existing AppKit bridge client.
- Commits use the page's existing Back/Forward actions, and list picks use the
  same index navigation as the Back/Forward history chooser, so history and
  POST state behave identically.

Once no context uses Chromium's recognizer, remove `native-history-swipe-direct`
and update the [hooks reference](chromium-hooks.md) in the same change. Removing
a patch while preserving behavior needs no approval.

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

1. Unfocused-window fix, on today's look.
2. Parc-owned recognizer with the new look, then retire the Chromium patch.
3. Swipe and hold.

Steps 2 and 3 follow the [interface review](visual-review.md) workflow. Start
from a Dia reference recording, and approve renders or animated mockups of
tracking, armed, commit, cancel and hold, in light, dark and private themes and
under Reduce Motion, before tests or review. A live look-and-feel pass in Parc
follows that guide's runtime boundary.

Checks: recognizer model tests over recorded event sequences (trackpad, Magic
Mouse, page-consumed scroll, `overscroll-behavior: none`, vertical cancel,
reversal, hold and selection, background window), Swift typecheck and SIL, and
an authorized engine build for the forwarder.

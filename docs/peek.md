# Peek ownership

Peek keeps an unsaved original `PCNativePage` and one `PCBrowserView` in its
source window. The native navigation adapter supplies the real request/source
relationship; the shell does not cancel and replay a URL. Profile, parent tab,
physical window and native binding must agree before adoption.

`PeekController` owns presentation/delegate; the browser window retains exact
page/parent sessions separately from saved tabs. Changing tab/Space hides without
disposing the document, and returning reveals the same page. Native selected/
visible-page callbacks expose Peek to security, page tools, extensions, media,
capture and fullscreen. The parent stays rendered behind the scrim.

## Dismissal and retirement

Close always uses genuine `requestClose`; beforeunload refusal preserves the page.
A fresh Escape can request Close confirmation; pointer/swipe/Close Tab during
microphone/camera capture requests Hang up. A pending Close can be confirmed by
an existing dismissal entry. Pending Hang up requires Escape, native Exit, Close
or Close Tab; repeated background/swipe attempts retain it and restart its timer,
even after capture stops. Attempt counts never imply automatic forced close.

Escape confirmation expires after one second; capture confirmation after ten.
Replacement, hide, actual close or owner retirement cancels the work item.
Expiry only resets controls, never closes/navigates/focuses a page. Weak owner
and generation checks prevent an old callback changing a newer presentation.

Parent and unsaved child join whole-set retirement. Peek protects its parent
from automatic archive. Independent parent destruction promotes a surviving
child to Today. Original parent-page adoption by another window uses the existing
collection transfer and rebinds the same child; no replacement page is created.
See [windows lifecycle](windows-lifecycle.md).

## Swiping and closing

On a Peek's first page, the two-finger swipe that would go Back grabs the card
instead; with pages behind it, the same swipe still goes Back. The card and its
side buttons follow the fingers, and the wash over the parent fades as the card
moves away. Letting go past halfway closes it, with one trackpad tap as the
swipe crosses that point, and a quick flick closes it sooner. Letting go
earlier, pulling back, flicking back toward the start or drifting mostly up or
down springs it back. A Magic Mouse follows AppKit's tracked swipe, and the
three-finger swipe some settings send closes with the same slide.
[Swipe navigation](swipe-navigation.md#peek-dismissal) covers the recognizer.

Every close Parc starts fades. A swipe slides the card on at its release speed
while it fades over 0.22 seconds; Escape, a click outside, Close and Close Tab
fade the card and wash together over 0.2 seconds. The page's genuine
`requestClose` runs once the card is invisible, so a close starts about 0.2
seconds after the request. As the card starts to go, the parent becomes the
window's selected page and, if the keyboard was in the Peek, takes it through
the usual focus return, so clicks, typing and page commands reach the parent
rather than the leaving page; when the parent can't take the keyboard yet, the
leaving page still lets go of it and the parent takes it as soon as it can,
which also covers coming back to a tab whose Peek is still leaving. If the page
then asks "Leave site?", the card comes back under the question (a swiped card
springs back, a faded one fades in), and a refusal without a question brings it
back too, each time with the selection and the keyboard; after Leave the card
goes with the page, without a second fade. A page that closes itself, or a Peek
closed while hidden, goes at once. During a call, a swipe past halfway springs
the card back beside the red Hang up confirmation. Reduce Motion replaces the
slide and springs with 0.15-second fades, and the drag dims the card instead of
moving it. A new swipe can't grab the card until it has settled.

If the parent tab or the whole window starts closing during the fade, the Peek's
close joins it: the card stays gone through any "Leave site?" question that
close asks, the page's own included, and the page closes with the tab or window,
with no return flash and no second close request. Should the tab or window stay
open, the Peek's own close carries on, unless a question came up meanwhile,
which counts as a refusal (the card comes back, under the page's question if
that is still showing) so nobody is asked twice. If the card is already back
under its own "Leave site?" when a tab close starts, its answer settles the Peek
at once: Leave closes it, Stay keeps it as it was, and the tab's close then
takes it along or leaves it. If only the parent page closes, on its own, the
waiting Peek becomes a Today tab as orphans do, and so does a Peek whose close
is refused after its parent has gone. Open in Peek hands the keyboard over in
the same way; its page goes back to its tab rather than closing, and a failed
hand-back brings the card, the selection and the keyboard back as a refusal
does.

`PeekCloseTransition` orders the drag, exit, close request, refusal, sheet
spring-back and the wait for a closing parent tab or window, and its exit timers
are generation-checked. Its leaving state drives the selection and keyboard
handover. Hiding a Peek mid-exit for a tab or Space switch hides it at once and
requests the close without waiting, and a retiring Peek goes invisible before
its view is removed, so no fading card lingers over a newer Peek or tab and
nothing flashes. `PeekDismissalMotion` is the pure spring, slide and fade model,
and `PeekDismissalAnimator` applies it to any card stage and wash view for reuse
by other Peek hosts; the host sets its geometry and resting wash and leaves the
stage's transform and opacity to it. `python3 tests/PeekSwipeDismissal/check.py`
checks `PeekCloseTransition` and `PeekDismissalMotion` with the real recognizer
and confirmation rules, including the keyboard handover and the wait for a
closing tab or window, plus the controller and window wiring.

## Promotion return ownership

Expand creates a Today record and reparents the same wrapper; Add to Split uses
that record in the existing split. Refused attachment restores the original Peek.
Accepted promotion records its original source in `referrerID` and
`activeTabBeforeCreationID`, and replaces the initiating window's return pool
only after attachment/claim succeeds. Refusal preserves the old pool. Closing
uses existing source-return selection, with surviving split panes taking priority.

A page entering tab fullscreen is promoted through this same transaction first.
New tabs created from Peek retain its parent tab as referrer. Orphan-preservation
promotion has its separate source-Space policy.

A promoted page is an ordinary tab from then on. The engine's creation marker
only hands a new page's parent to the window while it adopts the Peek; after
that the context menu, link routing, the hover capsule, page tools and swipe
targets ask the window what it is showing (`isPeekPage`,
`canNavigatePeekLinkFrom` and its selected and visible pages). An expanded Open
in Peek card counts the same way: its page is back in its tab before the card
fades, so its menu offers Open Link in Split View like any tab.

## Peeking at an existing tab

Open in Peek, on a folder preview card's tab row, shows that tab's own live page
in a Peek over the page you're on. The tab keeps its place in the sidebar and it
is the same page, so scroll position, form input, media and history come along
and nothing reloads: the window moves the tab's existing `PCBrowserView` from
its pane into the card and back. `TabPeekSession` and `TabPeekAdmission` in
ParcCore decide each step and `BrowserWindowController+TabPeek.swift` performs
it; a relay delegate keeps the sidebar row, address and history following the
page while it is in the card. An asleep tab reloads when shown, as it would in
its pane. A tab with no page gets its page created in its own hidden pane, with
its saved history, and moved into the card as soon as the engine hands it over.

Closing it (Escape, a click outside, a swipe, Close or Close Tab) plays the
usual close and then hands the page back to its tab, still loaded. The page is
never asked to close, so there is no beforeunload; you stay on your page, which
takes the keyboard as the card starts to go. The Escape confirmation still
applies, and during a call the pill reads Close rather than Hang up, since the
call carries on in its tab. Opening the tab normally (clicking it in the
sidebar, Expand, Open in [Space], the tab switcher, its Mini Player or the page
going fullscreen) moves the page back into its pane first, where the page-switch
hold keeps the old page up until it draws, then fades the emptied card with the
close fade, which follows the window's layout if the window is resized
meanwhile. Add to Split joins the tab to the current split the same way.
Switching tabs or Spaces, or closing, archiving or moving the tab, puts the page
back at once without a motion; closing the window closes it with the window's
other pages.

The item is offered only for a web tab in the current Space and Profile that
isn't on screen, closing, moving or failed, over a live web page in this window
that can host a Peek. A tab held by another window comes here through the
normal transfer first, or isn't offered when it can't move. If a Peek is
showing, it closes through its own close and consent, confirmation pill
included, and the tab opens once it is gone; a refused close or an expired
confirmation drops the request. While in Peek the tab neither
sleeps nor auto-archives. `tests/TabPeekTests.swift` covers admission, refusals,
replacement and the round trips, checking that the same page comes back, that
only a tab with no page loads, and that every way out of the card removes it or
plays its exit in the same step, so a hand-back never finds a stranded card.

## Open in current Space command

Open in [Space] is a menu/Shortcuts command with Command-O by default and Use Both
priority; it is not a command-search result. The command and Expand target the
current physical window's active Space after Profile/page checks. A Favorite
viewed in another same-Profile Space promotes there rather than its stored home.
Tracked menu actions retain modal/destination/window and reject replacement.
Binding changes/conflicts/removal/reset update the hint without stealing saved
customizations. Native security, sheet and marked-text gates remain enforced.

## Original current-tab links

Eligible activated outermost HTTP(S) links consult a default-off native policy
before Chromium creates its NavigationRequest. Negative admission continues the
original branch. Positive admission carries a one-use document/request token
through real OpenURL transport and security validation. Pinned/Favorite state,
current/saved hosts and existing authentication exceptions determine eligibility.
Forms, history, reloads and client redirects are not rerouted.

The synchronous query reads only materialized state: no UI, storage, new page/
Profile, renderer call, wait or nested loop. Weak frame/document and sequence
guards reject reentry, stale replies and consumed tokens. Real creation occurs
after return. Original body/referrer/initiator/security callbacks survive.
Specialized download, ad, injection, origin-trial and deferred-commit requests
retain their own path.

## Authentication continuation lifetime

A live WebContents retains intrinsic or authentication-unlocked state. Matching
authentication navigation keeps the previous source URL as baseline through
intermediate hosts. Returning to that host or the eligible saved target restores
intrinsic state. Missing transition data preserves prior state. While unlocked,
automatic Peek does not interrupt the pinned-tab flow.

The genuine main-frame address callback updates the baseline, including
same-document changes. State survives intermediate document replacement but a
fresh native page starts intrinsic. This continuation state belongs to the live
document and is not persisted.

## Native Escape ownership

Native-control Exit uses the AppKit responder chain. Renderer descendants and
native editors cannot enter a window-level fallback. Renderer Escape uses the
matching main-thread RawKeyDown acknowledgment and actual focused editability,
with OS repeat delay and a monotonic clock. Consumed/editable input requests
confirmation; eligible unconsumed input can close directly. No raw key monitor,
JavaScript query, synthetic acknowledgment or timeout closes Peek.

Admission binds Browser/page, selected Peek, physical key window, primary/focused
documents, node/widget and original timestamp/key/modifiers. IME, context menus,
security surfaces, keyboard lock, fullscreen and customized shortcuts retain
their own route. Outcomes are consumed once beyond observer iteration, then
revalidate all owners. Navigation, focus/visibility changes and other input
invalidate pending delivery. Only the exact acknowledged event suppresses fallback.

## Original responder entry and return

Focus uses the physical window's registered responder manager and exact selected,
attached, visible page. The app must be active/key and free of sheets, security
reservations or menus. Requesting focus does not select/activate the window or
prove actual renderer focus.

One-use weak return tokens protect asynchronous presentation. A close lends the
keyboard to the surviving parent as the card starts leaving; a refusal brings it
back to the original control/editor, and actual dismissal leaves it with the
parent; promotion returns to the same child after reparenting. Any newer
concrete responder permanently cancels return. Temporary nil/window focus during
teardown still needs fresh original-owner checks. Native traversal remains
intact.

## Presentation and remaining scope

The Peek floats above the whole window in its own layer: above the page card,
its shadow, the split grip and the side panel, below Find and the sidebar, so a
floating sidebar still covers it. The card takes 80% of the page card's width,
centred on it (narrow pages keep room for the controls), and sits 12 points from
the window's top and bottom at every frame thickness, reaching past the page card
into the frame. It has 8-point corners, a near-white or near-black fill, a
hairline edge and a soft 4-point shadow; the page fills the card and there is no
title band. A copy of the window's theme background covers the parent page card
at 70%, so the parent shows through at 30%, in light and dark themes alike. The
sidebar, side panel and split grip stay bright and keep working.

While a Peek shows, the parent steps back: the page card and its shadow, or a
split's whole group with each pane's card and shadow, shrink evenly about their
centre by 9 points at the sides and a little less at the top and bottom.
`PeekStepBack` applies this as a Core Animation transform on those layers, so
the page never relays out, resizes its renderer or redraws. The step rides with
the 0.3-second entry fade, follows the swipe and closing fade through the wash,
and drops at once when the tab changes or the Peek is promoted. When the sidebar
or Library slides, the step rides the slide's own animation, so the page stays
centred throughout; a Peek opening during a slide combines its entry with the
slide the same way, for as long as either runs. The frame crank's shudder adds
to it while the Peek card stays still. Reduce Motion keeps the page where it is. The page's own loading
bar hides while a Peek shows; the Peek's bar takes the gap above its card.

Clicks follow what you see (`PeekWindowLayout`). The card and its buttons are the
Peek and the faded page closes it. Everything else belongs to the window, including
the band of frame colour the step reveals: the top edge drags the window and a
right-click offers Adjust Window Frame. Toasts, Find, extension popups and the
Back swipe arrow stay with the card. Moving a tab with its Peek to another window
lands the Peek in that window's layer. The Library still opens over the layer, as
it opened over the page card, and an archive preview's card sits beside it.

Round Close, Expand and Split controls sit 13 points right of the card, filled
with the Space theme's background-extra colour and drawn in its primary ink (kept
dark enough on light themes). They lift on hover, shrink when pressed and show
tooltips to their right. Close confirmation widens Close into a red Close or Hang
up pill on a 0.25/0.8 spring; entry fades over 0.3 seconds. Reduce Motion
settles the entry and confirmation animations. Tab and Shift-Tab follow the
window key-view loop through the Peek's renderer and controls, excluding the
dimmed parent. Controls have
accessible names and the close-confirmation state announces its instruction.

Automatic Peek for links to other sites and Shift-click Peek are both on by
default for new users; this is a settled product decision. Either can be
switched off in Settings → Links. The engine's default-off policy flag is
enabled for registered pages.

Parent transfer, orphan preservation, promotion and new-tab provenance already
use the original page and parent identity. Model/native components cover those
transactions, confirmation timers, renderer acknowledgments and focus
cancellation; window key-loop checks cover forward and backward traversal.
`tests/PeekWindowHost` checks the card and step geometry, the step following a
slide or an opening during one, the click regions, and real view hit-testing for
the top edge, the revealed frame band, the split grip and the floating sidebar.

## Links inside a Peek

Peeks never stack or nest; this is a settled product decision. A tab has at most
one Peek, and a visible Peek admits no second card. An ordinary click navigates
the Peek's page, and a link the site opens in a new tab becomes an ordinary
new tab, as before.

Shift-click, the deliberate "peek at this" gesture, opens the link in that same
Peek. The engine turns the click's new-window request into an ordinary
current-tab navigation of the Peek's page, keeping the user gesture, referrer
and initiator, so the usual navigation rules apply and the page joins the Peek's
own Back and Forward history, two-finger swipe included. It does this only for
HTTP(S) links while Shift-click Peek is switched on and the Peek is the window's
shown, interactive Peek (`canNavigatePeekLinkFrom`). Otherwise a Shift-click in
a Peek opens a new window, as it did before. A private window's Peek stays in its private
Profile, and Space routing rules never apply to Shift-click.

Links in ordinary embedded frames take the same route as the page's own, inside
and outside a Peek; fenced ad frames keep Chromium's behaviour. Inside a Peek, an
embedded frame sandboxed against navigating the page keeps the new window, and
the hover capsule says so. Other modifier clicks keep their routes; see
[web interactions](web-interactions.md#hovered-link-status).

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
seconds after the request; meanwhile clicks pass through to the parent. If the
page then asks "Leave site?", the card comes back under the question (a swiped
card springs back, a faded one fades in), and a refusal without a question
brings it back too; after Leave the card goes with the page, without a second
fade. A page that closes itself, or a Peek closed while hidden, goes at once.
During a call, a swipe past halfway springs the card back beside the red Hang
up confirmation. Reduce Motion replaces the slide and springs with 0.15-second
fades, and the drag dims the card instead of moving it. A new swipe can't grab
the card until it has settled.

`PeekCloseTransition` orders the drag, exit, close request, refusal and sheet
spring-back, and its exit timers are generation-checked. Hiding a Peek mid-exit
for a tab or Space switch hides it at once and requests the close without
waiting, and a retiring Peek goes invisible before its view is removed, so no
fading card lingers over a newer Peek or tab and nothing flashes.
`PeekDismissalMotion` is the pure spring, slide and fade model, and
`PeekDismissalAnimator` applies it to any card stage and wash view for reuse by
other Peek hosts; the host sets its geometry and resting wash and leaves the
stage's transform and opacity to it. `python3 tests/PeekSwipeDismissal/check.py`
checks `PeekCloseTransition` and `PeekDismissalMotion` with the real recognizer
and confirmation rules, plus the controller's close wiring.

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
`canNavigatePeekLinkFrom` and its selected and visible pages).

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
never asked to close, so there is no beforeunload; you stay on your page and
focus returns to it. The Escape confirmation still applies, and during a call
the pill reads Close rather than Hang up, since the call carries on in its tab.
Opening the tab normally (clicking it in the sidebar, Expand, Open in [Space],
the tab switcher, its Mini Player or the page going fullscreen) moves the page
back into its pane first, where the page-switch hold keeps the old page up until
it draws, then fades the emptied card with the close fade. Add to Split joins
the tab to the current split the same way. Switching tabs or Spaces, or
closing, archiving or moving the tab, puts the page back at once without a
motion; closing the window closes it with the window's other pages.

The item is offered only for a web tab in the current Space and Profile that
isn't on screen, closing, moving or failed, over a live web page in this window
that can host a Peek. A tab held by another window comes here through the
normal transfer first, or isn't offered when it can't move. If a Peek is
showing, it closes through its own close and consent, confirmation pill
included, and the tab opens once it is gone; a refused close or an expired
confirmation drops the request. While in Peek the tab neither
sleeps nor auto-archives. `tests/TabPeekTests.swift` covers admission, refusals,
replacement and the round trips, checking that the same page comes back and
that only a tab with no page loads.

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

One-use weak return tokens protect asynchronous presentation. Refused close keeps
the original control/editor; actual dismissal returns to the surviving parent;
promotion returns to the same child after reparenting. Any newer concrete responder
permanently cancels return. Temporary nil/window focus during teardown still needs
fresh original-owner checks. Native traversal remains intact.

## Presentation and remaining scope

The card takes 80% of the page width (narrow pages keep room for the
controls), with 12-point top and bottom insets, 8-point corners, a near-white
or near-black card fill, a hairline edge and a soft 4-point shadow. The page fills
the card; there is no title band. A copy of the window's theme background covers
the parent at 70%, so the parent shows through at 30%, in light and dark
themes alike.

Round Close, Expand and Split controls sit 13 points right of the card, filled
with the Space theme's background-extra colour and drawn in its primary ink (kept
dark enough on light themes). They lift on hover, shrink when pressed and show
tooltips to their right. Close confirmation widens Close into a red Close or Hang
up pill on a 0.25/0.8 spring; entry fades over 0.3 seconds. Reduce Motion
settles the entry and confirmation animations. Tab and Shift-Tab follow the
window key-view loop through the Peek's renderer and controls, excluding the
dimmed parent. Controls have
accessible names and the close-confirmation state announces its instruction.

The remaining presentation item, measuring the card from the window edge, is in
[the backlog](backlog.md#peek).

Automatic Peek for links to other sites and Shift-click Peek are both on by
default for new users; this is a settled product decision. Either can be
switched off in Settings → Links. The engine's default-off policy flag is
enabled for registered pages.

Parent transfer, orphan preservation, promotion and new-tab provenance already
use the original page and parent identity. Model/native components cover those
transactions, confirmation timers, renderer acknowledgments and focus
cancellation; window key-loop checks cover forward and backward traversal.

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

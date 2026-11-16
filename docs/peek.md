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
up pill on a 0.25/0.8 spring; entry fades over 0.3 seconds. Reduce Motion settles
owned animation. Tab and Shift-Tab follow the window key-view loop through the
Peek's renderer and controls, excluding the dimmed parent. Controls have
accessible names and the close-confirmation state announces its instruction.

Dismissal handles a completed right swipe. Continuous drag progress, velocity,
reversal and cancellation are absent. Teardown removes the view immediately;
there is no exit fade, transition snapshot or Peek-specific haptic feedback.
Nested Peek is also unavailable: a visible Peek blocks another child, and
creation requires an original saved parent tab. These are concrete remaining
presentation and nesting items in [the backlog](backlog.md).

Automatic Peek for links to other sites and Shift-click Peek are both on by
default for new users; this is a settled product decision. Either can be
switched off in Settings → Links. The engine's default-off policy flag is
enabled for registered pages.

Parent transfer, orphan preservation, promotion and new-tab provenance already
use the original page and parent identity. Model/native components cover those
transactions, confirmation timers, renderer acknowledgments and focus
cancellation; window key-loop checks cover forward and backward traversal.

## Links inside a Peek

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
embedded frame sandboxed against navigating the page keeps the new window, though
the hover capsule still says "in this Peek". Other modifier clicks keep their
routes; see [web interactions](web-interactions.md#hovered-link-status).

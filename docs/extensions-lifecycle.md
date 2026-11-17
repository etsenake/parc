# Extension presentation lifecycle

Extension popups and side panels retain their real Chromium pages and original
Browser/Profile ownership. Presentation never creates a substitute browser or
looks up a newer extension action to replay an older gesture.

## Popup opening, dismissal and motion

`NativeExtensionActionContainer` owns one current popup, immutable action-model
identity, generations and separately retained terminal sessions. Replacement,
unload or delayed close cannot remove a newer popup. Active-tab change, original
Browser deselection and shutdown end the session.

`NativeExtensionPopup` installs the real ExtensionView before renderer creation.
Terminal requests suppress posted load/resize work, retain the view through
modal-handler teardown, defer host deletion beyond engine/AppKit event stacks
and resolve the show callback exactly once. Parent close, page detachment and
engine close share cleanup. Load-before-show, explicit renderer focus,
modal/DevTools holds and security-UI refusal remain enforced. A file chooser
from a popup is a sheet on the popup's own window and holds the popup open like
a JavaScript dialog; one from a side panel is a sheet on the browser window.
Both use a page lease the popup or side panel hands out while its page is shown,
so a chooser cancels when that page hides, closes or moves. A folder upload's
confirmation uses the same lease, as a child window of the popup or, for a side
panel, of the browser window.

Popups use native window presentation and terminal detachment. A loaded popup is
ordered in and made key while still invisible, then waits until its page has
drawn and its size has held for about two frames, never more than 0.15 seconds,
so it doesn't flash empty or at a stale size. It fades in over 0.2 seconds while
easing 8 points down into place. Once revealed, a size change glides over 0.18
seconds on the same curve. The page takes its new size at once, matching its
renderer, and only the window's edges move over it, so the page never re-lays
out mid-glide; while a popup shrinks, the strip its page no longer covers shows
the page's own background color. The edge facing the button stays still, the
glide ends where placement puts the new size, even when that switches fallbacks,
and a change mid-glide sets off from the current size. A popup that is closing,
sits in a hidden or minimized window or has a sheet or child window resizes at
once, and a sheet or child window arriving mid-glide finishes it. Closing
reverses it: the popup stops taking clicks, hands the keyboard back to its
browser window and fades out over 0.15 seconds while drifting 4 points back up.
Its real page stays in it until the fade ends, then detaches and closes. Reduce
Motion keeps both fades, drops the glides and resizes at once. Browser security
UI, the parent closing, shutdown, the popup's close button, a sheet or child
window on the popup, an unloaded extension and a popup that never became visible
close it at once. Becoming key in the popup's own parent dismisses it; another
app or window becoming active does not substitute that event. Resize repositions
only until the user moves the popup, then grows from its top left corner;
dragging it mid-fade shows it at once and mid-resize finishes the resize. Escape
stays with its real ExtensionViewHost delegate. The presenter tells the browser
window's controller when a popup is revealed, when its closing fade starts and
when it closes by any path, which drives the
[lit extension button](extensions-interaction.md#controls).

## Site Control Center to extension handoff

Extension context menus keep the Site Control Center open and use the themed
menu described in [web interactions](web-interactions.md). Opening an extension
action dismisses the card first and dispatches only after native close completion.

The controller retains itself through `willClose`/`didClose`.
`SiteControlCenterDismissal` retains all still-closing controllers by identity;
a second action cannot bypass an older native close. Each action replaces or
cancels the pending request. A generation check also invalidates queued work
between `didClose` and the next main-loop turn.

The window removes the matching session before PageInfo's terminal close, so a
synchronous final row callback cannot cancel the intended action or a newer
session. Dispatch rechecks the original window, Browser binding, page wrapper,
real page, document revision, Space, key-window state and generation. New card
or extension requests invalidate the old action lease.

## Side-panel lifecycle

The connected Chromium service owns hidden attachment before load, original
container validation before shown events, identity-checked replacement,
contextual caching, tab movement and extension unload/disable cancellation.
Native detachment is synchronous; actual host/manager destruction completes
before Browser/Profile release.

The close header calls `closeExtensionSidePanel()` on the original binding.
Background, detached, unselected and retiring Browser owners refuse. Plain,
unhandled Escape is accepted only from the panel's original key window after
session validation. Both routes close the real service, rather than hiding its
container while retaining the page.

The panel-only focus scope includes its close header. Restoration validates
weak scope identity, original-window attachment, current page ancestry and the
saved responder's visibility/enabled state. A newer unrelated responder remains
untouched. No arbitrary delay holds the engine page alive for animation.

## Checks

Focused Site Control Center checks cover close-delegate ownership, overlapping
closes, latest-action replacement, cancellation and delayed-show rejection.
Native side-panel checks cover exact window ownership, modified Escape, close
header focus and detached/foreign pages. Swift and pinned native compiler
checks complement these inert tests.

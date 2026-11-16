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

Popups use native window presentation and terminal detachment. Becoming key in
the popup's own parent dismisses it; another app or window becoming active does
not substitute that event. Resize repositions only until the user moves the
popup. Escape stays with its real ExtensionViewHost delegate.

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

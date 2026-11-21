# Window activation and interrupted import

Window commands retain their original physical owner. A last-active browser is
not a substitute when Settings, an importer, another auxiliary window or a
native sheet owns the key context.

## Import and auxiliary windows

New Tab refuses while an importer or its attached sheet owns key focus. Closing
an importer returns its original browser to the front only when the import still
owned key focus, the app remains active and that browser is visible, ready and
unobstructed. A newer key window during cleanup cancels return. Background close
or parent retirement cannot activate another window.

Command-W closes Settings only when Settings owns key context, and refuses its
attached sheet. Other auxiliary windows cannot implicitly close a selected tab
behind them. Browser closure retains genuine consent/beforeunload ownership.

## Browser command admission

Sidebar focus/toggle, reload/stop, history, zoom, Duplicate, Pin and normal Space
creation/theme commands require their actual key browser, no attached sheet and
native security admission. Existing command-specific Profile/page eligibility
still applies. Private windows do not gain normal Profile/Space mutations.

Reopen resolves the key browser or its original command surface, then rechecks
the same owner and original reopen step after cleanup. Command presentation
checks physical owner before cancelling split insertion, Space creation or
capture. Synchronous callbacks can invalidate ownership; every later step checks
again. A child panel can return key status only to its original parent when no
newer window took focus. The command bar itself is now hosted in the browser
window, as described in [command bar](command-bar.md).

Plain Copy retains explicit command/shortcut-education owners. Markdown and
Quote require the key browser. Their final native operation remains authoritative
for original page, URL, selection, renderer and security admission. Share, Cast
and Extensions likewise validate the original browser rather than a global
foreground lookup.

Manage/Add Extensions and delayed Site Control Center presentation retain the
original window, page revision, Space and Profile through dismissal and input
resolution. Popup requests use the original-page and hidden-destination
admission described in [the native handoff](#native-admission-handoff).

## Existing interruption owners

- The tab switcher cancels on app or parent key loss, sheet, miniaturization,
  close and changed ownership without acquiring key focus.
- Settings retains weak per-pane responder identity, ends shortcut recording on
  key loss and restores only a visible, active, sheet-free original pane.
- Extension popups dismiss when their own parent becomes key; unrelated windows
  are not the same event.
- Per-window content, Peek and chooser focus retain exact original responders.

See [navigation](navigation.md), [keyboard navigation](keyboard-navigation.md),
[extension lifecycle](extensions-lifecycle.md) and
[windows lifecycle](windows-lifecycle.md) for their contracts. Key/main/app
notifications remain distinct from a request to move a responder.

## Native admission handoff

The facade exposes two read-only main-thread queries:

- `page.canCopyURL(fromCommandWindow:browser:)` uses the same exact-page
  `CopyCommandWindow`/plain-URL admission without copying or writing a clipboard.
- `binding.canAdmitHiddenPageTransferDestination` checks engine/app state,
  registration, close state, sheets, security reservation and miniaturization
  without requiring visibility/key status or performing a transfer.

Both are momentary checks, not retained leases, so each consumer asks again at
every decision point.

**Shortcut-education Copy.** The Essential Keyboard Shortcuts window offers and
performs Copy through one route. A web page uses the command-window query to
decide availability and the matching native copy to perform it, so a crashed
page, dead renderer, owner sheet, minimized or invisible browser, security
reservation or retiring page greys out Edit → Copy URL instead of reporting an
unavailable link. An open command bar or a tab without a web page keeps the
plain URL copy. Availability is asked live at each menu validation and shortcut
press; nothing is cached while the window stays open.

**Popup New Tab and addresses.** Command-T or a submitted address in a popup
hands off through `PopupTabHandoffCoordinator`. It captures the popup, its
window, its selected page and browsing session, then picks the most recent
window that shares that session, accepts tabs for its Profile and passes the
hidden-destination query. An ordinary minimized window is eligible when no sheet
holds it; it is restored first and admitted afterwards. Each step that brings the
destination forward rechecks the original page and the destination's window,
binding, Space and Profile. After it comes forward the full query runs again; a
window still restoring is awaited briefly, each request on its own wait, so a
second request never drops the first. A destination that is blocked, closed or
never restores yields a fresh window, the same fallback as having no window, and
a vanished original page delivers nothing. The app sees a minimized window's
security reservation only through that later query, so such a window is restored
and then refused in favour of a fresh window. A private popup never hands off:
its session belongs to it alone, so it always opens a new private window.
[`PopupTabHandoff`](../Sources/ParcCore/PopupTabHandoff.swift) holds the choice.

## Checks

Import-focus and original-owner sequence components cover background, minimized
and obstructed parents, inactive app, key changes during cleanup and refusal.
`WindowOwnerSequence` exercises revalidation between callback-capable steps.
`swift test --filter PopupTabHandoffTests` covers admitted, blocked, minimized, fresh and
private popup handoffs; `EssentialsTests` covers the Copy
routes and their native admission wiring.

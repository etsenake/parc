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
resolution. A popup-to-normal-window handoff additionally needs a hidden
destination's admission and an original-page lease; that consumer integration
is not established merely by the native query's existence.

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

## Native admission handoff for WIN13

The facade exposes two read-only main-thread queries:

- `page.canCopyURL(fromCommandWindow:browser:)` uses the same exact-page
  `CopyCommandWindow`/plain-URL admission without copying or writing a clipboard.
- `binding.canAdmitHiddenPageTransferDestination` checks engine/app state,
  registration, close state, sheets, security reservation and miniaturization
  without requiring visibility/key status or performing a transfer.

Both are momentary checks, not retained leases. The app consumer must capture
source and destination page/Profile/Space/window identities, validate before
first show and revalidate across every callback. The API exists in source;
consuming integration and remaining activation behavior stay open under WIN13
in [the backlog](backlog.md), rather than a missing-engine-API claim.

## Validation boundary

Import-focus and original-owner sequence components cover background/minimized/
obstructed parents, inactive app, key changes during cleanup and refusal paths.
Swift/native compilation checks API compatibility. They do not establish every
application-modal combination or live focus timing. No app launch or browser
interaction is authorized by this guide.

# Extension side-panel compatibility boundary

Parc supports genuine Chromium extension side panels in its native AppKit
windows. Chromium owns extension permissions, Profile/window/tab identities,
options, loading, contextual switching and unload. Parc supplies the native
container and focus/lifetime adapter through `NativeSidePanelHost` and
`extension_side_panel.mm`.

## Why the current engine needs an adaptation

The upstream presentation delegate uses Views; Parc hosts the same extension
WebContents in an AppKit page region. It does not navigate an ordinary tab to
an extension URL or replace extension content with a shell approximation.

- The trailing container shares the page's top and bottom. Preferred width is
  30% of window width, bounded to 240–360 points and clipped to actual remaining
  space, including narrow and zero-sized hosts.
- A 32-point header labels the surface Extension. Its 32 × 24 close control
  invokes `closeExtensionSidePanel()` on the exact binding. The page occupies a
  separate content container below it.
- Show waits for real host loading and a valid visible original window and
  container. Coordinator notification and focus follow successful attachment.
- A loading panel already counts as the open entry of its window or tab, so an
  extension's close request for it cancels the open before anything appears. A
  window-wide close leaves a loading tab panel alone, and a tab close leaves
  other entries alone. A page change during loading reuses the same page and
  shows only once the newest page has loaded.
- Replacement/context switching detach synchronously and preserve eligible real
  hosts in their coordinator caches. Tab moves transfer or reuse the actual
  session. Generation checks reject stale presentation.
- Close, disable, unload and shutdown detach immediately. Host deletion and
  manager draining wait for callbacks to unwind before Browser/Profile deletion.
  A presentation animation must not prolong a terminal page's lifetime.

## Keyboard and focus ownership

A native unhandled plain Escape can close the panel only after validating the
original session, key window and actual key-down event. Modified keys or another
window cannot dismiss it. Header close and Escape both use the real service's
close/drain transaction rather than merely hiding a view.

The panel captures its original responder weakly. Close restores it only when
the panel still owns focus and no newer responder has taken over. An explicit
panel-only focus scope includes header and body; clients without it use the body
alone. The scope must still contain the actual page in the same window. Hidden
views and disabled controls are refused, and a generic superview is never treated
as the application root.

## Checks

Focused native compiler checks cover the panel and host with their actual
Chromium flags. Inert input/focus checks cover original-owner validation and
teardown; header and layout checks include narrow/zero-sized fit and real close
callbacks. Whole-module Swift checks cover the app bridge.

[Geometry](extensions-geometry.md) and [lifecycle](extensions-lifecycle.md)
carry the related contracts.

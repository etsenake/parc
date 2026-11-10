# Native page-host component

`Engine/ParcNative/page_host.h/.mm` implements native containment of a supplied
WebContents NSView. It does not create or own Chromium WebContents, a Browser,
a profile or an NSWindow. The engine adapter must retain the returned stable
host, supply the actual WebContents native container and coordinate engine
ownership/close consent separately.

Run the focused native suite on macOS with Xcode command-line tools:

```sh
bash tests/NativePageHost/run.sh
```

The script compiles the production component and tests with ARC and warnings
treated as errors, then executes the standalone test binary. It links AppKit
ignored `build/tests/native-page-host/`. Test NSWindows stay offscreen; the suite
uses their real view hierarchies, Auto Layout, first-responder mechanism and a
running main queue.

The suite runs in `scripts/test.sh` and covers containment/reuse, replacement/
external removal, deferred renderer focus/replacement, window move and detach, invalidation/weak lifetime,
reentrant replacement teardown, hidden queued-focus refusal, initially-hidden
content visibility, reentrant visibility ownership, the pane compositor view
(never the renderer responder, events pass through, on-screen state, screen
callbacks for hiding, a hidden ancestor, parking in a hidden container and
leaving the window, and geometry callbacks) and content restoration after a
Chromium-style detach
([page compositing](../../docs/page-compositing.md)). The background-visibility
regression against the earlier component exits 1 at “selected initially-hidden
native content and its renderer are actually unhidden”.

The fresh-tab regressions attach the real native DevTools pane
after the shell wrapper has been laid out, then show without a window event.
Both initially visible and initially hidden new pages, their renderer fixtures
and the compositor display must have the host's size when show returns. They
also cover changed pane/infobar geometry, replacement content, clean repeated
shows without subtree walks, parked-page selection, two visible split panes,
window transfer, native content reattachment, and transfer, hide or invalidation
callbacks during layout. Against the preceding production host,
the new foreground-page regression fails with a 0×0 page and renderer. These
checks exercise the geometry defect and correction.

## Containment and lifetime

`PCNativePageHost` retains the supplied native content, reuses an exact existing
host, and pins content to four edges. It exposes actual attachment through a
weak observer. Browser/window ownership and unload consent remain external.

Queued renderer focus binds the original renderer and window, requires the host
to remain first responder, and rejects hidden, moved, replaced or invalidated
owners. The compositor display view is never treated as the renderer responder.
`restoreContentView:` restores detached managed content beneath the infobar shelf
only while valid and unattached elsewhere. Replacement clears old constraints
and rechecks callback-driven invalidation before installing new content.

`invalidate` is a terminal, idempotent lifetime boundary. The owner calls it before destroying the page/window: it cancels
pending focus/callbacks, clears constraints, and detaches the supplied view and
host. It is terminal and idempotent. Ordinary host detachment preserves the page
and still reports the actual window change. Neither operation closes a browser
tab or grants consent to unload.

## Chromium 156 parent-view visibility adaptation

The Chromium version pinned in [the source lock](../../Engine/source-lock.json)
requires the host to show the native WebContents container, in addition to
renderer visibility notifications:

| Pinned source evidence | Established behavior |
|---|---|
| `chrome/browser/extensions/open_tab_helper.cc:183–198` | `active:false` selects `NEW_BACKGROUND_TAB`. |
| `chrome/browser/ui/navigator/browser_navigator.cc:539–540` | Background creation sets `initially_hidden`. |
| `content/browser/web_contents/web_contents_view_mac.mm:434–440,861–866` | Creation hides the native container; the host-visible setter forwards to its native bridge. |
| `content/app_shim_remote_cocoa/web_contents_ns_view_bridge.mm:91–115` | The bridge sets the actual container NSView's hidden flag. |
| `ui/views/controls/native/native_view_host_mac.mm:287–318` | The normal native host explicitly shows/hides that container. |
| `content/browser/web_contents/web_contents_impl.cc:3179–3182,5436–5465` | `WasShown()` updates page/renderer visibility; showing the renderer child does not clear its container parent's hidden flag. |

The native adapter now applies the existing shell-visible-page decision to that
exact managed container before `WasShown()`/`WasHidden()`. It revalidates the
Browser, page binding, pane, view, supplied window and CEF attachment around the
native callback, then checks the latest reconciliation generation and actual
visible-page set before the engine notification. Superseded work cannot change a
later owner's visibility. This adds no page, selection, navigation or focus
operation and does not recreate the renderer.

Browser/profile activation, keyboard dispatch, accessibility,
color-provider and compositor policy belong to the surrounding engine adapter.
The wrapper does not infer visibility from attachment or successful focus from
a processed request.

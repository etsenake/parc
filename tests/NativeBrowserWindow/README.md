# Native Chromium BrowserWindow adapter

`Engine/ParcNative/native_browser_window.h/.mm` implements Chromium's actual
`BrowserWindow` interface for a caller-owned AppKit window. Browser owns the
adapter; the shell owns NSWindow. `AsBrowserView()` returns null. This source

The adapter connects real Browser activation/close subscriptions, native window
association, active page geometry, modal hosting, location services and native
theme/color providers. It arbitrates selected Browsers sharing one NSWindow,
coalesces reentrant activation notifications, and forwards completed native
fullscreen transitions to the real ExclusiveAccessManager. Fullscreen request
acceptance and completed state are distinct. The required shell host must show
the actual security/exit controls and present the operation's actual origin.

The window now owns one `NativeExtensionKeybindingRegistry` for its real
Browser/Profile/TabList. `BrowserWindowFeatures::Init` supplies the TabListBridge
before the window factory runs. Construction initializes Chromium's actual
command observations and permission-aware dispatcher, but does not publish a
detached/unregistered window as active. The mandatory host method
`DispatchExtensionActionAccelerator` must route to that Browser's real action
models and popup service; it has no no-op default. Actions remain distinct from
shared named-command dispatch and its actual activeTab grant.

Selected flags for every Browser sharing an NSWindow are committed first. Each
activation drain publishes the Profile registry for the selected Browser only
when its actual window is key, before arbitrary Chromium or host callbacks.
This publication also runs during a reentrant drain, so a newly selected
Profile cannot leave the previous registry active until callbacks finish.
Conditional deactivation cannot clear a newer Browser's active registry.
Window key/resign, selection changes, approved Browser close and native window
close all pass through this reconciliation.

At teardown the registry is suspended, deactivated and destroyed before native
activation/cancellation callbacks or pre-window feature teardown. Its borrowed
Profile, TabList and action service are still alive; command/media observations
are removed before those callbacks can reenter. The remaining native services
keep their existing pre-window teardown order.

Post-renderer `HandleKeyboardEvent` dispatches the registry once, only for the
selected Browser in its actual key NSWindow outside teardown. It preserves
virtual-key/modifier/phase/timestamp conversion and rejects `skip_if_unhandled`
events. `PreHandleKeyboardEvent` returns NOT_HANDLED; Chromium's exclusive-access
manager runs before it. The native client's earlier menu route must not dispatch
extensions a second time.

`Close()` uses Chromium's real UnloadController. The shell coordinator must wait
for all Browsers sharing a native window to approve closing; a native close
notification does not grant beforeunload consent. The adapter performs required
pre-window feature teardown while its services are alive, cancels native
requests through the host, invalidates observations, releases native services,
and defers adapter deletion. BrowserManager retains ownership of Browser.

`NativeBrowserWindowHost` makes native services and presentation capabilities
explicit. Compatibility hooks need not reproduce Chrome UI; their current
callers still require truthful results, request completion and safe lifetimes.
The interface has no default successful UI callbacks. The concrete host, native
page delegate, factory route and adapted native feature-initialization branches
are now canonical and exercised by the independent application. The original
upstream first-tab BrowserView assumption was an integration requirement, not a
reason to create a hidden BrowserView. Component checks below remain narrower
than the production runtime results tracked in the main README and parity ledger.

`GetStatusBubbles()` returns the empty list allowed by `BrowserWindow` and has
no host service requirement. Chromium156's `UpdateTargetURL` and
`ContentsMouseEvent` cast every supplied status bubble to `StatusBubbleViews`
and its anchor to `ContentsWebView`; a custom AppKit implementation would be
unsafe through those consumers. The separate native hovered-link/status route
is tied to the originating WebContents; this empty compatibility result does not

## Verification

```sh
python3 tests/NativeBrowserWindow/check-chromium.py /absolute/path/to/chromium/src
```

The complete Objective-C++ implementation passes the pinned Chromium156 compiler
as errors. A static assertion also requires the class to implement every pure
virtual BrowserWindow and color-source method. The script reads the checkout,
invokes only its compiler in syntax-only mode, and writes commands/diagnostics
under ignored `build/tests/native-browser-window/`. It does not run generators,
modify the engine checkout, link, or launch a browser.

The separate page-host and window-association executable tests cover their
component lifetimes. They do not validate this complete adapter's Browser
construction/destruction, activation, beforeunload, fullscreen, multi-profile
or renderer integration. Registry activation under reentrant profile selection,
stale window-resign notifications, real action/named-command dispatch,
suspension, media commands, split active-tab grants and teardown also require
linked/runtime checks. The host/factory now runs in the independent browser;
its passing basic runtime cases do not close these broader component gates.

## Engine selection and shell layout

Geometry-only synchronization is separate from explicit selection commands.
Engine-origin selection reaches the exact existing page after tab-strip observer
unwind. Stale, moved, closed or superseded selections are rejected; split
membership survives and pages are never recreated by URL. Local Start/Easel
selection deselects native pages; navigation back waits for the exact page to
attach. Request generations prevent older callbacks overriding newer commands.

Historical GUI investigation receipts remain in Git history. They are not live
process records or current assignments. [Product status](../../docs/parity.md)
and [window lifecycle](../../docs/windows-lifecycle.md) track present behavior.

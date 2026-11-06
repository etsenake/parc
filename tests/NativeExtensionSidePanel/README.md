# Native extension side panel

The service registers a real browser-scoped `SidePanelUI` and the actual global `ExtensionSidePanelManager` after the native Browser has been registered. Existing per-tab managers and the actual `SidePanelService` retain options, permission/incognito filtering and global/contextual precedence. The coordinator uses `ExtensionViewHostFactory::CreateSidePanelHost` with its original Browser or TabInterface. Parc installs that real host's NSView through `PCNativePageHost` in the host-supplied container. No Views page proxy or ordinary-tab URL recreation is used.

The upstream coordinator still uses its existing platform delegate for host creation and nonvisual shared action-item references. Its Views `CreateView` path is not called by native presentation. A narrow shared-host lease extends the actual host through callbacks; ordinary Views ownership remains coordinator-owned. Global and contextual identity are checked separately. Spanning incognito hosts retain the factory's original-profile context, with the current profile's incognito permission checked; this branch has source checks, not runtime verification yet.

## Presentation and lifecycle

`NativeSidePanelHost` supplies the exact app-owned NSWindow/container, selected-browser state, actual visibility/layout operation and native key fallback. It must exist before service construction and outlive `Shutdown` completion. `HostStateChanged` is required after selection, layout or association changes. Pre-attachment and hidden/unselected-window requests do not acknowledge presentation.

The page attaches hidden before renderer creation, so the real native window is available to Chromium modal ownership. Only `has_loaded_once`, exact entry/profile/tab/window association, successful shell visibility and actual native attachment/visible bounds allow `OnEntryShown` and shown notifications. API success from upstream `open()` still means accepted routing, not loaded visibility. The tests deliberately distinguish these.


`Shutdown(done)` stops requests and unregisters `SidePanelUI` synchronously, detaches current/cached pages, and retires each real host after its guarded engine calls unwind, using non-nestable UI tasks for final host/manager destruction. The actual global manager and its coordinators are destroyed from the posted drain after every host is gone. Completion is always asynchronous, including an empty tab list or zero hosts. Repeated calls add completion observers. Browser/Profile and the app host must remain alive through completion and the originating callback. The native BrowserManager pre-delete gate must invoke this before Browser/Profile teardown, including last-tab/internal deletion; destructor-only cleanup is insufficient. Do not enable the native factory without that connected gate.

## Evidence and verification boundaries


Sixteen genuine browser cases use actual Browser/Profile/TabInterface, service, registries, extension hosts and AppKit windows. They cover registered global routing and window identity; hidden/unselected refusal; background contextual selection; global/contextual precedence; pending unload; actual page `window.close`; wrong-window rejection; asynchronous host/manager drain; cached JavaScript state; explicit-close state; reentrant shutdown; live tab movement; native focus restoration; empty-tab drain; path-change/disable behavior; and pending background load without page recreation. The explicitly non-Views `TestBrowserWindow` fixture isolates the registration/presentation boundary, rather than letting stock BrowserView satisfy it accidentally. The fixture remains a test window, not production construction.


The reviewed v26 source overlay maps the native service and its separate browser-test target, adds the actual coordinator/registry adaptation, and registers the tests under the existing macOS/CEF browser-test guard. Read-only replay validates all 69 source additions and 74 patched targets. This source integration has not been applied to the active v22 checkout: the full baseline build continues uninterrupted. Fresh GN generation/header-dependency checking, linking and execution remain pending.

## Native dismissal input component

`bash tests/NativeExtensionSidePanel/run-input.sh` compiles and executes only the
production AppKit Escape-admission helper against inert windows and NSEvents.
It creates no Browser, Profile, extension or renderer, performs no activation and
drives no browser. The component controls the key-window predicate so event
ownership, key kind, modifiers and nil rejection can be checked independently of
the machine's foreground application. Its 23 assertions do not establish live
keyboard acceptance. The service additionally requires genuine original
Browser/Profile/page/container identity before calling the helper.

The native `closeExtensionSidePanel()` bridge validates the real selected
Browser owner, matching native binding/client window, key window and shown
panel, then invokes service close. It shares the existing deferred host drain
with unhandled Escape; neither route deletes an extension host inside its
keyboard or AppKit callback stack.

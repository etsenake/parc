# Native extension side panel

The service registers a real browser-scoped `SidePanelUI` and the actual global `ExtensionSidePanelManager` after the native Browser has been registered. Existing per-tab managers and the actual `SidePanelService` retain options, permission/incognito filtering and global/contextual precedence. The coordinator uses `ExtensionViewHostFactory::CreateSidePanelHost` with its original Browser or TabInterface. Parc installs that real host's NSView through `PCNativePageHost` in the host-supplied container. No Views page proxy or ordinary-tab URL recreation is used.

The upstream coordinator still uses its existing platform delegate for host creation and nonvisual shared action-item references. Its Views `CreateView` path is not called by native presentation. A narrow shared-host lease extends the actual host through callbacks; ordinary Views ownership remains coordinator-owned. Global and contextual identity are checked separately. Spanning incognito hosts retain the factory's original-profile context, with the current profile's incognito permission checked; the host's Profile and the invoking Profile remain distinct owners.

## Presentation and lifecycle

`NativeSidePanelHost` supplies the exact app-owned NSWindow/container, selected-browser state, actual visibility/layout operation and native key fallback. It must exist before service construction and outlive `Shutdown` completion. `HostStateChanged` is required after selection, layout or association changes. Pre-attachment and hidden/unselected-window requests do not acknowledge presentation.

The page attaches hidden before renderer creation, so the real native window is available to Chromium modal ownership. Only `has_loaded_once`, no pending navigation, exact entry/profile/tab/window association, successful shell visibility and actual native attachment/visible bounds allow `OnEntryShown` and shown notifications. From the start of an open, the loading entry is the active entry of its own window or tab registry and the showing query reports it, so Chromium's scoped close routes reach it: a window-wide close cancels a loading window panel and a tab close cancels that tab's loading panel, while neither touches another entry. A window panel opening over a tab's panel also clears that tab's active entry, as Chromium does when a panel shows. Leaving the current slot before showing puts back whatever both registries marked before, and a window panel that ends up showing on another tab puts back the tab entry it cleared. A page change during loading therefore navigates the same host, and a load-stop observer shows it only once the newest page has loaded. API success from upstream `open()` still means accepted routing, not loaded visibility. The tests deliberately distinguish these.

Background contextual pages remain the same live WebContents; selecting them restores their native view without navigation. Moving their actual TabInterface between native windows transfers that session and reuses the coordinator's actual host. Movement to a non-native host closes this native presentation instead; mixed native/Views production windows are not claimed. A prior weak same-window native responder is restored on close only if the panel still owns focus, preserving later unrelated focus. The [compatibility contract](../../docs/extensions-side-panel-adaptation.md)
describes the AppKit geometry, immediate transitions and conservative
focus-restoration policy.

`Shutdown(done)` stops requests and unregisters `SidePanelUI` synchronously, detaches current/cached pages, and retires each real host after its guarded engine calls unwind, using non-nestable UI tasks for final host/manager destruction. The actual global manager and its coordinators are destroyed from the posted drain after every host is gone. Completion is always asynchronous, including an empty tab list or zero hosts. Repeated calls add completion observers. Browser/Profile and the app host must remain alive through completion and the originating callback. The native host's pre-delete drain invokes this before Browser/Profile teardown, including last-tab/internal deletion; destructor-only cleanup is insufficient.

## Checks

Twenty-two genuine browser cases use actual Browser/Profile/TabInterface, service, registries, extension hosts and AppKit windows. They cover registered global routing and window identity; hidden/unselected refusal; background contextual selection; global/contextual precedence; pending unload; actual page `window.close`; wrong-window rejection; asynchronous host/manager drain; cached JavaScript state; explicit-close state; reentrant shutdown; live tab movement; native focus restoration; empty-tab drain; path-change/disable behavior; pending background load without page recreation; window-wide and tab close requests during loading, each cancelling only its own entry, including a window panel loading over a tab's panel; and a page change during loading that shows only the newest page. The explicitly non-Views `TestBrowserWindow` fixture isolates the registration/presentation boundary, rather than letting stock BrowserView satisfy it accidentally. The fixture remains a test window, not production construction.

The production service and browser-test target are in the reviewed overlay.
Compiler checks validate their actual generated flags and headers. Executing
the browser-test fixture requires valid Chromium process/context initialization.

## Native dismissal input component

`bash tests/NativeExtensionSidePanel/run-input.sh` compiles and executes only the
production AppKit Escape-admission helper against inert windows and NSEvents.
It creates no Browser, Profile, extension or renderer, performs no activation and
drives no browser. The component controls the key-window predicate so event
ownership, key kind, modifiers and nil rejection can be checked independently of
the machine's foreground application. Its 23 assertions cover this isolated input helper. The service additionally requires genuine original
Browser/Profile/page/container identity before calling the helper.

The native `closeExtensionSidePanel()` bridge validates the real selected
Browser owner, matching native binding/client window, key window and shown
panel, then invokes service close. It shares the existing deferred host drain
with unhandled Escape; neither route deletes an extension host inside its
keyboard or AppKit callback stack.

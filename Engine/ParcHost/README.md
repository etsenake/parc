# Native host capability experiment


## Why this experiment is separate from the architecture decision


Shipped pretty-function and source strings identify the native adapter as **`arc::browser::ui::Window`**, not BrowserView: vtable `0xbc92590` points to `0x68a9370` logging `Window::IsMaximized` at `arc/browser/ui/window.cc:882`; adjacent entries name `GetRestoredBounds`, `GetRestoredState` and `Hide`. The actual replacement must match this app-owned native-window contract before adopting an upstream presentation design.

|---|---|
| Live content transfer (`0x68b6918 → 0x685ebe0`) rejects cross-profile transfer and moves the existing tab/content object. Popup channels carry existing contents and separate activation intent. | The harness retains Chrome's real TabStripModel/WebContents and native popup handling. No URL recreation or fabricated tab/window callbacks. Live transfer and full popup adoption conformance remain untested. |

The earlier CEF **Views-backed** candidate is rejected for this slice. Its `CefBrowserViewImpl::BrowserCreated` stores one `browser_`; each created page's Views platform delegate calls into that same binding, and its destruction clears the active WebView. Making that window `TYPE_NORMAL` alone would not make multiple tabs safe. This harness supplies neither `parent_view` nor `CefBrowserView`, so the ordinary Chrome path creates independent page hosts. It leaves `TYPE_NORMAL` intact naturally. It does not alter the existing Views path's type conversion.

No hidden parking window, NSWindow content-view replacement, Alloy runtime substitution, fake extension action, or stub BrowserWindow is used. A Chrome-owned native window is not being selected as the final architecture. Parc's four-pane presentation and multiple profile bindings in one app-supplied window remain separate mandatory source and runtime gates.

## Implemented slice

`parc_native_host.mm` registers a browser-scoped `SidePanelEntry`, an owned action ID and a real `NativeViewHost`. The entry owns/caches the view, which strongly owns its AppKit NSView. Attachment occurs only after Views supplies a valid widget and checks that the native view is attached to that widget's actual NSWindow. The native wrapper controls bounds and visibility. No native window delegate or content view is replaced.

The AppKit controls enumerate actual TabStripModel pages; select by immutable session tab ID; create a normal native tab; navigate the active contents; perform Back, Forward and Reload; and request native close with beforeunload negotiation. Tab rows update only from model notifications. Closing does not synthesize success or remove a row before the model changes. A user-triggered **Log identities** snapshot prints actual session window/tab IDs, indices, active state, CEF host IDs and native attachment equality to stdout, without page URLs or text.

All bridge calls, model notifications and AppKit ownership changes run on Chromium's UI/main thread. The tab observer clears its model/browser pointers when the model begins destruction. The reverse AppKit owner pointer is cleared before detach/release; cached side-panel views can outlive the model safely. The host never owns or deletes a Browser, Profile, TabStripModel or WebContents. The panel can close/reopen through Chrome's real action/header behavior.

## Exact source integration

`overlay.json` is bound to CEF commit `4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f` and Chromium commit `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c` (156.0.8078.48). Every input and modified target has a SHA-256. The overlay tool owns application to the dedicated checkout; do not hand-edit it there.

- Add the two internal files to `cef/libcef/browser/chrome/views/` and the three harness inputs to `cef/tests/parc_host/`.
- Add the macOS `.mm` to `source_set("libcef_static")`, with the explicit side-panel, browser-actions, sessions and actions dependencies in the patch.
- Hook `ChromeBrowserHostImpl::Create` **after** the first real `chrome::AddTabAt` and focus call, guarded by the exact `parc.native_host.v1` extra-info Bool. The hook rejects a Views-backed or non-normal browser instead of adapting it silently. Other browser creation is unchanged.
- Add a dedicated side-panel entry ID and action ID; update its matching histogram-name metadata. Existing feature IDs are not borrowed. These are source changes, not binary patches. The new IDs are integration-only, not a stable public ABI.

After overlay application and CEF generation, the additional GN target is **`parc_host_harness`** in the same ARM64 component output as the pinned engine. Keep the app at its generated location because the component build uses relative dylib paths. The target does not replace the production Parc executable. No new CEF C API/export entry is needed: the harness uses public CEF client APIs, while the native bridge compiles inside libcef.

Overlay version 2 also maps the stable `ParcNative` page/window/modal source set and its dedicated **`parc_native_window_tests`** target. The test is reachable through the upstream `cef` graph but is built explicitly; no test dependency is added to the production framework. These native components are separate from this ordinary-Chrome-window capability harness. The LocationBar and complete BrowserWindow adapter are not part of this overlay version.

The patch changes five existing text files. No changed Chromium target is a target of the pinned CEF patch inventory; the overlay tool must still verify final bytes after generation. CEF project generation has succeeded with overlay version 2, and compilation is underway. All generated CEF/Chromium headers must come from that pinned build; do not replace missing generated dependencies with guessed local headers.

See [native harness procedures](../../tests/EngineConformance/native/README.md) for source checks, launch and actual pass/fail gates. Source validation is not compilation, and compilation is not evidence that native input, page ownership, extensions or close behavior work.

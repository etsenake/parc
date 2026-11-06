# Native extension action context menus

This source slice connects the actual Chromium156 action menu model to the actual `MenuControllerCocoa` and native `NSMenu`. It is a service for `NativeExtensionActionHost::ShowActionContextMenu`, not a toolbar or a completed extension UI.

## Reference and source contract


- `0x6896a3c` looks up the live action by ID, calls its dynamic `GetContextMenu` equivalent `0x6098044` with source0 (toolbar action), and passes that model plus the actual native window to `0xa89cc5c`.
- `0xa89cc5c` allocates `MenuControllerCocoa`, initializes it with the model and nil delegate, obtains its `NSMenu`, and synchronously uses `popUpMenuPositioningItem:atLocation:inView:`. It uses the current mouse location and supplied window content view. It does not construct a Views menu or invent a separate extension-command model.


Current156's `ExtensionActionViewModel::GetContextMenu` still creates its real dynamic `ExtensionContextMenuModel`, replacing the previous instance. `MenuControllerCocoa` holds weak model references, installs original menu indexes/targets, validates checked/visible/enabled state, and sends `ActivatedAt` with native event flags. This service keeps that implementation. Its guarded item target forwards the original selector to the original controller only after validating current ownership; it does not interpret commands, recreate permission grants or clone a parallel menu model.

## Ownership and truthful capabilities

`NativeExtensionContextMenu::Show` is synchronous. The existing action-container fallback retains its real action across the host callback. Future toolbar callers must retain that same model through the nested AppKit call; a naked `GetActionForId` pointer is insufficient. Browser/Profile and their services must also outlive `Show`. Use `CancelAndWait(completion)` before teardown and retain them until completion. This terminal operation refuses new tracking and posts a non-nestable completion only after the real native tracking loop, action-model lease and any reentrant cancellation have unwound; it also survives presenter destruction during command dispatch. Presenter destruction during `Show` cancels safely while the local session retains native targets until return.

The session checks the exact registered action pointer, exact enabled extension instance, Browser/Profile, actual active WebContents and actual parent window. It cancels on tab changes/removal/replacement, main-frame navigation, extension unload, page destruction and parent close. Shell selection/security changes call `HostStateChanged`. Host queries retain the existing side-effect-free snapshot contract. A second `Show` is rejected before it can replace the currently used model. Cancellation retains the active session slot, and a UI-thread action-model lease lasts until the original `Show` returns, even if its presenter is destroyed/replaced during a synchronous pin notification. This prevents the new presenter from destroying a model whose `ExecuteCommand` is still running. Weak submenu models and index/command identity prevent dispatch into a destroyed/rebuilt model.

The original cursor/window anchor is retained, using AppKit's screen-to-window-to-view conversion for both flipped and unflipped roots. The original helper's unflipped branch appears to mix screen/view coordinates; that anomaly is not copied. Multi-monitor placement still requires runtime comparison.

Uninstall uses the registered Browser-owned native service's exact capability check. Its command captures the real Browser/page/window/extension binding before asynchronous icon loading and uses Chromium's removal controller with the native confirmation sheet. Without a valid registered service, the row remains disabled with its capability-reason tooltip. Side-panel presentation remains unavailable in this menu. Other commands execute the original model and still depend on genuine native Browser navigation/settings/inspection services. See the [uninstall integration and runtime limits](../NativeExtensionUninstall/README.md).

`Engine/ParcNative/extension_context_menu_native.patch` preserves real `ToolbarActionsModel::SetActionVisibility` and its metrics. It guards the optional pin-feedback notification when `BrowserElements` or a real element context is absent and connects the native uninstall binding to the real command helper. Do not fabricate a Views element or disable pinning to avoid the optional notification. Missing native pin feedback remains an integration/polish gap.

Patch target: `chrome/browser/extensions/extension_context_menu_model.cc`. Original SHA256 `c8f5cfc59ba611fb8455d453faabed1e1b6bc03d903504216a532ec1e8d5efa5`; v22 patched SHA256 `0cce3371a4cce9b6717790b8d9e80cc710f8777b2eaece46495f1ff402b4448d`. The overlay maintains one contextual patch for this target.

## Checks and integration

```sh
python3 tests/NativeExtensionContextMenu/check-chromium.py /absolute/path/to/chromium/src
```


The twelve browser cases use actual loaded extensions, real action models and actual `NSMenu` dispatch/tracking. They cover pin mutation, cancellation, rejected nested Show, cancellation and presenter replacement inside a real synchronous pin observer, stale rebuilt model, presenter destruction during tracking, active-page changes, security changes unavailable uninstall, terminal drain after actual pin dispatch destroys the presenter, and repeated idle drains that permanently refuse new tracking. Callback state belongs to the fixture, including failure paths. They have **not been linked or executed**. No menu runtime acceptance is claimed from compiler results.

The reviewed v12 overlay includes both implementation files in `native_extensions`, exposes the real extension-model header dependency and links the Cocoa menu adapter. It registers `//cef/tests/parc_native_extensions:context_menu_browser_tests` with Chromium browser tests, including `HAS_OUT_OF_PROC_TEST_RUNNER` and its direct resource/header dependencies. This is source/target integration; production native shell routing remains pending.

The v22 integration also closes menu/popup presentation when the exact native window gains an uninstall reservation or a Chromium security widget, including registration before visibility. Unrelated native windows remain independent. Actual shell security-state notifications remain required.

Still required: linked tests, native-only pin operation with no BrowserElements, actual custom extension command delivery and site-permission actions, extension unload/reload while tracking, macOS menu cancellation/key behavior, integrated uninstall execution, native side-panel/inspection/settings services, multiwindow/profile changes and visual/motion comparison.

The two added drain cases and production menu unit pass actual-target compiler checks through an isolated VFS overlay. Source overlay v24 includes these changes; the full build is deliberately continuing on v22 without source mutation. The new cases remain unlinked and unexecuted.

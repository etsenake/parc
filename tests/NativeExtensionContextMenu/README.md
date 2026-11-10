# Native extension action context menus

This source slice connects the actual Chromium156 action menu model to the actual `MenuControllerCocoa` and native `NSMenu`. It is a service for `NativeExtensionActionHost::ShowActionContextMenu`, not a toolbar or a completed extension UI.

## Source contract

`ExtensionActionViewModel::GetContextMenu` builds the real dynamic menu model.
`MenuControllerCocoa` preserves model indexes, enabled/visible/checked state and
native activation flags. Guarded targets forward to that controller only after
validating current ownership; Parc does not clone commands or permission grants.

## Ownership and truthful capabilities

`NativeExtensionContextMenu::Show` is synchronous. The existing action-container fallback retains its real action across the host callback. Future toolbar callers must retain that same model through the nested AppKit call; a naked `GetActionForId` pointer is insufficient. Browser/Profile and their services must also outlive `Show`. Use `CancelAndWait(completion)` before teardown and retain them until completion. This terminal operation refuses new tracking and posts a non-nestable completion only after the real native tracking loop, action-model lease and any reentrant cancellation have unwound; it also survives presenter destruction during command dispatch. Presenter destruction during `Show` cancels safely while the local session retains native targets until return.

The session checks the exact registered action pointer, exact enabled extension instance, Browser/Profile, actual active WebContents and actual parent window. It cancels on tab changes/removal/replacement, main-frame navigation, extension unload, page destruction and parent close. Shell selection/security changes call `HostStateChanged`. Host queries retain the existing side-effect-free snapshot contract. A second `Show` is rejected before it can replace the currently used model. Cancellation retains the active session slot, and a UI-thread action-model lease lasts until the original `Show` returns, even if its presenter is destroyed/replaced during a synchronous pin notification. This prevents the new presenter from destroying a model whose `ExecuteCommand` is still running. Weak submenu models and index/command identity prevent dispatch into a destroyed/rebuilt model.

The original cursor/window anchor is retained, using AppKit's screen-to-window-to-view conversion for both flipped and unflipped roots. An app presenter (`PCNativeMenuPresenter`, passed to `showExtensionActionContextMenu:forPage:presenter:`) replaces only that popup call: within the same synchronous `Show`, after the same validation, it receives the controller's `NSMenu`, sends its delegate's open/close calls, performs any chosen item after closing, and returns. Session cancellation also calls its `cancelMenu`. The Site Control Center uses it for Parc's own menu (see [WEB14](../../docs/web-interactions.md#site-control-center--web14)). Multi-monitor placement still requires runtime comparison.

Uninstall uses the registered Browser-owned native service's exact capability check. Its command captures the real Browser/page/window/extension binding before asynchronous icon loading and uses Chromium's removal controller with the native confirmation sheet. Without a valid registered service, the row remains disabled with its capability-reason tooltip. Side-panel presentation remains unavailable in this menu. Other commands execute the original model and still depend on genuine native Browser navigation/settings/inspection services. See the [uninstall integration and runtime limits](../NativeExtensionUninstall/README.md).

`Engine/ParcNative/extension_context_menu_native.patch` preserves real `ToolbarActionsModel::SetActionVisibility` and its metrics. It guards the optional pin-feedback notification when `BrowserElements` or a real element context is absent and connects the native uninstall binding to the real command helper. Do not fabricate a Views element or disable pinning to avoid the optional notification. Missing native pin feedback remains an integration/polish gap.

The patch targets `chrome/browser/extensions/extension_context_menu_model.cc`.
The [overlay manifest](../../Engine/ParcHost/overlay.json) owns its input and
output checksums and maintains one contextual patch for this target.

## Checks and integration

```sh
python3 tests/NativeExtensionContextMenu/check-chromium.py /absolute/path/to/chromium/src
```


The twelve browser cases use actual loaded extensions, real action models and actual `NSMenu` dispatch/tracking. They cover pin mutation, cancellation, rejected nested Show, cancellation and presenter replacement inside a real synchronous pin observer, stale rebuilt model, presenter destruction during tracking, active-page changes, security changes unavailable uninstall, terminal drain after actual pin dispatch destroys the presenter, and repeated idle drains that permanently refuse new tracking. Callback state belongs to the fixture, including failure paths. They have **not been linked or executed**. No menu runtime acceptance is claimed from compiler results.

The reviewed v12 overlay includes both implementation files in `native_extensions`, exposes the real extension-model header dependency and links the Cocoa menu adapter. It registers `//cef/tests/parc_native_extensions:context_menu_browser_tests` with Chromium browser tests, including `HAS_OUT_OF_PROC_TEST_RUNNER` and its direct resource/header dependencies. This is source/target integration; production native shell routing uses the same service.

The v22 integration also closes menu/popup presentation when the exact native window gains an uninstall reservation or a Chromium security widget, including registration before visibility. Unrelated native windows remain independent. Actual shell security-state notifications remain required.

Still required: linked tests, native-only pin operation with no BrowserElements, actual custom extension command delivery and site-permission actions, extension unload/reload while tracking, macOS menu cancellation/key behavior, integrated uninstall execution, native side-panel/inspection/settings services, multiwindow/profile changes and visual/motion comparison.

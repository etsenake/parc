# Native extension action context menus

The native action-menu service connects Chromium's menu model to
`MenuControllerCocoa` and `NSMenu`. Toolbar and Site Control Center controls use
the same model through Parc's themed menu presenter.

## Source contract

`ExtensionActionViewModel::GetContextMenu` builds the real dynamic menu model.
`MenuControllerCocoa` preserves model indexes, enabled/visible/checked state and
native activation flags. Guarded targets forward to that controller only after
validating current ownership; Parc does not clone commands or permission grants.

## Ownership and truthful capabilities

`NativeExtensionContextMenu::Show` is synchronous. The existing action-container fallback retains its real action across the host callback. The action bridge retains that same model through the nested AppKit call; a naked `GetActionForId` pointer is insufficient. Browser/Profile and their services must also outlive `Show`. Use `CancelAndWait(completion)` before teardown and retain them until completion. This terminal operation refuses new tracking and posts a non-nestable completion only after the real native tracking loop, action-model lease and any reentrant cancellation have unwound; it also survives presenter destruction during command dispatch. Presenter destruction during `Show` cancels safely while the local session retains native targets until return.

The session checks the exact registered action pointer, exact enabled extension instance, Browser/Profile, actual active WebContents and actual parent window. It cancels on tab changes/removal/replacement, main-frame navigation, extension unload, page destruction and parent close. Shell selection/security changes call `HostStateChanged`. Host queries retain the existing side-effect-free snapshot contract. A second `Show` is rejected before it can replace the currently used model. Cancellation retains the active session slot, and a UI-thread action-model lease lasts until the original `Show` returns, even if its presenter is destroyed/replaced during a synchronous pin notification. This prevents the new presenter from destroying a model whose `ExecuteCommand` is still running. Weak submenu models and index/command identity prevent dispatch into a destroyed/rebuilt model.

The original cursor/window anchor is retained, using AppKit's screen-to-window-to-view conversion for both flipped and unflipped roots. An app presenter (`PCNativeMenuPresenter`, passed to `showExtensionActionContextMenu:forPage:presenter:`) replaces only that popup call: within the same synchronous `Show`, after the same validation, it receives the controller's `NSMenu`, sends its delegate's open/close calls, performs any chosen item after closing, and returns. Session cancellation also calls its `cancelMenu`. The Site Control Center uses it for Parc's own menu (see [WEB14](../../docs/web-interactions.md#site-control-center--web14)).

Uninstall uses the registered Browser-owned native service's exact capability check. Its command captures the real Browser/page/window/extension binding before asynchronous icon loading and uses Chromium's removal controller with the native confirmation sheet. Without a valid registered service, the row remains disabled with its capability-reason tooltip. Open/Close Side Panel is enabled when the Browser's `SidePanelUI` is Parc's native panel; Chromium's own command then toggles that panel. Chromium's model labels the row from the panel's showing query, which counts an entry Parc's panel is still loading while its own registry marks it active; the session also retitles the row Close Side Panel for any loading entry of that extension, and the toggle closes a loading panel, so the label matches the click. When the app hides a shown panel's area before the panel notices, the showing query already reports it closed, so the row says Open Side Panel and the toggle opens the panel afresh instead of closing the hidden one. Pop-up windows keep the row disabled with a pop-up reason, and a window without the native panel keeps it disabled with a general reason. The row's `extension-menu:side-panel` identifier lets the app close an open Site Control Center before performing it. Other commands execute the original model and still depend on genuine native Browser navigation/settings/inspection services. See the [uninstall integration](../NativeExtensionUninstall/README.md).

`Engine/ParcNative/extension_context_menu_native.patch` preserves real `ToolbarActionsModel::SetActionVisibility` and its metrics. It guards the optional pin-feedback notification when `BrowserElements` or a real element context is absent and connects the native uninstall binding to the real command helper. Do not fabricate a Views element or disable pinning to avoid the optional notification. Pin changes update the real toolbar model, whose bridge notification refreshes the pinned controls and Site Control Center pin indicator. The optional Views education notification is omitted when no Views element context exists.

The patch targets `chrome/browser/extensions/extension_context_menu_model.cc`.
The [overlay manifest](../../Engine/ParcHost/overlay.json) owns its input and
output checksums and maintains one contextual patch for this target.

## Checks and integration

```sh
python3 tests/NativeExtensionContextMenu/check-chromium.py /absolute/path/to/chromium/src
```

The checker compiles the production unit and seventeen-case browser-test source
with their generated target settings. The patched upstream menu model uses its
own generated target flags. `--output-name` selects another built output; use
it when the default output has not been rebuilt since a Chromium upgrade,
because its generated headers then fail inside `base`. It requires
`obj/parc/native/native_extensions.ninja` and
`obj/parc/tests/parc_native_extensions/context_menu_browser_tests.ninja`.
ARC, warnings-as-errors, and the browser test's
`HAS_OUT_OF_PROC_TEST_RUNNER` definition are required. Source, compiler, flag,
toolchain hashes and commands are recorded under ignored
`build/tests/native-extension-context-menu/`.

The seventeen browser cases use actual loaded extensions, real action models and actual `NSMenu` dispatch/tracking. The first twelve cover pin mutation, cancellation, rejected nested Show, cancellation and presenter replacement inside a real synchronous pin observer, stale rebuilt model, presenter destruction during tracking, active-page changes, security changes unavailable uninstall, terminal drain after actual pin dispatch destroys the presenter, and repeated idle drains that permanently refuse new tracking. Five side-panel cases use a non-Views test Browser with Parc's own action container and native side panel: Open Side Panel shows the panel, Close Side Panel hides it, a panel opened just before the menu is built is still loading yet offers only Close Side Panel, which closes it and destroys the loading page, a shown panel whose area the app hides offers only Open Side Panel, which replaces the hidden page with a fresh one that shows, and a pop-up window disables the row with its reason and refuses a programmatic dispatch. Callback state belongs to the fixture, including failure paths. Execution requires a valid Chromium process/context.

The overlay includes both implementation files in `native_extensions`, exposes the real extension-model header dependency and links the Cocoa menu adapter. It registers `//parc/tests/parc_native_extensions:context_menu_browser_tests` with Chromium browser tests, including `HAS_OUT_OF_PROC_TEST_RUNNER` and its direct resource/header dependencies. This is source/target integration; production native shell routing uses the same service.

The service also closes menu/popup presentation when the exact native window gains an uninstall reservation or a Chromium security widget, including registration before visibility. Unrelated native windows remain independent. The native host supplies the selection/security-state notifications.

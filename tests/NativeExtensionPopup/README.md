# Native extension actions and popup lifecycle


## Presentation and lifecycle

The actual supplied page view is hosted in an AppKit child window anchored to
the owning page/sidebar/window. Resize preserves its anchor until the user moves
it. Attachment to a visible parent waits for load readiness; preparing a popup
must not show it prematurely.

`ExtensionActionViewModel` and `ExtensionActionDelegate` preserve upstream grants.
Delegates bind exact model identity, so unloading an extension cannot clear a
replacement with the same ID. Page-host detachment closes the real ExtensionHost;
the container clears its current-host slot before deletion.

Popup-owned dialogs or DevTools inspection hold ordinary parent-key dismissal.
Browser security UI instead prevents showing or closes an obscuring popup.
The supplied host uses `AppModalDialogManager`; keep this distinct from the
separate page JavaScript-dialog runner.

## Source boundaries

- `extension_popup_presenter.{h,mm}` owns only AppKit presentation. Parent/anchor references are explicit; close intent is once-only, terminal invalidation detaches the existing native page, and callbacks cannot remove a replacement popup. It does not own the engine.
- `extension_popup.{h,mm}` uniquely owns the supplied host and real ExtensionView, keeps the native view alive through host modal-handler destruction, enables actual renderer auto-resize (25×25 through 800×600), and preserves the host's Escape/delegate routing. Real visibility/focus notifications can reenter close: actual host deletion is guarded until owned engine operations return. External callback/sendEvent closure uses the current Mac default-run-loop deferral. `OnLoaded` is posted because upstream `DidStopLoading` continues accessing its host afterward.
- `extension_action_container.{h,mm}` observes the actual profile ToolbarActionsModel, owns actual action models, registers on the actual Browser's `ExtensionsContainer` identity, observes real TabList selection, and coordinates one current popup plus terminal sessions awaiting safe destruction. No additional activeTab grants or synthetic user gestures are introduced. Pinned state uses the actual profile model and respects managed/incognito restrictions.

The `NativeExtensionActionHost` interface is a mandatory connection to real native shell services, not a supplied no-op implementation. Const queries are side-effect-free main-thread snapshots. Menu/inspection/change callbacks may reenter. Unsupported context-menu, extension-menu and inspect surfaces report capability failure; they are not silently reported as successful UI. Production must supply actual menu presentation, active Browser selection, anchor geometry, one post-renderer native menu route, and genuine browser-security visibility notifications.

## Integration obligations

1. Construct the container only after the actual Browser/Profile/TabList/ToolbarActionsModel exists, and only on the native path where another ExtensionsContainer has not been registered. Keep the shell host alive through container shutdown. Connect the existing native keybinding registry's action dispatcher to `DispatchActionAccelerator` exactly once.
2. Forward shell selection/security-state changes to `HostStateChanged`; do not use `SecurityDialogTracker`'s Views-only false result as native security evidence. The native factory/window supplies extension context menus and toolbar/menu rendering.
3. Shut the container down before Browser/Profile/TabList destruction. Browser/Profile must outlive any in-flight engine or native `sendEvent` callback and deferred terminal host destruction. Use `Shutdown(completion)` and retain Browser/Profile until its completion. Shutdown retains active and retiring popup sessions together with their real action models; a non-nestable task releases those models only after every supplied host is destroyed. Even an empty shutdown completes asynchronously. Do not destroy the Browser halfway through its own popup engine callback and assume a retained session also retains the Browser.
4. Keep the supplied host's genuine WebContents delegate, background-readiness logic, modal handler and Escape behavior. If JS-dialog routing is later replaced with Parc's native dialog runner, feed its actual dialog state into the policy; the global AppModal queue will no longer describe that route.
5. The native view is installed before renderer creation, which may run synchronously. A queued terminal dismissal prevents load completion from showing/focusing/reporting success. The show callback runs once with a real shown host or null on cancellation. Old-generation callbacks cannot clear a new session.

## Checks


```sh
bash tests/NativeExtensionPopup/run.sh
```

The suite covers **57 assertions in seven groups**. The executable uses real NSWindows, supplied NSViews, native close/notification delivery and the main run loop. It covers exact child/page identity and geometry, moved-window resize, parent-specific dismissal with a policy hold, callback reentry/final owner release, replacement during native detachment, invalid attachment, anchor callback invalidation, and a visible parent that must not expose an opening popup.

Syntax-check the three production translation units and six genuine-host browser-test cases using their actual reviewed shared target flags, without generating or building upstream:

```sh
python3 tests/NativeExtensionPopup/check-chromium.py /absolute/path/to/chromium/src
```

The checker requires
`obj/parc/native/native_extensions.ninja` and
`obj/parc/tests/parc_native_extensions/popup_browser_tests.ninja` from the
reviewed integration. It checks all four translation units with ARC and
warnings-as-errors and records source, flag, toolchain and compiler hashes.

The browser tests use actual loaded extensions, actual `ExtensionViewHostFactory`, actual WebContents and visibility observers. They cover supplied identity, close-once results, close during hide/show notification without deleting the notifying WebContents on its stack, security appearing during opening, close completion after actual WebContents destruction, and repeated close observers delivered once each. `Close(completion)` reports actual terminal host destruction after existing result callbacks, not merely a requested dismissal. Execution requires a valid Chromium process/context.

The [native runtime action suite](../NativeRuntime/README.md) exercises real
grants and stale selection through the production bridge. Popup presentation
and retirement use the source owners described above.

The reviewed source overlay compiles all six production files in
`//parc/native:native_extensions`, which consumes the existing
`native_components` page host and has no engine-private dependency. Both
`//parc:browser` and `//parc/tests/parc_native_extensions:popup_browser_tests` use
that implementation. The latter is registered with the actual macOS Chromium
`chrome/test:browser_tests` target and declares `HAS_OUT_OF_PROC_TEST_RUNNER`, as
required for test cases executed by that binary.

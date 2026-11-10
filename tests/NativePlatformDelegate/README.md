# Native Chrome page platform delegate

`Engine/ParcNative/native_chrome_platform_delegate.{h,mm}` connects the actual Chrome
runtime platform-delegate interface to Parc's page wrapper and page-bound
JavaScript dialog runner. The canonical typed native route now selects this
delegate, and the promoted Objective-C facade and Swift shell use the independent
engine path.

## Native ownership

The delegate wraps the existing WebContents native view and preserves its page,
renderer and native hierarchy through creation and transfer. Wrapper focus is
queued and revalidates the actual window at delivery; successful processing is
not proof the renderer focused. Window movement invalidates old attachment.
The native path returns no Views Widget and creates no hidden Chrome window.

The pinned CEF Chrome base preserves actual Browser, Profile, TabStripModel and
WebContents ownership and forwards native input translation to its native
secondary delegate. Parc wraps the supplied NSView without creating a tab,
loading a replacement URL, replacing NSWindow.contentView or taking ownership
of the window. The shell embeds that stable wrapper in its real page container.
The attachment check requires both the owning Browser's tab membership and the
same actual NSWindow as BrowserWindow. Popups cannot inherit a window merely
because the opener had one.

A detached/closing page cannot receive a new dialog or an affirmative focus
request. Detachment closes the request gate before delivering cancellation;
reattachment during that delivery is rejected. The dialog manager owns its
runner; the delegate stores a weak pointer. Native-window changes invalidate
attachment, and the shell must explicitly complete the new association before
calling `PageHostDidAttach()`. `CloseHostWindow()` invalidates this page host,
leaving native window close consent/shared-window coordination with the actual
BrowserWindow owner. It does not delete Browser or WebContents.

CEF may query the window handle on other threads. A lock protects publication
of the stable parent NSView handle; geometry remains UI-thread-only. An
invalidated wrapper stays retained through delegate destruction so a handle
fetched just before closure is not immediately freed. Renderer activation uses
the real RenderWidgetHostView; focus then follows the deferred native wrapper.

Screen conversion follows the **current CEF Mac input contract**: page-local
top-left DIP points go through the actual view's bounds/flip and window conversion
to AppKit screen points. This includes split-pane offsets. This is an explicit
API integration.
The inherited modal host uses the owning Browser's active tab, matching the
shared window-host design. Chrome runtime context menus are a separate route.
The Alloy-only CEF native menu runner is not selected here.

## Checks and integration

```sh
python3 -B tests/NativePlatformDelegate/check-chromium.py /absolute/path/to/chromium/src
```

and warnings as errors. No fake headers or substitute Browser classes are used.
Logs remain in ignored `build/tests/native-platform-delegate/`.

The canonical `native-host-route.patch` selects `NativeChromePlatformDelegate`
and constructs the native BrowserWindow through the real shell provider.
`native_appkit_host.mm` attaches pages after Browser/tab registration, and
`Sources/ParcApp/BrowserWindowController.swift` supplies the actual window and
balanced `pageWillDetach`/`pageDidAttach` calls. Popup/internal creation policy,
the dedicated DevTools route and native first-tab feature hooks are implemented
in source.

# Native Chrome page platform delegate

`Engine/ParcNative/native_chrome_platform_delegate.{h,mm}` connects the actual Chrome
runtime platform-delegate interface to Parc's page wrapper and page-bound
JavaScript dialog runner. The canonical typed native route now selects this
delegate, and the promoted Objective-C facade and Swift shell use the independent
engine path. Release delivery and runtime verification are tracked separately in
[product status](../../docs/parity.md).

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
shared window-host design; per-pane modal behavior still needs runtime
verification. Chrome runtime context menus are a separate route. The Alloy-only
CEF native menu runner is not selected here.

## Verification and integration gates

```sh
python3 -B tests/NativePlatformDelegate/check-chromium.py /absolute/path/to/chromium/src
```

The implementation passes syntax-only compilation with the pinned compiler,
headers or substitute Browser classes are used. Logs remain in ignored
`build/tests/native-platform-delegate/`. This command is not a linked/runtime
test of the adapter. The later complete v50 engine build linked the delegate;
page containment, focus and dialog presentation also have separate executed
AppKit suites. Neither result establishes this bridge's live browser lifecycle.

The canonical `native-host-route.patch` selects `NativeChromePlatformDelegate`
and constructs the native BrowserWindow through the real shell provider.
`native_appkit_host.mm` attaches pages after Browser/tab registration, and
`Sources/ParcApp/BrowserWindowController.swift` supplies the actual window and
balanced `pageWillDetach`/`pageDidAttach` calls. Popup/internal creation policy,
the dedicated DevTools route and native first-tab feature hooks are implemented
in source; their runtime coverage is separate from this integration status.

Remaining runtime acceptance:

1. Exercise native browser creation and popup/DevTools/internal routes with the
   actual independent app, including the supplied window and first-tab services.
2. Verify registration, attachment, removal and live transfer preserve the same
   WebContents and balance the attachment gates across real native callbacks.
3. Verify the retained v5 typed CEF beforeunload dispatch with actual renderer
   requests, including real close consent and shell sequencing.
4. Exercise the integrated native context menus, per-page modals,
   permission/extension presentation, navigation/selection, split/profile
   boundaries and closed-window references against the independent engine.
5. Exercise real HTTPS rendering, compositor/occlusion/accessibility, input,
   zoom/multiple-display coordinate conversion, alert/prompt and Stay/Leave

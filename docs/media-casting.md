# Casting

View → Cast and the current page menu open the genuine Chromium Cast dialog for the original selected page. The registered View command is also available through the command bar. The dialog owns real device discovery, tab/desktop Sources, connecting and connected status, issues, Stop, and the pause/resume controls supported by a real route. Closing the chooser ends discovery/UI ownership; it does not pretend to stop an established route. Reopening exposes the router’s current routes.

## Native ownership

Parc uses Chromium 156 `MediaRouterUI::CreateWithDefaultMediaSourceAndMirroring` and the actual `CastDialogView`. Its native adapter supplies the original AppKit page parent and anchor instead of manufacturing a Chrome BrowserView/toolbar. The real router retains discovery, supported sinks/modes, default presentation requests, OS capture permission, route requests/results and failure messages. The dialog retains Chromium's geometry, palette, keyboard and accessibility behavior.

The native session binds the original WebContents/document, Browser/Profile and NSWindow. Each route-changing action revalidates them, selected/visible page, policy, security reservation, retirement and transfer state. Navigation, hidden/changed selection, transfer, renderer loss, parent closure/minimization and profile/service shutdown revoke the chooser. Controller dispatch retains its owner and defers destructive reentry until the current controller call returns. Native service observers detach before service shutdown. No URL is replayed and no page or device list is duplicated.

Read-only menu eligibility may run while the original window’s command bar is key. Opening discovery/UI still requires the original browser window to be key and the app active, then repeats validation after dropping renderer fullscreen. The true fullscreen blocker remains owned until the chooser closes.

When policy enables Chromium’s Access Code control, the genuine starter and WebUI retain the original Profile and request. A stale native controller returns no starter and opens nothing; a native AppKit parent uses the original WebContents view without requiring an unrelated Views widget. That accepted continuation follows upstream ownership and permissions. The separate website-initiated Presentation/Remote Playback chooser is described below.

## Website presentation requests: native media-controls chooser

A website Presentation or Remote Playback prompt carries its original `StartPresentationContext`, including the requesting frame, source URLs and real result callbacks. Parc opens the genuine Chromium global media controls dialog, native-parented to the requesting window, with the request's actual media-session item or the supplemental presentation item. Discovery, device selection, route results, media controls and their availability remain owned by Chromium. This replaces the interim Cast-view presentation; ordinary Cast keeps its own native dialog and both entry paths close the other before taking ownership.

The chooser owns the original WebContents, main and requesting-frame documents, Browser/Profile and window. Navigation, frame deletion, selection changes, parent closure/minimization and service shutdown revoke the exact request; actions recheck the original owner and current policy. Replacement and asynchronous device-picker callbacks are token-scoped, so a retired request cannot dismiss or complete its successor. Before route selection, cancellation returns the original context's Chromium error. Once selected, the in-flight route response retains its original document validation independently of the dialog: closing the chooser or switching tabs does not itself cancel it. A response for a stale document is refused and a non-local returned route is detached; an unregistered local connection is released.

The upstream device host prefers presentation or remote playback and, where Chromium's enabled audio-mirroring feature permits, offers tab mirroring for audio speakers and groups. The latter starts the real mirroring route; because it is not a presentation route, the unconsumed website context receives Chromium's cancellation/no-screen result when its controller is retired. No tab or desktop source is substituted for the website's successful presentation callback.

## Checks and remaining comparison

Pinned native/Chromium compiler checks cover the Cast and presentation adapters.
Focused manager, supplemental-picker, presentation-item and service regression
sources have compilation coverage; this is not test execution. Device
interoperability, network/OS permission presentation and integrated keyboard,
accessibility and appearance remain unverified. PiP work is not reopened.

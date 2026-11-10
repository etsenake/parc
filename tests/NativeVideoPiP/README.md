# Native video Picture-in-Picture

Chromium owns the actual VideoOverlayWindow, media controller, Viz surface and
compositor. The application retains PCVideoPiPPresenter and its panel/controls.
The route adds no WebContents or hidden BrowserView. PiP is accepted as complete
by Josh; old investigation receipts do not reopen that assignment.

## Behavior and ownership

The native factory validates exact tab/Browser ownership. Ordinary browsers keep
their upstream route. Immersive stereo sessions are refused because this macOS
presenter does not support their projection. Actions and capability changes use
the actual media controller; a stale panel cannot close a newer global session.
Release returns to the application client that created the panel.

Close pauses and exits; Hide exits without pause; Return exits and restores the
source window. The floating, nonactivating, resizable all-spaces panel cannot
become key. Initial width is 320 points with the source aspect ratio. The same
native video view survives hide/reentry.

Create the hosting CALayer and DisplayCALayerTree before enabling AppKit layer
hosting. Commit size before notifying occlusion observers, revalidate after
callbacks and update the real layer bounds last. Native window identity, bounds,
visibility and destruction feed the security-occlusion tracker. Disconnect the
compositor callback/root before destruction. A terminal close callback can delete
the overlay synchronously; never access its members afterward.

## Checks and limits

Presenter and layer component checks cover native panel state, callbacks,
replacement, resize and teardown. Chromium controller tests cover their actual
engine boundaries. Compiler acceptance does not mean those linked cases ran.
Use finished-source receipts for current verification; old package/GUI diaries
are available in Git history and are not current failures or live processes.

Browser/app launch and screenshots are prohibited by [AGENTS.md](../../AGENTS.md).
Current media behavior and remaining work belong in
[media interactions](../../docs/media-interactions.md) and
[the backlog](../../docs/backlog.md).

## Integration membership

The CEF engine owns `video_overlay_window.mm`; the header-only native PiP API
allows Chrome callers to use the bridge without a Chrome-to-libcef cycle.
Production targets depend on the real media-session, compositor, accelerated
widget, display and window owners. AppKit and QuartzCore are explicit.

The native video PiP browser/unit test targets are reached from the actual Chrome
test graph and link the engine implementation. Browser fixtures require valid
CEF test initialization before execution. The app build compiles
`Sources/ParcEngine/VideoPiPWindow.m` with the existing facade and QuartzCore.
Target membership, compilation, linking and execution are separate checks.

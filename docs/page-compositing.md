# Page compositing across tab switches

Pages in a window draw through compositors the window keeps, so switching
tabs in a pane shows that pane's last frame and then the new page's frame,
with no white in between. Josh reported (November 1) that every tab switch in a
single window flashed white, whether he came back after two seconds or twenty

## Cause

Parc has no Views window compositor, so each page drew through its own
compositor (`BrowserCompositorMac` in its `HasOwnCompositor` state). Hiding a
tab destroyed that compositor (`browser_compositor_view_mac.mm` 251–264) and
showing it built a new one (274–292). The page view displays a remote layer
bound to its compositor's GPU-side context (`display_ca_layer_tree.mm`
141–165), so the old frame vanished at once, and the new one arrived only
after the new compositor's first frame (`render_widget_host_view_mac.mm`
211–221). Meanwhile the pane's white page backing showed. This has been the
behaviour since the native host started hiding unselected pages on October 24;
none of the November engine changes caused it.


approximate):

| Address | What it does |
|---|---|
| `-[WebContentsPaneHostView initWithFrame:]` `0x4737074` | Installs a `PaneHostCompositorOverlayView` and takes Chromium's `ImageTransportFactory`: each pane owns a compositor. |
| `attachWebContentsHostView:` `0x4737eb4` | Detaches the previous page, then attaches the next to the same pane. |
| `syncHostedWebContentsState` `0x4738bb0` | Feeds the window, hidden state, bounds, screen, scale, display and refresh rate. |
| `viewDidMoveToWindow` `0x4737c38` | Observes the window's screen changes. |

Josh compares against. Not traced: the Swift owner of the pane host (reached
through protocol tables), whether its overlay sits above or below the page

## Parc

`Engine/ParcNative/pane_compositor.{h,mm}` (source set
`native_pane_compositor`):

- **Compositor.** A `ui::RecyclableCompositorMac` with a transparent,
  undrawn root layer, shown by a `PCNativePaneCompositorView`
  `ui::DisplayCALayerTree`, the pattern of the video Picture-in-Picture window.
  While attached it is the `ui::ViewsHostableView::Host` of one page's
  WebContents view, so Chromium draws every renderer of that page, including
  ones it creates on later navigations, into its root layer
  (`UseParentLayerCompositor`, the state Chrome's own windows use).
- **Window pool.** Parc's shell keeps a view per tab rather than per pane, so
  the compositors belong to the NSWindow, shared by every Profile's browser
  host in it. A page about to be shown keeps its own compositor, else takes
  one whose display view has left the screen, else gets a new one. Taking one
  does.
- **Held frames.** The display view still holds the last frame it drew. The
  new page keeps showing it until its own frame arrives only when it fits the
  page (`PaneHeldFrameFits`): the same role (page or docked DevTools), and
  the size the compositor draws at (its root layer's bounds) and the page
  view's size each covering at least 90% of the other, so a top bar coming or
  going still counts. Otherwise the frame belongs to another pane (the other
  side of a split, a whole pane under a Peek card, the page a docked DevTools
  narrowed) and the display is cleared before the page is placed, so it shows
  the pane's own backing as a fresh compositor would. Sizes decide, not
  places: until overlay 342 the rule compared the place recorded for the
  departing page with the incoming view's place in the window, and the two
  differ for the same pane whenever the shell has parked one or not yet laid
  the other out, so an ordinary tab switch cleared the display and showed the
  pane's white backing until the new page's first frame. The places still
  rank candidates: a fitting compositor is preferred, then the one last shown
  overlapping the page most, then a free one, then the most recently used.
- **Drawing.** A compositor stops drawing as soon as its display view leaves
  the screen (the page, or an ancestor such as the pane Parc parks, is
  hidden, or it leaves the window), unless a capture lock is held, and its
  widget ignores frames still in flight; so no frame without the page can
  replace the one held for the next page, however late the host's pass runs.
  It resumes when the view is back on screen with its page shown. A page
  being captured keeps its compositor drawing (`CreateVideoCaptureLock`). The
  pool also follows `display::Screen` metric changes, for a refresh-rate,
  colour-space or HDR change on the same screen.
- **Busy hand-offs.** If a hand-off involving the page is mid-flight in a
  native callback, `ShowInPaneCompositor` reports it busy: the host reruns its
  visibility pass, and the DevTools pane lays out again, rather than unhide a
  page with nothing to draw through.
- **Sweeps.** Every two seconds while any compositor is idle, an idle one is
  marked, and retired at the next sweep if still idle. The most recently used
  idle compositor stays as a spare for the next switch, such as docked
  DevTools coming back with its tab. In a hidden or minimized window, hidden
  pages keep their compositors so the restored window shows them at once;
  free ones still go. With no host left in the window, nothing is spared.
- **Display view placement.** Inside the page's WebContents view, directly
  above the renderer view (Chromium inserts renderers at the bottom of that
  view, and keeps other overlays above it), filling its bounds, so it shares
  the page's frame and hidden state. It takes no events, focus, dragging or
  accessibility. `PCNativePageHost` skips it when it picks the renderer
  Parc's per-tab page hosts and first-docked DevTools have no such shared
  container.

### Chromium constraints

- Once a renderer view has drawn through a parent compositor, Chromium turns
  off that view's own drawing for good (`RenderWidgetHostViewMac::
  SetParentUiLayer`, `DisableDisplay`); a renderer view created later, while
  the page has no compositor, draws by itself until it gets one. So a page
  must be attached before it is shown. The native host's visibility pass
  attaches tabs, splits, Peek and Easel pages before it unhides them, and the
  DevTools pane attaches docked tools. Undocked DevTools, popups and document
  Picture-in-Picture windows have browser hosts of their own running the same
  pass. A page Chromium shows by itself outside that pass (its WebContents
  view unhidden, or added to a window, by AppKit) draws nothing until the
  pass attaches it, which normally happens in the same run loop turn.
- `WebContentsViewMac::ViewsHostableDetach` hides the WebContents view and
  removes it from its superview. Parc owns that hierarchy, so the engine puts
  it back where it was: `-[PCNativePageHost restoreContentView:]` re-pins a
  page host's content, and a first-docked DevTools view goes back below the
  inspected page with its frame. The view's hidden state is restored too.
  The page's attachment stays marked busy until Chromium's detach returns, so
  no visibility callback during it can reattach the page.
- `WebContentsViewMac`'s destructor requires its host to detach first
  (`OnHostableViewDestroying`). The pool lives while a browser host holds a
  claim on its window or a compositor holds a page, and a detached
  compositor releases its pool on a later task so it never destroys itself
  mid-call; a dropped task leaks the reference.
- No compositor may outlive Chromium's `ImageTransportFactory`, which
  `CefShutdown` terminates (`BrowserMainLoop::ShutdownThreadsAndCleanUp`,
  after `BrowserCompositorMac::DisableRecyclingForShutdown`).
  `PrepareNativeApplicationShutdown`, which runs on the main thread after the
  message loop returns and immediately before `CefShutdown`, calls
  `ShutDownPaneCompositors`: every page is detached and every compositor
  destroyed there, and nothing attaches or schedules work afterwards. This
  was chosen over relying on deferred releases alone, which already leak when
  dropped but could still run during shutdown's own run loops.

### Timing

The shell swaps panes synchronously in its render
(`updateSplitArrangement`: the outgoing pane goes to `parkedPages`, the
incoming one into the split view), and the incoming page's WebContents view is
still hidden from its last deselection (`setContentVisible:`). Until overlay
301 only a posted task (`Synchronize`, `PostNonNestableTask`) unhid it. AppKit
runs its run loop with return-after-source-handled, so a commit can happen when
the run loop exits after each Chromium task batch, before that task runs. That
commit showed the new pane with its page hidden: the white page backing,
whatever frame the compositor held. This was a flash on every switch, and the
held frame never made a difference.

Since overlay 302, the shell's `synchronizeSelectionAndLayout` and
`synchronizeLayout` calls, which it makes after rearranging its panes, also
run the visibility pass synchronously (`SynchronizeAppKitBrowserVisibility`).
The hand-off, the unhide and `WasShown` then join the shell's arrangement in
the same commit. The posted pass still runs afterwards for adoption and
selection, and repeats the same visibility work with no further effect. A pass
started by a native callback during another one is skipped; the outer pass
reruns through `Synchronize` when what it showed has changed. The CA
commit-on-exit ordering comes from AppKit and Core Animation behaviour, not
from Parc source, and hasn't been observed in a run yet.

## What still shows white

- The first page shown through a brand-new compositor (a new window, an
  extra split pane, a Peek, the first docked DevTools) waits for its first
  frame, as before.
- A page whose last frame Chromium evicted (it keeps a limited number of
  hidden tabs' frames, fewer under memory pressure), or a background tab that
  has never drawn, shows the previous frame for a few frames and then the pane
  backing until it repaints, as in Chrome.
- A page replacing another pane's frame starts from the pane backing: a page
  shown where a split used to be, a Peek, and a tab replacing one whose page
  docked DevTools, so the whole pane's frame could be held there, isn't
  established; Parc's page and tools each have their own.
- Docked DevTools can still flash when its window has used more compositors
  than its one spare since the tools were last shown, for example after
  opening and closing a split on another tab.

## Checks

- `scripts/test-pane-compositor-policy.sh` (in `scripts/test.sh`): hand-off
  choice, the held-frame rule and sweep decisions, 41 checks.
- `tests/NativePageHost/run.sh` (now in `scripts/test.sh`): the display view
  in real offscreen AppKit (never the renderer responder, events pass
  through, on-screen state including a page parked in a hidden container,
  screen and geometry callbacks) and content restoration after a
  Chromium-style detach; see [its README](../tests/NativePageHost/README.md).
  `tests/NativeFocusManager/run.sh` and `tests/NativeExtensionPopup/run.sh`,
  which also build the page host, now run there too.
- `tests/Packaging/test_native_page_host_exports.py`: the page host still
  links across the Swift boundary and the display view isn't exported.
- `tests/NativeDevTools/check-chromium.py` syntax-checks `page_host.mm`,
  `pane_compositor_view.mm` and `pane_compositor.mm` at their integrated
  targets once the overlay is applied.
- Compiled with their real `Release_GN_arm64` commands (`siso query
  commands`, outputs redirected to `/tmp`), with this checkout's
  `Engine/ParcNative` searched ahead of the engine tree so every
  `cef/libcef/browser/parc_native` include is overlay 297's:
  `pane_compositor_view.mm` and `page_host.mm` (native_components),
  `pane_compositor.mm` (native_devtools' and libcef_static's commands, as its
  new target has none until generation), `devtools_pane.mm`,
  `native_appkit_host.mm` and `native_appkit_application.mm`.

Overlay 302's synchronous pass: `native_appkit_host.mm` and
`native_appkit_application.mm` compiled with their real `Release_GN_arm64`
commands against this checkout's `Engine/ParcNative`. Not yet built into an
engine or run in the app.

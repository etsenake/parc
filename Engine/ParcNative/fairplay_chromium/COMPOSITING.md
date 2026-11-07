# FairPlay compositing (display half of M1)

A FairPlay renderer decodes into an `AVSampleBufferDisplayLayer` that Apple
never reads back, so Chromium can't draw the video. It can only put that layer
where the `<video>` element is, among the page's other CALayers. This document
covers the path that does that, what happens when it can't, and what Josh's
first engine build should check. The CDM, renderer and media pipeline belong to
`fairplay-media`; this covers the registry and the compositor.

Engine changes: `Engine/ParcHost/integration/fairplay-compositing.patch`, plus
`protected_layer_registry.{h,mm}` installed at
`//ui/accelerated_widget_mac/`. Nothing here changes ordinary video. Every new
branch is taken only for a `viz::VideoHoleDrawQuad`, and on Mac only a FairPlay
renderer makes those. The other producer, `VideoOverlayFactory`, serves the
Mojo `Renderer` service, Cast and Android flinging, and a Mac build enables
none of them (`media/media_options.gni` gives Apple only decoder and encoder
Mojo services).

## From frame to CALayer

1. **GPU process, renderer side (`fairplay-media`).** The FairPlay
   `media::Renderer` creates a `base::UnguessableToken`, then calls
   `ui::ProtectedLayerRegistry::Register(token, layer)` with its
   `AVSampleBufferDisplayLayer` before the token leaves the process. The
   registry is thread-safe and retains the layer until `Unregister`. The
   native HLS player ([NATIVE_HLS.md](NATIVE_HLS.md), not built yet) will
   register its `AVPlayerLayer` the same way, and it is placed the same way,
   except as noted in step 8.
2. **Renderer process.** The renderer client receives `(token, natural_size)`
   over its client extension and paints
   `media::VideoFrame::CreateVideoHoleFrame(token, natural_size, ts)` through
   `VideoRendererSink::PaintSingleFrame`. It paints again whenever the natural
   size changes. The frame is `STORAGE_OPAQUE` and `PIXEL_FORMAT_UNKNOWN`, with
   the token in `metadata().tracking_token`. No pixels exist; canvas, WebGL and
   `requestVideoFrameCallback` see only this frame, and
   `PaintCanvasVideoRenderer` (`media/gfx/`) paints black for a frame with no
   pixels.
3. **Video surface.** Blink's `VideoFrameSubmitter` gives the frame to
   `media::VideoResourceUpdater` (`media/gfx/video_resource_updater.cc`, not
   changed). That updater already turns any opaque unknown-format frame that
   carries a tracking token into a `viz::VideoHoleDrawQuad` with
   `overlay_plane_id = token`, at `quad_rect = natural_size` and with the
   video's rotation as the quad transform. The quad serializes over mojo on
   every platform (`services/viz/.../quads_mojom_traits`).
4. **Aggregation.** The page embeds the video surface through a SurfaceLayer
   stretched to the element's content box (object-fit already applied), so the
   aggregated quad's transform maps `natural_size` onto the element. The video
   surface's root pass normally merges into the page's root pass. When a copy
   request or video capture would stop that merge, `SurfaceAggregator` still
   force-merges the quad, because `OverlayCandidate::RequiresOverlay` is true
   for `kVideoHole` (already upstream).
5. **Overlay processing** (`components/viz/service/display/ca_layer_overlay.cc`).
   `FromDrawQuad` now accepts `kVideoHole`. The candidate gets the quad's rect,
   clip, rounded corners, transform, opacity and sorting context like any quad,
   plus `protected_layer_token` (new, Apple only, in
   `overlay_candidate.h`) and `protected_video_type = kHardwareProtected`. It
   counts as a video for CoreAnimation's layer limits.
6. **SkiaRenderer** (`skia_renderer.cc`). `ScheduleOverlays` skips the resource
   lock for such a candidate (it has no resource), so it reaches the output
   surface with a zero mailbox. `SkiaOutputDeviceBufferQueue` already passes a
   zero mailbox through with no overlay access.
7. **Presenter** (`output_presenter_gl.cc`). The candidate becomes
   `ui::CARendererLayerParams` with a null IOSurface and
   `protected_layer_token` set (new member in `ui/gl/ca_renderer_layer_params.h`).
   It reaches `ImageTransportSurfaceOverlayMacEGL::ScheduleCALayer` on the GPU
   main thread.
8. **CALayer tree** (`ui/accelerated_widget_mac/ca_renderer_layer_tree.mm`).
   A content layer with a token is the new `CALayerType::kProtectedLayer`:
   - It looks the token up in the registry when the frame is scheduled.
   - Its `ca_layer_` is a plain CALayer host that the tree owns, positioned at
     the quad's rect with the quad's opacity. The usual clip, rounded-corner
     and transform layers above it carry the rest of the geometry.
   - At commit, `CommitProtectedLayer` adds the registered layer to the host
     and fills it: anchor (0, 0), position (0, 0), bounds equal to the host's,
     identity transform, opacity 1, not hidden. On an
     `AVSampleBufferDisplayLayer` it also sets `preventsCapture = YES`,
     `videoGravity = AVLayerVideoGravityResize` (as Chromium's own video layers
     do) and `geometryFlipped = YES` (Chromium's HDR-transform workaround).
     On the native HLS player's `AVPlayerLayer` ([NATIVE_HLS.md](NATIVE_HLS.md))
     it sets only the Resize gravity: AVFoundation keeps FairPlay video from an
     `AVPlayer` out of captures by itself (clear HLS stays capturable, as in
     Safari), and the flip is an `AVSampleBufferDisplayLayer` workaround that
     WebKit doesn't apply to its `AVPlayerLayer`.
   - The host sits in the same back-to-front sibling order as the quad, so page
     content drawn over the video (controls, subtitles) stays above it.
   - Old-tree matching keys a protected content layer by its registered layer,
     as other layers are keyed by IOSurface, so the same host is reused frame
     after frame. Scroll and resize change only the transform and rect of
     layers that already exist.

The host exists so the tree's existing reuse and removal code (each destructor
calls `removeFromSuperlayer` on its own CALayer) can never detach the registered
layer from a newer tree. A CALayer has one superlayer, so the hosting rule is:
the tree committing now takes the layer. A compositor that stopped drawing (a
hidden or parked pane compositor) keeps its last tree but never commits, so it
can't hold the layer away from the compositor that shows the page now.

Every committed content layer that shows a registered layer is recorded,
process-wide, with its commit order. When the holder lets the layer go (its
tree replaced by one without the token, a new token in its host, its
coordinator's tree dropped on resize, or teardown), the layer moves at once to
the most recently committed layer that still shows it in a live tree. So a
stale frame committed late (Parc holds the previous page's frame during a tab
switch) and then replaced can't strand it. The visible tree gets it back
without a commit of its own, which may never come because the video plays
without compositor frames.

The cost is that two trees that both keep drawing the same token trade the
layer every frame. Only one surface embedded in two live compositors does that,
and Picture in Picture must avoid it (below).

Parked pane compositors never take a layer. A parked (suspended) pane
compositor still redraws when a surface its held frame embeds changes, and the
GPU process can't tell it from one on screen. So Parc tells viz:
`NativePaneCompositor::SuspendDrawing` (and the constructor, since a compositor
starts parked) calls `ui::Compositor::SetProtectedLayersAllowed(false)`.
`ResumeDrawing` sets it back to true before unsuspending, but only when the
display's held frame is the resumed page's own (`held_frame_page_`). When the
held frame is another page's (a spare reused after a page moved away),
redrawing it would place that page's video and take it from the compositor
showing it. So the flag stays false until the new page's first frame is on
screen (`RequestSuccessfulPresentationTimeForNextFrame`, which queues a
callback and makes no frame). The flag goes through
`viz::mojom::DisplayPrivate::SetProtectedLayersAllowed` to
`viz::Display::SetProtectedLayersAllowed` and then to `CALayerOverlayProcessor`.
While it is false, a FairPlay hole quad becomes a black solid-color CALayer
with no token on the all-CALayer path, or stays in the primary plane, drawn
black (magenta with DCHECKs), when the frame falls back to underlays. Either
way, a parked display's tree never takes or claims the layer.

When the flag changes on a display whose last frame had a FairPlay hole,
`Display` redraws that frame once (full damage on the root surface, as
`SetColorMatrix` does). On parking, the redraw replaces the parked tree's
protected host with the black layer: the old host is destroyed, its claim
dropped, and the layer handed on to the newest live tree that shows it. On
resuming, the redraw places the layer again. This closes the window-drag race,
where the old window's spare redrew after a same-size hole frame and took the
layer. It also closes the two cases where a parked tree kept the layer, or
received it by hand-on, through a claim made before it parked.

Ordinary pages are unchanged:
- The flag is read only in the `kVideoHole` branches of `FromDrawQuad` and
  `PutForcedOverlayContentIntoUnderlays`. Nothing else in a frame depends on
  it (`CALayerOverlayTest.ProtectedLayersFlagLeavesOrdinaryFramesAlone`).
- `Display` redraws only when the last frame had a FairPlay hole. Otherwise
  the change is a stored boolean, with no damage and no draw.
- `ui::Compositor` sends it only when it changes, and again after a new frame
  sink, as it does `SetOutputIsSecure`.
- `SuspendDrawing` and `ResumeDrawing` still suspend and unsuspend the widget
  and compositor exactly as before, in the same order. The flag is one extra
  call in each, after `Suspend()` and before `SetSuspended(false)`. Resuming
  for another page's held frame also queues a presentation callback, which
  makes no frame.
- The hand-off policy (`pane_compositor_policy.h`: `ChoosePaneCompositor`,
  `PaneHeldFrameFits`, the sweep) is untouched, and its 50 checks
  (`tests/PaneCompositorPolicy`) pass.

So a tab switch from a page without FairPlay video keeps the previous frame
until the new page's first frame, as 04b9741d and 115676bb made it. For a page
with FairPlay video, the redraw that parking triggers shows the video area of
the held frame black. The next page keeps showing it that way until its own
frame arrives, and the video is never placed in that compositor meanwhile. A
page shown again in its own compositor gets its video back with the first
redraw.

## When the frame can't be all CALayers

`OverlayProcessorMac` first tries to turn every root-pass quad into a CALayer.
When that fails for a frame, `PutForcedOverlayContentIntoUnderlays` runs, and it
now treats `kVideoHole` like hardware-protected texture video. The quad goes
into an underlay CALayer below the primary plane, through the same
CARendererLayerTree path. Its place in the primary plane is replaced by
`ReplaceExistingQuadWithHolePunch`: a transparent quad that clears what was
drawn below it, or a DstOut quad if the video is translucent. Content composited
above the video is drawn after it, so the protected layer shows through the hole
under controls and subtitles exactly as in the all-CALayer case.

Frames that take this underlay route (the user sees no difference):

- **Video capture or a copy request on the root surface** (the whole
  compositor, not the page). Tab capture, getDisplayMedia of this tab,
  `CopyFromSurface` snapshots (Parc's tab previews and page capture) and
  DevTools screenshots attach to the page's surface instead. The aggregator
  then keeps the page in its own pass for the copy and still copies the hole
  quad into the root pass, because the quad requires an overlay. So the screen
  usually stays all-CALayer. The captured image is black where the video is,
  as in Safari (magenta in DCHECK builds; transparent for a root-surface copy).
- **More than 128 quads in the root pass** (300 with five or more videos;
  `kCALayerNewLimit` is off by default). Busy pages, such as a browse grid with
  a preview playing, can exceed this.
- **Something else in the page that CoreAnimation can't represent:** a
  non-src-over blend mode on any quad (mix-blend-mode), backdrop-filter, an
  unsupported filter, a render pass in a 3D sorting context or under a
  non-axis-aligned clip, more than 30 render passes, or non-uniform corner
  radii.

The video area is **black** (never stale, never garbage) only when even the
underlay can't be used:

- **The hole quad isn't in the root render pass,** because an ancestor of the
  video needs a render surface. Causes: CSS filter, clip-path or mask, an
  opacity group over the video and siblings (for example a fade transition),
  mix-blend-mode isolation, preserve-3d, or a video surface transform that
  isn't axis-aligned (a rotation other than a multiple of 90°), which stops
  the aggregator merging the surface. SkiaRenderer already draws any quad that
  requires an overlay as solid black in release builds (magenta with DCHECKs).
- **The quad itself can't be a CALayer:** a blend mode other than src-over on
  the video, non-uniform corner radii, or a clip change inside a 3D sorting
  context. The hole stays in the primary plane, drawn black, and other videos'
  underlays in the same frame are kept.
- **Software compositing** (GPU compositing disabled). The patch makes
  `SoftwareRenderer` draw the hole black instead of its unsupported-quad white.
- **No layer is registered under the token:** the renderer is gone, or the GPU
  process restarted and the page still shows the last hole frame. The host is
  black and empty.

How often: the services' players (Netflix's watch page, Apple TV+'s player)
put the video in an ordinary box under their controls, so they should stay on
the all-CALayer path while playing. They should drop to the underlay for single
capture frames and on busy pages. They go black only during effects applied to
the video or its container, such as a cross-fade, a filter or clip-path, or a
free rotation. Counts are unmeasured until there is a build. Each frame's result
is recorded in the `Compositing.Renderer.CALayerResult` histogram, and
`--show-mac-overlay-borders` outlines the protected host in orange.

Whether the black frames can be avoided: the underlay route already covers
every case where the quad reaches the root pass. Covering a quad inside a
render pass would mean promoting that pass as a CALayer, punching a hole in its
backing and placing the protected layer below it, with the pass's filter
applied to the video. CoreAnimation can't apply most CSS filters to another
process's AVSampleBufferDisplayLayer, so this stays black by design. Safari
behaves the same way for filters it can't composite.

## Geometry, windows and teardown

- **Scroll and resize:** every compositor frame re-schedules the quad, and
  the matched host and its transform layer update in place. The video plays
  without compositor frames, because the AVSampleBufferDisplayLayer renders
  itself; only geometry changes need frames.
- **Window resize and fullscreen:** a resize is a new frame at a new size.
  The tree matches the same host, and only the transform and rect change.
  `kCATransactionV2` is off upstream. With it on, a resize makes
  `CALayerTreeCoordinator` drop its tree and CAContext before the next commit,
  and the next tree builds a new host, which takes the layer, all inside one
  CATransaction. Parc's fullscreen keeps the page in its own window and
  compositor, so it is a resize. The video element itself entering fullscreen
  ends its PiP (`HTMLVideoElement::DidEnterFullscreen`, called only when the new
  fullscreen element is the video). A container entering fullscreen, as
  Netflix's player does, leaves PiP running; the page still draws no video
  quad, so the video stays in the PiP window. Low-power
  fullscreen detachment (`kFullscreenLowPowerBackdropMac`) is off upstream; if
  it were on, a protected layer would count as the video layer.
- **Moving between windows:** Parc's pane compositors belong to a window, so a
  page moved to another window, or shown by another pane compositor after a
  tab switch, is drawn by a different `CALayerTreeCoordinator`. All
  coordinators live on the GPU main thread of the same process. The tree that
  draws the page takes the layer at its first commit. Within one window, only
  the compositor that last drew a hidden page embeds its video, and that
  compositor either keeps the page or draws the incoming page over its held
  frame (`ChoosePaneCompositor`). So a tab switch never leaves a second tree
  naming the token. A page dragged to another window leaves its old window's
  compositor parked, and a parked compositor never takes the layer (above).
  When a tree that took the layer drops the token, the layer returns to the
  page's tree. A layer can only be in one place.
- **Tab switch and hidden page:** the pane compositor moves on to the new
  page, so the old page's tree drops the token and the layer is detached
  (nothing else shows it). Half a second later the video surface submits an
  empty frame (`VideoFrameSubmitter::SubmitEmptyFrameIfNeeded`). When the page
  is shown again, the submitter sends the hole frame again and the page's tree
  takes the layer. Whether a detached AVSampleBufferDisplayLayer keeps decoding
  or sets `requiresFlushToResumeDecoding` is unverified; fairplay-core
  re-enqueues from the last keyframe when it does. While hidden,
  `WebMediaPlayerImpl::ShouldDisableVideoWhenHidden` may also disable the video
  track of an A/V MSE player that isn't in PiP. A disabled stream ends video in
  the FairPlay renderer, so `fairplay-media` makes that function return false
  for FairPlay players (06350901): the track stays enabled while hidden, as in
  PiP. It also turns off idle and background auto-suspend for them, since a
  suspended renderer would drop its layer while the painted hole frame still
  named it.
- **Teardown:** the renderer flushes with removal of the displayed image,
  then unregisters. The tree that holds the layer releases it at its next
  commit: that commit's lookup misses, the host goes black, and the layer is
  removed from it. Until then the flushed layer shows nothing. The tree's own
  reference is released when the tree goes away.

## Picture in Picture (M3)

Beyond the compositor above, the only engine change is in Parc's PiP window:
it stops drawing while hidden (step 4). The steps below are what the pinned
source does, plus the natural-size contract with `fairplay-media`.
`CALayerTreeTest.ProtectedLayerPictureInPicture` runs the CALayer side of this
sequence.

1. **The page stops drawing its video.** `WebMediaPlayerImpl::OnDisplayTypeChanged`
   calls `client_->SetCcLayer(nullptr)` for `kVideoPictureInPicture` unless
   `IsInAutoPIP()`, and restores the layer when PiP ends. `IsInAutoPIP()` is
   true only for persistent video, which only Android sets
   (`WebContentsAndroid::SetHasPersistentVideo`). So on Mac the page's frames
   don't name the token during PiP, and they can't pull the layer back from the
   PiP window, whose video plays without compositor frames.
2. **The PiP window's first frame.** The same call posts
   `VideoFrameCompositor::SetForceSubmit(true)`, so `VideoFrameSubmitter`
   submits its current frame (the hole frame) at once and keeps submitting
   while the page is hidden. Its same-frame check skips that submission only
   while the surface still holds the hole frame. After a hidden page's empty
   frame, the check is reset and the hole frame goes out again. Its wait for a
   compositor ack can't hold the hole frame back either: an empty frame clears
   it, a frame in flight is the same hole frame, and a size change bypasses
   it. Parc's window
   (`Engine/ParcNative/video_overlay_window.mm`) embeds the surface stretched
   to its view (`LayerSurface::SetShowSurface`) in its own
   `RecyclableCompositorMac`. That is a browser compositor, so its display uses
   `OverlayProcessorMac` like a page's. The hole quad is promoted, and the PiP
   window's tree takes the layer at its first commit, at the panel's size.
   `preventsCapture` still applies.
3. **Natural size.** Blink's `StartSession` and `PictureInPictureSession::Update`
   send `WebMediaPlayerImpl::NaturalSize()`, which reaches
   `NativeVideoOverlayWindow::UpdateNaturalSize`, then
   `-[PCVideoPiPPresenter setNaturalSize:]`. That value is set from the
   stream's config with the metadata (`OnMetadata`), then changes only through
   `RendererClient::OnVideoNaturalSizeChange`. Updates also follow surface ID
   changes, which the hole frame's size changes cause. As agreed with
   `fairplay-media` (06350901), FairPlayRendererClient forwards each size to
   the pipeline's `OnVideoNaturalSizeChange` first, then repaints the hole
   frame at that size, and the GPU adapter reports the config's size once at
   the first `StartPlayingFrom`.
4. **Leaving PiP.** The page adds its video layer back and its next frame
   takes the layer. Parc hides the PiP window for reuse, and
   `NativeVideoOverlayWindow::Hide` now also makes its compositor invisible
   (`ui::Compositor::SetVisible(false)`, as `NativeWidgetMacNSWindowHost` does
   for hidden windows). It also starts invisible until `ShowInactive`.
   Suspending alone only deferred the window's own commits: its display still
   redrew when the embedded video surface got a frame (for example the hole
   frame again after the page was hidden and shown). That draw would take the
   layer from the page. A hidden window now keeps its last tree without
   drawing. If the window is closed before the page's frame arrives, the layer
   is in no tree until that frame, which follows at once because adding the
   layer triggers a commit.
5. **Not AVKit.** System PiP (`AVPictureInPictureController` with a
   sample-buffer content source) needs the display layer in the browser
   process, and this layer lives in the GPU process. Parc's own panel is the
   path.

## What Josh's first build should check

1. The overlay applies, and `accelerated_widget_mac`, `viz_service` and
   `gl` compile. Optionally build and run `accelerated_widget_mac_unittests`
   with `--gtest_filter='CALayerTreeTest.ProtectedLayer*'`. `ProtectedLayer`
   checks placement, reuse across frames, taking the layer back from an idle
   tree, handing it back when a late tree drops the token, and the black host.
   `ProtectedLayerPictureInPicture` runs the PiP sequence. `viz_unittests`
   with `--gtest_filter='CALayerOverlayTest.Protected*'` checks that a parked
   display shows the hole black without a token, and that the flag leaves an
   ordinary frame alone.
2. Ordinary video is unchanged: YouTube and an MSE test page still show
   yellow (8-bit) or cyan (HDR) AV layers, or regular layers, with
   `--show-mac-overlay-borders`.
3. Once `fairplay-media` lands, an Axinom FairPlay vector in a Parc tab shows
   an orange-bordered host with the video inside, under the page's controls.
4. Scroll, resize the window, enter and leave fullscreen, switch tabs away
   and back, and drag the tab to another window. The video follows each time
   and never shows stale content. After the drag, hide and show the tab in the
   new window: the video stays there. Ordinary tab switches still show the
   previous page until the new one draws.
5. Screenshots (⌘⇧4) and screen sharing show black where the video is.
   Watch the macOS fullscreen transition too: its animation is a window
   snapshot and may show the video black for its half second.
6. Picture in Picture from the video's context menu or the page's button:
   - The video moves into Parc's panel, orange-bordered, at the panel's
     aspect ratio, and the page shows its placeholder.
   - Resizing the panel follows. A screenshot of the panel is black.
   - Leaving PiP puts the video back in the page.
   - Repeat with auto PiP on a tab switch.
   - Put the video element itself into fullscreen while in PiP: PiP ends and
     the video shows in the page.
   - Put Netflix's player container into fullscreen while in PiP: PiP stays
     and the video stays in the panel.
   - After leaving PiP, hide and show the tab: the video shows in the page,
     not in the hidden panel.
7. Hidden tab for about 30 seconds, then back: does the video resume, or
   does the display layer report `requiresFlushToResumeDecoding`?
8. `chrome://histograms/Compositing.Renderer.CALayerResult` while playing:
   mostly success (0) on Netflix's and Apple TV+'s players.

## Verification done without a build

- Registry: syntax-checked against the pinned Chromium headers with
  `-Wall -Wextra -Werror -Wthread-safety`. A behaviour test built with small
  stand-ins for the base classes passes under ThreadSanitizer. It covers input
  checks, re-registration rules, a `Lookup` reference surviving a concurrent
  `Unregister`, release after `Unregister`, and 8 threads × 2,000 operations.
- `ca_renderer_layer_tree.mm`, `ca_layer_tree_unittest_mac.mm`,
  `ca_renderer_layer_params.h` and `overlay_candidate.h` are syntax-checked
  against the pinned headers with stand-ins only for perfetto's generated trace
  macros, one generated mojom enum and generated buildflag headers. The new
  viz code is compiled as an extract against the real viz headers. The full viz
  `.cc` files need generated mojom headers that don't exist without a build
  directory, so their hunks were re-read against the pinned source.
- Every hunk applies with `scripts/engine-source.py`'s exact-context patcher,
  and the whole overlay transforms in memory against the shared workspace's
  recorded originals, with no writes.

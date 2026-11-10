# FairPlay compositing (display half of M1)

A FairPlay renderer decodes into an `AVSampleBufferDisplayLayer` that Apple
never reads back, so Chromium can't draw the video. It can only put that layer
where the `<video>` element is, among the page's other CALayers. This document
covers the path that does that, what happens when it can't, and its verification boundaries. The CDM, renderer and media pipeline belong to
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
   `ui::ProtectedLayerRegistry::Register(token, layer)` with its display
   layer host before the token leaves the process: a plain `CALayer` whose
   `AVSampleBufferDisplayLayer` fills it, so the renderer can swap that layer
   for one in a new key session without a new token or compositor frame
   (`FairPlayRenderer::SetCdm`). The renderer gives its display layers what
   step 8 gives an `AVSampleBufferDisplayLayer` placed directly
   (`preventsCapture`, the Resize gravity and the flip); the compositor
   places the host like any registered layer. The
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
   counts as a video for CoreAnimation's layer limits. A hole inside a
   non-root render pass is placed too (see "When the video is inside a render
   pass").
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

## When the video is inside a render pass

Some players draw the video inside a render pass of its own. Apple TV+'s
player is a modal `<dialog>` that fades in with a CSS animation (opacity and
transform, `fill: forwards`). The finished animation holds its end state, so
Chromium keeps the dialog as an opacity effect with its own render surface. A
GPU trace showed the hole drawn in that 10-quad pass, never in the 14-quad
root pass. The overlay processor only looks at the root pass, so the hole was
drawn black there.

`CALayerOverlayProcessor::ProcessNestedProtectedLayers` (`ca_layer_overlay.cc`)
runs after the root pass, on both routes. It walks from the hole's pass up to
the root through the render pass draw quad that draws each pass, and works out
the hole's geometry in root space:
- each quad's transform, plus the offset between the pass's output rect and
  the quad's rect;
- every clip on the way: the hole's own, each pass's output rect, each
  quad's rect and clip, and any mask filter that is a plain rect;
- the opacities;
- at most one uniform rounded clip.

Then:

- **All CALayers:** the protected layer goes into the candidate list right
  before the CALayer of the pass that the root draws. The root's content below
  that pass stays below the video, and the pass stays above it. The hole is
  punched out of its own pass with `ReplaceExistingQuadWithHolePunch`
  (transparent, or DstOut when the video is translucent), so captions and
  controls that the pass draws over the video stay on top.
- **Underlays:** Apple TV+'s playing page went this way, with about 130 layers.
  The protected layer is an underlay below the primary plane. The hole is
  punched out of its own pass the same way. The root also gets a black DstOut
  copy of the video's footprint just below the pass's quad, at that quad's
  opacity, so what the root draws under the dialog gives way by the share the
  video covers.

Opacity is handled differently on each route:
- **Underlays:** the punches carry the opacity, so the layer is drawn at full
  strength. Upstream's hole punch relies on the same identity: DstOut over an
  opaque page, then the video at full strength below it.
- **All CALayers:** the pass's CALayer applies the outer pass's opacity to what
  the punch leaves. So the layer gets c / (1 − a + c), where c is the video's
  opacity times every pass's, and a is the outermost pass's.

Both are exact when at most one of the video and its passes is translucent,
assuming that what a translucent video covers in its own pass is opaque (a
dialog background). That covers a fading dialog and a fading video once the
fade ends, and a fading video at any point. Two translucent levels at once come
out slightly off. So does content drawn over the video inside a translucent
pass, such as captions or controls while a dialog fades: part of the video
shows through them. Separate layers can't reproduce a group's flattening,
which Safari's CALayer group opacity does. One case is exact anyway. Where the
pass draws something opaque over the video, the occlusion culler trims the
hole there, and the layer and the root's copy leave that part out.

Ordinary pages are unchanged. A frame with no hole quad in a non-root pass
costs one look at each non-root quad, and nothing in it changes. When a pass's
punch starts or stops, that pass is redrawn whole, along with the passes that
draw it and, on the underlay route, the root. That happens when a display
parks or a hole becomes placeable or stops being placeable. A cached pass
backing never keeps a stale punch or stale black. A parked display leaves
nested holes black, exactly as it does root ones.

The hole stays black, the way Safari leaves video it can't composite, when
something on the way changes how the video looks:
- a CSS filter or backdrop-filter;
- a mask image (clip-path or mask) or a gradient mask;
- mix-blend-mode;
- rotation, skew or perspective on a pass;
- a 3D sorting context;
- two different rounded clips;
- a pass drawn twice;
- a pass that no quad draws. One kept only for a copy request, which the
  aggregator's forced merge leaves, is like this; the hole's copy in the root
  is placed instead.

A pass on the way that has a copy request (a tab preview, `CopyFromSurface`,
tab capture) is still punched, so the screen keeps the video, as Safari's does
while capturing. The copy shows the punch, transparent where the video is, and
never the video. Leaving such a frame black would flash the video black on
screen for every snapshot, and for the whole of a tab capture.

A hole several passes deep, such as a dialog inside a page-level opacity
group, works the same way. Each pass in between draws the inner pass over what
it draws below it, which the video covers too. So each of those passes gets the
same black DstOut copy of the footprint, in its own space, just below the inner
pass's quad and at that quad's opacity. On the underlay route the root gets
one too.

## When the video stays black

The video area is **black** (never stale, never garbage) only when even the
underlay can't be used:

- **The hole is inside a render pass behind an effect a CALayer can't carry**
  (above). `SkiaRenderer::DrawQuadInternal` draws any quad that requires an
  overlay solid black in release builds, magenta with DCHECKs. Every
  `kVideoHole` requires one, and that check comes before the material switch,
  so `DrawUnsupportedQuad`'s release white never reaches a hole.
- **The quad itself can't be a CALayer:** a blend mode other than src-over on
  the video, non-uniform corner radii, or a clip change inside a 3D sorting
  context. The hole stays in the primary plane, drawn black, and other videos'
  underlays in the same frame are kept.
- **Software compositing** (GPU compositing disabled). The patch makes
  `SoftwareRenderer` draw the hole black instead of its unsupported-quad white.
- **No layer is registered under the token:** the renderer is gone, or the GPU
  process restarted and the page still shows the last hole frame. The host is
  black and empty.

How often:
- Netflix's watch page puts the video in an ordinary box under its controls,
  so it should stay on the all-CALayer path while playing.
- Apple TV+'s player puts the video in a dialog pass (above), and its playing
  page took the underlay route.
- Both should take the underlay route for single capture frames and on busy
  pages.
- They go black only during effects that a CALayer can't carry, applied to the
  video or its container: a filter, clip-path, or a free rotation.

Counts are unmeasured until there is a build. Each frame's result is recorded
in the `Compositing.Renderer.CALayerResult` histogram, and
`--show-mac-overlay-borders` outlines the protected host in orange.

The black cases are black by design. CoreAnimation can't apply most CSS filters
or masks to another process's AVSampleBufferDisplayLayer, and Safari leaves
video it can't composite the same way.

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
6. **Native HLS.** The native HLS player's `AVPlayerLayer` takes the same
   steps; what that route must keep for them, and the proof with the layer
   moving between CAContexts, are in [NATIVE_HLS.md](NATIVE_HLS.md).

## Verification targets

`accelerated_widget_mac_unittests` contains `CALayerTreeTest.ProtectedLayer*`
for placement, reuse, cross-tree ownership, black fallback and PiP. `viz_unittests`
contains `CALayerOverlayTest.Protected*` and `CALayerOverlayNestedTest.*` for
parked frames, nested passes, clipping, punches, opacity and redraws.

Use generated target flags and the pinned headers for compiler checks. Tests
that have only compiled must not be reported as executed. Existing component
receipts do not establish service playback, capture protection on every display,
physical receiver behavior or current integrated performance.

Browser/app launch, screenshots and live playback checks require explicit new
user authorization under [AGENTS.md](../../../AGENTS.md). This document does not
authorize them. Current source/release status belongs in
[product status](../../../docs/parity.md).

## Verification done without a build

Registry fixtures cover input validation, re-registration, retained lookup across
unregister and concurrent operations. Compositor fixtures cover geometry and
ownership. Their commands, target settings and result receipts must be bound to
the exact source being checked; old increment receipts do not verify a later
change. A compiler check is not engine test execution or browser acceptance.

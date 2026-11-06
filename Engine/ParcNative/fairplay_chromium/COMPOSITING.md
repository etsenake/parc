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
   registry is thread-safe and retains the layer until `Unregister`.
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
   - The host sits in the same back-to-front sibling order as the quad, so page
     content drawn over the video (controls, subtitles) stays above it.
   - Old-tree matching keys a protected content layer by its registered layer,
     as other layers are keyed by IOSurface, so the same host is reused frame
     after frame. Scroll and resize change only the transform and rect of
     layers that already exist.

The host exists so the tree's existing reuse and removal code (each destructor
calls `removeFromSuperlayer` on its own CALayer) can never detach the registered
layer from a newer tree. A CALayer has one superlayer, and the hosting rule
follows from that. A host takes the layer when the host is new, when it held
another token's layer, or when no live tree holds the layer (its current host
has no superlayer). Otherwise another, newer host took it, and this tree leaves
it alone instead of taking it back on every commit.

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

- **Video capture or a root copy request:** this tab shared with
  getDisplayMedia or tab capture, `CopyFromSurface` snapshots such as Parc's tab
  previews and page capture, DevTools screenshots. The captured image shows
  black where the video is, as Safari's does.
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
  context.
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
- **Window resize and fullscreen:** with `kCATransactionV2`, a resize makes
  `CALayerTreeCoordinator` drop its tree and CAContext before the next commit.
  That tree's hosts are destroyed, so the next tree builds a new host, which
  takes the layer. Parc's fullscreen keeps the page in its own window and
  compositor, so it follows this path. Low-power fullscreen detachment
  (`kFullscreenLowPowerBackdropMac`) is off upstream; if it were turned on, a
  protected layer would count as the video layer.
- **Moving between windows:** Parc's pane compositors belong to a window, so a
  page moved to another window, or shown by another pane compositor after a
  tab switch, is drawn by a different `CALayerTreeCoordinator`. All
  coordinators live on the GPU main thread of the same process. The new tree's
  new host takes the layer, and the old tree doesn't take it back, even if a
  stale frame there still names the token. If two live trees both show the
  token, as when one surface is embedded twice, the newest host wins. A layer
  can only be in one place.
- **Hidden page:** a page with no compositor has no tree holding the layer,
  so the layer is detached. Whether a detached AVSampleBufferDisplayLayer keeps
  decoding, or sets `requiresFlushToResumeDecoding`, is Apple's behaviour and
  is unverified (see the checks below). The renderer side handles it.
- **Teardown:** the renderer flushes with removal of the displayed image,
  then unregisters. The tree that holds the layer releases it at its next
  commit: that commit's lookup misses, the host goes black, and the layer is
  removed from it. Until then the flushed layer shows nothing. The tree's own
  reference is released when the tree goes away.

## Picture in Picture readiness (M3, design only)

Parc's PiP window (`Engine/ParcNative/video_overlay_window.mm`, presented by
`PCVideoPiPPresenter` in `Sources/ParcEngine/VideoPiPWindow.m`) has its own
`RecyclableCompositorMac`. Its root layer embeds the video's surface (the
`SetSurfaceId` it gets from Chromium's PiP controller) and shows it through
`AcceleratedWidgetMac` and `DisplayCALayerTree` in the panel's video view. For
a FairPlay video that surface holds the hole frame, so:

- The PiP compositor's aggregated frame contains the same `VideoHoleDrawQuad`
  at the PiP window's size. It goes through the same CA overlay path, into the
  PiP compositor's own `CARendererLayerTree` in the same GPU process.
- That tree's new host takes the registered layer under the hosting rule, so
  the playing video moves into the PiP panel with no extra engine API. Leaving
  PiP destroys that compositor's tree and detaches its host, and the page's
  next frame takes the layer back.
- `preventsCapture` and the panel's rounded corners still apply: the browser
  process masks the remote CALayerHost.

What M3 still needs from the engine:

1. Confirm Blink stops drawing the in-page video quad while in PiP. Otherwise
   both trees name the token, and the PiP host wins only because it is newer.
   A page frame that builds a new host (a page relayout during PiP) would pull
   the layer back. If that happens, the fix is a "suppressed" flag on the
   page's SurfaceLayer, not a registry change.
2. A first frame in the PiP compositor as soon as it opens. Check that the
   video surface's existing frame is aggregated there without a new hole
   frame.
3. The FairPlay renderer client must report natural size to the PiP
   controller (`WebMediaPlayer::NaturalSize`), so `setNaturalSize:` sizes the
   panel.
4. AVKit's system PiP (`AVPictureInPictureController` with a sample-buffer
   content source) isn't usable: it needs the display layer in the browser
   process, and this layer lives in the GPU process. Parc's own panel is the
   path.

## What Josh's first build should check

1. The overlay applies, and `accelerated_widget_mac`, `viz_service` and
   `gl` compile. Optionally build and run `accelerated_widget_mac_unittests`
   with `--gtest_filter=CALayerTreeTest.ProtectedLayer`. It checks placement,
   reuse across frames, the hand-off between trees and the black host.
2. Ordinary video is unchanged: YouTube and an MSE test page still show
   yellow (8-bit) or cyan (HDR) AV layers, or regular layers, with
   `--show-mac-overlay-borders`.
3. Once `fairplay-media` lands, an Axinom FairPlay vector in a Parc tab shows
   an orange-bordered host with the video inside, under the page's controls.
4. Scroll, resize the window, enter and leave fullscreen, switch tabs away
   and back, and drag the tab to another window. The video follows each time
   and never shows stale content.
5. Screenshots (⌘⇧4) and screen sharing show black where the video is.
6. Hidden tab for about 30 seconds, then back: does the video resume, or
   does the display layer report `requiresFlushToResumeDecoding`?
7. `chrome://histograms/Compositing.Renderer.CALayerResult` while playing:
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

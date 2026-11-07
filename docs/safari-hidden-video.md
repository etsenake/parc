# Safari hidden playing video (WMPI-4)

Reference: WebKit main `db2d79f4` (November 7, 2026), paths below relative to
`Source/WebCore`. This concerns audio+video that is allowed to keep playing;
media-session interruption/autoplay policy is a separate decision.

## WebKit source contract

- `html/HTMLMediaElement.cpp:7548-7560`: visibility changes notify the media
  session, then call `MediaPlayer::setPageIsVisible(!m_elementIsHidden)`.
  Viewport visibility is forwarded separately (10299, 10452, 10648).
- `platform/graphics/MediaPlayer.cpp:1195-1213`: page, canvas and viewport
  visibility are forwarded to the private player. `html/HTMLVideoElement.cpp:463`
  sets visible-for-canvas before painting. `MediaPlayerPrivate.h:132` defaults
  canvas visibility to `setPageIsVisible`; neither macOS AVFoundation player
  overrides that method. The current name for the viewport API is
  `setViewportVisibility`, not `setVisibleInViewport`.
- `platform/graphics/avfoundation/MediaPlayerPrivateAVFoundation.cpp:616-638`:
  showing the page calls `setUpVideoRendering`, then the platform hook;
  viewport visibility has its own platform hook. Neither selects a different
  video track nor seeks.
- `platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm:1452-1463,4330-4362`:
  hooks update layer attachment. Unless the client disables visibility teardown,
  hidden/offscreen video detaches AVPlayerLayer from AVPlayer; showing attaches
  it again. This changes presentation; it does not pause the AVPlayer or disable
  its video track. AVFoundation's internal decoding/power scheduling is private,
  so this source cannot prove every frame is decoded while detached, or a
  zero-latency first visible picture.
- `platform/graphics/avfoundation/objc/MediaPlayerPrivateMediaSourceAVFObjC.mm:445-476,986-997`:
  visibility sets renderer visibility and, by default, disables accelerated
  rendering while hidden/offscreen. Clients may opt out of that teardown.
- `platform/graphics/avfoundation/AudioVideoRendererAVFObjC.mm:1027-1037`:
  visibility itself only updates a flag/spatial metadata. At 1492-1510 and
  1798-1822, eligible decompression-session playback switches to a renderless
  video renderer; protected content that cannot use that session retains a
  layer/renderer. At 263-322 video samples still go to the selected renderer.
  `platform/graphics/cocoa/VideoMediaSampleRenderer.mm:427-467` creates a
  decompression session when no presentation renderer exists; decoding continues
  with bounded sample queues (`decodeNextSampleIfNeeded`, 516 onward).

There is no WebKit visibility timer that deselects this video track and later
flushes/reseeks it to rejoin audio. There **is** presentation teardown/reattachment,
renderer staging and normal decoder backpressure. Do not equate this source
contract with guaranteed hidden-frame counters or measured return latency.

## Parc routes and change

`WebMediaPlayerImpl::UpdateBackgroundVideoOptimizationState` schedules the
10-second task. `DisableVideoTrackIfNeeded` calls
`ShouldDisableVideoWhenHidden`, then deselects video; foregrounding calls
`EnableVideoTrackIfNeeded`, which reselects it. This shared player covers clear
URL and Media Source playback before delegating to the selected renderer.

- Clear URL and clear Media Source using Chromium's renderer were eligible.
  Safari identity now returns false from `ShouldDisableVideoWhenHidden`.
  Their selected video stream continues decoding instead of entering this
  artificial end/reselect/flush/seek cycle. Chrome identity retains its existing
  audio/video, streaming, PiP, capture, flinging and keyframe eligibility rules.
- FairPlay MSE uses `FairPlayRendererAdapter` → `fairplay_renderer.mm`;
  the adapter reads demuxer buffers (adapter lines 484-530), treating EOS as
  stream end. Existing `kFairPlay`, attaching/pending FairPlay CDM and unbound
  encrypted-stream exemptions already prevent this optimization reaching it.
- Native HLS uses `NativeHlsRenderer` → native AVPlayer in
  `fairplay_hls_player.mm`. Its `kFairPlayHls` exemption already prevents track
  disabling; AVPlayer owns the actual media streams. Neither native renderer
  needs changes for WMPI-4, so no native renderer test changes are required.

This closes the track-selection mismatch. Parc does not reproduce WebKit's
AVFoundation-specific presentation teardown in Chromium's clear renderer.
Other compositor scheduling, private AVFoundation behavior, protected-canvas
restrictions and media interruption rules remain independent of this edge.

## Cost and validation boundary

Keeping Chromium's clear video decoder working after ten hidden seconds costs
more decoder/GPU activity and frame-buffer bandwidth than audio-only playback.
Hardware acceleration, resolution, codec and frame rate determine the cost;
no CPU percentage or battery measurement was performed. FairPlay/HLS costs do
not change. Chrome identity does not change. Renderless WebKit playback can
also decode while hidden, but this does not establish equal power consumption.

The existing Blink unit target adds parameterized Safari and Chrome cases for
both URL and Media Source, varying keyframe distances, PiP, capture and flags.
Safari eligible cases would return true without the new identity exemption;
Chrome cases assert the original eligibility expression. Files are compiled
read-only using `compile_copy.sh`; Chromium test executables are unavailable,
so these tests are compiled, not linked or run. No browser/app build or runtime
acceptance is claimed.

## Check commands

Copy root and receipt directory:
`/Users/josh.etsenake/parc/work/safari-media-audit-src/scratch/WMPI-4`.

```
PYTHONPATH=tests/EngineSource python3 -m unittest tests.EngineSource.test_overlays
bash /Users/josh.etsenake/parc/work/safari-media-audit-src/compile_copy.sh ParcDistribution_GN_arm64 obj/third_party/blink/renderer/platform/media/media/web_media_player_impl.o /Users/josh.etsenake/parc/work/safari-media-audit-src/scratch/WMPI-4 third_party/blink/renderer/platform/media/web_media_player_impl.cc /Users/josh.etsenake/parc/work/safari-media-audit-src/scratch/WMPI-4/player-final.o
bash /Users/josh.etsenake/parc/work/safari-media-audit-src/compile_copy.sh ParcDistribution_GN_arm64 obj/third_party/blink/renderer/core/unit_tests/web_media_player_impl_unittest.o /Users/josh.etsenake/parc/work/safari-media-audit-src/scratch/WMPI-4 third_party/blink/renderer/core/exported/web_media_player_impl_unittest.cc /Users/josh.etsenake/parc/work/safari-media-audit-src/scratch/WMPI-4/tests-rebased.o
```

Independent review: bounded read-only review of the Safari identity gate and
Chrome/Safari URL/MSE regression cases; no findings. Source-identical WMPI-4
hunks were retained across the rebase. Other contributors' key-request source
and tests were preserved and the combined files recompiled.

Results: all 27 overlay tests passed; both final rebased translation units
compiled successfully. `git diff --check` passed. Chromium tests were not run.

# Safari hidden playing video (WMPI-4)

The WebKit source paths below are relative to `Source/WebCore`. This concerns
audio and video that are allowed to keep playing;
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

## Checks

`tests/EngineSource/test_overlays.py` checks overlay structure. The pinned Blink
unit source covers Safari/Chrome URL and MSE cases; recorded native compilation
uses shipping flags. A compiled test object is not an executed Chromium test.
Current source/publication status is in [product status](parity.md), separate
from live playback, return latency or power measurements.

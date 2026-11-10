# Native HLS presentation proofs

Proves the presentation side of Parc's native HLS route
([NATIVE_HLS.md](../../../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md))
against AVFoundation independently of the Chromium engine.

```bash
scripts/test-fairplay-hls-presentation.sh            # every section
scripts/test-fairplay-hls-presentation.sh --only Display
```

The harness is compiled with clang only (C++20, `-Wall -Wextra -Werror`,
macOS 13.0 target, ARC). It opens two small windows and plays Apple's public
BipBop example (`bipbop_16x9_variant.m3u8`: five video variants, two audio
renditions, WebVTT subtitles in four languages with forced variants). It needs
network access. The player is made and driven on a serial queue with no run
loop, as the GPU process's media service thread is; layers are placed on the
main thread, as `CARendererLayerTree` places them.

## Sections

- **Display.** An `AVPlayerLayer` made on that queue inside an explicit
  `CATransaction`, placed in a page window's host the way
  `FillProtectedLayer` fills it (`fairplay-compositing.patch`: anchor and
  position zero, the host's bounds, Resize gravity). It becomes ready for
  display, its `videoRect` equals its bounds, and it keeps playing when moved
  to a second window's host (Picture in Picture), back again, and after a few
  seconds in no tree at all (a hidden tab). Frame counts are read from
  `-[AVPlayerLayer videoPerformanceMetrics]` (WebKit's source) off the main
  thread. Teardown lets go of the player on the queue.

- **Accumulator.** `FrameCountAccumulator` on synthetic readings: the first
  reading counts in full, later ones add what moved, either count going back
  (a restarted decoder) counts both readings in full, negative readings add
  nothing.
- **FrameStats.** `HlsFrameStats` on a playing `AVPlayerLayer`, reporting on
  the media queue: reports arrive about four times a second while playing and
  add up to the frames played; stopping counts once more, so the sum reaches
  the layer's total; nothing is reported while paused; counts resume with
  playback and stop for good when it is destroyed. A layer whose player is
  gone, or that never played, gives no reading.

- **RemotePiP.** The layer inside CAContexts shown through `CALayerHost`s, as
  the GPU process's page and PiP-window trees are
  (`CALayerTreeCoordinator`'s context and flipped root layer), in windows
  kept on screen and clear of each other. The layer is the core's
  `PCHlsPlayerLayer`, staged at the element's 640×360 pt size in a CAContext
  of its own before the item goes on the player, as `FairPlayHlsPlayer::Start`
  does with the render process's size. On a 2× display it plays in the
  page's context at 720p (not 1080p), even after the earlier sections left
  AVFoundation a bandwidth estimate for 1080p, moves to
  1280×720 pt (fullscreen, a resize) and switches up to 1080p, then goes to
  the PiP window's context and back, playing throughout.

## Results

Recorded 2026-11-06 on this MacBook Air (macOS 27.2): Display 15 checks,
Accumulator 8, FrameStats 10, RemotePiP 13, 0 failed, all sections in one
run (RemotePiP's item started at 1030k, 720p, after the earlier sections).

- Ready for display in the 640×360 host; `videoRect` 640×360, then 320×180 in
  the PiP host.
- Frames 10 → 81 over 2.94 s of media, none dropped or corrupted; they keep
  coming in the PiP host (93 → 173, clock +2.51 s), back in the page
  (190 → 246) and after the hidden spell (352 → 414).
- A layer in no tree keeps decoding and the clock keeps running (+3.01 s;
  frames 246 → 336 while detached).
- The variant climbed 264k → 578k → 916k → 1030k as the layer grew. In one
  earlier run the frame counter restarted (178 → 75) on the move back to the
  larger page host, when AVFoundation switched variants: a count below the
  last one starts a new run, which the frame statistics must add, not ignore.
- FrameStats: +79 decoded over 3.01 s of media in 12 reports; on pausing the
  last count brought the sum to the layer's total (89 = 89); paused 2 s,
  89 → 89 with no reports; +72 after resuming; no report in the 1.5 s after
  destruction.
- RemotePiP: 720p for the 640×360 pt layer on the 2× display, 1080p within
  15 s of growing to 1280×720 pt; frames keep coming in the PiP context
  (144 → 220, clock +2.51 s) and back in the page (the counter restarted,
  229 → 107, on a variant switch). In separate runs, a visit at PiP size
  before growing kept AVFoundation at its earlier best variant (720p) for
  30 s, with plain windows as with CAContexts; without the visit, 1080p
  within a second.

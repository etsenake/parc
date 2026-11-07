# Decode timestamps and the FairPlay renderer

Asks whether `AVSampleBufferDisplayLayer` plays a reordered stream worse when
its samples carry no decode timestamp. Chromium's `DecoderBuffer` has none, so
the FairPlay renderer gives AVFoundation `kCMTimeInvalid`, while WebKit's MSE
route hands it the file's decode times. The question came from Netflix on
Parc 1.3.0, which in stretches froze for 130–165 ms every 8 frames. Its
fragments reorder frames in groups of four (P, then three hierarchical
B-frames; `trun` composition offsets 7, 4, 2, 3 frames).

```bash
tests/FairPlay/decode_times/run.sh                  # clear, eager feed
tests/FairPlay/decode_times/run.sh --feed 2         # one sample per 2 ms round trip
tests/FairPlay/decode_times/run.sh --protected 1    # FairPlay, Axinom license (network)
PARC_DECODE_TIMES_SIZE=3840x2160 PARC_DECODE_TIMES_KBPS=40000 tests/FairPlay/decode_times/run.sh
```

Needs `x265` (Homebrew). Silent: video only, no audio renderer. It opens a
960×540 window per run (20 s each, two runs per call: invalid then real decode
times). Clips are cached in `$PARC_DECODE_TIMES_DIR` (default
`$TMPDIR/parc-decode-times`).

## What it does

- `--write-yuv` makes the source: a moving blurred-noise texture with fresh
  noise in every frame (so x265 spends its bit rate), and the frame number as
  two rows of 16 bit blocks (bits and their complement) across the top.
- x265 encodes it with a fixed structure: `--bframes 3 --b-pyramid
  --b-adapt 0` gives Netflix's P, B, b, b groups (`PARC_DECODE_TIMES_BFRAMES=7`
  gives groups of eight), closed GOPs of 48 frames, parameter sets on every
  keyframe, access unit delimiters, and a frame CSV with each picture's POC.
- `--play` splits the stream at the delimiters, takes presentation order from
  the POC (restarting at each IDR) and plays it through `FairPlayRenderer` as
  Chromium hands buffers over: Annex B, an empty decoder record, microsecond
  times. `--dts real` adds decode times four frames before presentation, as in
  Netflix's fragment; `--dts invalid` leaves them out, as Parc does.
  `--protected 1` encrypts each sample in memory (cbcs 1:9, slice headers
  clear) with the Axinom key the [codec proof](../codecs/README.md#key) uses
  and plays it under a real FairPlay license.
- Feeding: `eager` enqueues while the renderer is ready; `--feed <ms>`
  enqueues one sample per readiness check after that delay, as the Chromium
  adapter does with one `DemuxerStream::Read(1)` round trip per sample.
- Every 4 ms it reads the displayed picture's frame number
  (`copyDisplayedPixelBuffer`, scaled down), and every 50 ms AVFoundation's
  `AVVideoPerformanceMetrics`. It reports dropped frames, the frames decoded
  ahead of the clock (decoded count minus frames due), how far ahead of the
  clock samples were enqueued, and every picture that stayed up for 2.5 frames
  or more while the clock ran. Protected pictures can't be read back, so
  protected runs report metrics only.

## Results

Recorded 2026-11-07 on this MacBook Air (macOS 27.2): 24 fps, 480 frames,
each row run with decode times left out (as Parc plays) and then with them.
"Decoded ahead" leaves out the first 0.5 s and the last 2 s.

| Clip | Feed | Decode times | Frames (dropped) | Decoded ahead, min / median | Enqueued ahead, min | Pictures held ≥ 104 ms |
| --- | --- | --- | --- | --- | --- | --- |
| 1080p HEVC 12 Mb/s, groups of 4 | eager | none / real | 480 (0) / 480 (0) | 25 / 41, 25 / 42 frames | 1125 / 1121 ms | 0 / 0 |
| same | 2 ms per sample | none / real | 480 (0) / 480 (0) | 25 / 40, 25 / 40 | 1129 / 1137 ms | 0 / 0 |
| same, FairPlay cbcs | 2 ms | none / real | 480 (0) / 480 (0) | 25 / 41, 25 / 40 | 1154 / 1135 ms | not readable |
| 1080p 13 Mb/s FairPlay, groups of 8 | 2 ms | none / real | 480 (0) / 480 (0) | 25 / 40, 25 / 40 | 1103 / 1126 ms | not readable |
| 4K HEVC 39 Mb/s, groups of 4 | 2 ms | none / real | 480 (1) / 480 (1) | 25 / 39, 25 / 40 | 1100 / 1097 ms | 0 / 0 |
| same | 30 ms | none / real | 480 (1) / 480 (0) | 25 / 37, 25 / 37 | 1060 / 1063 ms | 0 / 0 |

AVFoundation decodes at least a second (25 frames) ahead of the clock with
or without decode times, so a reference frame is decoded long before the
B-frames that need it come due. Decode times change nothing a viewer can see,
in the clear and under FairPlay, at 1080p and 4K. No run froze periodically;
the odd dropped frame is a single picture, with decode times or without (an
earlier pass of the same runs dropped up to 5 each way).

The feed holds up too. With one sample per readiness check, AVFoundation
keeps more than a second enqueued ahead of the clock even when every sample
costs a 30 ms round trip at 4K and 39 Mb/s. At 24 fps the lead falls only if
round trips average over 41 ms (a frame's time) or the render process stops
answering for over a second.

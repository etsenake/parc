# FairPlay GPU-sandbox probe

Checks the GPU-process sandbox rules Parc adds for FairPlay
(`sandbox/policy/mac/gpu.sb` in `Engine/ParcHost/integration/fairplay-media.patch`)
on a real Mac, without an engine build. It plays FairPlay media through the
FairPlay core (`FairPlayCdm` + `FairPlayRenderer`, the same code the GPU
process runs) inside Chromium's own GPU seatbelt profile.

```sh
python3 tests/FairPlay/sandbox/run.py                  # every scenario, with and without the rules
python3 tests/FairPlay/sandbox/run.py --scenarios h264 --ablate --ablate-groups
python3 tests/FairPlay/sandbox/run.py --rules candidate.sb   # try other rules
```

Needs Python 3.11+, Xcode's clang, network access (for the helper only) and
the pinned Chromium checkout (`--source`, default the shared engine source, or
`PARC_PINNED_CHROMIUM`). Media is cached in `$TMPDIR/parc-fairplay-cache` (or
`PARC_FAIRPLAY_CACHE`). It writes only to a temporary directory and that cache.

## What it does

- `run.py` compiles the core, `tests/FairPlay/fmp4_parser.cc` and the probe
  with clang, as `scripts/test-fairplay-core.sh` does, into three pieces.
  - `fpsbprobe` (`probe_main.cc`) is plain C++ and links no framework
    (`run.py` checks with `otool -L`), like the helper executable Parc's GPU
    process starts as.
  - `fpsbhelper` (`probe_helper.mm`) does HTTP.
  - `libfpsbplayer.dylib` (`probe_player.mm`) links AVFoundation and the
    core.
- `run.py` takes `common.sb` and `gpu.sb` from the pinned source with
  `git show`, and `gpu.sb` with the FairPlay hunk applied by the overlay tool's
  exact applier. It concatenates them the way
  `sandbox::policy::GetSandboxProfile` does (`common + gpu`).
- `fpsbprobe` spawns `fpsbhelper` unsandboxed on a socketpair. The GPU process
  has no network, so the helper does every HTTP request: playlists, segments,
  the FairPlay certificate and the license POSTs. Before the sandbox the probe
  downloads and parses the media. The clear clips come from the pinned
  checkout's `media/test/data`, which `run.py` extracts.
- The probe then calls `sandbox_init_with_parameters` with the profile and the
  parameters `content/browser/sandbox_parameters_mac.mm` gives a GPU process:
  - `EXECUTABLE_PATH`, `BUNDLE_PATH`, `BUNDLE_ID`, `BROWSER_PID`,
    `LOG_FILE_PATH`, `OS_VERSION` and `USER_HOMEDIR_AS_LITERAL`;
  - the canonical `DARWIN_USER_DIR`, `_CACHE_DIR` and `_TEMP_DIR`;
  - `DISABLE_METAL_SHADER_CACHE=FALSE` and `RESTRICT_GPU_DARWIN_USER_DIRS=TRUE`
    (the feature's default).

  Logging is on, as with `--enable-sandbox-logging`, so denials reach the log.
  If outbound network still works, the run is a setup failure: the profile
  wasn't applied as meant.
- Only then does it open `libfpsbplayer.dylib`. Every framework (AVFoundation,
  CoreMedia, CoreAudio and their initializers) loads inside the sandbox, as it
  does in Parc, whose GPU helper applies its sandbox before it loads the
  engine framework.
- The player does what the GPU process does. For protected scenarios it sets
  the server certificate and generates a request (`cenc` from the vector's
  pssh boxes, or an `skd` URI). The helper POSTs the SPCs, and the player
  updates the session. It feeds Chromium-shaped buffers (Annex B, ADTS,
  scheme-only encryption, 16-byte IVs) to a `FairPlayRenderer` joined to the
  CDM until ~5 s of media time have played, or a clear clip's end.
- Every run has one deadline on its own thread: a setup budget until the
  sandbox is applied, then a playback budget, because a denied service can
  block AVFoundation on the main thread. `run.py` then reads the kernel's
  sandbox denials for that pid from the unified log.

### Scenarios

| Name | Media |
| --- | --- |
| `h264` | Axinom "CMAF H264 SingleKey (cbcs)": 720p H.264 + AAC, both protected, `cenc` |
| `hevc` | Axinom "CMAF H265 SingleKey": 720p HEVC + AAC, both protected, `skd` |
| `dolby-vision` | Chromium's clear Dolby Vision profile 5 clip |
| `eac3`, `ac3` | Chromium's clear E-AC-3 and AC-3 clips |

No public FairPlay vector has Dolby Vision, E-AC-3 or AC-3. Their clear clips
use the same decoders and output a protected sample does once it is
decrypted, so they exercise everything except the key path.

### Outcomes

| Result | Meaning |
| --- | --- |
| `PASS` | Played to the target with every present stream rendering, protected formats on every stream of a protected scenario, no decode failure, and for video AVFoundation's metrics, counted halfway and at the end: at least 80% of the frames due, and between the two counts at least 80% of the frames that came due and were still to decode (one count alone includes the frames decoded ahead, and a short clip decodes whole up front), a frame ready for display, none corrupted, at most 10% dropped |
| `FAIL` | Playback failed in the sandbox, including an AVFoundation exception, or the player didn't load there |
| `TIMEOUT` | No result in time. A denied service can do this (without the display-pipe grant the key never becomes usable) |
| `SETUP-FAIL` | Before the sandbox: download, parse, `sandbox_init` |
| `INCONCLUSIVE` | In the sandbox but not the profile's doing: the license server, or output obscured by screen capture |

Only `FAIL` and `TIMEOUT` say anything about the profile. A failed or partial
download is never cached or used. The without-rules run must be denied a grant
playback needs (the `NEEDED` set in `run.py`). Ablation replaces a
grant with a filter of the same kind that matches nothing, so its rule never
loses its last filter. A grant counts as `NEEDED` only when playback then fails
or times out and the kernel logged a denial naming it. Anything else is
reported as unclear.

## Results (November 6, 2026, Apple Silicon, macOS 27.2)

With the rules in the patch, every scenario passes:

| Scenario | Result |
| --- | --- |
| `h264` | 5.2 s, key usable, 160 frames (125 due), 53 of 62 between the counts, 0 dropped, 0 corrupted, `qavc`/`qaac` |
| `hevc` | 5.2 s, key usable, 164 frames (125 due), 53 of 62 between the counts, 0 dropped, 0 corrupted, `qhvc`/`qaac` |
| `dolby-vision` | to the clip's end, 120 frames (116 due, all decoded by the first count), 0 dropped, 0 corrupted, `dvh1` |
| `eac3`, `ac3` | to the clip's end, audio rendering |

Without the FairPlay rules, `h264` fails at renderer Initialize:
`AVSampleBufferRenderSynchronizer addRenderer:` refuses the audio renderer
("invalid renderer"; the core catches the exception),
because CoreAudio is unreachable. The kernel denied `com.apple.audio.audiohald`,
`com.apple.audio.AudioSession`, `com.apple.coremedia.routingcontext.xpc` and
`com.apple.audio.SandboxHelper`.

Denials that remain while every scenario passes, left denied:
`network-outbound` (the probe's own check), `system-info vfs.disk-space`,
`sysctl-read` (`sysctl.proc_translated`, `kern.bootargs`, `hw.product`),
`mach-lookup com.apple.tccd.system`, `com.apple.audioanalyticsd` (WebKit
denies it too), `com.apple.UsageTrackingAgent`, distributed notifications,
iokit `IOSurfaceAcceleratorClient` (H.264 and HEVC; Dolby Vision doesn't
open it), and reads of `/System/Library/Audio/Tunings` (spatial-audio and
loudness presets). `com.apple.audio.AudioConverterService` is never looked
up, not even for E-AC-3 or AC-3.

### Which rules playback needs

`--ablate` replaces each grant on its own, and `--ablate-groups` each
commented group (for grants that stand in for each other), with a filter that
matches nothing. Scenario `h264`:

| Grant | Without it |
| --- | --- |
| `com.apple.lskdd` + `com.apple.lskdd.xpc` | NEEDED as a pair: `generateRequest` rejected, -11800 over -42664, both denied. Either alone plays: the client falls back to the other name |
| `com.apple.audio.audiohald` | NEEDED: audio renderer fails, -11800 over -101 |
| `com.apple.coremedia.routingcontext.xpc` | NEEDED: `addRenderer:` refuses the audio renderer ("invalid renderer") |
| iokit `AppleAVDUserClient` | NEEDED: video decode fails, -11839 over -12913 |
| iokit `IOMobileFramebufferUserClient` | NEEDED: times out at `update`; the key never becomes usable |
| `/System/Library/Components/CoreAudio.component` | NEEDED: times out in playback; audio never starts |
| `/System/Library/Components/AudioDSP.component` | plays; read (and denied) while audio plays |
| `com.apple.audio.AudioSession`, `com.apple.audio.SandboxHelper` | plays; both looked up (and denied) while audio plays |

The last two rows stay in the rules for routes the probe can't exercise, as
`audio.sb` allows them. Intel-only audio drivers, HAL plug-ins (coreaudiod
loads them, not clients) and services playback never looks up were dropped.

WebKit restricts `AppleAVDUserClient` and `IOMobileFramebufferUserClient` to a
few methods with `apply-message-filter`. The same filters here make
`sandbox_init_with_parameters` fail with "Operation not permitted"; without
the filters the same profile applies and plays. A non-Apple process can't use
message filters, so the grants cover the whole user clients.

## What it doesn't cover

- The real GPU process has more state (Metal, the command buffer, a
  CAContext the browser hosts), and its executable sits in a helper app bundle
  (`HELPER_BUNDLE_ID` is set there). The probe's display layer sits in no
  layer tree, so the frames above are decoded and counted, not shown on
  screen, and on-screen scaling (where `IOSurfaceAcceleratorClient` could
  matter) isn't exercised.
- One Mac and OS version, with built-in audio output. Intel Macs' kernel audio
  drivers, third-party HAL plug-ins, AirPlay, Bluetooth and external displays
  aren't exercised.
- Protected Dolby Vision, AV1, E-AC-3 and AC-3: no public FairPlay vectors
  exist, so their clear clips stand in for the decoders and output.

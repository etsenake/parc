# FairPlay protected-codec proof

This program makes FairPlay samples for Dolby Vision, AV1, HE-AAC, xHE-AAC,
AC-3 and E-AC-3. It encrypts clear samples in memory with a public test key
that Axinom's FairPlay license service licenses.
Then it plays them through `FairPlayCdm` and `FairPlayRenderer`
([core](../../../Engine/ParcNative/fairplay/README.md)) the way Chromium hands
them over. Running this visible harness requires explicit authorization under
[AGENTS.md](../../../AGENTS.md).

```bash
scripts/test-fairplay-codecs.sh
```

The script compiles the core, `../fmp4_parser.cc` and this directory with
clang only (C++20, `-Wall -Wextra -Werror`, ARC), then runs the program. It
needs network access and opens a visible window for about five and a half minutes.
Downloads are cached in `$PARC_FAIRPLAY_CACHE` (default
`$TMPDIR/parc-fairplay-cache`, shared with the core harness). The program
samples its stack and exits with status 3 if the main thread stalls for 15 s,
or with status 4 after `--time-limit` seconds (default 600). The script kills
it at 660 s. `--only <text>` plays only the clips whose names contain the
text, and `--muted` mutes every audio renderer at volume 0 (decoding and the
decoder-log checks are unchanged; nothing plays through the speakers). Exit
status is the number of failed checks clamped to 1.

## Key

Axinom publishes the content keys of its v10 vectors next to their key IDs
and entitlement tokens, in
[ContentKeys/](https://github.com/Axinom/public-test-vectors/tree/master/ContentKeys).
The "CMAF H264 SingleKey" fixture uses `kKeyIdHex`, `kKeyBase64` and
`kLicenseIv` in [codecs.mm](codecs.mm), with the same entitlement token as the
core harness. Axinom's FairPlay service licenses that public test key for the
locally encrypted content. The token carries the constant IV used by Axinom's
own content; keep the encryption and license IV aligned.

The older v9 token lacks an IV and was refused by the FairPlay service. Its
signature prevents adding one locally, so use the v10 fixture rather than
substituting the older token.

## What the program does

1. Offline checks of the encryption against packagers' own output:
   - cbcs with the 1:9 pattern and the H.264 subsample layout reproduce
     Shaka Packager's `bear-640x360-v_frag-cbcs.mp4` byte for byte. That
     file's samples are each either the clear sample (clear lead) or exactly
     this program's encryption of it.
   - The slice header ends found by `sample_encryptor.cc` equal the clear
     bytes of Axinom's own cbcs vectors, H.264 and HEVC, for every NAL unit.
   - The 16-byte-aligned HEVC cenc layout equals the one Chromium's Dolby
     Vision `dvhe` test file was packaged with.
   - AES-CTR decrypts Shaka's AV1 cenc files to Chromium's clear AV1 files.
2. Apple's E-AC-3 decoder on a clear 7.1 stream, and the layouts Apple derives
   from that file's `dec3` and from the two `dec3` boxes the core can build.
3. One FairPlay license for the key, through `FairPlayCdm` with `cenc` init
   data: a common-system `pssh` naming the key ID.
4. Each clip encrypted in memory and played through `FairPlayRenderer` to
   `OnEnded`. The input matches what Chromium's MP4 parser gives a renderer:
   - samples converted by `ChromiumBuffer`: Annex B with parameter sets on
     keyframes, ADTS on AAC, microsecond timestamps and 16-byte IVs;
   - no decode timestamp;
   - Chromium's configs: empty video `extra_data`, Dolby Vision as profile
     and level, AAC with its AudioSpecificConfig, no `dac3`/`dec3`, and
     encryption as the scheme alone;
   - AC-3/E-AC-3 channel counts from `dac3`/`dec3`, as Chromium reports them.

   Video uses cbcs with the 1:9 pattern. Audio is protected whole-sample, as
   in CMAF. The license's IV is the constant IV.

A clip passes when every check holds:

- it reaches HAVE_ENOUGH and `OnEnded` at the clip's end;
- the renderer status is rendering, with no decode or renderer errors;
- every sample went to AVFoundation as a protected sample buffer;
- the protected format type is Apple's;
- for video, AVFoundation's metrics count at least 90% of the frames, none
  corrupted;
- Apple's decoders logged no errors in this process's unified log while the
  clip played (read through `OSLogStore`, current-process scope).

The log check matters. A wrong key makes Apple's AAC, xHE-AAC, AC-3 and
E-AC-3 decoders fail every packet, but the audio renderer still reports
rendering and the clock still reaches the end. Only the log
(`ACCPEDecoderWrapper`, `ParseAC3Header failed`, `Error deserializing packet`)
shows the failure. Controls under a wrong key, with the right key ID, check
that each signal notices garbage. The log query filters on the clip's start
date in its predicate: `positionWithDate:` alone still walks every earlier
entry, and failing clips log tens of thousands.

A clip that isn't required to play stops waiting one second after its first
renderer error or rejected enqueue. Such an error rules out a healthy result,
and the failed clock never reaches the end, so the HAVE_ENOUGH and `OnEnded`
deadlines would only add dead time.

## Results

The table separates clear and protected playback. Wrong-key controls are
required for protected codecs; AV1 has the diagnostic limitation below. A clip
expected to fail counts as a check when it fails in the expected way.

| Codec / fixture | Protected type | Expected outcome |
|---|---|---|
| Dolby Vision profile 5 `dvh1` and `dvhe` | `qdh1` | Protected playback reaches the end without corruption; the `dvh1` wrong-key control fails. |
| AV1 8-bit and 10-bit `av01` | `qav1` | Protected playback completes without decoder errors; the wrong-key control is unreliable (see below). |
| HE-AAC and HE-AACv2 | `qaac` | Protected playback completes without decoder errors; an AAC wrong-key control fails. |
| xHE-AAC | `qusa` | Clear and protected playback passes; the wrong-key control fails. |
| AC-3 and E-AC-3 | `qac3`, `qec3` | Protected playback passes; wrong-key controls fail. |
| E-AC-3 7.1, DASH-IF FA01 | `qec3` | Plays both with the file's `dec3` and with the box built from Chromium's rate/channel configuration. |
| FLAC, `bear-flac_frag.mp4` with STREAMINFO only | `qflc` | Clear and protected playback reach the end; the wrong-key control fails. |
| Opus, `bear-opus.mp4` with OpusHead | none | Clear playback passes; no protected type exists. |
| ALAC, stereo ALACSpecificConfig from Apple's encoder | `qlac` | Clear and protected playback passes; the wrong-key control fails. |
| PCM `ipcm` 16/24-bit and `fpcm` 32-bit float with `pcmC` | none | Clear playback passes; protected enqueue is refused, as in Safari. |
| VP9, `bear-vp9.webm` frames with no `vpcC` | none | Clear playback displays a frame and reaches the end without corruption. |
| Vorbis, `bear-320x240-audio-only.webm` with CodecPrivate cookie | none | Clear playback reaches the end; the damaged-header control does not. |

Muted audio still decodes. The core's `CheckRequestLater` recovers when
AVFoundation omits a ready-for-more-data callback, including muted FLAC: it checks
readiness after 100 ms and delivers the pending request once under the request
gate. A flush or a newer request invalidates the old callback.

Controls through the same path: Axinom's own H.264 segment as served (144/144
frames), this program's encryption of H.264 (82/82) and HEVC (82/82), and
AAC-LC (132/132 packets, no decoder errors). H.264 under a wrong key fails all
82 frames with -12909.

AV1 caveat: Apple's AV1 decoder decodes garbage tile data without complaint.
Under six wrong keys, two gave decode errors (24 and 68 corrupted frames) and
four looked exactly like the right key. Protected AV1 frames can't be read
back (`copyDisplayedPixelBuffer` returns nothing, while the clear stream gives
`&8v0` frames). The fixture therefore treats AV1 metrics as decoder health
only; they cannot reliably distinguish every wrong-key output.

7.1 channel layout: CoreMedia's top layer for the file's `dec3` (Lrs/Rrs
in `chan_loc`) is 8 channels, `EAC3_7_1_A` (L C R Ls Rs LFE Rls Rrs).
Apple's E-AC-3 decoder decodes all 30 s of the clear stream to 8 channels with
that layout, each carrying signal (RMS 0.015–0.024). The core builds the same
layout both from the clear syncframes and from rate and 8 channels: a 5.1 core
plus a dependent Lrs/Rrs substream, with an unknown bit rate in the latter case.
`ChannelLayoutChecks` in [codecs.mm](codecs.mm) compares both generated boxes
with the file's own box. CoreMedia lists
both as 8 channels, `EAC3_7_1_A`, over a 6-channel layer. Chromium also counts
8 channels for 7.1 wide (Lc/Rc); such a stream gets the Lrs/Rrs box, so Apple
places its extra pair as rear surrounds.

Platform behaviour (checked to fail, so a change would show up):

- cenc (AES-CTR) is out of scope: WebKit's FairPlay takes cbcs only, and
  Parc refuses cenc on Safari pages. The clips with 8-byte per-sample IVs
  fail: H.264 all 82 frames (-12909), Dolby Vision `dvhe` all 75 frames, and AAC-LC
  logs decoder errors (`Error deserializing packet`) though the renderer
  reports nothing. Every IV the license's fails the same way.

- `qavc`, `qhvc` and `qdh1` are decrypted with the IV the CKC carries. A
  constant IV the license doesn't carry fails every frame, whether it is in
  the `tenc` or in the per-sample `CryptorIV` attachment. The core harness's
  constant-IV result used content whose IV equals the license's.
- AC-3 and E-AC-3 with their syncframe headers clear (a subsample layout)
  fail every packet exactly like a wrong key, including 7.1 (188/188
  packets). Whole-sample protection, the CMAF form, works.
- Opus has no protected type: CoreAudio's decoders include `qflc` (FLAC) and
  `qlac` (ALAC) but no protected Opus one, so protected Opus is refused at
  the first enqueue.
- PCM has no protected type either: protected `ipcm` and `fpcm` stay `enca`
  and AVSampleBufferAudioRenderer fails at the first enqueue after the key is
  usable (-11800, `fmt?`), as Safari's AVStreamDataParser output does on this
  Mac. Clear `ipcm` (16, 24 bits) and `fpcm` (32-bit float) play as `lpcm`.
- AV1 has no cenc protected type (the description stays `encv`, -12167).
  Encrypted AV1 frame headers fail ("fail to parse av1 header"). Video
  protected with every block encrypted (pattern 0:0) fails about half its
  frames even with the right key.

License renewal has a separate `RenewalScenario` in the
[core harness](../README.md).

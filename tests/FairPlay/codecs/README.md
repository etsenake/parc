# FairPlay protected-codec proof

No public FairPlay content exists for Dolby Vision, AV1, HE-AAC, xHE-AAC,
AC-3 or E-AC-3, so this program makes its own. It encrypts clear samples in
memory with a content key that Axinom's FairPlay license service licenses.
Then it plays them through `FairPlayCdm` and `FairPlayRenderer`
([core](../../../Engine/ParcNative/fairplay/README.md)) the way Chromium hands
them over.

```bash
scripts/test-fairplay-codecs.sh
```

The script compiles the core, `../fmp4_parser.cc` and this directory with
clang only (C++20, `-Wall -Wextra -Werror`, ARC), then runs the program. It
needs network access and opens a visible window for about six minutes.
Downloads are cached in `$PARC_FAIRPLAY_CACHE` (default
`$TMPDIR/parc-fairplay-cache`, shared with the core harness). The program
samples its stack and exits with status 3 if the main thread stalls for 15 s,
or with status 4 after `--time-limit` seconds (default 600). The script kills
it at 660 s. `--only <text>` plays only the clips whose names contain the
text. Exit status is the number of failed checks clamped to 1.

## Key

Axinom publishes the content keys of its v10 vectors next to their key IDs
and entitlement tokens, in
[ContentKeys/](https://github.com/Axinom/public-test-vectors/tree/master/ContentKeys).
"CMAF H264 SingleKey" is key `302f80dd-411e-4886-bca5-bb1f8018a024`, content
key `FbKq+Qbr7GMJ1A+RKJEnuA==`, with the same token the core harness uses.
Axinom's FairPlay service licenses that key ID for any content. The token's
inline key also carries the FairPlay IV (`77fd1889aaf4143b085548b3c0f95b9a`),
which is the constant IV of Axinom's own content.

Dead ends:

- `clearkey.axprod.net` (the Clear Key service in Axinom's README) no longer
  exists in DNS: NXDOMAIN from Google's and Cloudflare's resolvers.
- The v9 vector's page publishes key `f8c80c25-690f-4736-8132-430e5c6994ce`
  and its token, but the FairPlay service refuses that token with HTTP 400:
  "An initialization vector must be provided with every key in the
  entitlement message". The token has no IV and is signed, so it can't be
  amended.

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
that each signal notices garbage.

## Results

Recorded 2026-11-06 on this MacBook Air (macOS 27.2): 167 checks, 15
failed. Every failure is one of the open problems listed below. Run time is
about six minutes.

Proven: each decrypts and decodes with no decoder errors, and a wrong key
under the same key ID fails visibly.

| Codec | Protected type | Evidence |
|---|---|---|
| Dolby Vision profile 5 `dvh1` (glass-blowing2) | `qdh1` | 120/120 frames, 0 corrupted, `OnEnded` at 2.000 s; wrong key: 120 decode failures |
| Dolby Vision profile 5 `dvhe` (color_pattern 1080p) | `qdh1` | 75/75 frames, 0 corrupted, `OnEnded` at 3.125 s |
| AV1 8-bit and 10-bit `av01` | `qav1` | 82/82 frames each, 0 corrupted, no decoder errors (see the AV1 caveat) |
| HE-AAC (`mp4a.40.5`) and HE-AACv2 (`mp4a.40.29`) | `qaac` | 68/68 packets, `OnEnded` at 3.158 s, no decoder errors; an AAC wrong key logs 550 |
| xHE-AAC (`mp4a.40.42`) | `qusa` | 24/24 packets, no decoder errors (the clear stream: none); wrong key: 22 `ACCPEDecoderWrapper` errors |
| AC-3 | `qac3` | 30/30 packets, no decoder errors; wrong key: 60 (`ParseAC3Header failed`) |
| E-AC-3 | `qec3` | 30/30 packets, no decoder errors; wrong key: 60 |
| E-AC-3 7.1 (DASH-IF, FA01), with the file's `dec3` | `qec3` | 188/188 packets, 6.016 s, no decoder errors |

Controls through the same path: Axinom's own H.264 segment as served (144/144
frames), this program's encryption of H.264 (82/82) and HEVC (82/82), and
AAC-LC (132/132 packets, no decoder errors). H.264 under a wrong key fails all
82 frames with -12909.

AV1 caveat: Apple's AV1 decoder decodes garbage tile data without complaint.
Under six wrong keys, two gave decode errors (24 and 68 corrupted frames) and
four looked exactly like the right key. Protected AV1 frames can't be read
back (`copyDisplayedPixelBuffer` returns nothing, while the clear stream gives
`&8v0` frames). So the frames are decrypted with the key (some wrong keys
break them; the right key never has), but correct decryption of every block
isn't proven.

7.1 channel layout: CoreMedia's top layer for the file's `dec3` (chan_loc
`0x002`, Lrs/Rrs) is 8 channels, `EAC3_7_1_A` (L C R Ls Rs LFE Rls Rrs).
Apple's E-AC-3 decoder decodes all 30 s of the clear stream to 8 channels with
that layout, each carrying signal (RMS 0.015–0.024).

Open problems:

- Core: 7.1 E-AC-3 as Chromium delivers it (8 channels, no `dec3`,
  whole-sample encryption) is rejected at the first enqueue, because
  `Eac3SpecificBoxFromConfig(48000, 8)` returns nothing ("AC-3/E-AC-3 config
  needs a 48, 44.1 or 32 kHz rate and 1-6 channels"). The box above plays,
  so the core's box building is the only blocker.
- Core: `Eac3SpecificBoxPayload` builds `dec3` `1800200f0280` from the clear
  syncframes of that stream. It gives chan_loc `0x080` where the file has
  `0x002`, with the 9-bit order reversed. Apple reads it as 7 channels,
  `EAC3_6_1_C` (tag 159), instead of 8.
- cenc (AES-CTR) doesn't decode:
  - H.264 fails all 82 frames, and the log says
    `FigCPECryptorCreateProcessedBlockBufferAndSubsampleAuxiliaryData
    returned error -12160`;
  - Dolby Vision `dvhe` fails all 75 frames (AppleAVD error 406);
  - AAC-LC logs 432 decoder errors (`Error deserializing packet`), though
    the renderer reports nothing.

  The same happens when every sample's IV is the license's. The cause, core
  or platform, isn't established.

Platform behaviour (checked to fail, so a change would show up):

- `qavc`, `qhvc` and `qdh1` are decrypted with the IV the CKC carries. A
  constant IV the license doesn't carry fails every frame, whether it is in
  the `tenc` or in the per-sample `CryptorIV` attachment. The core harness's
  constant-IV result used content whose IV equals the license's.
- AC-3 and E-AC-3 with their syncframe headers clear (a subsample layout)
  fail every packet exactly like a wrong key, including 7.1 (188/188
  packets). Whole-sample protection, the CMAF form, works.
- AV1 has no cenc protected type (the description stays `encv`, -12167).
  Encrypted AV1 frame headers fail ("fail to parse av1 header"). Video
  protected with every block encrypted (pattern 0:0) fails about half its
  frames even with the right key.

Not covered: Dolby Vision profile 8, per-sample key rotation, license
renewal, HDCP and external displays.

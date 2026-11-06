# FairPlay M0 proof

Proves the engine-independent FairPlay core in
[Engine/ParcNative/fairplay](../../Engine/ParcNative/fairplay/README.md) plays
real FairPlay content on this Mac, before any Chromium integration.

```bash
scripts/test-fairplay-core.sh
```

The script compiles the core and the harness with clang only (C++20,
`-Wall -Wextra -Werror`, macOS 13.0 target, ARC), then runs it. It needs
network access and opens a visible window for about two minutes. Downloads
are cached in `$PARC_FAIRPLAY_CACHE` (default `$TMPDIR/parc-fairplay-cache`).
Exit status is the number of failed checks clamped to 1.

## Content and license

Axinom's public test vector "CMAF H264 SingleKey (cbcs)" (v10), from
[Axinom/public-test-vectors](https://github.com/Axinom/public-test-vectors).
The README's Shaka player link for the FairPlay variant gives:

- media: `https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/`
  (HLS playlists over CMAF byte ranges; the harness uses the 720p rendition and
  English audio),
- license: `https://drm-fairplay-licensing.axprod.net/AcquireLicense`,
- certificate: `https://tools.axinom.com/FPScert/fairplay.cer`,
- the entitlement token for key `302f80dd-411e-4886-bca5-bb1f8018a024`.

Axinom's player (tools.axinom.com `js/players/shaka.js`) adds only the
`X-AxDRM-Message: <token>` header to Shaka's default FairPlay request, so the
license service takes the raw SPC as the POST body
(`application/octet-stream`) and answers with the raw CKC. The skd URI is in the
media playlists' `EXT-X-KEY` with `KEYFORMAT="com.apple.streamingkeydelivery"`.

The clear variant (`clear_1080p_h264`) is the same encode (identical `avcC` and
`esds`), so its first segment stands in for clear-lead samples.

## What the harness does

`fmp4_parser.cc` is a minimal parser that yields what Chromium's
`MP4StreamParser` gives a renderer at the pinned tag: codec config,
sinf/schm/tenc, and per sample its bytes, timing (edit list applied), keyframe
flag and DecryptConfig with subsamples from senc or saiz/saio (both are read
and must agree) and seig groups. `ChromiumBuffer` then applies Chromium's
reframing: Annex B with SPS/PPS before keyframes, ADTS on AAC, microseconds,
16-byte IVs.

1. Offline self-tests on the downloaded segments: box builders against the
   file's own `sinf`, the AAC cookie through CoreAudio, Annex B and ADTS round
   trips through the core's reframing, init-data planning.
2. License exchange through `FairPlayCdm` with skd init data.
3. Chromium-framed playback: play 8 s, pause, resume, rate 1.5, volume/mute,
   seek to 40 s (mid-segment), and end of stream with `OnEnded`.
4. ISO-framed playback: play and seek.
5. Clear lead: a clear segment, then protected segments, in one track.
6. Underflow: 6 s of data, HAVE_NOTHING with the clock stopped, then more data
   and recovery.
7. Samples before keys: encrypted samples are held, then played when the
   license arrives.
8. sinf, keyids and cenc init data (cenc both with the vector's own pssh boxes
   and with a FairPlay pssh added): each gets a license and plays 3 s.
9. Netflix's key flow on Axinom's three-key vector ("CMAF H264 MultiKey",
   cbcs). One `cenc` request carries the vector's pssh boxes plus a FairPlay
   pssh naming all three keys. That produces one JSON message with three SPCs
   and one JSON response, then video and audio play under different keys. A
   second run does the same without the FairPlay pssh, using the Widevine key
   IDs.
10. HEVC: "CMAF H265 SingleKey" (cbcs, its own token and key), Chromium-framed,
    5 s.
11. Netflix's codecs through the renderer's clear path, Chromium-framed and
    played to `OnEnded`, each followed by a check of its protected format type.
    Media comes from Chromium's `media/test/data`: `hev1` (also with its
    parameter sets moved in-band), Dolby Vision profile 5, AV1 and xHE-AAC.
    HE-AAC and HE-AACv2 are encoded locally with AudioToolbox.
12. Session remove and close.

## Results

Recorded 2026-11-06 on this MacBook Air (macOS 27.2, build 26B123): 186 checks,
0 failed. Excerpts:

- License (skd): 7632-byte SPC, HTTP 200, 1004-byte CKC, key
  `302f80dd411e4886bca5bb1f8018a024` usable in 0.45 s.
- Chromium framing (Annex B + in-band SPS/PPS, ADTS, µs, 16-byte IVs), 720p +
  AAC:
  - play: media time 0.000 → 7.900 over 8.005 s wall; video and audio
    `rendering`; AVFoundation metrics 243 frames, 0 dropped, 0 corrupted;
  - pause: 7.902 → 7.902 over 2.03 s; resume: +2.026 s over 2.014 s; rate
    1.5: +3.018 s over 2.021 s;
  - seek to 40 s: lands at 40.000, then +3.952 s over 4.028 s, 259 more
    frames, 0 dropped or corrupted;
  - end of stream: `OnEnded` at t=78.019 for a 78.000 s end;
  - no HAVE_NOTHING during steady playback; output never obscured.
- ISO framing: +7.951 s over 8.031 s (231 frames); seek, then +3.949 s.
- Clear lead: 4.951 s clear, then 6.000 s over 6.000 s into protected samples,
  303 frames, 0 dropped or corrupted.
- Underflow: HAVE_NOTHING at t=6.001 (data ended at 6.0); clock frozen for
  1.5 s; with more data, HAVE_ENOUGH, then +3.034 s over 3.009 s.
- Late keys: samples held, `OnWaitingForKey` once, nothing enqueued until the
  license; then +3.948 s over 4.025 s.
- sinf, keyids, cenc (vector pssh boxes), cenc (with a FairPlay pssh): each
  license is HTTP 200, each plays about 2.95 s of 3 s.
- HEVC (H265 vector, key `abcc44e5c12245abac80a5b3522a0a31`): 5840-byte SPC,
  HTTP 200; +4.947 s over 5.021 s; 159 frames, 0 dropped or corrupted.
- Remove reports the key released and unusable; close fires
  `OnSessionClosed`; an update after close is rejected (InvalidStateError).

Netflix profile (2026-11-06, 249 checks, 0 failed):

- Three keys: the `cenc` init data was 890 bytes (vector boxes plus a FairPlay
  pssh). It produced one 31,225-byte JSON license message with three SPCs;
  Netflix's messages were 27–39 KB. Three Axinom CKCs went back in one JSON
  response, and `b54ec914…` (audio), `c868c702…` (720p video) and `c83c4ea8…`
  all became usable. Playback: 3.923 s over 4.001 s, 133 frames, 0 dropped or
  corrupted. The same works with only the Widevine key IDs.
- Clear-path decoding with Chromium framing, each played to `OnEnded` at the
  clip's end:
  - hev1: 82/82 frames, 0 corrupted;
  - hev1 with in-band parameter sets only: 82/82;
  - Dolby Vision profile 5: 120/120 frames, 0 corrupted;
  - AV1: 82/82 frames;
  - xHE-AAC, HE-AAC, HE-AACv2: each ended on time.
- Protected types: `qhvc`, `qdh1`, `qav1`, `qusa`, and `qaac` with `qach` or
  `qacp` layers.
- During some runs `outputObscuredDueToInsufficientExternalProtection` went
  true for about 30 s while frames kept decoding. That is consistent with
  screen capture by another process on this Mac. The harness logs it rather
  than failing.

Screenshots of the window show no picture, as expected for protected video.
Playback is proven by the clock, the renderer status and AVFoundation's frame
counts instead.

Not verified: protected decoding of Dolby Vision, AV1, HE-AAC and xHE-AAC (no
public FairPlay vector exists; their clear decoding and protected format types
are proven), `dvhe`/`avc3` (normalized like `hev1`, untested), E-AC-3 and AC-3
(not exercised at all), Dolby Vision profile 8 (`dvvC`), cenc-scheme content (8-byte IV truncation and
the `CryptorIV` attachment are unexercised because both vectors use a constant
IV), per-sample key rotation within one track (one format description per key
ID is implemented, but untested), license renewal, macOS versions below 27,
external displays and HDCP.

## Apple API behaviour

Established on this Mac (macOS 27.2, Xcode SDK 27.2), with the probes noted.

Key delivery
- `AVSampleBufferAttachContentKey` fails on every sample with
  `AVFoundationErrorDomain -11836` ("Cannot Open", failure reason "This app is
  not authorized to play this file") over `NSOSStatusErrorDomain -12161`. The
  first call also takes about 0.7 s. WebKit commit 271966@main (Apple-reviewed)
  states the API needs `com.apple.private.coremedia.allow-fps-attachment` on
  macOS, and WebKit grants that only to its GPU process. An ad-hoc signed binary
  that claims the entitlement is SIGKILLed at launch (exit 137). The API can't
  be used by Parc.
- `AVSampleBufferDisplayLayer` and `AVSampleBufferAudioRenderer` conform to
  `AVContentKeyRecipient` at runtime (only `AVURLAsset` is declared so in the
  macOS SDK). `AVSampleBufferVideoRenderer` doesn't conform. Added with the
  public `-[AVContentKeySession addContentKeyRecipient:]`, they decrypt
  client-built protected buffers with the session's keys. No entitlement is
  needed.
- Recipients match keys by the key ID in the sample's format description. A
  key from a request named by an skd URI is never used: both renderers fail
  with `-11800` "no content key present", and no new request is raised. A key
  from a request named by the 16-byte key ID plays.
- AVFoundation names a request by the key ID (`identifier` is `NSData`) for
  sinf JSON `{"sinf": [...]}` and for a FairPlay pssh `{"pssh": "<base64>"}`.
  A FairPlay pssh arrives through the plural
  `didProvideContentKeyRequests:forInitializationData:` (macOS 14.4+) with
  `ProtocolVersionsKey [1]` in the options. A minimal synthesized pssh
  (`fpsd { fpsi(scheme), fpsk { fkri(key ID) } }`) is enough. Its scheme field
  doesn't matter: a 'cenc' pssh keys 'cbcs' content.
- `processContentKeyRequestWithIdentifier:<NSData key ID> initializationData:nil`
  is silently ignored: no request and no error.
- The SPC's content identifier is independent of the request identifier. Axinom
  accepts the whole skd URI (WebKit's choice) and the raw 16-byte key ID.
- Custom keys in the `options` given to `processContentKeyRequestWithIdentifier:`
  come back in `AVContentKeyRequest.options`. The core routes requests to EME
  sessions with them.
- After `processContentKeyResponse:`, the key is in `request.contentKey`.
  `contentKeySession:didProvideContentKey:` belongs to `AVContentKeyRecipient`,
  not the session delegate, so it never fires there.
- `AVContentKeyReportGroup` is not in the macOS 27 SDK. Per-session key
  release uses `-[AVContentKey revoke]` (macOS 14.4+), because `expire`
  disables every recipient of the shared session.

Sample buffers (from Apple's own `AVStreamDataParser` on the same segments,
probed through its runtime interface)
- Protected sample entry types are `qavc` (H.264), `qhvc` (HEVC) and `qaac`
  (AAC). `kCMFormatDescriptionExtension_ProtectedContentOriginalFormat` is the
  string `CommonEncryptionOriginalFormat`. The parser also sets
  `CommonEncryptionProtected` and `CommonEncryptionTrackEncryptionBox` (the
  41-byte `tenc` payload, version and flags included), plus `avcC`/`hvcC` and
  `sinf` (frma/schm/schi payload) in `SampleDescriptionExtensionAtoms`. The
  core builds exactly these; its `sinf` bytes equal the file's.
- AAC: ASBD `mFormatID` is `qaac`, and the magic cookie is an `esds` atom
  header followed directly by the ES_Descriptor (no version or flags). Stereo
  layout tag.
- Per sample: `CryptorSubsampleAuxiliaryData` (native-endian uint32
  clear/protected pairs) and `BytesOfClearDataCount` (the sum of clear bytes).
  There is no IV attachment with a constant-IV `tenc`. The exported
  `kCMSampleAttachmentKey_CryptorInitializationVector` is the string
  `CryptorIV`; the core sets it only for per-sample IVs. CMAF cbcs audio has no
  subsample attachment (whole-sample protection).
- CoreMedia's public `CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData`
  and `CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData` (ISO
  flavor) turn an `encv`/`enca` sample entry into the same format description
  `AVStreamDataParser` builds, including `VerbatimISOSampleEntry`. The core
  relies on them for every codec. Protected types they report: `qhev` (hev1),
  `qdh1` (dvh1, keeping `hvcC` and `dvcC`), `qav1`, `qusa` (xHE-AAC), and
  `qaac` for HE-AAC and HE-AACv2 with `qach`/`qacp` layers in the format list.
- VideoToolbox configures its decoder only from the format description's
  record. An `hev1` description fails every frame (`-12906`) for samples that
  decode as `hvc1`. A record without parameter sets fails too (`-4` as `hvc1`,
  `-12906` as `hev1`), even when every keyframe carries them in-band.
- A stream that ends before AVFoundation reports
  `hasSufficientMediaDataForReliablePlaybackStart` (a 2 s clip) must count as
  enough at end of stream, or HAVE_ENOUGH never fires.
- On this M3, VideoToolbox hardware-decodes `avc1`, `hvc1`, `dvh1` and `av01`
  (not `vp09`). CoreAudio lists protected decoders `qaac`, `qach`, `qacp`,
  `qusa`, `qac3`, `qec3`, `qflc`, `qlac` and `qapc`.
- `outputObscuredDueToInsufficientExternalProtection` turns on while
  something on the Mac captures the screen; decoding continues.
- Constant-IV cbcs content also decrypts when every sample carries its IV as a
  `CryptorIV` attachment and the `tenc` says 16-byte per-sample IVs, which is
  what a renderer can build from Chromium's input (a 16-byte IV on every
  DecryptConfig, no `tenc`). Proven on the Axinom vector with the Chromium
  configs.
- AVFoundation silently drops a request it can't serve: a FairPlay pssh that
  names no key gets no delegate call at all, not even a failure. The key
  session's request timeout is what keeps `generateRequest` from hanging.
- A malformed CKC for a renewal fails with `CoreMediaErrorDomain -42681`. The
  answered key keeps working.
- The ad-hoc signed command-line harness gets SPCs, CKCs and protected playback
  with no app bundle and no entitlement. It ran unsandboxed; the sandbox profile
  of the engine process that hosts the core must allow FairPlay (unverified).

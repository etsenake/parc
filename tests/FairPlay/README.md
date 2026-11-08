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
Exit status is the number of failed checks clamped to 1. `--only <text>`
keeps the scenario groups whose names contain it, and `--muted` mutes every
audio renderer at volume 0 (decoding, flushes and re-delivery are unchanged),
so nothing plays through the speakers.

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
16-byte IVs, and no decode timestamps (DecoderBuffer has none, so B-frames
arrive in decode order with presentation times only).

1. Offline self-tests on the downloaded segments: box builders against the
   file's own `sinf`, the AAC cookie through CoreAudio, Annex B and ADTS round
   trips through the core's reframing, init-data planning.
2. License exchange through `FairPlayCdm` with skd init data.
3. Chromium-framed playback: play 8 s, pause, resume, rate 1.5, volume/mute,
   seek to 40 s (mid-segment), and end of stream with `OnEnded`. The frame
   counts the Chromium adapter reports as playback statistics move with the
   clock: the core's `frames_passed` matches the frames due after 8 s (also
   ISO-framed), and both it and AVFoundation's counts stand still while
   paused, then advance again after resuming.
4. ISO-framed playback: play and seek.
5. Clear lead: a clear segment, then protected segments, in one track.
6. Underflow: 6 s of data, HAVE_NOTHING with the clock stopped, then more data
   and recovery.
7. Samples before keys, as WebKit handles them: encrypted samples are held
   (up to 4 s past the clock) and count as buffered, so HAVE_ENOUGH comes
   before the license while the clock waits at the start for samples it can
   play; they play when the license arrives. A short clip enqueued in full
   with end of stream before its license gets HAVE_ENOUGH and a clock held at
   its start (rate 1 set), then plays from the start once the key arrives and
   ends on time. A clear video lead followed by a protected tail and end of
   stream, without the tail's license, keeps the clock running over the
   frozen picture and ends at the tail's end, as Safari does.
8. sinf, keyids and cenc init data (cenc both with the vector's own pssh boxes
   and with a FairPlay pssh added): each gets a license and plays 3 s.
9. Netflix's key flow on Axinom's three-key vector ("CMAF H264 MultiKey",
   cbcs). One `cenc` request carries the vector's pssh boxes plus a FairPlay
   pssh naming all three keys. That produces one JSON message with three SPCs,
   each named by its own key ID; a response naming a key twice is rejected;
   one JSON response makes all three keys usable, then video and audio play
   under different keys. The FairPlay pssh is version 0 (key IDs only in its
   `fpsd`), so the plan names no key IDs and each request carries only its
   own: a version 1 box with the key IDs in its header gets no request from
   AVFoundation at all on macOS 27.2. A
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
13. Keys after playback started (`HandOffScenario`): a clear lead played
    without a CDM, then `SetCdm` during it, after it (over the frozen
    picture), while paused, just before a seek and just before teardown; the
    page's MediaKeys replaced during protected playback; clear Dolby Vision
    without keys, then keys. Polled every 20 ms: a picture in the layer at
    every poll, the clock never still longer than in plain playback (its
    timebase reads back in steps of about 80 ms), no HAVE_NOTHING, and the
    outgoing display layer gone once the new one has a frame (35-50 ms on
    this Mac). Protected samples then play with the new keys.
14. Video track switches (`VideoSwitchScenario`): protected to clear and
    back, and the track turned off (end of stream) and on again, with audio
    playing. The same display layer shows the new track; the clock waits for
    its first frame (20-140 ms here), with no HAVE_NOTHING.

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
- Frame counts (2026-11-06, with the adapter's statistics): after 8 s the
  core counted 190 of 190 frames due (AVFoundation 247); paused 1.5 s apart,
  core 190 → 190 and AVFoundation 247 → 247, dropped 0 → 0; 2 s after
  resuming, core +49 (24 fps) and AVFoundation +32. AVFoundation's count
  includes the frames decoded ahead of the clock, so right after a pause it
  follows the decoder's queue rather than the clock. ISO-framed: 191 of 191
  due. The full run reached 571 checks, 0 failed, before its 290 s time cap;
  the two sections past the cap passed on their own (HEVC B-frames 82/82
  frames; close and remove). The sandbox probe's h264 and hevc scenarios
  passed under the GPU profile with the FairPlay rules (163 and 164 frames,
  0 dropped).
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

Protected decoding of the other codecs is in [codecs/](codecs/README.md). It
covers Dolby Vision (`dvh1`, `dvhe`), AV1, HE-AAC, HE-AACv2, xHE-AAC, AC-3,
E-AC-3, 7.1 E-AC-3 and the cenc scheme, using content encrypted locally under
Axinom's published key. Its results list what still fails.

Not verified: `avc3` (normalized like `hev1`, untested), Dolby Vision profile
8 (`dvvC`), per-sample key rotation within one track (one format description
per key ID is implemented, but untested), license renewal, macOS versions
below 27, external displays and HDCP.

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
  configs. Axinom's content IV equals the IV in its CKC, though. With a
  different content IV, `qavc`, `qhvc` and `qdh1` fail every frame, so the IV
  used is the license's ([codecs/](codecs/README.md)).
- AVFoundation silently drops a request it can't serve: a FairPlay pssh that
  names no key gets no delegate call at all, not even a failure. WebKit's
  `generateRequest` then stays pending, and so does the key session's (it
  has no timeout).
- A malformed CKC for a renewal fails with `CoreMediaErrorDomain -42681`. The
  answered key keeps working.
- The ad-hoc signed command-line harness gets SPCs, CKCs and protected playback
  with no app bundle and no entitlement. It ran unsandboxed; the sandbox profile
  of the engine process that hosts the core must allow FairPlay (unverified).
- Setting `audioOutputDeviceUniqueID` on a playing `AVSampleBufferAudioRenderer`
  (from unset to the built-in speakers' explicit UID) posts
  `AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification` once, with
  the flush time; setting the same device again posts none. Setting nil throws
  `NSInvalidArgumentException` (`audioOutputDeviceUniqueID != nil`), so the
  system default has to be passed as its UID.
- CoreMedia accepts `dac3`/`dec3` boxes with the bit rate fields 0: clear AC-3
  and E-AC-3 decode to the end with them.
- A covered harness window that plays video without audio appears to be App
  Napped: in one full run, main-queue timers fired 1.2–1.8 s late while
  samples showed the main thread idle in `mach_msg`, and two video-only clips
  missed `OnEnded` (one stopped getting need-data). The same clips pass when
  run alone with the window in front. The harness now holds an
  `NSActivityUserInitiated | NSActivityLatencyCritical` activity for its run.
- `-[AVSampleBufferRenderSynchronizer addRenderer:]` throws
  `NSInvalidArgumentException` ("invalid renderer") for an
  `AVSampleBufferAudioRenderer` created while `com.apple.audio.audiohald`,
  `com.apple.audio.AudioSession` and `com.apple.coremedia.routingcontext.xpc`
  are denied (`sandbox-exec`); the proof script runs that case.
- `AVSampleBufferDisplayLayer` plays reordered H.264 the same with real decode
  times, with `kCMTimeInvalid`, or with the PTS copied in (decode times
  running backwards): 0 dropped and 0 corrupted frames each way. The same
  holds for HEVC with Netflix's hierarchical B-frames, 1080p and 4K, clear and
  under FairPlay: AVFoundation decodes about 1.6 s ahead of the clock with or
  without decode times ([decode_times/](decode_times/README.md#results)).
- Removing the display layer from its tree for 3 s mid-playback neither stops
  decoding nor sets `requiresFlushToResumeDecoding`.
- DASH-IF's 7.1 Dolby Digital Plus channel-ID stream (Dolby Media Generator)
  carries `dec3` `chan_loc` = 0x002 for Lrs/Rrs: bit 0 is the LSB. CoreMedia's
  format description lists that box with a top layer of 8 channels
  (`EAC3_7_1_A`) over a 6-channel one, and the stream decodes to the end
  ([codecs/](codecs/README.md#results)).

HLS assets (`AVURLAsset` under `AVPlayer`, the native HLS route; probed with
Axinom's SingleKey and MultiKey HLS on assets that load by themselves, not
through the player's client URL loading)
- An asset added with `addContentKeyRecipient:` before its `AVPlayerItem`
  exists never sends skd requests to its resource loader. Its key request
  reaches the session's delegate named by the skd URI (`NSString`, no init
  data, `ProtocolVersionsKey [1]`), once per URI even when audio and video
  playlists share it; a CKC from that request's SPC (content identifier = the
  URI) plays.
- A key the session already holds for the URI
  (`processContentKeyRequestWithIdentifier:<URI>`, made before the asset
  existed) is used without a further request once the asset is a recipient.
  The same key made while a loading request is held plays once the asset is
  made a recipient and the held request is finished with
  `contentType = AVStreamingKeyDeliveryContentKeyType` (WebKit's
  `attemptToDecryptWithInstance` order).
- A held skd loading request finished that way before the session has a
  usable key for its URI never plays, also when the key arrives afterwards
  (one requested and in flight when it was finished included): no delegate
  call, the player waits for ever. Finished that way while the asset is no
  recipient, the item fails with `CoreMediaErrorDomain -19156`.
- Once the asset is a recipient, `processContentKeyRequestWithIdentifier:` for
  the URI of a still-held loading request produces no request at all, and
  `-[AVAssetResourceLoadingRequest streamingContentKeyRequestDataForApp:...]`
  throws `NSInternalInconsistencyException` ("Cannot generate content key
  request when AVAsset is attached to AVContentKeySession").
- While the asset is no recipient, a held loading request answered with a CKC
  from its own SPC (`respondWithData:`, the streaming key content type,
  `finishLoading`) plays (WebKit's legacy route); Axinom expects the URI as
  content identifier there too. A second SPC from the same loading request
  fails (`AVFoundationErrorDomain -11800` over `-12158`): one SPC per request.
- With these, a stand-in of the core's routes passed 35 of 37 checks
  (session route, resource loader route, MultiKey's separate audio and video
  keys on both, a key licensed before the load, a session waiting for the
  asset, sessions made before the asset was attached, a legacy content ID,
  obscured output); the two failures were a closed session handing its used
  loading request to another session, which the core now fails instead so
  AVFoundation asks again. Parc then dropped the recipient route: a recipient
  asset raises no `webkitneedkey` (its requests never reach the resource
  loader), and the resource loader route plays in every order. The `keys-*`
  scenarios of `scripts/test-fairplay-hls.sh` cover it through
  `FairPlayHlsPlayer` and `FairPlayHlsKeyLoader`.

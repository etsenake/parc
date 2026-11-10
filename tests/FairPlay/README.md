# FairPlay M0 proof

Exercises the engine-independent FairPlay core in
[Engine/ParcNative/fairplay](../../Engine/ParcNative/fairplay/README.md) with
real FairPlay content, independently of Chromium. This harness opens a window;
running it requires explicit authorization under [AGENTS.md](../../AGENTS.md).

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
- the SingleKey entitlement token and key identifier, held as `kToken` and
  `kSkd` in [the harness](harness.mm).

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

1. Offline segment checks: box builders match the file's `sinf`; AAC cookies
   work through CoreAudio; Annex B/ADTS round trips and init-data planning agree.
2. License exchange through `FairPlayCdm` with skd init data.
3. Chromium-framed playback: play, pause, resume, rate 1.5, volume/mute,
   mid-segment seek and end of stream. Core frame statistics track frames due
   at the clock; core and AVFoundation counters stay fixed while paused.
4. ISO-framed playback and seeking.
5. Clear lead followed by protected samples in the same track.
6. Underflow: HAVE_NOTHING stops the clock; more data restores playback.
7. Samples before keys: encrypted samples are held up to 4 s past the clock
   and count as buffered. HAVE_ENOUGH can precede the license while playback
   waits. A complete encrypted clip waits at its start and ends on time after
   licensing; a clear lead with an unlicensed encrypted tail keeps the clock
   running over the frozen picture and ends at the tail's end, as Safari does.
8. sinf, keyids and cenc init data, with both the vector's pssh boxes and an
   added FairPlay pssh, each license and play.
9. Multi-key `cenc` requests: Axinom's "CMAF H264 MultiKey" produces one JSON
   message containing three SPCs. Duplicate response key IDs are rejected;
   one valid response makes the audio and video keys usable. A version 0
   FairPlay pssh names keys only in `fpsd`, so each request carries its own.
   A version 1 pssh with key IDs in its header gets no AVFoundation request
   on macOS 27.2. The scenario also runs with only Widevine key IDs.
10. HEVC: Axinom's "CMAF H265 SingleKey" with its own key/token and Chromium
    framing.
11. Clear codec playback to `OnEnded` and protected-format checks: Chromium's
    `hev1` (including in-band parameter sets), Dolby Vision profile 5, AV1 and
    xHE-AAC; locally encoded HE-AAC/HE-AACv2; WebM VP9/Vorbis parsed by
    `webm_parser.cc`. VP9 and Vorbis run separately and under Dolby Vision;
    `CodecSwitchScenario` reconfigures VP9 → Dolby Vision → VP9.
12. SAMPLE-AES TS: Axinom's "HLS H264 SingleKey" is split by `ts_parser.cc`
    like Chromium, with the mpts key ID. `AVStreamDataParser` supplies the
    reference init data, formats and sample bytes. Axinom needs a key GUID
    as the SPC asset ID, supplied by `SetSpcContentIdentifierForTesting`;
    WebKit and Parc use `TransportStreamIdentifier`. AC-3, E-AC-3 and the
    HE-AAC variants retain the parser's format types.
13. Session remove and close.
14. `HandOffScenario`: attach keys during/after clear lead, while paused,
    before seek and before teardown; replace MediaKeys during protected
    playback; attach keys after clear Dolby Vision. It polls picture presence
    and clock progress, requires no HAVE_NOTHING, and retires the outgoing
    layer only after the replacement has a frame.
15. `VideoSwitchScenario`: protected ↔ clear and video off/on while audio
    plays. The same display layer shows the new track; the clock waits for
    its first frame without HAVE_NOTHING.

## Interpreting checks

The checks distinguish frames due at the playback clock from AVFoundation's
frames decoded ahead. Pause holds both counters; resume advances them. Protected
playback checks use the clock, renderer state and frame metrics, while output
protection is recorded separately. Protected video is intentionally unavailable
to capture APIs.

[Protected-codec checks](codecs/README.md) exercise locally encrypted Dolby Vision,
AV1, AAC variants, AC-3 and E-AC-3, including 7.1 channel layout, and encode the
unsupported encryption/codec cases as expected failures. `RenewalScenario` checks
that playback keeps its answered key through a pending or failed renewal.

## Apple API behaviour

Established on this Mac (macOS 27.2, Xcode SDK 27.2), with the probes noted.

Key delivery
- `AVSampleBufferAttachContentKey` fails on every sample with
  `AVFoundationErrorDomain -11836` ("Cannot Open", failure reason "This app is
  not authorized to play this file") over `NSOSStatusErrorDomain -12161`. The
  first call also takes about 0.7 s. WebKit's content-key attachment implementation
  requires `com.apple.private.coremedia.allow-fps-attachment` on
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
  with no app bundle and no entitlement. The separate
  [GPU sandbox fixture](sandbox/README.md) exercises the required sandbox grants.
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
  sets the second least-significant `dec3` `chan_loc` bit for Lrs/Rrs. CoreMedia's
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
- Parc uses the resource-loader route so every native key request can raise
  `webkitneedkey`. Reusing a loading request after its SPC has been consumed
  fails; the core preserves request ownership instead of handing it to another
  session. The `keys-*` scenarios of `scripts/test-fairplay-hls.sh` exercise
  ordering through `FairPlayHlsPlayer` and `FairPlayHlsKeyLoader`.

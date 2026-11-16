# FairPlay playback core

Engine-independent FairPlay Streaming playback for Parc. Chromium keeps demuxing the page's media; these classes take the still
encrypted samples with their DecryptConfig and play them through Apple's public
sample-buffer API. Nothing here depends on Chromium: ObjC++ with ARC over
AVFoundation, CoreMedia and AudioToolbox, plus the C++ standard library. Headers
are plain C++ so Chromium `.cc` files can include them. Deployment target is
macOS 13.0; newer APIs are behind `@available`. The production overlay builds it with the GPU media service.

The proof harness is [tests/FairPlay](../../../tests/FairPlay/README.md), run by
`scripts/test-fairplay-core.sh`.

## Files

- `fairplay_types.h`: shared value types (samples, DecryptInfo, codec configs,
  MediaTime, Result).
- `fairplay_key_session.{h,mm}`: `FairPlayCdm`, sessions over
  `AVContentKeySession` (`AVContentKeySystemFairPlayStreaming`).
- `fairplay_init_data.{h,mm}`: skd, sinf, cenc, mpts and keyids init data,
  mirroring WebKit's FairPlay CDM.
- `fairplay_renderer.{h,mm}`: `FairPlayRenderer`, an
  `AVSampleBufferDisplayLayer` and an `AVSampleBufferAudioRenderer` per audio
  track (played mixed, as WebKit's `AudioVideoRendererAVFObjC` keeps one per
  enabled track) under an `AVSampleBufferRenderSynchronizer`. Streams added
  during playback (`AddVideo`, `AddAudio`) join the synchronizer; the clock
  waits for their samples. Another video track (`ReplaceVideo`) plays in the
  same display layer from the current time.
- `fairplay_bitstream.{h,cc}`: Annex B and ADTS reframing, subsample
  bookkeeping, and the `tenc`/`sinf`/`esds` bytes.
- `fairplay_key_session_internal.h`: content key recipient attachment for the
  renderer (ObjC++ only).
- `fairplay_hls_frame_stats.{h,mm}`: frame counts for the native HLS player
  ([NATIVE_HLS.md](../fairplay_chromium/NATIVE_HLS.md)), read from
  `-[AVPlayerLayer videoPerformanceMetrics]` on a private queue every 250 ms
  while playing and reported as deltas (ObjC++ only). Proven by
  [tests/FairPlay/hls_presentation](../../../tests/FairPlay/hls_presentation/README.md).
- `fairplay_hls_media_selection.{h,mm}`: `HlsMediaSelection`, the native HLS
  player's audio and text tracks and cues exactly as Safari's AVFoundation
  player exposes them (see Native HLS tracks below);
  `fairplay_hls_media_selection_internal.h` attaches it to the player's
  `AVPlayer` and item (ObjC++ only).
- `fairplay_hls_player.{h,mm}`: `FairPlayHlsPlayer`, Safari's native HLS route
  (`<video src="….m3u8">`) through `AVPlayer`, with every load handed to the
  embedder's `HlsLoader` (see below and
  [NATIVE_HLS.md](../fairplay_chromium/NATIVE_HLS.md)).
- `fairplay_hls_player_internal.h`: the player's asset, `AVPlayer` and
  `AVPlayerLayer` for the key loader and display, and the key request
  handler seam (ObjC++ only).
- `fairplay_hls_keys.{h,mm}`: `FairPlayHlsKeyLoader`, the FairPlay keys of
  the native HLS player's asset ("HLS assets" below; ObjC++ only).
- `fairplay_hls_timeline.{h,cc}`: the player's duration, seekable window and
  start date by WebKit's rules, with Safari's caching (plain C++).

## Mapping onto Chromium (M1)

| Chromium | Core |
| --- | --- |
| `ContentDecryptionModule::SetServerCertificate` | `FairPlayCdm::SetServerCertificate` |
| `CdmConfig::allow_persistent_state` | `SetPersistentStateAllowed(bool)` |
| `CreateSessionAndGenerateRequest` | `CreateSessionAndGenerateRequest(SessionType, InitDataType, init_data)` (temporary or Safari's persistent-usage-record) |
| `LoadSession` / `UpdateSession` / `CloseSession` / `RemoveSession` | same names (`LoadSession` and `RemoveSession` as WebKit's `loadSession`/`removeSessionData`) |
| `ContentDecryptionModuleClient` (`OnSessionMessage`, `OnSessionKeysChange`, `OnSessionClosed`) | `FairPlayCdmClient` |
| `Renderer::Initialize` (decoder configs) | `FairPlayRenderer::Initialize(VideoConfig, AudioConfig)` |
| `Renderer::SetCdm` | `SetCdm(FairPlayCdm*)` (joins the renderers to the CDM's key session, or new ones that take over after media was processed) |
| `DemuxerStream::Read` loop | `OnNeedData` + `IsReadyForMoreData` + `Enqueue(EncodedSample)` |
| `DecoderBuffer` + `DecryptConfig` | `EncodedSample` + `DecryptInfo` |
| `StartPlayingFrom` / `SetPlaybackRate` / `SetVolume` / `Flush` / `GetMediaTime` | same names (plus `SetMuted`); the rate picks the audio renderer's pitch algorithm as WebKit's `AudioVideoRendererAVFObjC` does (Spectral off 1x, else Varispeed) |
| `ParcRendererExtension::ParcSetPlaybackRateAt` (Parc) | `SetPlaybackRateAt`: the rate on another renderer's clock (a time at a host time), as WebKit's `setRateAtHostTime`, so a hand-off from Chromium's renderer has no gap |
| `Renderer::SetPreservesPitch` | `SetPreservesPitch` (true until set; the Chromium FairPlay client forwards the page's choice through the adapter, including a false set before the GPU renderer connected) |
| `RendererClient::OnWaiting(kNoDecryptionKey)` | `OnWaitingForKey` |
| `OnEnded` / `OnError` / `OnVideoNaturalSizeChange` / `OnBufferingStateChange` | same names; a later natural size is reported when the clock reaches its first sample (WebKit's `sizeWillChangeAtTime`) |
| compositing (`ca_renderer_layer_tree.mm`) | `display_layer()` (a `CALayer` host filled by the `AVSampleBufferDisplayLayer`) |
| `RendererClient::OnStatisticsUpdate` (frames decoded/dropped) | `LoadVideoMetrics`: AVFoundation's cumulative counts (macOS 14.4+) and `frames_passed`, the core's count of video samples the clock reached |

Threading: every public method runs on one owner sequence, and every client
callback is posted to it through the `PostTask` given at construction (a
`base::SequencedTaskRunner` in the engine). AVFoundation callbacks arrive on
private serial queues and hop over; the `PostTask` must be callable from any
thread. Callbacks never run inside a call into the core.

The renderer takes exactly what Chromium's MP4 parser produces: Annex B
H.264/HEVC with parameter sets re-inserted before keyframes
(`BitstreamFormat::kAnnexB`), ADTS-prefixed AAC (`AudioFraming::kADTS`),
microsecond timestamps, a 16-byte IV on every encrypted sample (the constant IV
copied in), and the matching adjusted subsamples. It also takes untouched ISO
samples (`kLengthPrefixed`, `kRaw`) in the track timescale.

## Key delivery

`AVSampleBufferAttachContentKey` (attach a key to each `CMSampleBuffer`) is not
available to Parc on macOS. It needs the private entitlement
`com.apple.private.coremedia.allow-fps-attachment` (WebKit commit 271966@main,
"On macOS, this API requires the com.apple.private.coremedia.allow-fps-attachment
entitlement"; WebKit grants it only to its GPU process). Without it every call
fails with `AVFoundationErrorDomain -11836` ("Cannot Open", "This app is not
authorized to play this file") over `OSStatus -12161`. A binary ad-hoc signed
with the entitlement is killed at launch (SIGKILL, exit 137).

The core uses the public path WebKit used before adopting that API:

- `FairPlayCdm` owns one `AVContentKeySession` shared by all its EME sessions.
  The renderer's `AVSampleBufferDisplayLayer` and `AVSampleBufferAudioRenderer`s
  join it with `addContentKeyRecipient:` in `SetCdm`, and a renderer added
  later joins it when it is created, before it processes media. Both conform to
  `AVContentKeyRecipient` at runtime, though only `AVURLAsset` is declared so
  in the macOS headers; `AVSampleBufferVideoRenderer` doesn't conform, so the
  layer is the recipient even when samples go through `sampleBufferRenderer`.
- Recipients find a key by the 16-byte key ID in each sample's format
  description (`tenc` default KID), so a request must be named by that key ID.
  AVFoundation does that for sinf JSON and FairPlay `pssh` init data (the
  request's `identifier` is the key ID as `NSData`). A request named by an skd
  URI produces a key that no recipient matches (`-11800` "no content key
  present"), and an `NSData` identifier without init data is silently dropped.
  So skd URIs that embed the key ID, keyids, and cenc without a FairPlay pssh
  go through a synthesized minimal FairPlay `pssh` naming the key ID, keeping
  WebKit's SPC content identifier. An skd URI without a key ID still gets a
  license, but no renderer can use it.
- A sample is enqueued only once the session holds a usable key for its key
  ID; until then it is held and `OnWaitingForKey` fires. A protected sample
  enqueued without a key fails the renderer.
- Each key ID gets its own protected format description, since that is what
  recipients match on.
- Recipients must join before they process media and belong to one session.
  So a `SetCdm` after the first sample, or with another CDM, makes new
  renderers that join first and take over on the same synchronizer, as
  WebKit's `stageVideoRenderer` swaps video renderers on one timeline: they
  get what the outgoing ones hold (video from the keyframe before the clock,
  hidden up to it; audio from a sample 0.25 s ahead, where the outgoing
  renderer leaves the synchronizer, so nothing plays twice or not at all),
  the new display layer sits under the outgoing one in `display_layer()`'s
  host until it has a frame, and the outgoing renderers keep the old CDM's
  keys until they leave. The clock never stops and nothing is reported to
  the page. Samples the new CDM has no key for are held.
  `setMediaKeys(null)` is `DetachCdm`, as WebKit's renderer without a CDM:
  the renderers stay in the session, so samples already enqueued keep
  decrypting, and every later protected sample is held until `SetCdm` sets the
  same CDM again.
- Expiring the shared session would disable every recipient, so closing or
  removing an EME session revokes its keys with `-[AVContentKey revoke]`
  (macOS 14.4+; `AVContentKeyReportGroup` isn't in the macOS SDK). Before
  14.4 a closed session's keys stay usable until the `FairPlayCdm` is
  destroyed.

## Format descriptions

The renderer builds the ISO sample entry each stream would have carried, with
its `avcC`/`hvcC`/`av1C`/`dvcC`/`dvvC`/`esds`/`dac3`/`dec3` box. When the track
is protected, it wraps the entry as `encv`/`enca` with a `sinf`. CoreMedia's
public parser then turns it into a format description
(`CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData` /
`CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData`, ISO
flavor).

For a protected entry this produces exactly what Apple's own
`AVStreamDataParser` produces, so each codec's FairPlay type comes from Apple
rather than from a table:

| Stream | Protected type |
| --- | --- |
| H.264 | `qavc` |
| HEVC | `qhvc` |
| Dolby Vision `dvh1` | `qdh1` (`hvcC` + `dvcC`) |
| AV1 | `qav1` |
| AAC-LC | `qaac` |
| HE-AAC | `qaac`, with a `qach` layer in its format list |
| HE-AACv2 | `qaac`, with `qacp` and `qach` layers |
| xHE-AAC | `qusa` |

The core's `sinf` and `tenc` bytes equal those in the Axinom files. Its
synthesized entries convert to the same format descriptions as the files' own
entries.

FairPlay's MPEG-2 TS encryption (HLS SAMPLE-AES, mpts init data) has no key
ID or IV in the stream. Chromium's TS parser marks those samples with WebKit's
key ID `TransportStreamIdentifier` (`kTransportStreamKeyId`), which the mpts
request's key answers to. The renderer then gives them `AVStreamDataParser`'s
format: the clear one under Apple's SAMPLE-AES type (`zavc`; `zaac`, `zach` or
`zacp` as the AAC config signals; `zac3`, `zec3`) with a
`TransportStreamEncryptionInitData` extension, and its bytes: no IV or
subsample attachments, and slices longer than 48 bytes without emulation
prevention. Recipients decrypt with the key and the IV the CKC carries.

`hev1`, `avc3` and `dvhe` are presented to CoreMedia as `hvc1`, `avc1` and
`dvh1`. VideoToolbox configures its decoder only from the format description's
record: `AVSampleBufferDisplayLayer` rejects every frame of an `hev1`
description (`-12906`) that it decodes as `hvc1`. Chromium re-inserts parameter
sets before keyframes in any case. When the record has no parameter sets, the
renderer builds one from the first keyframe's in-band sets
(`CMVideoFormatDescriptionCreateFromHEVCParameterSets` /
`...H264ParameterSets`) before creating the formats.

Chromium's configs carry less than the file did, and the renderer takes them
as they are:
- Video records are always empty (`EmptyExtraData()`). The record comes from
  the first keyframe (in-band sets, or AV1's sequence header OBU) and is
  rebuilt when a keyframe brings different ones. A keyframe that repeats only
  some kinds (SPS and PPS under a known VPS) keeps the earlier sets of the
  other kinds. A rebuild that fails leaves the previous record and formats in
  place. The config's natural size wins over the stream's own display size.
- Dolby Vision carries profile and level plus the Safari route's SDR marker
  and color transfer. The adapter preserves SDR compatibility ID 2 and HLG
  compatibility ID 4; otherwise the core uses the profile's default. Profile
  10 uses an AV1-based `dav1` entry with `av1C` and `dvvC`.
- AC-3 and E-AC-3 carry no `dac3`/`dec3`. The box is parsed from the first
  syncframe's header when it is in clear bytes (E-AC-3 substreams grouped by
  type and ID). When the whole sample is encrypted, the box comes from the
  config's sample rate and channel count, with E-AC-3 7.1 as its 5.1 core
  plus a dependent substream of Lrs/Rrs (the layout of Dolby's 7.1 streams,
  which Apple reads as 8 channels) and other 6.1/7.1 as the 5.1 core, and
  the bit rate written as 0 (CoreMedia decodes such boxes; checked with clear
  AC-3 and E-AC-3). Only the count survives, so 7.0 also becomes the 5.1 core,
  wide 7.1 becomes standard 7.1, three or four channels follow the count alone
  and Atmos loses its marker. This limit stays: services send stereo and 5.1,
  which come out exact, and a fix would touch the step that builds their box.
- Buffers carry no decode timestamp (`mojom::DecoderBuffer` has none). The
  sample's decode time stays `kCMTimeInvalid` and AVFoundation decodes in
  enqueue order; on the reordered Axinom H.264 vector this plays exactly as
  with real decode times (and as with the PTS copied in, which the layer also
  tolerates).
- Encryption is the scheme alone. Protected formats are built per key ID (and
  pattern) from each sample's `DecryptConfig`, with 16-byte per-sample IVs
  (Chromium copies a constant IV into every sample).

## Netflix's profile

Observed in a WKWebView with Safari's user agent: standard EME with
`requestMediaKeySystemAccess("com.apple.fps.3_0")` and `cenc` init data
(344 and 272 bytes), a 27–39 KB license message, a 3,555-byte response and
three usable key IDs; media through MSE as `avc1`, `hev1`, `dvhe`/`dvh1`
profile 5 and `av01` video with `mp4a.40.5` (HE-AAC) audio, probing
`mp4a.40.42` (xHE-AAC).

- `FairPlayCdm::IsKeySystemSupported` accepts `com.apple.fps` and
  `com.apple.fps.<version>`, as WebKit does. Netflix's UI also requires the
  legacy prefixed `WebKitMediaKeys.isTypeSupported("com.apple.fps.2_0")`
  before it plays; Safari-identity pages get it as a capability probe
  (docs/fairplay-identity.md, "WebKitMediaKeys"), and the player itself uses
  standard EME.
- A `cenc` FairPlay pssh naming several keys yields one JSON license message
  with an SPC per key, and one JSON response makes them all usable (proven
  with Axinom's three-key vector).
- Codecs: `VideoCodec::kHEVC` (`hvc1`/`hev1`), `kDolbyVision` (`dvh1`/`dvhe`,
  `hvcC` + `dvcC`/`dvvC`), `kAV1` (`av1C`, never Annex B) and `AudioCodec::kAAC`
  for every AudioSpecificConfig object type. Each decodes through the renderer
  from Chromium's own test media. The [protected-codec harness](../../../tests/FairPlay/codecs/README.md)
  encrypts clear fixtures with a licensed public test key and exercises their
  protected decode path. CoreAudio has protected
  decoders for AAC, HE-AAC, HE-AACv2, xHE-AAC, AC-3, E-AC-3, FLAC (`qflc`) and
  ALAC (`qlac`), none for Opus. Hardware AV1 decoding needs M3 or later.
- FLAC and Opus come from Chromium's MP4 parser as the STREAMINFO block and
  the OpusHead it rebuilds from `dOps`. The core turns them back into `fLaC`
  with `dfLa` and `Opus` with `dOps` (48 kHz in the sample entry, the input
  rate in `dOps`), which CoreMedia reads; protected FLAC becomes `qflc`.
  Protected Opus has no decoder, so it fails at the first enqueue, as it would
  in Safari.
- ALAC (`AudioCodec::kALAC`) comes as the 24-byte ALACSpecificConfig (or
  Apple's magic cookie with its `alac` atom, FFmpeg's form). The core builds
  Apple's `alac` sample entry with that config in its ALACSpecificBox;
  protected ALAC becomes `qlac`.
- VP9 (`VideoCodec::kVP9`) and Vorbis (`AudioCodec::kVorbis`) come from
  Chromium's WebM parser, as Safari's Media Source plays them through the same
  AVFoundation renderers. VP9 frames go as stored in a `vp09` entry whose
  `vpcC` the core builds from the keyframe's uncompressed header (profile, bit
  depth, chroma, range) and the container's color; AVSampleBufferDisplayLayer
  decodes it only after `VTRegisterSupplementalVideoDecoderIfAvailable`, which
  the core calls once, as WebKit's GPU process does (without it every frame
  fails with -12906). Vorbis has no ISO entry: its Xiph-laced headers are the
  magic cookie of a `vorb` description, as WebKit's
  `cookieFromVorbisCodecPrivate` builds it, which AudioToolbox decodes as it
  is. FairPlay protects neither.
- PCM (`AudioCodec::kPCM`, Chromium's from ISO 23003-5 `ipcm`/`fpcm`) comes as
  interleaved little-endian samples of `pcm_bits` (16, 24 or 32, or 32-bit
  float). The core builds the `ipcm` or `fpcm` entry with its `pcmC`, which
  CoreMedia makes `lpcm` exactly as AVStreamDataParser does, and enqueues each
  sample as one buffer, as Safari does. Protected PCM stays `enca`: CoreAudio
  has no protected PCM decoder, so AVSampleBufferAudioRenderer fails at the
  first enqueue (-11800, `fmt?`), in Safari too.

## M1 constraints from key delivery

The CDM and its sample-buffer renderers share one GPU process and owner sequence.
Recipients join the `AVContentKeySession` before receiving media; replacing keys
after playback begins stages new recipients on the existing synchronizer. The
compositor places the protected layer without obtaining decoded video pixels.
Canvas, WebGL and capture APIs cannot read protected frames.

The GPU sandbox includes the required FairPlay/CoreMedia services; dedicated
sandbox fixtures describe the required grants and their ablation checks.

Audio bypasses Chromium's mixer. Web Audio's `createMediaElementSource` receives
silence from this path. Volume, mute, ducking and output device map to the native
renderers. A named device disappearing falls back to the default before native
audio fails; empty device selection follows the system default. The native HLS
route uses AVPlayer's corresponding device selection.

The synchronizer owns time. It advances when buffering and available samples
permit, stops at the supplied stream boundary, and handles multiple renderers
sharing one MediaKeys. Key-held samples and buffering are separate signals.

## Recovery inside the renderer

- **Automatic audio flushes.** `AVSampleBufferAudioRenderer` flushes itself
  when its output changes (a route or device switch) and reports the start of
  the first sample it dropped. The renderer keeps the audio it enqueued from
  half a second behind the clock on. As WebKit's `reenqueSamples`
  (`NeedsFlush::Yes`), it flushes the audio renderer, then enqueues again, in
  order, every kept sample from the one containing the clock; otherwise the
  queued duration would play as silence while the clock runs on. The renderer
  is empty when the first goes in, so each sample is in it once, including
  any enqueued between AVFoundation's flush and its notice. A flush time
  outside what was enqueued since the last Flush (a late notice from the
  previous timeline) is ignored. Proven muted with a device switch during
  protected playback (one flush, 42 samples re-delivered, no double enqueue,
  no underflow) and the main scenario's rate steps (one flush, 33).
- **Video decoder resets.** When `requiresFlushToResumeDecoding` turns on, the
  renderer flushes the video renderer and enqueues again from the last
  keyframe at or before the clock, marking frames already due
  `DoNotDisplay`. The clock then waits until a frame decodes again
  (`readyForDisplay`, posted by
  `AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification` on macOS
  14.4+; successful `prerollDecodeWithCompletionHandler:` on macOS
  13.0–14.3), as WebKit's `flushVideo`
  and `updateAllRenderersHaveAvailableSamples`; audio's availability is
  untouched. The Failed status that comes with `requiresFlushToResumeDecoding`
  isn't reported as a decode error.
- `RendererStatus` counts both (`audio_automatic_flushes`,
  `video_decoder_resets`, `redelivered`), and `audio_double_enqueues` counts
  audio samples enqueued while already in the renderer (0 unless a page
  appends over audio already read in a misaligned frame grid).
- Taking the display layer out of its tree for 3 s and putting it back (a
  page losing its compositor) doesn't interrupt decoding or set
  `requiresFlushToResumeDecoding` on this macOS: playback continues, no
  underflow, no corrupted frames.
- When the synchronizer refuses a renderer (an `AVSampleBufferAudioRenderer`
  is invalid when Core Audio's services are out of reach, and
  `-addRenderer:` throws), `Initialize` returns an error and the renderer
  stays uninitialized instead of throwing out of the call.
- Layer creation is committed in an explicit `CATransaction`, since the owner
  sequence may have no run loop.

## Key session contract

- Every promise callback and client callback runs in a later task on the owner
  sequence, never inside a call into `FairPlayCdm`, so a client may re-enter
  it (for example, close the session from `OnSessionKeysChange`).
- `UpdateSession` calls made while one is in flight run in order after it.
- `generateRequest` and `update()` have no timeout of their own, as WebKit's
  `requestLicense` and `updateLicense`: they settle when AVFoundation
  provides, answers or fails the request, and an skd session waiting on an
  HLS asset settles whenever the asset asks for its URI. A request
  AVFoundation drops without a delegate call (a FairPlay pssh naming no key)
  leaves `generateRequest` pending, as in Safari. A failure for a request
  AVFoundation never provided fails that request's part of the license request.
- Failures carry WebKit's names: `generateRequest` rejects with
  NotSupportedError (no certificate, init data `supportsInitData` refuses,
  AVFoundation failing the request, the session closed meanwhile), `update()`
  with TypeError (`MediaKeySession::update` rejects whatever `updateLicense`
  fails with), except on a closed session (InvalidStateError). A JSON
  session's `update()` resolves once every entry settled, even when
  AVFoundation rejected some (WebKit's `UpdateResponseCollector` counts errors
  as responses); their keys then show `internal-error`.
- `update("renew")` settles when the renewal message goes out (WebKit's
  `didProvideRenewingRequest`), or with TypeError if the renewal fails; later
  updates wait for it.
- A renewal (`update("renew")`, or one AVFoundation starts) runs beside the
  answered request. The answered key stays usable until the renewal succeeds
  (it then replaces the key); a failed renewal retains the answered key.
- A JSON license response is validated entirely before any of it is applied.

## Device identifier

As WebKit's `optionsForKeyRequestWithHashSalt`, every SPC an
`AVContentKeyRequest` makes asks AVFoundation for a device identifier
randomized from the document's salt (`SetDeviceIdentifierSalt`;
`AVContentKeyRequestShouldRandomizeDeviceIdentifierKey` and a 20-byte seed of
the salt's hex digit values under `AVContentKeyRequestRandomDeviceIdentifierSeedKey`,
SPI looked up at run time, none when absent). The engine's salt is the
frame's media device ID salt: per top-level site and origin, replaced when
site data is cleared, in memory off the record, as WebKit's
`DeviceIdHashSaltStorage`. Should AVFoundation refuse an SPC with these
options in Parc's process, that CDM makes its SPCs without them from then on.
SPCs made from an HLS asset's loading request carry none, as WebKit's
loading-request path (`CDMSessionAVFoundationObjC`) passes none.

## Messages

skd, sinf and mpts sessions exchange the raw SPC and CKC. cenc and keyids sessions
exchange JSON arrays of `{"keyID", "payload"}` entries (WebKit's cenc format;
a response entry may carry `"error"` instead). `UpdateSession` with the literal
`renew` requests a renewal message, as in WebKit.

The SPC's content identifier follows WebKit: the whole skd URI as UTF-8 for skd,
the raw 16-byte key ID for sinf and FairPlay pssh requests (and, as a Parc
extension, for keyids and for cenc without a FairPlay pssh, which requests the
key IDs the other pssh boxes name), and `TransportStreamIdentifier` for mpts
init data (`{"codc": n, "mtyp": n, "cont": "mpts"}`, passed to AVFoundation
unchanged). Key statuses report that transport-stream identifier, and the
SAMPLE-AES renderer matches it to the TS samples. WebKit's legacy `com.apple.fps.2_N`
sessions name the SPC by the page's bytes instead; Parc's legacy script
(`Engine/ParcRenderer/parc_webkit_media_keys.h`) sends them as sinf init data
with a `"contentId"` member (base64), and AVFoundation gets the sinf entries
alone. (Blink passes sinf init data through unchanged but rebuilds keyids init
data from its key IDs, so extensions can't ride on keyids.) Its legacy `com.apple.fps`/`1_0` sessions
(WebKit's AVFoundation player) name the SPC by the page's content ID: skd init
data `{"skd": "<URI>", "contentId": "<base64>"}` is the URI's request with
that content identifier.

## Apple API behaviour

See [tests/FairPlay/README.md](../../../tests/FairPlay/README.md#apple-api-behaviour)
for what the proof established.

## Native HLS player

`FairPlayHlsPlayer` plays URL media with `AVPlayer` in the GPU media service.
The complete route, networking, display, AirPlay, timing and element behavior are
maintained in [Native HLS](../fairplay_chromium/NATIVE_HLS.md).

The core creates an asset using exclusive client URL loading. `IsSupported`
checks the required OS interfaces; unavailable interfaces refuse the load.
`HlsLoader` receives all ordinary loads, while the asset key loader receives
`skd://` requests and the legacy key path receives `clearkey://` requests.

Metadata precedes player-item creation and key events. Preload/prepare-to-play
controls when the item reaches the player; live items attach immediately.
Notifications retain their observed values before posting to the owner queue,
so a short buffering dip cannot disappear before delivery. Seeks before item
readiness keep only the latest request. Teardown cancels loads and invalidates
queued callbacks.

The HLS player, timeline, key and sandbox fixtures are described in
[FairPlay tests](../../../tests/FairPlay/README.md).

## HLS assets (FairPlay keys on the native HLS route)

`FairPlayHlsKeyLoader` holds each asset resource-loading request and reports it
before licensing. The attached CDM answers `generateRequest("skd", uri)` using
that request's own SPC; earlier session requests wait for the matching asset
request. The asset is never made a content-key recipient on this route, because
that prevents held requests from generating their own SPC and suppresses legacy
key events on the tested OS.

Each URI is the key identity and content identifier, except a legacy session's
explicit `contentId`. The message and response are raw SPC/CKC. `webkitneedkey`
precedes `encrypted`, and metadata precedes both. A session created before asset
attachment receives a further license request rather than a duplicate encrypted
event. Modern attachment and licensing order may vary.

Resource-loader keys have no `AVContentKey`, so they cannot renew or revoke that
object. Output-protection state comes from AVPlayer. Closing/removing a session
or detaching its CDM before answering leaves its held request pending; the
player does not invent a failure or retry. A cancelled request caused by a seek
can become a new license request. The legacy renewal delegate is not supplied.
See [key routing](../fairplay_chromium/NATIVE_HLS.md#keys).

## Native HLS tracks

`HlsMediaSelection` supplies the GPU service's `FairPlayHlsTrackBridge`; it is
connected to the player and DOM track manager. It disables AVFoundation's
automatic media-selection criteria and applies page choices plus system language
and accessibility preferences.

- Audio options retain stable keys, labels, language, kind and ordering. A page
  enabling one option updates the native selection and subsequent reported state.
- Text options include subtitles, forced and SDH/closed captions. One automatic
  choice follows system caption preferences and enabled audio language. The page
  controls modes; the legible output uses the first showing or last hidden track.
- Chapter tracks expose per-locale WebVTT cues.
- Timed/date-range metadata exposes data cues with the streaming dispatch type;
  open cues end on later data or are removed at seek.
- WebVTT and generic caption cues preserve IDs, timing, styling and changes.
  Seek bracketing flushes open cues and prevents stale updates.

[Native HLS tracks](../fairplay_chromium/NATIVE_HLS.md#tracks) owns the end-to-end
contract. `scripts/test-fairplay-hls-tracks.sh` exercises the core selection and
cue lifecycle; read the script and current execution rules before selecting it.

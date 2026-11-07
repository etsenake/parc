# FairPlay playback core

Engine-independent FairPlay Streaming playback for Parc's second DRM option
(M0). Chromium keeps demuxing the page's media; these classes take the still
encrypted samples with their DecryptConfig and play them through Apple's public
sample-buffer API. Nothing here depends on Chromium: ObjC++ with ARC over
AVFoundation, CoreMedia and AudioToolbox, plus the C++ standard library. Headers
are plain C++ so Chromium `.cc` files can include them. Deployment target is
macOS 13.0; newer APIs are behind `@available`. Not wired into any build yet.

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
  `AVSampleBufferDisplayLayer` and an `AVSampleBufferAudioRenderer` under an
  `AVSampleBufferRenderSynchronizer`.
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
| `Renderer::SetCdm` | `SetCdm(FairPlayCdm*)` (joins the renderers to the CDM's key session) |
| `DemuxerStream::Read` loop | `OnNeedData` + `IsReadyForMoreData` + `Enqueue(EncodedSample)` |
| `DecoderBuffer` + `DecryptConfig` | `EncodedSample` + `DecryptInfo` |
| `StartPlayingFrom` / `SetPlaybackRate` / `SetVolume` / `Flush` / `GetMediaTime` | same names (plus `SetMuted`) |
| `RendererClient::OnWaiting(kNoDecryptionKey)` | `OnWaitingForKey` |
| `OnEnded` / `OnError` / `OnVideoNaturalSizeChange` / `OnBufferingStateChange` | same names |
| compositing (`ca_renderer_layer_tree.mm`) | `display_layer()` (`AVSampleBufferDisplayLayer*`) |
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
  The renderer's `AVSampleBufferDisplayLayer` and `AVSampleBufferAudioRenderer`
  join it with `addContentKeyRecipient:` in `SetCdm`. Both conform to
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
- Recipients must join before they process media and belong to one session,
  so `SetCdm` comes before the first sample and can't move to another CDM.
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
- Dolby Vision arrives as profile and level only. The `dvcC`/`dvvC` is built
  from them, with compatibility ID 0 for profiles 4, 5 and 7, 2 (SDR) for 9,
  and 1 (HDR10) assumed for 8.
- AC-3 and E-AC-3 carry no `dac3`/`dec3`. The box is parsed from the first
  syncframe's header when it is in clear bytes (E-AC-3 substreams grouped by
  type and ID). When the whole sample is encrypted, the box comes from the
  config's sample rate and channel count (6.1 and 7.1 as their 5.1 core), with
  the bit rate written as 0 (CoreMedia decodes such boxes; checked with clear
  AC-3 and E-AC-3).
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
  from Chromium's own test media (tests/FairPlay). No public FairPlay-protected
  sample exists for Dolby Vision, AV1, HE-AAC or xHE-AAC, so only their
  protected format descriptions are checked, not protected decoding. On this M3, VideoToolbox
  hardware-decodes `avc1`, `hvc1`, `dvh1` and `av01`; CoreAudio has protected
  decoders for AAC, HE-AAC, HE-AACv2, xHE-AAC, AC-3 and E-AC-3. AV1 needs M3 or
  later.

## M1 constraints from key delivery

Keys reach the renderer only because its `AVSampleBufferDisplayLayer` and
`AVSampleBufferAudioRenderer` are recipients of the CDM's `AVContentKeySession`
object. `addContentKeyRecipient:` takes the object itself, not an identifier,
so this forces the following on the Chromium integration.

- **One process for the CDM and every renderer using it.** A MediaKeys'
  `FairPlayCdm` and the `FairPlayRenderer` of each media element it is attached
  to must live in the same process, on one sequence. Chromium already has this
  shape on Windows: `MediaFoundationService` hosts `MediaFoundationCdm` and
  `MediaFoundationRenderer` together, and the renderer finds the CDM through
  the in-process `CdmContext`. The FairPlay CDM and renderer should be served
  the same way, as the `media::mojom::ContentDecryptionModule` and
  `media::mojom::Renderer` of one service, with `SetCdm` resolving the
  `cdm_id` within that process.
- **The video layer must be composited from that process.** No `VideoFrame`
  ever exists, so Chromium can only place the layer.
  - In the GPU process (WebKit's choice), the layer can join the
    `CARendererLayerTree` that `ca_renderer_layer_tree.mm` already builds with
    `AVSampleBufferDisplayLayer`s.
  - In a separate service process, it needs remote hosting (a `CAContext` and
    `CALayerHost`, as the GPU process uses towards the browser).
  - In the browser process, Parc's AppKit page host can parent it directly.
  - In every case the video element's rect, clipping, visibility and z-order,
    plus Picture in Picture, must be forwarded to the layer, as
    `MediaFoundationRendererExtension` forwards the output rect on Windows.
    Canvas `drawImage`, WebGL, `captureStream` and `requestVideoFrameCallback`
    on protected video get no pixels.
- **That process's sandbox must allow FairPlay.** SPC generation, decryption
  and protected decode go through system FairPlay and CoreMedia services. The
  harness proves them only unsandboxed; the Chromium sandbox profile of the
  hosting process needs the matching allowances (unverified).
- **The renderer replaces Chromium's decode path for these streams.** Samples
  stay encrypted from the demuxer to `Enqueue`; there is no `media::Decryptor`
  (`CdmContext::GetDecryptor` returns null), no `DecryptingDemuxerStream` and
  no software fallback. The pipeline must choose the FairPlay renderer when a
  `com.apple.fps` CDM is attached, like the MediaFoundation renderer type for
  MediaFoundation CDMs.
- **The CDM is fixed per renderer, from before the first sample.** Recipients
  must join before processing media and can join only one session, so
  `SetCdm` precedes the first encrypted (or clear-lead) sample and can't change
  later. That matches `RendererImpl`, which refuses to change a set CDM. If
  `setMediaKeys` arrives after playback began on another renderer, the
  pipeline must switch renderers rather than retrofit this one.
- **Audio bypasses Chromium's audio stack.** `AVSampleBufferAudioRenderer`
  plays to the system directly: Web Audio `createMediaElementSource` gets
  silence. Volume, mute, audio focus and ducking must map to `SetVolume` and
  `SetMuted`; `setSinkId` maps to `SetAudioOutputDevice` (a Core Audio device
  UID). Empty keeps following the system default until a device is named;
  after that it names the default device of the moment, since
  `audioOutputDeviceUniqueID` throws on nil.
- **The clock is the synchronizer's.** The pipeline reads `GetMediaTime`,
  which may be called from any thread (it reads a retained `CMTimebase`). It
  starts on HAVE_ENOUGH and stops on underflow inside the renderer, as
  `RendererImpl` does.
- **The hosting process must not be napped.** Synchronizer time observers,
  media-data requests and posted callbacks drive end of stream, underflow and
  need-data. In the harness, a covered window playing video alone showed
  seconds-late timers until it opted out of App Nap. Whether Chromium's GPU
  process is ever napped is unverified.
- **Several media elements can share one MediaKeys.** Each renderer's layer
  joins the same session; keys are matched by key ID, so any element can use
  any usable key of that MediaKeys.

## Recovery inside the renderer

- **Automatic audio flushes.** `AVSampleBufferAudioRenderer` flushes itself
  when its output changes (a route or device switch) and reports the start of
  the first sample it dropped. The renderer keeps the audio it enqueued from
  half a second behind the clock on, and enqueues everything from the flush
  time again; otherwise the queued duration would play as silence while the
  clock runs on. A flush time outside what was enqueued since the last Flush
  (a late notice from the previous timeline) is ignored. Proven with a device switch during protected playback (one
  flush, 107 samples re-delivered, no underflow).
- **Video decoder resets.** When `requiresFlushToResumeDecoding` turns on, the
  renderer flushes the video renderer and enqueues again from the last
  keyframe at or before the clock, marking frames already due
  `DoNotDisplay`. No public trigger exists on macOS, so this path is untested.
- `RendererStatus` counts both (`audio_automatic_flushes`,
  `video_decoder_resets`, `redelivered`).
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
- `generateRequest` and `update()` reject after `SetRequestTimeout` seconds
  (default 15) if AVFoundation never answers. A failure for a request
  AVFoundation never provided fails that request's part of the license request.
- A renewal (`update("renew")`, or one AVFoundation starts) runs beside the
  answered request. The answered key stays usable until the renewal succeeds
  (it then replaces the key) or fails (it is dropped).
- A JSON license response is validated entirely before any of it is applied.

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
unchanged), which names no key ID; key statuses report that name, and no
renderer can use the key. WebKit's legacy `com.apple.fps.2_N`
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

`FairPlayHlsPlayer` plays an HLS URL through `AVPlayer`, as Safari does, for
pages that hand the element a playlist instead of using MSE. The GPU
service runs it for Safari-identity pages
([NATIVE_HLS.md](../fairplay_chromium/NATIVE_HLS.md)).

- AVFoundation never fetches by itself: the asset is created with
  `AVURLAssetUseClientURLLoadingExclusively` and its resource loader's
  `URLSession` is the player's stand-in, whose data tasks become
  `HlsLoader::StartLoad` calls (WebKit's SPI, its `WebCoreNSURLSession` does
  the same). `IsSupported()` checks both exist; `Load` refuses otherwise.
- `skd://` key requests go to the CDM's key loader for the asset when one is
  installed (`SetHlsKeyRequestHandler`, between `CreateAsset` and `Start`,
  because the loader must exist before the item routes a request), else to
  the client (`OnKeyRequest`, for every request). A failed key request is
  asked for again rather than failing the item. AVPlayer's
  `outputObscuredDueToInsufficientExternalProtection` reaches the client as
  `OnOutputObscuredChange`.
- `clearkey://` key requests (the legacy `org.w3c.clearkey` key system) go to
  the client the same way; `FulfillKeyRequests` answers them with the raw key
  (WebKit's `fulfillRequestWithKeyData`), and `HlsClearKeyId` gives WebKit's
  key ID for them (the URL's resource specifier).
- State comes from the item: metadata at `readyToPlay`, buffering from
  `playbackLikelyToKeepUp`/`playbackBufferFull`/`playbackBufferEmpty`,
  loaded ranges, presentation size, end, failure (URL errors are network
  errors; others before metadata are unsupported sources, after it decode
  errors). Seeks are exact (zero tolerance).
- Live and DVR timing (`HlsTimeline`, WebKit's
  `MediaPlayerPrivateAVFoundationObjC` with the cache its GPU process keeps
  for the page): the duration is the item's, +infinity when indefinite (live)
  and 0 when invalid, and `OnDurationChange` fires only when it really
  changes (live becoming VOD at `EXT-X-ENDLIST`; never while live). Seekable
  is one window from the smallest start to the largest end of the valid,
  non-empty `seekableTimeRanges`, up to the duration when there are none,
  and empty when its end is 0; it is recomputed when the ranges change and,
  while empty, at each buffering change. `getStartDate()` is
  `round(currentDate − currentTime)` in whole seconds, none without
  `EXT-X-PROGRAM-DATE-TIME`, sampled at metadata and at each buffering change
  (Safari's ready-state changes), reported by `OnStartDateChange` just before
  `OnBufferingStateChange`.
- Threads: one owner sequence; KVO, notifications and resource loader calls
  hop to it. `CurrentTime()` reads the item's timebase from any thread.

Proof: `scripts/test-fairplay-hls.sh` ([harness](../../../tests/FairPlay/hls_player_harness.mm))
runs the player on a serial queue with no run loop and serves the streams
under a host only its loader can reach (`parc-hls.invalid`), so playing proves
every load went through `HlsLoader`. On macOS 27.2 (M3): Apple's TS VOD
(79 loads, exact seek to 300 s, pause holds the clock, ended), Axinom's clear
CMAF fMP4 with alternate audio and subtitle groups, Unified Streaming's live
stream (infinite duration, a ~595 s DVR window, a program date time), a 404
playlist (network error before metadata), an `http://` playlist (App
Transport Security doesn't apply: AVFoundation fetches nothing itself),
`preservesPitch` and rate picking the pitch algorithm, Axinom's FairPlay HLS (the skd URI
reaches the client and never the loader; no key, no playback) and teardown
with loads in flight. The `keys-*` scenarios license Axinom's FairPlay HLS
vectors through `FairPlayHlsKeyLoader` and `FairPlayCdm` on both key routes
("HLS assets"). The `timeline` scenario checks WebKit's timing rules
with no network; `live` also checks the one-range window, a whole-second start
date that matches the wall clock, an exact seek into the DVR window and one to
its end reaching the live edge.

`tests/FairPlay/sandbox` (`--scenarios hls-ts,hls-fmp4`) plays both clear
streams inside Chromium's GPU seatbelt profile with only the MSE route's
FairPlay rules, every load going through the unsandboxed helper.

## HLS assets (FairPlay keys on the native HLS route)

Safari gets an HLS stream's FairPlay keys from AVFoundation asking for each
`EXT-X-KEY` skd URI. `FairPlayHlsKeyLoader` gives pages WebKit's events and
messages for them: the element's `encrypted` (initDataType `skd`, the URI as
UTF-8) when a key is needed and no session asked for it (`OnKeyNeeded`), a raw
SPC with the URI as content identifier (a legacy session's `contentId`
instead), the raw CKC, and key statuses under the URI's bytes. Every loading
request it is handed is also reported (`OnKeyLoadingRequest`), for legacy
pages' `webkitneedkey`.

AVFoundation asks for the keys through the asset's resource loader, which
the player hands to the loader, and Parc keeps it there: the loader holds
each skd request and reports it, and the attached CDM answers the page's
`generateRequest("skd", uri)` with a CKC from the request's own SPC
(`streamingContentKeyRequestDataForApp:`, WebKit's legacy
`CDMSessionAVFoundationObjC`). A `generateRequest` that comes first waits for
the asset to ask. It works whatever order the page attaches MediaKeys and
licenses keys in, and every request raises `webkitneedkey` as in Safari.
WebKit's modern route instead licenses by URI through the
`AVContentKeySession`, then makes the asset a content key recipient and
finishes the held requests; on this macOS a held request finished before its
key is usable never plays, and once the asset is a recipient a still-held
request can neither make an SPC nor be requested through the session, so
that order stalls a key requested before an earlier one was licensed, and a
recipient asset raises no `webkitneedkey` at all
([tests/FairPlay README](../../../tests/FairPlay/README.md#apple-api-behaviour),
"HLS assets").

These keys have no `AVContentKey`: no `renew`, no `revoke`, and output
protection comes from `AVPlayer`'s
`outputObscuredDueToInsufficientExternalProtection` (`SetOutputObscured`),
WebKit's fallback. A loading request gives one SPC, so a session closed or
removed before its answer, or a CDM detached, fails it and AVFoundation asks
again (a new `encrypted`). AVFoundation asking again for a key a session
answered becomes that session's renewal message, and after it cancelled a
taken request (a seek) that session's new license request.

With an asset attached, skd init data is always named by the URI; without
one it keeps the MSE route's plan. A session made for a URI before its asset
was attached gets the asset's request as a further license request instead
of the page getting a second `encrypted` (pages drop duplicate init data).
Legacy `WebKitMediaKeys` sessions (`com.apple.fps`, `1_0`) send
`{"skd": URI, "contentId": base64}` through the same path.

## Native HLS tracks

`HlsMediaSelection` is a port of WebKit's AVFoundation track code
(`MediaPlayerPrivateAVFoundationObjC`'s `tracksChanged`, `updateAudioTracks`,
`processMediaSelectionOptions`, `setCurrentTextTrack` and legible output,
`configureInbandTracks`, `MediaSelectionGroupAVFObjC`,
`AVTrackPrivateAVFObjCImpl`, `InbandTextTrackPrivateAVF(ObjC)`). It is
compiled into the core but not yet called by the GPU service.

- audioTracks: the audible group's playable options (the item's audio tracks
  when there is no group). WebKit, not AVFoundation, picks the option: the
  player's `appliesMediaSelectionCriteriaAutomatically` is NO, and until the
  page enables a track the group follows the user's languages and the
  accessibility audio characteristics (audio descriptions). Ids, kinds,
  labels, languages and indexes come from the asset track WebKit finds for
  the option, else the option, exactly as WebKit derives them (so an id can
  repeat, and `description` is WebKit's audio kind keyword).
- textTracks: the legible group's playable options, numbered from 0 in order
  of discovery; kinds `captions` (closed captions, SDH), `forced` or
  `subtitles`. The legible output serves one track, the first showing, else
  the last hidden; no option is selected until the page shows one. One text
  track is marked `automatic`: the one WebKit's automatic selection shows
  when none is showing (`configureTextTrackGroup` scored by
  `CaptionUserPreferencesMediaAF` from MediaAccessibility's display mode,
  caption languages and SDH preference, the user's languages, and the
  enabled audio track's language; languages matched as WTF does on Cocoa).
- Cues: one `AVPlayerItemLegibleOutput` (2 s advance, player rendering
  suppressed, source and rules styling) with WebVTT as native samples. WebVTT
  arrives as ISO WebVTT cue boxes (`kWebVtt`, plus the `vttC` header once per
  track); everything else (CEA-608/708, other formats) as generic cues added
  open-ended and completed, extended or, on a seek or output flush, removed
  as WebKit does. The page side turns them into `VTTCue`s.

Proof: `scripts/test-fairplay-hls-tracks.sh`
([harness](../../../tests/FairPlay/hls_media_selection_harness.mm)) runs the
selection on a serial queue with no run loop over Apple's
`bipbop_16x9_variant` (two audio renditions, eight WebVTT subtitle options
with forced ones) and `img_bipbop_adv_example_fmp4` (CEA-608 CC1): the track
lists, kinds, labels, languages and defaults; WebKit's automatic audio
choice; enabling audio 2 selecting its option and audio 1 then reporting
disabled; show/hide/disable picking the legible option; WebVTT and CEA-608
cues with their timing; a seek flushing the open caption; teardown with cues
flowing.

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
- `fairplay_init_data.{h,mm}`: skd, sinf, cenc and keyids init data, mirroring
  WebKit's FairPlay CDM.
- `fairplay_renderer.{h,mm}`: `FairPlayRenderer`, an
  `AVSampleBufferDisplayLayer` and an `AVSampleBufferAudioRenderer` under an
  `AVSampleBufferRenderSynchronizer`.
- `fairplay_bitstream.{h,cc}`: Annex B and ADTS reframing, subsample
  bookkeeping, and the `tenc`/`sinf`/`esds` bytes.
- `fairplay_key_session_internal.h`: content key recipient attachment for the
  renderer (ObjC++ only).

## Mapping onto Chromium (M1)

| Chromium | Core |
| --- | --- |
| `ContentDecryptionModule::SetServerCertificate` | `FairPlayCdm::SetServerCertificate` |
| `CreateSessionAndGenerateRequest` | `CreateSessionAndGenerateRequest(InitDataType, init_data)` |
| `UpdateSession` / `CloseSession` / `RemoveSession` | same names |
| `ContentDecryptionModuleClient` (`OnSessionMessage`, `OnSessionKeysChange`, `OnSessionClosed`) | `FairPlayCdmClient` |
| `Renderer::Initialize` (decoder configs) | `FairPlayRenderer::Initialize(VideoConfig, AudioConfig)` |
| `Renderer::SetCdm` | `SetCdm(FairPlayCdm*)` (joins the renderers to the CDM's key session) |
| `DemuxerStream::Read` loop | `OnNeedData` + `IsReadyForMoreData` + `Enqueue(EncodedSample)` |
| `DecoderBuffer` + `DecryptConfig` | `EncodedSample` + `DecryptInfo` |
| `StartPlayingFrom` / `SetPlaybackRate` / `SetVolume` / `Flush` / `GetMediaTime` | same names (plus `SetMuted`) |
| `RendererClient::OnWaiting(kNoDecryptionKey)` | `OnWaitingForKey` |
| `OnEnded` / `OnError` / `OnVideoNaturalSizeChange` / `OnBufferingStateChange` | same names |
| compositing (`ca_renderer_layer_tree.mm`) | `display_layer()` (`AVSampleBufferDisplayLayer*`) |

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
  `com.apple.fps.<version>`, as WebKit does. The legacy prefixed
  `WebKitMediaKeys` that Netflix also probes (`com.apple.fps.2_0`) has no
  Chromium counterpart.
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

skd and sinf sessions exchange the raw SPC and CKC. cenc and keyids sessions
exchange JSON arrays of `{"keyID", "payload"}` entries (WebKit's cenc format;
a response entry may carry `"error"` instead). `UpdateSession` with the literal
`renew` requests a renewal message, as in WebKit.

The SPC's content identifier follows WebKit: the whole skd URI as UTF-8 for skd,
the raw 16-byte key ID for sinf and FairPlay pssh requests (and, as a Parc
extension, for keyids and for cenc without a FairPlay pssh, which requests the
key IDs the other pssh boxes name).

## Apple API behaviour

See [tests/FairPlay/README.md](../../../tests/FairPlay/README.md#apple-api-behaviour)
for what the proof established.

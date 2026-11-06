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

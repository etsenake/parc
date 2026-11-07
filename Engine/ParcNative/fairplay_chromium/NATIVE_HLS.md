# Native HLS (Safari's second FairPlay route)

Status: design, nothing built. Owners: `fp-native-hls` (routing, the AVPlayer
host, network, media element state and events), `fp-hls-keys` (skd in the
CDM, the asset's content keys, modern EME), `fp-hls-display` (display, PiP and
fullscreen, frame counts, audio and text tracks, live/DVR ranges). Interface
changes go into this file first.

Safari plays `<video src="….m3u8">` through `AVPlayer` (WebKit's
`MediaPlayerPrivateAVFoundationObjC`) and FairPlay HLS keys through
`AVContentKeySession`. Parc's MSE route (the [core](../fairplay/README.md) and
[README.md](README.md)) only takes demuxed samples. Under Safari's identity
TELUS TV+ (Shaka 4.15.5) hands the element an HLS URL with
`EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://…"`; Chromium's built-in HLS player
takes it and fails fetching `skd://` as a URL.

## Switch

Until every piece below is on main, the route is off: `DemuxerManager` keeps
choosing Chromium's `ManifestDemuxer`, exactly as today. One constant,
`parc::fairplay::kNativeHlsEnabled` (`fairplay_key_system.h`), turns it on;
the last piece flips it. Every piece lands compiled but unreachable.

## Process: the GPU process

`AVPlayer` lives in the GPU process, on the media service thread, next to the
FairPlay CDM and renderer. Why:

- Keys reach an `AVURLAsset` only as a content key recipient of the CDM's
  `AVContentKeySession` (`addContentKeyRecipient:` takes the object), so the
  asset must be in the CDM's process. The CDM is in the GPU process.
- `ui::ProtectedLayerRegistry` and `CARendererLayerTree` are in the GPU
  process: an `AVPlayerLayer` is placed exactly as the MSE route's
  `AVSampleBufferDisplayLayer`, with no remote layer hosting.
- It is WebKit's model: its GPU process runs `AVPlayer` with no network access
  of its own and loads everything through `WebCoreNSURLSession`, which asks
  the web process to fetch.
- The sandbox rules FairPlay needs are already in `gpu.sb`.

The GPU sandbox has no network, and none is added. AVFoundation's loads go
through a client URL session, as in WebKit: the asset is created with
`AVURLAssetUseClientURLLoadingExclusively = YES` and its
`resourceLoader.URLSession` is Parc's `NSURLSession` stand-in (both SPI; both
present on macOS 27.2, checked with `dlsym`/`respondsToSelector:`). Each task
it creates is a load request sent to the render process (Network below).
Whether AVFoundation sends every load (playlists, segments, keys' certificate
fetches) there on macOS is the first thing `fp-native-hls` proves with a
harness; the public fallback is a custom-scheme `AVAssetResourceLoader`
delegate that rewrites playlist URIs. Extra mach services AVPlayer needs in
the GPU sandbox (beyond the MSE route's) are proven with
`tests/FairPlay/sandbox`.

Rejected: the browser process plus `CAContext`/`CALayerHost` into the
registry, or a separate media process. Either moves the CDM out of the GPU
process (the asset must share its session), adds remote layer hosting for
every frame, and still has to fetch through the page's loader to get CORS and
DevTools attribution right.

## Routing (render process)

- `HTMLMediaElement` tells its player whether the document presents Safari's
  identity (`IsParcSafariIdentityUserAgent`, as the rest of
  fairplay-identity): a new `WebMediaPlayerClient::ParcPresentsSafariIdentity()`.
- `DemuxerManager::CreateDemuxer` takes its HLS branch as today (path ends in
  `.m3u8`, or `DEMUXER_ERROR_DETECTED_HLS` from FFmpeg's sniffing). With the
  switch on and Safari's identity, it creates `parc::fairplay::NativeHlsDemuxer`
  instead of `ManifestDemuxer`. `canPlayType` keeps answering "maybe".
- M156 has no `MediaUrlDemuxer` and `mojom::Renderer.Initialize` takes streams
  only, and `PipelineImpl` creates the renderer after the demuxer has reported
  metadata. So the demuxer owns the player connection:
  `NativeHlsDemuxer::Initialize` opens the GPU player, waits for its metadata
  and exposes one placeholder `DemuxerStream` per kind (audio, video) whose
  config carries the codec and natural size AVFoundation reports. They never
  deliver buffers.
- The renderer is a render-process facade, `NativeHlsRenderer`
  (`media::Renderer`, media thread), that drives the demuxer's player. The
  pipeline gets it from the demuxer: a new `Demuxer::CreateNativeRenderer()`
  (default null) checked first in `PipelineImpl::RendererWrapper::CreateRenderer`.
  Suspend/resume destroy and recreate only the facade.
- `PipelineImpl::RendererWrapper::SetCdm` also hands the `CdmContext` to the
  demuxer (`Demuxer::SetCdmForNativePlayer`, default no-op) so a CDM set before
  the renderer exists reaches the player at once.

## Mojo

New interfaces in `media/mojo/mojom/renderer_extensions.mojom`, beside
`FairPlayRendererClientExtension`, module `media.mojom`:

```
// InterfaceFactory (render process → browser MediaInterfaceProxy → the
// frame's GPU InterfaceFactoryImpl, the one holding its CDMs):
CreateFairPlayHlsPlayer(pending_receiver<FairPlayHlsPlayer> player,
                        pending_remote<FairPlayHlsPlayerClient> client);

struct FairPlayHlsLoadRequest {
  url.mojom.Url url; string method;
  map<string, string> headers;      // Range, Accept, X-Playback-Session-Id…
};
struct FairPlayHlsLoadResponse {
  int32 http_status; string mime_type; int64 content_length;  // -1 unknown
  url.mojom.Url final_url;          // after redirects
};
interface FairPlayHlsLoad {          // render process implements, per load
  Cancel();
};
interface FairPlayHlsLoadClient {    // GPU implements, per load
  OnResponse(FairPlayHlsLoadResponse response,
             handle<data_pipe_consumer> body);
  OnComplete(int32 net_error);       // net::OK or a net error
};

struct FairPlayHlsTrack {
  string id; string kind; string label; string language;
  bool enabled; DemuxerStream.Type type;   // AUDIO, VIDEO or TEXT
};
struct FairPlayHlsMetadata {
  bool has_audio; bool has_video; gfx.mojom.Size natural_size;
  AudioCodec audio_codec; VideoCodec video_codec;   // kUnknown if not given
  mojo_base.mojom.TimeDelta duration;  // TimeDelta::Max() = live (Infinity)
  mojo_base.mojom.Time? start_date;    // EXT-X-PROGRAM-DATE-TIME at time 0
  array<MediaTimeRange> seekable;      // seekableTimeRanges (DVR window)
  array<FairPlayHlsTrack> tracks;
};

interface FairPlayHlsPlayer {        // GPU implements
  Initialize(url.mojom.Url url, string mime_type)
      => (bool success, FairPlayHlsMetadata? metadata);
  SetCdm(mojo_base.mojom.UnguessableToken cdm_id) => (bool success);
  Play(double rate); Pause();
  Seek(mojo_base.mojom.TimeDelta time) => (bool success);
  SetVolume(float volume); SetMuted(bool muted);
  SelectAudioTrack(string id); SelectTextTrack(string? id);
  Suspend(); Resume();               // stop/restart loading (preload, idle)
};

interface FairPlayHlsPlayerClient {  // render process implements
  StartLoad(FairPlayHlsLoadRequest request,
            pending_receiver<FairPlayHlsLoad> load,
            pending_remote<FairPlayHlsLoadClient> client);
  OnTimeUpdate(mojo_base.mojom.TimeDelta time, double rate,
               mojo_base.mojom.TimeTicks capture_time);
  OnBufferingStateChange(BufferingState state);
  OnBufferedRangesChanged(array<MediaTimeRange> loaded);
  OnSeekableRangesChanged(array<MediaTimeRange> seekable);
  OnDurationChange(mojo_base.mojom.TimeDelta duration);
  OnTracksChanged(array<FairPlayHlsTrack> tracks);
  OnTextCues(string track_id, array<FairPlayHlsCue> cues);  // fp-hls-display
  OnNaturalSizeChange(gfx.mojom.Size size);
  OnLayerRegistered(mojo_base.mojom.UnguessableToken token,
                    gfx.mojom.Size natural_size);
  OnStatisticsUpdate(PipelineStatistics delta);
  OnEncrypted(string init_data_type, array<uint8> init_data);
  OnWaiting(WaitingReason reason);    // kNoDecryptionKey
  OnEnded();
  OnError(PipelineStatus status, string message);
};
```

`fp-hls-display` defines `FairPlayHlsCue` here when it gets there.

## Network (render process)

`NativeHlsDemuxer` serves `StartLoad` through the built-in HLS player's own
fetch layer, `WebMediaPlayerImpl::GetHlsDataSourceProvider()`
(`MultiBufferDataSource` on the frame's `UrlIndex`, with the element's CORS
mode). So AVFoundation's loads carry the page's cookies, referrer and
credentials mode, pass CORS, use the profile's proxy and appear in DevTools as
the element's media requests. `Range` headers map to the provider's byte
ranges; the response's MIME type is the server's `Content-Type`. Redirects are
followed in the render process; `final_url` tells AVFoundation the URL that
relative playlist URIs resolve against. `skd://` URIs never reach
`StartLoad` (Keys).

## Keys

The player's `AVAssetResourceLoader` delegate sees `skd://` key requests
(AVFoundation can't load that scheme). It follows WebKit
(`MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource`,
`attemptToDecryptWithInstance`):

1. No CDM yet: keep the loading request, send
   `OnEncrypted("skd", <URI as UTF-8>)` and `OnWaiting(kNoDecryptionKey)`.
   The render process raises `encrypted` (initDataType `"skd"`) and
   `waitingforkey`; `fp-safari-eme-surface` turns the same call into
   `webkitneedkey` with WebKit's legacy layout (4-byte little-endian length,
   then the URI as UTF-16).
2. `SetCdm(cdm_id)` resolves the frame's `FairPlayCdm` through
   `CdmContext::GetFairPlayCdm()`. The player registers with the core:
   `FairPlayCdm::AttachAsset(AVURLAsset*, AssetKeyClient*)` /
   `DetachAsset`, on the CDM's sequence (`fp-hls-keys` defines it).
3. The page's `generateRequest("skd", uri)` names the request by the URI
   (`processContentKeyRequestWithIdentifier:uri`, content identifier = the
   URI, as WebKit) whenever an asset is attached, instead of the MSE route's
   synthesized pssh. `update(ckc)` makes the key usable.
4. When a usable key covers a pending URI, the core calls
   `AssetKeyClient::OnKeyUsable(uri)`; the player adds the asset as a
   recipient of the session (`addContentKeyRecipient:`), sets each pending
   request's `contentInformationRequest.contentType =
   AVStreamingKeyDeliveryContentKeyType`, `finishLoading`s it and sends
   `OnWaiting` clear (playback resumes). AVFoundation then takes the key from
   the session.
5. An skd request after the CDM is attached is finished at once the same way.
   A key request the session gets that no EME session asked for (a new key
   mid-stream) is parked by the core and reported as
   `AssetKeyClient::OnUnrequestedKey("skd", uri)` → `OnEncrypted`; the page's
   `generateRequest` with that URI takes the parked request (WebKit's
   `takeUnexpectedKeyRequestForInitializationData`).

Chromium's `EmeInitDataType` has no `skd`: `fp-hls-keys` adds
`EmeInitDataType::SKD` and its `"skd"` string, unless
`fp-safari-eme-surface` lands it first.

## Display

The GPU player makes one `AVPlayerLayer` for its `AVPlayer`, registers it in
`ui::ProtectedLayerRegistry` under a new `base::UnguessableToken` before the
token leaves the process, and sends `OnLayerRegistered(token, natural_size)`.
`NativeHlsRenderer` paints `VideoFrame::CreateVideoHoleFrame(token,
natural_size)` through its `VideoRendererSink::PaintSingleFrame`, again on
every natural-size change, exactly like `FairPlayRendererClient`. cc makes a
`VideoHoleDrawQuad` and fairplay-compositing places the layer there, so
scrolling, clipping, PiP and fullscreen behave as for MSE playback. Teardown
unregisters the layer before the player goes.

## Media element state and events

`AVPlayerItem` is the authority, as in Safari; the render process mirrors it.

| Element | Source in the GPU | Render-process path |
| --- | --- | --- |
| `HAVE_METADATA` | item `readyToPlay` | `Initialize` reply → demuxer init → pipeline metadata |
| `HAVE_ENOUGH` / underflow | `playbackLikelyToKeepUp` / `playbackBufferEmpty` | `OnBufferingStateChange` → facade's `RendererClient` |
| `currentTime` | `currentTime`, periodic observer | `OnTimeUpdate` → facade's `GetMediaTime` interpolates |
| `duration` | `duration` (indefinite = live) | demuxer's `DemuxerHost::SetDuration` (`kInfiniteDuration`) |
| `buffered` | `loadedTimeRanges` | `DemuxerHost::OnBufferedTimeRangesChanged` |
| `seekable` | `seekableTimeRanges` | demuxer; `WebMediaPlayerImpl::Seekable()` asks it for this demuxer type (today live gives empty) |
| `getStartDate()` | `currentDate` − `currentTime` | `Demuxer::GetTimelineOffset()` |
| seeking/seeked | `seekToTime:completionHandler:` | `Demuxer::Seek` / facade `StartPlayingFrom` |
| rate, pause | `rate` | facade `SetPlaybackRate` → `Play`/`Pause` |
| volume, muted | `volume`, `muted` | facade `SetVolume`; tab mute as the MSE route |
| `ended` | `AVPlayerItemDidPlayToEndTimeNotification` | `OnEnded` |
| `error` | item `failed`, `AVPlayerItemFailedToPlayToEndTime`, error log | `OnError` → `MEDIA_ERR_NETWORK` / `DECODE` / `SRC_NOT_SUPPORTED` as Safari maps them |
| `audioTracks` / `textTracks` | `AVMediaSelectionGroup`s, legible output | `OnTracksChanged` → `DemuxerManager`'s track manager; cues by `OnTextCues` |
| decoded/dropped frames | access log / video metrics | `OnStatisticsUpdate` (as fp-frame-stats) |
| `encrypted`, `waitingforkey` | resource loader skd requests | `OnEncrypted`, `OnWaiting` |

## Threads

GPU: the player runs on the media service thread (no run loop). KVO,
notifications, the periodic time observer and resource loader callbacks
arrive on AVFoundation's queues and hop to that thread with the core's
`PostTask` (`fairplay_task_runner.h`). Render process: the demuxer, facade and
loads run on the media thread; `encrypted` and track changes reach the element
through `DemuxerManager` on the main thread, as the built-in HLS player's do.

## Pieces, in landing order

1. This design. 2. Routing, switch off. 3. GPU player with clear HLS and
network through Chromium (harness first). 4. Display (`fp-hls-display`).
5. skd keys and modern EME (`fp-hls-keys`). 6. Live/DVR, tracks, frame counts.
7. Switch on, docs (`docs/fairplay-identity.md` known limits, READMEs).

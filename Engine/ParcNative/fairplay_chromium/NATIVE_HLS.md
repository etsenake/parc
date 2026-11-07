# Native HLS (Safari's second FairPlay route)

Status: design; pieces landing. Owners: `fp-native-hls` (the GPU core player,
`Engine/ParcNative/fairplay/fairplay_hls_player.*`), `fp-hls-render` (the
render-process route: Blink, `DemuxerManager`, `NativeHlsDemuxer`, the
`NativeHlsRenderer` facade, pipeline hooks, element state), `fp-hls-mojo`
(mojo interfaces, `InterfaceFactory`, the GPU service wrapping the core, the
render-process loader), `fp-hls-keys` (skd in the CDM, the asset's content
keys, modern EME), `fp-hls-display` (display, PiP and fullscreen, frame
counts), `fp-hls-tracks` (audio and text tracks), `fp-hls-live` (live and DVR
timing). Interface changes go into this file first.

Safari plays `<video src="….m3u8">` through `AVPlayer` (WebKit's
`MediaPlayerPrivateAVFoundationObjC`) and FairPlay HLS keys through
`AVContentKeySession`. Parc's MSE route (the [core](../fairplay/README.md) and
[README.md](README.md)) only takes demuxed samples. Under Safari's identity
TELUS TV+ (Shaka 4.15.5) hands the element an HLS URL with
`EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://…"`; Chromium's built-in HLS player
takes it and fails fetching `skd://` as a URL.

## Switch

Until every piece below is on main, the route is off: `DemuxerManager` keeps
choosing Chromium's `ManifestDemuxer`, exactly as today. One build-time
constant, `parc::fairplay::kNativeHlsEnabled` (`fairplay_key_system.h`,
false), gates it; the last piece flips it to true. It is never a runtime,
command-line or Finch switch (Josh's rule for FairPlay). Every piece lands
compiled but unreachable. The same constant makes the Safari-identity script
installer (`fairplay-identity-blink.patch`) turn `/*PARC_NATIVE_HLS*/false` into
`true` in `Engine/ParcRenderer/parc_webkit_media_keys.h`, which then offers
WebKit's legacy AVFoundation-player key systems (`com.apple.fps`,
`com.apple.fps.1_0`, `org.w3c.clearkey`) on `WebKitMediaKeys`.

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
  switch on and Safari's identity, it asks its client
  (`DemuxerManager::Client::CreateParcNativeHlsDemuxer`, default null) and
  uses that demuxer instead of `ManifestDemuxer`. `canPlayType` keeps
  answering "maybe".
- `WebMediaPlayerImpl` gets the demuxer from the factory registered for
  `RendererType::kFairPlayHls` (`RendererFactorySelector::GetFactory`, a new
  `RendererFactory::CreateParcNativeHlsDemuxer` hook), which `MediaFactory`
  adds next to the FairPlay renderer factory and which holds the frame's
  `InterfaceFactory`. The demuxer and facade live in
  `//content/renderer/media/fairplay` beside `FairPlayRendererClient`.
- M156 has no `MediaUrlDemuxer` and `mojom::Renderer.Initialize` takes streams
  only, and `PipelineImpl` creates the renderer after the demuxer has reported
  metadata. So the demuxer owns the player connection:
  `NativeHlsDemuxer::Initialize` opens the GPU player, waits for its metadata
  and exposes one placeholder `DemuxerStream` per kind (audio, video) whose
  config carries the codec and natural size AVFoundation reports. They never
  deliver buffers.
- The renderer is a render-process facade, `NativeHlsRenderer`
  (`media::Renderer`, media thread), that drives the demuxer's player.
  `PipelineImpl::RendererWrapper::CreateRenderer` asks for
  `RendererType::kFairPlayHls` when the demuxer is a native HLS demuxer (a
  `MediaResource::GetParcNativeHlsSource()` hook, default null), so the facade
  comes from the same factory with the element's `VideoRendererSink` for the
  hole frame. Its `Initialize` binds to the demuxer's player through that
  hook. Suspend/resume destroy and recreate only the facade.
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
  mojo_base.mojom.Time? start_date;    // getStartDate() (Live and DVR)
  array<MediaTimeRange> seekable;      // one window or none (Live and DVR)
  array<FairPlayHlsTrack> tracks;
};

interface FairPlayHlsPlayer {        // GPU implements
  Initialize(url.mojom.Url url, string mime_type)
      => (bool success, FairPlayHlsMetadata? metadata);
  SetCdm(mojo_base.mojom.UnguessableToken cdm_id) => (bool success);
  Play(double rate); Pause();
  Seek(mojo_base.mojom.TimeDelta time) => (bool success);
  SetVolume(float volume); SetMuted(bool muted);
  SetPreservesPitch(bool preserves_pitch);   // Renderer::SetPreservesPitch
  ProvideClearKey(string key_id, array<uint8> key);  // legacy clear key
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
  OnStartDateChanged(mojo_base.mojom.Time? start_date);  // before
                                     // the OnBufferingStateChange it goes with
  OnTracksChanged(array<FairPlayHlsTrack> tracks);
  OnTextCues(string track_id, array<FairPlayHlsCue> cues);  // fp-hls-display
  OnNaturalSizeChange(gfx.mojom.Size size);
  OnLayerRegistered(mojo_base.mojom.UnguessableToken token,
                    gfx.mojom.Size natural_size);
  OnStatisticsUpdate(PipelineStatistics delta);
  OnEncrypted(string init_data_type, array<uint8> init_data);
  OnClearKeyNeeded(string key_id);    // legacy clear key (Keys)
  OnWaiting(WaitingReason reason);    // kNoDecryptionKey
  OnEnded();
  OnError(PipelineStatus status, string message);
};
```

`fp-hls-display` defines `FairPlayHlsCue` here when it gets there.

## GPU core player

`parc::fairplay::FairPlayHlsPlayer` (`Engine/ParcNative/fairplay/fairplay_hls_player.h`,
with `fairplay_hls_timeline.{h,cc}`, which the core's build target lists with
it; [core README](../fairplay/README.md#native-hls-player)) is the engine-free
player the GPU service owns, on the media service thread with the core's
`PostTask`:

| Core | Mojo (GPU service) |
| --- | --- |
| `HlsLoader::StartLoad(request, HlsLoadClient*)` → `HlsLoad` (destroy = cancel) | `FairPlayHlsPlayerClient.StartLoad` → `FairPlayHlsLoad` (reset = `Cancel`) |
| `HlsLoadClient::OnResponse` / `OnData` / `OnComplete(net_error)` | `FairPlayHlsLoadClient.OnResponse` + data pipe reads / `OnComplete` |
| `CreateAsset(url, mime)` + `Start()` (or `Load`), `SetRate`, `Seek(s, done)`, `SetVolume`, `SetMuted`, `SetPreservesPitch` | `Initialize`, `Play`/`Pause`, `Seek`, `SetVolume`, `SetMuted`, `SetPreservesPitch` |
| `HlsPlayerClient::OnMetadata` (once, `readyToPlay`) | `Initialize` reply |
| `OnBufferingStateChange`, `OnLoadedRangesChange`, `OnSeekableRangesChange`, `OnDurationChange`, `OnStartDateChange`, `OnNaturalSizeChange`, `OnEnded`, `OnError` | the client calls of the same meaning |
| `SetHlsKeyRequestHandler` (between `CreateAsset` and `Start`) → the CDM's key loader takes skd requests | its `OnKeyNeeded(uri)` → `OnEncrypted("skd", uri)` (Keys) |
| `OnOutputObscuredChange(bool)` | the key loader's `SetOutputObscured` |
| `OnKeyRequest(clearkey uri)`, `FulfillKeyRequests(uri, key)`, `HlsClearKeyId` | `OnClearKeyNeeded(key_id)` / `ProvideClearKey(key_id, key)` |
| `CurrentTime()` (any thread), `Rate()` | `OnTimeUpdate` |
| `HlsPlayerAsset` / `HlsPlayerLayer` (`fairplay_hls_player_internal.h`) | `addContentKeyRecipient:` (Keys) / `ProtectedLayerRegistry` (Display) |

The core never blocks on the embedder and never calls the client inside a call
into it. Facts the harness established: every load AVFoundation makes goes to
`HlsLoader` (a host only the loader can reach still plays); AVFoundation asks
again for a key whose request failed instead of failing the item; a live
variant that 404s makes it retry silently, with no item error; an `http://`
playlist plays (App Transport Security doesn't apply to client loads). The
GPU-sandbox probe plays native HLS with only the MSE route's sandbox rules.

## Network (render process)

`StartLoad` runs one `blink::WebAssociatedURLLoader` per load on the main
thread, made by the element's `ResourceFetchContext` (the factory
`ResourceMultiBufferDataProvider` uses for every `<video src>` load), with the
element's CORS mode and credentials. So AVFoundation's loads carry the page's
cookies and referrer, pass CORS, use the profile's proxy and appear in DevTools
as the element's media requests. The real status, headers and MIME type go
back to AVFoundation. Of AVFoundation's request headers only `Range` is
forwarded: its own `User-Agent` (AppleCoreMedia) and `X-Playback-Session-Id`
would make cross-origin CORS loads preflight, and the page's identity UA is
sent instead. Redirects are followed in the render process (cross-origin ones
only in CORS mode, as for any media load); `final_url` tells AVFoundation the
URL that relative playlist URIs resolve against. Bodies stream back over the
load's data pipe. `skd://` URIs never reach `StartLoad` (Keys).

## Keys

How the GPU service wires keys: after `FairPlayHlsPlayer::CreateAsset` it
creates the CDM's key loader for the asset (`FairPlayHlsKeyLoader`, from
`fp-hls-keys`) with the attached CDM if any, installs it with
`SetHlsKeyRequestHandler`, then calls `Start`; it forwards the loader's
`OnKeyNeeded(uri)` as `OnEncrypted("skd", uri)` plus
`OnWaiting(kNoDecryptionKey)`, `SetCdm` to the loader, and the player's
`OnOutputObscuredChange` to its `SetOutputObscured`. The key loader's tests
showed that a request held on the resource loader can't be finished for the
session afterwards (it never plays), so the loader decides at creation
whether the asset is a content key recipient and answers held requests with
their own SPC/CKC otherwise; where the steps below differ, the key loader's
header is right.

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

`EmeInitDataType::SKD` and its `"skd"` string are on main (7c317739,
`fp-safari-eme-surface`).

### Legacy clear key (`clearkey://`)

WebKit's player also answers `clearkey://` key requests, for the legacy
`org.w3c.clearkey` key system (`CDMSessionClearKey`, in
`parc_webkit_media_keys.h` behind the same switch). Safari raises no
`encrypted` event for them, only `webkitneedkey`:

1. The core reports the request (`HlsPlayerClient::OnKeyRequest(uri)`, scheme
   `clearkey`). The GPU service sends
   `FairPlayHlsPlayerClient.OnClearKeyNeeded(key_id)` with
   `HlsClearKeyId(uri)` (WebKit's key ID: the URL's resource specifier),
   keeping key ID → URI.
2. The render process raises `webkitneedkey` on the element with the key ID
   as UTF-8 (WebKit's `keyNeeded(initData)`), never an `encrypted` event.
3. When the page's legacy session takes a JWK set (`keysAdded` in the
   script), the element side gives every held key ID the script has a key
   for back to the player: `FairPlayHlsPlayer.ProvideClearKey(key_id, key)` →
   `FairPlayHlsPlayer::FulfillKeyRequests(uri, key)`, which answers the
   requested byte range of the raw key (WebKit's `fulfillRequestWithKeyData`)
   and answers later requests for that URI the same way.

The bridge between the page-world script and the element (raising
`webkitneedkey` from the player's call; the script's `keysAdded` reaching
`WebMediaPlayer`) belongs to the legacy element side
(`fp-safari-eme-surface`) with `fp-hls-render`; the mojo calls to
`fp-hls-mojo`.

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

The compositor fills an `AVPlayerLayer` like the MSE layer, with Resize
gravity (cc already laid the quad out at the video's aspect ratio). It sets no
capture flag: AVFoundation keeps FairPlay video from an `AVPlayer` out of
screenshots and screen sharing by itself, and clear HLS stays capturable, as
in Safari. `tests/FairPlay/hls_presentation` (Display) proves on this Mac that
a layer made on a queue with no run loop renders, fills its host, and keeps
playing when moved between windows' hosts (PiP), back, and after a spell in no
tree (a hidden tab).

## Media element state and events

`AVPlayerItem` is the authority, as in Safari; the render process mirrors it.

| Element | Source in the GPU | Render-process path |
| --- | --- | --- |
| `HAVE_METADATA` | item `readyToPlay` | `Initialize` reply → demuxer init → pipeline metadata |
| `HAVE_ENOUGH` / underflow | `playbackLikelyToKeepUp` / `playbackBufferEmpty` | `OnBufferingStateChange` → facade's `RendererClient` |
| `currentTime` | `currentTime`, periodic observer | `OnTimeUpdate` → facade's `GetMediaTime` interpolates |
| `duration` | `duration` (indefinite = live), Live and DVR | demuxer's `DemuxerHost::SetDuration` (`kInfiniteDuration`) |
| `buffered` | `loadedTimeRanges` | `DemuxerHost::OnBufferedTimeRangesChanged` |
| `seekable` | `seekableTimeRanges` as one window, Live and DVR | demuxer's `GetParcNativeTimeline()`; `WebMediaPlayerImpl::Seekable()` answers it |
| `getStartDate()` | `round(currentDate − currentTime)`, Live and DVR | demuxer's `GetParcNativeTimeline()`; `WebMediaPlayer::ParcStartDate()` |
| seeking/seeked | `seekToTime:completionHandler:` | `Demuxer::Seek` / facade `StartPlayingFrom` |
| rate, pause | `rate` | facade `SetPlaybackRate` → `Play`/`Pause` |
| volume, muted | `volume`, `muted` | facade `SetVolume`; tab mute as the MSE route |
| `ended` | `AVPlayerItemDidPlayToEndTimeNotification` | `OnEnded` |
| `error` | item `failed`, `AVPlayerItemFailedToPlayToEndTime`, error log | `OnError` → `MEDIA_ERR_NETWORK` / `DECODE` / `SRC_NOT_SUPPORTED` as Safari maps them |
| `audioTracks` / `textTracks` | `AVMediaSelectionGroup`s, legible output | `OnTracksChanged` → `DemuxerManager`'s track manager; cues by `OnTextCues` |
| decoded/dropped frames | `-[AVPlayerLayer videoPerformanceMetrics]` (`HlsFrameStats`) | `OnStatisticsUpdate` deltas (as fp-frame-stats) |
| `encrypted`, `waitingforkey` | resource loader skd requests | `OnEncrypted`, `OnWaiting` |

## Frame counts

`getVideoPlaybackQuality()`, `webkitDecodedFrameCount` and
`webkitDroppedFrameCount` come from WebKit's source for an `AVPlayer`,
`-[AVPlayerLayer videoPerformanceMetrics]` (SPI; the object answers WebKit's
`totalNumberOfVideoFrames`/`numberOfDroppedVideoFrames` and, from macOS 14.4,
the public `totalNumberOfFrames`/`numberOfDroppedFrames`). The core's
`HlsFrameStats` (`fairplay/fairplay_hls_frame_stats.h`) owns the polling: the
player creates it with its `AVPlayerLayer` and its `PostTask`, calls
`SetPlaying(started && rate > 0)` on every play, pause, rate change, seek and
end, and forwards each `FrameCountDelta` as `OnStatisticsUpdate`
(`video_frames_decoded`, `video_frames_dropped`), which `PipelineImpl` adds
up as for the MSE route. It reads on its own serial queue every 250 ms while
playing, because the call can block (WebKit reads it on a background queue),
counts once more on stopping, and never reports after it is destroyed.

Unlike an `AVSampleBufferDisplayLayer`'s, this count restarts when
AVFoundation rebuilds its decoder (seen once on a variant switch, 178 → 75):
a reading with either count below the previous one is a new run and both of
its counts are added in full, where the MSE adapter's rule (a smaller total
adds nothing) would stall the counts until the new run passed the old total.
An all-zero reading (nothing decoded yet, or no player) is skipped, so it
can't be taken for a restart. The class holds the layer weakly and drops its
callback on the owner sequence when destroyed. Bytes decoded stay 0, as Safari's AVPlayer
route reports none. One difference from Safari, kept on purpose: its
`MediaPlayerPrivateAVFoundationObjC` has no `decodedFrameCount()`, so
`webkitDecodedFrameCount` reads 0 there for HLS, while in Parc it advances
with `getVideoPlaybackQuality()` because Chromium reads both from the same
statistics, as for the MSE route.

## Live and DVR

`HlsTimeline` (`fairplay/fairplay_hls_timeline.h`) gives the GPU player
WebKit's rules (`MediaPlayerPrivateAVFoundationObjC`), with the cache Safari's
GPU process (`RemoteMediaPlayerProxy`) keeps for the page:

- `duration`: the item's, +Infinity when indefinite (live), 0 when invalid.
  `durationchange` fires at `loadedmetadata` and then only when the value
  really changes: never while live, once when a live playlist gains
  `EXT-X-ENDLIST`. A live stream's duration never shrinks at its end.
- `seekable`: one range from the smallest start to the largest end of the
  valid, non-empty `seekableTimeRanges` (start 0 when none is valid), up to
  the duration when AVFoundation lists none ([0, Infinity) for live), and no
  range when its end is 0. It changes with the ranges; while it is empty a
  ready-state change computes it again. No DOM event, as in Safari.
- `getStartDate()`: `round(currentDate − currentTime)` whole seconds since
  the epoch, from `EXT-X-PROGRAM-DATE-TIME`, an Invalid Date without one.
  Safari samples it only at ready-state changes, so the player samples it at
  metadata and at each buffering change and sends `OnStartDateChanged` just
  before the `OnBufferingStateChange`.
- Seeking: the element clamps to the duration and then to the nearest point
  of the one seekable range, as WebKit's `seekTask` does, so a seek past the
  window's end lands on the live edge and one before its start on the oldest
  DVR point. The player seeks exactly. On Safari-identity pages `currentTime`
  takes WebKit's `unrestricted double`: +Infinity (`currentTime = duration` on
  a live stream) seeks to the live edge, −Infinity and NaN to 0, where
  Chromium throws a TypeError.

Render process: the native HLS demuxer keeps the last window and start date
under a lock and answers `media::Demuxer::GetParcNativeTimeline()` (nullopt
from every other demuxer) from any thread: `{Ranges<TimeDelta> seekable,
std::optional<base::Time> start_date}`, an end of `kInfiniteDuration` meaning
Infinity. `WebMediaPlayerImpl::Seekable()` returns that window for it (instead
of Chromium's empty live answer), and `WebMediaPlayer::ParcStartDate()`
(milliseconds, NaN without one) backs `HTMLMediaElement.getStartDate()`, which
exists only on Safari-identity pages (`[ContextEnabled=ParcSafariIdentity]`)
and answers an Invalid Date for every other player, as WebKit's default.

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

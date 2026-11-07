# Native HLS (Safari's second FairPlay route)

Status: design; pieces landing. Owners: `fp-native-hls` (the GPU core player,
`Engine/ParcNative/fairplay/fairplay_hls_player.*`), `fp-hls-render` (the
render-process route: Blink, `DemuxerManager`, `NativeHlsDemuxer`, the
`NativeHlsRenderer` facade, pipeline hooks, element state), `fp-hls-mojo`
(mojo interfaces, `InterfaceFactory`, the GPU service wrapping the core, the
render-process loader), `fp-hls-keys` (skd in the CDM, the asset's content
keys, modern EME), `fp-hls-display` (display, PiP and fullscreen, frame
counts), `fp-hls-tracks` (audio and text tracks: `fairplay_hls_media_selection.*`
and the page side, Tracks below), `fp-hls-live` (live and DVR
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

- Keys reach an `AVURLAsset` only through objects of its own process: the
  CDM answers the asset's `AVAssetResourceLoadingRequest`s (and
  `addContentKeyRecipient:` would take the object too), so the asset must be
  in the CDM's process. The CDM is in the GPU process.
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

- `HTMLMediaElement` already tells its player whether the document presents
  Safari's identity (`MediaPlayerClient::PresentsParcSafariIdentity()`, as the
  rest of fairplay-identity); `WebMediaPlayerImpl` passes it on as
  `DemuxerManager::Client::PresentsParcSafariIdentity()`.
- `DemuxerManager::CreateDemuxer` takes its HLS branch as today (path ends in
  `.m3u8`, or `DEMUXER_ERROR_DETECTED_HLS` from FFmpeg's sniffing). With the
  switch on and Safari's identity, it asks its client
  (`DemuxerManager::Client::CreateParcNativeHlsDemuxer`, default null) and
  uses that demuxer instead of `ManifestDemuxer`, with no data source.
  `canPlayType` keeps answering "maybe". The request is a
  `media::ParcNativeHlsDemuxerParams` (`renderer_factory.h`): the playlist URL
  (after a sniffed load's redirects), the MIME type AVFoundation is told (as
  WebKit, only one not inferred from the extension: HLS's for a sniffed
  playlist, empty for a `.m3u8` path), the media task runner, the media log
  (the demuxer clones it) and the callback that raises `encrypted`.
  `fp-hls-mojo` adds the loader to it. The demuxer reports
  `DemuxerType::kManifestDemuxer`, so it is deleted on the media thread and
  counted as HLS.
- `WebMediaPlayerImpl` gets the demuxer from the factory registered for
  `RendererType::kFairPlayHls` (13; `RendererFactorySelector::GetFactory`, a
  new `RendererFactory::CreateParcNativeHlsDemuxer` hook), which `MediaFactory`
  adds next to the FairPlay renderer factory and which holds the frame's
  `InterfaceFactory`. With no such factory the HLS branch keeps
  `ManifestDemuxer`. The demuxer and facade live in
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
  hole frame. `WebMediaPlayerImpl::CreateRenderer` takes that factory directly,
  past the conditional (remoting) factories, whose renderers can't play the
  placeholder streams. Its `Initialize` binds to the demuxer's player through
  that hook. Suspend/resume destroy and recreate only the facade.
- `PipelineImpl::RendererWrapper::SetCdm` also hands the `CdmContext` to the
  demuxer (`Demuxer::SetCdmForNativePlayer`, default no-op) so a CDM set before
  the renderer exists reaches the player at once; `Start` hands it one set
  before the pipeline started.
- `WebMediaPlayerImpl` treats `kFairPlayHls` as `kFairPlay`: audio isn't the
  audio service's, the player is never auto-suspended, and its video is never
  disabled while hidden.
- `NativeHlsRendererFactory`, `NativeHlsDemuxer` and `NativeHlsRenderer`
  (`content/renderer/media/fairplay`, tested by `native_hls_unittest.cc`)
  implement it. The factory connects the player when it makes the demuxer
  (main thread); the demuxer binds the pipes on the media thread and closes
  them in `Stop`. The placeholder streams are clear (keys never pass a
  decryptor here), so the pipeline never waits for a CDM. An item error before
  the metadata fails `Initialize` with that status (otherwise
  `DEMUXER_ERROR_COULD_NOT_OPEN`); later ones go to the facade's
  `RendererClient`, or to the demuxer host while no facade exists. A lost GPU
  connection is `PIPELINE_ERROR_DISCONNECTED`. `waitingforkey` and the display
  layer arriving before a facade exists are replayed to it. The facade reports
  buffering only between `StartPlayingFrom` and `Flush` (RendererImpl's
  contract) and `ended` once per run to the end; its time is the player's last
  `OnTimeUpdate` advanced at that rate within [0, duration], and the target
  during a seek. `WebMediaPlayerImpl` makes the element's
  `blink::FairPlayHlsLoader` with the demuxer and hands its
  `GetStartLoadCallback()` over as `ParcNativeHlsDemuxerParams::start_load_cb`,
  which the demuxer's `StartLoad` runs (Network). Tracks are `fp-hls-tracks`'
  (`ParcNativeHlsDemuxerParams::track_manager`). The demuxer answers
  `GetParcNativeTimeline()` from `OnSeekableRangesChanged` and
  `OnStartDateChanged` under its time lock, and turns `OnKeyRequest` into
  `WebMediaPlayerEncryptedMediaClient::ParcWebKitKeyRequest`
  (`webkitneedkey`) through `DemuxerManager` on the main thread, posted in the
  player's order so it precedes the request's `encrypted`. A legacy clear key
  Blink hands the element's player (`WebMediaPlayer::ParcProvideClearKey`)
  goes from `WebMediaPlayerImpl` through `DemuxerManager` to the demuxer on
  the media thread (`Demuxer::ParcProvideClearKey`) and on as
  `FairPlayHlsPlayer.ProvideClearKey`.

## Mojo

The interfaces are in `media/mojo/mojom/renderer_extensions.mojom`, beside
`FairPlayRendererClientExtension`, module `media.mojom`, all
`[EnableIf=is_mac]` (fairplay-media.patch; the patch's comments are the
reference):

```
// InterfaceFactory (render process → browser MediaInterfaceProxy → the
// frame's GPU InterfaceFactoryImpl, the one holding its CDMs). The render
// process passes a null lifetime; the browser substitutes its own.
CreateFairPlayHlsPlayer(pending_receiver<FairPlayHlsPlayer> player,
                        pending_remote<FairPlayHlsPlayerClient> client,
                        pending_remote<FairPlayHlsPlayerLifetime>? lifetime);

struct FairPlayHlsRequest {
  url.mojom.Url url; string method;
  map<string, string> headers;      // as AVFoundation set them
};
struct FairPlayHlsResponse {
  int32 http_status; string mime_type;  // Content-Type without parameters
  int64 content_length;             // -1 unknown or decoded Content-Encoding
  url.mojom.Url final_url;          // after redirects
  map<string, string> headers;      // combined per name
};
interface FairPlayHlsLoad {          // render process implements, per load
  Cancel();                          // or close the pipe
};
interface FairPlayHlsLoadClient {    // GPU implements, per load
  OnResponse(FairPlayHlsResponse response,
             handle<data_pipe_consumer> body);  // closes after the last byte
  OnComplete(int32 net_error);       // net::OK or a net error
};

struct FairPlayHlsTimeRange { mojo_base.mojom.TimeDelta start, end; };
enum FairPlayHlsTrackType { kAudio, kVideo, kText };
enum FairPlayHlsTextTrackMode { kDisabled, kHidden, kShowing };
struct FairPlayHlsTrack {            // core HlsTrack (Tracks below)
  string key;                        // unique; names it in calls and cues
  string id; string kind; string label; string language;  // WebKit's DOM values
  bool enabled;                      // audio
  int64 index;                       // TrackPrivateBase::trackIndex: lists
                                     // order by it, -1 (audio) last
  FairPlayHlsTrackType type;         // kAudio or kText
  bool is_default; bool is_closed_captions; bool is_sdh;  // text: caption
  bool contains_only_forced_subtitles;                    // preference inputs
  bool is_main_program_content; bool is_easy_to_read;
};
enum FairPlayHlsCueType { kWebVttHeader, kWebVtt, kAdd, kUpdate, kRemove };
enum FairPlayHlsCueAlign { kNone, kStart, kMiddle, kEnd };
struct FairPlayHlsCue {              // core HlsCue, one change in order
  FairPlayHlsCueType type; uint64 cue_id;   // cue_id: generic cues
  double start; double end;          // seconds; generic end +inf while
                                     // open; WebVTT end NaN if no duration
  bool complete; string text;
  string identifier; string settings;       // WebVTT iden, sttg,
  string source_id; string original_start_time;   // vsid, ctim boxes
  double line; double position; double size;      // generic layout, -1 unset
  double base_font_size; double relative_font_size; string font_name;
  FairPlayHlsCueAlign align; FairPlayHlsCueAlign position_align;
  uint32? foreground_color; uint32? background_color;   // 0xRRGGBBAA
  uint32? highlight_color; bool prevent_line_wrapping;
};
struct FairPlayHlsMetadata {
  bool has_audio; bool has_video; gfx.mojom.Size natural_size;
  AudioCodec audio_codec; VideoCodec video_codec;   // kUnknown if not given
  mojo_base.mojom.TimeDelta duration;  // TimeDelta::Max() = live (Infinity)
  mojo_base.mojom.Time? start_date;    // getStartDate() (Live and DVR)
  array<FairPlayHlsTimeRange> seekable;  // one window or none (Live and DVR)
  array<FairPlayHlsTimeRange> buffered;  // loadedTimeRanges
  array<FairPlayHlsTrack> tracks;
};

interface FairPlayHlsPlayerLifetime {};  // browser implements, no methods

interface FairPlayHlsPlayer {        // GPU implements
  Initialize(url.mojom.Url url, string mime_type)
      => (bool success, FairPlayHlsMetadata? metadata);
  SetCdm(mojo_base.mojom.UnguessableToken cdm_id) => (bool success);
  Play(double rate); Pause();
  Seek(mojo_base.mojom.TimeDelta time) => (bool success);
  SetVolume(float volume); SetMuted(bool muted);
  SetPreservesPitch(bool preserves_pitch);   // Renderer::SetPreservesPitch
  ProvideClearKey(string key_id, array<uint8> key);  // legacy clear key
  SetAudioTrackEnabled(string key, bool enabled);   // AudioTrack.enabled
  SetTextTrackMode(string key, FairPlayHlsTextTrackMode mode);  // .mode
  Suspend(); Resume();               // stop/restart loading (preload, idle)
};

interface FairPlayHlsPlayerClient {  // render process implements
  StartLoad(FairPlayHlsRequest request,
            pending_receiver<FairPlayHlsLoad> load,
            pending_remote<FairPlayHlsLoadClient> client);
  OnTimeUpdate(mojo_base.mojom.TimeDelta time, double rate,
               mojo_base.mojom.TimeTicks capture_time);
  OnBufferingStateChange(BufferingState state);
  OnBufferedRangesChanged(array<FairPlayHlsTimeRange> buffered);
  OnSeekableRangesChanged(array<FairPlayHlsTimeRange> seekable);
  OnDurationChange(mojo_base.mojom.TimeDelta duration);
  OnStartDateChanged(mojo_base.mojom.Time? start_date);  // before
                                     // the OnBufferingStateChange it goes with
  OnTracksChanged(array<FairPlayHlsTrack> tracks);  // whole list: audio
                                     // then text, each in DOM order
  OnTextCues(string track_key, array<FairPlayHlsCue> cues);
  OnNaturalSizeChange(gfx.mojom.Size size);
  OnLayerRegistered(mojo_base.mojom.UnguessableToken token,
                    gfx.mojom.Size natural_size);
  OnStatisticsUpdate(PipelineStatistics delta);
  OnEncrypted(string init_data_type, array<uint8> init_data);
  OnKeyRequest(string key_uri);       // every skd:// and clearkey://
                                     // loading request, first (Keys)
  OnWaiting(WaitingReason reason);    // kNoDecryptionKey
  OnEnded();
  OnError(PipelineStatus status, string message);
};
```

`media.mojom` has no time-range struct, and `DemuxerStream.Type` is a
`[Native]` enum, hence `FairPlayHlsTimeRange` and `FairPlayHlsTrackType`.
`FairPlayHlsMetadata.tracks` is the selection's list (`Tracks()`) when the
`Initialize` reply is sent; the GPU service sends no `OnTracksChanged` before
that reply (the two travel on different pipes) and folds earlier lists into
it. The page treats `metadata.tracks` and every `OnTracksChanged` alike: the
whole list replaces the previous one, tracks matched by `key`.

Routing, as the FairPlay renderer's and CDM's:

- Render process: `content::MediaInterfaceFactory::CreateFairPlayHlsPlayer`
  hops to its thread and always sends a null lifetime.
- Browser: `MediaInterfaceProxy::CreateFairPlayHlsPlayer` drops the request
  unless `parc::fairplay::kNativeHlsEnabled` is true, then forwards it to the frame's
  GPU `InterfaceFactory` (the one that created its FairPlay CDMs) with its own
  `FairPlayHlsPlayerLifetime`, a self-owned receiver holding the frame's
  `AudibilityBypassTracker` grant until the GPU player closes it: AVPlayer's
  audio bypasses the audio service like the MSE renderer's.
  `FramelessMediaInterfaceProxy` drops it.
- GPU: `InterfaceFactoryImpl::CreateFairPlayHlsPlayer` asks
  `MojoMediaClient::CreateFairPlayHlsPlayer` (default null) for the service,
  handing it a getter for `MojoCdmServiceContext::GetCdmContextRef` so
  `SetCdm` resolves the frame's CDM, and owns it in a receiver set that keeps
  the factory alive (`IsEmpty`) and goes before the CDMs.
  `GpuMojoMediaClientMac` returns `media::FairPlayHlsPlayerService`
  (`fairplay_hls_player_service.{h,mm}`), which also registers the tab-mute
  observer as `CreateFairPlayRenderer` does.

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
| `SetHlsKeyRequestHandler` (between `CreateAsset` and `Start`) → the CDM's key loader takes skd requests | `OnKeyRequest(uri)` for every request it is handed; its `OnKeyNeeded(uri)` → `OnEncrypted("skd", uri)` (Keys) |
| `OnOutputObscuredChange(bool)` | the key loader's `SetOutputObscured` |
| `OnKeyRequest(clearkey uri)`, `FulfillKeyRequests(uri, key)`, `HlsClearKeyId` | `OnKeyRequest(uri)` / `ProvideClearKey(key_id, key)` |
| `CurrentTime()` (any thread), `Rate()` | `OnTimeUpdate` |
| `HlsPlayerAsset` / `HlsPlayerLayer` (`fairplay_hls_player_internal.h`) | the key loader's asset (Keys) / `ProtectedLayerRegistry` (Display) |

The core never blocks on the embedder and never calls the client inside a call
into it. Facts the harness established: every load AVFoundation makes goes to
`HlsLoader` (a host only the loader can reach still plays); AVFoundation asks
again for a key whose request failed instead of failing the item; a live
variant that 404s makes it retry silently, with no item error; an `http://`
playlist plays (App Transport Security doesn't apply to client loads). The
GPU-sandbox probe plays native HLS with only the MSE route's sandbox rules.

## Network (render process)

`blink::FairPlayHlsLoader`
(`third_party/blink/renderer/platform/media/fairplay_hls_loader.{h,cc}`,
installed from `fairplay_chromium/`) serves `StartLoad` on the main thread.
Each load is one `blink::WebAssociatedURLLoader` made by the element's
`ResourceFetchContext` (the factory `ResourceMultiBufferDataProvider` uses for
every `<video src>` load), with the element's CORS mode and credentials
exactly as that provider applies them (CORS mode with no preflight; anonymous
sends same-origin credentials) and the video or audio request destination. So
AVFoundation's loads carry the page's cookies and referrer, pass CORS, use the
profile's proxy and appear in DevTools as the element's media requests.

- Only `GET` and `HEAD` of `http`/`https` URLs are fetched; anything else
  answers `OnComplete(ERR_DISALLOWED_URL_SCHEME / ERR_METHOD_NOT_SUPPORTED)`
  at once. `skd://` and `clearkey://` URIs never reach `StartLoad` (Keys).
- Of AVFoundation's request headers only `Range` is forwarded (a well-formed
  ASCII value): its own `User-Agent` (AppleCoreMedia) and
  `X-Playback-Session-Id` would make cross-origin CORS loads preflight, and
  the page's identity UA is sent instead. A `Range` request gets the
  identity encoding exactly as `ResourceMultiBufferDataProvider`'s do: added
  by the network layer after any service worker
  (`kDeferMediaAcceptEncodingInjection`, on by default), or by the loader when
  that switch is off. A playlist fetched without `Range` lets the network
  stack negotiate and decode compression.
- Redirects are followed in the render process as for any fresh media load
  (`WebAssociatedURLLoader` enforces CORS on them in CORS mode); `final_url`
  is the URL after the last one, which relative playlist URIs resolve
  against.
- The real status, MIME type (without parameters) and headers go back to
  AVFoundation. A body the network stack decoded (a `Content-Encoding` other
  than identity) reports length -1 and drops `Content-Length` and
  `Content-Encoding`, since the decoded body is not that length.
- The body streams over the load's data pipe (512 KiB); while the pipe is full
  the loader defers loading and keeps the overflow, and `OnComplete(net::OK)`
  follows the last byte. A failure reports its net error (after a partial
  body, the bytes already sent stay in the pipe).
- `FairPlayHlsLoad.Cancel()`, the load's or client's pipe closing, or the body
  pipe's consumer closing early cancels the `WebAssociatedURLLoader`.
  Destroying the loader cancels every load.
- GPU side (the service's `HlsLoader` over these pipes): `OnComplete` is a
  message on `FairPlayHlsLoadClient` and the body is a separate data pipe, so
  `OnComplete` can arrive while bytes are still unread. The service passes
  `HlsLoadClient::OnComplete(net::OK)` to the core only after it has read the
  pipe to its end (the producer closed it and nothing is left), and
  `OnData` every chunk before that; a failure's `OnComplete` waits the same
  way for the partial body already in the pipe. Otherwise AVFoundation gets a
  truncated segment or playlist as complete. Destroying the core's `HlsLoad`
  calls `Cancel()` and closes the pipe.

`WebMediaPlayerImpl` (fp-hls-render's routing) builds the loader with
`url_index_->fetch_context()`, its `cors_mode_` and
`client_->IsAudioElement()`, and gives the demuxer `GetStartLoadCallback()`, a
callback any thread may run that posts to the loader and is dropped (closing
the pipes) once the loader is gone. The demuxer's
`FairPlayHlsPlayerClient::StartLoad` just runs it. Unit tests:
`fairplay_hls_loader_unittest.cc` in `blink_platform_unittests`.

## Keys

How the GPU service wires keys: after `FairPlayHlsPlayer::CreateAsset` it
creates the CDM's key loader for the asset (`FairPlayHlsKeyLoader`, from
`fp-hls-keys`) with the attached CDM if any, installs it with
`SetHlsKeyRequestHandler`, then calls `Start`; it forwards the loader's
`OnKeyNeeded(uri)` as `OnEncrypted("skd", uri)` plus
`OnWaiting(kNoDecryptionKey)`, `SetCdm` to the loader, and the player's
`OnOutputObscuredChange` to its `SetOutputObscured`. The key loader's tests
showed that a request held on the resource loader can't be finished for the
session afterwards (it never plays), so the loader answers held requests with
their own SPC/CKC and never makes the asset a content key recipient; where
the steps below differ, the key loader's header is right.

`webkitneedkey`: every `skd://` request the key loader is handed (its
client's `OnKeyLoadingRequest(url)`) and every `clearkey://` request the core
reports, whether or not a CDM is set and including repeats of a URI, first
sends `OnKeyRequest(<the request URL's absoluteString, UTF-8, unchanged>)`. The render process passes it to
`WebMediaPlayerEncryptedMediaClient::ParcWebKitKeyRequest()`, which on a
Safari-identity page queues `webkitneedkey` at the element before anything
else the request raises: for `skd://` with WebKit's legacy layout (4-byte
little-endian UTF-16 byte length, then the URI as UTF-16), for `clearkey://`
with the key ID (the URL after `clearkey:`, as `HlsClearKeyId`) as UTF-8
(WebKit's `keyNeeded` in `shouldWaitForLoadingOfResource`;
`parc_webkit_need_key.h`, `fp-legacy-element`).

What the key loader does (its header and the [core README](../fairplay/README.md),
"HLS assets", have the detail; the AVFoundation facts are in
[tests/FairPlay README](../../../tests/FairPlay/README.md#apple-api-behaviour),
"HLS assets"):

1. The loader takes the element's CDM at creation if it has one, and
   `SetCdm` attaches, replaces or drops it later. Every skd request stays on
   the asset's resource loader (the loader never makes the asset a content
   key recipient), so each raises `webkitneedkey` as in Safari and is answered
   with its own SPC in whatever order the page licenses keys.
2. A key no session of the attached CDM asked for: `OnKeyNeeded(uri)`, which
   the GPU service sends as `OnEncrypted("skd", <URI as UTF-8>)` and
   `OnWaiting(kNoDecryptionKey)`. The render process raises `encrypted`
   (initDataType `"skd"`) and `waitingforkey`, after the request's
   `webkitneedkey` (above).
3. The page's `generateRequest("skd", uri)` reaches the same `FairPlayCdm`
   over its own pipe. With an asset attached the request is named by the URI
   (content identifier = the URI, or a legacy session's `contentId`), and it
   takes the asset's held loading request, answered with that request's own
   SPC. Made first, it waits for the asset to ask.
4. `update(ckc)` delivers the key and playback resumes by itself; nothing
   else crosses the GPU service.

`EmeInitDataType::SKD` and its `"skd"` string are on main (7c317739,
`fp-safari-eme-surface`).

### Legacy clear key (`clearkey://`)

WebKit's player also answers `clearkey://` key requests, for the legacy
`org.w3c.clearkey` key system (`CDMSessionClearKey`, in
`parc_webkit_media_keys.h` behind the same switch). Safari raises no
`encrypted` event for them, only `webkitneedkey`:

1. The core reports the request (`HlsPlayerClient::OnKeyRequest(uri)`, scheme
   `clearkey`). The GPU service sends `FairPlayHlsPlayerClient.OnKeyRequest(uri)`,
   keeping `HlsClearKeyId(uri)` (WebKit's key ID: the URL's resource
   specifier) → URI.
2. The render process raises `webkitneedkey` on the element with the key ID
   as UTF-8 (WebKit's `keyNeeded(initData)`), never an `encrypted` event,
   unless the element's own keys already hold that key: then the key goes
   straight back as in step 3 and nothing is raised (WebKit checks
   `cachedKeyForKeyId` first).
3. When the page's legacy session takes a JWK set (`keysAdded` in the
   script), the element side gives every held key ID the script has a key
   for back to the player: the script calls the `provideKey` Blink handed its
   key-needed hook with the request (`ParcProvideClearKey` in
   `parc_webkit_need_key.h`), which calls
   `WebMediaPlayer::ParcProvideClearKey(key_id, key)`; `WebMediaPlayerImpl`
   forwards it to `FairPlayHlsPlayer.ProvideClearKey(key_id, key)` →
   `FairPlayHlsPlayer::FulfillKeyRequests(uri, key)`, which answers the
   requested byte range of the raw key (WebKit's `fulfillRequestWithKeyData`)
   and answers later requests for that URI the same way.

The bridge between the page-world script and `WebMediaPlayer` is on main
(`fp-legacy-element`); `WebMediaPlayerImpl::ParcProvideClearKey` reaching the
native HLS player is `fp-hls-render`'s, the mojo calls `fp-hls-mojo`'s.

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

### Picture in Picture and fullscreen

Parc's own paths, unchanged: the PiP sequence in
[COMPOSITING.md](COMPOSITING.md) applies as it is. `WebMediaPlayerImpl` stops
the page drawing the video, Parc's panel draws the same hole frame in its own
compositor, whose tree takes the `AVPlayerLayer`, and leaving PiP gives it
back. Fullscreen is a resize of the page's compositor. As for the MSE route,
this is not AVKit's PiP: that needs the layer in the browser process. What
the route must keep for it:

- `NativeHlsRenderer` forwards each natural size to its `RendererClient`
  before repainting the hole, as `FairPlayRendererClient` does (the panel's
  aspect ratio comes from `NaturalSize()`). `AVPlayerItem.presentationSize`
  changes with each variant switch, so this happens during playback, in PiP
  too.
- `WebMediaPlayerImpl`'s FairPlay exemptions cover
  `RendererType::kFairPlayHls` (routing, 79a807d9): the video track stays
  enabled while hidden (`ShouldDisableVideoWhenHidden`) and the player isn't
  auto-suspended, so the layer keeps its picture for a PiP panel and a page
  shown again.

`tests/FairPlay/hls_presentation` (RemotePiP) runs this sequence with the
layer inside CAContexts shown through `CALayerHost`s, as the GPU process's
trees are, and proves on this Mac:

- The layer keeps playing when it moves to the PiP window's context and back.
- AVFoundation picks variants by the layer's size on screen inside such a
  context exactly as in a window: 720p (not 1080p) for a 640×360 pt layer on
  a 2× display, 1080p once fullscreen makes it 1280×720 pt, as Safari's
  `AVPlayerLayer` gets.
- A variant switch can restart the frame counter (seen on the way back from
  PiP, 229 → 107), which `HlsFrameStats` counts as a new run.

Separate runs (not in the harness) found the same variant choice with the
layer under an ancestor transform, as Chromium's tree carries the quad's, and
with plain windows instead of contexts. They also found that after a spell at
PiP size AVFoundation doesn't go above its earlier best variant when the layer
grows again. Plain windows behave the same, so this is AVFoundation's
behavior, not Parc's hosting.

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
| `audioTracks` / `textTracks` | `HlsMediaSelection` (Tracks) | `OnTracksChanged`, `OnTextCues` (Tracks) |
| decoded/dropped frames | `-[AVPlayerLayer videoPerformanceMetrics]` (`HlsFrameStats`) | `OnStatisticsUpdate` deltas (as fp-frame-stats) |
| `webkitneedkey` | every resource loader skd and clearkey request | `OnKeyRequest` → `ParcWebKitKeyRequest` |
| `encrypted`, `waitingforkey` | resource loader skd requests | `OnEncrypted`, `OnWaiting` |

## Tracks

The core's `HlsMediaSelection` (`fairplay/fairplay_hls_media_selection.h`,
[core README](../fairplay/README.md#native-hls-tracks)) is a port of WebKit's
AVFoundation track code: audioTracks from the audible media selection group
(WebKit choosing the option, AVFoundation's automatic criteria off), textTracks
from the legible group, cues from one `AVPlayerItemLegibleOutput` for the one
track the modes pick. GPU service: `media::FairPlayHlsTrackBridge`
(`fairplay_hls_track_bridge.{h,mm}`, the GPU source set) owns the selection
and does the rest; the service makes one with its client remote and
`PostTask`, calls `Attach(player.impl())` right after `Load`, puts
`TakeTracksForInitialize()` in the `Initialize` reply, forwards
`SetAudioTrackEnabled`/`SetTextTrackMode`, and calls `WillSeek()` before each
`FairPlayHlsPlayer::Seek` and `DidSeek()` in its `done`, whatever the result.
The bridge attaches with `HlsMediaSelectionAttach(selection.impl(),
HlsPlayerAVPlayer(player.impl()), player.currentItem)`, maps
`HlsTrack`/`HlsCue` onto `FairPlayHlsTrack`/`FairPlayHlsCue` field for field,
holds lists back until the reply, and brackets seeks as WebKit does: the
selection's `BeginSeeking()` on every seek and `EndSeeking()` once the last
one is done (WebKit's `beginSeeking`/`endSeeking` on the current text track:
the open cue is flushed and cues arriving meanwhile get no end from the next
one; like WebKit, only the track current at the seek's start is flagged).
The GPU never picks a text track: it serves whichever one the page's modes
pick.

Page side, Safari-identity documents only (the route exists only there).
The demuxer gets `ParcNativeHlsDemuxerParams.track_manager`, a
`media::TrackManager` callable on the media thread that posts to the element:
`AddTrack`/`RemoveTrack`/`SetTrackState` for audio, and
`ParcSetInbandTextTracks(tracks, set_mode)` / `ParcAddInbandTextCues(key,
cues)` (`media/base/media_track.h`, through `DemuxerManager` and
`WebMediaPlayerImpl` to `HTMLMediaElement`) for text. `set_mode` is a
`ParcInbandTextTrackModeCB` the demuxer binds to itself on the media thread
(`BindPostTask` with its weak pointer) that sends `SetTextTrackMode`; the
element calls it from the main thread on every in-band mode change.


- Audio: each audio `FairPlayHlsTrack` becomes a `media::MediaTrack` through
  the demuxer's `TrackManager` (added in list order, removed when gone,
  `SetTrackState` for `enabled`), with WebKit's kind (`description` kept as
  WebKit spells it), label and language. The `MediaTrack` id is the `key`,
  so the pipeline's enabled-track ids stay unique; the page is shown WebKit's
  `id`, which can repeat. The demuxer's `OnEnabledAudioTracksChanged` diffs
  the enabled keys against the last list and sends
  `SetAudioTrackEnabled(key, …)` per changed track.
- Text: M156 Blink defines `TextTrack::kInBand` but nothing creates such
  tracks, so `fp-hls-tracks` adds the minimal path: the player client makes
  Blink `TextTrack`s of type `kInBand` in the element's list (WebKit's kind
  `forced` included) and forwards their mode changes as
  `SetTextTrackMode(key, mode)`. Which track shows by default is decided only
  in the render process, by the element's automatic text track selection
  with WebKit's caption preference rules (the flags above feed them). Cues
  become `VTTCue`s as WebKit's `InbandGenericTextTrack` makes them (`kWebVtt`
  parsed like `WebVTTParser::parseCueData`, the header for regions and style
  sheets, generic cues added, updated and removed by `cue_id`, an open cue's
  end shown as the media duration, +inf for live).

## Frame counts

`getVideoPlaybackQuality()`, `webkitDecodedFrameCount` and
`webkitDroppedFrameCount` come from WebKit's source for an `AVPlayer`,
`-[AVPlayerLayer videoPerformanceMetrics]` (SPI; the object answers WebKit's
`totalNumberOfVideoFrames`/`numberOfDroppedVideoFrames` and, from macOS 14.4,
the public `totalNumberOfFrames`/`numberOfDroppedFrames`). The core's
`HlsFrameStats` (`fairplay/fairplay_hls_frame_stats.h`) owns the polling, and
`FairPlayHlsPlayer` owns one from the moment its `AVPlayerLayer` exists
(`HlsPlayerLayer`). The player counts while its rate is above 0, drops the
counter first when it shuts down, and reports each delta as
`HlsPlayerClient::OnVideoFrameCounts(decoded, dropped)`.
`FairPlayHlsPlayerService` is to forward that as `OnStatisticsUpdate`
(`video_frames_decoded`, `video_frames_dropped`), which `PipelineImpl` adds
up as for the MSE route. `HlsFrameStats` reads on its own serial queue every
250 ms while playing, because the call can block (WebKit reads it on a
background queue), counts once more on stopping, and never reports after it
is destroyed.

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
and answers an Invalid Date for every other player, as WebKit's default. It
is installed with the context's `HTMLMediaElement` interface object, so a
document that takes over a context in which an earlier document (an initial
`about:blank`) already used that interface goes without it.

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

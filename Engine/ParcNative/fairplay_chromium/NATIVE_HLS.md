# Native HLS (Safari's second FairPlay route)

Status: on main and on for Safari-identity pages; not yet built or run in
an engine. Owners: `fp-native-hls` (the GPU core player,
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

## On for Safari-identity pages

The route has no switch: every Safari-identity page plays HLS through it, and
every other page keeps Chromium's `ManifestDemuxer` as before. Its pieces
landed separately behind a build-time constant, which was removed once they
were all on main. The Safari-identity script installer always offers WebKit's
legacy AVFoundation-player key systems (`com.apple.fps`, `com.apple.fps.1_0`,
`org.w3c.clearkey`) on `WebKitMediaKeys`
(`Engine/ParcRenderer/parc_webkit_media_keys.h`).

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
  `.m3u8`, or `DEMUXER_ERROR_DETECTED_HLS` from FFmpeg's sniffing). With
  Safari's identity, it asks its client
  (`DemuxerManager::Client::CreateParcNativeHlsDemuxer`, default null) and
  uses that demuxer instead of `ManifestDemuxer`, with no data source.
  `canPlayType` keeps answering "maybe". A `data:` URL whose type is an HLS
  type (`application/vnd.apple.mpegurl`, `application/x-mpegurl`,
  `audio/mpegurl`, `audio/x-mpegurl`) takes the branch too
  (`DemuxerManager::ParcNativeHlsDataUrlMimeType`), and `WebMediaPlayerImpl`
  starts the pipeline with it instead of decoding it into a memory data
  source: Safari takes a data: URL's type from the URL, and AVFoundation
  decodes the playlist itself, and data: playlists a playlist names too,
  so only segment URIs go through the loader (harness `data-url`,
  `data-url-video`). Spotify plays its generated playlists that way. The GPU
  service leaves the scheme to the core. AVFoundation refuses a `blob:` playlist as an unsupported URL before
  any load, so the core refuses one at `Load`. The request is a
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
- Chromium never suspends the native HLS player, from the moment its demuxer
  exists: `DemuxerManager::CreateDemuxer` starts it with
  `Pipeline::StartType::kNormal` (Chromium's own HLS branch takes a suspended
  start, suspend after metadata, which a `preload="metadata"` element would
  take before the renderer type is known), and `UpdatePlayState` keys on
  `DemuxerManager::HasParcNativeHlsDemuxer()` as well as the renderer type:
  no idle, background, frame-frozen or stay-suspended suspend. WebKit's
  preload rules live in the GPU player (it loads nothing past the playlists
  until the element prepares to play), and a suspend and resume would destroy
  the facade a pending seek completes through, leaving the element seeking
  for ever (TELUS's start-position seek on a `preload="metadata"` element).
  Explicit restart cycles (`ScheduleRestart`) still run. Tested in
  `parc_native_hls_routing_unittest.cc`.
- `NativeHlsRendererFactory`, `NativeHlsDemuxer` and `NativeHlsRenderer`
  (`content/renderer/media/fairplay`, tested by `native_hls_unittest.cc`)
  implement it. The factory connects the player when it makes the demuxer
  (main thread); the demuxer binds the pipes on the media thread and closes
  them in `Stop`. The placeholder streams are clear (keys never pass a
  decryptor here), so the pipeline never waits for a CDM. An item error before
  the metadata fails `Initialize` with that status (otherwise
  `DEMUXER_ERROR_COULD_NOT_OPEN`); later ones go to the facade's
  `RendererClient`, or to the demuxer host while no facade exists. A lost GPU
  connection is `PIPELINE_ERROR_DISCONNECTED`. A wait for a key (only while no
  CDM is attached) and the display layer arriving before a facade exists are
  replayed to it. The facade reports
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
  Initialize(url.mojom.Url url, string mime_type);  // → OnInitialized
  SetCdm(mojo_base.mojom.UnguessableToken? cdm_id) => (bool success);  // null: setMediaKeys(null)
  Play(double rate); Pause();
  Seek(mojo_base.mojom.TimeDelta time, mojo_base.mojom.TimeDelta tolerance_before)
      => (bool success, mojo_base.mojom.TimeDelta current_time);
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
  OnInitialized(FairPlayHlsMetadata? metadata);  // null: failed (after an
                                     // OnError naming the item's failure)
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
`OnInitialized` is sent; the GPU service sends no `OnTracksChanged` before it
and folds earlier lists into it. `Initialize` has no reply: its answer is
`OnInitialized` on the client's pipe, because the player's pipe and the
client's (both made in the render process and passed through the browser)
aren't ordered with each other, and everything the render process does at
initialization (the item error, the layer token, buffering) must arrive in
order with the answer. The page treats `metadata.tracks` and every `OnTracksChanged` alike: the
whole list replaces the previous one, tracks matched by `key`.

Routing, as the FairPlay renderer's and CDM's:

- Render process: `content::MediaInterfaceFactory::CreateFairPlayHlsPlayer`
  hops to its thread and always sends a null lifetime.
- Browser: `MediaInterfaceProxy::CreateFairPlayHlsPlayer` forwards it to the
  frame's GPU `InterfaceFactory` (the one that created its FairPlay CDMs) with its own
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

What the GPU service (`fairplay_hls_player_service.{h,mm}`) guarantees the
render process:

- `Initialize` creates the core player and the track bridge (Tracks), calls
  `CreateAsset`, creates the CDM's `FairPlayHlsKeyLoader` for the asset (with
  the CDM a `SetCdm` before it named) and installs it with
  `SetHlsKeyRequestHandler`, and calls `Start`. In `OnMetadata` it attaches
  the bridge to the new item (not yet on the player), registers the layer
  and sends `OnInitialized`. `SetCdm` afterwards goes to the loader (`false` when it can't
  take the asset; the old CDM stays). The loader's `OnKeyLoadingRequest(url)`
  is `OnKeyRequest(url)`, its `OnKeyNeeded(uri, cdm_attached)` is
  `OnEncrypted("skd", uri)` plus, unless `cdm_attached`,
  `OnWaiting(kNoDecryptionKey)`, and the player's
  `OnOutputObscuredChange` goes to `SetOutputObscured`. `OnInitialized` carries the
  metadata as WebKit reports `HAVE_METADATA`: once the asset's metadata keys
  have loaded and it is playable, before the item exists (GPU core player).
  A failure before it is `OnInitialized(null)`: after `OnError` with the
  asset's error when its loading failed (the demuxer fails with that
  status), alone for a bad URL or an OS without client URL loading
  (`DEMUXER_ERROR_COULD_NOT_OPEN`). A second `Initialize` is a bad message.
- `preload`: as WebKit (`updateStates`, `setPreload`), the item goes on the
  player only once the element prepares to play: by WebKit's rules its
  preload is auto (any `preload` but `none` or `metadata`, a missing one
  included, where Chromium's default is metadata), it has `autoplay`, or it
  has prepared to play on this or any earlier load, as WebKit's never-reset
  `m_hasEverPreparedToPlay`: `load()`, play while it has no future data, a
  seek before future data below preload auto, or a fragment start
  (`HTMLMediaElement::ParcPreparesToPlay`; the demuxer sends `PrepareToPlay`
  after `Initialize`), so after one of those every later source on the
  element puts its item on at once; or its preload becomes auto later
  (`Demuxer::ParcPrepareToPlay` from `DemuxerManager::SetPreload`), or it
  plays or seeks (the core's `SetRate` and `Seek`); a live stream's goes on
  at once.
  Until then a `preload="metadata"` VOD loads its playlists only and asks for
  no key.
- Before `OnInitialized`, the client gets only `StartLoad` (the asset's
  playlists) and an asset error. The item is made just after it, so every
  key call (`OnKeyRequest`, `OnEncrypted`, `OnWaiting`), cue and track list
  comes after `OnInitialized`, as `webkitneedkey` and `encrypted` come after
  `loadedmetadata` in Safari. The metadata has the asset's duration and the
  seekable window up to it, no buffered range, and the media types from the
  variants (both assumed when a variant doesn't name its codecs); the item's
  duration, seekable window, natural size, start date and tracks follow as
  changes once it is ready to play. The layer token (`OnLayerRegistered`,
  video only) is sent just before it.
- `OnTimeUpdate` carries the item's timebase time and AVPlayer's actual rate
  (0 while it waits for data), at every play, pause, seek completion,
  buffering change and end, and every 125 ms while the page's rate is above
  0, as `MojoRendererService`.
- Errors map as WebKit reports them: network to
  `PIPELINE_ERROR_NETWORK`, decode to `PIPELINE_ERROR_DECODE`, not supported
  to `DEMUXER_ERROR_COULD_NOT_OPEN`. Frame counts go out as
  `OnStatisticsUpdate` deltas; the codecs come from the format descriptions'
  media subtypes (Core Audio IDs, MP4 sample entries and the protected
  `q…` forms), `kUnknown` for anything else.
- AVPlayer is muted while the page mutes (`SetMuted`) or the tab does, and
  until the browser's first mute answer. `Suspend`/`Resume` do nothing:
  WebKit's AVFoundation player has no suspended-loading state.
- A load is one `Load` object owned by the core: it cancels the render
  process's load when the core drops it, delivers the body as it arrives and
  completes once both the pipe is drained and `OnComplete` arrived (a
  failure's partial body is delivered first too, see Network); the client
  pipe closing without `OnComplete` is `ERR_ABORTED`.

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
| `HlsPlayerClient::OnMetadata` (once, the asset playable, before the item) | `OnInitialized(metadata)` |
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
`SetHlsKeyRequestHandler`, then calls `Start`, which makes the item only
after `HAVE_METADATA` (so no key request precedes `loadedmetadata`); it forwards the loader's
`OnKeyNeeded(uri, cdm_attached)` as `OnEncrypted("skd", uri)` plus, unless
`cdm_attached`, `OnWaiting(kNoDecryptionKey)`, `SetCdm` to the loader, and the
player's
`OnOutputObscuredChange` to its `SetOutputObscured`. The key loader's tests
showed that a request held on the resource loader can't be finished for the
session afterwards (it never plays), so the loader answers held requests with
their own SPC/CKC and never makes the asset a content key recipient; where
the steps below differ, the key loader's header is right.

Attaching the HLS asset records its CDM without creating an AVContentKeySession,
as WebKit's `MediaPlayerPrivateAVFoundationObjC::cdmInstanceAttached` does.
Session creation is deferred to `generateRequest`: failure rejects that request
with `NotSupportedError`, without a player MediaError, leaving the asset and its
held loading request available for a fresh session to retry. The native
`keys-session-failure` harness forces the system factory to return nil and then
restores it, checking rejection followed by licensed playback.

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
   `SetCdm` attaches, replaces or drops it later (a null `SetCdm`, the page's
   `setMediaKeys(null)`, drops it as WebKit's `cdmInstanceDetached`: keys
   already delivered stay with the asset and later requests wait for the next
   CDM). Every skd request stays on
   the asset's resource loader (the loader never makes the asset a content
   key recipient), so each raises `webkitneedkey` as in Safari and is answered
   with its own SPC in whatever order the page licenses keys.
2. A key no session of the attached CDM asked for: `OnKeyNeeded(uri,
   cdm_attached)`, which the GPU service sends as `OnEncrypted("skd", <URI as
   UTF-8>)`, followed by `OnWaiting(kNoDecryptionKey)` only if the loader held
   no CDM when AVFoundation made the request. As WebKit's
   `shouldWaitForLoadingOfResource` checks `m_cdmInstance` then, only the GPU
   player can decide: `SetCdm`'s answer and the request cross on different
   pipes. The render process raises `encrypted` (initDataType `"skd"`), after
   the request's `webkitneedkey` (above), and on `OnWaiting` waits for the
   key: `waitingforkey` and the lower `readyState` of WebKit's Wait for Key
   ([README](README.md#ready-state-stalls-and-keys-what-the-page-sees)). A
   session of the attached CDM with a request for that key (checked at once
   for a CDM attached since, as WebKit's setMediaKeys does, and at each newly
   usable key), or the player playing on, ends the wait.
3. The page's `generateRequest("skd", uri)` reaches the same `FairPlayCdm`
   over its own pipe. With an asset attached the request is named by the URI
   (content identifier = the URI, or a legacy session's `contentId`), and it
   takes the asset's held loading request, answered with that request's own
   SPC. Made first, it waits for the asset to ask.
4. `update(ckc)` delivers the key and playback resumes by itself; nothing
   else crosses the GPU service.

Order, as in Safari: `HAVE_METADATA` comes from the asset before the item
exists, so `loadedmetadata` reaches the page before any `webkitneedkey` or
`encrypted`. Legacy pages depend on it: Shaka's WebKitMediaKeys path makes
the keys before the load, calls `webkitSetMediaKeys` once `readyState` reaches
`HAVE_METADATA`, and makes its session at `webkitneedkey`. A legacy session
made before the keys are attached has no player behind it and never answers,
even after the attach, exactly as WebKit's (`CDMPrivateMediaPlayer::
createSession` returns none; `parc_webkit_media_keys.h`). Modern MediaKeys
sessions work in any order (steps above). `tests/FairPlay/hls_player_harness.mm`
`keys-legacy-order` plays Axinom's vector in the legacy order.

`EmeInitDataType::SKD` and its `"skd"` string are on main (7c317739,
`fp-safari-eme-surface`).

### Legacy clear key (`clearkey://`)

WebKit's player also answers `clearkey://` key requests, for the legacy
`org.w3c.clearkey` key system (`CDMSessionClearKey`, in
`parc_webkit_media_keys.h`). Safari raises no
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
gravity (cc already laid the quad out at the video's aspect ratio), and gives
it the display's scale as its `contentsScale` before its bounds, as WebKit
gives its `AVPlayerLayer` the page's (`mediaPlayerContentsScale`).

The layer exists before the page draws it, as WebKit's does. WebKit's web
process sends the element's size to the GPU process up front
(`setInitialVideoLayerSize`), and the player makes its `AVPlayerLayer` at
that size and scale in a CAContext of its own (`LayerHostingContext`) and
gives it the player in the same turn as the item
(`createAVPlayerLayer`, then `updateLayerAttachment`). AVFoundation picks
the item's first variant for that layer's size on screen. Parc does the
same: `HTMLMediaElement::ParcVideoLayerSize` (the video element's content box
in points and the display's scale) rides on `FairPlayHlsPlayer.Initialize`,
and the core's `Start` makes the player, stages its layer
(`PCHlsPlayerLayer`, `fairplay_hls_player_layer.h`) in an unhosted CAContext
at that size, which hands it the player, and only then gives the player its
item. The compositor's tree takes the layer when the page draws it. An
element with no layout box yet (or an audio element) sends no size; its
layer then takes the player at the compositor's first size. It sets no
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
  `AVPlayerLayer` gets. That holds after earlier playback too, when
  AVFoundation's bandwidth estimate would start the item at 1080p, because
  the layer is staged at the element's size with the player before the item
  arrives: the item starts at 720p (1030k). A layer with no size when the
  item arrived (sized only once the page drew it) left the item at 1080p
  (1924k) in 3 of 4 runs, and so did a layer sized but in no CAContext.
- A variant switch can restart the frame counter (seen on the way back from
  PiP, 229 → 107), which `HlsFrameStats` counts as a new run.

Separate runs (not in the harness) found the same variant choice with the
layer under an ancestor transform, as Chromium's tree carries the quad's, and
with plain windows instead of contexts. They also found that after a spell at
PiP size AVFoundation doesn't go above its earlier best variant when the layer
grows again. Plain windows behave the same, so this is AVFoundation's
behavior, not Parc's hosting.

## AirPlay

Safari sends FairPlay HLS to an Apple TV with AirPlay: WebKit's AVPlayer
plays to the AVOutputContext its route picker chose
(`MediaPlayerPrivateAVFoundationObjC::setWirelessPlaybackTarget`,
`setShouldPlayToPlaybackTarget`), which AVFoundation streams to the device
itself, FairPlay included. Chrome's casting refuses encrypted media and
mirroring shows the video black, so this is the only way FairPlay video
reaches a TV from Parc. Parc follows WebKit's split:

- Browser (`Engine/ParcNative/native_airplay.mm`, WebKit's
  `WebMediaSessionManager` with `AVRoutePickerViewTargetPicker`): one
  `AVRouteDetector`, on while an element needs it, for availability; the iTunes
  audio `AVOutputContext` WebKit's picker uses; and the system's AirPlay route
  list for that context (`-[AVRoutePickerView
  showRoutePickingControlsForOutputContext:relativeToRect:ofView:]`, AVKit
  SPI). An app can't list or choose AirPlay devices itself: that needs
  `com.apple.avfoundation.allows-access-to-device-list` and
  `allows-set-output-device`, which only AVKit's `RoutePickerViewService` and
  `OutputDeviceMenuService` hold (checked on macOS 27.2: detailed discovery
  in-process lists no devices while route presence is detected), so the list
  is the one Safari shows. When a route becomes active, the element that
  opened the list (else the one already playing) gets the context's ID with
  should-play, and only that one, as `configurePlaybackTargetClients` does; a
  route ended (the user chose this Mac) takes it back. It implements
  `content::ParcPlaybackTargetHandler` (`content/public/browser/parc_playback_target.h`).
- Element and browser talk over the element's `media.mojom.MediaPlayer`
  (`ParcSetPlaybackTargetAvailability`, `ParcSetPlaybackTarget(id, device
  name, should_play)`) and `MediaPlayerObserver`
  (`OnParcPlaybackTargetStateChanged(requires_monitoring, supports_target,
  plays_to_target, wireless)`, `OnParcShowPlaybackTargetPicker(position)`),
  which `MediaWebContentsObserver` hands to the handler.
- Element (Safari-identity pages only, `fairplay-identity-blink.patch`):
  `webkitShowPlaybackTargetPicker()` (nothing before `HAVE_METADATA`; the list
  opens at the last mouse position, as `Document::showPlaybackTargetPicker`
  places it, and only for the visible page of the key window),
  `webkitCurrentPlaybackTargetIsWireless`,
  `webkitcurrentplaybacktargetiswirelesschanged` (in a media element task,
  `setIsPlayingToWirelessTarget`), `webkitplaybacktargetavailabilitychanged`
  as a `WebKitPlaybackTargetAvailabilityEvent` (`availability` "available"
  or "not-available"; the interface comes from
  `Engine/ParcRenderer/parc_webkit_playback_target.h`, whose hook Blink calls)
  at the first listener, a new player, HAVE_METADATA, a route change and the
  player's clearing, as WebKit queues it; `x-webkit-airplay="deny"`,
  `webkitwirelessvideoplaybackdisabled` and `disableremoteplayback` disable it
  (`isWirelessPlaybackTargetDisabledChanged`). The element keeps its target
  across loads (`mediaEngineUpdated`).
- Remote Playback, controls and placard (Safari-identity pages, for an
  element whose player plays to a target): `video.remote` is AirPlay, as
  WebKit's `RemotePlayback` on macOS (`RemotePlaybackController`'s Parc
  hooks): `prompt()` rejects before `HAVE_METADATA` or without devices while
  disconnected (`NotSupportedError`), else opens the route list; a pick
  resolves it and the state goes connecting, then connected when AVPlayer is
  external, disconnected when the route ends; a list closed without a choice
  rejects it with `NotAllowedError` (`ParcPlaybackTargetPickerDismissed`, sent
  a second after the list closes unchanged). Availability callbacks follow the
  AirPlay devices. The controls' cast button becomes Safari's AirPlay button
  in the bar after the volume, shown once the media has played, with the
  Mini Player's glyph and states (accent while connecting and connected,
  pulsing while connecting unless motion is reduced) and no overlay button;
  where Remote Playback stays Cast it stays in the overflow menu. While
  `webkitCurrentPlaybackTargetIsWireless`, the video's remoting interstitial
  is WebKit's AirPlay placard: "AirPlay" over "This video is playing on
  “<device>”." ("Apple TV" without a name) on black, icon, title and
  description by Placard's size thresholds. `webkitWirelessVideoPlaybackDisabled`
  is the attribute, `disableremoteplayback`, or no player
  (`MediaElementSession::wirelessVideoPlaybackDisabled`); setting it sets the
  attribute.
- Player: `WebMediaPlayer::ParcSetPlaybackTarget` and
  `ParcSetWirelessVideoPlaybackDisabled` reach the native HLS demuxer
  (`ParcNativeHlsDemuxerParams` for the one a load makes, then
  `Demuxer::ParcSetPlaybackTarget` on the media thread) and
  `FairPlayHlsPlayer.SetPlaybackTarget` / `SetWirelessVideoPlaybackDisabled`
  before `Initialize`. Only this route plays to a target, as only WebKit's
  AVFoundation player does (its Media Source and WebM players refuse one,
  `supportsTypeAndCodecs` and `checkPlaybackTargetCompatibility`).
- Clear files: Safari plays a src= file in AVPlayer, so it AirPlays. Here a
  clear HTTP(S) file Chromium's FFmpeg demuxer opened whose container
  AVFoundation plays (MP4/MOV/3GP, MPEG-2 TS, MP3, AAC, AC-3, E-AC-3, AIFF,
  AMR, CAF, FLAC, WAV; not WebM or Ogg) supports a target from
  `HAVE_METADATA` (`WebMediaPlayerImpl::ParcSupportsPlaybackTarget`, so the
  browser monitors routes and the Mini Player offers AirPlay). Played to one,
  `WebMediaPlayerImpl::ParcSwitchRoute` stops the pipeline and restarts it on
  this route (`DemuxerManager::ParcSetNativeRoute`, AVFoundation told the
  container's type), seeking to the element's time; given back the target
  (this Mac, or the route ended) it restarts on a new `MultiBufferDataSource`
  the same way. Rate, pause and volume stay with the pipeline. Until the new
  route has seeked, the element keeps its time (as a seek's target), duration
  and readyState, and the tracks Chromium listed stay (the route's own track
  reports are dropped); then the route's readyState applies (never lowered to
  `HAVE_METADATA`) and a different duration raises one `durationchange`. A
  file the native route can't open goes back to Chromium's pipeline at the
  same time and stops supporting a target, as WebKit turns the target down.
  Media Source never moves: WebKit's player refuses a target, and Safari's
  switch to a `<source>` alternative is `ManagedMediaSource`'s (AIRPLAY-3).
- GPU core: `FairPlayHlsPlayer::SetPlaybackTarget(id, should_play)` finds the
  context with `+[AVOutputContext outputContextForID:]` (an ID the media
  server doesn't know finds none) and sets `AVPlayer.outputContext` only
  while should-play; `allowsExternalPlayback` is `!disabled`; KVO of
  `externalPlaybackActive` and `allowsExternalPlayback` reports
  `OnPlaybackTargetIsWirelessChange`, which the service sends as
  `OnPlaybackTargetIsWirelessChanged`. Teardown sets the context back to none.
  The GPU sandbox allows the coremedia endpoint, route and volume services
  and timesync that WebKit's GPU process profile allows for AirPlay.
- Mini Player: `PCNativeMediaState.airPlayState` (Available, Connecting once a
  device is picked until AVPlayer is external, Connected) and
  `airPlayDeviceName`; `-[PCNativePage
  showAirPlayPickerForMediaState:relativeToRect:ofView:inWindow:dismissed:]`
  opens the same list at the row's AirPlay button.

Playback state, seeking, rate and volume need nothing new: AVPlayer drives the
device, and the element, Now Playing and the media keys keep driving AVPlayer.
A background tab keeps playing (native HLS is never suspended); a page entering
the back/forward cache pauses without events and resumes on return, as WebKit's
`stopWithoutDestroyingMediaPlayer`; navigating away destroys the player, which
ends playback on the device.

Checked on this Mac: `tests/FairPlay/hls_player_harness.mm` `airplay` (the
context reaches AVPlayer before and after it is made, comes off with
should-play off or an unknown ID, the disabled flag, local playback goes on
with no device in the context) and `file` (a clear MP4 served as
`application/octet-stream` and an MP3 play through the loader in byte ranges
with the target set and the container's type, from a seek to the element's
time); `tests/FairPlay/sandbox` plays native HLS and
FairPlay under the new rules. Needs an AirPlay receiver, unchecked: playback
moving to the TV, `externalPlaybackActive`, the device name, FairPlay keys on
the device, and the AirPlay services the GPU sandbox needs.

## Media element state and events

`AVPlayerItem` is the authority, as in Safari; the render process mirrors it.

| Element | Source in the GPU | Render-process path |
| --- | --- | --- |
| `HAVE_METADATA` | the asset's metadata keys loaded and the asset playable, before the item exists (WebKit's `updateStates`) | `OnInitialized` → demuxer init → pipeline metadata |
| `HAVE_CURRENT_DATA` | the layer's first frame (`readyForDisplay`, WebKit's `hasAvailableVideoFrame`), or `playbackBufferEmpty` | `OnReadyStateChanged` → demuxer's `ready_state_cb` → `WebMediaPlayerImpl::ApplyParcNativeHlsReadyState` sets it, up or down, as WebKit's element takes the player's; held while a seek is in flight |
| `HAVE_FUTURE_DATA` | item `readyToPlay` with media loaded past `currentTime` (and, with video, its first frame), WebKit's `updateStates` | as `HAVE_CURRENT_DATA` |
| media types (`hasVideo`, audio) | the variants at metadata (both assumed when they don't name codecs), then the item's `hasEnabledAudio`/`hasEnabledVideo` once it is ready to play and at each change (WebKit's `characteristicsChanged`) | `OnMediaTypesChanged` (after `OnLayerRegistered` when video appears) → demuxer's `media_types_cb` → `WebMediaPlayerImpl` updates the pipeline metadata, `DidMediaMetadataChange`, the video surface |
| `HAVE_ENOUGH_DATA` | `playbackLikelyToKeepUp` or a full buffer | as `HAVE_CURRENT_DATA`. The same state also goes to the pipeline as buffering (`OnBufferingStateChange` → facade's `RendererClient`, reported in the task after every `StartPlayingFrom`), which no longer sets `readyState` for this route |
| `currentTime` | `currentTime`, periodic observer (0 until the item is ready) | `OnTimeUpdate` → facade's `GetMediaTime` interpolates |
| `timeupdate` for a jump back | a time sent below the one before it, outside seeks, also sampled at each `AVPlayerItemTimeJumpedNotification` (WebKit's `MediaPlayerPrivateRemote::currentTimeChanged`) | `OnTimeJumpedBackward(seeks_received)` → demuxer's `time_jumped_cb` (dropped if the player hadn't received a seek sent since; a seek still in flight keeps the jump's time) → `WebMediaPlayerImpl::ParcNativeHlsTimeJumped` resets the pipeline's never-backward clamp → `HTMLMediaElement::ParcPlayerTimeChanged` |
| `duration` | the asset's until the item is ready to play, then the item's (indefinite = live), Live and DVR | demuxer's `DemuxerHost::SetDuration` (`kInfiniteDuration`) |
| `buffered` | `loadedTimeRanges` (none before the item loads) | `DemuxerHost::OnBufferedTimeRangesChanged` |
| `seekable` | `seekableTimeRanges` as one window, up to the duration before the item lists any, Live and DVR | demuxer's `GetParcNativeTimeline()`; `WebMediaPlayerImpl::Seekable()` answers it |
| `getStartDate()` | `round(currentDate − currentTime)`, Live and DVR | demuxer's `GetParcNativeTimeline()`; `WebMediaPlayer::ParcStartDate()` |
| seeking/seeked | `seekToTime:completionHandler:`; a seek before the item is ready to play waits for it (the latest only). `readyState` stays where AVPlayer has it (Chromium's drop to `HAVE_METADATA` is skipped), and `seeked` fires when the AVPlayer seek completes with `readyState` at `HAVE_CURRENT_DATA` or more (WebKit's `seekCompleted` and `resolveSeekPromiseIfNeeded`), not at `HAVE_ENOUGH_DATA`: a seek within what AVPlayer holds raises no `waiting`, `canplay` or `playing` | `Demuxer::Seek` / facade `StartPlayingFrom`; `WebMediaPlayerImpl::OnPipelineSeeked` applies the held `readyState` and calls `TimeChanged` |
| rate, pause | `rate` | facade `SetPlaybackRate` → `Play`/`Pause` |
| volume, muted | `volume`, `muted` | facade `SetVolume`; tab mute as the MSE route |
| `ended` | `AVPlayerItemDidPlayToEndTimeNotification` | `OnEnded` |
| `error` | an asset key that failed before metadata (`MEDIA_ERR_NETWORK` for a URL error or a misconfigured server, else `SRC_NOT_SUPPORTED`), then the item's `failed` status (`MEDIA_ERR_DECODE`), as WebKit's `assetStatus` and `updateStates` map them; `AVPlayerItemFailedToPlayToEndTime` isn't an error (WebKit doesn't observe it) | `OnError` |
| `audioTracks` / `textTracks` | `HlsMediaSelection` (Tracks) | `OnTracksChanged`, `OnTextCues` (Tracks) |
| decoded/dropped frames | `-[AVPlayerLayer videoPerformanceMetrics]` (`HlsFrameStats`) | `OnStatisticsUpdate` deltas (as fp-frame-stats) |
| `webkitneedkey` | every resource loader skd and clearkey request | `OnKeyRequest` → `ParcWebKitKeyRequest` |
| `encrypted`, `waitingforkey` | resource loader skd requests; waiting only for a request made while the player held no CDM, until a session has a request for the key or playback goes on | `OnEncrypted`, `OnWaiting`; `WebMediaPlayerImpl::ParcOnCdmEvent` or `BUFFERING_HAVE_ENOUGH` ends it |

## Tracks

The core's `HlsMediaSelection` (`fairplay/fairplay_hls_media_selection.h`,
[core README](../fairplay/README.md#native-hls-tracks)) is a port of WebKit's
AVFoundation track code: audioTracks from the audible media selection group
(WebKit choosing the option, AVFoundation's automatic criteria off), textTracks
from the legible group, cues from one `AVPlayerItemLegibleOutput` for the one
track the modes pick. GPU service: `media::FairPlayHlsTrackBridge`
(`fairplay_hls_track_bridge.{h,mm}`, the GPU source set) owns the selection
and does the rest; the service makes one with its client remote and
`PostTask`, calls `Attach(player.impl())` in `OnMetadata` (the item exists
then and isn't on the player yet), puts
`TakeTracksForInitialize()` in `OnInitialized`'s metadata, forwards
`SetAudioTrackEnabled`/`SetTextTrackMode`, and calls `WillSeek()` before each
`FairPlayHlsPlayer::Seek` and `DidSeek()` in its `done`, whatever the result.
The bridge attaches with `HlsMediaSelectionAttach(selection.impl(),
HlsPlayerAVPlayer(player.impl()), HlsPlayerItem(player.impl()))`, maps
`HlsTrack`/`HlsCue` onto `FairPlayHlsTrack`/`FairPlayHlsCue` field for field,
holds lists back until `OnInitialized`, and brackets seeks as WebKit does: the
selection's `BeginSeeking()` on every seek and `EndSeeking()` once the last
one is done (WebKit's `beginSeeking`/`endSeeking` on the current text track:
the open cue is flushed and cues arriving meanwhile get no end from the next
one; like WebKit, only the track current at the seek's start is flagged).
The GPU never picks a text track: it serves whichever one the page's modes
pick.

Page side, Safari-identity documents only (the route exists only there).
The demuxer gets `ParcNativeHlsDemuxerParams.track_manager`, a
`media::TrackManager` callable on the media thread that posts to the element:
`ParcSetInbandAudioTracks(tracks, set_enabled)` for audio, and
`ParcSetInbandTextTracks(tracks, set_mode)` / `ParcAddInbandTextCues(key,
cues)` for text (`media/base/media_track.h`, through `DemuxerManager` and
`WebMediaPlayerImpl` to `HTMLMediaElement`); the demuxer sends both lists at
`Initialize` and on every `OnTracksChanged`, holding lists and cues that
overtake the `Initialize` reply until it arrives. `set_mode` is a
`ParcInbandTextTrackModeCB` the demuxer binds to itself on the media thread
(`BindPostTask` with its weak pointer) that sends `SetTextTrackMode`; the
element calls it from the main thread on every in-band mode change.


- Audio: the element makes one Blink `AudioTrack` per audio
  `FairPlayHlsTrack` (added in list order, removed when gone, `enabled`
  followed), with WebKit's id (which can repeat; the element keys its tracks
  by `key`), kind (`description` as WebKit spells it), label and language.
  As in WebKit the tracks aren't exclusive: a page's `enabled` change goes
  to the player for that track alone (`set_enabled`, bound like `set_mode`,
  sends `SetAudioTrackEnabled`), not through the pipeline, and the other
  tracks follow when the player reports its selection. No placeholder audio
  track is made for this route.
- Text: M156 Blink defines `TextTrack::kInBand` but nothing creates such
  tracks, so `fp-hls-tracks` adds the minimal path: the player client makes
  Blink `TextTrack`s of type `kInBand` in the element's list (WebKit's kind
  `forced` included) and forwards their mode changes as
  `SetTextTrackMode(key, mode)`. Which track shows by default is WebKit's
  choice: the player scores the tracks as `HTMLMediaElement::configureTextTrackGroup`
  with `CaptionUserPreferencesMediaAF` does, from the system caption
  settings it reads in the GPU process (MediaAccessibility's display mode,
  caption languages and SDH preference, the user's languages) and the
  enabled audio track, and marks that one track `automatic`; the element's
  automatic selection shows it as its default and gives these tracks no
  score of Chrome's own. Chapter tracks (WebKit's
  `InbandChapterTrackPrivateAVFObjC`, one per chapter locale) arrive the
  same way with kind `chapters` and WebVTT cues. The metadata track (WebKit's
  `InbandMetadataTextTrackPrivateAVF`, kind `metadata`) arrives the same way
  with `inBandMetadataTrackDispatchType` `com.apple.streaming`; its timed
  and date range metadata come as data cue changes (`OnDataCues`) that the
  track applies as WebKit's `InbandDataTextTrack` does to Blink `DataCue`s,
  a Safari-identity-only interface Parc adds (`parc_data_cue.*`). Cues
  become `VTTCue`s as WebKit's `InbandGenericTextTrack` makes them (`kWebVtt`
  parsed like `WebVTTParser::parseCueData`, the header for regions and style
  sheets, generic cues added, updated and removed by `cue_id`, an open cue's
  end shown as the media duration, +inf for live). A generic cue draws its
  colours as WebKit's `TextTrackCueGeneric` does (foreground and highlight
  on the text, background on the box) and wraps only when its markup allows;
  its font size and font name are kept, as in WebKit, not drawn.

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

- `duration`: the asset's at `loadedmetadata` (WebKit's `platformDuration`
  reads the item only once it is ready to play), then the item's, +Infinity
  when indefinite (live), 0 when invalid. `durationchange` fires at
  `loadedmetadata` and then only when the value
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
  each buffering change (there is no item, so no date, at `loadedmetadata`)
  and sends `OnStartDateChanged` just before the `OnBufferingStateChange`.
- Seeking: the element clamps to the duration and then to the nearest point
  of the one seekable range, as WebKit's `seekTask` does, so a seek past the
  window's end lands on the live edge and one before its start on the oldest
  DVR point. The player seeks exactly, except for `fastSeek()`: its
  tolerance (`Demuxer::ParcSetFastSeek`) reaches AVPlayer's
  `toleranceBefore`, and the clock and the pipeline take the time AVPlayer
  landed on, which `Seek` answers. On Safari-identity pages `currentTime`
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

1. This design. 2. Routing. 3. GPU player with clear HLS and network through
Chromium. 4. Display. 5. skd keys and modern EME. 6. Live/DVR, tracks, frame
counts, legacy EME. 7. The route turned on for Safari-identity pages, with
no switch left.

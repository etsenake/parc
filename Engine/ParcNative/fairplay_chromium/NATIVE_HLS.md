# Native HLS and AirPlay

Safari-identity pages use Parc's native HLS route: AVPlayer in the GPU media
service, with network requests performed by the page's Chromium loader and
FairPlay keys supplied through the page's CDM. Other pages keep Chromium's HLS
route. This guide describes current source; [product status](../../../docs/parity.md)
records release delivery.

## On for Safari-identity pages

The route has no user switch. HLS URL detection includes `.m3u8`, a sniffed HLS
response and supported HLS MIME types in `data:` URLs. AVFoundation decodes data
playlists itself, while referenced segments use the page loader. `blob:`
playlists are refused because AVFoundation cannot open them.

Safari-identity pages also expose legacy WebKitMediaKeys systems
`com.apple.fps`, `com.apple.fps.1_0` and `org.w3c.clearkey`. Modern EME and legacy
key events share the native player without moving web content out of Chromium.

## Process: the GPU process

The player, CDM and protected-layer registry share the GPU process. Content-key
recipients must be native objects in the CDM's process. The media service thread
owns the player; it does not require a run loop.

The GPU sandbox gains no network access. The AVURLAsset uses exclusive client URL
loading and a resource-loader URL-session adapter. Required OS interfaces are
checked before loading; unsupported systems refuse the route. All ordinary
loads return to Chromium, preserving profile, cookie, proxy and CORS behavior.

## Routing (render process)

`HTMLMediaElement` passes document identity through `WebMediaPlayerImpl` to
`DemuxerManager`. The manager selects `NativeHlsDemuxer` from the registered
`kFairPlayHls` factory. The demuxer connects to the GPU player and reports real
metadata through placeholder audio/video streams; those streams never supply
encoded buffers.

`NativeHlsRenderer` is a media-thread facade driving that same player through
`MediaResource::GetParcNativeHlsSource()`. The demuxer owns the connection so
metadata can precede renderer construction. CDMs set before renderer creation
reach the demuxer directly. The pipeline and `DemuxerManager` reach the player
through the same source (`media/base/parc_native_hls_source.h`) for its CDM,
timeline, clear keys, AirPlay target and file track choices, so Chromium's
`Demuxer` carries none of them. Suspend/resume of the renderer facade does not
create another native player.

Native HLS is exempt from ordinary idle/background/frozen-frame suspension and
hidden-video disabling from the moment the demuxer exists. Preload policy lives
in AVPlayer; a Chromium suspension must not strand a pending seek by deleting
its facade. Explicit pipeline restarts still apply.

Initialization errors fail demuxer initialization; later failures reach the
renderer client or demuxer host. GPU disconnection is a pipeline-disconnected
error. Key waits and layer registration arriving before the facade are replayed.
Buffering is reported between StartPlayingFrom and Flush, and ended is delivered
once per run. Time interpolates the latest native sample at its actual rate,
bounded by the timeline; a pending seek exposes its target.

## Mojo

The authoritative interfaces are in `fairplay_media.mojom` beside this guide.
Do not copy their complete schemas into this guide.

| Boundary | Contract |
| --- | --- |
| Renderer → browser | Create a player through the frame's `FairPlayMediaHost`, naming the player whose audibility grant it holds; the renderer supplies no lifetime. |
| Browser → GPU | Forward to the document's `FairPlayFrameMedia`, which also hosts its CDMs, adding a browser-owned audibility lifetime with that player's grant. Frameless documents have no host. |
| GPU service | Own the core player, track bridge, CDM loader, mute observer and registered layer. Destroy players before their CDMs. |
| GPU → renderer | Ordered initialization, metadata, buffering, time, tracks/cues, key events, errors and statistics on the client pipe. |
| Per-load transport | Response metadata plus a data pipe, completion and cancellation. Completion must wait for body drain. |

Initialization is answered on the client pipe, not the player's pipe, so earlier
errors, layer state and metadata remain ordered. A second Initialize is invalid.
Track changes before initialization fold into its metadata; later lists replace
the previous list by stable track key.

Before metadata, the client receives only asset loads and asset errors. Metadata
comes from playable asset keys before item creation, so loadedmetadata precedes
key events and cues. The video layer token is registered before publication.
A metadata preload loads playlists without attaching the item or requesting keys.
Preparing to play, auto preload, autoplay, play/seek and live media attach it;
an element that has prepared once retains that state across later loads.

Time updates occur on play, pause, seek, buffering and end, and every 125 ms
while the requested rate is positive. They carry actual native rate, which can
be zero during a wait. The player is muted until the browser's first mute answer
and whenever the tab or page mutes. Network, decode and unsupported-source errors
retain distinct pipeline statuses.

## GPU core player

`FairPlayHlsPlayer` in `Engine/ParcNative/fairplay` owns the AVURLAsset, AVPlayer,
item, layer and timeline. Its public methods run on one owner sequence; client
callbacks are posted, never invoked inside a call into the core. Creation is
split into CreateAsset, key-loader installation and Start to guarantee that no
key request precedes its handler.

Core fixtures exercise playlists/segments through a host reachable only by the
client loader, metadata errors, clear and protected playback, seeks, cancellation
and teardown. They also show that AVFoundation may retry failed key requests or
live variants without immediately failing the item.

## Network (render process)

`blink::FairPlayHlsLoader` creates a WebAssociatedURLLoader from the element's
ResourceFetchContext with its actual CORS mode, credentials and media destination.
Requests therefore use the page's cookies, referrer, proxy and DevTools context.

- Only GET/HEAD over HTTP(S) are fetched. Key schemes never enter this loader.
- Only a well-formed Range header is forwarded from AVFoundation. The page's
  identity supplies User-Agent; native playback-session headers are omitted.
- Range loads use identity encoding through Chromium's normal media path.
  Non-range playlist responses may be decompressed by the network stack.
- Redirects retain CORS enforcement and report their final URL for relative
  resource resolution. MIME type and real status/headers reach AVFoundation.
- A decoded response reports unknown length and removes stale encoded length
  and encoding headers.
- A 512 KiB body pipe provides backpressure. Cancellation, closed peers or early
  consumer closure cancel the actual URL loader; destroying the owner cancels all.
- The GPU waits for the body pipe to drain before delivering completion, even
  when the completion message arrives first. Failed loads deliver their already
  received partial body before the error.

## Keys

The asset's `FairPlayHlsKeyLoader` holds each `skd://` resource request. It does
not make the asset a content-key recipient. A held loading request must generate
its own SPC and receive its own CKC; transferring it to the session after holding
it does not work on the tested OS and would suppress legacy events.

Every request first raises `webkitneedkey`, including repeated URIs. Modern
`encrypted` follows when no session already requested that key. A no-CDM wait is
decided in the GPU when the request arrives, because CDM attachment crosses a
different pipe. A later matching session or resumed native playback ends it.

`generateRequest("skd", uri)` matches the held request by URI; a session created
first waits for the asset. The URI is the content identifier unless the legacy
session supplied its own. Attaching an asset records its CDM without creating
an AVContentKeySession: session-creation failure rejects the request and leaves
the asset available for a retry.

Replacing or dropping MediaKeys changes later requests while already delivered
keys remain with the asset. Resource-loader keys have no AVContentKey renewal or
revocation object. Closing a session before answering leaves its request pending;
a seek-cancelled request can later produce another license request. Output
protection comes from AVPlayer's obscured-output state.

Metadata precedes legacy key events. Legacy sessions created before their keys
are attached have no player and do not become usable retroactively. Modern
sessions support attachment/licensing in either order.

### Legacy clear key (`clearkey://`)

Legacy clear-key requests raise `webkitneedkey` with the URI's resource-specifier
key ID, without modern encrypted events. Cached keys answer immediately. New
JWK keys travel through the element, WebMediaPlayer and demuxer to ProvideClearKey;
the core fulfills the requested range and caches the key for later requests.

## Display

The GPU registers the player's AVPlayerLayer under an unguessable token.
NativeHlsRenderer paints a video-hole frame through the existing VideoRendererSink;
the compositor places the actual layer. Size changes update renderer metadata
before repainting the hole. Teardown unregisters the token before player deletion.

The layer receives the element's initial content-box size and display scale in
an unhosted CAContext before attaching its item. That gives AVFoundation the
correct initial variant-selection size. The compositor takes the layer when the
page draws it. Audio elements or elements without a layout box defer sizing.
Protected capture is enforced by AVFoundation; clear HLS stays capturable.

### Picture in Picture and fullscreen

PiP uses Parc's existing panel/compositor and moves the same layer; it does not
create another player. Leaving PiP returns it to the page. Fullscreen resizes
the page compositor. Natural-size changes continue updating panel aspect ratio,
and hidden-video exemptions preserve playback. See [compositing](COMPOSITING.md).

Component fixtures cover moving the layer between remote contexts and hidden
hosts, resizing and variant selection.

## AirPlay

`native_airplay.mm` owns one route detector and the system AVRoutePickerView
presentation. The system service lists and chooses devices; Parc does not gain
private device-list entitlements or implement its own chooser. Only the element
that requested the route, or the current routed player, receives its output
context ID. Returning to this Mac removes it.

Safari-identity elements expose WebKit availability/wireless events and picker
methods. The picker requires metadata and a visible page in the key window.
AirPlay-deny and remote-playback-disabled attributes disable it. The selected
target survives element loads.

For a supported player, Remote Playback is AirPlay: prompt rejects without
metadata/devices, resolves a route choice, and reports connecting/connected from
actual AVPlayer state. Dismissal without a choice rejects the pending prompt.
Controls and the Mini Player use the same route and show its device name; the
video displays an AirPlay placard while wireless playback is active.

Native HLS plays through AVPlayer's output context. Clear HTTP(S) files with
AVFoundation-supported containers can switch from Chromium to this route at the
same time, retaining pause/rate/volume and track selection. Returning locally
restarts Chromium with those values. Live reconnection offsets timeline values
so the element continues on its previous timeline. An unsupported native file
falls back locally and stops advertising a target.

Media Source does not move directly. With an eligible alternate source, a target
change can select that alternative while retaining time, pause and rate; without
one it stays local. ManagedMediaSource waits to open until remote playback is
disabled or a suitable non-blob alternative exists.

Background tabs keep playing. Back/forward caching pauses without synthetic
page events and resumes on return; navigation destroys the player and ends the
route. Now Playing and media keys continue driving the same element/player.
Core fixtures cover context attachment, route removal, local playback and file
track transfer.

## Media element state and events

AVPlayerItem supplies native state; the renderer mirrors it rather than inventing
readiness from pipeline buffering. Metadata precedes key events. Current/future/
enough-data reflect the item, first-frame readiness and buffered data. During a
seek the element retains native readiness and completes seeked at current-data
or better, without requiring enough-data or spurious waiting/playing events.

Native time jumps can move currentTime backward outside a seek. Seek counters
reject stale jump notifications. Duration, loaded and seekable ranges update
independently. Track/media-type changes update metadata and video surfaces;
errors preserve network/decode/unsupported distinctions.

## Tracks

`FairPlayHlsTrackBridge` connects `HlsMediaSelection` to the element's track
manager. Initialize contains the first list; later snapshots replace tracks by
stable key, because visible IDs can repeat. Lists/cues overtaking initialization
are held until it completes. Weak callbacks post page choices to the media thread.

Audio enablement controls the native option and reports all resulting states.
Text modes select one legible output; system caption/language/accessibility
preferences choose the automatic default, and the page can override it. Chapter
tracks carry WebVTT, and metadata tracks carry streaming DataCues. Generic cues
preserve IDs, timing, colors and wrapping; font metadata is retained but not
rendered. Seek bracketing flushes open cues and discards stale changes.

## Frame counts

HlsFrameStats reads AVPlayerLayer metrics on a private queue every 250 ms while
playing and once more on stopping. It holds the layer weakly and never calls back
after destruction. A decreasing nonzero counter starts a new native decoder run;
its full values are added so variant switches do not freeze page statistics.
All-zero samples are ignored. Decoded bytes remain zero.

Parc deliberately exposes the same accumulated count to webkitDecodedFrameCount
and getVideoPlaybackQuality; Safari's HLS legacy decoded counter instead stays
zero. This shared-statistics choice is intentional.

## Live and DVR

HlsTimeline reports the asset duration at metadata, then the ready item's
value: infinity for live, zero when invalid. Duration changes only when the value
changes; a live playlist gaining ENDLIST does not shrink an already observed end.
Seekable combines valid ranges into one window and falls back to duration while
native ranges are absent. Seek targets clamp to that window, including its live
edge; fastSeek carries its tolerance and reports the actual landing time.

Safari-identity currentTime accepts unrestricted numbers: positive infinity
seeks to the live edge, negative infinity and NaN to zero. getStartDate uses
rounded currentDate minus currentTime, sampled at buffering changes and delivered
before the corresponding state event. Without program date/time it is invalid.
The demuxer protects cached timeline values for cross-thread queries.

The identity-only getStartDate interface is installed with its context's media
element interface object; a reused context whose earlier document already created
that object may lack it, along with the other identity-only media members. This
limit stays: no affected site is known, and players that use getStartDate check
for it and carry on without it.

## Threads

GPU player operations run on the media service thread. AVFoundation KVO,
notifications, periodic observers and resource callbacks post captured values to
that sequence. The demuxer and renderer run on the renderer media thread;
network loading and DOM delivery run on the renderer main thread. Teardown
invalidates callbacks at each boundary before dropping its owner.

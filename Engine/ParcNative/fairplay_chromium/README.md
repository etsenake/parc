# FairPlay in Chromium

FairPlay Streaming is an ordinary Chromium DRM option in Parc. Sites ask for
`com.apple.fps` (or a versioned `com.apple.fps.N_M`) through standard EME, as
Netflix and Apple TV+ do once they see Safari's identity. The CDM and the
media renderer run together in the GPU process's media service, because the
playback core's renderers get their keys only as content key recipients of
the CDM's `AVContentKeySession` (see [the core](../fairplay/README.md)).

This directory holds the Chromium-side sources. The overlay installs them at
`//third_party/parc_fairplay`, next to the core
(`Engine/ParcNative/fairplay` → `//third_party/parc_fairplay/core`). It is
under third_party so Chromium's clang style plugin and unsafe-buffers checks,
which the core predates, don't apply. Upstream hunks are in
`Engine/ParcHost/integration/fairplay-media*.patch`.

## Status

The production overlay includes CDM registration, GPU renderer and sandbox
integration, tab mute/audibility and native HLS. Current shipping status is in
[product status](../../../docs/parity.md).

[Native HLS](NATIVE_HLS.md) describes URL playback through AVPlayer. The rest of
this guide covers demuxed samples and the Chromium/CDM boundary.

## What is where

| Piece | Where |
| --- | --- |
| Key system names | `fairplay_key_system.h` (`IsFairPlayKeySystem`, same rule as the core and WebKit) |
| `media::ContentDecryptionModule` + `CdmContext` | `fairplay_cdm_adapter.{h,cc}` over `parc::fairplay::FairPlayCdm` |
| Parc's FairPlay media service (GPU) | `fairplay_media_service.{h,cc}` (`:service`) and `fairplay_media.mojom`: `ParcContentGpuClient::ExposeInterfacesToBrowser` binds `media.mojom.FairPlayMediaService` on a single-thread task runner configured like the GPU media service's runner. Each document gets a `FairPlayFrameMedia` hosting its CDMs (`MojoCdmService`), FairPlay Renderers (`MojoRendererService`) and native HLS players. A render process's documents share one `MojoCdmServiceContext`, so CDM IDs resolve within that process only |
| Browser host | `parc/native/fairplay_media_host.{h,cc}` (`FairPlayDocumentHost`, one per document): serves `FairPlayMediaHost` to the render process (`ParcContentBrowserClient::RegisterBrowserInterfaceBindersForFrame`) and `FairPlayFrameHost` (storage, salt, ephemeral session, audio output, tab mute) to the GPU service, which it reaches with `content::BindInterfaceInGpuProcess` and reconnects after a GPU restart |
| CDM factory | `fairplay_cdm_factory.{h,cc}`, used by `FairPlayFrameMedia`, with the document's `FairPlayFrameHost` answers |
| CDM routing | `MediaInterfaceProxy::CreateCdm` runs Parc's CDM creator (`parc_hooks::SetFairPlayCdmCreator`, `FairPlayDocumentHost::CreateCdm`) after the Widevine observer. FairPlay key systems go to the document's `FairPlayFrameMedia`, before the library CDM path (which would look for a CDM binary) |
| Renderer selection | `CdmContext::RequiresFairPlayRenderer()`, carried to the render process as `mojom::CdmContext.requires_fairplay_renderer`; `PipelineImpl` then asks for `RendererType::kFairPlay`. In the GPU process the FairPlay renderer and HLS player reach the key session with `FairPlayCdmAdapter::GetFairPlayCdm()` |
| GPU `media::Renderer` | `fairplay_renderer_adapter.{h,mm}` over `parc::fairplay::FairPlayRenderer`, created by `FairPlayFrameMedia::CreateRenderer` |
| Render-process client | `fairplay_renderer_client{,_factory}.{h,cc}` → `//content/renderer/media/fairplay`, registered as `kFairPlay` (never the base renderer) by `fairplay_renderer_factories.{h,cc}`, which `MediaFactory` calls to add the FairPlay and native HLS factories, give them the built player's ID and move them. `fairplay_media_host_connection.{h,cc}` is the frame's pipe to its `FairPlayMediaHost`, callable from any thread |
| Display handoff | layer token over `mojom::FairPlayRendererClientExtension.OnLayerRegistered`; `ui::ProtectedLayerRegistry` and the compositor side in [COMPOSITING.md](COMPOSITING.md) (fairplay-compositing) |
| Native HLS (Safari's AVPlayer route) | [NATIVE_HLS.md](NATIVE_HLS.md): `mojom::FairPlayHlsPlayer` over `FairPlayMediaHost.CreateHlsPlayer`; GPU `fairplay_hls_player_service.{h,mm}` (`FairPlayFrameMedia::CreateHlsPlayer`); render-process loads `fairplay_hls_loader.{h,cc}` → `//third_party/blink/renderer/platform/media` |
| Key system registration | `fairplay_cdm_info.{h,cc}` and `fairplay_key_system_info.{h,cc}` (`:registration`), from one capability: `ParcContentClient::AddContentDecryptionModules` lists the `CdmInfo` after Chrome's CDMs (browser), and `ParcContentRendererClient::GetSupportedKeySystems` adds the `KeySystemInfo` to each of Chrome's key system updates (renderer) |
| Widevine request hook | `parc::fairplay::SetWidevineCdmRequestObserver` (`parc_fairplay_hooks.h`, defined in `media_interface_proxy.cc`), for fairplay-identity |
| VideoToolbox decoder facts | `parc_video_toolbox_decoding.{h,mm}` → `//content/browser/media`, with its own `parc_video_toolbox_decoding.mojom` in `//media/mojo/mojom`: the browser reads what WebKit's MediaCapabilities asks VideoToolbox (H.264 hardware, HEVC per-profile hardware and levels, Dolby Vision profiles and levels) once and serves `media.mojom.ParcVideoToolboxDecoding` to frames (`ParcContentBrowserClient::RegisterBrowserInterfaceBindersForFrame`) and dedicated workers (`browser_interface_binders.cc`), for Safari-identity `decodingInfo`. `ParcContentBrowserClient::AppendExtraCommandLineSwitches` gives each renderer the AV1 hardware-decoder answer |
| Renderer hand-off and reverse turn | `parc_renderer_transitions.{h,cc}` → `//media/base`, owned by PipelineImpl's renderer wrapper; the split readers in `parc_chunk_demuxer_hand_off.{h,cc}` → `//media/filters`, owned by each ChunkDemuxerStream and the ChunkDemuxer ([why](../../../docs/chromium-seams.md#media-player-boundaries)) |
| GPU sandbox | `sandbox/policy/mac/gpu.sb`, rules listed below |
| Parc operations on Chromium's media interfaces | `parc_renderer_extensions.h`, `parc_pipeline_extension.h` and `parc_demuxer_stream_extension.h` → `//media/base`: `Renderer`, `AudioRenderer`, `VideoRenderer`, `Pipeline` (and `PipelineController`) and `DemuxerStream` each declare one `GetParcExtension()`, null by default, so Parc's backward playback, mixed audio, output device, hand-off and stream calls change without rebuilding every includer of those headers |

FairPlay has its own GPU service and browser host, built from Chromium's public
media service classes. It doesn't make the GPU renderer the default for ordinary
pages or change Chromium's media services. Chromium keeps one CDM hook, so
Blink's EME path is unchanged.

## Call flow (CDM)

1. Blink's `MediaKeys` asks the render process's `MojoCdmFactory`, which sends
   `InterfaceFactory::CreateCdm` to the browser's `MediaInterfaceProxy`
   (UI thread), which hands it to Parc's CDM creator.
2. `FairPlayDocumentHost::CreateCdm` sees a FairPlay key system. If
   `CdmRegistryImpl` has no `CdmInfo` for it, it refuses
   (`kUnsupportedKeySystem`), as Chromium does for any unregistered key
   system. Otherwise it forwards it to the document's `FairPlayFrameMedia`,
   the one that also serves the document's renderers. The
   `MojoCdmServiceContext` the render process's documents share is what lets
   a renderer find the CDM by its ID later, also in another frame a
   Safari-identity page moved the element to.
3. In the GPU process, `FairPlayFrameMedia` → `MojoCdmService` →
   `FairPlayCdmFactory::Create` → `FairPlayCdmAdapter`, on the FairPlay
   media service's sequence. On macOS `kDedicatedMediaServiceThread` is on, so
   that's a ThreadPool single-thread task runner with no run loop, not the GPU
   main thread; its worker may be shared.
4. Session calls arrive over `mojom::ContentDecryptionModule` and go to the
   core on the same thread. The core posts its callbacks to that thread
   (`fairplay_task_runner.h`). Promises are tracked by a `CdmPromiseAdapter`,
   so a callback that arrives after the CDM is gone is dropped and the promise
   is rejected on destruction. `close()` resolves from a posted task, so the
   session-closed event reaches Blink first: Blink drops the session when the
   close promise resolves, and the core settles the promise before it reports
   the session closed.

Init data: `cenc`, `keyids`, and on Safari-identity documents `sinf`, `skd`
and `mpts` (fairplay-media.patch adds them to `EmeInitDataType`; Blink treats
them as unregistered elsewhere). `sinf`, `skd` and `mpts` pass to the core
unchanged, as WebKit passes them. Netflix and Apple TV+ use `cenc` only. Sessions:
temporary, and Safari's `persistent-usage-record` on Safari-identity documents
(fairplay-media.patch adds it to Blink's and Chromium's session types; the key
system info offers it only where the render process can persist data, and the
CDM takes it only with the CdmConfig's `allow_persistent_state`, as WebKit's
`isLicenseTypeSupported`). Session IDs are WebKit's: the uppercase hex of a
random 16-byte identifier. A CDM whose configuration allows persistent state
asks the document's `FairPlayFrameHost.GetStorageDirectory` (the browser's
`FairPlayDocumentHost`) for its storage, WebKit's per-origin
MediaKeys directory: `<Profile engine folder>/Parc FairPlay/MediaKeys/`, then
the SHA-256 of the top-level origin and of the frame's origin, created by the
browser, empty off the record or for an opaque origin. The core then creates
its AVContentKeySession with `SecureStop.plist` there, which the GPU sandbox
allows (`gpu.sb`). `remove()` follows WebKit's `removeSessionData`: keys
revoked; a persistent-usage-record session reports the expired-session
reports AVFoundation keeps under its session ID as released keys and a
`license-release` message (none on macOS, where reports are named by the
shared key session), a temporary one rejects with NotSupported after an empty
key status change; `update("acknowledged")` removes reports found. `persistent-license` rejects with NotSupported, as
on Safari for macOS. `CdmContext::ParcHasSessionForInitData` (asked by a
Safari-identity Media Source element through MojoCdm before it fires
`encrypted` with `sinf`) answers from `FairPlayCdm::HasSessionForInitData`.
Every FairPlay CDM also asks `FairPlayFrameHost.GetDeviceIdSalt`
for the frame's media device ID salt (`GetMediaDeviceSaltAndOrigin`), WebKit's
MediaKeys hash salt, which randomizes the device identifier in its SPCs (core
README, "Device identifier").
`LoadSession` is WebKit's `loadSession`: a persistent-usage-record session
loads the expired-session reports under its ID (resolving with an empty ID,
EME's false, when there are none), other types reject with NotSupported.
`GetStatusForPolicy` rejects with NotSupported.

## Call flow (playback)

1. Blink's `setMediaKeys` attaches the `MojoCdm`. Its
   `RequiresFairPlayRenderer()` is true, so `PipelineImpl` asks the
   `RendererFactorySelector` for `RendererType::kFairPlay` when it creates the
   renderer (encrypted streams wait for the CDM first). Without a FairPlay CDM
   the pipeline is unchanged.
2. `FairPlayRendererClientFactory` makes a `MojoRenderer` through
   `FairPlayMediaHost.CreateRenderer` (render process → browser's
   `FairPlayDocumentHost` → the document's `FairPlayFrameMedia`). The
   `FairPlayRendererClient` that wraps it binds the client extension.
3. In the GPU process, `FairPlayFrameMedia` hosts `FairPlayRendererAdapter`
   under a `MojoRendererService` with the render process's
   `MojoCdmServiceContext`. `SetCdm(cdm_id)` therefore resolves the frame's
   FairPlay CDM, and the adapter hands its key session to the core
   (`FairPlayRenderer::SetCdm`, before `Initialize` is fine).
4. `Initialize` hands the core Chromium's decoder configs as they are: the
   codec, the coded and natural size, the AudioSpecificConfig (empty
   `extra_data` for MP4 video and for AC-3/E-AC-3, which the core builds from
   the first keyframe or syncframe), Dolby Vision's profile and level, and the
   encryption scheme only. H.264/HEVC/DV go as Annex B, AV1 as stored, AAC with
   ADTS. The core builds protected formats from each sample's `DecryptConfig`
   (key ID, pattern, 16-byte IV), so clear lead works. `kConfigChanged` goes
   to `FairPlayRenderer::Reconfigure`, also for a new codec: MSE `changeType`
   stays allowed for FairPlay players (Netflix switches audio languages, e.g.
   E-AC-3 to AAC, and video codecs the same way), but only among the codecs
   the renderer plays: `WebMediaPlayerImpl` gives the demuxer a filter
   (`ChunkDemuxer::RestrictCanChangeType`) that accepts AAC, AC-3, E-AC-3, FLAC,
   Opus, ALAC, H.264, HEVC and Dolby Vision 5 and 8 (and on Safari-identity
   pages 10, played as a 'dav1' entry with av1C and dvvC, PCM, `ipcm` and
   `fpcm`, AV1, VP9 profiles 0 and 2, and Vorbis), so any other codec makes
   `changeType()`
   throw NotSupportedError instead of failing playback. The core builds the
   new formats from the next samples, protected ones per key ID.
   `tests/FairPlay/sandbox` switches protected AAC → clear E-AC-3 → protected
   AAC under protected H.264, and clear H.264 → HEVC → H.264, with no
   underflow.
5. With video, the adapter registers the core's display layer host (a
   `CALayer` holding its `AVSampleBufferDisplayLayer`, or two while a new one
   takes over after `SetCdm`) in
   `ui::ProtectedLayerRegistry` under a new `UnguessableToken` and sends
   `OnLayerRegistered(token, natural_size)`. The client paints
   `VideoFrame::CreateVideoHoleFrame(token, natural_size)` through
   `VideoRendererSink::PaintSingleFrame`, and again on every natural-size
   change. cc makes it a `VideoHoleDrawQuad`, and fairplay-compositing's
   `CARendererLayerTree` places the registered layer there.
6. The core pulls more data with `OnNeedData`. Each `DecoderBuffer` goes to the
   core still encrypted, with its `DecryptConfig` (key ID, 16-byte IV,
   subsamples, pattern). The core holds samples until their key is usable and
   reports `OnWaiting(kNoDecryptionKey)` meanwhile. Buffering state, ended,
   natural size and errors go back through `RendererClient`.
7. While the clock runs (started, rate above 0) the adapter polls the core's
   `LoadVideoMetrics` every 250 ms and reports `OnStatisticsUpdate`, which
   `PipelineImpl` adds up as deltas into what `getVideoPlaybackQuality()`,
   `webkitDecodedFrameCount`/`webkitDroppedFrameCount` and the decoded byte
   counts read, at least as often as Safari's GPU process refreshes them for
   the page while playing (at the page's read interval, checked every 250 ms:
   `RemoteAudioVideoRendererProxyManager`, `RemoteMediaPlayerProxy`).
   On macOS 14.4+ the frames come from
   `AVSampleBufferVideoRenderer`'s `AVVideoPerformanceMetrics`: the decoder's
   own count, cumulative for the layer's lifetime, including frames decoded
   ahead of the clock (as `RendererImpl` counts them) and real drops. Before
   14.4 there is no such API, so the core counts the video samples whose
   presentation time the clock reached, with no drops. A total only adds
   what goes past the last one reported, so a late answer or a switch
   between the two adds nothing twice. Bytes are those of the samples handed
   to the core. Pausing or seeking stops the poll after one last count. The
   memory, keyframe-distance, frame-duration, power-efficient and
   decoder-name fields stay unset, as upstream's `MediaFoundationRenderer`
   on Windows leaves them (it reports decoded and dropped deltas from a
   500 ms poll while playing). Pages don't read those fields. Blink's
   `VideoDecodeStatsReporter` does: with no frame duration it files FairPlay
   sessions under the 5 fps bucket in the MediaCapabilities
   history, where no 24, 30 or 60 fps `decodingInfo` query looks, just as it
   does for MediaFoundation. Reporting a frame duration would need the
   power-efficient count as well, or `decodingInfo` would start answering
   `powerEfficient: false` for FairPlay configs.
8. `Flush` drops what is queued and waits for reads already in flight (the
   demuxer aborts them before a seek). Teardown flushes the display layers
   with removal of the displayed image, unregisters the host, then destroys
   the core,
   which leaves the CDM's key session. `MojoRendererService` destroys the
   renderer before it drops the CDM reference.

## Threads and processes

- Browser, UI thread: `MediaInterfaceProxy` (Widevine and CDM hooks),
  `FairPlayDocumentHost` and `CdmRegistryImpl`.
- Render process, media thread: `FairPlayRendererClient`, `MojoRenderer` and
  `MojoCdm`. Blink's key system info is evaluated on the main thread. A
  factory's renderer or player request hops to the frame's main thread
  (`FairPlayMediaHostConnection`), as the frame's InterfaceFactory requests
  do, then reaches the browser host on the UI thread.
- GPU process, the FairPlay media service's sequence: `FairPlayCdmAdapter`,
  `FairPlayRendererAdapter`, `FairPlayHlsPlayerService` and the core. It is
  chosen as the GPU media service chooses its own: on macOS
  `kDedicatedMediaServiceThread` is on, so that's a ThreadPool single-thread
  task runner with no run loop, not the GPU main thread; its worker may be
  shared. The core posts every AVFoundation callback to it. CALayer creation
  is wrapped in an explicit CATransaction there. The compositor touches the
  layer only from the GPU main thread, and only its placement.
- Audio goes from `AVSampleBufferAudioRenderer` straight to CoreAudio from the
  GPU process, never through Chromium's audio service. Web Audio's
  `createMediaElementSource` doesn't see it. Tab mute, the tab's audio
  indicator and `setSinkId` do, the first two the way MediaFoundation's
  renderer gets them on Windows:
  - Mute: `FairPlayFrameMedia::CreateRenderer` registers a
    `mojom::FairPlayMuteStateObserver` with the document's
    `FairPlayFrameHost`. The browser answers with the tab's state at once
    and on every change; the adapter mutes the core (`SetMuted`, kept until
    the core is initialized). Until that first answer the adapter keeps the
    audio muted, so a muted tab plays no sound while it is on its way. The
    observer closes with the renderer.
  - Indicator: `FairPlayDocumentHost::CreateRenderer` holds an
    `AudibilityBypassTracker` grant in the proxy it puts between the GPU
    adapter and the render-process client, so the grant ends with the GPU
    renderer. The grant is the player's own
    (`AudibilityBypassTracker::AddPlayerGrant`, keyed by the ID `MediaFactory`
    gives the factories once the player exists), so players never take each
    other's, and an unclaimed grant follows its player to another frame of the
    process. The player reports that it doesn't use the audio service, so
    `MediaWebContentsObserver` claims the grant and registers it with
    `AudioStreamMonitor` while the player is audible. A frame gets the grant
    only after it asked `CreateCdm` for a registered FairPlay key system, or
    when it presents Safari's identity. The native HLS player's lifetime
    handle holds its grant the same way.
  - Output device (`setSinkId`): the element's audio sink still switches
    and checks the device, so the promise settles as for clear media. Once
    it has, `WebMediaPlayerImpl` tells the pipeline, which tells its
    renderers (`ParcRendererExtension::ParcOnAudioOutputDeviceChanged`), and
    the render-process client sends the hashed ID its sink names, as at
    `Initialize`, over `FairPlayRendererExtension` (or `FairPlayHlsPlayer`).
    The GPU process asks the browser for its Core Audio UID
    (`FairPlayFrameHost.GetAudioOutputDeviceUid`), so the page
    never sees one, and the core puts every audio renderer, later and mixed
    ones too, on it (`AVPlayer` for native HLS), as WebKit's
    `setOutputDeviceId` does.
  - The layer token (`OnLayerRegistered`) goes through that proxy on the
    browser's UI thread, so a busy UI thread delays the first video frame's
    hole; the render-process client paints the hole whenever it arrives.

## Ready state, stalls and keys (what the page sees)

A Safari-identity Media Source element, whichever renderer plays it, takes
its readyState as WebKit's does (`WebMediaPlayerImpl::ParcMonitorSourceBuffers`
after `MediaSource::monitorSourceBuffers`,
`MediaPlayerPrivateMediaSourceAVFObjC::updateStateFromReadyState` and
`seekTask`); the FairPlay Renderer follows WebKit's renderer
(`AudioVideoRendererAVFObjC`, `resetStallForTime`,
`HTMLMediaElement::mediaPlayerWaitingForKeyChanged`):

- `loadedmetadata` once the init segments are parsed. Then readyState comes
  from the buffered ranges at the current time (or a seek's target), with
  WebKit's gap allowances: HAVE_METADATA when that time isn't buffered,
  HAVE_ENOUGH (`canplaythrough`) when 3 s past it are (up to the duration
  once ended), HAVE_FUTURE (`canplay`) with any data ahead, otherwise
  HAVE_CURRENT. It is checked after appends, removals, end of stream and
  duration changes, while playing, at stalls and resumptions, and at a seek's
  start and end.
- With video, HAVE_CURRENT or more waits for a video frame, as WebKit's
  player waits for `hasAvailableVideoFrame`: the renderer's first HAVE_ENOUGH
  after the start or a seek, which the FairPlay Renderer reports only once a
  frame decoded there (`readyForDisplay` on macOS 14.4+, successful
  `prerollDecodeWithCompletionHandler:` on macOS 13.0–14.3). So protected video
  stays at HAVE_METADATA until its keys arrive and a frame decodes, with or
  without a CDM (before one, Chromium creates no renderer at all); a page
  that waits for `canplay` before licensing waits for ever, as in Safari.
  Audio-only elements aren't held: encrypted audio reaches `canplay` and
  `canplaythrough` from buffered data before any CDM or key.
- A SourceBuffer added after the others initialized joins the buffered
  ranges with its first init segment, so readyState drops to HAVE_METADATA
  and rises through HAVE_FUTURE as its data comes. Its tracks join the
  playing renderer, as WebKit's `AudioVideoRendererAVFObjC::addTrack` adds a
  display layer or audio renderer to its synchronizer: the picture and the
  other tracks stay, nothing decodes again, and the clock waits at the
  current time until the new track has samples (video: a decoded frame).
  The pipeline's track change carries it (`ChunkDemuxer::OnTracksChanged`
  starts the stream at that time), and the render process hands its
  DemuxerStream to the GPU process through `FairPlayRendererExtension`.
  Each SourceBuffer's first audio track is enabled, so a second audio
  SourceBuffer plays mixed with the first, one `AVSampleBufferAudioRenderer`
  each, as in Safari; an audio track the page turns off leaves its renderer.
  Chromium's renderer (`RendererImpl`) takes a new kind of track the same
  way, but plays one audio stream, so it keeps the first.
- A seek keeps readyState: into buffered data it fires only `seeking`,
  `timeupdate` and `seeked`; into unbuffered data `waiting`, then `canplay`
  and `canplaythrough` as data comes, and `playing` after `seeked`. It
  finishes once the pipeline's seek is done and the renderer has its samples
  (for video, the frame), not at a readyState change.
- `play()` before the keys: `currentTime` stays at the start until the keys
  let samples reach the renderers, as Safari's synchronizer waits for
  `allRenderersHaveAvailableSamples`; `playing` comes with `canplay`.
- Waiting for a key runs WebKit's Wait for Key on the element
  (`HTMLMediaElement::ParcWaitForKey`), once per blocked episode: `readyState`
  drops to HAVE_CURRENT_DATA if the current time is buffered, else
  HAVE_METADATA (only if that is lower), `waiting` fires if the element was
  potentially playing, then `waitingforkey`. While blocked the element follows
  only changes of the player's `readyState` (Chromium's player repeats its
  own); when the player stops waiting the latch clears and the player's
  `readyState` comes back. A new load clears the latch (WebKit's
  `prepareForLoad`). Media Source waits when encrypted init data finds no
  session and stops when later init data finds one (WebKit's
  `SourceBufferPrivateAVFObjC`); at the start the element is already at
  HAVE_NOTHING, so nothing drops, and keys don't hold `readyState` before the
  first block. Native HLS waits only for a key request that comes while its
  player holds no CDM, and stops when the attached CDM has a newly usable key
  or the player plays on (`MediaPlayerPrivateAVFoundationObjC::
  shouldWaitForLoadingOfResource` and `attemptToDecryptWithInstance`). Any
  other Safari-identity player waits from Chromium's first stall for a key
  until the CDM has a newly usable key or it plays on, rather than for an
  instant.
- Keys missing mid-playback (a new key ID, a license that hasn't come): the
  picture freezes, audio goes quiet and `currentTime` runs on to the buffered
  end, as in Safari. Held samples the clock passes are dropped, video kept
  from its last keyframe, which decoding resumes from when the key arrives.
  With end of stream, the element ends at the end even without the keys, as
  Safari does.
- A stall happens only at the buffered end (the end of what a stream without
  end of stream was given), on a synchronizer boundary rather than a poll:
  `waiting`, then `canplay`/`playing` as soon as any data is ahead, as in
  Safari; the picture resumes once the renderer has enough again.

### Frame readiness before macOS 14.4

Before macOS 14.4, successful `prerollDecodeWithCompletionHandler:` on a
displayable sample supplies frame readiness. Flush and renderer replacement
invalidate older callbacks. Buffer capacity or a usable key alone cannot release
the playback clock; see [waiting for keys](WAITING_FOR_KEY.md).

## Known gaps

Safari-identity MSE can hand off from Chromium's renderer to FairPlay at a future
video keyframe. The incoming renderer prerolls on the outgoing clock, and the
pipeline swaps at the split without synthetic waiting/playing/ended events.
Seek, suspend, reverse playback, CDM replacement and track changes have explicit
restart or cancellation paths. Where hand-off is impossible, restart can cause
one rebuffer. This also affects casting, PiP and background tabs.

The current core supports VP9 and Vorbis for Safari-identity media, but has no
VP8 or MP3 renderer implementation. Transitions into Dolby Vision beside those
codecs can fail, and late FairPlay attachment can require restart.

The MSE FairPlay client and GPU adapter also omit `SetPreservesPitch`, so a
page cannot disable pitch preservation on this route. The core supports the
choice, and native HLS forwards it. Connect that choice through the FairPlay
client/adapter boundary.

## Widevine request hook

```cpp
// content/browser/media/parc_fairplay_hooks.h
namespace parc::fairplay {
using WidevineCdmRequestObserver = base::RepeatingCallback<
    bool(content::RenderFrameHost* frame, const std::string& key_system)>;
CONTENT_EXPORT void SetWidevineCdmRequestObserver(
    WidevineCdmRequestObserver observer);
}
```

It runs on the UI thread from `MediaInterfaceProxy::CreateCdm`, only for
`com.widevine.alpha` and its sub key systems. Returning true parks the mojo
callback in `held_widevine_cdm_callbacks_`, declared before `receivers_` so
the pipes close first. It's never run and is destroyed with the document.
At most 16 requests are held per document; later ones fail with
`kCdmCreationAborted` (no CDM, so no license request). If the observer ends
the document while it runs, `CreateCdm` notices through a weak pointer and
returns. Parc's CDM creator runs next. The held callbacks stay in the proxy,
not in Parc's host, because their place before `receivers_` closes the pipes
first. MojoRendererService and MojoRenderer keep the FairPlay CDM swap: CDM
attach on another pipe would lose its order with the Renderer's calls.

## Codec build flags (increment 3)

`Engine/source-lock.json` adds `enable_platform_dolby_vision=true`,
`enable_platform_encrypted_dolby_vision=true` and
`enable_platform_ac3_eac3_audio=true`. Netflix and Apple TV+ pick Dolby
Vision 5 and AC-3/E-AC-3 when they see Safari.

- Dolby Vision plays through the FairPlay renderer. On Chrome-identity pages,
  `MediaSource.isTypeSupported` says no to `dvh1`/`dvhe`, and EME offers it only
  through key systems whose codecs list it, which means FairPlay and not Widevine. That is
  Chromium's model on Windows. FairPlay's `CdmInfo` lists profile 5 only. The
  adapter and core can also play profile 8, but sites aren't offered it under the current
  capability policy.
- Dolby Vision in Media Source follows Safari, whose
  `AVSampleBufferDisplayLayer` decodes it clear or encrypted, with keys set
  before, after or never. On a document presenting Safari's identity (with
  the handoff and restart rules described under Known gaps):
  - A clear Dolby Vision init segment (a plain `dvhe`/`dvh1` sample entry, no
    `encv` or `tenc`, as in a clear lead) is accepted in profiles 5 and 8,
    whatever the key timing. `WebMediaPlayerImpl` tells the demuxer when the
    Media Source opens, before the page can add a SourceBuffer
    (`ChunkDemuxer::ParcSetClearDolbyVisionAllowed`, handed to each
    `SourceBufferState`). Chrome-identity documents still reject clear Dolby
    Vision as on Windows ("only supported via platform decryptor") unless a
    FairPlay CDM is set; the global
    `kAllowClearDolbyVisionInMseWhenPlatformEncryptedDvEnabled` stays off, so
    `isTypeSupported` answers the same as before for every document.
  - Playback whose video is Dolby Vision goes to the FairPlay Renderer with or
    without a CDM (`PipelineImpl` picks it from the enabled video stream's
    codec, where the demuxer lets clear Dolby Vision through), the
    only renderer in Parc that decodes it: the adapter takes an unencrypted
    Dolby Vision config and the core plays clear Chromium-framed DV5 to the end
    ([tests/FairPlay](../../../tests/FairPlay/README.md)). The browser lets
    Safari-identity frames create that renderer without a FairPlay CDM
    (`parc::fairplay::SetSafariIdentityQuery`). A SourceBuffer that takes
    Dolby Vision later (`changeType()`) makes the demuxer prefer that renderer
    too (`Demuxer::ParcPrefersFairPlayRenderer`). The player attempts a
    synchronized handoff and restarts only when that cannot proceed.
- AC-3/E-AC-3 is ordinary codec support: pages
  ask `isTypeSupported` first, and a page that offers E-AC-3 gets it decoded by
  AudioToolbox, as in Safari. Widevine's capability stays exactly as before:
  `media/cdm/supported_audio_codecs.cc` leaves AC-3/E-AC-3 out of library CDMs
  on macOS, so Widevine sites negotiate the same codecs as today.
- Upstream side effects of the flags, the same as on Windows: every page's
  `addSourceBuffer`/`changeType` now accept `dvh1`/`dvhe` (outside FairPlay
  only to reject a clear Dolby Vision init segment later, where it threw
  NotSupportedError before), and ClearKey's EME also offers AC-3/E-AC-3.
- Changing `gn_defines` changes the source lock's digest, so an existing
  workspace needs `scripts/engine-source.py reconfigure` before the next build.
  The media buildflag headers change, so dependents of
  `media/media_buildflags.h` recompile.

## GPU sandbox additions

Checked on this Mac (Apple Silicon, macOS 27.2) by playing FairPlay inside
Chromium's real GPU seatbelt profile, without a build:
[tests/FairPlay/sandbox](../../../tests/FairPlay/sandbox/README.md) (run with
`python3 tests/FairPlay/sandbox/run.py`, and `--ablate --ablate-groups` for the
table). AVFoundation and the core load inside the sandbox there, as in Parc's
GPU helper. The scenarios are protected H.264 and HEVC with AAC (Axinom), plus
Chromium's clear Dolby Vision 5, E-AC-3 and AC-3 clips. References: WebKit's
`com.apple.WebKit.GPUProcess.sb`, the App Sandbox (`application.sb`) and
Chromium's own `audio.sb`.

| Rule | Why (what the probe shows without it) |
| --- | --- |
| mach-lookup `com.apple.lskdd`, `com.apple.lskdd.xpc` | FairPlay Streaming's key daemon. Without both, `generateRequest` fails (-42664); either alone is enough. WebKit's GPU process and the App Sandbox allow both. `fairplayd`/`fpsd` are App Store DRM and aren't needed. |
| mach-lookup `com.apple.audio.audiohald` | AVSampleBufferAudioRenderer can't render (-11800 over -101). |
| mach-lookup `com.apple.coremedia.routingcontext.xpc` | AVSampleBufferAudioRenderer is invalid and the synchronizer refuses it ("invalid renderer"), so renderer Initialize fails. |
| mach-lookup `com.apple.audio.AudioSession`, xpc `com.apple.audio.SandboxHelper` | Looked up while audio plays; built-in output plays without them. Kept for other routes, which the probe can't exercise (both in `audio.sb`). |
| iokit `AppleAVDUserClient` | Protected video is decoded in this process on the hardware decoder, not in VideoToolbox's XPC decoder. Without it decoding fails (-11839 over -12913). WebKit's GPU process allows it. |
| iokit `IOMobileFramebufferUserClient` | Without it the content key never becomes usable (output protection). WebKit allows it on arm64. |
| file-read `/System/Library/Components/CoreAudio.component` | Without it audio never starts and playback stalls. Only `AudioCodecs.component` was allowed. |
| file-read `/System/Library/Components/AudioDSP.component` | Read while audio plays; built-in output plays without it. `audio.sb` allows all of `/System/Library/Components`. |

Replaced by a filter that never matches, every other rule fails playback,
with a kernel denial naming it (the two lskdd names only as a pair). Only
`AudioSession`, `SandboxHelper` and `AudioDSP.component` play without
theirs. Message filters aren't available: WebKit lets its GPU process call only a
few AVD and display-pipe methods (`apply-message-filter`), but
`sandbox_init` refuses a profile with message filters from a non-Apple
process (EPERM, checked with the probe). So both IOKit grants cover the whole
user client, in every GPU process: Chromium's GPU profile does have
parameters (`RESTRICT_GPU_DARWIN_USER_DIRS`, `DISABLE_METAL_SHADER_CACHE`), but
FairPlay is on in every build, so a parameter wouldn't narrow anything. The
way to keep this attack surface out of the GPU process is a separate FairPlay
media process that hosts the display layer through `CAContext`/`CALayerHost`.

Already allowed by `gpu.sb`: all preference reads, all POSIX shared memory
(CoreAudio's `AudioIO`), `com.apple.coremedia.videodecoder` and
`com.apple.CARenderServer`. Still denied while FairPlay plays, without effect:
`tccd.system`, `audioanalyticsd` (WebKit denies it too), `UsageTrackingAgent`,
distributed notifications, a few sysctls and `/System/Library/Audio/Tunings`.
`IOSurfaceAcceleratorClient` remains denied; the sandbox fixture records its
decoder behavior separately from compositor placement. `AudioConverterService`
is not needed by the fixture's AC-3/E-AC-3 path.

## Checks run without a build

Use source/manifest validation and compiler checks with the pinned generated
headers and target flags. The core, codec, timeline, key, presentation and
sandbox fixtures are documented in [FairPlay tests](../../../tests/FairPlay/README.md).
Record whether each selected check compiled or executed, and bind its receipt to
the finished source. Historical increment results are available in Git; do not
reuse them as current verification.

## Binary test data

The engine overlay accepts only reviewable UTF-8 text, so the small TS and
3GP clips in `testdata/` are not overlay files. Media unit tests that open
`media/test/data/parc-*.ts` or `parc-h263-amr.3gp` (the MPEG-2 video,
SAMPLE-AES, AC-3/E-AC-3, two-audio and H.263/AMR parser and decoder tests) need
those clips copied into `media/test/data/` before running `media_unittests`.
Shipping builds don't build those tests.

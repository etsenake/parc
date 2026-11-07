# FairPlay in Chromium (M1 media plumbing)

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

Landed on main in increments, each building on its own:

1. The CDM: routing, GPU adapter and factory, `CdmContext` additions, the
   Widevine hook and the GPU sandbox rules. Inert: `MediaInterfaceProxy`
   creates a FairPlay CDM only for a key system `CdmRegistryImpl` has
   registered, as for every other CDM, and nothing registers it yet.
2. The renderer: `RendererType::kFairPlay`, `InterfaceFactory.CreateFairPlayRenderer`,
   the GPU renderer adapter and the render-process client. Still inert, since
   it is only selected for a FairPlay CDM.
3. Registration (browser `CdmInfo`, Blink key system info) and the codec build
   flags. From here FairPlay is offered to every page.
4. The GPU sandbox rules as `tests/FairPlay/sandbox` proved them.
5. Tab mute and the tab's audio indicator.

Safari's second route, native HLS (`<video src="….m3u8">` through `AVPlayer`
with `skd` keys), is designed in [NATIVE_HLS.md](NATIVE_HLS.md) and lands in
pieces behind a disabled switch. Its engine-free player is the core's
`FairPlayHlsPlayer` ([core README](../fairplay/README.md#native-hls-player)),
compiled into the core source set (overlay 381) and unused until the GPU
service wires it in.

## What is where

| Piece | Where |
| --- | --- |
| Key system names | `fairplay_key_system.h` (`IsFairPlayKeySystem`, same rule as the core and WebKit) |
| `media::ContentDecryptionModule` + `CdmContext` | `fairplay_cdm_adapter.{h,cc}` over `parc::fairplay::FairPlayCdm` |
| GPU media service CDM factory | `fairplay_cdm_factory.{h,cc}`, returned by `GpuMojoMediaClientMac::CreatePlatformCdmFactory` |
| CDM routing | `MediaInterfaceProxy::CreateCdm` sends FairPlay key systems to the frame's GPU media service `InterfaceFactory`, before the library CDM path (which would look for a CDM binary) |
| Renderer selection | `CdmContext::RequiresFairPlayRenderer()` / `GetFairPlayCdm()`, carried to the render process as `mojom::CdmContext.requires_fairplay_renderer`; `PipelineImpl` then asks for `RendererType::kFairPlay` |
| GPU `media::Renderer` | `fairplay_renderer_adapter.{h,mm}` over `parc::fairplay::FairPlayRenderer`, created by `GpuMojoMediaClientMac::CreateFairPlayRenderer` through `InterfaceFactory.CreateFairPlayRenderer` |
| Render-process client | `fairplay_renderer_client{,_factory}.{h,cc}` → `//content/renderer/media/fairplay`, registered in `MediaFactory` as `kFairPlay` (never the base renderer) |
| Display handoff | layer token over `mojom::FairPlayRendererClientExtension.OnLayerRegistered`; `ui::ProtectedLayerRegistry` and the compositor side in [COMPOSITING.md](COMPOSITING.md) (fairplay-compositing) |
| Key system registration | `GetFairPlayCdmInfo()` in `CdmRegistryImpl::Init` (browser); `fairplay_key_system_info.{h,cc}` → `//components/cdm/renderer`, added by `key_system_support_update.cc` (renderer) |
| Widevine request hook | `parc::fairplay::SetWidevineCdmRequestObserver` (`parc_fairplay_hooks.h`, defined in `media_interface_proxy.cc`), for fairplay-identity |
| VideoToolbox decoder facts | `parc_video_toolbox_decoding.{h,mm}` → `//content/browser/media`: the browser reads what WebKit's MediaCapabilities asks VideoToolbox (H.264 hardware, HEVC per-profile hardware and levels, Dolby Vision profiles and levels) once and serves `media.mojom.ParcVideoToolboxDecoding` to frames and dedicated workers, for Safari-identity `decodingInfo` |
| GPU sandbox | `sandbox/policy/mac/gpu.sb`, rules listed below |

No mojo-media GN arguments change. `enable_library_cdms` is true on macOS,
so `mojo_media_services` already contains `"cdm"` (`ENABLE_MOJO_CDM`) and
`mojo_media_host` is `"gpu"`. `"renderer"` stays out of `mojo_media_services`:
it would make the GPU's default renderer every page's renderer. The FairPlay
renderer has its own `InterfaceFactory` method instead, as Windows'
MediaFoundation renderer does, and `InterfaceFactoryImpl` compiles its renderer
receivers on macOS for it.

## Call flow (CDM)

1. Blink's `MediaKeys` asks the render process's `MojoCdmFactory`, which sends
   `InterfaceFactory::CreateCdm` to the browser's `MediaInterfaceProxy`
   (UI thread).
2. `MediaInterfaceProxy` sees a FairPlay key system. If `CdmRegistryImpl` has
   no `CdmInfo` for it, it refuses (`kUnsupportedKeySystem`), as Chromium does
   for any unregistered key system. Otherwise it forwards it to the
   frame's GPU media service `InterfaceFactoryImpl`, the one that also serves
   the frame's renderers. One `MojoCdmServiceContext` per frame is what lets a
   renderer find the CDM by its ID later.
3. In the GPU process, `InterfaceFactoryImpl` → `MojoCdmService` →
   `FairPlayCdmFactory::Create` → `FairPlayCdmAdapter`, on the media service
   thread. On macOS `kDedicatedMediaServiceThread` is on, so that's a
   ThreadPool thread with no run loop, not the GPU main thread.
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
asks the frame's `FrameInterfaceFactory.GetFairPlayStorageDirectory` (the
browser's `MediaInterfaceProxy`) for its storage, WebKit's per-origin
MediaKeys directory: `<Profile engine folder>/Parc FairPlay/MediaKeys/`, then
the SHA-256 of the top-level origin and of the frame's origin, created by the
browser, empty off the record or for an opaque origin. The core then creates
its AVContentKeySession with `SecureStop.plist` there, which the GPU sandbox
allows (`gpu.sb`). `persistent-license` rejects with NotSupported, as
on Safari for macOS. `CdmContext::ParcHasSessionForInitData` (asked by a
Safari-identity Media Source element through MojoCdm before it fires
`encrypted` with `sinf`) answers from `FairPlayCdm::HasSessionForInitData`.
`LoadSession` and `GetStatusForPolicy` reject with NotSupported.

## Call flow (playback)

1. Blink's `setMediaKeys` attaches the `MojoCdm`. Its
   `RequiresFairPlayRenderer()` is true, so `PipelineImpl` asks the
   `RendererFactorySelector` for `RendererType::kFairPlay` when it creates the
   renderer (encrypted streams wait for the CDM first). Without a FairPlay CDM
   the pipeline is unchanged.
2. `FairPlayRendererClientFactory` makes a `MojoRenderer` through
   `InterfaceFactory.CreateFairPlayRenderer` (render process → browser's
   `MediaInterfaceProxy` → the frame's GPU media service `InterfaceFactoryImpl`).
   The `FairPlayRendererClient` that wraps it binds the client extension.
3. In the GPU process, `InterfaceFactoryImpl` hosts `FairPlayRendererAdapter`
   under a `MojoRendererService` that shares the factory's
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
   (`Demuxer::RestrictCanChangeType`) that accepts AAC, AC-3, E-AC-3, H.264,
   HEVC and Dolby Vision 5 and 8, so any other codec makes `changeType()`
   throw NotSupportedError instead of failing playback. The core builds the
   new formats from the next samples, protected ones per key ID.
   `tests/FairPlay/sandbox` switches protected AAC → clear E-AC-3 → protected
   AAC under protected H.264, and clear H.264 → HEVC → H.264, with no
   underflow.
5. With video, the adapter registers the core's `AVSampleBufferDisplayLayer` in
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
   counts read. Netflix fails with S7353-5101 (decoder timeout) when
   `totalVideoFrames` stays put for 10 s. On macOS 14.4+ the frames come from
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
   demuxer aborts them before a seek). Teardown flushes the layer with
   removal of the displayed image, unregisters it, then destroys the core,
   which leaves the CDM's key session. `MojoRendererService` destroys the
   renderer before it drops the CDM reference.

## Threads and processes

- Browser, UI thread: `MediaInterfaceProxy` (routing, Widevine hook) and
  `CdmRegistryImpl`.
- Render process, media thread: `FairPlayRendererClient`, `MojoRenderer` and
  `MojoCdm`. Blink's key system info is evaluated on the main thread.
- GPU process, media service thread: `FairPlayCdmAdapter`,
  `FairPlayRendererAdapter` and the core. On macOS `kDedicatedMediaServiceThread`
  is on, so that's a ThreadPool thread with no run loop, not the GPU main
  thread. The core posts every AVFoundation callback to it. CALayer creation
  is wrapped in an explicit CATransaction there. The compositor touches the
  layer only from the GPU main thread, and only its placement.
- Audio goes from `AVSampleBufferAudioRenderer` straight to CoreAudio from the
  GPU process, never through Chromium's audio service. Web Audio's
  `createMediaElementSource` and `setSinkId` don't see it. Tab mute and the
  tab's audio indicator do, the way MediaFoundation's renderer gets them on
  Windows:
  - Mute: `GpuMojoMediaClientMac::CreateFairPlayRenderer` registers a
    `mojom::MuteStateObserver` with the frame's `FrameInterfaceFactory`
    (enabled on macOS too). The browser answers with the tab's state at once
    and on every change; the adapter mutes the core (`SetMuted`, kept until
    the core is initialized). Until that first answer the adapter keeps the
    audio muted, so a muted tab plays no sound while it is on its way. The
    observer closes with the renderer.
  - Indicator: `MediaInterfaceProxy::CreateFairPlayRenderer` holds an
    `AudibilityBypassTracker` grant in the proxy it puts between the GPU
    adapter and the render-process client, so the grant ends with the GPU
    renderer. The player reports that it doesn't use the audio service, so
    `MediaWebContentsObserver` claims the grant while the player is audible
    and registers it with `AudioStreamMonitor`. A frame gets the grant only
    after it asked `CreateCdm` for a registered FairPlay key system.
  - The layer token (`OnLayerRegistered`) goes through that proxy on the
    browser's UI thread, so a busy UI thread delays the first video frame's
    hole; the render-process client paints the hole whenever it arrives.

## Known gaps

- A page that turns its own video track off (`videoTracks`) ends video until
  the next seek; a disabled `ChunkDemuxerStream` answers with end of stream.
  The background-tab optimization that does the same is turned off for
  FairPlay players.
- A `setMediaKeys` that arrives after a clear pipeline already chose
  `RendererImpl` doesn't switch renderers (same as MediaFoundation upstream).
- `setSinkId` isn't wired. The core has `SetAudioOutputDevice`, but
  `media::Renderer` has no sink switch, so it needs a client extension call.
- Two FairPlay players in one frame can lose the speaker icon: upstream's
  `AudibilityBypassTracker` hands any pending grant to whichever player
  claims first, so when one renderer goes, the other player's claimed grant
  can go with it (the same holds for MediaFoundation on Windows).

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
returns.

## Codec build flags (increment 3)

`Engine/source-lock.json` adds `enable_platform_dolby_vision=true`,
`enable_platform_encrypted_dolby_vision=true` and
`enable_platform_ac3_eac3_audio=true`. Netflix and Apple TV+ pick Dolby
Vision 5 and AC-3/E-AC-3 when they see Safari.

- Dolby Vision is encrypted-only: `kPlatformEncryptedDolbyVision` is on by
  default for macOS too (`media_switches.cc`). `MediaSource.isTypeSupported`
  still says no to `dvh1`/`dvhe`, clear Dolby Vision is rejected at the init
  segment, and EME offers it only through key systems whose codecs list it,
  which means FairPlay and not Widevine. That is Chromium's model on Windows.
  FairPlay's `CdmInfo` lists profile 5 only. The adapter and core can also play
  profile 8, but sites aren't offered it (Josh's decision, November 6).
- AC-3/E-AC-3 is ordinary codec support (Josh's decision, November 6): pages
  ask `isTypeSupported` first, and a page that offers E-AC-3 gets it decoded by
  AudioToolbox, as in Safari. Widevine's capability stays exactly as before:
  `media/cdm/supported_audio_codecs.cc` leaves AC-3/E-AC-3 out of library CDMs
  on macOS, so Widevine sites negotiate the same codecs as today.
- Upstream side effects of the flags, the same as on Windows: every page's
  `addSourceBuffer`/`changeType` now accept `dvh1`/`dvhe` (only to reject a
  clear Dolby Vision init segment later, where it threw NotSupportedError
  before), and ClearKey's EME also offers AC-3/E-AC-3.
- Changing `gn_defines` changes the source lock's digest, so Josh's existing
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
`IOSurfaceAcceleratorClient` is denied too: H.264 and HEVC open it, Dolby
Vision doesn't, and all play without it. On-screen scaling isn't covered,
because the probe's layer is in no window. `AudioConverterService` is never looked up, E-AC-3 and AC-3
included. The probe doesn't cover Intel Macs, external displays, AirPlay or
Bluetooth route changes. To check a real build, use
`log stream --predicate 'eventMessage CONTAINS "deny(" AND eventMessage CONTAINS "Helper (GPU)"'`.

## What Josh's first build should test

Use a fresh disposable profile. The steps assume the increments up to key
system registration are on main.

1. `chrome://media-internals` → Registered CDMs lists "Apple FairPlay
   Streaming" (`com.apple.fps`, software secure, empty path).
2. In a Parc tab on any https page, in DevTools:
   `await navigator.requestMediaKeySystemAccess("com.apple.fps.3_0", [{initDataTypes: ["cenc"], videoCapabilities: [{contentType: 'video/mp4; codecs="avc1.640028"'}], audioCapabilities: [{contentType: 'audio/mp4; codecs="mp4a.40.2"'}]}])`
   resolves, and `createMediaKeys()` resolves. That proves the CDM was created
   in the GPU process.
3. Axinom's FairPlay CMAF vector ("CMAF H264 SingleKey (cbcs)", HLS over
   CMAF: `https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/`,
   details in [tests/FairPlay/README.md](../../../tests/FairPlay/README.md))
   through Shaka Player in a Parc tab (a local page loading
   shaka-player.compiled.js, or the Shaka demo's custom content). Chromium's
   MP4 parser raises `encrypted` with `cenc` init data (the vector's Widevine
   and PlayReady pssh), so the CDM sends WebKit's cenc message, a JSON array
   `[{"keyID", "payload"}]`. Axinom's service wants the raw SPC, so unwrap it
   and wrap the CKC back:

   ```js
   player.configure({drm: {
     servers: {"com.apple.fps": "https://drm-fairplay-licensing.axprod.net/AcquireLicense"},
     advanced: {"com.apple.fps": {serverCertificateUri: "https://tools.axinom.com/FPScert/fairplay.cer"}}}});
   const net = player.getNetworkingEngine(), LICENSE = shaka.net.NetworkingEngine.RequestType.LICENSE;
   let keyID;
   net.registerRequestFilter((type, req) => {
     if (type !== LICENSE) return;
     const [entry] = JSON.parse(new TextDecoder().decode(req.body));
     keyID = entry.keyID;
     req.body = Uint8Array.from(atob(entry.payload), c => c.charCodeAt(0));
     req.headers["Content-Type"] = "application/octet-stream";
     req.headers["X-AxDRM-Message"] = TOKEN;  // kToken in tests/FairPlay/harness.mm
   });
   net.registerResponseFilter((type, res) => {
     if (type !== LICENSE) return;
     const ckc = btoa(String.fromCharCode(...new Uint8Array(res.data)));
     res.data = new TextEncoder().encode(JSON.stringify([{keyID, payload: ckc}]));
   });
   await player.load("https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/manifest.m3u8");
   ```

   Expect: one license request in the Network tab, `keystatuseschange` to
   "usable", video in the element's box that follows scrolling, resizing and
   fullscreen, audio, and working seek and pause. The tab shows its speaker
   icon while audio plays, and muting the tab (or the site) silences it.
   The vector has no clear lead, so this doesn't depend on the core's clear-lead work. (Check the vector's
   master playlist name in Axinom's README if `manifest.m3u8` 404s.)
4. Ordinary paths unchanged: a clear MP4/MSE video, and a Widevine site (e.g.
   Shaka's Widevine demo asset) play as before. In media-internals their
   renderer is "RendererImpl", not "FairPlayRenderer".
5. If FairPlay fails, first check Console for GPU sandbox denials:
   `log stream --predicate 'eventMessage CONTAINS "deny(" AND eventMessage CONTAINS "Helper (GPU)"'`.
   Then check media-internals' log for "FairPlay renderer" errors.

## Checks run without a build

Nothing here builds the engine. For each increment:

- Every hunk was re-read against the pinned source (d0c02bfa). Each target is
  byte-identical to `git show d0c02bfa:<path>` (no CEF patch or earlier overlay
  touches it), and none is a target of another overlay patch on main.
- The overlay tool's exact applier (`apply_context_patch` in
  `scripts/engine-source.py`) applies `fairplay-media.patch` to those
  preimages with matching after-hashes. Every manifest input digest matches,
  no target is duplicated, and no new file exists upstream.
- `tests/EngineSource` and `tests/EngineConformance/native` pass. The codec
  defines have their own test (`test_development_and_shipping_engines_build_fairplay_platform_codecs`).
  against the pinned headers and stub buildflag headers. These compile clean
  at `-Wall`: `fairplay_cdm_adapter.cc`, `fairplay_cdm_factory.cc`,
  `fairplay_renderer_adapter.mm` (with fairplay-compositing's registry
  header), `fairplay_key_system_info.cc`, and the patched
  `media/base/cdm_context.cc`, `media/base/renderer.cc`,
  `media/base/pipeline_impl.cc` and `media/cdm/supported_audio_codecs.cc`.
- Not compiled, because they need generated mojom or perfetto headers that only
  exist in a build directory: `media_interface_proxy.cc`,
  `frameless_media_interface_proxy.cc`, `mojo_cdm.cc`, `mojo_cdm_service.cc`,
  `interface_factory_impl.cc`, `mojo_media_client.cc`,
  `gpu_mojo_media_client_mac.cc`, `mojo_renderer_factory.cc`, the
  render-process `media_interface_factory.cc`, `media_factory.cc`,
  `fairplay_renderer_client{,_factory}.cc`, `key_system_support_update.cc`
  and `cdm_registry_impl.cc`. Those hunks follow the existing
  MediaFoundation code next to them line for line, and were re-read for exact
  signatures.
- Playback statistics (2026-11-06): `fairplay_renderer_adapter.mm` passes
  `-fsyntax-only` (debug and `NDEBUG`) against the pinned headers with
  fairplay-media's patched `renderer.h`/`cdm_context.h` (exact applier,
  every before/after digest matching) and stub buildflag headers; a copy
  with a misspelled member fails, so the check reads the code. The counts it
  reports are covered by `tests/FairPlay` (see its README's results).
- Native HLS mojo and loader (2026-11-06): Chromium's mojom parser accepts
  the patched `renderer_extensions.mojom` and `interface_factory.mojom` with
  every import, and its C++ bindings generator (Python 3.13, a typemap file
  written from the GN `cpp_typemaps` of the types used) produces their
  headers. Against those, the generated `-shared.h` headers of the network
  and Blink fetch mojoms, the pinned headers and stub buildflag headers,
  `fairplay_hls_loader.cc` and `fairplay_hls_loader_unittest.cc` pass
  `-fsyntax-only -Wall -Wextra -Werror` (`NDEBUG`, `INSIDE_BLINK`); a copy
  with a misspelled member fails. That check caught a struct name clashing
  with a mojo-generated alias (`FairPlayHlsLoadRequest` vs the
  `FairPlayHlsLoadRequestDataView` of interface `FairPlayHlsLoad`), now
  `FairPlayHlsRequest`/`FairPlayHlsResponse`. The unit tests run only when
  `blink_platform_unittests` is built.
- Each increment had an independent read-only review before main, and its
  findings were fixed.

Unverified until Josh builds: compilation of the files above, mojom
generation, `gn check`, the GPU sandbox rules, and all runtime behaviour.

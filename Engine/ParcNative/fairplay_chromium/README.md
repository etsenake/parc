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

Lands on main in three increments, each building on its own:

1. The CDM: routing, GPU adapter and factory, `CdmContext` additions, the
   Widevine hook and the GPU sandbox rules. Inert: `MediaInterfaceProxy`
   creates a FairPlay CDM only for a key system `CdmRegistryImpl` has
   registered, as for every other CDM, and nothing registers it yet.
2. The renderer: `RendererType::kFairPlay`, `InterfaceFactory.CreateFairPlayRenderer`,
   the GPU renderer adapter and the render-process client. Still inert, since
   it is only selected for a FairPlay CDM.
3. Registration (browser `CdmInfo`, Blink key system info) and the codec build
   flags. From here FairPlay is offered to every page.

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

Init data: `cenc` and `keyids` (Chromium's `EmeInitDataType` has no `sinf`
or `skd`; Netflix and Apple TV+ use `cenc` only). Sessions: temporary only.
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
   to `FairPlayRenderer::Reconfigure`.
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
7. `Flush` drops what is queued and waits for reads already in flight (the
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
  `createMediaElementSource`, `setSinkId` and the tab's audio indicator don't
  see it.

## Known gaps

- `requiresFlushToResumeDecoding` (layer detached while the page has no
  compositor) is reported by the core but not yet recovered; fairplay-core's
  next batch adds recovery.
- A page that turns its own video track off (`videoTracks`) ends video until
  the next seek; a disabled `ChunkDemuxerStream` answers with end of stream.
  The background-tab optimization that does the same is turned off for
  FairPlay players.
- A codec change through MSE `changeType` ends playback with an error.
- A `setMediaKeys` that arrives after a clear pipeline already chose
  `RendererImpl` doesn't switch renderers (same as MediaFoundation upstream).
- `setSinkId` isn't wired yet (the core is adding `SetAudioOutputDevice`).

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

Reference: WebKit's `com.apple.WebKit.GPUProcess.sb` (macOS ships it in
WebKit.framework's Resources), the App Sandbox (`application.sb`), and
Chromium's own `audio.sb`, which already hosts an AVSampleBufferAudioRenderer.

| Rule | Why |
| --- | --- |
| mach-lookup `com.apple.lskdd`, `com.apple.lskdd.xpc` | FairPlay Streaming's key daemon (SPC/CKC for AVContentKeySession). WebKit's GPU process and the App Sandbox allow exactly these; `fairplayd`/`fpsd` are App Store DRM and are not needed. |
| mach-lookup `com.apple.audio.audiohald`, `com.apple.audio.coreaudiod`, `com.apple.audio.AudioSession` | CoreAudio HAL client for AVSampleBufferAudioRenderer output (audio.sb). |
| mach-lookup `com.apple.coremedia.routingcontext.xpc` | Needed to create AVSampleBufferAudioRenderer (audio.sb's comment). |
| xpc `com.apple.audio.AudioConverterService` | Out-of-process audio converters (WebKit GPU process). |
| xpc `com.apple.audio.SandboxHelper` | HAL plug-in helper (audio.sb, WebKit). |
| iokit-open `IOAudioControlUserClient`, `IOAudioEngineUserClient` | Intel Macs' kernel audio drivers (audio.sb). |
| file-read `/Library/Audio/Plug-Ins/HAL`, `~/Library/Caches/com.apple.coreaudio.components.plist` | HAL plug-ins and component cache (audio.sb, WebKit). |

The rules apply to every GPU process (Chromium's GPU profile has no
per-feature switch), not only to pages playing FairPlay.

Already allowed by `gpu.sb`: all preference reads, all POSIX shared memory
(CoreAudio's `AudioIO` regions), `com.apple.coremedia.videodecoder`, and
`com.apple.CARenderServer`. If Josh's first build logs other GPU sandbox
denials during playback, candidates from WebKit's profile are
`com.apple.mediaremoted.xpc` and `com.apple.coremedia.samplebufferconsumer.xpc`.
To check: `log stream --predicate 'eventMessage CONTAINS "deny" AND process CONTAINS "GPU"'`.

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
   fullscreen, audio, and working seek and pause. The vector has no clear lead,
   so this doesn't depend on the core's clear-lead work. (Check the vector's
   master playlist name in Axinom's README if `manifest.m3u8` 404s.)
4. Ordinary paths unchanged: a clear MP4/MSE video, and a Widevine site (e.g.
   Shaka's Widevine demo asset) play as before. In media-internals their
   renderer is "RendererImpl", not "FairPlayRenderer".
5. If FairPlay fails, first check Console for GPU sandbox denials:
   `log stream --predicate 'eventMessage CONTAINS "deny" AND process CONTAINS "Helper (GPU)"'`.
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
- Each increment had an independent read-only review before main, and its
  findings were fixed.

Unverified until Josh builds: compilation of the files above, mojom
generation, `gn check`, the GPU sandbox rules, and all runtime behaviour.

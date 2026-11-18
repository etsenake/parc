# Chromium hooks: media, FairPlay and Blink

Part of the [hooks and patches reference](chromium-hooks.md). The
[FairPlay guide](../Engine/ParcNative/fairplay_chromium/README.md) explains the media service these
hooks feed, and the [seams guide](chromium-seams.md#media-player-boundaries) explains the player,
element and Media Source code Chromium calls directly. Answering code lives in `Engine/ParcNative/`
unless a path says otherwise.

## Media and FairPlay hooks

Four of these are declared in `parc/chromium_hooks.h`; the rest in a Parc header installed in
`content`, which carries `CONTENT_EXPORT` because content is a component library.

- **`SetCdmServiceChildFlags`**: Widevine runs in Parc's dedicated CDM helper, the only helper
  signed without library validation. `content/browser/media/service_factory.cc` builds the CDM
  service's launch options itself. Installed in `ParcContentBrowserClient::CreateBrowserMainParts`
  in `parc_content_clients.mm`, only when the bundle has the helper and before the interface thread
  forbids blocking; `GetChildProcessPath` there resolves the flag.
- **`SetFairPlayCdmCreator`**: FairPlay key requests go to Parc's FairPlay media service.
  `MediaInterfaceProxy::CreateCdm` in `content/browser/media/media_interface_proxy.cc` makes one
  call into Parc's `parc_media_routing.cc` in the same layer, which runs the Widevine request
  observer and then this creator; false leaves the request to Chromium. Installed in
  `PreMainMessageLoopRun`; answered by `FairPlayDocumentHost::CreateCdm` in `fairplay_media_host.cc`.
  The [FairPlay guide](../Engine/ParcNative/fairplay_chromium/README.md#widevine-request-hook)
  explains why the order needs a hook.
- **`SetWidevineCdmRequestObserver`**: a site that belongs on FairPlay never starts Widevine; its
  Widevine request is held and dropped with the document. Declared in
  `content/browser/media/parc_fairplay_hooks.h` and defined in Parc's `parc_media_routing.cc`. Installed
  by `InstallFairPlayIdentity` in `fairplay_identity.mm`, which `native_engine_entry.mm` runs before
  Chromium's command line exists and before any page or worker; answered by `OnWidevineCdmRequest`
  there.
- **`SetSafariIdentityQuery`** and its call-in **`FramePresentsSafariIdentity`**: Chromium code asks
  whether a frame presents Safari's identity, so those pages get Safari's media behaviour. Same
  header and file; asked by Parc's media session, input diagnostics and picture-in-picture patches
  and by `FairPlayDocumentHost`. Installed by `InstallFairPlayIdentity`; answered by
  `FramePresentsSafari` in `fairplay_identity.mm`.
- **`SetParcWorkerIdentityHook`**: service, shared and dedicated workers on Safari-identity sites
  report the same browser as their pages, in `navigator.userAgent` and in their requests. Declared in
  `content/public/browser/parc_worker_identity.h`, defined in
  `content/browser/service_worker/service_worker_version.cc` and called there and from
  `shared_worker_host.cc`, `service_worker_loader_helpers.cc` and `worker_script_fetcher.cc`. A
  request throttle would set the user agent after Chrome's own. Installed by
  `InstallFairPlayIdentity`; answered by `ApplyWorkerIdentity`.
- **`SetParcPlaybackTargetHandler`** and its call-ins **`SetParcPlaybackTargetAvailability`**,
  **`SetParcPlaybackTarget`** and **`SetParcPlaybackTargetPickerDismissed`**: AirPlay works for video
  on Safari-identity pages, with the device list, route and dismissal reaching each player. Declared
  in `content/public/browser/parc_playback_target.h`; the handler setter is defined in
  `content/browser/media/media_web_contents_observer.cc`, which already routes each player's
  observer messages, and the three call-ins in Parc's `parc_media_routing.cc`. Installed by `InstallNativeAirPlay` from `native_engine_entry.mm`; answered by
  `NativeAirPlay` in `native_airplay.mm`.
- **`SetAutoPictureInPictureVisibilitySync`**: automatic picture in picture on a tab switch waits
  until the page's renderer confirms it is hidden, so the video never flashes. The wait starts and is
  cancelled at private points in
  `chrome/browser/picture_in_picture/auto_picture_in_picture_tab_helper.cc`; unhooked builds enter at
  once. Installed in the `ParcMainDelegate` constructor; answered by
  `SynchronizeAutoPictureInPictureVisibility` in `native_media_controls.mm`.
- **`SetVideoPictureInPictureSessionStarted`** and its call-in **`ScrubVideoPictureInPicture`**: each
  picture-in-picture session gets only its own captions, and dragging Parc's scrubber pauses and
  resumes as WebKit's scrubbing does. Both are defined in
  `content/browser/picture_in_picture/video_picture_in_picture_window_controller_impl.cc`, as each
  session starts; the call-in is declared in `video_overlay_window.mm`. Installed in
  `PreMainMessageLoopRun`; answered by `StartPictureInPictureCaptionsSession` in
  `video_overlay_window.mm`.

## Blink and renderer hooks

- **`SetMoveWebMediaPlayer`**: a Safari-identity video moved into another frame keeps playing when
  the frame that made it goes away, and its sound, Now Playing, media keys and picture in picture
  follow it to the new frame's tab. Declared in `parc_media_player_move.h`, installed at
  `third_party/blink/renderer/core/html/media/`, with its slot in Parc's `parc_media_element.cc`
  beside it, which calls it when the element moves. Blink's `modules_initializer.cc` installs it, as
  it installs its own module hooks, because the move needs the element's audio output device from
  modules; the adopting frame's `WebLocalFrameClient::ParcAdoptMediaPlayer` takes the player. A hook
  keeps the move off `LocalFrameClient` and `CoreInitializer`.

Other renderer points are direct calls from patched Blink and media files into Parc files installed
beside them: the top-band tracker and network-activity counter on LocalFrame, the media element and
AirPlay supplements, MediaCapabilities and EME rules, Safari's scripts, Media Source policy, the
hand-off readers, renderer transitions and the compositing planner and layer claims. Generic cue
colours and wrapping use `ApplyParcGenericCueStyle` in the owned in-band text-track file, called
immediately after the cue box receives its default CSS; cue mutation notifications remain on VTTCue.

## Media and FairPlay patches

- **`cdm-helper`**: only the CDM child-flags hook, in `service_factory.cc`.
- **`fairplay-media`**: the Parc accessor on each media interface, player orchestration, the
  CreateCdm and renderer-registration calls, Media Source gap bridging, late SourceBuffers, the
  renderers' reverse-playback and mixing calls, plus the FairPlay, Safari-identity and AirPlay hook
  definitions and the GPU sandbox rule. It spans 154 files across `media/base`, `media/filters`,
  `media/formats`, `media/mojo`, `media/renderers`, content's media code and Blink's platform media
  and loader. Each change sits where Chromium's private player, demuxer and renderer state lives.
  Since Chromium 157 the player is built without its frame and binds the user-activation check to the
  creating frame, so the patch drops `const` from `has_transient_user_activation_cb_` in
  `web_media_player_impl.h`; a Safari-identity player moved to another frame re-binds it there, and
  nothing else in the player or its builder lets it change frames.
- **`fairplay-compositing-direct`**: the nested render-pass planner call, the protected-layer claim
  call and the CALayer compositing core, with a per-processor switch for protected layers. Touches 22
  Viz display, frame-sink, CALayer tree, compositor and mojom files; candidate construction, the
  rounded mask, root-pass processing and the parked-compositor flag stay at their call sites.
- **`fairplay-identity-workers`**: the worker-identity definition and its four call points.
- **`fairplay-playback-controls`**: the player observer's two virtuals, the controller's scrub call
  and the picture-in-picture session and scrubbing hooks, across 24 media-session, controller,
  picture-in-picture and media-controls files and their tests.
- **`native-media-controls`**: Parc's media controls set each session's volume and route scrubbing,
  which live in MediaSessionImpl's private state; adds a per-session volume multiplier in
  `media_session_impl.{h,cc}`.
- **`native-cast`**, **`native-presentation`**, **`native-gmc-presentation`**: the Cast device dialog
  and presentation requests honor native page revocation and Parc's cast flow. The presentation patch
  adds a per-request success validator and token, and the media-controls patch an interaction guard
  and builds the dialog's Live Caption section only while Chromium's `LiveCaption` feature is on;
  the dialog decides that in its own `Init` from a hardware and OS check Parc can't set from
  outside, so only a patch can hide it. The cast route each player's notification uses is chosen in
  Parc's `native_cast_route.cc`.
- **`platform-codecs`**, **`webaudio-aac`**: format support inside Chromium's parsers and the
  AudioToolbox decoder, and pipelined MojoAudioDecoder decodes for `decodeAudioData`. Parsers are
  never forked, so these stay patches across 33 media, FFmpeg configuration, WebRTC and Web Audio
  files. AMR and H.263 play only on Safari-identity pages ([decisions](chromium-seams.md#decisions)).
- **`native-viz-capture-direct`**: a capture fix; failed or stale copies complete the capture oracle's
  frame, in `frame_sink_video_capturer_impl.cc` and its test.
- **`native-video-pip-direct`**: split links and repost warnings in Chromium's web-contents delegate,
  caption notifications, style, paint and animation integration in Blink, and the Live Caption
  button of Chromium's own picture-in-picture window, which Chromium always builds while laying out
  its controls, so the patch shows it only while `LiveCaption` is on; eight files in all.
  Native video admission runs in Parc's existing web-contents delegate override before Chromium
  enters its picture-in-picture manager. Caption bitmap painting lives in `parc_page_captions.cc`
  and uses the existing container and public layout and paint APIs; TextTrackContainer is stock.
- **`native-auto-pip-host-occlusion-direct`**: Chromium's occlusion helper is behind an off flag,
  merges shell and page states Parc keeps apart and goes quiet while not observing; entry's wait for
  the renderer's hidden acknowledgement starts and is cancelled at seven private points. Only that
  acknowledgement is a hook; the patch adds a host-occlusion setter in
  `auto_picture_in_picture_tab_helper.{h,cc}`.
- **`document-pip-minimum-size`**: Blink clamps script-requested sizes before the browser sees them;
  `third_party/blink/common/widget/constants.cc` keeps the global 52-pixel minimum.
- **`native-document-pip-content-settings`**: a document picture-in-picture window has no Views frame
  or content-setting icons, in `chrome_content_settings_utils.cc`.

## Blink and renderer patches

- **`fairplay-identity-blink-direct`**: the media element's Safari-identity gates, EME, Media Source
  and MediaCapabilities gates, Safari's script installation from LocalWindowProxy and the worker
  controller and the player-move installer. EME bindings appear on Safari-identity pages through the
  per-context `ContextEnabled=ParcSafariIdentityEme` switch answered by `ContextFeatureSettings`, so
  Blink's bindings generator, validator and runtime-feature list stay stock. Safari's autoplay rule
  lives in Parc's media element supplement and its `decodingInfo` answers in a Parc navigator
  supplement, leaving one gate each in `autoplay_policy.cc` and `media_capabilities.cc`. It spans
  78 Blink core, modules, bindings and IDL files; the element's algorithm is private to Blink.
- **`fairplay-tracks`**: Safari's text, audio and video track behaviour in 17 Blink track, cue and
  binding files. The in-band media types compile in owned `media/base/parc_inband_tracks.cc`, in
  the same media component. Generic cue styling leaves one direct owned helper call at the cue
  box's existing CSS application point; its style storage and mutation notifications stay on VTTCue.
- **`top-band-color`**: the top-band tracker's event hooks at frame install, post-canvas sampling,
  parsing, LCP, new documents and resource loads, with its Blink build registration and Mojo target,
  in seven frame, document, loader and BUILD files. A lifecycle observer runs before canvas onpaint,
  too early to sample.
- **`blink-overlay-scrollbar-fade`**: overlay scrollbars fade correctly after a theme change; no seam
  wraps the private fade timer in `scrollable_area.cc`.

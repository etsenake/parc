# Safari's FairPlay web surface in Parc

Every web-facing piece a page can use on Safari for FairPlay playback and
presentation, and where Parc stands on Safari-identity pages
([fairplay-identity.md](fairplay-identity.md)). Sources: WebKit main
(`Source/WebCore`, read 2026-11-06), the pinned Chromium tree, and the player
scripts summarized in the FairPlay notes (Netflix akira/cadmium, Apple TV+
mediakit and hls.js, Disney+ web player, TELUS's Shaka
`PatchedMediaKeysApple`). Everything Parc adds here exists only on
Safari-identity documents (and their dedicated workers where Safari exposes
it), keyed on the context's user agent like the rest of the identity.

Status: **present** (matches Safari; a harmless superset counts), **missing**,
**different** (exists but answers or behaves unlike Safari), **pending** (an
in-flight change from the named owner provides it), **decision** (an open
choice, with the default followed). Owner is the session driving the row:

- `fp-safari-eme-surface`: the legacy prefixed API (this document's author).
- `fp-eme-modern`: modern EME.
- `fp-eme-pur`: Safari's `persistent-usage-record` sessions (session types,
  release, load).
- `fp-eme-caps`: capability answers and `requestMediaKeySystemAccess`
  configuration handling (taken over from fp-eme-modern).
- `fp-mms-presentation`: ManagedMediaSource.
- `fp-presentation`: presentation/fullscreen.
- `fp-native-hls`: native HLS on AVPlayer and `skd` in the CDM.
- `fp-netflix-identity`, `fp-frame-stats`, `fp-compositor-groups`: their
  in-flight changes (WebKitMediaKeys probe, frame counts, protected layer
  placement).
- `fp-hls-keys`: the HLS key-request hookup between native HLS and the
  legacy API.
- `identity`: already shipped with the Safari identity, no open work.
- **cut**: one of Josh's explicit cuts (CDM attached after playback started,
  a page toggling its own video track, Dolby Vision profile 8, choosing a
  speaker for FairPlay audio, cenc-scheme content).

## Modern EME (`com.apple.fps`, `com.apple.fps.N_x`)

WebKit: `Modules/encryptedmedia/*`, `platform/graphics/avfoundation/CDMFairPlayStreaming.cpp`,
`objc/CDMInstanceFairPlayStreamingAVFObjC.mm`. Parc: `Engine/ParcNative/fairplay`
(core), `Engine/ParcNative/fairplay_chromium` (adapter, key system info),
`fairplay-media.patch`.

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| Key system names | `com.apple.fps` and `com.apple.fps.<anything>`, case-sensitive | same (`IsFairPlayKeySystem`) | present | fp-eme-modern |
| initDataType `cenc` | FairPlay pssh required (`supportsInitData`) | accepted; FairPlay pssh, else key IDs of other pssh boxes (Parc extension) | present | fp-eme-modern |
| initDataType `sinf` | `{"sinf":["<b64>"]}` from AVStreamDataParser; the type Safari's MSE `encrypted` event uses | `EmeInitDataType::SINF` (fairplay-media.patch), kept by rMKSA and accepted by `generateRequest` on Safari-identity pages only, passed unchanged to the core's `kSinf` | present | fp-eme-modern |
| initDataType `skd` | skd URI | `EmeInitDataType::SKD` the same way, to the core's `kSkd` (usable by MSE renderers only when the URI names the key ID); with a native HLS asset attached, named by the URI and answering the asset's resource loader key request with its own SPC in any order (`FairPlayHlsKeyLoader`) | present (enum, core); the GPU service wiring is pending with native HLS | fp-native-hls / fp-hls-keys |
| initDataType `mpts` | macOS (`HAVE(FAIRPLAYSTREAMING_MTPS_INITDATA)`): MPEG-2 TS JSON `{"codc": n, "mtyp": n, "cont": "mpts"}`, passed to AVContentKeySession unchanged, key ID `TransportStreamIdentifier` | `EmeInitDataType::MPTS` like `SINF` (Safari-identity pages only), to the core's `kMpts`: the JSON checked as `extractKeyIDsMpts` reads it, passed unchanged with no identifier, SPC content identifier and reported key ID `TransportStreamIdentifier`, raw SPC/CKC (no renderer can use its key) | present | fp-eme-caps |
| initDataType `keyids` | not offered | accepted (Parc extension) | present (superset) | fp-eme-modern |
| `encrypted` event for MSE | fires `sinf` for every protected track (`SourceBufferPrivateAVFObjC::didProvideContentKeyRequestInitializationDataForTrackID`), with or without pssh, unless the attached MediaKeys already has a session for its key IDs (`AudioVideoRendererAVFObjC::setInitData`); never `cenc` | fires `sinf` for every protected track on Safari-identity Media Source elements (`mp4_stream_parser.cc` `AddSinfInitData`, `WebMediaPlayerImpl` gate), no `cenc` or `webm` there, skipped while a session of the attached MediaKeys has a request for its key ID (`FairPlayCdm::HasSessionForInitData` via `CdmContext::ParcHasSessionForInitData`) | present | fp-eme-modern |
| Session types | `temporary`; `persistent-usage-record` when persistent state allowed (macOS: `pendingExpiredSessionReports…` exists), refused in private windows; a temporary session once persistentState is `required` refused; `persistent-license` iOS only | `persistent-usage-record` added to Blink's enum and Chromium's session types for Safari-identity pages only (elsewhere unknown, createSession's TypeError); rMKSA applies WebKit's FairPlay rules (temporary after `required`, none in private windows); the CDM takes it with persistent state allowed, session IDs are WebKit's (uppercase hex of a random 16-byte identifier); with persistent state allowed the key session keeps AVFoundation's reports in `SecureStop.plist` under `<Profile engine folder>/Parc FairPlay/MediaKeys/<top origin>/<origin>/` (browser-created, none off the record or for opaque origins, GPU sandbox rule in `fairplay-media.patch`) | present (`persistent-license` beside `temporary`: see the capability row) | fp-eme-pur |
| `setServerCertificate` | resolves true | resolves true; required before `generateRequest` | present | fp-eme-modern |
| Key statuses | usable, status-pending, released, internal-error, output-restricted (request status, SecurityLevelError, external protection status); never expired/output-downscaled | same mapping (`StatusOf` in `fairplay_key_session.mm`) | present | fp-eme-modern |
| Renewal | `update("renew")` → `license-renewal` message | same | present | fp-eme-modern |
| Release | `remove()` (`removeSessionData`): keys revoked; `persistent-usage-record` → one released key with an empty key ID per AVFoundation expired-session report whose `PlaybackSessionID` is the session ID, the reports as `license-release` (binary plist, dict or array), resolve; on macOS the session ID is the built-in key group's random UUID, which no report carries, so remove() fires an empty `keystatuseschange` and resolves with no message; temporary → empty `keystatuseschange`, NotSupportedError; `update("acknowledged")` removes found reports | same, over the key session's storage (`ExpiredSessionReports`, `fairplay_key_session.mm`) | present | fp-eme-pur |
| `load()` | `loadSession` for `persistent-usage-record`: TypeError without persistent state or storage; false without a server certificate or with no AVFoundation expired-session report whose `PlaybackSessionID` is the ID; otherwise true, then one released key with an empty key ID per report (remove() then sends them, `acknowledged` removes them); QuotaExceededError for an open session's ID; any non-empty ID is passed to the CDM (`sanitizeSessionId` keeps it) | same in the core's `LoadSession`; Blink's own session ID check stays, so a non-ASCII, unprintable or over-512-character ID is a TypeError where Safari resolves false | present; decision (Blink's ID check kept: only IDs no player saved from Safari differ) | fp-eme-pur |
| `closed` | `Promise<undefined>` | `Promise<MediaKeySessionClosedReason>` | present (superset) | fp-eme-modern |
| `expiration` | NaN | NaN | present | fp-eme-modern |
| `MediaKeys.getStatusForPolicy` | absent (not in WebKit's IDL) | absent on Safari-identity pages: a main-world script deletes it from `MediaKeys.prototype` (`parc_safari_media_keys.h`); isolated worlds keep Chromium's | present | fp-eme-modern |
| Robustness | `""` only | `""` only | present | fp-eme-modern |
| distinctiveIdentifier / persistentState | not-allowed / optional | not-supported / requestable | present | fp-eme-modern |
| Widevine hidden | n/a | refused on Safari identity (`fairplay-identity-blink.patch`) | present | identity |

## Capability answers

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `requestMediaKeySystemAccess` codecs | AVFoundation's MSE types | FairPlay `CdmCapability` (H.264, HEVC, DV profile 5, AAC, AC-3, E-AC-3) | present | fp-eme-caps |
| Configuration enum values | `encryptionScheme` and `sessionTypes` are IDL enums (`cenc`, `cbcs`; `temporary`, `persistent-usage-record`, `persistent-license`): any other value, `cbcs-1-9` included, is a TypeError for the whole call, whatever the key system | the same under Safari's identity (`navigator_request_media_key_system_access.cc`); Chrome pages skip such a capability or configuration | present | fp-eme-caps |
| FairPlay `encryptionScheme` | null or `cbcs` (`supportsMediaCapability`); a `cenc` capability is skipped | the same under Safari's identity (`media_key_system_access_initializer_base.cc`) | present | fp-eme-caps |
| FairPlay `initDataTypes` required | a configuration naming none is refused (`supportsConfiguration` finds none of its types) | the same under Safari's identity (`media_key_system_access_initializer_base.cc`) | present | fp-eme-caps |
| FairPlay capability `contentType` | codecs optional (`video/mp4` alone is supported); `video/` types only in `videoCapabilities`, `audio/` only in `audioCapabilities`, the HLS types (`application/vnd.apple.mpegurl`, `application/x-mpegurl`) in either; a type may list the other kind's codecs (AVFoundation plays muxed media); an unparsable type or one with another parameter skips only that capability | the same under Safari's identity for what FairPlay plays (`media_key_system_access_initializer_base.cc`); the HLS types, as MP4 (native HLS plays them) | present | fp-eme-caps |
| `decodingInfo`, with or without `keySystemConfiguration` | `keySystemConfiguration` isn't in WebKit's IDL: ignored, the media answered as clear, the result has no `keySystemAccess` and carries `configuration` (with `alphaChannel`). `computeMediaCapabilitiesInfo`: an HDR field refuses H.264 and needs HEVC Main10 (Dolby Vision profiles 4/5/7/8); `smooth`/`powerEfficient` from VideoToolbox (H.264 smooth, hardware; HEVC per-profile hardware, smooth up to the playback level, refused over the decode level; Dolby Vision smooth, hardware, its profiles and levels); audio alone supported, neither smooth nor power efficient | the same under Safari's identity for H.264, HEVC, Dolby Vision profile 5 (the profile Parc's FairPlay offers) and audio alone, in windows and dedicated workers (`media_capabilities.cc`, VideoToolbox read by the browser in `parc_video_toolbox_decoding.mm`) | present | fp-eme-caps |
| `decodingInfo` `spatialRendering` | WebKit's AudioConfiguration has it unflagged; with it true, `supported` follows SpatialAudioPlaybackHelperMac: the default output device's spatial audio sources (`AudioGetDeviceSpatialPreferencesForContentType`, audiovisual or audio-only) against `channels` (multichannel for more than two, mono or stereo for at least one); `smooth`/`powerEfficient` unchanged; echoed in `configuration` | the same under Safari's identity for H.264, HEVC, Dolby Vision profile 5 and audio alone (the IDL member is read on every page, Chromium still uses it only behind its flag; the browser reads the sources at each query in `parc_video_toolbox_decoding.mm`; the rule is `IsParcSafariSpatialAudioSupported` in `parc_safari_identity.h`) | present | fp-eme-caps |
| `decodingInfo` for video FairPlay doesn't play (VP9, AV1, VP8, MPEG-4 Part 2) | WebKit's VideoToolbox rules for those codecs, with the spatial audio check | Chromium's answers in WebKit's result shape, `spatialRendering` not applied | different (not FairPlay) | fp-eme-caps |
| FairPlay `sessionTypes` with `persistent-license` beside `temporary` | macOS: `requestMediaKeySystemAccess` resolves (`supportsConfiguration` passes while `temporary` is listed; persistentState becomes `required`), then `createMediaKeys` rejects with NotAllowedError in a media element task (`initializeWithConfiguration`: no persistent keys outside iOS); `persistent-license` alone, after a refused `temporary`, or without persistent state (private windows) is refused | the same under Safari's identity: the key system selector's Safari FairPlay rule (`fairplay-media.patch`), `MediaKeySystemAccess::createMediaKeys` (`fairplay-identity-blink.patch`) | present | fp-eme-caps |
| `MediaSource.isTypeSupported`, `canPlayType` (MP4) | Safari's answers incl. Dolby | identity patch answers Dolby audio and DV profile 5 like Safari | present | fp-eme-caps |
| `canPlayType('application/vnd.apple.mpegurl')` and HLS `<video src>` | "maybe"; AVPlayer plays it | "maybe"; Safari-identity pages play it through AVPlayer in the GPU process (NATIVE_HLS.md) | present | fp-native-hls |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_N'/'3_N', type)` | legacy MSE CDM: `keyrelease` (ignoring case), else MSE support | the same (`parc_webkit_media_keys.h`) | present | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps'/'1_0', type)` | true (AVFoundation player) | AVFoundation's type answers (`parc_webkit_media_keys.h`) | present | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('org.w3c.clearkey', 'application/x-mpegurl')` | true (HLS only) | true for no type or `application/x-mpegurl` | present | fp-safari-eme-surface |

## Media element timing (native HLS live and DVR)

WebKit: `platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm`,
`MediaPlayerPrivateAVFoundation.cpp`, `html/HTMLMediaElement.{idl,cpp}`, and
the GPU process's cache (`RemoteMediaPlayerProxy`, `MediaPlayerPrivateRemote`).
Parc: `Engine/ParcNative/fairplay/fairplay_hls_timeline.*`, NATIVE_HLS.md
(Live and DVR).

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `duration` of live HLS, `durationchange` | +Infinity; fires only on a real change (live to VOD at `EXT-X-ENDLIST`) | the core's timeline; the route sets it | present | fp-hls-live |
| `seekable` of HLS | one range from the smallest start to the largest end of the valid `seekableTimeRanges`, the duration's end without any, none when the end is 0 | the core's timeline; `WebMediaPlayerImpl::Seekable()` answers the native HLS demuxer's window | present | fp-hls-live |
| `getStartDate()` | WebKit IDL, unconditional: `round(currentDate − currentTime)` whole seconds sampled at ready-state changes, Invalid Date without a date or for other players, the epoch before the first ready-state change | the same method under Safari's identity (`[ContextEnabled=ParcSafariIdentity]`), values from the native HLS demuxer | present (method); dates pending (native HLS route) | fp-hls-live |
| `currentTime` setter | `unrestricted double`: +Infinity seeks to the seekable end (live edge), −Infinity and NaN to 0 | the same under Safari's identity; a TypeError elsewhere | present | fp-hls-live |
| `fastSeek(time)` | WebKit IDL: a seek with tolerance toward the current time | Safari-identity pages only; Media Source and FairPlay land on WebKit's keyframe (ChunkDemuxer, once the target is buffered), native HLS within AVPlayer's tolerance as WebKit asks it; `src=` files land exactly, which the tolerance allows | present | fp-presentation |

## Legacy prefixed EME (`WebKitMediaKeys`)

WebKit: `Modules/encryptedmedia/legacy/*`, `LegacyCDMPrivateAVFObjC.mm`
(MSE, `^com\.apple\.fps\.[23]_\d+(,\d+)*$` ignoring case),
`CDMSessionAVContentKeySession.mm` (MSE sessions), `LegacyCDMPrivateMediaPlayer`
(AVFoundation player: `com.apple.fps`, `com.apple.fps.1_0`, clear key on HLS).
Parc: `Engine/ParcRenderer/parc_webkit_media_keys.h`, a script in the main
world of Safari-identity documents built on Parc's modern FairPlay EME
(`tests/FairPlayIdentity/webkit_media_keys.mjs`).

| Piece | Safari | Status | Owner |
|---|---|---|---|
| `new WebKitMediaKeys(keySystem)`, `keySystem` | empty → InvalidAccessError; unsupported → NotSupportedError | present for 2_N/3_N; HLS key systems below | fp-safari-eme-surface |
| `createSession(type, initData)` | empty type/initData → InvalidAccessError; unsupported type → NotSupportedError | present | fp-safari-eme-surface |
| MSE 3_N protocol | createSession(type, initData = `webkitneedkey` data) → message `"certificate"` → `update(cert)` → SPC message → `update(CKC)` → `webkitkeyadded`; `update("renew")` → new SPC | present (`cenc` sessions: one message per key; `sinf` sessions raw) | fp-safari-eme-surface |
| MSE 2_N protocol | as 3_N but initData is the content identifier and the init data comes from the attached protected SourceBuffer (`update(cert)` before that → InvalidPlayerState) | present (the CDM takes the page's identifier as a `contentId` member of the source buffer's sinf JSON, `fairplay_init_data.mm`; Blink rebuilds keyids init data, so it can't carry it) | fp-safari-eme-surface |
| Secure stop (`keyrelease`, `update("acknowledged")`, expired-session message on `close()`) | the session's own AVContentKeySession keeps reports in the document's MediaKeys storage; `close()` expires it and sends the report whose PlaybackSessionID is its contentProtectionSessionIdentifier; `keyrelease` sends the first report for the certificate (none or no storage: CLIENT `'!mor'`); `acknowledged` removes it and fires `webkitkeyadded` | present on fp-eme-pur's storage (legacy keys ask for persistent state and use persistent-usage-record sessions; the core's sinf `{"legacySecureStop"}` request); a keys object's sessions share one key session, so the report comes with the last close | fp-safari-eme-surface |
| `WebKitMediaKeySession` `sessionId`, `keySystem`, `error`, `update`, `close`, `onwebkitkeyadded/error/message` | per IDL; MSE `sessionId` is empty | present | fp-safari-eme-surface |
| `WebKitMediaKeyMessageEvent` (`message`, `destinationURL`), `WebKitMediaKeyNeededEvent` (`initData`) constructors | per IDL | present; `webkitneedkey` is queued by Blink, so it is trusted as in WebKit (`webkitkeymessage`/`added`/`error` are dispatched by the script, untrusted) | fp-safari-eme-surface, fp-legacy-element |
| `WebKitMediaKeyError` codes 1–6, `systemCode` | per IDL | present | fp-safari-eme-surface |
| `HTMLMediaElement.webkitSetMediaKeys`, `webkitKeys`; `mediaKeys` null under legacy keys | per IDL, in every context; keys follow the last element set (`WebKitMediaKeys::setMediaElement`), each element keeps reporting the keys set on it, and clearing them on any element holding them detaches them | present | fp-legacy-element |
| `webkitneedkey` on MSE | `HTMLMediaElement::mediaPlayerKeyNeeded`: a trusted task at the element, with the sinf of each protected track, before `encrypted` and whether or not `encrypted` follows | present: `WebMediaPlayerImpl::OnEncryptedMediaInitData` calls `ParcWebKitMediaSourceKeyNeeded` before deciding on `encrypted` (942c8e61's skip), Blink queues the script's event (`parc_webkit_need_key.h`), for elements in or out of the tree | fp-legacy-element |
| `onwebkitneedkey`, `onwebkitkeyadded`, `onwebkitkeyerror`, `onwebkitkeymessage` content attributes | event handler content attributes on every HTML element (WebKit's `HTMLElement` handler table), no IDL attributes | present on Safari-identity documents; plain attributes elsewhere (`html_element.cc` in fairplay-identity-blink.patch) | fp-legacy-element |
| `webkitneedkey` on HLS | every `skd://` request (legacy layout: UTF-16 byte length, URI as UTF-16) and `clearkey://` request (key ID, UTF-8), CDM or not | present: the native HLS player reports every request (`OnKeyRequest`) and Blink raises it (`ParcWebKitKeyRequest`) | fp-legacy-element with fp-hls-keys, fp-hls-render |
| `MediaError.MEDIA_ERR_ENCRYPTED` (5) | constant present; error fired only with modern EME off | present | fp-safari-eme-surface |
| HLS (`com.apple.fps`, `1_0`): `isTypeSupported` and `createSession` by AVFoundation's types (`AVURLAsset.audiovisualMIMETypes`, codecs it plays); a session needs keys attached to a player (none: it does nothing); createSession(type, [URI][content ID][certificate]) takes the request the player holds for that URI (else UNKNOWN), the SPC is the first message, each update answers it and fires `webkitkeyadded`; session IDs are UUIDs | per `MediaPlayerPrivateAVFoundationObjC`, `CDMSessionAVFoundationObjC` | present; the core takes `generateRequest('skd', {"skd", "contentId"})` (`fairplay_init_data.mm`) | fp-safari-eme-surface with fp-hls-keys |
| Legacy clear key on HLS (`org.w3c.clearkey`) | HLS only (`application/x-mpegurl`); message = the key ID; `update` takes a JWK set (A128KW, oct, kid, base64 k) else CLIENT; keys fulfil the player's held `clearkey://` requests | present: a `clearkey://` request raises `webkitneedkey` unless the element's keys already hold the key, and held requests get their keys on `keysAdded`, through `WebMediaPlayer::ParcProvideClearKey`; `WebMediaPlayerImpl` passes them to the native HLS player | fp-safari-eme-surface with fp-hls-keys |

## ManagedMediaSource

WebKit: `Modules/mediasource/ManagedMediaSource.*`, `ManagedSourceBuffer.*`,
`BufferedChangeEvent.idl`. Parc: `Engine/ParcRenderer/parc_managed_media_source.h`.

| Piece | Status | Owner |
|---|---|---|
| Constructor, extends MediaSource, `isTypeSupported` | present (exactly WebKit's IDL members, `MediaSourceInit`, statics, brand checks) | fp-mms-presentation |
| `streaming`, `startstreaming`/`endstreaming`, handlers | present (WebKit's policy, gap tolerances and timing: attribute at once, events as tasks; never stops without a known element) | fp-mms-presentation |
| `quality` (`"high"`) and `onqualitychange` (WebKit IDL, unconditional) | present | fp-mms-presentation |
| `ManagedSourceBuffer` `bufferedchange`, `onbufferedchange`, `BufferedChangeEvent` | present (WebKit's timing: inside the operation, before `update`/`updateend`, with `updating` true and its guards; other changes as tasks) | fp-mms-presentation |
| Dedicated workers, `handle`, `canConstructInDedicatedWorker` | present | fp-mms-presentation |
| `src`/`<source>`/`srcObject` attachment | present | fp-mms-presentation |
| Opening without `disableRemotePlayback` or an AirPlay source (`ManagedMediaSourceNeedsAirPlay`, on in Safari for macOS) | present: Parc opens at once, as WebKit built without wireless playback targets does (`deferredMediaSourceOpenCanProgress`); AirPlay is cut | fp-mms-presentation |
| Memory-pressure purge (`SourceBuffer::memoryPressure`: active SourceBuffers keep the playback window, inactive ones empty; `bufferedchange` and `startstreaming` follow) | present (engine purge with WebKit's windows, gap tolerances and ended-source behaviour; for a multi-track SourceBuffer WebKit's keyframe choice depends on its hash-map order, Parc takes the earliest) | fp-mms-presentation |

## Presentation and fullscreen

WebKit: `html/HTMLVideoElement.{idl,cpp}`, `HTMLMediaElement.cpp`,
`MediaElementSession.cpp` (macOS: video fullscreen is element fullscreen).
Parc: `Engine/ParcRenderer/parc_webkit_presentation.h`, a main-world script on
Chromium's standard Picture-in-Picture and Fullscreen APIs, so Parc's panel
(`native-video-pip.patch`) and fullscreen window
(`native-fullscreen-window.patch`) present the video.

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `webkitSupportsPresentationMode(mode)` | fullscreen/picture-in-picture/inline support | inline always; fullscreen once a load started; picture in picture once there's video | present | fp-presentation |
| `webkitSetPresentationMode(mode)` | enters/leaves PiP or video fullscreen; ignored while changing; needs a user gesture except PiP→PiP, lifted once the element had a gesture-started load, play, volume, muted or autoplay change | same, over the standard APIs (PiP without a gesture takes Chromium's request token) | present | fp-presentation |
| `webkitPresentationMode` | `inline`/`fullscreen`/`picture-in-picture` | same; changes this API or the page's `requestPictureInPicture` starts report as WebKit's do, others when Chromium's event arrives | present | fp-presentation |
| `webkitpresentationmodechanged` event | on every mode change | same, trusted, before the standard event | present | fp-presentation |
| `webkitEnterFullscreen`/`webkitExitFullscreen` (+ `FullScreen` aliases), `webkitSupportsFullscreen`, `webkitDisplayingFullscreen` | per IDL; displaying includes PiP; enter throws InvalidStateError without a gesture (or the lifted rule) or support, or while changing | same, over element fullscreen and the standard PiP exit | present | fp-presentation |
| `webkitbeginfullscreen`/`webkitendfullscreen` events | macOS: end only on fullscreen → PiP, begin never (element fullscreen) | same, trusted; a page's own `requestPictureInPicture` from fullscreen changes the mode as WebKit's (picture in picture first, then `webkitendfullscreen`, before Chromium's fullscreen exit) | present | fp-presentation |
| `fullscreenchange`/`webkitfullscreenchange`, `fullscreenerror`/`webkitfullscreenerror` | unprefixed event, then the prefixed change unless the target or its document listens for both, and both errors, whatever the request's prefix (DocumentFullscreen) | same, in Blink's fullscreen rendering steps | present | fp-presentation |
| `disablePictureInPicture` | reflected only; never checked, so PiP (standard or webkit) still enters and setting it leaves PiP alone | same (Chromium's PiP controller and video element skip it on Safari-identity documents) | present | fp-presentation |
| Protected picture in PiP/fullscreen | AVSampleBufferDisplayLayer moves | the compositor places the protected layer at any render-pass depth, in the PiP window and fullscreen as inline | present | fp-compositor-groups |
| `webkitDecodedFrameCount`/`webkitDroppedFrameCount`, `getVideoPlaybackQuality` | decoder counts | the FairPlay renderer and the native HLS player report decoded and dropped frames | present | fp-frame-stats |
| AirPlay (`webkitShowPlaybackTargetPicker`, `webkitCurrentPlaybackTargetIsWireless`, `webkitWirelessVideoPlaybackDisabled`, `WebKitPlaybackTargetAvailabilityEvent`) | AVFoundation routes | absent; players feature-detect it and hide AirPlay | decision: casting, not playback; default left absent | fp-mms-presentation |

## Native HLS audio and text tracks

WebKit: `MediaPlayerPrivateAVFoundationObjC` (track code, legible output),
`MediaSelectionGroupAVFObjC`, `AVTrackPrivateAVFObjCImpl`,
`InbandTextTrackPrivateAVF(ObjC)`, `InbandGenericTextTrack`, `TextTrack`. Parc:
`fairplay/fairplay_hls_media_selection.*` (core), the native HLS mojo route
([NATIVE_HLS.md](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md#tracks)),
`fairplay-tracks.patch`.

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `audioTracks` of an HLS `<video src>` | the audible group's options (or the item's audio tracks), WebKit choosing by the user's languages and audio-description preference until the page enables one; ids, kinds (`main`, `alternative`, `description`), labels and languages as `AVTrackPrivateAVFObjCImpl` derives them | core reports them (`HlsMediaSelection`); the element lists them with WebKit's ids, kinds, labels and languages, not exclusive, a page's `enabled` change going to the player track by track (`fairplay-tracks.patch`, `fairplay-identity-blink.patch`); the GPU service drives them through `FairPlayHlsTrackBridge` | present | fp-hls-tracks |
| `textTracks` of an HLS `<video src>` | the legible group's options as in-band tracks (`captions` for closed captions and SDH, `forced`, `subtitles`), numbered from 0; none selected until a mode picks one | core reports them; the element lists them as in-band tracks after the others and sends mode changes back (`ParcInbandTextTrack`, `fairplay-tracks.patch`); the GPU service drives them through `FairPlayHlsTrackBridge` | present | fp-hls-tracks |
| Cues | one legible output: WebVTT as ISO WebVTT cues (`WebVTTParser::parseCueData`, header for regions and style), CEA-608/708 and other formats as generic cues (`TextTrackCueGeneric`, a `VTTCue`) added open-ended and completed by the next one | core delivers them; the element makes `VTTCue`s as `InbandGenericTextTrack` does (dedupe and extension within a quarter second, an open cue ending at the duration); a generic cue's colours are drawn as `TextTrackCueGenericBoxElement` draws them (foreground and highlight colour on the cue's text, background colour on its box, kept when an update has none) and it wraps only when its markup allows; WebKit keeps its font size and font name without drawing them, and so does Parc (`VTTCue::SetParcGenericStyle`, `fairplay-tracks.patch`) | present | fp-native-hls |
| `TextTrack.kind` `"forced"` | in `TextTrackKind` (`addTextTrack`, `<track kind>`, in-band forced subtitles); grouped and rendered with subtitles, left out of the caption menu | the same on Safari-identity documents (`fairplay-tracks.patch`); others refuse it as before (one trace: `addTextTrack("forced", label)` converts the label before throwing, where Chromium throws first) | present | fp-hls-tracks |
| Automatic text track selection | `HTMLMediaElement::configureTextTrackGroup` scored by `CaptionUserPreferencesMediaAF`: the system caption display mode (`MACaptionAppearanceGetDisplayType`; forced only by default, which shows a forced-only track whose language matches the enabled audio track's), automatic (subtitles in the user's language when the audio isn't), always on (captions/SDH preference, `MACaptionAppearanceCopySelectedLanguages`) | the same for native HLS: the player reads the system caption settings in the GPU process (MediaAccessibility display mode, caption languages, SDH preference) and the user's languages, scores the in-band tracks as `configureTextTrackGroup` with `CaptionUserPreferencesMediaAF` against the enabled audio track, and marks the track to show; the element's automatic selection shows it (`ParcInbandTextTrack::IsDefault`) and gives in-band tracks no score of Chrome's own (`automatic_track_selection.cc`). A caption setting changed while the page is open applies to tracks configured afterwards; `<track>` elements keep Blink's selection | present | fp-native-hls |
| In-band metadata track (`com.apple.streaming`, `DataCue`, `inBandMetadataTrackDispatchType`) | `InbandMetadataTextTrackPrivateAVF`: one `metadata` track (dispatch type `com.apple.streaming`) made when the item has an enabled metadata track or timed metadata arrives; ID3 and other timed metadata from `AVPlayerItemMetadataOutput` and date ranges from `AVPlayerItemMetadataCollector` become `DataCue`s whose `value` is the item (`type`, attributes, `locale`, `key`, `data`) and whose `type` names the key space; open cues end at the next item, are flushed on a seek, and show the duration meanwhile (`InbandDataTextTrack`); pages construct `DataCue`s with a value or an `ArrayBuffer` | the same on Safari-identity documents: the core reads both sources and sends add, update and remove (`HlsMediaSelection`); the element applies them as `InbandDataTextTrack` does (`ParcInbandTextTrack`) to a Blink `DataCue` (`parc_data_cue.*`, `[ContextEnabled=ParcSafariIdentity]`, as M156 Blink has none); `TextTrack.inBandMetadataTrackDispatchType` is `""` elsewhere | present | fp-native-hls |
| Chapter tracks | `InbandChapterTrackPrivateAVFObjC` from the asset's chapter metadata: one `chapters` track per `availableChapterLocales` locale (language its identifier), one WebVTT cue per chapter item (number as id, title as text), deduplicated, refreshed on `AVAssetChapterMetadataGroupsDidChangeNotification`; never auto-selected | the same: the core makes the tracks and cues (`HlsMediaSelection`, with the non-deprecated `loadChapterMetadataGroupsWithTitleLocale:`), and they reach the element as in-band text tracks of kind `chapters` with WebVTT cues; a mode change does nothing, as WebKit's private chapter track stays hidden | present | fp-native-hls |

## Netflix and Apple TV+ paths to keep

Netflix gates on `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0')` and
plays through modern EME with `cenc`. Apple TV+ (hls.js, mediakit) uses modern
EME for video; mediakit switches its encrypted audio to legacy or skd when
`WebKitMediaKeys.isTypeSupported('com.apple.fps.1_0')` is true, which it now
is, as in Safari, since native HLS serves `1_0`. Every change re-checks these
paths: the `cenc` `encrypted` event when pssh is present, Safari's `1_0`
answer, and no change to modern EME answers they use.

## Departures from WebKit

An audit of Safari mode against WebKit main (50738f45, November 6) for
behaviour that differs from WebKit's or follows one site's habits, on
November 7. Each entry gives WebKit's behaviour and source, Parc's, what a
user notices and the general fix. **Fixed** entries name the commit;
**open** ones are general fixes not made yet; **supervisor** ones need an
architectural change or touch one of Josh's decisions and went to the
supervisor first; **decision** ones are documented choices, kept.

### Modern EME (key session core)

- **License requests timed out after 15 s.** WebKit: `CDMInstanceSessionFairPlayStreamingAVFObjC::requestLicense` and `updateLicense` keep the callback until AVFoundation answers; no timer. Parc rejected `generateRequest` (NotSupportedError) and `update()` (InvalidStateError) after 15 s, also for an skd session waiting for the native HLS asset to ask for its URI. User: on a busy Mac, or an HLS page that licenses a key before the stream reaches it, the licence failed where Safari starts late. Fix: no timer; a renewal AVFoundation starts while the previous one's answer is in flight no longer orphans that update. **Fixed** 8635b6a2.
- **Error names.** WebKit: `MediaKeySession::update` rejects every CDM failure with TypeError; `generateRequest` rejects every `requestLicense` failure (no certificate, a closed session) with NotSupportedError; init data `supportsInitData` refuses is NotSupportedError (sinf, skd and mpts pass `sanitizeInitData` unchanged); a cenc session's `update()` resolves once every entry settled, failed or not (`UpdateResponseCollector`). Parc used InvalidStateError and TypeError there and rejected a cenc update whose CKCs AVFoundation refused. User: players that branch on `error.name` took a different path. **Fixed** 9bb709b1.
- **`keystatuseschange` only on change.** WebKit runs Update Key Statuses with every successful update, so the event fires even when nothing changed (a renewal). Parc fired only on a change. **Fixed** 7f25afe1.
- **Key system `com.apple.fps.`** WebKit's `CDMFactoryFairPlayStreaming::supportsKeySystem` takes anything starting with `com.apple.fps.`; Parc wanted a non-empty version. **Fixed** 567e54f5.
- **Device identifier.** WebKit passes `AVContentKeyRequestShouldRandomizeDeviceIdentifierKey` with a seed from the MediaKeys hash salt to every `makeStreamingContentKeyRequestData` (`optionsForKeyRequestWithHashSalt`); Parc passes no options. User: licence servers see one stable FairPlay device ID for the Mac across sites, which clearing site data doesn't reset. Fix: a per-origin salt from the browser. **Supervisor.**
- **Raw sessions with several requests out.** WebKit queues a session's requests and answers `m_currentRequest` (`nextRequest`); Parc sends every SPC at once and a raw CKC answers the oldest request created, not the oldest message sent. User: a renewal and a new key in flight together can get each other's CKC. Fix: answer in message order. **Fixed** bfe1e843.
- **`update("renew")` timing.** WebKit resolves `update()` with the renewal message (`didProvideRenewingRequest`), and a SecurityLevelError on the renewal reports output-restricted (`requestDidSucceed`); Parc resolved at once and kept the old key's status. **Fixed** 5ecab927 (Parc still renews the last answered key where WebKit takes the last request whatever its state, and rejects a renewal whose SPC fails where WebKit never settles).
- **`keystatuseschange` before `update()` resolves.** WebKit resolves first and queues the event; Blink fires the event Parc reports before the promise's result arrives. Needs a Blink change. **Open.**
- **Output protection before macOS 14.4.** WebKit falls back to `willOutputBeObscuredDueToInsufficientExternalProtectionForDisplays:` and the request-level delegate (`protectionStatusForRequest`); Parc reads `externalContentProtectionStatus` only on 14.4+, so Media Source keys stay `usable` on an HDCP-less display on macOS 13 to 14.3. **Open.**
- **cenc without a FairPlay pssh, `keyids`, sinf `contentId`, `legacySecureStop`, queued updates, revoke on close.** Parc extensions (core README). **Decision.**

### Media Source playback (FairPlay renderer)

- **Pitch at rates other than 1x.** WebKit: `AudioVideoRendererAVFObjC::setRate` and `setPreservesPitchAndCorrectionAlgorithm` pick Spectral off 1x with pitch preserved, else Varispeed; Parc left the SDK default (TimeDomain). User: warbly audio at 1.25x to 2x. **Fixed** 1137acfc for the default `preservesPitch`; `preservesPitch = false` still needs a render-to-GPU call (`media::mojom::Renderer` carries none). **Open** for that part.
- **Readiness waits for keys.** WebKit: `MediaSource::monitorSourceBuffers` sets `readyState` from buffered ranges alone and the clock starts once a frame and an audio sample are there (`updateAllRenderersHaveAvailableSamples`). Parc reports enough data only when both AVFoundation renderers say so, and held protected samples never reach them, so `canplay` waits for keys. User: a page that licenses after `canplay` hangs. **Supervisor.**
- **Stalls.** WebKit stalls only at the buffered end (`resetStallForTime`) and a sample held for a key doesn't stop the clock; Parc stops on a held key and polls every 100 ms with a 50 ms margin. **Supervisor.**
- **`waitingforkey`.** WebKit fires it once, after `encrypted`, when the init segment's key has no session (`setInitData`, `setWaitingForKey`); Parc fires it whenever a protected sample is held, also while a licence is pending. **Open.**
- **Natural size changes** are reported when samples are queued; WebKit reports at the first new-format sample's presentation time (`sizeWillChangeAtTime`). **Open.**
- **Re-delivery after an automatic audio flush** doesn't flush first, so a read landing in between can be enqueued twice. **Open** (WebKit's order not fully visible in the checkout).
- **Decoder reset** keeps the clock running; WebKit's `flushAndReenqueueVideo` holds it until a frame decodes. **Open**, untested on both.
- **Frame counts** poll every 250 ms; WebKit refreshes at the page's read interval, checked every 250 ms (`RemoteAudioVideoRendererProxyManager`). The comments cited a site's timeout. **Fixed** 6512c592, 0704b7dd.
- **Keys or Dolby Vision arriving after playback started** cost one restart (recipient key delivery; WebKit attaches keys per sample with an entitlement Parc can't have). **Decision**, f583a913.

### Native HLS

- **Error codes.** WebKit: `MediaPlayerPrivateAVFoundation::updateStates` makes a failed item a DecodeError; before that `assetStatus` gives NetworkError for a URL error or a misconfigured server and FormatError otherwise, by the error's own domain; `AVPlayerItemFailedToPlayToEndTime` isn't observed; a cancelled metadata key is a FormatError. Parc reported network errors for underlying URL errors after metadata, failed on the notification and stalled on a cancelled key. **Fixed** 2c4becd5.
- **`preload="metadata"`.** WebKit makes the item only for preload auto or live (`updateStates`, `setPreload`); Parc always makes it, so VOD buffers and requests licences before play. **Supervisor.**
- **Ready states.** WebKit reaches HAVE_CURRENT_DATA at the first frame and HAVE_FUTURE_DATA at ready-to-play with data ahead; Parc reports only enough data or underflow, so `loadeddata` and `canplay` come with `canplaythrough`. **Supervisor.**
- **Closing a session fails the held key request** and AVFoundation asks again; WebKit leaves it pending. **Supervisor** (documented in the core README, "HLS assets").
- **Renewal requests** (`shouldWaitForRenewalOfRequestedResource`) aren't in WebKit's loader delegate. **Fixed** 85290ed7.
- **A key AVFoundation asks for again** goes to the session that answered it as a renewal; WebKit treats it as an unexpected request (new `encrypted`, new session). **Supervisor.**
- **Seeks during a seek**: WebKit queues the latest (`seekToTarget`, `seekCompleted`); Chromium's `PipelineController` does the same before a seek reaches the player. Not a departure.
- **`x-itunes-inherit-uri-query-component`.** WebKit sets `AVURLAssetInheritURIQueryComponentFromReferencingURIKey` when the element has the attribute; Parc doesn't read it. **Open.**
- **Asset options** WebKit sets that pages can't see (sandboxed parsing, no persistent cache), and `hasEnabledAudio`/`hasEnabledVideo` changes not revisiting the media types. **Open.**
- **Display sleep** comment claimed WebKit's setting; WebKit on macOS leaves AVPlayer's default and holds its own sleep disabler. Comment **fixed** 342f579b.
- **An unplayable enabled track** is a format error at once; WebKit's asset stays loading and is checked again. Comment corrected, behaviour kept (HLS assets list no tracks). **Open.**

### Legacy `WebKitMediaKeys`

- **`webkitkeyadded` timing.** WebKit: `CDMSessionAVContentKeySession::update` and `CDMSessionAVFoundationObjC::update` hand the CKC over and report the key stored at once (`addKeyTimerFired`); there's no failure callback, so a rejected CKC raises no `webkitkeyerror`. Parc waited for the modern update and raised an error on rejection. **Fixed** 4b8bcb76.
- **HDCP on HLS sessions.** WebKit: an obscured output gives the player's legacy session `webkitkeyerror` with systemCode `'HDCP'` (`outputObscuredDueToInsufficientExternalProtectionChanged`, `playerDidReceiveError`). Parc raised nothing. **Fixed** 4b8bcb76.
- **`keyrelease` without a report** reported the CDM's code; WebKit always gives `'!mor'` (`generateKeyReleaseMessage`). **Fixed** 342f579b.
- **Protocol versions** in the key system (`com.apple.fps.3_1,2`) reach AVFoundation as `AVContentKeyRequestProtocolVersionsKey` in WebKit (`parseKeySystem`, `update`); Parc keeps only the major version. **Open.**
- **Init data across loads (2_N).** WebKit's init data lives on the player and a new load starts clean; Parc keeps an element's init data and renderer session across loads. **Open.**
- **Unrecognized init data** is refused at `update(cert)`; WebKit passes any bytes to AVFoundation. **Open.**
- **Insecure origins and frames without `allow="encrypted-media"`.** WebKit's legacy API has no secure-context or permissions-policy gate; Parc's sits on modern EME, so the constructor throws there while `isTypeSupported` says yes. **Supervisor.**
- **Secure stop per keys object**, not per session. **Decision** (legacy table above).

### Capability answers

- **Fixed lists where WebKit asks AVFoundation.** WebKit answers `requestMediaKeySystemAccess` through `isPlayableExtendedMIMEType` and the HLS key systems through `AVAssetMIMETypeCache`; Parc uses fixed lists: ALAC, FLAC, Opus and `video/mp2t` or `quicktime` containers are refused for FairPlay, and the legacy HLS list is one Mac's snapshot (`av01` yes even without AV1 hardware, `flac` no, `text/vtt` yes). **Supervisor** (AV1 for FairPlay is a decision).

### Claims

- Site habits used as reasons (frame-count polling) are gone from the code; site names left in comments name no behaviour. The Chromium README's "cached capabilities picked Dolby Vision" line went with 5093e9e1.

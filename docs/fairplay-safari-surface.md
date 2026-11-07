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
| initDataType `skd` | skd URI | `EmeInitDataType::SKD` the same way, to the core's `kSkd` (usable by MSE renderers only when the URI names the key ID) | present (enum); key requests pending | fp-native-hls / fp-hls-keys |
| initDataType `mpts` | macOS (`HAVE(FAIRPLAYSTREAMING_MTPS_INITDATA)`): MPEG-2 TS JSON `{"codc": n, "mtyp": n, "cont": "mpts"}`, passed to AVContentKeySession unchanged, key ID `TransportStreamIdentifier` | `EmeInitDataType::MPTS` like `SINF` (Safari-identity pages only), to the core's `kMpts`: the JSON checked as `extractKeyIDsMpts` reads it, passed unchanged with no identifier, SPC content identifier and reported key ID `TransportStreamIdentifier`, raw SPC/CKC (no renderer can use its key) | present | fp-eme-caps |
| initDataType `keyids` | not offered | accepted (Parc extension) | present (superset) | fp-eme-modern |
| `encrypted` event for MSE | fires `sinf` for every protected track (`SourceBufferPrivateAVFObjC::didProvideContentKeyRequestInitializationDataForTrackID`), with or without pssh, unless the attached MediaKeys already has a session for its key IDs (`AudioVideoRendererAVFObjC::setInitData`); never `cenc` | fires `sinf` for every protected track on Safari-identity Media Source elements (`mp4_stream_parser.cc` `AddSinfInitData`, `WebMediaPlayerImpl` gate), no `cenc` or `webm` there, skipped while a session of the attached MediaKeys has a request for its key ID (`FairPlayCdm::HasSessionForInitData` via `CdmContext::ParcHasSessionForInitData`) | present | fp-eme-modern |
| Session types | `temporary`; `persistent-usage-record` when persistent state allowed (macOS: `pendingExpiredSessionReports…` exists), refused in private windows; a temporary session once persistentState is `required` refused; `persistent-license` iOS only | `persistent-usage-record` added to Blink's enum and Chromium's session types for Safari-identity pages only (elsewhere unknown, createSession's TypeError); rMKSA applies WebKit's FairPlay rules (temporary after `required`, none in private windows); the CDM takes it with persistent state allowed, session IDs are WebKit's (uppercase hex of a random 16-byte identifier); with persistent state allowed the key session keeps AVFoundation's reports in `SecureStop.plist` under `<Profile engine folder>/Parc FairPlay/MediaKeys/<top origin>/<origin>/` (browser-created, none off the record or for opaque origins, GPU sandbox rule in `fairplay-media.patch`) | present | fp-eme-pur |
| `setServerCertificate` | resolves true | resolves true; required before `generateRequest` | present | fp-eme-modern |
| Key statuses | usable, status-pending, released, internal-error, output-restricted (request status, SecurityLevelError, external protection status); never expired/output-downscaled | same mapping (`StatusOf` in `fairplay_key_session.mm`) | present | fp-eme-modern |
| Renewal | `update("renew")` → `license-renewal` message | same | present | fp-eme-modern |
| Release | `remove()` (`removeSessionData`): keys revoked; `persistent-usage-record` → one released key with an empty key ID per AVFoundation expired-session report whose `PlaybackSessionID` is the session ID, the reports as `license-release` (binary plist, dict or array), resolve; on macOS the session ID is the built-in key group's random UUID, which no report carries, so remove() fires an empty `keystatuseschange` and resolves with no message; temporary → empty `keystatuseschange`, NotSupportedError; `update("acknowledged")` removes found reports | same, over the key session's storage (`ExpiredSessionReports`, `fairplay_key_session.mm`) | present | fp-eme-pur |
| `load()` | persistent sessions | rejects NotSupportedError | missing (with session type) | fp-eme-pur |
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
| FairPlay capability `contentType` | codecs optional (`video/mp4` alone is supported); `video/` types only in `videoCapabilities`, `audio/` only in `audioCapabilities`, the HLS types (`application/vnd.apple.mpegurl`, `application/x-mpegurl`) in either; a type may list the other kind's codecs (AVFoundation plays muxed media); an unparsable type or one with another parameter skips only that capability | the same under Safari's identity for what FairPlay plays (`media_key_system_access_initializer_base.cc`); the HLS types once native HLS is on (`parc::fairplay::kNativeHlsEnabled`) | present | fp-eme-caps |
| `decodingInfo`, with or without `keySystemConfiguration` | `keySystemConfiguration` isn't in WebKit's IDL: ignored, the media answered as clear, the result has no `keySystemAccess` and carries `configuration` (with `alphaChannel`). `computeMediaCapabilitiesInfo`: an HDR field refuses H.264 and needs HEVC Main10 (Dolby Vision profiles 4/5/7/8); `smooth`/`powerEfficient` from VideoToolbox (H.264 smooth, hardware; HEVC per-profile hardware, smooth up to the playback level, refused over the decode level; Dolby Vision smooth, hardware, its profiles and levels); audio alone supported, neither smooth nor power efficient | the same under Safari's identity for H.264, HEVC, Dolby Vision profile 5 (the profile Parc's FairPlay offers) and audio alone, in windows and dedicated workers (`media_capabilities.cc`, VideoToolbox read by the browser in `parc_video_toolbox_decoding.mm`) | present | fp-eme-caps |
| `decodingInfo` for video FairPlay doesn't play (VP9, AV1, VP8, MPEG-4 Part 2) and `spatialRendering` | WebKit's VideoToolbox rules for those codecs; `spatialRendering` judged against the audio output device | Chromium's answers in WebKit's result shape; `spatialRendering` isn't read (Blink keeps it behind a test flag) | different (not FairPlay) | fp-eme-caps |
| FairPlay `sessionTypes` with `persistent-license` beside `temporary` | macOS: `requestMediaKeySystemAccess` resolves (`supportsConfiguration` passes while `temporary` is listed), then `createMediaKeys` rejects with NotAllowedError (`initializeWithConfiguration`: no persistent keys outside iOS); `persistent-license` alone is refused | the configuration is refused at `requestMediaKeySystemAccess` (persistent licenses unsupported) | decision: both end without MediaKeys; Chromium's refusal kept | fp-eme-caps |
| `MediaSource.isTypeSupported`, `canPlayType` (MP4) | Safari's answers incl. Dolby | identity patch answers Dolby audio and DV profile 5 like Safari | present | fp-eme-caps |
| `canPlayType('application/vnd.apple.mpegurl')` and HLS `<video src>` | "maybe" | Chromium's | missing | fp-native-hls |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_N'/'3_N', type)` | legacy MSE CDM: `keyrelease` (ignoring case), else MSE support | the same (`parc_webkit_media_keys.h`) | present | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps'/'1_0', type)` | true (AVFoundation player) | false until native HLS exists | missing (flip when fp-native-hls lands) | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('org.w3c.clearkey', 'application/x-mpegurl')` | true (HLS only) | false | missing (with HLS) | fp-safari-eme-surface |

## Media element timing (native HLS live and DVR)

WebKit: `platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm`,
`MediaPlayerPrivateAVFoundation.cpp`, `html/HTMLMediaElement.{idl,cpp}`, and
the GPU process's cache (`RemoteMediaPlayerProxy`, `MediaPlayerPrivateRemote`).
Parc: `Engine/ParcNative/fairplay/fairplay_hls_timeline.*`, NATIVE_HLS.md
(Live and DVR).

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `duration` of live HLS, `durationchange` | +Infinity; fires only on a real change (live to VOD at `EXT-X-ENDLIST`) | the core's timeline; the route sets it | pending (native HLS route) | fp-hls-live |
| `seekable` of HLS | one range from the smallest start to the largest end of the valid `seekableTimeRanges`, the duration's end without any, none when the end is 0 | the core's timeline; `WebMediaPlayerImpl::Seekable()` answers the native HLS demuxer's window | pending (native HLS route) | fp-hls-live |
| `getStartDate()` | WebKit IDL, unconditional: `round(currentDate − currentTime)` whole seconds sampled at ready-state changes, Invalid Date without a date or for other players, the epoch before the first ready-state change | the same method under Safari's identity (`[ContextEnabled=ParcSafariIdentity]`), values from the native HLS demuxer | present (method); dates pending (native HLS route) | fp-hls-live |
| `currentTime` setter | `unrestricted double`: +Infinity seeks to the seekable end (live edge), −Infinity and NaN to 0 | the same under Safari's identity; a TypeError elsewhere | present | fp-hls-live |
| `fastSeek(time)` | WebKit IDL: a seek with tolerance toward the current time | absent (Chromium's FIXME) | missing | — |

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
| MSE 2_N protocol | as 3_N but initData is the content identifier and the init data comes from the attached protected SourceBuffer (`update(cert)` before that → InvalidPlayerState) | present (the CDM takes the page's identifier with the media's init data through a `keyids` extension, `fairplay_init_data.mm`) | fp-safari-eme-surface |
| Secure stop (`keyrelease`, `update("acknowledged")`, expired-session message on `close()`) | needs AVContentKeySession storage | different: answers as WebKit does with no stored report (`keyrelease` → CLIENT `'!mor'`, `acknowledged` → InvalidPlayerState); reports come with `persistent-usage-record` | fp-safari-eme-surface |
| `WebKitMediaKeySession` `sessionId`, `keySystem`, `error`, `update`, `close`, `onwebkitkeyadded/error/message` | per IDL; MSE `sessionId` is empty | present | fp-safari-eme-surface |
| `WebKitMediaKeyMessageEvent` (`message`, `destinationURL`), `WebKitMediaKeyNeededEvent` (`initData`) constructors | per IDL | present; `webkitneedkey` is queued by Blink, so it is trusted as in WebKit (`webkitkeymessage`/`added`/`error` are dispatched by the script, untrusted) | fp-safari-eme-surface, fp-legacy-element |
| `WebKitMediaKeyError` codes 1–6, `systemCode` | per IDL | present | fp-safari-eme-surface |
| `HTMLMediaElement.webkitSetMediaKeys`, `webkitKeys`; `mediaKeys` null under legacy keys | per IDL, in every context; keys follow the last element set (`WebKitMediaKeys::setMediaElement`), each element keeps reporting the keys set on it, and clearing them on any element holding them detaches them | present | fp-legacy-element |
| `webkitneedkey` on MSE | `HTMLMediaElement::mediaPlayerKeyNeeded`: a trusted task at the element, with the sinf of each protected track, before `encrypted` and whether or not `encrypted` follows | present: `WebMediaPlayerImpl::OnEncryptedMediaInitData` calls `ParcWebKitMediaSourceKeyNeeded` before deciding on `encrypted` (942c8e61's skip), Blink queues the script's event (`parc_webkit_need_key.h`), for elements in or out of the tree | fp-legacy-element |
| `onwebkitneedkey`, `onwebkitkeyadded`, `onwebkitkeyerror`, `onwebkitkeymessage` content attributes | event handler content attributes on every HTML element (WebKit's `HTMLElement` handler table), no IDL attributes | present on Safari-identity documents; plain attributes elsewhere (`html_element.cc` in fairplay-identity-blink.patch) | fp-legacy-element |
| `webkitneedkey` on HLS | every `skd://` request (legacy layout: UTF-16 byte length, URI as UTF-16) and `clearkey://` request (key ID, UTF-8), CDM or not | Blink side present (`ParcWebKitKeyRequest`); the player's `OnKeyRequest` for every request is the native HLS route's (NATIVE_HLS.md, Keys step 0) | fp-legacy-element with fp-hls-keys, fp-hls-render |
| `MediaError.MEDIA_ERR_ENCRYPTED` (5) | constant present; error fired only with modern EME off | present | fp-safari-eme-surface |
| HLS (`com.apple.fps`, `1_0`): `isTypeSupported` and `createSession` by AVFoundation's types (`AVURLAsset.audiovisualMIMETypes`, codecs it plays); a session needs keys attached to a player (none: it does nothing); createSession(type, [URI][content ID][certificate]) takes the request the player holds for that URI (else UNKNOWN), the SPC is the first message, each update answers it and fires `webkitkeyadded`; session IDs are UUIDs | per `MediaPlayerPrivateAVFoundationObjC`, `CDMSessionAVFoundationObjC` | present in the script, switched on with native HLS (the installer turns the script's `/*PARC_NATIVE_HLS*/` token on when `parc::fairplay::kNativeHlsEnabled` is); the core takes `generateRequest('skd', {"skd", "contentId"})` (`fairplay_init_data.mm`) | fp-safari-eme-surface with fp-hls-keys |
| Legacy clear key on HLS (`org.w3c.clearkey`) | HLS only (`application/x-mpegurl`); message = the key ID; `update` takes a JWK set (A128KW, oct, kid, base64 k) else CLIENT; keys fulfil the player's held `clearkey://` requests | session side present behind the native HLS token; element side present: a `clearkey://` request raises `webkitneedkey` unless the element's keys already hold the key, and held requests get their keys on `keysAdded`, through `WebMediaPlayer::ParcProvideClearKey`; `WebMediaPlayerImpl` to the native HLS player is the HLS route's | fp-safari-eme-surface with fp-hls-keys |

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
| Memory-pressure purge (`SourceBuffer::memoryPressure`: active SourceBuffers keep the playback window, inactive ones empty; `bufferedchange` and `startstreaming` follow) | present (engine purge in `SourceBufferStream` with WebKit's windows; an ended source keeps what follows the playable run) | fp-mms-presentation |

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
| `webkitPresentationMode` | `inline`/`fullscreen`/`picture-in-picture` | same; changes this API starts report as WebKit's do, others when Chromium's event arrives | present | fp-presentation |
| `webkitpresentationmodechanged` event | on every mode change | same, trusted, before the standard event | present | fp-presentation |
| `webkitEnterFullscreen`/`webkitExitFullscreen` (+ `FullScreen` aliases), `webkitSupportsFullscreen`, `webkitDisplayingFullscreen` | per IDL; displaying includes PiP; enter throws InvalidStateError without a gesture (or the lifted rule) or support, or while changing | same, over element fullscreen and the standard PiP exit | present | fp-presentation |
| `webkitbeginfullscreen`/`webkitendfullscreen` events | macOS: end only on fullscreen → PiP, begin never (element fullscreen) | same, trusted, for changes this API starts; a page's own `requestPictureInPicture` from fullscreen reports inline then PiP and no end event when Chromium leaves fullscreen first (as WebKit, when PiP comes up first) | different | fp-presentation |
| `fullscreenchange`/`webkitfullscreenchange`, `fullscreenerror`/`webkitfullscreenerror` | unprefixed event, then the prefixed change unless the target or its document listens for both, and both errors, whatever the request's prefix (DocumentFullscreen) | same, in Blink's fullscreen rendering steps | present | fp-presentation |
| `disablePictureInPicture` | reflected only; never checked, so PiP (standard or webkit) still enters and setting it leaves PiP alone | same (Chromium's PiP controller and video element skip it on Safari-identity documents) | present | fp-presentation |
| Protected picture in PiP/fullscreen | AVSampleBufferDisplayLayer moves | compositor places the protected layer | pending | fp-compositor-groups |
| `webkitDecodedFrameCount`/`webkitDroppedFrameCount`, `getVideoPlaybackQuality` | decoder counts | FairPlay renderer reports | pending | fp-frame-stats |
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
| `audioTracks` of an HLS `<video src>` | the audible group's options (or the item's audio tracks), WebKit choosing by the user's languages and audio-description preference until the page enables one; ids, kinds (`main`, `alternative`, `description`), labels and languages as `AVTrackPrivateAVFObjCImpl` derives them | core reports them (`HlsMediaSelection`); mojo, GPU service and the element side pending | pending | fp-hls-tracks |
| `textTracks` of an HLS `<video src>` | the legible group's options as in-band tracks (`captions` for closed captions and SDH, `forced`, `subtitles`), numbered from 0; none selected until a mode picks one | core reports them; Blink in-band text tracks pending (M156 creates none) | pending | fp-hls-tracks |
| Cues | one legible output: WebVTT as ISO WebVTT cues (`WebVTTParser::parseCueData`, header for regions and style), CEA-608/708 and other formats as generic `VTTCue`s added open-ended and completed by the next one | core delivers them; the element side pending | pending | fp-hls-tracks |
| `TextTrack.kind` `"forced"` | in `TextTrackKind` (`addTextTrack`, `<track kind>`, in-band forced subtitles); grouped and rendered with subtitles, left out of the caption menu | the same on Safari-identity documents (`fairplay-tracks.patch`); others refuse it as before (one trace: `addTextTrack("forced", label)` converts the label before throwing, where Chromium throws first) | present | fp-hls-tracks |
| Automatic text track selection | `CaptionUserPreferencesMediaAF`: the system caption display mode (forced only by default), languages, audio language | Blink's (user preference, default attribute) | missing | fp-hls-tracks |
| In-band metadata track (`com.apple.streaming`, `DataCue`, `inBandMetadataTrackDispatchType`) | a `metadata` text track for timed metadata, `DataCue` with `value`/`type` | absent | missing | fp-hls-tracks |
| Chapter tracks | `InbandChapterTrackPrivateAVFObjC` from the asset's chapter metadata | absent | missing | fp-hls-tracks |

## Netflix and Apple TV+ paths to keep

Netflix gates on `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0')` and
plays through modern EME with `cenc`. Apple TV+ (hls.js, mediakit) uses modern
EME; mediakit only switches to legacy or skd when
`WebKitMediaKeys.isTypeSupported('com.apple.fps.1_0')` is true, which must stay
false until native HLS lands. Every change re-checks that both keep these
paths: the `cenc` `encrypted` event when pssh is present, `com.apple.fps.1_0`
false until fp-native-hls ships, and no change to modern EME answers they use.

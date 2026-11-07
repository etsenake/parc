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
- `fp-eme-modern`: modern EME and capability answers.
- `fp-mms-presentation`: ManagedMediaSource and presentation/fullscreen.
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
| initDataType `keyids` | not offered | accepted (Parc extension) | present (superset) | fp-eme-modern |
| `encrypted` event for MSE | fires `sinf` for every protected track (`SourceBufferPrivateAVFObjC::didProvideContentKeyRequestInitializationDataForTrackID`), with or without pssh | fires `cenc` only when the init/moof segment has pssh boxes (`mp4_stream_parser.cc` 889/959); FairPlay CMAF without pssh fires nothing | missing (pssh-less content); `cenc` when pssh present kept so Netflix/Apple TV+ paths don't change | fp-eme-modern |
| Session types | `temporary`; `persistent-usage-record` when persistent state allowed (macOS: `pendingExpiredSessionReports…` exists); `persistent-license` iOS only | `temporary` only; Chromium's enum has no `persistent-usage-record` | missing (`persistent-usage-record`) | fp-eme-modern |
| `setServerCertificate` | resolves true | resolves true; required before `generateRequest` | present | fp-eme-modern |
| Key statuses | usable, status-pending, released, internal-error, output-restricted (request status, SecurityLevelError, external protection status); never expired/output-downscaled | same mapping (`StatusOf` in `fairplay_key_session.mm`) | present | fp-eme-modern |
| Renewal | `update("renew")` → `license-renewal` message | same | present | fp-eme-modern |
| Release | `remove()` on `persistent-usage-record` → `license-release` with the expired-session report; temporary → keys released | temporary → keys released; no `license-release` (no usage records) | missing (with session type) | fp-eme-modern |
| `load()` | persistent sessions | rejects NotSupportedError | missing (with session type) | fp-eme-modern |
| `closed` | `Promise<undefined>` | `Promise<MediaKeySessionClosedReason>` | present (superset) | fp-eme-modern |
| `expiration` | NaN | NaN | present | fp-eme-modern |
| `MediaKeys.getStatusForPolicy` | absent (not in WebKit's IDL) | absent on Safari-identity pages: a main-world script deletes it from `MediaKeys.prototype` (`parc_safari_media_keys.h`); isolated worlds keep Chromium's | present | fp-eme-modern |
| Robustness | `""` only | `""` only | present | fp-eme-modern |
| distinctiveIdentifier / persistentState | not-allowed / optional | not-supported / requestable | present | fp-eme-modern |
| encryptionScheme | `cbcs`, `cbcs-1-9` | `cbcs`, `cbcs-1-9` (Blink maps it to `cbcs`); `cenc` listed but cut | present | fp-eme-modern |
| Widevine hidden | n/a | refused on Safari identity (`fairplay-identity-blink.patch`) | present | identity |

## Capability answers

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `requestMediaKeySystemAccess` codecs | AVFoundation's MSE types | FairPlay `CdmCapability` (H.264, HEVC, DV profile 5, AAC, AC-3, E-AC-3) | present | fp-eme-modern |
| `decodingInfo` with `keySystemConfiguration` | supported | supported; Widevine refused on Safari identity | present | fp-eme-modern |
| `MediaSource.isTypeSupported`, `canPlayType` (MP4) | Safari's answers incl. Dolby | identity patch answers Dolby audio and DV profile 5 like Safari | present | fp-eme-modern |
| `canPlayType('application/vnd.apple.mpegurl')` and HLS `<video src>` | "maybe" | Chromium's | missing | fp-native-hls |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_N'/'3_N', type)` | legacy MSE CDM: `keyrelease` (ignoring case), else MSE support | the same (`parc_webkit_media_keys.h`) | present | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('com.apple.fps'/'1_0', type)` | true (AVFoundation player) | false until native HLS exists | missing (flip when fp-native-hls lands) | fp-safari-eme-surface |
| `WebKitMediaKeys.isTypeSupported('org.w3c.clearkey', 'application/x-mpegurl')` | true (HLS only) | false | missing (with HLS) | fp-safari-eme-surface |

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
| `WebKitMediaKeyMessageEvent` (`message`, `destinationURL`), `WebKitMediaKeyNeededEvent` (`initData`) constructors | per IDL | present (script-made events have `isTrusted` false) | fp-safari-eme-surface |
| `WebKitMediaKeyError` codes 1–6, `systemCode` | per IDL | present | fp-safari-eme-surface |
| `HTMLMediaElement.webkitSetMediaKeys`, `webkitKeys`; `mediaKeys` null under legacy keys | per IDL | present | fp-safari-eme-surface |
| `webkitneedkey` on MSE | fired with the sinf init data for each protected track | different: carries the `encrypted` event's data (`cenc` pssh boxes; `sinf` once fp-eme-modern fires it for pssh-less content) | fp-safari-eme-surface |
| `MediaError.MEDIA_ERR_ENCRYPTED` (5) | constant present; error fired only with modern EME off | present | fp-safari-eme-surface |
| HLS (`com.apple.fps`, `1_0`): `isTypeSupported` and `createSession` by AVFoundation's types (`AVURLAsset.audiovisualMIMETypes`, codecs it plays); a session needs keys attached to a player (none: it does nothing); createSession(type, [URI][content ID][certificate]) takes the request the player holds for that URI (else UNKNOWN), the SPC is the first message, each update answers it and fires `webkitkeyadded`; session IDs are UUIDs | per `MediaPlayerPrivateAVFoundationObjC`, `CDMSessionAVFoundationObjC` | present in the script, switched on with native HLS (`/*PARC_NATIVE_HLS*/` token, turned on by the installer under `media::kParcNativeHls`); needs fp-hls-keys to take `generateRequest('skd', {"skd", "contentId"})` | fp-safari-eme-surface with fp-hls-keys |
| Legacy clear key on HLS (`org.w3c.clearkey`) | HLS only | missing | fp-safari-eme-surface with fp-hls-keys |

## ManagedMediaSource

WebKit: `Modules/mediasource/ManagedMediaSource.*`, `ManagedSourceBuffer.*`,
`BufferedChangeEvent.idl`. Parc: `Engine/ParcRenderer/parc_managed_media_source.h`.

| Piece | Status | Owner |
|---|---|---|
| Constructor, extends MediaSource, `isTypeSupported` | present | fp-mms-presentation |
| `streaming`, `startstreaming`/`endstreaming`, handlers | present (WebKit's policy, gap tolerances and timing: attribute at once, events as tasks; never stops without a known element) | fp-mms-presentation |
| `quality` (`"high"`) and `onqualitychange` (WebKit IDL, unconditional) | missing | fp-mms-presentation |
| `ManagedSourceBuffer` `bufferedchange`, `onbufferedchange`, `BufferedChangeEvent` | present (changes outside appends/removes up to 1 s late) | fp-mms-presentation |
| Dedicated workers, `handle`, `canConstructInDedicatedWorker` | present | fp-mms-presentation |
| `src`/`<source>`/`srcObject` attachment | present | fp-mms-presentation |

## Presentation and fullscreen

WebKit: `html/HTMLVideoElement.{idl,cpp}`, `HTMLMediaElement.cpp`. Parc maps
onto Chromium's Picture-in-Picture and fullscreen (`native-video-pip.patch`,
`native-fullscreen-window.patch`).

| Piece | Safari | Parc | Status | Owner |
|---|---|---|---|---|
| `webkitSupportsPresentationMode(mode)` | fullscreen/picture-in-picture/inline support | absent | missing | fp-mms-presentation |
| `webkitSetPresentationMode(mode)` | enters/leaves PiP or video fullscreen; ignored while changing; needs a user gesture except PiP→PiP | absent | missing | fp-mms-presentation |
| `webkitPresentationMode` | `inline`/`fullscreen`/`picture-in-picture` | absent | missing | fp-mms-presentation |
| `webkitpresentationmodechanged` event | on every mode change | absent | missing | fp-mms-presentation |
| `webkitEnterFullscreen`/`webkitExitFullscreen` (+ `FullScreen` aliases), `webkitSupportsFullscreen`, `webkitDisplayingFullscreen` | per IDL | Chromium has them | present | fp-mms-presentation |
| `webkitbeginfullscreen`/`webkitendfullscreen` events | fired around video fullscreen | absent | missing | fp-mms-presentation |
| Protected picture in PiP/fullscreen | AVSampleBufferDisplayLayer moves | compositor places the protected layer | pending | fp-compositor-groups |
| `webkitDecodedFrameCount`/`webkitDroppedFrameCount`, `getVideoPlaybackQuality` | decoder counts | FairPlay renderer reports | pending | fp-frame-stats |
| AirPlay (`webkitShowPlaybackTargetPicker`, `webkitCurrentPlaybackTargetIsWireless`, `webkitWirelessVideoPlaybackDisabled`, `WebKitPlaybackTargetAvailabilityEvent`) | AVFoundation routes | absent; players feature-detect it and hide AirPlay | decision: casting, not playback; default left absent | fp-mms-presentation |

## Netflix and Apple TV+ paths to keep

Netflix gates on `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0')` and
plays through modern EME with `cenc`. Apple TV+ (hls.js, mediakit) uses modern
EME; mediakit only switches to legacy or skd when
`WebKitMediaKeys.isTypeSupported('com.apple.fps.1_0')` is true, which must stay
false until native HLS lands. Every change re-checks that both keep these
paths: the `cenc` `encrypted` event when pssh is present, `com.apple.fps.1_0`
false until fp-native-hls ships, and no change to modern EME answers they use.

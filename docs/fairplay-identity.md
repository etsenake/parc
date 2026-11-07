# Safari identity for FairPlay sites

Sites offer Apple FairPlay only to Safari (see "Apple FairPlay inside
Chromium" in [engine-flags.md](engine-flags.md)). So Parc shows Safari's
identity to the sites that need FairPlay and stays Chrome everywhere else.
There's no built-in list of sites. Parc learns them, and the user can undo
any of them.

## What a Safari-identity page shows

The probes in the decision (a WKWebView with Safari's user agent, then the
same view with every WebKit-only API Chromium lacks removed) showed that
Netflix and Apple TV+ decide by the user agent string, `navigator.vendor` and
whether `navigator.userAgentData` exists. Apple TV+ also constructs
`ManagedMediaSource`, which Chromium doesn't have. Neither checked
`window.chrome`. That probe missed one: Netflix's UI does check legacy
`WebKitMediaKeys` (see below), and Parc 1.2.0 showed UI3001 without it.

On a page that presents Safari's identity:

- Requests carry Safari's `User-Agent`, built the way Safari builds it:
  `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15
  (KHTML, like Gecko) Version/27.2 Safari/605.1.15`. The version comes from
  the installed Safari's `CFBundleShortVersionString`, read once at engine
  start. If that can't be read, the macOS version is used, since Safari's
  version has matched macOS's since macOS 26.
- No `Sec-CH-UA*` client hints are sent: Chromium drops them when a UA
  override comes without client-hint metadata.
- `navigator.userAgent` and `navigator.appVersion` match the header.
  `navigator.vendor` is `Apple Computer, Inc.`. `navigator.userAgentData`
  doesn't exist, in the page or in its workers.
- Safari's legacy prefixed EME exists (`WebKitMediaKeys`, its sessions,
  `webkitSetMediaKeys`, `webkitneedkey`); Netflix requires its capability
  probe (see "WebKitMediaKeys" below).
- `MediaKeys` has no `getStatusForPolicy`, as in Safari (WebKit's
  `MediaKeys.idl` has none), so a player that tests for it behaves as it
  does there. A main-world script (`Engine/ParcRenderer/parc_safari_media_keys.h`),
  run with the other Safari scripts, deletes it from `MediaKeys.prototype`.
- `requestMediaKeySystemAccess` reads its configurations as WebKit's bindings
  do: an `encryptionScheme` other than `cenc` or `cbcs` (`cbcs-1-9` included)
  or a session type WebKit doesn't know is a TypeError for the whole call,
  where a Chrome page skips that capability or configuration. FairPlay takes
  a capability naming no encryption scheme or `cbcs`, as WebKit's FairPlay
  CDM does, and skips one naming `cenc`; it refuses a configuration that
  names no init data type, as that CDM does. Its capabilities read
  `contentType` as WebKit does: `video/mp4` or `audio/mp4` without codecs is
  supported, a type may also list the other kind's FairPlay codecs, and an
  unparsable type skips only that capability. The HLS types join once
  Parc's native HLS route is on.
- Widevine isn't there. `requestMediaKeySystemAccess("com.widevine.alpha")`
  rejects with `NotSupportedError` and Chromium's usual message, and
  `mediaCapabilities.decodingInfo` with a Widevine `keySystemConfiguration`
  answers unsupported. Apple TV+ probes PlayReady, Widevine and ClearKey
  before FairPlay, so it would pick Widevine and fail if it answered. FairPlay
  and ClearKey stay available (Safari has ClearKey too).
- FairPlay takes WebKit's init data types `sinf` and `skd` besides `cenc`:
  `requestMediaKeySystemAccess` keeps them in a FairPlay configuration and
  `generateRequest` accepts them. Every other page treats them as the
  unregistered names they were before. Netflix and Apple TV+ ask for `cenc`
  only.
- A Media Source element fires `encrypted` with `sinf` init data,
  `{"sinf":["<base64 sinf payload>"]}`, for each protected track of an
  initialization segment, as Safari's Media Source does. The MP4 parser
  reports it for every page (fairplay-media.patch, `mp4_stream_parser.cc`);
  `WebMediaPlayerImpl` passes it on only for Media Source on a
  Safari-identity document (`HTMLMediaElement::PresentsParcSafariIdentity`).
  Such an element hears no other `encrypted` init data: Safari's Media
  Source surfaces only `sinf`, never pssh boxes (`cenc`) or WebM key IDs.
  Elements playing a URL keep Chromium's events. As in Safari
  (`AudioVideoRendererAVFObjC::setInitData`), the event is skipped while a
  session of the element's MediaKeys has a key request, answered or not, for
  a key ID it names; a removed session keeps its requests, a closed one has
  none. The FairPlay CDM answers that from the GPU process
  (`CdmContext::ParcHasSessionForInitData` through MojoCdm), so with
  MediaKeys attached the event follows that answer.
- Service and shared workers of the site start with the same user agent
  (not those partitioned under another site's page, where the site's frames
  stay Chrome), so their `navigator.userAgent` and their fetches match, and
  their scripts
  (service worker scripts, imports and update checks, shared worker scripts)
  are requested with it. A service worker's imports from another site follow
  the worker. Dedicated workers take their document's user agent, and the
  browser requests their scripts with that document's identity.

## Dolby audio

AC-3 and E-AC-3 (Dolby Digital and Dolby Digital Plus) answer yes only in a
document presenting Safari's identity; every other page keeps Chromium's
answer from before Parc turned them on. Apple TV+ asks for `ac-3` and `ec-3`
next to Dolby Vision. fairplay-media turns on `enable_platform_ac3_eac3_audio`
and lists both codecs for FairPlay; the gate is in Blink and keys on the
context's user agent like the rest of the identity:

- `MediaSource.isTypeSupported`, `addSourceBuffer` and `SourceBuffer.changeType`
  (`MediaSource::IsTypeSupportedInternal`), for the codec IDs `ac-3`, `ec-3`,
  `mp4a.a5` and `mp4a.a6`.
- `HTMLMediaElement.canPlayType`, the choice among `<source type>` children,
  `mediaCapabilities.decodingInfo` and WebCodecs `AudioDecoder`
  (`isConfigSupported` and `configure`), so a Chrome page never hears
  "probably" from one and "no" from another. A document without a window of
  its own answers for the window that created it.
  On a Chrome page `AudioDecoder.configure()` with a Dolby codec fails with
  `NotSupportedError`, as the WebCodecs spec asks for an unsupported codec,
  where Chromium without the codecs reported `OperationError` from decoder
  setup.
- EME: `MediaKeySystemAccessInitializerBase` gives an audio capability naming
  AC-3 or E-AC-3 an unknown codec outside Safari's identity, so the key-system
  selector skips that capability and judges the rest of the configuration as
  before. Widevine's own audio support is unchanged.

## Dolby Vision

Netflix adds Dolby Vision SourceBuffers (`dvhe.05.01`, `dvhe.05.04`) and Apple
TV+ uses `dvh1.05.01`. Both ask first and drop to other streams on a "no".
Chromium plays Dolby Vision only encrypted here: fairplay-media builds with
`enable_platform_encrypted_dolby_vision`, turns `kPlatformEncryptedDolbyVision`
on for macOS and lists profile 5 for FairPlay. Chromium's own rules then
already answer yes for `addSourceBuffer`, `changeType`, EME capabilities and
`mediaCapabilities.decodingInfo` with a key system, and no for clear Dolby
Vision everywhere else. On a Safari-identity document Parc also answers yes,
as Safari does, for profile 5 (`dvh1.05.*`, `dvhe.05.*`):

- `MediaSource.isTypeSupported` checks the rest of the type without those
  codecs, as `addSourceBuffer` already does.
- `HTMLMediaElement.canPlayType` does the same; a type naming only them
  answers "probably".

Other Dolby Vision profiles, profile 8 (`dvh1.08.*`, `dvhe.08.*`) included,
keep Chromium's answer there. EME and `decodingInfo` with a key system follow
the profiles fairplay-media lists for FairPlay; `addSourceBuffer` and
`changeType` accept every Dolby Vision profile, as Chromium does once
encrypted Dolby Vision is on. The choice among
`<source type>` children keeps Chromium's answer too: a `<source>` plays as a
plain file, where clear Dolby Vision can't decode, and failing after its
metadata loaded wouldn't fall back to the next `<source>`. Clear Dolby Vision
still can't play, and `decodingInfo` without a key system still answers no.

## Which documents present it

A site is a registrable domain, private registries included, so
`user.github.io` is its own site. Each browsing context has two lists: Safari
sites, and Chrome sites. Chrome sites are ones the user moved back to Chrome,
and they win over a Safari entry. A normal Profile and its private windows
are separate contexts. The shell owns the lists and gives them to the engine
with `+[PCNativeBrowserApplication setFairPlayIdentitySafariSites:chromeSites:profilePath:offTheRecord:]`.

Each native page's contents carry Safari's user agent as Chromium's UA
override (`WebContents::SetUserAgentOverride`, without client-hint metadata).
Chromium uses it only for a navigation that asks for it, and every navigation
decides in `DidStartNavigation`, the one place
`NavigationHandle::SetIsOverridingUserAgent` is allowed:

- A main frame presents Safari's identity when its URL's site is a Safari
  site. Leaving that site in the same tab returns to Chrome.
- A subframe on the main document's site (scheme included, as site isolation
  compares it) follows the main document, wherever it sits in the page.
- A subframe on another site keeps Chrome's identity, even when its site is a
  Safari site. A fenced frame counts as a subframe of the page holding it.
- A frame without a site (about:blank, srcdoc, data:) inherits its parent.
- With site isolation turned off every subframe shares the main document's
  process, so every subframe follows the main document.
- Parc's renderer applies the override to each frame from the document of its
  local root, the main frame or the frame at the top of its process's part of
  the page (`RenderFrameImpl::ShouldUseUserAgentOverride`, changed in
  `native-host-route.patch`; upstream follows the main frame and never
  overrides a frame in another process). So a frame on the main document's
  site that Chromium puts in a process of its own, a sandboxed frame without
  `allow-same-origin` or one isolated by a response header
  (`Origin-Agent-Cluster: ?1`, `Content-Security-Policy: sandbox`), shows its
  scripts the identity its request carried. Choosing the headers by the same
  rule keeps every frame's headers equal to what its scripts see.
- Once frames have committed, a frame presents what its local root's
  document was committed with (its SiteInstanceGroup decides which frame
  that is).

The helper attaches when Parc's platform delegate receives the new contents,
which is before the first navigation of a popup or a new tab. A main-frame
commit that started before the helper existed is checked when it commits.

The renderer side keys on the context's own user agent string
(`third_party/blink/renderer/core/frame/parc_safari_identity.h`), so vendor,
`userAgentData` and Widevine always agree with what `navigator.userAgent`
shows. That also covers DevTools when it emulates a Safari user agent.

The identity is fixed when a document commits. Three cases fix a mismatch by
reloading:

- A redirect from one identity's site to the other's commits with the
  identity chosen at the start. The tab reloads once with the right one. A
  POST result isn't reloaded.
- When the lists change, each open page whose main document no longer
  matches its site's identity reloads. A page in the middle of a navigation
  is left to that navigation, a POST result isn't resubmitted, and a
  discarded tab picks up the new identity when it's next shown.
- A page restored from the back/forward cache with the old identity is
  evicted and loaded again; Chromium does that when the requested identity
  differs.

A subframe whose scripts got the wrong identity because a redirect took it
elsewhere reloads on its own: one that left the main document's site for a
process of its own while presenting Safari, or one that a redirect brought
onto the main document's site inside a cross-site frame with Chrome's
identity (a player there couldn't get Widevine or FairPlay's identity
otherwise). Its reload starts from the address it ended at, so the choice
then fits. A frame reloads at most once for each identity in a main
document, and a POST result never reloads.

## ManagedMediaSource

Apple TV+ plays titles through Safari's `ManagedMediaSource`, which Chromium
doesn't have. Whether its player falls back to plain `MediaSource` wasn't
tested. So the main world of every Safari-identity document gets a
`ManagedMediaSource` before any of the page's scripts run. The script is
`Engine/ParcRenderer/parc_managed_media_source.h`, run from
`LocalWindowProxy::Initialize` next to the `userAgentData` removal.

- `ManagedMediaSource` extends Chromium's `MediaSource`, so appends, MSE
  parsing and FairPlay decryption are Chromium's. It adds `quality`, which
  answers `"high"` as WebKit's always does (so `qualitychange` never fires),
  and `onqualitychange`; `streaming`, `startstreaming`/`endstreaming` with
  `onstartstreaming`/`onendstreaming`; and a static `isTypeSupported` that
  answers like `MediaSource`'s, as WebKit's does. The three interfaces have
  exactly the members of WebKit's IDL: `addSourceBuffer` stays on
  `MediaSource.prototype` and `canConstructInDedicatedWorker` comes from
  `MediaSource`; the constructor converts WebKit's `MediaSourceInit`;
  `BufferedChangeEvent` requires its init dictionary, takes only `TimeRanges`
  and reports ranges not given as `null`; members called on another object
  throw as WebIDL's do.
- Its SourceBuffers are `ManagedSourceBuffer`s that fire `bufferedchange`, a
  `BufferedChangeEvent` with `addedRanges` and `removedRanges` as
  `TimeRanges`, whenever their buffered ranges change. WebKit queues it while
  the append or removal that caused it (eviction during an append included)
  is still running, so the page hears it before `update` and `updateend`,
  with `updating` true. Chromium has finished the operation by then, so the
  event is dispatched as `update` arrives, ahead of the page's listeners,
  and while it is, the SourceBuffer acts as WebKit's does while updating:
  `updating` reads true; `appendBuffer`, `remove`, `changeType`, setting
  `timestampOffset`, `appendWindowStart`, `appendWindowEnd` or `mode`, and the
  source's `endOfStream()` and `duration` throw `InvalidStateError`;
  `abort()` (or `removeSourceBuffer`) ends an append with `abort` and
  `updateend` instead of `update` and `updateend`, and throws during a
  removal. An append that fails or is aborted reports what its parsing
  changed before `updateend`. Changes made outside an operation (end of
  stream, a shorter duration, an ended source reopened by setting
  `timestampOffset` or `mode`) are queued as tasks. Anything else Chromium
  changes is caught by the once-a-second check. The replaced members sit
  where Chromium has them, on `SourceBuffer.prototype` and
  `MediaSource.prototype`, and act only for managed ones.
- `streaming` follows WebKit's `ManagedMediaSource::monitorSourceBuffers`.
  With no active SourceBuffer it's true. Otherwise it turns true while the
  next 10 s after the playback position aren't buffered, and false once the
  next 30 s are; only once the source has ended are those windows capped at
  the duration, and an ended source whose position reached the duration
  stops. Buffered means the intersection of the active SourceBuffers' ranges
  (each reaching the highest end time once ended), with WebKit's gap
  tolerances: 125 ms, 250 ms where a SourceBuffer carrying audio covers the
  gap, and 1 s before a first range that starts within the first second. The
  attribute changes at once and `startstreaming`/`endstreaming` follow as
  tasks, so it's already true when the page hears `sourceopen`, and current
  when it hears `update`, `updateend`, `sourceended` and `sourceclose`. A seek
  back after `endOfStream()` starts it again. It's checked on the media
  element's playback events, as appends and removals complete and once a
  second while the source is open; that check holds the source weakly, so a
  torn-down player can still be collected. Without a known media element the
  source may start streaming but never stops, so a player that obeys it
  can't stall.
- It can be attached through `src` or `setAttribute('src')` with an object
  URL, through a `<source>` child, or through `srcObject`, as Safari allows
  (`setAttribute` is followed on media and `<source>` elements only).
  Chromium's `srcObject` takes only MediaStreams, so a managed source assigned
  there plays through an object URL. While it does, `srcObject` returns the
  source, `src` and `currentSrc` are empty as in Safari, `load()` attaches it
  again, and clearing `srcObject` restores any `src` set before.
- Dedicated workers of a Safari-identity document get it too, before their
  own script runs, and `ManagedMediaSource.canConstructInDedicatedWorker`
  answers like `MediaSource`'s (true, as in Safari). In a worker it attaches
  through `handle`; with no media element to watch, it may start streaming
  but never stops, so a player that moves its buffering to a worker because
  of that answer relies on its own buffer limits. Workers have no
  `TimeRanges` interface, so its event ranges take the prototype of the first
  real buffered ranges (an event a page builds before reading any gets plain
  objects). Its errors aren't muted, and a document that can't run scripts
  doesn't get it.
- A popup's initial empty document can hand its window and script context to
  the same-origin page it loads. That page loses `userAgentData` in every
  world when it takes the window over, and gets `ManagedMediaSource` from a
  microtask: after the commit has finished (the window's globals may hold the
  opener's getters, which mustn't run in the middle of a commit) and before
  any of its own scripts run.
- `scripts/test-fairplay-identity.sh` runs the exact script against a model of
  the media APIs (`tests/FairPlayIdentity/managed_media_source.mjs`).

## WebKitMediaKeys

Netflix's UI (`akiraClient`) decides that Safari can play DRM video with
exactly `!!(window.WebKitMediaKeys &&
WebKitMediaKeys.isTypeSupported("com.apple.fps.2_0"))`. Without it, Netflix
logs `canPlayHTML5WithDRM: false` and shows UI3001 before asking for a
manifest. Its player then uses standard EME (`com.apple.fps.3_0`, `cenc`) and
never constructs `WebKitMediaKeys`. Other players use the legacy sessions. So
the main world of every Safari-identity document gets Safari's legacy prefixed
EME for Media Source, installed with `ManagedMediaSource`, from
`Engine/ParcRenderer/parc_webkit_media_keys.h`. Workers don't get it; Safari
has it in windows only. The rows and what is still open are in
[fairplay-safari-surface.md](fairplay-safari-surface.md).

- `WebKitMediaKeys.isTypeSupported(keySystem, type)` answers true for the key
  systems of WebKit's legacy Media Source CDM, `com.apple.fps.2_N` and
  `com.apple.fps.3_N` (`LegacyCDMPrivateAVFObjC`, the same pattern). With a
  type, it answers as that CDM does: true for `keyrelease` (ignoring case),
  otherwise whether Media Source plays the type (Chromium's
  `MediaSource.isTypeSupported`, taken before any page script). `createSession`
  takes `keyrelease` only in lower case, as WebKit's `supportsMIMEType`.
- `com.apple.fps` and `com.apple.fps.1_0` belong to WebKit's AVFoundation
  player, which plays HLS through `<video src>` with skd key requests. They
  answer false, and constructing `WebKitMediaKeys` with them throws
  `NotSupportedError`, until Parc's native HLS route
  ([NATIVE_HLS.md](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md)) is
  on: the installer turns the script's `/*PARC_NATIVE_HLS*/false` token into
  true when `parc::fairplay::kNativeHlsEnabled` is (it includes the header-only
  `fairplay_key_system.h` without a GN dep, which `gn check` would flag; Parc's
  build doesn't run it). Then they follow WebKit's
  `CDMSessionAVFoundationObjC`: types by what AVFoundation decodes, sessions
  bound to the attached player's held key requests, the SPC as the first
  message, `webkitkeyadded` after every update. Clear key
  (`org.w3c.clearkey`, for `application/x-mpegurl` only) comes with them, as
  WebKit's `CDMSessionClearKey`: the key ID is the message and `update` takes a
  JWK set for the player's `clearkey://` key requests.
- `new WebKitMediaKeys(keySystem)` works for `com.apple.fps.2_N` and `3_N`
  (`InvalidAccessError` for an empty key system, `NotSupportedError` for one
  it doesn't serve, as WebKit). Its keys are a modern FairPlay `MediaKeys`
  made through the EME natives the script took before any page script ran, so
  a page that replaces `requestMediaKeySystemAccess` or `setMediaKeys` (Shaka's
  `PatchedMediaKeysApple` does, on top of `WebKitMediaKeys`) doesn't loop back
  into itself. A media element using them reports `mediaKeys` null, as in
  Safari, and keys set on a second element move there.
- `createSession(type, initData)` follows WebKit's
  `CDMSessionAVContentKeySession`. The first `webkitkeymessage` is the bytes
  `certificate`; `update(certificate)` sets the certificate and the next
  message is the SPC; `update(ckc)` answers it and fires `webkitkeyadded`;
  `update("renew")` sends a renewal SPC; `close()` closes the keys. Version 3
  takes the init data from `createSession` (the `webkitneedkey` data, `cenc`
  pssh boxes or `sinf` JSON); version 2 takes the SPC's content identifier
  there and the init data from the media the keys are attached to
  (InvalidPlayerState until it has some), which Parc's CDM takes as a `keyids`
  extension (`{"initDataType", "initData", "contentId"}`). Parc's CDM sends `cenc` requests as JSON with one SPC per
  key, so the script sends each SPC as its own message and gives each CKC to
  the oldest unanswered one. Errors are `webkitkeyerror` with a
  `WebKitMediaKeyError`: DOMAIN with the CDM's system code when an SPC can't be
  made. `keyrelease` sessions and `update("acknowledged")` answer as WebKit
  does when it holds no expired-session report (Parc keeps none).
- `webkitneedkey` (`WebKitMediaKeyNeededEvent`) fires on a media element for
  each `encrypted` event, with its init data (an skd URI in WebKit's legacy
  layout, for native HLS). The window catches every element in its tree before
  the element's own listeners, and an element with a `webkitneedkey` listener
  or legacy keys forwards its own (detached elements, shadow trees). Each
  `encrypted` event raises it once, and only the media pipeline's own
  (trusted) ones do: a page's script-made `encrypted` event doesn't.
  `MediaError.MEDIA_ERR_ENCRYPTED` is 5. These events are script-made, so
  their `isTrusted` is false.

What the other services' current scripts do with it (fetched without signing
in, November 6, 2026):

- **Apple TV+** keeps its path. Its hls.js never touches `WebKitMediaKeys`
  and picks its key system from `requestMediaKeySystemAccess`. MusicKit
  (`mediakit~*.js`) probes only `isTypeSupported("com.apple.fps.1_0", …)`, for
  `hasWebKitMediaKeysSupport` and in the media extension of its encrypted
  audio player and the native Safari video player behind a feature flag. A yes
  there would switch it to skd EME or `new WebKitMediaKeys("com.apple.fps")`.
  That probe answers false, so it stays on standard EME.
- **Disney+** keeps its path. Its web player detects DRM with
  `requestMediaKeySystemAccess` over Widevine, PlayReady, `com.apple.fps.2_0`
  and ClearKey. Its native media client constructs
  `new WebKitMediaKeys("com.apple.fps.1_0")` inside a try, but the server's
  playback schema chooses that client, not this object. The throw ends the way
  the `ReferenceError` did before.
- **TELUS TV+** changes path. On a Safari user agent its app calls Shaka's
  `PatchedMediaKeysApple.install()`, which only acts when `WebKitMediaKeys`
  exists. It then replaces `requestMediaKeySystemAccess`, `MediaKeys` and
  `HTMLMediaElement.setMediaKeys` with legacy WebKit EME, and TELUS's
  FairPlay key system, `com.apple.fps.1_0`, is refused there. Its Safari path
  (native HLS with skd FairPlay) can't play in Parc with or without the
  object, because Parc has no native HLS player. If TELUS is learned
  as a Safari site, View > Use Chrome Identity for This Site puts it back on
  Widevine.

`scripts/test-fairplay-identity.sh` runs the script
(`tests/FairPlayIdentity/webkit_media_keys.mjs`, with each service's check
copied exactly). It also checks the renderer's gate with the real
`IsParcSafariIdentityUserAgent` and the user agent Parc sends
(`tests/FairPlayIdentity/renderer_gate_main.cc`).

## How Parc learns a site

Asking for Widevine while in Chrome's identity is the signal. fairplay-media's
hook (`parc::fairplay::SetWidevineCdmRequestObserver`, called from
`MediaInterfaceProxy::CreateCdm` for `com.widevine.alpha` and its sub key
systems) reaches `OnWidevineCdmRequest` in `fairplay_identity.mm` before the
CDM exists:

- The request is let through (Widevine as today) when the page isn't a
  native page, isn't the tab's primary page, has no site, or the asking frame
  is in another process than the main document, so a reload couldn't give it
  Safari's identity. It's also let through when the user chose Chrome for the
  site.
- Otherwise the CDM is held, so no Widevine license request ever leaves.
  Netflix signs users out after a failed one. The main document's site joins
  the context's Safari sites at once. The page's observer gets
  `nativePage:didLearnSafariIdentityForSite:`, and the application client gets
  `nativeApplicationDidLearnSafariIdentityForSite:profilePath:offTheRecord:`
  even when no page forwards it, so the shell always records it. The site's
  running service workers stop (they restart with Safari's user agent), and
  every open page of that site in the context reloads with Safari's identity.
- The page holding the request reloads. If it's a POST result, its address
  loads again as a GET in place of its entry; a page a script wrote into its
  initial entry (`document.open`) has no address of its own and is left
  alone. If another navigation is waiting on a beforeunload dialog, or the
  browser is quitting or closing every window, the reload waits and tries
  again every half second until the dialog is answered or the page closes.
  Further held requests from the same page don't restart its workers again.
- A page already in Safari's identity shouldn't reach Widevine, which is
  hidden there. If one does, its request is held without a reload, so it
  can't loop.

## The lists: storage and undo

The shell keeps the lists (`Sources/ParcApp/FairPlayIdentityController.swift`,
model in `Sources/ParcCore/FairPlayIdentity.swift`):

- A Profile's lists are `Parc FairPlay Identity.json` in its engine folder,
  so they go with the Profile when it's removed. A file that can't be decoded
  is moved aside as `.damaged-<time>`, not overwritten. One that can't be
  read, or that a newer Parc wrote, stays untouched and changes stay in
  memory.
- A private window starts with its Profile's lists. Its own choices go on top
  in memory, are never written, and end when the last private window closes;
  every Profile's private lists then go back to the Profile's, including a
  site learned in a private window just before it closed.
- At engine start, the shell gives the engine every Profile's lists for its
  normal and private context, before any page loads. Every change is given to
  the engine again, and open pages update.
- View > Use Chrome Identity for This Site appears on a page whose site Parc
  learned. It moves the site to the Chrome list, so learning won't add it
  again; its open pages reload as Chrome. On a site the user moved to Chrome,
  the item reads Use Safari Identity for This Site and moves it back. It's
  hidden on every other site.

## Engine pieces

- `Engine/ParcNative/fairplay_identity.{h,mm}`: the per-page helper, the
  lists, the worker hook and the bridge methods.
  `Engine/ParcNative/fairplay_identity_policy.h` holds the decisions with no
  Chromium dependency; `scripts/test-fairplay-identity.sh` checks them.
- `fairplay-identity-blink.patch`: `navigator.vendor`, removal of
  `userAgentData` in windows (`LocalWindowProxy::Initialize`) and workers
  (`WorkerOrWorkletScriptController::PrepareForEvaluation`), the
  `ManagedMediaSource` and `WebKitMediaKeys` scripts
  (`Engine/ParcRenderer/parc_managed_media_source.h`,
  `parc_webkit_media_keys.h`), the `getStatusForPolicy` removal
  (`parc_safari_media_keys.h`), FairPlay's `sinf` and `skd` init data gate,
  and the Widevine refusal in
  `requestMediaKeySystemAccess` and `decodingInfo`.
- `fairplay-identity-workers.patch`: `content/public/browser/parc_worker_identity.h`,
  a hook that service and shared workers call as they start, and that worker
  script requests consult for their `User-Agent` (a dedicated worker's with
  its creating frame).
- `native-host.patch` adds the new sources to `libcef_static`, and
  `native-host-route.patch` makes the renderer apply the override from each
  frame's local root.

## Known limits

- A Safari site embedded by a page on another site keeps Chrome's identity
  (see the subframe rule above).
- The lists are a preference, not site data: clearing a site's data leaves
  its entry, which the user removes with the View menu item. A private
  window starts from its Profile's lists. So which learned sites present
  Safari is visible across clearing data and between a Profile and its
  private windows. Only a site the user opened and that asked for Widevine
  there gets an entry.
- A subframe that a redirect brings onto the main document's site in the
  main document's process shows its scripts the main document's identity,
  but its own request carried the identity chosen at the start. It isn't
  reloaded to fix those headers, since the response already arrived and a
  reload could repeat a one-time address (a sign-in callback).
- A prerendered page's subframes aren't checked for redirects when the
  page is activated, and fenced frames aren't checked at all: a fenced frame
  whose URL is on a Safari page's site keeps Safari's identity if a redirect
  takes it to another site.
- Chromium copies each committing subframe's identity into the page's
  history entry. Parc puts the main document's identity back after every
  subframe commit, so restoring or prerendering the entry uses the right one.
- A shared worker that is already running when its site's identity changes
  keeps the old user agent until it ends. Service workers are stopped and
  restart with the new one.
- Safari purges a `ManagedMediaSource`'s buffered data under memory
  pressure (WebKit's `SourceBuffer::memoryPressure`, from
  `HTMLMediaElement::purgeBufferedDataIfPossible`): an active SourceBuffer
  keeps only the playback window, from the earlier of the keyframe before
  the position and 3.75 s back to the end of the playable range, and an
  inactive one is emptied; `bufferedchange` and `startstreaming` follow.
  Chromium's Media Source never evicts on memory pressure, so Parc keeps the
  data and a page never sees that purge. Matching it needs a purge in
  Chromium's `SourceBufferStream` with keyframe-aware bounds (its append
  garbage collection can't express it), plumbing through `ChunkDemuxer` and
  `WebSourceBuffer`, and a memory-pressure listener on Blink's `MediaSource`
  for managed sources.
- A managed source opens without `disableRemotePlayback` or an AirPlay
  source. Safari for macOS defers `sourceopen` until one is present
  (`ManagedMediaSourceNeedsAirPlay`); WebKit built without wireless playback
  targets opens at once, as Parc does with AirPlay cut.
- `ManagedMediaSource` is a script on top of Chromium's MediaSource, not
  WebKit's engine policy (below). It is visible to a page that inspects it,
  for example through `Function.prototype.toString`. Isolated worlds and
  shared or service workers don't get it (Safari offers it to windows and
  dedicated workers). `WebKitMediaKeys` is a script too, visible the same
  way, and it overrides `addEventListener` and the `mediaKeys` getter on
  `HTMLMediaElement.prototype`. Its legacy HLS key systems wait for native
  HLS (TELUS TV+'s Shaka setup and Disney+'s native client use
  `com.apple.fps.1_0`). `getStatusForPolicy` is removed by a main-world
  script too, so isolated worlds (extensions) still see it.
- FairPlay is offered to every page, Chrome identity included, as the decision
  asks. A multi-DRM player that lists FairPlay before Widevine and has a
  FairPlay license server could now choose FairPlay on a site that used
  Widevine before. Hiding `com.apple.fps*` from Chrome-identity frames would
  keep those sites on Widevine; it's a one-line addition next to the Widevine
  refusal if wanted.

## What Josh's first build should test

Nothing here has run yet; every piece needs the engine build. Steps 1, 2, 5
and 6 need learning (the Widevine hook observer); without it, a site can be
seeded by adding it to `safari` in the Profile's `Parc FairPlay Identity.json`
while Parc is quit. On a fresh build, signed in to each service:

1. **Netflix learns.** Open netflix.com and play a title. The first Widevine
   request is held (no license request in DevTools' Network panel, no
   sign-out). The tab reloads by itself, `Parc FairPlay Identity.json` in the
   Profile's engine folder lists `netflix.com`, and the title plays through
   FairPlay (`com.apple.fps.3_0` in the media log).
2. **Apple TV+ learns.** Open tv.apple.com/ca (the store must match the
   account) and play a title; same sequence as Netflix, with the list showing
   `apple.com`. Watch whether the player constructs `ManagedMediaSource` and
   receives `startstreaming`.
3. **Identity surface on a learned site.** In the console: `navigator.userAgent`
   ends `Version/27.2 Safari/605.1.15`, `navigator.vendor` is
   `Apple Computer, Inc.`, `'userAgentData' in navigator` is `false`, and
   `navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{}])`
   rejects with `NotSupportedError`, and
   `WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0')` is `true`. Requests
   show no `Sec-CH-UA` headers.
4. **Chrome everywhere else.** Navigate the same tab to google.com: the user
   agent is Chrome's again, `navigator.userAgentData` exists and
   `'WebKitMediaKeys' in window` is `false`. A cross-site iframe on
   netflix.com reports Chrome's user agent.
5. **Undo.** View > Use Chrome Identity for This Site on Netflix reloads it as
   Chrome; the file moves `netflix.com` to `chrome`. The item then reads Use
   Safari Identity for This Site and moves it back.
6. **Private windows.** A private window plays Netflix as Safari right away
   (inherited). Learning a new site there doesn't change the file, and the
   site is forgotten after the last private window closes.

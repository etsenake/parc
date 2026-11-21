# Safari identity for FairPlay sites

Parc presents Safari's media-facing identity to sites it learns need FairPlay,
while other sites retain Chromium identity. There is no built-in site list.
The user can undo a learned choice. Pages remain in Chromium, including their
extensions, passwords, cookies, history, DevTools and native page owners.
The protected-media architecture is in [engine policy](engine-flags.md).

## What a Safari-identity page shows

Requests and scripts use a Safari User-Agent derived from the installed Safari
version read once at engine start, with the macOS version as fallback. Client
hint metadata is absent, so `Sec-CH-UA*` is omitted. `navigator.vendor` is
`Apple Computer, Inc.`; `userAgentData` is absent in documents and workers.

The media surface includes ManagedMediaSource, legacy WebKitMediaKeys and video
presentation/fullscreen helpers. `MediaKeys.getStatusForPolicy` is removed in the
main world. Widevine requests reject with NotSupportedError on this identity;
FairPlay and ClearKey remain. Ordinary Chrome-identity pages keep their existing
surface, while FairPlay itself is available to every page.

### EME and capability rules

Safari-identity EME permits HTTP and frames without an encrypted-media policy,
matching the compatibility surface. Other pages retain Chromium's security gates.
Configuration conversion rejects unknown encryption/session types with TypeError.
FairPlay accepts absent encryptionScheme or `cbcs`, skips `cenc`, and requires
an init-data type. AVFoundation checks each MIME capability; MP4 also requires a
codec the FairPlay renderer can play. HLS support follows its native platform
route. `persistent-license` beside `temporary` can select required persistent
state, but `createMediaKeys` then rejects; persistent licenses alone are refused.

FairPlay accepts `cenc`, `sinf`, `skd` and `mpts`. Media Source on Safari identity
surfaces `sinf` per protected MP4 track rather than pssh/WebM init events. A key
request already covering that ID suppresses a duplicate event; removed sessions
retain requests, closed sessions do not. SAMPLE-AES MPEG-2 TS reports `mpts`
per protected stream. Its SPC asset identifier is `TransportStreamIdentifier`,
which the license service must support. Native URL playback retains its own
init-data event route.

`mediaCapabilities.decodingInfo` ignores `keySystemConfiguration` for this
identity, returns no keySystemAccess and carries the converted configuration,
including alphaChannel. H.264/HEVC/Dolby Vision answers use browser-side
VideoToolbox capabilities. HDR fields refuse H.264 and require HEVC Main10;
profile/level constraints determine smoothness and power efficiency. Audio-only
support is neither smooth nor power-efficient. Spatial rendering additionally
checks the current audio device's source capabilities for the requested channels.
Other video codecs retain Chromium support in this result shape.

AV1 requires actual VideoToolbox hardware support on Safari identity, including
undeclared streams and configuration changes; see [AV1](media/av1-hardware.md).
Supported Dolby Vision 10/20 capability routes preserve their type support even
without platform smoothness/efficiency facts. SDR-compatible 8.2/10.2 base layers
retain compatibility ID 2 and BT.709 tagging instead of PQ.

### Presentation and playback API

The prefixed presentation/fullscreen methods map to Chromium's real PiP and
fullscreen owners. API state stays aligned with native events. Fullscreen fires
the standard event then the prefixed event unless the listener configuration
already covers both; errors fire both. `disablePictureInPicture` reflects its
attribute but does not prevent entry or force exit on Safari identity.

`fastSeek` carries a keyframe tolerance through the demuxer/pipeline. Forward
seeks cannot land before the current position; neither direction lands after the
target. MSE chooses the earliest eligible keyframe across enabled streams once
the target is buffered. Unsupported demuxers use exact seek.

`getStartDate` reports native HLS program-date-time in whole seconds, Invalid
Date for other media and epoch before the first ready-state update. Nonfinite
`currentTime` follows the compatibility surface: positive Infinity seeks to the
live edge, negative Infinity and NaN to zero. Other identities retain Chromium's
conversion rules.

## Dolby audio

AC-3/E-AC-3 are advertised only on Safari identity. MSE type queries, add/change
SourceBuffer, canPlayType, source selection, decodingInfo, WebCodecs and EME
capabilities share the gate. Chrome-identity AudioDecoder configuration refuses
these codecs with NotSupportedError; Widevine's audio support is unchanged.

## Dolby Vision

Platform Dolby Vision and encrypted Dolby Vision build flags are enabled.
Safari-identity MSE routes clear/encrypted Dolby Vision 5/8 through the FairPlay
renderer, with keys set before, after or never. A renderer handoff happens at an
eligible keyframe. Profile 5 type queries are exposed for this route; ordinary
file/source selection and other profiles retain their route-specific support
checks. Advertising one type is not a promise that every container/profile can
play. Detailed codec handling belongs to
[the renderer guide](../Engine/ParcNative/fairplay_chromium/README.md).

## Which documents present it

A site is a registrable domain, including private registries. Safari and explicit
Chrome lists belong to a browsing context; Chrome wins if both contain a site.
Normal and private contexts remain separate. The shell publishes their lists
through `setFairPlayIdentitySafariSites:chromeSites:profilePath:offTheRecord:`.

A page's native UA override is selected at navigation start:

- Main frames use their destination site's learned choice.
- Same-site subframes, including scheme, follow the main document. Cross-site
  subframes stay Chrome even when independently learned as Safari sites.
- `about:blank`, srcdoc and data frames inherit their parent. Without site
  isolation, subframes share the main document's process/identity.
- Renderer scripts use the committed document of their local root, preserving
  the identity carried by isolated same-site or sandboxed frame requests.
- Service/shared workers use their site's identity except when partitioned under
  another site's page. Dedicated workers inherit their document's identity;
  script requests, imports and update checks use the corresponding header.

The helper attaches before new-tab/popup navigation; commits that predate helper
attachment are checked as they arrive. Identity is fixed at commit. A main-frame
redirect/list change may reload once to correct it, but POST results are not
resubmitted. A running navigation determines its own result; discarded tabs
update on next show. BFCache entries with an old identity are evicted/reloaded.
Eligible redirected subframes get at most one correction per identity in the
main document, never by replaying POST. History entries are restored to the
main document's identity after subframe commits.

## ManagedMediaSource

`Engine/ParcRenderer/parc_managed_media_source.h` installs a main-world class
before page scripts. It extends Chromium MediaSource rather than creating a
second parser/decoder. Dedicated workers also receive it; shared/service workers
and extension isolated worlds do not.

- `quality` is high and does not change. The object supplies streaming state,
  start/endstreaming events, ManagedSourceBuffer and BufferedChangeEvent with
  converted TimeRanges and WebIDL-style receiver/argument checks.
- Managed buffers report added/removed ranges before page update/updateend
  listeners. During that event, updating and mutation errors behave as an active
  operation; abort/removeSourceBuffer preserve the relevant event order.
  Outside-operation changes are queued, with a periodic fallback check.
- Streaming starts when the next 10 seconds are missing and stops once 30 seconds
  are buffered. Ended sources cap those windows at duration and stop at the end;
  seeking back can restart them. Active buffers intersect with gap tolerances
  of 125 ms, 250 ms where audio covers the gap, and one second before an initial
  range beginning in the first second. State changes precede queued events.
- The monitor checks media events, append/removal completions and once a second
  while open using a weak source reference. Without an observed media element,
  including worker-owned buffering, streaming starts but never stops by design,
  so a player that obeys it can't stall and keeps its own buffer limit.
- Memory pressure empties inactive buffers and purges active data outside the
  retained playing/keyframe region. It preserves the earliest playing GOP across
  tracks and defers until active append/removal finishes. A purge does not repeat
  until playback advances. Removed ranges reach bufferedchange and can request
  streaming again. SourceBufferState, ChunkDemuxer and Blink own actual eviction.
- Attachment supports src/object URLs, source children and srcObject. A managed
  srcObject uses an internal object URL while exposing empty src/currentSrc;
  clearing it restores an earlier src. Worker attachment uses its handle.

A reused initial popup document installs helpers after commit in a microtask,
before the new page's scripts, so inherited getters cannot run during commit.

## WebKitMediaKeys

`parc_webkit_media_keys.h` installs legacy prefixed EME in Safari document main
worlds, not workers. It retains the original modern EME functions before page
scripts, preventing recursion when a service wraps the legacy layer itself.

Media Source key systems `com.apple.fps.2_N` and `.3_N` use modern FairPlay keys.
Type support checks the actual MSE route, plus keyrelease. Version 3 takes its
init data directly; version 2 combines the supplied content identifier with its
first eligible renderer-session init data. The session exchange is certificate
request → certificate update → SPC → CKC update. Session key events are
script-generated; the native `webkitneedkey` bridge produces the trusted event.
Renewal sends another SPC. Per-key requests receive their own messages and CKCs
answer the oldest outstanding request.

Legacy keys move when attached to another element and expose mediaKeys as null.
Closing the final session expires its native key session. Secure-stop reports
are kept in the document MediaKeys store outside private browsing; keyrelease
retrieves and acknowledges them. Actual native failure codes remain available
through WebKitMediaKeyError rather than fabricated success.

Native HLS serves `com.apple.fps`/`.1_0` and its attached player's key requests.
Its ClearKey route accepts `org.w3c.clearkey` for HLS and JWK updates. See
[native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md).

`webkitneedkey` is a trusted queued task before the matching encrypted event,
including detached elements and shadow trees. Blink retains its private dispatch
hook; page scripts cannot replace it. Modern encrypted events do not themselves
create a duplicate legacy event. Legacy event-handler content attributes and
MEDIA_ERR_ENCRYPTED are identity-gated.

## How Parc learns a site

The Widevine CDM request observer runs before CDM creation. It lets the request
through when the page is not a native primary page, lacks a site, originates in
another process, or the user explicitly chose Chrome. Otherwise it holds the
request before a license exchange, adds the main site's identity and notifies
both the page and app client so the shell records it.

The site's service workers stop and restart with the new identity. Open matching
pages reload; an already-Safari request is held without creating a reload loop.
The requesting POST result loads its address as GET rather than resubmitting its
body. A script-written initial page without an address is left alone. Pending
beforeunload, quit or whole-window close defers reload and retries while the
original page survives. Repeated held requests do not repeatedly stop workers.

## The lists: storage and undo

`FairPlayIdentityController.swift` and `FairPlayIdentity.swift` own each Profile's
`Parc FairPlay Identity.json` in its engine folder. Malformed JSON is
moved aside with a damaged timestamp; unreadable or newer-version files remain
untouched and changes stay in memory. Profile removal owns the file's lifetime.

Private contexts start from their normal Profile's lists; later choices are
memory-only and reset after the last private window closes. The lists are
preferences, not site data, so clearing site data does not remove an entry.
View → Use Chrome Identity for This Site moves a learned site to the override
list; the inverse menu restores Safari. Open pages update accordingly.

## Engine pieces

| Owner | Responsibility |
|---|---|
| `Engine/ParcNative/fairplay_identity.{h,mm}` | Browser-side page identity, navigation, workers, lists and bridge |
| `Engine/ParcNative/fairplay_identity_policy.h` | Chromium-independent decisions |
| `Engine/ParcRenderer` | Safari script surface, EME and capability rules, media-element supplements and player state |
| `fairplay-identity-blink-direct.patch` | Exact Blink algorithm gates, interface wiring, trusted-event call sites and the memory-pressure listener |
| `fairplay-media.patch` | Media-pipeline accessors and call sites, managed-buffer eviction, key-system/CDM/init-data integration, and parser and renderer changes that remain in Chromium |
| `fairplay-identity-workers.patch` | Worker identity and script-request call sites |
| `native-host-route-direct-overlay.patch` | Per-local-root renderer identity |

## Known limits

- HLS relies on platform client-URL-loading SPI. Missing SPI produces unsupported
  source rather than bypassing Chromium networking. MSE does not route to
  AirPlay; native HLS uses the system route list.
- A same-process redirect onto the main site can leave its already-sent request
  header different from its eventual script identity; replaying one-time callback
  URLs would be unsafe. Prerender subframe redirects and fenced-frame redirect
  correction are not covered by the ordinary subframe correction path.
- A running shared worker keeps its old identity until it ends, since ending it
  early could break a page still reloading. Service workers are stopped when
  identity changes. Cross-site embedded learned sites remain Chrome by design.
- Script compatibility layers are observable through reflection. Isolated worlds
  retain their own prototype surface. Standard PiP/fullscreen changes initiated
  elsewhere update the compatibility state when Chromium's event arrives.
- FairPlay is advertised outside Safari identity too. A multi-DRM site offering
  FairPlay first may choose it even when it previously selected Widevine.
- Learned identity persists across site-data clearing and is inherited initially
  by private windows; private learning itself does not persist.

## Validation

`FairPlayIdentityPolicyTests` exercises site decisions and navigation.
`FairPlayRendererGateTests` calls the renderer’s identity, codec, session and
key-system predicates. `WebKitNeedKeyTests` checks the init-data bytes, and
`FairPlayIdentitySitesTests` covers stored choices. The
[compatibility script checks](../scripts/test-fairplay-identity.sh) run the
five shipped scripts against JavaScript fixtures with Node. Exercising
Blink’s actual script installation and encrypted-event dispatch requires an
engine integration test. Separate FairPlay media fixtures play real content.

Page attachment and system power restrictions live in Parc-owned per-page state.
The browser client reapplies them after Chrome computes page preferences, so
settings refreshes retain the current window and power policy.

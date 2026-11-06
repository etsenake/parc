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
whether `navigator.userAgentData` exists. Neither checked `window.chrome`,
legacy `WebKitMediaKeys` or other WebKit-only APIs. Apple TV+ also constructs
`ManagedMediaSource`, which Chromium doesn't have.

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
- Widevine isn't there. `requestMediaKeySystemAccess("com.widevine.alpha")`
  rejects with `NotSupportedError` and Chromium's usual message, and
  `mediaCapabilities.decodingInfo` with a Widevine `keySystemConfiguration`
  answers unsupported. Apple TV+ probes PlayReady, Widevine and ClearKey
  before FairPlay, so it would pick Widevine and fail if it answered. FairPlay
  and ClearKey stay available (Safari has ClearKey too).
- Service and shared workers of the site start with the same user agent, so
  their `navigator.userAgent` and their fetches match. Dedicated workers
  already take their document's user agent.

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
  compares it) follows the main document.
- A subframe on another site keeps Chrome's identity, even when its site is a
  Safari site. Chromium's renderer applies the override only to frames that
  share the main document's process (`RenderFrameImpl::ShouldUseUserAgentOverride`),
  and with site isolation those are the frames on its site. Choosing the
  headers the same way keeps every frame's headers equal to what its scripts
  see. A sandboxed frame without `allow-same-origin` gets its own process, so
  it keeps Chrome's identity too.
- A frame without a site (about:blank, srcdoc, data:) inherits its parent.
- Once frames have committed, a frame counts as Safari only when it shares
  the main document's SiteInstanceGroup (its process and frame tree), which
  is what the renderer goes by.

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

## The lists: storage and undo

The shell keeps the lists (`Sources/ParcApp/FairPlayIdentityController.swift`,
model in `Sources/ParcCore/FairPlayIdentity.swift`):

- A Profile's lists are `Parc FairPlay Identity.json` in its engine folder,
  so they go with the Profile when it's removed. A file that can't be decoded
  is moved aside as `.damaged`, not overwritten; one that can't be read stays
  untouched and changes stay in memory.
- A private window starts with its Profile's lists. Its own choices go on top
  in memory, are never written, and end when the last private window closes.
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
  (`WorkerOrWorkletScriptController::PrepareForEvaluation`), and the Widevine
  refusal in `requestMediaKeySystemAccess` and `decodingInfo`.
- `fairplay-identity-workers.patch`: `content/public/browser/parc_worker_identity.h`,
  a hook that service and shared workers call as they start.
- `native-host.patch` adds the new sources to `libcef_static`.

## Known limits

- A Safari site embedded by a page on another site keeps Chrome's identity
  (see the subframe rule above).
- A same-site subframe that answers with `Origin-Agent-Cluster: ?1` or a
  `Content-Security-Policy: sandbox` header gets its own process only once its
  response arrives. Its request already carried Safari's user agent, while its
  scripts see Chrome's.
- Chromium copies each committing subframe's identity into the page's
  history entry. Parc puts the main document's identity back after every
  subframe commit, so restoring or prerendering the entry uses the right one.
- A service worker's own script request carries Chrome's user agent. The
  network service fills it in, and only the worker's script and fetches see
  Safari's.
- Chromium has no `ManagedMediaSource`, which Apple TV+ constructs.
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
   rejects with `NotSupportedError`. Requests show no `Sec-CH-UA` headers.
4. **Chrome everywhere else.** Navigate the same tab to google.com: the user
   agent is Chrome's again and `navigator.userAgentData` exists. A
   cross-site iframe on netflix.com reports Chrome's user agent.
5. **Undo.** View > Use Chrome Identity for This Site on Netflix reloads it as
   Chrome; the file moves `netflix.com` to `chrome`. The item then reads Use
   Safari Identity for This Site and moves it back.
6. **Private windows.** A private window plays Netflix as Safari right away
   (inherited). Learning a new site there doesn't change the file, and the
   site is forgotten after the last private window closes.

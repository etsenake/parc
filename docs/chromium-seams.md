# Chromium seams plan

This is the plan for the next major release. When it's done, this document becomes the durable
architecture guide. Parc stops changing Chromium's own files wherever Chromium already gives an embedder
a way in. Our logic moves into Parc-owned code. What can't move shrinks to a one-call hook inside a
Chromium source file, except for the named exceptions below, which keep a real patch: the STAY patches,
a few narrow core media headers, and some `.mm`, GN and Keychain changes. With CEF gone, Parc owns the main delegate,
the content and browser clients, its own BrowserWindow and WebContentsDelegate, so most of those ways in
are now ours to use.

There are three goals. Each Chromium upgrade, starting with 157, should become a version bump plus small
refits. Day-to-day engine work should stop recompiling large parts of Chromium. And performance and
behaviour must stay exactly as good as today, or get better.

The four research reports behind this plan classify every one of our 78 patches. They're kept in the
ignored `work/chromium-seams/` folder.

## Fixed constraints

- Settled product decisions stay settled ([product status](parity.md)). Above all, protected and
  Safari-identity video stays in Chromium, on the FairPlay route, with automatically learned site
  identity. No WKWebView, no fixed site list, no pages moved out of Chromium.
- Chromium's media parsers and demuxers are never forked or copied, so their security fixes keep reaching
  us.
- Nothing on the decode or display path changes: VideoToolbox, AVSampleBufferDisplayLayer and CALayer
  placement stay as they are. No timers, extra IPC hops or frame copies are added. A hook is the same
  direct call it replaces.
- No user-visible behaviour is removed. A STAY patch keeps its behaviour until a lossless replacement is
  designed and reviewed.
- Builds use the release script. The only other compile is a targeted compile of the files a slice
  touches, on the engine copy.

## Where we start

The 78 patches add about 46,700 lines inside Chromium files, beside 409 Parc-owned files. Together they edit
284 Chromium headers. The build's recorded dependencies show the widest of those pulled into up to about
4,400 compile steps. Those records are older and partial, so read the figure as the scale of the problem,
not an exact current count.

About 84% of the patch lines are media: FairPlay plus WebKit behaviour on Safari-identity pages. About 14%
route Chromium's interface to Parc's native interface, and the rest is startup and browser ownership. About
15,300 of the lines are Parc tests appended to 53 upstream test files.

## The hook pattern

Where Chromium has no extension point, the Chromium `.cc` that owns the behaviour gets a function pointer
and a setter, defined in that file. A single Parc header, `parc/chromium_hooks.h`, declares the setters.
Chromium never includes a Parc file, so there are no BUILD edits or buildflag includes for a hook, and
upstream unit tests still link. Parc installs its interface-routing hooks in
`ParcBrowserMainExtraParts::PreMainMessageLoopRun`, beside the file-dialog factory it already installs there.
Startup and browser hooks run earlier than that: during resource initialization and before profile
services exist. Those are installed from the main delegate's early startup, never from a late
ExtraParts callback. A signature mismatch fails at link time; nothing
fails silently at runtime.

Site permissions are the reference conversion. `permission_prompt_factory.cc` declares and defines
`parc_hooks::SetPermissionPromptFactory`, and its factory returns Parc's result, a null one included, exactly
as the old patch did. The header belongs to `//parc:browser`, and only the install points include it. A
feature exposes its factory in its own header, here `CreateSitePermissionPrompt`, and the install point
passes that factory to the setter, so the `//parc/native` targets never depend on `//parc:browser`.
A hook defined inside a component library, such as `content` or `media` in component builds, carries
that library's export macro on its `.cc` declaration, as `service_factory.cc` does for
`parc_hooks::SetCdmServiceChildFlags`.

Parc state that today lives as members of Chromium classes moves into Parc-owned objects:
- Blink supplements;
- `UserData` and tab features;
- one Parc accessor per media interface, replacing many Parc methods in core headers.

Policy and heavy includes live in Parc `.cc`/`.mm` files behind a narrow owned API. A policy edit then
recompiles that Parc file and relinks. A hook edit recompiles the one Chromium file and relinks.

## What the research found

The initial interface-routing research classified 35 patches: 14 SEAM, 17 HOOK and 4 STAY. These patches edit about 60 Chromium
headers today. Afterwards about 8 remain, none with more than 42 direct includers, and the 7 Parc headers
injected into Chromium's tree go away. It proposed three shared funnels for most dialogs: the extension
dialog utilities, `ShowTabModal` and the page-info dialog. The first two carry too little context for the
dialogs Parc presents; the confirmed boundaries below say what replaced them. The 4,744-line autofill capability patch can probably be
deleted. Parc's existing bubble handler would decline every offer Parc has no interface for, and the
offers that need an account are already off, because sign-in is off. That needs a per-feature audit first.

Browser, window and startup covers 28 patches: 5 SEAM, 12 HOOK and 11 STAY. Chromium's concrete
construction, its private startup stages and its deletion rules can't be overridden, so they keep small
`.cc` hooks rather than observers. Observers would run too late to guard native deletion. The 11 STAY patches
are genuine Chromium fixes, build dependencies, Keychain naming, and three behaviours with no lossless
replacement yet:
- atomic browser import;
- native link transport;
- one fullscreen failure transition.

Media covers about 24,150 product lines. About 2,100 leave Chromium files through seams, about 8,900 move
into Parc files behind hooks or accessors, and about 13,000 stay as patches, mostly hooks and state
machines (all ±20%). About 10,000 of its 15,335 upstream test lines can follow into Parc test files. A
Parc-owned media player is rejected. Chromium picks the player once, from the URL, before any CDM
exists, so a separate player would mean forking WebMediaPlayerImpl. What stays patched has no seam:
- the HTMLMediaElement algorithm steps, though their state moves to a supplement;
- Media Source gap bridging and late SourceBuffers;
- format support in the parsers and the AudioToolbox decoder;
- reverse playback and audio mixing in the renderers;
- the CALayer compositing core;
- the EME enums;
- the Cast device dialog.

These widely included headers leave:
- `execution_context.h`, `element.h`, `node_rare_data.h` and `page.h`;
- `web_preferences.h` and its mojom;
- the local-frame clients;
- the `html_names`/`event_type_names` regeneration;
- the renderer-factory struct;
- the four FairPlay mojoms;
- the overlay-window and picture-in-picture interfaces;
- the stable media-session mojoms.

Build and tests: Parc-owned build targets per subsystem, owned test targets for the 53 upstream test files,
and a shared compile cache. Chromium's build tool can use the NativeLink server on the second Mac as a cache
only, with no remote execution. That still needs macOS-specific configuration and verification. Releases
already reuse a sealed engine when its inputs are unchanged, so once engine changes are small and rare, the
production engine build mostly happens at Chromium upgrades.

## Order of work

Each step is its own reviewable change. Each one keeps Parc working and is compiled on the engine copy
before it lands. Slices run in parallel only when their files are verified to be disjoint. The DevTools,
context-menu and file-selector work shares files across areas, so it goes through one owner.

1. **Pattern and proof.** Add `parc/chromium_hooks.h` and the install point. Convert site permissions to
   the hook pattern as the thinnest slice that proves it end to end.
2. **Delete what upstream already offers.** These need no patch:
   - interface routing: the action icon, version, licence and logo branding, and the import utility
     service use existing extension points; HTTP authentication uses an owned coordinator and tab
     helper with a narrow credential-validation hook;
   - browser: the five SEAM patches;
   - media stage 1: the key-system and CDM registration seams, the VideoToolbox facts binder, the AV1 and
     ALAC support switches, the PiP window creation seam, and presentation routing. Renderer-factory
     registration moves its bodies out, but keeps one registration call and the renderer enum and
     accessor as a small patch.
3. **Freeze headers.** This is most of the rebuild win:
   - 2a: one media accessor per interface across Renderer, Pipeline, the audio and video renderers and
     DemuxerStream;
   - 2b: the Blink public and platform accessors;
   - 2c: the widely included Blink and base headers listed above. The HTML and event names,
     `execution_context.h`, `memory_pressure_listener.h`, `element.h` and `node_rare_data.h` are back
     to Chromium's. WebKit's names are Parc statics. The EME bindings test Safari's identity themselves.
     The ManagedMediaSource listener's tag lies past every suppression mask, so nothing can silence its
     purge. The picture-in-picture caption boxes sit in a Parc set. The `ParcSafariIdentityEme` runtime
     feature stays, because Blink's IDL reader requires every `[SecureContext=…]` name to be one.
     `page.h` leaves with the WebPreferences fields in step 8.

   Browser state stays in `Browser` and the restore-state headers until step 4's ownership work lands.
4. **Move bodies behind hooks.** This is most of the refit win:
   - the interface funnels with the native dialog host;
   - page-scoped prompts such as sad tab, external protocol, certificate viewer and client certificates;
   - extension install;
   - autofill and passwords, after their audit;
   - WebAuthn and capture;
   - startup plumbing without lifecycle changes, and the central policy hooks (profile prefs, session
     cookies, the Gaia guard);
   - browser admission: first keep today's construction and deletion behind thin `.cc` calls, then
     replace the `Browser` fields with a scoped creation context and an owned lifetime record;
   - deletion and retirement, as separate slices: the central drain, the off-the-record deferral, then
     transactional close and transfer;
   - profile removal and embedded sessions, which move behind final-destruction hooks, then the
     restore-state fields leave once exact owned associations exist;
   - renderer state and page appearance:
     - WebPreferences recomputation moves into the owned browser client;
     - frame-focus subscriptions move into an owned registry;
     - top-band state moves into a supplement, keeping its exact `.cc` event hooks, its post-canvas
       sampling and its document invalidation;
   - the branding outputs, inventoried and moved with their owner, including translated outputs that
     aren't in pak files;
   - the media supplements: HTMLMediaElement with AirPlay; EME and MediaCapabilities; the
     WebMediaPlayerImpl rules; //media/filters; the Viz planner; and the renderer arithmetic, which ships
     only together with a real playback check.
5. **Parc FairPlay media service.** A Parc-owned GPU-process service and browser host, built from public
   APIs, replaces our additions to Chromium's media factories and mojoms. That removes about 1,100 upstream
   lines, 12 headers and 4 mojoms, and binds each audio grant to its own player. That last part fixes the
   known gap where the speaker indicator can be lost. It goes in as two changes, the new service first and
   then the switch-over, and can be reviewed alongside step 4.
6. **FairPlay hand-off out of the pipeline.** A Parc helper owned by the renderer wrapper, plus a decorator
   stream, replaces the hand-off code in PipelineImpl and ChunkDemuxer. Its tests move first, and the old
reader stays until those tests pass on the new path.
7. **Tests out of upstream files.** Start with the small suites (scrollbar, Viz capture, AMR), then cast,
   autofill, controls and PiP, then the large media and Blink fixtures. Keep the compatibility edits those
   tests rely on.
8. **Smaller conversions.** Auto-PiP occlusion, the playback-controls dispatcher, PiP captions over a Parc
   mojom bound to a session token, the decodeAudioData hook (measured first), and WebPreferences fields over
   a Parc mojom, whose first value must arrive before any media plays.
9. **Compile cache.** Add the macOS cache configuration to both build recipes, prove cache hits with no
   remote execution, and keep existing objects untouched.
10. **Patches as a branch.** The export and equivalence tooling comes first, and can start alongside
    step 1. Carry our Chromium changes as a branch moved by three-way merges, with a deterministic export to
    the overlay manifest. The export must match file bytes and modes exactly. There's one way to
    materialize the source, and the manifest's validation stays in place. Then take Chromium 157, or 158
    once it's stable, with that merge, as its own separately authorized build.

Optional items that each need a measured experiment and their own approval: moving the wait-for-key latch
into the player, using `SetOutputIsSecure` instead of the parked-compositor flag, a composite renderer, and
a separate FairPlay process with `CALayerHost`.

## Risks that each step must guard

- **Media:**
  - the order of media events on Safari-identity elements;
  - the clock during the hand-off to the FairPlay renderer;
  - FairPlay and HLS players never being suspended;
  - audio grants and mute;
  - CDM lifetime;
  - persistent usage records never in private windows;
  - one superlayer per CALayer, plus the parked-compositor flag;
  - the hot paths: the ChunkDemuxer lock, the video renderer lock and the audio render callback;
  - the Widevine hold, where held callbacks never run and are destroyed after their pipes;
  - reconnecting after a GPU crash;
  - one CDM service context per renderer process, with CDM IDs resolved only inside that process's context;
  - the worker decoding route;
  - the black fallback for captures;
  - nested-pass and copy-request handling;
  - PiP layer ownership and `preventsCapture`;
  - re-checking compositor features at the Chromium 157 upgrade.
- **Browser:**
  - refusing a window before a Browser exists;
  - draining the native host before deletion;
  - deferring off-the-record operations;
  - rolling back a transfer when its last tab fails;
  - crash-safe profile removal.
- **Interface:** every prompt keeps its source page and window checks, is cancelled on detach and
  navigation, and completes exactly once.

## Confirmed interface boundaries

Three proposed zero-patch routes retain their current patches. JavaScript app-modal dialogs need
factory capture when queued and ownership validation after queue advancement; the public view factory
runs only when shown and cannot preserve both guarantees. The intent picker needs its source page
through asynchronous icon loading; the BrowserWindow method does not receive that page. The context-menu
observer must run first for command dispatch; the public testing registration appends it after Chrome’s
observers. These are STAY boundaries until a lossless hook is designed. Shared DevTools and page-menu
hunks remain with their core owner.

Native page-menu presentation now enters Parc through an implementation-only hook in Chromium’s Cocoa
implementation, before the Views widget lookup. That Cocoa file no longer includes Parc, and its Cocoa
build target no longer carries a page-menu dependency. Parc still validates the source document, page
and window, and cancels the menu on navigation, detach or window invalidation. The observer patch above
remains deliberately separate: its first-dispatch, last-construction ordering is private behavior that
the public testing registration cannot preserve.

DevTools presents through hooks in the docked-tools controller, whose header is Chromium's own again. For
a Browser Parc hosts, Parc answers the controller's update, scrim and teardown calls, and holds the modal
host of docked tools as a lease over the public dialog manager. Its keyboard routing and the preparation
of a new frontend's contents are hooks too, so the DevTools files no longer include Parc. The page commands (Developer Tools,
Inspect, Console, Network) keep a small patch in `DevToolsWindow`: whether the window is closing or
loaded, and the counter that drops a stale panel reply, are private with no public query. A Parc port
couldn't tell a closing window from a loading one and would run beforeunload twice. The public toggle
also closes with another reason and reveals an undocked window instead of closing it. The frontend's
panel query stays too.

HTTP authentication keeps a source-only validation hook because a stale request’s cancellation defers
modal-list mutation. Credentials propagated from a matching request must be rejected during that gap.
The import service uses an owned utility client and protocol target; its atomic history and web-data
transaction patch stays unchanged. The licence WebUI is owned by Parc; a literal licence-host entry
stays in Chromium’s host list for address completion and bookmark import. Product-name and translated
branding outputs remain in step 4.

The toolbar and narrow-window drawers share the owned dark-logo resource. This also fixes a branding
bug: those drawers showed Chrome’s logo in dark mode while already showing Parc’s in light mode.

Extension uninstall doesn't use the extension-dialog funnel, which only sees the window once the icon
has loaded. Parc binds consent to the asking Browser, page and extension instance, and reserves the
window, before loading starts. The context menu's uninstall command reaches Parc through a hook, and
Parc subclasses Chromium's uninstall dialog, building the same model as the Views version. The crash
the research expected in that funnel isn't reachable: nothing in Chromium calls its BrowserView overload.

Folder-upload consent doesn't use `ShowTabModal` either, because Parc cancels it when the asking frame
navigates or goes away and `ShowTabModal` only receives the page. A hook in FileSelectHelper hands Parc
the frame too. The consent stays Chromium's Views dialog in Parc's sheet, so its acceptance check stays
a patch: a dialog model's accept action can only be run by a dialog host.

FileSelectHelper’s per-accept-type filter construction also stays patched. It builds the combined filter
first and, when multiple accept types match, appends their individual filters afterwards. Parc’s
file-dialog factory only receives the merged extension list, after the per-type groups and labels are
gone, so it cannot reconstruct those choices. A sole recognized type keeps its specific label even when
an unrecognized type follows it. The existing folder-upload hook in the same file remains untouched.

The neighboring extension-menu pin guard stays. Pinning still updates the preference and metrics, but
optional element-tracker feedback is skipped when a native Browser has no `BrowserElements`. Parc could
instead register a minimal `BrowserElements` for every native window, but that would change what every
Chromium caller gets when it looks up a native window’s `BrowserElements`. The local guard keeps the
exception at the only optional-feedback call that needs it.

Sad tab, open-in-app, certificate viewing and client-certificate routing are one-call hooks. Parc presents
installed pages natively and gives any other page Chromium's own interface. The sad tab's focus goes
through Parc's view delegate. Two client-certificate pieces stay patched. The selector refuses a stale
choice before Chromium shares it with other requests for the same host, which a wrapped delegate would
only see afterwards. Parc also still hosts Chromium's Views certificate list, so its first-row setup stays
exposed. The picture-in-picture occlusion registry and build dependency that rode in the open-in-app and
certificate-viewer patches stay there for their owner.

WebAuthn request creation moved to Parc's browser client, which tells the page's native context about
each request Chromium's scheduler makes. The rest of the WebAuthn patch stays. Its call sites ask
an opt-in page context and otherwise run Chromium's own dialog, ambient bubble and recovery window
unchanged. Final-answer hooks would make Parc rebuild those for every other page, and the recovery
window holds a typed lease object inside Chromium's window class.

The tab-sharing bar, its page-info link and its session profile are hooks, and the unused message
accessor the patch added is gone. Two capture fixes stay as small patches and are worth sending
upstream: the share-this-tab picker reports its own destruction and its hiding, which Parc needs to
keep the window reserved until the dialog is really gone, and the delegated system picker keeps only
an accepted session. The reader keeps private-window caches private with a plain edit, since this tree
only builds Parc. The side panel stays: Chromium has no deregistration observer for a pending entry,
the borrowed extension host has no seam, and the load-time mark is private. So does the
protocol-handler accessor, which has no public alternative.

## Browser integration boundaries

Page preference state and frame-focus subscriptions belong to Parc. The top-band
tracker is a Blink `LocalFrame` supplement. Its lifecycle observer alternative is
not equivalent: observers run before canvas onpaint, while sampling must run after
it. The frame-install, post-canvas, parsing, LCP, new-document and resource-load
implementation hooks stay.
Website-theme already uses an owned renderer observer and needs no replacement.

These remaining browser patches preserve private implementation behavior or keep
required build inputs. Declaration-only changes can move separately from the
implementation they describe:

| Boundary | Why the current patch stays |
|---|---|
| Fullscreen entry failure | Recovery needs the controller's private pending transition and original window frame. Public exit returns early once failure has made the window windowed. |
| History swipes | Cancellation must reach the retained AppKit tracker, its generation and overlay before a stale gesture can navigate. Keep the implementation's weak-owner checks, bounds coordinates and Reduce Motion behavior. The cancellation declarations can move separately into owned Objective-C categories. |
| Overlay scrollbar fading | No embedder seam wraps the private fade timer. Its callback hands visibility back to a changed theme without leaving an invisible hit target. Keep its regression test. |
| Script-requested window sizes | Blink clamps before the browser receives the request. Keep the current global 52-pixel minimum, including its effect on ordinary popups. Native PiP bounds cannot replace that clamp. |
| Mac framework layout and Keychain | Pristine GetFrameworkBundlePath rebuilds Chrome's versioned layout instead of honoring the installed framework override; PathService does not reach direct callers. Keep the Mac source and its Parc buildflag dependency as an exception to the no-Parc-includes rule. The Keychain compile definition must make its namespace mutable in both implementation and callers. |
| Native diagnostics | Responder and accessibility observers do not expose the patched branch rejection/results. Keep the opt-in probes at those branches. |
| Build dependencies | Safe Browsing needs its direct protobuf/buildflag dependencies; background extension dependencies must remain conditional. UI-owned declarations and test registrations move only with their consumers. |
| Blink top-band targets | The tracker uses internal layout/paint types and Blink's exports. Keep its core build registration and existing Mojo target until an owned target preserves that internal access and generated ABI. |

The internal extension has owned resource packaging and an exact-ID allowlist.
Its installation callback stays at Chromium's background-component registration
point: a later profile callback omits some profile types and cannot reproduce the
private test override of background-extension suppression. Its manifest key and
worker bytes stay unchanged. GCM's factory selects Parc's legacy-registration
policy; modern registration and transport remain upstream.

## Media player boundaries

WebMediaPlayerImpl keeps every call site that drives its own state: readyState
changes, seek completion, restarts, suspend decisions and observer
notifications stay in Chromium's file, in their current order. What moves out
is Parc's own machinery. The two main-thread task runners, the one that
follows a moved element's frame and the one that keeps a cast's pipeline
running in a frozen page, live in a Parc header that WebMediaPlayerImpl and
WebMediaPlayerMS include. The rules the player applies to values it holds are
pure functions in a Parc file: which codecs the FairPlay Renderer plays and
accepts through `changeType()`, the type AVFoundation is told for a file
played to an AirPlay target, and the readyState a Safari-identity Media
Source's buffered ranges give. The player still runs that check where WebKit
runs `monitorSourceBuffers`, and still makes the readyState change and the
seek's time notification itself.

Parc's per-player state lives in one object, the player's only Parc member,
which the player befriends and which reaches the player the same way. The key
tracker runs inside it: when a Safari-identity element starts and stops
waiting for a key, and which CDM it asks. Its callbacks still go through the
player's weak pointer, so they stop at the same moment as before, and the
player still calls it from the same points. The object is built before the
player's main-thread task runner, which on Safari-identity pages is the
object's frame task runner. Two of its fields are now destroyed slightly
later in the player's destructor than before, the native HLS loader and a
replaced CDM reference; both go after `Shutdown()` has stopped the pipeline,
so nothing can observe the difference.

The player header still declares Parc methods: overrides of Parc's player,
demuxer and track interfaces, and the orchestration that drives the player's
own state machine, namely the FairPlay hand-off and restarts, the AirPlay
route switch, document moves, casting while frozen and the readyState gates.
They stay in Chromium's file because they read and change the player's
private state in place, in an order Safari-identity pages depend on.

MediaCapabilities answers Safari-identity documents as WebKit's `decodingInfo`
does. Its HEVC and Dolby Vision codec-string parsers, the video rules over
VideoToolbox's facts and the shape of a finished result live in a Parc file
beside it. Chromium's file still parses the video's content type and checks
that the type plays, then hands the parsed codecs to the Parc rules. Those
two steps stay because they use that file's private content-type parser and
Media Source support check, and they run in the same order as before.

Safari's Media Source eviction, ManagedMediaSource purge, buffered-interval
math, gap tolerances and type mapping live in Parc-owned media filter files.
ChunkDemuxer still calls the policy under its existing lock and keeps every
stream lookup, range removal and parser construction primitive in place.
SourceBufferStream still advances its read cursor from `GetNextBuffer`, while a
private Parc state pointer keeps the interval history out of the Chromium
headers. Parser codec validation and the ignore-declared-codecs flag remain
with Chromium's parser factory and parser.

EME's configuration rules for Safari's identity and FairPlay live in a Parc
file beside the encrypted-media module: which init data types, codecs,
content types, containers, encryption schemes and session types a document
may ask for, which enum values throw a TypeError, and which capabilities
AVFoundation must judge and how its answers rewrite them. The initializers call
each rule at the step where it used to run, so the order of the checks is
unchanged. The AVFoundation request itself stays with the request's
initializer, a garbage-collected Blink object that owns the Mojo connection
and resumes the request when the answers arrive. The small
gates inside MediaKeySession, MediaKeys and MediaKeySystemAccess stay in
place: each is a few lines tied to that object's own events, promises or
pending updates, so moving them would only add a wrapper.

Safari-identity documents get Safari's script APIs before any page script
runs: ManagedMediaSource, the prefixed EME, Safari's MediaKeys, the video
presentation API and AirPlay availability, without `navigator.userAgentData`.
That installer lives in a Parc bindings file. LocalWindowProxy calls it where
a context is created and where a document takes over its window's context,
from a microtask in the latter case, so no script runs during the commit.
WorkerOrWorkletScriptController calls its worker half after a worker's
features are installed. These stay call sites rather than an embedder
callback, because `DidCreateScriptContext` misses the take-over path and
can't reach Blink's trusted-event internals.

The nested protected-video render-pass planner and the process-wide CALayer
claim and hand-on policy live in Parc-owned Viz files. Chromium keeps one
direct planner call and one claim hook; its candidate construction, rounded
mask primitive, root-pass processing and parked-compositor flag stay at their
original call sites. The owned policy preserves one superlayer per video,
copy-request and nested-pass handling, black capture fallbacks, Picture in
Picture ownership and `preventsCapture`. Renderer window planning and mixing
arithmetic remain patched until that separate move ships with a real playback
check.

## Decisions

- **AMR and H.263 files:** decided. They keep playing only on Safari-identity pages, exactly as they do today, so that small patch stays.
- **Autofill capability patch:** decided, it stays. The audit found Parc presents almost every gated
  offer natively, and each native sheet is built on the presentation results and request state the
  patch adds. Without them a refused sheet would count as an ignored offer and collect strikes. Only
  the password sheet's routing moved behind a hook. A later compiled slice can still free
  `autofill_client.h`, whose only change is one defaulted capability query.
- **Extension install:** decided, it stays. The research's show-time hooks only see the page once the
  prompt is ready, but Parc binds consent to the asking page's document and Browser when the prompt is
  created, and starts watching for navigation and detach before the icon loads.
- **STAY patches:** a few are better sent upstream to Chromium and WebRTC than carried forever. The
  candidates are the macOS system screen-picker fix, mp2t multi-audio, ipcm/fpcm in MP4, pipelined
  MojoAudioDecoder decodes, the global-media-controls reentrancy fix, and FFmpeg's ADTS parameters.

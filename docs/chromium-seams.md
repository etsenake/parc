# How Parc changes Chromium

Parc builds pinned Chromium with its own code beside it. This guide explains where that code lives, how
it reaches Chromium and what a new change must guard. The [hooks and patches reference](chromium-hooks.md)
lists every hook and every kept patch with its reason. The [engine guide](../Engine/README.md) covers
building and the [overlay README](../Engine/ParcHost/README.md) covers the manifest.

The rule is simple. Use an extension point Chromium already gives an embedder. Where there is none,
put Parc's logic in a Parc-owned file and leave a one-call hook in the Chromium file that owns the
behaviour. Keep a real patch only when neither preserves the behaviour exactly, and record why below.
This keeps three promises: a Chromium upgrade is a version bump plus small refits, day-to-day engine
work recompiles little of Chromium, and behaviour and performance stay exactly as they were.

## Rules every change keeps

- Settled product decisions stay settled ([product status](parity.md)). Protected and Safari-identity
  video stays in Chromium on the FairPlay route, with automatically learned site identity. No
  WKWebView, no fixed site list and no pages moved out of Chromium.
- Chromium's media parsers and demuxers are never forked or copied, so their security fixes keep
  reaching Parc.
- Nothing on the decode or display path changes: VideoToolbox, AVSampleBufferDisplayLayer and CALayer
  placement stay as they are. A hook is the same direct call it replaces, with no timer, extra IPC hop
  or frame copy.
- No user-visible behaviour is removed. A kept patch keeps its behaviour until a lossless replacement
  has been designed and reviewed.
- Builds go through the release script; engine operations need explicit authorization
  ([working contract](../AGENTS.md#engine-and-release-operations)).

## Where the code lives

[`overlay.json`](../Engine/ParcHost/overlay.json) lists every owned file with its install location
and every patch with the exact bytes it expects before and after. Owned files come from these
repository folders:

| Repository folder | Installed at | Holds |
|---|---|---|
| `Engine/ParcChromium` | `//parc` | Main delegate, content clients, hook header, branding, page preferences, frame focus, web push |
| `Engine/ParcNative` | `//parc/native` | Native BrowserWindow and Browser, page hosts, dialogs, prompts, extensions, DevTools, FairPlay host |
| `Engine/ParcRenderer` | Blink and `//media/base` layers | Media element and page supplements, player rules and state, EME, MediaCapabilities, Safari scripts, top band |
| `Engine/ParcNative/fairplay_chromium` | `//third_party/parc_fairplay`, media, content, Viz layers | FairPlay service, CDM and renderer adapters, native HLS, Media Source policy, hand-off, compositing |
| `Engine/ParcNative/fairplay` | `//third_party/parc_fairplay/core` | The FairPlay playback core ([guide](../Engine/ParcNative/fairplay/README.md)) |
| `Engine/ParcChromium/tests` | `parc_tests` folders inside each layer | Parc's regression suites for Chromium code |
| `Engine/ParcImport`, `Engine/ParcInternalExtension` | `//parc/importer`, `//parc/internal_extension` | Browser import service and the internal extension |

Patches live in `Engine/ParcHost/integration/`, except the extension context-menu patch, which sits
beside its Parc code in `Engine/ParcNative/`. A Parc file that must see a layer's internals, such as
a Media Source policy that touches ChunkDemuxer's locked state, is installed inside that layer, for
example `media/filters/parc_source_buffer_eviction.cc`, and the layer's BUILD file lists it. Editing
it recompiles that file and relinks; it never touches the Chromium headers around it.

## Extension points come first

With CEF gone, Parc owns Chromium's embedder classes and uses them before anything else:

- `ParcMainDelegate` chooses the content clients, sets the exact user-data root before the sandbox,
  keeps Parc's own application and strings, and registers Parc's utility services.
- `ParcContentBrowserClient` overrides the public browser-client methods it needs: HTTP authentication
  through an owned coordinator, helper paths for the CDM and Alerts helpers, per-frame interface
  binders, WebPreferences recomputation, the WebAuthn request delegate, the video picture-in-picture
  window, the web-contents view delegate and internal URLs.
- `ParcContentGpuClient` exposes the FairPlay media service. `ParcContentRendererClient` adds the
  FairPlay key systems, the ALAC answer and Parc's renderer observers. `ParcContentClient` adds the
  internal scheme and the FairPlay CDM entry.
- `ParcBrowserMainExtraParts` installs the native file-dialog factory and the licence WebUI.
- Parc's BrowserWindow, Browser record and WebContentsDelegate serve each native window, so
  JavaScript dialogs and new pages reach Parc through Chromium's own interfaces.

## The hook pattern

Where Chromium has no extension point, the Chromium `.cc` that owns the behaviour declares a function
pointer and a setter, and defines both. Site permissions are the reference example:
`permission_prompt_factory.cc` declares `parc_hooks::SetPermissionPromptFactory`, stores the factory
in a file-local pointer and, when it is set, returns Parc's result, a null "no prompt" included,
before any Chrome prompt logic runs. Unhooked Chromium keeps its original path.

[`parc/chromium_hooks.h`](../Engine/ParcChromium/chromium_hooks.h) declares every browser-side setter,
grouped by the Chromium file that defines it; the [reference](chromium-hooks.md) describes each one. Chromium files never include it; only Parc's
install points do. A signature that drifts fails at link time, never silently at runtime, and there
are no BUILD edits or buildflag includes for a hook, so upstream unit tests still link. A feature
exposes its factory in its own header, such as `CreateSitePermissionPrompt`, and the install point
passes it to the setter, so `//parc/native` targets never depend on `//parc:browser`.

### Install points

A hook is installed before the first moment Chromium can call it. The
[reference](chromium-hooks.md) names each hook's install point; these are the moments they use:

- The `ParcMainDelegate` constructor installs startup and browser hooks, before resource
  initialization and before profile services exist.
- The `ParcContentBrowserClient` constructor installs frame focus, web push and the internal extension.
- `CreateBrowserMainParts` selects the CDM helper's child flags before the UI thread forbids blocking.
- `ParcBrowserMainExtraParts::PostBrowserStart` installs the second-launch handler before Chrome's own
  PostBrowserStart lets the process singleton deliver launches; PostMainMessageLoopRun removes it.
- `ParcBrowserMainExtraParts::PreMainMessageLoopRun` installs the interface hooks before any page exists.
- The engine entry installs the FairPlay identity and AirPlay hooks before Chromium's command line
  exists, so no page or worker starts without them.

### Hooks inside component libraries and Blink

A hook defined inside a component library carries that library's export macro on its declaration,
as `service_factory.cc` does with `CONTENT_EXPORT` for `SetCdmServiceChildFlags`. The CDM creator,
the picture-in-picture session hooks and the session-restore omissions follow the same rule.

Renderer-side and content hooks use a Parc header installed inside the layer instead. Blink's player
move is declared in `parc_media_player_move.h` under `blink::parc_hooks`, keeps its slot in Parc's
`parc_media_element.cc` beside it, and is installed by `ModulesInitializer`, as Blink installs its
own module hooks. The Widevine request observer and the Safari-identity query live in the owned
`content/browser/media/parc_fairplay_hooks.h`; worker identity and AirPlay have their own owned
headers in `content/public/browser`.

## Parc state in Parc-owned objects

Parc state that used to sit in Chromium classes now lives in objects Parc owns:

- Blink supplements: the media element and AirPlay supplements on HTMLMediaElement, page media state
  on Page, and the top-band tracker and network-activity counter on LocalFrame.
- One Parc accessor per media interface. Renderer, AudioRenderer, VideoRenderer, Pipeline (with
  PipelineController), Demuxer and DemuxerStream each declare a single `GetParcExtension()`, null by
  default, and WebMediaPlayer has its own. Parc's playback, seeking, hand-off and stream calls change
  behind it without rebuilding every includer of those headers.
- One Parc state object per WebMediaPlayerImpl, its only Parc member.
- Browser-side records Parc keeps for each native Browser, page and unload controller.

## Interface routing

Every prompt keeps its source page and window checks, is cancelled on detach and navigation, and
completes exactly once. Sad tab, open-in-app requests, certificate viewing and client-certificate
selection are one-call hooks: Parc presents installed pages natively and gives any
other page Chromium's own interface. The sad tab's focus goes through Parc's view delegate.

Native page menus enter through an implementation-only hook in Chromium's Cocoa menu file, before the
Views widget lookup. Parc validates the source document, page and window, and cancels the menu on
navigation, detach or window invalidation. The extension context menu's uninstall command reaches
Parc through a hook; Parc binds consent to the asking Browser, page and extension, reserves the window
before the icon loads, and subclasses Chromium's uninstall dialog to build the same model as Views.

Folder-upload consent arrives through a hook in FileSelectHelper that hands Parc the asking frame, so
Parc can cancel when that frame navigates or goes away. The consent stays Chromium's Views dialog in
Parc's sheet. DevTools presents through hooks in the docked-tools controller: for a Browser Parc
hosts, Parc answers update, scrim and teardown, holds the docked modal host as a lease over the public
dialog manager, and routes keys and prepares new frontends through hooks, so the DevTools files no
longer include Parc.

HTTP authentication uses an owned coordinator and tab helper with a source-only validation hook.
WebAuthn request creation runs in Parc's browser client. The password sheet, tab-sharing bar and its
page-info link and profile are hooks. The autofill capability query is a free function backed by a
core-client hook, so `autofill_client.h` and `chrome_autofill_client.h` are Chromium's own. Product
names use owned numeric-ID tables in every process. The toolbar and narrow-window drawers share an
owned dark logo, so they show Parc's logo in dark mode as well as light.

## Browser and startup ownership

Chromium's Browser, window factory, window features, manager and navigator reach native Browsers
through `.cc` hooks. Admission refuses a native window before a Browser is allocated. A scoped creation
context gives exactly the next Browser its opener and the shell's one-use window reservation, and
Parc's record of each native Browser runs from the start of its constructor to the end of its
destructor, so features and the window never outlive it. `browser.h`, `browser_manager_service.h`,
`unload_controller.h` and `profile_manager.h` are Chromium's own.

Deletion drains the native host first, defers off-the-record destruction while a native operation
needs it, and runs close and transfer as transactions in Parc's unload records. Profile removal and
embedded sessions move behind final-destruction and restore-omission hooks. Startup keeps
Chromium's order: the staged content entry stays in Chromium's startup file, resource factories and
startup policy are installed before Chromium touches installer preferences, crash reporting or root
selection, and the Mac main-parts factory keeps Chromium's full extra-parts sequence. The
[engine guide](../Engine/README.md#native-construction-and-startup-source-integration) describes the
lifecycle in detail.

Navigator internal-address canonicalization is a hook at the original early point; only the URL is
replaced. Three tab-strip details are hooks too: AddTabAt's address-bar transition, the synchronous
loading-UI gate for a delegated tab that has not reached its strip, and the native color provider for
a genuinely empty Browser. Unhooked Chromium keeps all three original paths.

## Renderer state and page appearance

WebPreferences recomputation lives in Parc's browser client and page-preference records. Frame-focus
subscriptions live in an owned registry, so `web_contents_observer.h` is Chromium's own. The top-band
tracker is a LocalFrame supplement whose event hooks stay at their exact `.cc` points: frame install,
post-canvas sampling, parsing, LCP, new documents and resource loads. A lifecycle observer would run
before canvas onpaint, too early to sample. Website themes use an owned renderer observer.

## Media player boundaries

WebMediaPlayerImpl keeps every call site that drives its own state: readyState changes, seek
completion, restarts, suspend decisions and observer notifications stay in Chromium's file, in their
order. Parc's machinery lives outside it. The task runners that follow a moved element's frame and
keep a cast's pipeline running in a frozen page are in `parc_media_task_runners.h`. The rules the
player applies to its values are pure functions in `parc_web_media_player_rules`: which codecs the
FairPlay renderer plays and accepts through `changeType()`, the type AVFoundation is told for AirPlay,
and the readyState a Safari-identity Media Source's buffered ranges give.

Parc's per-player state lives in `parc_web_media_player_state`, which the player befriends. It holds
the key tracker for Safari-identity elements that wait for a key, and its callbacks still go through
the player's weak pointer, so they stop exactly when they did. The player header still declares Parc
overrides and the orchestration that changes the player's private state in place: the FairPlay
hand-off and restarts, the AirPlay route switch, document moves, casting while frozen and readyState
gates. Hidden Safari-identity video keeps its track by the player's own identity check, because a
player copies the frame's background-track option once and keeps it after Parc moves it.

HTMLMediaElement's Parc state and steps live in `parc_media_element`, a supplement the element makes
in its constructor. The element's algorithm still runs in Chromium's file, because readyState, seeks,
timeupdate scheduling, the load algorithm, document moves and the event queue are private; each
Safari-identity gate there is a one-line call into the supplement, in the same order. AirPlay's state
lives in a second supplement, and WebKit's AirPlay members reach it through core partial interfaces
with `[ImplementedAs]`, which keeps the prototype's property order. The supplement's timeupdate
throttle uses WebKit's 250 ms. Chromium's element test is its own again, apart from two empty handlers
for the messages Parc adds to the player observer.

MediaCapabilities answers Safari-identity documents as WebKit's `decodingInfo` does, with the HEVC and
Dolby Vision parsers and video rules in `parc_media_capabilities`. EME's configuration rules for
Safari's identity and FairPlay live in `parc_encrypted_media`; each initializer calls them where the
check used to run, and the small gates in MediaKeySession, MediaKeys and MediaKeySystemAccess stay in
place. Safari's script APIs are installed by `parc_safari_scripts` from LocalWindowProxy, where a
context is created or a document takes over its window, and from the worker controller.
`DidCreateScriptContext` would miss the take-over path and cannot reach Blink's trusted events.

Picture in picture: captions reach Parc's window over a navigation-associated Parc interface, so the
session interface and window class are stock. Scrubbing keeps Chromium's media-session and controller
interfaces, because the controls send it on their play and pause pipe in order. The shell's in-window
and power values ride in WebPreferences, which reach a renderer in order with its page lifecycle, and
a page supplement holds them, so `page.h` is stock.

## The FairPlay media service

FairPlay has its own GPU service, `fairplay_media_service`, and one browser host per document,
`FairPlayDocumentHost` in `//parc/native`, built from Chromium's public media service classes.
Chromium's media service, interface factories and the interface-factory, frame-interface-factory,
renderer-extension and media-service mojoms are pristine; `media_factory.cc` keeps only the calls
that add and move Parc's renderer factories. Each document's CDMs, FairPlay renderers and native HLS
players live together in that service, and a render process's documents share one CDM service
context, so CDM IDs resolve only inside that process. Each audio grant belongs to its own player, so
closing one player can't take another's speaker indicator. `MediaInterfaceProxy::CreateCdm` keeps the
Widevine hold and one CDM-creator hook, and MojoRenderer keeps its CDM swap; the
[FairPlay guide](../Engine/ParcNative/fairplay_chromium/README.md#widevine-request-hook) explains why
their order requires that.

## The FairPlay hand-off

When a Safari-identity Media Source element needs FairPlay mid-playback, playback hands off from
Chromium's renderer to the FairPlay renderer at a future video keyframe. The hand-off and the silent
reverse turn live in `parc_renderer_transitions`, owned by PipelineImpl's renderer wrapper, which keeps
one call where each step ran. Renderer choice stays upstream's pattern in `CreateRendererInternal`, and
`pipeline.h` carries only the pipeline accessor. `pipeline_impl.h` declares the extension it
implements, a backward flag on its end notification and a native-HLS flag.

The split readers live in `parc_chunk_demuxer_hand_off`: a hand-off object each stream owns, the
decorator stream the incoming renderer reads, and the demuxer's split negotiation. The split is placed
under the stream's lock as data arrives, sees a config change without taking it, and answers both
readers' seeks, aborts, disabling and shutdown in that locked step. A decorator outside the lock would
split later, could pass the playing renderer frames past the split and would add work to every read.
The hand-off, fast-seek landing and renderer preference share the one Demuxer accessor, which is all
`demuxer.h` carries. The hand-off lives only in `ParcStreamHandOff`, `ParcDemuxerHandOff` and the
pipeline helper; ChunkDemuxer has no hand-off reader of its own.

## Media Source, formats and compositing

Safari's eviction, ManagedMediaSource purge, buffered-interval math, gap tolerances and type mapping
live in owned `media/filters` files. ChunkDemuxer calls them under its existing lock and keeps every
stream lookup, range removal and parser construction primitive. Formats Chromium lacks get owned
elementary-stream parsers, an Ogg parser and VideoToolbox decoders; the format rules inside
Chromium's own parsers and the AudioToolbox decoder stay patched, because those parsers are never
forked.

The nested protected-video render-pass planner and the CALayer claim and hand-on policy live in owned
Viz and accelerated-widget files. Chromium keeps one planner call and one claim hook; candidate
construction, the rounded mask, root-pass processing and the parked-compositor flag stay at their
call sites. Renderer window planning and mixing arithmetic stay patched for now
([backlog](backlog.md#engine-architecture)).

## Parc-owned test targets

Parc's regression tests for Chromium code live in `Engine/ParcChromium/tests` and install into
`parc_tests` folders inside each layer, such as `//media/parc_tests` and
`//third_party/blink/renderer/parc_tests`, so they keep that layer's internal visibility and compiler
configs. Each target is a dependency of the original test binary, so `media_unittests`,
`blink_unittests`, `content_unittests`, `components_unittests` and `unit_tests` still run them.
`parc-owned-tests.patch` wires the browser, cast, autofill and core Blink suites; the media,
compositing, identity, cast-presentation and codec patches wire the targets beside their own edits. Suites are named with a `Parc` prefix. Upstream test files are Chromium's own except
for compatibility edits a changed interface needs. Parc files beside a layer, such as
`parc_media_element_test.cc` and `parc_chunk_demuxer_hand_off_unittest.cc`, keep their own fixtures.

## Kept patches and why

Every patch the overlay still carries, what it changes, the files it touches and why it must stay a
patch are listed by area in the [hooks and patches reference](chromium-hooks.md#the-areas). The
decisions below explain the patches kept on purpose.

## Decisions

- **AMR and H.263:** they keep playing only on Safari-identity pages, so that small patch stays.
- **Autofill capability patch:** it stays. Parc presents almost every gated offer natively using the
  patch's presentation results and request state; otherwise a refused sheet would count as ignored and
  collect strikes.
- **Extension install:** it stays. Show-time hooks see the page only once the prompt is ready, but
  Parc binds consent to the asking document and Browser when the prompt is created.
- **App-modal JavaScript dialogs, intent picker and context-menu observer:** these keep patches until a lossless
  hook exists; the public routes run too late or lose the source page.
- **Parc-owned media player:** rejected. Chromium picks the player once, from the URL, before any CDM
  exists, so a separate player would mean forking WebMediaPlayerImpl.
- **Upstream candidates:** the macOS system screen-picker fix, mp2t multi-audio, ipcm and fpcm in MP4,
  pipelined MojoAudioDecoder decodes, the global-media-controls reentrancy fix and FFmpeg's ADTS
  parameters are better sent to Chromium and WebRTC than carried forever.

## Risks every change must guard

Media:
- the order of media events on Safari-identity elements, and the clock during the hand-off;
- FairPlay and HLS players never being suspended; audio grants and mute; CDM lifetime;
- persistent usage records never in private windows;
- one superlayer per CALayer, the parked-compositor flag, PiP layer ownership and `preventsCapture`;
- the hot paths: the ChunkDemuxer lock, the video renderer lock and the audio render callback;
- the Widevine hold, where held callbacks never run and are destroyed after their pipes;
- reconnecting after a GPU crash, and one CDM service context per render process;
- the worker decoding route, the black capture fallback, nested passes and copy requests;
- compositor features, rechecked at every Chromium upgrade.

Browser: refuse a window before a Browser exists, drain the native host before deletion, defer
off-the-record operations, roll back a transfer when its last tab fails, and keep profile removal
crash-safe.

Interface: keep each prompt's source page and window checks, cancel on detach and navigation, and
complete exactly once.

## Adding a hook

1. Look for an extension point first: a content-client or main-delegate override, an extra-parts
   callback, a BrowserWindow or WebContentsDelegate method, a Blink supplement or a public observer.
   Check that it runs at the same moment and with the same context as the code it replaces.
2. Otherwise, in the Chromium `.cc` that owns the behaviour, declare the setter in `namespace
   parc_hooks`, keep the pointer file-local and call it at exactly the original point. Return early
   only with a value Chromium would accept, and leave the unhooked path unchanged. Add the library's
   export macro if the file is in a component library.
3. Declare the setter in `parc/chromium_hooks.h`, beside the setters for the same Chromium file. Renderer and media
   hooks use a Parc header installed in their layer instead.
4. Put the logic in a Parc-owned file and install the hook at the earliest point Chromium can call it.
5. Move the Parc tests into the layer's `parc_tests` target, and make the unhooked upstream test pass
   unchanged.
6. Update `overlay.json` under the [overlay rules](../AGENTS.md#engine-and-release-operations) and
   update the area's guide in place.
7. In the same change, add, change, move or remove the hook's and patch's entries and counts in the
   [hooks and patches reference](chromium-hooks.md); reviewers treat a missing update as blocking.

A new hook or any other Chromium change first needs the user's approval, with the alternatives tried and
why each fails ([Chromium boundary](../AGENTS.md#chromium-boundary)).

## Builds and upgrades

Both engine recipes can use a shared compile cache on a trusted builder, with remote execution off and
every miss compiled locally ([cache setup](../tests/EngineSource/README.md#shared-compile-cache)).
`scripts/engine-overlay-export.py` exports a committed Chromium branch to a candidate manifest and
proves byte-for-byte equivalence with the current one
([export](../tests/EngineSource/README.md#branch-export-and-equivalence)); the release pipeline still
materializes pinned Chromium plus the overlay once. The step-by-step procedure for minor and major
Chromium bumps is in [Upgrading Chromium](../Engine/README.md#upgrading-chromium). Carrying the changes
as a branch, the next Chromium upgrade and other open engine work are in the
[backlog](backlog.md#engine-architecture).

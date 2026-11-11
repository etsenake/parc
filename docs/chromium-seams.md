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
   - 2c: the widely included Blink and base headers listed above.

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

## Decisions

- **AMR and H.263 files:** decided. They keep playing only on Safari-identity pages, exactly as they do today, so that small patch stays.
- **Autofill capability patch:** whether it's deleted depends on the per-feature audit in step 4.
- **STAY patches:** a few are better sent upstream to Chromium and WebRTC than carried forever. The
  candidates are the macOS system screen-picker fix, mp2t multi-audio, ipcm/fpcm in MP4, pipelined
  MojoAudioDecoder decodes, the global-media-controls reentrancy fix, and FFmpeg's ADTS parameters.

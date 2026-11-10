# Independent Chromium engine



## Build configuration

Use a native Apple Silicon Mac, usable Xcode and a writable APFS workspace. `check` and `plan` report the selected path, storage policy and commands without creating the checkout; `sync` and `build` perform the requested work. Read the tool's help and refusal messages before retrying an interrupted operation. It never resets, cleans or deletes an existing source tree.

```sh
python3 scripts/engine-source.py plan --workspace "$PWD/work/engine"
python3 scripts/engine-source.py check --workspace "$PWD/work/engine"
python3 scripts/engine-source.py sync --workspace "$PWD/work/engine"
python3 scripts/engine-source.py build --workspace "$PWD/work/engine"
```


The example volume must already exist; choose a dedicated actual location. The tool requires Python 3.11+ and defaults to four build jobs. The selected configuration is ARM64 Release with component libraries, DCHECKs and the field-trial testing config off, proprietary codecs decoded and encoded by macOS rather than bundled FFmpeg/OpenH264 code ([codec route](../docs/engine-flags.md#macos-codec-route)), platform Dolby Vision (encrypted only, for FairPlay) and AC-3/E-AC-3 decoding ([FairPlay codecs](ParcNative/fairplay_chromium/README.md#codec-build-flags-increment-3)), the Hangouts services extension, no dSYM bundles and `symbol_level=0`. `--symbol-level 1` retains minimal symbols when selected consistently for that workspace. Component builds support local integration development; release packaging and performance verification require their own configuration and checks.


Both configurations also set `disable_fieldtrial_testing_config=true`, which pinned CEF's `tools/gn_args.py` adds for official builds. Its only consumer, `components/variations/service/BUILD.gn`, generates `FIELDTRIAL_TESTING_ENABLED=0`; that removes the startup path which applies `testing/variations/fieldtrial_testing_config.json` (on macOS it would enable, among others, `AperitifHelpers`, `HistoryEmbeddings`, `GlicActorUi`, `TabHoverCardImages`, `AutofillEnableWalletReminderNotice` and `AutofillEnableResurrectingPaymentsUsers`), leaving ordinary feature defaults. The production `--disable-field-trial-config` switch already skipped it for default launches; an explicit `--enable-field-trial-config` now ends startup with Chromium's excluded-config message, and individual features still follow `--enable-features`. `scripts/build.py` refuses to package an engine whose `args.gn` lacks either setting or whose generated `gen/components/variations/service/buildflags.h` still enables the testing config.

Receipts bind the source lock's digest, so a changed `build.gn_defines` refuses the existing workspace until it is reconfigured with the lock it was built from. `reconfigure` refuses any other lock difference, verifies the unchanged sources against that previous lock and returns the receipt to `synced` without touching sources or objects; the next `build` regenerates and compiles. An existing shipping output receives its new `args.gn` and a `reconfigured` receipt that cannot be sealed until `shipping-build` completes.

```sh
git show <commit-before-the-change>:Engine/source-lock.json > "$PWD/work/previous-source-lock.json"
python3 scripts/engine-source.py reconfigure --workspace /absolute/engine-source \
  --previous-lock "$PWD/work/previous-source-lock.json"
python3 scripts/engine-source.py build --workspace /absolute/engine-source --jobs 8
```

CEF's Apple Silicon quickstart recommends a component build and runs its generated app in the build-output directory. The framework's component RPATH in `cef/BUILD.gn` reaches the sibling libraries there. Parc now publishes a fresh development directory containing `Parc.app` beside those component libraries, preserving the engine's dependency names and search paths; copied images are signed normally. Packages through v59 pass strict app/sibling signing and provenance checks, and actual independent browsing runs in this layout. The earlier relocatable package rewrote load commands and corrupted nine sectionless libraries; its temporary header workaround is historical and has been removed from the packager. Shipping configuration remains a separate gate below.


After normal CEF source generation and applying the current reviewed overlay:

```sh
python3 scripts/engine-source.py shipping-plan --workspace /absolute/engine-source
python3 scripts/engine-source.py shipping-generate --workspace /absolute/engine-source
python3 scripts/engine-source.py shipping-build --workspace /absolute/engine-source
```

`shipping-plan` is read-only. `shipping-generate` writes the isolated arguments and runs normal `gn gen`, without compiling Chromium; `shipping-build` generates and incrementally builds `cef_framework`. All use the same workspace operation lock. The shipping receipt binds successful compilation to the exact source lock, overlay, source fingerprint and GN arguments. A generated-only, failed, stale or interrupted build cannot be sealed as a completed shipping engine. Returned failures can resume; unowned existing output is preserved and refused. Neither the development receipt nor its arguments are rewritten.

The shipping recipe and output require their own disk capacity; the build reserve is a conservative preflight threshold, not a guarantee that a second output fits. No clean or duplicate source checkout is performed. See [packaging](../tests/Packaging/README.md#standalone-distribution) for the standalone app and signing path. A release Swift build or certificate cannot convert component artifacts into a distribution. [CEF development workflow](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/docs/master_build_quick_start.md), [CEF distribution configuration](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/tools/gn_args.py).


The storage thresholds are conservative policy, not a measured requirement for this configuration. Upstream documents 150 GB free for its Debug workflow. Debug symbols can be disabled, but that does not establish an exact lower workspace size. Measure checkout and output growth during the actual build. Keep the checkout, tool caches, generated outputs and packaged app under ignored `work/` and `build/` in this repository (never commit them). [CEF build guide](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/docs/master_build_quick_start.md#mac-os-x-setup), [Chromium build options](https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/docs/mac_build_instructions.md#faster-builds).

## Required native integration


Keep real Chromium `Profile`, `BrowserWindowInterface`/`Browser`, tab-model and `WebContents` identities behind Parc's native shell. Extension services, permissions, commands, navigation and lifecycle operations must use the same objects that own the visible pages. Source-owned Objective-C++ code should bridge these to Swift/AppKit with explicit ownership, callbacks and main-thread rules.

Stock macOS CEF native-parent embedding selects Alloy, which lacks parts of the owning Chrome browser/window machinery. Stock Chrome-style CEF also allows only one Chrome BrowserView per Views window. These constraints must be solved in source; changing a runtime enum or reloading a URL in a second view is not an implementation of tab ownership. [Native-parent constraint](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/include/internal/cef_types_mac.h), [Chrome host creation](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/chrome/chrome_browser_host_impl.cc), [BrowserView association](https://github.com/chromiumembedded/cef/blob/4fa4ab516dacf6c49fc7e6e70d2b7ebce29fa35f/libcef/browser/views/browser_view_impl.cc).



- Browser contexts own profile services, including extensions, preferences, history and downloads. Browser instances also carry independent native-window association.
- `takeOwnershipOfWebContents:` at `0x68b6918`, forwarding to `0x685ebe0`, rejects cross-profile transfer before mutation. It detaches the existing tab object, appends that same object to the destination, and activates it only when the destination was empty. The destination's existing selection otherwise survives. Delegates and observers are rebound around that transfer.
- Browser and page popup callbacks wrap incoming native contents. They do not reconstruct the page by loading a URL. Preserve the actual contents, pending navigation, POST body and opener relationship. The global ordering between those callback channels is not yet established.
- Extension action execution is browser/window-associated; action metadata and popup open/resize/close arrive through native callbacks. A toolbar button pointing to an extension URL does not reproduce this mechanism.

These are recovered contracts, not original source. Native view reparenting/focus/occlusion and remaining popup/permission policies still need bounded REA and runtime checks. Continue that investigation while implementing the independent source bridge.


Earlier project generation with the native component overlay succeeded. The older baseline subsequently stopped at the native-window test link after passing the harness compiler correction; v49 normal generation now succeeds with 36,720 targets from 5,045 files and all 117 CEF patches accepted. Sixteen scoped GN header checks pass across 34 explicit targets; 51 checked source/object-owner pairs resolve correctly. Actual-target compiler checks continue, and complete framework/test linking remains pending. The native save-session, regression-test and upstream Autofill UI targets pass GN header-dependency checks. All eight native source/test units and all 29 changed upstream Autofill translation units pass the pinned compiler with actual generated target settings and real generated headers. The earlier baseline generation accepted all 117 CEF patches; v48 separately verifies the updated patch definitions before regeneration. These are syntax and dependency checks, not linked Chromium test execution.

The autofill integration distinguishes supported local new-card/address prompts from unsupported presentation families at real producer and controller entry points. Actual presentation is observed asynchronously; refusal completes neutrally and does not add strikes, store data, acknowledge a shown prompt or mutate mandatory-reauth preferences. Reentry protection covers queued controller replacement, page visibility, view generations and destruction during callbacks. A separate generated Parc product flag excludes Autofill AI and AtMemory initialization and direct UI dispatch before Browser lookup, independently of native capabilities. Engine-wide AI exclusion verification remains open. Focus, dialogs, Find and save sheets pass executed AppKit suites (83, 82, 79 and 75 assertions respectively), with 33 additional deferred-presentation checks. Genuine Chromium cases now include seven save-session cases, eleven capability cases parameterized over BubbleManager state, six manager cases, five queue cases and two product-policy cases, plus existing wallet-controller regressions. These are registered in real targets but have not been linked or executed. Review the [autofill verification boundary](../tests/NativeAutofillSave/README.md) before treating them as integrated behavior.

The native extension popup presenter passes 57 AppKit assertions across seven groups, including visible-parent preparation, geometry, close/reentry and replacement during detachment. Actual action models preserve upstream grants and shortcut semantics; the session owns the supplied ExtensionViewHost and defers destruction out of active engine/native event callbacks. Four genuine-host tests are registered in `chrome/test:browser_tests`; their source target declares Chromium's required out-of-process test-runner contract. The three production units and four-case browser-test source pass their actual generated target compiler checks; linking/execution and production factory/menu/security-state wiring remain pending. See [native extension boundaries](../tests/NativeExtensionPopup/README.md).

Native extension context menus share `native_extensions` and use the real action model with `MenuControllerCocoa`/`NSMenu`. The model remains protected through a synchronous pin callback, cancellation and presenter replacement. A narrow upstream patch guards only optional Views pin feedback. Ten genuine browser cases cover tracking, dispatch, invalidation and reentry. Production/test compiler checks and GN header-dependency checks pass with their actual targets; the patched full upstream menu model also compiles. Linked test execution remains pending. Native uninstall is integrated at source and target level; the v26 side-panel service and v27 host routing extend this source path, while linked execution and real shell toolbar/menu behavior remain unverified. See [context-menu boundaries](../tests/NativeExtensionContextMenu/README.md).

Native extension uninstall now uses Chromium's real command helper, controller and DialogModel with the source-owned AppKit sheet. The Browser adapter registers its exact owner-bound service; page detach and Browser shutdown cancel pending consent. A weak native-window reservation coordinates popup/menu/security suppression, including Chromium security registration before Show. The v22 overlay applies and generates successfully; all 117 retained CEF patches take their normal already-applied path. All eight native/test units and three modified upstream translation units pass actual-target compiler checks. The native component, extension service and uninstall browser-test targets pass header-dependency checks. The broader upstream extensions target reports two unchanged pinned-CEF include-boundary errors; the suggested dependency would create a cycle and was not added. The sheet passes 45 AppKit assertions across nine groups. Twelve real-controller browser cases are registered but not linked or executed. See [uninstall ownership, checks and remaining gates](../tests/NativeExtensionUninstall/README.md).

The generic window lookup now returns the actual tab owner's BrowserWindow, including native windows without a BrowserView. A connected address-save continuation checks the real Views capability before attempting its optional desktop promotion. Four real regression cases compile and are registered in the existing macOS `chrome/test:unit_tests` target. Both modified full upstream translation units now pass their actual target compiler checks with generated headers present; linked tests, native save-controller lifecycle and saved-data persistence remain pending. See [window lookup checks](../tests/NativeWindowLookup/README.md). The full native AutofillBubbleHandler is implemented, but production registration and actual native factory/shell routing remain pending; these component factories are not full browser autofill.

The native Window returns the empty status-bubble list expressly permitted by Chromium. Current upstream consumers statically cast entries to Views classes; an AppKit bubble would be unsafe there. The original page's hovered-link/status presentation still needs its own native route. Compatibility hooks do not require recreating every Chrome bubble, but must preserve actual callback results and lifetimes.


## Native construction and startup source integration

The v27 factory path uses `native_host_route` to associate a real Profile with an application-owned client and a one-use native-window reservation. It validates the reservation before constructing Browser, supplies the actual native BrowserWindow/platform delegate, and registers the host after BrowserManager ownership exists. Popup creation carries the existing page and original navigation/opener state. The route refuses unsupported managed-profile or unregistered private-profile construction before allocating a stock window. These refusals remain functionality gaps; they do not establish profile or popup parity.

`native_appkit_host` binds the supplied NSWindow to separate real Browser/Profile instances, registers Find/autofill/extension action/menu/side-panel services and retains their ownership through asynchronous teardown. Menu cancellation waits for native tracking to unwind; action and side-panel hosts drain before Browser/Profile destruction. Window and app close collect genuine beforeunload decisions before triggering their own unloads. Native fullscreen and lock controls use real controller callbacks and origin/exit presentation. `native_appkit_page` exposes the same actual WebContents and reports real close, metadata and archive-protection state. Physical-window transfer, DevTools/document-PiP creation and several native presenter families remain incomplete.

`native_engine_entry` supplies a small exported C ABI for helper dispatch, browser initialization, the Chromium-owned main loop and idle shutdown. Initialization distinguishes ready, normal early exit (including process-singleton notification) and failure, preserving the engine exit code. Shutdown waits for pending native creation, real Browser ownership and CEF page hosts to drain; it does not fabricate close approval. The matching Swift/facade candidate implements the actual CEF AppKit event protocol and an asynchronous `terminate:` override, because returning `NSTerminateLater` before the CEF loop returns can deadlock the pinned runtime. This is an explicit current-CEF adaptation; singleton receiving-process routing and integrated quit/startup tests remain pending.

Actual-target checks pass for the host/page/exclusive-access source, the route/entry source and thirteen complete modified upstream translation units, using generated headers and isolated VFS inputs. The full candidate Swift shell and Objective-C facade also pass compiler checks; their production promotion is pending. The native retirement model executes 420 assertions and the per-window presentation/ownership model executes 35. The 47 bootstrap checks and v27 source/target hash replay pass. These results do not establish linked runtime correctness. Keep the v22 full build running until it completes or reports an actual failure; then apply the reviewed later source and regenerate/build incrementally.

The v28 increment connects exact subset-page retirement to the real UnloadController. It reserves every target before prompting, asks groups sharing a physical window sequentially, requires the model's synchronous final validator, rechecks actual page/document/Browser identities after callback reentry, and only then schedules unload. Native completion follows real WebContents destruction. Late replies remain page/token-bound across transfers; navigation and renderer loss retire them neutrally. Whole-window/app closing refuses overlapping subset ownership before queueing callbacks. Six actual-target compiler checks include nineteen real controller/coordinator cases; linking and execution are pending. The Swift batch consumer typechecks with the current model, including fresh all-window archive protection and reconciliation of independently destroyed pages. Version 28 read-only replay validates 87 mapped files and 94 patched targets without changing the running v22 checkout. See [retirement checks](../tests/NativePageRetirement/README.md).

## Native relaunch and independent encrypted storage

The v29–31 source increment consumes Chromium singleton relaunches through the required native application client, including during shutdown. It copies the command and sender directory before the callback returns. The prepared Swift consumer routes only destinations through registered Parc windows; it does not apply second-process engine/profile settings. The executable parser suite passes 22 assertions. Parc-valued switches are normalized before Chromium reorders them, and the normalized null-terminated argv storage stays alive through CefShutdown. The combined relaunch/retirement application and startup units pass pinned-target compiler checks; the Swift consumer remains a candidate pending production integration.


## Typed native site permissions

Version 32 connects the actual manager-owned Chromium permission prompt to Parc's native page platform delegate. The adapter preserves typed geolocation options, one-time grants and genuine Accept/Deny/Dismiss/Ignore decisions. It binds origin, requesting documents, Profile, Browser, page view and exact window; hiding, navigation, detachment or closure cancel stale presentation. The shared native security reservation is released and ownership checked again before a decision. Camera/microphone stay on the normal Chromium media policy and OS authorization path; other CEF platform delegates retain their previous behavior.


## Native extension installation consent


The presenter executes 42 AppKit assertions. Six combined compiler checks pass, including thirteen genuine prompt cases; linked execution is pending. Read-only replay validates 99 mapped files and 98 patched targets, preserving earlier source increments and the uninterrupted v22 build. No actual Web Store installation, grant persistence or extension compatibility is claimed. See [installation reference and verification](../tests/NativeExtensionInstall/README.md).

## Same-profile live page transfer

Version 36 transfers the actual TabModel/WebContents between real same-profile Browsers. Original ownership is restored if destination attachment fails; failed restoration reports interruption. Exact native owner lookup and the prepared Swift consumer keep uncertain claims/container ownership reserved until genuine attachment or page closure. Empty-source retirement is deferred until the result callback returns; preexisting empty destinations are preserved on failure.

Five combined compiler checks pass, including twenty-two genuine controller cases that remain unlinked/unexecuted. The ownership/presentation model executes 57 assertions. Read-only replay covers 103 mapped files and 98 patched targets; v22 remains running unchanged. Production Swift promotion, renderer/extension continuity, focus and actual two-window reparenting remain pending. See [transfer reference and checks](../tests/NativeTabTransfer/README.md).

## Profile downloads and native file selection

Version 37 observes the actual Profile DownloadManager, publishes copied GUID-scoped values after observer frames unwind, and resolves pause/resume/cancel in that same manager. It preserves Chromium target determination, filename and safety policy. The actual macOS SelectFileDialog stays bound to its requesting page/Browser/window; source loss, navigation or competing security ownership cancels once. Native callbacks and platform-runner retirement remain deferred through nested event loops. The old independent page-only download delivery is removed.


## Native HTTP and proxy authentication

Version 38 installs a native LoginHandler factory on the exact WebContents while retaining Chrome's HttpAuthCoordinator, enterprise and extension interception, LoginTabHelper, HttpAuthManager and original network continuation. The real WebContentsModalDialogManager owns renderer blocking and modal accounting. The AppKit presenter binds document, Browser, Profile, page and window; native detach closes its attachment gate before cancellation, preserving the existing download/file-dialog and other prompt teardown paths. Credentials are revalidated after native modal and security-reservation release, including when inherited from another matching handler.


The regression launcher is a separate integration gate: with ENABLE_CEF, Browser creation reaches CefContext, but ordinary ChromeUnitTestSuite does not initialize it and creates its own per-case TestingBrowserProcess. BrowserWithTestWindowTest also owns task/profile test environments. Ordinary InProcessBrowserTest startup assumes Chrome startup paths disabled by ENABLE_CEF. Version 42 adds a focused native runner using production startup and actual native Browser/page construction instead. Its three synthetic HTTP-auth cases retain the real LoginHandler, native sheet controls, modal manager and continuation; shutdown goes through real all-window close and CEF idle shutdown. This does not adapt or execute the existing Chrome fixtures.

The runtime driver passes an isolated compatibility compiler check; the external
AppKit main links with the actual packaging flags and has only system-library
dependencies. Two fresh-profile/result guard tests execute. Read-only composition
validates 131 mapped files and 113 patched targets. Normal generation, framework
linking/exports, canonical independent packager/helper promotion and the three
controller cases remain pending. No runtime result or real 401/407 behavior is
claimed. See [native runtime procedure](../tests/NativeRuntime/README.md).

## Native client certificates

Version 40 preserves the actual Chromium certificate selector/table, details,
policy-filtered identities, SSL authentication observer and native private-key
acquisition. CEF's generic callback defers without consuming its continuation,
so enterprise filtering and automatic selection precede the page-owned factory.
widget adapter connects that real selector to the supplied AppKit parent and
actual page-modal manager, without a surrogate browser window.

Document/window/attachment and sole-reservation validation run before acquisition,
before late-key broadcast and before deferred network continuation. Real widget
destruction and pending key acquisition retain separate lifetimes. Each platform
cancellation hook preserves its weak-self boundary. Six integrated isolated
compiler checks pass, including fourteen real selector cases that remain
unlinked/unexecuted. Read-only v40 replay covers 122 mapped files and 109 patched
targets. Actual target checks, TLS/OS authorization, focus/modality/details and
[client-certificate evidence and checks](../tests/NativeClientCertificates/README.md).

## Native external protocols

Version 43 presents the original policy-checked request in a native page-owned
sheet, following REA's pending-request replacement and accept/remember/cancel
contract. Chrome retains default-application lookup, scheme/enterprise/gesture
policy, remembered origin/scheme preferences and actual platform launch. Exact
document, Browser/Profile, native window and attachment generation guard deferred
consent; detaching invalidates an already queued acceptance before cancellation.
Preference-observer reentry is checked again before launching.

The native sheet uses the real activation protector and actual PiP occlusion
tracker without a surrogate browser widget. Thirty-five AppKit assertions and
seven combined isolated compiler checks pass, including seventeen genuine
controller/protection cases that remain unlinked/unexecuted. Read-only replay
covers 138 mapped files and 117 patched targets. Actual target generation/linking,
real external navigation/OS launch and interaction parity remain open. The
current CEF path refuses browser-initiated requests without a valid initiating
document; this is an included-functionality gap. See
[external-protocol evidence and checks](../tests/NativeExternalProtocol/README.md).

## Native WebAuthn

Version 44 retains Chromium's genuine request scheduler, request delegate, model,
creates the Views controller and exposes its auxiliary NSWindow; this adapter
replaces the current Views browser-parent assumption with the exact native page
window and real WebContents modal manager. Request/document/Profile/Browser and
attachment checks reject stale owners. A host change latches cancellation
immediately and removes the modal outside the manager's list iteration; explicit
CloseAllDialogs still removes synchronously as the real manager requires.

Seven combined compatibility compiler checks pass, including eleven genuine
request/controller cases that remain unlinked/unexecuted. Read-only overlay
replay covers 143 mapped files and 123 patched targets. The production/test
source targets are registered; newly generated target/header validation, linking
and actual OS credential behavior remain pending. Conditional/autofill/ambient UI,
standalone WINDOW steps and non-request settings models remain gaps. Exact
focus, modality, accessibility, device/iframe behavior and visual/motion parity
require runtime verification. See [WebAuthn evidence and checks](../tests/NativeWebAuthn/README.md).

## Native DevTools

Version 41 supplies native presentation for the actual DevToolsWindow and its
unchanged main/toolbox WebContents. A typed native delegate preserves the original
controller, resizing strategy, policy and close behavior. Each inspected-page
binding hosts the real views, keeps Find/status in the inspected rectangle, and
tracks its exact external shell container for transfer. Scoped modal bindings
follow the actual destination Browser; generation checks prevent stale leases
from clearing a newer owner. View hierarchy checks prevent old panes from hiding
or resizing views adopted elsewhere. Undocked tools retain their real auxiliary
Browser delegate for keyboard dispatch.

Forty AppKit assertions execute. Thirteen combined isolated compiler checks pass,
including six genuine DevTools cases and eleven chooser cases that remain
unlinked/unexecuted. The optional tab lookup safely cancels non-tab choosers
instead of crashing. Read-only replay covers 128 mapped files and 113 patched
targets. Actual generation/dependency/link checks, the Swift auxiliary window's
production promotion, frontend loading, docking, transfer, focus and close still
need integrated runtime verification. Docked tools have no normal TabInterface;
their CEF focus/coordinates, JavaScript and page-bound permission/file/auth
services require a separate exact auxiliary binding. The normal page guards
remain intact. See [DevTools evidence and checks](../tests/NativeDevTools/README.md).

Version 45 adds exact auxiliary ownership for the docked main frontend. The
lease follows the actual inspected tab/Browser/Profile, DevToolsWindow and native
view containment, with irreversible revocation before reentry. The real AppModal
manager/queue/controller retains suppression and result delivery; a captured
validator rechecks the owner after advancing the queue. File, permission, HTTP
auth and client-certificate services share the lease. HTTP host cancellation
latches before deferred modal-list removal, and old pane cleanup preserves a
replacement frontend. The acyclic shared targets and strict actual-owner checker
are registered. Sixteen combined compatibility checks pass; twelve new genuine
auxiliary cases and thirteen HTTP-auth cases remain unlinked/unexecuted. Replay
covers 148 mapped and 127 patched targets. New target generation/header checks,
real Swift/CEF execution, toolbox services and visual/motion parity remain open.
See [auxiliary ownership checks](../tests/NativeDevTools/Auxiliary.md).

Overlay 321 turns web push back on. CEF's `components_gcm_disable` patch
(CEF issue 4078) makes `GCMClientImpl::Start` return at once and every
`Register` fail, to silence Google's DEPRECATED_ENDPOINT answer to legacy
sender-ID registrations. That also stopped GCM from ever loading or checking
in, so `pushManager.subscribe()` waited forever for its Instance ID token and
Slack, Gmail, Calendar and Discord could not notify a closed tab.
`integration/native-web-push.patch` restores upstream `Start` and refuses only
legacy `GCMRegistrationInfo` registrations, letting Instance ID (FCM) tokens
through. It also drops the entry from CEF's `patch/patch.cfg`, because CEF's
`patcher.py` runs again during generation and would otherwise re-apply the
patch over the restored file (it skips only patches that reverse-apply
cleanly). Not yet built or run; the check is a site's push subscription
resolving and `chrome://gcm-internals` reaching READY after a check-in.

Overlay 319 checks that macOS lets Parc show notifications once a site may
send them. Chromium checks the system permission only for installed web apps,
so a browser whose notifications are off in System Settings dropped every
banner silently. When Allow answers a notification prompt,
`site_permissions.mm` reads `UNUserNotificationCenter`'s authorization: not yet
Notifications Permission", "Open System Preferences" / "Never Mind", from
`notificationPermissionRequestsEnabled` (the profile's default notification
setting, Ask or Block) has no visible control in 1.122 or 1.170, so Parc adds
none. Not yet built or run.

Overlay 327 corrects the Keychain namespace on direct internal CEF startup.
CEF's runtime API version was unset, so its guarded settings assignment skipped
the Parc names. The native entry now sets the shared OSCrypt names before any
Profile starts. Existing encrypted data keeps its exact key through a normal
authorized copy into a separate Parc Safe Storage account; prior keys and
ciphertext remain intact. The namespace marker contains no secret. See the
[migration contract and inert checks](../tests/KeychainNamespace/README.md).
The official shipping engine built three incremental actions in 2m23.54s and
sealed from `ba53bf63`, preserving objects/caches. App source `cd78e23e` produced
the Developer ID app and DMG in `v1.0.0`; both have accepted Apple notarization
and validated stapled tickets. The app was immediately installed and opened.
The observer recorded a crash while Josh was deliberately testing a separate
behavior; Josh clarified that normal startup and use worked. That interrupted
observation does not establish a startup failure. His confirmation is recorded
separately for release acceptance without rewriting the raw observer result.
Josh assigned the specific behavior crash elsewhere and stopped investigation
here; another app build waits for his ready signal. The migration marker was
observed, but encrypted restart is not claimed.

Overlay 326 stops quitting from crashing while a Profile is still loading.
Settings asks for the selected Profile's search and download preferences as
soon as it opens, which starts loading that Profile; quitting before it
finished let the engine shut down with its callbacks still waiting, tripping
the waiters CHECK in PrepareNativeApplicationShutdown (three crash traps in
seven quick quits). The idle test now counts loading Profiles, a finished
load re-checks a pending quit, and no new Profile starts loading once quit is
approved. The official shipping engine and Apple-signed release app built and
published on November 5 as `app-20261106T015401Z-2193db9c`. The installed app
passed a bounded 90-second startup check; the Profile-loading quit scenario
was not exercised in that check.

The same unchanged sealed engine was reused for the first Developer ID
Application distribution package, `app-20261106T023749Z-e38d702a`. Apple accepted
its notarization with no issues; the stapled ticket and Gatekeeper assessment
passed before publication and installation. All 12 installed code images match
the published package and Team `94HKA7L2DR`; a fresh 90.06-second launch produced
no new app/helper crash reports. Production publication now requires this signing
and notarization path; see [packaging](../tests/Packaging/README.md#publishing-app-builds).
This does not verify the Profile-loading quit scenario or encrypted restart.

Overlay 325 stops a page opened from another app staying white. Since
overlay 312 a covered window marks its pages occluded after a second; a link
from another app attaches its new page to that window and activates Parc,
but activation only re-ran the visibility pass, so the page started occluded
(no paint, background priority) until macOS sent the window's occlusion
change after its next draw. The host now re-checks occlusion on activation,
deactivation and gaining or losing key, and treats the active app's key window as in
front. A window covered by other apps or behind another Parc window still
goes occluded, as 312 intends. Not yet built or run.

Overlay 317 asks "Confirm Form Resubmission" on the page's own alert sheet.
Reloading after a form POST used to open Chrome's Views tab-modal dialog,
unstyled. Chrome's `BrowserWebContentsDelegate::ShowRepostFormWarningDialog`
now hands a Parc page to `parc::ShowNativeRepostFormWarning`
(`native_repost_form_warning_api`), which shows Chromium's title and message on
Escape, a refused sheet, a new load or the page leaving its window (the
platform delegate's `PageHostWillDetach`) cancel it, as
`RepostFormWarningController` does; a second warning lets the open sheet
answer for Chromium's one pending reload. A page without a native view keeps
Chrome's dialog. The patch applies to the pinned originals with its recorded
digests. Not yet built or run.

Overlay 311 removes a two-second wait from every dockable DevTools open,
docked or undocked, first or later. CEF's renderer asks the browser synchronously which
CefBrowser owns each new page (`GetNewBrowserInfo`) and blocks its main thread
until the answer. A docked frontend never has a CefBrowser, and an undocked one
gets its CefBrowser only after the frontend loads, so the answer came only from
CEF's two-second timeout (`PARC_POPUP_TIMEOUT ... view_type=12` in smoke logs).
Traces showed a 2.01–2.03 s long task on the frontend's main thread right after
commit. Overlay 309's immediate excluded-view answer for browserless extension
hosts now also covers `ViewType::kDeveloperTools`; a frontend whose CefBrowser
already exists still gets it. Not yet built or run.

Overlay 279 fixes a renderer abort when leaving DevTools device emulation:
after mobile view, switching back to desktop killed the page with SIGABRT
(Sad Tab error code 6) and closed DevTools. Mobile emulation forces Blink's
mobile overlay scrollbar theme, whose fade Blink drives with
`ScrollableArea`'s fade timer. Turning emulation off switches the page to
`ScrollbarThemeMac`, whose animator owns overlay visibility, without stopping a
pending timer. The timer then fails `SetScrollbarsHiddenIfOverlay`'s
`BlinkControlsOverlayVisibility()` DCHECK. Before the `dcheck_always_on=false`
source-lock change, both of Parc's non-official recipes kept Chromium's default
DCHECKs, which made that check fatal; official Chrome builds compile it out, and
compile it out too. `blink-overlay-scrollbar-fade.patch` keeps that check out of
the timer once the theme no longer lets Blink control visibility, as upstream
already does in `ScrollingCoordinator::DidChangeScrollbarsHidden`. The pending
fade still hides the scrollbar, because the Mac animator starts hidden and
reports only transitions; otherwise an invisible scrollbar would keep taking
hit tests until the next scroll. Blink-controlled themes still fade. The fix
and a new `scrollable_area_test.cc` case pass actual-target syntax checks;
`blink_unittests` was not linked or run.

## Native server-certificate inspection

Version 46 connects generic certificate details to the actual SFCertificatePanel
WebContents/document/visible-entry/certificate and native-window checks own the
request. Native detach retires its generation before cancellation; the actual OS
modal delegate remains alive through dismissal, including cancellation while the
OS begin call is still active. A returned old begin frame preserves a newer sheet.
Chromium retains SSL warning, trust and network decisions, and client-auth Details
keeps its existing route. The shared source target owns SecurityInterface linking.

Thirty-four real OS-panel assertions pass. Five combined compiler checks pass,
including thirteen genuine controller cases awaiting link/execution. Read-only
replay covers 155 mapped files and 129 patched targets. Actual target generation,
TLS warning/details/back/proceed/policy flows, native page-info entry, background/
[certificate details evidence and checks](../tests/NativeCertificateViewer/README.md).

## Page compositing across tab switches

Shown pages, docked DevTools included, draw through compositors their window
page replacing another in its pane takes the compositor that page left, so a
tab switch shows the pane's last frame until the new page's own, not the white
pane backing a fresh compositor showed; another pane's frame is cleared first.
Chromium stops a renderer view drawing by itself once it has drawn through
one, so every path that shows a page attaches it first, and every compositor
is destroyed before `CefShutdown`. See
[page compositing](../docs/page-compositing.md); not yet built or run.

## Product name

Chromium's string resources call the browser Chromium in about 620 English
strings across six bundles, and in each translation. Grit names Parc instead
as it emits each message (`integration/parc_branding.py`, hooked into
`MessageNode.Translate` by `integration/product-name.patch`, overlay 649). That
covers every locale and the inflected, misspelt and transliterated forms
translators used, without forking the `.grd`/`.xtb` files or their message IDs.
The Chromium Authors' copyright, links to the Chromium project, Chromium OS and
Google's Chromebook and Chromecast devices keep their names.
Identifiers stay as they are: the user agent, bundle IDs, keychain items, paths
and preference keys. `tests/ProductName` fails on any translation that still names
Chromium (it needs `PARC_ENGINE_WORKSPACE`), and on any Parc source string
that does outside its reviewed list. Not yet built.

## Acceptance and migration

Version 39 connects the real CEF source-page status callback to a page-owned
AppKit overlay, retaining Chromium's original input processing and the empty
Views-only status-bubble compatibility result. Native attachment and document,
renderer and page lifetime cancel stale text/timers. The recovered show and
expansion delays, compact sizing and click-through pointer avoidance execute
35 AppKit assertions; four isolated compiler checks and read-only overlay replay
pass (118 mapped files, 104 patched targets). Actual page callbacks, exit clearing,
formatting and exact presentation remain runtime gates. See
[status-preview reference and checks](../tests/NativeStatusText/README.md).

The local [extension fixture](../tests/EngineConformance/README.md) exercises action popups, granted activeTab scripting, tab/window identities, commands, worker events and profile storage. Its validator checks the fixture's source and assertions; passing that validator does not establish browser compatibility. Runtime reports remain separate, and denied-permission enforcement, Web Store installation and full extension UX need additional checks.


1. Verify the native window, all supported pane counts, profile switching, real tab transfer, extension actions/popups and actual popup adoption. Test focus, native accessibility, GPU rendering, IME and resize/occlusion.
2. Make individual close and app termination consent-aware and asynchronous. Do not remove/archive a tab while a beforeunload decision is pending.
3. Reimplement the recovered profile-owned downloads, native form/user-edit and media archive protection, dialogs, permissions and lifecycle behavior. Repeat existing real HTTPS, archive and encrypted-restart tests on the replacement.


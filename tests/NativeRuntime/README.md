# Native runtime controller regressions

Browser/app launch is currently prohibited by [AGENTS.md](../../AGENTS.md).
The runtime procedures below are retained for a future explicitly authorized
run. Source/model checks do not grant that authorization.

This focused AppKit application uses the **production** `parc_engine_initialize` → `parc_engine_run_message_loop` → genuine all-window close → idle callback → `parc_engine_shutdown_if_idle` lifecycle. Its default controller suite registers an actual supplied NSWindow and opens one real `PCNativePage` at the exact nonempty data-document URL shared by `runtime_driver.h`, the launcher and the driver. The document contains ordinary HTML controls, needs no external server, and remains the exact required URL across the real renderer crash/reload. It does not use `ChromeUnitTestSuite`, `TestingBrowserProcess`, `BrowserTaskEnvironment`, or a second `CefInitialize`.

The internal driver lives in CEF's existing `libcef_test_support` boundary, which already links CEF's internal test helpers into its framework. No new GN argument, source-lock variant or product UI is added. The driver refuses an ordinary app process: it requires the explicit harness switch, Chromium's official `--use-mock-keychain`, exact `runtime-profile` path, and owned disposable-root marker. The launcher and executable separately reject profile reuse before startup. This is a test seam, not a web-accessible API.

## Optional extension-action regression

`--suite extension-actions` uses this same production-lifecycle application with two actual tabs in one disposable Profile/Browser. The launcher owns an ephemeral `127.0.0.1` HTTP origin serving the packaged test documents. The actual `UnpackedInstaller` loads a bundled MV3 fixture with only `activeTab`; the production native action bridge supplies snapshots, pin mutations and action dispatch. No test grants, fake Browser/Profile, hidden BrowserView or second CEF owner are introduced.

The disposable profile first enables developer mode through the same `SetDeveloperModeForProfile` helper as the normal Extensions UI. A managed preference is refused; exact page/Profile identity and the effective setting are rechecked afterward. The genuine installer and its policy decisions remain authoritative. Separate assertions require the same installed object and its actual enabled-registry entry before any action checks.

The suite checks copied immutable pin snapshots against the real toolbar model and order, restores the original pin state, rejects unselected/stale snapshots after selection away and back, and verifies those refusals grant no access. A genuine current action must grant host access only to the selected tab and origin, leaving the other same-origin tab and another origin denied. Ordinary aggregate close and real engine shutdown are required. It does not establish GUI gestures, popup/side-panel/menu presentation, profile persistence or complete extension compatibility.

```sh
python3 tests/NativeRuntime/run.py /new/output/runtime-development/parc_native_runtime_tests.app --artifacts /existing/test-artifacts --deadline 300 --suite extension-actions
```

Readiness diagnostics record fixed stage labels and existing per-page loading,
commit, frame and process state, including whether a process is blocked. They
leave navigation, deadlines and assertion order unchanged and redact page URLs
and text. An installation or readiness failure must be distinguished from a
failed snapshot, selection or grant assertion.

## Engine selection regression

The extension-action suite also checks engine-to-shell selection through real
`TabListInterface::ActivateTab`, the route used by `tabs.update`. It requires
exact shell/engine selection after non-nestable task delivery, geometry-only
synchronization, rapid B-to-A changes and a newer explicit shell command
overriding an older queued event. The required marker is defined as
`ENGINE_SELECTION` in [the launcher](run.py); a result from before this gate
existed cannot satisfy it.

Recorded packaged runs passed the selection, pin/snapshot and selected-tab
permission checks, followed by the post-shutdown accessibility query and clean
engine shutdown. These results cover their recorded source only. An earlier
intermittent readiness timeout did not recur in those runs; its cause was not
established. This suite does not verify popup/side-panel presentation, saved
split/profile moves, popup restart, PiP input or the default recovery/auth suite.
Current browser behavior belongs in [product status](../../docs/parity.md) and
[the backlog](../../docs/backlog.md), not old package receipts.

## Optional native video-PiP controller regression

`--suite video-pip` reuses this CEF application, its real supplied NSWindow,
Profile/Browser/tab and the production native PiP factory. The app links the
same `PCVideoPiPPresenter` source as Parc. The launcher serves the package-bound
upstream `media/test/data/bear.webm` from an ephemeral loopback origin with HTTP
range support; packaging and launch both check its hash. No replacement
BrowserClient, hidden BrowserView, second engine owner or direct overlay Show
call is used.

The seven assertions migrate the existing
[`NativeVideoPiP` controller cases](../NativeVideoPiP/controller_browsertest.mm):
Close pauses the real player; Hide preserves playback and the original page;
native window close synchronously destroys its overlay; exit/reentry reuses the
window and actual video view; Return targets that original page without pausing;
native resize produces the actual JavaScript `640,360` event; and the real
compositor child fills the video view before/after resize and reentry. Each case
exits real DOM PiP before advancing. Final Browser destruction must release the
presenter, followed by actual engine shutdown.

Initial script evaluation uses the public
`RenderFrameHost::ExecuteJavaScriptWithUserGestureForTests`. Because that API
does not resolve returned Promises, a unique test-owned record on the original
document records real completion or rejection. Subsequent public
`ExecuteJavaScriptForTests` calls observe/delete that record without another
activation. The same exact document, tab, Browser, Profile, observer and native
window are checked before each continuation; replacement, cancellation,
rejection or the 15-second case deadline fails the suite. Continuations run
outside the renderer IPC stack. This preserves the old tests' synthetic test
activation and Promise assertions, not a physical user gesture.

```sh
python3 tests/NativeRuntime/run.py /new/output/runtime-development/parc_native_runtime_tests.app --artifacts /existing/test-artifacts --deadline 300 --suite video-pip
```

The original Chrome browser fixtures require valid CEF initialization; their
`InProcessBrowserTest` startup assumptions do not supply this application's
production lifecycle. Compilation, framework linking, packaging and an actual
suite pass are separate checks. This migration alone does not pass those
fixtures. The seven controller assertions do not verify floating pixels,
pointer input, returned-page activation/focus, document PiP or complete media
behavior. General PiP acceptance remains recorded in the
[PiP guide](../NativeVideoPiP/README.md); default recovery/auth and optional
extension-action results remain separate.

## Native accessibility regression

Before the authentication cases, the driver invokes the real NSApplication
`accessibilityRole` hook. It requires basic native/web accessibility without
newly forcing advanced or screen-reader flags, waits for the live renderer tree,
and walks the actual attached AppKit accessibility children to `AXWebArea`.
The detach case also checks that the same page's native tree survives reattachment.
After genuine CefShutdown, the app queries its role again; this must not recreate
an engine accessibility scope after shutdown. Both AX markers are required
by the launcher. Recorded controller runs passed the genuine engine tree and
native `AXWebArea` checks. They do not establish current whole-browser
accessibility. A timeout needs its stage diagnostics to distinguish document
readiness, a missing engine AX root and native-child traversal.

The role/manual/enhanced request policy uses basic mode 3, separate from the
`ARC_UI_TESTS` full-mode startup path. Real system VoiceOver
uses Chromium156's complete/screen-reader scope and releases that scope when
VoiceOver stops. No renderer AX mode is enabled merely by application readiness.
The local `fixtures/accessibility.html` provides a real button, checkbox and text
field for the separate packaged-app AX interaction check; no synthetic AX objects
or forced-accessibility command-line switches are used. Full control semantics,
VoiceOver toggling and web content navigation remain runtime gates.

Stage/deadline diagnostics record only URL classification, document/frame
readiness, AX mode/root state, exact attachment, and bounded native class/role/
child-count summaries. They reuse existing AX queries and never log page text,
values or credentials. The ordinary NSView summary is diagnostic only; it does
not supply a second route to pass the AX assertion.

## Page notification and shutdown regression

After the real AX check and before authentication, the driver temporarily
observes the actual native page and calls public `RenderProcessHost::Shutdown`
for that disposable page's genuine renderer. A later `WebContentsObserver`
pumps a nestable run loop during process-gone and recovery loading callbacks.
Neither metadata nor error delivery may enter the shell from that observer
stack; the delivered callback performs the real selection/layout operation
from the production crash stack. The real native SadTab snapshot must preserve
its exact termination status and error code, survive actual detach/reattach,
and avoid a duplicate transient renderer NSError. Public page reload then has
to recover the same WebContents/tab with a fresh committed document and clear
the actual snapshot before authentication begins. Old snapshot actions and
presentation acknowledgments must be rejected after recovery. This does not
navigate or recreate a replacement page by URL. The required
`NATIVE_PAGE_EVENTS_PASS` marker appears once between AX and the first
authentication result. This deliberately terminates only the marked disposable
renderer; it is not network-failure coverage. No private content headers or
synthetic event dispatch are used.

The production native SadTab factory keeps Chromium156's genuine SadTabHelper
classification, background-memory policy and reset lifecycle. Normal
`FastShutdown` is not an error; launch failure retains the pinned CEF error
route. Metadata and genuine errors use lifetime-checked non-nestable delivery.
New navigation invalidates pending errors; metadata reads current state. The
native shell's visible drawing acknowledgment and actual Retry action are
separate from this controller fixture, which deliberately does not invent a
first-paint event. Final aggregate close still has to exit
zero through actual engine shutdown, without suppressing unexpected failures.
Recorded controller runs passed genuine renderer failure/recovery and all three
authentication cases, followed by clean shutdown. Earlier crash investigations
are retained in Git history;
they are not current failures. The scheduling preserves current-engine observer
and callback lifetimes.

## Cases and limits

All three cases call the **actual** `LoginHandler::Create` and `ShowLoginPrompt` on the production-created page. They require the real native factory, `WebContentsModalDialogManager`, attached visible native sheet, actual controls and genuine continuation. They check exact Browser/Profile/TabInterface/WebContents/document/window identity throughout.

1. Enter synthetic credentials and press the real **Sign In** NSButton; require one matching credential continuation and modal cleanup.
2. Press the real **Cancel** NSButton; require one empty continuation and cleanup.
3. Call the production binding's `pageWillDetach`; require cancellation through the attachment gate while the original page/window remain alive, then reattach the same page through `pageDidAttach`.

The challenge is **synthetic** and loopback-labelled; no request is sent to port 9. These are integrated controller/presenter cases, not real server `401`, proxy `407`, same-challenge propagation, password-store persistence, or whole-browser functionality tests. Only disposable synthetic credentials are used and no credential value is logged. The real network and normal Keychain/restart gates remain separate.

## Build closure

Map `BUILD.gn`, `runtime_driver.h` and `runtime_driver.mm` to `//cef/tests/parc_native_runtime/`. The small contextual `cef/BUILD.gn` addition makes the existing macOS `libcef_test_support` depend on `:driver`. The driver uses production controller/core targets and `libcef_static`; it has **no** Chrome unit/browser-test runner dependency. There is no dependency back from `libcef_static` to this source set. Normal CEF framework generation/linking is still required after applying this source cohort.


After the reviewed cohort is applied and the normal engine build completes:

```sh
python3 tests/NativeRuntime/check-chromium.py /absolute/chromium/src
python3 scripts/build.py seal-engine --engine-dir /absolute/chromium/src/out/Release_GN_arm64 --manifest /new/output/engine.json
python3 tests/NativeRuntime/package.py --engine-dir /absolute/chromium/src/out/Release_GN_arm64 --manifest /new/output/engine.json --output /new/output/runtime-development
python3 tests/NativeRuntime/run.py /new/output/runtime-development/parc_native_runtime_tests.app --artifacts /existing/test-artifacts
```

The packager refuses an active build, incomplete source seal, missing test exports, external runtime dependency or reused output. It retains copied Chromium resources, graphics/sandbox libraries, helper variants, exact dependency closure and source provenance. It publishes a fresh development directory containing `parc_native_runtime_tests.app`, sibling component dylibs and `runtime-package-report.json`; `.app` output arguments are rejected. The report distinguishes identical pre-sign engine copies from final signed bytes. Only copied app/libraries are signed, and no Keychain setting or system policy changes. Move this whole directory together. Helpers receive the standard CEF link-time RPATH needed for the sandbox-first load; engine load commands are never rewritten. Ad-hoc signing follows the production packager's explicit development entitlement policy.

The launcher imposes a 120-second outer deadline (the app uses 80 seconds, each controller case 15 seconds). Failure first cancels the test-owned handler and requests actual Browser close. If close or idle shutdown stalls, the outer deadline fails and terminates the test process group; it does not claim clean shutdown or prove every helper exited. Profiles and logs are retained. A default-suite success receipt requires all three unique cases, exit zero and the post-loop actual `CefShutdown` result. Optional suites require their own complete ordered markers, including all seven PiP case markers for `video-pip`; partial controller results do not pass another suite.

`python3 tests/NativeRuntime/test_launcher.py` verifies the fresh-profile/result guards and actual loopback transport/hash/range behavior. It never runs Chromium and its success is not runtime browser coverage. The source checker verifies the full applied overlay and exact generated driver object/flags before syntax checking; it has no compatibility fallback and never invokes GN/Ninja.

## Verification boundaries

The driver requires real Browser/Profile/tab/window registration before controller
cases, then native accessibility, renderer-failure/recovery and authentication
markers in order. Missing, duplicate, false or out-of-order markers fail the run.
A successful package or compiled driver is not a runtime pass.

Launcher unit tests verify receipt parsing and guard behavior without executing
Chromium. Run them with:

```sh
python3 tests/NativeRuntime/test_launcher.py -v
```

Actual origin HTTP 401/proxy 407, normal encrypted restart and whole-browser
behavior remain separate from synthetic LoginHandler controller cases. Current
runtime work and product gaps belong in [the backlog](../../docs/backlog.md).
Historical run receipts remain in Git history; they are not live process
records, current release failures or authorization to repeat browser runs.

# Native Chromium BrowserWindow adapter

`Engine/ParcNative/native_browser_window.h/.mm` implements Chromium's actual
`BrowserWindow` interface for a caller-owned AppKit window. Browser owns the
adapter; the shell owns NSWindow. `AsBrowserView()` returns null. This source

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
Recovered contracts are retained in the analysis workspace's
`outputs/parc/arc-window-override-inventory.md`, `arc-modal-host-contract.md`,
`arc-location-bar-contract.md`, `arc-exclusive-access-and-find-contract.md`
and `arc-window-theme-provider-contract.md`. Extension ownership and event
evidence are in `arc-extension-keyboard-contract.md`. The source annotates original
compatibility no-ops separately from mandatory native host responsibilities.

The adapter connects real Browser activation/close subscriptions, native window
association, active page geometry, modal hosting, location services and native
theme/color providers. It arbitrates selected Browsers sharing one NSWindow,
coalesces reentrant activation notifications, and forwards completed native
fullscreen transitions to the real ExclusiveAccessManager. Fullscreen request
acceptance and completed state are distinct. The required shell host must show
the actual security/exit controls and present the operation's actual origin.

The v64 production PiP run exposed a native activation gap: Return from a
minimized source left its window invisible/non-key and the application inactive
before any CUA query. The canonical correction (`999d30d`) selects the actual
Browser, activates NSApplication, deminiaturizes the exact associated window
when needed, then makes it key/front, with weak owner/selection/association
checks after callback-capable operations. Strict compilation and the v67 engine
build pass. The actual v67 rerun shows partial restoration before CUA observation:
the same window is visible and unminimized, but remains non-key/non-main, with
the app inactive and renderer focus absent. Media controls and a fresh counter
still fail input after Return/reload; ordinary quit exits 0 with natural helper
cleanup. This does not establish the input failure's cause or complete native
activation. See [the v67 PiP receipt and limits](../NativeVideoPiP/README.md#checks-and-limits).

The window now owns one `NativeExtensionKeybindingRegistry` for its real
Browser/Profile/TabList. `BrowserWindowFeatures::Init` supplies the TabListBridge
before the window factory runs. Construction initializes Chromium's actual
command observations and permission-aware dispatcher, but does not publish a
detached/unregistered window as active. The mandatory host method
`DispatchExtensionActionAccelerator` must route to that Browser's real action
models and popup service; it has no no-op default. Actions remain distinct from
shared named-command dispatch and its actual activeTab grant.

Selected flags for every Browser sharing an NSWindow are committed first. Each
activation drain publishes the Profile registry for the selected Browser only
when its actual window is key, before arbitrary Chromium or host callbacks.
This publication also runs during a reentrant drain, so a newly selected
Profile cannot leave the previous registry active until callbacks finish.
Conditional deactivation cannot clear a newer Browser's active registry.
Window key/resign, selection changes, approved Browser close and native window
close all pass through this reconciliation.

At teardown the registry is suspended, deactivated and destroyed before native
activation/cancellation callbacks or pre-window feature teardown. Its borrowed
Profile, TabList and action service are still alive; command/media observations
are removed before those callbacks can reenter. The remaining native services
keep their existing pre-window teardown order.

**The Window's post-renderer registry dispatch is implemented.** The follow-up
REA trace proves the stored original Browser delegate (`0xa504c3c`) tries
DevTools, then its actual Window's registry, after the earlier native menu
attempt. `HandleKeyboardEvent` is the single registry call site and requires
the selected Browser's actual key NSWindow outside teardown. The registry uses
Chromium's real virtual-key/modifier/phase/timestamp conversion and rejects
`skip_if_unhandled` events before either action or named commands.
exclusive-access manager already runs before it. The ambiguous host pre/post
keyboard callbacks have been removed. Native client menu wiring, the outer
native skip guard, actual action/popup service and runtime ordering checks
remain integration gates, not passing shortcut claims. See
`arc-page-platform-contract.md` and the extension-command verification README.

`Close()` uses Chromium's real UnloadController. The shell coordinator must wait
for all Browsers sharing a native window to approve closing; a native close
notification does not grant beforeunload consent. The adapter performs required
pre-window feature teardown while its services are alive, cancels native
requests through the host, invalidates observations, releases native services,
and defers adapter deletion. BrowserManager retains ownership of Browser.

`NativeBrowserWindowHost` makes native services and presentation capabilities
explicit. Compatibility hooks need not reproduce Chrome UI; their current
callers still require truthful results, request completion and safe lifetimes.
The interface has no default successful UI callbacks. The concrete host, native
page delegate, factory route and adapted native feature-initialization branches
are now canonical and exercised by the independent application. The original
upstream first-tab BrowserView assumption was an integration requirement, not a
reason to create a hidden BrowserView. Component checks below remain narrower
than the production runtime results tracked in the main README and parity ledger.

`GetStatusBubbles()` returns the empty list allowed by `BrowserWindow` and has
no host service requirement. Chromium156's `UpdateTargetURL` and
`ContentsMouseEvent` cast every supplied status bubble to `StatusBubbleViews`
and its anchor to `ContentsWebView`; a custom AppKit implementation would be
unsafe through those consumers. The separate native hovered-link/status route
is tied to the originating WebContents; this empty compatibility result does not

## Verification

```sh
python3 tests/NativeBrowserWindow/check-chromium.py /absolute/path/to/chromium/src
```

The complete Objective-C++ implementation passes the pinned Chromium156 compiler
as errors. A static assertion also requires the class to implement every pure
virtual BrowserWindow and color-source method. The script reads the checkout,
invokes only its compiler in syntax-only mode, and writes commands/diagnostics
under ignored `build/tests/native-browser-window/`. It does not run generators,
modify the engine checkout, link, or launch a browser.

The separate page-host and window-association executable tests cover their
component lifetimes. They do not validate this complete adapter's Browser
construction/destruction, activation, beforeunload, fullscreen, multi-profile
or renderer integration. Registry activation under reentrant profile selection,
stale window-resign notifications, real action/named-command dispatch,
suspension, media commands, split active-tab grants and teardown also require
linked/runtime checks. The host/factory now runs in the independent browser;
its passing basic runtime cases do not close these broader component gates.
The v64 panel-switch abort also exposes selection/layout reentry during an
engine-originated tab change. Its v69 repair is canonical and now passes the
v70 actual tab-selection harness described below; it is not included in v67.
The production GUI result below closes the observed nested-selection abort;
complete BrowserWindow lifecycle and whole-browser acceptance remain open.

## Engine selection and shell layout

The v64 side-panel tab switch exposed a real nested `ActivateTab` abort: panel
visibility changed during Chromium selection, and Swift layout sent the old
shell selection back into the guarded tab strip. The v69 correction separates
geometry-only synchronization from explicit shell commands. Actual engine
selection is published to the exact existing page after observer unwind;
stale, moved, closed or superseded selections are rejected. The shell preserves
existing split membership and never recreates a page by URL. Explicit local
Start/Easel selection deselects native pages; navigation back to the web waits
for that same tab's actual page attachment. A request generation also prevents
an older synchronous callback continuation from overriding a newer command.

`onWantsActivation`, through its Combine subject. Evidence IDs are
`ev_bfd26244de5e329972bd4d3ea74602c033e52d4ed66ebb85f641ac22312fe807`
and `ev_183092d846ae4012729c66e1fd6086780f92ec41b10ac68a3a0dc30ea050481c`.
downstream scheduling policy. Non-nestable/coalesced tab-strip observation is
Parc's adaptation to Chromium 156's guarded selection callbacks.

The affected native units and public harness client pass their actual compiler
flags, the full Swift application typechecks with warnings as errors, and 88
window-presentation/model assertions pass. The new actual-runtime driver
checks engine-origin selection, geometry preservation, rapid changes and a
newer explicit command after queued notification. It does not itself recreate
the panel GUI abort or same-stack callback supersession. Normal generation
accepts all 117 CEF patches and the v69 engine build succeeds in 13 steps
(84.75 seconds); the exact runtime-driver GN header check also passes. Both
fresh v70 packages pass standard signing/provenance. The actual extension-action
harness now passes `NATIVE_ENGINE_SELECTION_PASS` with `exact_page`, `deferred`,
`geometry_preserved`, `latest_wins` and `shell_override` all true. Copied snapshots,
real pin order, stale-selection refusal and scoped grants then pass, followed
by clean shutdown and post-shutdown AX querying. Exit is 0 after 81.245 seconds,
with no timeout, forced cleanup or remaining exact-package processes. The
receipt is `build/parc-runtime-fmzi86mf-logs/result.json`, SHA256
`65770685b84fbbf8de6e21b2e8a32f283faa10f3b8c68a3a714fc4d606cfb219`.

This passes the actual tab/controller regression. The separate production GUI
run below exercises the original side-panel selection path. Asynchronous
attachment, split/focus, same-stack callback supersession and move/close
lifecycle acceptance remain open.

## Production selection and restart check

The v70 production app completes the formerly aborting extension
`tabs.update` selection: actual tab B becomes active and the sidebar follows.
The GLOBAL panel retains its same instance, edited text and counter value 1.
Selecting A in the sidebar restores its original page and the same CONTEXTUAL
panel instance/text/count. Saved post-edit AX and screenshots bind those
observations. Contextual close removes its panel; reopening creates a new empty
instance, which is separate from state preservation during selection.

B was created in the background and remains white with empty webpage AX,
including after explicit sidebar selection. It had never visibly rendered
before the first switch, so this does not establish selection as the cause.
No B reload was attempted. That failure prevents the reverse B-page API action
and keeps full attachment/side-panel acceptance open. Source investigation
identifies a missing native parent-view visibility step; its correction still
needs the same production rerun.

Saved Start and Easel entries hide the native panel; Cmd-L navigation from each
to a real counter page accepts input (0 to 1), with matching sidebar entry
count/position. Internal saved IDs were not introspected. Same-profile restart
renders the former B URL, restores the installed pinned popup on its first
attempt, and retains the profile nonce without writing it. Newly created
session-owned fixture tabs can open, close and reopen the global panel. Unsaved
panel state is not claimed to survive the process restart.

Both ordinary quits exit 0 (314.711 and 72.322 seconds); final exact-package
process scans are empty, with no forced cleanup. The v59 missing-popup/watchdog
failure does not recur in this bounded run. A second popup in the first lifetime
is visible but the fixture refuses multiple live popup contexts; that ambiguity
does not by itself establish a production popup-lifecycle defect.

Frozen receipt `work/independent-v70-selection-wetjgwhd/receipt.json` SHA256:
`780de6c531a6a23d84dc211c0e3d5a36746383689e0121a0bf1a6d8fe0b84260`.
All 58 bound evidence files were verified. The production package stayed
unchanged. Neither this partial GUI result nor the controller suite completes
an entire P0 area.

## Minimize and restore input control

A fresh, unchanged v74 production app reproduced the input failure without
entering PiP. The same counter changed 0→1 before minimizing. After the observed
minimize action, computer-use observation and exact Window-menu restoration,
indexed-button and screenshot-grounded coordinate clicks both left it at 1.
There was one initial page request, no reload/navigation, media or extra tab.
An indexed computer-use click is not itself evidence of native AXPress delivery.

Ordinary Cmd-Q exited 0; no owned helpers or forced cleanup remained. Receipt
`work/independent-v74-no-pip-control-qn9ix5yx/receipt.json` SHA256
`68013a4a3badb07a29be59880f220c1b6b3ac8deb3c821ffd85dc70de14f8716`
binds 18 verified evidence files. PiP is unnecessary for this reproduction;
which native/Chromium/renderer handoff fails remains unknown. The opt-in
`--parc-input-diagnostics` trace records actual event ingress, routing/gates and
renderer outcomes using identifiers only. Its source checks are not a fix or
an executed end-to-end result.

The fresh v77 repetition uses package-report SHA256
`4ec85d6975080f7fdebffcc2c5c0a62c3e7b332c4e7712992a08b50e4e41e94d`.
The original counter reaches 2 before the same minimize/observe/Window-menu
restore sequence. One indexed and one pointer click afterward both leave it at
2. Events 240/242 reach Cocoa ingress/hit/routing, the actual page widget and
input ACK; failed events 243/245 reach application send/return only. Window
18297, page 1 and the original renderer identities remain the observed owners.
No native AX-press entries appear; indexed targeting used the pointer route.
The trace localizes the boundary before Chromium’s Cocoa page view but does not
yet establish the native dispatch cause.

Ordinary Cmd-Q destroys page 1, then reaches the upstream ten-second teardown
watchdog and exits 2. No package processes remain and no external app/helper
signal was used. The log mentions a dump attempt, but no dump was located in
the exact disposable profile or a new Parc DiagnosticReport. Receipt
`work/independent-v77-input-control-g8yczim8/receipt.json` SHA256
`91054cc42ed199a4edf51431e94857be98bb4d136efd210dcf03513104244113`
binds 20 verified files. The next run adds bounded weak native-view/window
snapshots around dispatch and the existing local monitor, and logs the actual
single superclass root hit-test result. These are observations only; a missing
hit-result alone cannot establish cause, and synchronous logging may affect
timing. A one-shot two-second process sample on ordinary Quit will observe the
teardown wait without changing its watchdog or enabling crash reporting.

The v82 package passes strict signing/provenance (519 exact pre-sign engine
copies, 524 signed images); package-report SHA256 is
`310d2dd35ffced9a3491eb7d3ee0fe43f823e17e4b28d085194de12801011768`.
Its same-document control again reaches 2 before minimize/restore and stays 2
for failed events 249/251. Actual root hit tests still return the original
RenderWidgetHostViewCocoa, with unchanged visible/unhidden views and geometry
through the local monitor. The window is visible and not minimized, but remains
non-key; public NSRunningApplication metadata also reports the app inactive.

A normal Dock observation timed out without an action. One CUA Cmd-Tab did not
activate Parc. Immediately afterward, public NSWorkspace metadata identifies
PID 47809 / com.apple.SecurityAgent as frontmost. That process predates these
runs, but its prior foreground ownership and prompt/caller are unknown. No
protected surface was inspected or operated. This external state prevents
isolated browser activation/input acceptance; it is not evidence for a focus,
visibility or click-replay repair. GUI actions are stopped pending human
identification/resolution of that protected authorization surface.

Held process 84433 and original window 18340 remain in
`work/independent-v82-input-control-dmltsfek`; its logs are live, not a sealed
completed-run receipt. A two-second read-only process sample shows Parc idle in
its normal NSApplication loop, with no sampled Keychain wait. The official
mock-Keychain switch reaches Chromium’s browser-side OSCrypt provider; it is
not a system-wide Security API mock and does not identify the prompt’s caller.
The one-shot quit sampler is armed but ordinary Quit has not been requested.
Resume by verifying actual app activation before clicking the unchanged page;
then capture ordinary Quit and run the separate folder confirmation gates.

# Native DevTools

This source keeps Chromium's real `DevToolsWindow`, main tools/toolbox WebContents, inspected-page identity, docking state, resize strategy and close decisions. Parc supplies native presentation; it does not recreate a tools URL, use a hidden BrowserView or insert developer tools into BrowserStore.

## Ownership and integration

- The actual `DevtoolsUIController` keeps Chromium's class unchanged. For a Browser Parc hosts, three `.cc` hooks in its `UpdateDevtools`, `SetDevtoolsScrimVisibility` and `TearDown` hand those calls to the native host, and a controller Parc did not make keeps its ordinary Views behavior. BrowserWindowFeatures owns its lifetime. Docking still requires the real CanDockDevtools policy; no test-only route marker bypasses it.
- One `NativeDevToolsPane` belongs to each exact native page binding. Its composite retains the unchanged inspected page host, the actual tools or toolbox native view, the inspected-only Find overlay and a tools scrim. It never owns/deletes WebContents. Status remains inside the inspected host.
- First docking hosts the supplied native view directly. If a real native page wrapper already exists, the pane reuses that exact wrapper and its platform observer. Undock/redock/undock reuses the same existing native host and actual contents instead of creating another host.
- The actual Chromium resize strategy determines bounds and hide-inspected state. View replacement, attachment, visibility and destruction are guarded against native reentry and later owners. Exact external shell container identity is preserved for transfer rollback; the composite's interior superview is not a shell container.
- The dedicated Swift auxiliary client holds no saved tab/history record. Actual tools-tab detachment relinquishes its exact observer. Last-Browser drain and unused reservation-abort notifications are posted with binding-epoch and pending-reservation checks, so an old notification cannot close a newly acquired owner.
- Direct docked main/toolbox keys use one native menu offer and the exact same-window inspected Browser's registry. Undocked main tools have their actual auxiliary Browser's `BrowserWebContentsDelegate` (the Parc subclass in production), so they use NativeClient's single menu offer followed by that auxiliary Browser's registry. A real delegate-identity assertion covers this distinction; no inactive inspected-window registry is substituted. `skip_if_unhandled` is terminal.
- A scoped modal binding in the pane follows actual docked main contents after pane registration. It updates the real modal manager, replays actual blocking state even when the delegate is unchanged, and takes a generation from the tools' own contents so an older release never clears a newer binding. Existing docked contents keep this association when legitimately transferred into a native popup Browser; the initial docking eligibility policy is unchanged. Toolbox never steals its undocked main's modal owner.
- Extension-popup inspection uses the genuine supplied popup contents. Acceptance means a real controller accepted the request, not that asynchronous frontend loading or window presentation has completed. Upstream DevTools AppModal/web-modal ownership is retained.

## Checks

From the repository:

```sh
bash tests/NativeDevTools/run.sh
python3 tests/NativeDevTools/check-chromium.py /absolute/path/to/chromium/src
```


The six `NativeDevToolsBrowserTest.*` cases cover actual tools/resize strategy, exact contents/delegate through dock/undock/redock, real close restoring the inspected page, active modal transfer between ordinary Browsers, transfer into a native popup Browser, and stale modal-lease protection. The modal cases use the actual Chromium manager/delegates with a platform-dialog test double. The test Browser supplies real Profile/tab/DevTools policy and the typed native presenter. Execution requires a valid Chromium process/context. The separate NativeRuntime harness covers its own controller suites.

The reusable checker above has no compatibility fallback: it requires the complete reviewed overlay applied, exact object membership, generated final target flags, ARC/warnings-as-errors, source/toolchain/compiler hashes and unchanged inputs. It performs syntax checking only, without GN, Ninja or runtime execution.

The pane view belongs to `native_components`; `NativeDevToolsPane` belongs to shared `native_devtools`, consumed by `//parc:browser` and `//parc/tests/native_devtools:browser_tests`. Native host/application/page route remains in `//parc:browser`. The genuine test target defines `HAS_OUT_OF_PROC_TEST_RUNNER`. Root owns final GN/overlay composition and dependency checks.

## Auxiliary services and presentation

Docked main tools have an explicit auxiliary-page lease tied to the inspected
page, real DevTools contents, Browser/Profile and exact native containment.
The pane installs it after attachment and revokes it before detachment or
replacement. File selection, typed permissions, HTTP authentication and client
certificates use this owner; AppModal supplies the native sheet for main tools.
A retained native host uses the same lease for focus, screen coordinates and its
JavaScript runner. First docking can host the genuine engine view without a
native wrapper. See [auxiliary ownership](Auxiliary.md).

The lease deliberately excludes toolbox contents. Other auxiliary security
services do not inherit this authority automatically; each needs its own exact
owner contract before it can use a page-bound native service.

Undocked autosave is `bundleIdentifier + ".devToolsWindowAutosaveFrame"` with
`setFrameUsingName:` and `center` on failure. The first-open empty-rect fallback
size is a current-engine adaptation. Docked bounds use Chromium's resizing
strategy. Native tools focus on appear through the genuine AppKit view.

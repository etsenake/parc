# Native DevTools

This source keeps Chromium's real `DevToolsWindow`, main tools/toolbox WebContents, inspected-page identity, docking state, resize strategy and close decisions. Parc supplies native presentation; it does not recreate a tools URL, use a hidden BrowserView or insert developer tools into BrowserStore.


## Ownership and integration

- The actual `DevtoolsUIController` gains a typed native presentation delegate only for a registered Parc route. Its ordinary Views behavior stays intact. BrowserWindowFeatures owns its lifetime. Docking requires both the real CanDockDevtools policy and an owned live NativeDelegate; no test-only route marker bypasses the capability check.
- One `NativeDevToolsPane` belongs to each exact native page binding. Its composite retains the unchanged inspected page host, the actual tools or toolbox native view, the inspected-only Find overlay and a tools scrim. It never owns/deletes WebContents. Status remains inside the inspected host.
- First docking hosts the supplied native view directly. If a real CEF page wrapper already exists, the pane reuses that exact wrapper and its platform observer. Undock/redock/undock reuses the same existing CEF host and actual contents instead of creating another host.
- The actual Chromium resize strategy determines bounds and hide-inspected state. View replacement, attachment, visibility and destruction are guarded against native reentry and later owners. Exact external shell container identity is preserved for transfer rollback; the composite's interior superview is not a shell container.
- The dedicated Swift auxiliary client holds no saved tab/history record. Actual tools-tab detachment relinquishes its exact observer. Last-Browser drain and unused reservation-abort notifications are posted with binding-epoch and pending-reservation checks, so an old notification cannot close a newly acquired owner.
- Direct docked main/toolbox keys use one native menu offer and the exact same-window inspected Browser's registry. Undocked main tools have their actual auxiliary Browser's `BrowserWebContentsDelegate` (the CEF subclass in production), so they use NativeClient's single menu offer followed by that auxiliary Browser's registry. A real delegate-identity assertion covers this distinction; no inactive inspected-window registry is substituted. `skip_if_unhandled` is terminal.
- An explicit scoped `DevToolsWindow` modal binding follows actual docked main contents after pane registration. It updates the real modal manager, observes Browser lifetime before callbacks and replays actual blocking state even when the delegate is unchanged. Weak owners and a generation protect newer bindings from old detach. Existing docked contents keep this association when legitimately transferred into a native popup Browser; the initial docking eligibility policy is unchanged. Toolbox never steals its undocked main's modal owner.
- Extension-popup inspection uses the genuine supplied popup contents. Acceptance means a real controller accepted the request, not that asynchronous frontend loading or window presentation has completed. Upstream DevTools AppModal/web-modal ownership is retained; actual native dialog behavior remains a runtime gate.

## Checks

From the repository:

```sh
bash tests/NativeDevTools/run.sh
python3 tests/NativeDevTools/check-chromium.py /absolute/path/to/chromium/src
```


The candidate's five native units and five changed upstream implementation units pass pinned-Clang syntax checks with warnings as errors. The six genuine `NativeDevToolsBrowserTest.*` cases also pass syntax checking: actual tools/resize strategy, exact contents/delegate through dock/undock/redock, real close restoring the inspected page, active modal transfer between ordinary Browsers, transfer into a native popup Browser, and stale modal-lease protection. The modal cases use the actual Chromium manager/delegates with a platform-dialog test double. **Those genuine browser cases have not been linked or executed.** The test Browser supplies real Profile/tab/DevTools policy and the real typed native presenter; it does not certify Parc's native construction/Swift window route. The known current CEF/browser-test initialization mismatch must be resolved before executing these cases; syntax success alone does not make that runner compatible. The separately prepared NativeRuntime runner currently covers HTTP-auth, not these DevTools cases.


The pane view belongs to `native_components`; `NativeDevToolsPane` belongs to shared `native_devtools`, consumed by `libcef_static` and `//cef/tests/parc_native_devtools:browser_tests`. Native host/application/page route remains in `libcef_static`. The genuine test target defines `HAS_OUT_OF_PROC_TEST_RUNNER`. Root owns final GN/overlay composition and dependency checks.

## Remaining acceptance

Linked native runtime must verify frontend load; left/right/bottom docking; undock/redock exact CEF/WebContents identity; page and extension-popup inspection; split/transfer/hidden-page visibility; toolbox; focus/keyboard routing; scrim, Find and status overlap; inspected/page/window close and beforeunload; creation refusal/unused reservation; crash and engine shutdown drain. Native modal runtime handling, CEF public DevTools API compatibility and direct frontend command coverage also remain acceptance gates.

**Known unavailable auxiliary service binding:** first-docked tools need not have a CEF host. A retained CEF host after redocking has no Browser-owned TabInterface, and `NativeChromePlatformDelegate::PageHostDidAttach` / `HasAttachedPage` deliberately reject it. Thus CEF `SetFocus`/`GetScreenPoint`, the native CEF JavaScript runner and permission attachment, and the tab-owned native file/authentication/client-certificate routes are not connected for docked tools. Direct DevTools WebContents focus/render and its genuine AppModal/web-modal route are separate; they do not establish those CEF services. This needs an exact auxiliary-owner service binding, not a fabricated tab or weaker ownership check.


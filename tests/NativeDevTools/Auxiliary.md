# Docked main-tools service ownership

This cohort adds a scoped native presentation lease for the actual main DevTools WebContents. It does not create a TabInterface, Browser, separate browser host or replacement page. The inspected page's real TabInterface, Browser/Profile, current DevToolsWindow, supplied NSWindow and exact native-view containment must all agree. Toolbox contents are deliberately excluded.

The lease is revoked before pane replacement/detachment, inspected-tab transfer/discard, native window close or contents destruction. Requests capture that lease when created. A later owner cannot revive an earlier request. Normal tab validation stays unchanged. Pane generation checks preserve a newer frontend installed by a cancellation callback; precise lifetime retention covers callbacks releasing the final pane owner.

The main frontend is marked before its first navigation only for the inspected page's actual native Browser route. File-selection and typed permission factories use that explicit route and cancel when it is unbound; they do not choose a frontmost/focused window. Existing chooser, permission, HTTP-auth and client-certificate services retain their genuine controllers, policy, document and shared-window security checks. Retained native hosts use a separate auxiliary attachment gate for focus, coordinates and existing native JS-runner attachment. First-docked frontends still use the real engine native view and DevTools/AppModal paths without a fabricated native host.

AppModal keeps Chromium's actual manager, queue, controller, suppression, beforeunload and continuation. A per-WebContents provider captures the original lease when the real controller is created. Its native view is a source-owned Parc dialog sheet with a rounded prompt field and the circular suppression checkbox; the actual tools delegate activates the inspected page before display. Accept/cancel rechecks the owner and shared-window security state after sheet/reservation release. A captured side-effect-free controller validator checks ownership again after the real queue advances, immediately before its result/suppression update. Legitimate next queue items are not rejected merely because they own the next sheet.

The HTTP-auth request also latches cancellation before deferred modal-list removal. Restoring the same hierarchy before the posted task cannot authorize a queued or propagated SetAuth. CloseAllDialogs continues removing its actual entry synchronously.

## Checks

The source checker covers native and upstream implementations plus the
DevTools/AppModal/chooser and HTTP-auth test sources. It requires the applied
overlay and the owning targets' generated flags; it does not generate or build
the engine.

The twelve cases cover exact engine/window identity, reentrant lease replacement, actual default prompt/suppression, a genuinely queued old-owner request, detach cancellation, real chooser cancellation, unbound rejection, release-time competing security UI, real inspected-tab activation, queue-advancement lease revocation, final pane-owner release and reentrant frontend replacement during old-tools destruction. Result state lives in the fixture through teardown.

The browser fixture installs the native presentation hooks over a real
test Browser. Execution requires a valid Chromium process/context. Toolbox contents
are outside this main-frontend lease; they cannot borrow the inspected page's
service authority.

## Integration ownership

The overlay registers a shared `native_auxiliary_page` source set for `native_auxiliary_page.{h,mm}`, and a separate `native_auxiliary_services` source set for `native_auxiliary_services.{h,mm}`. This keeps the service dependencies acyclic: the lease depends on actual DevTools/browser/tab/native-components; existing auth/certificate/permission/download targets depend on the lease; the new AppModal service depends on the lease plus existing auth/certificate targets. `native_devtools` and `//parc:browser` consume the services. The source targets and their consumers are registered in the overlay.

The existing `//parc/tests/parc_native_devtools:browser_tests` source set includes `auxiliary_browsertest.mm`, retains `HAS_OUT_OF_PROC_TEST_RUNNER` and declares its real controller/chooser dependencies. The existing HTTP-auth test target keeps its membership. The platform preserves external-protocol and WebAuthn attachment/cancellation guards. The strict `check-chromium.py` verifies the full applied source cohort and actual generated object ownership before compilation.

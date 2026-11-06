# Docked main-tools service ownership

This cohort adds a scoped native presentation lease for the actual main DevTools WebContents. It does not create a TabInterface, Browser, CEF browser host or replacement page. The inspected page's real TabInterface, Browser/Profile, current DevToolsWindow, supplied NSWindow and exact native-view containment must all agree. Toolbox contents are deliberately excluded.

The lease is revoked before pane replacement/detachment, inspected-tab transfer/discard, native window close or contents destruction. Requests capture that lease when created. A later owner cannot revive an earlier request. Normal tab validation stays unchanged. Pane generation checks preserve a newer frontend installed by a cancellation callback; precise lifetime retention covers callbacks releasing the final pane owner.

The main frontend is marked before its first navigation only for the inspected page's actual native Browser route. File-selection and typed permission factories use that explicit route and cancel when it is unbound; they do not choose a frontmost/focused window. Existing chooser, permission, HTTP-auth and client-certificate services retain their genuine controllers, policy, document and shared-window security checks. Retained CEF hosts use a separate auxiliary attachment gate for focus, coordinates and existing native JS-runner attachment. First-docked frontends still use the real engine native view and DevTools/AppModal paths without a fabricated CEF host.

AppModal keeps Chromium's actual manager, queue, controller, suppression, beforeunload and continuation. A per-WebContents provider captures the original lease when the real controller is created. Its native view is a source-owned sheet; the actual tools delegate activates the inspected page before display. Accept/cancel rechecks the owner and shared-window security state after sheet/reservation release. A captured side-effect-free controller validator checks ownership again after the real queue advances, immediately before its result/suppression update. Legitimate next queue items are not rejected merely because they own the next sheet.

The HTTP-auth request also latches cancellation before deferred modal-list removal. Restoring the same hierarchy before the posted task cannot authorize a queued or propagated SetAuth. CloseAllDialogs continues removing its actual entry synchronously.

## Evidence and adaptation


## Verification

Sixteen pinned-Clang syntax checks cover eight native implementations, six changed upstream implementations, the new 12-case genuine DevTools/AppModal/chooser test source and the 13-case HTTP-auth source. The latter adds one invalid-host/restoration regression to the existing twelve. Checks use an isolated VFS and generated source-owner or explicitly labelled compatibility flags; they do not mutate the engine checkout, generate GN, link or execute the browser cases.

The twelve new cases cover exact engine/window identity, reentrant lease replacement, actual default prompt/suppression, a genuinely queued old-owner request, detach cancellation, real chooser cancellation, unbound rejection, release-time competing security UI, real inspected-tab activation, queue-advancement lease revocation, final pane-owner release and reentrant frontend replacement during old-tools destruction. Result state lives in the fixture through teardown.

Integrated GN/include/object checks, engine link, the CEF-compatible runtime runner and real Swift/native-shell execution remain required. The current Browser test fixture substitutes only the native presentation delegate over a real test Browser; it is not proof of Parc's production factory or Swift route. Verify actual repeated docking/transfer/close, focus and coordinates, alert/confirm/prompt/beforeunload, chooser, permission, HTTP/proxy and certificate flows. Toolbox, exact visual/motion parity, and unrelated auxiliary security services remain open. No standalone AppKit assertions are claimed for these new C++ controller paths.

## Integration ownership

The overlay registers a shared `native_auxiliary_page` source set for `native_auxiliary_page.{h,mm}`, and a separate `native_auxiliary_services` source set for `native_auxiliary_services.{h,mm}`. This keeps the service dependencies acyclic: the lease depends on actual DevTools/browser/tab/native-components; existing auth/certificate/permission/download targets depend on the lease; the new AppModal service depends on the lease plus existing auth/certificate targets. `native_devtools` and `libcef_static` consume the services. The source targets are registered. Actual generated dependency/object validation remains pending the current engine build.

The existing `//cef/tests/parc_native_devtools:browser_tests` source set includes `auxiliary_browsertest.mm`, retains `HAS_OUT_OF_PROC_TEST_RUNNER` and declares its real controller/chooser dependencies. The existing HTTP-auth test target keeps its membership. The merged platform preserves v44 external-protocol and WebAuthn attachment/cancellation guards. The strict `check-chromium.py` verifies the full applied source cohort and actual generated object ownership before compilation.

# Native extension uninstall

The repository source connects Chromium's actual action-menu `UNINSTALL`
command, policy/removal controller, asynchronous icon loading and
`DialogModel` to a source-owned AppKit sheet. The command reaches Parc through
a one-call hook in `extension_context_menu_model.cc`; Parc's
`NativeExtensionUninstallDialog` subclasses Chromium's uninstall dialog and
builds the same model as its Views implementation. The production native host
registers this service.

## Confirmation presentation

The source-owned NSPanel uses scheduled `beginSheet` on the captured parent,
validity-gated Return/Escape and terminal teardown before result delivery. The
actual Chromium model supplies sanitized title, icon, buttons, optional
triggering-extension text and report-abuse checkbox. Model callbacks and
`OnDialogDestroying` run once; unsupported model fields cancel.

Consent binds exact Browser/Profile/page/window/extension instance. Navigation
retains profile-scoped consent, but detach, selection loss, owner teardown and
extension replacement cancel. A replacement with the same ID cannot inherit
consent. Browsers without the native service retain the ordinary Views route.

## Ownership and shell obligations

- `NativeBrowserWindow` owns `NativeExtensionUninstallService` as typed unowned
  Browser data. The real menu command captures its binding, and `Confirm` arms
  it, before async icon loading. It uses the same supplied parent/security/selection host as menus and
  popups, with no key/frontmost-window lookup.
- `Arm` commits observers and a pending reservation before notifications can
  close menus or popups. Reservation state belongs to the exact weak `NSWindow`,
  so multiple Browsers sharing that window see the same state. Release is
  idempotent; acquisition cancellation cannot leak a returned reservation.
- Popup/menu services union the reservation, the native host security query and
  Chromium's tracker. `OnSecurityDialogAdded` matches actual Widget/native-window
  ancestry before visibility: registration can precede `Show`. Relevant-window
  registration cancels; unrelated windows remain isolated. This conservative
  registration-time policy prevents security UI being obscured.
- The shell's side-effect-free `HasVisibleBrowserSecurityUI` query covers the
  whole window. The presenter uses `HasVisibleBrowserSecurityUIExcluding` with
  its exact sheet and reservation; only a sole active lease in that same window
  can be excluded. Hosts without this distinction stay conservative. The request
  observes exact-window reservation changes itself and rechecks after acquisition,
  including notifications delivered before the lease is returned. Browser selection
  changes still call `HostStateChanged`. The Views tracker alone is insufficient
  for a native window without `BrowserElementsViews`.
- Page detachment cancels before the native view moves. Browser shutdown stops
  this service before shell/features, Profile, TabList or Browser destruction.
  Requests do not keep those owners alive or choose replacement owners.
- The binding owns the real model while visible and temporarily retains it
  across accepting callbacks that unload an extension or delete the controller.
  Terminal state is committed before external delivery. A late model after
  cancellation is destroyed once and cannot resurrect the sheet.

The production native BrowserWindow owns and registers this service. It must
retain the host and Browser/Profile through shutdown completion.

## Verification

The standalone AppKit suite covers **52 assertions in 9 groups**. Real windows/sheets exercise button and checkbox dispatch,
Return through `NSWindow.sendEvent:`, Escape, accessible naming, enabled-state
gating, cancellation before presentation, reentrant validation/release, weak
window lifetime, foreign-sheet rejection and parent closure. This is component
execution, not Chromium removal execution.

Fifteen genuine browser-test cases cover actual controller Cancel, the real
UNINSTALL hook/dialog/registrar route, pending-owner expiry, service destruction
during reservation acquisition, real-model checkbox/reentrant Close, page detach,
same-ID replacement, unsupported/late models, navigation retention and security
registration before Show with unrelated-window isolation. Added cases use the
production-style aggregate security query and cover own-acquisition notification
reentry, competing reservations and unrelated-window reservations. The checker compiles them with their own generated target settings.

### Integration verification

The aggregate security query must exclude only the request's own exact sheet and
reservation. Competing reservations still cancel it. Generated-target compiler
checks and header checks verify source membership. Executing the browser fixture
requires valid Chromium process/context initialization.

## Targets and commands

`//parc/native:native_components` owns the presenter and shared
reservation and exposes their headers. `native_extensions` owns uninstall and
its security-context helper; `security_dialog_tracker` and `//ui/views` are
public dependencies because public headers expose their types. The hook is
installed beside the other interface hooks in `ParcBrowserMainExtraParts`.

`//parc/tests/native_extensions:uninstall_browser_tests` is consumed by the
macOS `browser_tests` graph. It defines `HAS_OUT_OF_PROC_TEST_RUNNER` and directly
depends on both native targets, the tracker and real Chromium test services.
Membership is maintained in `tests/NativeExtensionPopup/BUILD.gn`, which the
overlay installs at the shared native-extension test directory.

Run from the repository root:

```sh
bash tests/NativeExtensionUninstall/run.sh
python3 tests/NativeExtensionUninstall/check-chromium.py /path/to/chromium/src --output-name Release_GN_arm64
```

The compiler checker requires the applied reviewed overlay and generated targets;
it has no compatibility fallback. It verifies mapped source/header/patch-output
hashes, actual ObjC++ object membership and each upstream CXX owner, preserving
real flags, ARC, warnings-as-errors and module settings. It performs no generation,
linking or test execution and supplies no fake headers. Logs, command/hash records
and the standalone executable stay under ignored
`build/tests/native-extension-uninstall/`. Apply/generate/build through the
reviewed engine source workflow before running the actual-target check.

The confirmation result returns to Chromium's removal controller. Its policy,
report-abuse handling and extension registry own the removal outcome; the sheet
only supplies the user's decision for the captured extension instance.

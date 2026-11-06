# Native extension uninstall

The repository source connects Chromium's actual action-menu `UNINSTALL`
command, helper, policy/removal controller, asynchronous icon loading and
`DialogModel` to a source-owned AppKit sheet. The v22 source overlay is applied
and its targets are generated. Linked browser execution remains pending; this

## Reference and adaptations

`0x6895c74`, show path `0x6895f0c` and main app exact-frame sheet presenter
controller through `0x6896378`. The research record is
`outputs/parc/arc-extension-uninstall-contract.md`; recovered pseudocode is not
original source. The original permissive missing-delegate fallback is not copied.

The presenter follows the recovered custom `Dialogs.SheetWindow` boundary:
source-owned `NSPanel` and content view, scheduled `beginSheet` on the captured
parent, validity-gated `insertNewline:`/`cancelOperation:` and terminal teardown
before result delivery. It consumes the real Chromium 156 model's sanitized
title, icon, buttons, optional triggering-extension paragraph and report-abuse
checkbox. It invokes model callbacks and `OnDialogDestroying` exactly once;
unsupported model fields cancel. Provisional geometry/fonts and AppKit sheet
motion do not claim visual parity.

Exact Browser/Profile/page/window/extension-instance binding, the shared-window
pending reservation and expiry rules are Parc/current-engine adaptations.
Ordinary navigation retains profile-scoped consent. Page detach/ownership loss,
Browser selection loss, owner teardown and extension unload/replacement cancel
it. A replacement extension with the same ID cannot inherit consent. Browsers
without the registered native service retain the ordinary Views factory route.

## Ownership and shell obligations

- `NativeBrowserWindow` owns `NativeExtensionUninstallService` as typed unowned
  Browser data. The real menu command captures its binding before async icon
  loading. It uses the same supplied parent/security/selection host as menus and
  popups, with no key/frontmost-window lookup.
- `Arm` commits observers and a pending reservation before notifications can
  close menus or popups. Reservation state belongs to the exact weak `NSWindow`,
  so multiple Browsers sharing that window see the same state. Release is
  idempotent; acquisition cancellation cannot leak a returned reservation.
- Popup/menu services union the reservation, the native host security query and
  Chromium's tracker. `OnSecurityDialogAdded` matches actual Widget/native-window
  ancestry before visibility: registration can precede `Show`. Relevant-window
  registration cancels; unrelated windows remain isolated. This conservative
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

The production native factory and complete shell are still integration work;
registering this service alone does not create the required native browser.

## Verification

**Standalone AppKit: 52 assertions in 9 groups passed**, including the owner's
repository run. Real windows/sheets exercise button and checkbox dispatch,
Return through `NSWindow.sendEvent:`, Escape, accessible naming, enabled-state
gating, cancellation before presentation, reentrant validation/release, weak
window lifetime, foreign-sheet rejection and parent closure. This is component
execution, not Chromium removal execution.

Fifteen genuine browser-test cases cover actual controller Cancel, the real
UNINSTALL helper/factory/registrar route, pending-owner expiry, service destruction
during reservation acquisition, real-model checkbox/reentrant Close, page detach,
same-ID replacement, unsupported/late models, navigation retention and security
registration before Show with unrelated-window isolation. Added cases use the
production-style aggregate security query and cover own-acquisition notification
reentry, competing reservations and unrelated-window reservations. They pass the compiler
with their own generated target settings but **have not been linked or executed**.

### Integration verification

The v33 source correction fixes a concrete integration defect: the full AppKit
host includes all sheets/reservations in its aggregate query, so the uninstall
request was rejecting its own pending reservation. Exact-owner exclusion now
preserves its confirmation while competing owners cancel it. The actual host,
request and fifteen-case browser source compile with pinned target settings;
read-only overlay replay passes. The unchanged v22 build does not yet contain
this correction, and genuine Chromium removal remains unexecuted.

- Reviewed source/hash coverage: **65 mapped files and 67 patched outputs passed**.
- Live v22 overlay application and GN generation pass. All 117 CEF patches take
  the normal already-applied path, with none failing.
- Header-dependency checks pass for `native_components`, `native_extensions`
  and `uninstall_browser_tests`.
- All eight native/test units and all three complete upstream translation units
  pass their actual generated target compiler checks, with warnings as errors.
- The broader upstream `chrome/browser/extensions:extensions` header check
  reports two existing pinned-CEF includes in `extension_tab_util.cc` and
  `api/chrome_extensions_api_client.cc`. Both are introduced by CEF's unchanged
  `chrome_browser_extensions.patch`; neither file is modified by this overlay.
  Adding the suggested `libcef_static` dependency would create a cycle and has
  not been done. This broader check is not reported as passing.
- Linked browser tests and production native-shell runtime: **pending**.

## Targets and commands

`//cef/libcef/browser/parc_native:native_components` owns the presenter and shared
reservation and exposes their headers. `native_extensions` owns uninstall and
its security-context helper; `security_dialog_tracker` and `//ui/views` are
public dependencies because public headers expose their types. The extensions
upstream target includes `extension_uninstall_native_host.h` and publicly
propagates `//ui/base/unowned_user_data`.

`//cef/tests/parc_native_extensions:uninstall_browser_tests` is consumed by the
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

Remaining runtime gates include removal/rejection/reload and managed policy,
report-abuse behavior, two real native Browsers sharing one window, popup/menu/
security ordering, callback-driven helper deletion, Profile/Browser teardown,
behavior. Passing AppKit assertions does not close those gates.

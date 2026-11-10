# Native autofill and password presentation

`autofill_save_presenter` is a custom AppKit sheet and retained request. It uses
a supplied page view and NSWindow, never NSAlert, an app-modal fallback, the
frontmost window, or a fabricated successful bubble. `autofill_save_session`
implements real `AutofillBubbleBase` factories using pinned Chromium156's
actual local-save controllers and the transferred `UpdateAddressBubbleController`.
`NativeAutofillBubbleHandler` supplies these presentations through the real
Browser-owned interface. Its other methods have explicit unavailable results,
paired with producer and continuation guards in the reviewed upstream patch.
The handler is registered by the canonical native host. Historical checks below
retain their original scope; unrun browser tests are not implementation gates
under the current user direction.

## Native password Save and Update

`password_prompt` connects the actual ManagePasswordsUIController/BubbleManager
to SaveUpdateBubbleController and the shared native sheet. Save writes through
Chromium's real form manager and store; No and Never on this site use their real
controller decisions. Never is omitted for an update. The exact submitted form,
page, browser, profile and physical window are revalidated before an action.
Detach, replacement, navigation and visibility loss interrupt the captured request;
actual sheet attachment precedes OnBubbleShown. No credential values are sent to
the Swift shell. Trusted-vault blocking retains Chromium's unlock-before-save path.

Management is reachable through the command bar and Settings. Generation retains
Chromium's existing Cocoa-container popup route; manager reveal retains the real
profile store and macOS DeviceAuthenticator. No duplicate generation or reveal
surface was added. Remaining account-address/card/payment modes are separate
implementation work; this password-save path is implemented.

## Address update and editing

The native update session owns the real `UpdateAddressProfileView` and transferred
controller, preserving actual old/new values, localized Update/Cancel/Edit choices
and account disclosures. The editor uses `EditAddressProfileDialogControllerImpl`,
`AddressEditorController` and `AddressEditorView`, including country-dependent fields
and real validation. Cocoa parents use the existing constrained WebContents modal
route because `TabDialogManager` requires a Views host widget. Ordinary Views
browsers retain that route. Page hiding/navigation/detachment cancels unfinished
editing; old controllers cannot clear a replacement request.

New account-address saves,
migration/Home-Work merge, sign-in promotion and remaining payment modes still
have explicit capability boundaries. No functional browser tests were run here.

## Presentation boundaries

The native controls use a 400×180 initial sheet, AppKit layout and system sheet
motion. Card copy comes from the actual controller, which distinguishes card-only
and card+CVC saves. Localization, long translated text, focus restoration and
integrated presentation need validation beyond source checks.

Terminal state, delayed delivery, generation invalidation and physical-owner
checks prevent stale results from consuming replacement requests.

## Scope and integration contract

- `SupportsLocalCard` accepts actual local-save state without requested name,
  expiration editing, upload or legal-message UI. Manage/CVC-only/upload and
  continuation/confirmation modes are not claimed. `SupportsLocalAddress`
  requires the actual typed `kSave` mode and excludes account profiles, migration
  and Home/Work/name/email merge prompts. Cancellation semantics alone cannot
  distinguish merge from ordinary save. The exact type uses the reviewed
  read-only `GetSaveAddressBubbleType()` upstream accessor; this source needs
  that integration patch, not a local substitute declaration.
  These non-consuming predicates are caller
  capabilities, not disabled full-browser feature policy.
- The factory requires the supplied WebContents' actual TabInterface to belong
  to the supplied Browser/Profile. The supplied host must contain that exact
  native content view in that Browser's supplied NSWindow. Non-tab guest/inner
  WebContents adaptation is not implemented; ordinary subframes share their
  page WebContents.
- A factory returns a genuine pending session; presentation is queued using
  the real UI task runner and all sheet results are subsequently deferred.
  Chromium's synchronous `DoShowBubble` must install its returned bubble pointer
  before queued presentation/completion. No factory invokes an engine result
  inline, including detached-window failure.
- Sessions own their lifetime and delete only after callback delivery. The
  application keeps `GetWeakPtr()` for cancellation, not an owning raw pointer.
  **Call `PageHostWillDetach()` before every page reparent/profile/window swap
  and host teardown**, even a remove/reinsert into the same physical window.
  This request is terminal; a new association requires a new request. Physical
  window checks alone cannot detect same-window removal/reinsertion.
- The address variant owns the transferred controller. The card variant uses
  its real weak lifetime token and weak close callback, verifies userdata
  identity, and never recreates a controller from another active tab.
- Both variants check the parent's current bubble pointer. A result from an old
  sheet cannot consume or clear a replacement request. After a save callback,
  the pointer/lifetime is checked again before delivering close bookkeeping.
  If upstream `HideBubble` reenters during an already accepted card Save,
  `Hide` consumes the weak Accepted-close callback while this session still
  owns the view, before upstream clears it. This prevents leaving LocalSave
  with a consumed save callback; subsequent replacement setup sees finalized
  old state. The callback is moved before invocation to prevent recursion.
  If the parent already uninstalled this bubble, old close notification is
  skipped instead of clearing its replacement.
- A pending session reports presentation only after its sheet is attached to
  the expected visible, non-miniaturized parent and is itself visible. A
  request that never appears has a neutral not-presented result: card/IBAN
  managers do not add strikes, and address imports use `kAutoDeclined` without
  treating it as a user refusal. Request/view generations prevent an old
  result from clearing a newer request on the same controller.
- User Save, explicit Decline (including Escape), and
  interruption after presentation are distinct. Interrupted visible address UI only closes bookkeeping;
  the real backend retains its pending decision and reports Ignored on page
  destruction. Interrupted card UI uses NotInteracted when it still owns the
  current bubble. No interruption calls Save or fabricates a user decline.
- `Hide()` blocks further user actions and defers completion. Page destruction
  and committed primary cross-document navigation interrupt. Parent close,
  weak-window loss, an unrelated attached sheet and stale association also
  interrupt. Closing an unrelated NSWindow cannot affect this request.

The source-owned handler registers through
`ScopedUnownedUserData<AutofillBubbleHandler>`. The concrete native host must
install it before page clients are created and return that same instance from
the Browser window getter. It supplies exact page-host/window identity, blocks
requests during detachment, and revalidates the association after host callbacks.
The host must balance `PageHostWillDetach`/`PageHostDidAttach` and destroy the
handler before Browser/Profile services.

The capability patch checks unsupported modes at their real producers and
again during direct dispatch/reshow. Unavailable UI does not synthesize a
decline, enrollment, reauthentication preference change or wallet disclosure
acknowledgment. The BubbleManager preserves queue progress across refusal,
controller/page destruction, replacement and callback-induced tab deactivation.
Ordinary Views behavior remains supported, including the wallet page-action
icon after successful presentation. The product buildflag excludes Autofill AI
and AtMemory construction/direct presentation before Browser attachment; this
is a scoped exclusion, not proof that the entire engine contains no AI.

The address acceptance continuation needs a native-window capability guard:
`AddressBubblesController::MaybeShowIOSDektopAddressPromo` unconditionally used
`AsBrowserView()->browser()` after the generic lookup. The reviewed overlay
checks for the actual Views presentation capability before that optional
desktop promotion. The [lookup regressions](../NativeWindowLookup/README.md)
include the real local-save controller reaching this continuation. This does
not bypass the actual save controller or establish saved-data persistence.

## Executable AppKit checks

```sh
bash tests/NativeAutofillSave/run.sh
```

Build output stays in `build/tests/native-autofill-save/`. The suite creates
real offscreen AppKit windows, custom sheets and native buttons. It exercises
deferred start/results, Save/Decline/Return/Escape, duplicate calls, external
sheet dismissal, existing-sheet conflict, queued and displayed parent close,
actual page reparenting, same-window explicit invalidation, stale queued Save,
validator reentry, callback reentry/replacement, unrelated-window filtering and
request retention/release. **75 assertions across eight groups pass.** The
presentation-outcome suite adds **33 checks across seven groups**, including
hidden/minimized parents, cancellation, validator reentry and owner release.
Both suites pass through the repository runner. No browser/profile or real
payment data is accessed.

## Actual Chromium interface check

```sh
python3 tests/NativeAutofillSave/check-chromium.py /path/to/chromium/src
python3 tests/NativeAutofillSave/check-upstream.py /path/to/chromium/src
```

The checker reuses the bounded literal flags reader in NativeLocationBar and
generated `native_components`, `autofill_save_sessions` and `session_tests`
targets; it checks the presenter, production session, handler and regression sources with
their respective settings. Missing targets are an error before compilation.
The explicit `--pre-integration` option checks only compatibility with older
`libcef_static` / `unit_tests` settings and labels that limited result separately.
Logs, command records and caches stay in the ignored test build directory. The
checker performs no generation, GN, Ninja, source-checkout writes, downloads or
synthetic-header substitution.

The upstream checker resolves each modified Autofill `.cc` file's actual CXX
object owner from generated Ninja files. It retains the generated compiler
flags, module dependencies and private module name, and verifies the applied
source hashes against the manifest. It records source, compiler, target flags,
toolchain and overlay identities. Missing or ambiguous target ownership fails
before compilation. This checks the complete changed translation units,
including the modified existing Chromium test sources.

## Real controller regression target

The shared production source set
`//cef/libcef/browser/parc_native:autofill_save_sessions` is used by the engine
and `//cef/tests/parc_native_autofill:session_tests`. The latter is included in
Chromium's existing `//chrome/test:unit_tests` for macOS CEF builds. This avoids
compiling a second copy of the session or linking the whole CEF implementation
into the tests. UI thread checks use the same real Chromium browser thread.

Seven cases use `BrowserWithTestWindowTest`, actual Browser/Tab/WebContents,
both real save controllers, scoped handler registration and real AppKit buttons:

- Synchronous bubble registration before deferred presentation/result delivery.
- Accepted card save with reentrant `HideBubble` finalizing real controller state.
- A replacement request surviving the old session's completion.
- Page destruction cancelling a queued card acceptance and invalidating its controller.
- Address save through the transferred, owned controller.
- Explicit address decline distinguished from interruption and page destruction.
- Exact local-save capability excluding migration and merge modes.

The fixture uses an in-memory test personal-data manager, offscreen windows and
`about:blank`; it does not access real payment data or Keychain. It is a test-only
handler for these factories. Additional sources exercise the real native handler
and producer/controller behavior: eleven capability cases parameterized over
BubbleManager enabled/disabled, six manager cases, five queue-reentry cases and
two product-policy cases. Modified upstream wallet-controller tests include
destruction during handler return/action notification and closing before
presentation observation. These tests use the real controllers and managers;
none of the Chromium cases has been linked or executed yet.

Passing AppKit tests proves presenter behavior. Passing pinned syntax checks
proves source interfaces, **not linked Chromium controller execution or saved
data**. Synthetic-profile persistence, execution of the BubbleManager feature-state
matrix, navigation/transfer and address-replacement coverage remain open. Production routing is installed by the native host; component checks alone do
not establish persisted data or browser-level acceptance.

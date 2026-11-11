# Native autofill and password presentation

`autofill_save_presenter` is a custom AppKit sheet and retained request. It uses
a supplied page view and NSWindow, never NSAlert, an app-modal fallback, the
frontmost window, or a fabricated successful bubble. `autofill_save_session`
implements real `AutofillBubbleBase` factories using pinned Chromium156's
actual local-save controllers and the transferred `UpdateAddressBubbleController`.
`NativeAutofillBubbleHandler` supplies these presentations through the real
Browser-owned interface. The canonical native host registers the handler and
payment-entry owner before page clients are created. Additional native sessions
present address-account and payment modes through their actual controllers.
Producer and continuation guards preserve neutral refusal for unavailable UI.

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
surface was added.

## Address update and editing

The native update session owns the real `UpdateAddressProfileView` and transferred
controller, preserving actual old/new values, localized Update/Cancel/Edit choices
and account disclosures. The editor uses `EditAddressProfileDialogControllerImpl`,
`AddressEditorController` and `AddressEditorView`, including country-dependent fields
and real validation. Cocoa parents use the existing constrained WebContents modal
route because `TabDialogManager` requires a Views host widget. Ordinary Views
browsers retain that route. Page hiding/navigation/detachment cancels unfinished
editing; old controllers cannot clear a replacement request.

Account-address save, migration and Home/Work/name/email merge use the actual
save-address view and controller when a real primary account and account-address
storage are eligible. The session revalidates that account before acting.
Sign-in promotion uses its genuine controller when DICE support and the current
Profile permit it; the presentation does not create an account or grant eligibility.

## Payment modes

`NativeCardSaveSession` handles local/CVC saves, upload consent, in-progress and
completed uploads, and Manage Cards. It preserves legal links and forwards
accepted details to the real save controller. The view accepts either a requested
name or expiration correction; simultaneous requests for both are refused.

`NativeIbanSession` handles local/upload save, nickname editing, management and
completion. `NativePaymentConsentSession` owns virtual-card enrollment and
mandatory-reauthentication opt-in/confirmation. Information sessions show offers
and filled-card details; tab-owned sessions handle omnibox suggestions, eligible
returning-payment-user prompts and wallet reminders.

The native host publishes current payment actions to the browser sidebar and
menu. Actions revalidate the same page, request and controller before reshowing
UI. Saved feedback is acknowledged only after it reaches the visible control.
Upstream account, feature, policy and backend eligibility remain authoritative.

## Presentation boundaries

The native controls use a 400×180 initial sheet, AppKit layout and system sheet
motion. Card copy comes from the actual controller, which distinguishes card-only
and card+CVC saves. The additional address and payment sessions retain their
controller-provided text and actual view-specific controls.

Terminal state, delayed delivery, generation invalidation and physical-owner
checks prevent stale results from consuming replacement requests.

## Scope and integration contract

- `SupportsLocalCard` selects the simple local-save sheet; other admitted card
  modes use `NativeCardSaveSession`. `SupportsLocalAddress` selects ordinary
  local saves, while `SupportsAccountAddress` admits eligible account saves,
  migration and merge. The exact typed mode comes from the integrated
  `GetSaveAddressBubbleType()` accessor. These predicates route real requests
  without changing the Profile's upstream feature or account policy.
- The factory requires the supplied WebContents' actual TabInterface to belong
  to the supplied Browser/Profile. The supplied host must contain that exact
  native content view in that Browser's supplied NSWindow. Non-tab guest/inner
  WebContents are outside this tab-owned presentation route; ordinary subframes
  share their page WebContents.
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

The integrated address acceptance continuation checks actual Views presentation
capability before optional desktop promotion. Native address saving therefore
keeps its real controller without entering a Views-only promotion path. The [lookup regressions](../NativeWindowLookup/README.md)
include the real local-save controller reaching this continuation.

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
request retention/release. The presentation-outcome suite covers hidden/minimized
parents, cancellation, validator reentry and owner release. No browser/Profile
or real payment data is accessed.

## Actual Chromium interface check

```sh
python3 tests/NativeAutofillSave/check-chromium.py /path/to/chromium/src
python3 tests/NativeAutofillSave/check-upstream.py /path/to/chromium/src
```

The checker reuses the bounded literal flags reader in NativeLocationBar and
the actual ObjC++ rule, with ARC and `-Werror`. It requires the
generated `native_components`, `autofill_save_sessions` and `session_tests`
targets; it checks the presenter, production session, handler and regression sources with
their respective settings. Missing targets are an error before compilation.
The checker uses `//parc/native` and `//parc/tests/parc_native_autofill` targets;
it requires the direct engine graph rather than the retired CEF target flags.
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
`//parc/native:autofill_save_sessions` is used by the engine
and `//parc/tests/parc_native_autofill:session_tests`. The latter is included in
Chromium's existing `//chrome/test:unit_tests` for macOS Parc builds. This avoids
compiling a second copy of the session or linking the whole browser implementation
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
the configured Chromium target supplies their execution environment.

Follow [AGENTS.md](../../AGENTS.md) when selecting checks. The AppKit runner
covers its presenter and lifecycle components; the Chromium target owns real
controller/manager regressions.

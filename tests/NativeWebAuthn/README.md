# Native WebAuthn request presentation

This source-owned adapter retains Chromium's genuine scheduler, request delegate, dialog model/sheets, transport dispatch and Apple AuthenticationServices implementation. It supplies the exact app-owned NSWindow and real modal/auxiliary-window ownership. No hidden BrowserView, credential store or fabricated authentication result is involved.

The current Chromium adaptation changes only registered native pages. It preserves the default Chrome factory and PWA exclusion, replaces the Views-parent assumption with an actual native child window, and uses the genuine WebContents modal manager and security-dialog tracker. The context binds exact request/document/page/Browser/Profile/window identity; detachment cannot revive an old request. Callback-registration and modal-manager host-iteration boundaries defer real cancellation/removal where synchronous deletion would invalidate the caller.

`request_unittest.mm` uses the real scheduler, request delegate, model, Views sheet, Browser/Profile/TabInterface and modal manager. Its cases cover native ownership, genuine cancellation, detach/reattach, pre-registration invalidation, duplicate request refusal, OS-window binding, competing security reservations, navigation, window close, construction reentry and real modal-host change. Credential success and OS authorization are not mocked or asserted.

Verification is currently **isolated compatibility compilation only** with the pinned Chromium compiler/generated flags; the cases have not been linked or executed. Production GN registration is source-connected; actual generated target/header validation, linking and runtime execution remain integration gates. Run `python3 tests/NativeWebAuthn/check-chromium.py /absolute/path/to/chromium/src` only after applying the complete reviewed overlay and generating its actual targets. The checker rejects an unapplied/stale source cohort or missing source object membership before compilation. It does not generate/build/link or execute tests, and has no compatibility mode.

The completion source adds ambient sign-in, standalone `WINDOW` recovery and non-request settings/change-PIN ownership. Ambient uses the genuine Chromium credential rows, icons, labels, sign-in controls and callbacks, anchored to the exact Cocoa page. Each selection revalidates the request/document/profile/window and the original model's passive-autofill step. Backgrounding hides the native bubble; controller/model destruction disconnects it.

Recovery keeps the original Chromium Browser and WebContents, original-profile cookies, account index, recovery URL, response/origin checks, RAPT and reset observers, and original model events. The registered Parc profile route creates the actual native popup. Its presentation lease binds the original caller and releases before the subsequent PIN dialog acquires its security reservation. Deferred window teardown avoids destruction during model/navigation notification. Settings starts a distinct native generation only from the genuine `ChangePinControllerImpl::StartChangePin` action; PIN success still comes only from `EnclaveManager::ChangePIN`.

Conditional/autofill credentials, another-device choices and inline QR already use the genuine `PasswordAutofillManager` and `ChromeWebAuthnCredentialsDelegate`. `CanShowRootPopup` and `PopupBaseView::DoShow` explicitly support a Cocoa parent without a Views BrowserWindow. No replacement popup or fabricated passkey result is introduced.

Compiler and component receipts apply only to their recorded source. Ambient and
recovery presentation, keyboard/accessibility and real authenticator interaction
need separate authorized validation; a source change alone does not establish
those results.

The integrated v44 composition preserves the current external-protocol install,
attachment and cancellation hooks, with a separate weak-self check after
WebAuthn cancellation. Seven combined compatibility units pass against the full
143-mapping/123-patch-target cohort. The running baseline was not modified.

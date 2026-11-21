# Native WebAuthn request presentation

This source-owned adapter retains Chromium's genuine scheduler, request delegate, dialog model/sheets, transport dispatch and Apple AuthenticationServices implementation. It supplies the exact app-owned NSWindow and real modal/auxiliary-window ownership. No hidden BrowserView, credential store or fabricated authentication result is involved.

The current Chromium adaptation changes only registered native pages. It preserves the default Chrome factory and PWA exclusion, replaces the Views-parent assumption with an actual native child window, and uses the genuine WebContents modal manager and security-dialog tracker. The context binds exact request/document/page/Browser/Profile/window identity; detachment cannot revive an old request. Callback-registration and modal-manager host-iteration boundaries defer real cancellation/removal where synchronous deletion would invalidate the caller.

`request_unittest.mm` uses the real scheduler, request delegate, model, Views sheet, Browser/Profile/TabInterface and modal manager. Its cases cover native ownership, genuine cancellation, detach/reattach, pre-registration invalidation, duplicate request refusal, OS-window binding, competing security reservations, navigation, window close, construction reentry and real modal-host change. Credential success and OS authorization are not mocked or asserted.

The production page delegate installs the WebAuthn context when it creates a
page, admits presentation on exact native attachment, and cancels on detachment.
Parc's browser client creates each request through Chromium's scheduler and
tells that context about it. The overlay connects Chromium's dialog factory,
platform-window selection and request callbacks to the same context. Its GN target is linked into
the Chromium native route; the request tests join Chromium's unit-test target.

Ambient sign-in, standalone `WINDOW` recovery and non-request settings/change-PIN
presentation use the same native ownership. Ambient uses the genuine Chromium
credential rows, icons, labels, sign-in controls and callbacks, anchored to the
exact Cocoa page. Each selection revalidates the request/document/profile/window
and the original model's passive-autofill step. Backgrounding hides the native
bubble; controller/model destruction disconnects it.

Recovery keeps the original Chromium Browser and WebContents, original-profile cookies, account index, recovery URL, response/origin checks, RAPT and reset observers, and original model events. The registered Parc profile route creates the actual native popup. Its presentation lease binds the original caller and releases before the subsequent PIN dialog acquires its security reservation. Deferred window teardown avoids destruction during model/navigation notification. Settings starts a distinct native generation only from the genuine `ChangePinControllerImpl::StartChangePin` action; PIN success still comes only from `EnclaveManager::ChangePIN`.

Conditional/autofill credentials, another-device choices and inline QR already use the genuine `PasswordAutofillManager` and `ChromeWebAuthnCredentialsDelegate`. `CanShowRootPopup` and `PopupBaseView::DoShow` explicitly support a Cocoa parent without a Views BrowserWindow. No replacement popup or fabricated passkey result is introduced.

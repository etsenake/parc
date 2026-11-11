# Native extension consent checks

Native consent now also handles enterprise extension requests and already-pending
requests. A request uses the actual prompt title, permission list and localized
justification labels, permits up to Chromium's 280 UTF-16 code units, and returns
the text in the real DoneCallbackPayload. A pending request has only Close.
Cancellation/interruption discards the text; acceptance still revalidates the
original document/profile/window and exclusive reservation before delivery.
The enterprise controller owns the eventual request/policy result. This does not
install an extension or substitute ordinary acceptance for parent approval.

Enterprise justification extends the same native consent presentation with
Chromium's actual controller and limits. Parent approval uses its own upstream
policy; ordinary acceptance cannot substitute for it.


`install_browsertest.mm` contains thirteen genuine Chromium Browser/Profile/ExtensionInstallPrompt cases. The overlay registers `//parc/tests/parc_native_extensions:install_browser_tests` in Chrome's macOS `browser_tests`; run filter `NativeExtensionInstallTest.*` only after the reviewed source overlay is applied and built. Execution requires a valid Chromium process/context. They exercise consent outcomes, not a fabricated grant/installer implementation.

The cases exercise prompt decisions; Chromium's installer and policy services
own the resulting install. [Extensions](../../docs/extensions.md) describes
ordinary, enterprise and parent-approval behavior.

## Native consent contract

Parc captures the actual Browser/Profile/window/page before icon loading and
uses current Chromium's real InstallPromptData, permission messages, withholding
policy and once-only result callback. It preserves the upstream input delay and
PiP overlap protection. Ownerless/ambiguous native requests abort. Navigation,
selection change, detach, extension replacement and shutdown invalidate consent;
a competing reservation acquired during completion also invalidates acceptance.
Installer results present no native surface; only a non-bubble app opens the
Apps page. No grant or successful installation is manufactured. Chromium's
prompt header owns the consent-binding interface; a narrow capture hook routes
to Parc's Browser-owned service without injecting another Chromium header.

The production/test targets share the implementation. Compiler checks validate
actual generated flags and source membership.

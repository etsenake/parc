# Native extension consent checks

Current implementation direction: functional browser tests are not completion
gates and are not being run. PiP is accepted as done. Historical test instructions
and results below are retained as evidence, not an active task list.

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


`install_browsertest.mm` contains thirteen genuine Chromium Browser/Profile/ExtensionInstallPrompt cases. The reviewed v35 overlay registers `//cef/tests/parc_native_extensions:install_browser_tests` in Chrome's macOS `browser_tests`; run filter `NativeExtensionInstallTest.*` only after the reviewed source overlay is applied and built. Six integrated syntax checks pass with existing pinned generated target flags, but these cases have not yet been linked or executed. They exercise consent outcomes, not a fabricated grant/installer implementation.

Acceptance still needs real Web Store/CRX download/policy/install behavior, optional grant persistence, native factory ownership, PiP overlap timing, extension restart/unload and actual post-result presentation. Do not infer installer or supervised-parent outcomes from prompt component tests.

Current EXT11 source, helper evidence, independent review and check boundaries are documented in [Extensions](../../docs/extensions.md). The historical acceptance narrative below does not reopen completed P0 rows or authorize browser tests.

## Native consent contract

Parc captures the actual Browser/Profile/window/page before icon loading and
uses current Chromium's real InstallPromptData, permission messages, withholding
policy and once-only result callback. It preserves the upstream input delay and
PiP overlap protection. Ownerless/ambiguous native requests abort. Navigation,
selection change, detach, extension replacement and shutdown invalidate consent;
a competing reservation acquired during completion also invalidates acceptance.
Installer results present no native surface; only a non-bubble app opens the
Apps page. No grant or successful installation is manufactured.

The production/test targets share the implementation. Compiler checks validate
actual generated flags and source membership; linked test execution and real
installation outcomes need separate receipts.

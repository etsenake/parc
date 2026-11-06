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

ownership. Enterprise justification and its limit are explicit adaptations to the
recovered. They extend the same native consent presentation rather than invoking
a BrowserView. Genuine supervised-parent approval and original presentation
details remain implementation work.


`install_browsertest.mm` contains thirteen genuine Chromium Browser/Profile/ExtensionInstallPrompt cases. The reviewed v35 overlay registers `//cef/tests/parc_native_extensions:install_browser_tests` in Chrome's macOS `browser_tests`; run filter `NativeExtensionInstallTest.*` only after the reviewed source overlay is applied and built. Six integrated syntax checks pass with existing pinned generated target flags, but these cases have not yet been linked or executed. They exercise consent outcomes, not a fabricated grant/installer implementation.

Acceptance still needs real Web Store/CRX download/policy/install behavior, optional grant persistence, native factory ownership, PiP overlap timing, extension restart/unload and actual post-result presentation. Unpacked directory selection and enterprise/parent approval are separate unfinished stages.

Current EXT11 source, helper evidence, independent review and check boundaries are documented in [Extensions](../../docs/extensions.md). The historical acceptance narrative below does not reopen completed P0 rows or authorize browser tests.

## Recovered contract and current-engine adaptation

`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`.
REA resolves Browser consent at `0x68b9528`, context prompt/info/messages and
Boolean completion at `0x68c58f8`, and context-owned extension service at
`0x68c866c`. Installer entrypoints `0x68c8f40` and `0x68c90a0` instead complete
`Dialogs.ExtensionPromptView` contains title, permissions and icon. This proves
separate consent and install-outcome routes, not original button policy,
presentation-parent selection, timing or every result case. Retained REA records
are `ev_3d2a789106b5ce0b87c4e677b082e64842238c097cf2454c476b0e7ac49eb183`,
`ev_5eb4d3b96264d44004425845e20438ff50b06511190d6c5d4dd68163d888e6cf`
and `ev_64cae3aaf165848c9a8480ab6e4060dc9436a81a35f75f2b29bf12629749dcb2`.

Parc captures the actual Browser/Profile/window/page before icon loading and
uses current Chromium's real InstallPromptData, permission messages, withholding
policy and once-only result callback. It preserves the upstream input delay and
PiP overlap protection. Ownerless/ambiguous native requests abort. Navigation,
selection change, detach, extension replacement and shutdown invalidate consent;
a competing reservation acquired during completion also invalidates acceptance.
Installer results present no native surface; only a non-bubble app opens the
Apps page. No grant or successful installation is manufactured.

The shared native production/test targets are source-connected. Read-only replay
passes for 99 mapped files and 98 patched upstream targets. Actual new-target
generation/header checks, linking and browser execution await the full build;
compatibility compiler flags do not prove those gates.

# Native HTTP and proxy authentication


The handler binds the original document, Browser, Profile, native page and NSWindow. Native detach closes the attachment gate before cancellation. Credentials are revalidated after modal dismissal and security-reservation release, then passed to the real LoginHandler on a non-nestable task. The additive `CanSetAuth()` guard also covers matching-credential propagation from another handler. The genuine WebContentsModalDialogManager owns native-modal bookkeeping and renderer blocking. Its adapter closes synchronously when the manager requests closure; host-change notifications defer list mutation.


`login_unittest.mm` contains **12 genuine Browser/Profile/LoginHandler/WebContentsModalDialogManager cases**: submission, proxy identity/warning, handler destruction, detach/reattach, navigation, release-time competing security UI, existing lease, concurrent request refusal, propagated-credential guard, manager close, completion reentry and hidden-window refusal. These compile with the real generated `chrome/test:unit_tests` ObjC++ rule. **They have not been linked or executed.** No successful HTTP exchange or credential persistence is claimed from compilation.

After generation, `python3 tests/NativeHTTPAuth/check-chromium.py /path/to/chromium/src` validates the entire applied overlay against repository input/output hashes and source-lock identities, then checks exact generated object membership and each source's own target flags before compiling. It rejects stale applied snapshots, accepts no VFS/include override, and invokes neither GN nor Ninja. The real-controller test must belong to its own `parc_native_http_auth:unit_tests` source set; the top-level Chrome test flags are not accepted as its owner. Six isolated compatibility checks pass with the complete v38 source: the new native service borrows existing native-extensions flags and the test borrows top-level unit-test flags pending generation; the other four units use their existing owners' flags. No synthetic generated headers or relaxed warning policy were used.

The production and controller-test targets are registered in the reviewed overlay.
The tests need a CEF-compatible runner with actual process/context initialization;
registration or compilation does not establish execution. Old candidate receipts
must not be used to describe current release delivery.

The remaining runtime gates are actual origin 401 and proxy 407 challenges, wrong-password retry, main-frame LoginTabHelper versus subresource challenges, extension `onAuthRequired`, managed proxy policy, saved HTTP credential autofill/submission/restart, transfer/navigation/quit with pending challenges, concurrent contexts and real-page responsiveness. A hidden/background owner or concurrent browser-security sheet currently cancels that particular prompt; queuing/background presentation is unfinished. Ownerless `CefURLRequest` authentication still has no native owner and is not redirected to an arbitrary window. WebAuthn, certificates and external protocols are separate P0-19 work.


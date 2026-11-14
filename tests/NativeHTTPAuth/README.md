# Native HTTP and proxy authentication

Parc supplies a native LoginHandler view for its exact registered WebContents. Parc subclasses Chromium's coordinator and tab helper; extension interception, enterprise proxy decisions, credential matching, HttpAuthManager and actual network continuation remain in use. This is source-owned AppKit presentation.

The handler binds the original document, Browser, Profile, native page and NSWindow. Native detach closes the attachment gate before cancellation. Credentials are revalidated after modal dismissal and security-reservation release, then passed to the real LoginHandler on a non-nestable task. The credential-validation hook in Chromium’s handler also covers matching-credential propagation from another handler. The genuine WebContentsModalDialogManager owns native-modal bookkeeping and renderer blocking. Its adapter closes synchronously when the manager requests closure; host-change notifications defer list mutation.

`bash tests/NativeHTTPAuth/run.sh` executes native AppKit presenter checks using disposable offscreen test windows. The suite covers **54 assertions**: supplied-window attachment, the Parc dialog's sign-in text, labelled rounded fields and controls (WEB15, [web-interactions.md](../../docs/web-interactions.md#dialogs-authentication-certificates-and-permissions--web15)), secure password field, proxy title, Return/Escape/keypad Enter from any focus, input-method composition, late autofill, cancellation, invalid owners, cleared fields, reentrant validation and replacement.

`login_unittest.mm` contains **13 genuine Browser/Profile/LoginHandler/WebContentsModalDialogManager cases**: submission, proxy identity/warning, handler destruction, detach/reattach, navigation, release-time competing security UI, existing lease, concurrent request refusal, propagated-credential guard, manager close, completion reentry, hidden-window refusal and invalid-host restoration before deferred cancellation.

After generation, `python3 tests/NativeHTTPAuth/check-chromium.py /path/to/chromium/src` validates the entire applied overlay against repository input/output hashes and source-lock identities, then checks exact generated object membership and each source's own target flags before compiling. It rejects stale applied snapshots, accepts no VFS/include override, and invokes neither GN nor Ninja. The real-controller test must belong to its own `parc_native_http_auth:unit_tests` source set; the top-level Chrome test flags are not accepted as its owner.

The production and controller-test targets are registered in the reviewed overlay.
Executing the Chrome controller fixture requires a valid Chromium process/context.
The [native runtime harness](../NativeRuntime/README.md) separately drives the
production handler's submit, cancel and detach paths with synthetic challenges.

## Admission and cancellation

Hidden/background pages and requests competing with an existing browser-security
sheet cancel that prompt. They are not queued for later presentation. The
original document and visible selected page must retain ownership through
submission; returning to the same hierarchy does not revive a cancelled request.

An authentication request without a native page/window owner is not redirected
to another window. WebAuthn, certificates and external protocols use their own
services. Docked main DevTools uses its explicit
[auxiliary-page lease](../NativeDevTools/Auxiliary.md) for authentication.

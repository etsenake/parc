# Native server-certificate details

This adapter routes the generic Chromium `ShowCertificateViewer` call for an installed, attached native page to Apple's genuine `SFCertificatePanel`. It uses `SecPolicyCreateBasicX509` and `beginSheetForWindow:...showGroup:YES`. The request belongs to the exact WebContents, primary document, visible navigation entry/certificate chain, TabInterface, Browser/Profile, NSWindow and native page. A stale or detached native request is refused; it cannot fall through to an unrelated Views window. Ordinary pages without this installed route retain the existing WebUI viewer.

This is certificate inspection only. It does not replace `SSLErrorNavigationThrottle`, the Chrome security blocking-page factory, SSL policy or interstitial commands. It does not grant trust, accept a network certificate, import a certificate, write a Keychain identity or fabricate a Proceed result. The separate macOS client-auth Details route still uses its real selector Widget/Mojo interface unchanged. Native page-info UI is not added by this slice.


The request holds the shared native security reservation, rejects competing prompts, and retires on page navigation/destruction, detach or parent close. Detach changes its epoch before any callback; reattachment cannot revive it. The presenter defers opening, checks the actual parent/page before and after the OS call, and retains its modal delegate until the actual OS callback. On this macOS version, the allocated panel is a factory and `beginSheet` creates a separate attached `SFCertificatePanel`; cancellation targets that exact sheet. A completed begin frame never adopts or hides a replacement sheet opened by a nested callback. The completion is dismissal only, once, with no SSL decision attached.

Run the standalone native suite from the repository:

```sh
bash tests/NativeCertificateViewer/run.sh
```

It compiles and opens genuine OS certificate sheets over synthetic AppKit pages, using only the public certificate in `fixture.pem`. The current suite executes **34 assertions**, including exact parent/visibility, BasicX509 policy, deferred cancellation, invalid page/hidden parent, once-only completion, parent close, delegate lifetime, a replacement sheet shown before the old begin call returns, and cancellation that releases the external owner during begin before sheet capture. The nested test temporarily intercepts the real `SFCertificatePanel` begin method in its own test process; it still presents and ends real OS panels, and restores the original method afterward. The in-flight cancellation case also checks retained callback ownership before the real OS completion. No trust/settings controls are exercised.

`fixture.pem` is the public synthetic `net/data/ssl/certificates/root_ca_cert.pem` from pinned Chromium `d0c02bfad08ec92a6ffcf989e53cd995e6381a4c` (Chromium BSD-style license). It contains no private key or user identity. The runner converts it into an ignored build-directory DER file; it does not install it.

The thirteen `viewer_unittest.mm` cases use genuine Browser/Profile/TabInterface/WebContents, the generic viewer entry and `SSLErrorControllerClient`, the real native security lease and OS sheet. They cover exact owner/certificate checks, duplicate calls, detach/reattach, navigation/destruction, competing/reentrant reservations, parent close and preservation of stock dispatch. The test window only supplies the native NSWindow. These cases currently **compile but have not been linked or executed**. The current CEF-enabled Chrome test-main/context limitation remains; passing syntax is not controller runtime coverage.

After the complete overlay is applied and its actual targets generated, run:

```sh
python3 tests/NativeCertificateViewer/check-chromium.py /absolute/path/to/chromium/src
```

The checker verifies the entire overlay cohort, source lock, generated object membership and exact compiler rules before checking the two production ObjC++ units, platform integration, generic Chromium viewer and controller test source. It has no compatibility fallback and does not generate, build, link, execute tests or write into the checkout. The private candidate was checked with five pinned-compiler VFS compatibility commands; new source-set flags are pending real generation.

Integration maps the new typed header to `chrome/browser/native_server_certificate_viewer.h`, the native sources into `cef/libcef/browser/parc_native`, and the controller test into `cef/tests/parc_native_certificate_viewer`. The shared `native_certificate_viewer` target owns both production implementations and SecurityInterface linking; `libcef_static` and the test source set depend on it. Only `chrome/test:unit_tests` under macOS plus `enable_cef` imports the test source set. The test target does not depend on `libcef_static`.


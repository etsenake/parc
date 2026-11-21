# Native client-certificate selection

This service keeps Chromium's actual `SSLClientCertificateSelector`, certificate table/details action, filtered identity list, SSL auth observer and private-key acquisition. It attaches the genuine dialog's NSWindow to the supplied native browser window through a real WebContents modal manager. It does not instantiate a browser BrowserView or replace the certificate list.

Parc's content browser client does not override certificate selection. Chrome enterprise policy, automatic selection and the empty-list outcome run before a one-call hook hands the request to Parc; installed pages get the page-owned native presentation and any other page Chromium's Views selector. The selector's authorization check stays a small patch: it must refuse a stale choice before Chromium shares it with other requests for the same host. Actual macOS private-key acquisition and later OS signing authorization remain unchanged. Explicit user cancellation retains Chrome's null-certificate result; interrupted ownership aborts the original request.

The source binds the real page/document/Profile/Browser/window and requires live native attachment, activation, visible parent and sole security reservation. It validates before key acquisition, after key completion before same-challenge broadcast, and before deferred network continuation. Native widget close and pending key acquisition have separate lifetimes. Detach/navigation/parent close abort, and reservation release detects reentrant replacement. The original page's modal manager owns input blocking and list removal.

The current Mac Views parent resolver only understands Views-owned NSWindows. A narrow NativeWidgetMac subclass for this auxiliary dialog lets the real native modal manager and exact AppKit parent provide that relationship. This adapts the current engine to the app-owned window.

`selector_unittest.mm` has 14 genuine-controller cases: real native-parent/table/identity selection, explicit no-certificate cancellation, empty list, detached/hidden owners, exact-page detach, delayed key completion, invalid late-key same-challenge broadcast, competing reservation, release-time replacement, navigation, parent close, concurrent request refusal and delegate reentry destroying the page. The fixtures use synthetic certificate/key inputs, not the user's identities.

The integrated platform retains a weak-self check after HTTP cancellation and
another after certificate cancellation: either callback can destroy the owning
platform before the next service is accessed. This preserves the previous status,
authentication, file-dialog, permission and extension teardown paths. Review also
confirmed that Chromium's macOS native-window wrapper is weak, so later widget
destruction does not leave a dangling Objective-C window handle in the request.

Certificate-error UI, WebAuthn and external protocols use their own services.
[Web interactions](../../docs/web-interactions.md) describes their shared page and
window ownership.

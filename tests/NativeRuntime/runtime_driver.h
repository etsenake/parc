// Copyright 2026 Parc contributors. Test-only exports from libcef_test_support.
#pragma once
#import <AppKit/AppKit.h>
@class PCNativePage;
@class PCNativeBrowserWindow;
@protocol PCNativeVideoPiPWindow;
// One exact, nonempty document for initial navigation and actual renderer
// recovery. No external server, script-created document, or synthetic AX tree.
// Keep the data URL canonical across NSURL and GURL; never log its contents.
// Decoded HTML (line breaks below are for readability):
// <!doctype html><html lang="en"><meta charset="utf-8">
// <title>Parc native runtime</title><body><main>
// <h1>Native runtime fixture</h1><button>Ready</button>
// <label>Fixture<input></label></main></body></html>
static inline NSString* PCRuntimeDocumentURLString(void) {
  return @"data:text/"
         @"html;charset=utf-8;base64,PCFkb2N0eXBlIGh0bWw+"
         @"PGh0bWwgbGFuZz0iZW4iPjxt"
         @"ZXRhIGNoYXJzZXQ9InV0Zi04Ij48dGl0bGU+"
         @"UGFyYyBuYXRpdmUgcnVudGltZTwvdGl0bGU+PGJvZHk+"
         @"PG1haW4+PGgxPk5hdGl2ZSBydW50aW1lIGZpeHR1cmU8L2gxPjxidXR0b24+"
         @"UmVhZHk8L2J1dHRvbj48"
         @"bGFiZWw+Rml4dHVyZTxpbnB1dD48L2xhYmVsPjwvbWFpbj48L2JvZHk+PC9odG1sPg="
         @"=";
}
#ifdef __cplusplus
extern "C" {
#endif
#define PARC_RUNTIME_TEST_EXPORT __attribute__((visibility("default")))
typedef NS_ENUM(NSInteger, PCRuntimeHTTPAuthCase) {
  PCRuntimeHTTPAuthAccept,
  PCRuntimeHTTPAuthCancel,
  PCRuntimeHTTPAuthDetach,
};
// One asynchronous request at a time. Callback is copied and runs on CEF UI
// after the real LoginHandler and modal have been retired. No credentials are
// logged or returned. A synthetic challenge is not a real 401/407 exchange.
PARC_RUNTIME_TEST_EXPORT void parc_test_http_auth(
    PCNativePage* page,
    PCNativeBrowserWindow* binding,
    NSView* supplied_container,
    PCRuntimeHTTPAuthCase test_case,
    void (^finished)(BOOL passed, NSString* detail));
// Optional extension suite in the same real native application. Both supplied
// pages must be actual tabs in one disposable Profile/Browser. The callback
// changes the shell's selected page and synchronizes the real tab selection.
// The launcher owns the loopback origin; no network permission is fabricated.
PARC_RUNTIME_TEST_EXPORT void parc_test_extension_actions(
    PCNativePage* first,
    PCNativePage* second,
    PCNativeBrowserWindow* binding,
    NSString* loopback_document,
    BOOL (^select_page)(PCNativePage*),
    void (^finished)(BOOL passed, NSString* detail));
PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_extension_actions(void);
// Optional seven-case real video controller suite. The presenter query returns
// the application's actual current presenter; it must be side-effect-free.
// JS uses the same test activation and Promise semantics as ExecJs/EvalJs.
PARC_RUNTIME_TEST_EXPORT void parc_test_video_pip(
    PCNativePage* page,
    PCNativeBrowserWindow* binding,
    NSString* loopback_media,
    id<PCNativeVideoPiPWindow> (^presenter)(void),
    void (^finished)(BOOL passed, NSString* detail));
PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_video_pip(void);

// Cancels the test-owned handler; it never approves, closes or recreates pages.
PARC_RUNTIME_TEST_EXPORT void parc_test_cancel_http_auth(void);
#ifdef __cplusplus
}
#endif

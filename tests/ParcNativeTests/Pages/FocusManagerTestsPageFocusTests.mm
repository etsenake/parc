#import "FocusManagerTestsSupport.h"

using namespace FocusManagerTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_FocusManagerTestsPageFocusTests")))
@interface FocusManagerTestsPageFocusTests : ParcNativeTestCase
@end

@implementation FocusManagerTestsPageFocusTests

- (void)withPageHost:(void (^)(NSWindow*, PCNativePageHost*, NSView*, FocusManagerTestsFocusView*))check {
  NSWindow* window = Window();
  NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  FocusManagerTestsFocusView* renderer = [[FocusManagerTestsFocusView alloc] initWithFrame:page.bounds];
  [page addSubview:renderer];
  PCNativePageHost* host = Offscreen([PCNativePageHost hostWithContentView:page
                                                        observer:nil]);
  [window.contentView addSubview:host];
  check(window, host, page, renderer);
  [host invalidate];
  ParcNativeClose(window);
}

- (void)testDeferredPageFocusResolvesToTheRenderer {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusManagerTestsFocusView* renderer) {
    FocusManagerTestsFocusView* sentinel = View(window);
    [window makeFirstResponder:sentinel];
    PCNativeFocusManager* manager =
        Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
    PCNativeFocusRegistration* token = Register(manager, host, @"page");
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestAccepted,
          "manager requests the real deferred page host");
    Drain();
    Check(window.firstResponder == renderer,
          "page host focuses renderer through actual queued work");
    Check([manager requestFocusForKey:@"page"] ==
              PCNativeFocusRequestAlreadyFocused,
          "manager preserves renderer descendant focus");
    [token invalidate];
    [manager invalidate];
  }];
}

- (void)testManagersRejectAHostMovedToAnotherWindow {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusManagerTestsFocusView* ) {
    NSWindow* destination = Window();
    PCNativeFocusManager* manager =
        Offscreen([[PCNativeFocusManager alloc] initWithWindow:window]);
    PCNativeFocusRegistration* token = Register(manager, host, @"page");
    [host removeFromSuperview];
    [destination.contentView addSubview:host];
    Check([manager requestFocusForKey:@"page"] == PCNativeFocusRequestRejected,
          "old window manager rejects the live reparented host");
    [token invalidate];
    [manager invalidate];
    ParcNativeClose(destination);
  }];
}

- (void)testAControlCanSupersedeQueuedPageFocus {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusManagerTestsFocusView* renderer) {
    FocusManagerTestsFocusView* control = View(window);
    Check([window makeFirstResponder:host], "real page host queues native focus");
    Check([window makeFirstResponder:control], "native control supersedes queued page focus");
    Drain();
    Check(window.firstResponder == control && renderer.requests == 0,
          "deferred renderer request cannot steal from a later native control");
  }];
}

- (void)testQueuedFocusCannotMigrateToAnotherWindow {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusManagerTestsFocusView* renderer) {
    NSWindow* destination = Window();
    FocusManagerTestsFocusView* otherControl = View(destination);
    Check([window makeFirstResponder:host], "original page can request focus again");
    [host removeFromSuperview];
    [destination.contentView addSubview:host];
    Check([destination makeFirstResponder:otherControl], "destination window owns its own responder");
    Drain();
    Check(destination.firstResponder == otherControl && renderer.requests == 0,
          "queued work never retargets a moved page to its new physical window");
    ParcNativeClose(destination);
  }];
}

- (void)testAReplacementRendererNeedsAFreshRequest {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* page, FocusManagerTestsFocusView* renderer) {
    FocusManagerTestsFocusView* control = View(window);
    Check([window makeFirstResponder:control], "original window returns to native control");
    Check([window makeFirstResponder:host], "page accepts another explicit request");
    [renderer removeFromSuperview];
    FocusManagerTestsFocusView* replacement = [[FocusManagerTestsFocusView alloc] initWithFrame:page.bounds];
    [page addSubview:replacement];
    Drain();
    Check(replacement.requests == 0, "replacement renderer cannot inherit a queued focus request");
    Check([window makeFirstResponder:control], "control remains available after renderer replacement");
    Check([window makeFirstResponder:host], "fresh original-owner request admits actual new renderer");
    Drain();
    Check(window.firstResponder == replacement && replacement.requests == 1,
          "fresh request reaches actual renderer through original host");
  }];
}

- (void)testInvalidationCancelsQueuedRendererFocus {
  [self withPageHost:^(NSWindow* window, PCNativePageHost* host, NSView* , FocusManagerTestsFocusView* renderer) {
    [window makeFirstResponder:host];
    [host invalidate];
    Drain();
    XCTAssertEqual(renderer.requests, 0u);
  }];
}

@end

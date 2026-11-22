#import "HTTPAuthTestsSupport.h"

using namespace HTTPAuthTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_HTTPAuthTestsInvalidationTests")))
@interface HTTPAuthTestsInvalidationTests : ParcNativeTestCase
@end

@implementation HTTPAuthTestsInvalidationTests {
  NSWindow* _window;
  NSView* _page;
  PCHTTPAuthPresenter* _presenter;
  HTTPAuthTestsState* _state;
}

- (void)tearDown {
  ParcNativeClose(_window);
  [super tearDown];
}

- (void)showInWindowVisible:(BOOL)visible valid:(BOOL)valid {
  _window = Window(visible);
  _page = Page(_window);
  _state = [HTTPAuthTestsState new];
  HTTPAuthTestsState* state = _state;
  _presenter = Make(
      _page, _window, false,
      ^{
        return valid;
      },
      ^(PCHTTPAuthChoice choice, NSString*, NSString*) {
        ++state.count;
        state.outcome = choice;
      });
  [_presenter show];
}

- (void)expectInterruptedOnce {
  Pump();
  Check(_state.count == 1 && _state.outcome == PCHTTPAuthInterrupted,
        "invalid owner cannot present or supply credentials");
  Check(!ParcNativeAttachedSheet(_window), "interrupted sheet absent");
  [_presenter invalidate];
  Pump();
  Check(_state.count == 1, "interruption remains once-only");
}

- (void)testAnInvisibleWindowInterruptsTheRequest {
  [self showInWindowVisible:NO valid:YES];
  [self expectInterruptedOnce];
}

- (void)testAFailedValidationInterruptsTheRequest {
  [self showInWindowVisible:YES valid:NO];
  [self expectInterruptedOnce];
}

- (void)testARemovedPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_page removeFromSuperview];
  [self expectInterruptedOnce];
}

- (void)testInvalidatingInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  [_presenter invalidate];
  [self expectInterruptedOnce];
}

- (void)testAClosedWindowInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  ParcNativeClose(_window);
  [self expectInterruptedOnce];
}

- (void)testAHiddenPageInterruptsTheRequest {
  [self showInWindowVisible:YES valid:YES];
  _page.hidden = YES;
  [self expectInterruptedOnce];
}

@end

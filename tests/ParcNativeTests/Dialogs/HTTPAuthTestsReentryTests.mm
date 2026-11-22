#import "HTTPAuthTestsSupport.h"

using namespace HTTPAuthTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_HTTPAuthTestsReentryTests")))
@interface HTTPAuthTestsReentryTests : ParcNativeTestCase
@end

@implementation HTTPAuthTestsReentryTests {
  NSWindow* _window;
  NSView* _page;
  HTTPAuthTestsState* _state;
  PCHTTPAuthPresenter* _presenter;
  PCHTTPAuthPresenter* _replacement;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _state = [HTTPAuthTestsState new];
}

- (void)tearDown {
  ParcNativeClose(_window);
  [super tearDown];
}

- (void)testValidationCannotResurrectPresentation {
  HTTPAuthTestsState* state = _state;
  __block bool reenter = false;
  __block PCHTTPAuthPresenter* r;
  r = Make(
      _page, _window, false,
      ^{
        if (reenter) {
          [r invalidate];
        }
        return YES;
      },
      ^(PCHTTPAuthChoice choice, NSString*, NSString*) {
        ++state.count;
        Check(choice == PCHTTPAuthInterrupted, "validation reentry interrupts");
      });
  reenter = true;
  [r show];
  Pump();
  Check(state.count == 1 && !ParcNativeAttachedSheet(_window), "validation callback cannot resurrect presentation");
  r = nil;
}

- (void)cancelWhileReplacingTheOwner {
  HTTPAuthTestsState* state = _state;
  NSView* page = _page;
  NSWindow* window = _window;
  __weak HTTPAuthTestsReentryTests* weakSelf = self;
  __block PCHTTPAuthPresenter* r;
  r = Make(
      page, window, false,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice, NSString*, NSString*) {
        ++state.count;
        r = nil;
        HTTPAuthTestsReentryTests* strongSelf = weakSelf;
        strongSelf->_replacement = Make(
            page, window, true,
            ^{
              return YES;
            },
            ^(PCHTTPAuthChoice, NSString*, NSString*) {
              ++state.count;
            });
        [strongSelf->_replacement show];
      });
  _presenter = r;
  [r show];
  Pump();
  [r.sheet cancelOperation:nil];
  Pump();
  r = nil;
}

- (void)testTheOwnerCanBeReleasedAndReplacedDuringTheNativeCallback {
  [self cancelWhileReplacingTheOwner];
  Check(_state.count == 1 && ParcNativeSheetParent(_replacement.sheet) == _window,
        "owner release and replacement during native callback");
}

- (void)testAReplacementSeparatelyCompletes {
  [self cancelWhileReplacingTheOwner];
  [_replacement invalidate];
  Pump();
  Check(_state.count == 2, "replacement separately completes");
}

@end

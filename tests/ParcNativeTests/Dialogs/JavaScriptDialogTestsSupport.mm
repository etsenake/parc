#import "JavaScriptDialogTestsSupport.h"

using namespace JavaScriptDialogTestsSupportFunctions;

@implementation JavaScriptDialogTestsSupport

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _presenter = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:_page]);
}

- (void)tearDown {
  [_presenter invalidate];
  ParcNativeClose(_window);
  [super tearDown];
}

- (PCJavaScriptDialogCompletion)completion {
  return ^(BOOL accepted, NSString* input, BOOL suppressed) {
    ++self->_results;
    self->_accepted = accepted;
    self->_suppressed = suppressed;
    self->_input = input;
  };
}

- (NSWindow*)present:(PCJavaScriptDialogKind)kind suppression:(BOOL)suppression {
  Present(_presenter, kind, self.completion, suppression);
  return _presenter.presentedSheet;
}

- (NSWindow*)present:(PCJavaScriptDialogKind)kind {
  return [self present:kind suppression:NO];
}

@end

#import "JavaScriptDialogTestsSupport.h"

using namespace JavaScriptDialogTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_JavaScriptDialogTestsLifecycleTests")))
@interface JavaScriptDialogTestsLifecycleTests : JavaScriptDialogTestsSupport
@end

@implementation JavaScriptDialogTestsLifecycleTests

- (void)testTheSamePageCannotStackAConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  PCJavaScriptDialogPresenter* other = _presenter;
  __block BOOL rejected = NO;
  Present(other, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) { rejected = !accepted; });
  PARC_CHECK(rejected && _presenter.isPresenting && _results == 0);
}

- (void)testAnotherPageInTheWindowCannotStackAConfirmation {
  [self present:PCJavaScriptDialogConfirm];
  PCJavaScriptDialogPresenter* other = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:Page(_window)]);
  __block BOOL rejected = NO;
  Present(other, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) { rejected = !accepted; });
  PARC_CHECK(rejected && _presenter.isPresenting && _results == 0);
}

- (void)testMovingThePageRejectsALateAcceptance {
  [self present:PCJavaScriptDialogConfirm];
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  [_presenter handleAccepted:YES promptOverride:nil];
  ParcNativeClose(other);
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testANewRequestBindsToTheNewWindow {
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  PARC_CHECK(ParcNativeSheetParent([self present:PCJavaScriptDialogConfirm]) == other);
  ParcNativeClose(other);
}

- (void)testDetachingRejectsThePendingRequestImmediately {
  [self present:PCJavaScriptDialogConfirm];
  [_presenter pageHostWillDetach];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testADetachedPageCannotShowBeforeUnload {
  [_page removeFromSuperview];
  [self present:PCJavaScriptDialogBeforeUnload];
  PARC_CHECK(_results == 1 && !_accepted && !ParcNativeAttachedSheet(_window));
}

- (void)testClosingTheParentRejectsThePendingRequest {
  [self present:PCJavaScriptDialogConfirm];
  ParcNativeClose(_window);
  PARC_CHECK(_results == 1 && !_accepted);
}

- (void)testAClosedWindowCannotReceiveANewRequest {
  [self present:PCJavaScriptDialogConfirm];
  ParcNativeClose(_window);
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 2 && !_accepted && !_presenter.isPresenting);
}

- (void)testCompletionMayPresentANewConfirmation {
  Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
    PARC_CHECK(!accepted);
    [self present:PCJavaScriptDialogConfirm];
  });
  [_presenter cancel];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted);
}

- (void)testDeallocationRejectsThePendingRequest {
  __weak PCJavaScriptDialogPresenter* weak = _presenter;
  @autoreleasepool {
    [self present:PCJavaScriptDialogConfirm];
    _presenter = nil;
  }
  PARC_CHECK(!weak && _results == 1 && !_accepted && !ParcNativeAttachedSheet(_window));
}

- (void)testAButtonCompletionCanReleaseThePresenter {
  __weak PCJavaScriptDialogPresenter* weak = _presenter;
  @autoreleasepool {
    Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      PARC_CHECK(accepted);
      ++self->_results;
      self->_presenter = nil;
    });
    Click(_presenter, @"OK");
  }
  PARC_CHECK(!weak && _results == 1);
}

- (void)testAReleasedPageCannotPresent {
  __weak NSView* weak;
  @autoreleasepool {
    NSView* detached = [NSView new];
    weak = detached;
    _presenter = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:detached]);
  }
  [self present:PCJavaScriptDialogAlert];
  PARC_CHECK(!weak && _results == 1 && !_accepted);
}

- (void)testDetachmentRejectsACallbackThatTriesToReopen {
  Present(_presenter, PCJavaScriptDialogBeforeUnload, ^(BOOL accepted, NSString*, BOOL) {
    PARC_CHECK(!accepted);
    [self present:PCJavaScriptDialogConfirm];
  });
  [_presenter pageHostWillDetach];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testDetachmentBlocksTheOldHierarchy {
  [_presenter pageHostWillDetach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testAnAttachSignalRequiresAnActualWindow {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testReattachmentRequiresABalancedSignal {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_presenter pageHostDidAttach];
  [_window.contentView addSubview:_page];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testBalancedReattachmentAllowsANewDecision {
  [_presenter pageHostWillDetach];
  [_page removeFromSuperview];
  [_window.contentView addSubview:_page];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  Click(_presenter, @"OK");
  PARC_CHECK(_results == 1 && _accepted && !_presenter.isPresenting);
}

- (void)testAttachmentCannotReviveAnInvalidatedPresenter {
  [_presenter invalidate];
  [_presenter pageHostDidAttach];
  [self present:PCJavaScriptDialogConfirm];
  PARC_CHECK(_results == 1 && !_accepted && !_presenter.isPresenting);
}

- (void)testEndingOneWindowsSheetLeavesTheOtherPending {
  [self present:PCJavaScriptDialogConfirm];
  NSWindow* other = Window();
  PCJavaScriptDialogPresenter* second = Offscreen([[PCJavaScriptDialogPresenter alloc] initWithPageView:Page(other)]);
  Present(second, PCJavaScriptDialogConfirm, ^(BOOL, NSString*, BOOL) {});
  ParcNativeEndSheetWithCode(_window, _presenter.presentedSheet, NSModalResponseAbort);
  PARC_CHECK(_results == 1 && !_accepted && second.isPresenting && ParcNativeSheetParent(second.presentedSheet) == other);
  [second invalidate];
  ParcNativeClose(other);
}

- (void)testADecisionReleasesTheCompletionCapture {
  __weak NSObject* weak;
  @autoreleasepool {
    NSObject* capture = [NSObject new];
    weak = capture;
    Present(_presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      PARC_CHECK(accepted && capture);
    });
  }
  PARC_CHECK(weak);
  @autoreleasepool { Click(_presenter, @"OK"); }
  PARC_CHECK(!weak);
}

@end

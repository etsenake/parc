#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#include <cstdio>
#include <cstdlib>

#import "site_permission_presenter.h"
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Drain() {
  ParcNativeSettle();
}
static NSWindow* Window(BOOL visible = YES) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2200, -2200, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    ParcNativeMarkVisible(w);
  }
  return w;
}
static NSView* Page(NSWindow* w) {
  NSView* v = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:v];
  return v;
}
static NSButton* Button(NSView* v, NSString* label) {
  if ([v isKindOfClass:NSButton.class] &&
      [((NSButton*)v).title isEqual:label]) {
    return (NSButton*)v;
  }
  for (NSView* child in v.subviews) {
    if (auto b = Button(child, label)) {
      return b;
    }
  }
  return nil;
}
static BOOL Contains(NSView* v, NSString* text) {
  if ([v isKindOfClass:NSTextField.class] &&
      [((NSTextField*)v).stringValue containsString:text]) {
    return YES;
  }
  for (NSView* child in v.subviews) {
    if (Contains(child, text)) {
      return YES;
    }
  }
  return NO;
}
static PCSitePermissionPresenter* Request(
    NSView* page,
    NSWindow* w,
    BOOL (^valid)(void),
    void (^result)(PCSitePermissionChoice)) {
  auto* r = [[PCSitePermissionPresenter alloc] initWithPage:page
      window:w
      title:@"Allow frame.example:8443 to access your camera, microphone?"
      locationMode:PCSiteLocationNone
      initialPrecise:NO
      validate:valid
      presented:^{
      }
      result:^(PCSitePermissionChoice choice, BOOL) {
        result(choice);
      }];
  r.presentation = ParcNativePresentation();
  r.scheduler = ParcNativeScheduler();
  [r configureSymbol:@"camera.fill" pointSize:14 bold:NO offsetY:-1];
  return r;
}
static void Click(PCSitePermissionPresenter* r, NSString* label) {
  auto button = Button(r.sheet.contentView, label);
  Check(button && button.enabled, "actual native decision button exists");
  [button performClick:nil];
}
static double DrawnAlpha(NSButton* button) {
  NSShadow* shadow = button.shadow;
  button.shadow = nil;
  NSBitmapImageRep* rep =
      [button bitmapImageRepForCachingDisplayInRect:button.bounds];
  [button cacheDisplayInRect:button.bounds toBitmapImageRep:rep];
  button.shadow = shadow;
  double sum = 0;
  for (NSInteger y = 0; y < rep.pixelsHigh; ++y) {
    for (NSInteger x = 0; x < rep.pixelsWide; ++x) {
      sum += [rep colorAtX:x y:y].alphaComponent;
    }
  }
  return sum;
}
@interface ParcNativeTests_SitePermissionPresenterTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_SitePermissionPresenterTests {
  NSWindow* _window;
  NSView* _page;
  PCSitePermissionPresenter* _request;
  BOOL _valid;
  BOOL _precise;
  NSUInteger _results;
  NSUInteger _presentations;
  NSUInteger _systemActions;
  PCSitePermissionChoice _choice;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _valid = YES;
}

- (void)tearDown {
  [_request invalidate];
  Drain();
  ParcNativeClose(_window);
  [super tearDown];
}

- (void)prepare:(PCSiteLocationMode)mode {
  _request = [[PCSitePermissionPresenter alloc] initWithPage:_page window:_window
      title:@"Allow frame.example:8443 to access your camera, microphone?"
      locationMode:mode initialPrecise:YES validate:^{ return self->_valid; }
      presented:^{ ++self->_presentations; }
      result:^(PCSitePermissionChoice choice, BOOL precise) {
        self->_choice = choice;
        self->_precise = precise;
        ++self->_results;
      }];
  _request.presentation = ParcNativePresentation();
  _request.scheduler = ParcNativeScheduler();
  [_request configureSymbol:@"camera.fill" pointSize:14 bold:NO offsetY:-1];
}

- (void)show {
  [self prepare:PCSiteLocationNone];
  [_request start];
  Drain();
}

- (void)showFollowUp {
  [self prepare:PCSiteLocationNone];
  [_request configureFollowUpWithTitle:@"You previously allowed camera"
                                labels:@[ @"Continue allowing", @"Stop allowing" ]
                               choices:@[ @(PCSitePermissionDismiss), @(PCSitePermissionBlock) ]
                          systemAction:^(PCSitePermissionChoice) { ++self->_systemActions; }];
  [_request start];
  Drain();
}

- (void)testPresentationIsDeferred {
  [self prepare:PCSiteLocationNone];
  [_request start];
  PARC_CHECK(!_presentations && !_request.sheet && !_results);
}

- (void)testRepeatedStartAcknowledgesTheSamePresentationOnce {
  [self prepare:PCSiteLocationNone];
  [_request start];
  [_request start];
  Drain();
  PARC_CHECK(_presentations == 1 && _request.shown);
}

- (void)testThePromptLeavesTheParentsSheetSlotAvailable {
  [self show];
  PARC_CHECK(_request.shown && _request.sheet != _window && !ParcNativeAttachedSheet(_window));
}

- (void)testTheTitleNamesTheRequestingSiteAndItsPermissions {
  [self show];
  PARC_CHECK(Contains(_request.sheet.contentView, @"Allow frame.example:8443 to access your camera, microphone?"));
}

- (void)testTheInitialChoicesAreAllowAndNotNow {
  [self show];
  NSView* view = _request.sheet.contentView;
  PARC_CHECK(Button(view, @"Allow") && Button(view, @"Not Now") && !Button(view, @"Block") && !Button(view, @"Allow This Time"));
}

- (void)testReturnDoesNotGrantPermission {
  [self show];
  PARC_CHECK(!Button(_request.sheet.contentView, @"Allow").keyEquivalent.length);
}

- (void)testAButtonDecisionIsDeliveredAfterTheButtonCallback {
  [self show];
  Click(_request, @"Allow");
  PARC_CHECK(!_results);
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionAllow);
}

- (void)testNotNowDismisses {
  [self show];
  Click(_request, @"Not Now");
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionDismiss);
}

- (void)testEscapeDismisses {
  [self show];
  [_request.sheet cancelOperation:nil];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionDismiss);
}

- (void)testACompletedRequestCannotBeReplayed {
  [self show];
  Click(_request, @"Allow");
  Drain();
  [_request invalidate];
  [_request start];
  Drain();
  PARC_CHECK(_results == 1 && _presentations == 1);
}

- (void)testAHiddenParentInterruptsWithoutAcknowledging {
  ParcNativeOrderOut(_window);
  [self show];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted && !_presentations);
}

- (void)testAnInvalidContextInterruptsWithoutAcknowledging {
  _valid = NO;
  [self show];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted && !_presentations);
}

- (void)testValidationCanCancelAQueuedGrant {
  [self show];
  Click(_request, @"Allow");
  _valid = NO;
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted);
}

- (void)testDetachingThePageCancelsAQueuedGrant {
  [self show];
  Click(_request, @"Allow");
  [_page removeFromSuperview];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted);
}

- (void)testInvalidationCancelsAQueuedGrant {
  [self show];
  Click(_request, @"Allow");
  [_request invalidate];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted);
}

- (void)testClosingTheParentInterruptsThePrompt {
  [self show];
  ParcNativeClose(_window);
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted);
}

- (void)testMovingThePageCannotTransferAQueuedGrant {
  [self show];
  Click(_request, @"Allow");
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted && !ParcNativeAttachedSheet(_window) && !ParcNativeAttachedSheet(other));
  ParcNativeClose(other);
}

- (void)testASecondPromptIsRejectedWithoutDismissingTheFirst {
  [self show];
  __block NSUInteger interruptions = 0;
  auto other = Request(_page, _window, ^{ return YES; }, ^(PCSitePermissionChoice choice) {
    if (choice == PCSitePermissionInterrupted) ++interruptions;
  });
  [other start];
  Drain();
  PARC_CHECK(interruptions == 1 && _request.shown && !_results);
}

- (void)testTheCompletionMayPresentAReplacement {
  auto first = Request(_page, _window, ^{ return YES; }, ^(PCSitePermissionChoice choice) {
    PARC_CHECK(choice == PCSitePermissionAllow);
    [self show];
  });
  [first start];
  Drain();
  Click(first, @"Allow");
  Drain();
  [first invalidate];
  PARC_CHECK(_request.shown && !_results);
}

- (void)testTheCompletionCanReleaseItsLastOwner {
  __weak PCSitePermissionPresenter* weak;
  @autoreleasepool {
    __block PCSitePermissionPresenter* owned;
    owned = Request(_page, _window, ^{ return YES; }, ^(PCSitePermissionChoice) {
      ++self->_results;
      owned = nil;
    });
    weak = owned;
    [owned start];
    Drain();
    Click(owned, @"Not Now");
    Drain();
  }
  PARC_CHECK(!weak && _results == 1);
}

- (void)checkAccuracyFor:(PCSiteLocationMode)mode precise:(BOOL)expected {
  [self prepare:mode];
  [_request start];
  Drain();
  Click(_request, @"Allow");
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionAllow && _precise == expected);
}

- (void)testANonLocationGrantNeverReportsPrecise {
  [self checkAccuracyFor:PCSiteLocationNone precise:NO];
}

- (void)testAnApproximateGrantNeverReportsPrecise {
  [self checkAccuracyFor:PCSiteLocationApproximate precise:NO];
}

- (void)testASelectableGrantKeepsTheChosenAccuracy {
  [self checkAccuracyFor:PCSiteLocationApproximateOrPrecise precise:YES];
}

- (void)testAnUpgradeCanGrantPreciseLocation {
  [self checkAccuracyFor:PCSiteLocationUpgradeToPrecise precise:YES];
}

- (void)testAFollowUpUsesTheSuppliedTitleAndActions {
  [self showFollowUp];
  NSView* content = _request.sheet.contentView;
  PARC_CHECK(Contains(content, @"You previously allowed camera") && Button(content, @"Continue allowing") && !Button(content, @"Allow"));
}

- (void)testStopAllowingReturnsBlockWithoutASystemAction {
  [self showFollowUp];
  Click(_request, @"Stop allowing");
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionBlock && !_systemActions);
}

- (void)testAnotherSheetInterruptsTheOpenPrompt {
  [self show];
  NSWindow* sheet = ParcNativeOffscreenWindow(NSMakeRect(0, 0, 200, 100), NSWindowStyleMaskBorderless);
  ParcNativeBeginSheet(_window, sheet, nil);
  Drain();
  PARC_CHECK(_results == 1 && _choice == PCSitePermissionInterrupted && !_request.shown);
  ParcNativeEndSheet(_window, sheet);
}

- (void)testTheFallbackAnchorIsTheTopCornerOfThePage {
  [self show];
  ParcNativePopoverWindow* host = (ParcNativePopoverWindow*)_request.sheet;
  PARC_CHECK(host.anchorView == _page && host.anchorEdge == NSRectEdgeMinY &&
             NSEqualRects(host.anchorRect, NSMakeRect(0, NSMaxY(_page.bounds) - 1, 1, 1)));
}

- (void)checkPressedFeedback:(NSString*)title appearance:(NSAppearanceName)appearance {
  [self show];
  _request.sheet.appearance = [NSAppearance appearanceNamed:appearance];
  NSButton* button = Button(_request.sheet.contentView, title);
  [button viewDidChangeEffectiveAppearance];
  double rest = DrawnAlpha(button);
  [button.cell highlight:YES withFrame:button.bounds inView:button];
  double pressed = DrawnAlpha(button);
  [button.cell highlight:NO withFrame:button.bounds inView:button];
  PARC_CHECK(rest > 0 && fabs(pressed / rest - 0.75) < 0.01);
  PARC_CHECK(fabs(DrawnAlpha(button) - rest) < 0.5);
}

- (void)testAllowShowsPressedFeedbackInAqua {
  [self checkPressedFeedback:@"Allow" appearance:NSAppearanceNameAqua];
}

- (void)testNotNowShowsPressedFeedbackInAqua {
  [self checkPressedFeedback:@"Not Now" appearance:NSAppearanceNameAqua];
}

- (void)testAllowShowsPressedFeedbackInDarkAqua {
  [self checkPressedFeedback:@"Allow" appearance:NSAppearanceNameDarkAqua];
}

- (void)testNotNowShowsPressedFeedbackInDarkAqua {
  [self checkPressedFeedback:@"Not Now" appearance:NSAppearanceNameDarkAqua];
}

@end

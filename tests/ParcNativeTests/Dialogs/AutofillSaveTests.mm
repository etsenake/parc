#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"
#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "autofill_save_presenter.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Drain() {
  ParcNativeSettle();
}
static NSWindow* Window() {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  ParcNativeMarkVisible(window);
  return window;
}
static NSView* Page(NSWindow* window) {
  NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:page];
  return page;
}
static NSButton* Button(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [((NSButton*)view).title isEqualToString:title]) {
    return (NSButton*)view;
  }
  for (NSView* child in view.subviews) {
    if (NSButton* result = Button(child, title)) {
      return result;
    }
  }
  return nil;
}
static PCAutofillSavePresenter* Request(NSView* page,
                                        NSWindow* window,
                                        BOOL (^valid)(void),
                                        void (^result)(PCAutofillSaveOutcome)) {
  return [[PCAutofillSavePresenter alloc]
      initWithPageView:page
                window:window
                 title:@"Save this card?"
               message:@"Synthetic fixture — no payment data"
             saveLabel:@"Save"
          declineLabel:@"Not Now"
       validateContext:valid
            completion:result];
}
static void Click(PCAutofillSavePresenter* request, NSString* title) {
  NSButton* button = Button(request.sheet.contentView, title);
  Check(button != nil && button.enabled,
        "real sheet button exists and is enabled");
  [button performClick:nil];
}

@interface AttachmentTrackingWindow : NSWindow
@property(nonatomic, copy) void (^willBeginSheet)(NSWindow*);
@end
@implementation AttachmentTrackingWindow
- (void)beginSheet:(NSWindow*)sheet
    completionHandler:(void (^)(NSModalResponse))handler {
  if (self.willBeginSheet) {
    self.willBeginSheet(self);
  }
  [super beginSheet:sheet completionHandler:handler];
}
@end

@interface AutofillSaveTests : ParcNativeTestCase
@end

@implementation AutofillSaveTests {
  NSWindow* _window;
  NSView* _page;
  PCAutofillSavePresenter* _request;
  BOOL _valid;
  NSUInteger _results;
  PCAutofillSaveOutcome _outcome;
}

- (void)setUp {
  [super setUp];
  _window = Window();
  _page = Page(_window);
  _valid = YES;
  _request = Request(_page, _window, ^{ return self->_valid; }, ^(PCAutofillSaveOutcome result) {
    ++self->_results;
    self->_outcome = result;
  });
}

- (void)tearDown {
  [_request invalidate];
  ParcNativeSettle();
  [_window close];
  [super tearDown];
}

- (void)present {
  [_request start];
  ParcNativeSettle();
}

- (void)testStartDefersAttachment {
  [_request start];
  PARC_CHECK(!_request.sheet && !_results);
}

- (void)testRepeatedStartAttachesOneSheetToItsOwnWindow {
  [_request start];
  [self present];
  PARC_CHECK(_request.isPresenting && _request.sheet.sheetParent == _window && !NSApp.modalWindow);
}

- (void)testHoverReflectsThePointerInsideTheSheet {
  [self present];
  NSRect bounds = [_request.sheet contentRectForFrameRect:_request.sheet.frame];
  PARC_CHECK(_request.isMouseHovered == NSPointInRect(NSEvent.mouseLocation, bounds));
}

- (void)testClickDetachesTheSheetBeforeDelivery {
  [self present];
  Click(_request, @"Save");
  PARC_CHECK(!_request.sheet && !_window.attachedSheet && !_results);
}

- (void)testSaveAccepts {
  [self present];
  Click(_request, @"Save");
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveAccepted);
}

- (void)testNotNowDeclines {
  [self present];
  Click(_request, @"Not Now");
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveDeclined);
}

- (void)testEscapeDeclines {
  [self present];
  [_request.sheet cancelOperation:nil];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveDeclined);
}

- (void)testReturnAccepts {
  [self present];
  [_request.sheet insertNewline:nil];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveAccepted);
}

- (void)testEndingTheSheetInterrupts {
  [self present];
  [_window endSheet:_request.sheet];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted);
}

- (void)testClosingTheParentInterrupts {
  [self present];
  [_window close];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted);
}

- (void)testAFinishedRequestCannotReplay {
  [self present];
  Click(_request, @"Save");
  ParcNativeSettle();
  [_request invalidate];
  [self present];
  PARC_CHECK(_results == 1 && !_request.sheet);
}

- (void)testInitialValidationRejectsTheRequest {
  _valid = NO;
  [_request start];
  PARC_CHECK(!_results);
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_request.sheet);
}

- (void)testInvalidatingTwiceInterruptsThePendingRequestOnce {
  [_request start];
  [_request invalidate];
  [_request invalidate];
  PARC_CHECK(!_results);
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_request.sheet);
}

- (void)testValidationBeforeAttachmentCanReject {
  [_request start];
  _valid = NO;
  PARC_CHECK(!_results);
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_request.sheet);
}

- (void)testADetachedPageCannotPresent {
  [_request start];
  [_page removeFromSuperview];
  PARC_CHECK(!_results);
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_request.sheet);
}

- (void)testClosingAQueuedParentDeliversAnInterruptionLater {
  [_request start];
  [_window close];
  PARC_CHECK(!_results);
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_request.sheet);
}

- (void)testInvalidateCancelsAQueuedSave {
  [self present];
  Click(_request, @"Save");
  [_request invalidate];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_window.attachedSheet);
}

- (void)testAQueuedSaveRechecksItsContext {
  [self present];
  Click(_request, @"Save");
  _valid = NO;
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_window.attachedSheet);
}

- (void)testReattachingCannotReviveAnInvalidatedRequest {
  [self present];
  [_request invalidate];
  [_page removeFromSuperview];
  [_window.contentView addSubview:_page];
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_window.attachedSheet);
}

- (void)testMovingAPageCannotTransferItsSave {
  [self present];
  NSWindow* other = Window();
  [other.contentView addSubview:_page];
  Click(_request, @"Save");
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && !_window.attachedSheet && !other.attachedSheet);
  [other close];
}

- (void)testAnExistingSheetKeepsItsPlace {
  NSWindow* other = ParcNativeOffscreenWindow(NSMakeRect(0, 0, 200, 100), NSWindowStyleMaskBorderless);
  [_window beginSheet:other completionHandler:nil];
  [self present];
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted && _window.attachedSheet == other);
  [_window endSheet:other];
}

- (void)testClosingAnUnrelatedWindowKeepsTheRequestPending {
  [self present];
  [Window() close];
  ParcNativeSettle();
  PARC_CHECK(_request.isPresenting && !_results);
}

- (void)testFinalValidationCanCancelQueuedAcceptance {
  __block BOOL interrupt = NO;
  __weak __block PCAutofillSavePresenter* weak;
  _request = Request(_page, _window, ^{
    if (interrupt) [weak invalidate];
    return YES;
  }, ^(PCAutofillSaveOutcome result) {
    self->_outcome = result;
    ++self->_results;
  });
  weak = _request;
  [self present];
  Click(_request, @"Save");
  interrupt = YES;
  ParcNativeSettle();
  PARC_CHECK(_results == 1 && _outcome == PCAutofillSaveInterrupted);
}

- (void)testACompletionCanPresentAReplacementAfterItsOwnerIsReleased {
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block int count = 0;
  __block PCAutofillSavePresenter* next = nil;
  __weak PCAutofillSavePresenter* weak;
  @autoreleasepool {
    PCAutofillSavePresenter* request = Request(
        page, window,
        ^{
          return YES;
        },
        ^(PCAutofillSaveOutcome result) {
          ++count;
          Check(result == PCAutofillSaveAccepted, "original result intact");
          next = Request(
              page, window,
              ^{
                return YES;
              },
              ^(PCAutofillSaveOutcome later) {
                ++count;
                Check(later == PCAutofillSaveDeclined,
                      "replacement result intact");
              });
          [next start];
          Drain();
          Check(next.isPresenting,
                "new request can present inside reentrant callback");
        });
    weak = request;
    [request start];
    Drain();
    NSButton* save = Button(request.sheet.contentView, @"Save");
    request = nil;
    Check(weak != nil, "AppKit sheet completion retains active request");
    [save performClick:nil];
    Drain();
  }
  Drain();
  Check(weak == nil, "old request released after callback and sheet teardown");
  Check(next.isPresenting && count == 1,
        "old completion does not dismiss replacement");
  Click(next, @"Not Now");
  Drain();
  Check(count == 2, "both independent requests resolve exactly once");
  [window close];
}

- (void)testAttachmentRetainsTheValidatedWindowUntilTheSheetBegins {
  __block AttachmentTrackingWindow* owner = [[AttachmentTrackingWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  owner.releasedWhenClosed = NO;
  ParcNativeMarkVisible(owner);
  NSView* page = Page(owner);
  __weak NSWindow* original = owner;
  __block int attached = 0;
  __block int count = 0;
  owner.willBeginSheet = ^(NSWindow* actual) {
    ++attached;
    Check(owner == nil, "validator released the external native owner");
    Check(actual == original && page.window == actual,
          "attachment retains the exact validated window and page");
  };
  PCAutofillSavePresenter* request = Request(
      page, owner,
      ^{
        owner = nil;
        return YES;
      },
      ^(PCAutofillSaveOutcome result) {
        ++count;
        Check(result == PCAutofillSaveInterrupted,
              "owner-release fixture terminates without fabricated acceptance");
      });
  [request start];
  Drain();
  Check(attached == 1, "owner release cannot silently send beginSheet to nil");
  Check(NSApp.modalWindow == nil,
        "owner release never creates an app-modal fallback");
  [request invalidate];
  Drain();
  Check(count == 1 && !request.sheet, "owner-release request resolves once");
  [original close];
}

@end

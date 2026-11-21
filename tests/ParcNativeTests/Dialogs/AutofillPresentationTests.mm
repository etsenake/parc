#import "ParcNativeTest.h"
#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "autofill_save_presenter.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
static void Drain() {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:0.2];
  while (end.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
}
@interface PresentationWindow : NSWindow
@property(nonatomic, copy) void (^afterAttach)(void);
@end
@implementation PresentationWindow
@synthesize afterAttach = _afterAttach;
- (void)beginSheet:(NSWindow*)sheet
    completionHandler:(void (^)(NSModalResponse))completion {
  [super beginSheet:sheet completionHandler:completion];
  if (self.afterAttach) {
    self.afterAttach();
  }
}
@end
static PresentationWindow* Window() {
  auto* window = [[PresentationWindow alloc]
      initWithContentRect:NSMakeRect(-2200, -2200, 600, 400)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  [window orderFront:nil];
  return window;
}
static NSButton* FindButton(NSView* view, NSString* title) {
  if ([view isKindOfClass:NSButton.class] &&
      [((NSButton*)view).title isEqual:title]) {
    return (NSButton*)view;
  }
  for (NSView* child in view.subviews) {
    if (NSButton* b = FindButton(child, title)) {
      return b;
    }
  }
  return nil;
}
static void TestVisibleDecision(BOOL accepted) {
  auto* window = Window();
  NSView* page = window.contentView;
  __block int presented = 0, completed = 0;
  __block PCAutofillSaveOutcome outcome = PCAutofillSaveInterrupted;
  auto* request = [[PCAutofillSavePresenter alloc] initWithPageView:page
      window:window
      title:@"Synthetic local save"
      message:@"No personal data"
      saveLabel:@"Save"
      declineLabel:@"Not Now"
      validateContext:^{
        return YES;
      }
      completion:^(PCAutofillSaveOutcome result) {
        ++completed;
        outcome = result;
      }];
  request.onPresented = ^{
    ++presented;
    Check(window.visible && window.attachedSheet.visible,
          "true event requires actual visible sheet and parent");
    Check(window.attachedSheet.sheetParent == window,
          "true event preserves exact parent");
  };
  [request start];
  Check(presented == 0 && completed == 0,
        "queued request is neither shown nor decided");
  Drain();
  Check(presented == 1 && completed == 0,
        "actual attachment reports once before decision");
  NSButton* button =
      FindButton(request.sheet.contentView, accepted ? @"Save" : @"Not Now");
  Check(button != nil, "real user decision button exists");
  [button performClick:nil];
  Drain();
  Check(completed == 1 && outcome == (accepted ? PCAutofillSaveAccepted
                                               : PCAutofillSaveDeclined),
        "real decisions retain their distinct outcome");
  [request invalidate];
  [request start];
  Drain();
  Check(presented == 1 && completed == 1,
        "terminal request cannot replay either event");
  [window close];
}
static void TestUnavailable(int mode) {
  auto* window = Window();
  NSView* page = window.contentView;
  __block int presented = 0, completed = 0;
  __block PCAutofillSaveOutcome outcome = PCAutofillSaveAccepted;
  auto* request = [[PCAutofillSavePresenter alloc] initWithPageView:page
      window:window
      title:@"Synthetic local save"
      message:@"No personal data"
      saveLabel:@"Save"
      declineLabel:@"Not Now"
      validateContext:^{
        return YES;
      }
      completion:^(PCAutofillSaveOutcome result) {
        ++completed;
        outcome = result;
      }];
  request.onPresented = ^{
    ++presented;
  };
  if (mode == 0) {
    [window orderOut:nil];
  }
  if (mode == 1) {
    __weak NSWindow* weak = window;
    window.afterAttach = ^{
      [weak orderOut:nil];
    };
  }
  [request start];
  if (mode == 2) {
    [request invalidate];
  }
  if (mode == 3) {
    [window close];
  }
  Drain();
  Check(presented == 0,
        "hidden/lost parent and cancelled queue never report presentation");
  Check(completed == 1 && outcome == PCAutofillSaveInterrupted,
        "unavailable sheet resolves interruption exactly once");
  Check(!request.sheet && !window.attachedSheet,
        "unavailable request leaves no sheet");
  [request invalidate];
  Drain();
  Check(completed == 1, "repeat invalidation cannot add a result");
  [window close];
}
static void TestPresentedReentry() {
  auto* window = Window();
  __block int presented = 0, completed = 0;
  __block PCAutofillSavePresenter* owner =
      [[PCAutofillSavePresenter alloc] initWithPageView:window.contentView
          window:window
          title:@"Synthetic"
          message:@"Local"
          saveLabel:@"Save"
          declineLabel:@"Not Now"
          validateContext:^{
            return YES;
          }
          completion:^(PCAutofillSaveOutcome outcome) {
            ++completed;
            Check(outcome == PCAutofillSaveInterrupted,
                  "presented callback cancellation is not consent");
          }];
  __weak PCAutofillSavePresenter* weak = owner;
  owner.onPresented = ^{
    ++presented;
    [weak invalidate];
    owner = nil;
    Drain();
  };
  [owner start];
  Drain();
  Check(presented == 1 && completed == 1,
        "callback reentry and final owner release settle once");
  Check(!window.attachedSheet, "reentrant close detaches native sheet");
  [window close];
}
@interface AutofillPresentationTests : ParcNativeTestCase
@end

@implementation AutofillPresentationTests

- (void)testDeclinedDecision {
  TestVisibleDecision(NO);
}

- (void)testAcceptedDecision {
  TestVisibleDecision(YES);
}

- (void)testHiddenParentInterrupts {
  TestUnavailable(0);
}

- (void)testParentHiddenDuringAttachInterrupts {
  TestUnavailable(1);
}

- (void)testInvalidatedRequestInterrupts {
  TestUnavailable(2);
}

- (void)testClosedParentInterrupts {
  TestUnavailable(3);
}

- (void)testPresentedReentry {
  TestPresentedReentry();
}

@end

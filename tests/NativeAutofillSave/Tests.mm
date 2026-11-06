#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "autofill_save_presenter.h"

static int assertions = 0;
static int groups = 0;
static void Check(BOOL value, const char* description) {
  ++assertions;
  if (!value) {
    fprintf(stderr, "FAIL: %s\n", description);
    exit(1);
  }
}
static void Drain() {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:0.15];
  while (deadline.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
}
static NSWindow* Window() {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  [window orderFront:nil];
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

static void TestButtonsAndDeferredCompletion() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block int count = 0;
  __block PCAutofillSaveOutcome outcome = PCAutofillSaveInterrupted;
  PCAutofillSavePresenter* request = Request(
      page, window,
      ^{
        return YES;
      },
      ^(PCAutofillSaveOutcome result) {
        ++count;
        outcome = result;
        Check(window.attachedSheet == nil,
              "sheet detached before client completion");
      });
  [request start];
  [request start];
  Check(!request.sheet && count == 0,
        "start returns before presenting or completing");
  Drain();
  Check(request.isPresenting, "real custom sheet presented");
  Check(request.sheet.sheetParent == window,
        "sheet belongs to exact supplied window");
  Check([NSStringFromClass(request.sheet.class)
            isEqualToString:@"PCAutofillSaveSheet"],
        "uses custom NSWindow subclass, not NSAlert");
  Check(NSApp.modalWindow == nil, "no application-modal loop");
  Check(!request.isMouseHovered, "offscreen sheet is not mouse-hovered");
  Click(request, @"Save");
  Check(count == 0,
        "button result is deferred after synchronous caller registration");
  Check(!request.sheet, "sheet removed immediately at finish");
  Drain();
  Check(count == 1 && outcome == PCAutofillSaveAccepted,
        "Save delivers one acceptance");
  [request invalidate];
  [request start];
  Drain();
  Check(count == 1, "finished request cannot replay");
  request = Request(
      page, window,
      ^{
        return YES;
      },
      ^(PCAutofillSaveOutcome result) {
        ++count;
        outcome = result;
      });
  [request start];
  Drain();
  Click(request, @"Not Now");
  Drain();
  Check(count == 2 && outcome == PCAutofillSaveDeclined,
        "explicit decline is distinct");
  [window close];
}
static void TestKeysAndExternalSheetEnd() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block int count = 0;
  __block PCAutofillSaveOutcome outcome;
  for (int i = 0; i < 3; ++i) {
    PCAutofillSavePresenter* request = Request(
        page, window,
        ^{
          return YES;
        },
        ^(PCAutofillSaveOutcome result) {
          ++count;
          outcome = result;
        });
    [request start];
    Drain();
    NSWindow* sheet = request.sheet;
    Check(sheet != nil, "key/dismiss fixture has actual sheet");
    if (i == 0) {
      [sheet cancelOperation:nil];
    }
    if (i == 1) {
      [sheet insertNewline:nil];
    }
    if (i == 2) {
      [window endSheet:sheet];
    }
    Drain();
    Check(count == i + 1, "key/dismiss resolves once");
    Check(outcome == (i == 0   ? PCAutofillSaveDeclined
                      : i == 1 ? PCAutofillSaveAccepted
                               : PCAutofillSaveInterrupted),
          "Escape, Return and external dismissal keep distinct semantics");
    [request invalidate];
  }
  [window close];
}
static void TestPendingInvalidation() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  for (int i = 0; i < 4; ++i) {
    __block int count = 0;
    __block BOOL valid = i != 0;
    PCAutofillSavePresenter* request = Request(
        page, window,
        ^{
          return valid;
        },
        ^(PCAutofillSaveOutcome result) {
          ++count;
          Check(result == PCAutofillSaveInterrupted,
                "failure never fabricates consent");
        });
    [request start];
    if (i == 1) {
      [request invalidate];
      [request invalidate];
    }
    if (i == 2) {
      valid = NO;
    }
    if (i == 3) {
      [page removeFromSuperview];
    }
    Check(count == 0, "invalid pending request does not complete inline");
    Drain();
    Check(count == 1 && !request.sheet,
          "invalid pending request resolves without sheet");
    if (i == 3) {
      [window.contentView addSubview:page];
    }
  }
  [window close];
}
static void TestLateInvalidationAndWindowBinding() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  NSWindow* other = Window();
  for (int i = 0; i < 4; ++i) {
    __block int count = 0;
    __block BOOL valid = YES;
    PCAutofillSavePresenter* request = Request(
        page, window,
        ^{
          return valid;
        },
        ^(PCAutofillSaveOutcome result) {
          ++count;
          Check(result == PCAutofillSaveInterrupted,
                "late invalidation prevents stale save");
        });
    [request start];
    Drain();
    if (i == 0) {
      Click(request, @"Save");
      [request invalidate];
    }
    if (i == 1) {
      Click(request, @"Save");
      valid = NO;
    }
    if (i == 2) {
      [other.contentView addSubview:page];
      Click(request, @"Save");
    }
    if (i == 3) {
      [request invalidate];
      [page removeFromSuperview];
      [window.contentView addSubview:page];
    }
    Drain();
    Check(count == 1, "invalidated result delivered once");
    Check(!window.attachedSheet && !other.attachedSheet,
          "no sheet follows moved page");
    [window.contentView addSubview:page];
  }
  [other close];
  [window close];
}
static void TestConflictingSheetAndParentClose() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  NSWindow* otherSheet =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                  styleMask:NSWindowStyleMaskTitled
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  otherSheet.releasedWhenClosed = NO;
  [window beginSheet:otherSheet completionHandler:nil];
  __block int count = 0;
  PCAutofillSavePresenter* request = Request(
      page, window,
      ^{
        return YES;
      },
      ^(PCAutofillSaveOutcome result) {
        ++count;
        Check(result == PCAutofillSaveInterrupted,
              "occupied parent interrupts new request");
      });
  [request start];
  Drain();
  Check(count == 1 && window.attachedSheet == otherSheet,
        "does not replace somebody else's sheet");
  [window endSheet:otherSheet];
  [otherSheet orderOut:nil];
  Drain();
  request = Request(
      page, window,
      ^{
        return YES;
      },
      ^(PCAutofillSaveOutcome result) {
        ++count;
        Check(result == PCAutofillSaveInterrupted,
              "actual parent close interrupts");
      });
  [request start];
  Drain();
  [window close];
  Drain();
  Check(count == 2 && !request.sheet,
        "closing parent resolves displayed sheet");
}
static void TestReentrantDeliveryAndLifetime() {
  ++groups;
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
static void TestValidationReentryAndQueuedClose() {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block int count = 0;
  __block int validations = 0;
  __block __weak PCAutofillSavePresenter* weak;
  PCAutofillSavePresenter* request = Request(
      page, window,
      ^{
        ++validations;
        if (validations == 3) {
          [weak invalidate];
        }
        return YES;
      },
      ^(PCAutofillSaveOutcome outcome) {
        ++count;
        Check(outcome == PCAutofillSaveInterrupted,
              "validation callback can invalidate queued acceptance");
      });
  weak = request;
  [request start];
  Drain();
  NSWindow* unrelated = Window();
  [unrelated close];
  Drain();
  Check(request.isPresenting && count == 0,
        "unrelated window close cannot cancel request");
  Click(request, @"Save");
  Drain();
  Check(count == 1 && validations == 3, "reentrant validator delivered once");
  request = Request(
      page, window,
      ^{
        return YES;
      },
      ^(PCAutofillSaveOutcome outcome) {
        ++count;
        Check(outcome == PCAutofillSaveInterrupted,
              "queued parent close never presents");
      });
  [request start];
  [window close];
  Check(count == 1, "queued parent close remains deferred");
  Drain();
  Check(count == 2 && !request.sheet,
        "queued request resolves after parent close");
}
static void TestValidationReleasesNativeOwner() {
  ++groups;
  __block AttachmentTrackingWindow* owner = [[AttachmentTrackingWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 600, 400)
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:NO];
  owner.releasedWhenClosed = NO;
  [owner orderFront:nil];
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
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    TestButtonsAndDeferredCompletion();
    TestKeysAndExternalSheetEnd();
    TestPendingInvalidation();
    TestLateInvalidationAndWindowBinding();
    TestConflictingSheetAndParentClose();
    TestReentrantDeliveryAndLifetime();
    TestValidationReentryAndQueuedClose();
    TestValidationReleasesNativeOwner();
    printf("NativeAutofillSave: %d assertions in %d groups passed\n",
           assertions, groups);
  }
}

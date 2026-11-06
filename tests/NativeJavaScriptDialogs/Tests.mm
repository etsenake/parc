#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "javascript_dialog_presenter.h"

static int assertions = 0;
static int groups = 0;
static void Check(BOOL value, const char* message) {
  ++assertions;
  if (!value) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}
static void Drain(void) {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:0.12];
  while (deadline.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
}
static NSWindow* Window(void) {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 640, 480)
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
    NSButton* button = Button(child, title);
    if (button) {
      return button;
    }
  }
  return nil;
}
static NSTextField* Input(NSView* view) {
  if ([view isKindOfClass:NSTextField.class] && ((NSTextField*)view).editable) {
    return (NSTextField*)view;
  }
  for (NSView* child in view.subviews) {
    NSTextField* field = Input(child);
    if (field) {
      return field;
    }
  }
  return nil;
}
static void Click(PCJavaScriptDialogPresenter* presenter, NSString* title) {
  NSButton* button = Button(presenter.presentedSheet.contentView, title);
  Check(button != nil, "actual native sheet contains requested button");
  [button performClick:nil];
  Drain();
}
static void Present(PCJavaScriptDialogPresenter* presenter,
                    PCJavaScriptDialogKind kind,
                    PCJavaScriptDialogCompletion completion,
                    BOOL suppression = NO) {
  [presenter presentKind:kind
                    title:@"127.0.0.1:8080 says"
                  message:@"Fixture dialog"
              defaultText:@"seed 🪴"
        offersSuppression:suppression
               completion:completion];
}
static NSTextField* Label(NSView* view, NSString* text) {
  if ([view isKindOfClass:NSTextField.class] &&
      [((NSTextField*)view).stringValue isEqualToString:text]) {
    return (NSTextField*)view;
  }
  for (NSView* child in view.subviews) {
    NSTextField* field = Label(child, text);
    if (field) {
      return field;
    }
  }
  return nil;
}

static void TestButtonsAndPrompt(void) {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  PCJavaScriptDialogPresenter* presenter =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  __block int count = 0;
  __block BOOL result = NO;
  __block NSString* text = nil;
  PCJavaScriptDialogCompletion completion = ^(BOOL accepted, NSString* input, BOOL) {
    ++count;
    result = accepted;
    text = input;
    Check(!presenter.isPresenting, "request cleared before completion");
    Check(!window.attachedSheet, "sheet removed before completion");
  };
  Present(presenter, PCJavaScriptDialogAlert, completion);
  Check(presenter.isPresenting, "alert is pending");
  Check(presenter.presentedSheet.sheetParent == window,
        "sheet belongs to actual page window");
  Check(NSApp.modalWindow == nil, "no application modal fallback");
  Click(presenter, @"OK");
  Check(count == 1 && result && text.length == 0,
        "alert acknowledges exactly once");
  [presenter cancel];
  [presenter handleAccepted:YES promptOverride:nil];
  Check(count == 1, "late cancel/accept cannot replay result");
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  Click(presenter, @"Cancel");
  Check(count == 2 && !result, "native Cancel rejects confirm");
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  Click(presenter, @"OK");
  Check(count == 3 && result, "native OK accepts confirm");
  Present(presenter, PCJavaScriptDialogPrompt, completion);
  NSTextField* field = Input(presenter.presentedSheet.contentView);
  Check([field.stringValue isEqualToString:@"seed 🪴"],
        "prompt preserves Unicode default");
  field.stringValue = @"typed é 🧪";
  Click(presenter, @"OK");
  Check(count == 4 && result && [text isEqualToString:@"typed é 🧪"],
        "native field value returned");
  Present(presenter, PCJavaScriptDialogPrompt, completion);
  [presenter handleAccepted:YES promptOverride:@""];
  Drain();
  Check(count == 5 && result && text.length == 0,
        "empty override replaces default");
  Present(presenter, PCJavaScriptDialogPrompt, completion);
  [presenter handleAccepted:YES promptOverride:nil];
  Drain();
  Check(count == 6 && [text isEqualToString:@"seed 🪴"],
        "nil override retains current input");
  Present(presenter, PCJavaScriptDialogPrompt, completion);
  [presenter handleAccepted:NO promptOverride:@"not returned"];
  Drain();
  Check(count == 7 && !result && text.length == 0,
        "rejected prompt returns no input");
  [presenter invalidate];
  [window close];
}

static void TestBeforeUnload(void) {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  PCJavaScriptDialogPresenter* presenter =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  __block int count = 0;
  __block BOOL result = YES;
  PCJavaScriptDialogCompletion completion = ^(BOOL accepted, NSString*, BOOL) {
    ++count;
    result = accepted;
  };
  [presenter presentKind:PCJavaScriptDialogBeforeUnload
                    title:@"Leave site?"
                  message:@"Changes you made may not be saved."
              defaultText:@""
        offersSuppression:YES
               completion:completion];
  NSView* content = presenter.presentedSheet.contentView;
  Check(Label(content, @"Leave site?") &&
            Label(content, @"Changes you made may not be saved."),
        "before unload shows the engine title and message");
  Check(!Button(content, @"Don't show this again"),
        "before unload never offers suppression");
  Click(presenter, @"Cancel");
  Check(count == 1 && !result, "Cancel stays on the page");
  Present(presenter, PCJavaScriptDialogBeforeUnload, completion);
  Check(!Button(presenter.presentedSheet.contentView, @"Leave Page"),
        "the sheet has no Leave Page button");
  Click(presenter, @"OK");
  Check(count == 2 && result, "later OK leaves after Cancel");
  [presenter presentKind:PCJavaScriptDialogBeforeUnload
                    title:@"Reload site?"
                  message:@"Changes you made may not be saved."
              defaultText:@""
        offersSuppression:NO
               completion:completion];
  Click(presenter, @"OK");
  Check(count == 3 && result, "reload request uses the same OK sheet");
  Present(presenter, PCJavaScriptDialogBeforeUnload, completion);
  [presenter invalidate];
  [presenter invalidate];
  Drain();
  Check(count == 4 && !result, "terminal teardown rejects beforeunload once");
  Present(presenter, PCJavaScriptDialogBeforeUnload, completion);
  Check(count == 5 && !result && !presenter.isPresenting,
        "invalidated presenter cannot accept new request");
  [window close];
}

static void TestHostBindingAndBusyWindow(void) {
  ++groups;
  NSWindow* first = Window();
  NSWindow* second = Window();
  NSView* page = Page(first);
  NSView* otherPage = Page(first);
  PCJavaScriptDialogPresenter* presenter =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  PCJavaScriptDialogPresenter* other =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:otherPage];
  __block int count = 0;
  __block BOOL result = YES;
  PCJavaScriptDialogCompletion completion = ^(BOOL accepted, NSString*, BOOL) {
    ++count;
    result = accepted;
  };
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  __block int rejected = 0;
  Present(presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
    ++rejected;
    Check(!accepted, "concurrent per-page request is rejected");
  });
  Present(other, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
    ++rejected;
    Check(!accepted, "another page cannot stack a sheet in same window");
  });
  Check(rejected == 2 && count == 0 && presenter.isPresenting,
        "busy rejection preserves first request");
  [page removeFromSuperview];
  [second.contentView addSubview:page];
  [presenter handleAccepted:YES promptOverride:nil];
  Drain();
  Check(count == 1 && !result,
        "late accept after unannounced window move is rejected");
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  Check(presenter.presentedSheet.sheetParent == second,
        "next request binds new actual window");
  [presenter pageHostWillDetach];
  Check(count == 2 && !result && !presenter.isPresenting,
        "explicit detach cancels immediately");
  [page removeFromSuperview];
  Present(presenter, PCJavaScriptDialogBeforeUnload, completion);
  Check(count == 3 && !result && !first.attachedSheet && !second.attachedSheet,
        "detached page fails without app-modal dialog or consent");
  [second.contentView addSubview:page];
  [presenter pageHostDidAttach];
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  [second close];
  Drain();
  Check(count == 4 && !result, "actual parent-window close cancels once");
  Present(presenter, PCJavaScriptDialogConfirm, completion);
  Check(count == 5 && !result, "closed window cannot receive another request");
  [first close];
}

static void TestOwnershipAndReentry(void) {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  __block PCJavaScriptDialogPresenter* presenter = nil;
  __weak PCJavaScriptDialogPresenter* weakPresenter = nil;
  __block int count = 0;
  @autoreleasepool {
    presenter = [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
    weakPresenter = presenter;
    Present(presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      ++count;
      Check(!accepted, "first cancelled request rejects");
      Present(weakPresenter, PCJavaScriptDialogConfirm,
              ^(BOOL next, NSString*, BOOL) {
                ++count;
                Check(next, "reentrant replacement receives its own decision");
              });
    });
    [presenter cancel];
    Drain();
    Check(count == 1 && presenter.isPresenting,
          "completion may submit new sheet without stale cleanup");
    Click(presenter, @"OK");
    Check(count == 2 && !presenter.isPresenting,
          "reentrant sheet completed once");
    Present(presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      ++count;
      Check(!accepted, "presenter destruction rejects pending request");
    });
    presenter = nil;
    Drain();
  }
  Drain();
  Check(weakPresenter == nil && count == 3 && !window.attachedSheet,
        "request does not retain presenter and deallocation cancels");
  @autoreleasepool {
    presenter = [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
    weakPresenter = presenter;
    Present(presenter, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      ++count;
      Check(accepted, "button completion can destroy presenter");
      presenter = nil;
    });
    Click(presenter, @"OK");
  }
  Drain();
  Check(weakPresenter == nil && count == 4,
        "completion-triggered destruction has no stale callback");
  [window close];
  __weak NSView* weakPage = nil;
  @autoreleasepool {
    NSView* detached = [[NSView alloc] initWithFrame:NSZeroRect];
    weakPage = detached;
    presenter = [[PCJavaScriptDialogPresenter alloc] initWithPageView:detached];
  }
  Check(!weakPage, "presenter does not retain page");
  Present(presenter, PCJavaScriptDialogAlert, ^(BOOL accepted, NSString*, BOOL) {
    ++count;
    Check(!accepted, "destroyed page cannot present or accept");
  });
  Check(count == 5, "missing page resolves exactly once");
  presenter = nil;
}

static void TestDetachReentry(void) {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  PCJavaScriptDialogPresenter* presenter =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  __block int rejected = 0;
  PCJavaScriptDialogCompletion reject = ^(BOOL accepted, NSString*, BOOL) {
    ++rejected;
    Check(!accepted, "host transition cannot grant a reentrant request");
  };
  Present(presenter, PCJavaScriptDialogBeforeUnload,
          ^(BOOL accepted, NSString*, BOOL) {
            reject(accepted, @"", NO);
            Present(presenter, PCJavaScriptDialogConfirm, reject);
          });
  [presenter pageHostWillDetach];
  Check(rejected == 2 && !presenter.isPresenting && !window.attachedSheet,
        "detach blocks new sheet before delivering cancellation callback");
  Present(presenter, PCJavaScriptDialogConfirm, reject);
  Check(rejected == 3,
        "transition remains blocked while old hierarchy still exists");
  [page removeFromSuperview];
  [presenter pageHostDidAttach];
  Present(presenter, PCJavaScriptDialogConfirm, reject);
  Check(rejected == 4,
        "attach notification without an actual window cannot unblock");
  [window.contentView addSubview:page];
  Present(presenter, PCJavaScriptDialogConfirm, reject);
  Check(rejected == 5,
        "reattachment requires explicit balanced lifecycle signal");
  [presenter pageHostDidAttach];
  __block int accepted = 0;
  Present(presenter, PCJavaScriptDialogConfirm, ^(BOOL result, NSString*, BOOL) {
    Check(result,
          "same-window reattachment permits a new independent decision");
    ++accepted;
  });
  Click(presenter, @"OK");
  Check(accepted == 1 && rejected == 5,
        "reattachment does not resurrect old callback");
  [presenter invalidate];
  [presenter pageHostDidAttach];
  Present(presenter, PCJavaScriptDialogConfirm, reject);
  Check(rejected == 6, "attach cannot revive terminal invalidation");
  [window close];
}

static void TestIndependentWindowsAndCallbackRelease(void) {
  ++groups;
  NSWindow* first = Window();
  NSWindow* second = Window();
  NSView* firstPage = Page(first);
  NSView* secondPage = Page(second);
  PCJavaScriptDialogPresenter* one =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:firstPage];
  PCJavaScriptDialogPresenter* two =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:secondPage];
  __block int firstCount = 0;
  __block int secondCount = 0;
  Present(one, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
    ++firstCount;
    Check(!accepted, "external sheet abort rejects its request");
  });
  __weak NSObject* weakCapture = nil;
  @autoreleasepool {
    NSObject* capture = [NSObject new];
    weakCapture = capture;
    Present(two, PCJavaScriptDialogConfirm, ^(BOOL accepted, NSString*, BOOL) {
      ++secondCount;
      Check(accepted && capture != nil,
            "completion capture is alive through delivery");
    });
  }
  Check(one.isPresenting && two.isPresenting,
        "independent windows may each own a dialog");
  Check(first.attachedSheet == one.presentedSheet &&
            second.attachedSheet == two.presentedSheet,
        "each request keeps its own window association");
  Check(weakCapture != nil, "pending completion retained until resolution");
  [first endSheet:one.presentedSheet returnCode:NSModalResponseAbort];
  Drain();
  Check(firstCount == 1 && secondCount == 0 && two.isPresenting,
        "ending one sheet leaves other window request intact");
  @autoreleasepool {
    Click(two, @"OK");
  }
  Drain();
  Check(secondCount == 1 && !weakCapture,
        "completed request releases captured callback state");
  [one invalidate];
  [two invalidate];
  [first close];
  [second close];
}

static void TestArcPresentation(void) {
  ++groups;
  NSWindow* window = Window();
  NSView* page = Page(window);
  PCJavaScriptDialogPresenter* presenter =
      [[PCJavaScriptDialogPresenter alloc] initWithPageView:page];
  __block int count = 0;
  __block BOOL result = NO;
  __block BOOL suppressed = NO;
  PCJavaScriptDialogCompletion completion =
      ^(BOOL accepted, NSString*, BOOL suppress) {
        ++count;
        result = accepted;
        suppressed = suppress;
      };
  Present(presenter, PCJavaScriptDialogAlert, completion);
  NSView* content = presenter.presentedSheet.contentView;
  Check(Label(content, @"127.0.0.1:8080 says") &&
            Label(content, @"Fixture dialog"),
        "title is the message text and page text the informative text");
  Check(Button(content, @"OK") && !Button(content, @"Cancel"),
        "alert has only OK");
  Check(!Button(content, @"Don't show this again") && !Input(content),
        "plain alert has no accessory");
  Click(presenter, @"OK");
  Present(presenter, PCJavaScriptDialogPrompt, completion, YES);
  content = presenter.presentedSheet.contentView;
  NSTextField* field = Input(content);
  NSButton* box = Button(content, @"Don't show this again");
  Check(field && box && field.superview == box.superview &&
            [field.superview isKindOfClass:NSStackView.class],
        "prompt field and checkbox share the stack");
  NSStackView* stack = (NSStackView*)field.superview;
  Check(stack.orientation == NSUserInterfaceLayoutOrientationVertical &&
            stack.frame.size.width == 280 && stack.frame.size.height == 48,
        "stack is vertical, 280 wide and 24 points per view");
  Check(presenter.presentedSheet.initialFirstResponder == field,
        "prompt field is the initial first responder");
  Check([Button(content, @"Cancel").keyEquivalent isEqualToString:@"\033"],
        "Cancel answers Escape");
  box.state = NSControlStateValueOn;
  Click(presenter, @"Cancel");
  Check(count == 2 && !result && suppressed,
        "checked suppression is reported with Cancel too");
  Present(presenter, PCJavaScriptDialogConfirm, completion, YES);
  Click(presenter, @"OK");
  Check(count == 3 && result && !suppressed,
        "unchecked suppression is not reported");
  Present(presenter, PCJavaScriptDialogConfirm, completion, YES);
  Button(presenter.presentedSheet.contentView, @"Don't show this again")
      .state = NSControlStateValueOn;
  [presenter handleAccepted:YES promptOverride:nil];
  Drain();
  Check(count == 4 && result && !suppressed,
        "programmatic handling never reports suppression");
  [presenter invalidate];
  [window close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    TestButtonsAndPrompt();
    TestBeforeUnload();
    TestHostBindingAndBusyWindow();
    TestOwnershipAndReentry();
    TestDetachReentry();
    TestIndependentWindowsAndCallbackRelease();
    TestArcPresentation();
    printf("NativeJavaScriptDialogs: %d assertions across %d groups passed\n",
           assertions, groups);
  }
  return 0;
}

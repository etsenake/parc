#import <AppKit/AppKit.h>

#include <cstdio>
#include <cstdlib>

#import "http_auth_presenter.h"
static int checks;
static void Check(bool value, const char* message) {
  ++checks;
  if (!value) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}
static void Pump() {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:.08];
  while (end.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, .005, true);
  }
}
static NSWindow* Window(bool visible = true) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    [w orderFront:nil];
  }
  return w;
}
static NSView* Page(NSWindow* w) {
  NSView* p = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:p];
  return p;
}
static NSTextField* Label(NSView* v, NSString* text) {
  if ([v isKindOfClass:NSTextField.class] &&
      [static_cast<NSTextField*>(v).stringValue isEqual:text]) {
    return static_cast<NSTextField*>(v);
  }
  for (NSView* child in v.subviews) {
    if (auto f = Label(child, text)) {
      return f;
    }
  }
  return nil;
}
static NSView* Find(NSView* v, NSString* name) {
  if ([v.identifier isEqual:name] ||
      ([v isKindOfClass:NSButton.class] &&
       [static_cast<NSButton*>(v).title isEqual:name])) {
    return v;
  }
  for (NSView* child in v.subviews) {
    if (auto f = Find(child, name)) {
      return f;
    }
  }
  return nil;
}
static PCHTTPAuthPresenter* Make(NSView* p,
                                 NSWindow* w,
                                 bool proxy,
                                 BOOL (^valid)(void),
                                 void (^result)(PCHTTPAuthChoice,
                                                NSString*,
                                                NSString*)) {
  return [[PCHTTPAuthPresenter alloc]
      initWithPage:p
            window:w
         authority:proxy ? @"The proxy http://proxy.example:8080 requires a "
                           @"username and password."
                         : @"https://login.example:8443"
       explanation:proxy ? @"Your connection is not private." : @""
             proxy:proxy
          validate:valid
            result:result];
}
static void Decisions() {
  NSWindow* w = Window();
  NSView* p = Page(w);
  __block int count = 0;
  __block PCHTTPAuthChoice outcome = PCHTTPAuthInterrupted;
  __block NSString* user;
  __block NSString* secret;
  auto r = Make(
      p, w, false,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice c, NSString* u, NSString* s) {
        ++count;
        outcome = c;
        user = u;
        secret = s;
        Check(!w.attachedSheet, "sheet removed before controller decision");
      });
  Check(r.sheet && !r.sheet.visible,
        "real window exists but is not falsely presented");
  [r show];
  [r show];
  Check(count == 0, "show is deferred");
  Pump();
  Check(r.sheet.visible && r.sheet.sheetParent == w,
        "exact native sheet attached");
  auto username = static_cast<NSTextField*>(
      Find(r.sheet.contentView, @"http-auth-username"));
  auto password = static_cast<NSSecureTextField*>(
      Find(r.sheet.contentView, @"http-auth-password"));
  Check([password isKindOfClass:NSSecureTextField.class],
        "secure password control");
  NSFont* label = [NSFont systemFontOfSize:13];
  NSFont* weighted = [[NSFontManager.sharedFontManager
      fontWithFamily:label.familyName
              traits:0
              weight:7
                size:13] fontWithSize:18];
  Check([Label(r.sheet.contentView, @"Sign in to login.example").font
            isEqual:weighted] &&
            username.font.pointSize == 13,
        "the FontSet.label body and its weight-7, 18-point title");
  Check(Label(r.sheet.contentView, @"Sign in to login.example") &&
            Label(r.sheet.contentView,
                  @"Your connection to this site is private."),
        "the title names the host; no explanation means private");
  Check(Label(r.sheet.contentView, @"Username") &&
            Label(r.sheet.contentView, @"Password") &&
            [username.placeholderString isEqual:@"Username"],
        "the field labels and placeholders");
  Check(r.sheet.contentView.frame.size.width >= 400 &&
            (r.sheet.styleMask & NSWindowStyleMaskFullSizeContentView),
        "the 400-point full-size-content login window");
  [r autofillUsername:@"saved" password:@"original"];
  Check([username.stringValue isEqual:@"saved"] &&
            [password.stringValue isEqual:@"original"],
        "autofill delivered to actual fields");
  username.stringValue = @"edited";
  [r autofillUsername:@"later" password:@"wrong"];
  Check([username.stringValue isEqual:@"edited"] &&
            [password.stringValue isEqual:@"original"],
        "late autofill preserves edited identity");
  password.stringValue = @"submitted";
  [static_cast<NSButton*>(Find(r.sheet.contentView, @"http-auth-sign-in"))
      performClick:nil];
  Pump();
  Check(count == 1 && outcome == PCHTTPAuthAccept, "explicit accept once");
  Check([user isEqual:@"edited"] && [secret isEqual:@"submitted"],
        "exact input delivered");
  Check(username.stringValue.length == 0 && password.stringValue.length == 0,
        "terminal fields cleared");
  [r invalidate];
  [r show];
  Pump();
  Check(count == 1, "terminal request cannot replay");
  r = Make(
      p, w, true,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice c, NSString* u, NSString* s) {
        ++count;
        outcome = c;
        Check(!u.length && !s.length, "cancel returns no credentials");
      });
  [r show];
  Pump();
  Check(Label(r.sheet.contentView,
              @"Your connection to this site is not private."),
        "an engine explanation means a connection that is not private");
  Check(Find(r.sheet.contentView, @"Cancel") &&
            Find(r.sheet.contentView, @"Sign in"),
        "the Cancel and Sign in buttons");
  Check(Label(r.sheet.contentView,
              @"Sign in to The proxy http://proxy.example:8080 requires a "
              @"username and password."),
        "a proxy title carries Chromium's whole proxy sentence");
  [r.sheet cancelOperation:nil];
  Pump();
  Check(count == 2 && outcome == PCHTTPAuthCancel,
        "Escape means explicit cancellation");
  [w close];
}
static void Invalidations() {
  for (int mode = 0; mode < 6; ++mode) {
    NSWindow* w = Window(mode != 0);
    NSView* p = Page(w);
    __block BOOL valid = mode != 1;
    __block int count = 0;
    __block PCHTTPAuthChoice result = PCHTTPAuthAccept;
    auto r = Make(
        p, w, false,
        ^{
          return valid;
        },
        ^(PCHTTPAuthChoice c, NSString*, NSString*) {
          ++count;
          result = c;
        });
    [r show];
    if (mode == 2) {
      [p removeFromSuperview];
    }
    if (mode == 3) {
      [r invalidate];
    }
    if (mode == 4) {
      [w close];
    }
    if (mode == 5) {
      p.hidden = YES;
    }
    Pump();
    Check(count == 1 && result == PCHTTPAuthInterrupted,
          "invalid owner cannot present or supply credentials");
    Check(!w.attachedSheet, "interrupted sheet absent");
    [r invalidate];
    Pump();
    Check(count == 1, "interruption remains once-only");
    [w close];
  }
}
static void Reentry() {
  NSWindow* w = Window();
  NSView* p = Page(w);
  __block PCHTTPAuthPresenter* r;
  __block int calls = 0;
  __block bool reenter = false;
  r = Make(
      p, w, false,
      ^{
        if (reenter) {
          [r invalidate];
        }
        return YES;
      },
      ^(PCHTTPAuthChoice c, NSString*, NSString*) {
        ++calls;
        Check(c == PCHTTPAuthInterrupted, "validation reentry interrupts");
      });
  reenter = true;
  [r show];
  Pump();
  Check(calls == 1 && !w.attachedSheet,
        "validation callback cannot resurrect presentation");
  __block PCHTTPAuthPresenter* replacement;
  r = Make(
      p, w, false,
      ^{
        return YES;
      },
      ^(PCHTTPAuthChoice, NSString*, NSString*) {
        ++calls;
        r = nil;
        replacement = Make(
            p, w, true,
            ^{
              return YES;
            },
            ^(PCHTTPAuthChoice, NSString*, NSString*) {
              ++calls;
            });
        [replacement show];
      });
  [r show];
  Pump();
  [r.sheet cancelOperation:nil];
  Pump();
  Check(calls == 2 && replacement.sheet.sheetParent == w,
        "owner release and replacement during native callback");
  [replacement invalidate];
  Pump();
  Check(calls == 3, "replacement separately completes");
  [w close];
}
int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    Decisions();
    Invalidations();
    Reentry();
    printf("NativeHTTPAuth: %d assertions passed\n", checks);
  }
}

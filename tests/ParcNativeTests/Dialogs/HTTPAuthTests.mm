#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"

#include <cstdio>
#include <cstdlib>

#import "http_auth_presenter.h"
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
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
  Check([Label(r.sheet.contentView, @"Sign in to login.example").font
            isEqual:[NSFont systemFontOfSize:18 weight:NSFontWeightMedium]] &&
            username.font.pointSize == 14 && password.font.pointSize == 14,
        "Parc's 18-point medium title and 14-point fields");
  Check(username.focusRingType == NSFocusRingTypeNone &&
            password.focusRingType == NSFocusRingTypeNone,
        "fields draw Parc's edit treatment instead of the focus ring");
  Check([username.accessibilityLabel isEqual:@"Username"] &&
            [password.accessibilityLabel isEqual:@"Password"],
        "fields keep their VoiceOver labels");
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
        "full-size-content Parc dialog at least 400 points wide");
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
  __block int keyed = 0;
  __block PCHTTPAuthChoice keyedChoice = PCHTTPAuthInterrupted;
  auto keyResult = ^(PCHTTPAuthChoice c, NSString*, NSString*) {
    ++keyed;
    keyedChoice = c;
  };
  auto key = ^NSEvent*(NSWindow* sheet, NSString* characters, unsigned short code) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:0
                           timestamp:NSProcessInfo.processInfo.systemUptime
                        windowNumber:sheet.windowNumber
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:characters
                           isARepeat:NO
                             keyCode:code];
  };
  r = Make(p, w, false, ^{ return YES; }, keyResult);
  [r show];
  Pump();
  auto field = static_cast<NSTextField*>(Find(r.sheet.contentView, @"http-auth-username"));
  auto editor = static_cast<NSTextView*>(field.currentEditor);
  Check([editor isKindOfClass:NSTextView.class], "username edits when the sheet opens");
  [editor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0)
       replacementRange:NSMakeRange(NSNotFound, 0)];
  Check(![r.sheet performKeyEquivalent:key(r.sheet, @"\r", 36)] &&
            ![r.sheet performKeyEquivalent:key(r.sheet, @"\033", 53)],
        "Return and Escape go to the input method while composing");
  Pump();
  Check(keyed == 0, "composition never answers the sign-in sheet");
  [editor unmarkText];
  auto secretField = static_cast<NSTextField*>(Find(r.sheet.contentView, @"http-auth-password"));
  [r.sheet makeFirstResponder:secretField];
  auto secretEditor = static_cast<NSTextView*>(secretField.currentEditor);
  [secretEditor setMarkedText:@"か" selectedRange:NSMakeRange(1, 0)
             replacementRange:NSMakeRange(NSNotFound, 0)];
  if (secretEditor.hasMarkedText) {
    Check(![r.sheet performKeyEquivalent:key(r.sheet, @"\r", 36)] &&
              ![r.sheet performKeyEquivalent:key(r.sheet, @"\033", 53)],
          "composition in the password field keeps Return and Escape");
    [secretEditor unmarkText];
  }
  Pump();
  Check(keyed == 0, "password-field composition never answers the sheet");
  [r.sheet makeFirstResponder:Find(r.sheet.contentView, @"http-auth-cancel")];
  Check([r.sheet performKeyEquivalent:key(r.sheet, @"\r", 36)],
        "Return signs in with focus on a button");
  Pump();
  Check(keyed == 1 && keyedChoice == PCHTTPAuthAccept, "Return from any focus signs in");
  r = Make(p, w, false, ^{ return YES; }, keyResult);
  [r show];
  Pump();
  Check([r.sheet performKeyEquivalent:key(r.sheet, @"\003", 76)], "keypad Enter is handled");
  Pump();
  Check(keyed == 2 && keyedChoice == PCHTTPAuthAccept, "keypad Enter signs in");
  r = Make(p, w, false, ^{ return YES; }, keyResult);
  [r show];
  Pump();
  [r.sheet makeFirstResponder:nil];
  Check([r.sheet performKeyEquivalent:key(r.sheet, @"\033", 53)],
        "Escape is handled without a focused field");
  Pump();
  Check(keyed == 3 && keyedChoice == PCHTTPAuthCancel, "Escape from any focus cancels");
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
@interface HTTPAuthTests : ParcNativeTestCase
@end

@implementation HTTPAuthTests

- (void)testDecisions {
  Decisions();
}

- (void)testInvalidations {
  Invalidations();
}

- (void)testReentry {
  Reentry();
}

@end

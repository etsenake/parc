#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#import "http_auth_presenter.h"
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace HTTPAuthTestsSupport {
static inline void SendClick(NSControl* control) {
  if (!control.enabled) return;
  [control.cell setNextState];
  [control sendAction:control.action to:control.target];
}

static inline void Pump() {
  ParcNativeAdvance(.08);
}
static inline NSWindow* Window(bool visible = true) {
  NSWindow* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2300, -2300, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  if (visible) {
    ParcNativeMarkVisible(w);
  }
  return w;
}
static inline NSView* Page(NSWindow* w) {
  NSView* p = [[NSView alloc] initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:p];
  return p;
}
static inline NSTextField* Label(NSView* v, NSString* text) {
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
static inline NSView* Find(NSView* v, NSString* name) {
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
static inline PCHTTPAuthPresenter* Make(NSView* p,
                                 NSWindow* w,
                                 bool proxy,
                                 BOOL (^valid)(void),
                                 void (^result)(PCHTTPAuthChoice,
                                                NSString*,
                                                NSString*)) {
  PCHTTPAuthPresenter* presenter = [[PCHTTPAuthPresenter alloc]
      initWithPage:p
            window:w
         authority:proxy ? @"The proxy http://proxy.example:8080 requires a "
                           @"username and password."
                         : @"https://login.example:8443"
       explanation:proxy ? @"Your connection is not private." : @""
             proxy:proxy
          validate:valid
            result:result];
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
}

@interface HTTPAuthTestsState : NSObject
@property int count;
@property PCHTTPAuthChoice outcome;
@property(copy) NSString* user;
@property(copy) NSString* secret;
@end

namespace HTTPAuthTestsSupport {
static inline NSTextField* UsernameField(PCHTTPAuthPresenter* r) {
  return static_cast<NSTextField*>(Find(r.sheet.contentView, @"http-auth-username"));
}
static inline NSSecureTextField* PasswordField(PCHTTPAuthPresenter* r) {
  return static_cast<NSSecureTextField*>(Find(r.sheet.contentView, @"http-auth-password"));
}
static inline NSEvent* KeyDown(NSWindow* sheet, NSString* characters, unsigned short code) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:ParcNativeNow()
                      windowNumber:sheet.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:NO
                           keyCode:code];
}

}

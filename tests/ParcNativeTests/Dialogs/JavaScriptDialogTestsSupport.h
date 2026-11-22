#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#include <cstdio>
#include <cstdlib>

#import "javascript_dialog_presenter.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace JavaScriptDialogTestsSupportFunctions {
static inline void SendClick(NSControl* control) {
  if (!control.enabled) return;
  [control.cell setNextState];
  [control sendAction:control.action to:control.target];
}

static inline PCJavaScriptDialogPresenter* Offscreen(PCJavaScriptDialogPresenter* presenter) NS_RETURNS_RETAINED {
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
static inline void Drain(void) {
  ParcNativeAdvance(0.12);
}
static inline NSWindow* Window(void) {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2000, -2000, 640, 480)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  ParcNativeMarkVisible(window);
  return window;
}
static inline NSView* Page(NSWindow* window) {
  NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:page];
  return page;
}
static inline NSButton* Button(NSView* view, NSString* title) {
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
static inline NSTextField* Input(NSView* view) {
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
static inline void EnableAfterDelay(NSButton* button) {
  ParcNativeAdvance(0.5);
  PARC_CHECK(button.enabled);
}
static inline void Click(PCJavaScriptDialogPresenter* presenter, NSString* title) {
  NSButton* button = Button(presenter.presentedSheet.contentView, title);
  Check(button != nil, "actual native sheet contains requested button");
  EnableAfterDelay(button);
  SendClick(button);
  Drain();
}
static inline NSEvent* Key(NSWindow* window, NSString* characters, unsigned short code,
                    NSTimeInterval timestamp, BOOL repeat = NO) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown
                          location:NSZeroPoint
                     modifierFlags:0
                         timestamp:timestamp
                      windowNumber:window.windowNumber
                           context:nil
                        characters:characters
       charactersIgnoringModifiers:characters
                         isARepeat:repeat
                           keyCode:code];
}
static inline NSTimeInterval Now(void) {
  return ParcNativeNow();
}
static inline void Present(PCJavaScriptDialogPresenter* presenter,
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
static inline NSTextField* Label(NSView* view, NSString* text) {
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

}

@interface JavaScriptDialogTestsSupport : ParcNativeTestCase {
@protected
  NSWindow* _window;
  NSView* _page;
  PCJavaScriptDialogPresenter* _presenter;
  NSUInteger _results;
  BOOL _accepted;
  BOOL _suppressed;
  NSString* _input;
}
- (PCJavaScriptDialogCompletion)completion;
- (NSWindow*)present:(PCJavaScriptDialogKind)kind suppression:(BOOL)suppression;
- (NSWindow*)present:(PCJavaScriptDialogKind)kind;
@end

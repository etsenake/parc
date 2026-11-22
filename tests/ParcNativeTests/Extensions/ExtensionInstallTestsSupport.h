#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#import "extension_install_presenter.h"
#import "window_security_reservation.h"
#define EXPECT(condition) PARC_CHECK(condition)
namespace ExtensionInstallTestsSupportFunctions {
static inline void SendClick(NSControl* control) {
  if (!control.enabled) return;
  [control.cell setNextState];
  [control sendAction:control.action to:control.target];
}

static inline void Pump(double seconds = .12) {
  ParcNativeAdvance(seconds);
}
static inline NSWindow* Window() {
  auto* w = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-20000, -20000, 600, 500)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  w.releasedWhenClosed = NO;
  ParcNativeMarkVisible(w);
  return w;
}
static inline NSButton* Button(NSView* root, NSString* title) {
  if ([root isKindOfClass:NSButton.class] &&
      [((NSButton*)root).title isEqual:title]) {
    return (NSButton*)root;
  }
  for (NSView* child in root.subviews) {
    if (auto* b = Button(child, title)) {
      return b;
    }
  }
  return nil;
}
static inline NSScrollView* Scroll(NSView* root) {
  if ([root isKindOfClass:NSScrollView.class]) {
    return (NSScrollView*)root;
  }
  for (NSView* child in root.subviews) {
    if (auto* scroll = Scroll(child)) {
      return scroll;
    }
  }
  return nil;
}
static inline BOOL Text(NSView* root, NSString* expected) {
  if ([root isKindOfClass:NSTextField.class] &&
      [((NSTextField*)root).stringValue isEqual:expected]) {
    return YES;
  }
  for (NSView* child in root.subviews) {
    if (Text(child, expected)) {
      return YES;
    }
  }
  return NO;
}
static inline NSView* View(NSView* root, NSString* className) {
  if ([root.className isEqual:className]) {
    return root;
  }
  for (NSView* child in root.subviews) {
    if (auto* view = View(child, className)) {
      return view;
    }
  }
  return nil;
}
static inline BOOL Near(CGFloat a, CGFloat b) {
  return std::abs(a - b) < .01;
}
static inline void ExpectDialogFrame(NSWindow* sheet, NSScrollView* scroll) {
  NSView* root = sheet.contentView;
  NSButton* add = Button(root, @"Add Extension");
  EXPECT(Near(NSHeight(scroll.frame),
              std::min<CGFloat>(NSHeight(scroll.documentView.frame), 113)));
  EXPECT(Near(NSMinY(add.frame) + .5, NSMaxY(scroll.frame) + 8));
  EXPECT(std::abs(NSHeight(root.frame) - (NSMinY(add.frame) + .5 + 36 + 28)) < 1);
  EXPECT(NSEqualSizes(sheet.frame.size, root.frame.size));
}
static inline BOOL Fill(NSWindow* sheet, CGFloat x, CGFloat y, int r, int g, int b) {
  NSView* root = sheet.contentView;
  NSBitmapImageRep* rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
  [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
  NSColor* c = [rep colorAtX:(NSInteger)(x * rep.pixelsWide / NSWidth(root.bounds))
                           y:(NSInteger)(y * rep.pixelsHigh / NSHeight(root.bounds))];
  NSColor* expected = [[NSColor colorWithSRGBRed:r / 255. green:g / 255. blue:b / 255. alpha:1]
      colorUsingColorSpace:rep.colorSpace];
  return root.opaque && c.alphaComponent > .99 &&
         std::abs(c.redComponent - expected.redComponent) < 1.5 / 255 &&
         std::abs(c.greenComponent - expected.greenComponent) < 1.5 / 255 &&
         std::abs(c.blueComponent - expected.blueComponent) < 1.5 / 255;
}
static inline NSTimeInterval Uptime() {
  return ParcNativeNow();
}
static inline BOOL Key(NSWindow* sheet, NSString* key, unsigned short code,
                NSTimeInterval timestamp, BOOL repeat = NO) {
  return [sheet performKeyEquivalent:[NSEvent keyEventWithType:NSEventTypeKeyDown
                                                       location:NSZeroPoint
                                                  modifierFlags:0
                                                      timestamp:timestamp
                                                   windowNumber:sheet.windowNumber
                                                        context:nil
                                                     characters:key
                                    charactersIgnoringModifiers:key
                                                      isARepeat:repeat
                                                        keyCode:code]];
}
static inline PCExtensionInstallPresenter* Make(
    NSWindow* w,
    BOOL (^valid)(),
    BOOL (^input)(NSWindow*),
    void (^result)(PCExtensionInstallChoice, BOOL)) {
  PCExtensionInstallPresenter* presenter = [[PCExtensionInstallPresenter alloc]
      initWithWindow:w
               title:@"Add example?"
                icon:nil
             heading:@"It can:"
         permissions:@[
           @"Read and change data on example.test", @"Read browsing history"
         ]
             details:@[ @"example.test", @"" ]
         acceptLabel:@"Add"
         cancelLabel:@"Cancel"
       checkboxLabel:@"Grant host permissions"
            validate:valid
        inputAllowed:input
              result:result];
  presenter.presentation = ParcNativePresentation();
  presenter.scheduler = ParcNativeScheduler();
  return presenter;
}
}

@interface ExtensionInstallTestsSupport : ParcNativeTestCase {
@protected
  NSWindow* _w;
  int _results;
  PCExtensionInstallChoice _choice;
  BOOL _grants;
  BOOL _input;
}
- (void (^)(PCExtensionInstallChoice, BOOL))result;
- (BOOL (^)(NSWindow*))inputAllowed;
- (PCExtensionInstallPresenter*)makeValidating:(BOOL (^)(void))valid;
- (PCExtensionInstallPresenter*)make;
- (PCExtensionInstallPresenter*)shownPresenter;
- (PCExtensionInstallPresenter*)upstreamPresenterWithPermissions:(NSArray*)permissions details:(NSArray*)details;
@end

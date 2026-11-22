#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"
#import "native_appkit_bridge.h"
#import "status_text.h"
#include <cstdio>
#include <cstdlib>

@interface PCNativeStatusTextController (StatusTextTestsPointerChecks)
- (void)updatePointerInOverlay:(NSPoint)point;
- (void)updateModifierFlags:(NSEventModifierFlags)flags;
- (BOOL)hasMouseMovedMonitor;
- (BOOL)pointerAvoidanceWouldLayoutAt:(NSPoint)point;
@end
@interface StatusTextTestsStatusTheme : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSColor* background;
@property(nonatomic, strong) NSAppearance* appearance;
@end
#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace StatusTextTestsSupportFunctions {
static inline void Pump(double seconds) {
  ParcNativeAdvance(seconds);
}
static inline NSView* Find(NSView* view, NSString* name) {
  if ([view.identifier isEqual:name]) { return view; }
  for (NSView* child in view.subviews) {
    if (NSView* match = Find(child, name)) { return match; }
  }
  return nil;
}
static inline NSWindow* Window() {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(-2400, -2400, 920, 500)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  ParcNativeMarkVisible(window);
  return window;
}
static inline NSView* Page(NSWindow* window) {
  NSView* page = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:page];
  return page;
}
static inline PCNativeStatusTextController* Controller(NSView* page) {
  auto controller = [[PCNativeStatusTextController alloc]
      initWithPage:page validate:^BOOL { return YES; }];
  controller.presentation = ParcNativePresentation();
  controller.scheduler = ParcNativeScheduler();
  [controller setAttached:YES];
  return controller;
}
static inline NSString* LongText() {
  return [@"https://example.test/" stringByPaddingToLength:250
      withString:@"a-very-long-path/" startingAtIndex:0];
}

}

@interface StatusTextTestsSupport : ParcNativeTestCase {
@protected
  NSWindow* window;
  NSView* page;
  PCNativeStatusTextController* controller;
  NSView* overlay;
  NSView* pill;
  NSTextField* label;
  NSImageView* icon;
}
- (void)attach;
- (void)show:(NSString*)text;
@end

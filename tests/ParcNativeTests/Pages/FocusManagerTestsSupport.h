#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"

#include <cstdio>
#include <cstdlib>

#import "focus_manager.h"
#import "page_host.h"

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
@interface FocusManagerTestsFocusView : NSView
@property(nonatomic) BOOL acceptsFocus;
@property(nonatomic) NSUInteger requests;
@end

@interface FocusManagerTestsGateWindow : NSWindow
@property(nonatomic, weak) NSResponder* blockedTarget;
@property(nonatomic) BOOL acceptWithoutChanging;
@property(nonatomic) NSUInteger blockedRequests;
@property(nonatomic) BOOL reportsNilResponder;
- (void)simulateMissingFirstResponder;
@end

namespace FocusManagerTestsSupport {
static inline PCNativeFocusManager* Offscreen(PCNativeFocusManager* manager) NS_RETURNS_RETAINED {
  manager.scheduler = ParcNativeScheduler();
  return manager;
}
static inline PCNativePageHost* Offscreen(PCNativePageHost* host) NS_RETURNS_RETAINED {
  host.presentation = ParcNativePresentation();
  host.scheduler = ParcNativeScheduler();
  return host;
}
static inline NSWindow* Window(Class cls = NSWindow.class) {
  NSWindow* window = [[cls alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 320)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}
static inline FocusManagerTestsFocusView* View(NSWindow* window) {
  FocusManagerTestsFocusView* view = [[FocusManagerTestsFocusView alloc] initWithFrame:NSMakeRect(0, 0, 100, 50)];
  [window.contentView addSubview:view];
  return view;
}
static inline void Drain(void) {
  ParcNativeSettle();
}
static inline PCNativeFocusRegistration* Register(PCNativeFocusManager* manager,
                                           NSResponder* responder,
                                           NSString* key) {
  PCNativeFocusRegistration* token = [manager registerResponder:responder
                                                         forKey:key
                                                      didBecome:nil
                                                      didResign:nil];
  Check(token != nil, "native responder registration succeeds");
  return token;
}

}

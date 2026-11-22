#pragma once

#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import <QuartzCore/QuartzCore.h>
#import "page_host.h"
#import "pane_compositor_view.h"
#import "devtools_pane_view.h"

#include <cstdio>
#include <cstdlib>


#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

@interface PageHostTestsRendererView : NSView
@property(nonatomic) BOOL acceptsFocus;
@property(nonatomic) NSUInteger focusRequests;
@end

@interface PageHostTestsHostObserver : NSObject <PCNativePageHostObserver>
@property(nonatomic, strong) NSMutableArray<NSString *> *moves;
@property(nonatomic, weak) NSWindow *lastWindow;
@property(nonatomic) NSUInteger focusAttempts;
@end

@interface PageHostTestsReentrantView : NSView
@property(nonatomic, copy) void (^didAttach)(void);
@end

@interface PCNativePageHost (PageHostTestsVisibilityRegression)
- (BOOL)setContentVisible:(BOOL)visible inWindow:(NSWindow *)window;
@end

@interface PageHostTestsVisibilityView : NSView
@property(nonatomic, copy) void (^visibilityChanged)(void);
@property(nonatomic) NSUInteger hiddenChanges;
@end

@interface PageHostTestsLayoutView : NSView
@property(nonatomic) NSUInteger subtreeLayouts;
@property(nonatomic, copy) void (^didLayout)(void);
@end

@interface PCNativePageHost (PageHostTestsRendererResponder)
- (NSView *)rendererResponder;
@end

namespace PageHostTestsSupport {

inline PCNativePageHost *Offscreen(PCNativePageHost *host) NS_RETURNS_RETAINED {
  host.presentation = ParcNativePresentation();
  host.scheduler = ParcNativeScheduler();
  return host;
}
inline NSWindow *Window(void) {
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 320)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

inline NSView *Page(PageHostTestsRendererView *__strong *rendererOut) {
  NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(13, 17, 240, 150)];
  PageHostTestsRendererView *renderer = [[PageHostTestsRendererView alloc] initWithFrame:page.bounds];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  if (rendererOut) *rendererOut = renderer;
  return page;
}

inline PageHostTestsRendererView *SetSentinel(NSWindow *window) {
  PageHostTestsRendererView *sentinel = [[PageHostTestsRendererView alloc] initWithFrame:NSZeroRect];
  [window.contentView addSubview:sentinel];
  Check([window makeFirstResponder:sentinel], "set native sentinel responder");
  return sentinel;
}

inline void DrainMainQueue(void) {
  ParcNativeSettle();
}

struct PageFixture {
  NSWindow* window = Window();
  PageHostTestsRendererView* renderer = nil;
  NSView* page = Page(&renderer);
  PageHostTestsHostObserver* observer = [PageHostTestsHostObserver new];
  PCNativePageHost* host = Offscreen([PCNativePageHost hostWithContentView:page observer:observer]);

  void Attach() { [window.contentView addSubview:host]; }
  ~PageFixture() {
    [host invalidate];
    ParcNativeClose(window);
  }
};

struct FreshPage {
  NSWindow* window = Window();
  PageHostTestsLayoutView* page = [[PageHostTestsLayoutView alloc] initWithFrame:NSZeroRect];
  PageHostTestsRendererView* renderer = [[PageHostTestsRendererView alloc] initWithFrame:NSZeroRect];
  PCNativePaneCompositorView* display = [[PCNativePaneCompositorView alloc] initWithHostedLayer:[CALayer layer]];
  PCNativePageHost* host;
  PCNativeDevToolsPaneView* pane;
  explicit FreshPage(BOOL initiallyHidden) {
    NSView *wrapper = [[NSView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:wrapper];
    [window.contentView layoutSubtreeIfNeeded];
    page.hidden = initiallyHidden;
    renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [page addSubview:renderer];
    [page addSubview:display];
    host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
    pane = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:host];
    pane.frame = wrapper.bounds;
    [wrapper addSubview:pane];
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
  }
  ~FreshPage() {
    [pane invalidate];
    [host invalidate];
    ParcNativeClose(window);
  }
};

struct CompositorFixture : PageFixture {
  PCNativePaneCompositorView* overlay = [[PCNativePaneCompositorView alloc] initWithHostedLayer:[CALayer layer]];
  NSUInteger geometryChanges = 0;
  NSUInteger screenChanges = 0;
  BOOL lastOnScreen = NO;
  CompositorFixture() {
    Attach();
    overlay.geometryHandler = ^{ ++geometryChanges; };
    overlay.screenHandler = ^{ ++screenChanges; lastOnScreen = overlay.onScreen; };
  }
  ~CompositorFixture() {
    overlay.geometryHandler = nil;
    overlay.screenHandler = nil;
  }
};
}

// Copyright 2026 Parc contributors.
//
// initWithFrame:] 0x4737074 installs PaneHostCompositorOverlayView, its
// viewDidMoveToWindow 0x4737c38 observes the window's screen changes, and its
// viewDidHide/viewDidUnhide 0x4737e14/0x4737e64 resynchronize the hosted page.
#import "pane_compositor_view.h"

@implementation PCNativePaneCompositorView {
  NSWindow* __weak _observedWindow;
}
@synthesize geometryHandler = _geometryHandler;
@synthesize screenHandler = _screenHandler;

- (instancetype)initWithHostedLayer:(CALayer*)layer {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    // Layer-hosting: the layer is set before wantsLayer so AppKit adopts it
    // instead of creating its own (as Chromium's renderer view does).
    self.layer = layer;
    self.wantsLayer = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)isOpaque {
  return NO;
}

- (NSView*)hitTest:(NSPoint)point {
  return nil;
}

- (BOOL)acceptsFirstResponder {
  return NO;
}

- (BOOL)isAccessibilityElement {
  return NO;
}

- (NSArray*)accessibilityChildren {
  return @[];
}

- (BOOL)isOnScreen {
  return self.window && !self.hiddenOrHasHiddenAncestor;
}

- (void)setFrameSize:(NSSize)size {
  const NSSize previous = self.frame.size;
  [super setFrameSize:size];
  if (!NSEqualSizes(previous, size)) {
    [self geometryChanged];
  }
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  NSWindow* window = self.window;
  if (window != _observedWindow) {
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self
                      name:NSWindowDidChangeScreenNotification
                    object:nil];
    _observedWindow = window;
    if (window) {
      [center addObserver:self
                 selector:@selector(windowDidChangeScreen:)
                     name:NSWindowDidChangeScreenNotification
                   object:window];
    }
  }
  [self screenChanged];
  [self geometryChanged];
}

- (void)viewDidHide {
  [super viewDidHide];
  [self screenChanged];
}

- (void)viewDidUnhide {
  [super viewDidUnhide];
  [self screenChanged];
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  [self geometryChanged];
}

- (void)windowDidChangeScreen:(NSNotification*)notification {
  [self geometryChanged];
}

- (void)screenChanged {
  void (^handler)(void) = self.screenHandler;
  if (handler) {
    handler();
  }
}

- (void)geometryChanged {
  void (^handler)(void) = self.geometryHandler;
  if (handler) {
    handler();
  }
}

@end

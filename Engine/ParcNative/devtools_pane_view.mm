// Copyright 2026 Parc contributors.
#import "devtools_pane_view.h"

@interface PCDevToolsOverlay : NSView
@end
@implementation PCDevToolsOverlay
- (BOOL)isFlipped {
  return YES;
}
- (NSView*)hitTest:(NSPoint)point {
  NSView* hit = [super hitTest:point];
  return hit == self ? nil : hit;
}
@end
@interface PCDevToolsScrim : NSView
@end
@implementation PCDevToolsScrim
- (BOOL)isFlipped {
  return YES;
}
- (void)drawRect:(NSRect)rect {
  [[NSColor colorWithWhite:0 alpha:0.25] setFill];
  NSRectFill(rect);
}
@end
namespace {
void SetFrameIfNeeded(NSView* view, NSRect frame) {
  if (view && !NSEqualRects(view.frame, frame)) {
    view.frame = frame;
  }
}
void SetHiddenIfNeeded(NSView* view, BOOL hidden) {
  if (view && view.hidden != hidden) {
    view.hidden = hidden;
  }
}
}  // namespace

@implementation PCNativeDevToolsPaneView {
  NSView* _inspectedView;
  NSView* _inspectedOverlay;
  NSView* _toolsView;
  PCDevToolsScrim* _scrim;
  BOOL _invalidated;
  BOOL _applyingLayout;
  NSUInteger _generation;
}
@synthesize layoutHandler = _layoutHandler;
- (instancetype)initWithInspectedView:(NSView*)view {
  self = [super initWithFrame:view.frame];
  if (self) {
    _inspectedView = view;
    _inspectedOverlay = [[PCDevToolsOverlay alloc] initWithFrame:self.bounds];
    _scrim = [[PCDevToolsScrim alloc] initWithFrame:NSZeroRect];
    _scrim.hidden = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:view];
    [self addSubview:_inspectedOverlay];
    [self addSubview:_scrim];
  }
  return self;
}
- (BOOL)isFlipped {
  return YES;
}
- (NSView*)inspectedView {
  return _inspectedView;
}
- (NSView*)inspectedOverlay {
  return _inspectedOverlay;
}
- (NSView*)toolsView {
  return _toolsView;
}
- (void)layout {
  [super layout];
  __attribute__((objc_precise_lifetime)) PCNativeDevToolsPaneView* keep = self;
  if (keep->_invalidated || keep->_applyingLayout || !self.layoutHandler) {
    return;
  }
  keep->_applyingLayout = YES;
  self.layoutHandler(self.bounds);
  keep->_applyingLayout = NO;
}
- (BOOL)setHostedToolsView:(NSView*)view {
  __attribute__((objc_precise_lifetime)) PCNativeDevToolsPaneView* keep = self;
  if (_invalidated || view == self || view == _inspectedView ||
      (view && [self isDescendantOf:view])) {
    return NO;
  }
  if (_toolsView == view) {
    return !view || view.superview == self;
  }
  const NSUInteger generation = ++_generation;
  NSView* old = _toolsView;
  _toolsView = nil;
  if (old.superview == self) {
    [old removeFromSuperview];
  }
  if (keep->_invalidated || generation != _generation) {
    return NO;
  }
  _toolsView = view;
  if (view) {
    [self addSubview:view positioned:NSWindowBelow relativeTo:_inspectedView];
  }
  if (_invalidated || generation != _generation) {
    return NO;
  }
  self.needsLayout = YES;
  return !view || view.superview == self;
}
- (void)applyInspectedRect:(NSRect)inspected
                 toolsRect:(NSRect)tools
             hideInspected:(BOOL)hidden {
  __attribute__((objc_precise_lifetime)) PCNativeDevToolsPaneView* keep = self;
  if (_invalidated || _inspectedView.superview != self ||
      (_toolsView && _toolsView.superview != self)) {
    return;
  }
  const NSUInteger generation = _generation;
  const auto still_owns = [&] {
    return !keep->_invalidated && generation == _generation &&
           _inspectedView.superview == self &&
           (!_toolsView || _toolsView.superview == self);
  };
  struct ApplyingLayout {
    BOOL* flag;
    BOOL nested;
    explicit ApplyingLayout(BOOL* value) : flag(value), nested(*value) {
      *flag = YES;
    }
    ~ApplyingLayout() {
      if (!nested) {
        *flag = NO;
      }
    }
  } applying(&_applyingLayout);
  SetFrameIfNeeded(_inspectedView, inspected);
  if (!still_owns()) {
    return;
  }
  SetFrameIfNeeded(_inspectedOverlay, inspected);
  if (!still_owns()) {
    return;
  }
  SetHiddenIfNeeded(_inspectedView, hidden);
  if (!still_owns()) {
    return;
  }
  SetHiddenIfNeeded(_inspectedOverlay, hidden);
  if (!still_owns()) {
    return;
  }
  SetFrameIfNeeded(_toolsView, tools);
  if (!still_owns()) {
    return;
  }
  SetFrameIfNeeded(_scrim, tools);
}
- (BOOL)focusTools {
  __attribute__((objc_precise_lifetime)) PCNativeDevToolsPaneView* keep = self;
  if (_invalidated || !_toolsView || _toolsView.superview != self) {
    return NO;
  }
  NSWindow* window = self.window;
  if (!window || _toolsView.window != window) {
    return NO;
  }
  return [window makeFirstResponder:_toolsView];
}
- (void)setToolsBlocked:(BOOL)blocked {
  if (!_invalidated && _toolsView && _toolsView.superview == self) {
    _scrim.hidden = !blocked;
  }
}
- (void)invalidate {
  __attribute__((objc_precise_lifetime)) PCNativeDevToolsPaneView* keep = self;
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  ++_generation;
  self.layoutHandler = nil;
  NSView* tools = _toolsView;
  _toolsView = nil;
  if (tools.superview == self) {
    [tools removeFromSuperview];
  }
  if (_inspectedView.superview == self) {
    [_inspectedView removeFromSuperview];
  }
  [keep removeFromSuperview];
}
@end

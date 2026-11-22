#import "page_host.h"

#import "dialog_style.h"
#import "pane_compositor_view.h"

@interface PCNativeHistoryOverlayContainerView : NSView
@end

@implementation PCNativeHistoryOverlayContainerView
- (BOOL)acceptsFirstResponder {
  return NO;
}
- (NSView *)hitTest:(NSPoint)point {
  return nil;
}
@end

@interface PCNativePageHost () {
  NSView *_contentView;
  NSArray<NSLayoutConstraint *> *_contentConstraints;
  NSView *_infobarView;
  NSArray<NSLayoutConstraint *> *_infobarConstraints;
  NSLayoutConstraint *_infobarHeight;
  NSLayoutConstraint *_contentTop;
  NSView *_historyOverlayContainer;
  __weak id<PCNativePageHostObserver> _observer;
  BOOL _invalidated;
  NSUInteger _visibilityGeneration;
}
- (instancetype)initWithContentView:(NSView *)contentView
                           observer:(nullable id<PCNativePageHostObserver>)observer;
- (void)pinContentView:(NSView *)contentView;
- (nullable NSView *)rendererResponder;
@end

@implementation PCNativePageHost
@synthesize presentation = _presentation;
@synthesize scheduler = _scheduler;

+ (instancetype)hostWithContentView:(NSView *)contentView
                          observer:(id<PCNativePageHostObserver>)observer {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  NSParameterAssert(contentView);
  // The original checks exact class membership, not isKindOfClass:. Reuse
  // leaves the original observer intact, including when it has become nil.
  NSView *parent = contentView.superview;
  if ([parent isMemberOfClass:PCNativePageHost.class]) {
    return (PCNativePageHost *)parent;
  }
  return [[PCNativePageHost alloc] initWithContentView:contentView
                                             observer:observer];
}

- (instancetype)initWithContentView:(NSView *)contentView
                           observer:(id<PCNativePageHostObserver>)observer {
  self = [super initWithFrame:contentView.frame];
  if (self) {
    _observer = observer;
    _presentation = PCNativeSystemPresentation.sharedPresentation;
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
    _contentView = contentView;
    [self addSubview:contentView];
    [self pinContentView:contentView];
  }
  return self;
}

- (NSView *)contentView {
  return _contentView;
}

- (void)setFrameSize:(NSSize)size {
  const NSSize previous = self.frame.size;
  [super setFrameSize:size];
  // AppKit does not necessarily mark a manually framed host dirty until a
  // later window pass. Its edge-constrained content needs this size now.
  if (!NSEqualSizes(previous, self.frame.size)) {
    self.needsLayout = YES;
  }
}

- (void)pinContentView:(NSView *)contentView {
  contentView.translatesAutoresizingMaskIntoConstraints = NO;
  _contentTop = [contentView.topAnchor constraintEqualToAnchor:
      _infobarView ? _infobarView.bottomAnchor : self.topAnchor];
  _contentConstraints = @[
    [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    _contentTop,
    [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
  ];
  [NSLayoutConstraint activateConstraints:_contentConstraints];
  self.needsLayout = YES;
}

- (void)setInfobarView:(NSView *)view preferredHeight:(CGFloat)height {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated || view == self || view == _contentView ||
      (view && [self isDescendantOf:view])) return;
  if (view == _infobarView) {
    if (_infobarHeight.constant != MAX(0, height)) {
      _infobarHeight.constant = MAX(0, height);
      self.needsLayout = YES;
    }
    return;
  }
  [NSLayoutConstraint deactivateConstraints:_infobarConstraints ?: @[]];
  _infobarConstraints = nil;
  _infobarHeight = nil;
  [_infobarView removeFromSuperview];
  _infobarView = view;
  if (view) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:view];
    if (_invalidated || view.superview != self) return;
    _infobarHeight = [view.heightAnchor constraintEqualToConstant:MAX(0, height)];
    _infobarHeight.priority = NSLayoutPriorityDefaultHigh;
    _infobarConstraints = @[
      [view.topAnchor constraintEqualToAnchor:self.topAnchor],
      [view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [view.heightAnchor constraintGreaterThanOrEqualToConstant:0],
      [view.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.5],
      _infobarHeight,
    ];
    [NSLayoutConstraint activateConstraints:_infobarConstraints];
  }
  if (_contentView) {
    [NSLayoutConstraint deactivateConstraints:_contentConstraints];
    [self pinContentView:_contentView];
  }
}

- (BOOL)replaceContentView:(NSView *)contentView {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  NSView *previous = _contentView;
  if (_invalidated || !contentView || !previous ||
      contentView == self || [self isDescendantOf:contentView]) {
    return NO;
  }
  if (contentView == previous) {
    return YES;
  }
  [NSLayoutConstraint deactivateConstraints:_contentConstraints];
  _contentConstraints = nil;
  _contentView = nil;
  [self replaceSubview:previous with:contentView];
  // A native child can run callbacks during reparenting. Do not resurrect a
  // host invalidated by one of those callbacks.
  if (_invalidated || contentView.superview != self) {
    if (contentView.superview == self) {
      [contentView removeFromSuperview];
    }
    return NO;
  }
  _contentView = contentView;
  [self pinContentView:contentView];
  return YES;
}

- (BOOL)restoreContentView:(NSView *)contentView {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated || _contentView || !contentView || contentView.superview ||
      contentView == self || [self isDescendantOf:contentView]) {
    return NO;
  }
  // The managed content is the first subview, below the infobar shelf.
  [self addSubview:contentView positioned:NSWindowBelow relativeTo:nil];
  // Reparenting can run native callbacks; one may have invalidated this host
  // or installed other content.
  if (_invalidated || _contentView || contentView.superview != self) {
    if (contentView.superview == self) {
      [contentView removeFromSuperview];
    }
    return NO;
  }
  _contentView = contentView;
  [self pinContentView:contentView];
  return YES;
}

- (void)willRemoveSubview:(NSView *)subview {
  if (subview == _contentView) {
    [NSLayoutConstraint deactivateConstraints:_contentConstraints];
    _contentConstraints = nil;
    _contentView = nil;
  }
  [super willRemoveSubview:subview];
}

- (BOOL)setContentVisible:(BOOL)visible inWindow:(NSWindow *)window {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  PCNativePageHost *host = self;
  NSView *content = _contentView;
  NSView *parent = self.superview;
  if (_invalidated || !content || !parent || !window || self.window != window ||
      content.superview != self || content.window != window ||
      (visible && self.hiddenOrHasHiddenAncestor)) {
    return NO;
  }
  const NSUInteger generation = ++_visibilityGeneration;
  const auto still_current = [&] {
    return !host->_invalidated && host->_visibilityGeneration == generation &&
           host->_contentView == content && host.superview == parent &&
           content.superview == host && host.window == window &&
           content.window == window &&
           (!visible || !host.hiddenOrHasHiddenAncestor);
  };
  // A fresh tab's pane sizes this host before AppKit has solved the managed
  // content's edge constraints. The outer pane can already be clean while
  // the WebContents view and its renderer are still 0x0. Settle that dirty
  // host before showing it, without waiting for another window/input event.
  // Clean hosts keep the no-op path: no walk through Chromium's view tree.
  if (visible && host.needsLayout) {
    [host layoutSubtreeIfNeeded];
    if (!still_current()) {
      return NO;
    }
  }
  // Current Chromium's WebContentsViewMac creates the actual container hidden
  // for NEW_BACKGROUND_TAB. Its normal NativeViewHostMac explicitly shows the
  // container; WebContents::WasShown only shows the renderer child. This is the
  // equivalent native-host step, independent of focus or mere attachment.
  if (content.hidden == visible) {
    content.hidden = !visible;
  }
  // Layout and setHidden can synchronously notify native/engine observers.
  // Never finish an old owner's operation or supersede a newer show/hide.
  return still_current() && content.hidden == !visible;
}

- (NSView *)historyOverlayContainer {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated) {
    return nil;
  }
  if (!_historyOverlayContainer) {
    _historyOverlayContainer =
        [[PCNativeHistoryOverlayContainerView alloc] initWithFrame:self.bounds];
    _historyOverlayContainer.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;
    _historyOverlayContainer.clipsToBounds = YES;
  }
  if (self.subviews.lastObject != _historyOverlayContainer) {
    [self addSubview:_historyOverlayContainer positioned:NSWindowAbove
          relativeTo:nil];
  }
  if (_invalidated || _historyOverlayContainer.superview != self) {
    return nil;
  }
  if (!NSEqualRects(_historyOverlayContainer.frame, self.bounds)) {
    _historyOverlayContainer.frame = self.bounds;
  }
  return _historyOverlayContainer;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!_invalidated) {
    [_observer pageHost:self didMoveToWindow:self.window];
  }
}

- (NSView *)rendererResponder {
  for (NSView *child in _contentView.subviews) {
    if (![child isKindOfClass:PCNativePaneCompositorView.class]) {
      return child;
    }
  }
  return nil;
}

- (BOOL)acceptsFirstResponder {
  return !_invalidated && !self.hiddenOrHasHiddenAncestor &&
         !self.rendererResponder.hiddenOrHasHiddenAncestor &&
         [self.rendererResponder acceptsFirstResponder];
}

- (BOOL)becomeFirstResponder {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated || self.hiddenOrHasHiddenAncestor ||
      self.rendererResponder.hiddenOrHasHiddenAncestor) {
    return NO;
  }
  NSWindow* __weak originalWindow = self.window;
  NSView* __weak originalRenderer = self.rendererResponder;
  [_scheduler dispatchToMainQueue:^{
    if (self->_invalidated) {
      return;
    }
    NSView *renderer = originalRenderer;
    NSWindow *window = originalWindow;
    if (window && renderer && self.window == window &&
        self.rendererResponder == renderer && renderer.window == window &&
        window.firstResponder == self &&
        ![self->_presentation attachedSheetOfWindow:window] &&
        !self.hiddenOrHasHiddenAncestor &&
        !renderer.hiddenOrHasHiddenAncestor) {
      [window makeFirstResponder:renderer];
    }
    if (!self->_invalidated) {
      [self->_observer pageHostDidAttemptDeferredFocus:self];
    }
  }];
  return YES;
}

- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  _observer = nil;
  [NSLayoutConstraint deactivateConstraints:_infobarConstraints ?: @[]];
  _infobarConstraints = nil;
  _infobarHeight = nil;
  [_infobarView removeFromSuperview];
  _infobarView = nil;
  [_historyOverlayContainer removeFromSuperview];
  _historyOverlayContainer = nil;
  [NSLayoutConstraint deactivateConstraints:_contentConstraints];
  _contentConstraints = nil;
  NSView *contentView = _contentView;
  _contentView = nil;
  [contentView removeFromSuperview];
  [self removeFromSuperview];
}

@end

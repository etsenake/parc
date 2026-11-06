#import "page_host.h"

#import "pane_compositor_view.h"

//
// 0xa88cb4c: exact-class host reuse, same native view, four edge constraints.
// 0xa88adfc/0xa88adb0: managed content's first child / acceptsFirstResponder.
// 0xa88ac10/0xa88ac64: deferred focus, live same-window check, attempt callback.
// 0xa88af38: actual window attachment callback; fullscreen policy is not copied.
// 0xa88b91c: replace existing managed content and re-establish its four edges.
// Explicit invalidation/constraint cleanup below are source-owned lifetime
// safeguards; they are not claims of recovered original destructor behavior.

//
// and returns nil from hitTest:, so the overlay never takes page input.
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
}
- (instancetype)initWithContentView:(NSView *)contentView
                           observer:(nullable id<PCNativePageHostObserver>)observer;
- (void)pinContentView:(NSView *)contentView;
- (nullable NSView *)rendererResponder;
@end

@implementation PCNativePageHost

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
    _contentView = contentView;
    [self addSubview:contentView];
    [self pinContentView:contentView];
  }
  return self;
}

- (NSView *)contentView {
  return _contentView;
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
}

- (void)setInfobarView:(NSView *)view preferredHeight:(CGFloat)height {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated || view == self || view == _contentView ||
      (view && [self isDescendantOf:view])) return;
  if (view == _infobarView) {
    _infobarHeight.constant = MAX(0, height);
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
  // Current Chromium's WebContentsViewMac creates the actual container hidden
  // for NEW_BACKGROUND_TAB. Its normal NativeViewHostMac explicitly shows the
  // container; WebContents::WasShown only shows the renderer child. This is the
  // equivalent native-host step, independent of focus or mere attachment.
  if (content.hidden == visible) {
    content.hidden = !visible;
  }
  // setHidden can synchronously notify native/engine observers. Never finish
  // an old owner's operation against a replacement or reparented live page.
  return !host->_invalidated && host->_contentView == content &&
         host.superview == parent && content.superview == host && host.window == window &&
         content.window == window && content.hidden == !visible &&
         (!visible || !host.hiddenOrHasHiddenAncestor);
}

- (NSView *)historyOverlayContainer {
  NSAssert(NSThread.isMainThread, @"Native page hosts require the main thread");
  if (_invalidated) {
    return nil;
  }
  // -[WebContentsPaneHostView initWithFrame:] 0x4749ef4 adds it clipped,
  // above the compositor overlay. An infobar shelf added later goes above
  // it, so restore it to the top; autoresizing survives that re-add.
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
  //
  // is outside this boundary; arbitrary added subviews are not focus targets.
  //
  // it, above the renderer, and is never the renderer.
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
  // Retain the wrapper until the queued operation completes, as the recovered
  // self-capturing block does. The original renderer/window stay weak; another
  // control, replacement renderer or physical owner supersedes this request.
  NSWindow* __weak originalWindow = self.window;
  NSView* __weak originalRenderer = self.rendererResponder;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_invalidated) {
      return;
    }
    NSView *renderer = originalRenderer;
    NSWindow *window = originalWindow;
    // A native crash sibling may hide this page after focus was queued. A
    // different first responder must retain its native selection and IME.
    if (window && renderer && self.window == window &&
        self.rendererResponder == renderer && renderer.window == window &&
        window.firstResponder == self && !window.attachedSheet &&
        !self.hiddenOrHasHiddenAncestor &&
        !renderer.hiddenOrHasHiddenAncestor) {
      [window makeFirstResponder:renderer];
    }
    if (!self->_invalidated) {
      [self->_observer pageHostDidAttemptDeferredFocus:self];
    }
  });
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

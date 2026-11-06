// Copyright 2026 Parc contributors.
#import "extension_popup_presenter.h"

#include <algorithm>
#include <cmath>

#import "page_host.h"

@interface PCExtensionPopupAnchor ()
@property NSInteger kind;
@property CGFloat sidebarWidth;
@property(weak) NSView* view;
@end
@implementation PCExtensionPopupAnchor
@synthesize kind = _kind;
@synthesize sidebarWidth = _sidebarWidth;
@synthesize view = _view;
+ (instancetype)windowAnchor {
  return [[self alloc] init];
}
+ (instancetype)sidebarAnchorWithWidth:(CGFloat)width {
  PCExtensionPopupAnchor* result = [self windowAnchor];
  result.kind = 1;
  result.sidebarWidth = width;
  return result;
}
+ (instancetype)focusedViewAnchor:(NSView*)view {
  PCExtensionPopupAnchor* result = [self windowAnchor];
  result.kind = 2;
  result.view = view;
  return result;
}
@end

@interface PCExtensionPopupPresenter () <NSWindowDelegate> {
  __weak NSWindow* _parent;
  PCNativePageHost* _page;
  NSWindow* _popupWindow;
  PCExtensionPopupAnchor* (^_anchor)(void);
  BOOL (^_mayDismiss)(void);
  void (^_onDismiss)(void);
  id _parentKeyObserver;
  id _parentCloseObserver;
  BOOL _presenting;
  BOOL _invalidated;
  BOOL _dismissRequested;
  BOOL _userHasMovedWindow;
}
@end
@implementation PCExtensionPopupPresenter
- (instancetype)initWithParentWindow:(NSWindow*)parent
                            pageHost:(PCNativePageHost*)page
                              anchor:(PCExtensionPopupAnchor* (^)(void))anchor
              mayDismissForParentKey:(BOOL (^)(void))mayDismiss
                           onDismiss:(void (^)(void))onDismiss {
  NSParameterAssert(parent && page && anchor && mayDismiss && onDismiss);
  NSAssert(NSThread.isMainThread, @"Main thread required");
  if ((self = [super init])) {
    _parent = parent;
    _page = page;
    _anchor = [anchor copy];
    _mayDismiss = [mayDismiss copy];
    _onDismiss = [onDismiss copy];
  }
  return self;
}
- (NSWindow*)popupWindow {
  return _popupWindow;
}
- (BOOL)isPresenting {
  return _presenting;
}
- (BOOL)isInvalidated {
  return _invalidated;
}
- (BOOL)userHasMovedWindow {
  return _userHasMovedWindow;
}
- (BOOL)position {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || !_parent || !_popupWindow || !_anchor) {
    return NO;
  }
  NSWindow* parent = _parent;
  NSWindow* popup = _popupWindow;
  PCExtensionPopupAnchor* anchor = _anchor();
  if (_invalidated || parent != _parent || popup != _popupWindow) {
    return NO;
  }
  NSSize size = popup.frame.size;
  NSPoint point = NSMakePoint(parent.frame.size.width - size.width - 40,
                              parent.frame.size.height - size.height - 10);
  if (anchor.kind == 1 && std::isfinite(anchor.sidebarWidth)) {
    point.x = std::max(anchor.sidebarWidth - size.width - 40, CGFloat(40));
  } else if (anchor.kind == 2 && anchor.view && anchor.view.window == parent &&
             parent.contentView) {
    NSRect rect = [anchor.view convertRect:anchor.view.bounds
                                    toView:parent.contentView];
    point = NSMakePoint(NSMaxX(rect) - size.width - 40,
                        NSMaxY(rect) - size.height - 10);
  }
  [popup setFrameOrigin:[parent convertPointToScreen:point]];
  return !_invalidated;
}
- (BOOL)prepare {
  NSAssert(NSThread.isMainThread, @"Main thread required");
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || !_parent || !_page.contentView) {
    return NO;
  }
  if (_popupWindow) {
    return YES;
  }
  // A popup cannot steal a page already attached to another native window.
  if (_page.window) {
    return NO;
  }
  NSWindow* parent = _parent;
  _popupWindow = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 300, 300)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  _popupWindow.releasedWhenClosed = NO;
  _popupWindow.collectionBehavior =
      NSWindowCollectionBehaviorFullScreenAuxiliary;
  _popupWindow.movableByWindowBackground = YES;
  _popupWindow.tabbingMode = NSWindowTabbingModeDisallowed;
  _popupWindow.delegate = self;
  __weak PCExtensionPopupPresenter* weakSelf = self;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  _parentKeyObserver =
      [center addObserverForName:NSWindowDidBecomeKeyNotification
                          object:parent
                           queue:nil
                      usingBlock:^(NSNotification* note) {
                        PCExtensionPopupPresenter* strongSelf = weakSelf;
                        if (!strongSelf || strongSelf->_invalidated ||
                            !strongSelf->_presenting ||
                            note.object != strongSelf->_parent) {
                          return;
                        }
                        BOOL allowed = strongSelf->_mayDismiss &&
                                       strongSelf->_mayDismiss();
                        if (allowed && !strongSelf->_invalidated) {
                          [strongSelf requestDismiss];
                        }
                      }];
  _parentCloseObserver =
      [center addObserverForName:NSWindowWillCloseNotification
                          object:parent
                           queue:nil
                      usingBlock:^(NSNotification* note) {
                        PCExtensionPopupPresenter* strongSelf = weakSelf;
                        if (strongSelf && note.object == strongSelf->_parent) {
                          [strongSelf requestDismiss];
                        }
                      }];
  NSViewController* content = [[NSViewController alloc] init];
  content.view = _page;
  _popupWindow.contentViewController = content;
  [_popupWindow setContentSize:NSMakeSize(300, 300)];
  if (_invalidated || _parent != parent) {
    return NO;
  }
  // addChildWindow orders a child visibly when its parent is visible. Defer
  // that step until actual show/load completion to avoid a blank opening UI.
  return [self position];
}
- (BOOL)show {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (![self prepare] || _invalidated || !_parent ||
      _page.window != _popupWindow) {
    return NO;
  }
  if (_popupWindow.parentWindow && _popupWindow.parentWindow != _parent) {
    return NO;
  }
  if (!_popupWindow.parentWindow) {
    [_parent addChildWindow:_popupWindow ordered:NSWindowAbove];
  }
  if (_invalidated || !_parent || _popupWindow.parentWindow != _parent) {
    return NO;
  }
  _presenting = YES;
  [_popupWindow makeKeyAndOrderFront:nil];
  return !_invalidated && _popupWindow.isVisible;
}
- (BOOL)resizeContent:(NSSize)size {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || !_popupWindow || !std::isfinite(size.width) ||
      !std::isfinite(size.height) || size.width <= 0 || size.height <= 0) {
    return NO;
  }
  [_popupWindow setContentSize:size];
  if (_invalidated) {
    return NO;
  }
  return _userHasMovedWindow || [self position];
}
- (void)requestDismiss {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || _dismissRequested) {
    return;
  }
  _dismissRequested = YES;
  void (^callback)(void) = _onDismiss;
  if (callback) {
    callback();
  }
  // Explicit terminal detachment closes the observed lifecycle gap instead of
  // relying on NSWindow/controller release to destroy an engine-owned host.
  [self invalidate];
}
- (void)windowWillClose:(NSNotification*)notification {
  if (notification.object == _popupWindow) {
    [self requestDismiss];
  }
}
- (void)windowWillMove:(NSNotification*)notification {
  if (!_invalidated && notification.object == _popupWindow) {
    _userHasMovedWindow = YES;
  }
}
- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"Main thread required");
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  _presenting = NO;
  _anchor = nil;
  _mayDismiss = nil;
  _onDismiss = nil;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  if (_parentKeyObserver) {
    [center removeObserver:_parentKeyObserver];
  }
  if (_parentCloseObserver) {
    [center removeObserver:_parentCloseObserver];
  }
  _parentKeyObserver = nil;
  _parentCloseObserver = nil;
  NSWindow* popup = _popupWindow;
  _popupWindow = nil;
  popup.delegate = nil;
  [popup.parentWindow removeChildWindow:popup];
  [_page removeFromSuperview];
  popup.contentViewController = nil;
  [popup orderOut:nil];
  [popup close];
}
- (void)dealloc {
  [self invalidate];
}
@end

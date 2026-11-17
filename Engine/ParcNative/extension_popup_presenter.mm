// Copyright 2026 Parc contributors.
#import "extension_popup_presenter.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#import "page_host.h"

namespace {
constexpr NSTimeInterval kRevealSettle = 0.034;
constexpr NSTimeInterval kRevealLimit = 0.15;
constexpr NSTimeInterval kOpenDuration = 0.2;
constexpr NSTimeInterval kCloseDuration = 0.15;
constexpr NSTimeInterval kMotionInterval = 1.0 / 120;
constexpr CGFloat kOpenLift = 8;
constexpr CGFloat kCloseLift = 4;
enum class Motion { kNone, kOpening, kClosing };
CGFloat EaseOut(NSTimeInterval elapsed, NSTimeInterval duration) {
  const CGFloat progress =
      std::clamp(static_cast<CGFloat>(elapsed / duration), CGFloat(0),
                 CGFloat(1));
  const CGFloat remaining = 1 - progress;
  return 1 - remaining * remaining * remaining;
}
NSTimeInterval Now() {
  return NSProcessInfo.processInfo.systemUptime;
}
}

PCExtensionPopupMotionFrame PCExtensionPopupOpeningMotion(
    NSTimeInterval elapsed,
    BOOL reduceMotion) {
  if (!std::isfinite(elapsed)) {
    elapsed = kOpenDuration;
  }
  const CGFloat eased = EaseOut(elapsed, kOpenDuration);
  return {eased, reduceMotion ? 0 : kOpenLift * (1 - eased),
          elapsed >= kOpenDuration};
}

PCExtensionPopupMotionFrame PCExtensionPopupClosingMotion(
    NSTimeInterval elapsed,
    CGFloat alpha,
    CGFloat lift,
    BOOL reduceMotion) {
  if (!std::isfinite(elapsed)) {
    elapsed = kCloseDuration;
  }
  const CGFloat eased = EaseOut(elapsed, kCloseDuration);
  const CGFloat target = reduceMotion ? lift : kCloseLift;
  return {std::clamp(alpha, CGFloat(0), CGFloat(1)) * (1 - eased),
          lift + (target - lift) * eased, elapsed >= kCloseDuration};
}

NSTimeInterval PCExtensionPopupRevealTime(NSTimeInterval shown,
                                          NSTimeInterval painted,
                                          NSTimeInterval resized) {
  const NSTimeInterval limit = shown + kRevealLimit;
  if (std::isnan(painted)) {
    return limit;
  }
  NSTimeInterval settled = std::max(shown, painted);
  if (!std::isnan(resized)) {
    settled = std::max(settled, resized);
  }
  return std::min(limit, settled + kRevealSettle);
}

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
  BOOL _revealed;
  BOOL _retiring;
  BOOL _reduceMotion;
  Motion _motion;
  NSTimeInterval _motionStart;
  NSTimeInterval _shownAt;
  NSTimeInterval _paintedAt;
  NSTimeInterval _resizedAt;
  CGFloat _lift;
  NSPoint _resting;
  NSPoint _parentResting;
  CGFloat _fromAlpha;
  CGFloat _fromLift;
  NSTimer* _revealTimer;
  NSTimer* _motionTimer;
  NSMutableArray<void (^)(void)>* _dismissCompletions;
}
@end
@implementation PCExtensionPopupPresenter
@synthesize extensionIdentifier = _extensionIdentifier;
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
    _shownAt = NAN;
    _paintedAt = NAN;
    _resizedAt = NAN;
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
  NSSize size = popup.frame.size;
  NSString* extension = _extensionIdentifier;
  id controller = parent.windowController;
  SEL placing = @selector(parcExtensionPopupOriginForExtension:popup:size:);
  if (extension && [controller respondsToSelector:placing]) {
    NSValue* placed = [(id<PCExtensionPopupPlacing>)controller
        parcExtensionPopupOriginForExtension:extension
                                       popup:popup
                                        size:size];
    if (_invalidated || parent != _parent || popup != _popupWindow) {
      return NO;
    }
    if ([placed isKindOfClass:NSValue.class] &&
        std::strcmp(placed.objCType, @encode(NSPoint)) == 0) {
      NSPoint origin = placed.pointValue;
      if (std::isfinite(origin.x) && std::isfinite(origin.y)) {
        [popup setFrameOrigin:[self lifted:origin]];
        return !_invalidated;
      }
    }
  }
  PCExtensionPopupAnchor* anchor = _anchor();
  if (_invalidated || parent != _parent || popup != _popupWindow) {
    return NO;
  }
  size = popup.frame.size;
  NSPoint point = NSMakePoint(parent.frame.size.width - size.width - 40,
                              parent.frame.size.height - size.height - 10);
  if (anchor.kind == 1 && std::isfinite(anchor.sidebarWidth)) {
    point.x = std::max(anchor.sidebarWidth - size.width - 40, CGFloat(40));
  } else if (anchor.kind == 2 && anchor.view && anchor.view.window == parent) {
    NSRect rect = [anchor.view convertRect:anchor.view.bounds toView:nil];
    point = NSMakePoint(NSMaxX(rect) - size.width - 40,
                        NSMaxY(rect) - size.height - 10);
  }
  [popup setFrameOrigin:[self lifted:[parent convertPointToScreen:point]]];
  return !_invalidated;
}
- (NSPoint)lifted:(NSPoint)origin {
  _resting = origin;
  _parentResting = _parent.frame.origin;
  return NSMakePoint(origin.x, origin.y + (_userHasMovedWindow ? 0 : _lift));
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
                          [strongSelf requestDismiss:YES];
                        }
                      }];
  _parentCloseObserver =
      [center addObserverForName:NSWindowWillCloseNotification
                          object:parent
                           queue:nil
                      usingBlock:^(NSNotification* note) {
                        PCExtensionPopupPresenter* strongSelf = weakSelf;
                        if (strongSelf && note.object == strongSelf->_parent) {
                          [strongSelf requestDismiss:NO];
                        }
                      }];
  NSViewController* content = [[NSViewController alloc] init];
  content.view = _page;
  _popupWindow.contentViewController = content;
  [_popupWindow setContentSize:NSMakeSize(300, 300)];
  if (_invalidated || _parent != parent) {
    return NO;
  }
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
  if (_retiring ||
      (_popupWindow.parentWindow && _popupWindow.parentWindow != _parent)) {
    return NO;
  }
  if (!_popupWindow.parentWindow) {
    if (!_revealed) {
      _popupWindow.alphaValue = 0;
    }
    [_parent addChildWindow:_popupWindow ordered:NSWindowAbove];
  }
  if (_invalidated || !_parent || _popupWindow.parentWindow != _parent) {
    return NO;
  }
  _presenting = YES;
  [_popupWindow makeKeyAndOrderFront:nil];
  if (!_invalidated && !_revealed && std::isnan(_shownAt)) {
    _shownAt = Now();
    [self scheduleReveal];
  }
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
  NSRect frame = _popupWindow.frame;
  NSRect resized = [_popupWindow
      frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)];
  resized.origin =
      NSMakePoint(NSMinX(frame), NSMaxY(frame) - NSHeight(resized));
  [_popupWindow setFrame:resized display:YES];
  if (_invalidated) {
    return NO;
  }
  _resizedAt = Now();
  if (!_revealed) {
    [self scheduleReveal];
  }
  return _userHasMovedWindow || [self position];
}
- (void)contentDidPaint {
  if (_invalidated || !std::isnan(_paintedAt)) {
    return;
  }
  _paintedAt = Now();
  [self scheduleReveal];
}
- (void)scheduleReveal {
  [_revealTimer invalidate];
  _revealTimer = nil;
  if (_invalidated || _revealed || std::isnan(_shownAt)) {
    return;
  }
  const NSTimeInterval delay = std::max(
      0.0, PCExtensionPopupRevealTime(_shownAt, _paintedAt, _resizedAt) - Now());
  __weak PCExtensionPopupPresenter* weakSelf = self;
  _revealTimer = [NSTimer timerWithTimeInterval:delay
                                        repeats:NO
                                          block:^(NSTimer* timer) {
                                            [weakSelf reveal];
                                          }];
  [NSRunLoop.mainRunLoop addTimer:_revealTimer forMode:NSRunLoopCommonModes];
}
- (void)reveal {
  [_revealTimer invalidate];
  _revealTimer = nil;
  if (_invalidated || _revealed || _retiring || !_presenting) {
    return;
  }
  _revealed = YES;
  if (_userHasMovedWindow) {
    _popupWindow.alphaValue = 1;
    return;
  }
  [self beginMotion:Motion::kOpening];
}
- (void)beginMotion:(Motion)motion {
  [_motionTimer invalidate];
  _motionTimer = nil;
  _motion = motion;
  _motionStart = Now();
  _reduceMotion =
      NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  _fromAlpha = _popupWindow.alphaValue;
  _fromLift = _lift;
  _resting = NSMakePoint(_popupWindow.frame.origin.x,
                         _popupWindow.frame.origin.y - _lift);
  _parentResting = _parent.frame.origin;
  [self stepMotion];
  if (_invalidated || _motion != motion) {
    return;
  }
  __weak PCExtensionPopupPresenter* weakSelf = self;
  _motionTimer = [NSTimer timerWithTimeInterval:kMotionInterval
                                        repeats:YES
                                          block:^(NSTimer* timer) {
                                            [weakSelf stepMotion];
                                          }];
  [NSRunLoop.mainRunLoop addTimer:_motionTimer forMode:NSRunLoopCommonModes];
}
- (void)stepMotion {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  NSWindow* popup = _popupWindow;
  if (_invalidated || !popup || _motion == Motion::kNone) {
    [_motionTimer invalidate];
    _motionTimer = nil;
    return;
  }
  const NSTimeInterval elapsed = Now() - _motionStart;
  const Motion motion = _motion;
  const PCExtensionPopupMotionFrame frame =
      motion == Motion::kOpening
          ? PCExtensionPopupOpeningMotion(elapsed, _reduceMotion)
          : PCExtensionPopupClosingMotion(elapsed, _fromAlpha, _fromLift,
                                          _reduceMotion);
  if (motion == Motion::kClosing &&
      (popup.attachedSheet || popup.childWindows.count)) {
    [self invalidate];
    return;
  }
  _lift = frame.lift;
  NSWindow* parent = _parent;
  if (!_userHasMovedWindow && parent) {
    const NSPoint parentOrigin = parent.frame.origin;
    const NSPoint target = NSMakePoint(
        _resting.x + parentOrigin.x - _parentResting.x,
        _resting.y + parentOrigin.y - _parentResting.y + frame.lift);
    if (!NSEqualPoints(target, popup.frame.origin)) {
      [popup setFrameOrigin:target];
    }
  }
  popup.alphaValue = frame.alpha;
  if (!frame.finished || _invalidated || _motion != motion) {
    return;
  }
  _motion = Motion::kNone;
  [_motionTimer invalidate];
  _motionTimer = nil;
  if (motion == Motion::kClosing) {
    [self invalidate];
  }
}
- (BOOL)dismissWithMotion:(void (^)(void))completion {
  NSAssert(NSThread.isMainThread, @"Main thread required");
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated) {
    return NO;
  }
  if (_retiring) {
    if (completion) {
      [_dismissCompletions addObject:[completion copy]];
    }
    return YES;
  }
  NSWindow* popup = _popupWindow;
  NSWindow* parent = _parent;
  if (!_presenting || !_revealed || !popup || !parent || !popup.visible ||
      popup.alphaValue <= 0 || !parent.visible || parent.miniaturized ||
      popup.parentWindow != parent || _page.window != popup ||
      popup.attachedSheet || popup.childWindows.count) {
    return NO;
  }
  _retiring = YES;
  _presenting = NO;
  [_revealTimer invalidate];
  _revealTimer = nil;
  _dismissCompletions = [NSMutableArray array];
  if (completion) {
    [_dismissCompletions addObject:[completion copy]];
  }
  popup.ignoresMouseEvents = YES;
  if (popup.keyWindow && parent.canBecomeKeyWindow) {
    [parent makeKeyWindow];
  }
  if (!_invalidated) {
    [self beginMotion:Motion::kClosing];
  }
  return YES;
}
- (void)requestDismiss:(BOOL)animated {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated) {
    return;
  }
  if (!_dismissRequested) {
    _dismissRequested = YES;
    void (^callback)(void) = _onDismiss;
    if (callback) {
      callback();
    }
    if (_invalidated) {
      return;
    }
  }
  if (!animated || ![self dismissWithMotion:nil]) {
    [self invalidate];
  }
}
- (void)windowWillClose:(NSNotification*)notification {
  if (notification.object == _popupWindow) {
    [self requestDismiss:NO];
  }
}
- (void)windowWillMove:(NSNotification*)notification {
  if (_invalidated || notification.object != _popupWindow) {
    return;
  }
  _userHasMovedWindow = YES;
  _lift = 0;
  if (_motion == Motion::kOpening) {
    _motion = Motion::kNone;
    [_motionTimer invalidate];
    _motionTimer = nil;
    _popupWindow.alphaValue = 1;
  }
}
- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"Main thread required");
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  _presenting = NO;
  _motion = Motion::kNone;
  [_revealTimer invalidate];
  _revealTimer = nil;
  [_motionTimer invalidate];
  _motionTimer = nil;
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
  NSArray<void (^)(void)>* completions = _dismissCompletions;
  _dismissCompletions = nil;
  for (void (^completion)(void) in completions) {
    completion();
  }
}
- (void)dealloc {
  [self invalidate];
}
@end

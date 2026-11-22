// Copyright 2026 Parc contributors.
#import "extension_popup_presenter.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#import "dialog_style.h"
#import "page_host.h"

namespace {
constexpr NSTimeInterval kRevealSettle = 0.034;
constexpr NSTimeInterval kRevealLimit = 0.15;
constexpr NSTimeInterval kOpenDuration = 0.2;
constexpr NSTimeInterval kCloseDuration = 0.15;
constexpr NSTimeInterval kResizeDuration = 0.18;
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
CGFloat Glide(CGFloat from, CGFloat to, CGFloat eased) {
  if (from == to) {
    return to;
  }
  return std::clamp(std::round(from + (to - from) * eased), std::min(from, to),
                    std::max(from, to));
}
void GlideAxis(CGFloat fromMin,
               CGFloat fromLength,
               CGFloat toMin,
               CGFloat toLength,
               CGFloat eased,
               CGFloat* min,
               CGFloat* length) {
  const CGFloat fromMax = fromMin + fromLength;
  const CGFloat toMax = toMin + toLength;
  if (fromMin == toMin || fromMax == toMax) {
    *length = Glide(fromLength, toLength, eased);
    *min = fromMin == toMin ? toMin : toMax - *length;
    return;
  }
  const CGFloat low =
      std::clamp(std::ceil(fromMin + (toMin - fromMin) * eased),
                 std::min(fromMin, toMin), std::max(fromMin, toMin));
  const CGFloat high =
      std::clamp(std::floor(fromMax + (toMax - fromMax) * eased),
                 std::min(fromMax, toMax), std::max(fromMax, toMax));
  *min = low;
  *length = std::max(high - low, CGFloat(0));
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

PCExtensionPopupResizeFrame PCExtensionPopupResizeMotion(NSTimeInterval elapsed,
                                                         NSRect from,
                                                         NSRect to) {
  if (!std::isfinite(elapsed) || elapsed >= kResizeDuration) {
    return {to, YES};
  }
  const CGFloat eased = EaseOut(elapsed, kResizeDuration);
  NSRect frame;
  GlideAxis(NSMinX(from), NSWidth(from), NSMinX(to), NSWidth(to), eased,
            &frame.origin.x, &frame.size.width);
  GlideAxis(NSMinY(from), NSHeight(from), NSMinY(to), NSHeight(to), eased,
            &frame.origin.y, &frame.size.height);
  return {frame, NO};
}

PCExtensionPopupResize PCExtensionPopupRetargetResize(
    PCExtensionPopupResize resize,
    NSRect resting,
    NSRect target,
    NSTimeInterval now,
    BOOL reduceMotion) {
  const BOOL moving = std::isfinite(resize.start);
  if (reduceMotion || !std::isfinite(now)) {
    return {target, target, NAN};
  }
  if (moving && NSEqualRects(resize.to, target)) {
    return resize;
  }
  const NSRect from =
      moving
          ? PCExtensionPopupResizeMotion(now - resize.start, resize.from,
                                         resize.to)
                .frame
          : resting;
  return {from, target, NSEqualRects(from, target) ? NAN : now};
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
  PCExtensionPopupResize _resize;
  CGFloat _fromAlpha;
  CGFloat _fromLift;
  NSTimer* _revealTimer;
  NSTimer* _motionTimer;
  NSMutableArray<void (^)(void)>* _dismissCompletions;
}
@end
@implementation PCExtensionPopupPresenter
@synthesize extensionIdentifier = _extensionIdentifier;
@synthesize backdropColor = _backdropColor;
@synthesize presentation = _presentation;
@synthesize scheduler = _scheduler;
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
    _resize = {NSZeroRect, NSZeroRect, NAN};
    _presentation = PCNativeSystemPresentation.sharedPresentation;
    _scheduler = PCNativeSystemScheduling.sharedScheduling;
  }
  return self;
}
- (NSTimeInterval)now {
  return _scheduler.systemUptime;
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
- (void)setBackdropColor:(NSColor*)color {
  _backdropColor = [color copy];
  [self paintBackdrop];
}
- (void)paintBackdrop {
  NSView* container = _page.superview;
  if (!container || container.window != _popupWindow) {
    return;
  }
  container.wantsLayer = YES;
  container.layer.backgroundColor = _backdropColor.CGColor;
}
- (BOOL)resizing {
  return std::isfinite(_resize.start);
}
- (NSRect)restingFrame {
  const NSPoint parent = _parent.frame.origin;
  return NSOffsetRect(_popupWindow.frame, -parent.x,
                      -parent.y - (_userHasMovedWindow ? 0 : _lift));
}
- (BOOL)position {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  NSWindow* popup = _popupWindow;
  const NSSize size = popup.frame.size;
  NSPoint origin;
  if (![self restingOrigin:&origin forSize:size]) {
    return NO;
  }
  const NSPoint parent = _parent.frame.origin;
  _resize.to = NSMakeRect(origin.x - parent.x, origin.y - parent.y, size.width,
                          size.height);
  [popup setFrameOrigin:NSMakePoint(origin.x, origin.y + (_userHasMovedWindow
                                                              ? 0
                                                              : _lift))];
  return !_invalidated;
}
- (BOOL)restingOrigin:(NSPoint*)result forSize:(NSSize)size {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || !_parent || !_popupWindow || !_anchor) {
    return NO;
  }
  NSWindow* parent = _parent;
  NSWindow* popup = _popupWindow;
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
        *result = origin;
        return YES;
      }
    }
  }
  PCExtensionPopupAnchor* anchor = _anchor();
  if (_invalidated || parent != _parent || popup != _popupWindow) {
    return NO;
  }
  NSPoint point = NSMakePoint(parent.frame.size.width - size.width - 40,
                              parent.frame.size.height - size.height - 10);
  if (anchor.kind == 1 && std::isfinite(anchor.sidebarWidth)) {
    point.x = std::max(anchor.sidebarWidth - size.width - 40, CGFloat(40));
  } else if (anchor.kind == 2 && anchor.view && anchor.view.window == parent) {
    NSRect rect = [anchor.view convertRect:anchor.view.bounds toView:nil];
    point = NSMakePoint(NSMaxX(rect) - size.width - 40,
                        NSMaxY(rect) - size.height - 10);
  }
  *result = [parent convertPointToScreen:point];
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
  NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)];
  NSViewController* content = [[NSViewController alloc] init];
  content.view = container;
  _popupWindow.contentViewController = content;
  [_popupWindow setContentSize:NSMakeSize(300, 300)];
  _page.frame = container.bounds;
  _page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [container addSubview:_page];
  if (_invalidated || _parent != parent || _page.superview != container) {
    return NO;
  }
  [self paintBackdrop];
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
      ([_presentation parentWindowOfWindow:_popupWindow] &&
       [_presentation parentWindowOfWindow:_popupWindow] != _parent)) {
    return NO;
  }
  if (![_presentation parentWindowOfWindow:_popupWindow]) {
    if (!_revealed) {
      _popupWindow.alphaValue = 0;
    }
    [_presentation window:_parent addChildWindow:_popupWindow ordered:NSWindowAbove];
  }
  if (_invalidated || !_parent || [_presentation parentWindowOfWindow:_popupWindow] != _parent) {
    return NO;
  }
  _presenting = YES;
  [_presentation makeKeyAndOrderFrontWindow:_popupWindow];
  if (!_invalidated && !_revealed && std::isnan(_shownAt)) {
    _shownAt = [self now];
    [self scheduleReveal];
  }
  return !_invalidated && [_presentation isWindowVisible:_popupWindow];
}
- (BOOL)resizeContent:(NSSize)size {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  if (_invalidated || !_popupWindow || !std::isfinite(size.width) ||
      !std::isfinite(size.height) || size.width <= 0 || size.height <= 0) {
    return NO;
  }
  NSWindow* popup = _popupWindow;
  NSRect resized = [popup
      frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)];
  if ([self mayGlideResize]) {
    _resizedAt = [self now];
    return [self glideToFrameSize:resized.size content:size];
  }
  _resize.start = NAN;
  [self pinPage:size];
  const NSRect frame = popup.frame;
  resized.origin =
      NSMakePoint(NSMinX(frame), NSMaxY(frame) - NSHeight(resized));
  [popup setFrame:resized display:YES];
  if (_invalidated) {
    return NO;
  }
  [self fillPage];
  _resizedAt = [self now];
  if (!_revealed) {
    [self scheduleReveal];
  }
  return _userHasMovedWindow || [self position];
}
- (BOOL)mayGlideResize {
  NSWindow* popup = _popupWindow;
  NSWindow* parent = _parent;
  id<PCNativePresentation> presentation = _presentation;
  return _revealed && _presenting && !_retiring && parent &&
         [presentation isWindowVisible:parent] && !parent.miniaturized &&
         [presentation isWindowVisible:popup] &&
         [presentation parentWindowOfWindow:popup] == parent && _page.window == popup &&
         ![presentation attachedSheetOfWindow:popup] &&
         ![presentation childWindowsOfWindow:popup].count;
}
- (BOOL)glideToFrameSize:(NSSize)frameSize content:(NSSize)content {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  NSWindow* popup = _popupWindow;
  const NSRect resting = [self restingFrame];
  NSRect target = NSMakeRect(NSMinX(resting),
                             NSMaxY(resting) - frameSize.height,
                             frameSize.width, frameSize.height);
  if (!_userHasMovedWindow) {
    NSPoint origin;
    if (![self restingOrigin:&origin forSize:frameSize] ||
        popup != _popupWindow) {
      return NO;
    }
    const NSPoint parent = _parent.frame.origin;
    target.origin = NSMakePoint(origin.x - parent.x, origin.y - parent.y);
  }
  _resize = PCExtensionPopupRetargetResize(
      _resize, resting, target, [self now],
      NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion);
  [self pinPage:content];
  if (![self resizing]) {
    [self placeResting:_resize.to sized:YES];
    if (!_invalidated) {
      [self fillPage];
    }
    return !_invalidated;
  }
  [self stepMotion];
  if (_invalidated) {
    return NO;
  }
  [self runMotionTimer];
  return YES;
}
- (void)pinPage:(NSSize)size {
  NSView* container = _page.superview;
  if (!container || container.window != _popupWindow) {
    return;
  }
  _page.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
  const NSRect frame = NSMakeRect(0, NSHeight(container.bounds) - size.height,
                                  size.width, size.height);
  if (!NSEqualRects(_page.frame, frame)) {
    const BOOL resized = !NSEqualSizes(_page.frame.size, frame.size);
    _page.frame = frame;
    if (resized) {
      [_page layoutSubtreeIfNeeded];
    }
  }
}
- (void)fillPage {
  NSView* container = _page.superview;
  if (!container || container.window != _popupWindow) {
    return;
  }
  _page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  if (!NSEqualRects(_page.frame, container.bounds)) {
    _page.frame = container.bounds;
  }
}
- (void)settleResize {
  _resize.start = NAN;
  [self fillPage];
}
- (void)placeResting:(NSRect)resting sized:(BOOL)sized {
  NSWindow* popup = _popupWindow;
  NSWindow* parent = _parent;
  if (!popup || !parent) {
    return;
  }
  const NSPoint origin = parent.frame.origin;
  const NSRect frame = NSOffsetRect(
      resting, origin.x, origin.y + (_userHasMovedWindow ? 0 : _lift));
  if (sized && !NSEqualSizes(frame.size, popup.frame.size)) {
    [popup setFrame:frame display:YES];
  } else if (!NSEqualPoints(frame.origin, popup.frame.origin)) {
    [popup setFrameOrigin:frame.origin];
  }
}
- (void)contentDidPaint {
  if (_invalidated || !std::isnan(_paintedAt)) {
    return;
  }
  _paintedAt = [self now];
  [self scheduleReveal];
}
- (void)scheduleReveal {
  [_revealTimer invalidate];
  _revealTimer = nil;
  if (_invalidated || _revealed || std::isnan(_shownAt)) {
    return;
  }
  const NSTimeInterval delay = std::max(
      0.0, PCExtensionPopupRevealTime(_shownAt, _paintedAt, _resizedAt) - [self now]);
  __weak PCExtensionPopupPresenter* weakSelf = self;
  _revealTimer = [_scheduler timerWithTimeInterval:delay
                                           repeats:NO
                                             block:^(NSTimer* timer) {
                                               [weakSelf reveal];
                                             }];
  [_scheduler addTimer:_revealTimer forMode:NSRunLoopCommonModes];
}
- (void)reveal {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  [_revealTimer invalidate];
  _revealTimer = nil;
  if (_invalidated || _revealed || _retiring || !_presenting) {
    return;
  }
  _revealed = YES;
  if (_userHasMovedWindow) {
    _popupWindow.alphaValue = 1;
  } else {
    [self beginMotion:Motion::kOpening];
  }
  if (!_invalidated) {
    [self reportPhase:PCExtensionPopupPhaseRevealed
                popup:_popupWindow
               parent:_parent];
  }
}
- (void)reportPhase:(PCExtensionPopupPhase)phase
              popup:(NSWindow*)popup
             parent:(NSWindow*)parent {
  NSString* extension = _extensionIdentifier;
  id controller = parent.windowController;
  SEL reporting = @selector(parcExtensionPopup:forExtension:didChangePhase:);
  if (popup && extension && [controller respondsToSelector:reporting]) {
    [(id<PCExtensionPopupPlacing>)controller parcExtensionPopup:popup
                                                   forExtension:extension
                                                 didChangePhase:phase];
  }
}
- (void)beginMotion:(Motion)motion {
  _motion = motion;
  _motionStart = [self now];
  _reduceMotion =
      NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  _fromAlpha = _popupWindow.alphaValue;
  _fromLift = _lift;
  if (![self resizing]) {
    _resize.to = [self restingFrame];
  }
  [self stepMotion];
  if (_invalidated || _motion != motion) {
    return;
  }
  [self runMotionTimer];
}
- (void)runMotionTimer {
  if (_motionTimer || _invalidated) {
    return;
  }
  __weak PCExtensionPopupPresenter* weakSelf = self;
  _motionTimer = [_scheduler timerWithTimeInterval:kMotionInterval
                                           repeats:YES
                                             block:^(NSTimer* timer) {
                                               [weakSelf stepMotion];
                                             }];
  [_scheduler addTimer:_motionTimer forMode:NSRunLoopCommonModes];
}
- (void)stopMotionTimer {
  [_motionTimer invalidate];
  _motionTimer = nil;
}
- (void)stepMotion {
  __attribute__((objc_precise_lifetime)) PCExtensionPopupPresenter* keepAlive =
      self;
  (void)keepAlive;
  NSWindow* popup = _popupWindow;
  const BOOL resizing = [self resizing];
  if (_invalidated || !popup || (_motion == Motion::kNone && !resizing)) {
    [self stopMotionTimer];
    return;
  }
  const NSTimeInterval now = [self now];
  const Motion motion = _motion;
  if (motion == Motion::kClosing &&
      ([_presentation attachedSheetOfWindow:popup] ||
       [_presentation childWindowsOfWindow:popup].count)) {
    [self invalidate];
    return;
  }
  PCExtensionPopupMotionFrame fade = {popup.alphaValue, _lift, YES};
  if (motion == Motion::kOpening) {
    fade = PCExtensionPopupOpeningMotion(now - _motionStart, _reduceMotion);
  } else if (motion == Motion::kClosing) {
    fade = PCExtensionPopupClosingMotion(now - _motionStart, _fromAlpha,
                                         _fromLift, _reduceMotion);
  }
  const NSTimeInterval resizeStart = _resize.start;
  const BOOL covered = [_presentation attachedSheetOfWindow:popup] ||
                       [_presentation childWindowsOfWindow:popup].count;
  const PCExtensionPopupResizeFrame size =
      resizing && !covered
          ? PCExtensionPopupResizeMotion(now - resizeStart, _resize.from,
                                         _resize.to)
          : PCExtensionPopupResizeFrame{_resize.to, YES};
  _lift = fade.lift;
  if (resizing || !_userHasMovedWindow) {
    [self placeResting:size.frame sized:resizing];
    if (_invalidated || popup != _popupWindow) {
      return;
    }
  }
  if (motion != Motion::kNone) {
    popup.alphaValue = fade.alpha;
  }
  if (resizing && size.finished && _resize.start == resizeStart) {
    [self settleResize];
  }
  if (motion != Motion::kNone && fade.finished && !_invalidated &&
      _motion == motion) {
    _motion = Motion::kNone;
    if (motion == Motion::kClosing) {
      [self invalidate];
      return;
    }
  }
  if (_motion == Motion::kNone && ![self resizing]) {
    [self stopMotionTimer];
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
  id<PCNativePresentation> presentation = _presentation;
  if (!_presenting || !_revealed || !popup || !parent ||
      ![presentation isWindowVisible:popup] || popup.alphaValue <= 0 ||
      ![presentation isWindowVisible:parent] || parent.miniaturized ||
      [presentation parentWindowOfWindow:popup] != parent || _page.window != popup ||
      [presentation attachedSheetOfWindow:popup] ||
      [presentation childWindowsOfWindow:popup].count) {
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
    [_presentation makeKeyWindow:parent];
  }
  if (!_invalidated) {
    [self beginMotion:Motion::kClosing];
  }
  if (!_invalidated) {
    [self reportPhase:PCExtensionPopupPhaseClosing popup:popup parent:parent];
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
  if ([self resizing]) {
    const NSRect frame = _popupWindow.frame;
    const NSSize size = _resize.to.size;
    [_popupWindow setFrame:NSMakeRect(NSMinX(frame), NSMaxY(frame) - size.height,
                                      size.width, size.height)
                   display:YES];
    if (_invalidated) {
      return;
    }
    [self settleResize];
  }
  _userHasMovedWindow = YES;
  _lift = 0;
  if (_motion == Motion::kOpening) {
    _motion = Motion::kNone;
    [self stopMotionTimer];
    _popupWindow.alphaValue = 1;
  }
}
- (void)invalidate {
  NSAssert(NSThread.isMainThread, @"Main thread required");
  if (_invalidated) {
    return;
  }
  NSWindow* parent = _parent;
  _invalidated = YES;
  _presenting = NO;
  _motion = Motion::kNone;
  _resize.start = NAN;
  [_revealTimer invalidate];
  _revealTimer = nil;
  [self stopMotionTimer];
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
  [_presentation window:[_presentation parentWindowOfWindow:popup] removeChildWindow:popup];
  [_page removeFromSuperview];
  popup.contentViewController = nil;
  [_presentation orderOutWindow:popup];
  [_presentation closeWindow:popup];
  [self reportPhase:PCExtensionPopupPhaseClosed popup:popup parent:parent];
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

// Copyright 2026 Parc contributors.
#import "browser_window.h"
#import <objc/runtime.h>
#ifdef __cplusplus
#include "native_fullscreen_window.h"
#endif

static void PCRequireMainThread(void) {
  if (![NSThread isMainThread]) {
    [NSException raise:NSInternalInconsistencyException
                format:@"Parc native window components require the main thread"];
  }
}

// One placement record per supplied NSWindow, even when several Profiles
// attach separate Browser adapters. The window owns it; it owns no window or
// Browser and installs no competing NSWindowDelegate.
@interface PCNativeWindowPlacement : NSObject {
 @public
  NSRect beforeFullscreen;
  BOOL transitioning;
  NSUInteger generation;
}
@end
@implementation PCNativeWindowPlacement
@end

static PCNativeWindowPlacement* PCPlacement(NSWindow* window) {
  if (!window) {
    return nil;
  }
  static char key;
  PCNativeWindowPlacement* placement = objc_getAssociatedObject(window, &key);
  if (!placement) {
    placement = [[PCNativeWindowPlacement alloc] init];
    placement->beforeFullscreen = window.frame;
    objc_setAssociatedObject(window, &key, placement,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  return placement;
}

@implementation PCNativeWindowAssociation {
  __weak NSWindow* _window;
  __weak id<PCNativeWindowAssociationObserver> _observer;
  BOOL _invalidated;
}

- (instancetype)initWithObserver:
    (id<PCNativeWindowAssociationObserver>)observer {
  PCRequireMainThread();
  self = [super init];
  if (self) {
    _observer = observer;
  }
  return self;
}

- (void)dealloc {
  PCRequireMainThread();
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSWindow*)window {
  PCRequireMainThread();
  return _window;
}

- (BOOL)isInvalidated {
  PCRequireMainThread();
  return _invalidated;
}

- (NSRect)restoredFrame {
  PCRequireMainThread();
  NSWindow* window = _window;
  if (!window || _invalidated) {
    return NSZeroRect;
  }

#ifdef __cplusplus
  if (parc::HasNativeFullscreenWindow(window))
    return parc::NativeFullscreenRestoredFrame(window);
#endif
  PCNativeWindowPlacement* placement = PCPlacement(window);
  // Match Chromium's macOS placement contract: minimization keeps frame;
  // fullscreen preserves the frame before the native transition.
  if (placement->transitioning ||
      (window.styleMask & NSWindowStyleMaskFullScreen)) {
    return placement->beforeFullscreen;
  }
  return window.frame;
}

- (BOOL)fullscreenTransitioning {
  PCRequireMainThread();
  NSWindow* window = _window;

#ifdef __cplusplus
  if (window && !_invalidated && parc::HasNativeFullscreenWindow(window))
    return parc::NativeFullscreenTransitioning(window);
#endif
  return window && !_invalidated && PCPlacement(window)->transitioning;
}

- (NSUInteger)stateRequestGeneration {
  PCRequireMainThread();
  NSWindow* window = _window;
  return window && !_invalidated ? PCPlacement(window)->generation : 0;
}

- (NSUInteger)beginStateRequest {
  PCRequireMainThread();
  NSWindow* window = _window;
  return window && !_invalidated ? ++PCPlacement(window)->generation : 0;
}

- (BOOL)attachToWindow:(NSWindow*)window {
  PCRequireMainThread();
  if (_invalidated || !window) {
    return NO;
  }
  NSWindow* existing = _window;
  if (existing) {
    return existing == window;
  }
  // Remove any registrations whose prior weak window has disappeared.
  [self detach];
  _window = window;
  PCPlacement(window);
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  for (NSNotificationName name in @[
         NSWindowWillCloseNotification, NSWindowDidBecomeKeyNotification,
         NSWindowDidResignKeyNotification, NSWindowDidEnterFullScreenNotification,
         NSWindowDidExitFullScreenNotification,
         NSWindowWillEnterFullScreenNotification,
         NSWindowWillExitFullScreenNotification
       ]) {
    [center addObserver:self
               selector:@selector(receiveWindowNotification:)
                   name:name
                 object:window];
  }

#ifdef __cplusplus
  [center addObserver:self selector:@selector(receiveWindowNotification:)
                 name:parc::kNativeFullscreenSettledNotification object:window];
#endif
  return YES;
}

- (void)detach {
  PCRequireMainThread();
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _window = nil;
}

- (void)invalidate {
  PCRequireMainThread();
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  [self detach];
  _observer = nil;
}

- (void)receiveWindowNotification:(NSNotification*)notification {
  PCRequireMainThread();
  NSWindow* window = _window;
  if (_invalidated || !window || notification.object != window) {
    return;
  }
  PCNativeWindowEvent event;

#ifdef __cplusplus
  const bool managed_fullscreen = parc::HasNativeFullscreenWindow(window);
  if ([notification.name
          isEqualToString:parc::kNativeFullscreenSettledNotification]) {
    if (!parc::IsCurrentNativeFullscreenSettlement(notification)) return;
    id<PCNativeWindowAssociationObserver> observer = _observer;
    [observer nativeWindowAssociation:self
                     didReceiveEvent:PCNativeWindowEventFullscreenDidSettle
                              window:window];
    return;
  }
  if (managed_fullscreen) {
    parc::HandleNativeFullscreenNotification(notification);
    if ([notification.name isEqualToString:NSWindowDidEnterFullScreenNotification] ||
        [notification.name isEqualToString:NSWindowDidExitFullScreenNotification]) {
      // Intermediate did-exit is part of moving to another fullscreen display.
      // Only the controller's final settlement updates exclusive-access state.
      return;
    }
  }
#endif
  PCNativeWindowPlacement* placement = PCPlacement(window);
  if ([notification.name isEqualToString:NSWindowWillCloseNotification]) {
    event = PCNativeWindowEventWillClose;
    [self detach];
  } else if ([notification.name
                 isEqualToString:NSWindowDidBecomeKeyNotification]) {
    event = PCNativeWindowEventDidBecomeKey;
  } else if ([notification.name
                 isEqualToString:NSWindowDidResignKeyNotification]) {
    event = PCNativeWindowEventDidResignKey;
  } else if ([notification.name
                 isEqualToString:NSWindowDidEnterFullScreenNotification]) {
    placement->transitioning = NO;
    event = PCNativeWindowEventDidEnterFullScreen;
  } else if ([notification.name
                 isEqualToString:NSWindowDidExitFullScreenNotification]) {
    placement->transitioning = NO;
    event = PCNativeWindowEventDidExitFullScreen;
  } else if ([notification.name
                 isEqualToString:NSWindowWillEnterFullScreenNotification]) {
    if (!placement->transitioning) {
      placement->beforeFullscreen = window.frame;
    }
    placement->transitioning = YES;
    event = PCNativeWindowEventWillEnterFullScreen;
  } else if ([notification.name
                 isEqualToString:NSWindowWillExitFullScreenNotification]) {
    placement->transitioning = YES;
    event = PCNativeWindowEventWillExitFullScreen;
  } else {
    return;
  }
  id<PCNativeWindowAssociationObserver> observer = _observer;
  // A callback may invalidate or drop the owner's reference. No state is
  // accessed after delivery; strong local arguments survive that callback.
  [observer nativeWindowAssociation:self didReceiveEvent:event window:window];
}
@end

// The Objective-C half above can also be compiled as Objective-C for standalone
// AppKit tests. Normal engine builds compile this complete file as Objective-C++
// against the real Chromium headers/libraries; no replacement headers are used.
#ifdef __cplusplus
#include "base/check.h"

namespace parc {

NativeModalDialogHost::NativeModalDialogHost(
    NativeModalDialogHostDelegate& delegate)
    : delegate_(&delegate) {
  PCRequireMainThread();
}

NativeModalDialogHost::~NativeModalDialogHost() {
  PCRequireMainThread();
  CHECK(!notifying_position_);
  CHECK(!notifying_destruction_);
  Invalidate();
}

gfx::NativeView NativeModalDialogHost::GetHostView() const {
  PCRequireMainThread();
  return delegate_ ? delegate_->GetActivePageHostView() : gfx::NativeView();
}

gfx::Point NativeModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  PCRequireMainThread();
  if (!delegate_) {
    return gfx::Point();
  }
  const gfx::Size window = delegate_->GetBrowserWindowSize();
  // Preserve separate truncation. (800 / 2 - 301 / 2) is 250, whereas
  // (800 - 301) / 2 would incorrectly produce 249.
  return gfx::Point(window.width() / 2 - size.width() / 2,
                    window.height() / 2 - size.height() / 2);
}

gfx::Size NativeModalDialogHost::GetMaximumDialogSize() {
  PCRequireMainThread();
  return delegate_ ? delegate_->GetContentsSize() : gfx::Size();
}

bool NativeModalDialogHost::ShouldActivateDialog() const {
  PCRequireMainThread();
  return true;
}

bool NativeModalDialogHost::ShouldConstrainDialogBoundsByHost() {
  PCRequireMainThread();
  return true;
}

void NativeModalDialogHost::AddObserver(
    web_modal::ModalDialogHostObserver* observer) {
  PCRequireMainThread();
  CHECK(delegate_);
  CHECK(observer);
  observers_.AddObserver(observer);
}

void NativeModalDialogHost::RemoveObserver(
    web_modal::ModalDialogHostObserver* observer) {
  PCRequireMainThread();
  observers_.RemoveObserver(observer);
}

void NativeModalDialogHost::NotifyPositionRequiresUpdate() {
  PCRequireMainThread();
  if (!delegate_ || notifying_position_) {
    return;
  }
  notifying_position_ = true;
  for (auto& observer : observers_) {
    if (!delegate_) {
      break;
    }
    observer.OnPositionRequiresUpdate();
  }
  notifying_position_ = false;
}

void NativeModalDialogHost::Invalidate() {
  PCRequireMainThread();
  if (!delegate_) {
    return;
  }
  delegate_ = nullptr;
  notifying_destruction_ = true;
  for (auto& observer : observers_) {
    // Detach before the terminal callback: it may remove or destroy itself.
    // A position notification can still have an outer iterator alive, so
    // Clear() would mark already-removed checked observers a second time.
    // RemoveObserver keeps the outer iterator's tombstones until it unwinds.
    observers_.RemoveObserver(&observer);
    observer.OnHostDestroying();
  }
  notifying_destruction_ = false;
}

}  // namespace parc
#endif  // __cplusplus

#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PCNativePageHost;

@protocol PCNativePresentation <NSObject>
- (nullable NSWindow *)attachedSheetOfWindow:(nullable NSWindow *)window;
- (nullable NSWindow *)sheetParentOfWindow:(nullable NSWindow *)window;
- (nullable NSWindow *)parentWindowOfWindow:(nullable NSWindow *)window;
- (nullable NSArray<NSWindow *> *)childWindowsOfWindow:(nullable NSWindow *)window;
- (BOOL)isWindowVisible:(nullable NSWindow *)window;
- (void)window:(nullable NSWindow *)window
           beginSheet:(NSWindow *)sheet
    completionHandler:(nullable void (^)(NSModalResponse))handler;
- (void)window:(nullable NSWindow *)window endSheet:(nullable NSWindow *)sheet;
- (void)window:(nullable NSWindow *)window
      endSheet:(nullable NSWindow *)sheet
    returnCode:(NSModalResponse)code;
- (void)endApplicationSheet:(nullable NSWindow *)sheet;
- (void)window:(nullable NSWindow *)window
    addChildWindow:(NSWindow *)child
           ordered:(NSWindowOrderingMode)place;
- (void)window:(nullable NSWindow *)window removeChildWindow:(nullable NSWindow *)child;
- (void)orderFrontWindow:(nullable NSWindow *)window;
- (void)makeKeyAndOrderFrontWindow:(nullable NSWindow *)window;
- (void)makeKeyWindow:(nullable NSWindow *)window;
- (void)orderOutWindow:(nullable NSWindow *)window;
- (void)closeWindow:(nullable NSWindow *)window;
- (NSPopover *)makePopover;
@end

@protocol PCNativeScheduling <NSObject>
@property(nonatomic, readonly) NSTimeInterval systemUptime;
@property(nonatomic, readonly) NSDate *currentDate;
- (NSTimeInterval)timeIntervalSinceNowForDate:(nullable NSDate *)date;
- (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval
                          repeats:(BOOL)repeats
                            block:(void (^)(NSTimer *))block;
- (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                   repeats:(BOOL)repeats
                                     block:(void (^)(NSTimer *))block;
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
- (void)performInModes:(NSArray<NSRunLoopMode> *)modes block:(void (^)(void))block;
- (void)dispatchToMainQueue:(dispatch_block_t)block;
- (void)runAnimationGroup:(void (^)(NSAnimationContext *))changes
        completionHandler:(nullable void (^)(void))completion;
@end

@protocol PCNativePageHostObserver <NSObject>
// The actual view hierarchy's window, including nil on detachment. This does
// not transfer browser ownership or declare the page visible to Chromium.
- (void)pageHost:(PCNativePageHost *)host
    didMoveToWindow:(nullable NSWindow *)window;

// The queued focus request has been processed, even when no native focus send
// was possible. This is deliberately NOT a successful-focus acknowledgement.
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost *)host;
@end

// Main-thread-only. The engine retains this stable wrapper for the lifetime of
// its WebContents. The supplied view must be WebContents' native container;
// its first child is the renderer responder in the recovered managed hierarchy,
// skipping the pane compositor's display view (pane_compositor_view.h).
// This class owns neither an NSWindow nor a Browser/TabModel.
__attribute__((visibility("default")))
@interface PCNativePageHost : NSView

// Reuses an exact PCNativePageHost parent without replacing its observer.
// Otherwise wraps this same view using its current frame and four edge pins.
+ (instancetype)hostWithContentView:(NSView *)contentView
                          observer:(nullable id<PCNativePageHostObserver>)observer;

@property(nonatomic, strong, readonly, nullable) NSView *contentView;
@property(nonatomic, strong) id<PCNativePresentation> presentation;
@property(nonatomic, strong) id<PCNativeScheduling> scheduler;

// Replaces the existing managed view only. nil, hierarchy cycles, a missing
// current view or an invalidated host return NO without changing containment.
// No tab transfer, navigation or focus request is performed by replacement.
- (BOOL)replaceContentView:(nullable NSView *)contentView;

// Reinstalls managed content that a native owner removed without replacing
// it: Chromium's ViewsHostableDetach removes the WebContents view it hosted.
// Refused once invalidated, while another view is managed, or for a view that
// still has a superview. Visibility is the caller's to restore.
- (BOOL)restoreContentView:(NSView *)contentView;

// Apply the engine adapter's actual shell visibility to the same managed
// native container. Chromium can create that container hidden for a background
// tab; showing its renderer child does not unhide the container. A show requires
// an unhidden host in the exact supplied window. Returns NO if native callbacks
// invalidate, replace or move this ownership during the operation. Does not
// select a tab, focus a view or send Chromium WasShown/WasHidden notifications.
- (BOOL)setContentVisible:(BOOL)visible inWindow:(NSWindow *)window;

// One page-owned native infobar shelf. Reserves space above the actual renderer
// instead of obscuring content. nil removes it. The shelf never becomes the
// managed content or renderer focus target; invalidation removes both.
- (void)setInfobarView:(nullable NSView *)view preferredHeight:(CGFloat)height;

- (nullable NSView *)historyOverlayContainer;

// Terminal teardown, called before the engine destroys the native page or its
// containing window. Detaches the view/host and suppresses pending callbacks.
// Repeated calls are harmless. The caller remains responsible for engine close
// consent and for reporting native visibility through the engine adapter.
- (void)invalidate;

- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END

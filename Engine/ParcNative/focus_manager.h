#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@class PCNativeFocusManager;
@protocol PCNativeScheduling;

typedef NS_ENUM(NSInteger, PCNativeFocusRequestResult) {
  PCNativeFocusRequestRejected,
  PCNativeFocusRequestAlreadyFocused,
  PCNativeFocusRequestPending,
  // AppKit accepted the request. A page host may still defer renderer focus.
  PCNativeFocusRequestAccepted,
};

// Retain for the registration's lifetime. Releasing or invalidating it removes
// only its own generation, so an older token cannot remove a replacement.
@interface PCNativeFocusRegistration : NSObject
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Main-thread-only. Keys are shell-supplied identities (for example content ID
// plus "find"/"page"); they are NOT a pane ordering or a Chromium tab index.
// Window and registered responders are weak. Callback owners should use weak
// captures if they also own the manager or registration token.
@interface PCNativeFocusManager : NSObject
- (instancetype)initWithWindow:(NSWindow*)window;
// Injectable wall-clock seconds for deterministic pending-boundary tests.
- (instancetype)initWithWindow:(NSWindow*)window
                         clock:(NSTimeInterval (^)(void))clock
    NS_DESIGNATED_INITIALIZER;
@property(nonatomic, weak, readonly, nullable) NSWindow* window;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
@property(nonatomic, copy, readonly, nullable) NSString* focusedKey;
// Optional selected page key. Used only after observing a nil first responder
// with no fresh pending request; never selects a pane or steals nonnil focus.
@property(nonatomic, copy, nullable) NSString* fallbackKey;
@property(nonatomic, strong) id<PCNativeScheduling> scheduler;

- (nullable PCNativeFocusRegistration*)
    registerResponder:(NSResponder*)responder
               forKey:(NSString*)key
            didBecome:(nullable void (^)(void))didBecome
            didResign:(nullable void (^)(void))didResign;
- (PCNativeFocusRequestResult)requestFocusForKey:(NSString*)key;
// Actual firstResponder KVO drives this automatically. The shell can call it
// after hierarchy changes or deferred page focus. It never assumes success
// merely from a request/host callback and does not schedule timed retries.
- (void)reconcileFirstResponder;
// Terminal, idempotent. Removes observations, pending state and registrations;
// it does not close a window/page or change first responder.
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END

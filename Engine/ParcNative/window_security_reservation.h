// Parc-owned shared-NSWindow security reservation. Main-thread only.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const PCNativeWindowSecurityStateChanged;
FOUNDATION_EXPORT BOOL
PCNativeWindowHasSecurityReservation(NSWindow* _Nullable window);
// State is committed before notifications. Observers may release reservations
// or destroy services. No key/frontmost lookup and no raw callback target.
@interface PCNativeWindowSecurityReservation : NSObject
+ (nullable instancetype)acquireForWindow:(NSWindow*)window;
@property(nonatomic, readonly, weak, nullable) NSWindow* window;
@property(nonatomic, readonly, getter=isActive) BOOL active;
// True only while this exact lease is the sole active reservation.
@property(nonatomic, readonly) BOOL isOnlyReservation;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END

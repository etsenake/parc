#pragma once

#import <AppKit/AppKit.h>

#ifdef __cplusplus
extern "C" {
#endif
void ParcNativeDispatch(dispatch_queue_t queue, dispatch_block_t block);
#ifdef __cplusplus
}
#endif

@interface NSProcessInfo (ParcNativeClock)
@property(readonly) NSTimeInterval parcSystemUptime;
@end
@interface NSDate (ParcNativeClock)
+ (NSDate*)parcDate;
- (NSTimeInterval)parcTimeIntervalSinceNow;
@end
@interface NSTimer (ParcNativeClock)
+ (NSTimer*)parcTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer*))block;
+ (NSTimer*)parcScheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer*))block;
@end
@interface NSRunLoop (ParcNativeClock)
- (void)parcAddTimer:(NSTimer*)timer forMode:(NSRunLoopMode)mode;
- (void)parcPerformInModes:(NSArray<NSRunLoopMode>*)modes block:(dispatch_block_t)block;
@end
@interface NSAnimationContext (ParcNativeClock)
+ (void)parcRunAnimationGroup:(void (^)(NSAnimationContext*))changes completionHandler:(dispatch_block_t)completion;
@end

#define systemUptime parcSystemUptime
#define date parcDate
#define timeIntervalSinceNow parcTimeIntervalSinceNow
#define timerWithTimeInterval parcTimerWithTimeInterval
#define scheduledTimerWithTimeInterval parcScheduledTimerWithTimeInterval
#define addTimer parcAddTimer
#define performInModes parcPerformInModes
#define dispatch_async ParcNativeDispatch
#define runAnimationGroup parcRunAnimationGroup

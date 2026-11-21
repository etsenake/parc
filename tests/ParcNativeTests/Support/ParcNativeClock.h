#pragma once

#import <Foundation/Foundation.h>

#import "page_host.h"

NS_ASSUME_NONNULL_BEGIN

@interface ParcNativeTestScheduler : NSObject <PCNativeScheduling>
@property(nonatomic, readonly) NSTimeInterval now;
- (void)settle;
- (void)advance:(NSTimeInterval)seconds;
- (void)invalidate;
@end

#ifdef __cplusplus
extern "C" {
#endif
ParcNativeTestScheduler* ParcNativeScheduler(void);
void ParcNativeSettle(void);
void ParcNativeAdvance(NSTimeInterval seconds);
NSTimeInterval ParcNativeNow(void);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

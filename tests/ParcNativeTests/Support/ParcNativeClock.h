#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
void ParcNativeSettle(void);
void ParcNativeAdvance(NSTimeInterval seconds);
NSTimeInterval ParcNativeNow(void);
#ifdef __cplusplus
}
#endif

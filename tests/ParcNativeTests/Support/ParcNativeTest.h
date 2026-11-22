#pragma once

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

#import "ParcNativeClock.h"
#import "ParcNativeWindows.h"

#ifdef __cplusplus
extern "C" {
#endif
void ParcNativeCheck(BOOL passed, const char* expression, const char* file, int line);
void ParcNativeCheckMessage(const char* file, int line, bool passed, const char* message);
#ifdef __cplusplus
}
#endif

#define PARC_CHECK(condition) ParcNativeCheck((condition) ? YES : NO, #condition, __FILE__, __LINE__)

@interface ParcNativeTestCase : XCTestCase
@property(nonatomic, readonly) ParcNativeTestPresentation* presentation;
@property(nonatomic, readonly) ParcNativeTestScheduler* scheduler;
+ (Class)presentationClass;
@end

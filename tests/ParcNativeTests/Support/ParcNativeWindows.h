#pragma once

#import <AppKit/AppKit.h>

#ifdef __cplusplus
extern "C" {
#endif
NSWindow* ParcNativeOffscreenWindow(NSRect frame, NSWindowStyleMask style);
void ParcNativeMarkVisible(NSWindow* window);
BOOL ParcNativeWindowOrderedForReal(NSWindow* window);
#ifdef __cplusplus
}
#endif

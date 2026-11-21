#pragma once

#import <AppKit/AppKit.h>

NSCursor* ParcNativeCursor(void);
BOOL ParcNativeBackgroundCursorEnabled(void);
NSPoint ParcNativePointerLocation(void);
void ParcNativeResetPointer(void);

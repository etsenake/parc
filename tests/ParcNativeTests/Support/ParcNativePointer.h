#pragma once

#import <AppKit/AppKit.h>
#import "VideoPiPWindow.h"

@interface ParcNativePointerEnvironment : PCVideoPiPEnvironment
@property(nonatomic, readonly) NSCursor* cursor;
@property(nonatomic, readonly) BOOL backgroundCursorEnabled;
@property(nonatomic) NSPoint location;
@property(nonatomic) BOOL liveResize;
@end

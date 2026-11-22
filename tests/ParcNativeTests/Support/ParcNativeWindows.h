#pragma once

#import <AppKit/AppKit.h>

#import "page_host.h"

NS_ASSUME_NONNULL_BEGIN

@interface ParcNativeTestPresentation : NSObject <PCNativePresentation>
@property(nonatomic, copy, nullable) void (^willBeginSheet)(NSWindow* window, NSWindow* sheet);
@property(nonatomic, copy, nullable) void (^didBeginSheet)(NSWindow* window, NSWindow* sheet);
- (void)markVisible:(NSWindow*)window;
@end

@interface ParcNativePopoverWindow : NSWindow
@property(weak) NSPopover* popover;
@property(weak) NSView* anchorView;
@property NSRect anchorRect;
@property NSRectEdge anchorEdge;
@end

#ifdef __cplusplus
extern "C" {
#endif
ParcNativeTestPresentation* ParcNativePresentation(void);
NSWindow* ParcNativeOffscreenWindow(NSRect frame, NSWindowStyleMask style);
void ParcNativeMarkVisible(NSWindow* window);
BOOL ParcNativeVisible(NSWindow* _Nullable window);
NSWindow* _Nullable ParcNativeAttachedSheet(NSWindow* _Nullable window);
NSWindow* _Nullable ParcNativeSheetParent(NSWindow* _Nullable window);
NSWindow* _Nullable ParcNativeParentWindow(NSWindow* _Nullable window);
NSArray<NSWindow*>* _Nullable ParcNativeChildWindows(NSWindow* _Nullable window);
void ParcNativeBeginSheet(NSWindow* window, NSWindow* sheet, void (^_Nullable completion)(NSModalResponse));
void ParcNativeEndSheet(NSWindow* _Nullable window, NSWindow* _Nullable sheet);
void ParcNativeEndSheetWithCode(NSWindow* _Nullable window, NSWindow* _Nullable sheet, NSModalResponse code);
void ParcNativeOrderOut(NSWindow* _Nullable window);
void ParcNativeMakeKey(NSWindow* _Nullable window);
void ParcNativeClose(NSWindow* _Nullable window);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

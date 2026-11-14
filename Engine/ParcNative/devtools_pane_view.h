// Copyright 2026 Parc contributors.
// Native containment only. The engine retains both real WebContents objects.
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface PCNativeDevToolsPaneView : NSView
- (instancetype)initWithInspectedView:(NSView*)view;
@property(nonatomic, readonly) NSView* inspectedView;
@property(nonatomic, readonly) NSView* inspectedOverlay;
@property(nonatomic, readonly, nullable) NSView* toolsView;
@property(nonatomic, copy, nullable) void (^layoutHandler)(NSRect bounds);
- (BOOL)setHostedToolsView:(nullable NSView*)view;
// Rectangles are computed by Chromium's real resizing strategy, in flipped
// local coordinates. hideInspected also controls the Find overlay.
- (void)applyInspectedRect:(NSRect)inspected
                 toolsRect:(NSRect)tools
             hideInspected:(BOOL)hidden;
- (BOOL)focusTools;
- (void)setToolsBlocked:(BOOL)blocked;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END

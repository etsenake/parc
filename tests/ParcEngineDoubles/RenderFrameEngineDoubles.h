#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface RenderFrameTestPage : NSObject
@property(nonatomic, readonly) NSObject *page;
@property(nonatomic, readonly) NSView *host;
@property(nonatomic) CGFloat infobarHeight;
@property(nonatomic, readonly) NSUInteger liveObservations;
- (instancetype)initWithRenderer:(NSView *)renderer reportsFrames:(BOOL)reportsFrames
    NS_SWIFT_NAME(init(renderer:reportsFrames:));
- (void)drawViewport:(NSSize)viewport NS_SWIFT_NAME(draw(_:));
@end

NS_SWIFT_UI_ACTOR
@interface PCNativeDevToolsPaneView : NSView
@property(nonatomic, weak, nullable) NSView *inspected;
@property(nonatomic) CGFloat dockedWidth;
@property(nonatomic, readonly) NSUInteger layouts;
@end

NS_ASSUME_NONNULL_END

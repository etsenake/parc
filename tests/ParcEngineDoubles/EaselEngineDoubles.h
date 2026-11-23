#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface EaselTestEngineWindow : NSObject
@property(nonatomic, readonly) NSObject *binding;
@property(nonatomic, readonly) NSUInteger creations;
@property(nonatomic, readonly, nullable) NSURL *requestedURL;
@property(nonatomic, readonly, nullable) NSString *requestedProfile;
@property(nonatomic) BOOL allowsClose;
@property(nonatomic, readonly) NSUInteger closeRequests;
- (instancetype)initWithWindow:(NSWindow *)window;
- (BOOL)replyWithPage:(NSObject *)page NS_SWIFT_NAME(reply(with:));
@end

NS_SWIFT_UI_ACTOR
@interface EaselTestEnginePage : NSObject
@property(nonatomic, readonly) NSObject *page;
@property(nonatomic, weak, nullable) EaselTestEngineWindow *owner;
@property(nonatomic) BOOL embeddedOwnerValid;
@property(nonatomic, getter=isClosed) BOOL closed;
@property(nonatomic, copy) NSURL *URL;
@property(nonatomic, readonly) NSUInteger loads;
@property(nonatomic, readonly) NSView *nativeView;
@property(nonatomic, readonly, nullable) NSObject *crash;
- (void)setCrashed:(BOOL)crashed;
@property(nonatomic) BOOL supportsSnapshot;
@property(nonatomic) BOOL refusesSnapshot;
@property(nonatomic, readonly) NSUInteger snapshotRequests;
- (void)replyWithSnapshot:(nullable NSImage *)image NS_SWIFT_NAME(reply(withSnapshot:));
@property(nonatomic, readonly) double liveDisplayZoom;
@property(nonatomic) double siteZoom;
@property(nonatomic, readonly) double positionedWidth;
@property(nonatomic, readonly) NSUInteger positionRequests;
@property(nonatomic, readonly) NSRect positionedRegion;
@property(nonatomic, readonly) NSPoint positionedScroll;
@property(nonatomic, readonly) NSArray<NSString *> *positionedContainerPaths;
@property(nonatomic, readonly) NSArray<NSValue *> *positionedContainerOffsets;
- (BOOL)positionWasCancelledAtIndex:(NSUInteger)index NS_SWIFT_NAME(positionWasCancelled(at:));
- (void)replyAtPositionIndex:(NSUInteger)index success:(BOOL)success NS_SWIFT_NAME(reply(atPosition:success:));
- (instancetype)initWithURL:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END

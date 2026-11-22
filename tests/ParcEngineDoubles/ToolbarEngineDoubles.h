#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface ToolbarTestEnginePage : NSObject
@property(nonatomic, readonly) NSObject *page;
@property(nonatomic, copy, nullable) NSURL *URL;
@property(nonatomic) BOOL closed;
@property(nonatomic) BOOL loading;
@property(nonatomic, strong, nullable) NSColor *developerModeTint;
@property(nonatomic, strong, nullable) NSColor *pageBackgroundColor;
@property(nonatomic) BOOL reportsPageBackgroundColor;
@property(nonatomic) BOOL reportsTopBandColor;
@property(nonatomic) BOOL hasTopBandColorSample;
@property(nonatomic, strong, nullable) NSColor *topBandColor;
@property(nonatomic, copy, nullable) NSString *topBandColorHost;
@property(nonatomic) BOOL topBandColorCrossfades;
@end

NS_ASSUME_NONNULL_END

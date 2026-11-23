#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PageCaptureTestMethod) {
    PageCaptureTestMethodRegion,
    PageCaptureTestMethodViewport,
    PageCaptureTestMethodFullPage,
    PageCaptureTestMethodElement,
};

NS_SWIFT_UI_ACTOR
@interface PageCaptureTestLease : NSObject
@property(nonatomic, readonly) NSObject *lease;
@property(nonatomic, getter=isValid) BOOL valid;
@property(nonatomic) NSSize viewportSize;
@property(nonatomic) NSRect viewportFrame;
@property(nonatomic, copy) NSString *sourceURL;
@property(nonatomic, copy) NSString *pageTitle;
@property(nonatomic, strong, nullable) NSColor *pageThemeColor;
@property(nonatomic, copy, nullable) NSData *pngData;
@property(nonatomic, copy, nullable) NSData *pdfData;
@property(nonatomic, copy, nullable) NSString *errorMessage;
@property(nonatomic) BOOL deliversImmediately;
@property(nonatomic) BOOL includesLayout;
@property(nonatomic) NSSize layoutViewportSize;
@property(nonatomic) NSPoint layoutScrollOffset;
@property(nonatomic) NSRect layoutRegion;
@property(nonatomic, readonly) NSArray<NSNumber *> *captureMethods;
@property(nonatomic, readonly) NSRect lastRegion;
@property(nonatomic, readonly) NSUInteger pendingCaptures;
@property(nonatomic, readonly) NSUInteger invalidations;
@property(nonatomic, readonly) BOOL hasInvalidationHandler;
- (BOOL)deliverNextCapture;
- (void)invalidateFromEngine;
@end

NS_ASSUME_NONNULL_END

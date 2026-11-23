#import "PageCaptureEngineDoubles.h"
#import "ParcEngine.h"

@interface PageCaptureTestLayout : PCNativeCaptureLayout
@property(nonatomic) NSSize fixtureViewportSize;
@property(nonatomic) NSPoint fixtureScrollOffset;
@property(nonatomic) NSRect fixtureRegion;
@end

@implementation PageCaptureTestLayout
- (NSSize)viewportSize { return self.fixtureViewportSize; }
- (NSPoint)scrollOffset { return self.fixtureScrollOffset; }
- (NSRect)region { return self.fixtureRegion; }
- (NSArray<PCNativeCaptureScrollContainer *> *)scrollContainers { return @[]; }
@end

@interface PageCaptureTestResult : PCNativePageCaptureResult
@property(nonatomic, copy, nullable) NSData *fixturePNG;
@property(nonatomic, copy, nullable) NSString *fixtureError;
@property(nonatomic, strong, nullable) PCNativeCaptureLayout *fixtureLayout;
@property(nonatomic, copy, nullable) NSData *fixturePDF;
@end

@implementation PageCaptureTestResult
- (NSData *)pngData { return self.fixturePNG; }
- (NSImage *)image { return nil; }
- (NSSize)pixelSize { return NSZeroSize; }
- (NSString *)errorMessage { return self.fixtureError; }
- (PCNativeCaptureLayout *)layout { return self.fixtureLayout; }
- (NSData *)pdfData { return self.fixturePDF; }
@end

@interface PageCaptureTestNativeLease : PCNativePageCapture
@property(nonatomic, weak) PageCaptureTestLease *fixture;
@property(nonatomic, copy, nullable) void (^fixtureInvalidated)(void);
@end

@interface PageCaptureTestLease ()
@property(nonatomic, strong) PageCaptureTestNativeLease *nativeLease;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *methods;
@property(nonatomic, strong) NSMutableArray<void (^)(PCNativePageCaptureResult *)> *pending;
@property(nonatomic, readwrite) NSRect lastRegion;
@property(nonatomic, readwrite) NSUInteger invalidations;
- (void)requestCapture:(PageCaptureTestMethod)method completion:(void (^)(PCNativePageCaptureResult *))completion;
@end

@implementation PageCaptureTestNativeLease
- (BOOL)isValid { return self.fixture.valid; }
- (BOOL)isCapturing { return self.fixture.pendingCaptures > 0; }
- (NSSize)viewportSize { return self.fixture.viewportSize; }
- (NSRect)viewportFrame { return self.fixture.viewportFrame; }
- (NSString *)sourceURL { return self.fixture.sourceURL; }
- (NSString *)pageTitle { return self.fixture.pageTitle; }
- (NSColor *)pageThemeColor { return self.fixture.pageThemeColor; }
- (void (^)(void))invalidated { return self.fixtureInvalidated; }
- (void)setInvalidated:(void (^)(void))invalidated { self.fixtureInvalidated = invalidated; }
- (void)invalidate {
    self.fixture.invalidations += 1;
    self.fixture.valid = NO;
}
- (void)targetElementAtPoint:(NSPoint)point completion:(void (^)(PCNativePageCaptureTarget *))completion {
    (void)point;
    completion(nil);
}
- (void)captureElement:(PCNativePageCaptureTarget *)target completion:(void (^)(PCNativePageCaptureResult *))completion {
    (void)target;
    [self.fixture requestCapture:PageCaptureTestMethodElement completion:completion];
}
- (void)captureRegion:(NSRect)region completion:(void (^)(PCNativePageCaptureResult *))completion {
    self.fixture.lastRegion = region;
    [self.fixture requestCapture:PageCaptureTestMethodRegion completion:completion];
}
- (void)captureViewportWithCompletion:(void (^)(PCNativePageCaptureResult *))completion {
    [self.fixture requestCapture:PageCaptureTestMethodViewport completion:completion];
}
- (void)captureFullPageWithCompletion:(void (^)(PCNativePageCaptureResult *))completion {
    [self.fixture requestCapture:PageCaptureTestMethodFullPage completion:completion];
}
@end

@implementation PageCaptureTestLease

- (instancetype)init {
    if ((self = [super init])) {
        _nativeLease = (PageCaptureTestNativeLease *)[(NSObject *)[PageCaptureTestNativeLease alloc] init];
        _nativeLease.fixture = self;
        _methods = [NSMutableArray array];
        _pending = [NSMutableArray array];
        _valid = YES;
        _viewportSize = NSMakeSize(800, 600);
        _viewportFrame = NSMakeRect(0, 0, 800, 600);
        _sourceURL = @"https://example.test/page";
        _pageTitle = @"Example page";
        _deliversImmediately = YES;
    }
    return self;
}

- (NSObject *)lease { return self.nativeLease; }
- (NSArray<NSNumber *> *)captureMethods { return [self.methods copy]; }
- (NSUInteger)pendingCaptures { return self.pending.count; }
- (BOOL)hasInvalidationHandler { return self.nativeLease.fixtureInvalidated != nil; }

- (void)requestCapture:(PageCaptureTestMethod)method completion:(void (^)(PCNativePageCaptureResult *))completion {
    [self.methods addObject:@(method)];
    [self.pending addObject:[completion copy]];
    if (self.deliversImmediately) [self deliverNextCapture];
}

- (PCNativePageCaptureResult *)makeResult {
    PageCaptureTestResult *result = (PageCaptureTestResult *)[(NSObject *)[PageCaptureTestResult alloc] init];
    result.fixturePNG = self.pngData;
    result.fixturePDF = self.pdfData;
    result.fixtureError = self.errorMessage;
    if (self.includesLayout) {
        PageCaptureTestLayout *layout = (PageCaptureTestLayout *)[(NSObject *)[PageCaptureTestLayout alloc] init];
        layout.fixtureViewportSize = self.layoutViewportSize;
        layout.fixtureScrollOffset = self.layoutScrollOffset;
        layout.fixtureRegion = self.layoutRegion;
        result.fixtureLayout = layout;
    }
    return result;
}

- (BOOL)deliverNextCapture {
    if (self.pending.count == 0) return NO;
    void (^completion)(PCNativePageCaptureResult *) = self.pending.firstObject;
    [self.pending removeObjectAtIndex:0];
    completion([self makeResult]);
    return YES;
}

- (void)invalidateFromEngine {
    self.valid = NO;
    void (^handler)(void) = self.nativeLease.fixtureInvalidated;
    if (handler) handler();
}

@end

#import "EaselEngineDoubles.h"
#import "ParcEngine.h"
#import <objc/runtime.h>

static char easelWindowAssociation;

@interface EaselTestFocusableView : NSView
@end

@implementation EaselTestFocusableView
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface EaselTestRequest : PCNativeEmbeddedPageRequest
@property(nonatomic, copy, nullable) BOOL (^validateOwner)(void);
@property(nonatomic, copy, nullable) void (^reply)(PCNativePage *, NSError *);
@end

@implementation EaselTestRequest
- (BOOL)isPending { return self.reply != nil; }
- (void)cancel {
    void (^reply)(PCNativePage *, NSError *) = self.reply;
    self.reply = nil;
    self.validateOwner = nil;
    if (reply) reply(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]);
}
@end

@interface EaselTestPosition : PCNativeLiveCapturePosition
@property(nonatomic) BOOL cancelled;
@property(nonatomic, copy, nullable) void (^reply)(BOOL);
@end

@implementation EaselTestPosition
- (void)cancel { self.cancelled = YES; }
@end

@interface EaselTestSnapshot : PCNativePageCaptureResult
@property(nonatomic, strong, nullable) NSImage *fixtureImage;
@end

@implementation EaselTestSnapshot
- (NSImage *)image { return self.fixtureImage; }
@end

@interface EaselTestCrash : PCNativeRendererCrash
@end

@implementation EaselTestCrash
- (NSString *)title { return @"Fixture crash"; }
- (NSString *)message { return @"The page crashed"; }
- (NSString *)actionTitle { return @"Reload"; }
@end

@interface EaselTestBinding : PCNativeBrowserWindow
@property(nonatomic, weak) NSWindow *fixtureWindow;
@property(nonatomic, weak) EaselTestEngineWindow *fixture;
@property(nonatomic, strong) EaselTestRequest *request;
@property(nonatomic, readwrite) NSUInteger creations;
@property(nonatomic, readwrite) NSUInteger closeRequests;
@property(nonatomic, copy) NSURL *requestedURL;
@property(nonatomic, copy) NSString *requestedProfile;
@end

@interface EaselTestPage : PCNativePage
@property(nonatomic, weak) EaselTestEnginePage *fixture;
@property(nonatomic, weak, nullable) id<PCNativePageObserver> fixtureObserver;
@property(nonatomic, copy, nullable) void (^snapshotReply)(PCNativePageCaptureResult *);
@property(nonatomic, strong) NSMutableArray<EaselTestPosition *> *positions;
@property(nonatomic) NSRect positionedRegion;
@property(nonatomic) NSPoint positionedScroll;
@property(nonatomic, copy) NSArray<NSString *> *positionedContainerPaths;
@property(nonatomic, copy) NSArray<NSValue *> *positionedContainerOffsets;
@property(nonatomic, readwrite) NSUInteger snapshotRequests;
@property(nonatomic, readwrite) NSUInteger loads;
@end

@implementation EaselTestBinding
- (NSWindow *)window { return self.fixtureWindow; }
- (void)pageWillDetach:(PCNativePage *)page { (void)page; }
- (BOOL)pageDidAttach:(PCNativePage *)page container:(NSView *)container {
    if (page.nativeView.superview != container) [container addSubview:page.nativeView];
    return YES;
}
- (PCNativeEmbeddedPageRequest *)createEmbeddedPageWithURL:(NSURL *)url
    referrer:(NSURL *)referrer profilePath:(NSString *)profilePath container:(NSView *)container
    validateOwner:(BOOL (^)(void))validateOwner completion:(void (^)(PCNativePage *, NSError *))completion {
    (void)referrer;
    (void)container;
    self.creations += 1;
    self.requestedURL = url;
    self.requestedProfile = profilePath;
    EaselTestRequest *request = (EaselTestRequest *)[(NSObject *)[EaselTestRequest alloc] init];
    request.validateOwner = validateOwner;
    request.reply = completion;
    self.request = request;
    return request;
}
@end

@interface EaselTestEngineWindow ()
@property(nonatomic, strong) EaselTestBinding *fixtureBinding;
@end

@implementation EaselTestEngineWindow
- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super init];
    if (self) {
        _fixtureBinding = (EaselTestBinding *)[(NSObject *)[EaselTestBinding alloc] init];
        _fixtureBinding.fixtureWindow = window;
        _fixtureBinding.fixture = self;
        _allowsClose = YES;
        objc_setAssociatedObject(window, &easelWindowAssociation, _fixtureBinding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}
- (NSObject *)binding { return self.fixtureBinding; }
- (NSUInteger)creations { return self.fixtureBinding.creations; }
- (NSUInteger)closeRequests { return self.fixtureBinding.closeRequests; }
- (NSURL *)requestedURL { return self.fixtureBinding.requestedURL; }
- (NSString *)requestedProfile { return self.fixtureBinding.requestedProfile; }
- (BOOL)replyWithPage:(NSObject *)page {
    EaselTestRequest *request = self.fixtureBinding.request;
    if (!request.reply || !request.validateOwner || !request.validateOwner()) return NO;
    void (^reply)(PCNativePage *, NSError *) = request.reply;
    request.reply = nil;
    request.validateOwner = nil;
    reply((PCNativePage *)page, nil);
    return YES;
}
@end

@interface EaselTestEnginePage ()
@property(nonatomic, strong) EaselTestPage *fixturePage;
@property(nonatomic, strong) NSView *nativeView;
@property(nonatomic, strong, nullable) PCNativeRendererCrash *fixtureCrash;
@end

@implementation EaselTestEnginePage
- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _fixturePage = (EaselTestPage *)[(NSObject *)[EaselTestPage alloc] init];
        _fixturePage.fixture = self;
        _fixturePage.positions = [NSMutableArray array];
        _nativeView = [[EaselTestFocusableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _URL = [url copy];
        _embeddedOwnerValid = YES;
        _supportsSnapshot = YES;
    }
    return self;
}
- (NSObject *)page { return self.fixturePage; }
- (NSObject *)crash { return self.fixtureCrash; }
- (void)setCrashed:(BOOL)crashed {
    self.fixtureCrash = crashed ? (EaselTestCrash *)[(NSObject *)[EaselTestCrash alloc] init] : nil;
}
- (NSUInteger)loads { return self.fixturePage.loads; }
- (NSUInteger)snapshotRequests { return self.fixturePage.snapshotRequests; }
- (void)replyWithSnapshot:(NSImage *)image {
    void (^reply)(PCNativePageCaptureResult *) = self.fixturePage.snapshotReply;
    self.fixturePage.snapshotReply = nil;
    if (reply) {
        EaselTestSnapshot *snapshot = (EaselTestSnapshot *)[(NSObject *)[EaselTestSnapshot alloc] init];
        snapshot.fixtureImage = image;
        reply(snapshot);
    }
}
- (NSUInteger)positionRequests { return self.fixturePage.positions.count; }
- (NSRect)positionedRegion { return self.fixturePage.positionedRegion; }
- (NSPoint)positionedScroll { return self.fixturePage.positionedScroll; }
- (NSArray<NSString *> *)positionedContainerPaths { return self.fixturePage.positionedContainerPaths ?: @[]; }
- (NSArray<NSValue *> *)positionedContainerOffsets { return self.fixturePage.positionedContainerOffsets ?: @[]; }
- (BOOL)positionWasCancelledAtIndex:(NSUInteger)index {
    return index < self.fixturePage.positions.count && self.fixturePage.positions[index].cancelled;
}
- (void)replyAtPositionIndex:(NSUInteger)index success:(BOOL)success {
    if (index >= self.fixturePage.positions.count) return;
    EaselTestPosition *position = self.fixturePage.positions[index];
    void (^reply)(BOOL) = position.reply;
    position.reply = nil;
    if (reply) reply(success);
}
@end

@implementation EaselTestPage
- (BOOL)isEmbedded { return YES; }
- (BOOL)embeddedOwnerValid { return self.fixture.embeddedOwnerValid; }
- (NSString *)profilePath { return self.fixture.owner.requestedProfile ?: @""; }
- (NSView *)nativeView { return self.fixture.nativeView; }
- (NSURL *)URL { return self.fixture.URL; }
- (NSString *)title { return @"Fixture page"; }
- (PCNativeRendererCrash *)rendererCrash { return self.fixture.fixtureCrash; }
- (PCNativeCaptureState *)captureState { return nil; }
- (NSColor *)developerModeTint { return nil; }
- (BOOL)loading { return NO; }
- (BOOL)canGoBack { return NO; }
- (BOOL)canGoForward { return NO; }
- (BOOL)isClosed { return !self.fixture || self.fixture.isClosed; }
- (id<PCNativePageObserver>)observer { return self.fixtureObserver; }
- (void)setObserver:(id<PCNativePageObserver>)observer { self.fixtureObserver = observer; }
- (void)loadURL:(NSURL *)url { self.loads += 1; self.fixture.URL = url; }
- (BOOL)canPerformNavigationAction:(PCNativeNavigationAction)action { (void)action; return !self.isClosed; }
- (BOOL)rendererCrashDidPresent:(PCNativeRendererCrash *)crash { return crash == self.fixture.fixtureCrash; }
- (double)liveCaptureZoomFactor { return 1; }
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(snapshotEmbeddedPageWithCompletion:)) return self.fixture.supportsSnapshot;
    return [super respondsToSelector:selector];
}
- (BOOL)snapshotEmbeddedPageWithCompletion:(void (^)(PCNativePageCaptureResult *))completion {
    self.snapshotRequests += 1;
    if (self.fixture.refusesSnapshot) return NO;
    self.snapshotReply = completion;
    return YES;
}
- (PCNativeLiveCapturePosition *)positionLiveCapture:(NSRect)region
    scrollOffset:(NSPoint)scrollOffset scrollContainers:(NSArray<PCNativeCaptureScrollContainer *> *)containers
    displayWidth:(double)displayWidth completion:(void (^)(BOOL))completion {
    (void)displayWidth;
    EaselTestPosition *position = (EaselTestPosition *)[(NSObject *)[EaselTestPosition alloc] init];
    position.reply = completion;
    [self.positions addObject:position];
    self.positionedRegion = region;
    self.positionedScroll = scrollOffset;
    self.positionedContainerPaths = [containers valueForKey:@"path"];
    NSMutableArray<NSValue *> *offsets = [NSMutableArray array];
    for (PCNativeCaptureScrollContainer *container in containers) {
        [offsets addObject:[NSValue valueWithPoint:container.scrollOffset]];
    }
    self.positionedContainerOffsets = offsets;
    return position;
}
@end

static char anchorKey, pathKey, offsetKey, frameKey;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
@implementation PCNativeCaptureScrollContainer (EaselTestEngine)
- (instancetype)initWithAnchorID:(NSString *)anchorID path:(NSString *)path scrollOffset:(NSPoint)offset frame:(NSRect)frame {
    objc_setAssociatedObject(self, &anchorKey, anchorID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &pathKey, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &offsetKey, [NSValue valueWithPoint:offset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &frameKey, [NSValue valueWithRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (NSString *)anchorID { return objc_getAssociatedObject(self, &anchorKey); }
- (NSString *)path { return objc_getAssociatedObject(self, &pathKey); }
- (NSPoint)scrollOffset { return [objc_getAssociatedObject(self, &offsetKey) pointValue]; }
- (NSRect)frame { return [objc_getAssociatedObject(self, &frameKey) rectValue]; }
@end

@implementation PCNativeBrowserApplication (EaselTestEngine)
+ (PCNativeBrowserWindow *)windowForNativeWindow:(NSWindow *)window {
    return objc_getAssociatedObject(window, &easelWindowAssociation);
}
+ (PCNativeBrowserWindow *)ownerForPage:(PCNativePage *)page {
    if (![page isKindOfClass:EaselTestPage.class]) return nil;
    return ((EaselTestPage *)page).fixture.owner.fixtureBinding;
}
+ (void)requestClosePages:(NSArray<PCNativePage *> *)pages
    shouldCommit:(BOOL (^)(void))shouldCommit completion:(void (^)(BOOL))completion {
    for (PCNativePage *page in pages) {
        EaselTestBinding *binding = (EaselTestBinding *)[self ownerForPage:page];
        binding.closeRequests += 1;
        if (!binding.fixture.allowsClose) { completion(NO); return; }
    }
    BOOL allowed = shouldCommit();
    if (allowed) {
        for (EaselTestPage *page in pages) page.fixture.closed = YES;
    }
    completion(allowed);
}
@end
#pragma clang diagnostic pop

#import "RenderFrameEngineDoubles.h"
#import "ParcEngine.h"

@interface RenderFrameTestObservation : PCNativeRenderFrameObservation
@property(nonatomic, copy, nullable) void (^handler)(NSSize);
@end

@implementation RenderFrameTestObservation
- (void)invalidate { self.handler = nil; }
@end


@interface RenderFrameTestHostView : PCNativePageHost
@property(nonatomic, weak, nullable) NSView *renderer;
@end

@implementation RenderFrameTestHostView
- (NSView *)contentView { return self.renderer; }
@end

@interface RenderFrameTestPageDouble : PCNativePage
@property(nonatomic, weak) RenderFrameTestPage *fixture;
@property(nonatomic, weak, nullable) id<PCNativePageObserver> fixtureObserver;
@end

@interface RenderFrameTestPage ()
@property(nonatomic, strong) RenderFrameTestPageDouble *double_;
@property(nonatomic, strong) NSView *host;
@property(nonatomic, strong) NSView *renderer;
@property(nonatomic, strong) NSLayoutConstraint *shelf;
@property(nonatomic) BOOL reportsFrames;
@property(nonatomic) NSSize drawn;
@property(nonatomic, strong) NSMutableArray<RenderFrameTestObservation *> *observations;
@end

@implementation RenderFrameTestPage
- (instancetype)initWithRenderer:(NSView *)renderer reportsFrames:(BOOL)reportsFrames {
    self = [super init];
    if (self) {
        _renderer = renderer;
        _reportsFrames = reportsFrames;
        _observations = [NSMutableArray array];
        RenderFrameTestHostView *host = (RenderFrameTestHostView *)[(NSView *)[RenderFrameTestHostView alloc] initWithFrame:NSZeroRect];
        host.renderer = renderer;
        _host = host;
        NSView *infobar = [[NSView alloc] initWithFrame:NSZeroRect];
        _shelf = [infobar.heightAnchor constraintEqualToConstant:0];
        for (NSView *view in @[infobar, renderer]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [_host addSubview:view];
        }
        [NSLayoutConstraint activateConstraints:@[
            [infobar.topAnchor constraintEqualToAnchor:_host.topAnchor], _shelf,
            [infobar.leadingAnchor constraintEqualToAnchor:_host.leadingAnchor],
            [infobar.trailingAnchor constraintEqualToAnchor:_host.trailingAnchor],
            [renderer.topAnchor constraintEqualToAnchor:infobar.bottomAnchor],
            [renderer.bottomAnchor constraintEqualToAnchor:_host.bottomAnchor],
            [renderer.leadingAnchor constraintEqualToAnchor:_host.leadingAnchor],
            [renderer.trailingAnchor constraintEqualToAnchor:_host.trailingAnchor],
        ]];
        _double_ = (RenderFrameTestPageDouble *)[(NSObject *)[RenderFrameTestPageDouble alloc] init];
        _double_.fixture = self;
    }
    return self;
}
- (NSObject *)page { return self.double_; }
- (CGFloat)infobarHeight { return self.shelf.constant; }
- (void)setInfobarHeight:(CGFloat)height { self.shelf.constant = height; }
- (NSUInteger)liveObservations {
    NSUInteger count = 0;
    for (RenderFrameTestObservation *observation in self.observations) {
        if (observation.handler) count += 1;
    }
    return count;
}
- (void)drawViewport:(NSSize)viewport {
    self.drawn = viewport;
    for (RenderFrameTestObservation *observation in [self.observations copy]) {
        if (observation.handler) observation.handler(viewport);
    }
}
- (RenderFrameTestObservation *)observe:(void (^)(NSSize))handler {
    RenderFrameTestObservation *observation =
        (RenderFrameTestObservation *)[(NSObject *)[RenderFrameTestObservation alloc] init];
    observation.handler = handler;
    [self.observations addObject:observation];
    return observation;
}
@end

@implementation RenderFrameTestPageDouble
- (NSView *)nativeView { return self.fixture.host; }
- (BOOL)isClosed { return NO; }
- (NSString *)profilePath { return @""; }
- (NSString *)title { return @""; }
- (NSURL *)URL { return nil; }
- (BOOL)loading { return NO; }
- (BOOL)canGoBack { return NO; }
- (BOOL)canGoForward { return NO; }
- (NSColor *)developerModeTint { return nil; }
- (PCNativeCaptureState *)captureState { return nil; }
- (PCNativeRendererCrash *)rendererCrash { return nil; }
- (id<PCNativePageObserver>)observer { return self.fixtureObserver; }
- (void)setObserver:(id<PCNativePageObserver>)observer { self.fixtureObserver = observer; }
- (NSSize)renderFrameViewportSize { return self.fixture.drawn; }
- (PCNativeRenderFrameObservation *)observeRenderFrameViewportSize:(void (^)(NSSize))handler {
    return [self.fixture observe:handler];
}
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(renderFrameViewportSize) || selector == @selector(observeRenderFrameViewportSize:)) {
        return self.fixture.reportsFrames;
    }
    return [super respondsToSelector:selector];
}
@end

@implementation PCNativeDevToolsPaneView
- (BOOL)isFlipped { return YES; }
- (void)setDockedWidth:(CGFloat)dockedWidth {
    _dockedWidth = dockedWidth;
    self.needsLayout = YES;
}
- (void)layout {
    [super layout];
    _layouts += 1;
    self.inspected.frame = NSMakeRect(0, 0, self.bounds.size.width - self.dockedWidth, self.bounds.size.height);
}
@end

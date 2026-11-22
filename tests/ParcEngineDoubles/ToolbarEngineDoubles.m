#import "ToolbarEngineDoubles.h"
#import "ParcEngine.h"

@interface ToolbarTestPage : PCNativePage
@property(nonatomic, weak) ToolbarTestEnginePage *fixture;
@end

@implementation ToolbarTestPage
- (NSURL *)URL { return self.fixture.URL; }
- (BOOL)isClosed { return self.fixture.closed; }
- (BOOL)loading { return self.fixture.loading; }
- (NSColor *)developerModeTint { return self.fixture.developerModeTint; }
- (NSColor *)pageBackgroundColor { return self.fixture.pageBackgroundColor; }
- (BOOL)hasTopBandColorSample { return self.fixture.hasTopBandColorSample; }
- (NSColor *)topBandColor { return self.fixture.topBandColor; }
- (NSString *)topBandColorHost { return self.fixture.topBandColorHost; }
- (BOOL)topBandColorCrossfades { return self.fixture.topBandColorCrossfades; }
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(topBandColor)) return self.fixture.reportsTopBandColor;
    if (selector == @selector(pageBackgroundColor)) return self.fixture.reportsPageBackgroundColor;
    return [super respondsToSelector:selector];
}
@end

@interface ToolbarTestEnginePage ()
@property(nonatomic, strong) ToolbarTestPage *fixturePage;
@end

@implementation ToolbarTestEnginePage
- (instancetype)init {
    self = [super init];
    if (self) {
        _fixturePage = (ToolbarTestPage *)[(NSObject *)[ToolbarTestPage alloc] init];
        _fixturePage.fixture = self;
        _reportsPageBackgroundColor = YES;
    }
    return self;
}
- (NSObject *)page { return self.fixturePage; }
@end

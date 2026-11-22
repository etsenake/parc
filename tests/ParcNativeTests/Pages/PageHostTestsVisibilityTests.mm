#import "PageHostTestsSupport.h"

using namespace PageHostTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PageHostTestsVisibilityTests")))
@interface PageHostTestsVisibilityTests : ParcNativeTestCase
@end

@implementation PageHostTestsVisibilityTests

- (void)testAHiddenParkingViewCannotShowThePage {
  PageFixture f;
  f.Attach();
  NSView *parking = [[NSView alloc] initWithFrame:NSZeroRect];
  parking.hidden = YES;
  [f.window.contentView addSubview:parking];
  f.page.hidden = YES;
  [parking addSubview:f.host];
  Check(f.page.hidden && f.host.contentView == f.page,
        "background adoption preserves the same initially hidden native child");
  XCTAssertTrue([f.host setContentVisible:NO inWindow:f.window]);
  XCTAssertFalse([f.host setContentVisible:YES inWindow:f.window]);
}

- (void)testSelectingAParkedPageSizesAndShowsTheOriginalRenderer {
  NSWindow *window = Window();
  NSView *parking = [[NSView alloc] initWithFrame:NSZeroRect];
  parking.hidden = YES;
  [window.contentView addSubview:parking];
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  PageHostTestsRendererView *renderer = [[PageHostTestsRendererView alloc] initWithFrame:NSZeroRect];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [parking addSubview:host];
  Check(page.hidden && host.contentView == page,
        "background adoption preserves the same initially hidden native child");
  [window.contentView addSubview:host];
  host.frame = NSMakeRect(0, 0, 640, 360);
  renderer.hidden = NO;
  XCTAssertTrue([host setContentVisible:YES inWindow:window]);
  Check(!page.hidden && !renderer.hiddenOrHasHiddenAncestor,
        "selected initially-hidden native content and its renderer are actually unhidden");
  Check(host.contentView == page && page.superview == host && renderer.superview == page,
        "showing preserves the original native child and renderer identity");
  Check(NSEqualSizes(page.frame.size, NSMakeSize(640, 360)) &&
            NSEqualSizes(renderer.frame.size, NSMakeSize(640, 360)),
        "zero-sized parked page reaches actual selected host dimensions");
  [host invalidate];
  ParcNativeClose(window);
}

- (void)testShowingVisibleContentSkipsRedundantVisibilityCallbacks {
  NSWindow *window = Window();
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  PageHostTestsRendererView *renderer = [[PageHostTestsRendererView alloc] initWithFrame:NSZeroRect];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [window.contentView addSubview:host];
  XCTAssertTrue([host setContentVisible:YES inWindow:window]);
  NSUInteger changes = page.hiddenChanges;
  Check([host setContentVisible:YES inWindow:window] && page.hiddenChanges == changes,
        "repeated visibility does not emit another native hide callback");
  Check([host setContentVisible:NO inWindow:window] && page.hidden,
        "returning to background hides the same managed parent");
  [host invalidate];
  ParcNativeClose(window);
}

- (void)testAnotherWindowCannotExposeAHiddenPage {
  PageFixture f;
  f.Attach();
  f.page.hidden = YES;
  NSWindow *unrelated = Window();
  Check(![f.host setContentVisible:YES inWindow:unrelated] && f.page.hidden,
        "another supplied window cannot expose the page");
  ParcNativeClose(unrelated);
}

- (void)testDetachedContentIgnoresStaleVisibility {
  PageFixture f;
  f.Attach();
  f.page.hidden = YES;
  [f.host removeFromSuperview];
  Check(![f.host setContentVisible:YES inWindow:f.window] && f.page.hidden,
        "detached content is not exposed by stale presentation");
}

- (void)testShowingAnInitiallyVisiblePageSizesItsRendererAndCompositor {
  FreshPage f(NO);
  Check(!ParcNativeVisible(f.window) && !f.window.isKeyWindow,
        "fresh-page check needs no window activation or display");
  Check(NSIsEmptyRect(f.page.bounds) && NSIsEmptyRect(f.renderer.bounds),
        "new native page and renderer have no size before presentation");
  Check([f.host setContentVisible:YES inWindow:f.window], "fresh page can be shown");
  Check(NSEqualSizes(f.page.bounds.size, f.host.bounds.size) &&
            NSEqualSizes(f.renderer.bounds.size, f.host.bounds.size),
        "showing a brand-new page sizes its renderer without another window event");
  Check(NSEqualSizes(f.display.bounds.size, f.host.bounds.size),
        "the compositor display receives the same nonempty size");
  Check(!f.page.hidden, "fresh page is visible after its geometry is ready");
}

- (void)testShowingAnInitiallyHiddenPageSizesItsRendererAndCompositor {
  FreshPage f(YES);
  Check(!ParcNativeVisible(f.window) && !f.window.isKeyWindow,
        "fresh-page check needs no window activation or display");
  Check(NSIsEmptyRect(f.page.bounds) && NSIsEmptyRect(f.renderer.bounds),
        "new native page and renderer have no size before presentation");
  Check([f.host setContentVisible:YES inWindow:f.window], "fresh page can be shown");
  Check(NSEqualSizes(f.page.bounds.size, f.host.bounds.size) &&
            NSEqualSizes(f.renderer.bounds.size, f.host.bounds.size),
        "showing a brand-new page sizes its renderer without another window event");
  Check(NSEqualSizes(f.display.bounds.size, f.host.bounds.size),
        "the compositor display receives the same nonempty size");
  Check(!f.page.hidden, "fresh page is visible after its geometry is ready");
}

- (void)testSettledVisibilitySkipsRendererLayout {
  FreshPage f(YES);
  [f.host setContentVisible:YES inWindow:f.window];
  const NSUInteger layouts = f.page.subtreeLayouts;
  XCTAssertTrue([f.host setContentVisible:YES inWindow:f.window]);
  XCTAssertEqual(f.page.subtreeLayouts, layouts);
}

- (void)testAnInfobarReservesSpaceBeforeThePageIsShown {
  FreshPage f(YES);
  f.host.frame = NSMakeRect(0, 0, 640, 360);
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.host setInfobarView:shelf preferredHeight:30];
  Check([f.host setContentVisible:YES inWindow:f.window], "resized page can be shown");
  Check(NSEqualSizes(f.page.bounds.size, NSMakeSize(640, 330)) &&
            NSEqualSizes(f.renderer.bounds.size, f.page.bounds.size),
        "showing settles the page below its infobar at the new size");
}

- (void)testResizingAnInfobarChangesThePageInset {
  FreshPage f(YES);
  f.host.frame = NSMakeRect(0, 0, 640, 360);
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.host setInfobarView:shelf preferredHeight:30];
  [f.host setInfobarView:shelf preferredHeight:60];
  Check([f.host setContentVisible:YES inWindow:f.window] &&
            NSEqualSizes(f.page.bounds.size, NSMakeSize(640, 300)),
        "changing an existing infobar settles its new inset before show");
}

- (void)testRemovingAnInfobarReturnsItsSpaceToThePage {
  FreshPage f(YES);
  f.host.frame = NSMakeRect(0, 0, 640, 360);
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.host setInfobarView:shelf preferredHeight:30];
  [f.host setInfobarView:nil preferredHeight:0];
  Check([f.host setContentVisible:YES inWindow:f.window] &&
            NSEqualSizes(f.page.bounds.size, NSMakeSize(640, 360)),
        "removing an infobar gives the page its full size before show");
}

- (void)testShowingAReplacementSettlesItsGeometry {
  FreshPage f(YES);
  f.host.frame = NSMakeRect(0, 0, 640, 360);
  NSView *replacement = [[NSView alloc] initWithFrame:NSZeroRect];
  Check([f.host replaceContentView:replacement], "fresh native content can replace the old view");
  Check([f.host setContentVisible:YES inWindow:f.window] &&
            NSEqualSizes(replacement.bounds.size, NSMakeSize(640, 360)),
        "same-size host settles a newly replaced content view");
}

- (void)withParkedPage:(void (^)(NSWindow*, NSView*, NSView*, NSView*, PCNativePageHost*, PCNativeDevToolsPaneView*, NSView*, PageHostTestsRendererView*))check {
  NSWindow *first = Window();
  NSView *parking = [[NSView alloc] initWithFrame:NSZeroRect];
  parking.hidden = YES;
  [first.contentView addSubview:parking];
  NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 320)];
  NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(240, 0, 240, 320)];
  [first.contentView addSubview:left];
  [first.contentView addSubview:right];
  PageHostTestsRendererView *renderer = nil;
  NSView *page = Page(&renderer);
  page.frame = NSZeroRect;
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  PCNativeDevToolsPaneView *pane = [[PCNativeDevToolsPaneView alloc]
      initWithInspectedView:host];
  [parking addSubview:pane];
  [pane applyInspectedRect:NSZeroRect toolsRect:NSZeroRect hideInspected:NO];
  check(first, parking, left, right, host, pane, page, renderer);
  [pane invalidate];
  [host invalidate];
  ParcNativeClose(first);
}

- (void)testSelectingAParkedSplitSizesItOnTheFirstShow {
  [self withParkedPage:^(NSWindow* first, NSView*, NSView* left, NSView*, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView* page, PageHostTestsRendererView* renderer) {
    Check(![host setContentVisible:YES inWindow:first] && page.hidden,
          "a new parked page stays hidden until a visible pane owns it");
    [left addSubview:pane];
    pane.frame = left.bounds;
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    Check([host setContentVisible:YES inWindow:first] &&
              NSEqualSizes(page.bounds.size, left.bounds.size) &&
              NSEqualSizes(renderer.bounds.size, left.bounds.size),
          "selecting a parked page sizes it to its split pane without a window event");
  }];
}

- (void)testReselectingAParkedSplitRestoresItsDimensions {
  [self withParkedPage:^(NSWindow* first, NSView* parking, NSView* left, NSView*, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView*, PageHostTestsRendererView* renderer) {
    [left addSubview:pane];
    pane.frame = left.bounds;
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    [host setContentVisible:YES inWindow:first];
    Check([host setContentVisible:NO inWindow:first], "hide a page before parking it");
    [parking addSubview:pane];
    pane.frame = NSZeroRect;
    [pane applyInspectedRect:NSZeroRect toolsRect:NSZeroRect hideInspected:NO];
    [left addSubview:pane];
    pane.frame = left.bounds;
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    Check([host setContentVisible:YES inWindow:first] &&
              NSEqualSizes(renderer.bounds.size, left.bounds.size),
          "reselecting a parked page restores its dimensions immediately");
  }];
}

- (void)testMovingASplitPagePreservesBothPagesGeometry {
  [self withParkedPage:^(NSWindow* first, NSView*, NSView* left, NSView* right, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView* page, PageHostTestsRendererView* renderer) {
    NSWindow *second = Window();
    [second setContentSize:NSMakeSize(720, 480)];
    [left addSubview:pane];
    pane.frame = left.bounds;
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    [host setContentVisible:YES inWindow:first];
    NSView *otherPage = [[NSView alloc] initWithFrame:NSZeroRect];
    PCNativePageHost *otherHost = Offscreen([PCNativePageHost hostWithContentView:otherPage observer:nil]);
    PCNativeDevToolsPaneView *otherPane = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:otherHost];
    otherPane.frame = right.bounds;
    [right addSubview:otherPane];
    [otherPane applyInspectedRect:otherPane.bounds toolsRect:NSZeroRect hideInspected:NO];
    Check([otherHost setContentVisible:YES inWindow:first] &&
              NSEqualSizes(otherPage.bounds.size, right.bounds.size) && !page.hidden,
          "each displayed split page gets its own geometry without needing focus");
    Check([host setContentVisible:NO inWindow:first], "hide a page before window transfer");
    [pane invalidate];
    PCNativeDevToolsPaneView *moved = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:host];
    moved.frame = second.contentView.bounds;
    [second.contentView addSubview:moved];
    [moved applyInspectedRect:moved.bounds toolsRect:NSZeroRect hideInspected:NO];
    Check(![host setContentVisible:YES inWindow:first] && page.hidden,
          "the previous window cannot show a transferred page");
    Check([host setContentVisible:YES inWindow:second] &&
              NSEqualSizes(page.bounds.size, second.contentView.bounds.size) &&
              NSEqualSizes(renderer.bounds.size, second.contentView.bounds.size),
          "the receiving window sizes and shows the same page without activation");
    Check(!otherPage.hidden && NSEqualSizes(otherPage.bounds.size, right.bounds.size),
          "moving one split page preserves the other page's geometry and visibility");
    Check(!ParcNativeVisible(first) && !ParcNativeVisible(second) && !first.isKeyWindow && !second.isKeyWindow,
          "split selection and window transfer require no displayed or key test window");
    [moved invalidate];
    [otherPane invalidate];
    [otherHost invalidate];
    ParcNativeClose(second);
  }];
}

- (void)testRestoringTheNativeViewSettlesItsEdgesBeforeShow {
  PageFixture f;
  f.Attach();
  [f.host setContentVisible:NO inWindow:f.window];
  f.host.frame = f.window.contentView.bounds;
  [f.page removeFromSuperview];
  f.page.frame = NSZeroRect;
  Check([f.host restoreContentView:f.page], "reattach the native content to its existing host");
  Check([f.host setContentVisible:YES inWindow:f.window] &&
            NSEqualSizes(f.renderer.bounds.size, f.window.contentView.bounds.size),
        "reattachment into an unchanged host settles the new edge constraints");
}

@end

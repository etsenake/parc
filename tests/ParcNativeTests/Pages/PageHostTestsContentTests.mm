#import "PageHostTestsSupport.h"

using namespace PageHostTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PageHostTestsContentTests")))
@interface PageHostTestsContentTests : ParcNativeTestCase
@end

@implementation PageHostTestsContentTests

- (void)testANewHostAdoptsTheSuppliedPageAndFrame {
  NSView* page = Page(nullptr);
  NSRect originalFrame = page.frame;
  PCNativePageHost* host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  Check(host.contentView == page, "host preserves actual supplied page identity");
  Check(page.superview == host, "supplied view is hosted, not recreated");
  Check(NSEqualRects(host.frame, originalFrame), "initial host adopts supplied frame");
  [host invalidate];
}

- (void)testANewHostConstrainsThePageAtAllFourEdges {
  NSView* page = Page(nullptr);
  PCNativePageHost* host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  Check(!page.translatesAutoresizingMaskIntoConstraints, "page uses edge constraints");
  Check(host.constraints.count == 4, "exactly four owned edge constraints");
  for (NSLayoutConstraint *constraint in host.constraints) {
    Check(constraint.active && constraint.constant == 0 && constraint.multiplier == 1,
          "edge constraints are active equalities without insets");
    Check(constraint.relation == NSLayoutRelationEqual, "edge constraints are equalities");
  }
  [host invalidate];
}

- (void)testTheSamePageReusesItsHostAndConstraints {
  PageFixture f;
  PageHostTestsHostObserver *ignored = [PageHostTestsHostObserver new];
  PCNativePageHost *reused = Offscreen([PCNativePageHost hostWithContentView:f.page observer:ignored]);
  Check(reused == f.host, "exact existing host is reused");
  Check(f.host.subviews.count == 1 && f.host.constraints.count == 4,
        "reuse adds no view or constraints");
}

- (void)testReusingAHostKeepsTheOriginalObserver {
  PageFixture f;
  PageHostTestsHostObserver *ignored = [PageHostTestsHostObserver new];
  Offscreen([PCNativePageHost hostWithContentView:f.page observer:ignored]);
  [f.window.contentView addSubview:f.host];
  Check(f.observer.lastWindow == f.window && [f.observer.moves.lastObject isEqual:@"attach"],
        "reuse retains original observer");
  Check(ignored.moves.count == 0, "reuse does not replace observer");
}

- (void)testResizingTheHostResizesItsRenderer {
  PageFixture f;
  f.Attach();
  f.host.frame = NSMakeRect(30, 40, 365, 219);
  [f.host layoutSubtreeIfNeeded];
  Check(NSEqualRects(f.page.frame, f.host.bounds), "resized page fills host bounds");
  Check(NSEqualSizes(f.renderer.frame.size, f.page.bounds.size), "renderer follows page size");
}

- (void)testWindowDetachmentPreservesTheLivePage {
  PageFixture f;
  f.Attach();
  [f.host removeFromSuperview];
  Check(f.observer.lastWindow == nil && [f.observer.moves.lastObject isEqual:@"detach"],
        "detachment reports nil actual window");
  Check(f.host.contentView == f.page, "window detachment preserves the live page");
}

- (void)testAnOrdinarySuperviewIsNotReusedAsAHost {
  NSView *old = Page(nullptr);
  NSView *unrelatedContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  [unrelatedContainer addSubview:old];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:old observer:nil]);
  Check(host != unrelatedContainer && unrelatedContainer.subviews.count == 0,
        "an ordinary parent is not mistaken for a reusable host");
  [host invalidate];
}

- (void)testReplacingContentSwapsTheViewAndItsConstraints {
  PageFixture f;
  f.Attach();
  NSArray<NSLayoutConstraint *> *oldConstraints = f.host.constraints;
  NSView *replacement = Page(nullptr);
  Check([f.host replaceContentView:replacement], "accept real replacement");
  Check(f.host.contentView == replacement && replacement.superview == f.host,
        "replacement retains supplied view identity");
  Check(f.page.superview == nil, "old page is detached");
  Check(f.host.constraints.count == 4, "replacement has only four new edge pins");
  for (NSLayoutConstraint *constraint in oldConstraints) {
    Check(!constraint.active, "old edge pins are removed");
  }
  [f.host layoutSubtreeIfNeeded];
  Check(NSEqualRects(replacement.frame, f.host.bounds), "replacement fills host");
}

- (void)testReplacingContentWithItselfIsIdempotent {
  PageFixture f;
  f.Attach();
  Check([f.host replaceContentView:f.page] && f.host.constraints.count == 4,
        "same-view replacement is idempotent");
}

- (void)testNilReplacementPreservesThePage {
  PageFixture f;
  f.Attach();
  Check(![f.host replaceContentView:nil], "nil replacement does not remove page");
  XCTAssertEqual(f.host.contentView, f.page);
}

- (void)testSelfReplacementPreservesThePage {
  PageFixture f;
  f.Attach();
  Check(![f.host replaceContentView:f.host], "self replacement rejects hierarchy cycle");
  XCTAssertEqual(f.host.contentView, f.page);
}

- (void)testAncestorReplacementPreservesThePage {
  PageFixture f;
  f.Attach();
  Check(![f.host replaceContentView:f.window.contentView], "ancestor replacement rejects cycle");
  XCTAssertEqual(f.host.contentView, f.page);
}

- (void)testExternalRemovalClearsOwnedConstraints {
  PageFixture f;
  f.Attach();
  [f.page removeFromSuperview];
  Check(f.host.contentView == nil && f.host.constraints.count == 0,
        "external removal clears owned reference and constraints");
  XCTAssertFalse([f.host replaceContentView:Page(nullptr)]);
}

- (void)testContentCannotBeRestoredWhileAlreadyManaged {
  PageFixture f;
  f.Attach();
  Check(![f.host restoreContentView:f.page], "managed content cannot be restored over itself");
  NSView *other = Page(nullptr);
  Check(![f.host restoreContentView:other], "nothing is restored while content is managed");
}

- (void)testARestoredPageResumesItsPositionBelowTheInfobar {
  PageFixture f;
  f.Attach();
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.host setInfobarView:shelf preferredHeight:30];
  [f.host layoutSubtreeIfNeeded];
  const NSRect pinned = f.page.frame;
  f.page.hidden = YES;
  [f.page removeFromSuperview];
  Check(f.host.contentView == nil, "native removal clears the managed content");
  Check([f.host restoreContentView:f.page], "the removed WebContents view is reinstalled");
  Check(f.host.contentView == f.page && f.page.superview == f.host &&
            f.host.subviews.firstObject == f.page && f.host.subviews.lastObject == shelf,
        "reinstalled content is below the infobar shelf");
  [f.host layoutSubtreeIfNeeded];
  Check(NSEqualRects(f.page.frame, pinned), "reinstalled content is pinned below the shelf again");
  Check(f.page.hidden, "restoring visibility is the caller's");
  Check(f.host.rendererResponder == f.renderer, "the renderer is the responder again");
}

- (void)testAViewOwnedElsewhereCannotBeRestored {
  PageFixture f;
  f.Attach();
  [f.page removeFromSuperview];
  NSView *stranger = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.window.contentView addSubview:stranger];
  Check(![f.host restoreContentView:stranger], "a view with another superview is refused");
}

- (void)testTheHostCannotBeRestoredInsideItself {
  PageFixture f;
  f.Attach();
  [f.page removeFromSuperview];
  Check(![f.host restoreContentView:f.host], "the host itself is refused");
}

- (void)testInvalidationPermanentlyClosesContentRestoration {
  PageFixture f;
  f.Attach();
  [f.page removeFromSuperview];
  [f.host invalidate];
  Check(![f.host restoreContentView:f.page] && f.page.superview == nil, "an invalidated host refuses");
}

- (void)testTheHistoryOverlayCoversAndClipsToItsHost {
  PageFixture f;
  f.Attach();
  NSView *container = f.host.historyOverlayContainer;
  Check(container && container.superview == f.host && f.host.subviews.lastObject == container,
        "the history overlay container is the host's top subview");
  Check(NSEqualRects(container.frame, f.host.bounds) && container.clipsToBounds,
        "the container covers and clips to the host");
}

- (void)testTheHistoryOverlayPreservesInputForTheRenderer {
  PageFixture f;
  f.Attach();
  NSView *container = f.host.historyOverlayContainer;
  Check(!container.acceptsFirstResponder &&
            [container hitTest:NSMakePoint(10, 10)] == nil,
        "the container never takes focus or clicks");
  Check(f.host.rendererResponder == f.renderer, "the renderer stays the responder");
}

- (void)testAnInfobarCannotCoverTheHistoryOverlay {
  PageFixture f;
  f.Attach();
  NSView *container = f.host.historyOverlayContainer;
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [f.host setInfobarView:shelf preferredHeight:30];
  Check(f.host.historyOverlayContainer == container && f.host.subviews.lastObject == container,
        "the same container returns above a later infobar shelf");
}

- (void)testTheHistoryOverlayFollowsHostResizing {
  PageFixture f;
  f.Attach();
  NSView *container = f.host.historyOverlayContainer;
  [f.host setFrameSize:NSMakeSize(500, 300)];
  Check(NSEqualRects(container.frame, f.host.bounds), "the container follows the host's size");
}

- (void)testInvalidatingTheHostRemovesItsHistoryOverlay {
  PageFixture f;
  f.Attach();
  NSView *container = f.host.historyOverlayContainer;
  [f.host invalidate];
  Check(f.host.historyOverlayContainer == nil && container.superview == nil,
        "invalidation removes the container");
}

@end

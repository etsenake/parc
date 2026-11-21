#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"
#import "ParcNativeClock.h"
#import <QuartzCore/QuartzCore.h>
#import "page_host.h"
#import "pane_compositor_view.h"
#import "devtools_pane_view.h"

#include <cstdio>
#include <cstdlib>


#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

@interface RendererView : NSView
@property(nonatomic) BOOL acceptsFocus;
@property(nonatomic) NSUInteger focusRequests;
@end
@implementation RendererView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) self.acceptsFocus = YES;
  return self;
}
- (BOOL)acceptsFirstResponder { return self.acceptsFocus; }
- (BOOL)becomeFirstResponder {
  self.focusRequests += 1;
  return self.acceptsFocus;
}
@end

@interface HostObserver : NSObject <PCNativePageHostObserver>
@property(nonatomic, strong) NSMutableArray<NSString *> *moves;
@property(nonatomic, weak) NSWindow *lastWindow;
@property(nonatomic) NSUInteger focusAttempts;
@end
@implementation HostObserver
- (instancetype)init {
  self = [super init];
  if (self) self.moves = [NSMutableArray array];
  return self;
}
- (void)pageHost:(PCNativePageHost *)host didMoveToWindow:(NSWindow *)window {
  Check(host.window == window, "observer gets the actual current host window");
  self.lastWindow = window;
  [self.moves addObject:window ? @"attach" : @"detach"];
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost *)host {
  (void)host;
  self.focusAttempts += 1;
}
@end

@interface ReentrantView : NSView
@property(nonatomic, copy) void (^didAttach)(void);
@end
@implementation ReentrantView
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window && self.didAttach) self.didAttach();
}
@end

@interface PCNativePageHost (VisibilityRegression)
- (BOOL)setContentVisible:(BOOL)visible inWindow:(NSWindow *)window;
@end

@interface VisibilityView : NSView
@property(nonatomic, copy) void (^visibilityChanged)(void);
@property(nonatomic) NSUInteger hiddenChanges;
@end
@implementation VisibilityView
- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  ++_hiddenChanges;
  void (^callback)(void) = self.visibilityChanged;
  if (callback) callback();
}
@end

@interface LayoutView : NSView
@property(nonatomic) NSUInteger subtreeLayouts;
@property(nonatomic, copy) void (^didLayout)(void);
@end
@implementation LayoutView
- (void)layoutSubtreeIfNeeded {
  ++_subtreeLayouts;
  [super layoutSubtreeIfNeeded];
}
- (void)layout {
  [super layout];
  if (self.didLayout) self.didLayout();
}
@end

static NSWindow *Window(void) {
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 320)
                styleMask:NSWindowStyleMaskBorderless
                  backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  return window;
}

static NSView *Page(RendererView *__strong *rendererOut) {
  NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(13, 17, 240, 150)];
  RendererView *renderer = [[RendererView alloc] initWithFrame:page.bounds];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  if (rendererOut) *rendererOut = renderer;
  return page;
}

static RendererView *SetSentinel(NSWindow *window) {
  RendererView *sentinel = [[RendererView alloc] initWithFrame:NSZeroRect];
  [window.contentView addSubview:sentinel];
  Check([window makeFirstResponder:sentinel], "set native sentinel responder");
  return sentinel;
}

static void DrainMainQueue(void) {
  ParcNativeSettle();
}

@interface PCNativePageHost (RendererResponder)
- (NSView *)rendererResponder;
@end

namespace {

struct PageFixture {
  NSWindow* window = Window();
  RendererView* renderer = nil;
  NSView* page = Page(&renderer);
  HostObserver* observer = [HostObserver new];
  PCNativePageHost* host = [PCNativePageHost hostWithContentView:page observer:observer];

  void Attach() { [window.contentView addSubview:host]; }
  ~PageFixture() {
    [host invalidate];
    [window close];
  }
};

struct FreshPage {
  NSWindow* window = Window();
  LayoutView* page = [[LayoutView alloc] initWithFrame:NSZeroRect];
  RendererView* renderer = [[RendererView alloc] initWithFrame:NSZeroRect];
  PCNativePaneCompositorView* display = [[PCNativePaneCompositorView alloc] initWithHostedLayer:[CALayer layer]];
  PCNativePageHost* host;
  PCNativeDevToolsPaneView* pane;
  explicit FreshPage(BOOL initiallyHidden) {
    NSView *wrapper = [[NSView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:wrapper];
    [window.contentView layoutSubtreeIfNeeded];
    page.hidden = initiallyHidden;
    renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [page addSubview:renderer];
    [page addSubview:display];
    host = [PCNativePageHost hostWithContentView:page observer:nil];
    pane = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:host];
    pane.frame = wrapper.bounds;
    [wrapper addSubview:pane];
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
  }
  ~FreshPage() {
    [pane invalidate];
    [host invalidate];
    [window close];
  }
};

struct CompositorFixture : PageFixture {
  PCNativePaneCompositorView* overlay = [[PCNativePaneCompositorView alloc] initWithHostedLayer:[CALayer layer]];
  NSUInteger geometryChanges = 0;
  NSUInteger screenChanges = 0;
  BOOL lastOnScreen = NO;
  CompositorFixture() {
    Attach();
    overlay.geometryHandler = ^{ ++geometryChanges; };
    overlay.screenHandler = ^{ ++screenChanges; lastOnScreen = overlay.onScreen; };
  }
  ~CompositorFixture() {
    overlay.geometryHandler = nil;
    overlay.screenHandler = nil;
  }
};
}

@interface PageHostTests : ParcNativeTestCase
@end

@implementation PageHostTests

- (void)testNewHostsAdoptTheSuppliedPageAndItsFrame {
  NSView* page = Page(nullptr);
  NSRect originalFrame = page.frame;
  PCNativePageHost* host = [PCNativePageHost hostWithContentView:page observer:nil];
  Check(host.contentView == page, "host preserves actual supplied page identity");
  Check(page.superview == host, "supplied view is hosted, not recreated");
  Check(NSEqualRects(host.frame, originalFrame), "initial host adopts supplied frame");
  Check(!page.translatesAutoresizingMaskIntoConstraints, "page uses edge constraints");
  Check(host.constraints.count == 4, "exactly four owned edge constraints");
  for (NSLayoutConstraint *constraint in host.constraints) {
    Check(constraint.active && constraint.constant == 0 && constraint.multiplier == 1,
          "edge constraints are active equalities without insets");
    Check(constraint.relation == NSLayoutRelationEqual, "edge constraints are equalities");
  }
  [host invalidate];
}

- (void)testAskingForTheSamePageReusesItsOriginalObserver {
  PageFixture f;
  HostObserver *ignored = [HostObserver new];
  PCNativePageHost *reused = [PCNativePageHost hostWithContentView:f.page observer:ignored];
  Check(reused == f.host, "exact existing host is reused");
  Check(f.host.subviews.count == 1 && f.host.constraints.count == 4,
        "reuse adds no view or constraints");
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
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:old observer:nil];
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

- (void)testFocusIsForwardedToTheRendererOnTheQueue {
  PageFixture f;
  f.Attach();
  SetSentinel(f.window);
  Check(f.host.acceptsFirstResponder, "acceptance is forwarded to renderer");
  Check([f.window makeFirstResponder:f.host], "AppKit accepts host focus request");
  Check(f.window.firstResponder == f.host && f.renderer.focusRequests == 0,
        "renderer focus is deferred, not falsely reported synchronous");
  DrainMainQueue();
  Check(f.window.firstResponder == f.renderer && f.renderer.focusRequests == 1,
        "queued request focuses real renderer in same window");
  Check(f.observer.focusAttempts == 1, "observer notified after queued request");
}

- (void)testReplacementCancelsFocusRequestedForThePreviousRenderer {
  PageFixture f;
  f.Attach();
  SetSentinel(f.window);
  Check([f.window makeFirstResponder:f.host], "queue focus before renderer replacement");
  [f.renderer removeFromSuperview];
  RendererView *next = [[RendererView alloc] initWithFrame:f.page.bounds];
  [f.page addSubview:next];
  Check(f.window.firstResponder == f.host, "replacement does not focus eagerly");
  DrainMainQueue();
  Check(f.window.firstResponder == f.host && next.focusRequests == 0,
        "a replacement renderer supersedes the request queued for the old one");
  XCTAssertEqual(f.renderer.focusRequests, 0u);
  SetSentinel(f.window);
  Check([f.window makeFirstResponder:f.host], "queue focus after the replacement");
  DrainMainQueue();
  Check(f.window.firstResponder == next && next.focusRequests == 1,
        "a request made after replacement focuses the new renderer");
}

- (void)testARejectingRendererStillReportsItsAttempt {
  PageFixture f;
  f.Attach();
  SetSentinel(f.window);
  f.renderer.acceptsFocus = NO;
  Check(!f.host.acceptsFirstResponder, "nonaccepting renderer is not hidden by host");
  Check([f.host becomeFirstResponder], "direct host request acknowledges queued attempt");
  DrainMainQueue();
  Check(f.window.firstResponder != f.renderer, "attempt callback does not turn rejected focus into success");
  Check(f.observer.focusAttempts == 1, "attempt callback does not imply native focus success");
}

- (void)testQueuedFocusCannotCrossAWindowMove {
  NSWindow *first = Window();
  NSWindow *second = Window();
  RendererView *renderer = nil;
  HostObserver *observer = [HostObserver new];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:Page(&renderer)
                                                     observer:observer];
  [first.contentView addSubview:host];
  RendererView *firstSentinel = SetSentinel(first);
  RendererView *destinationSentinel = SetSentinel(second);
  Check([host becomeFirstResponder], "queue focus before window move");
  [second.contentView addSubview:host];
  DrainMainQueue();
  Check(host.window == second && renderer.window == second, "host and page move together");
  Check(second.firstResponder == destinationSentinel && renderer.focusRequests == 0,
        "a move to another window supersedes the queued request");
  Check(first.firstResponder == firstSentinel, "old window responder stays unchanged");
  Check(observer.lastWindow == second, "attachment observer follows actual destination");
  [host invalidate];
  [first close];
  [second close];
}

- (void)testDetachmentCancelsQueuedRendererFocus {
  PageFixture f;
  f.Attach();
  RendererView *sentinel = SetSentinel(f.window);
  NSUInteger attempts = f.observer.focusAttempts;
  NSUInteger focusRequests = f.renderer.focusRequests;
  Check([f.host becomeFirstResponder], "queue focus before detachment");
  [f.host removeFromSuperview];
  DrainMainQueue();
  Check(f.host.window == nil && f.renderer.window == nil, "detached views have no native window");
  Check(f.window.firstResponder == sentinel && f.renderer.focusRequests == focusRequests,
        "detached request does not focus another window");
  Check(f.observer.focusAttempts == attempts + 1,
        "detached focus still reports processing, not success");
}

- (void)testInvalidatingAHostDetachesContentAndCancelsFocus {
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  HostObserver *observer = [HostObserver new];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:observer];
  [window.contentView addSubview:host];
  SetSentinel(window);
  [host becomeFirstResponder];
  NSUInteger moves = observer.moves.count;
  [host invalidate];
  [window close];
  DrainMainQueue();
  Check(host.contentView == nil && host.superview == nil && page.superview == nil,
        "teardown detaches both host and actual page");
  Check(host.constraints.count == 0, "teardown removes owned constraints");
  Check(renderer.focusRequests == 0 && observer.focusAttempts == 0,
        "closing owner cancels queued renderer focus and observer callback");
  Check(observer.moves.count == moves, "no observer callbacks after invalidation");
  [host invalidate];
  Check(!host.acceptsFirstResponder && ![host becomeFirstResponder],
        "invalidated host cannot accept another focus request");
  Check(![host replaceContentView:page], "invalidated host cannot resurrect contents");
}

- (void)testThePageHostDoesNotKeepItsObserverAlive {
  __weak HostObserver *weakObserver = nil;
  PCNativePageHost *weaklyObserved = nil;
  @autoreleasepool {
    HostObserver *temporary = [HostObserver new];
    weakObserver = temporary;
    weaklyObserved = [PCNativePageHost hostWithContentView:Page(nullptr) observer:temporary];
  }
  Check(weakObserver == nil, "host does not retain its observer");
  [weaklyObserved becomeFirstResponder];
  DrainMainQueue();
  [weaklyObserved invalidate];
}

- (void)testQueuedFocusReleasesTheWrapperAfterInvalidation {
  __weak PCNativePageHost *queuedHost = nil;
  __weak NSView *releasedPage = nil;
  @autoreleasepool {
    NSView *temporaryPage = Page(nullptr);
    PCNativePageHost *temporaryHost = [PCNativePageHost hostWithContentView:temporaryPage observer:nil];
    queuedHost = temporaryHost;
    releasedPage = temporaryPage;
    [temporaryHost becomeFirstResponder];
    [temporaryHost invalidate];
  }
  Check(queuedHost != nil, "queued request retains wrapper until execution");
  Check(releasedPage == nil, "invalidation releases supplied page before queued task");
  DrainMainQueue();
  Check(queuedHost == nil, "queued task releases invalidated wrapper without cycle");
}

- (void)testAReplacementCallbackCanInvalidateItsHost {
  NSWindow *window = Window();
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:Page(nullptr) observer:nil];
  [window.contentView addSubview:host];
  ReentrantView *replacement = [[ReentrantView alloc] initWithFrame:NSZeroRect];
  __weak PCNativePageHost *weakHost = host;
  replacement.didAttach = ^{ [weakHost invalidate]; };
  Check(![host replaceContentView:replacement], "reentrant teardown cancels replacement");
  Check(host.contentView == nil && host.superview == nil,
        "replacement callback cannot resurrect an invalidated host");
  Check(replacement.superview == nil && host.constraints.count == 0,
        "failed replacement leaves no attached page or stale edge pins");
  [window close];
}

- (void)testHidingAnAncestorCancelsQueuedFocus {
  PageFixture f;
  f.Attach();
  NSView* container = [[NSView alloc] initWithFrame:f.window.contentView.bounds];
  [f.window.contentView addSubview:container];
  [container addSubview:f.host];
  Check([f.host becomeFirstResponder], "queue focus before native crash presentation");
  container.hidden = YES;
  DrainMainQueue();
  Check(f.renderer.focusRequests == 0, "queued focus cannot enter hidden renderer ancestry");
  Check(!f.host.acceptsFirstResponder && ![f.host becomeFirstResponder],
        "hidden page rejects new focus requests");
}

- (void)testRestoringAHiddenRendererAdmitsFreshFocus {
  PageFixture f;
  f.Attach();
  f.renderer.hidden = YES;
  Check(!f.host.acceptsFirstResponder && ![f.host becomeFirstResponder],
        "hidden renderer rejects focus even when outer host remains visible");
  f.renderer.hidden = NO;
  Check([f.window makeFirstResponder:f.host], "same retained host can focus after restoration");
  DrainMainQueue();
  Check(f.renderer.focusRequests == 1, "restored host focuses real renderer once");
  [f.host invalidate];
  [f.window close];
}

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
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  RendererView *renderer = [[RendererView alloc] initWithFrame:NSZeroRect];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
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
  [window close];
}

- (void)testShowingVisibleContentSkipsRedundantVisibilityCallbacks {
  NSWindow *window = Window();
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  RendererView *renderer = [[RendererView alloc] initWithFrame:NSZeroRect];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [window.contentView addSubview:host];
  XCTAssertTrue([host setContentVisible:YES inWindow:window]);
  NSUInteger changes = page.hiddenChanges;
  Check([host setContentVisible:YES inWindow:window] && page.hiddenChanges == changes,
        "repeated visibility does not emit another native hide callback");
  Check([host setContentVisible:NO inWindow:window] && page.hidden,
        "returning to background hides the same managed parent");
  [host invalidate];
  [window close];
}

- (void)testAnotherWindowCannotExposeAHiddenPage {
  PageFixture f;
  f.Attach();
  f.page.hidden = YES;
  NSWindow *unrelated = Window();
  Check(![f.host setContentVisible:YES inWindow:unrelated] && f.page.hidden,
        "another supplied window cannot expose the page");
  [unrelated close];
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
  Check(!f.window.visible && !f.window.isKeyWindow,
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
  Check(!f.window.visible && !f.window.isKeyWindow,
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

- (void)withParkedPage:(void (^)(NSWindow*, NSView*, NSView*, NSView*, PCNativePageHost*, PCNativeDevToolsPaneView*, NSView*, RendererView*))check {
  NSWindow *first = Window();
  NSView *parking = [[NSView alloc] initWithFrame:NSZeroRect];
  parking.hidden = YES;
  [first.contentView addSubview:parking];
  NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 320)];
  NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(240, 0, 240, 320)];
  [first.contentView addSubview:left];
  [first.contentView addSubview:right];
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  page.frame = NSZeroRect;
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  PCNativeDevToolsPaneView *pane = [[PCNativeDevToolsPaneView alloc]
      initWithInspectedView:host];
  [parking addSubview:pane];
  [pane applyInspectedRect:NSZeroRect toolsRect:NSZeroRect hideInspected:NO];
  check(first, parking, left, right, host, pane, page, renderer);
  [pane invalidate];
  [host invalidate];
  [first close];
}

- (void)testSelectingAParkedSplitSizesItOnTheFirstShow {
  [self withParkedPage:^(NSWindow* first, NSView*, NSView* left, NSView*, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView* page, RendererView* renderer) {
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
  [self withParkedPage:^(NSWindow* first, NSView* parking, NSView* left, NSView*, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView*, RendererView* renderer) {
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
  [self withParkedPage:^(NSWindow* first, NSView*, NSView* left, NSView* right, PCNativePageHost* host, PCNativeDevToolsPaneView* pane, NSView* page, RendererView* renderer) {
    NSWindow *second = Window();
    [second setContentSize:NSMakeSize(720, 480)];
    [left addSubview:pane];
    pane.frame = left.bounds;
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    [host setContentVisible:YES inWindow:first];
    NSView *otherPage = [[NSView alloc] initWithFrame:NSZeroRect];
    PCNativePageHost *otherHost = [PCNativePageHost hostWithContentView:otherPage observer:nil];
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
    Check(!first.visible && !second.visible && !first.isKeyWindow && !second.isKeyWindow,
          "split selection and window transfer require no displayed or key test window");
    [moved invalidate];
    [otherPane invalidate];
    [otherHost invalidate];
    [second close];
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

- (void)testLayoutCanMoveThePageToAnotherWindow {
  NSWindow *first = Window();
  NSWindow *second = Window();
  LayoutView *page = [[LayoutView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  host.frame = first.contentView.bounds;
  [first.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak LayoutView *weakPage = page;
  page.needsLayout = YES;
  page.didLayout = ^{
    weakPage.didLayout = nil;
    [second.contentView addSubview:weakHost];
  };
  Check(![host setContentVisible:YES inWindow:first],
        "show is refused when layout transfers the page to another window");
  Check(host.window == second && page.hidden,
        "old layout leaves the new owner's page hidden");
  [host invalidate];
  [first close];
  [second close];
}

- (void)testANewerHideDuringLayoutSupersedesTheShow {
  NSWindow *first = Window();
  LayoutView *current = [[LayoutView alloc] initWithFrame:NSZeroRect];
  current.hidden = YES;
  PCNativePageHost *currentHost = [PCNativePageHost hostWithContentView:current observer:nil];
  currentHost.frame = first.contentView.bounds;
  [first.contentView addSubview:currentHost];
  __weak PCNativePageHost *weakCurrentHost = currentHost;
  __weak LayoutView *weakCurrent = current;
  current.needsLayout = YES;
  current.didLayout = ^{
    weakCurrent.didLayout = nil;
    Check([weakCurrentHost setContentVisible:NO inWindow:first],
          "layout can deliver a newer hide for the same owner");
  };
  Check(![currentHost setContentVisible:YES inWindow:first] && current.hidden,
        "the older show cannot reverse a hide delivered by layout");
  Check([currentHost setContentVisible:YES inWindow:first], "a later show succeeds");
  [first close];
}

- (void)testInvalidationDuringLayoutKeepsThePageHidden {
  NSWindow *first = Window();
  LayoutView *current = [[LayoutView alloc] initWithFrame:NSZeroRect];
  current.hidden = YES;
  PCNativePageHost *currentHost = [PCNativePageHost hostWithContentView:current observer:nil];
  currentHost.frame = first.contentView.bounds;
  [first.contentView addSubview:currentHost];
  __weak PCNativePageHost *weakCurrentHost = currentHost;
  __weak LayoutView *weakCurrent = current;
  currentHost.frame = NSMakeRect(0, 0, 640, 360);
  current.needsLayout = YES;
  current.didLayout = ^{
    weakCurrent.didLayout = nil;
    [weakCurrentHost invalidate];
  };
  Check(![currentHost setContentVisible:YES inWindow:first],
        "layout invalidation refuses the pending show");
  Check(current.hidden && current.superview == nil,
        "invalidated layout cannot resurrect or unhide its content");
  [first close];
}

- (void)testVisibilityCallbacksCanTransferWindowOwnership {
  NSWindow *first = Window();
  NSWindow *second = Window();
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [first.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak VisibilityView *weakPage = page;
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    [second.contentView addSubview:weakHost];
    Check([weakHost setContentVisible:NO inWindow:second],
          "new native owner can hide its adopted content during callback");
  };
  Check(![host setContentVisible:YES inWindow:first],
        "old show refuses success after native callback moves the host");
  Check(host.window == second && page.hidden,
        "old show leaves newer owner visibility and hierarchy intact");
  [host invalidate];
  Check(![host setContentVisible:YES inWindow:second], "invalidated host rejects visibility");
  [first close];
  [second close];
}

- (void)testVisibilityCallbacksCanChangeContainers {
  NSWindow *second = Window();
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak VisibilityView *weakPage = page;
  NSView *newContainer = [[NSView alloc] initWithFrame:second.contentView.bounds];
  [second.contentView addSubview:newContainer];
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    [newContainer addSubview:weakHost];
    Check([weakHost setContentVisible:NO inWindow:second],
          "same-window newer container can set its own visibility");
  };
  Check(![host setContentVisible:YES inWindow:second],
        "old show refuses same-window reparenting during native callback");
  Check(host.superview == newContainer && page.hidden,
        "same-window ownership supersession preserves the new hidden state");
  [host invalidate];
  [second close];
}

- (void)testVisibilityCallbacksCanSupersedeAShow {
  NSWindow *second = Window();
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak VisibilityView *weakPage = page;
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    Check([weakHost setContentVisible:NO inWindow:second],
          "newer visibility decision can hide the same attached child");
  };
  Check(![host setContentVisible:YES inWindow:second] && page.hidden,
        "old show cannot acknowledge a superseding hidden decision");
  [host invalidate];
  [second close];
}

- (void)testVisibilityCallbacksCanReplaceThePage {
  NSWindow *second = Window();
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak VisibilityView *weakPage = page;
  NSView *replacement = [[NSView alloc] initWithFrame:page.frame];
  replacement.hidden = YES;
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    Check([weakHost replaceContentView:replacement], "callback replaces exact managed native child");
  };
  Check(![host setContentVisible:YES inWindow:second],
        "old show refuses success after content replacement");
  Check(host.contentView == replacement && replacement.hidden && !page.superview,
        "old operation never unhides replacement content");
  [host invalidate];
  [second close];
}

- (void)testAConcealedPictureKeepsItsDisplayConnection {
  NSWindow *window = Window();
  NSView *parent = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:parent];
  CALayer *root = [CALayer layer];
  CALayer *connection = [CALayer layer];
  connection.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
  [root addSublayer:connection];
  PCNativePaneCompositorView *display =
      [[PCNativePaneCompositorView alloc] initWithHostedLayer:root];
  [parent addSubview:display];
  display.frame = parent.bounds;
  display.frameConcealed = YES;
  Check(display.onScreen && !display.hidden && connection.hidden,
        "concealing the old picture does not hide the compositor view or stop drawing");
  parent.hidden = YES;
  parent.hidden = NO;
  Check(display.onScreen && connection.hidden && display.frameConcealed,
        "ancestor visibility cannot prematurely reveal the old picture");
  display.frame = NSMakeRect(0, 0, 720, 480);
  Check(connection.superlayer == root && root.sublayers.firstObject == connection,
        "resizing a concealed picture preserves its display connection");
  Check(NSEqualSizes(connection.bounds.size, display.bounds.size),
        "the concealed connection still follows the display size");
  display.frameConcealed = NO;
  Check(!connection.hidden && connection.superlayer == root,
        "presentation reveals the same connection without another layer message");
  [display removeFromSuperview];
  [window close];
}

- (void)testAttachingAndResizingTheCompositorReportsGeometry {
  CompositorFixture f;
  Check(!f.overlay.onScreen, "an unplaced compositor view is off screen");
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  Check(f.geometryChanges >= 1, "joining a window reports geometry");
  NSUInteger changes = f.geometryChanges;
  f.overlay.frame = f.page.bounds;
  Check(f.geometryChanges == changes + 1, "a size change reports geometry");
  changes = f.geometryChanges;
  f.overlay.frame = f.page.bounds;
  Check(f.geometryChanges == changes, "an unchanged size reports nothing");
}

- (void)testACompositorBelowTheRendererPreservesKeyboardFocus {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  Check(f.overlay.onScreen, "in a window with no hidden ancestor is on screen");
  Check(f.page.subviews.firstObject == f.overlay && f.host.acceptsFirstResponder,
        "a compositor view below the renderer does not stand in for it");
  SetSentinel(f.window);
  Check([f.window makeFirstResponder:f.host], "host focus request with compositor view");
  DrainMainQueue();
  Check(f.window.firstResponder == f.renderer, "queued focus reaches the renderer, not the compositor view");
}

- (void)testACompositorAboveTheRendererPassesEventsThrough {
  CompositorFixture f;
  f.overlay.frame = f.page.bounds;
  [f.page addSubview:f.overlay positioned:NSWindowAbove relativeTo:f.renderer];
  Check(f.page.subviews.lastObject == f.overlay && f.host.acceptsFirstResponder,
        "a compositor view above the renderer leaves it the responder");
  Check(!f.overlay.acceptsFirstResponder && !f.overlay.isAccessibilityElement &&
            f.overlay.accessibilityChildren.count == 0,
        "compositor view takes no focus or accessibility");
  const NSPoint inside = [f.page convertPoint:NSMakePoint(20, 20) toView:f.page.superview];
  Check([f.page hitTest:inside] == f.renderer, "events pass through the compositor view to the renderer");
}

- (void)testPageVisibilityUpdatesTheCompositor {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  NSUInteger screens = f.screenChanges;
  f.page.hidden = YES;
  Check(!f.overlay.onScreen, "a hidden WebContents view takes its compositor view off screen");
  Check(f.screenChanges > screens && !f.lastOnScreen,
        "hiding the WebContents view reports leaving the screen at once");
  screens = f.screenChanges;
  f.page.hidden = NO;
  Check(f.screenChanges > screens && f.lastOnScreen, "unhiding it reports rejoining the screen");
}

- (void)testAncestorVisibilityUpdatesTheCompositor {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  NSUInteger screens = f.screenChanges;
  f.host.hidden = YES;
  Check(!f.overlay.onScreen, "a hidden ancestor takes it off screen");
  Check(f.screenChanges > screens && !f.lastOnScreen, "a hidden ancestor reports leaving the screen");
  screens = f.screenChanges;
  f.host.hidden = NO;
  Check(f.overlay.onScreen, "unhiding brings it back on screen");
  Check(f.screenChanges > screens && f.lastOnScreen, "an unhidden ancestor reports rejoining");
}

- (void)testParkingAndUnparkingUpdateTheCompositor {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  NSUInteger screens = f.screenChanges;
  NSView *parked = [[NSView alloc] initWithFrame:f.window.contentView.bounds];
  parked.hidden = YES;
  [f.window.contentView addSubview:parked];
  screens = f.screenChanges;
  [parked addSubview:f.host];
  Check(f.screenChanges > screens && !f.lastOnScreen && !f.overlay.onScreen,
        "parking the page reports leaving the screen at once");
  screens = f.screenChanges;
  [f.window.contentView addSubview:f.host];
  Check(f.screenChanges > screens && f.lastOnScreen && f.overlay.onScreen,
        "unparking it reports rejoining the screen");
}

- (void)testLeavingAndRejoiningAWindowUpdatesTheCompositor {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  NSUInteger screens = f.screenChanges;
  const NSUInteger before = f.geometryChanges;
  screens = f.screenChanges;
  [f.overlay removeFromSuperview];
  Check(!f.overlay.onScreen && f.geometryChanges > before, "leaving the window reports geometry");
  Check(f.screenChanges > screens && !f.lastOnScreen, "leaving the window reports leaving the screen");
  screens = f.screenChanges;
  [f.page addSubview:f.overlay positioned:NSWindowAbove relativeTo:f.renderer];
  Check(f.screenChanges > screens && f.lastOnScreen, "joining a shown page reports the screen");
}

- (void)testACompositorCannotServeAsAFallbackRenderer {
  CompositorFixture f;
  f.renderer.acceptsFocus = NO;
  [f.page addSubview:f.overlay positioned:NSWindowAbove relativeTo:f.renderer];
  Check(!f.host.acceptsFirstResponder, "a nonaccepting renderer is still the one consulted");
  [f.renderer removeFromSuperview];
  Check(!f.host.acceptsFirstResponder, "a page with only the compositor view has no renderer");
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

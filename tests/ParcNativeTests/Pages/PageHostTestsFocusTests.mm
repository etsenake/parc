#import "PageHostTestsSupport.h"

using namespace PageHostTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PageHostTestsFocusTests")))
@interface PageHostTestsFocusTests : ParcNativeTestCase
@end

@implementation PageHostTestsFocusTests

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
  PageHostTestsRendererView *next = [[PageHostTestsRendererView alloc] initWithFrame:f.page.bounds];
  [f.page addSubview:next];
  Check(f.window.firstResponder == f.host, "replacement does not focus eagerly");
  DrainMainQueue();
  Check(f.window.firstResponder == f.host && next.focusRequests == 0,
        "a replacement renderer supersedes the request queued for the old one");
  XCTAssertEqual(f.renderer.focusRequests, 0u);
}

- (void)testARequestAfterReplacementFocusesTheNewRenderer {
  PageFixture f;
  f.Attach();
  SetSentinel(f.window);
  Check([f.window makeFirstResponder:f.host], "queue focus before renderer replacement");
  [f.renderer removeFromSuperview];
  PageHostTestsRendererView *next = [[PageHostTestsRendererView alloc] initWithFrame:f.page.bounds];
  [f.page addSubview:next];
  DrainMainQueue();
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
  PageHostTestsRendererView *renderer = nil;
  PageHostTestsHostObserver *observer = [PageHostTestsHostObserver new];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:Page(&renderer)
                                                     observer:observer]);
  [first.contentView addSubview:host];
  PageHostTestsRendererView *firstSentinel = SetSentinel(first);
  PageHostTestsRendererView *destinationSentinel = SetSentinel(second);
  Check([host becomeFirstResponder], "queue focus before window move");
  [second.contentView addSubview:host];
  DrainMainQueue();
  Check(host.window == second && renderer.window == second, "host and page move together");
  Check(second.firstResponder == destinationSentinel && renderer.focusRequests == 0,
        "a move to another window supersedes the queued request");
  Check(first.firstResponder == firstSentinel, "old window responder stays unchanged");
  Check(observer.lastWindow == second, "attachment observer follows actual destination");
  [host invalidate];
  ParcNativeClose(first);
  ParcNativeClose(second);
}

- (void)testDetachmentCancelsQueuedRendererFocus {
  PageFixture f;
  f.Attach();
  PageHostTestsRendererView *sentinel = SetSentinel(f.window);
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

- (void)testInvalidationDetachesTheHostAndContent {
  NSWindow *window = Window();
  PageHostTestsRendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PageHostTestsHostObserver *observer = [PageHostTestsHostObserver new];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:observer]);
  [window.contentView addSubview:host];
  SetSentinel(window);
  [host becomeFirstResponder];
  [host invalidate];
  ParcNativeClose(window);
  DrainMainQueue();
  Check(host.contentView == nil && host.superview == nil && page.superview == nil,
        "teardown detaches both host and actual page");
  Check(host.constraints.count == 0, "teardown removes owned constraints");
}

- (void)testInvalidationCancelsFocusAndObserverCallbacks {
  NSWindow *window = Window();
  PageHostTestsRendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PageHostTestsHostObserver *observer = [PageHostTestsHostObserver new];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:observer]);
  [window.contentView addSubview:host];
  SetSentinel(window);
  [host becomeFirstResponder];
  NSUInteger moves = observer.moves.count;
  [host invalidate];
  ParcNativeClose(window);
  DrainMainQueue();
  Check(renderer.focusRequests == 0 && observer.focusAttempts == 0,
        "closing owner cancels queued renderer focus and observer callback");
  Check(observer.moves.count == moves, "no observer callbacks after invalidation");
}

- (void)testInvalidationDisallowsNewFocus {
  NSWindow *window = Window();
  PageHostTestsRendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PageHostTestsHostObserver *observer = [PageHostTestsHostObserver new];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:observer]);
  [window.contentView addSubview:host];
  SetSentinel(window);
  [host becomeFirstResponder];
  [host invalidate];
  ParcNativeClose(window);
  DrainMainQueue();
  [host invalidate];
  Check(!host.acceptsFirstResponder && ![host becomeFirstResponder],
        "invalidated host cannot accept another focus request");
}

- (void)testInvalidationDisallowsReplacingContent {
  NSWindow *window = Window();
  PageHostTestsRendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PageHostTestsHostObserver *observer = [PageHostTestsHostObserver new];
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:observer]);
  [window.contentView addSubview:host];
  SetSentinel(window);
  [host becomeFirstResponder];
  [host invalidate];
  ParcNativeClose(window);
  DrainMainQueue();
  [host invalidate];
  Check(![host replaceContentView:page], "invalidated host cannot resurrect contents");
}

- (void)testThePageHostDoesNotKeepItsObserverAlive {
  __weak PageHostTestsHostObserver *weakObserver = nil;
  PCNativePageHost *weaklyObserved = nil;
  @autoreleasepool {
    PageHostTestsHostObserver *temporary = [PageHostTestsHostObserver new];
    weakObserver = temporary;
    weaklyObserved = Offscreen([PCNativePageHost hostWithContentView:Page(nullptr) observer:temporary]);
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
    PCNativePageHost *temporaryHost = Offscreen([PCNativePageHost hostWithContentView:temporaryPage observer:nil]);
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
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:Page(nullptr) observer:nil]);
  [window.contentView addSubview:host];
  PageHostTestsReentrantView *replacement = [[PageHostTestsReentrantView alloc] initWithFrame:NSZeroRect];
  __weak PCNativePageHost *weakHost = host;
  replacement.didAttach = ^{ [weakHost invalidate]; };
  Check(![host replaceContentView:replacement], "reentrant teardown cancels replacement");
  Check(host.contentView == nil && host.superview == nil,
        "replacement callback cannot resurrect an invalidated host");
  Check(replacement.superview == nil && host.constraints.count == 0,
        "failed replacement leaves no attached page or stale edge pins");
  ParcNativeClose(window);
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
  ParcNativeClose(f.window);
}

@end

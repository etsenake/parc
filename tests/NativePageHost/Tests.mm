#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "page_host.h"
#import "pane_compositor_view.h"
#import "devtools_pane_view.h"

#include <cstdio>
#include <cstdlib>

//
static unsigned assertions = 0;
static unsigned groups = 0;

static void Check(BOOL condition, const char *message) {
  ++assertions;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

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

// Also compile this test against the old production header/implementation.
// The availability branch below reproduces its absent parent-visibility step;
// the regression fails on the real managed child's hidden state, not the API.
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
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  // Keep tests offscreen: first-responder and view hierarchy behavior do not
  // require bringing a test window in front of the user's application.
  return window;
}

static NSView *Page(RendererView **rendererOut) {
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
  __block BOOL drained = NO;
  dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  while (!drained && deadline.timeIntervalSinceNow > 0) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
  }
  Check(drained, "main queue drains through the real run loop");
}

static void TestContainmentAndReuse(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  NSRect originalFrame = page.frame;
  HostObserver *original = [HostObserver new];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:original];
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
  HostObserver *ignored = [HostObserver new];
  PCNativePageHost *reused = [PCNativePageHost hostWithContentView:page observer:ignored];
  Check(reused == host, "exact existing host is reused");
  Check(host.subviews.count == 1 && host.constraints.count == 4,
        "reuse adds no view or constraints");
  [window.contentView addSubview:host];
  Check(original.lastWindow == window && [original.moves.lastObject isEqual:@"attach"],
        "reuse retains original observer");
  Check(ignored.moves.count == 0, "reuse does not replace observer");
  host.frame = NSMakeRect(30, 40, 365, 219);
  [host layoutSubtreeIfNeeded];
  Check(NSEqualRects(page.frame, host.bounds), "resized page fills host bounds");
  Check(NSEqualSizes(renderer.frame.size, page.bounds.size), "renderer follows page size");
  [host removeFromSuperview];
  Check(original.lastWindow == nil && [original.moves.lastObject isEqual:@"detach"],
        "detachment reports nil actual window");
  Check(host.contentView == page, "window detachment preserves the live page");
  [host invalidate];
  [window close];
}

static void TestReplacementAndExternalRemoval(void) {
  ++groups;
  NSWindow *window = Window();
  NSView *old = Page(nullptr);
  NSView *unrelatedContainer = [[NSView alloc] initWithFrame:NSZeroRect];
  [unrelatedContainer addSubview:old];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:old observer:nil];
  Check(host != unrelatedContainer && unrelatedContainer.subviews.count == 0,
        "an ordinary parent is not mistaken for a reusable host");
  [window.contentView addSubview:host];
  NSArray<NSLayoutConstraint *> *oldConstraints = host.constraints;
  NSView *replacement = Page(nullptr);
  Check([host replaceContentView:replacement], "accept real replacement");
  Check(host.contentView == replacement && replacement.superview == host,
        "replacement retains supplied view identity");
  Check(old.superview == nil, "old page is detached");
  Check(host.constraints.count == 4, "replacement has only four new edge pins");
  for (NSLayoutConstraint *constraint in oldConstraints) {
    Check(!constraint.active, "old edge pins are removed");
  }
  [host layoutSubtreeIfNeeded];
  Check(NSEqualRects(replacement.frame, host.bounds), "replacement fills host");
  Check([host replaceContentView:replacement] && host.constraints.count == 4,
        "same-view replacement is idempotent");
  Check(![host replaceContentView:nil], "nil replacement does not remove page");
  Check(![host replaceContentView:host], "self replacement rejects hierarchy cycle");
  Check(![host replaceContentView:window.contentView], "ancestor replacement rejects cycle");
  Check(host.contentView == replacement, "rejected changes preserve page");
  [replacement removeFromSuperview];
  Check(host.contentView == nil && host.constraints.count == 0,
        "external removal clears owned reference and constraints");
  Check(![host replaceContentView:old], "replacement does not invent zero-child installation");
  [host invalidate];
  [window close];
}

static void TestDeferredFocusAndRendererReplacement(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  HostObserver *observer = [HostObserver new];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:observer];
  [window.contentView addSubview:host];
  SetSentinel(window);
  Check(host.acceptsFirstResponder, "acceptance is forwarded to renderer");
  Check([window makeFirstResponder:host], "AppKit accepts host focus request");
  Check(window.firstResponder == host && renderer.focusRequests == 0,
        "renderer focus is deferred, not falsely reported synchronous");
  DrainMainQueue();
  Check(window.firstResponder == renderer && renderer.focusRequests == 1,
        "queued request focuses real renderer in same window");
  Check(observer.focusAttempts == 1, "observer notified after queued request");

  // The queued request names the renderer and window it was made for; a
  // replacement renderer supersedes it (Peek focus routing, 90578fb5).
  SetSentinel(window);
  Check([window makeFirstResponder:host], "queue focus before renderer replacement");
  [renderer removeFromSuperview];
  RendererView *next = [[RendererView alloc] initWithFrame:page.bounds];
  [page addSubview:next];
  Check(window.firstResponder == host, "replacement does not focus eagerly");
  DrainMainQueue();
  Check(window.firstResponder == host && next.focusRequests == 0,
        "a replacement renderer supersedes the request queued for the old one");
  Check(renderer.focusRequests == 1, "old renderer is never focused again");
  SetSentinel(window);
  Check([window makeFirstResponder:host], "queue focus after the replacement");
  DrainMainQueue();
  Check(window.firstResponder == next && next.focusRequests == 1,
        "a request made after replacement focuses the new renderer");

  SetSentinel(window);
  next.acceptsFocus = NO;
  Check(!host.acceptsFirstResponder, "nonaccepting renderer is not hidden by host");
  Check([host becomeFirstResponder], "direct host request acknowledges queued attempt");
  DrainMainQueue();
  Check(window.firstResponder != next, "attempt callback does not turn rejected focus into success");
  Check(observer.focusAttempts == 4, "attempt callback does not imply native focus success");
  [host invalidate];
  [window close];
}

static void TestDeferredMoveAndDetach(void) {
  ++groups;
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
  // The request belongs to the window it was made in (90578fb5).
  Check(second.firstResponder == destinationSentinel && renderer.focusRequests == 0,
        "a move to another window supersedes the queued request");
  Check(first.firstResponder == firstSentinel, "old window responder stays unchanged");
  Check(observer.lastWindow == second, "attachment observer follows actual destination");

  RendererView *secondSentinel = SetSentinel(second);
  NSUInteger attempts = observer.focusAttempts;
  NSUInteger focusRequests = renderer.focusRequests;
  Check([host becomeFirstResponder], "queue focus before detachment");
  [host removeFromSuperview];
  DrainMainQueue();
  Check(host.window == nil && renderer.window == nil, "detached views have no native window");
  Check(second.firstResponder == secondSentinel && renderer.focusRequests == focusRequests,
        "detached request does not focus another window");
  Check(observer.focusAttempts == attempts + 1,
        "detached focus still reports processing, not success");
  [host invalidate];
  [first close];
  [second close];
}

static void TestInvalidationAndWeakLifetime(void) {
  ++groups;
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

static void TestReentrantReplacementTeardown(void) {
  ++groups;
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

static void TestHiddenQueuedFocus(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *content = Page(&renderer);
  NSView *container = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:container];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:content observer:nil];
  [container addSubview:host];
  Check([host becomeFirstResponder], "queue focus before native crash presentation");
  container.hidden = YES;
  DrainMainQueue();
  Check(renderer.focusRequests == 0, "queued focus cannot enter hidden renderer ancestry");
  Check(!host.acceptsFirstResponder && ![host becomeFirstResponder],
        "hidden page rejects new focus requests");
  container.hidden = NO;
  renderer.hidden = YES;
  Check(!host.acceptsFirstResponder && ![host becomeFirstResponder],
        "hidden renderer rejects focus even when outer host remains visible");
  renderer.hidden = NO;
  Check([window makeFirstResponder:host], "same retained host can focus after restoration");
  DrainMainQueue();
  Check(renderer.focusRequests == 1, "restored host focuses real renderer once");
  [host invalidate];
  [window close];
}

static void TestBackgroundContentVisibility(void) {
  ++groups;
  NSWindow *window = Window();
  NSView *parking = [[NSView alloc] initWithFrame:NSZeroRect];
  parking.hidden = YES;
  [window.contentView addSubview:parking];
  VisibilityView *page = [[VisibilityView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;  // Real WebContentsViewMac's initially_hidden contract.
  RendererView *renderer = [[RendererView alloc] initWithFrame:NSZeroRect];
  renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [page addSubview:renderer];
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [parking addSubview:host];
  Check(page.hidden && host.contentView == page,
        "background adoption preserves the same initially hidden native child");
  BOOL hasVisibility = [host respondsToSelector:@selector(setContentVisible:inWindow:)];
  if (hasVisibility) {
    Check([host setContentVisible:NO inWindow:window], "background visibility remains hidden");
    Check(![host setContentVisible:YES inWindow:window],
          "a hidden ancestor cannot make the native content visible");
  }
  [window.contentView addSubview:host];
  host.frame = NSMakeRect(0, 0, 640, 360);
  // The old host has no parent visibility operation: reparenting, resizing
  // and showing the renderer child leave this native parent hidden.
  renderer.hidden = NO;
  if (hasVisibility) {
    Check([host setContentVisible:YES inWindow:window], "visible shell shows exact native content");
  }
  Check(!page.hidden && !renderer.hiddenOrHasHiddenAncestor,
        "selected initially-hidden native content and its renderer are actually unhidden");
  Check(host.contentView == page && page.superview == host && renderer.superview == page,
        "showing preserves the original native child and renderer identity");
  Check(NSEqualSizes(page.frame.size, NSMakeSize(640, 360)) &&
            NSEqualSizes(renderer.frame.size, NSMakeSize(640, 360)),
        "zero-sized parked page reaches actual selected host dimensions");
  NSUInteger changes = page.hiddenChanges;
  Check([host setContentVisible:YES inWindow:window] && page.hiddenChanges == changes,
        "repeated visibility does not emit another native hide callback");
  Check([host setContentVisible:NO inWindow:window] && page.hidden,
        "returning to background hides the same managed parent");
  NSWindow *unrelated = Window();
  Check(![host setContentVisible:YES inWindow:unrelated] && page.hidden,
        "another supplied window cannot expose the page");
  [unrelated close];
  [host removeFromSuperview];
  Check(![host setContentVisible:YES inWindow:window] && page.hidden,
        "detached content is not exposed by stale presentation");
  [host invalidate];
  [window close];
}

static void TestFreshContentSizeBeforeShow(void) {
  ++groups;
  // A new foreground page's native container starts visible, but unsized.
  // A new background page starts hidden. Neither has run an AppKit layout
  // pass when the native tab attachment sizes the outer host and shows it.
  const BOOL initialVisibility[] = {NO, YES};
  for (BOOL initiallyHidden : initialVisibility) {
    NSWindow *window = Window();
    NSView *wrapper = [[NSView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:wrapper];
    [window.contentView layoutSubtreeIfNeeded];
    LayoutView *page = [[LayoutView alloc] initWithFrame:NSZeroRect];
    page.hidden = initiallyHidden;
    RendererView *renderer = [[RendererView alloc] initWithFrame:NSZeroRect];
    renderer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [page addSubview:renderer];
    PCNativePaneCompositorView *display = [[PCNativePaneCompositorView alloc]
        initWithHostedLayer:[CALayer layer]];
    [page addSubview:display];
    PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
    // Native attachment adds a pane after the shell has already sized its
    // wrapper. Layout of the pane sets the host's frame, not its constraints.
    PCNativeDevToolsPaneView *pane = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:host];
    pane.frame = wrapper.bounds;
    [wrapper addSubview:pane];
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    Check(!window.visible && !window.isKeyWindow,
          "fresh-page check needs no window activation or display");
    Check(NSIsEmptyRect(page.bounds) && NSIsEmptyRect(renderer.bounds),
          "new native page and renderer have no size before presentation");
    Check([host setContentVisible:YES inWindow:window], "fresh page can be shown");
    Check(NSEqualSizes(page.bounds.size, host.bounds.size) &&
              NSEqualSizes(renderer.bounds.size, host.bounds.size),
          "showing a brand-new page sizes its renderer without another window event");
    Check(NSEqualSizes(display.bounds.size, host.bounds.size),
          "the compositor display receives the same nonempty size");
    Check(!page.hidden, "fresh page is visible after its geometry is ready");
    const NSUInteger layouts = page.subtreeLayouts;
    for (int i = 0; i < 5; ++i) {
      Check([host setContentVisible:YES inWindow:window], "settled show remains valid");
    }
    Check(page.subtreeLayouts == layouts,
          "settled visibility does not walk the renderer subtree again");

    // A later pane resize or infobar changes the constraints; drawing must
    // use their actual result, not overwrite them with the outer host size.
    host.frame = NSMakeRect(0, 0, 640, 360);
    NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
    [host setInfobarView:shelf preferredHeight:30];
    Check([host setContentVisible:YES inWindow:window], "resized page can be shown");
    Check(NSEqualSizes(page.bounds.size, NSMakeSize(640, 330)) &&
              NSEqualSizes(renderer.bounds.size, page.bounds.size),
          "showing settles the page below its infobar at the new size");
    [host setInfobarView:shelf preferredHeight:60];
    Check([host setContentVisible:YES inWindow:window] &&
              NSEqualSizes(page.bounds.size, NSMakeSize(640, 300)),
          "changing an existing infobar settles its new inset before show");
    [host setInfobarView:nil preferredHeight:0];
    Check([host setContentVisible:YES inWindow:window] &&
              NSEqualSizes(page.bounds.size, NSMakeSize(640, 360)),
          "removing an infobar gives the page its full size before show");

    NSView *replacement = [[NSView alloc] initWithFrame:NSZeroRect];
    Check([host replaceContentView:replacement], "fresh native content can replace the old view");
    Check([host setContentVisible:YES inWindow:window] &&
              NSEqualSizes(replacement.bounds.size, NSMakeSize(640, 360)),
          "same-size host settles a newly replaced content view");
    [pane invalidate];
    [host invalidate];
    [window close];
  }
}

static void TestParkedSplitAndTransferredGeometry(void) {
  ++groups;
  NSWindow *first = Window();
  NSWindow *second = Window();
  [second setContentSize:NSMakeSize(720, 480)];
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
  Check(![host setContentVisible:YES inWindow:first] && page.hidden,
        "a new parked page stays hidden until a visible pane owns it");
  [left addSubview:pane];
  pane.frame = left.bounds;
  [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
  Check([host setContentVisible:YES inWindow:first] &&
            NSEqualSizes(page.bounds.size, left.bounds.size) &&
            NSEqualSizes(renderer.bounds.size, left.bounds.size),
        "selecting a parked page sizes it to its split pane without a window event");

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

  Check([host setContentVisible:NO inWindow:second], "hide before native content reattachment");
  [page removeFromSuperview];
  page.frame = NSZeroRect;
  Check([host restoreContentView:page], "reattach the native content to its existing host");
  Check([host setContentVisible:YES inWindow:second] &&
            NSEqualSizes(renderer.bounds.size, second.contentView.bounds.size),
        "reattachment into an unchanged host settles the new edge constraints");
  Check(!first.visible && !second.visible && !first.isKeyWindow && !second.isKeyWindow,
        "split selection and window transfer require no displayed or key test window");
  [moved invalidate];
  [host invalidate];
  [otherPane invalidate];
  [otherHost invalidate];
  [first close];
  [second close];
}

static void TestLayoutReentrantOwnership(void) {
  ++groups;
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

  // Layout may also deliver a newer visibility decision for the same owner.
  // Retaining the right host/window alone cannot authorize the old show.
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
  [currentHost setContentVisible:NO inWindow:first];
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
  [second close];
}

static void TestVisibilityReentrantOwnership(void) {
  ++groups;
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
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    Check([weakHost setContentVisible:NO inWindow:second],
          "newer visibility decision can hide the same attached child");
  };
  Check(![host setContentVisible:YES inWindow:second] && page.hidden,
        "old show cannot acknowledge a superseding hidden decision");
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
  Check(![host setContentVisible:YES inWindow:second], "invalidated host rejects visibility");
  [first close];
  [second close];
}

@interface PCNativePageHost (RendererResponder)
- (NSView *)rendererResponder;
@end

static void TestConcealedPictureKeepsItsConnection(void) {
  ++groups;
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

// pane_compositor.mm places the compositor's view inside the WebContents view,
// above the renderer (or at the bottom before a renderer exists).
static void TestPaneCompositorViewIsNeverTheRenderer(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [window.contentView addSubview:host];
  __block NSUInteger geometryChanges = 0;
  __block NSUInteger screenChanges = 0;
  __block BOOL lastOnScreen = NO;
  PCNativePaneCompositorView *overlay =
      [[PCNativePaneCompositorView alloc] initWithHostedLayer:[CALayer layer]];
  __weak PCNativePaneCompositorView *weakOverlay = overlay;
  overlay.geometryHandler = ^{ ++geometryChanges; };
  overlay.screenHandler = ^{
    ++screenChanges;
    lastOnScreen = weakOverlay.onScreen;
  };
  Check(!overlay.onScreen, "an unplaced compositor view is off screen");
  [page addSubview:overlay positioned:NSWindowBelow relativeTo:nil];
  // Joining a window can also report a backing change; count only deltas.
  Check(geometryChanges >= 1, "joining a window reports geometry");
  NSUInteger changes = geometryChanges;
  overlay.frame = page.bounds;
  Check(geometryChanges == changes + 1, "a size change reports geometry");
  changes = geometryChanges;
  overlay.frame = page.bounds;
  Check(geometryChanges == changes, "an unchanged size reports nothing");
  Check(overlay.onScreen, "in a window with no hidden ancestor is on screen");
  Check(page.subviews.firstObject == overlay && host.acceptsFirstResponder,
        "a compositor view below the renderer does not stand in for it");
  SetSentinel(window);
  Check([window makeFirstResponder:host], "host focus request with compositor view");
  DrainMainQueue();
  Check(window.firstResponder == renderer, "queued focus reaches the renderer, not the compositor view");
  [page addSubview:overlay positioned:NSWindowAbove relativeTo:renderer];
  Check(page.subviews.lastObject == overlay && host.acceptsFirstResponder,
        "a compositor view above the renderer leaves it the responder");
  Check(!overlay.acceptsFirstResponder && !overlay.isAccessibilityElement &&
            overlay.accessibilityChildren.count == 0,
        "compositor view takes no focus or accessibility");
  const NSPoint inside = [page convertPoint:NSMakePoint(20, 20) toView:page.superview];
  Check([page hitTest:inside] == renderer, "events pass through the compositor view to the renderer");
  NSUInteger screens = screenChanges;
  page.hidden = YES;
  Check(!overlay.onScreen, "a hidden WebContents view takes its compositor view off screen");
  Check(screenChanges > screens && !lastOnScreen,
        "hiding the WebContents view reports leaving the screen at once");
  screens = screenChanges;
  page.hidden = NO;
  Check(screenChanges > screens && lastOnScreen, "unhiding it reports rejoining the screen");
  screens = screenChanges;
  host.hidden = YES;
  Check(!overlay.onScreen, "a hidden ancestor takes it off screen");
  Check(screenChanges > screens && !lastOnScreen, "a hidden ancestor reports leaving the screen");
  screens = screenChanges;
  host.hidden = NO;
  Check(overlay.onScreen, "unhiding brings it back on screen");
  Check(screenChanges > screens && lastOnScreen, "an unhidden ancestor reports rejoining");
  // Parc parks a departing tab's pane in a hidden container in the same window.
  NSView *parked = [[NSView alloc] initWithFrame:window.contentView.bounds];
  parked.hidden = YES;
  [window.contentView addSubview:parked];
  screens = screenChanges;
  [parked addSubview:host];
  Check(screenChanges > screens && !lastOnScreen && !overlay.onScreen,
        "parking the page reports leaving the screen at once");
  screens = screenChanges;
  [window.contentView addSubview:host];
  Check(screenChanges > screens && lastOnScreen && overlay.onScreen,
        "unparking it reports rejoining the screen");
  const NSUInteger before = geometryChanges;
  screens = screenChanges;
  [overlay removeFromSuperview];
  Check(!overlay.onScreen && geometryChanges > before, "leaving the window reports geometry");
  Check(screenChanges > screens && !lastOnScreen, "leaving the window reports leaving the screen");
  screens = screenChanges;
  [page addSubview:overlay positioned:NSWindowAbove relativeTo:renderer];
  Check(screenChanges > screens && lastOnScreen, "joining a shown page reports the screen");
  [overlay removeFromSuperview];
  overlay.geometryHandler = nil;
  overlay.screenHandler = nil;
  renderer.acceptsFocus = NO;
  [page addSubview:overlay positioned:NSWindowAbove relativeTo:renderer];
  Check(!host.acceptsFirstResponder, "a nonaccepting renderer is still the one consulted");
  [renderer removeFromSuperview];
  Check(!host.acceptsFirstResponder, "a page with only the compositor view has no renderer");
  [host invalidate];
  [window close];
}

// Chromium's ViewsHostableDetach hides and removes the hosted WebContents view.
static void TestRestoreContentAfterNativeDetach(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [window.contentView addSubview:host];
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [host setInfobarView:shelf preferredHeight:30];
  [host layoutSubtreeIfNeeded];
  const NSRect pinned = page.frame;
  Check(![host restoreContentView:page], "managed content cannot be restored over itself");
  page.hidden = YES;
  [page removeFromSuperview];
  Check(host.contentView == nil, "native removal clears the managed content");
  NSView *stranger = [[NSView alloc] initWithFrame:NSZeroRect];
  [window.contentView addSubview:stranger];
  Check(![host restoreContentView:stranger], "a view with another superview is refused");
  Check(![host restoreContentView:host], "the host itself is refused");
  Check([host restoreContentView:page], "the removed WebContents view is reinstalled");
  Check(host.contentView == page && page.superview == host &&
            host.subviews.firstObject == page && host.subviews.lastObject == shelf,
        "reinstalled content is below the infobar shelf");
  [host layoutSubtreeIfNeeded];
  Check(NSEqualRects(page.frame, pinned), "reinstalled content is pinned below the shelf again");
  Check(page.hidden, "restoring visibility is the caller's");
  Check(host.rendererResponder == renderer, "the renderer is the responder again");
  NSView *other = Page(nullptr);
  Check(![host restoreContentView:other], "nothing is restored while content is managed");
  [page removeFromSuperview];
  [host invalidate];
  Check(![host restoreContentView:page] && page.superview == nil, "an invalidated host refuses");
  [window close];
}

// Chromium's history swipe overlay goes in a container above the page and
// the pane compositor's display view, which never takes input.
static void TestHistoryOverlayContainer(void) {
  ++groups;
  NSWindow *window = Window();
  RendererView *renderer = nil;
  NSView *page = Page(&renderer);
  PCNativePageHost *host = [PCNativePageHost hostWithContentView:page observer:nil];
  [window.contentView addSubview:host];
  NSView *container = host.historyOverlayContainer;
  Check(container && container.superview == host && host.subviews.lastObject == container,
        "the history overlay container is the host's top subview");
  Check(NSEqualRects(container.frame, host.bounds) && container.clipsToBounds,
        "the container covers and clips to the host");
  Check(!container.acceptsFirstResponder &&
            [container hitTest:NSMakePoint(10, 10)] == nil,
        "the container never takes focus or clicks");
  Check(host.rendererResponder == renderer, "the renderer stays the responder");
  NSView *shelf = [[NSView alloc] initWithFrame:NSZeroRect];
  [host setInfobarView:shelf preferredHeight:30];
  Check(host.historyOverlayContainer == container && host.subviews.lastObject == container,
        "the same container returns above a later infobar shelf");
  [host setFrameSize:NSMakeSize(500, 300)];
  Check(NSEqualRects(container.frame, host.bounds), "the container follows the host's size");
  [host invalidate];
  Check(host.historyOverlayContainer == nil && container.superview == nil,
        "invalidation removes the container");
  [window close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    @try {
      TestContainmentAndReuse();
      TestReplacementAndExternalRemoval();
      TestDeferredFocusAndRendererReplacement();
      TestDeferredMoveAndDetach();
      TestInvalidationAndWeakLifetime();
      TestReentrantReplacementTeardown();
      TestHiddenQueuedFocus();
      TestFreshContentSizeBeforeShow();
      TestBackgroundContentVisibility();
      TestParkedSplitAndTransferredGeometry();
      TestLayoutReentrantOwnership();
      TestVisibilityReentrantOwnership();
      TestConcealedPictureKeepsItsConnection();
      TestPaneCompositorViewIsNeverTheRenderer();
      TestRestoreContentAfterNativeDetach();
      TestHistoryOverlayContainer();
    } @catch (NSException *exception) {
      std::fprintf(stderr, "FAIL: unexpected AppKit exception: %s\n", exception.description.UTF8String);
      return 1;
    }
    std::printf("PASS: %u assertions across %u native page-host groups (real AppKit views, windows and run loop)\n",
                assertions, groups);
  }
  return 0;
}

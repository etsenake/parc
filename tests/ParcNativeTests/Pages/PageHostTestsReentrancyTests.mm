#import "PageHostTestsSupport.h"

using namespace PageHostTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PageHostTestsReentrancyTests")))
@interface PageHostTestsReentrancyTests : ParcNativeTestCase
@end

@implementation PageHostTestsReentrancyTests

- (void)testLayoutCanMoveThePageToAnotherWindow {
  NSWindow *first = Window();
  NSWindow *second = Window();
  PageHostTestsLayoutView *page = [[PageHostTestsLayoutView alloc] initWithFrame:NSZeroRect];
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  host.frame = first.contentView.bounds;
  [first.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak PageHostTestsLayoutView *weakPage = page;
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
  ParcNativeClose(first);
  ParcNativeClose(second);
}

- (void)testANewerHideDuringLayoutSupersedesTheShow {
  NSWindow *first = Window();
  PageHostTestsLayoutView *current = [[PageHostTestsLayoutView alloc] initWithFrame:NSZeroRect];
  current.hidden = YES;
  PCNativePageHost *currentHost = Offscreen([PCNativePageHost hostWithContentView:current observer:nil]);
  currentHost.frame = first.contentView.bounds;
  [first.contentView addSubview:currentHost];
  __weak PCNativePageHost *weakCurrentHost = currentHost;
  __weak PageHostTestsLayoutView *weakCurrent = current;
  current.needsLayout = YES;
  current.didLayout = ^{
    weakCurrent.didLayout = nil;
    Check([weakCurrentHost setContentVisible:NO inWindow:first],
          "layout can deliver a newer hide for the same owner");
  };
  Check(![currentHost setContentVisible:YES inWindow:first] && current.hidden,
        "the older show cannot reverse a hide delivered by layout");
  Check([currentHost setContentVisible:YES inWindow:first], "a later show succeeds");
  ParcNativeClose(first);
}

- (void)testInvalidationDuringLayoutKeepsThePageHidden {
  NSWindow *first = Window();
  PageHostTestsLayoutView *current = [[PageHostTestsLayoutView alloc] initWithFrame:NSZeroRect];
  current.hidden = YES;
  PCNativePageHost *currentHost = Offscreen([PCNativePageHost hostWithContentView:current observer:nil]);
  currentHost.frame = first.contentView.bounds;
  [first.contentView addSubview:currentHost];
  __weak PCNativePageHost *weakCurrentHost = currentHost;
  __weak PageHostTestsLayoutView *weakCurrent = current;
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
  ParcNativeClose(first);
}

- (void)testVisibilityCallbacksCanTransferWindowOwnership {
  NSWindow *first = Window();
  NSWindow *second = Window();
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [first.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak PageHostTestsVisibilityView *weakPage = page;
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
  ParcNativeClose(first);
  ParcNativeClose(second);
}

- (void)testVisibilityCallbacksCanChangeContainers {
  NSWindow *second = Window();
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak PageHostTestsVisibilityView *weakPage = page;
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
  ParcNativeClose(second);
}

- (void)testVisibilityCallbacksCanSupersedeAShow {
  NSWindow *second = Window();
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak PageHostTestsVisibilityView *weakPage = page;
  page.visibilityChanged = ^{
    weakPage.visibilityChanged = nil;
    Check([weakHost setContentVisible:NO inWindow:second],
          "newer visibility decision can hide the same attached child");
  };
  Check(![host setContentVisible:YES inWindow:second] && page.hidden,
        "old show cannot acknowledge a superseding hidden decision");
  [host invalidate];
  ParcNativeClose(second);
}

- (void)testVisibilityCallbacksCanReplaceThePage {
  NSWindow *second = Window();
  PageHostTestsVisibilityView *page = [[PageHostTestsVisibilityView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  page.hidden = YES;
  PCNativePageHost *host = Offscreen([PCNativePageHost hostWithContentView:page observer:nil]);
  [second.contentView addSubview:host];
  __weak PCNativePageHost *weakHost = host;
  __weak PageHostTestsVisibilityView *weakPage = page;
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
  ParcNativeClose(second);
}

@end

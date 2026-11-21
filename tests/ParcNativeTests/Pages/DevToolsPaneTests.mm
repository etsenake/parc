#import <AppKit/AppKit.h>
#import "ParcNativeTest.h"

#include <cstdio>
#include <cstdlib>

#import "devtools_pane_view.h"
#define EXPECT(condition) PARC_CHECK(condition)
@interface KeyWindow : NSWindow
@property(nonatomic) BOOL key;
@end
@implementation KeyWindow
@synthesize key = _key;
- (BOOL)isKeyWindow {
  return _key;
}
@end
@interface DevToolsFocusView : NSView
@end
@implementation DevToolsFocusView
- (BOOL)acceptsFirstResponder {
  return YES;
}
@end
@interface DevToolsReentrantView : NSView
@property(nonatomic, copy) void (^moved)(void);
@property(nonatomic, copy) void (^framed)(void);
@end
@implementation DevToolsReentrantView
@synthesize moved = _moved;
@synthesize framed = _framed;
- (void)setFrame:(NSRect)frame {
  [super setFrame:frame];
  if (_framed) {
    _framed();
  }
}
- (void)viewDidMoveToSuperview {
  [super viewDidMoveToSuperview];
  if (_moved) {
    _moved();
  }
}
@end
@interface DevToolsPaneTests : ParcNativeTestCase
@end

@implementation DevToolsPaneTests {
  KeyWindow* _parent;
  DevToolsFocusView* _inspected;
  DevToolsFocusView* _tools;
  PCNativeDevToolsPaneView* _pane;
  NSView* _next;
}

- (void)setUp {
  [super setUp];
  _parent = [[KeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                         styleMask:NSWindowStyleMaskBorderless
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
  _parent.releasedWhenClosed = NO;
  _parent.key = YES;
  _inspected = [[DevToolsFocusView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
  _pane = [[PCNativeDevToolsPaneView alloc] initWithInspectedView:_inspected];
  [_parent.contentView addSubview:_pane];
  _tools = [[DevToolsFocusView alloc] initWithFrame:NSZeroRect];
  _next = [[NSView alloc] initWithFrame:NSZeroRect];
}

- (void)tearDown {
  [_pane invalidate];
  [_parent close];
  [super tearDown];
}

- (void)split {
  EXPECT([_pane setHostedToolsView:_tools]);
  [_pane applyInspectedRect:NSMakeRect(0, 0, 600, 700) toolsRect:NSMakeRect(600, 0, 300, 700) hideInspected:NO];
}

- (void)testThePaneHostsTheInspectedPage {
  EXPECT(_pane.inspectedView == _inspected);
  EXPECT(_inspected.superview == _pane && _inspected.window == _parent);
  EXPECT(_pane.toolsView == nil && !_pane.hidden);
}

- (void)testHostedToolsJoinThePanesWindow {
  EXPECT([_pane setHostedToolsView:_tools]);
  EXPECT(_tools.superview == _pane && _tools.window == _parent);
}

- (void)testASplitLaysOutThePageItsOverlayAndTheTools {
  [self split];
  EXPECT(NSEqualRects(_inspected.frame, NSMakeRect(0, 0, 600, 700)));
  EXPECT(NSEqualRects(_pane.inspectedOverlay.frame, _inspected.frame));
  EXPECT(NSEqualRects(_tools.frame, NSMakeRect(600, 0, 300, 700)));
  EXPECT(!_inspected.hidden && !_pane.inspectedOverlay.hidden);
}

- (void)testClicksReachTheToolsUnlessBlocked {
  [self split];
  EXPECT([_pane hitTest:NSMakePoint(700, 10)] == _tools);
  EXPECT([_pane hitTest:NSMakePoint(100, 10)] == _inspected);
  [_pane setToolsBlocked:YES];
  EXPECT([_pane hitTest:NSMakePoint(700, 10)] != _tools);
  [_pane setToolsBlocked:NO];
  EXPECT([_pane hitTest:NSMakePoint(700, 10)] == _tools);
}

- (void)testFocusMovesToTheToolsOnRequest {
  [self split];
  EXPECT([_pane focusTools]);
  EXPECT(_parent.firstResponder == _tools);
  NSView* inspected_focus = _inspected;
  EXPECT([_parent makeFirstResponder:inspected_focus]);
  EXPECT(_parent.firstResponder == inspected_focus);
  EXPECT([_pane focusTools]);
  EXPECT(_parent.firstResponder == _tools);
}

- (void)testHidingThePageHidesItsOverlay {
  [self split];
  [_pane applyInspectedRect:NSZeroRect toolsRect:_pane.bounds hideInspected:YES];
  EXPECT(_inspected.hidden && _pane.inspectedOverlay.hidden);
}

- (void)testRemovingTheToolsRestoresTheWholePage {
  [self split];
  [_pane applyInspectedRect:NSZeroRect toolsRect:_pane.bounds hideInspected:YES];
  EXPECT([_pane setHostedToolsView:nil]);
  [_pane applyInspectedRect:_pane.bounds toolsRect:NSZeroRect hideInspected:NO];
  EXPECT(!_tools.superview && !_inspected.hidden);
  EXPECT(NSEqualRects(_inspected.frame, _pane.bounds));
}

- (void)testLayoutReportsThePaneBounds {
  __block int layouts = 0;
  _pane.layoutHandler = ^(NSRect bounds) {
    ++layouts;
    EXPECT(bounds.size.width == 900);
  };
  [_pane layout];
  EXPECT(layouts == 1);
}

- (void)testThePageThePaneOrItsWindowCannotBecomeTheTools {
  EXPECT(![_pane setHostedToolsView:_inspected]);
  EXPECT(![_pane setHostedToolsView:_pane]);
  EXPECT(![_pane setHostedToolsView:_parent.contentView]);
}

- (void)testInvalidationLeavesMovedViewsAndEndsThePane {
  __block int layouts = 0;
  _pane.layoutHandler = ^(NSRect) {
    ++layouts;
  };
  [_pane layout];
  EXPECT([_pane setHostedToolsView:_tools]);
  [_next addSubview:_tools];
  [_next addSubview:_inspected];
  [_pane invalidate];
  [_pane invalidate];
  EXPECT(_tools.superview == _next && _inspected.superview == _next);
  EXPECT(_pane.superview == nil && _pane.toolsView == nil);
  [_pane layout];
  EXPECT(layouts == 1);
  EXPECT(![_pane setHostedToolsView:_tools]);
}

- (void)testToolsThatInvalidateThePaneWhileMovingAreRefused {
  DevToolsReentrantView* reentrant = [[DevToolsReentrantView alloc] initWithFrame:NSZeroRect];
  PCNativeDevToolsPaneView* second =
      [[PCNativeDevToolsPaneView alloc] initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
  __weak PCNativeDevToolsPaneView* weak = second;
  __weak DevToolsReentrantView* weak_reentrant = reentrant;
  reentrant.moved = ^{
    if (weak_reentrant.superview) [weak invalidate];
  };
  EXPECT(![second setHostedToolsView:reentrant]);
  EXPECT(second.toolsView == nil && !reentrant.superview);
  reentrant.moved = nil;
}

- (void)testAReplacementHostedDuringASwapWins {
  DevToolsReentrantView* old = [[DevToolsReentrantView alloc] initWithFrame:NSZeroRect];
  NSView* replacement = [[NSView alloc] initWithFrame:NSZeroRect];
  PCNativeDevToolsPaneView* third =
      [[PCNativeDevToolsPaneView alloc] initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
  EXPECT([third setHostedToolsView:old]);
  __weak PCNativeDevToolsPaneView* weak_third = third;
  __weak DevToolsReentrantView* weak_old = old;
  old.moved = ^{
    if (!weak_old.superview) [weak_third setHostedToolsView:replacement];
  };
  EXPECT(![third setHostedToolsView:_tools]);
  EXPECT(third.toolsView == replacement && replacement.superview == third);
  old.moved = nil;
  [third invalidate];
}

- (void)testToolsMovedAwayDuringInvalidationStayWhereTheyWent {
  DevToolsReentrantView* migrating = [[DevToolsReentrantView alloc] initWithFrame:NSZeroRect];
  PCNativeDevToolsPaneView* fourth =
      [[PCNativeDevToolsPaneView alloc] initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
  EXPECT([fourth setHostedToolsView:migrating]);
  __weak DevToolsReentrantView* weak_migrating = migrating;
  NSView* next = _next;
  migrating.moved = ^{
    if (!weak_migrating.superview) [next addSubview:weak_migrating];
  };
  [fourth invalidate];
  EXPECT(migrating.superview == _next);
  EXPECT(fourth.toolsView == nil);
  migrating.moved = nil;
}

- (void)testViewsMovedAwayDuringASplitAreLeftAlone {
  DevToolsReentrantView* moving_page = [[DevToolsReentrantView alloc] initWithFrame:NSZeroRect];
  NSView* moving_tools = [[NSView alloc] initWithFrame:NSMakeRect(1, 2, 3, 4)];
  PCNativeDevToolsPaneView* fifth = [[PCNativeDevToolsPaneView alloc] initWithInspectedView:moving_page];
  EXPECT([fifth setHostedToolsView:moving_tools]);
  __weak DevToolsReentrantView* weak_page = moving_page;
  NSView* next = _next;
  moving_page.framed = ^{
    [next addSubview:moving_tools];
    [next addSubview:weak_page];
  };
  [fifth applyInspectedRect:NSMakeRect(0, 0, 50, 50) toolsRect:NSMakeRect(50, 0, 50, 50) hideInspected:YES];
  EXPECT(moving_tools.superview == _next && moving_page.superview == _next);
  EXPECT(!moving_page.hidden);
  EXPECT(NSEqualRects(moving_tools.frame, NSMakeRect(1, 2, 3, 4)));
  EXPECT(![fifth setHostedToolsView:moving_tools]);
  moving_page.framed = nil;
  [fifth invalidate];
}

- (PCNativeDevToolsPaneView*)stablePaneWithPage:(DevToolsReentrantView*)counted tools:(DevToolsFocusView*)tools {
  PCNativeDevToolsPaneView* stable = [[PCNativeDevToolsPaneView alloc] initWithInspectedView:counted];
  [_parent.contentView addSubview:stable];
  EXPECT([stable setHostedToolsView:tools]);
  [stable applyInspectedRect:NSMakeRect(0, 0, 600, 700) toolsRect:NSMakeRect(600, 0, 300, 700) hideInspected:NO];
  return stable;
}

- (void)testUnchangedGeometryWritesNoFrames {
  DevToolsReentrantView* counted = [[DevToolsReentrantView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
  PCNativeDevToolsPaneView* stable = [self stablePaneWithPage:counted tools:_tools];
  __block int writes = 0;
  counted.framed = ^{
    ++writes;
  };
  [stable applyInspectedRect:NSMakeRect(0, 0, 600, 700) toolsRect:NSMakeRect(600, 0, 300, 700) hideInspected:NO];
  EXPECT(writes == 0);
  EXPECT(NSEqualRects(counted.frame, NSMakeRect(0, 0, 600, 700)));
  [stable applyInspectedRect:NSMakeRect(0, 0, 500, 700) toolsRect:NSMakeRect(500, 0, 400, 700) hideInspected:NO];
  EXPECT(writes == 1);
  EXPECT(NSEqualRects(counted.frame, NSMakeRect(0, 0, 500, 700)));
  counted.framed = nil;
  [stable invalidate];
}

- (void)testALayoutHandlerReapplyingTheSameGeometryWritesNothing {
  DevToolsReentrantView* counted = [[DevToolsReentrantView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
  PCNativeDevToolsPaneView* stable = [self stablePaneWithPage:counted tools:_tools];
  __block int writes = 0, handlers = 0;
  counted.framed = ^{
    ++writes;
  };
  __weak PCNativeDevToolsPaneView* weak_stable = stable;
  __weak DevToolsFocusView* weak_tools = _tools;
  __weak DevToolsReentrantView* weak_counted = counted;
  stable.layoutHandler = ^(NSRect) {
    ++handlers;
    PCNativeDevToolsPaneView* pane = weak_stable;
    DevToolsFocusView* tools = weak_tools;
    if (!pane || !tools) return;
    [pane applyInspectedRect:weak_counted.frame toolsRect:tools.frame hideInspected:NO];
  };
  [stable layout];
  EXPECT(handlers == 1);
  EXPECT(writes == 0);
  [stable layout];
  EXPECT(handlers == 2);
  EXPECT(writes == 0);
  counted.framed = ^{
    ++writes;
    [weak_stable layout];
  };
  [stable applyInspectedRect:NSMakeRect(0, 0, 400, 700) toolsRect:NSMakeRect(400, 0, 500, 700) hideInspected:NO];
  EXPECT(writes == 1);
  EXPECT(handlers == 2);
  counted.framed = nil;
  [stable invalidate];
}

@end

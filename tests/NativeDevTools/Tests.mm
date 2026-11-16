#import <AppKit/AppKit.h>
#include "../Support/TestFailure.h"

#include <cstdio>
#include <cstdlib>

#import "devtools_pane_view.h"
static int assertions;
#define EXPECT(x)                                          \
  do {                                                     \
    ++assertions;                                          \
    if (!(x)) {                                            \
      std::fprintf(stderr, "line %d: %s\n", __LINE__, #x); \
      std::exit(1);                                        \
    }                                                      \
  } while (0)
@interface KeyWindow : NSWindow
@property(nonatomic) BOOL key;
@end
@implementation KeyWindow
@synthesize key = _key;
- (BOOL)isKeyWindow {
  return _key;
}
@end
@interface FocusView : NSView
@end
@implementation FocusView
- (BOOL)acceptsFirstResponder {
  return YES;
}
@end
@interface ReentrantView : NSView
@property(nonatomic, copy) void (^moved)(void);
@property(nonatomic, copy) void (^framed)(void);
@end
@implementation ReentrantView
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
int main() {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    [NSApplication sharedApplication];
    KeyWindow* parent =
        [[KeyWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
                                     styleMask:NSWindowStyleMaskTitled
                                       backing:NSBackingStoreBuffered
                                         defer:NO];
    parent.releasedWhenClosed = NO;
    parent.key = YES;
    FocusView* inspected =
        [[FocusView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    PCNativeDevToolsPaneView* pane =
        [[PCNativeDevToolsPaneView alloc] initWithInspectedView:inspected];
    [parent.contentView addSubview:pane];
    EXPECT(pane.inspectedView == inspected);
    EXPECT(inspected.superview == pane && inspected.window == parent);
    EXPECT(pane.toolsView == nil && !pane.hidden);
    FocusView* tools = [[FocusView alloc] initWithFrame:NSZeroRect];
    EXPECT([pane setHostedToolsView:tools]);
    EXPECT(tools.superview == pane && tools.window == parent);
    [pane applyInspectedRect:NSMakeRect(0, 0, 600, 700)
                   toolsRect:NSMakeRect(600, 0, 300, 700)
               hideInspected:NO];
    EXPECT(NSEqualRects(inspected.frame, NSMakeRect(0, 0, 600, 700)));
    EXPECT(NSEqualRects(pane.inspectedOverlay.frame, inspected.frame));
    EXPECT(NSEqualRects(tools.frame, NSMakeRect(600, 0, 300, 700)));
    EXPECT(!inspected.hidden && !pane.inspectedOverlay.hidden);
    EXPECT([pane hitTest:NSMakePoint(700, 10)] == tools);
    EXPECT([pane hitTest:NSMakePoint(100, 10)] == inspected);
    [pane setToolsBlocked:YES];
    EXPECT([pane hitTest:NSMakePoint(700, 10)] != tools);
    [pane setToolsBlocked:NO];
    EXPECT([pane hitTest:NSMakePoint(700, 10)] == tools);
    EXPECT([pane focusTools]);
    EXPECT(parent.firstResponder == tools);
    NSView* inspected_focus = inspected;
    EXPECT([parent makeFirstResponder:inspected_focus]);
    EXPECT(parent.firstResponder == inspected_focus);
    EXPECT([pane focusTools]);
    EXPECT(parent.firstResponder == tools);
    [pane applyInspectedRect:NSZeroRect
                   toolsRect:pane.bounds
               hideInspected:YES];
    EXPECT(inspected.hidden && pane.inspectedOverlay.hidden);
    EXPECT([pane setHostedToolsView:nil]);
    [pane applyInspectedRect:pane.bounds toolsRect:NSZeroRect hideInspected:NO];
    EXPECT(!tools.superview && !inspected.hidden);
    EXPECT(NSEqualRects(inspected.frame, pane.bounds));
    __block int layouts = 0;
    pane.layoutHandler = ^(NSRect bounds) {
      ++layouts;
      EXPECT(bounds.size.width == 900);
    };
    [pane layout];
    EXPECT(layouts == 1);
    EXPECT(![pane setHostedToolsView:inspected]);
    EXPECT(![pane setHostedToolsView:pane]);
    EXPECT(![pane setHostedToolsView:parent.contentView]);
    EXPECT([pane setHostedToolsView:tools]);
    NSView* next = [[NSView alloc] initWithFrame:NSZeroRect];
    [next addSubview:tools];
    [next addSubview:inspected];
    [pane invalidate];
    [pane invalidate];
    EXPECT(tools.superview == next && inspected.superview == next);
    EXPECT(pane.superview == nil && pane.toolsView == nil);
    [pane layout];
    EXPECT(layouts == 1);
    EXPECT(![pane setHostedToolsView:tools]);
    ReentrantView* reentrant = [[ReentrantView alloc] initWithFrame:NSZeroRect];
    PCNativeDevToolsPaneView* second = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
    __weak PCNativeDevToolsPaneView* weak = second;
    __weak ReentrantView* weak_reentrant = reentrant;
    reentrant.moved = ^{
      if (weak_reentrant.superview) {
        [weak invalidate];
      }
    };
    EXPECT(![second setHostedToolsView:reentrant]);
    EXPECT(second.toolsView == nil && !reentrant.superview);
    reentrant.moved = nil;
    ReentrantView* old = [[ReentrantView alloc] initWithFrame:NSZeroRect];
    NSView* replacement = [[NSView alloc] initWithFrame:NSZeroRect];
    PCNativeDevToolsPaneView* third = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
    EXPECT([third setHostedToolsView:old]);
    __weak PCNativeDevToolsPaneView* weak_third = third;
    __weak ReentrantView* weak_old = old;
    old.moved = ^{
      if (!weak_old.superview) {
        [weak_third setHostedToolsView:replacement];
      }
    };
    EXPECT(![third setHostedToolsView:tools]);
    EXPECT(third.toolsView == replacement && replacement.superview == third);
    old.moved = nil;
    [third invalidate];
    ReentrantView* migrating = [[ReentrantView alloc] initWithFrame:NSZeroRect];
    PCNativeDevToolsPaneView* fourth = [[PCNativeDevToolsPaneView alloc]
        initWithInspectedView:[[NSView alloc] initWithFrame:NSZeroRect]];
    EXPECT([fourth setHostedToolsView:migrating]);
    __weak ReentrantView* weak_migrating = migrating;
    migrating.moved = ^{
      if (!weak_migrating.superview) {
        [next addSubview:weak_migrating];
      }
    };
    [fourth invalidate];
    EXPECT(migrating.superview == next);
    EXPECT(fourth.toolsView == nil);
    migrating.moved = nil;
    ReentrantView* moving_page =
        [[ReentrantView alloc] initWithFrame:NSZeroRect];
    NSView* moving_tools =
        [[NSView alloc] initWithFrame:NSMakeRect(1, 2, 3, 4)];
    PCNativeDevToolsPaneView* fifth =
        [[PCNativeDevToolsPaneView alloc] initWithInspectedView:moving_page];
    EXPECT([fifth setHostedToolsView:moving_tools]);
    __weak ReentrantView* weak_page = moving_page;
    moving_page.framed = ^{
      [next addSubview:moving_tools];
      [next addSubview:weak_page];
    };
    [fifth applyInspectedRect:NSMakeRect(0, 0, 50, 50)
                    toolsRect:NSMakeRect(50, 0, 50, 50)
                hideInspected:YES];
    EXPECT(moving_tools.superview == next && moving_page.superview == next);
    EXPECT(!moving_page.hidden);
    EXPECT(NSEqualRects(moving_tools.frame, NSMakeRect(1, 2, 3, 4)));
    EXPECT(![fifth setHostedToolsView:moving_tools]);
    moving_page.framed = nil;
    [fifth invalidate];
    ReentrantView* counted =
        [[ReentrantView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    PCNativeDevToolsPaneView* stable =
        [[PCNativeDevToolsPaneView alloc] initWithInspectedView:counted];
    [parent.contentView addSubview:stable];
    FocusView* stable_tools = [[FocusView alloc] initWithFrame:NSZeroRect];
    EXPECT([stable setHostedToolsView:stable_tools]);
    [stable applyInspectedRect:NSMakeRect(0, 0, 600, 700)
                     toolsRect:NSMakeRect(600, 0, 300, 700)
                 hideInspected:NO];
    __block int writes = 0;
    counted.framed = ^{
      ++writes;
    };
    [stable applyInspectedRect:NSMakeRect(0, 0, 600, 700)
                     toolsRect:NSMakeRect(600, 0, 300, 700)
                 hideInspected:NO];
    EXPECT(writes == 0);
    EXPECT(NSEqualRects(counted.frame, NSMakeRect(0, 0, 600, 700)));
    [stable applyInspectedRect:NSMakeRect(0, 0, 500, 700)
                     toolsRect:NSMakeRect(500, 0, 400, 700)
                 hideInspected:NO];
    EXPECT(writes == 1);
    EXPECT(NSEqualRects(counted.frame, NSMakeRect(0, 0, 500, 700)));
    __block int handlers = 0;
    __weak PCNativeDevToolsPaneView* weak_stable = stable;
    __weak FocusView* weak_tools = stable_tools;
    stable.layoutHandler = ^(NSRect) {
      ++handlers;
      PCNativeDevToolsPaneView* pane = weak_stable;
      FocusView* tools = weak_tools;
      if (!pane || !tools) {
        return;
      }
      [pane applyInspectedRect:counted.frame
                     toolsRect:tools.frame
                 hideInspected:NO];
    };
    [stable layout];
    EXPECT(handlers == 1);
    EXPECT(writes == 1);
    [stable layout];
    EXPECT(handlers == 2);
    EXPECT(writes == 1);
    counted.framed = ^{
      ++writes;
      [weak_stable layout];
    };
    [stable applyInspectedRect:NSMakeRect(0, 0, 400, 700)
                     toolsRect:NSMakeRect(400, 0, 500, 700)
                 hideInspected:NO];
    EXPECT(writes == 2);
    EXPECT(handlers == 2);
    counted.framed = nil;
    [stable invalidate];
    [parent close];
    std::printf("NativeDevTools AppKit: %d assertions across 8 groups passed\n",
                assertions);
  }
}

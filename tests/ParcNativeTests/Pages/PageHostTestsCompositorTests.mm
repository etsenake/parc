#import "PageHostTestsSupport.h"

using namespace PageHostTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_PageHostTestsCompositorTests")))
@interface PageHostTestsCompositorTests : ParcNativeTestCase
@end

@implementation PageHostTestsCompositorTests

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
  ParcNativeClose(window);
}

- (void)testAttachingTheCompositorReportsGeometry {
  CompositorFixture f;
  Check(!f.overlay.onScreen, "an unplaced compositor view is off screen");
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
  Check(f.geometryChanges >= 1, "joining a window reports geometry");
}

- (void)testResizingTheCompositorReportsOnlyChangedGeometry {
  CompositorFixture f;
  [f.page addSubview:f.overlay positioned:NSWindowBelow relativeTo:nil];
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

@end

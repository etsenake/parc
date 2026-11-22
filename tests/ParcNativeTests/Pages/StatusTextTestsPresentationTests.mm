#import "StatusTextTestsSupport.h"

using namespace StatusTextTestsSupportFunctions;

__attribute__((objc_runtime_name("ParcNativeTests_StatusTextTestsPresentationTests")))
@interface StatusTextTestsPresentationTests : StatusTextTestsSupport
@end

@implementation StatusTextTestsPresentationTests

- (void)testStatusStartsHidden {
  [self attach];
  Check(pill.hidden && pill.alphaValue == 0, "initially hidden and transparent");
}

- (void)testTheOverlayPassesClicksThrough {
  [self attach];
  Check([overlay hitTest:NSMakePoint(30, 30)] == nil, "overlay is click-through");
}

- (void)testChangedTextRestartsTheShowDelay {
  [self attach];
  [controller updateText:@"https://first.test"];
  Pump(.3);
  Check(pill.hidden, "visibility delay is not an immediate show");
  [controller updateText:LongText()];
  Pump(.3);
  Check(pill.hidden, "changed text restarts visibility delay");
  Pump(.3);
  Check(!pill.hidden, "latest nonempty text shows after debounce");
  Check([label.stringValue isEqual:[LongText() substringFromIndex:8]],
        "latest text keeps everything after the removed https:// prefix");
}

- (void)testLongLinksInitiallyUseTheCompactPill {
  [self show:LongText()];
  Check(NSWidth(pill.frame) == 400 && NSHeight(pill.frame) == 24,
        "compact width and recovered height");
  Check(NSMaxY(pill.frame) == NSHeight(overlay.bounds) - 10,
        "page-local bottom inset in flipped overlay");
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle, "compact truncation");
}

- (void)testThePillKeepsItsSideWhenAvoidanceZonesOverlap {
  [self show:LongText()];
  [controller updatePointerInOverlay:NSMakePoint(12, NSMinY(pill.frame) + 12)];
  page.frame = NSMakeRect(0, 0, 500, 500);
  [overlay layoutSubtreeIfNeeded];
  [controller updatePointerInOverlay:NSMakePoint(200, NSMinY(pill.frame) + 12)];
  Check(NSMaxX(pill.frame) == 490, "overlapping zones retain the previous side");
}

- (void)testDuplicateTextKeepsTheExpansionDeadline {
  [self show:LongText()];
  [controller updateText:LongText()];
  Pump(1.0);
  Check(NSWidth(pill.frame) == 900, "duplicate text does not restart expansion dwell");
  Check(label.lineBreakMode == NSLineBreakByTruncatingTail, "expanded truncation");
}

- (void)testClearingTheLinkDelaysHidingItsText {
  [self show:LongText()];
  [controller updateText:@""];
  Pump(.2);
  Check(!pill.hidden && [label.stringValue isEqual:[LongText() substringFromIndex:8]],
        "empty input preserves content until delayed hide");
  Pump(.7);
  Check(pill.hidden && pill.alphaValue == 0, "empty input finishes native fade");
}

- (void)testHidingTheExpandedPillRestoresMiddleTruncation {
  [self show:LongText()];
  Pump(1);
  [controller updateText:@""];
  Pump(.7);
  Check(label.lineBreakMode == NSLineBreakByTruncatingMiddle, "hide resets expansion");
}

- (void)testResetCancelsAPendingShow {
  [self attach];
  [controller updateText:@"https://cancelled.test"];
  Pump(.1);
  [controller reset];
  Pump(.7);
  Check(pill.hidden && label.stringValue.length == 0, "reset cancels pending show");
}

- (void)testInvalidationRemovesOnlyTheOverlay {
  [self attach];
  [controller invalidate];
  Check(overlay.superview == nil, "terminal teardown removes only owned overlay");
  Check(page.superview == window.contentView, "teardown preserves real page");
}

- (void)testShowingThePillInstallsTheMouseMonitor {
  [self show:LongText()];
  Check(!pill.hidden && [controller hasMouseMovedMonitor],
        "visible pill installs the local mouseMoved monitor");
}

- (void)testPointerMovesWithinTheSameZoneSkipLayout {
  [self show:LongText()];
  const NSPoint left = NSMakePoint(12, NSMinY(pill.frame) + 12);
  Check([controller pointerAvoidanceWouldLayoutAt:left],
        "entering the left avoidance zone needs layout");
  [controller updatePointerInOverlay:left];
  Check(NSMaxX(pill.frame) == NSWidth(Find(page, @"parc-status-overlay").bounds) - 10,
        "left-zone flips trailing");
  Check(![controller pointerAvoidanceWouldLayoutAt:left],
        "same left-zone point under unchanged overlay/pill fingerprint skips layout");
  const NSRect trailing = pill.frame;
  for (int i = 0; i < 8; ++i) {
    [controller updatePointerInOverlay:NSMakePoint(14 + i, NSMinY(trailing) + 10)];
  }
  Check(NSEqualRects(pill.frame, trailing),
        "repeated left-zone moves keep the trailing frame (true no-op)");
}

- (void)testLeavingTheAvoidanceZoneRestoresTheLeadingSide {
  [self show:LongText()];
  const NSPoint left = NSMakePoint(12, NSMinY(pill.frame) + 12);
  const NSPoint outside = NSMakePoint(20, 20);
  [controller updatePointerInOverlay:left];
  Check([controller pointerAvoidanceWouldLayoutAt:outside],
        "leaving the left zone needs layout to restore leading");
  [controller updatePointerInOverlay:outside];
  Check(NSMinX(pill.frame) == 10, "outside left zone restores leading");
  Check(![controller pointerAvoidanceWouldLayoutAt:outside],
        "stable outside-zone fingerprint skips layout");
}

- (void)testHidingThePillStopsTheMouseMonitor {
  [self show:LongText()];
  [controller updateText:@""];
  Pump(.9);
  Check(pill.hidden && ![controller hasMouseMovedMonitor],
        "hidden pill idle-stops the mouseMoved monitor");
}

- (void)testHidingThePillStopsPointerAvoidance {
  [self show:LongText()];
  const NSPoint left = NSMakePoint(12, NSMinY(pill.frame) + 12);
  [controller updateText:@""];
  Pump(.9);
  Check(![controller pointerAvoidanceWouldLayoutAt:left],
        "hidden pill cannot schedule avoidance layout");
}

@end

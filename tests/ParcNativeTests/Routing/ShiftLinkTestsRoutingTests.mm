#import "ShiftLinkTestsSupport.h"

using namespace ShiftLinkTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_ShiftLinkTestsRoutingTests")))
@interface ShiftLinkTestsRoutingTests : ParcNativeTestCase
@end

@implementation ShiftLinkTestsRoutingTests

- (void)checkHintInsidePeek:(bool)inside allowsNavigation:(bool)allowed foregroundTab:(bool)tab {
  auto page = opened(shift, inside);
  page.click.frame_can_navigate_page = allowed;
  page.new_window = !tab;
  page.foreground_tab = tab;
  PARC_CHECK(NativeShiftLinkOutcome(route(page)) == hint(inside, allowed));
}

- (void)testShiftRoutesCreatedPages {
  Check(ChooseNativeCreatedPageRoute(shift, false, true) == NativeCreatedPageRoute::kShift,
        "a page opened while only Shift is held follows the Shift-click link rules");
}

- (void)testCapsLockPreservesCreatedPageShift {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCapsLock, false, true) ==
            NativeCreatedPageRoute::kShift,
        "Caps Lock does not change the Shift route");
}

- (void)testEmbeddedFramesCanUseShift {
  Check(ChooseNativeCreatedPageRoute(shift, false, false) == NativeCreatedPageRoute::kShift,
        "a page opened from an ordinary embedded frame with only Shift held follows the frame's "
        "Shift-click links");
}

- (void)testEmbeddedFramesCannotAutomaticallyOpenPeeks {
  Check(ChooseNativeCreatedPageRoute(0, false, false) == NativeCreatedPageRoute::kNone,
        "the automatic Peek keeps its rule that only the page's own frame opens one");
}

- (void)testMeetingLinksCanUseShift {
  Check(ChooseNativeCreatedPageRoute(shift, true, true) == NativeCreatedPageRoute::kShift,
        "a Shift-clicked meeting button follows the Shift-click link rules like a meeting link");
}

- (void)testMeetingLinksSkipAutomaticPeeks {
  Check(ChooseNativeCreatedPageRoute(0, true, true) == NativeCreatedPageRoute::kNone,
        "the automatic Peek still leaves meeting pages alone");
}

- (void)testPlainLinksCanAutomaticallyOpenPeeks {
  Check(ChooseNativeCreatedPageRoute(0, false, true) == NativeCreatedPageRoute::kAutomatic,
        "a page opened without Shift keeps the automatic Peek rule");
}

- (void)testCommandLinksKeepTheirTab {
  Check(ChooseNativeCreatedPageRoute(NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Command-click opening keeps its tab");
}

- (void)testShiftCommandLinksKeepTheirTab {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Shift-Command opening keeps its tab");
}

- (void)testShiftOptionLinksUseAutomaticRouting {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagOption, false, true) ==
            NativeCreatedPageRoute::kAutomatic,
        "other Shift mixes keep the automatic Peek rule they had");
}

- (void)testOnlyUnmixedShiftCountsAsHeld {
  Check(NativeShiftHeld(shift) && !NativeShiftHeld(shift | NSEventModifierFlagControl) &&
            !NativeShiftHeld(0),
        "only Shift on its own counts as a Shift-click");
}

- (void)testPermittedWindowHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:true foregroundTab:false];
}

- (void)testPermittedTabHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:true foregroundTab:true];
}

- (void)testRestrictedWindowHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:false foregroundTab:false];
}

- (void)testRestrictedTabHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:false foregroundTab:true];
}

- (void)testPermittedWindowHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:true foregroundTab:false];
}

- (void)testPermittedTabHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:true foregroundTab:true];
}

- (void)testRestrictedWindowHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:false foregroundTab:false];
}

- (void)testRestrictedTabHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:false foregroundTab:true];
}

- (void)testSamePeekRoutesPromiseTheCurrentPeek {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kSamePeek) == PCNativeStatusLinkOutcomeThisPeek,
        "the hint says a same-Peek link opens in this Peek");
}

- (void)testPeekRoutesPromiseANewPeek {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kPeek) == PCNativeStatusLinkOutcomePeek,
        "the hint promises a Peek outside one");
}

- (void)testOrdinaryRoutesPromiseANewWindow {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kOrdinary) == PCNativeStatusLinkOutcomeNewWindow,
        "the hint says a new window otherwise");
}

@end

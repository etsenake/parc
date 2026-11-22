#import "ShiftLinkTestsSupport.h"

using namespace ShiftLinkTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_ShiftLinkTestsClickTests")))
@interface ShiftLinkTestsClickTests : ParcNativeTestCase
@end

@implementation ShiftLinkTestsClickTests

- (void)checkOrdinaryModifier:(NSEventModifierFlags)flags insidePeek:(bool)inside {
  PARC_CHECK(ClassifyNativeShiftLink(Click(flags, inside)) == NativeShiftLink::kOrdinary);
  PARC_CHECK(route(opened(flags, inside)) == NativeShiftLink::kOrdinary);
}

- (void)testShiftInsideAPeekReusesIt {
  Check(ClassifyNativeShiftLink(Click(shift, true)) == NativeShiftLink::kSamePeek,
        "Shift-click inside the shown Peek navigates that Peek");
}

- (void)testShiftOutsideAPeekOpensOne {
  Check(ClassifyNativeShiftLink(Click(shift, false)) == NativeShiftLink::kPeek,
        "Shift-click outside a Peek opens a Peek");
}

- (void)testCapsLockPreservesShiftClick {
  Check(ClassifyNativeShiftLink(Click(shift | NSEventModifierFlagCapsLock, true)) ==
            NativeShiftLink::kSamePeek,
        "Caps Lock does not change the Shift-click");
}

- (void)testPlainClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:0 insidePeek:false];
}

- (void)testCommandClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagCommand insidePeek:false];
}

- (void)testOptionClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagOption insidePeek:false];
}

- (void)testControlClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagControl insidePeek:false];
}

- (void)testShiftCommandClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagCommand insidePeek:false];
}

- (void)testShiftOptionClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagOption insidePeek:false];
}

- (void)testShiftControlClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagControl insidePeek:false];
}

- (void)testDisabledPeekKeepsShiftClicksOrdinaryOutsideAPeek {
  auto click = Click(shift, false);
  click.shift_peek_enabled = false;
  PARC_CHECK(ClassifyNativeShiftLink(click) == NativeShiftLink::kOrdinary);
}

- (void)testPlainClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:0 insidePeek:true];
}

- (void)testCommandClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagCommand insidePeek:true];
}

- (void)testOptionClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagOption insidePeek:true];
}

- (void)testControlClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagControl insidePeek:true];
}

- (void)testShiftCommandClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagCommand insidePeek:true];
}

- (void)testShiftOptionClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagOption insidePeek:true];
}

- (void)testShiftControlClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagControl insidePeek:true];
}

- (void)testDisabledPeekKeepsShiftClicksOrdinaryInsideAPeek {
  auto click = Click(shift, true);
  click.shift_peek_enabled = false;
  PARC_CHECK(ClassifyNativeShiftLink(click) == NativeShiftLink::kOrdinary);
}

- (void)testShiftCannotStackPeeks {
  auto stacked = Click(shift, true);
  stacked.can_open_peek = true;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kSamePeek,
        "a Shift-click inside a Peek never stacks a second Peek");
}

- (void)testSandboxedFramesCannotReplaceTheirPeek {
  auto stacked = Click(shift, true);
  stacked.can_open_peek = true;
  stacked.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kOrdinary,
        "an embedded frame sandboxed against navigating the page keeps the ordinary route");
}

- (void)testSandboxedFramesCanOpenANewPeek {
  auto sandboxed = Click(shift, false);
  sandboxed.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(sandboxed) == NativeShiftLink::kPeek,
        "the page-navigation sandbox only matters for the same-Peek navigation");
}

- (void)testRefusedPeeksKeepTheOrdinaryRoute {
  auto refused = Click(shift, false);
  refused.can_open_peek = false;
  Check(ClassifyNativeShiftLink(refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek right now keeps the ordinary route");
}

- (void)testTopFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(true, true, true),
        "the page's own frame can always navigate the page");
}

- (void)testUnsandboxedFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(false, false, false),
        "an embedded frame without a sandbox can navigate the page");
}

- (void)testUserActivationCanAdmitFrameNavigation {
  Check(NativeFrameCanNavigatePage(false, true, false),
        "a sandboxed frame allowed to navigate the page on a click can take the click there");
}

- (void)testPermittedFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(false, false, true),
        "a sandboxed frame allowed to navigate the page can take the click there");
}

- (void)testRestrictedFramesCannotNavigateThePage {
  Check(!NativeFrameCanNavigatePage(false, true, true),
        "a frame sandboxed against navigating the page cannot take the click there");
}

- (void)testRestrictedFramesInsideAPeekPromiseANewWindow {
  Check(hint(true, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomeNewWindow,
        "inside a Peek, the hint over a frame sandboxed against navigating the page says a new window");
}

- (void)testActivatedFramesInsideAPeekPromiseTheCurrentPeek {
  Check(hint(true, NativeFrameCanNavigatePage(false, true, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over a frame allowed to navigate the page on a click says this Peek");
}

- (void)testOrdinaryFramesInsideAPeekPromiseTheCurrentPeek {
  Check(hint(true, NativeFrameCanNavigatePage(false, false, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over an ordinary embedded frame says this Peek");
}

- (void)testRestrictedFramesOutsideAPeekPromiseAPeek {
  Check(hint(false, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomePeek,
        "outside a Peek, the hint over a sandboxed frame still promises a Peek");
}

@end

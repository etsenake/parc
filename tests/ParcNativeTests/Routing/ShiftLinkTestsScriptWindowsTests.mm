#import "ShiftLinkTestsSupport.h"

using namespace ShiftLinkTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_ShiftLinkTestsScriptWindowsTests")))
@interface ShiftLinkTestsScriptWindowsTests : ParcNativeTestCase
@end

@implementation ShiftLinkTestsScriptWindowsTests

- (void)testAScriptWindowFromShiftClickOpensAPeek {
  Check(route(opened(shift, false)) == NativeShiftLink::kPeek,
        "a page a site opens in a new window from a Shift-click opens in a Peek");
}

- (void)testCapsLockPreservesTheScriptWindowRoute {
  Check(route(opened(shift | NSEventModifierFlagCapsLock, false)) == NativeShiftLink::kPeek,
        "Caps Lock does not change a script-opened Shift-click");
}

- (void)testAScriptWindowInsideAPeekReusesIt {
  Check(route(opened(shift, true)) == NativeShiftLink::kSamePeek,
        "a page a site opens from a Shift-click inside a shown Peek navigates that Peek");
}

- (void)testScriptWindowsCannotStackPeeks {
  auto opened_in_peek = opened(shift, true);
  opened_in_peek.click.can_open_peek = true;
  Check(route(opened_in_peek) == NativeShiftLink::kSamePeek,
        "a script-opened page from inside a shown Peek never stacks a second Peek");
}

- (void)testScriptWindowsRemainWindowsWhenPeeksAreUnavailable {
  auto opened_refused = opened(shift, false);
  opened_refused.click.can_open_peek = false;
  Check(route(opened_refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek keeps a script-opened page's window");
}

- (void)testSandboxedScriptsCanOpenAPeek {
  auto sandboxed_opener = opened(shift, false);
  sandboxed_opener.click.frame_can_navigate_page = NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener) == NativeShiftLink::kPeek,
        "outside a Peek, a page opened from a sandboxed frame still opens a Peek");
}

- (void)testSandboxedScriptsCannotReplaceTheirPeek {
  auto sandboxed_opener_in_peek = opened(shift, true);
  sandboxed_opener_in_peek.click.frame_can_navigate_page =
      NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener_in_peek) == NativeShiftLink::kOrdinary,
        "inside a Peek, a page opened from a frame sandboxed against navigating the page keeps "
        "its window");
}

- (void)testLateForegroundTabsOpenAPeek {
  auto late = opened(shift, false);
  late.new_window = false;
  late.foreground_tab = true;
  Check(route(late) == NativeShiftLink::kPeek,
        "a page a site opens late as a foreground tab while only Shift is held opens a Peek");
}

- (void)testLateForegroundTabsReuseTheCurrentPeek {
  auto late_in_peek = opened(shift, true);
  late_in_peek.new_window = false;
  late_in_peek.foreground_tab = true;
  Check(route(late_in_peek) == NativeShiftLink::kSamePeek,
        "a late foreground-tab open with only Shift held inside a Peek navigates that Peek");
}

- (void)testRefusingALatePeekKeepsTheTab {
  auto late = opened(shift, false);
  late.new_window = false;
  late.foreground_tab = true;
  auto late_refused = late;
  late_refused.click.can_open_peek = false;
  Check(route(late_refused) == NativeShiftLink::kOrdinary,
        "a late open from a window that cannot present a Peek keeps its tab");
}

- (void)testDisabledScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.click.shift_peek_enabled = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testDisabledScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.click.shift_peek_enabled = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testGesturelessScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.user_gesture = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testGesturelessScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.user_gesture = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBlankScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.web_url = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBlankScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.web_url = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBackgroundScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.new_window = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBackgroundScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.new_window = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testPopupScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.popup = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testPopupScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.popup = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testSizedScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.sized_by_page = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testSizedScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.sized_by_page = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testFencedScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.fenced_frame = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testFencedScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.fenced_frame = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

@end

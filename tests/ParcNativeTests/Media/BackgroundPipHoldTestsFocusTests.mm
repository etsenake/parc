#import "BackgroundPipHoldTestsSupport.h"

using namespace BackgroundPipHoldTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_BackgroundPipHoldTestsFocusTests")))
@interface BackgroundPipHoldTestsFocusTests : ParcNativeTestCase
@end

@implementation BackgroundPipHoldTestsFocusTests

- (void)testTheKeyWindowBelongsToItsOwnChain {
  const FakeWindow first;
  PARC_CHECK(InKeyChain(true, &first, &first));
}

- (void)testAnotherWindowHasADifferentKeyChain {
  const FakeWindow first;
  const FakeWindow second;
  PARC_CHECK(!InKeyChain(true, &second, &first));
}

- (void)testSheetsBelongToTheirParent {
  const FakeWindow first;
  const FakeWindow sheet{&first, nullptr};
  PARC_CHECK(InKeyChain(true, &sheet, &first));
}

- (void)testChildrenBelongToTheirParent {
  const FakeWindow first;
  const FakeWindow child{nullptr, &first};
  PARC_CHECK(InKeyChain(true, &child, &first));
}

- (void)testGrandchildrenBelongToTheirRoot {
  const FakeWindow first;
  const FakeWindow child{nullptr, &first};
  const FakeWindow grandchild{nullptr, &child};
  PARC_CHECK(InKeyChain(true, &grandchild, &first));
}

- (void)testSheetsOnChildrenBelongToTheirRoot {
  const FakeWindow first;
  const FakeWindow child{nullptr, &first};
  const FakeWindow sheet_on_child{&child, nullptr};
  PARC_CHECK(InKeyChain(true, &sheet_on_child, &first));
}

- (void)testUnrelatedSheetsHaveDifferentKeyChains {
  const FakeWindow first;
  const FakeWindow second;
  const FakeWindow sheet{&first, nullptr};
  PARC_CHECK(!InKeyChain(true, &sheet, &second));
}

- (void)testOtherAppPanelsHaveDifferentKeyChains {
  const FakeWindow first;
  const FakeWindow other_app_panel;
  PARC_CHECK(!InKeyChain(true, &other_app_panel, &first));
}

- (void)testMissingKeyWindowsHaveNoChain {
  const FakeWindow first;
  PARC_CHECK(!InKeyChain(true, nullptr, &first));
}

- (void)testInactiveAppsHaveNoKeyWindow {
  const FakeWindow first;
  PARC_CHECK(!InKeyChain(false, &first, &first));
}

- (void)testInactiveAppsHaveNoKeySheet {
  const FakeWindow first;
  const FakeWindow sheet{&first, nullptr};
  PARC_CHECK(!InKeyChain(false, &sheet, &first));
}

- (void)testMissingRootsHaveNoKeyChain {
  const FakeWindow first;
  PARC_CHECK(!InKeyChain(true, &first, nullptr));
}

- (void)testResigningTheAppAllowsHolding {
  const FakeWindow first;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(Holds(GateFor(false, &first, &first), page, laptop, beside));
}

- (void)testAnotherKeyWindowAllowsHolding {
  const FakeWindow first;
  const FakeWindow second;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(Holds(GateFor(true, &second, &first), page, laptop, beside));
}

- (void)testLosingTheKeyWindowAllowsHolding {
  const FakeWindow first;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(Holds(GateFor(true, nullptr, &first), page, laptop, beside));
}

- (void)testTheKeyWindowCannotBeHeld {
  const FakeWindow first;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(!Holds(GateFor(true, &first, &first), page, laptop, beside));
}

- (void)testKeySheetsPreventHolding {
  const FakeWindow first;
  const FakeWindow sheet{&first, nullptr};
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(!Holds(GateFor(true, &sheet, &first), page, laptop, beside));
}

- (void)testKeyChildrenPreventHolding {
  const FakeWindow first;
  const FakeWindow child{nullptr, &first};
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(!Holds(GateFor(true, &child, &first), page, laptop, beside));
}

- (void)testKeySheetsReleaseAnExistingHold {
  const FakeWindow first;
  const FakeWindow sheet{&first, nullptr};
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(!Recheck(true, GateFor(true, &sheet, &first), page, laptop, beside));
}

- (void)testAnotherKeyWindowOpensTheGate {
  const FakeWindow first;
  const FakeWindow second;
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(GateFor(true, &second, &first)));
}

- (void)testAKeyGrandchildClosesTheGate {
  const FakeWindow first;
  const FakeWindow child{nullptr, &first};
  const FakeWindow grandchild{nullptr, &child};
  PARC_CHECK(!parc::BackgroundPipHoldGateOpen(GateFor(true, &grandchild, &first)));
}

- (void)testLosingFocusBeginsAnAwayPass {
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(false, true) ==
              BackgroundPipFocusChange::kLost);
}

- (void)testRegainingFocusEndsAnAwayPass {
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(true, false) ==
              BackgroundPipFocusChange::kRegained);
}

- (void)testStayingKeyDoesNotStartAPass {
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(false, false) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testStayingAwayDoesNotStartAPass {
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(true, true) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testAppResignationLosesPageFocus {
  const FakeWindow first;
  const bool key_here = !InKeyChain(true, &first, &first);
  const bool parc_resigned = !InKeyChain(false, nullptr, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(key_here, parc_resigned) ==
              BackgroundPipFocusChange::kLost);
}

- (void)testAnotherKeyWindowLosesPageFocus {
  const FakeWindow first;
  const FakeWindow second;
  const bool key_here = !InKeyChain(true, &first, &first);
  const bool other_parc_window = !InKeyChain(true, &second, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(key_here, other_parc_window) ==
              BackgroundPipFocusChange::kLost);
}

- (void)testResigningFromAnotherWindowStaysAway {
  const FakeWindow first;
  const FakeWindow second;
  const bool other_parc_window = !InKeyChain(true, &second, &first);
  const bool parc_resigned = !InKeyChain(false, nullptr, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(other_parc_window, parc_resigned) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testReturningToAnotherWindowStaysAway {
  const FakeWindow first;
  const FakeWindow second;
  const bool other_parc_window = !InKeyChain(true, &second, &first);
  const bool parc_resigned = !InKeyChain(false, nullptr, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(parc_resigned, other_parc_window) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testOpeningASheetPreservesPageFocus {
  const FakeWindow first;
  const FakeWindow sheet{&first, nullptr};
  const bool key_here = !InKeyChain(true, &first, &first);
  const bool sheet_key = !InKeyChain(true, &sheet, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(key_here, sheet_key) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testReturningToThePageRegainsFocus {
  const FakeWindow first;
  const FakeWindow second;
  const bool key_here = !InKeyChain(true, &first, &first);
  const bool other_parc_window = !InKeyChain(true, &second, &first);
  using parc::BackgroundPipFocusTransition;
  PARC_CHECK(BackgroundPipFocusTransition(other_parc_window, key_here) ==
              BackgroundPipFocusChange::kRegained);
}

- (void)testAnAwayUnheldPageIsOccluded {
  PARC_CHECK(parc::BackgroundPipFocusAwayOccludes(true, false));
}

- (void)testAnAwayHeldPageStaysVisible {
  PARC_CHECK(!parc::BackgroundPipFocusAwayOccludes(true, true));
}

- (void)testAnActiveUnheldPageStaysVisible {
  PARC_CHECK(!parc::BackgroundPipFocusAwayOccludes(false, false));
}

- (void)testAnActiveHeldPageStaysVisible {
  PARC_CHECK(!parc::BackgroundPipFocusAwayOccludes(false, true));
}

@end

// Copyright 2026 Parc contributors.
#import "ParcNativeTest.h"

#include <cmath>
#include <cstdint>
#include <optional>
#include <vector>

#include "native_background_picture_in_picture_hold.h"

using parc::BackgroundPipFocusChange;
using parc::BackgroundPipHoldGate;
using parc::BackgroundPipHoldPass;
using parc::BackgroundPipRect;
using parc::BackgroundPipWindowRecord;
using Covers = std::optional<std::vector<BackgroundPipRect>>;

namespace {

bool Near(double a, double b) {
  return std::fabs(a - b) < 1e-9;
}

bool SameRect(const BackgroundPipRect& a, const BackgroundPipRect& b) {
  return Near(a.left, b.left) && Near(a.top, b.top) && Near(a.right, b.right) &&
         Near(a.bottom, b.bottom);
}

BackgroundPipRect Quartz(double x, double y, double width, double height) {
  return parc::BackgroundPipRectFromQuartz(x, y, width, height);
}

BackgroundPipHoldGate Away() {
  BackgroundPipHoldGate gate;
  gate.focus_away = true;
  gate.page_shown = true;
  gate.window_visible = true;
  return gate;
}

bool Holds(const BackgroundPipHoldGate& gate,
           const BackgroundPipRect& page,
           const std::vector<BackgroundPipRect>& screens,
           const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kFocusLost,
                                       false, gate, page, screens, covers);
}

bool Recheck(bool held,
             const BackgroundPipHoldGate& gate,
             const BackgroundPipRect& page,
             const std::vector<BackgroundPipRect>& screens,
             const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kRecheck, held,
                                       gate, page, screens, covers);
}

struct FakeWindow {
  const FakeWindow* sheet_parent = nullptr;
  const FakeWindow* parent = nullptr;
};

bool InKeyChain(bool app_active, const FakeWindow* key, const FakeWindow* window) {
  return parc::BackgroundPipWindowInActiveKeyChain(
      app_active, key, window, [](const FakeWindow* candidate) {
        return candidate->sheet_parent ? candidate->sheet_parent
                                       : candidate->parent;
      });
}

BackgroundPipHoldGate GateFor(bool app_active,
                              const FakeWindow* key,
                              const FakeWindow* window) {
  auto gate = Away();
  gate.focus_away = !InKeyChain(app_active, key, window);
  return gate;
}

struct WatchPage {
  bool held = false;
  bool can_enter = false;
};

bool WatchRuns(bool gate_open, const std::vector<WatchPage>& pages) {
  return parc::BackgroundPipHoldWatchRuns(
      gate_open, pages, [](const WatchPage& page) { return page.held; },
      [](const WatchPage& page) { return page.can_enter; });
}

struct Watch {
  std::optional<int64_t> below_half_since;
  bool Keep(const BackgroundPipHoldGate& gate,
            const BackgroundPipRect& page,
            const std::vector<BackgroundPipRect>& screens,
            const Covers& covers,
            int64_t now_ms) {
    return parc::KeepBackgroundPipHold(below_half_since, gate, page, screens,
                                       covers, now_ms);
  }
};

Covers FromRecords(const std::vector<BackgroundPipWindowRecord>& records) {
  return parc::BackgroundPipCoveringWindows(records);
}

struct HostPage {
  bool held = false;
  bool decided = false;
  bool shown = true;
  bool can_enter = false;
  bool picture_in_picture_open = false;
  bool releasing = false;
  int eligibility_reads = 0;

  BackgroundPipHoldGate PageGate(BackgroundPipHoldGate window) const {
    window.page_shown = window.page_shown && shown;
    window.picture_in_picture_open =
        window.picture_in_picture_open || picture_in_picture_open;
    return window;
  }
  void Pass(BackgroundPipHoldPass pass,
            const BackgroundPipHoldGate& window,
            const BackgroundPipRect& page,
            const std::vector<BackgroundPipRect>& screens,
            const Covers& covers) {
    const auto can_enter_now = [this] {
      ++eligibility_reads;
      return can_enter;
    };
    if (!parc::BackgroundPipHoldPassMeasures(pass, held, releasing, decided,
                                             can_enter_now)) {
      return;
    }
    const bool window_gate_open = window.focus_away && window.window_visible &&
                                  !window.displays_asleep &&
                                  !window.screen_locked;
    const bool measured = window_gate_open && shown;
    held = measured && parc::ShouldHoldBackgroundPip(pass, held, PageGate(window),
                                                     page, screens, covers);
    decided = parc::BackgroundPipHoldDecided(pass, decided, measured);
  }
  bool Occluded(const BackgroundPipHoldGate& window) const {
    return parc::BackgroundPipFocusAwayOccludes(
        window.focus_away,
        parc::BackgroundPipPageKept(
            held, decided, parc::BackgroundPipHoldGateOpen(PageGate(window))));
  }
};

bool DecisionPending(bool window_gate_open, const std::vector<HostPage>& pages) {
  return parc::BackgroundPipHoldDecisionPending(
      window_gate_open, pages,
      [](const HostPage& page) { return !page.decided && page.shown; },
      [](const HostPage& page) { return page.can_enter; });
}

}

@interface ParcNativeTests_BackgroundPipHoldTests : ParcNativeTestCase
@end

static const std::vector<BackgroundPipRect> laptop{Quartz(0, 0, 1440, 900)};

@implementation ParcNativeTests_BackgroundPipHoldTests

- (void)testTopEdgesFlipAtThePrimaryScreenHeight {
  PARC_CHECK(SameRect(parc::BackgroundPipRectFromCocoa(0, 800, 100, 100, 900),
                       Quartz(0, 0, 100, 100)));
}

- (void)testBottomEdgesFlipIntoQuartzCoordinates {
  PARC_CHECK(SameRect(parc::BackgroundPipRectFromCocoa(20, 0, 100, 50, 900),
                       Quartz(20, 850, 100, 50)));
}

- (void)testScreensAboveThePrimaryUseNegativeQuartzCoordinates {
  PARC_CHECK(SameRect(parc::BackgroundPipRectFromCocoa(-200, 900, 1920, 1080, 900),
                       Quartz(-200, -1080, 1920, 1080)));
}

- (void)testAnEmptyUnionHasNoArea {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea({}), 0));
}

- (void)testZeroWidthHasNoArea {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea({Quartz(0, 0, 0, 10)}), 0));
}

- (void)testSeparateWindowsContributeBothAreas {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea(
                       {Quartz(0, 0, 10, 10), Quartz(20, 20, 10, 10)}),
                   200));
}

- (void)testIdenticalWindowsCountOnce {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea(
                       {Quartz(0, 0, 10, 10), Quartz(0, 0, 10, 10)}),
                   100));
}

- (void)testContainedWindowsAddNoArea {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea(
                       {Quartz(0, 0, 10, 10), Quartz(2, 2, 3, 3)}),
                   100));
}

- (void)testPartialOverlapsCountOnce {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea(
                       {Quartz(0, 0, 10, 10), Quartz(5, 5, 10, 10)}),
                   175));
}

- (void)testCrossingStripsCountTheirIntersectionOnce {
  PARC_CHECK(Near(parc::BackgroundPipUnionArea(
                       {Quartz(0, 0, 30, 10), Quartz(10, -10, 10, 30),
                        Quartz(0, 0, 30, 10)}),
                   500));
}

- (void)testAdjacentWindowsKeepTheHold {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers other_app{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(Holds(Away(), page, laptop, other_app));
}

- (void)testHalfWidthCoverageKeepsTheHold {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers overlapping_app{{Quartz(360, 25, 1080, 875)}};
  PARC_CHECK(Holds(Away(), page, laptop, overlapping_app));
}

- (void)testMostlyCoveredPagesReleaseTheHold {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  PARC_CHECK(!Holds(Away(), page, laptop, mostly_over));
}

- (void)testHorizontalCoverageChangesAtHalfWidth {
  const auto page = Quartz(100, 100, 100, 100);
  PARC_CHECK(Holds(Away(), page, laptop, Covers{{Quartz(150, 0, 500, 500)}}));
  PARC_CHECK(!Holds(Away(), page, laptop, Covers{{Quartz(149, 0, 500, 500)}}));
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(
                       page, laptop, Covers{{Quartz(149, 0, 500, 500)}}),
                   4900));
}

- (void)testVerticalCoverageChangesAtHalfHeight {
  const auto page = Quartz(100, 100, 100, 100);
  PARC_CHECK(Holds(Away(), page, laptop, Covers{{Quartz(100, 150, 100, 50)}}));
  PARC_CHECK(!Holds(Away(), page, laptop, Covers{{Quartz(100, 149, 100, 51)}}));
}

- (void)testSpanningPagesUseBothDisplays {
  const double primary = 900;
  const std::vector<BackgroundPipRect> displays{
      parc::BackgroundPipRectFromCocoa(0, 0, 1440, 900, primary),
      parc::BackgroundPipRectFromCocoa(1440, -180, 1920, 1080, primary)};
  const auto spanning =
      parc::BackgroundPipRectFromCocoa(1000, 100, 1000, 700, primary);
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(spanning, displays, Covers{{}}),
                   700000));
  PARC_CHECK(Holds(Away(), spanning, displays, Covers{{}}));
  PARC_CHECK(!Holds(Away(), spanning, laptop, Covers{{}}));
}

- (void)testMostlyOffscreenPagesReleaseTheHold {
  const double primary = 900;
  const std::vector<BackgroundPipRect> displays{
      parc::BackgroundPipRectFromCocoa(0, 0, 1440, 900, primary),
      parc::BackgroundPipRectFromCocoa(1440, -180, 1920, 1080, primary)};
  const auto hanging_low =
      parc::BackgroundPipRectFromCocoa(1000, -300, 400, 400, primary);
  PARC_CHECK(!Holds(Away(), hanging_low, displays, Covers{{}}));
}

- (void)testDisplaySeamsClipTheVisibleArea {
  const double primary = 900;
  const std::vector<BackgroundPipRect> displays{
      parc::BackgroundPipRectFromCocoa(0, 0, 1440, 900, primary),
      parc::BackgroundPipRectFromCocoa(1440, -180, 1920, 1080, primary)};
  const auto across_seam =
      parc::BackgroundPipRectFromCocoa(1340, -100, 200, 200, primary);
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(across_seam, displays, Covers{{}}),
                   30000));
  PARC_CHECK(Holds(Away(), across_seam, displays, Covers{{}}));
}

- (void)testMirroringAVisibleDisplayCannotDoubleTheArea {
  const std::vector<BackgroundPipRect> mirrored{
      Quartz(0, 0, 1440, 900), Quartz(0, 0, 1440, 900)};
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(
                       Quartz(1340, 0, 200, 100), mirrored, Covers{{}}),
                   10000));
}

- (void)testCoversOutsideTheDisplayDoNotReduceTheVisibleArea {
  const auto half_off = Quartz(1000, 0, 880, 900);
  const Covers off_screen_cover{{Quartz(1440, 0, 500, 900)}};
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(half_off, laptop, off_screen_cover),
                   396000));
  PARC_CHECK(Holds(Away(), half_off, laptop, off_screen_cover));
}

- (void)testOverlappingWindowsCountOnce {
  const auto page = Quartz(0, 0, 100, 100);
  const Covers overlapping{{Quartz(0, 0, 30, 100), Quartz(10, 0, 30, 100)}};
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(page, laptop, overlapping), 6000));
  PARC_CHECK(Holds(Away(), page, laptop, overlapping));
}

- (void)testStackedWindowsDoNotDoubleCoverThePage {
  const auto page = Quartz(0, 0, 100, 100);
  const Covers stacked{{Quartz(0, 0, 40, 100), Quartz(0, 0, 40, 100),
                        Quartz(20, 0, 20, 100)}};
  PARC_CHECK(Holds(Away(), page, laptop, stacked));
}

- (void)testCrossingCoversCanHideMostOfThePage {
  const auto page = Quartz(0, 0, 100, 100);
  const Covers crossing{{Quartz(0, 0, 100, 40), Quartz(0, 0, 40, 100)}};
  PARC_CHECK(Near(parc::BackgroundPipVisibleArea(page, laptop, crossing), 3600));
  PARC_CHECK(!Holds(Away(), page, laptop, crossing));
}

- (void)testRecheckingAnExistingHoldUsesTheCurrentCover {
  const auto page = Quartz(0, 25, 1440, 875);
  PARC_CHECK(Holds(Away(), page, laptop, Covers{{}}));
  const Covers late_cover{{Quartz(0, 0, 1440, 900)}};
  PARC_CHECK(!Recheck(true, Away(), page, laptop, late_cover));
  PARC_CHECK(Recheck(true, Away(), page, laptop, Covers{{}}));
  PARC_CHECK(!Recheck(false, Away(), page, laptop, Covers{{}}));
}

- (void)testReturningFocusClosesTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.focus_away = false;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  PARC_CHECK(!Recheck(true, gate, page, laptop, clear));
}

- (void)testHidingTheTabClosesTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.page_shown = false;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
}

- (void)testHidingTheWindowClosesTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.window_visible = false;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  PARC_CHECK(!Recheck(true, gate, page, laptop, clear));
}

- (void)testSleepingDisplaysCloseTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.displays_asleep = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
}

- (void)testALockedScreenClosesTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.screen_locked = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  PARC_CHECK(!Recheck(true, gate, page, laptop, clear));
}

- (void)testAnExistingPictureClosesTheGate {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  PARC_CHECK(parc::BackgroundPipHoldGateOpen(gate));
  gate.picture_in_picture_open = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
}

- (void)testAnEmptyGateCannotHoldAPage {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  PARC_CHECK(!Holds(BackgroundPipHoldGate{}, page, laptop, clear));
}

- (void)testAnEmptyPageCannotBeHeld {
  const Covers clear{{}};
  PARC_CHECK(!Holds(Away(), Quartz(0, 0, 0, 0), laptop, clear));
}

- (void)testMissingDisplaysCannotHoldAPage {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  PARC_CHECK(!Holds(Away(), page, {}, clear));
}

- (void)testFailedListingsFallBackToTheVisibleArea {
  const std::optional<std::vector<BackgroundPipWindowRecord>> failed;
  PARC_CHECK(!parc::BackgroundPipCoveringWindows(failed));
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers fallback = parc::BackgroundPipCoveringWindows(failed);
  PARC_CHECK(Holds(Away(), page, laptop, fallback));
  PARC_CHECK(!Holds(Away(), Quartz(1000, 25, 1440, 875), laptop, fallback));
}

- (void)testHiddenWindowsAreExcludedEvenWhenListingFails {
  const std::optional<std::vector<BackgroundPipWindowRecord>> failed;
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers fallback = parc::BackgroundPipCoveringWindows(failed);
  auto hidden = Away();
  hidden.window_visible = false;
  PARC_CHECK(!Holds(hidden, page, laptop, fallback));
}

- (void)testAWindowWithMissingBoundsInvalidatesTheListing {
  const std::vector<BackgroundPipWindowRecord> missing_bounds{
      {0, 1.0, std::nullopt}};
  PARC_CHECK(!parc::BackgroundPipCoveringWindows(missing_bounds));
}

- (void)testAWindowWithMissingLayerInvalidatesTheListing {
  const std::vector<BackgroundPipWindowRecord> missing_layer{
      {std::nullopt, 1.0, Quartz(0, 0, 10, 10)}};
  PARC_CHECK(!parc::BackgroundPipCoveringWindows(missing_layer));
}

- (void)testOnlyVisibleNormalLayerWindowsCanCoverPages {
  const std::vector<BackgroundPipWindowRecord> records{
      {24, 1.0, Quartz(0, 0, 1440, 25)},
      {20, 1.0, Quartz(0, 820, 1440, 80)},
      {25, 1.0, std::nullopt},
      {0, 0.0, Quartz(0, 0, 1440, 900)},
      {0, std::nullopt, Quartz(720, 25, 720, 875)},
      {0, 0.5, Quartz(0, 25, 100, 100)}};
  const auto covers = parc::BackgroundPipCoveringWindows(records);
  PARC_CHECK(covers && covers->size() == 2);
  PARC_CHECK(SameRect((*covers)[0], Quartz(720, 25, 720, 875)));
  PARC_CHECK(SameRect((*covers)[1], Quartz(0, 25, 100, 100)));
  PARC_CHECK(Holds(Away(), Quartz(0, 25, 720, 875), laptop, covers));
}

- (void)testFullPageCoversPreventHolding {
  PARC_CHECK(!Holds(Away(), Quartz(0, 25, 1440, 875), laptop,
                     Covers{{Quartz(0, 25, 1440, 875)}}));
}

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

- (void)testCoveredPagesReleaseAfterTheGracePeriod {
  PARC_CHECK(parc::kBackgroundPipHoldWatchIntervalMs == 500);
  PARC_CHECK(parc::kBackgroundPipHoldReleaseAfterMs == 1000);
  const int64_t tick = parc::kBackgroundPipHoldWatchIntervalMs;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  const Covers full{{Quartz(0, 0, 1440, 900)}};

  Watch watch;
  PARC_CHECK(watch.Keep(Away(), page, laptop, clear, 0));
  PARC_CHECK(!watch.below_half_since);
  PARC_CHECK(watch.Keep(Away(), page, laptop, full, tick));
  PARC_CHECK(watch.below_half_since && *watch.below_half_since == tick);
  PARC_CHECK(watch.Keep(Away(), page, laptop, full, 2 * tick));
  PARC_CHECK(!watch.Keep(Away(), page, laptop, full, 3 * tick));
  PARC_CHECK(!watch.below_half_since);
}

- (void)testReleaseBeginsExactlyAtTheDeadline {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers full{{Quartz(0, 0, 1440, 900)}};
  Watch exact;
  PARC_CHECK(exact.Keep(Away(), page, laptop, full, 10000));
  PARC_CHECK(exact.Keep(Away(), page, laptop, full, 10999));
  PARC_CHECK(!exact.Keep(Away(), page, laptop, full, 11000));
}

- (void)testUncoveringAPageRestartsTheGracePeriod {
  const int64_t tick = parc::kBackgroundPipHoldWatchIntervalMs;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  const Covers full{{Quartz(0, 0, 1440, 900)}};
  Watch reset;
  PARC_CHECK(reset.Keep(Away(), page, laptop, full, 0));
  PARC_CHECK(reset.Keep(Away(), page, laptop, full, tick));
  PARC_CHECK(reset.Keep(Away(), page, laptop, clear, 2 * tick));
  PARC_CHECK(!reset.below_half_since);
  PARC_CHECK(reset.Keep(Away(), page, laptop, full, 3 * tick));
  PARC_CHECK(reset.Keep(Away(), page, laptop, full, 4 * tick));
  PARC_CHECK(!reset.Keep(Away(), page, laptop, full, 5 * tick));
}

- (void)testHalfVisibilityCancelsTheGracePeriod {
  const int64_t tick = parc::kBackgroundPipHoldWatchIntervalMs;
  const auto page = Quartz(0, 25, 720, 875);
  const Covers full{{Quartz(0, 0, 1440, 900)}};
  Watch at_half;
  const Covers half_over{{Quartz(360, 25, 1080, 875)}};
  PARC_CHECK(at_half.Keep(Away(), page, laptop, full, 0));
  PARC_CHECK(at_half.Keep(Away(), page, laptop, half_over, tick));
  PARC_CHECK(!at_half.below_half_since);
  for (int64_t reading = 2; reading < 20; ++reading) {
    PARC_CHECK(at_half.Keep(Away(), page, laptop, half_over, reading * tick));
  }
}

- (void)testAnEmptyPageListNeedsNoWatch {
  PARC_CHECK(!WatchRuns(true, {}));
}

- (void)testUnheldPagesNeedNoWatch {
  PARC_CHECK(!WatchRuns(true, {{false, false}, {false, true}}));
}

- (void)testPausedHeldPagesNeedNoWatch {
  PARC_CHECK(!WatchRuns(true, {{true, false}, {true, false}}));
}

- (void)testAPlayingPageMustItselfBeHeld {
  PARC_CHECK(!WatchRuns(true, {{true, false}, {false, true}}));
}

- (void)testHeldPlayingPagesNeedAWatch {
  PARC_CHECK(WatchRuns(true, {{true, false}, {true, true}}));
}

- (void)testAClosedWindowGateStopsTheWatch {
  PARC_CHECK(!WatchRuns(false, {{true, true}}));
}

- (void)testUnheldPagesAreNeverAskedWhetherTheyArePlaying {
  int asked = 0;
  const std::vector<WatchPage> pages{{false, true}, {false, true}};
  PARC_CHECK(!parc::BackgroundPipHoldWatchRuns(
      true, pages, [](const WatchPage& page) { return page.held; },
      [&](const WatchPage&) {
        ++asked;
        return true;
      }));
  PARC_CHECK(asked == 0);
}

- (void)testGrowingSolidCoversEventuallyReleaseAPage {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  PARC_CHECK(Holds(Away(), page, laptop, beside));
  const auto grown = FromRecords({{0, 1.0, Quartz(0, 0, 1440, 900)}});
  auto gate = Away();
  PARC_CHECK(gate.window_visible);
  Watch watch;
  PARC_CHECK(watch.Keep(gate, page, laptop, grown, 0));
  PARC_CHECK(watch.Keep(gate, page, laptop, grown, 500));
  PARC_CHECK(!watch.Keep(gate, page, laptop, grown, 1000));
}

- (void)testGrowingTranslucentCoversEventuallyReleaseAPage {
  const auto page = Quartz(0, 25, 720, 875);
  auto gate = Away();
  const auto translucent_grown =
      FromRecords({{0, 0.9, Quartz(0, 0, 1440, 900)}});
  Watch translucent;
  PARC_CHECK(translucent.Keep(gate, page, laptop, translucent_grown, 0));
  PARC_CHECK(!translucent.Keep(gate, page, laptop, translucent_grown, 1000));
}

- (void)testFloatingPicturesDoNotCountAsCover {
  const auto page = Quartz(0, 25, 720, 875);
  auto gate = Away();
  const auto floating_pip = FromRecords({{3, 1.0, Quartz(0, 25, 720, 875)}});
  Watch floating;
  for (int64_t now = 0; now <= 3000; now += 500) {
    PARC_CHECK(floating.Keep(gate, page, laptop, floating_pip, now));
  }
}

- (void)testHiddenWindowsImmediatelyReleaseTheirPage {
  const auto page = Quartz(0, 25, 720, 875);
  auto gate = Away();
  gate.window_visible = false;
  Watch hidden;
  PARC_CHECK(!hidden.Keep(gate, page, laptop, Covers{{}}, 0));
}

- (void)testAFullParcWindowCanReleaseThePage {
  const FakeWindow first;
  const FakeWindow second;
  const auto page = Quartz(0, 25, 1440, 875);
  const auto gate = GateFor(true, &second, &first);
  const auto full_parc = FromRecords({{0, 1.0, Quartz(0, 0, 1440, 900)}});
  PARC_CHECK(!Holds(gate, page, laptop, full_parc));
  PARC_CHECK(!Recheck(true, gate, page, laptop, full_parc));
}

- (void)testHalfCoveredPagesCanStayHeldUnderParcWindows {
  const FakeWindow first;
  const FakeWindow second;
  const auto page = Quartz(0, 25, 1440, 875);
  const auto gate = GateFor(true, &second, &first);
  const auto half_parc = FromRecords({{0, 1.0, Quartz(720, 0, 720, 900)}});
  PARC_CHECK(Holds(gate, page, laptop, half_parc));
  PARC_CHECK(Recheck(true, gate, page, laptop, half_parc));
  Watch half;
  for (int64_t now = 0; now <= 5000; now += 500) {
    PARC_CHECK(half.Keep(gate, page, laptop, half_parc, now));
  }
}

- (void)testMostlyCoveredPagesReleaseUnderParcWindows {
  const FakeWindow first;
  const FakeWindow second;
  const auto page = Quartz(0, 25, 1440, 875);
  const auto gate = GateFor(true, &second, &first);
  const auto most_parc = FromRecords({{0, 1.0, Quartz(719, 0, 721, 900)}});
  PARC_CHECK(!Holds(gate, page, laptop, most_parc));
}

- (void)testGrowingParcWindowsUseTheGracePeriod {
  const FakeWindow first;
  const FakeWindow second;
  const auto page = Quartz(0, 25, 1440, 875);
  const auto gate = GateFor(true, &second, &first);
  const auto full_parc = FromRecords({{0, 1.0, Quartz(0, 0, 1440, 900)}});
  const auto half_parc = FromRecords({{0, 1.0, Quartz(720, 0, 720, 900)}});
  Watch full;
  PARC_CHECK(full.Keep(gate, page, laptop, half_parc, 0));
  PARC_CHECK(full.Keep(gate, page, laptop, full_parc, 500));
  PARC_CHECK(full.Keep(gate, page, laptop, full_parc, 1000));
  PARC_CHECK(!full.Keep(gate, page, laptop, full_parc, 1500));
}

- (void)testClearPagesStayHeldAtEachTick {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  PARC_CHECK(Holds(Away(), page, laptop, clear));
  Watch away;
  for (int64_t now = 0; now <= 5000; now += 500) {
    PARC_CHECK(away.Keep(Away(), page, laptop, clear, now));
  }
}

- (void)testAnOpenPictureStopsTheWatch {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  gate.picture_in_picture_open = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  Watch open;
  PARC_CHECK(!open.Keep(gate, page, laptop, clear, 0));
}

- (void)testScreenLockStopsTheWatch {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  gate.screen_locked = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  Watch locked;
  PARC_CHECK(!locked.Keep(gate, page, laptop, clear, 0));
}

- (void)testDisplaySleepStopsTheWatch {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  gate.displays_asleep = true;
  PARC_CHECK(!Holds(gate, page, laptop, clear));
  Watch asleep;
  PARC_CHECK(!asleep.Keep(gate, page, laptop, clear, 0));
}

- (void)testHidingThePageStopsTheWatch {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  gate.page_shown = false;
  Watch hidden;
  PARC_CHECK(!hidden.Keep(gate, page, laptop, clear, 0));
}

- (void)testCollapsedPagesReleaseAfterTheGracePeriod {
  const Covers clear{{}};
  Watch collapsed;
  PARC_CHECK(collapsed.Keep(Away(), Quartz(0, 25, 0, 0), laptop, clear, 0));
  PARC_CHECK(!collapsed.Keep(Away(), Quartz(0, 25, 0, 0), laptop, clear, 1000));
}

- (void)testLosingEveryDisplayReleasesAfterTheGracePeriod {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  Watch no_display;
  PARC_CHECK(no_display.Keep(Away(), page, {}, clear, 0));
  PARC_CHECK(!no_display.Keep(Away(), page, {}, clear, 1000));
}

- (void)testTheReturningKeyWindowResetsTheWatch {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers clear{{}};
  auto gate = Away();
  gate.focus_away = false;
  Watch back;
  back.below_half_since = 0;
  PARC_CHECK(!back.Keep(gate, page, laptop, clear, 500));
  PARC_CHECK(!back.below_half_since);
}

- (void)testTheFirstRecheckIsDeferred {
  PARC_CHECK(parc::kBackgroundPipHoldRecheckDelayMs == 250);
}

- (void)testHeldPagesStayKeptWhenIneligible {
  PARC_CHECK(parc::BackgroundPipPageKept(true, true, false));
}

- (void)testHeldPagesStayKeptWhenEligible {
  PARC_CHECK(parc::BackgroundPipPageKept(true, true, true));
}

- (void)testUndecidedEligiblePagesStayKept {
  PARC_CHECK(parc::BackgroundPipPageKept(false, false, true));
}

- (void)testIneligibleUndecidedPagesAreReleased {
  PARC_CHECK(!parc::BackgroundPipPageKept(false, false, false));
}

- (void)testReleasedDecidedPagesStayReleased {
  PARC_CHECK(!parc::BackgroundPipPageKept(false, true, true));
}

- (void)testMeasuringOnFocusLossRecordsADecision {
  PARC_CHECK(parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kFocusLost,
                                             false, true));
}

- (void)testUnmeasuredFocusLossClearsTheOldDecision {
  PARC_CHECK(!parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kFocusLost,
                                              true, false));
}

- (void)testNewlyEligibleMeasurementsRecordDecisions {
  PARC_CHECK(parc::BackgroundPipHoldDecided(
      BackgroundPipHoldPass::kBecameEligible, false, true));
}

- (void)testUnmeasuredEligiblePagesRemainUndecided {
  PARC_CHECK(!parc::BackgroundPipHoldDecided(
      BackgroundPipHoldPass::kBecameEligible, false, false));
}

- (void)testARecheckPreservesTheExistingDecision {
  PARC_CHECK(parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kRecheck,
                                             true, false));
}

- (void)testARecheckCannotDecideForAnUntestedPage {
  PARC_CHECK(!parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kRecheck,
                                              false, true));
}

- (void)testFocusLossMeasuresPreviouslyDecidedPages {
  PARC_CHECK(parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kFocusLost, false, false, true, [] { return false; }));
}

- (void)testFocusLossCanMeasureDuringRelease {
  PARC_CHECK(parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kFocusLost, true, true, true, [] { return false; }));
}

- (void)testARecheckMeasuresHeldPages {
  PARC_CHECK(parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kRecheck, true, false, true, [] { return false; }));
}

- (void)testARecheckSkipsPagesInTheirGracePeriod {
  PARC_CHECK(!parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kRecheck, true, true, true, [] { return true; }));
}

- (void)testARecheckSkipsUnheldPages {
  PARC_CHECK(!parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kRecheck, false, false, false, [] { return true; }));
}

- (void)testBecomingEligibleMeasuresAnUndecidedPage {
  PARC_CHECK(parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kBecameEligible, false, false, false, [] { return true; }));
}

- (void)testIneligiblePagesSkipMeasurement {
  PARC_CHECK(!parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kBecameEligible, false, false, false, [] { return false; }));
}

- (void)testDecidedPagesSkipNewEligibility {
  PARC_CHECK(!parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kBecameEligible, false, false, true, [] { return true; }));
}

- (void)testHeldPagesSkipNewEligibility {
  PARC_CHECK(!parc::BackgroundPipHoldPassMeasures(
      BackgroundPipHoldPass::kBecameEligible, true, false, true, [] { return true; }));
}

- (void)testAttachingAwayDoesNotIntroduceAnotherFocusTransition {
  const FakeWindow first;
  const FakeWindow second;
  const bool away_at_attach = !InKeyChain(true, &second, &first);
  PARC_CHECK(away_at_attach);
  PARC_CHECK(parc::BackgroundPipFocusTransition(
                  away_at_attach, !InKeyChain(true, &second, &first)) ==
              BackgroundPipFocusChange::kNone);
  PARC_CHECK(parc::BackgroundPipFocusTransition(
                  away_at_attach, !InKeyChain(false, nullptr, &first)) ==
              BackgroundPipFocusChange::kNone);
  PARC_CHECK(parc::BackgroundPipFocusTransition(
                  !InKeyChain(false, nullptr, &first),
                  !InKeyChain(true, nullptr, &first)) ==
              BackgroundPipFocusChange::kNone);
}

- (void)testNewlyPlayablePagesCanBeHeldWhenAttachedAway {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  PARC_CHECK(!video.Occluded(gate));
  PARC_CHECK(!DecisionPending(true, {video}));
  video.can_enter = true;
  PARC_CHECK(!video.Occluded(gate));
  PARC_CHECK(DecisionPending(true, {video}));
  PARC_CHECK(!DecisionPending(false, {video}));
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  PARC_CHECK(video.held && video.decided);
  PARC_CHECK(!video.Occluded(gate));
  PARC_CHECK(!DecisionPending(true, {video}));
  PARC_CHECK(WatchRuns(true, {{video.held, video.can_enter}}));
  video.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, clear);
  PARC_CHECK(video.held && !video.Occluded(gate));
  Watch watch;
  for (int64_t now = 0; now <= 5000; now += 500) {
    PARC_CHECK(watch.Keep(gate, page, laptop, clear, now));
  }
  PARC_CHECK(!video.Occluded(GateFor(false, nullptr, &first)));
  PARC_CHECK(!video.Occluded(GateFor(true, &first, &first)));
}

- (void)testMoreThanHalfVisiblePagesAreHeld {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 720, 875);
  const Covers just_over_half{{Quartz(396, 25, 1044, 875)}};
  HostPage half;
  half.can_enter = true;
  half.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
            just_over_half);
  PARC_CHECK(half.held && half.decided && !half.Occluded(gate));
}

- (void)testPagesBesideAnotherWindowAreHeld {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  HostPage clear_side;
  clear_side.can_enter = true;
  clear_side.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
                  beside);
  PARC_CHECK(clear_side.held && !clear_side.Occluded(gate));
}

- (void)testACoveredPagesFirstDecisionPersists {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage under;
  under.can_enter = true;
  PARC_CHECK(!under.Occluded(gate));
  under.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
             mostly_over);
  PARC_CHECK(!under.held && under.decided);
  PARC_CHECK(under.Occluded(gate));
  PARC_CHECK(!DecisionPending(true, {under}));
  under.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
             beside);
  PARC_CHECK(!under.held && under.Occluded(gate));
  PARC_CHECK(under.eligibility_reads == 1);
}

- (void)testALaterCoverCanReleaseAHeldPage {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage late;
  late.can_enter = true;
  late.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
            beside);
  PARC_CHECK(late.held);
  late.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, mostly_over);
  PARC_CHECK(!late.held && late.decided && late.Occluded(gate));
}

- (void)testTheGracePeriodBelongsToItsOwnPage {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage watched;
  watched.can_enter = true;
  watched.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
               beside);
  Watch grace;
  PARC_CHECK(grace.Keep(gate, page, laptop, mostly_over, 0));
  watched.releasing = grace.below_half_since.has_value();
  PARC_CHECK(watched.releasing);
  HostPage newcomer;
  newcomer.can_enter = true;
  newcomer.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
                beside);
  PARC_CHECK(newcomer.held);
  watched.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop,
               mostly_over);
  newcomer.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop,
                mostly_over);
  PARC_CHECK(watched.held && !watched.Occluded(gate));
  PARC_CHECK(!newcomer.held && newcomer.Occluded(gate));
  PARC_CHECK(grace.Keep(gate, page, laptop, mostly_over, 500));
  PARC_CHECK(!grace.Keep(gate, page, laptop, mostly_over, 1000));
}

- (void)testPausedPagesDecideWithoutReadingPlaybackEligibility {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage measured_paused;
  measured_paused.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page,
                       laptop, mostly_over);
  PARC_CHECK(measured_paused.decided && !measured_paused.held);
  PARC_CHECK(measured_paused.eligibility_reads == 0);
  measured_paused.can_enter = true;
  PARC_CHECK(!DecisionPending(true, {measured_paused}));
  measured_paused.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                       laptop, beside);
  PARC_CHECK(measured_paused.Occluded(Away()));
}

- (void)testBackgroundTabsWaitUntilShown {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  HostPage background_tab;
  background_tab.shown = false;
  background_tab.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page, laptop,
                      beside);
  PARC_CHECK(!background_tab.decided && !background_tab.held);
  background_tab.can_enter = true;
  PARC_CHECK(!DecisionPending(true, {background_tab}));
  background_tab.shown = true;
  PARC_CHECK(!background_tab.Occluded(Away()));
  PARC_CHECK(DecisionPending(true, {background_tab}));
  background_tab.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                      laptop, beside);
  PARC_CHECK(background_tab.held && !background_tab.Occluded(Away()));
}

- (void)testCoveredPagesWaitForAVisibleWindow {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage covered;
  covered.can_enter = true;
  auto hidden = Away();
  hidden.window_visible = false;
  PARC_CHECK(covered.Occluded(hidden));
  covered.Pass(BackgroundPipHoldPass::kBecameEligible, hidden, page, laptop,
               beside);
  PARC_CHECK(!covered.decided && !covered.held);
  PARC_CHECK(covered.Occluded(hidden));
  PARC_CHECK(!covered.Occluded(Away()));
  PARC_CHECK(DecisionPending(true, {covered}));
  covered.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page, laptop,
               mostly_over);
  PARC_CHECK(covered.decided && covered.Occluded(Away()));
}

- (void)testARecheckCannotDecideForAnUntouchedPage {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
  HostPage untouched;
  untouched.can_enter = true;
  untouched.Pass(BackgroundPipHoldPass::kRecheck, Away(), page, laptop,
                 mostly_over);
  PARC_CHECK(!untouched.decided && !untouched.Occluded(Away()));
}

- (void)testAnOpenPictureDecidesWithoutHolding {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  HostPage already_open;
  already_open.can_enter = true;
  already_open.picture_in_picture_open = true;
  PARC_CHECK(already_open.Occluded(Away()));
  already_open.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                    laptop, beside);
  PARC_CHECK(already_open.decided && !already_open.held);
  already_open.picture_in_picture_open = false;
  PARC_CHECK(already_open.Occluded(Away()));
}

- (void)testDisplaySleepSkipsTheFocusLossMeasurement {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  auto gate = Away();
  gate.displays_asleep = true;
  HostPage unmeasured;
  unmeasured.can_enter = true;
  PARC_CHECK(unmeasured.Occluded(gate));
  unmeasured.Pass(BackgroundPipHoldPass::kFocusLost, gate, page, laptop,
                  beside);
  PARC_CHECK(!unmeasured.decided && unmeasured.Occluded(gate));
}

- (void)testScreenLockSkipsTheFocusLossMeasurement {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  auto gate = Away();
  gate.screen_locked = true;
  HostPage unmeasured;
  unmeasured.can_enter = true;
  PARC_CHECK(unmeasured.Occluded(gate));
  unmeasured.Pass(BackgroundPipHoldPass::kFocusLost, gate, page, laptop,
                  beside);
  PARC_CHECK(!unmeasured.decided && unmeasured.Occluded(gate));
}

- (void)testReturningToTheKeyWindowAllowsAFreshDecision {
  const auto page = Quartz(0, 25, 720, 875);
  const Covers beside{{Quartz(720, 25, 720, 875)}};
  HostPage key_again;
  key_again.can_enter = true;
  auto back = Away();
  back.focus_away = false;
  PARC_CHECK(!key_again.Occluded(back));
  key_again.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page, laptop,
                 beside);
  PARC_CHECK(key_again.held && key_again.decided);
}

- (void)testADecisionWaitsForEveryPlayingPage {
  HostPage paused;
  HostPage decided;
  decided.decided = true;
  decided.can_enter = true;
  HostPage playing;
  playing.can_enter = true;
  PARC_CHECK(!DecisionPending(true, {paused, decided}));
  PARC_CHECK(DecisionPending(true, {paused, decided, playing}));
  playing.shown = false;
  PARC_CHECK(!DecisionPending(true, {paused, decided, playing}));
}

@end

#import "BackgroundPipHoldTestsSupport.h"

using namespace BackgroundPipHoldTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_BackgroundPipHoldTestsVisibilityTests")))
@interface BackgroundPipHoldTestsVisibilityTests : ParcNativeTestCase
@end

@implementation BackgroundPipHoldTestsVisibilityTests

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

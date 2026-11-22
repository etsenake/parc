#import "BackgroundPipHoldTestsSupport.h"

using namespace BackgroundPipHoldTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_BackgroundPipHoldTestsDecisionTests")))
@interface BackgroundPipHoldTestsDecisionTests : ParcNativeTestCase
@end

@implementation BackgroundPipHoldTestsDecisionTests

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

- (void)testAnAwayPageStaysVisibleWhilePlaybackBecomesEligible {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  HostPage video;
  PARC_CHECK(!video.Occluded(gate));
  video.can_enter = true;
  PARC_CHECK(!video.Occluded(gate));
}

- (void)testOnlyEligibleUndecidedPagesNeedAHoldDecision {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  PARC_CHECK(!DecisionPending(true, {video}));
  video.can_enter = true;
  PARC_CHECK(DecisionPending(true, {video}));
  PARC_CHECK(!DecisionPending(false, {video}));
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  PARC_CHECK(!DecisionPending(true, {video}));
}

- (void)testNewlyPlayablePagesAreHeldWhenAttachedAway {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  video.can_enter = true;
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  PARC_CHECK(video.held && video.decided);
  PARC_CHECK(!video.Occluded(gate));
}

- (void)testAnEligibleHeldPageKeepsTheWatchRunning {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  video.can_enter = true;
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  PARC_CHECK(WatchRuns(true, {{video.held, video.can_enter}}));
}

- (void)testARecheckKeepsAClearHeldPageVisible {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  video.can_enter = true;
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  video.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, clear);
  PARC_CHECK(video.held && !video.Occluded(gate));
  Watch watch;
  for (int64_t now = 0; now <= 5000; now += 500) {
    PARC_CHECK(watch.Keep(gate, page, laptop, clear, now));
  }
}

- (void)testAHeldPageStaysVisibleAcrossFocusChanges {
  const FakeWindow first;
  const FakeWindow second;
  const auto gate = GateFor(true, &second, &first);
  const auto page = Quartz(0, 25, 1440, 875);
  const Covers clear{{}};
  HostPage video;
  video.can_enter = true;
  video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
  video.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, clear);
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

@end

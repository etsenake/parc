#import "BackgroundPipHoldTestsSupport.h"

using namespace BackgroundPipHoldTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_BackgroundPipHoldTestsWatchTests")))
@interface BackgroundPipHoldTestsWatchTests : ParcNativeTestCase
@end

@implementation BackgroundPipHoldTestsWatchTests

- (void)testTheWatchChecksEveryHalfSecond {
  PARC_CHECK(parc::kBackgroundPipHoldWatchIntervalMs == 500);
}

- (void)testTheGracePeriodLastsOneSecond {
  PARC_CHECK(parc::kBackgroundPipHoldReleaseAfterMs == 1000);
}

- (void)testCoveringAPageStartsTheGracePeriodBeforeRelease {
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

@end

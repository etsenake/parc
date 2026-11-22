#import "BackgroundPipHoldTestsSupport.h"

using namespace BackgroundPipHoldTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_BackgroundPipHoldTestsCoverageTests")))
@interface BackgroundPipHoldTestsCoverageTests : ParcNativeTestCase
@end

@implementation BackgroundPipHoldTestsCoverageTests

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

@end

#import "TopBandColorTestsSupport.h"

using namespace TopBandColorTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_TopBandColorTestsSamplingTests")))
@interface TopBandColorTestsSamplingTests : ParcNativeTestCase
@end

@implementation TopBandColorTestsSamplingTests

- (void)testOpaqueBandsKeepTheirColor {
  PARC_CHECK(Bitmap(100, 20, 0xFF1A73E8u).Sample() == 0xFF1A73E8u);
}

- (void)testTranslucentBandsKeepTheirAlpha {
  PARC_CHECK(Bitmap(100, 20, 0x801A73E8u).Sample() == 0x801A73E8u);
}

- (void)testEmptyWidthsHaveNoSample {
  PARC_CHECK(!tb::SampleBand(0, 5, 8, 24, [](int, int) { return 0u; }));
}

- (void)testEmptyHeightsHaveNoSample {
  PARC_CHECK(!tb::SampleBand(5, 0, 8, 24, [](int, int) { return 0u; }));
}

- (void)testSamplingSkipsTheRightMargin {
  Bitmap margin(124, 10, 0xFF000000u);
  for (int y = 0; y < 10; ++y) {
    for (int x = 101; x < 124; ++x) {
      margin.Set(x, y, 0xFFFFFFFFu);
    }
  }
  PARC_CHECK(margin.Sample() == 0xFF000000u);
}

- (void)testSamplingIncludesTheLastColumnBeforeTheMargin {
  Bitmap margin(124, 10, 0xFF000000u);
  margin.Set(100, 0, 0xFF0A0A0Au);
  PARC_CHECK(margin.Sample() == 0xFF020202u);
}

- (void)testRowsBelowTheBandDoNotContribute {
  Bitmap lower(124, 20, 0xFF000000u);
  lower.Set(0, 8, 0xFFFFFFFFu);
  PARC_CHECK(lower.Sample() == 0xFF000000u);
}

- (void)testTheLastBandRowContributes {
  Bitmap lower(124, 20, 0xFF000000u);
  lower.Set(0, 7, 0xFFFFFFFFu);
  PARC_CHECK(!lower.Sample());
}

- (void)testShortImagesSampleTheirLastRow {
  Bitmap short_band(124, 3, 0xFF000000u);
  short_band.Set(100, 2, 0xFF808080u);
  PARC_CHECK(!short_band.Sample());
}

- (void)testWideColorSpreadsRejectTheBand {
  Bitmap spread(124, 10, 0xFF000000u);
  spread.Set(50, 0, 0xFF800000u);
  PARC_CHECK(!spread.Sample());
}

- (void)testTheLargestAllowedSpreadIsAveraged {
  Bitmap spread(124, 10, 0xFF000000u);
  spread.Set(50, 0, 0xFF7F0000u);
  PARC_CHECK(spread.Sample() == 0xFF190000u);
}

- (void)testTheAverageIncludesAlpha {
  Bitmap spread(124, 10, 0xFF000000u);
  spread.Set(50, 0, 0x007F0000u);
  PARC_CHECK(spread.Sample() == 0xCC190000u);
}

- (void)testRetinaMarginsUsePixelCoordinates {
  Bitmap retina(248, 16, 0xFF202020u);
  for (int x = 201; x < 248; ++x) {
    retina.Set(x, 0, 0xFFFFFFFFu);
  }
  PARC_CHECK(retina.Sample(16, 48) == 0xFF202020u);
  PARC_CHECK(!retina.Sample(16, 24));
}

- (void)testEqualVotesFavorTheFirstColor {
  Votes votes;
  votes.ForColor(1, 0xFF000000u);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(1, 0xFF000000u);
  auto choice = tb::ChooseBand(votes, std::optional<uint32_t>(), false);
  PARC_CHECK(choice.color == 0xFF000000u && !choice.sample_frame);
}

- (void)testCanvasMustOutvoteTheWinningColor {
  Votes canvas;
  canvas.ForColor(1, 0xFF112233u);
  canvas.ForCanvas();
  PARC_CHECK(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFF112233u);
  canvas.ForCanvas();
  PARC_CHECK(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFFFFFFFFu);
}

- (void)testTransparentCanvasCanReuseTheFrame {
  Votes transparent;
  transparent.ForCanvas();
  transparent.ForCanvas();
  auto none = tb::ChooseBand(transparent, std::optional<uint32_t>(), true);
  PARC_CHECK(!none.color && !none.sample_frame && none.reuse_frame_sample);
}

- (void)testFrameVotesRequestACopy {
  Votes frame;
  frame.ForFrameSample(5, 3);
  frame.ForCanvas();
  frame.ForCanvas();
  frame.ForCanvas();
  auto sampled = tb::ChooseBand(frame, std::optional<uint32_t>(0xFFFFFFFFu), true);
  PARC_CHECK(sampled.sample_frame && sampled.frame_sample_id == 3 && !sampled.color &&
         !sampled.reuse_frame_sample);
}

- (void)testAColorCanReuseTheFrameSample {
  Votes reuse;
  reuse.ForColor(4, 0xFF333333u);
  auto kept = tb::ChooseBand(reuse, std::optional<uint32_t>(), true);
  PARC_CHECK(kept.color == 0xFF333333u && kept.reuse_frame_sample);
}

- (void)testManyTiedColorsKeepTheFirstWinner {
  Votes many;
  for (int key = 0; key < 5; ++key) {
    many.ForColor(key, 0xFF000000u + key);
  }
  PARC_CHECK(many.Winner()->key == 0);
}

@end

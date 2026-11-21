#import "ParcNativeTest.h"
#include <cstdint>
#include <optional>
#include <vector>

#include "top_band_color_sampling.h"

namespace tb = parc::top_band;

namespace {

struct Bitmap {
  int width;
  int height;
  std::vector<uint32_t> pixels;
  Bitmap(int w, int h, uint32_t fill) : width(w), height(h), pixels(w * h, fill) {}
  void Set(int x, int y, uint32_t c) { pixels[y * width + x] = c; }
  std::optional<uint32_t> Sample(int rows = tb::kBandRows,
                                 int margin = tb::kRightMargin) const {
    return tb::SampleBand(width, height, rows, margin,
                          [this](int x, int y) { return pixels[y * width + x]; });
  }
};

tb::PixelSampleMemory::Key ImageKey(int64_t node, const void* image, bool loaded) {
  tb::PixelSource source;
  source.AddImage(image, loaded);
  return {node, source.value()};
}
uint64_t Generated(uint32_t value, int width, uint32_t color, int scheme, float zoom) {
  tb::PixelSource source;
  source.AddGenerated(value, width, 120, color, scheme, zoom);
  return source.value();
}
using Votes = tb::BandVotes<int, uint32_t>;
}
@interface ParcNativeTests_TopBandColorTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_TopBandColorTests

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

- (void)testASufficientlyTallLeadingBoxSpansTheBand {
  PARC_CHECK(tb::SpansBand(0, 300, 11, 900));
}

- (void)testAThinLeadingBoxMissesTheBand {
  PARC_CHECK(!tb::SpansBand(0, 300, 10, 900));
}

- (void)testANarrowLeadingBoxMissesTheBand {
  PARC_CHECK(!tb::SpansBand(0, 299, 40, 900));
}

- (void)testAClippedLeadingBoxSpansTheBand {
  PARC_CHECK(tb::SpansBand(-20, 400, 40, 900));
}

- (void)testATrailingBoxSpansTheBand {
  PARC_CHECK(tb::SpansBand(600, 300, 40, 900));
}

- (void)testInsetBoxesMissBothEdges {
  PARC_CHECK(!tb::SpansBand(1, 898, 40, 900));
}

- (void)testCenteredBoxesMissBothEdges {
  PARC_CHECK(!tb::SpansBand(100, 700, 40, 900));
}

- (void)testTheFirstColumnStartsAtZero {
  PARC_CHECK(tb::SampleColumn(0, 1001) == 0);
}

- (void)testTheFourthColumnStartsAtThreeQuarters {
  PARC_CHECK(tb::SampleColumn(3, 1001) == 750);
}

- (void)testImageIdentityIsStable {
  int first = 0;
  PARC_CHECK(ImageKey(0, &first, false).source == ImageKey(0, &first, false).source);
}

- (void)testLoadCompletionChangesImageIdentity {
  int first = 0;
  PARC_CHECK(ImageKey(0, &first, false).source != ImageKey(0, &first, true).source);
}

- (void)testReplacingAnImageChangesIdentity {
  int first = 0, second = 0;
  PARC_CHECK(ImageKey(0, &first, true).source != ImageKey(0, &second, true).source);
}

- (void)testReorderingImagesChangesTheSource {
  int first = 0, second = 0;
  tb::PixelSource forward, backward;
  forward.AddImage(&first, true);
  forward.AddImage(&second, true);
  backward.AddImage(&second, true);
  backward.AddImage(&first, true);
  PARC_CHECK(forward.value() != backward.value());
}

- (void)testGeneratedSourcesAreStable {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base == Generated(0xabc, 800, 0xFF000000u, 0, 1));
}

- (void)testImageValuesDistinguishGeneratedSources {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base != Generated(0xabd, 800, 0xFF000000u, 0, 1));
}

- (void)testWidthDistinguishesGeneratedSources {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base != Generated(0xabc, 640, 0xFF000000u, 0, 1));
}

- (void)testColorDistinguishesGeneratedSources {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base != Generated(0xabc, 800, 0xFFFFFFFFu, 0, 1));
}

- (void)testSchemeDistinguishesGeneratedSources {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base != Generated(0xabc, 800, 0xFF000000u, 1, 1));
}

- (void)testZoomDistinguishesGeneratedSources {
  const uint64_t base = Generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_CHECK(base != Generated(0xabc, 800, 0xFF000000u, 0, 2));
}

- (void)testSecurePagesCacheByHost {
  PARC_CHECK(tb::CacheHost("https", "chatgpt.com") == "chatgpt.com");
}

- (void)testPlainHttpPagesCacheByHost {
  PARC_CHECK(tb::CacheHost("http", "example.com") == "example.com");
}

- (void)testReaderPagesSkipTheHostCache {
  PARC_CHECK(tb::CacheHost("chrome-distiller", "3f2a_9c1d").empty());
}

- (void)testSettingsPagesSkipTheHostCache {
  PARC_CHECK(tb::CacheHost("chrome", "settings").empty());
}

- (void)testExtensionPagesSkipTheHostCache {
  PARC_CHECK(tb::CacheHost("chrome-extension", "abcdefghijklmnop").empty());
}

- (void)testStartPagesSkipTheHostCache {
  PARC_CHECK(tb::CacheHost("parc", "newtab").empty());
}

- (void)testLocalFilesSkipTheHostCache {
  PARC_CHECK(tb::CacheHost("file", "").empty());
}

- (void)testFailedDecodesAreRetriedOnlyAfterTheirCooldown {
  tb::PixelSampleMemory memory;
  int image = 0;
  const tb::PixelSampleMemory::Key failing = ImageKey(7, &image, true);
  int decodes = 0;
  auto fail = [&decodes] {
    ++decodes;
    return std::optional<uint32_t>();
  };
  memory.BeginPass();
  for (int point = 0; point < 4; ++point) {
    PARC_CHECK(!memory.Color(failing, 1'000'000, fail));
  }
  PARC_CHECK(decodes == 1);
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    PARC_CHECK(!memory.Color(failing, 1'000'000 + pass * 100'000, fail));
  }
  PARC_CHECK(decodes == 1);
  memory.BeginPass();
  memory.Color(failing, 2'500'001, fail);
  memory.Color(failing, 2'500'001, fail);
  PARC_CHECK(decodes == 2);
}

- (void)testLoadCompletionGetsItsOwnDecodeAttempt {
  tb::PixelSampleMemory memory;
  int decodes = 0;
  auto fail = [&decodes] {
    ++decodes;
    return std::optional<uint32_t>();
  };
  int late = 0;
  const auto loading = ImageKey(8, &late, false);
  const auto loaded = ImageKey(8, &late, true);
  const int before_load = decodes;
  for (int pass = 0; pass < 5; ++pass) {
    memory.BeginPass();
    memory.Color(loading, 2'500'100 + pass * 100'000, fail);
  }
  PARC_CHECK(decodes == before_load + 1);
  memory.BeginPass();
  memory.Color(loaded, 3'000'000, fail);
  memory.Color(loaded, 3'000'000, fail);
  PARC_CHECK(decodes == before_load + 2);
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    memory.Color(loaded, 3'000'000 + pass * 100'000, fail);
  }
  PARC_CHECK(decodes == before_load + 2);
}

- (void)testNewlyLoadedImagesCanSupplyAPreviouslyMissingColor {
  tb::PixelSampleMemory memory;
  int decodes = 0;
  auto fail = [&decodes] {
    ++decodes;
    return std::optional<uint32_t>();
  };
  int painted = 0;
  int load_reads = 0;
  auto ready = [&load_reads] {
    ++load_reads;
    return std::optional<uint32_t>(0xFF202124u);
  };
  memory.BeginPass();
  memory.Color(ImageKey(10, &painted, false), 3'100'000, fail);
  memory.BeginPass();
  PARC_CHECK(memory.Color(ImageKey(10, &painted, true), 3'200'000, ready) ==
         0xFF202124u);
  PARC_CHECK(load_reads == 1);
}

- (void)testTheFailureCacheKeepsDistinctImageAndNodeIdentities {
  tb::PixelSampleMemory memory;
  int image = 0;
  const tb::PixelSampleMemory::Key failing = ImageKey(7, &image, true);
  int decodes = 0;
  auto fail = [&decodes] {
    ++decodes;
    return std::optional<uint32_t>();
  };
  int other = 0;
  const auto restyled = ImageKey(7, &other, true);
  memory.BeginPass();
  memory.Color(failing, 5'000'000, fail);
  memory.Color(restyled, 5'000'000, fail);
  for (int node = 20; node < 20 + int(tb::PixelSampleMemory::kRememberedFailures) - 2; ++node) {
    memory.Color({node, 1}, 5'000'000, fail);
  }
  const int after_others = decodes;
  memory.BeginPass();
  memory.Color(restyled, 5'100'000, fail);
  memory.Color(failing, 5'100'000, fail);
  for (int node = 20; node < 20 + int(tb::PixelSampleMemory::kRememberedFailures) - 2; ++node) {
    memory.Color({node, 1}, 5'100'000, fail);
  }
  PARC_CHECK(decodes == after_others);
}

- (void)testSuccessfulPixelsAreReadOncePerPass {
  tb::PixelSampleMemory memory;
  int reads = 0;
  auto blue = [&reads] {
    ++reads;
    return std::optional<uint32_t>(0xFF1A73E8u);
  };
  memory.BeginPass();
  PARC_CHECK(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  PARC_CHECK(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  PARC_CHECK(reads == 1);
  memory.BeginPass();
  memory.Color({9, 1}, 5'200'001, blue);
  PARC_CHECK(reads == 2);
}

- (void)testForgettingClearsTheDecodeCooldown {
  tb::PixelSampleMemory memory;
  int image = 0;
  const tb::PixelSampleMemory::Key failing = ImageKey(7, &image, true);
  int decodes = 0;
  auto fail = [&decodes] {
    ++decodes;
    return std::optional<uint32_t>();
  };
  memory.BeginPass();
  memory.Color(failing, 5'200'000, fail);
  memory.Forget();
  memory.BeginPass();
  memory.Color(failing, 5'300'000, fail);
  PARC_CHECK(decodes == 2);
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

- (void)testDirectColorsNeedNoCopy {
  tb::FrameSampleDelivery delivery;
  auto a = delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  PARC_CHECK(a.deliver && a.deliver->color == 0xFF000000u && !a.copy);
}

- (void)testRepeatedColorsSkipDelivery {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  PARC_CHECK(!delivery.OnRendererSample(0xFF000000u, false, 0, false, true).deliver);
}

- (void)testClearingAColorCanCrossfade {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  auto none = delivery.OnRendererSample(std::nullopt, false, 0, false, true);
  PARC_CHECK(none.deliver && !none.deliver->color && none.deliver->crossfade);
}

- (void)testMatchingCopyRequestsCoalesce {
  tb::FrameSampleDelivery delivery;
  auto copy = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  PARC_CHECK(!copy.deliver && copy.copy == 1);
  PARC_CHECK(!delivery.OnRendererSample(std::nullopt, true, 1, false, false).copy);
}

- (void)testStaleFrameResponsesAreIgnored {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  PARC_CHECK(!delivery.OnFrameSample(2, 0xFF111111u).deliver);
}

- (void)testMatchingFramesDeliverTheSampledColor {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  delivery.OnRendererSample(std::nullopt, true, 1, false, false);
  auto sampled = delivery.OnFrameSample(1, 0xFF336699u);
  PARC_CHECK(sampled.deliver && sampled.deliver->color == 0xFF336699u);
  PARC_CHECK(!sampled.deliver->crossfade);
}

- (void)testReturningToASampledFrameUsesItsCachedColor {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  delivery.OnFrameSample(1, 0xFF336699u);
  auto reused = delivery.OnRendererSample(0xFFFFFFFFu, false, 0, false, false);
  PARC_CHECK(reused.deliver && reused.deliver->color == 0xFFFFFFFFu);
  auto cached = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  PARC_CHECK(cached.deliver && cached.deliver->color == 0xFF336699u && !cached.copy);
}

- (void)testRendererReuseReturnsTheLastFrameColor {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  delivery.OnFrameSample(1, 0xFF336699u);
  delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  auto reuse = delivery.OnRendererSample(0xFF000000u, false, 0, true, false);
  PARC_CHECK(reuse.deliver && reuse.deliver->color == 0xFF336699u);
}

- (void)testAnOutstandingCopyYieldsToTheLatestRequestedFrame {
  tb::FrameSampleDelivery delivery;
  auto first = delivery.OnRendererSample(std::nullopt, true, 2, false, false);
  PARC_CHECK(first.copy == 2);
  PARC_CHECK(!delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy);
  auto again = delivery.OnFrameSample(2, 0xFF222222u);
  PARC_CHECK(!again.deliver && again.copy == 3);
  auto third = delivery.OnFrameSample(3, 0xFF333333u);
  PARC_CHECK(third.deliver && third.deliver->color == 0xFF333333u);
}

- (void)testAnUnavailableCopyCanBeRequestedAgain {
  tb::FrameSampleDelivery delivery;
  auto blocked = delivery.OnRendererSample(std::nullopt, true, 4, false, false);
  PARC_CHECK(blocked.copy == 4);
  delivery.CopyUnavailable();
  PARC_CHECK(delivery.OnRendererSample(std::nullopt, true, 4, false, false).copy == 4);
}

- (void)testResetClearsTheDeliveredColorAndCachedFrame {
  tb::FrameSampleDelivery delivery;
  delivery.OnRendererSample(std::nullopt, true, 3, false, false);
  delivery.OnFrameSample(3, 0xFF333333u);
  delivery.Reset();
  auto fresh = delivery.OnRendererSample(0xFF333333u, false, 0, false, false);
  PARC_CHECK(fresh.deliver && fresh.deliver->color == 0xFF333333u);
  PARC_CHECK(delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy == 3);
}

@end

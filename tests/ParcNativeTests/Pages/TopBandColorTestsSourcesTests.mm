#import "TopBandColorTestsSupport.h"

using namespace TopBandColorTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_TopBandColorTestsSourcesTests")))
@interface TopBandColorTestsSourcesTests : ParcNativeTestCase
@end

@implementation TopBandColorTestsSourcesTests

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

@end

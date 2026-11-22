#import "TopBandColorTestsSupport.h"

using namespace TopBandColorTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_TopBandColorTestsFrameDeliveryTests")))
@interface TopBandColorTestsFrameDeliveryTests : ParcNativeTestCase
@end

@implementation TopBandColorTestsFrameDeliveryTests

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

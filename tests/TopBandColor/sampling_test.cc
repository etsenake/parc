#include "../Support/TestFailure.h"
#include <cstdint>
#include <iostream>
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

void Sampling() {
  PARC_EXPECT(Bitmap(100, 20, 0xFF1A73E8u).Sample() == 0xFF1A73E8u);
  PARC_EXPECT(Bitmap(100, 20, 0x801A73E8u).Sample() == 0x801A73E8u);
  PARC_EXPECT(!tb::SampleBand(0, 5, 8, 24, [](int, int) { return 0u; }));
  PARC_EXPECT(!tb::SampleBand(5, 0, 8, 24, [](int, int) { return 0u; }));

  Bitmap margin(124, 10, 0xFF000000u);
  for (int y = 0; y < 10; ++y) {
    for (int x = 101; x < 124; ++x) {
      margin.Set(x, y, 0xFFFFFFFFu);
    }
  }
  PARC_EXPECT(margin.Sample() == 0xFF000000u);
  margin.Set(100, 0, 0xFF0A0A0Au);
  PARC_EXPECT(margin.Sample() == 0xFF020202u);

  Bitmap lower(124, 20, 0xFF000000u);
  lower.Set(0, 8, 0xFFFFFFFFu);
  PARC_EXPECT(lower.Sample() == 0xFF000000u);
  lower.Set(0, 7, 0xFFFFFFFFu);
  PARC_EXPECT(!lower.Sample());
  Bitmap short_band(124, 3, 0xFF000000u);
  short_band.Set(100, 2, 0xFF808080u);
  PARC_EXPECT(!short_band.Sample());

  Bitmap spread(124, 10, 0xFF000000u);
  spread.Set(50, 0, 0xFF800000u);
  PARC_EXPECT(!spread.Sample());
  spread.Set(50, 0, 0xFF7F0000u);
  PARC_EXPECT(spread.Sample() == 0xFF190000u);
  spread.Set(50, 0, 0x007F0000u);
  PARC_EXPECT(spread.Sample() == 0xCC190000u);

  Bitmap retina(248, 16, 0xFF202020u);
  for (int x = 201; x < 248; ++x) {
    retina.Set(x, 0, 0xFFFFFFFFu);
  }
  PARC_EXPECT(retina.Sample(16, 48) == 0xFF202020u);
  PARC_EXPECT(!retina.Sample(16, 24));
}

void BandGeometry() {
  PARC_EXPECT(tb::SpansBand(0, 300, 11, 900));
  PARC_EXPECT(!tb::SpansBand(0, 300, 10, 900));
  PARC_EXPECT(!tb::SpansBand(0, 299, 40, 900));
  PARC_EXPECT(tb::SpansBand(-20, 400, 40, 900));
  PARC_EXPECT(tb::SpansBand(600, 300, 40, 900));
  PARC_EXPECT(!tb::SpansBand(1, 898, 40, 900));
  PARC_EXPECT(!tb::SpansBand(100, 700, 40, 900));
  PARC_EXPECT(tb::SampleColumn(0, 1001) == 0);
  PARC_EXPECT(tb::SampleColumn(3, 1001) == 750);
}

tb::PixelSampleMemory::Key ImageKey(int64_t node, const void* image, bool loaded) {
  tb::PixelSource source;
  source.AddImage(image, loaded);
  return {node, source.value()};
}

void PixelSources() {
  int first = 0, second = 0;
  auto image = [](const void* identity, bool loaded) {
    tb::PixelSource source;
    source.AddImage(identity, loaded);
    return source.value();
  };
  PARC_EXPECT(image(&first, false) == image(&first, false));
  PARC_EXPECT(image(&first, false) != image(&first, true));
  PARC_EXPECT(image(&first, true) != image(&second, true));
  tb::PixelSource forward, backward;
  forward.AddImage(&first, true);
  forward.AddImage(&second, true);
  backward.AddImage(&second, true);
  backward.AddImage(&first, true);
  PARC_EXPECT(forward.value() != backward.value());
  auto generated = [](uint32_t value, int width, uint32_t color, int scheme,
                      float zoom) {
    tb::PixelSource source;
    source.AddGenerated(value, width, 120, color, scheme, zoom);
    return source.value();
  };
  const uint64_t base = generated(0xabc, 800, 0xFF000000u, 0, 1);
  PARC_EXPECT(base == generated(0xabc, 800, 0xFF000000u, 0, 1));
  PARC_EXPECT(base != generated(0xabd, 800, 0xFF000000u, 0, 1));
  PARC_EXPECT(base != generated(0xabc, 640, 0xFF000000u, 0, 1));
  PARC_EXPECT(base != generated(0xabc, 800, 0xFFFFFFFFu, 0, 1));
  PARC_EXPECT(base != generated(0xabc, 800, 0xFF000000u, 1, 1));
  PARC_EXPECT(base != generated(0xabc, 800, 0xFF000000u, 0, 2));
}

void CacheHosts() {
  PARC_EXPECT(tb::CacheHost("https", "chatgpt.com") == "chatgpt.com");
  PARC_EXPECT(tb::CacheHost("http", "example.com") == "example.com");
  PARC_EXPECT(tb::CacheHost("chrome-distiller", "3f2a_9c1d").empty());
  PARC_EXPECT(tb::CacheHost("chrome", "settings").empty());
  PARC_EXPECT(tb::CacheHost("chrome-extension", "abcdefghijklmnop").empty());
  PARC_EXPECT(tb::CacheHost("parc", "newtab").empty());
  PARC_EXPECT(tb::CacheHost("file", "").empty());
}

void PixelMemory() {
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
    PARC_EXPECT(!memory.Color(failing, 1'000'000, fail));
  }
  PARC_EXPECT(decodes == 1);
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    PARC_EXPECT(!memory.Color(failing, 1'000'000 + pass * 100'000, fail));
  }
  PARC_EXPECT(decodes == 1);
  memory.BeginPass();
  memory.Color(failing, 2'500'001, fail);
  memory.Color(failing, 2'500'001, fail);
  PARC_EXPECT(decodes == 2);
  int late = 0;
  const auto loading = ImageKey(8, &late, false);
  const auto loaded = ImageKey(8, &late, true);
  const int before_load = decodes;
  for (int pass = 0; pass < 5; ++pass) {
    memory.BeginPass();
    memory.Color(loading, 2'500'100 + pass * 100'000, fail);
  }
  PARC_EXPECT(decodes == before_load + 1);
  memory.BeginPass();
  memory.Color(loaded, 3'000'000, fail);
  memory.Color(loaded, 3'000'000, fail);
  PARC_EXPECT(decodes == before_load + 2);
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    memory.Color(loaded, 3'000'000 + pass * 100'000, fail);
  }
  PARC_EXPECT(decodes == before_load + 2);
  int painted = 0;
  int load_reads = 0;
  auto ready = [&load_reads] {
    ++load_reads;
    return std::optional<uint32_t>(0xFF202124u);
  };
  memory.BeginPass();
  memory.Color(ImageKey(10, &painted, false), 3'100'000, fail);
  memory.BeginPass();
  PARC_EXPECT(memory.Color(ImageKey(10, &painted, true), 3'200'000, ready) ==
         0xFF202124u);
  PARC_EXPECT(load_reads == 1);
  memory.Forget();
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
  PARC_EXPECT(decodes == after_others);
  int reads = 0;
  auto blue = [&reads] {
    ++reads;
    return std::optional<uint32_t>(0xFF1A73E8u);
  };
  memory.BeginPass();
  PARC_EXPECT(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  PARC_EXPECT(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  PARC_EXPECT(reads == 1);
  memory.BeginPass();
  memory.Color({9, 1}, 5'200'001, blue);
  PARC_EXPECT(reads == 2);
  memory.Forget();
  memory.BeginPass();
  memory.Color(failing, 5'300'000, fail);
  PARC_EXPECT(decodes == after_others + 1);
}

void VotesAndChoice() {
  using Votes = tb::BandVotes<int, uint32_t>;
  Votes votes;
  votes.ForColor(1, 0xFF000000u);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(1, 0xFF000000u);
  auto choice = tb::ChooseBand(votes, std::optional<uint32_t>(), false);
  PARC_EXPECT(choice.color == 0xFF000000u && !choice.sample_frame);
  Votes canvas;
  canvas.ForColor(1, 0xFF112233u);
  canvas.ForCanvas();
  PARC_EXPECT(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFF112233u);
  canvas.ForCanvas();
  PARC_EXPECT(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFFFFFFFFu);
  Votes transparent;
  transparent.ForCanvas();
  transparent.ForCanvas();
  auto none = tb::ChooseBand(transparent, std::optional<uint32_t>(), true);
  PARC_EXPECT(!none.color && !none.sample_frame && none.reuse_frame_sample);
  Votes frame;
  frame.ForFrameSample(5, 3);
  frame.ForCanvas();
  frame.ForCanvas();
  frame.ForCanvas();
  auto sampled = tb::ChooseBand(frame, std::optional<uint32_t>(0xFFFFFFFFu), true);
  PARC_EXPECT(sampled.sample_frame && sampled.frame_sample_id == 3 && !sampled.color &&
         !sampled.reuse_frame_sample);
  Votes reuse;
  reuse.ForColor(4, 0xFF333333u);
  auto kept = tb::ChooseBand(reuse, std::optional<uint32_t>(), true);
  PARC_EXPECT(kept.color == 0xFF333333u && kept.reuse_frame_sample);
  Votes many;
  for (int key = 0; key < 5; ++key) {
    many.ForColor(key, 0xFF000000u + key);
  }
  PARC_EXPECT(many.Winner()->key == 0);
}

void Delivery() {
  using D = tb::FrameSampleDelivery;
  D delivery;
  auto a = delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  PARC_EXPECT(a.deliver && a.deliver->color == 0xFF000000u && !a.copy);
  PARC_EXPECT(!delivery.OnRendererSample(0xFF000000u, false, 0, false, true).deliver);
  auto none = delivery.OnRendererSample(std::nullopt, false, 0, false, true);
  PARC_EXPECT(none.deliver && !none.deliver->color && none.deliver->crossfade);

  auto copy = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  PARC_EXPECT(!copy.deliver && copy.copy == 1);
  PARC_EXPECT(!delivery.OnRendererSample(std::nullopt, true, 1, false, false).copy);
  PARC_EXPECT(!delivery.OnFrameSample(2, 0xFF111111u).deliver);
  auto sampled = delivery.OnFrameSample(1, 0xFF336699u);
  PARC_EXPECT(sampled.deliver && sampled.deliver->color == 0xFF336699u);
  PARC_EXPECT(!sampled.deliver->crossfade);
  auto reused = delivery.OnRendererSample(0xFFFFFFFFu, false, 0, false, false);
  PARC_EXPECT(reused.deliver && reused.deliver->color == 0xFFFFFFFFu);
  auto cached = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  PARC_EXPECT(cached.deliver && cached.deliver->color == 0xFF336699u && !cached.copy);
  delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  auto reuse = delivery.OnRendererSample(0xFF000000u, false, 0, true, false);
  PARC_EXPECT(reuse.deliver && reuse.deliver->color == 0xFF336699u);

  auto first = delivery.OnRendererSample(std::nullopt, true, 2, false, false);
  PARC_EXPECT(first.copy == 2);
  PARC_EXPECT(!delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy);
  auto again = delivery.OnFrameSample(2, 0xFF222222u);
  PARC_EXPECT(!again.deliver && again.copy == 3);
  auto third = delivery.OnFrameSample(3, 0xFF333333u);
  PARC_EXPECT(third.deliver && third.deliver->color == 0xFF333333u);

  auto blocked = delivery.OnRendererSample(std::nullopt, true, 4, false, false);
  PARC_EXPECT(blocked.copy == 4);
  delivery.CopyUnavailable();
  PARC_EXPECT(delivery.OnRendererSample(std::nullopt, true, 4, false, false).copy == 4);

  delivery.Reset();
  auto fresh = delivery.OnRendererSample(0xFF333333u, false, 0, false, false);
  PARC_EXPECT(fresh.deliver && fresh.deliver->color == 0xFF333333u);
  PARC_EXPECT(delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy == 3);
}

}

int main() {
  Sampling();
  BandGeometry();
  PixelSources();
  PixelMemory();
  CacheHosts();
  VotesAndChoice();
  Delivery();
  std::cout << "Passed top-band sampling, band geometry, pixel sources and "
               "memory, cache hosts, votes and choice, and frame-sample "
               "delivery rules; no browser execution.\n";
}

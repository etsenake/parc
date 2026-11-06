// Checks the header-only top-band rules (Engine/ParcRenderer/
//
// 1.170. No Chromium, browser or renderer.
#include <cassert>
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
  // Uniform: the exact colour, alpha included.
  assert(Bitmap(100, 20, 0xFF1A73E8u).Sample() == 0xFF1A73E8u);
  assert(Bitmap(100, 20, 0x801A73E8u).Sample() == 0x801A73E8u);
  // Empty bitmaps have no colour.
  assert(!tb::SampleBand(0, 5, 8, 24, [](int, int) { return 0u; }));
  assert(!tb::SampleBand(5, 0, 8, 24, [](int, int) { return 0u; }));

  // Columns: x = i/4 of (width - 24), so a 124-wide band reads 0, 25, 50, 75
  // and 100; the right 24 px never count.
  Bitmap margin(124, 10, 0xFF000000u);
  for (int y = 0; y < 10; ++y) {
    for (int x = 101; x < 124; ++x) {
      margin.Set(x, y, 0xFFFFFFFFu);
    }
  }
  assert(margin.Sample() == 0xFF000000u);
  margin.Set(100, 0, 0xFF0A0A0Au);
  // A small spread averages row 0: 4 * 0 + 10 over 5 rounds to 2.
  assert(margin.Sample() == 0xFF020202u);

  // The lower row is min(8, h) - 1: row 7 of a tall band, the last of a short.
  Bitmap lower(124, 20, 0xFF000000u);
  lower.Set(0, 8, 0xFFFFFFFFu);
  assert(lower.Sample() == 0xFF000000u);
  lower.Set(0, 7, 0xFFFFFFFFu);
  assert(!lower.Sample());  // spread sqrt(3) > 0.5
  Bitmap short_band(124, 3, 0xFF000000u);
  short_band.Set(100, 2, 0xFF808080u);  // distance 0.87 at the right column
  assert(!short_band.Sample());

  // Spread exactly at and above 0.5 (distance in RGB, alpha ignored).
  Bitmap spread(124, 10, 0xFF000000u);
  spread.Set(50, 0, 0xFF800000u);  // 128/255 = 0.502
  assert(!spread.Sample());
  spread.Set(50, 0, 0xFF7F0000u);  // 127/255 = 0.498
  assert(spread.Sample() == 0xFF190000u);  // 127 / 5 = 25.4 -> 25
  spread.Set(50, 0, 0x007F0000u);  // alpha averages too: 4*255/5 = 204
  assert(spread.Sample() == 0xCC190000u);

  // Device scale: the browser's 8 DIP band and 24 DIP margin at 2x.
  Bitmap retina(248, 16, 0xFF202020u);
  for (int x = 201; x < 248; ++x) {
    retina.Set(x, 0, 0xFFFFFFFFu);
  }
  assert(retina.Sample(16, 48) == 0xFF202020u);
  assert(!retina.Sample(16, 24));
}

void BandGeometry() {
  // At least 11 px tall and a third of the viewport wide, reaching an edge.
  assert(tb::SpansBand(0, 300, 11, 900));
  assert(!tb::SpansBand(0, 300, 10, 900));
  assert(!tb::SpansBand(0, 299, 40, 900));
  assert(tb::SpansBand(-20, 400, 40, 900));
  assert(tb::SpansBand(600, 300, 40, 900));
  assert(!tb::SpansBand(1, 898, 40, 900));
  assert(!tb::SpansBand(100, 700, 40, 900));
  assert(tb::SampleColumn(0, 1001) == 0);
  assert(tb::SampleColumn(3, 1001) == 750);
}

// An element's key from its image's identity and load state.
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
  assert(image(&first, false) == image(&first, false));
  assert(image(&first, false) != image(&first, true));
  assert(image(&first, true) != image(&second, true));
  // Layers fold in order.
  tb::PixelSource forward, backward;
  forward.AddImage(&first, true);
  forward.AddImage(&second, true);
  backward.AddImage(&second, true);
  backward.AddImage(&first, true);
  assert(forward.value() != backward.value());
  // A generated layer changes with its value, raster size and style inputs.
  auto generated = [](uint32_t value, int width, uint32_t color, int scheme,
                      float zoom) {
    tb::PixelSource source;
    source.AddGenerated(value, width, 120, color, scheme, zoom);
    return source.value();
  };
  const uint64_t base = generated(0xabc, 800, 0xFF000000u, 0, 1);
  assert(base == generated(0xabc, 800, 0xFF000000u, 0, 1));
  assert(base != generated(0xabd, 800, 0xFF000000u, 0, 1));
  assert(base != generated(0xabc, 640, 0xFF000000u, 0, 1));
  assert(base != generated(0xabc, 800, 0xFFFFFFFFu, 0, 1));
  assert(base != generated(0xabc, 800, 0xFF000000u, 1, 1));
  assert(base != generated(0xabc, 800, 0xFF000000u, 0, 2));
}

void CacheHosts() {
  assert(tb::CacheHost("https", "chatgpt.com") == "chatgpt.com");
  assert(tb::CacheHost("http", "example.com") == "example.com");
  assert(tb::CacheHost("chrome-distiller", "3f2a_9c1d").empty());
  assert(tb::CacheHost("chrome", "settings").empty());
  assert(tb::CacheHost("chrome-extension", "abcdefghijklmnop").empty());
  assert(tb::CacheHost("parc", "newtab").empty());
  assert(tb::CacheHost("file", "").empty());
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
  // One pass reads a failing element once, however many points hit it.
  memory.BeginPass();
  for (int point = 0; point < 4; ++point) {
    assert(!memory.Color(failing, 1'000'000, fail));
  }
  assert(decodes == 1);
  // Later detections within 1.5 s do not decode it again.
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    assert(!memory.Color(failing, 1'000'000 + pass * 100'000, fail));
  }
  assert(decodes == 1);
  // After the window it is read again, once.
  memory.BeginPass();
  memory.Color(failing, 2'500'001, fail);
  memory.Color(failing, 2'500'001, fail);
  assert(decodes == 2);
  // A load transition is one new read; a restyle isn't. An image still
  // loading gives no colour and keeps its key however often the element is
  // restyled; once it finishes it is read on the next detection, once, and a
  // finished image that still gives no colour stays remembered.
  int late = 0;
  const auto loading = ImageKey(8, &late, false);
  const auto loaded = ImageKey(8, &late, true);
  const int before_load = decodes;
  for (int pass = 0; pass < 5; ++pass) {
    memory.BeginPass();
    memory.Color(loading, 2'500'100 + pass * 100'000, fail);
  }
  assert(decodes == before_load + 1);
  memory.BeginPass();
  memory.Color(loaded, 3'000'000, fail);
  memory.Color(loaded, 3'000'000, fail);
  assert(decodes == before_load + 2);
  for (int pass = 1; pass <= 14; ++pass) {
    memory.BeginPass();
    memory.Color(loaded, 3'000'000 + pass * 100'000, fail);
  }
  assert(decodes == before_load + 2);
  // A finished image with a colour is read when it finishes.
  int painted = 0;
  int load_reads = 0;
  auto ready = [&load_reads] {
    ++load_reads;
    return std::optional<uint32_t>(0xFF202124u);
  };
  memory.BeginPass();
  memory.Color(ImageKey(10, &painted, false), 3'100'000, fail);
  memory.BeginPass();
  assert(memory.Color(ImageKey(10, &painted, true), 3'200'000, ready) ==
         0xFF202124u);
  assert(load_reads == 1);
  // A failing element takes one slot however often it fails, so as many
  // failing elements as slots are each remembered.
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
  assert(decodes == after_others);
  // A colour is read once per pass and again in the next.
  int reads = 0;
  auto blue = [&reads] {
    ++reads;
    return std::optional<uint32_t>(0xFF1A73E8u);
  };
  memory.BeginPass();
  assert(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  assert(memory.Color({9, 1}, 5'200'000, blue) == 0xFF1A73E8u);
  assert(reads == 1);
  memory.BeginPass();
  memory.Color({9, 1}, 5'200'001, blue);
  assert(reads == 2);
  // A new document or contentful paint forgets the failures.
  memory.Forget();
  memory.BeginPass();
  memory.Color(failing, 5'300'000, fail);
  assert(decodes == after_others + 1);
}

void VotesAndChoice() {
  using Votes = tb::BandVotes<int, uint32_t>;
  // The element with most votes wins; the first one voted for on a tie.
  Votes votes;
  votes.ForColor(1, 0xFF000000u);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(2, 0xFFFFFFFFu);
  votes.ForColor(1, 0xFF000000u);
  auto choice = tb::ChooseBand(votes, std::optional<uint32_t>(), false);
  assert(choice.color == 0xFF000000u && !choice.sample_frame);
  // The opaque canvas wins only with more votes than the best element.
  Votes canvas;
  canvas.ForColor(1, 0xFF112233u);
  canvas.ForCanvas();
  assert(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFF112233u);
  canvas.ForCanvas();
  assert(tb::ChooseBand(canvas, std::optional<uint32_t>(0xFFFFFFFFu), false).color == 0xFFFFFFFFu);
  // Without an opaque canvas its points count for nothing.
  Votes transparent;
  transparent.ForCanvas();
  transparent.ForCanvas();
  auto none = tb::ChooseBand(transparent, std::optional<uint32_t>(), true);
  assert(!none.color && !none.sample_frame && none.reuse_frame_sample);
  // A frame-sample winner beats the canvas and drops the reuse flag.
  Votes frame;
  frame.ForFrameSample(5, 3);
  frame.ForCanvas();
  frame.ForCanvas();
  frame.ForCanvas();
  auto sampled = tb::ChooseBand(frame, std::optional<uint32_t>(0xFFFFFFFFu), true);
  assert(sampled.sample_frame && sampled.frame_sample_id == 3 && !sampled.color &&
         !sampled.reuse_frame_sample);
  // A colour winner keeps the reuse flag for the browser.
  Votes reuse;
  reuse.ForColor(4, 0xFF333333u);
  auto kept = tb::ChooseBand(reuse, std::optional<uint32_t>(), true);
  assert(kept.color == 0xFF333333u && kept.reuse_frame_sample);
  // Four points vote at most four keys; a fifth is ignored safely.
  Votes many;
  for (int key = 0; key < 5; ++key) {
    many.ForColor(key, 0xFF000000u + key);
  }
  assert(many.Winner()->key == 0);
}

void Delivery() {
  using D = tb::FrameSampleDelivery;
  D delivery;
  // A colour is delivered once; a repeat is not.
  auto a = delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  assert(a.deliver && a.deliver->color == 0xFF000000u && !a.copy);
  assert(!delivery.OnRendererSample(0xFF000000u, false, 0, false, true).deliver);
  // No colour is a delivery of its own.
  auto none = delivery.OnRendererSample(std::nullopt, false, 0, false, true);
  assert(none.deliver && !none.deliver->color && none.deliver->crossfade);

  // A frame sample copies once, caches by id and keeps its crossfade.
  auto copy = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  assert(!copy.deliver && copy.copy == 1);
  assert(!delivery.OnRendererSample(std::nullopt, true, 1, false, false).copy);
  assert(!delivery.OnFrameSample(2, 0xFF111111u).deliver);
  auto sampled = delivery.OnFrameSample(1, 0xFF336699u);
  assert(sampled.deliver && sampled.deliver->color == 0xFF336699u);
  assert(!sampled.deliver->crossfade);  // the latest request's flag
  // The same id again reuses the cached frame colour without copying.
  auto reused = delivery.OnRendererSample(0xFFFFFFFFu, false, 0, false, false);
  assert(reused.deliver && reused.deliver->color == 0xFFFFFFFFu);
  auto cached = delivery.OnRendererSample(std::nullopt, true, 1, false, true);
  assert(cached.deliver && cached.deliver->color == 0xFF336699u && !cached.copy);
  // `reuse_frame_sample` replaces the renderer's colour with the cached one.
  delivery.OnRendererSample(0xFF000000u, false, 0, false, false);
  auto reuse = delivery.OnRendererSample(0xFF000000u, false, 0, true, false);
  assert(reuse.deliver && reuse.deliver->color == 0xFF336699u);

  // A newer id while a copy is in flight waits for it, then copies again.
  auto first = delivery.OnRendererSample(std::nullopt, true, 2, false, false);
  assert(first.copy == 2);
  assert(!delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy);
  auto again = delivery.OnFrameSample(2, 0xFF222222u);
  assert(!again.deliver && again.copy == 3);
  auto third = delivery.OnFrameSample(3, 0xFF333333u);
  assert(third.deliver && third.deliver->color == 0xFF333333u);

  // A copy that cannot start stays pending for the next message.
  auto blocked = delivery.OnRendererSample(std::nullopt, true, 4, false, false);
  assert(blocked.copy == 4);
  delivery.CopyUnavailable();
  assert(delivery.OnRendererSample(std::nullopt, true, 4, false, false).copy == 4);

  // A new document forgets everything.
  delivery.Reset();
  auto fresh = delivery.OnRendererSample(0xFF333333u, false, 0, false, false);
  assert(fresh.deliver && fresh.deliver->color == 0xFF333333u);
  assert(delivery.OnRendererSample(std::nullopt, true, 3, false, false).copy == 3);
}

}  // namespace

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

#pragma once

#import "ParcNativeTest.h"
#include <cstdint>
#include <optional>
#include <vector>

#include "top_band_color_sampling.h"

namespace tb = parc::top_band;

namespace TopBandColorTestsSupport {

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

inline tb::PixelSampleMemory::Key ImageKey(int64_t node, const void* image, bool loaded) {
  tb::PixelSource source;
  source.AddImage(image, loaded);
  return {node, source.value()};
}
inline uint64_t Generated(uint32_t value, int width, uint32_t color, int scheme, float zoom) {
  tb::PixelSource source;
  source.AddGenerated(value, width, 120, color, scheme, zoom);
  return source.value();
}
using Votes = tb::BandVotes<int, uint32_t>;
}

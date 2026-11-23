// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_
#define PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

namespace parc {

enum class PageCapturePurpose { kPerson, kPlaceholder };

struct PageCaptureWindow {
  bool app_active = false;
  bool visible = false;
  bool miniaturized = false;
  bool key = false;
  bool attached_sheet = false;
  bool security_reservation = false;
};

constexpr bool PageCaptureNeedsKeyWindow(PageCapturePurpose purpose) {
  return purpose == PageCapturePurpose::kPerson;
}

constexpr bool PageCaptureViewportOnly(PageCapturePurpose purpose) {
  return purpose == PageCapturePurpose::kPlaceholder;
}

constexpr bool PageCaptureWindowAdmits(const PageCaptureWindow& window,
                                       bool require_key) {
  return window.app_active && window.visible && !window.miniaturized &&
         (window.key || !require_key) && !window.attached_sheet &&
         !window.security_reservation;
}

inline constexpr int kPageCaptureMaxSide = 16384;
inline constexpr int64_t kPageCaptureMaxPixels = 80000000;
inline constexpr int kPageCaptureMaxFrames = 64;

struct PageCaptureGeometry {
  int frame_width = 0;
  int frame_height = 0;
  double scale = 1;
  double area_left = 0;
  double area_top = 0;
  double area_right = 0;
  double area_bottom = 0;
  double top_bar = 0;
  double bottom_bar = 0;
  double content_height = 0;
  double client_height = 0;
  int max_side = kPageCaptureMaxSide;
  int64_t max_pixels = kPageCaptureMaxPixels;
};

struct PageCaptureSlice {
  int left = 0;
  int width = 0;
  int source_y = 0;
  int dest_y = 0;
  int height = 0;
  friend bool operator==(const PageCaptureSlice&,
                         const PageCaptureSlice&) = default;
};

struct PageCaptureBands {
  int width = 0;
  int height = 0;
  int left = 0;
  int right = 0;
  int area_top = 0;
  int top = 0;
  int bottom = 0;
  int max_shift = 0;
  int output_height = 0;
  double max_offset = 0;
  bool scrolls = false;
};

struct PageCaptureStep {
  std::vector<PageCaptureSlice> slices;
  std::vector<PageCaptureSlice> fills;
  int covered = 0;
  std::optional<double> next_offset;
  std::optional<double> retry_offset;
};

struct PageCaptureFrame {
  double offset = 0;
  std::vector<PageCaptureSlice> slices;
};

struct PageCapturePlan {
  int width = 0;
  int height = 0;
  std::vector<PageCaptureFrame> frames;
  std::vector<PageCaptureSlice> fills;
};

inline int PageCapturePixels(double value, double scale) {
  const double pixels = value * scale;
  if (!std::isfinite(pixels)) {
    return 0;
  }
  return static_cast<int>(std::lround(std::clamp(pixels, -1e9, 1e9)));
}

inline PageCaptureBands PageCaptureBandsFor(const PageCaptureGeometry& g) {
  PageCaptureBands b;
  if (g.frame_width <= 0 || g.frame_height <= 0 || !std::isfinite(g.scale) ||
      g.scale <= 0 || g.max_side <= 0 || g.max_pixels <= 0) {
    return b;
  }
  b.width = g.frame_width;
  b.height = g.frame_height;
  b.area_top = std::clamp(PageCapturePixels(g.area_top, g.scale), 0, b.height);
  const int area_bottom = std::clamp(PageCapturePixels(g.area_bottom, g.scale),
                                     b.area_top, b.height);
  b.left = std::clamp(PageCapturePixels(g.area_left, g.scale), 0, b.width);
  b.right =
      std::clamp(PageCapturePixels(g.area_right, g.scale), b.left, b.width);
  int top_bar = std::max(0, PageCapturePixels(g.top_bar, g.scale));
  int bottom_bar = std::max(0, PageCapturePixels(g.bottom_bar, g.scale));
  const int least_band = std::max(1, b.height / 8);
  if (area_bottom - bottom_bar - (b.area_top + top_bar) < least_band) {
    top_bar = 0;
    bottom_bar = 0;
  }
  b.top = b.area_top + top_bar;
  b.bottom = area_bottom - bottom_bar;
  const double max_offset = g.content_height - g.client_height;
  b.max_offset = std::isfinite(max_offset) && max_offset > 0 ? max_offset : 0;
  b.max_shift = std::max(0, PageCapturePixels(b.max_offset, g.scale));
  b.scrolls =
      b.max_shift > 0 && b.bottom - b.top >= least_band && b.right > b.left;
  const int64_t cap = std::min<int64_t>(g.max_side, g.max_pixels / b.width);
  const int64_t full =
      static_cast<int64_t>(b.height) + (b.scrolls ? b.max_shift : 0);
  b.output_height = static_cast<int>(std::max<int64_t>(0, std::min(full, cap)));
  return b;
}

inline double PageCaptureOffsetFor(const PageCaptureBands& b,
                                   double scale,
                                   int shift) {
  if (shift >= b.max_shift) {
    return b.max_offset;
  }
  return std::max(0.0, std::floor(shift / scale));
}

inline void PageCaptureAddSlice(std::vector<PageCaptureSlice>& slices,
                                const PageCaptureBands& b,
                                int left,
                                int right,
                                int from,
                                int to,
                                int shift) {
  from = std::max({from, 0, -shift});
  to = std::min({to, b.height, b.output_height - shift});
  if (to <= from || right <= left) {
    return;
  }
  slices.push_back({left, right - left, from, from + shift, to - from});
}

inline std::vector<PageCaptureSlice> PageCaptureFills(const PageCaptureBands& b,
                                                      int end) {
  std::vector<PageCaptureSlice> fills;
  const int stop = std::min(end, b.output_height);
  if (!b.scrolls || b.bottom <= 0 || stop <= b.bottom) {
    return fills;
  }
  if (b.left > 0) {
    fills.push_back({0, b.left, b.bottom - 1, b.bottom, stop - b.bottom});
  }
  if (b.right < b.width) {
    fills.push_back({b.right, b.width - b.right, b.bottom - 1, b.bottom,
                     stop - b.bottom});
  }
  return fills;
}

inline PageCaptureStep PageCaptureTakeFrame(const PageCaptureGeometry& g,
                                            int covered,
                                            double reached,
                                            bool first,
                                            bool may_retry) {
  PageCaptureStep step;
  step.covered = covered;
  const PageCaptureBands b = PageCaptureBandsFor(g);
  if (b.output_height <= 0) {
    return step;
  }
  if (!b.scrolls) {
    PageCaptureAddSlice(step.slices, b, 0, b.width, 0, b.height, 0);
    step.covered = std::min(b.height, b.output_height);
    return step;
  }
  const int shift = PageCapturePixels(reached, g.scale);
  if (first) {
    if (shift != 0 && may_retry) {
      step.retry_offset = 0;
      return step;
    }
    if (shift == 0) {
      PageCaptureAddSlice(step.slices, b, 0, b.width, 0, b.bottom, 0);
    } else {
      PageCaptureAddSlice(step.slices, b, 0, b.width, 0, b.top, 0);
      PageCaptureAddSlice(step.slices, b, 0, b.left, b.top, b.bottom, 0);
      PageCaptureAddSlice(step.slices, b, b.left, b.right, b.top, b.bottom,
                          shift);
      PageCaptureAddSlice(step.slices, b, b.right, b.width, b.top, b.bottom, 0);
    }
    step.covered = std::min(b.bottom + std::max(shift, 0), b.output_height);
  } else {
    int from = covered - shift;
    if (from < b.top) {
      if (b.top - from > 1 && may_retry) {
        step.retry_offset = PageCaptureOffsetFor(b, g.scale, covered - b.top);
        return step;
      }
      from = b.top - from > 1 ? std::max(from, b.area_top) : b.top;
    }
    const bool last = shift + 1 >= b.max_shift || b.bottom + shift <= covered;
    PageCaptureAddSlice(step.slices, b, b.left, b.right, from, b.bottom, shift);
    step.covered =
        std::max(covered, std::min(b.bottom + shift, b.output_height));
    if (last) {
      const int bottom_from = std::max(b.bottom, covered - shift);
      PageCaptureAddSlice(step.slices, b, 0, b.width, bottom_from, b.height,
                          shift);
      step.fills = PageCaptureFills(b, bottom_from + shift);
      step.covered =
          std::max(step.covered, std::min(b.height + shift, b.output_height));
      return step;
    }
  }
  if (step.covered >= b.output_height) {
    step.fills = PageCaptureFills(b, step.covered);
    return step;
  }
  step.next_offset = PageCaptureOffsetFor(b, g.scale, step.covered - b.top);
  return step;
}

inline PageCapturePlan PlanPageCapture(const PageCaptureGeometry& g) {
  PageCapturePlan plan;
  const PageCaptureBands b = PageCaptureBandsFor(g);
  plan.width = b.width;
  double offset = 0;
  int covered = 0;
  bool pending = false;
  for (int frame = 0; frame < kPageCaptureMaxFrames; ++frame) {
    PageCaptureStep step =
        PageCaptureTakeFrame(g, covered, offset, frame == 0, false);
    plan.frames.push_back({offset, std::move(step.slices)});
    covered = step.covered;
    plan.fills = std::move(step.fills);
    pending = step.next_offset.has_value();
    if (!pending) {
      break;
    }
    offset = *step.next_offset;
  }
  if (pending) {
    plan.fills = PageCaptureFills(b, covered);
  }
  plan.height = covered;
  return plan;
}

}

#endif

// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_HOLD_H_
#define PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_HOLD_H_

#include <algorithm>
#include <cstddef>
#include <optional>
#include <utility>
#include <vector>

namespace parc {

inline constexpr int kBackgroundPipNormalWindowLayer = 0;

struct BackgroundPipRect {
  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;

  bool Empty() const { return !(right > left) || !(bottom > top); }
  double Area() const { return Empty() ? 0 : (right - left) * (bottom - top); }
};

inline BackgroundPipRect BackgroundPipRectFromCocoa(
    double x,
    double y,
    double width,
    double height,
    double primary_screen_height) {
  return {x, primary_screen_height - y - height, x + width,
          primary_screen_height - y};
}

inline BackgroundPipRect BackgroundPipRectFromQuartz(double x,
                                                     double y,
                                                     double width,
                                                     double height) {
  return {x, y, x + width, y + height};
}

inline BackgroundPipRect BackgroundPipIntersection(const BackgroundPipRect& a,
                                                   const BackgroundPipRect& b) {
  const BackgroundPipRect overlap{
      std::max(a.left, b.left), std::max(a.top, b.top),
      std::min(a.right, b.right), std::min(a.bottom, b.bottom)};
  return overlap.Empty() ? BackgroundPipRect{} : overlap;
}

inline double BackgroundPipUnionArea(const std::vector<BackgroundPipRect>& rects) {
  std::vector<double> edges;
  for (const auto& rect : rects) {
    if (!rect.Empty()) {
      edges.push_back(rect.left);
      edges.push_back(rect.right);
    }
  }
  std::ranges::sort(edges);
  edges.erase(std::unique(edges.begin(), edges.end()), edges.end());
  double area = 0;
  std::vector<std::pair<double, double>> spans;
  for (size_t index = 0; index + 1 < edges.size(); ++index) {
    const double left = edges[index];
    const double right = edges[index + 1];
    spans.clear();
    for (const auto& rect : rects) {
      if (!rect.Empty() && rect.left <= left && rect.right >= right) {
        spans.emplace_back(rect.top, rect.bottom);
      }
    }
    std::ranges::sort(spans);
    double covered = 0;
    std::optional<std::pair<double, double>> run;
    for (const auto& [top, bottom] : spans) {
      if (run && top <= run->second) {
        run->second = std::max(run->second, bottom);
        continue;
      }
      if (run) {
        covered += run->second - run->first;
      }
      run = std::pair(top, bottom);
    }
    if (run) {
      covered += run->second - run->first;
    }
    area += covered * (right - left);
  }
  return area;
}

inline double BackgroundPipVisibleArea(
    const BackgroundPipRect& page,
    const std::vector<BackgroundPipRect>& screens,
    const std::optional<std::vector<BackgroundPipRect>>& covers) {
  std::vector<BackgroundPipRect> on_screen;
  for (const auto& screen : screens) {
    const auto piece = BackgroundPipIntersection(page, screen);
    if (!piece.Empty()) {
      on_screen.push_back(piece);
    }
  }
  const double shown = BackgroundPipUnionArea(on_screen);
  if (!covers) {
    return shown;
  }
  std::vector<BackgroundPipRect> hidden;
  for (const auto& piece : on_screen) {
    for (const auto& cover : *covers) {
      const auto overlap = BackgroundPipIntersection(piece, cover);
      if (!overlap.Empty()) {
        hidden.push_back(overlap);
      }
    }
  }
  return std::max(0.0, shown - BackgroundPipUnionArea(hidden));
}

struct BackgroundPipWindowRecord {
  std::optional<int> layer;
  std::optional<double> alpha;
  std::optional<BackgroundPipRect> bounds;
};

inline std::optional<std::vector<BackgroundPipRect>> BackgroundPipCoveringWindows(
    const std::optional<std::vector<BackgroundPipWindowRecord>>& records) {
  if (!records) {
    return std::nullopt;
  }
  std::vector<BackgroundPipRect> covers;
  for (const auto& record : *records) {
    if (!record.layer) {
      return std::nullopt;
    }
    if (*record.layer != kBackgroundPipNormalWindowLayer ||
        (record.alpha && !(*record.alpha > 0))) {
      continue;
    }
    if (!record.bounds) {
      return std::nullopt;
    }
    covers.push_back(*record.bounds);
  }
  return covers;
}

struct BackgroundPipHoldGate {
  bool app_active = true;
  bool page_shown = false;
  bool window_visible = false;
  bool displays_asleep = false;
  bool screen_locked = false;
  bool picture_in_picture_open = false;
};

inline bool BackgroundPipHoldGateOpen(const BackgroundPipHoldGate& gate) {
  return !gate.app_active && gate.page_shown && gate.window_visible &&
         !gate.displays_asleep && !gate.screen_locked &&
         !gate.picture_in_picture_open;
}

enum class BackgroundPipHoldPass {
  kResign,
  kRecheck,
};

inline bool ShouldHoldBackgroundPip(
    BackgroundPipHoldPass pass,
    bool held,
    const BackgroundPipHoldGate& gate,
    const BackgroundPipRect& page,
    const std::vector<BackgroundPipRect>& screens,
    const std::optional<std::vector<BackgroundPipRect>>& covers) {
  if ((pass == BackgroundPipHoldPass::kRecheck && !held) ||
      !BackgroundPipHoldGateOpen(gate)) {
    return false;
  }
  const double area = page.Area();
  return area > 0 && BackgroundPipVisibleArea(page, screens, covers) * 2 >= area;
}

}

#endif

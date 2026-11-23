// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_
#define PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_

#include <algorithm>
#include <cmath>

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

inline constexpr double kFullPageMaxSide = 16384;
inline constexpr double kFullPageMaxPixels = 80000000;

inline double FullPageScale(double width, double height, double density) {
  if (!std::isfinite(width) || !std::isfinite(height) ||
      !std::isfinite(density) || width < 1 || height < 1 || density <= 0) {
    return 0;
  }
  const double device_width = width * density;
  const double device_height = height * density;
  const double scale = std::min(
      {1.0, (kFullPageMaxSide - 1) / device_width,
       (kFullPageMaxSide - 1) / device_height,
       std::sqrt(kFullPageMaxPixels * 0.999 / (device_width * device_height))});
  return std::ceil(device_width * scale) >= 1 &&
                 std::ceil(device_height * scale) >= 1
             ? scale
             : 0;
}

}

#endif

// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_
#define PARC_NATIVE_NATIVE_PAGE_CAPTURE_H_

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

}

#endif

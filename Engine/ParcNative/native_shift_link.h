// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SHIFT_LINK_H_
#define PARC_NATIVE_NATIVE_SHIFT_LINK_H_
#import <AppKit/AppKit.h>
#import "status_text.h"

namespace parc {
enum class NativeShiftLink { kOrdinary, kPeek, kSamePeek };

struct NativeShiftLinkClick {
  NSEventModifierFlags modifiers = 0;
  bool shift_peek_enabled = false;
  bool in_shown_peek = false;
  bool frame_can_navigate_page = true;
  bool can_open_peek = false;
};

inline bool NativeFrameCanNavigatePage(bool main_frame, bool top_navigation_sandboxed,
                                       bool user_activation_top_navigation_sandboxed) {
  return main_frame || !top_navigation_sandboxed || !user_activation_top_navigation_sandboxed;
}

inline NativeShiftLink ClassifyNativeShiftLink(const NativeShiftLinkClick& click) {
  constexpr NSEventModifierFlags relevant = NSEventModifierFlagShift |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
  if ((click.modifiers & relevant) != NSEventModifierFlagShift || !click.shift_peek_enabled)
    return NativeShiftLink::kOrdinary;
  if (click.in_shown_peek)
    return click.frame_can_navigate_page ? NativeShiftLink::kSamePeek : NativeShiftLink::kOrdinary;
  return click.can_open_peek ? NativeShiftLink::kPeek : NativeShiftLink::kOrdinary;
}

struct NativeShiftCreatedPage {
  NativeShiftLinkClick click;
  bool user_gesture = false;
  bool web_url = false;
  bool new_window = false;
  bool popup = false;
  bool sized_by_page = false;
};

inline bool NativeShiftCreatedPageOpensPeek(const NativeShiftCreatedPage& page) {
  return page.user_gesture && page.web_url && page.new_window && !page.popup &&
      !page.sized_by_page && ClassifyNativeShiftLink(page.click) == NativeShiftLink::kPeek;
}

inline PCNativeStatusLinkOutcome NativeShiftLinkOutcome(NativeShiftLink link) {
  switch (link) {
    case NativeShiftLink::kPeek: return PCNativeStatusLinkOutcomePeek;
    case NativeShiftLink::kSamePeek: return PCNativeStatusLinkOutcomeThisPeek;
    case NativeShiftLink::kOrdinary: return PCNativeStatusLinkOutcomeNewWindow;
  }
  return PCNativeStatusLinkOutcomeNewWindow;
}
}
#endif

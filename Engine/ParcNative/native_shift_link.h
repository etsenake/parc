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
  bool sends_body = false;
};

inline bool NativeFrameCanNavigatePage(bool main_frame, bool top_navigation_sandboxed,
                                       bool user_activation_top_navigation_sandboxed) {
  return main_frame || !top_navigation_sandboxed || !user_activation_top_navigation_sandboxed;
}

inline bool NativeShiftHeld(NSEventModifierFlags modifiers) {
  constexpr NSEventModifierFlags relevant = NSEventModifierFlagShift |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
  return (modifiers & relevant) == NSEventModifierFlagShift;
}

inline NativeShiftLink ClassifyNativeShiftLink(const NativeShiftLinkClick& click) {
  if (!NativeShiftHeld(click.modifiers) || !click.shift_peek_enabled || click.sends_body)
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
  bool foreground_tab = false;
  bool popup = false;
  bool sized_by_page = false;
  bool fenced_frame = false;
};

inline NativeShiftLink ClassifyNativeShiftCreatedPage(const NativeShiftCreatedPage& page) {
  if (!page.user_gesture || !page.web_url || !(page.new_window || page.foreground_tab) ||
      page.popup || page.sized_by_page || page.fenced_frame)
    return NativeShiftLink::kOrdinary;
  return ClassifyNativeShiftLink(page.click);
}

enum class NativeCreatedPageRoute { kNone, kShift, kAutomatic };

inline NativeCreatedPageRoute ChooseNativeCreatedPageRoute(NSEventModifierFlags modifiers,
                                                           bool meeting,
                                                           bool main_frame_opener) {
  if (NativeShiftHeld(modifiers)) return NativeCreatedPageRoute::kShift;
  if ((modifiers & NSEventModifierFlagCommand) || meeting || !main_frame_opener)
    return NativeCreatedPageRoute::kNone;
  return NativeCreatedPageRoute::kAutomatic;
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

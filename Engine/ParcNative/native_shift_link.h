// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SHIFT_LINK_H_
#define PARC_NATIVE_NATIVE_SHIFT_LINK_H_
#import <AppKit/AppKit.h>
#include <string>
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

inline bool NativeShiftHeld(NSEventModifierFlags modifiers) {
  constexpr NSEventModifierFlags relevant = NSEventModifierFlagShift |
      NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
  return (modifiers & relevant) == NSEventModifierFlagShift;
}

inline NativeShiftLink ClassifyNativeShiftLink(const NativeShiftLinkClick& click) {
  if (!NativeShiftHeld(click.modifiers) || !click.shift_peek_enabled)
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

template <typename Params, typename Disposition>
void RetargetNativeShiftLink(Params& params, NativeShiftLink link, Disposition current_tab,
                             Disposition foreground_tab) {
  if (link == NativeShiftLink::kSamePeek) {
    params.disposition = current_tab;
    params.frame_tree_node_id = {};
  } else if (link == NativeShiftLink::kPeek) {
    params.disposition = foreground_tab;
  }
}

struct NativeHeldShiftNavigation {
  bool web_url = false;
  bool from_opener = false;
  bool post = false;
  bool has_body = false;
  bool peek_takes_link = false;
};

inline bool NativeHeldShiftNavigationJoinsPeek(const NativeHeldShiftNavigation& navigation) {
  return navigation.web_url && navigation.from_opener && navigation.peek_takes_link &&
      (!navigation.post || navigation.has_body);
}

template <typename Params, typename Referrer, typename Body>
void CarryNativeShiftRequest(Params& params, const Referrer& referrer, const Body& body,
                             const std::string& content_type) {
  params.referrer = referrer;
  params.post_data = body;
  if (body && !content_type.empty()) params.extra_headers = "Content-Type: " + content_type;
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

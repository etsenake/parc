#pragma once

#import "native_shift_link.h"
#import "ParcNativeTest.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
#include <memory>
#include <string>

using parc::CarryNativeShiftRequest;
using parc::ClassifyNativeShiftLink;
using parc::NativeHeldShiftNavigation;
using parc::NativeHeldShiftNavigationJoinsPeek;
using parc::RetargetNativeShiftLink;
using parc::NativeFrameCanNavigatePage;
using parc::NativeShiftCreatedPage;
using parc::ChooseNativeCreatedPageRoute;
using parc::ClassifyNativeShiftCreatedPage;
using parc::NativeCreatedPageRoute;
using parc::NativeShiftHeld;
using parc::NativeShiftLink;
using parc::NativeShiftLinkClick;
using parc::NativeShiftLinkOutcome;

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace ShiftLinkTestsSupport {
static inline NativeShiftLinkClick Click(NSEventModifierFlags modifiers, bool in_shown_peek) {
  return {.modifiers = modifiers, .shift_peek_enabled = true, .in_shown_peek = in_shown_peek,
          .can_open_peek = !in_shown_peek};
}

constexpr int kCurrentTab = 1;
constexpr int kForegroundTab = 3;
constexpr int kNewWindow = 6;
constexpr char kFormBody[] = "SAMLResponse=PHNhbWw%2BPC9zYW1sPg%3D%3D&RelayState=app";
constexpr char kFormType[] = "application/x-www-form-urlencoded";
constexpr char kFormReferrer[] = "https://portal.example/app/home";

struct Body {
  std::string bytes;
};
struct OpenParams {
  int disposition = kNewWindow;
  int frame_tree_node_id = 7;
  std::shared_ptr<Body> post_data;
  std::string extra_headers;
  std::string referrer;
};

inline OpenParams DirectPost() {
  return {.post_data = std::make_shared<Body>(Body{kFormBody}),
          .extra_headers = std::string("Content-Type: ") + kFormType,
          .referrer = kFormReferrer};
}
inline bool KeepsForm(const OpenParams& params) {
  return params.post_data && params.post_data->bytes == kFormBody &&
      params.extra_headers == std::string("Content-Type: ") + kFormType &&
      params.referrer == kFormReferrer;
}

static constexpr NSEventModifierFlags shift = NSEventModifierFlagShift;

static inline PCNativeStatusLinkOutcome hint(bool in_shown_peek, bool frame_can_navigate_page) {
  auto click = Click(shift, in_shown_peek);
  click.frame_can_navigate_page = frame_can_navigate_page;
  return NativeShiftLinkOutcome(ClassifyNativeShiftLink(click));
}

static inline NativeShiftCreatedPage opened(NSEventModifierFlags modifiers, bool in_shown_peek) {
  return NativeShiftCreatedPage{.click = Click(modifiers, in_shown_peek), .user_gesture = true, .web_url = true,
                                .new_window = true};
}

static inline NativeShiftLink route(const NativeShiftCreatedPage& page) {
  return ClassifyNativeShiftCreatedPage(page);
}

static const NativeHeldShiftNavigation held_post{.web_url = true, .from_opener = true, .post = true,
                                                 .has_body = true, .peek_takes_link = true};

}

#import "native_shift_link.h"
#include "../Support/TestFailure.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

using parc::ClassifyNativeShiftLink;
using parc::NativeFrameCanNavigatePage;
using parc::NativeShiftCreatedPage;
using parc::ChooseNativeCreatedPageRoute;
using parc::ClassifyNativeShiftCreatedPage;
using parc::NativeCreatedPageRoute;
using parc::NativeShiftHeld;
using parc::NativeShiftLink;
using parc::NativeShiftLinkClick;
using parc::NativeShiftLinkOutcome;

static int checks;
static void Check(bool value, const char* message) {
  ++checks;
  if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static NativeShiftLinkClick Click(NSEventModifierFlags modifiers, bool in_shown_peek) {
  return {.modifiers = modifiers, .shift_peek_enabled = true, .in_shown_peek = in_shown_peek,
          .can_open_peek = !in_shown_peek};
}

int main() {
  ParcExitOnUncaughtExceptions();
  constexpr auto shift = NSEventModifierFlagShift;
  Check(ClassifyNativeShiftLink(Click(shift, true)) == NativeShiftLink::kSamePeek,
        "Shift-click inside the shown Peek navigates that Peek");
  Check(ClassifyNativeShiftLink(Click(shift, false)) == NativeShiftLink::kPeek,
        "Shift-click outside a Peek opens a Peek");
  Check(ClassifyNativeShiftLink(Click(shift | NSEventModifierFlagCapsLock, true)) ==
            NativeShiftLink::kSamePeek,
        "Caps Lock does not change the Shift-click");
  for (const bool in_shown_peek : {false, true}) {
    for (const NSEventModifierFlags other : {NSEventModifierFlags(0),
             NSEventModifierFlags(NSEventModifierFlagCommand),
             NSEventModifierFlags(NSEventModifierFlagOption),
             NSEventModifierFlags(NSEventModifierFlagControl),
             NSEventModifierFlags(shift | NSEventModifierFlagCommand),
             NSEventModifierFlags(shift | NSEventModifierFlagOption),
             NSEventModifierFlags(shift | NSEventModifierFlagControl)}) {
      Check(ClassifyNativeShiftLink(Click(other, in_shown_peek)) == NativeShiftLink::kOrdinary,
            "other modifier clicks keep their ordinary route");
    }
    auto disabled = Click(shift, in_shown_peek);
    disabled.shift_peek_enabled = false;
    Check(ClassifyNativeShiftLink(disabled) == NativeShiftLink::kOrdinary,
          "turning off Shift-click Peek restores the ordinary route");
  }

  auto stacked = Click(shift, true);
  stacked.can_open_peek = true;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kSamePeek,
        "a Shift-click inside a Peek never stacks a second Peek");
  stacked.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kOrdinary,
        "an embedded frame sandboxed against navigating the page keeps the ordinary route");
  auto sandboxed = Click(shift, false);
  sandboxed.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(sandboxed) == NativeShiftLink::kPeek,
        "the page-navigation sandbox only matters for the same-Peek navigation");
  auto refused = Click(shift, false);
  refused.can_open_peek = false;
  Check(ClassifyNativeShiftLink(refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek right now keeps the ordinary route");

  Check(NativeFrameCanNavigatePage(true, true, true),
        "the page's own frame can always navigate the page");
  Check(NativeFrameCanNavigatePage(false, false, false),
        "an embedded frame without a sandbox can navigate the page");
  Check(NativeFrameCanNavigatePage(false, true, false),
        "a sandboxed frame allowed to navigate the page on a click can take the click there");
  Check(NativeFrameCanNavigatePage(false, false, true),
        "a sandboxed frame allowed to navigate the page can take the click there");
  Check(!NativeFrameCanNavigatePage(false, true, true),
        "a frame sandboxed against navigating the page cannot take the click there");

  const auto hint = [](bool in_shown_peek, bool frame_can_navigate_page) {
    auto click = Click(shift, in_shown_peek);
    click.frame_can_navigate_page = frame_can_navigate_page;
    return NativeShiftLinkOutcome(ClassifyNativeShiftLink(click));
  };
  Check(hint(true, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomeNewWindow,
        "inside a Peek, the hint over a frame sandboxed against navigating the page says a new window");
  Check(hint(true, NativeFrameCanNavigatePage(false, true, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over a frame allowed to navigate the page on a click says this Peek");
  Check(hint(true, NativeFrameCanNavigatePage(false, false, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over an ordinary embedded frame says this Peek");
  Check(hint(false, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomePeek,
        "outside a Peek, the hint over a sandboxed frame still promises a Peek");

  auto get_form = Click(shift, false);
  Check(ClassifyNativeShiftLink(get_form) == NativeShiftLink::kPeek,
        "a Shift-submitted search form without a body opens a Peek like a link");
  auto post_form = get_form;
  post_form.sends_body = true;
  Check(ClassifyNativeShiftLink(post_form) == NativeShiftLink::kOrdinary,
        "a Shift-submitted form with a body keeps Chromium's new window");
  auto get_form_in_peek = Click(shift, true);
  Check(ClassifyNativeShiftLink(get_form_in_peek) == NativeShiftLink::kSamePeek,
        "a Shift-submitted search form inside a Peek navigates that Peek");
  auto post_form_in_peek = get_form_in_peek;
  post_form_in_peek.sends_body = true;
  Check(ClassifyNativeShiftLink(post_form_in_peek) == NativeShiftLink::kOrdinary,
        "a Shift-submitted form with a body inside a Peek keeps the new window");

  const auto opened = [&](NSEventModifierFlags modifiers, bool in_shown_peek) {
    return NativeShiftCreatedPage{.click = Click(modifiers, in_shown_peek), .user_gesture = true,
                                  .web_url = true, .new_window = true};
  };
  const auto route = [](const NativeShiftCreatedPage& page) {
    return ClassifyNativeShiftCreatedPage(page);
  };
  Check(route(opened(shift, false)) == NativeShiftLink::kPeek,
        "a page a site opens in a new window from a Shift-click opens in a Peek");
  Check(route(opened(shift | NSEventModifierFlagCapsLock, false)) == NativeShiftLink::kPeek,
        "Caps Lock does not change a script-opened Shift-click");
  Check(route(opened(shift, true)) == NativeShiftLink::kSamePeek,
        "a page a site opens from a Shift-click inside a shown Peek navigates that Peek");
  auto opened_in_peek = opened(shift, true);
  opened_in_peek.click.can_open_peek = true;
  Check(route(opened_in_peek) == NativeShiftLink::kSamePeek,
        "a script-opened page from inside a shown Peek never stacks a second Peek");
  for (const bool in_shown_peek : {false, true}) {
    for (const NSEventModifierFlags other : {NSEventModifierFlags(0),
             NSEventModifierFlags(NSEventModifierFlagCommand),
             NSEventModifierFlags(NSEventModifierFlagOption),
             NSEventModifierFlags(NSEventModifierFlagControl),
             NSEventModifierFlags(shift | NSEventModifierFlagCommand),
             NSEventModifierFlags(shift | NSEventModifierFlagOption),
             NSEventModifierFlags(shift | NSEventModifierFlagControl)}) {
      Check(route(opened(other, in_shown_peek)) == NativeShiftLink::kOrdinary,
            "a script-opened page from any other modifier click keeps its window");
    }
    auto opened_disabled = opened(shift, in_shown_peek);
    opened_disabled.click.shift_peek_enabled = false;
    Check(route(opened_disabled) == NativeShiftLink::kOrdinary,
          "turning off Shift-click Peek keeps a script-opened page's window");
    auto opened_without_gesture = opened(shift, in_shown_peek);
    opened_without_gesture.user_gesture = false;
    Check(route(opened_without_gesture) == NativeShiftLink::kOrdinary,
          "a page opened without a user gesture keeps its window");
    auto opened_blank = opened(shift, in_shown_peek);
    opened_blank.web_url = false;
    Check(route(opened_blank) == NativeShiftLink::kOrdinary,
          "a script-opened page that starts blank or is not HTTP(S) keeps its window");
    auto opened_background = opened(shift, in_shown_peek);
    opened_background.new_window = false;
    Check(route(opened_background) == NativeShiftLink::kOrdinary,
          "only a new window or a foreground tab takes the Shift-click Peek route");
    auto opened_popup = opened(shift, in_shown_peek);
    opened_popup.popup = true;
    Check(route(opened_popup) == NativeShiftLink::kOrdinary,
          "a page asking for popup window features stays a popup");
    auto opened_sized = opened(shift, in_shown_peek);
    opened_sized.sized_by_page = true;
    Check(route(opened_sized) == NativeShiftLink::kOrdinary,
          "a page that sizes or places its own window keeps it");
    auto opened_fenced = opened(shift, in_shown_peek);
    opened_fenced.fenced_frame = true;
    Check(route(opened_fenced) == NativeShiftLink::kOrdinary,
          "a page opened from a fenced ad frame keeps Chromium's behaviour");
  }
  auto opened_refused = opened(shift, false);
  opened_refused.click.can_open_peek = false;
  Check(route(opened_refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek keeps a script-opened page's window");

  auto sandboxed_opener = opened(shift, false);
  sandboxed_opener.click.frame_can_navigate_page = NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener) == NativeShiftLink::kPeek,
        "outside a Peek, a page opened from a sandboxed frame still opens a Peek");
  auto sandboxed_opener_in_peek = opened(shift, true);
  sandboxed_opener_in_peek.click.frame_can_navigate_page =
      NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener_in_peek) == NativeShiftLink::kOrdinary,
        "inside a Peek, a page opened from a frame sandboxed against navigating the page keeps "
        "its window");

  auto late = opened(shift, false);
  late.new_window = false;
  late.foreground_tab = true;
  Check(route(late) == NativeShiftLink::kPeek,
        "a page a site opens late as a foreground tab while only Shift is held opens a Peek");
  auto late_in_peek = opened(shift, true);
  late_in_peek.new_window = false;
  late_in_peek.foreground_tab = true;
  Check(route(late_in_peek) == NativeShiftLink::kSamePeek,
        "a late foreground-tab open with only Shift held inside a Peek navigates that Peek");
  auto late_refused = late;
  late_refused.click.can_open_peek = false;
  Check(route(late_refused) == NativeShiftLink::kOrdinary,
        "a late open from a window that cannot present a Peek keeps its tab");

  Check(ChooseNativeCreatedPageRoute(shift, false, true) == NativeCreatedPageRoute::kShift,
        "a page opened while only Shift is held follows the Shift-click link rules");
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCapsLock, false, true) ==
            NativeCreatedPageRoute::kShift,
        "Caps Lock does not change the Shift route");
  Check(ChooseNativeCreatedPageRoute(shift, false, false) == NativeCreatedPageRoute::kShift,
        "a page opened from an ordinary embedded frame with only Shift held follows the frame's "
        "Shift-click links");
  Check(ChooseNativeCreatedPageRoute(0, false, false) == NativeCreatedPageRoute::kNone,
        "the automatic Peek keeps its rule that only the page's own frame opens one");
  Check(ChooseNativeCreatedPageRoute(shift, true, true) == NativeCreatedPageRoute::kShift,
        "a Shift-clicked meeting button follows the Shift-click link rules like a meeting link");
  Check(ChooseNativeCreatedPageRoute(0, true, true) == NativeCreatedPageRoute::kNone,
        "the automatic Peek still leaves meeting pages alone");
  Check(ChooseNativeCreatedPageRoute(0, false, true) == NativeCreatedPageRoute::kAutomatic,
        "a page opened without Shift keeps the automatic Peek rule");
  Check(ChooseNativeCreatedPageRoute(NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Command-click opening keeps its tab");
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Shift-Command opening keeps its tab");
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagOption, false, true) ==
            NativeCreatedPageRoute::kAutomatic,
        "other Shift mixes keep the automatic Peek rule they had");
  Check(NativeShiftHeld(shift) && !NativeShiftHeld(shift | NSEventModifierFlagControl) &&
            !NativeShiftHeld(0),
        "only Shift on its own counts as a Shift-click");

  for (const bool in_shown_peek : {false, true}) {
    for (const bool frame_can_navigate_page : {false, true}) {
      auto page = opened(shift, in_shown_peek);
      page.click.frame_can_navigate_page = frame_can_navigate_page;
      for (const bool foreground_tab : {false, true}) {
        page.new_window = !foreground_tab;
        page.foreground_tab = foreground_tab;
        Check(NativeShiftLinkOutcome(route(page)) ==
                  NativeShiftLinkOutcome(ClassifyNativeShiftLink(page.click)),
              "the hint over a link promises what a page the site opens from that click does");
      }
    }
  }

  Check(NativeShiftLinkOutcome(NativeShiftLink::kSamePeek) == PCNativeStatusLinkOutcomeThisPeek,
        "the hint says a same-Peek link opens in this Peek");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kPeek) == PCNativeStatusLinkOutcomePeek,
        "the hint promises a Peek outside one");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kOrdinary) == PCNativeStatusLinkOutcomeNewWindow,
        "the hint says a new window otherwise");
  printf("Passed %d Shift-click Peek routing and hint checks; no browser execution.\n", checks);
}

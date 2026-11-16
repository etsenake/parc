#import "native_shift_link.h"
#include "../Support/TestFailure.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

using parc::ClassifyNativeShiftLink;
using parc::NativeFrameCanNavigatePage;
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

  Check(NativeShiftLinkOutcome(NativeShiftLink::kSamePeek) == PCNativeStatusLinkOutcomeThisPeek,
        "the hint says a same-Peek link opens in this Peek");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kPeek) == PCNativeStatusLinkOutcomePeek,
        "the hint promises a Peek outside one");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kOrdinary) == PCNativeStatusLinkOutcomeNewWindow,
        "the hint says a new window otherwise");
  printf("Passed %d Shift-click Peek routing and hint checks; no browser execution.\n", checks);
}

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
static NativeShiftLinkClick Click(NSEventModifierFlags modifiers, bool in_shown_peek) {
  return {.modifiers = modifiers, .shift_peek_enabled = true, .in_shown_peek = in_shown_peek,
          .can_open_peek = !in_shown_peek};
}

namespace {
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

OpenParams DirectPost() {
  return {.post_data = std::make_shared<Body>(Body{kFormBody}),
          .extra_headers = std::string("Content-Type: ") + kFormType,
          .referrer = kFormReferrer};
}
bool KeepsForm(const OpenParams& params) {
  return params.post_data && params.post_data->bytes == kFormBody &&
      params.extra_headers == std::string("Content-Type: ") + kFormType &&
      params.referrer == kFormReferrer;
}
}

@interface ShiftLinkTests : ParcNativeTestCase
@end

static constexpr NSEventModifierFlags shift = NSEventModifierFlagShift;

static PCNativeStatusLinkOutcome hint(bool in_shown_peek, bool frame_can_navigate_page) {
  auto click = Click(shift, in_shown_peek);
  click.frame_can_navigate_page = frame_can_navigate_page;
  return NativeShiftLinkOutcome(ClassifyNativeShiftLink(click));
}

static NativeShiftCreatedPage opened(NSEventModifierFlags modifiers, bool in_shown_peek) {
  return NativeShiftCreatedPage{.click = Click(modifiers, in_shown_peek), .user_gesture = true, .web_url = true,
                                .new_window = true};
}

static NativeShiftLink route(const NativeShiftCreatedPage& page) {
  return ClassifyNativeShiftCreatedPage(page);
}

static const NativeHeldShiftNavigation held_post{.web_url = true, .from_opener = true, .post = true,
                                                 .has_body = true, .peek_takes_link = true};

@implementation ShiftLinkTests

- (void)testAShiftClickOpensAPeekAndOtherClicksStayOrdinary {
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
}

- (void)testAPeekThatCannotTakeTheClickKeepsTheOrdinaryRoute {
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
}

- (void)testTheFrameSandboxDecidesWhetherAFrameCanNavigateThePage {
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
}

- (void)testTheHintSaysWhereAShiftClickInAFrameGoes {
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
}

- (void)testShiftSubmittedFormsKeepTheirBody {
  auto direct_post = DirectPost();
  RetargetNativeShiftLink(direct_post, ClassifyNativeShiftLink(Click(shift, false)), kCurrentTab,
                          kForegroundTab);
  Check(direct_post.disposition == kForegroundTab && KeepsForm(direct_post),
        "a Shift-submitted POST form opens a Peek with its body, content type and referrer");
  auto direct_post_in_peek = DirectPost();
  RetargetNativeShiftLink(direct_post_in_peek, ClassifyNativeShiftLink(Click(shift, true)),
                          kCurrentTab, kForegroundTab);
  Check(direct_post_in_peek.disposition == kCurrentTab &&
            direct_post_in_peek.frame_tree_node_id == 0 && KeepsForm(direct_post_in_peek),
        "a Shift-submitted POST form inside a Peek navigates that Peek's page with its body, "
        "content type and referrer");
  auto direct_get = DirectPost();
  direct_get.post_data.reset();
  direct_get.extra_headers.clear();
  RetargetNativeShiftLink(direct_get, ClassifyNativeShiftLink(Click(shift, true)), kCurrentTab,
                          kForegroundTab);
  Check(direct_get.disposition == kCurrentTab && !direct_get.post_data,
        "a Shift-submitted search form inside a Peek navigates that Peek without inventing a body");
  auto direct_post_off = DirectPost();
  auto shift_off = Click(shift, false);
  shift_off.shift_peek_enabled = false;
  RetargetNativeShiftLink(direct_post_off, ClassifyNativeShiftLink(shift_off), kCurrentTab,
                          kForegroundTab);
  Check(direct_post_off.disposition == kNewWindow && direct_post_off.frame_tree_node_id == 7 &&
            KeepsForm(direct_post_off),
        "with Shift-click Peek off, a Shift-submitted POST form keeps Chromium's new window "
        "untouched");
}

- (void)testScriptOpenedPagesFollowTheShiftClickThatOpenedThem {
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
}

- (void)testScriptOpenedPagesFromSandboxedFrames {
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
}

- (void)testLateForegroundTabOpensFollowTheShiftClick {
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
}

- (void)testAScriptSubmittedPostOutsideAPeekBecomesThePeek {
  Check(route(opened(shift, false)) == NativeShiftLink::kPeek &&
            ChooseNativeCreatedPageRoute(shift, false, true) == NativeCreatedPageRoute::kShift,
        "a page a site's script submits a POST form into outside a Peek becomes the Peek itself, "
        "so the form's own submission lands there with its body");
}

- (void)testScriptSubmittedNavigationsInsideAPeekJoinIt {
  Check(route(opened(shift, true)) == NativeShiftLink::kSamePeek &&
            NativeHeldShiftNavigationJoinsPeek(held_post),
        "a POST form a site's script submits into a new window inside a Peek joins that Peek");
  OpenParams same_peek{.disposition = kCurrentTab, .frame_tree_node_id = 0};
  const auto script_body = std::make_shared<Body>(Body{kFormBody});
  CarryNativeShiftRequest(same_peek, std::string(kFormReferrer), script_body,
                          std::string(kFormType));
  Check(same_peek.post_data == script_body && KeepsForm(same_peek),
        "the same-Peek navigation carries the script-submitted form's body, content type and "
        "referrer");
  OpenParams multipart{.disposition = kCurrentTab};
  CarryNativeShiftRequest(multipart, std::string(kFormReferrer), script_body,
                          std::string("multipart/form-data; boundary=----parc7MA4YWxk"));
  Check(multipart.extra_headers == "Content-Type: multipart/form-data; boundary=----parc7MA4YWxk",
        "a multipart form keeps its boundary in the carried content type");
  OpenParams script_get{.disposition = kCurrentTab};
  CarryNativeShiftRequest(script_get, std::string(kFormReferrer), std::shared_ptr<Body>(),
                          std::string());
  Check(!script_get.post_data && script_get.extra_headers.empty() &&
            script_get.referrer == kFormReferrer,
        "a script-opened plain visit joins the Peek with its referrer and no body or content type");
  auto held_get = held_post;
  held_get.post = false;
  held_get.has_body = false;
  Check(NativeHeldShiftNavigationJoinsPeek(held_get),
        "a page a site's script opens with a plain visit inside a Peek joins that Peek");
  auto held_lost_body = held_post;
  held_lost_body.has_body = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_lost_body),
        "a POST whose body can't be read keeps Chromium's window rather than becoming a plain visit");
  auto held_elsewhere = held_post;
  held_elsewhere.from_opener = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_elsewhere),
        "a navigation another frame starts in the held window keeps Chromium's window");
  auto held_peek_gone = held_post;
  held_peek_gone.peek_takes_link = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_peek_gone),
        "a Peek that can no longer take the link leaves the page to Chromium's window");
  auto held_other_scheme = held_post;
  held_other_scheme.web_url = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_other_scheme),
        "a held window that navigates somewhere other than HTTP(S) keeps Chromium's window");
}

- (void)testCreatedPagesFollowTheShiftRouteOnlyForShiftOnItsOwn {
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
}

- (void)testTheHintPromisesWhatAScriptOpenedPageDoes {
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
}

- (void)testEachRouteHasItsHint {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kSamePeek) == PCNativeStatusLinkOutcomeThisPeek,
        "the hint says a same-Peek link opens in this Peek");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kPeek) == PCNativeStatusLinkOutcomePeek,
        "the hint promises a Peek outside one");
  Check(NativeShiftLinkOutcome(NativeShiftLink::kOrdinary) == PCNativeStatusLinkOutcomeNewWindow,
        "the hint says a new window otherwise");
}

@end

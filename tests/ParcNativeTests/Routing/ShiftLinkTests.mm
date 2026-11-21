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

- (void)testShiftInsideAPeekReusesIt {
  Check(ClassifyNativeShiftLink(Click(shift, true)) == NativeShiftLink::kSamePeek,
        "Shift-click inside the shown Peek navigates that Peek");
}

- (void)testShiftOutsideAPeekOpensOne {
  Check(ClassifyNativeShiftLink(Click(shift, false)) == NativeShiftLink::kPeek,
        "Shift-click outside a Peek opens a Peek");
}

- (void)testCapsLockPreservesShiftClick {
  Check(ClassifyNativeShiftLink(Click(shift | NSEventModifierFlagCapsLock, true)) ==
            NativeShiftLink::kSamePeek,
        "Caps Lock does not change the Shift-click");
}

- (void)checkOrdinaryModifier:(NSEventModifierFlags)flags insidePeek:(bool)inside {
  PARC_CHECK(ClassifyNativeShiftLink(Click(flags, inside)) == NativeShiftLink::kOrdinary);
  PARC_CHECK(route(opened(flags, inside)) == NativeShiftLink::kOrdinary);
}

- (void)testPlainClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:0 insidePeek:false];
}

- (void)testCommandClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagCommand insidePeek:false];
}

- (void)testOptionClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagOption insidePeek:false];
}

- (void)testControlClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagControl insidePeek:false];
}

- (void)testShiftCommandClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagCommand insidePeek:false];
}

- (void)testShiftOptionClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagOption insidePeek:false];
}

- (void)testShiftControlClicksKeepTheirRouteOutsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagControl insidePeek:false];
}

- (void)testDisabledPeekKeepsShiftClicksOrdinaryOutsideAPeek {
  auto click = Click(shift, false);
  click.shift_peek_enabled = false;
  PARC_CHECK(ClassifyNativeShiftLink(click) == NativeShiftLink::kOrdinary);
}

- (void)testPlainClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:0 insidePeek:true];
}

- (void)testCommandClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagCommand insidePeek:true];
}

- (void)testOptionClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagOption insidePeek:true];
}

- (void)testControlClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:NSEventModifierFlagControl insidePeek:true];
}

- (void)testShiftCommandClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagCommand insidePeek:true];
}

- (void)testShiftOptionClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagOption insidePeek:true];
}

- (void)testShiftControlClicksKeepTheirRouteInsideAPeek {
  [self checkOrdinaryModifier:shift | NSEventModifierFlagControl insidePeek:true];
}

- (void)testDisabledPeekKeepsShiftClicksOrdinaryInsideAPeek {
  auto click = Click(shift, true);
  click.shift_peek_enabled = false;
  PARC_CHECK(ClassifyNativeShiftLink(click) == NativeShiftLink::kOrdinary);
}

- (void)testShiftCannotStackPeeks {
  auto stacked = Click(shift, true);
  stacked.can_open_peek = true;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kSamePeek,
        "a Shift-click inside a Peek never stacks a second Peek");
}

- (void)testSandboxedFramesCannotReplaceTheirPeek {
  auto stacked = Click(shift, true);
  stacked.can_open_peek = true;
  stacked.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(stacked) == NativeShiftLink::kOrdinary,
        "an embedded frame sandboxed against navigating the page keeps the ordinary route");
}

- (void)testSandboxedFramesCanOpenANewPeek {
  auto sandboxed = Click(shift, false);
  sandboxed.frame_can_navigate_page = false;
  Check(ClassifyNativeShiftLink(sandboxed) == NativeShiftLink::kPeek,
        "the page-navigation sandbox only matters for the same-Peek navigation");
}

- (void)testRefusedPeeksKeepTheOrdinaryRoute {
  auto refused = Click(shift, false);
  refused.can_open_peek = false;
  Check(ClassifyNativeShiftLink(refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek right now keeps the ordinary route");
}

- (void)testTopFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(true, true, true),
        "the page's own frame can always navigate the page");
}

- (void)testUnsandboxedFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(false, false, false),
        "an embedded frame without a sandbox can navigate the page");
}

- (void)testUserActivationCanAdmitFrameNavigation {
  Check(NativeFrameCanNavigatePage(false, true, false),
        "a sandboxed frame allowed to navigate the page on a click can take the click there");
}

- (void)testPermittedFramesCanNavigateThePage {
  Check(NativeFrameCanNavigatePage(false, false, true),
        "a sandboxed frame allowed to navigate the page can take the click there");
}

- (void)testRestrictedFramesCannotNavigateThePage {
  Check(!NativeFrameCanNavigatePage(false, true, true),
        "a frame sandboxed against navigating the page cannot take the click there");
}

- (void)testRestrictedFramesInsideAPeekPromiseANewWindow {
  Check(hint(true, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomeNewWindow,
        "inside a Peek, the hint over a frame sandboxed against navigating the page says a new window");
}

- (void)testActivatedFramesInsideAPeekPromiseTheCurrentPeek {
  Check(hint(true, NativeFrameCanNavigatePage(false, true, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over a frame allowed to navigate the page on a click says this Peek");
}

- (void)testOrdinaryFramesInsideAPeekPromiseTheCurrentPeek {
  Check(hint(true, NativeFrameCanNavigatePage(false, false, false)) ==
            PCNativeStatusLinkOutcomeThisPeek,
        "inside a Peek, the hint over an ordinary embedded frame says this Peek");
}

- (void)testRestrictedFramesOutsideAPeekPromiseAPeek {
  Check(hint(false, NativeFrameCanNavigatePage(false, true, true)) ==
            PCNativeStatusLinkOutcomePeek,
        "outside a Peek, the hint over a sandboxed frame still promises a Peek");
}

- (void)testShiftPostPreservesTheFormWhenOpeningAPeek {
  auto direct_post = DirectPost();
  RetargetNativeShiftLink(direct_post, ClassifyNativeShiftLink(Click(shift, false)), kCurrentTab,
                          kForegroundTab);
  Check(direct_post.disposition == kForegroundTab && KeepsForm(direct_post),
        "a Shift-submitted POST form opens a Peek with its body, content type and referrer");
}

- (void)testShiftPostPreservesTheFormWhenReusingAPeek {
  auto direct_post_in_peek = DirectPost();
  RetargetNativeShiftLink(direct_post_in_peek, ClassifyNativeShiftLink(Click(shift, true)),
                          kCurrentTab, kForegroundTab);
  Check(direct_post_in_peek.disposition == kCurrentTab &&
            direct_post_in_peek.frame_tree_node_id == 0 && KeepsForm(direct_post_in_peek),
        "a Shift-submitted POST form inside a Peek navigates that Peek's page with its body, "
        "content type and referrer");
}

- (void)testShiftGetInsideAPeekCarriesNoBody {
  auto direct_get = DirectPost();
  direct_get.post_data.reset();
  direct_get.extra_headers.clear();
  RetargetNativeShiftLink(direct_get, ClassifyNativeShiftLink(Click(shift, true)), kCurrentTab,
                          kForegroundTab);
  Check(direct_get.disposition == kCurrentTab && !direct_get.post_data,
        "a Shift-submitted search form inside a Peek navigates that Peek without inventing a body");
}

- (void)testDisablingShiftPeekPreservesTheOriginalPost {
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

- (void)testAScriptWindowFromShiftClickOpensAPeek {
  Check(route(opened(shift, false)) == NativeShiftLink::kPeek,
        "a page a site opens in a new window from a Shift-click opens in a Peek");
}

- (void)testCapsLockPreservesTheScriptWindowRoute {
  Check(route(opened(shift | NSEventModifierFlagCapsLock, false)) == NativeShiftLink::kPeek,
        "Caps Lock does not change a script-opened Shift-click");
}

- (void)testAScriptWindowInsideAPeekReusesIt {
  Check(route(opened(shift, true)) == NativeShiftLink::kSamePeek,
        "a page a site opens from a Shift-click inside a shown Peek navigates that Peek");
}

- (void)testScriptWindowsCannotStackPeeks {
  auto opened_in_peek = opened(shift, true);
  opened_in_peek.click.can_open_peek = true;
  Check(route(opened_in_peek) == NativeShiftLink::kSamePeek,
        "a script-opened page from inside a shown Peek never stacks a second Peek");
}

- (void)testScriptWindowsRemainWindowsWhenPeeksAreUnavailable {
  auto opened_refused = opened(shift, false);
  opened_refused.click.can_open_peek = false;
  Check(route(opened_refused) == NativeShiftLink::kOrdinary,
        "a window that cannot present a Peek keeps a script-opened page's window");
}

- (void)testSandboxedScriptsCanOpenAPeek {
  auto sandboxed_opener = opened(shift, false);
  sandboxed_opener.click.frame_can_navigate_page = NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener) == NativeShiftLink::kPeek,
        "outside a Peek, a page opened from a sandboxed frame still opens a Peek");
}

- (void)testSandboxedScriptsCannotReplaceTheirPeek {
  auto sandboxed_opener_in_peek = opened(shift, true);
  sandboxed_opener_in_peek.click.frame_can_navigate_page =
      NativeFrameCanNavigatePage(false, true, true);
  Check(route(sandboxed_opener_in_peek) == NativeShiftLink::kOrdinary,
        "inside a Peek, a page opened from a frame sandboxed against navigating the page keeps "
        "its window");
}

- (void)testLateForegroundTabsOpenAPeek {
  auto late = opened(shift, false);
  late.new_window = false;
  late.foreground_tab = true;
  Check(route(late) == NativeShiftLink::kPeek,
        "a page a site opens late as a foreground tab while only Shift is held opens a Peek");
}

- (void)testLateForegroundTabsReuseTheCurrentPeek {
  auto late_in_peek = opened(shift, true);
  late_in_peek.new_window = false;
  late_in_peek.foreground_tab = true;
  Check(route(late_in_peek) == NativeShiftLink::kSamePeek,
        "a late foreground-tab open with only Shift held inside a Peek navigates that Peek");
}

- (void)testRefusingALatePeekKeepsTheTab {
  auto late = opened(shift, false);
  late.new_window = false;
  late.foreground_tab = true;
  auto late_refused = late;
  late_refused.click.can_open_peek = false;
  Check(route(late_refused) == NativeShiftLink::kOrdinary,
        "a late open from a window that cannot present a Peek keeps its tab");
}

- (void)testScriptPostsOutsideAPeekFollowShift {
  Check(route(opened(shift, false)) == NativeShiftLink::kPeek &&
            ChooseNativeCreatedPageRoute(shift, false, true) == NativeCreatedPageRoute::kShift,
        "a page a site's script submits a POST form into outside a Peek becomes the Peek itself, "
        "so the form's own submission lands there with its body");
}

- (void)testScriptPostsInsideAPeekJoinIt {
  Check(route(opened(shift, true)) == NativeShiftLink::kSamePeek &&
            NativeHeldShiftNavigationJoinsPeek(held_post),
        "a POST form a site's script submits into a new window inside a Peek joins that Peek");
}

- (void)testScriptPostsCarryTheirBodyAndReferrer {
  OpenParams same_peek{.disposition = kCurrentTab, .frame_tree_node_id = 0};
  const auto script_body = std::make_shared<Body>(Body{kFormBody});
  CarryNativeShiftRequest(same_peek, std::string(kFormReferrer), script_body,
                          std::string(kFormType));
  Check(same_peek.post_data == script_body && KeepsForm(same_peek),
        "the same-Peek navigation carries the script-submitted form's body, content type and "
        "referrer");
}

- (void)testMultipartPostsKeepTheirBoundary {
  const auto script_body = std::make_shared<Body>(Body{kFormBody});
  OpenParams multipart{.disposition = kCurrentTab};
  CarryNativeShiftRequest(multipart, std::string(kFormReferrer), script_body,
                          std::string("multipart/form-data; boundary=----parc7MA4YWxk"));
  Check(multipart.extra_headers == "Content-Type: multipart/form-data; boundary=----parc7MA4YWxk",
        "a multipart form keeps its boundary in the carried content type");
}

- (void)testScriptGetsCarryOnlyTheirReferrer {
  OpenParams script_get{.disposition = kCurrentTab};
  CarryNativeShiftRequest(script_get, std::string(kFormReferrer), std::shared_ptr<Body>(),
                          std::string());
  Check(!script_get.post_data && script_get.extra_headers.empty() &&
            script_get.referrer == kFormReferrer,
        "a script-opened plain visit joins the Peek with its referrer and no body or content type");
}

- (void)testAHeldGetCanJoinThePeek {
  auto held_get = held_post;
  held_get.post = false;
  held_get.has_body = false;
  Check(NativeHeldShiftNavigationJoinsPeek(held_get),
        "a page a site's script opens with a plain visit inside a Peek joins that Peek");
}

- (void)testAHeldPostRequiresItsBody {
  auto held_lost_body = held_post;
  held_lost_body.has_body = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_lost_body),
        "a POST whose body can't be read keeps Chromium's window rather than becoming a plain visit");
}

- (void)testAHeldWindowRequiresTheOriginalOpener {
  auto held_elsewhere = held_post;
  held_elsewhere.from_opener = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_elsewhere),
        "a navigation another frame starts in the held window keeps Chromium's window");
}

- (void)testAHeldWindowRequiresAnAvailablePeek {
  auto held_peek_gone = held_post;
  held_peek_gone.peek_takes_link = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_peek_gone),
        "a Peek that can no longer take the link leaves the page to Chromium's window");
}

- (void)testAHeldWindowRequiresAWebUrl {
  auto held_other_scheme = held_post;
  held_other_scheme.web_url = false;
  Check(!NativeHeldShiftNavigationJoinsPeek(held_other_scheme),
        "a held window that navigates somewhere other than HTTP(S) keeps Chromium's window");
}

- (void)testDisabledScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.click.shift_peek_enabled = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testDisabledScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.click.shift_peek_enabled = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testGesturelessScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.user_gesture = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testGesturelessScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.user_gesture = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBlankScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.web_url = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBlankScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.web_url = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBackgroundScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.new_window = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testBackgroundScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.new_window = false;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testPopupScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.popup = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testPopupScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.popup = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testSizedScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.sized_by_page = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testSizedScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.sized_by_page = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testFencedScriptWindowsKeepTheirRouteInsideAPeek {
  auto page = opened(shift, true);
  page.fenced_frame = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testFencedScriptWindowsKeepTheirRouteOutsideAPeek {
  auto page = opened(shift, false);
  page.fenced_frame = true;
  PARC_CHECK(route(page) == NativeShiftLink::kOrdinary);
}

- (void)testShiftRoutesCreatedPages {
  Check(ChooseNativeCreatedPageRoute(shift, false, true) == NativeCreatedPageRoute::kShift,
        "a page opened while only Shift is held follows the Shift-click link rules");
}

- (void)testCapsLockPreservesCreatedPageShift {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCapsLock, false, true) ==
            NativeCreatedPageRoute::kShift,
        "Caps Lock does not change the Shift route");
}

- (void)testEmbeddedFramesCanUseShift {
  Check(ChooseNativeCreatedPageRoute(shift, false, false) == NativeCreatedPageRoute::kShift,
        "a page opened from an ordinary embedded frame with only Shift held follows the frame's "
        "Shift-click links");
}

- (void)testEmbeddedFramesCannotAutomaticallyOpenPeeks {
  Check(ChooseNativeCreatedPageRoute(0, false, false) == NativeCreatedPageRoute::kNone,
        "the automatic Peek keeps its rule that only the page's own frame opens one");
}

- (void)testMeetingLinksCanUseShift {
  Check(ChooseNativeCreatedPageRoute(shift, true, true) == NativeCreatedPageRoute::kShift,
        "a Shift-clicked meeting button follows the Shift-click link rules like a meeting link");
}

- (void)testMeetingLinksSkipAutomaticPeeks {
  Check(ChooseNativeCreatedPageRoute(0, true, true) == NativeCreatedPageRoute::kNone,
        "the automatic Peek still leaves meeting pages alone");
}

- (void)testPlainLinksCanAutomaticallyOpenPeeks {
  Check(ChooseNativeCreatedPageRoute(0, false, true) == NativeCreatedPageRoute::kAutomatic,
        "a page opened without Shift keeps the automatic Peek rule");
}

- (void)testCommandLinksKeepTheirTab {
  Check(ChooseNativeCreatedPageRoute(NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Command-click opening keeps its tab");
}

- (void)testShiftCommandLinksKeepTheirTab {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagCommand, false, true) ==
            NativeCreatedPageRoute::kNone,
        "a Shift-Command opening keeps its tab");
}

- (void)testShiftOptionLinksUseAutomaticRouting {
  Check(ChooseNativeCreatedPageRoute(shift | NSEventModifierFlagOption, false, true) ==
            NativeCreatedPageRoute::kAutomatic,
        "other Shift mixes keep the automatic Peek rule they had");
}

- (void)testOnlyUnmixedShiftCountsAsHeld {
  Check(NativeShiftHeld(shift) && !NativeShiftHeld(shift | NSEventModifierFlagControl) &&
            !NativeShiftHeld(0),
        "only Shift on its own counts as a Shift-click");
}

- (void)checkHintInsidePeek:(bool)inside allowsNavigation:(bool)allowed foregroundTab:(bool)tab {
  auto page = opened(shift, inside);
  page.click.frame_can_navigate_page = allowed;
  page.new_window = !tab;
  page.foreground_tab = tab;
  PARC_CHECK(NativeShiftLinkOutcome(route(page)) == hint(inside, allowed));
}

- (void)testPermittedWindowHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:true foregroundTab:false];
}

- (void)testPermittedTabHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:true foregroundTab:true];
}

- (void)testRestrictedWindowHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:false foregroundTab:false];
}

- (void)testRestrictedTabHintsMatchTheRouteInsideAPeek {
  [self checkHintInsidePeek:true allowsNavigation:false foregroundTab:true];
}

- (void)testPermittedWindowHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:true foregroundTab:false];
}

- (void)testPermittedTabHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:true foregroundTab:true];
}

- (void)testRestrictedWindowHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:false foregroundTab:false];
}

- (void)testRestrictedTabHintsMatchTheRouteOutsideAPeek {
  [self checkHintInsidePeek:false allowsNavigation:false foregroundTab:true];
}

- (void)testSamePeekRoutesPromiseTheCurrentPeek {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kSamePeek) == PCNativeStatusLinkOutcomeThisPeek,
        "the hint says a same-Peek link opens in this Peek");
}

- (void)testPeekRoutesPromiseANewPeek {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kPeek) == PCNativeStatusLinkOutcomePeek,
        "the hint promises a Peek outside one");
}

- (void)testOrdinaryRoutesPromiseANewWindow {
  Check(NativeShiftLinkOutcome(NativeShiftLink::kOrdinary) == PCNativeStatusLinkOutcomeNewWindow,
        "the hint says a new window otherwise");
}

@end

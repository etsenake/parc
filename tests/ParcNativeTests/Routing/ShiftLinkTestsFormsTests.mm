#import "ShiftLinkTestsSupport.h"

using namespace ShiftLinkTestsSupport;

__attribute__((objc_runtime_name("ParcNativeTests_ShiftLinkTestsFormsTests")))
@interface ShiftLinkTestsFormsTests : ParcNativeTestCase
@end

@implementation ShiftLinkTestsFormsTests

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

@end

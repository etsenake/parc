#include "fairplay_identity_policy.h"

#include <cstdio>
#include <cstdlib>
#include <string>

namespace {

unsigned checks = 0;

void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

using parc::fairplay_identity::DecideWidevineRequest;
using parc::fairplay_identity::FrameNavigation;
using parc::fairplay_identity::IsSafariVersion;
using parc::fairplay_identity::NavigationPresentsSafari;
using parc::fairplay_identity::PresentsSafari;
using parc::fairplay_identity::SafariUserAgent;
using parc::fairplay_identity::SiteLists;
using parc::fairplay_identity::WidevineRequest;
using parc::fairplay_identity::WidevineRequestFrame;

SiteLists Lists() {
  SiteLists lists;
  lists.safari = {"netflix.com", "apple.com", "both.example"};
  lists.chrome = {"spotify.com", "both.example"};
  return lists;
}

FrameNavigation Main(const std::string& site) {
  FrameNavigation navigation;
  navigation.main_frame = true;
  navigation.site = site;
  return navigation;
}

FrameNavigation Sub(const std::string& site,
                    bool same_site_as_main,
                    bool main_safari,
                    bool parent_safari) {
  FrameNavigation navigation;
  navigation.site = site;
  navigation.same_site_as_main = same_site_as_main;
  navigation.main_frame_safari = main_safari;
  navigation.parent_safari = parent_safari;
  return navigation;
}

void SiteListRules() {
  const SiteLists lists = Lists();
  Check(PresentsSafari(lists, "netflix.com"), "learned site presents Safari");
  Check(!PresentsSafari(lists, "example.com"), "unknown site stays Chrome");
  Check(!PresentsSafari(lists, "spotify.com"), "user's Chrome site stays Chrome");
  Check(!PresentsSafari(lists, "both.example"),
        "user's Chrome choice wins over a learned entry");
  Check(!PresentsSafari(lists, ""), "a URL without a site stays Chrome");
  Check(!PresentsSafari(SiteLists{}, "netflix.com"), "empty lists are Chrome");
}

void NavigationRules() {
  const SiteLists lists = Lists();
  Check(NavigationPresentsSafari(lists, Main("netflix.com")),
        "main frame on a learned site");
  Check(!NavigationPresentsSafari(lists, Main("google.com")),
        "leaving a learned site in the same tab returns to Chrome");
  Check(!NavigationPresentsSafari(lists, Main("")),
        "about:blank main frame stays Chrome");
  Check(NavigationPresentsSafari(lists, Sub("netflix.com", true, true, true)),
        "same-site subframe follows its Safari main document");
  Check(!NavigationPresentsSafari(
            lists, Sub("doubleclick.net", false, true, true)),
        "subframe on another site keeps Chrome's identity");
  Check(!NavigationPresentsSafari(lists, Sub("apple.com", false, true, true)),
        "a learned site embedded cross-site keeps Chrome's identity");
  Check(!NavigationPresentsSafari(
            lists, Sub("netflix.com", false, true, true)),
        "same domain over another scheme is another site");
  Check(!NavigationPresentsSafari(
            lists, Sub("netflix.com", true, false, false)),
        "same-site subframe of a Chrome main document stays Chrome");
  Check(NavigationPresentsSafari(lists, Sub("netflix.com", true, true, false)),
        "a frame on the main document's site follows it, also when its "
        "parent is a cross-site frame or it gets a process of its own");
  Check(NavigationPresentsSafari(lists, Sub("", false, true, true)),
        "about:blank subframe inherits its Safari parent");
  Check(!NavigationPresentsSafari(lists, Sub("", false, true, false)),
        "about:blank inside a cross-site frame inherits its Chrome parent");
}

WidevineRequestFrame Frame(const std::string& site, bool follows, bool safari) {
  WidevineRequestFrame frame;
  frame.site = site;
  frame.follows_main_frame = follows;
  frame.page_safari = safari;
  return frame;
}

void WidevineRules() {
  const SiteLists lists = Lists();
  Check(DecideWidevineRequest(lists, Frame("tv.example", true, false)) ==
            WidevineRequest::kHoldAndLearn,
        "an unknown site asking for Widevine is learned");
  Check(DecideWidevineRequest(lists, Frame("netflix.com", true, false)) ==
            WidevineRequest::kHoldAndLearn,
        "a learned site still in Chrome's identity is held and reloaded");
  Check(DecideWidevineRequest(lists, Frame("netflix.com", true, true)) ==
            WidevineRequest::kHold,
        "a Safari page reaching Widevine is held without a reload loop");
  Check(DecideWidevineRequest(lists, Frame("spotify.com", true, false)) ==
            WidevineRequest::kAllow,
        "the user's Chrome site keeps Widevine");
  Check(DecideWidevineRequest(lists, Frame("both.example", true, false)) ==
            WidevineRequest::kAllow,
        "the user's Chrome choice wins for Widevine too");
  Check(DecideWidevineRequest(lists, Frame("player.example", false, false)) ==
            WidevineRequest::kAllow,
        "a cross-site frame cannot be given Safari's identity, so it keeps "
        "Widevine");
  Check(DecideWidevineRequest(lists, Frame("", true, false)) ==
            WidevineRequest::kAllow,
        "a frame without a site keeps Widevine");
}

void UserAgentRules() {
  Check(SafariUserAgent("27.2") ==
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 "
            "Safari/605.1.15",
        "Safari 27.2's user agent");
  Check(IsSafariVersion("27.2"), "major.minor");
  Check(IsSafariVersion("26.0.1"), "major.minor.patch");
  Check(!IsSafariVersion("27"), "major alone");
  Check(!IsSafariVersion(""), "empty");
  Check(!IsSafariVersion("27..2"), "double dot");
  Check(!IsSafariVersion(".27"), "leading dot");
  Check(!IsSafariVersion("27.2."), "trailing dot");
  Check(!IsSafariVersion("27.2 x"), "space");
  Check(!IsSafariVersion("27.2\r\nX: y"), "header injection");
  Check(!IsSafariVersion("1.2.3.4"), "four parts");
}

}

int main() {
  SiteListRules();
  NavigationRules();
  WidevineRules();
  UserAgentRules();
  std::printf("fairplay identity policy: %u checks passed\n", checks);
  return 0;
}

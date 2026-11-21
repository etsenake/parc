#import "ParcNativeTest.h"
#include "fairplay_identity_policy.h"

#include <string>

namespace {

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

WidevineRequestFrame Frame(const std::string& site, bool follows, bool safari) {
  WidevineRequestFrame frame;
  frame.site = site;
  frame.follows_main_frame = follows;
  frame.page_safari = safari;
  return frame;
}

}

@interface ParcNativeTests_FairPlayIdentityPolicyTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_FairPlayIdentityPolicyTests

- (void)testALearnedSitePresentsSafari {
  PARC_CHECK(PresentsSafari(Lists(), "netflix.com"));
}

- (void)testAnUnknownSiteKeepsChrome {
  PARC_CHECK(!PresentsSafari(Lists(), "example.com"));
}

- (void)testAnExplicitChromeSiteKeepsChrome {
  PARC_CHECK(!PresentsSafari(Lists(), "spotify.com"));
}

- (void)testChromeOverridesALearnedSite {
  PARC_CHECK(!PresentsSafari(Lists(), "both.example"));
}

- (void)testAURLWithoutASiteKeepsChrome {
  PARC_CHECK(!PresentsSafari(Lists(), ""));
}

- (void)testAnEmptyListKeepsChrome {
  PARC_CHECK(!PresentsSafari(SiteLists{}, "netflix.com"));
}

- (void)testAMainFrameOnALearnedSitePresentsSafari {
  PARC_CHECK(NavigationPresentsSafari(Lists(), Main("netflix.com")));
}

- (void)testLeavingALearnedSiteRestoresChrome {
  PARC_CHECK(!NavigationPresentsSafari(Lists(), Main("google.com")));
}

- (void)testABlankMainFrameKeepsChrome {
  PARC_CHECK(!NavigationPresentsSafari(Lists(), Main("")));
}

- (void)testASameSiteFrameFollowsItsSafariDocument {
  PARC_CHECK(NavigationPresentsSafari(Lists(), Sub("netflix.com", true, true, true)));
}

- (void)testACrossSiteFrameKeepsChrome {
  PARC_CHECK(!NavigationPresentsSafari(
            Lists(), Sub("doubleclick.net", false, true, true)));
}

- (void)testEmbeddingALearnedSiteCrossSiteKeepsChrome {
  PARC_CHECK(!NavigationPresentsSafari(Lists(), Sub("apple.com", false, true, true)));
}

- (void)testChangingSchemesMakesAFrameCrossSite {
  PARC_CHECK(!NavigationPresentsSafari(
            Lists(), Sub("netflix.com", false, true, true)));
}

- (void)testASameSiteFrameFollowsItsChromeDocument {
  PARC_CHECK(!NavigationPresentsSafari(
            Lists(), Sub("netflix.com", true, false, false)));
}

- (void)testAMatchingFrameFollowsItsDocumentAcrossACrossSiteParent {
  PARC_CHECK(NavigationPresentsSafari(Lists(), Sub("netflix.com", true, true, false)));
}

- (void)testABlankFrameInheritsItsSafariParent {
  PARC_CHECK(NavigationPresentsSafari(Lists(), Sub("", false, true, true)));
}

- (void)testABlankFrameInheritsItsChromeParent {
  PARC_CHECK(!NavigationPresentsSafari(Lists(), Sub("", false, true, false)));
}

- (void)testAnUnknownWidevineSiteIsLearned {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("tv.example", true, false)) ==
            WidevineRequest::kHoldAndLearn);
}

- (void)testALearnedSiteStillPresentingChromeReloads {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("netflix.com", true, false)) ==
            WidevineRequest::kHoldAndLearn);
}

- (void)testASafariPageHoldsWidevineWithoutReloading {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("netflix.com", true, true)) ==
            WidevineRequest::kHold);
}

- (void)testAnExplicitChromeSiteKeepsWidevine {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("spotify.com", true, false)) ==
            WidevineRequest::kAllow);
}

- (void)testChromeOverridesALearnedWidevineEntry {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("both.example", true, false)) ==
            WidevineRequest::kAllow);
}

- (void)testACrossSiteFrameKeepsWidevine {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("player.example", false, false)) ==
            WidevineRequest::kAllow);
}

- (void)testAFrameWithoutASiteKeepsWidevine {
  PARC_CHECK(DecideWidevineRequest(Lists(), Frame("", true, false)) ==
            WidevineRequest::kAllow);
}

- (void)testTheUserAgentIncludesTheRequestedSafariVersion {
  PARC_CHECK(SafariUserAgent("27.2") ==
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 "
            "Safari/605.1.15");
}

- (void)testAMajorMinorVersionIsAccepted {
  PARC_CHECK(IsSafariVersion("27.2"));
}

- (void)testAPatchVersionIsAccepted {
  PARC_CHECK(IsSafariVersion("26.0.1"));
}

- (void)testAMajorVersionAloneIsRejected {
  PARC_CHECK(!IsSafariVersion("27"));
}

- (void)testAnEmptyVersionIsRejected {
  PARC_CHECK(!IsSafariVersion(""));
}

- (void)testAnEmptyVersionComponentIsRejected {
  PARC_CHECK(!IsSafariVersion("27..2"));
}

- (void)testALeadingVersionDotIsRejected {
  PARC_CHECK(!IsSafariVersion(".27"));
}

- (void)testATrailingVersionDotIsRejected {
  PARC_CHECK(!IsSafariVersion("27.2."));
}

- (void)testSpacesInAVersionAreRejected {
  PARC_CHECK(!IsSafariVersion("27.2 x"));
}

- (void)testNewlinesInAVersionAreRejected {
  PARC_CHECK(!IsSafariVersion("27.2\r\nX: y"));
}

- (void)testAFourPartVersionIsRejected {
  PARC_CHECK(!IsSafariVersion("1.2.3.4"));
}

@end

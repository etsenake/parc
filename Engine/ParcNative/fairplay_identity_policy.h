// Copyright 2026 Parc contributors.
// Which identity, Chrome's or Safari's, a document presents, and what a
// Widevine request from a Chrome-identity frame does. Sites offer Apple
// FairPlay only to Safari, so Parc presents Safari's identity to the sites it
// learned need FairPlay and stays Chrome everywhere else
// (docs/fairplay-identity.md). No AppKit or Chromium dependency, so the rules
// are checked by tests/FairPlayIdentity without a browser.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_POLICY_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_POLICY_H_

#include <set>
#include <string>

namespace parc::fairplay_identity {

// One browsing context's sites, as registrable domains ("netflix.com").
// `safari` holds the learned sites; `chrome` holds the sites the user moved
// back to Chrome's identity, which learning never adds again. A site in both
// stays Chrome: the user's choice wins.
struct SiteLists {
  std::set<std::string> safari;
  std::set<std::string> chrome;
};

inline bool PresentsSafari(const SiteLists& lists, const std::string& site) {
  return !site.empty() && lists.safari.count(site) && !lists.chrome.count(site);
}

// A navigation about to start in one frame.
struct FrameNavigation {
  bool main_frame = false;
  // The registrable domain of the URL being loaded; empty for URLs without
  // one (about:, data:, javascript:, file:, chrome:), which load into their
  // parent's document process.
  std::string site;
  // For a subframe: the URL is on the main document's site, scheme included,
  // as Chromium's site isolation compares it. Also true for every subframe
  // when Chromium doesn't give each site its own process (site isolation
  // turned off), since then every frame shares the main document's process.
  bool same_site_as_main = false;
  // For a subframe: the identity of the page's committed main document, and
  // the identity the parent frame presents now.
  bool main_frame_safari = false;
  bool parent_safari = false;
};

// A subframe on the main document's site follows the main document, and a
// frame without a site (about:blank, srcdoc, data:) follows its parent. A
// frame from another site keeps Chrome's identity, so a Safari site embedded
// by another site's page stays Chrome. Parc's renderer applies the override
// to each frame from the document of its local root, the main frame or the
// frame at the top of its process's part of the page
// (RenderFrameImpl::ShouldUseUserAgentOverride as Parc patches it), so a
// frame on the main document's site that Chromium puts in a process of its
// own (sandboxed without allow-same-origin, or isolated by a response header)
// presents what its navigation chose. Choosing the request headers the same
// way keeps every frame's headers equal to what its scripts see.
inline bool NavigationPresentsSafari(const SiteLists& lists,
                                     const FrameNavigation& navigation) {
  if (navigation.main_frame) {
    return PresentsSafari(lists, navigation.site);
  }
  if (navigation.site.empty()) {
    return navigation.parent_safari;
  }
  return navigation.main_frame_safari && navigation.same_site_as_main;
}

// What happens to a page's request for a Widevine CDM.
enum class WidevineRequest {
  // Let Chromium create the CDM.
  kAllow,
  // Keep the CDM from being created, so no Widevine license request leaves.
  kHold,
  // Hold it, learn the site and reload its pages with Safari's identity.
  kHoldAndLearn,
};

struct WidevineRequestFrame {
  // The site of the page's main document; empty when it has none.
  std::string site;
  // The frame presents the main document's identity (the main document, a
  // frame on its site, or a frame without a site inside one of those), so
  // reloading the page gives it Safari's identity. A frame from another site
  // keeps Chrome's identity whatever the lists say.
  bool follows_main_frame = false;
  // The page's main document already presents Safari's identity.
  bool page_safari = false;
};

inline WidevineRequest DecideWidevineRequest(const SiteLists& lists,
                                             const WidevineRequestFrame& frame) {
  if (frame.site.empty() || !frame.follows_main_frame ||
      lists.chrome.count(frame.site)) {
    return WidevineRequest::kAllow;
  }
  // Safari's identity hides Widevine, so a request from it means the page
  // reached Widevine anyway; holding it never lets a license request out, and
  // reloading would repeat the same request.
  if (frame.page_safari) {
    return WidevineRequest::kHold;
  }
  return WidevineRequest::kHoldAndLearn;
}

// Safari's user agent on macOS: WebKit's application-independent part, with
// the macOS version frozen at 10_15_7 as every Safari since Big Sur reports
// it, then Safari's own "Version/<Safari version> Safari/605.1.15" suffix.
// The version is Safari's CFBundleShortVersionString (27.2 on macOS 27.2).
inline std::string SafariUserAgent(const std::string& safari_version) {
  return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
         "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/" +
         safari_version + " Safari/605.1.15";
}

// A Safari version string is digits separated by single dots ("27.2",
// "26.0.1"); anything else is refused so a damaged bundle cannot put
// arbitrary text into request headers.
inline bool IsSafariVersion(const std::string& version) {
  if (version.empty() || version.size() > 16 || version.front() == '.' ||
      version.back() == '.') {
    return false;
  }
  bool previous_dot = false;
  int dots = 0;
  for (char c : version) {
    if (c == '.') {
      if (previous_dot) {
        return false;
      }
      previous_dot = true;
      ++dots;
    } else if (c >= '0' && c <= '9') {
      previous_dot = false;
    } else {
      return false;
    }
  }
  return dots >= 1 && dots <= 2;
}

}  // namespace parc::fairplay_identity

#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_FAIRPLAY_IDENTITY_POLICY_H_

// Copyright 2026 Parc contributors.
// Parc presents Safari's identity to the sites that need Apple FairPlay
// (docs/fairplay-identity.md). The browser chooses it per navigation through
// Chromium's user agent override, which also drops the UA client hints, so a
// document, the frames sharing its process and its workers see Safari's user
// agent string. The rest of what Safari lacks or reports differently follows
// from that string here, so every surface of one context stays consistent:
// navigator.vendor, no navigator.userAgentData, no Widevine.
// Installed at third_party/blink/renderer/core/frame/parc_safari_identity.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_

#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

// Safari's user agent ends "Version/27.2 Safari/605.1.15" after WebKit's
// "AppleWebKit/605.1.15". Chromium-based and other browsers that mention
// Safari also name themselves, so a Safari user agent is one with all three
// and none of those names. A DevTools override with Safari's user agent
// matches too, which makes that emulation faithful.
inline bool IsParcSafariIdentityUserAgent(const String& user_agent) {
  return user_agent.contains("AppleWebKit/") &&
         user_agent.contains(" Version/") && user_agent.contains(" Safari/") &&
         !user_agent.contains("Chrome/") && !user_agent.contains("Chromium/") &&
         !user_agent.contains("CriOS/") && !user_agent.contains("FxiOS/") &&
         !user_agent.contains("EdgiOS/");
}

// Key systems Safari never offers. Sites probe Widevine before FairPlay and
// choose it when it answers, so it must be absent under Safari's identity.
inline bool IsParcSafariHiddenKeySystem(const String& key_system) {
  return key_system == "com.widevine.alpha" ||
         key_system.starts_with("com.widevine.alpha.");
}

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_

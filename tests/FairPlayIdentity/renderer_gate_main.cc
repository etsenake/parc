// Checks the renderer's gate for the scripts a Safari-identity document gets
// (fairplay-identity-blink.patch, InstallParcSafariScripts): the real
// IsParcSafariIdentityUserAgent from Engine/ParcRenderer/parc_safari_identity.h
// (over a stand-in WTF::String in blink_stub/), the real script constants, and
// the user agent Parc sends for Safari's identity. A Safari-identity document
// gets ManagedMediaSource and WebKitMediaKeys; Chrome's identity and other
// browsers' user agents get neither. webkit_media_keys.mjs runs the script.
// It also checks which EME init data types a document may name: FairPlay's
// "sinf" and "skd" only under Safari's identity.
#include "fairplay_identity_policy.h"
#include "parc_managed_media_source.h"
#include "parc_safari_identity.h"
#include "parc_webkit_media_keys.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

unsigned checks = 0;

void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

// The decision and loop of InstallParcSafariScripts, for a main world whose
// document can run scripts.
std::vector<std::string> ScriptsFor(const std::string& user_agent) {
  std::vector<std::string> scripts;
  if (blink::IsParcSafariIdentityUserAgent(blink::String(user_agent))) {
    for (const char* source :
         {blink::kParcManagedMediaSourceScript, blink::kParcWebKitMediaKeysScript}) {
      scripts.emplace_back(source);
    }
  }
  return scripts;
}

// requestMediaKeySystemAccess's initDataTypes and generateRequest's
// initDataType after Parc's gate (fairplay-identity-blink.patch): the name is
// one media::StringToEmeInitDataType registers (fairplay-media.patch), and
// FairPlay's own only under Safari's identity.
bool InitDataTypeRegistered(const std::string& user_agent,
                            const std::string& type) {
  const bool registered = type == "cenc" || type == "keyids" ||
                          type == "webm" || type == "sinf" || type == "skd";
  return registered &&
         (!blink::IsParcSafariOnlyInitDataType(blink::String(type)) ||
          blink::IsParcSafariIdentityUserAgent(blink::String(user_agent)));
}

// Each script installs its global unless the page already has one.
bool Installs(const std::vector<std::string>& scripts, const char* global) {
  const std::string guard = std::string("'") + global + "' in g";
  for (const std::string& script : scripts) {
    if (script.find(guard) != std::string::npos) {
      return true;
    }
  }
  return false;
}

}  // namespace

int main() {
  // What Parc's browser sends for a Safari site (fairplay_identity.mm builds
  // it with SafariUserAgent from the installed Safari's version).
  for (const char* version : {"27.2", "26.0.1"}) {
    const std::vector<std::string> safari =
        ScriptsFor(parc::fairplay_identity::SafariUserAgent(version));
    Check(safari.size() == 2, "a Safari-identity document gets both scripts");
    Check(Installs(safari, "WebKitMediaKeys"),
          "a Safari-identity document gets WebKitMediaKeys");
    Check(Installs(safari, "ManagedMediaSource"),
          "a Safari-identity document gets ManagedMediaSource");
  }
  for (const char* version : {"27.2", "26.0.1"}) {
    const std::string safari =
        parc::fairplay_identity::SafariUserAgent(version);
    for (const char* type : {"sinf", "skd", "cenc", "keyids"}) {
      Check(InitDataTypeRegistered(safari, type),
            "a Safari-identity document may name sinf, skd, cenc and keyids");
    }
    // EME compares init data types case-sensitively, as WebKit does.
    for (const char* type : {"SINF", "Skd", "sinf ", ""}) {
      Check(!InitDataTypeRegistered(safari, type),
            "other spellings of sinf and skd stay unregistered");
    }
  }
  Check(std::strstr(blink::kParcWebKitMediaKeysScript,
                    "isTypeSupported(keySystem, type = undefined)") != nullptr,
        "the script defines the static isTypeSupported");

  const char* const not_safari[] = {
      // Chrome's identity (Parc's own user agent everywhere else).
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chromium/144.0.0.0 Safari/537.36",
      // Browsers on iOS name themselves next to Safari's tokens.
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/144.0.0.0 Version/18.0 "
      "Mobile/15E148 Safari/604.1",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/140.0 Version/18.0 "
      "Mobile/15E148 Safari/605.1.15",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/140.0 Version/18.0 "
      "Mobile/15E148 Safari/605.1.15",
      // Firefox, and an empty user agent.
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:140.0) Gecko/20100101 "
      "Firefox/140.0",
      "",
  };
  for (const char* user_agent : not_safari) {
    Check(ScriptsFor(user_agent).empty(),
          "documents not presenting Safari's identity get neither script");
    Check(!InitDataTypeRegistered(user_agent, "sinf") &&
              !InitDataTypeRegistered(user_agent, "skd"),
          "documents not presenting Safari's identity can't name sinf or skd");
    Check(InitDataTypeRegistered(user_agent, "cenc") &&
              InitDataTypeRegistered(user_agent, "keyids"),
          "every document keeps cenc and keyids");
  }

  std::printf("renderer gate: %u checks passed\n", checks);
  return 0;
}

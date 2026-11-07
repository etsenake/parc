// Checks the renderer's gate for the scripts a Safari-identity document gets
// (fairplay-identity-blink.patch, InstallParcSafariScripts): the real
// IsParcSafariIdentityUserAgent from Engine/ParcRenderer/parc_safari_identity.h
// (over a stand-in WTF::String in blink_stub/), the real script constants, and
// the user agent Parc sends for Safari's identity. A Safari-identity document
// gets ManagedMediaSource, WebKitMediaKeys, Safari's MediaKeys (no
// getStatusForPolicy), Safari's video presentation API and its AirPlay
// availability event; Chrome's identity and other browsers' user agents get
// none of them. webkit_media_keys.mjs, safari_media_keys.mjs,
// webkit_presentation.mjs and webkit_playback_target.mjs run the scripts.
// It also checks which EME init data types a document may name: FairPlay's
// "sinf", "skd" and "mpts" only under Safari's identity, and that a Media Source
// element there hears `encrypted` with "sinf" init data only, as in Safari;
// which encryptionScheme and sessionTypes values requestMediaKeySystemAccess
// takes there without a TypeError (WebKit's IDL enums); FairPlay's key
// system names; that "persistent-usage-record" is a session type only
// under Safari's identity; and WebKit's macOS spatial audio rule for
// decodingInfo's spatialRendering.
#include "fairplay_identity_policy.h"
#include "parc_managed_media_source.h"
#include "parc_safari_identity.h"
#include "parc_safari_media_keys.h"
#include "parc_webkit_media_keys.h"
#include "parc_webkit_playback_target.h"
#include "parc_webkit_presentation.h"

#include <algorithm>
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
         {blink::kParcManagedMediaSourceScript, blink::kParcWebKitMediaKeysScript,
          blink::kParcSafariMediaKeysScript,
          blink::kParcWebKitPresentationScript,
          blink::kParcWebKitPlaybackTargetScript}) {
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
                          type == "webm" || type == "sinf" || type == "skd" ||
                          type == "mpts";
  return registered &&
         (!blink::IsParcSafariOnlyInitDataType(blink::String(type)) ||
          blink::IsParcSafariIdentityUserAgent(blink::String(user_agent)));
}

// WebMediaPlayerImpl::OnEncryptedMediaInitData's gate (fairplay-media.patch)
// with HTMLMediaElement::PresentsParcSafariIdentity
// (fairplay-identity-blink.patch): the MP4 parser's "sinf" init data reaches
// a page only from a Media Source element of a Safari-identity document, and
// that element hears nothing else, as Safari's Media Source surfaces only
// sinf (SourceBufferPrivateAVFObjC, AudioVideoRendererAVFObjC::setInitData).
// Every other element hears "cenc" and "webm" as before, never "sinf".
enum class Load { kUrl, kMediaSource };
bool EncryptedEventDelivered(const std::string& user_agent,
                             Load load,
                             const std::string& type) {
  const bool safari_media_source =
      load == Load::kMediaSource &&
      blink::IsParcSafariIdentityUserAgent(blink::String(user_agent));
  return (type == "sinf") == safari_media_source;
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
    Check(safari.size() == 5, "a Safari-identity document gets all five scripts");
    Check(Installs(safari, "WebKitPlaybackTargetAvailabilityEvent"),
          "a Safari-identity document gets the AirPlay availability event");
    Check(Installs(safari, "WebKitMediaKeys"),
          "a Safari-identity document gets WebKitMediaKeys");
    Check(Installs(safari, "ManagedMediaSource"),
          "a Safari-identity document gets ManagedMediaSource");
    Check(std::find_if(safari.begin(), safari.end(),
                       [](const std::string& script) {
                         return script.find(
                                    "delete MediaKeysInterface.prototype."
                                    "getStatusForPolicy") != std::string::npos;
                       }) != safari.end(),
          "a Safari-identity document loses MediaKeys.getStatusForPolicy");
    Check(std::find_if(safari.begin(), safari.end(),
                       [](const std::string& script) {
                         return script.find("'webkitSetPresentationMode' in "
                                            "videoPrototype") !=
                                std::string::npos;
                       }) != safari.end(),
          "a Safari-identity document gets the video presentation API");
  }
  for (const char* version : {"27.2", "26.0.1"}) {
    const std::string safari =
        parc::fairplay_identity::SafariUserAgent(version);
    for (const char* type : {"sinf", "skd", "mpts", "cenc", "keyids"}) {
      Check(InitDataTypeRegistered(safari, type),
            "a Safari-identity document may name sinf, skd, mpts, cenc and "
            "keyids");
    }
    Check(EncryptedEventDelivered(safari, Load::kMediaSource, "sinf"),
          "a Safari-identity Media Source element hears sinf init data");
    Check(!EncryptedEventDelivered(safari, Load::kUrl, "sinf"),
          "a Safari-identity element playing a URL doesn't");
    Check(!EncryptedEventDelivered(safari, Load::kMediaSource, "cenc") &&
              !EncryptedEventDelivered(safari, Load::kMediaSource, "webm") &&
              !EncryptedEventDelivered(safari, Load::kMediaSource, "mpts"),
          "a Safari-identity Media Source element hears no cenc, webm or mpts");
    Check(EncryptedEventDelivered(safari, Load::kUrl, "cenc"),
          "a Safari-identity element playing a URL keeps Chromium's events");
    // EME compares init data types case-sensitively, as WebKit does.
    for (const char* type : {"SINF", "Skd", "sinf ", "MPTS", "mtps", ""}) {
      Check(!InitDataTypeRegistered(safari, type),
            "other spellings of sinf, skd and mpts stay unregistered");
    }
  }
  Check(std::strstr(blink::kParcWebKitMediaKeysScript,
                    "isTypeSupported(keySystem, type = undefined)") != nullptr,
        "the script defines the static isTypeSupported");

  // WebKit's MediaKeyEncryptionScheme and MediaKeySessionType enums.
  for (const char* scheme : {"cenc", "cbcs"}) {
    Check(blink::IsParcSafariEncryptionScheme(scheme),
          "cenc and cbcs are WebKit's encryption schemes");
  }
  for (const char* scheme : {"cbcs-1-9", "", "CBCS", "cens", "cbc1"}) {
    Check(!blink::IsParcSafariEncryptionScheme(scheme),
          "any other encryptionScheme is a TypeError under Safari's identity");
  }
  for (const char* type :
       {"temporary", "persistent-usage-record", "persistent-license"}) {
    Check(blink::IsParcSafariSessionType(type),
          "WebKit's three session types convert");
  }
  for (const char* type : {"", "Temporary", "persistent", "persistent-license "}) {
    Check(!blink::IsParcSafariSessionType(type),
          "any other session type is a TypeError under Safari's identity");
  }
  for (const char* key_system :
       {"com.apple.fps", "com.apple.fps.1_0", "com.apple.fps.3_0", "com.apple.fps."}) {
    Check(blink::IsParcFairPlayKeySystem(key_system),
          "com.apple.fps and names under it are FairPlay");
  }
  for (const char* key_system :
       {"com.apple.fpsx", "COM.APPLE.FPS", "com.apple", "org.w3c.clearkey", ""}) {
    Check(!blink::IsParcFairPlayKeySystem(key_system),
          "FairPlay's names compare case-sensitively");
  }
  // Safari's persistent-usage-record session type exists only under Safari's
  // identity, compared exactly as EME compares MediaKeySessionType values.
  Check(blink::IsParcSafariOnlySessionType("persistent-usage-record"),
        "persistent-usage-record is Safari-only");
  for (const char* type : {"temporary", "persistent-license",
                           "Persistent-Usage-Record", "persistent-usage-record ",
                           ""}) {
    Check(!blink::IsParcSafariOnlySessionType(type),
          "other session types are not Safari-only");
  }

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
          "documents not presenting Safari's identity get none of the scripts");
    Check(!InitDataTypeRegistered(user_agent, "sinf") &&
              !InitDataTypeRegistered(user_agent, "skd") &&
              !InitDataTypeRegistered(user_agent, "mpts"),
          "documents not presenting Safari's identity can't name sinf, skd or "
          "mpts");
    Check(InitDataTypeRegistered(user_agent, "cenc") &&
              InitDataTypeRegistered(user_agent, "keyids"),
          "every document keeps cenc and keyids");
    Check(!EncryptedEventDelivered(user_agent, Load::kMediaSource, "sinf") &&
              EncryptedEventDelivered(user_agent, Load::kMediaSource, "cenc") &&
              EncryptedEventDelivered(user_agent, Load::kMediaSource, "webm"),
          "other documents hear cenc and webm init data as before and never sinf");
  }

  // WebKit's macOS spatial audio rule for decodingInfo's spatialRendering:
  // the output device's sources against the configuration's channels.
  const std::vector<uint32_t> mono_or_stereo = {0x6d6f7374};  // 'most'
  const std::vector<uint32_t> multichannel = {0x6d6c7469};    // 'mlti'
  const std::vector<uint32_t> binaural = {0x62696e68};        // 'binh'
  Check(blink::IsParcSafariSpatialAudioSupported(mono_or_stereo, 2) &&
            blink::IsParcSafariSpatialAudioSupported(mono_or_stereo, 1),
        "mono or stereo sources spatialize one or two channels");
  Check(!blink::IsParcSafariSpatialAudioSupported(mono_or_stereo, 0),
        "no channel count, no spatial audio");
  Check(blink::IsParcSafariSpatialAudioSupported(multichannel, 5.1) &&
            !blink::IsParcSafariSpatialAudioSupported(multichannel, 2),
        "multichannel sources spatialize more than two channels");
  Check(!blink::IsParcSafariSpatialAudioSupported(binaural, 6) &&
            !blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>(), 2),
        "binaural sources or none spatialize nothing");

  std::printf("renderer gate: %u checks passed\n", checks);
  return 0;
}

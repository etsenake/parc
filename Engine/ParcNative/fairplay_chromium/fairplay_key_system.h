// FairPlay Streaming EME key system names, shared by the browser (CDM
// registration and routing), the renderer (key system info) and the GPU
// process (CDM factory). Header-only, so no layer links the playback core
// just to recognise the name.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_KEY_SYSTEM_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_KEY_SYSTEM_H_

#include <string_view>

namespace parc::fairplay {

// The base key system. Pages ask for it or for a versioned sub key system
// ("com.apple.fps.3_0").
inline constexpr char kFairPlayKeySystem[] = "com.apple.fps";

// Display name of the CDM in chrome://media-internals and CdmInfo.
inline constexpr char kFairPlayCdmDisplayName[] = "Apple FairPlay Streaming";

// Same rule as FairPlayCdm::IsKeySystemSupported in the core and WebKit's
// CDMFactoryFairPlayStreaming::supportsKeySystem: "com.apple.fps" or
// anything starting with "com.apple.fps." (the bare prefix too).
// Case-sensitive.
inline bool IsFairPlayKeySystem(std::string_view key_system) {
  constexpr std::string_view kBase(kFairPlayKeySystem);
  if (key_system == kBase) {
    return true;
  }
  return key_system.size() > kBase.size() &&
         key_system.substr(0, kBase.size()) == kBase &&
         key_system[kBase.size()] == '.';
}

}  // namespace parc::fairplay

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_KEY_SYSTEM_H_

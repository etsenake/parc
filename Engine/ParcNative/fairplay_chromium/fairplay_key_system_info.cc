// Installed by the reviewed overlay at
// //components/cdm/renderer/fairplay_key_system_info.cc.
#include "components/cdm/renderer/fairplay_key_system_info.h"

#include <utility>

#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"

using media::EmeConfig;
using media::EmeFeatureSupport;
using media::EmeInitDataType;
using media::EmeMediaType;
using media::SupportedCodecs;

namespace cdm {

FairPlayKeySystemInfo::FairPlayKeySystemInfo(
    SupportedCodecs codecs,
    base::flat_set<media::EncryptionScheme> encryption_schemes)
    : codecs_(codecs), encryption_schemes_(std::move(encryption_schemes)) {}

FairPlayKeySystemInfo::~FairPlayKeySystemInfo() = default;

std::string FairPlayKeySystemInfo::GetBaseKeySystemName() const {
  return parc::fairplay::kFairPlayKeySystem;
}

bool FairPlayKeySystemInfo::IsSupportedKeySystem(
    const std::string& key_system) const {
  return parc::fairplay::IsFairPlayKeySystem(key_system);
}

bool FairPlayKeySystemInfo::ShouldUseBaseKeySystemName() const {
  // The CDM gets the name the page asked for; any versioned name is served
  // the same way.
  return false;
}

bool FairPlayKeySystemInfo::IsSupportedInitDataType(
    EmeInitDataType init_data_type) const {
  // WebKit's FairPlay types ("cenc", "sinf", "skd"; fairplay-media.patch adds
  // the last two to EmeInitDataType, and Blink accepts them only from a
  // Safari-identity document) plus "keyids". Netflix and Apple TV+ send
  // "cenc".
  switch (init_data_type) {
    case EmeInitDataType::CENC:
    case EmeInitDataType::SINF:
    case EmeInitDataType::SKD:
      return (codecs_ & media::EME_CODEC_MP4_ALL) != 0;
    case EmeInitDataType::KEYIDS:
      return true;
    case EmeInitDataType::WEBM:
    case EmeInitDataType::UNKNOWN:
      return false;
  }
  return false;
}

EmeConfig::Rule FairPlayKeySystemInfo::GetEncryptionSchemeConfigRule(
    media::EncryptionScheme encryption_scheme) const {
  return encryption_schemes_.contains(encryption_scheme)
             ? EmeConfig::SupportedRule()
             : EmeConfig::UnsupportedRule();
}

SupportedCodecs FairPlayKeySystemInfo::GetSupportedCodecs() const {
  return codecs_;
}

EmeConfig::Rule FairPlayKeySystemInfo::GetRobustnessConfigRule(
    const std::string& key_system,
    EmeMediaType media_type,
    const std::string& requested_robustness,
    const bool* hw_secure_requirement) const {
  // FairPlay defines no robustness levels, so only the empty string is
  // supported (EME skips a capability with an unrecognized one). The pipeline
  // is registered as software secure, so it can't meet a hardware-secure
  // requirement either.
  if (!requested_robustness.empty() ||
      (hw_secure_requirement && *hw_secure_requirement)) {
    return EmeConfig::UnsupportedRule();
  }
  return EmeConfig::SupportedRule();
}

EmeConfig::Rule FairPlayKeySystemInfo::GetPersistentLicenseSessionSupport()
    const {
  return EmeConfig::UnsupportedRule();
}

EmeFeatureSupport FairPlayKeySystemInfo::GetPersistentStateSupport() const {
  // Nothing is persisted (temporary sessions, no AVContentKeySession storage),
  // so allowing it costs nothing and keeps pages that ask for it working.
  return EmeFeatureSupport::REQUESTABLE;
}

EmeFeatureSupport FairPlayKeySystemInfo::GetDistinctiveIdentifierSupport()
    const {
  return EmeFeatureSupport::NOT_SUPPORTED;
}

}  // namespace cdm

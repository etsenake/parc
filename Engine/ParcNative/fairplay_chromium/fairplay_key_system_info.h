// Installed by the reviewed overlay at
// //components/cdm/renderer/fairplay_key_system_info.h.
//
// KeySystemInfo for Apple FairPlay Streaming ("com.apple.fps" and its
// versioned sub key systems such as "com.apple.fps.3_0"), built from the
// capability the browser's CdmRegistry reports. The CDM and its renderer run
// in the GPU process's media service.
#ifndef COMPONENTS_CDM_RENDERER_FAIRPLAY_KEY_SYSTEM_INFO_H_
#define COMPONENTS_CDM_RENDERER_FAIRPLAY_KEY_SYSTEM_INFO_H_

#include <string>

#include "base/containers/flat_set.h"
#include "media/base/key_system_info.h"

namespace cdm {

class FairPlayKeySystemInfo : public media::KeySystemInfo {
 public:
  FairPlayKeySystemInfo(
      media::SupportedCodecs codecs,
      base::flat_set<media::EncryptionScheme> encryption_schemes);
  FairPlayKeySystemInfo(const FairPlayKeySystemInfo&) = delete;
  FairPlayKeySystemInfo& operator=(const FairPlayKeySystemInfo&) = delete;
  ~FairPlayKeySystemInfo() override;

  // media::KeySystemInfo implementation.
  std::string GetBaseKeySystemName() const override;
  bool IsSupportedKeySystem(const std::string& key_system) const override;
  bool ShouldUseBaseKeySystemName() const override;
  bool IsSupportedInitDataType(
      media::EmeInitDataType init_data_type) const override;
  media::EmeConfig::Rule GetEncryptionSchemeConfigRule(
      media::EncryptionScheme encryption_scheme) const override;
  media::SupportedCodecs GetSupportedCodecs() const override;
  media::EmeConfig::Rule GetRobustnessConfigRule(
      const std::string& key_system,
      media::EmeMediaType media_type,
      const std::string& requested_robustness,
      const bool* hw_secure_requirement) const override;
  media::EmeConfig::Rule GetPersistentLicenseSessionSupport() const override;
  media::EmeFeatureSupport GetPersistentStateSupport() const override;
  media::EmeFeatureSupport GetDistinctiveIdentifierSupport() const override;

 private:
  const media::SupportedCodecs codecs_;
  const base::flat_set<media::EncryptionScheme> encryption_schemes_;
};

}  // namespace cdm

#endif  // COMPONENTS_CDM_RENDERER_FAIRPLAY_KEY_SYSTEM_INFO_H_

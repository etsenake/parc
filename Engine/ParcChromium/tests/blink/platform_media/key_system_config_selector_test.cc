// Copyright 2026 Parc contributors.
// (Chromium Authors; BSD-style license in Chromium's LICENSE) and contains

#include "third_party/blink/public/platform/media/key_system_config_selector.h"

#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/strings/pattern.h"
#include "base/test/scoped_feature_list.h"
#include "build/build_config.h"
#include "media/base/cdm_config.h"
#include "media/base/eme_constants.h"
#include "media/base/key_systems.h"
#include "media/base/media_permission.h"
#include "media/base/media_switches.h"
#include "media/base/mime_util.h"
#include "media/cdm/clear_key_cdm_common.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/platform/web_content_settings_client.h"
#include "third_party/blink/public/platform/web_encrypted_media_types.h"
#include "third_party/blink/public/platform/web_media_key_system_configuration.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"

namespace blink {

namespace {

using ::media::EmeConfig;
using ::media::EmeConfigRuleState;
using ::media::EmeFeatureSupport;
using ::media::EmeInitDataType;
using ::media::EmeMediaType;
using MediaKeysRequirement = WebMediaKeySystemConfiguration::Requirement;
using EncryptionScheme = WebMediaKeySystemMediaCapability::EncryptionScheme;

const char kSupportedKeySystem[] = "keysystem.test.supported";
const char kSupportedSubKeySystem[] = "keysystem.test.supported.sub";

const char kSupportedRobustness[] = "supported";
const char kRecommendIdentifierRobustness[] = "recommend_identifier";
const char kRequireIdentifierRobustness[] = "require_identifier";
const char kDisallowedIdentifierRobustness[] = "disallow_identifier";
const char kDisallowIdentifierAndDisallowHwSecureCodecRobustness[] =
    "disallow_identifier_and_disallow_hw_secure_codec";
const char kDisallowIdentifierAndRequireHwSecureCodecRobustness[] =
    "disallow_identifier_and_require_hw_secure_codec";
const char kDisallowHwSecureCodecRobustness[] = "disallow_hw_secure_codec";
const char kRequireHwSecureCodecRobustness[] = "require_hw_secure_codec";
const char kRequireIdentifierAndHwSecureCodecRobustness[] =
    "require_identifier_and_hw_secure_codec";
const char kRequireIdentifierPersistenceAndHwSecureCodecRobustness[] =
    "require_identifier_persistence_and_hw_secure_codec";
const char kUnsupportedRobustness[] = "unsupported";

const char kSupportedAudioContainer[] = "audio/supported";
const char kUnsupportedContainer[] = "video/unsupported";
const char kInvalidContainer[] = "video/invalid";

const char kSupportedAudioCodec[] = "audio_codec";
const char kUnsupportedCodec[] = "unsupported_codec";
const char kInvalidCodec[] = "foo";
const char kRequireHwSecureCodec[] = "require_hw_secure_codec";
const char kDisallowHwSecureCodec[] = "disallow_hw_secure_codec";
const char kExtendedVideoCodecStripped[] = "video_extended_codec";
const char kUnsupportedByAesDecryptorCodec[] = "unsupported_by_aes_decryptor";

constexpr EncryptionScheme kSupportedEncryptionScheme = EncryptionScheme::kCenc;
constexpr EncryptionScheme kDisallowHwSecureCodecEncryptionScheme =
    EncryptionScheme::kCbcs;

media::EncryptionScheme ConvertEncryptionScheme(
    EncryptionScheme encryption_scheme) {
  switch (encryption_scheme) {
    case EncryptionScheme::kNotSpecified:
    case EncryptionScheme::kCenc:
      return media::EncryptionScheme::kCenc;
    case EncryptionScheme::kCbcs:
    case EncryptionScheme::kCbcs_1_9:
      return media::EncryptionScheme::kCbcs;
    case EncryptionScheme::kUnrecognized:
      break;
  }

  NOTREACHED();
}

bool IsValidContainerMimeType(const std::string& container_mime_type) {
  return container_mime_type != kInvalidContainer;
}

bool IsValidCodec(const std::string& codec) {
  return codec != kInvalidCodec;
}

bool IsCompatibleWithEmeMediaType(EmeMediaType media_type,
                                  const std::string& type) {
  if (media_type == EmeMediaType::AUDIO && base::MatchPattern(type, "video*"))
    return false;

  if (media_type == EmeMediaType::VIDEO && base::MatchPattern(type, "audio*"))
    return false;

  return true;
}

bool IsSupportedMediaType(const std::string& container_mime_type,
                          const std::string& codecs,
                          bool use_aes_decryptor) {
  if (container_mime_type == kInvalidContainer)
    return false;

  std::vector<std::string> codec_vector;
  media::SplitCodecs(codecs, &codec_vector);
  for (const std::string& codec : codec_vector) {
    DCHECK_NE(codec, kExtendedVideoCodecStripped)
        << "codecs passed into this function should not be stripped";

    if (codec == kInvalidCodec)
      return false;

    if (use_aes_decryptor && codec == kUnsupportedByAesDecryptorCodec)
      return false;
  }

  return true;
}

WebMediaKeySystemConfiguration EmptyConfiguration() {
  std::vector<WebEncryptedMediaSessionType> session_types;
  session_types.push_back(WebEncryptedMediaSessionType::kTemporary);

  WebMediaKeySystemConfiguration config;
  config.label = "";
  config.session_types = session_types;
  return config;
}

WebMediaKeySystemConfiguration UsableConfiguration() {
  std::vector<WebMediaKeySystemMediaCapability> audio_capabilities(1);
  audio_capabilities[0].mime_type = kSupportedAudioContainer;
  audio_capabilities[0].codecs = kSupportedAudioCodec;

  auto config = EmptyConfiguration();
  config.audio_capabilities = audio_capabilities;
  return config;
}

class FakeKeySystems : public media::KeySystems {
 public:
  ~FakeKeySystems() override = default;

  void UpdateIfNeeded(const std::string&, base::OnceClosure done_cb) override {
    std::move(done_cb).Run();
  }

  std::string GetBaseKeySystemName(
      const std::string& key_system) const override {
    DCHECK(IsSupportedKeySystem(key_system));
    return key_system == kSupportedSubKeySystem ? kSupportedKeySystem
                                                : key_system;
  }

  bool IsSupportedKeySystem(const std::string& key_system) const override {
    return key_system == media::kClearKeyKeySystem ||
           key_system == kSupportedKeySystem ||
           key_system == kSupportedSubKeySystem;
  }

  bool ShouldUseBaseKeySystemName(
      const std::string& key_system) const override {
    return key_system == kSupportedSubKeySystem;
  }

  bool CanUseAesDecryptor(const std::string& key_system) const override {
    return key_system == media::kClearKeyKeySystem;
  }

  bool IsSupportedInitDataType(const std::string& key_system,
                               EmeInitDataType init_data_type) const override {
    switch (init_data_type) {
      case EmeInitDataType::UNKNOWN:
      case EmeInitDataType::SINF:
      case EmeInitDataType::SKD:
      case EmeInitDataType::MPTS:
        return false;
      case EmeInitDataType::WEBM:
        return init_data_type_webm_supported_;
      case EmeInitDataType::CENC:
        return init_data_type_cenc_supported_;
      case EmeInitDataType::KEYIDS:
        return init_data_type_keyids_supported_;
    }
    NOTREACHED();
  }

  EmeConfig::Rule GetEncryptionSchemeConfigRule(
      const std::string& key_system,
      media::EncryptionScheme encryption_scheme) const override {
    if (encryption_scheme ==
        ConvertEncryptionScheme(kSupportedEncryptionScheme)) {
      return EmeConfig::SupportedRule();
    }

    if (encryption_scheme ==
        ConvertEncryptionScheme(kDisallowHwSecureCodecEncryptionScheme)) {
      return EmeConfig{.hw_secure_codecs = EmeConfigRuleState::kNotAllowed};
    }

    return EmeConfig::UnsupportedRule();
  }

  EmeConfig::Rule GetContentTypeConfigRule(
      const std::string& key_system,
      EmeMediaType media_type,
      const std::string& container_mime_type,
      const std::vector<std::string>& codecs) const override {
    DCHECK(IsValidContainerMimeType(container_mime_type))
        << "Invalid container mime type should not be passed in";

    if (container_mime_type == kUnsupportedContainer ||
        !IsCompatibleWithEmeMediaType(media_type, container_mime_type)) {
      return EmeConfig::UnsupportedRule();
    }

    bool hw_secure_codec_required_ = false;
    bool hw_secure_codec_not_allowed_ = false;

    for (const std::string& codec : codecs) {
      DCHECK(IsValidCodec(codec)) << "Invalid codec should not be passed in";

      if (codec == kUnsupportedCodec ||
          !IsCompatibleWithEmeMediaType(media_type, codec)) {
        return EmeConfig::UnsupportedRule();
      } else if (codec == kRequireHwSecureCodec) {
        hw_secure_codec_required_ = true;
      } else if (codec == kDisallowHwSecureCodec) {
        hw_secure_codec_not_allowed_ = true;
      }
    }

    if (hw_secure_codec_required_) {
      if (hw_secure_codec_not_allowed_) {
        return EmeConfig::UnsupportedRule();
      } else {
        return EmeConfig{.hw_secure_codecs = EmeConfigRuleState::kRequired};
      }
    }

    if (hw_secure_codec_not_allowed_) {
      return EmeConfig{.hw_secure_codecs = EmeConfigRuleState::kNotAllowed};
    }

    return EmeConfig::SupportedRule();
  }

  EmeConfig::Rule GetRobustnessConfigRule(
      const std::string& key_system,
      EmeMediaType media_type,
      const std::string& requested_robustness,
      const bool* hw_secure_requirement) const override {
    // TODO(crbug.com/40179944): Remove the `hw_secure_requirement` parameter.
    if (hw_secure_requirement && *hw_secure_requirement &&
        distinctive_identifier == EmeFeatureSupport::NOT_SUPPORTED) {
      return EmeConfig::UnsupportedRule();
    }
    if (requested_robustness.empty() ||
        requested_robustness == kSupportedRobustness) {
      return EmeConfig::SupportedRule();
    }
    if (requested_robustness == kRequireIdentifierRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kRequired};
    }
    if (requested_robustness == kRecommendIdentifierRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kRecommended};
    }
    if (requested_robustness == kDisallowedIdentifierRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kNotAllowed};
    }
    if (requested_robustness == kDisallowHwSecureCodecRobustness) {
      return EmeConfig{.hw_secure_codecs = EmeConfigRuleState::kNotAllowed};
    }
    if (requested_robustness ==
        kDisallowIdentifierAndDisallowHwSecureCodecRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kNotAllowed,
                       .hw_secure_codecs = EmeConfigRuleState::kNotAllowed};
    }
    if (requested_robustness ==
        kDisallowIdentifierAndRequireHwSecureCodecRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kNotAllowed,
                       .hw_secure_codecs = EmeConfigRuleState::kRequired};
    }
    if (requested_robustness == kRequireHwSecureCodecRobustness) {
      return EmeConfig{.hw_secure_codecs = EmeConfigRuleState::kRequired};
    }
    if (requested_robustness == kRequireIdentifierAndHwSecureCodecRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kRequired,
                       .hw_secure_codecs = EmeConfigRuleState::kRequired};
    }
    if (requested_robustness ==
        kRequireIdentifierPersistenceAndHwSecureCodecRobustness) {
      return EmeConfig{.identifier = EmeConfigRuleState::kRequired,
                       .persistence = EmeConfigRuleState::kRequired,
                       .hw_secure_codecs = EmeConfigRuleState::kRequired};
    }
    if (requested_robustness == kUnsupportedRobustness) {
      return EmeConfig::UnsupportedRule();
    }

    NOTREACHED();
  }

  EmeConfig::Rule GetPersistentLicenseSessionSupport(
      const std::string& key_system) const override {
    return persistent_license;
  }

  EmeConfig::Rule GetPersistentUsageRecordSessionSupport(
      const std::string& key_system) const override {
    return persistent_usage_record;
  }

  EmeFeatureSupport GetPersistentStateSupport(
      const std::string& key_system) const override {
    return persistent_state;
  }

  EmeFeatureSupport GetDistinctiveIdentifierSupport(
      const std::string& key_system) const override {
    return distinctive_identifier;
  }

  bool init_data_type_webm_supported_ = false;
  bool init_data_type_cenc_supported_ = false;
  bool init_data_type_keyids_supported_ = false;

  EmeConfig::Rule persistent_license = EmeConfig::UnsupportedRule();
  EmeConfig::Rule persistent_usage_record = EmeConfig::UnsupportedRule();

  EmeFeatureSupport persistent_state = EmeFeatureSupport::NOT_SUPPORTED;
  EmeFeatureSupport distinctive_identifier = EmeFeatureSupport::REQUESTABLE;
};

class FakeMediaPermission : public media::MediaPermission {
 public:
  void HasPermission(Type type,
                     PermissionStatusCB permission_status_cb) override {
    std::move(permission_status_cb).Run(is_granted);
  }

  void RequestPermission(Type type,
                         PermissionStatusCB permission_status_cb) override {
    requests++;
    std::move(permission_status_cb).Run(is_granted);
  }

  bool IsEncryptedMediaEnabled() override { return is_encrypted_media_enabled; }

#if BUILDFLAG(IS_WIN)
  void IsHardwareSecureDecryptionAllowed(
      IsHardwareSecureDecryptionAllowedCB cb) override {
    std::move(cb).Run(is_hardware_secure_decryption_allowed);
  }
#endif

  int requests = 0;
  bool is_granted = false;
  bool is_encrypted_media_enabled = true;
#if BUILDFLAG(IS_WIN)
  bool is_hardware_secure_decryption_allowed = true;
#endif
};

class FakeWebLocalFrameDelegate
    : public KeySystemConfigSelector::WebLocalFrameDelegate {
 public:
  FakeWebLocalFrameDelegate() = default;
  bool IsCrossOriginToOutermostMainFrame() override { return is_cross_origin_; }
  bool AllowStorageAccessSync(
      WebContentSettingsClient::StorageType storage_type) override {
    if (storage_type == WebContentSettingsClient::StorageType::kIndexedDB) {
      return local_storage_allowed_;
    }
    return true;
  }

  bool is_cross_origin_ = false;
  bool local_storage_allowed_ = true;
};

}

class ParcKeySystemConfigSelectorTest : public testing::Test {
 public:
  ParcKeySystemConfigSelectorTest()
      : key_systems_(std::make_unique<FakeKeySystems>()),
        media_permission_(std::make_unique<FakeMediaPermission>()),
        web_frame_delegate_(std::make_unique<FakeWebLocalFrameDelegate>()) {}
  ParcKeySystemConfigSelectorTest(const ParcKeySystemConfigSelectorTest&) =
      delete;
  ParcKeySystemConfigSelectorTest& operator=(
      const ParcKeySystemConfigSelectorTest&) = delete;

  void SelectConfig() {
    media_permission_->requests = 0;
    succeeded_count_ = 0;
    not_supported_count_ = 0;
    KeySystemConfigSelector key_system_config_selector(
        key_systems_.get(), media_permission_.get(),
        std::move(web_frame_delegate_));
    web_frame_delegate_ = std::make_unique<FakeWebLocalFrameDelegate>();

    key_system_config_selector.SetIsSupportedMediaTypeCBForTesting(
        BindRepeating(&IsSupportedMediaType));

    key_system_config_selector.SelectConfig(
        key_system_, configs_,
        BindOnce(&ParcKeySystemConfigSelectorTest::OnConfigSelected,
                 Unretained(this)));
  }

  void SelectConfigReturnsConfig() {
    SelectConfig();
    EXPECT_EQ(0, media_permission_->requests);
    EXPECT_EQ(1, succeeded_count_);
    EXPECT_EQ(0, not_supported_count_);
    ASSERT_NE(succeeded_count_, 0);
  }

  void SelectConfigReturnsError() {
    SelectConfig();
    EXPECT_EQ(0, media_permission_->requests);
    EXPECT_EQ(0, succeeded_count_);
    EXPECT_EQ(1, not_supported_count_);
    ASSERT_NE(not_supported_count_, 0);
  }

  void OnConfigSelected(KeySystemConfigSelector::Status status,
                        WebMediaKeySystemConfiguration* config,
                        media::CdmConfig*) {
    if (status == KeySystemConfigSelector::Status::kSupported) {
      succeeded_count_++;
      config_ = *config;
    } else {
      not_supported_count_++;
    }
  }

  std::unique_ptr<FakeKeySystems> key_systems_;
  std::unique_ptr<FakeMediaPermission> media_permission_;
  std::unique_ptr<FakeWebLocalFrameDelegate> web_frame_delegate_;

  WebString key_system_ = WebString::FromUtf8(kSupportedKeySystem);
  std::vector<WebMediaKeySystemConfiguration> configs_;

  WebMediaKeySystemConfiguration config_;

  int succeeded_count_;
  int not_supported_count_;
};

// Parc: Safari's FairPlay on macOS takes "persistent-license" beside
TEST_F(ParcKeySystemConfigSelectorTest,
       ParcSafariFairPlay_PersistentLicenseBesideTemporary) {
  key_systems_->persistent_state = EmeFeatureSupport::REQUESTABLE;
  key_systems_->persistent_usage_record =
      EmeConfig{.persistence = EmeConfigRuleState::kRequired};

  auto config = UsableConfiguration();
  config.parc_safari_fairplay = true;
  config.persistent_state = MediaKeysRequirement::kOptional;
  config.session_types = {WebEncryptedMediaSessionType::kTemporary,
                          WebEncryptedMediaSessionType::kPersistentLicense};
  configs_.push_back(config);

  SelectConfigReturnsConfig();
  EXPECT_EQ(MediaKeysRequirement::kRequired, config_.persistent_state);
  ASSERT_EQ(2u, config_.session_types.size());
  EXPECT_EQ(WebEncryptedMediaSessionType::kTemporary, config_.session_types[0]);
  EXPECT_EQ(WebEncryptedMediaSessionType::kPersistentLicense,
            config_.session_types[1]);
}

TEST_F(ParcKeySystemConfigSelectorTest,
       ParcSafariFairPlay_PersistentLicenseAlone) {
  key_systems_->persistent_state = EmeFeatureSupport::REQUESTABLE;
  key_systems_->persistent_usage_record =
      EmeConfig{.persistence = EmeConfigRuleState::kRequired};

  auto config = UsableConfiguration();
  config.parc_safari_fairplay = true;
  config.persistent_state = MediaKeysRequirement::kOptional;
  config.session_types = {WebEncryptedMediaSessionType::kPersistentLicense};
  configs_.push_back(config);

  SelectConfigReturnsError();
}

TEST_F(ParcKeySystemConfigSelectorTest,
       ParcSafariFairPlay_TemporaryAfterPersistentLicense) {
  key_systems_->persistent_state = EmeFeatureSupport::REQUESTABLE;
  key_systems_->persistent_usage_record =
      EmeConfig{.persistence = EmeConfigRuleState::kRequired};

  auto config = UsableConfiguration();
  config.parc_safari_fairplay = true;
  config.persistent_state = MediaKeysRequirement::kOptional;
  config.session_types = {WebEncryptedMediaSessionType::kPersistentLicense,
                          WebEncryptedMediaSessionType::kTemporary};
  configs_.push_back(config);

  SelectConfigReturnsError();
}

TEST_F(ParcKeySystemConfigSelectorTest,
       ParcSafariFairPlay_PersistentLicenseWithoutPersistentState) {
  key_systems_->persistent_state = EmeFeatureSupport::REQUESTABLE;
  key_systems_->persistent_usage_record = EmeConfig::UnsupportedRule();

  auto config = UsableConfiguration();
  config.parc_safari_fairplay = true;
  config.persistent_state = MediaKeysRequirement::kOptional;
  config.session_types = {WebEncryptedMediaSessionType::kTemporary,
                          WebEncryptedMediaSessionType::kPersistentLicense};
  configs_.push_back(config);

  SelectConfigReturnsError();
}

}

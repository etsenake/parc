#include "third_party/parc_fairplay/chromium/fairplay_cdm_info.h"

#include <memory>

#include "base/files/file_path.h"
#include "base/version.h"
#include "media/base/audio_codecs.h"
#include "media/base/cdm_capability.h"
#include "media/base/content_decryption_module.h"
#include "media/base/eme_constants.h"
#include "media/base/encryption_scheme.h"
#include "media/base/video_codecs.h"
#include "media/media_buildflags.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system_info.h"

namespace parc::fairplay {

namespace {

// It decodes with VideoToolbox and CoreAudio's protected decoders. AV1 is left
// out because only M3 and later decode it in hardware, which FairPlay
// requires.
media::CdmCapability FairPlayCapability() {
  media::CdmCapability capability;
  capability.audio_codecs = {media::AudioCodec::kAAC};
#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
  capability.audio_codecs.insert(media::AudioCodec::kAC3);
  capability.audio_codecs.insert(media::AudioCodec::kEAC3);
#endif  // BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
  // FLAC (clear, and protected through CoreAudio's qflc), Opus (clear:
  // CoreAudio has no protected Opus decoder) and ALAC (clear, and protected
  // through qlac) play through the FairPlay Renderer; Safari offers them where
  // AVFoundation plays them, and so do Safari-identity pages, which ask
  // AVFoundation besides.
  capability.audio_codecs.insert(media::AudioCodec::kFLAC);
  capability.audio_codecs.insert(media::AudioCodec::kOpus);
  capability.audio_codecs.insert(media::AudioCodec::kALAC);
  capability.video_codecs.emplace(media::VideoCodec::kH264,
                                  media::VideoCodecInfo());
#if BUILDFLAG(ENABLE_PLATFORM_HEVC)
  capability.video_codecs.emplace(media::VideoCodec::kHEVC,
                                  media::VideoCodecInfo());
#endif  // BUILDFLAG(ENABLE_PLATFORM_HEVC)
#if BUILDFLAG(ENABLE_PLATFORM_DOLBY_VISION)
  // Profile 5 only. The renderer can also play profile 8, but it isn't
  // offered.
  capability.video_codecs.emplace(
      media::VideoCodec::kDolbyVision,
      media::VideoCodecInfo({media::DOLBYVISION_PROFILE5}));
#endif  // BUILDFLAG(ENABLE_PLATFORM_DOLBY_VISION)
  capability.encryption_schemes = {media::EncryptionScheme::kCenc,
                                   media::EncryptionScheme::kCbcs};
  // persistent-usage-record is Safari's; the renderer offers it only to
  // Safari-identity pages in a process that can persist data.
  capability.session_types = {media::CdmSessionType::kTemporary,
                              media::CdmSessionType::kPersistentUsageRecord};
  return capability;
}

// FairPlayCapability()'s codecs as components/cdm's GetSupportedCodecs()
// gives them for Chrome's key systems.
media::SupportedCodecs FairPlayEmeCodecs() {
  media::SupportedCodecs codecs = media::EME_CODEC_AAC;
#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
  codecs |= media::EME_CODEC_AC3 | media::EME_CODEC_EAC3;
#endif  // BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
  codecs |= media::EME_CODEC_FLAC | media::EME_CODEC_OPUS |
            media::EME_CODEC_ALAC | media::EME_CODEC_AVC1;
#if BUILDFLAG(ENABLE_PLATFORM_HEVC)
  // No profiles listed means every profile.
  codecs |=
      media::EME_CODEC_HEVC_PROFILE_MAIN | media::EME_CODEC_HEVC_PROFILE_MAIN10;
#endif  // BUILDFLAG(ENABLE_PLATFORM_HEVC)
#if BUILDFLAG(ENABLE_PLATFORM_DOLBY_VISION)
  codecs |= media::EME_CODEC_DOLBY_VISION_PROFILE5;
#endif  // BUILDFLAG(ENABLE_PLATFORM_DOLBY_VISION)
  return codecs;
}

}  // namespace

content::CdmInfo GetFairPlayCdmInfo() {
  // Fixed, so FairPlay never shares per-CDM-type isolation with another CDM.
  constexpr media::CdmType kFairPlayCdmType{0x9c5f2a7d3e1b4f60ull,
                                            0x8a3d6e0f1c2b7a95ull};
  return content::CdmInfo(kFairPlayKeySystem,
                          content::CdmInfo::Robustness::kSoftwareSecure,
                          FairPlayCapability(),
                          /*supports_sub_key_systems=*/true,
                          kFairPlayCdmDisplayName, kFairPlayCdmType,
                          base::Version(), base::FilePath());
}

std::unique_ptr<media::KeySystemInfo> CreateFairPlayKeySystemInfo(
    bool can_persist_data) {
  return std::make_unique<FairPlayKeySystemInfo>(
      FairPlayEmeCodecs(), FairPlayCapability().encryption_schemes,
      /*persistent_usage_record=*/can_persist_data);
}

}  // namespace parc::fairplay

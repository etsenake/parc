// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/media_capabilities/parc_media_capabilities.cc.
#include "third_party/blink/renderer/modules/media_capabilities/parc_media_capabilities.h"

#include <algorithm>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

#include "media/base/video_codec_string_parsers.h"
#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom-blink.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_audio_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_capabilities_decoding_info.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_decoding_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_video_configuration.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/modules/encryptedmedia/media_key_system_access.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

namespace {

// Parc: WebKit's parseInteger (StringToIntegerConversion.h) for unsigned
// types: ASCII whitespace around, an optional '+', at least one digit of
// `base`, no overflow, nothing else.
template <typename T>
std::optional<T> ParcParseUnsigned(std::string_view text, unsigned base = 10) {
  auto is_space = [](char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\f' || c == '\r';
  };
  auto digit = [base](char c) -> int {
    int value = 99;
    if (c >= '0' && c <= '9') {
      value = c - '0';
    } else if (c >= 'a' && c <= 'z') {
      value = c - 'a' + 10;
    } else if (c >= 'A' && c <= 'Z') {
      value = c - 'A' + 10;
    }
    return value < static_cast<int>(base) ? value : -1;
  };
  while (!text.empty() && is_space(text.front())) {
    text.remove_prefix(1);
  }
  if (!text.empty() && text.front() == '+') {
    text.remove_prefix(1);
  }
  if (text.empty() || digit(text.front()) < 0) {
    return std::nullopt;
  }
  uint64_t value = 0;
  while (!text.empty() && digit(text.front()) >= 0) {
    value = value * base + static_cast<uint64_t>(digit(text.front()));
    if (value > std::numeric_limits<T>::max()) {
      return std::nullopt;
    }
    text.remove_prefix(1);
  }
  while (!text.empty() && is_space(text.front())) {
    text.remove_prefix(1);
  }
  if (!text.empty()) {
    return std::nullopt;
  }
  return static_cast<T>(value);
}

// WTF's StringView::split('.'): the non-empty pieces.
std::vector<std::string_view> ParcSplitCodec(std::string_view codec) {
  std::vector<std::string_view> pieces;
  size_t start = 0;
  while (start <= codec.size()) {
    size_t end = codec.find('.', start);
    if (end == std::string_view::npos) {
      end = codec.size();
    }
    if (end > start) {
      pieces.push_back(codec.substr(start, end - start));
    }
    start = end + 1;
  }
  return pieces;
}

// Parc: WebKit's MediaCapabilitiesDecodingInfo for a document presenting
// Safari's identity carries the configuration as WebKit read it (its
// MediaDecodingConfiguration, VideoConfiguration with alphaChannel and
// AudioConfiguration) and no keySystemAccess.
MediaDecodingConfiguration* ParcSafariEchoConfiguration(
    const MediaDecodingConfiguration* config) {
  auto* echo = MediaDecodingConfiguration::Create();
  echo->setType(config->type());
  if (config->hasVideo()) {
    const VideoConfiguration* video = config->video();
    auto* copy = VideoConfiguration::Create();
    copy->setContentType(video->contentType());
    copy->setWidth(video->width());
    copy->setHeight(video->height());
    copy->setBitrate(video->bitrate());
    copy->setFramerate(video->framerate());
    if (video->hasAlphaChannel()) {
      copy->setAlphaChannel(video->alphaChannel());
    }
    if (video->hasHdrMetadataType()) {
      copy->setHdrMetadataType(video->hdrMetadataType());
    }
    if (video->hasColorGamut()) {
      copy->setColorGamut(video->colorGamut());
    }
    if (video->hasTransferFunction()) {
      copy->setTransferFunction(video->transferFunction());
    }
    echo->setVideo(copy);
  }
  if (config->hasAudio()) {
    const AudioConfiguration* audio = config->audio();
    auto* copy = AudioConfiguration::Create();
    copy->setContentType(audio->contentType());
    if (audio->hasChannels()) {
      copy->setChannels(audio->channels());
    }
    if (audio->hasBitrate()) {
      copy->setBitrate(audio->bitrate());
    }
    if (audio->hasSamplerate()) {
      copy->setSamplerate(audio->samplerate());
    }
    if (audio->hasSpatialRendering()) {
      copy->setSpatialRendering(audio->spatialRendering());
    }
    echo->setAudio(copy);
  }
  return echo;
}

}  // namespace

std::optional<ParcHevcParameters> ParcParseHevc(std::string_view codec) {
  const std::vector<std::string_view> pieces = ParcSplitCodec(codec);
  if (pieces.empty() || (pieces[0] != "hvc1" && pieces[0] != "hev1") ||
      pieces.size() < 2) {
    return std::nullopt;
  }
  ParcHevcParameters parameters;
  std::string_view profile = pieces[1];
  if (profile[0] >= 'A' && profile[0] <= 'C') {
    parameters.profile_space = 1 + (profile[0] - 'A');
    profile.remove_prefix(1);
  }
  const std::optional<uint8_t> idc = ParcParseUnsigned<uint8_t>(profile);
  if (!idc || pieces.size() < 3) {
    return std::nullopt;
  }
  parameters.profile_idc = *idc;
  const std::optional<uint32_t> flags =
      ParcParseUnsigned<uint32_t>(pieces[2], 16);
  if (!flags || pieces.size() < 4) {
    return std::nullopt;
  }
  uint32_t reversed = 0;
  for (int bit = 0; bit < 32; ++bit) {
    if (*flags & (1u << bit)) {
      reversed |= 1u << (31 - bit);
    }
  }
  parameters.compatibility_flags = reversed;
  const std::string_view tier = pieces[3];
  if (tier[0] != 'L' && tier[0] != 'H') {
    return std::nullopt;
  }
  const std::optional<uint8_t> level =
      ParcParseUnsigned<uint8_t>(tier.substr(1));
  if (!level) {
    return std::nullopt;
  }
  parameters.level_idc = *level;
  for (size_t i = 4; i < pieces.size() && i < 10; ++i) {
    if (!ParcParseUnsigned<uint8_t>(pieces[i], 16)) {
      return std::nullopt;
    }
  }
  return parameters;
}

std::optional<ParcDoViParameters> ParcParseDoVi(std::string_view codec) {
  const std::vector<std::string_view> pieces = ParcSplitCodec(codec);
  if (pieces.empty()) {
    return std::nullopt;
  }
  if (codec.starts_with("dav1.10.") || codec.starts_with("dvh1.20.") ||
      codec.starts_with("dvhe.20.")) {
    const auto parsed = media::ParseDolbyVisionCodecId(codec);
    if (!parsed) {
      return std::nullopt;
    }
    return ParcDoViParameters{
        static_cast<uint8_t>(pieces[0] == "dav1" ? 10 : 20),
        static_cast<uint8_t>(parsed->level)};
  }
  const bool avc = pieces[0] == "dva1" || pieces[0] == "dvav";
  if (!avc && pieces[0] != "dvh1" && pieces[0] != "dvhe" &&
      pieces[0] != "dav1") {
    return std::nullopt;
  }
  if (pieces.size() < 2) {
    return std::nullopt;
  }
  ParcDoViParameters parameters;
  const std::string_view profile = pieces[1];
  if (profile[0] == '0') {
    const std::optional<uint8_t> id = ParcParseUnsigned<uint8_t>(profile);
    if (!id) {
      return std::nullopt;
    }
    parameters.profile = *id;
  } else {
    const std::string_view name =
        codec.substr(0, std::min(codec.size(), 5 + profile.size()));
    if (name == "dvav.se") {
      parameters.profile = 9;
    } else if (name == "dvhe.dtb") {
      parameters.profile = 7;
    } else if (name == "dvhe.dtr") {
      parameters.profile = 4;
    } else if (name == "dvhe.st") {
      parameters.profile = 8;
    } else if (name == "dvhe.stn") {
      parameters.profile = 5;
    } else {
      return std::nullopt;
    }
  }
  uint8_t maximum_level = 0;
  switch (parameters.profile) {
    case 4:
    case 7:
      maximum_level = 9;
      break;
    case 5:
    case 8:
      maximum_level = 13;
      break;
    case 9:
      maximum_level = 5;
      break;
    default:
      return std::nullopt;
  }
  if ((parameters.profile == 9) != avc ||
      ((parameters.profile == 10) != (pieces[0] == "dav1")) ||
      pieces.size() < 3) {
    return std::nullopt;
  }
  const std::optional<uint8_t> level = ParcParseUnsigned<uint8_t>(pieces[2]);
  if (!level || *level > maximum_level) {
    return std::nullopt;
  }
  parameters.level = *level;
  return parameters;
}


MediaCapabilitiesDecodingInfo* ParcFinishDecodingInfo(
    MediaCapabilitiesDecodingInfo* info,
    ExecutionContext* context,
    const MediaDecodingConfiguration* config,
    MediaKeySystemAccess* access) {
  if (context && config &&
      IsParcSafariIdentityUserAgent(context->UserAgent())) {
    info->setConfiguration(ParcSafariEchoConfiguration(config));
  } else {
    info->setKeySystemAccess(access);
  }
  return info;
}

bool ParcSafariVideoAnswer(
    const MediaDecodingConfiguration* config,
    const VideoConfiguration* video,
    const String& codecs,
    const media::mojom::blink::ParcVideoToolboxDecodingFacts* facts,
    ParcDecodingAnswer& answer) {
  // WebKit wants exactly one codec, counting as ContentType::codecs()
  // does: the non-empty pieces between commas, each trimmed.
  String codec;
  wtf_size_t codec_count = 0;
  for (const String& piece : codecs.Split(',')) {
    if (!piece.empty()) {
      codec = piece.StripWhiteSpace();
      ++codec_count;
    }
  }
  if (codec_count != 1 || !codec.ContainsOnlyAsciiOrEmpty()) {
    return false;
  }
  answer.supported = true;
  const bool hdr = video->hasColorGamut() || video->hasHdrMetadataType() ||
                   video->hasTransferFunction();
  const bool alpha = video->hasAlphaChannel() && video->alphaChannel();
  const std::string ascii = codec.Ascii();
  if (codec.starts_with("hvc1") || codec.starts_with("hev1")) {
    // validateHEVCParameters (HEVCUtilitiesCocoa.mm).
    const std::optional<ParcHevcParameters> parameters =
        ParcParseHevc(ascii);
    if (!parameters || !facts) {
      return false;
    }
    if (hdr && !(parameters->profile_space == 0 &&
                 (parameters->profile_idc == 2 ||
                  parameters->compatibility_flags == 1))) {
      return false;  // HDR needs HEVC Main10.
    }
    if (!(alpha ? facts->hevc_with_alpha_decoder : facts->hevc_decoder) ||
        !facts->hevc_profiles) {
      return false;
    }
    const media::mojom::blink::ParcHevcProfileSupport* profile = nullptr;
    for (const auto& entry : *facts->hevc_profiles) {
      if (entry->profile_idc == parameters->profile_idc) {
        profile = entry.get();
        break;
      }
    }
    if (!profile) {
      return false;
    }
    answer.power_efficient = profile->hardware_accelerated;
    if (profile->has_max_decode_level &&
        parameters->level_idc > profile->max_decode_level) {
      return false;
    }
    answer.smooth = profile->has_max_playback_level &&
                    parameters->level_idc <= profile->max_playback_level;
  } else if (codec.starts_with("dvh1") || codec.starts_with("dvhe") ||
             codec.starts_with("dav1.10.")) {
    // validateDoViParameters (HEVCUtilitiesCocoa.mm).
    const std::optional<ParcDoViParameters> parameters = ParcParseDoVi(ascii);
    const bool extended_mse =
        config->type() == V8MediaDecodingType::Enum::kMediaSource &&
        parameters && (parameters->profile == 10 || parameters->profile == 20);
    if (!parameters || (parameters->profile != 5 && !extended_mse) ||
        (hdr && parameters->profile != 5) || alpha) {
      return false;
    }
    const bool vt_supported = facts && facts->hevc_decoder &&
        facts->dolby_vision_profiles && facts->dolby_vision_levels &&
        std::ranges::contains(*facts->dolby_vision_profiles, parameters->profile) &&
        std::ranges::contains(*facts->dolby_vision_levels, parameters->level);
    if (!extended_mse && !vt_supported) {
      return false;
    }
    // MSE accepts these new types independently of VT's Dolby profile list.
    // VT still determines smoothness and hardware efficiency.
    answer.smooth = vt_supported;
    answer.power_efficient = vt_supported && facts->dolby_vision_hardware;
  } else {
    // H.264: no alpha or HDR; VTIsHardwareDecodeSupported.
    if (alpha || hdr) {
      return false;
    }
    if (facts && facts->hardware_decode_query) {
      answer.power_efficient = facts->h264_hardware;
      answer.smooth = true;
    }
  }
  return true;
}

}  // namespace blink

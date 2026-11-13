// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/modules/media_capabilities/parc_media_capabilities.h"

#include <algorithm>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

#include "base/containers/span.h"
#include "media/base/mime_util.h"
#include "media/base/video_codec_string_parsers.h"
#include "media/filters/stream_parser_factory.h"
#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom-blink.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_resolver.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_audio_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_capabilities_decoding_info.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_decoding_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_video_configuration.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/execution_context/navigator_base.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/modules/encryptedmedia/media_key_system_access.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/network/mime/content_type.h"
#include "third_party/blink/renderer/platform/network/mime/mime_type_registry.h"
#include "third_party/blink/renderer/platform/network/parsed_content_type.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/text/string_to_number.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

namespace {

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

bool ParcCheckMseSupport(const String& mime_type, const String& codec) {
  base::span<const std::string> codecs;
  const std::string codec_ascii = codec.Ascii();
  if (!codec_ascii.empty()) {
    codecs = base::span_from_ref(codec_ascii);
  }
  return media::StreamParserFactory::IsTypeSupported(mime_type.Ascii(),
                                                     codecs) ==
         media::SupportsType::kSupported;
}

bool ParcParseContentType(const String& content_type,
                          String* mime_type,
                          String* codec) {
  ParsedContentType parsed_content_type(content_type);
  if (!parsed_content_type.IsValid() ||
      parsed_content_type.GetParameters().HasDuplicatedNames()) {
    return false;
  }
  *mime_type = parsed_content_type.MimeType().ToAsciiLower();
  *codec = parsed_content_type.ParameterValueForName("codecs");
  return true;
}

bool ParcSafariTypeSupported(const MediaDecodingConfiguration* config,
                             const String& content_type,
                             const String& mime_type,
                             const String& codec) {
  if (ParcSafariAV1Unavailable(codec)) {
    return false;
  }
  if (mime_type == "video/mp4" &&
      (codec.starts_with("dvh1.") || codec.starts_with("dvhe.") ||
       codec.starts_with("dav1.10."))) {
    const std::optional<ParcDoViParameters> parameters =
        codec.ContainsOnlyAsciiOrEmpty()
            ? ParcParseDoVi(codec.Ascii())
            : std::nullopt;
    if (parameters &&
        (parameters->profile == 5 ||
         (config->type() == V8MediaDecodingType::Enum::kMediaSource &&
          (parameters->profile == 10 || parameters->profile == 20)))) {
      return true;
    }
  }
  if (config->type() == V8MediaDecodingType::Enum::kMediaSource) {
    const std::string mime_ascii = mime_type.Ascii();
    if (media::StreamParserFactory::ParcIsOggType(mime_ascii)) {
      const std::string codec_ascii = codec.Ascii();
      return !codec_ascii.empty() &&
             media::StreamParserFactory::ParcSafariTakesOgg(
                 mime_ascii, base::span_from_ref(codec_ascii));
    }
    return ParcCheckMseSupport(mime_type, codec);
  }
  return HTMLMediaElement::GetSupportsType(ContentType(content_type)) ==
         MIMETypeRegistry::kSupported;
}

std::optional<ParcDecodingAnswer> ParcSafariAnswer(
    const MediaDecodingConfiguration* config,
    const media::mojom::blink::ParcVideoToolboxDecodingFacts* facts) {
  ParcDecodingAnswer answer;
  if (config->hasVideo()) {
    const VideoConfiguration* video = config->video();
    String mime_type;
    String codecs;
    if (!ParcParseContentType(video->contentType(), &mime_type, &codecs) ||
        !ParcSafariTypeSupported(config, video->contentType(), mime_type,
                                 codecs)) {
      return std::nullopt;
    }
    if (!ParcSafariVideoAnswer(config, video, codecs, facts, answer)) {
      return std::nullopt;
    }
  }
  if (config->hasAudio()) {
    const AudioConfiguration* audio = config->audio();
    String mime_type;
    String codec;
    if (!ParcParseContentType(audio->contentType(), &mime_type, &codec) ||
        !ParcSafariTypeSupported(config, audio->contentType(), mime_type,
                                 codec)) {
      return std::nullopt;
    }
    answer.supported = true;
  }
  return answer;
}

}

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
    const std::optional<ParcHevcParameters> parameters =
        ParcParseHevc(ascii);
    if (!parameters || !facts) {
      return false;
    }
    if (hdr && !(parameters->profile_space == 0 &&
                 (parameters->profile_idc == 2 ||
                  parameters->compatibility_flags == 1))) {
      return false;
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
    answer.smooth = vt_supported;
    answer.power_efficient = vt_supported && facts->dolby_vision_hardware;
  } else {
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

bool IsParcSafariFairPlayVideoCodec(const String& codec) {
  return codec.starts_with("avc1") || codec.starts_with("avc3") ||
         codec.starts_with("hvc1") || codec.starts_with("hev1") ||
         codec.starts_with("dvh1") || codec.starts_with("dvhe") ||
         codec.starts_with("dav1.10.");
}

const char ParcSafariMediaCapabilities::kSupplementName[] =
    "ParcSafariMediaCapabilities";

ParcSafariMediaCapabilities& ParcSafariMediaCapabilities::From(
    NavigatorBase& navigator) {
  ParcSafariMediaCapabilities* capabilities =
      Supplement<NavigatorBase>::From<ParcSafariMediaCapabilities>(navigator);
  if (!capabilities) {
    capabilities =
        MakeGarbageCollected<ParcSafariMediaCapabilities>(navigator);
    ProvideTo(navigator, capabilities);
  }
  return *capabilities;
}

ParcSafariMediaCapabilities::ParcSafariMediaCapabilities(
    NavigatorBase& navigator)
    : Supplement<NavigatorBase>(navigator),
      video_toolbox_(navigator.GetExecutionContext()) {}

void ParcSafariMediaCapabilities::Trace(Visitor* visitor) const {
  visitor->Trace(video_toolbox_);
  Supplement<NavigatorBase>::Trace(visitor);
}

ScriptPromise<MediaCapabilitiesDecodingInfo>
ParcSafariMediaCapabilities::DecodingInfo(
    ScriptState* script_state,
    const MediaDecodingConfiguration* config,
    ExceptionState& exception_state) {
  auto* resolver = MakeGarbageCollected<
      ScriptPromiseResolver<MediaCapabilitiesDecodingInfo>>(
      script_state, exception_state.GetContext());
  auto promise = resolver->Promise();
  if (facts_) {
    OnFacts(resolver, config,
                            facts_.Clone());
    return promise;
  }
  Bind(ExecutionContext::From(script_state));
  video_toolbox_->GetFacts(mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      BindOnce(&ParcSafariMediaCapabilities::OnFacts,
               WrapPersistent(this), WrapPersistent(resolver),
               WrapPersistent(config)),
      media::mojom::blink::ParcVideoToolboxDecodingFactsPtr()));
  return promise;
}

void ParcSafariMediaCapabilities::OnFacts(
    ScriptPromiseResolver<MediaCapabilitiesDecodingInfo>* resolver,
    const MediaDecodingConfiguration* config,
    media::mojom::blink::ParcVideoToolboxDecodingFactsPtr facts) {
  if (facts && !facts_) {
    facts_ = facts.Clone();
  }
  ExecutionContext* execution_context = resolver->GetExecutionContext();
  if (!execution_context || execution_context->IsContextDestroyed()) {
    return;
  }
  const std::optional<ParcDecodingAnswer> answer =
      ParcSafariAnswer(config, facts.get());
  if (answer && config->hasAudio() &&
      config->audio()->hasSpatialRendering() &&
      config->audio()->spatialRendering()) {
    Bind(execution_context);
    video_toolbox_->GetSpatialAudioSources(
        config->hasVideo(),
        mojo::WrapCallbackWithDefaultInvokeIfNotRun(
            BindOnce(&ParcSafariMediaCapabilities::OnSpatialAudioSources,
                     WrapPersistent(this), WrapPersistent(resolver),
                     WrapPersistent(config), answer->smooth,
                     answer->power_efficient),
            Vector<uint32_t>()));
    return;
  }
  auto* info = MediaCapabilitiesDecodingInfo::Create();
  info->setSupported(answer && answer->supported);
  info->setSmooth(answer && answer->smooth);
  info->setPowerEfficient(answer && answer->power_efficient);
  resolver->Resolve(
      ParcFinishDecodingInfo(info, execution_context, config, nullptr));
}

void ParcSafariMediaCapabilities::OnSpatialAudioSources(
    ScriptPromiseResolver<MediaCapabilitiesDecodingInfo>* resolver,
    const MediaDecodingConfiguration* config,
    bool smooth,
    bool power_efficient,
    const Vector<uint32_t>& sources) {
  ExecutionContext* execution_context = resolver->GetExecutionContext();
  if (!execution_context || execution_context->IsContextDestroyed()) {
    return;
  }
  const String channels =
      config->audio()->hasChannels() ? config->audio()->channels() : String();
  size_t parsed_length = 0;
  const double channel_count =
      channels.empty()
          ? 0
          : (channels.Is8Bit()
                 ? CharactersToDouble(channels.Span8(), parsed_length)
                 : CharactersToDouble(channels.Span16(), parsed_length));
  auto* info = MediaCapabilitiesDecodingInfo::Create();
  info->setSupported(IsParcSafariSpatialAudioSupported(
      sources, channel_count));
  info->setSmooth(smooth);
  info->setPowerEfficient(power_efficient);
  resolver->Resolve(
      ParcFinishDecodingInfo(info, execution_context, config, nullptr));
}

void ParcSafariMediaCapabilities::Bind(
    ExecutionContext* execution_context) {
  if (video_toolbox_.is_bound()) {
    return;
  }
  execution_context->GetBrowserInterfaceBroker().GetInterface(
      video_toolbox_.BindNewPipeAndPassReceiver(
          execution_context->GetTaskRunner(TaskType::kMediaElementEvent)));
}

}

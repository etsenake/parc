// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/modules/encryptedmedia/parc_encrypted_media.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#include "media/base/audio_codecs.h"
#include "media/base/eme_constants.h"
#include "media/base/media_types.h"
#include "media/base/mime_util.h"
#include "media/base/video_codecs.h"
#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom-blink.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_encrypted_media_types.h"
#include "third_party/blink/public/platform/web_media_key_system_configuration.h"
#include "third_party/blink/public/platform/web_media_key_system_media_capability.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_resolver.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_key_system_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_key_system_media_capability.h"
#include "third_party/blink/renderer/core/dom/dom_exception.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/modules/encryptedmedia/media_keys.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_remote.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/network/parsed_content_type.h"
#include "third_party/blink/renderer/platform/wtf/text/strcat.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/wtf_size_t.h"

namespace blink {

namespace {

bool IsParcPCMCodec(const String& codec) {
  return codec == "ipcm" || codec.starts_with("ipcm.") || codec == "fpcm" ||
         codec.starts_with("fpcm.");
}

bool IsParcFairPlayCodec(const String& codec, bool video) {
  if (codec.empty() || !codec.ContainsOnlyAsciiOrEmpty()) {
    return false;
  }
  if (video) {
    const std::optional<media::VideoType> parsed =
        media::ParseVideoCodecString("video/mp4", codec.Ascii());
    return parsed && (parsed->codec == media::VideoCodec::kH264 ||
                      parsed->codec == media::VideoCodec::kHEVC ||
                      (parsed->codec == media::VideoCodec::kDolbyVision &&
                       parsed->profile == media::DOLBYVISION_PROFILE5));
  }
  const std::optional<media::AudioType> parsed =
      media::ParseAudioCodecString("audio/mp4", codec.Ascii());
  return parsed && (parsed->codec == media::AudioCodec::kAAC ||
                    parsed->codec == media::AudioCodec::kAC3 ||
                    parsed->codec == media::AudioCodec::kEAC3 ||
                    parsed->codec == media::AudioCodec::kFLAC ||
                    parsed->codec == media::AudioCodec::kOpus ||
                    parsed->codec == media::AudioCodec::kALAC);
}

void ParcApplySafariFairPlayContentType(
    WebMediaKeySystemMediaCapability& capability,
    bool video) {
  const String content_type = capability.content_type;
  if (content_type.empty()) {
    return;
  }
  auto skip = [&capability] {
    capability.mime_type = WebString::FromAscii("application/x-parc-skipped");
    capability.codecs = WebString::FromAscii("parc.skipped");
  };
  ParsedContentType type(content_type);
  if (!type.IsValid() || type.GetParameters().HasDuplicatedNames()) {
    skip();
    return;
  }
  const String codecs = type.ParameterValueForName("codecs");
  if (type.GetParameters().ParameterCount() > (codecs.empty() ? 0u : 1u)) {
    skip();
    return;
  }
  String container = type.MimeType();
  if (EqualIgnoringAsciiCase(container, "application/vnd.apple.mpegurl") ||
      EqualIgnoringAsciiCase(container, "application/x-mpegurl")) {
    container = video ? "video/mp4" : "audio/mp4";
  }
  const char* const own_codec = video ? "avc1.42E01E" : "mp4a.40.2";
  if (codecs.empty()) {
    if (!EqualIgnoringAsciiCase(container, video ? "video/mp4" : "audio/mp4")) {
      skip();
      return;
    }
    capability.mime_type = container;
    capability.codecs = WebString::FromAscii(own_codec);
    return;
  }
  StringBuilder own_codecs;
  for (const String& entry : codecs.Split(',')) {
    const String codec = entry.StripWhiteSpace();
    if (IsParcFairPlayCodec(codec, !video) || IsParcPCMCodec(codec)) {
      continue;
    }
    if (!own_codecs.empty()) {
      own_codecs.Append(',');
    }
    own_codecs.Append(codec);
  }
  capability.mime_type = container;
  capability.codecs = own_codecs.empty()
                          ? WebString::FromAscii(own_codec)
                          : WebString(own_codecs.ToString());
}

}

void ParcApplyInitDataTypeRules(const MediaKeySystemConfiguration& config,
                                bool safari_identity,
                                bool refuse_empty_init_data_types,
                                WebMediaKeySystemConfiguration& web_config) {
  if (!safari_identity) {
    for (wtf_size_t j = 0; j < config.initDataTypes().size(); ++j) {
      if (IsParcSafariOnlyInitDataType(config.initDataTypes()[j])) {
        web_config.init_data_types[j] = media::EmeInitDataType::UNKNOWN;
      }
    }
  }
  if (refuse_empty_init_data_types && web_config.init_data_types.empty()) {
    web_config.init_data_types.push_back(media::EmeInitDataType::UNKNOWN);
  }
}

void ParcApplySafariOnlyAudioCodecs(
    bool safari_identity,
    WebMediaKeySystemConfiguration& web_config) {
  if (!safari_identity) {
    for (WebMediaKeySystemMediaCapability& capability :
         web_config.audio_capabilities) {
      if (IsParcSafariOnlyAudioCodecs(capability.codecs)) {
        capability.codecs = WebString::FromAscii("parc.safari-only");
      }
    }
  }
}

void ParcApplyFairPlayCapabilityRules(
    const String& key_system,
    bool safari_fairplay,
    bool is_from_media_capabilities,
    WebMediaKeySystemConfiguration& web_config) {
  if (safari_fairplay && !is_from_media_capabilities) {
    for (WebMediaKeySystemMediaCapability& capability :
         web_config.audio_capabilities) {
      ParcApplySafariFairPlayContentType(capability, false);
    }
    for (WebMediaKeySystemMediaCapability& capability :
         web_config.video_capabilities) {
      ParcApplySafariFairPlayContentType(capability, true);
    }
  }

  if (IsParcFairPlayKeySystem(key_system)) {
    for (std::vector<WebMediaKeySystemMediaCapability>* capabilities :
         {&web_config.audio_capabilities, &web_config.video_capabilities}) {
      for (WebMediaKeySystemMediaCapability& capability : *capabilities) {
        const String container = capability.mime_type;
        if (!EqualIgnoringAsciiCase(container, "audio/mp4") &&
            !EqualIgnoringAsciiCase(container, "video/mp4") &&
            !capability.content_type.IsEmpty()) {
          capability.mime_type =
              WebString::FromAscii("application/x-parc-skipped");
          capability.codecs = WebString::FromAscii("parc.skipped");
        }
      }
    }
  }

  if (safari_fairplay) {
    for (std::vector<WebMediaKeySystemMediaCapability>* capabilities :
         {&web_config.audio_capabilities, &web_config.video_capabilities}) {
      for (WebMediaKeySystemMediaCapability& capability : *capabilities) {
        if (capability.encryption_scheme !=
                WebMediaKeySystemMediaCapability::EncryptionScheme::
                    kNotSpecified &&
            capability.encryption_scheme !=
                WebMediaKeySystemMediaCapability::EncryptionScheme::kCbcs) {
          capability.encryption_scheme = WebMediaKeySystemMediaCapability::
              EncryptionScheme::kUnrecognized;
        }
      }
    }
  }
}

void ParcApplySafariOnlySessionTypes(
    const MediaKeySystemConfiguration& config,
    bool safari_identity,
    WebMediaKeySystemConfiguration& web_config) {
  if (!safari_identity) {
    for (wtf_size_t j = 0; j < config.sessionTypes().size(); ++j) {
      if (IsParcSafariOnlySessionType(config.sessionTypes()[j])) {
        web_config.session_types[j] = WebEncryptedMediaSessionType::kUnknown;
      }
    }
  }
}

bool ParcCheckSafariEnumValues(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations,
    ExceptionState& exception_state) {
  auto check_capabilities =
      [&exception_state](
          const HeapVector<Member<MediaKeySystemMediaCapability>>&
              capabilities) {
        for (const MediaKeySystemMediaCapability* capability : capabilities) {
          if (capability->hasEncryptionScheme() &&
              !capability->encryptionScheme().IsNull() &&
              !IsParcSafariEncryptionScheme(capability->encryptionScheme())) {
            exception_state.ThrowTypeError(StrCat(
                {"Failed to read the 'encryptionScheme' property from "
                 "'MediaKeySystemMediaCapability': The provided value '",
                 capability->encryptionScheme(),
                 "' is not a valid enum value of type "
                 "MediaKeyEncryptionScheme."}));
            return false;
          }
        }
        return true;
      };
  for (const MediaKeySystemConfiguration* config : supported_configurations) {
    if (!check_capabilities(config->audioCapabilities())) {
      return false;
    }
    if (config->hasSessionTypes()) {
      for (const String& session_type : config->sessionTypes()) {
        if (!IsParcSafariSessionType(session_type)) {
          exception_state.ThrowTypeError(StrCat(
              {"Failed to read the 'sessionTypes' property from "
               "'MediaKeySystemConfiguration': The provided value '",
               session_type,
               "' is not a valid enum value of type MediaKeySessionType."}));
          return false;
        }
      }
    }
    if (!check_capabilities(config->videoCapabilities())) {
      return false;
    }
  }
  return true;
}

Vector<ParcAVFoundationCheck> ParcAVFoundationChecks(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations) {
  Vector<ParcAVFoundationCheck> checks;
  for (wtf_size_t i = 0; i < supported_configurations.size(); ++i) {
    for (bool video : {false, true}) {
      const HeapVector<Member<MediaKeySystemMediaCapability>>& capabilities =
          video ? supported_configurations[i]->videoCapabilities()
                : supported_configurations[i]->audioCapabilities();
      for (wtf_size_t j = 0; j < capabilities.size(); ++j) {
        const String content_type = capabilities[j]->contentType();
        ParsedContentType type(content_type);
        if (content_type.empty() || !type.IsValid()) {
          continue;
        }
        const String container = type.MimeType();
        const bool hls =
            EqualIgnoringAsciiCase(container, "application/vnd.apple.mpegurl") ||
            EqualIgnoringAsciiCase(container, "application/x-mpegurl");
        const bool mp4 = EqualIgnoringAsciiCase(container, "video/mp4") ||
                         EqualIgnoringAsciiCase(container, "audio/mp4");
        if (hls || mp4) {
          checks.push_back(
              ParcAVFoundationCheck{i, video, j, content_type, hls});
        }
      }
    }
  }
  return checks;
}

void ParcApplyAVFoundationAnswers(
    const Vector<ParcAVFoundationCheck>& checks,
    const HashMap<String, bool>& answers,
    std::vector<WebMediaKeySystemConfiguration>& configurations) {
  for (const ParcAVFoundationCheck& check : checks) {
    std::vector<WebMediaKeySystemMediaCapability>& capabilities =
        check.video
            ? configurations[check.configuration].video_capabilities
            : configurations[check.configuration].audio_capabilities;
    if (check.index >= capabilities.size()) {
      continue;
    }
    WebMediaKeySystemMediaCapability& capability = capabilities[check.index];
    auto it = answers.find(check.content_type);
    if (it == answers.end() || !it->value) {
      capability.mime_type = WebString::FromAscii("application/x-parc-skipped");
      capability.codecs = WebString::FromAscii("parc.skipped");
    } else if (check.hls) {
      capability.mime_type =
          WebString::FromAscii(check.video ? "video/mp4" : "audio/mp4");
      capability.codecs =
          WebString::FromAscii(check.video ? "avc1.42E01E" : "mp4a.40.2");
    }
  }
}

namespace {

class ParcAVFoundationQueryImpl final : public ParcAVFoundationQuery {
 public:
  ParcAVFoundationQueryImpl(ExecutionContext* context,
                            Vector<ParcAVFoundationCheck> checks)
      : checks_(std::move(checks)), avfoundation_(context) {}

  bool Ask(ExecutionContext& context, DoneCallback done) override {
    if (checks_.empty() || asked_) {
      return false;
    }
    asked_ = true;
    done_ = std::move(done);
    context.GetBrowserInterfaceBroker().GetInterface(
        avfoundation_.BindNewPipeAndPassReceiver(
            context.GetTaskRunner(TaskType::kMediaElementEvent)));
    avfoundation_.set_disconnect_handler(BindOnce(
        &ParcAVFoundationQueryImpl::Apply, WrapWeakPersistent(this)));
    for (const ParcAVFoundationCheck& check : checks_) {
      if (answers_.Contains(check.content_type)) {
        continue;
      }
      answers_.Set(check.content_type, false);
      ++pending_;
      avfoundation_->IsPlayableExtendedMIMEType(
          check.content_type,
          BindOnce(&ParcAVFoundationQueryImpl::OnAnswer,
                   WrapWeakPersistent(this), check.content_type));
    }
    return true;
  }

  void Trace(Visitor* visitor) const override {
    visitor->Trace(avfoundation_);
    ParcAVFoundationQuery::Trace(visitor);
  }

 private:
  void OnAnswer(const String& content_type, bool playable) {
    answers_.Set(content_type, playable);
    if (pending_ && --pending_ == 0) {
      Apply();
    }
  }

  void Apply() {
    if (checks_.empty()) {
      return;
    }
    Vector<ParcAVFoundationCheck> checks = std::move(checks_);
    checks_.clear();
    avfoundation_.reset();
    std::move(done_).Run(checks, answers_);
  }

  Vector<ParcAVFoundationCheck> checks_;
  HashMap<String, bool> answers_;
  wtf_size_t pending_ = 0;
  bool asked_ = false;
  DoneCallback done_;
  HeapMojoRemote<media::mojom::blink::ParcVideoToolboxDecoding> avfoundation_;
};

}

ParcAVFoundationQuery* ParcAVFoundationQuery::CreateIfNeeded(
    ExecutionContext* context,
    const String& key_system,
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations) {
  if (!context || !IsParcSafariIdentityUserAgent(context->UserAgent()) ||
      !IsParcFairPlayKeySystem(key_system)) {
    return nullptr;
  }
  return MakeGarbageCollected<ParcAVFoundationQueryImpl>(
      context, ParcAVFoundationChecks(supported_configurations));
}

bool ParcRejectFairPlayPersistentLicense(
    ScriptState* script_state,
    const String& key_system,
    const WebMediaKeySystemConfiguration& configuration,
    ScriptPromiseResolver<MediaKeys>* resolver) {
  ExecutionContext* context = ExecutionContext::From(script_state);
  if (!context || !IsParcSafariIdentityUserAgent(context->UserAgent()) ||
      !IsParcFairPlayKeySystem(key_system) ||
      std::find(configuration.session_types.begin(),
                configuration.session_types.end(),
                WebEncryptedMediaSessionType::kPersistentLicense) ==
          configuration.session_types.end()) {
    return false;
  }
  context->GetTaskRunner(TaskType::kMediaElementEvent)
      ->PostTask(FROM_HERE,
                 BindOnce(
                     [](ScriptPromiseResolver<MediaKeys>* resolver) {
                       resolver->Reject(MakeGarbageCollected<DOMException>(
                           DOMExceptionCode::kNotAllowedError));
                     },
                     WrapPersistent(resolver)));
  return true;
}

}

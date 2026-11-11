// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/encryptedmedia/parc_encrypted_media.cc.
#include "third_party/blink/renderer/modules/encryptedmedia/parc_encrypted_media.h"

#include <optional>
#include <vector>

#include "media/base/audio_codecs.h"
#include "media/base/eme_constants.h"
#include "media/base/media_types.h"
#include "media/base/mime_util.h"
#include "media/base/video_codecs.h"
#include "third_party/blink/public/platform/web_encrypted_media_types.h"
#include "third_party/blink/public/platform/web_media_key_system_configuration.h"
#include "third_party/blink/public/platform/web_media_key_system_media_capability.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_key_system_configuration.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/platform/network/parsed_content_type.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/wtf_size_t.h"

namespace blink {

namespace {

// Parc: ISO 23003-5 PCM ('ipcm', 'fpcm'), which the FairPlay Renderer plays
// clear; protected it fails as in Safari, where CoreAudio has no protected PCM
// decoder either. No key system's codecs name it, so AVFoundation's answer
// alone decides.
bool IsParcPCMCodec(const String& codec) {
  return codec == "ipcm" || codec.starts_with("ipcm.") || codec == "fpcm" ||
         codec.starts_with("fpcm.");
}

// Parc: whether FairPlay plays `codec` (its CdmCapability in
// fairplay-media.patch): AAC, AC-3, E-AC-3, FLAC, Opus and ALAC audio; H.264,
// HEVC and Dolby Vision profile 5 video.
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

// Parc: how FairPlay judges a capability's contentType under Safari's
// identity, as WebKit does (CDMPrivate::getSupportedCapabilitiesForAudioVideo
// Type, then CDMInstanceFairPlayStreamingAVFObjC::supportsMediaCapability,
// where AVFoundation decides what plays), rewritten into the container and
// codecs Chromium's key system selector checks. content_type, which
// getConfiguration() returns, stays the page's.
// - An unparsable type, or one with a parameter besides a non-empty
//   "codecs", skips only this capability (Chromium would refuse the whole
//   configuration for the first).
// - The HLS types (application/vnd.apple.mpegurl, application/x-mpegurl) go
//   in either list as MP4: Parc's native HLS route plays them. Whether one
//   plays is then AVFoundation's call alone, and an MP4 type needs
//   AVFoundation's yes besides (MediaKeySystemAccessInitializer in
//   navigator_request_media_key_system_access.cc).
// - Without codecs, video/mp4 (video) and audio/mp4 (audio) are supported:
//   FairPlay plays a codec of each. Chromium requires codecs.
// - The codecs may include those of the other media type that FairPlay
//   plays, as AVFoundation plays muxed media; they are checked here and the
//   rest by the selector. With only those, the type is judged as the
//   container with a FairPlay codec of its own kind. PCM counts as one of
//   those in either list.
void ParcApplySafariFairPlayContentType(
    WebMediaKeySystemMediaCapability& capability,
    bool video) {
  const String content_type = capability.content_type;
  if (content_type.empty()) {
    return;  // Refuses the configuration, in WebKit too.
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

}  // namespace

void ParcApplyInitDataTypeRules(const MediaKeySystemConfiguration& config,
                                bool safari_identity,
                                bool refuse_empty_init_data_types,
                                WebMediaKeySystemConfiguration& web_config) {
  // Parc: "sinf", "skd" and "mpts", FairPlay's init data types, only under
  // Safari's identity; elsewhere they stay unregistered, so no key system
  // takes them.
  if (!safari_identity) {
    for (wtf_size_t j = 0; j < config.initDataTypes().size(); ++j) {
      if (IsParcSafariOnlyInitDataType(config.initDataTypes()[j])) {
        web_config.init_data_types[j] = media::EmeInitDataType::UNKNOWN;
      }
    }
  }
  // Parc: under Safari's identity FairPlay refuses a configuration naming
  // no init data type, as WebKit's FairPlay CDM does: its
  // supportsConfiguration finds none of its types in an empty list. An
  // unknown type makes the selector refuse it the same way.
  if (refuse_empty_init_data_types && web_config.init_data_types.empty()) {
    web_config.init_data_types.push_back(media::EmeInitDataType::UNKNOWN);
  }
}

void ParcApplySafariOnlyAudioCodecs(
    bool safari_identity,
    WebMediaKeySystemConfiguration& web_config) {
  // Parc: AC-3 and E-AC-3 only under Safari's identity
  // (parc_safari_identity.h). A capability naming them gets a codec no key
  // system supports, so it is skipped like any unsupported capability
  // while the configuration's other capabilities still count.
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
      ParcApplySafariFairPlayContentType(capability, /*video=*/false);
    }
    for (WebMediaKeySystemMediaCapability& capability :
         web_config.video_capabilities) {
      ParcApplySafariFairPlayContentType(capability, /*video=*/true);
    }
  }

  // Parc: FairPlay plays MP4 only (and HLS, which the Safari path above
  // turns into MP4), as AVFoundation does. FLAC and Opus, which its
  // capability lists, are WebM codecs too, so a capability in any other
  // container is skipped like any unsupported capability, for
  // requestMediaKeySystemAccess and decodingInfo alike.
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

  // Parc: under Safari's identity FairPlay takes the encryption schemes
  // WebKit's FairPlay CDM takes (CDMInstanceFairPlayStreamingAVFObjC::
  // supportsMediaCapability): none named, or "cbcs". A capability naming
  // another is skipped like any unsupported capability.
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
  // Parc: "persistent-usage-record" only under Safari's identity;
  // elsewhere it stays an unknown session type, so no configuration
  // naming it is supported.
  if (!safari_identity) {
    for (wtf_size_t j = 0; j < config.sessionTypes().size(); ++j) {
      if (IsParcSafariOnlySessionType(config.sessionTypes()[j])) {
        web_config.session_types[j] = WebEncryptedMediaSessionType::kUnknown;
      }
    }
  }
}

}  // namespace blink

// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIASOURCE_PARC_MEDIA_SOURCE_TYPES_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIASOURCE_PARC_MEDIA_SOURCE_TYPES_H_

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

#include "media/base/mime_util.h"
#include "media/filters/stream_parser_factory.h"
#include "media/media_buildflags.h"
#include "third_party/blink/public/platform/web_time_range.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/modules/mediasource/media_source_attachment_supplement.h"
#include "third_party/blink/renderer/modules/mediasource/source_buffer.h"
#include "third_party/blink/renderer/modules/mediasource/source_buffer_list.h"
#include "third_party/blink/renderer/platform/network/mime/content_type.h"
#include "third_party/blink/renderer/platform/wtf/text/strcat.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

inline std::optional<bool> ParcSafariMediaSourceTypeAnswer(
    const String& user_agent,
    String& mime_type,
    String& codecs,
    ContentType& content_type) {
  if (!IsParcSafariIdentityUserAgent(user_agent)) {
    if (IsParcSafariOnlyAudioCodecs(codecs)) {
      return false;
    }
    return std::nullopt;
  }
  if (ParcSafariAV1Unavailable(codecs)) {
    return false;
  }
  const std::string lower_mime_type = mime_type.ToAsciiLower().Ascii();
  std::vector<std::string> parsed_codec_ids;
  media::SplitCodecs(codecs.Ascii(), &parsed_codec_ids);
  if (media::StreamParserFactory::ParcIsOggType(lower_mime_type)) {
    return media::StreamParserFactory::ParcSafariTakesOgg(lower_mime_type,
                                                          parsed_codec_ids);
  }
  std::optional<media::StreamParserFactory::ParcSafariType> safari_type =
      media::StreamParserFactory::ParcSafariMediaSourceType(lower_mime_type,
                                                            parsed_codec_ids);
  if (!safari_type) {
    return false;
  }
  if (safari_type->type != lower_mime_type ||
      safari_type->codecs != parsed_codec_ids) {
    std::string safari_codecs;
    for (const std::string& codec_id : safari_type->codecs) {
      safari_codecs += (safari_codecs.empty() ? "" : ",") + codec_id;
    }
    mime_type = String::FromUtf8(safari_type->type);
    codecs = String::FromUtf8(safari_codecs);
    content_type = ContentType(
        codecs.empty() ? mime_type
                       : StrCat({mime_type, "; codecs=\"", codecs, "\""}));
  }
#if BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
  if (IsParcSafariMediaSourceMp2tType(mime_type)) {
    return ParcSafariMp2tParserCodecs(codecs).has_value();
  }
#endif
  return std::nullopt;
}

inline void ParcSafariDropPcmCodecs(const String& user_agent,
                                    const String& mime_type,
                                    String& codecs,
                                    ContentType& filtered_content_type) {
  if (!IsParcSafariIdentityUserAgent(user_agent) ||
      (!EqualIgnoringAsciiCase(mime_type, "video/mp4") &&
       !EqualIgnoringAsciiCase(mime_type, "audio/mp4"))) {
    return;
  }
  auto without_pcm = [](const String& value) {
    String result;
    for (const String& codec : value.Split(',')) {
      const String id = codec.StripWhiteSpace();
      if (id == "ipcm" || id.starts_with("ipcm.") || id == "fpcm" ||
          id.starts_with("fpcm.")) {
        continue;
      }
      if (!result.empty()) {
        result = StrCat({result, ","});
      }
      result = StrCat({result, id});
    }
    return result;
  };
  codecs = without_pcm(codecs);
  const String filtered = without_pcm(filtered_content_type.Parameter("codecs"));
  filtered_content_type = ContentType(
      filtered.empty() ? mime_type
                       : StrCat({mime_type, "; codecs=\"", filtered, "\""}));
}

inline bool ParcSafariKeepsDuration(
    ExecutionContext* context,
    SourceBufferList& source_buffers,
    MediaSourceAttachmentSupplement::ExclusiveKey pass_key,
    double& new_duration,
    double old_duration) {
  if (!context || !IsParcSafariIdentityUserAgent(context->UserAgent())) {
    return false;
  }
  for (unsigned i = 0; i < source_buffers.length(); ++i) {
    WebTimeRanges ranges;
    source_buffers.item(i)->GetBuffered_Locked(&ranges, pass_key);
    if (!ranges.empty()) {
      new_duration = std::max(new_duration, ranges.back().end);
    }
  }
  return new_duration == old_duration;
}

}

#endif

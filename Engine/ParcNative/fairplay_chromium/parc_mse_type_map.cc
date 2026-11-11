// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_mse_type_map.cc.

#include "media/filters/parc_mse_type_map.h"

#include <algorithm>
#include <array>
#include <optional>

#include "build/build_config.h"
#include "media/base/mime_util.h"
#include "media/filters/stream_parser_factory.h"
#include "media/formats/mp4/mp4_stream_parser.h"
#include "media/formats/ogg/parc_ogg_stream_parser.h"
#include "media/formats/webm/webm_stream_parser.h"
#include "media/media_buildflags.h"

#if BUILDFLAG(USE_PROPRIETARY_CODECS) && \
    BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
#include "media/formats/mp2t/mp2t_stream_parser.h"
#endif

namespace media {

bool ParcMapSafariMseType(std::string_view type,
                         base::span<const std::string> codecs,
                         ParcMseCodecPredicate is_iamf,
                         ParcMseCodecPredicate is_valid_aac,
                         std::string* mapped_type,
                         std::vector<std::string>* mapped_codecs) {
  static constexpr auto kIsoBmffTypes = std::to_array<std::string_view>(
      {"application/mp4", "audio/3gpp", "audio/3gpp2", "audio/mp4",
       "audio/x-m4a", "audio/x-m4b", "audio/x-m4p", "audio/x-m4r",
       "audio/x-quicktime", "video/3gpp", "video/3gpp2", "video/quicktime",
       "video/x-m4v"});
  static constexpr auto kMp3Types = std::to_array<std::string_view>(
      {"audio/mp3", "audio/mpeg", "audio/mpeg3", "audio/mpg", "audio/x-mp3",
       "audio/x-mpeg", "audio/x-mpeg3", "audio/x-mpg"});

  for (const auto& codec : codecs) {
    if ((codec == "ipcm" || codec.starts_with("ipcm.") ||
         codec == "fpcm" || codec.starts_with("fpcm.")) &&
        (type == "video/quicktime" || type == "audio/x-quicktime")) {
      return false;
    }
  }

  *mapped_type = std::string(type);
  *mapped_codecs = std::vector<std::string>(codecs.begin(), codecs.end());
  if (is_iamf && std::ranges::any_of(*mapped_codecs, is_iamf)) {
    return false;
  }
  if (std::ranges::find(kIsoBmffTypes, type) != kIsoBmffTypes.end()) {
    *mapped_type = "video/mp4";
    // AVStreamDataParser takes 3GPP AMR and H.263, except H.263 in QuickTime;
    // MP4StreamParser takes them under Safari's init-segment rules.
    const auto names = [](const std::string& codec_id, std::string_view name) {
      return codec_id == name || (codec_id.starts_with(name) &&
                                  codec_id[name.size()] == '.');
    };
    if (type == "video/quicktime" || type == "audio/x-quicktime") {
      for (const std::string& codec_id : *mapped_codecs) {
        if (names(codec_id, "s263")) {
          return false;
        }
      }
    }
    std::erase_if(*mapped_codecs, [&names](const std::string& codec_id) {
      return names(codec_id, "samr") || names(codec_id, "sawb") ||
             names(codec_id, "s263");
    });
  } else if (std::ranges::find(kMp3Types, type) != kMp3Types.end()) {
    *mapped_type = "audio/mpeg";
    std::erase(*mapped_codecs, "mp3");
  } else if (type == "audio/aacp") {
    *mapped_type = "audio/aac";
  } else if (type == "audio/aac" && is_valid_aac) {
    std::erase_if(*mapped_codecs, is_valid_aac);
  }
  return true;
}

std::unique_ptr<StreamParser> ParcCreateMseParserWithoutCodecs(
    std::string_view type) {
  if (StreamParserFactory::IsTypeSupported(type, {}) !=
      SupportsType::kMaybeSupported) {
    return nullptr;
  }
  if (type == "video/webm" || type == "audio/webm") {
    return std::make_unique<WebMStreamParser>();
  }
  if (type == "video/mp4" || type == "audio/mp4") {
    // Without a codec string, keep Dolby Vision as Dolby Vision rather than
    // its cross-compatible codec.
    return std::make_unique<mp4::MP4StreamParser>(
        std::nullopt, /*has_sbr=*/false, /*has_flac=*/true,
        /*has_iamf=*/false, /*has_dv=*/true);
  }
#if BUILDFLAG(USE_PROPRIETARY_CODECS) && \
    BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
  if (type == "video/mp2t") {
    return std::make_unique<mp2t::Mp2tStreamParser>(std::nullopt,
                                                    /*has_sbr=*/false);
  }
#endif
  return nullptr;
}

bool ParcIsSafariOggType(std::string_view type) {
  return type == "audio/ogg" || type == "application/ogg";
}

bool ParcSafariTakesOgg(std::string_view type,
                       base::span<const std::string> codecs) {
  if (type == "application/ogg") {
    return codecs.empty();
  }
  return type == "audio/ogg" &&
         std::ranges::all_of(codecs, [](const std::string& codec_id) {
           return codec_id == "opus" || codec_id == "vorbis" ||
                  codec_id == "flac";
         });
}

std::unique_ptr<StreamParser> ParcCreateSafariOggParser(
    std::string_view type,
    base::span<const std::string> codecs) {
  if (!ParcSafariTakesOgg(type, codecs)) {
    return nullptr;
  }
  return std::make_unique<ParcOggStreamParser>();
}

}  // namespace media

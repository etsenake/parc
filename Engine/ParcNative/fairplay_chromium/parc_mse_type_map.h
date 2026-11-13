// Copyright 2026 Parc contributors.

#ifndef MEDIA_FILTERS_PARC_MSE_TYPE_MAP_H_
#define MEDIA_FILTERS_PARC_MSE_TYPE_MAP_H_

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "base/containers/span.h"
#include "media/base/media_export.h"

namespace media {

class StreamParser;

using ParcMseCodecPredicate = bool (*)(std::string_view codec);

bool ParcMapSafariMseType(std::string_view type,
                         base::span<const std::string> codecs,
                         ParcMseCodecPredicate is_iamf,
                         ParcMseCodecPredicate is_valid_aac,
                         std::string* mapped_type,
                         std::vector<std::string>* mapped_codecs);

std::unique_ptr<StreamParser> ParcCreateMseParserWithoutCodecs(
    std::string_view type);
bool ParcIsSafariOggType(std::string_view type);
bool ParcSafariTakesOgg(std::string_view type,
                       base::span<const std::string> codecs);
MEDIA_EXPORT std::unique_ptr<StreamParser> ParcCreateSafariOggParser(
    std::string_view type,
    base::span<const std::string> codecs);

}

#endif

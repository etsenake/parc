// Copyright 2026 Parc contributors.
// Installed at //media/filters/parc_mse_type_map.h.

#ifndef MEDIA_FILTERS_PARC_MSE_TYPE_MAP_H_
#define MEDIA_FILTERS_PARC_MSE_TYPE_MAP_H_

#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "base/containers/span.h"

namespace media {

class StreamParser;

using ParcMseCodecPredicate = bool (*)(std::string_view codec);

// Normalizes a page's type and codecs to Safari's Media Source parser route.
// The two predicates keep Chromium's own IAMF and AAC codec validation at the
// parser factory hook instead of copying it here.
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
std::unique_ptr<StreamParser> ParcCreateSafariOggParser(
    std::string_view type,
    base::span<const std::string> codecs);

}  // namespace media

#endif  // MEDIA_FILTERS_PARC_MSE_TYPE_MAP_H_

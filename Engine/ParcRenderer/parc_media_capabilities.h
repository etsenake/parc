// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/media_capabilities/parc_media_capabilities.h.
// The parts of WebKit's decodingInfo that MediaCapabilities applies on
// Safari-identity documents and that need nothing of its own: the HEVC and
// Dolby Vision codec-string parsers, and the shape of a finished result.
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIA_CAPABILITIES_PARC_MEDIA_CAPABILITIES_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIA_CAPABILITIES_PARC_MEDIA_CAPABILITIES_H_

#include <stdint.h>

#include <optional>
#include <string_view>

namespace blink {

class ExecutionContext;
class MediaCapabilitiesDecodingInfo;
class MediaDecodingConfiguration;
class MediaKeySystemAccess;

struct ParcHevcParameters {
  uint8_t profile_space = 0;
  uint8_t profile_idc = 0;
  uint32_t compatibility_flags = 0;  // Bit-reversed, as WebKit keeps it.
  uint8_t level_idc = 0;
};

// WebKit's parseHEVCCodecParameters (HEVCUtilities.cpp).
std::optional<ParcHevcParameters> ParcParseHevc(std::string_view codec);

struct ParcDoViParameters {
  uint8_t profile = 0;
  uint8_t level = 0;
};

// WebKit's parseDoViCodecParameters (HEVCUtilities.cpp), for the HEVC
// codec types (dvh1, dvhe) Parc dispatches to it.
std::optional<ParcDoViParameters> ParcParseDoVi(std::string_view codec);

// Finishes a decodingInfo result in the shape of the document asking:
// WebKit's under Safari's identity, Chromium's (keySystemAccess, null
// without a key system) elsewhere.
MediaCapabilitiesDecodingInfo* ParcFinishDecodingInfo(
    MediaCapabilitiesDecodingInfo* info,
    ExecutionContext* context,
    const MediaDecodingConfiguration* config,
    MediaKeySystemAccess* access);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIA_CAPABILITIES_PARC_MEDIA_CAPABILITIES_H_

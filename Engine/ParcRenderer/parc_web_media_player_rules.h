// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_web_media_player_rules.h.
// The rules WebMediaPlayerImpl applies to values it holds: which codecs the
// FairPlay Renderer plays, and the type AVFoundation is told for a file played
// to an AirPlay target. WebMediaPlayerImpl keeps every decision that acts on
// them.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_RULES_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_RULES_H_

#include <optional>
#include <string>

#include "media/base/container_names.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace media {
struct PipelineMetadata;
}  // namespace media

namespace blink {

// Whether the FairPlay Renderer plays every codec `codecs` names, for
// changeType() on its players. `safari`: the document presents Safari's
// identity.
PLATFORM_EXPORT bool ParcFairPlayChangeTypeSupported(
    bool safari,
    const std::string& content_type,
    const std::string& codecs);

// Whether the FairPlay Renderer plays the streams `metadata` describes.
// `safari`: a Safari-identity document's Media Source.
PLATFORM_EXPORT bool ParcFairPlayPlaysStreams(
    const media::PipelineMetadata& metadata,
    bool safari);

// The type AVFoundation is told for a file of `container`, or nullopt for one
// Safari's src= engine doesn't play.
PLATFORM_EXPORT std::optional<std::string> ParcNativeFileMimeType(
    std::optional<media::container_names::MediaContainerName> container,
    bool has_video);

// Puts `added`'s streams in `metadata`, replacing the config of a type it has
// (a SourceBuffer added after the one it replaces was removed).
PLATFORM_EXPORT void ParcAddStreams(const media::PipelineMetadata& added,
                                    media::PipelineMetadata* metadata);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_RULES_H_

// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_RULES_H_
#define THIRD_PARTY_BLINK_RENDERER_PLATFORM_MEDIA_PARC_WEB_MEDIA_PLAYER_RULES_H_

#include <optional>
#include <string>
#include <vector>

#include "base/time/time.h"
#include "media/base/container_names.h"
#include "media/base/eme_constants.h"
#include "media/filters/chunk_demuxer.h"
#include "third_party/blink/public/platform/web_encrypted_media_types.h"
#include "third_party/blink/public/platform/web_media_key_system_configuration.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/platform/platform_export.h"

namespace media {
struct PipelineMetadata;
}

namespace blink {

PLATFORM_EXPORT bool ParcFairPlayChangeTypeSupported(
    bool safari,
    const std::string& content_type,
    const std::string& codecs);

PLATFORM_EXPORT bool ParcFairPlayPlaysStreams(
    const media::PipelineMetadata& metadata,
    bool safari);

PLATFORM_EXPORT std::optional<std::string> ParcNativeFileMimeType(
    std::optional<media::container_names::MediaContainerName> container,
    bool has_video);

PLATFORM_EXPORT void ParcAddStreams(const media::PipelineMetadata& added,
                                    media::PipelineMetadata* metadata);

PLATFORM_EXPORT WebMediaPlayer::ReadyState ParcSourceBufferReadyState(
    const media::ChunkDemuxer::ParcBufferedState& source,
    base::TimeDelta now,
    bool time_progressing);

PLATFORM_EXPORT media::EmeConfig::Rule ParcSafariFairPlaySessionTypeRule(
    WebEncryptedMediaSessionType session_type,
    const std::vector<WebEncryptedMediaSessionType>& session_types,
    WebMediaKeySystemConfiguration::Requirement persistent_state,
    media::EmeConfig::Rule rule);

}

#endif

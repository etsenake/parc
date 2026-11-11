// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/parc_web_media_player_rules.cc.
#include "third_party/blink/renderer/platform/media/parc_web_media_player_rules.h"

#include <optional>
#include <string>
#include <vector>

#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/media_types.h"
#include "media/base/mime_util.h"
#include "media/base/pipeline_metadata.h"
#include "media/base/sample_format.h"
#include "media/base/video_codecs.h"
#include "media/base/video_decoder_config.h"

namespace blink {

// Parc: whether the FairPlay Renderer plays every codec `codecs` names: the
// ones FairPlay's CdmInfo lists, Dolby Vision profile 8, and on a
// Safari-identity page 10, which it plays without offering them, FLAC,
// Opus and ALAC (clear; FLAC and ALAC also protected), and on a
// Safari-identity page PCM ('ipcm', 'fpcm'), AV1, VP9 profiles 0 and 2 and
// Vorbis (clear), as Safari's renderer switches among everything its Media
// Source plays. An empty list leaves the decision to the demuxer.
bool ParcFairPlayChangeTypeSupported(
    bool safari,
    const std::string& content_type,
    const std::string& codecs) {
  std::vector<std::string> codec_ids;
  media::SplitCodecs(codecs, &codec_ids);
  for (const std::string& codec_id : codec_ids) {
    if (safari && (codec_id == "ipcm" || codec_id.starts_with("ipcm.") ||
                   codec_id == "fpcm" || codec_id.starts_with("fpcm."))) {
      continue;
    }
    if (std::optional<media::AudioType> audio =
            media::ParseAudioCodecString(content_type, codec_id)) {
      if (audio->codec != media::AudioCodec::kAAC &&
          audio->codec != media::AudioCodec::kAC3 &&
          audio->codec != media::AudioCodec::kEAC3 &&
          audio->codec != media::AudioCodec::kFLAC &&
          audio->codec != media::AudioCodec::kOpus &&
          audio->codec != media::AudioCodec::kALAC &&
          (!safari || audio->codec != media::AudioCodec::kVorbis)) {
        return false;
      }
      continue;
    }
    std::optional<media::VideoType> video =
        media::ParseVideoCodecString(content_type, codec_id);
    if (!video) {
      return false;
    }
    switch (video->codec) {
      case media::VideoCodec::kH264:
      case media::VideoCodec::kHEVC:
        break;
      case media::VideoCodec::kDolbyVision:
        if (video->profile != media::DOLBYVISION_PROFILE5 &&
            video->profile != media::DOLBYVISION_PROFILE8 &&
            (!safari || video->profile != media::DOLBYVISION_PROFILE10)) {
          return false;
        }
        break;
      case media::VideoCodec::kAV1:
        if (!safari) {
          return false;
        }
        break;
      case media::VideoCodec::kVP9:
        if (!safari || (video->profile != media::VP9PROFILE_PROFILE0 &&
                        video->profile != media::VP9PROFILE_PROFILE2)) {
          return false;
        }
        break;
      default:
        return false;
    }
  }
  return true;
}

bool ParcFairPlayPlaysStreams(const media::PipelineMetadata& metadata,
                              bool safari) {
  if (metadata.has_video) {
    const media::VideoDecoderConfig& video = metadata.video_decoder_config;
    switch (video.codec()) {
      case media::VideoCodec::kH264:
      case media::VideoCodec::kHEVC:
      case media::VideoCodec::kAV1:
        break;
      case media::VideoCodec::kVP9:
        if (!safari || (video.profile() != media::VP9PROFILE_PROFILE0 &&
                        video.profile() != media::VP9PROFILE_PROFILE2)) {
          return false;
        }
        break;
      case media::VideoCodec::kDolbyVision:
        if (video.profile() != media::DOLBYVISION_PROFILE5 &&
            video.profile() != media::DOLBYVISION_PROFILE8 &&
            video.profile() != media::DOLBYVISION_PROFILE10) {
          return false;
        }
        break;
      default:
        return false;
    }
  }
  if (metadata.has_audio) {
    switch (metadata.audio_decoder_config.codec()) {
      case media::AudioCodec::kAAC:
      case media::AudioCodec::kAC3:
      case media::AudioCodec::kEAC3:
      case media::AudioCodec::kFLAC:
      case media::AudioCodec::kOpus:
      case media::AudioCodec::kALAC:
        break;
      case media::AudioCodec::kVorbis:
        if (!safari) {
          return false;
        }
        break;
      case media::AudioCodec::kPCM: {
        // As the MP4 parser gives 'ipcm' and 'fpcm'.
        const media::SampleFormat format =
            metadata.audio_decoder_config.sample_format();
        if (format != media::kSampleFormatS16 &&
            format != media::kSampleFormatS24 &&
            format != media::kSampleFormatS32 &&
            format != media::kSampleFormatF32) {
          return false;
        }
        break;
      }
      default:
        return false;
    }
  }
  return true;
}

// Parc: the type AVFoundation is told for a file of `container`, for the
// containers Safari's src= engine (AVFoundation's) plays; WebM, Ogg and the
// rest play in players that can't play to an AirPlay target, if at all.
std::optional<std::string> ParcNativeFileMimeType(
    std::optional<media::container_names::MediaContainerName> container,
    bool has_video) {
  using media::container_names::MediaContainerName;
  switch (container.value_or(MediaContainerName::kContainerUnknown)) {
    case MediaContainerName::kContainerMOV:
      return has_video ? "video/mp4" : "audio/mp4";
    case MediaContainerName::kContainerMPEG2TS:
      return "video/mp2t";
    case MediaContainerName::kContainerMP3:
      return "audio/mpeg";
    case MediaContainerName::kContainerAAC:
      return "audio/aac";
    case MediaContainerName::kContainerAC3:
      return "audio/ac3";
    case MediaContainerName::kContainerEAC3:
      return "audio/eac3";
    case MediaContainerName::kContainerAIFF:
      return "audio/aiff";
    case MediaContainerName::kContainerAMR:
      return "audio/amr";
    case MediaContainerName::kContainerCAF:
      return "audio/x-caf";
    case MediaContainerName::kContainerFLAC:
      return "audio/flac";
    case MediaContainerName::kContainerWAV:
      return "audio/wav";
    default:
      return std::nullopt;
  }
}

void ParcAddStreams(const media::PipelineMetadata& added,
                    media::PipelineMetadata* metadata) {
  if (added.has_audio) {
    metadata->has_audio = true;
    metadata->audio_decoder_config = added.audio_decoder_config;
  }
  if (added.has_video) {
    metadata->has_video = true;
    metadata->video_decoder_config = added.video_decoder_config;
  }
}

}  // namespace blink

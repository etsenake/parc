#include "media/filters/mac/parc_audio_toolbox_aac.h"

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <vector>

#include "base/apple/osstatus_logging.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/numerics/safe_conversions.h"
#include "media/base/audio_buffer.h"
#include "media/base/audio_bus.h"
#include "media/base/limiting_audio_queue.h"
#include "media/base/media_log.h"
#include "media/filters/mac/audio_toolbox_audio_decoder.h"
#include "media/formats/mp4/es_descriptor.h"
#include "media/formats/mpeg/adts_constants.h"

namespace media {

namespace parc_audio_toolbox {

namespace {

std::vector<uint8_t> SignalImplicitSbr(
    const std::vector<uint8_t>& audio_specific_config,
    int sample_rate) {
  if (audio_specific_config.size() < 2) {
    return audio_specific_config;
  }
  const uint32_t object_type = audio_specific_config[0] >> 3;
  const uint32_t frequency_index = ((audio_specific_config[0] & 0x07) << 1) |
                                   (audio_specific_config[1] >> 7);
  const uint32_t channel_config = (audio_specific_config[1] >> 3) & 0x0f;
  const uint32_t frame_length_flag = (audio_specific_config[1] >> 2) & 0x01;
  if (object_type != 2 || frequency_index < 6 || frequency_index > 11 ||
      channel_config < 1 || channel_config > 7 ||
      (audio_specific_config[1] & 0x03) != 0 ||
      2 * kADTSFrequencyTable[frequency_index] != sample_rate) {
    return audio_specific_config;
  }
  const uint32_t extension_type = channel_config == 1 ? 29 : 5;
  const uint32_t bits = (extension_type << 27) | (frequency_index << 23) |
                        (channel_config << 19) | ((frequency_index - 3) << 15) |
                        (object_type << 10) | (frame_length_flag << 9);
  return {static_cast<uint8_t>(bits >> 24), static_cast<uint8_t>(bits >> 16),
          static_cast<uint8_t>(bits >> 8), static_cast<uint8_t>(bits)};
}

int ImplicitSbrCoreRate(const std::vector<uint8_t>& audio_specific_config) {
  if (audio_specific_config.size() != 2) {
    return 0;
  }
  const uint32_t object_type = audio_specific_config[0] >> 3;
  const uint32_t frequency_index = ((audio_specific_config[0] & 0x07) << 1) |
                                   (audio_specific_config[1] >> 7);
  const uint32_t channel_config = (audio_specific_config[1] >> 3) & 0x0f;
  if (object_type != 2 || frequency_index < 6 || frequency_index > 11 ||
      channel_config < 1 || channel_config > 7 ||
      (audio_specific_config[1] & 0x07) != 0) {
    return 0;
  }
  return kADTSFrequencyTable[frequency_index];
}

std::optional<bool> CarriesSbr(
    const std::vector<uint8_t>& audio_specific_config,
    base::span<const uint8_t> access_unit) {
  constexpr size_t kMaxAdtsFrameSize = 0x1fff;
  constexpr size_t kMinParsedBytes = 1024;
  const int core_rate = ImplicitSbrCoreRate(audio_specific_config);
  if (!core_rate) {
    return false;
  }
  const size_t frame_size = kADTSHeaderSizeNoCrc + access_unit.size();
  if (access_unit.empty() || frame_size > kMaxAdtsFrameSize) {
    return std::nullopt;
  }
  const uint8_t frequency_index = ((audio_specific_config[0] & 0x07) << 1) |
                                  (audio_specific_config[1] >> 7);
  const uint8_t channel_config = (audio_specific_config[1] >> 3) & 0x0f;
  const std::array<uint8_t, kADTSHeaderSizeNoCrc> header = {
      0xff,
      0xf1,
      static_cast<uint8_t>(0x40 | (frequency_index << 2) |
                           (channel_config >> 2)),
      static_cast<uint8_t>(((channel_config & 0x03) << 6) | (frame_size >> 11)),
      static_cast<uint8_t>(frame_size >> 3),
      static_cast<uint8_t>(((frame_size & 0x07) << 5) | 0x1f),
      0xfc};
  const size_t copies =
      std::max<size_t>(2, (kMinParsedBytes + frame_size - 1) / frame_size);
  std::vector<uint8_t> frames;
  frames.reserve(copies * frame_size);
  for (size_t i = 0; i < copies; ++i) {
    frames.insert(frames.end(), header.begin(), header.end());
    frames.insert(frames.end(), access_unit.begin(), access_unit.end());
  }

  AudioFileStreamID stream = nullptr;
  if (AudioFileStreamOpen(
          nullptr,
          [](void*, AudioFileStreamID, AudioFileStreamPropertyID,
             AudioFileStreamPropertyFlags*) {},
          [](void*, UInt32, UInt32, const void*,
             AudioStreamPacketDescription*) {},
          kAudioFileAAC_ADTSType, &stream) != noErr) {
    return std::nullopt;
  }
  base::ScopedClosureRunner close_stream(
      base::BindOnce(base::IgnoreResult(&AudioFileStreamClose), stream));
  UInt32 size = 0;
  if (AudioFileStreamParseBytes(stream,
                                base::checked_cast<UInt32>(frames.size()),
                                frames.data(), 0) != noErr ||
      AudioFileStreamGetPropertyInfo(stream,
                                     kAudioFileStreamProperty_FormatList, &size,
                                     nullptr) != noErr ||
      size < sizeof(AudioFormatListItem)) {
    return std::nullopt;
  }
  std::vector<AudioFormatListItem> layers(size / sizeof(AudioFormatListItem));
  size =
      base::checked_cast<UInt32>(layers.size() * sizeof(AudioFormatListItem));
  if (AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_FormatList,
                                 &size, layers.data()) != noErr) {
    return std::nullopt;
  }
  layers.resize(std::min(layers.size(), size / sizeof(AudioFormatListItem)));
  if (layers.empty()) {
    return std::nullopt;
  }
  return std::ranges::any_of(
      layers, [core_rate](const AudioFormatListItem& layer) {
        return (layer.mASBD.mFormatID == kAudioFormatMPEG4AAC_HE ||
                layer.mASBD.mFormatID == kAudioFormatMPEG4AAC_HE_V2) &&
               layer.mASBD.mSampleRate == 2 * core_rate;
      });
}

bool SelectAacLayer(const std::vector<uint8_t>& cookie,
                    int sample_rate,
                    AudioStreamBasicDescription& format,
                    MediaLog* media_log) {
  AudioFormatInfo info = {};
  info.mASBD.mFormatID = kAudioFormatMPEG4AAC;
  info.mMagicCookie = cookie.data();
  info.mMagicCookieSize = cookie.size();
  UInt32 size = 0;
  auto status = AudioFormatGetPropertyInfo(kAudioFormatProperty_FormatList,
                                           sizeof(info), &info, &size);
  if (status != noErr || size < sizeof(AudioFormatListItem)) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log)
        << "AudioFormatGetPropertyInfo() failed";
    return false;
  }
  std::vector<AudioFormatListItem> layers(size / sizeof(AudioFormatListItem));
  status = AudioFormatGetProperty(kAudioFormatProperty_FormatList, sizeof(info),
                                  &info, &size, layers.data());
  layers.resize(size / sizeof(AudioFormatListItem));
  if (status != noErr || layers.empty()) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log)
        << "AudioFormatGetProperty() failed";
    return false;
  }
  UInt32 playable = 0;
  size = sizeof(playable);
  status =
      AudioFormatGetProperty(kAudioFormatProperty_FirstPlayableFormatFromList,
                             layers.size() * sizeof(AudioFormatListItem),
                             layers.data(), &size, &playable);
  if (status != noErr || playable >= layers.size()) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log)
        << "AudioFormatGetProperty() found no playable AAC layer";
    return false;
  }
  auto candidates = base::span(layers).subspan(playable);
  auto match = std::ranges::find_if(
      candidates, [sample_rate](const AudioFormatListItem& layer) {
        return layer.mASBD.mSampleRate == sample_rate;
      });
  format = (match != candidates.end() ? *match : candidates.front()).mASBD;
  return true;
}

}

std::vector<AudioStreamPacketDescription> AmrPackets(
    AudioCodec codec,
    base::span<const uint8_t> sample) {
  static constexpr std::array<uint8_t, 16> kNarrowbandSizes = {
      13, 14, 16, 18, 20, 21, 27, 32, 6, 1, 1, 1, 1, 1, 1, 1};
  static constexpr std::array<uint8_t, 16> kWidebandSizes = {
      18, 24, 33, 37, 41, 47, 51, 59, 61, 6, 1, 1, 1, 1, 1, 1};
  const auto& sizes =
      codec == AudioCodec::kAMR_NB ? kNarrowbandSizes : kWidebandSizes;
  std::vector<AudioStreamPacketDescription> packets;
  size_t offset = 0;
  while (offset < sample.size()) {
    const size_t size = sizes[(sample[offset] >> 3) & 0x0f];
    if (size > sample.size() - offset) {
      break;
    }
    packets.push_back({static_cast<SInt64>(offset), 0,
                       static_cast<UInt32>(size)});
    offset += size;
  }
  return packets;
}

std::vector<uint8_t> AdtsAudioSpecificConfig(base::span<const uint8_t> adts) {
  const uint8_t object_type = (adts[2] >> 6) + 1;
  const uint8_t frequency_index = (adts[2] >> 2) & 0x0f;
  const uint8_t channel_config = ((adts[2] & 0x01) << 2) | (adts[3] >> 6);
  return {static_cast<uint8_t>((object_type << 3) | (frequency_index >> 1)),
          static_cast<uint8_t>(((frequency_index & 0x01) << 7) |
                               (channel_config << 3))};
}

std::optional<int> ImplicitSbrRate(
    const std::vector<uint8_t>& audio_specific_config,
    base::span<const uint8_t> access_unit,
    int sample_rate) {
  const int core_rate = ImplicitSbrCoreRate(audio_specific_config);
  if (!core_rate || sample_rate == 2 * core_rate) {
    return sample_rate;
  }
  const std::optional<bool> sbr =
      CarriesSbr(audio_specific_config, access_unit);
  if (!sbr) {
    return std::nullopt;
  }
  return *sbr ? 2 * core_rate : sample_rate;
}

bool AacInputFormat(const std::vector<uint8_t>& audio_specific_config,
                    int sample_rate,
                    std::vector<uint8_t>& magic_cookie,
                    AudioStreamBasicDescription& input_format,
                    MediaLog* media_log) {
  magic_cookie = mp4::ESDescriptor::CreateEsds(
      SignalImplicitSbr(audio_specific_config, sample_rate));
  return SelectAacLayer(magic_cookie, sample_rate, input_format, media_log);
}

bool AlacOrAmrInputFormat(const AudioDecoderConfig& config,
                          std::vector<uint8_t>& magic_cookie,
                          AudioStreamBasicDescription& input_format,
                          MediaLog* media_log) {
  if (config.codec() == AudioCodec::kALAC) {
    input_format.mFormatID = kAudioFormatAppleLossless;
    magic_cookie = config.extra_data();
    UInt32 format_size = sizeof(input_format);
    auto status = AudioFormatGetProperty(
        kAudioFormatProperty_FormatInfo, magic_cookie.size(),
        magic_cookie.data(), &format_size, &input_format);
    if (status != noErr) {
      OSSTATUS_MEDIA_LOG(ERROR, status, media_log)
          << "AudioFormatGetProperty() failed for ALAC";
      return false;
    }
    return true;
  }
  input_format.mFormatID = config.codec() == AudioCodec::kAMR_NB
                               ? kAudioFormatAMR
                               : kAudioFormatAMR_WB;
  input_format.mSampleRate =
      config.codec() == AudioCodec::kAMR_NB ? 8000 : 16000;
  input_format.mChannelsPerFrame = 1;
  input_format.mFramesPerPacket = input_format.mSampleRate / 50;
  return true;
}

}

using parc_audio_toolbox::AdtsAudioSpecificConfig;
using parc_audio_toolbox::DrainsAtEndOfStream;
using parc_audio_toolbox::ImplicitSbrRate;
using parc_audio_toolbox::IsAmr;
using parc_audio_toolbox::TakesConfigFromAdts;

bool AudioToolboxAudioDecoder::DrainsAtEndOfStreamForTesting(
    const AudioDecoderConfig& config) {
  return DrainsAtEndOfStream(config);
}

void AudioToolboxAudioDecoder::Deliver(
    int frames,
    const AudioDiscardHelper::TimeInfo& time_info) {
  if (!aligns_to_access_units_ || (!awaiting_first_output_ && !delay_)) {
    Output(*output_bus_, frames, time_info);
    return;
  }
  if (awaiting_first_output_) {
    awaiting_first_output_ = false;
    delay_ = std::max(output_bus_->frames() - frames, 0);
    if (!delay_) {
      Output(*output_bus_, frames, time_info);
      return;
    }
    output_bus_->CopyPartialFramesTo(0, frames, 0, held_.get());
    held_frames_ = frames;
    held_time_info_ = time_info;
    return;
  }
  const int completing =
      std::min({delay_, frames, held_->frames() - held_frames_});
  output_bus_->CopyPartialFramesTo(0, completing, held_frames_, held_.get());
  held_frames_ += completing;
  DeliverHeldFrames();
  held_frames_ = frames - completing;
  output_bus_->CopyPartialFramesTo(completing, held_frames_, 0, held_.get());
  held_time_info_ = time_info;
}

void AudioToolboxAudioDecoder::DeliverHeldFrames() {
  if (held_frames_) {
    Output(*held_, held_frames_, held_time_info_);
    held_frames_ = 0;
  }
}

void AudioToolboxAudioDecoder::Output(
    const AudioBus& bus,
    int frames,
    const AudioDiscardHelper::TimeInfo& time_info) {
  if (limiter_queue_) {
    limiter_queue_->Push(
        bus, frames, time_info.timestamp,
        base::BindOnce(&AudioToolboxAudioDecoder::OnOutputReady,
                       base::Unretained(this), time_info));
    return;
  }
  std::vector<base::span<const uint8_t>> channels;
  for (int i = 0; i < bus.channels(); ++i) {
    channels.push_back(base::as_bytes(
        base::allow_nonunique_obj,
        bus.channel(i).first(base::checked_cast<size_t>(frames))));
  }
  OnOutputReady(time_info,
                AudioBuffer::CopyFrom(kSampleFormatPlanarF32, channel_layout_,
                                      bus.channels(), sample_rate_, frames,
                                      channels, time_info.timestamp, pool_));
}

bool AudioToolboxAudioDecoder::ReplaceDecoder(
    const std::vector<uint8_t>& audio_specific_config,
    int sample_rate) {
  decoder_.reset();
  if (CreateDecoder(config_, audio_specific_config, sample_rate)) {
    return true;
  }
  if (sample_rate == config_.samples_per_second()) {
    return false;
  }
  MEDIA_LOG(WARNING, media_log_)
      << "Decoding implicitly signalled HE-AAC as its AAC-LC core";
  decoder_.reset();
  return CreateDecoder(config_, audio_specific_config,
                       config_.samples_per_second());
}

std::optional<DecoderStatus> AudioToolboxAudioDecoder::PrepareAacInput(
    const DecoderBuffer& buffer,
    size_t header_size) {
  if (header_size && (base::span(buffer)[6] & 0x03) != 0) {
    MEDIA_LOG(ERROR, media_log_)
        << "ADTS frames with several raw data blocks are unsupported";
    return DecoderStatus(DecoderStatus::Codes::kPlatformDecodeFailure);
  }

  if (!decoder_ ||
      (check_implicit_sbr_ && !buffer.end_of_stream() && buffer.size() > 0)) {
    if (!decoder_ && (buffer.end_of_stream() || buffer.size() == 0)) {
      return DecoderStatus(OkStatus());
    }
    if (!decoder_ && !header_size) {
      MEDIA_LOG(ERROR, media_log_)
          << "AAC without an AudioSpecificConfig must arrive as ADTS frames";
      return DecoderStatus(DecoderStatus::Codes::kPlatformDecodeFailure);
    }
    std::optional<std::vector<uint8_t>> audio_specific_config;
    if (!TakesConfigFromAdts(config_)) {
      audio_specific_config = config_.extra_data();
    } else if (header_size) {
      audio_specific_config = AdtsAudioSpecificConfig(base::span(buffer));
    }
    const std::optional<int> sample_rate =
        audio_specific_config
            ? ImplicitSbrRate(
                  *audio_specific_config,
                  base::span(buffer).subspan(header_size),
                  config_.samples_per_second())
            : std::nullopt;
    if (sample_rate) {
      check_implicit_sbr_ = false;
    }
    if (!decoder_ ||
        (sample_rate && *sample_rate != config_.samples_per_second())) {
      CHECK(audio_specific_config);
      if (!ReplaceDecoder(*audio_specific_config,
                          sample_rate.value_or(config_.samples_per_second()))) {
        decoder_.reset();
        return DecoderStatus(DecoderStatus::Codes::kFailedToCreateDecoder);
      }
    }
  }
  return std::nullopt;
}

void AudioToolboxAudioDecoder::ConfigureOutput(
    const AudioDecoderConfig& config,
    const AudioStreamBasicDescription& input_format,
    ChannelLayout channel_layout) {
  if ((config.codec() != AudioCodec::kAAC ||
       config.profile() == AudioCodecProfile::kXHE_AAC) &&
      !IsAmr(config)) {
    limiter_queue_ = std::make_unique<LimitingAudioQueue>(
        channel_layout, input_format.mSampleRate,
        input_format.mChannelsPerFrame, input_format.mFramesPerPacket);
  } else {
    limiter_queue_.reset();
  }
  channel_layout_ = channel_layout;
  sample_rate_ = input_format.mSampleRate;
  if (!pool_) {
    pool_ = base::MakeRefCounted<AudioBufferMemoryPool>();
  }

  aligns_to_access_units_ =
      input_format.mFormatID == kAudioFormatMPEG4AAC_HE ||
      input_format.mFormatID == kAudioFormatMPEG4AAC_HE_V2;
  awaiting_first_output_ = true;
  delay_ = 0;
  held_frames_ = 0;
  held_ = aligns_to_access_units_
              ? AudioBus::Create(input_format.mChannelsPerFrame,
                                 input_format.mFramesPerPacket)
              : nullptr;
}

}

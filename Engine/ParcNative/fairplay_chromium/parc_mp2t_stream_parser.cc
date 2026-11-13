#include "media/formats/mp2t/parc_mp2t_stream_parser.h"

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/containers/span.h"
#include "base/numerics/byte_conversions.h"
#include "base/strings/stringprintf.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/decrypt_config.h"
#include "media/base/encryption_scheme.h"
#include "media/base/stream_parser_buffer.h"
#include "media/formats/mp2t/descriptors.h"
#include "media/formats/mp2t/es_parser.h"
#include "media/formats/mp2t/es_parser_h264.h"
#include "media/formats/mp2t/mp2t_stream_parser.h"
#include "media/formats/mp2t/parc_es_parser_mpeg_video.h"
#include "media/media_buildflags.h"

#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
#include "media/formats/mp2t/parc_es_parser_ac3.h"
#endif

namespace media::mp2t {

namespace {

constexpr int kStreamTypeAACWithSampleAES = 0xcf;
constexpr int kStreamTypeAVCWithSampleAES = 0xdb;
constexpr uint32_t kSampleAESPrivateDataIndicatorAVC = 0x7a617663;
constexpr uint32_t kSampleAESPrivateDataIndicatorAAC = 0x61616364;
constexpr uint32_t kSampleAESPrivateDataIndicatorAC3 = 0x61633364;
constexpr uint32_t kSampleAESPrivateDataIndicatorEAC3 = 0x65633364;
constexpr uint32_t kAudioSetupInformation = 0x61706164;
constexpr uint32_t kFormatTypeZavc = 0x7a617663;
constexpr uint32_t kMediaTypeVideo = 0x76696465;
constexpr uint32_t kMediaTypeAudio = 0x736f756e;

}

namespace parc_mp2t {

AudioDecoderConfig SampleAesAudioConfig(const AudioDecoderConfig& es_config,
                                        const std::vector<uint8_t>& setup_data,
                                        uint32_t audio_type) {
  AudioDecoderConfig config = es_config;
  config.Initialize(es_config.codec(), es_config.sample_format(),
                    es_config.channel_layout_config(),
                    es_config.samples_per_second(),
                    setup_data.empty() ? es_config.extra_data() : setup_data,
                    EncryptionScheme::kCbcs, es_config.seek_preroll(),
                    es_config.codec_delay());
  config.set_parc_ts_audio_type(audio_type);
  return config;
}

}

void Mp2tStreamParser::ParcIgnoreDeclaredCodecs() {
  allowed_stream_types_.reset();
  parc_safari_streams_ = true;
}

std::unique_ptr<EsParser> Mp2tStreamParser::CreateParcMpegVideoParser(
    int pes_pid) {
  auto on_video_config_changed = base::BindRepeating(
      &Mp2tStreamParser::OnVideoConfigChanged, base::Unretained(this), pes_pid);
  auto on_emit_video_buffer = base::BindRepeating(
      &Mp2tStreamParser::OnEmitVideoBuffer, base::Unretained(this), pes_pid);
  return std::make_unique<ParcEsParserMpegVideo>(
      std::move(on_video_config_changed), std::move(on_emit_video_buffer));
}

#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
std::unique_ptr<EsParser> Mp2tStreamParser::CreateParcAc3Parser(int pes_pid,
                                                                bool eac3) {
  auto on_audio_config_changed = base::BindRepeating(
      &Mp2tStreamParser::OnAudioConfigChanged, base::Unretained(this), pes_pid);
  auto on_emit_audio_buffer = base::BindRepeating(
      &Mp2tStreamParser::OnEmitAudioBuffer, base::Unretained(this), pes_pid);
  return std::make_unique<ParcEsParserAc3>(eac3, on_audio_config_changed,
                                           std::move(on_emit_audio_buffer),
                                           media_log_.get());
}
#endif

std::unique_ptr<EsParser> Mp2tStreamParser::ParcCreateSampleAesParser(
    int pes_pid,
    int stream_type,
    const Descriptors& descriptors) {
  const bool video = stream_type == kStreamTypeAVCWithSampleAES;
  uint32_t indicator = kSampleAESPrivateDataIndicatorAVC;
  if (stream_type == kStreamTypeAACWithSampleAES) {
    indicator = kSampleAESPrivateDataIndicatorAAC;
  } else if (stream_type == parc_mp2t::kStreamTypeAC3WithSampleAES) {
    indicator = kSampleAESPrivateDataIndicatorAC3;
  } else if (stream_type == parc_mp2t::kStreamTypeEAC3WithSampleAES) {
    indicator = kSampleAESPrivateDataIndicatorEAC3;
  }
  if (!descriptors.HasPrivateDataIndicator(indicator)) {
    return nullptr;
  }
  uint32_t format_type = kFormatTypeZavc;
  std::vector<uint8_t> setup_data;
  if (!video) {
    uint32_t format_identifier = 0;
    std::vector<uint8_t> info;
    if (!descriptors.HasRegistrationDescriptor(&format_identifier, &info) ||
        format_identifier != kAudioSetupInformation || info.size() < 8 ||
        info.size() < 8u + info[7]) {
      return nullptr;
    }
    format_type = base::U32FromBigEndian(base::span(info).first<4u>());
    setup_data.assign(info.begin() + 8, info.begin() + 8 + info[7]);
  }

  std::unique_ptr<EsParser> es_parser;
  switch (stream_type) {
    case kStreamTypeAVCWithSampleAES:
      es_parser = std::make_unique<EsParserH264>(
          base::BindRepeating(&Mp2tStreamParser::OnVideoConfigChanged,
                              base::Unretained(this), pes_pid),
          base::BindRepeating(&Mp2tStreamParser::OnEmitVideoBuffer,
                              base::Unretained(this), pes_pid),
          EncryptionScheme::kCbcs, EsParserH264::GetDecryptConfigCB());
      break;
    case kStreamTypeAACWithSampleAES:
      es_parser = CreateAacParser(pes_pid);
      break;
#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
    case parc_mp2t::kStreamTypeAC3WithSampleAES:
    case parc_mp2t::kStreamTypeEAC3WithSampleAES:
      es_parser = CreateParcAc3Parser(
          pes_pid, stream_type == parc_mp2t::kStreamTypeEAC3WithSampleAES);
      break;
#endif
  }
  if (!es_parser) {
    return nullptr;
  }
  parc_sample_aes_pids_[pes_pid] =
      stream_type == kStreamTypeAACWithSampleAES ||
              stream_type == parc_mp2t::kStreamTypeEAC3WithSampleAES
          ? setup_data
          : std::vector<uint8_t>();
  if (!video)
    parc_sample_aes_audio_types_[pes_pid] = format_type;
  if (parc_mpts_reported_pids_.insert(pes_pid).second) {
    const std::string init_data = base::StringPrintf(
        "{\n  \"cont\" : \"mpts\",\n  \"codc\" : %u,\n  \"mtyp\" : %u\n}",
        format_type, video ? kMediaTypeVideo : kMediaTypeAudio);
    encrypted_media_init_data_cb_.Run(
        EmeInitDataType::MPTS,
        std::vector<uint8_t>(init_data.begin(), init_data.end()));
  }
  return es_parser;
}

}

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/at_exit.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "base/time/time.h"
#include "media/base/audio_buffer.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/audio_timestamp_helper.h"
#include "media/base/channel_layout.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/encryption_scheme.h"
#include "media/base/media_util.h"
#include "media/base/sample_format.h"
#include "media/base/timestamp_constants.h"
#include "media/ffmpeg/ffmpeg_common.h"
#include "media/filters/mac/audio_toolbox_audio_decoder.h"

extern "C" int sandbox_init_with_parameters(const char* profile,
                                            uint64_t flags,
                                            const char* const parameters[],
                                            char** errorbuf);

namespace {

using Packets = std::vector<std::vector<uint8_t>>;
using Pcm = std::vector<std::vector<float>>;

struct PacketTime {
  base::TimeDelta timestamp;
  base::TimeDelta duration;
};
using PacketTimes = std::vector<PacketTime>;
using Discards =
    std::vector<std::optional<media::DecoderBuffer::DiscardPadding>>;

int g_failures = 0;

void Expect(bool condition, const std::string& name, const std::string& what) {
  std::printf("%s %s: %s\n", condition ? "PASS" : "FAIL", name.c_str(),
              what.c_str());
  if (!condition) {
    ++g_failures;
  }
}

struct Stream {
  std::vector<uint8_t> audio_specific_config;
  Packets packets;
};

Stream ReadAdts(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), {});
  Stream stream;
  size_t offset = 0;
  while (offset + 7 <= data.size()) {
    const size_t size = ((data[offset + 3] & 0x03) << 11) |
                        (data[offset + 4] << 3) | (data[offset + 5] >> 5);
    if (data[offset] != 0xff || size < 7 || offset + size > data.size()) {
      break;
    }
    if (stream.packets.empty()) {
      const uint8_t object_type = (data[offset + 2] >> 6) + 1;
      const uint8_t frequency = (data[offset + 2] >> 2) & 0x0f;
      const uint8_t channels =
          ((data[offset + 2] & 0x01) << 2) | (data[offset + 3] >> 6);
      stream.audio_specific_config = {
          static_cast<uint8_t>((object_type << 3) | (frequency >> 1)),
          static_cast<uint8_t>(((frequency & 1) << 7) | (channels << 3))};
    }
    stream.packets.emplace_back(data.begin() + offset,
                                data.begin() + offset + size);
    offset += size;
  }
  return stream;
}

Stream ReadMp4Packets(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), {});
  size_t offset = 0;
  auto read32 = [&data, &offset]() {
    uint32_t value = 0;
    for (int shift = 0; shift < 32 && offset < data.size(); shift += 8) {
      value |= static_cast<uint32_t>(data[offset++]) << shift;
    }
    return value;
  };
  auto read_bytes = [&data, &offset](size_t size) {
    const size_t begin = std::min(offset, data.size());
    offset = std::min(offset + size, data.size());
    return std::vector<uint8_t>(data.begin() + begin, data.begin() + offset);
  };
  Stream stream;
  stream.audio_specific_config = read_bytes(read32());
  for (uint32_t count = read32(); count > 0 && offset < data.size(); --count) {
    stream.packets.push_back(read_bytes(read32()));
  }
  return stream;
}

Pcm ReadPcm(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), {});
  if (data.size() < 8) {
    return {};
  }
  uint32_t header[2];
  std::copy_n(data.begin(), sizeof(header), reinterpret_cast<uint8_t*>(header));
  const auto [channels, frames] = header;
  if (data.size() != 8 + size_t{4} * channels * frames) {
    return {};
  }
  Pcm pcm(channels, std::vector<float>(frames));
  for (uint32_t channel = 0; channel < channels; ++channel) {
    std::copy_n(data.begin() + 8 + size_t{4} * channel * frames,
                size_t{4} * frames,
                reinterpret_cast<uint8_t*>(pcm[channel].data()));
  }
  return pcm;
}

struct Demuxed {
  bool opened = false;
  bool sample_format_unset = false;
  bool valid_config = false;
  bool timestamps_defined_and_increasing = true;
  media::AudioDecoderConfig config;
  Packets packets;
  PacketTimes times;
  Discards discards;
};

struct Memory {
  std::vector<uint8_t> data;
  size_t position = 0;
};

int ReadMemory(void* opaque, uint8_t* buffer, int size) {
  auto* memory = static_cast<Memory*>(opaque);
  const size_t count = std::min(memory->data.size() - memory->position,
                                static_cast<size_t>(size));
  if (!count) {
    return AVERROR_EOF;
  }
  std::copy_n(memory->data.begin() + memory->position, count, buffer);
  memory->position += count;
  return static_cast<int>(count);
}

int64_t SeekMemory(void* opaque, int64_t offset, int whence) {
  auto* memory = static_cast<Memory*>(opaque);
  const int64_t size = memory->data.size();
  if (whence == AVSEEK_SIZE) {
    return size;
  }
  const int64_t target =
      offset + (whence == SEEK_CUR   ? static_cast<int64_t>(memory->position)
                : whence == SEEK_END ? size
                                     : 0);
  if (target < 0 || target > size) {
    return AVERROR(EINVAL);
  }
  memory->position = target;
  return target;
}

Demuxed DemuxWithFFmpeg(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  Memory memory{
      std::vector<uint8_t>((std::istreambuf_iterator<char>(file)), {})};
  constexpr int kBufferSize = 32 * 1024;
  AVIOContext* io = avio_alloc_context(
      static_cast<unsigned char*>(av_malloc(kBufferSize)), kBufferSize, 0,
      &memory, &ReadMemory, nullptr, &SeekMemory);
  io->seekable = AVIO_SEEKABLE_NORMAL;
  AVFormatContext* format = avformat_alloc_context();
  format->pb = io;
  format->flags |=
      AVFMT_FLAG_CUSTOM_IO | AVFMT_FLAG_FAST_SEEK | AVFMT_FLAG_NOH264PARSE;
  format->error_recognition |= AV_EF_EXPLODE;
  format->codec_whitelist = av_strdup(media::GetAllowedAudioDecoders());
  format->format_whitelist = av_strdup("ogg,matroska,wav,flac,mp3,mov,aac");
  format->max_analyze_duration = 60 * AV_TIME_BASE;
  Demuxed result;
  if (avformat_open_input(&format, nullptr, nullptr, nullptr) == 0 &&
      avformat_find_stream_info(format, nullptr) >= 0) {
    result.opened = true;
    for (AVStream* stream : media::AVFormatContextToSpan(format)) {
      if (stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) {
        continue;
      }
      result.sample_format_unset =
          stream->codecpar->format == AV_SAMPLE_FMT_NONE;
      result.valid_config =
          media::AVStreamToAudioDecoderConfig(stream, &result.config) &&
          result.config.IsValidConfig();
      AVPacket* packet = av_packet_alloc();
      while (av_read_frame(format, packet) >= 0) {
        if (packet->stream_index == stream->index) {
          auto data = media::AVPacketData(*packet);
          result.packets.emplace_back(data.begin(), data.end());
          if (packet->pts == AV_NOPTS_VALUE ||
              (!result.times.empty() &&
               media::ConvertFromTimeBase(stream->time_base, packet->pts) <=
                   result.times.back().timestamp)) {
            result.timestamps_defined_and_increasing = false;
          }
          result.times.push_back(
              {media::ConvertFromTimeBase(stream->time_base, packet->pts),
               media::ConvertFromTimeBase(stream->time_base,
                                          packet->duration)});
          result.discards.push_back(media::GetDiscardPaddingFromAVPacket(
              packet, result.config.samples_per_second()));
        }
        av_packet_unref(packet);
      }
      av_packet_free(&packet);
      break;
    }
  }
  avformat_close_input(&format);
  av_freep(&io->buffer);
  avio_context_free(&io);
  return result;
}

struct Output {
  bool initialized = false;
  bool decoded = true;
  int sample_rate = 0;
  int channels = 0;
  bool consistent = true;
  bool timestamps_increase = true;
  std::optional<base::TimeDelta> last_timestamp;
  std::vector<base::TimeDelta> timestamps;
  std::vector<int> buffer_frames;
  std::vector<std::vector<float>> pcm;
};

void Collect(Output* output, scoped_refptr<media::AudioBuffer> buffer) {
  if (!output->timestamps.empty() &&
      (buffer->sample_rate() != output->sample_rate ||
       buffer->channel_count() != output->channels)) {
    output->consistent = false;
  }
  output->sample_rate = buffer->sample_rate();
  output->channels = buffer->channel_count();
  if (output->last_timestamp &&
      buffer->timestamp() <= *output->last_timestamp) {
    output->timestamps_increase = false;
  }
  output->last_timestamp = buffer->timestamp();
  output->timestamps.push_back(buffer->timestamp());
  output->buffer_frames.push_back(buffer->frame_count());
  auto bus =
      media::AudioBus::Create(buffer->channel_count(), buffer->frame_count());
  buffer->ReadFrames(buffer->frame_count(), 0, 0, bus.get());
  output->pcm.resize(buffer->channel_count());
  for (int channel = 0; channel < buffer->channel_count(); ++channel) {
    auto samples = bus->channel(channel);
    output->pcm[channel].insert(output->pcm[channel].end(), samples.begin(),
                                samples.end());
  }
}

Output Decode(const media::AudioDecoderConfig& config,
              const Packets& packets,
              double packet_seconds,
              std::optional<size_t> reset_after = std::nullopt,
              const PacketTimes* times = nullptr,
              bool end_of_stream_first = false,
              const Discards* discards = nullptr) {
  media::AudioToolboxAudioDecoder decoder(
      std::make_unique<media::NullMediaLog>());
  Output output;
  std::optional<media::DecoderStatus> status;
  auto record = [](std::optional<media::DecoderStatus>* out,
                   media::DecoderStatus result) { *out = std::move(result); };
  decoder.Initialize(config, nullptr, base::BindOnce(record, &status),
                     base::BindRepeating(&Collect, &output), base::DoNothing());
  base::RunLoop().RunUntilIdle();
  output.initialized = status && status->is_ok();
  if (!output.initialized) {
    return output;
  }
  if (end_of_stream_first) {
    status.reset();
    decoder.Decode(media::DecoderBuffer::CreateEOSBuffer(),
                   base::BindOnce(record, &status));
    base::RunLoop().RunUntilIdle();
    if (!status || !status->is_ok()) {
      output.decoded = false;
      return output;
    }
    decoder.Reset(base::DoNothing());
    base::RunLoop().RunUntilIdle();
  }
  for (size_t index = 0; index < packets.size(); ++index) {
    if (reset_after && index == *reset_after) {
      decoder.Reset(base::DoNothing());
      base::RunLoop().RunUntilIdle();
    }
    auto buffer = media::DecoderBuffer::CopyFrom(packets[index]);
    if (times) {
      buffer->set_timestamp((*times)[index].timestamp);
      buffer->set_duration((*times)[index].duration);
    } else {
      buffer->set_timestamp(base::Seconds(index * packet_seconds));
      buffer->set_duration(base::Seconds(packet_seconds));
    }
    if (discards && index < discards->size() && (*discards)[index]) {
      buffer->set_discard_padding(*(*discards)[index]);
    }
    status.reset();
    decoder.Decode(buffer, base::BindOnce(record, &status));
    base::RunLoop().RunUntilIdle();
    if (!status || !status->is_ok()) {
      output.decoded = false;
      return output;
    }
  }
  status.reset();
  decoder.Decode(media::DecoderBuffer::CreateEOSBuffer(),
                 base::BindOnce(record, &status));
  base::RunLoop().RunUntilIdle();
  output.decoded = status && status->is_ok();
  return output;
}

double Tone(const std::vector<float>& samples, int rate, double frequency) {
  const size_t begin = samples.size() / 4;
  const size_t end = samples.size() - samples.size() / 4;
  const double coefficient = 2 * std::cos(2 * M_PI * frequency / rate);
  double previous = 0;
  double before_previous = 0;
  for (size_t index = begin; index < end; ++index) {
    const double current =
        samples[index] + coefficient * previous - before_previous;
    before_previous = previous;
    previous = current;
  }
  const double power = previous * previous + before_previous * before_previous -
                       coefficient * previous * before_previous;
  return std::sqrt(std::max(power, 0.0)) / (end - begin);
}

double Phase(const std::vector<float>& samples, int rate, double frequency) {
  std::complex<double> sum;
  for (size_t index = rate / 2; index < std::min<size_t>(samples.size(), 3 * rate / 2);
       ++index) {
    sum += static_cast<double>(samples[index]) *
           std::polar(1.0, -2 * M_PI * frequency * index / rate);
  }
  return std::arg(sum);
}

double ToneLagMs(const std::vector<float>& samples,
                 int rate,
                 const std::vector<float>& reference,
                 int reference_rate,
                 double frequency) {
  const double difference =
      std::remainder(Phase(reference, reference_rate, frequency) -
                         Phase(samples, rate, frequency),
                     2 * M_PI);
  return 1000 * difference / (2 * M_PI * frequency);
}

double HighBand(const std::vector<float>& samples, int rate) {
  double energy = 0;
  for (double frequency = 12000; frequency < 20000; frequency += 25) {
    const double magnitude = Tone(samples, rate, frequency);
    energy += magnitude * magnitude;
  }
  return std::sqrt(energy);
}

struct Expectation {
  int sample_rate;
  int channels;
  bool high_band;
  bool stereo_source;
  bool continuous = true;
};

void Check(const std::string& name,
           const Output& output,
           const Expectation& expected,
           size_t packets,
           double packet_seconds) {
  Expect(output.initialized && output.decoded, name, "initializes and decodes");
  if (!output.initialized || !output.decoded) {
    return;
  }
  Expect(output.consistent, name, "keeps one rate and channel count");
  Expect(output.sample_rate == expected.sample_rate, name,
         "output rate " + std::to_string(output.sample_rate) + ", expected " +
             std::to_string(expected.sample_rate));
  Expect(output.channels == expected.channels, name,
         "output channels " + std::to_string(output.channels) + ", expected " +
             std::to_string(expected.channels));
  Expect(output.timestamps_increase, name, "output timestamps increase");
  if (output.pcm.empty() || output.sample_rate != expected.sample_rate) {
    return;
  }
  const size_t frames = output.pcm[0].size();
  const double expected_frames = packets * packet_seconds * output.sample_rate;
  Expect(frames > 0.95 * expected_frames && frames <= expected_frames, name,
         std::to_string(frames) + " frames for " +
             std::to_string(static_cast<int>(expected_frames)) + " expected");
  if (!expected.continuous) {
    return;
  }
  const int rate = output.sample_rate;
  const auto& left = output.pcm[0];
  const double left_1k = Tone(left, rate, 1000);
  const double left_500 = Tone(left, rate, 500);
  if (expected.stereo_source && output.channels == 2) {
    const auto& right = output.pcm[1];
    const double right_500 = Tone(right, rate, 500);
    const double right_1k = Tone(right, rate, 1000);
    Expect(
        left_1k > 0.1 && left_500 < 0.03 && right_500 > 0.1 && right_1k < 0.03,
        name,
        "channels stay separate (L 1k " + std::to_string(left_1k) + ", L 500 " +
            std::to_string(left_500) + ", R 500 " + std::to_string(right_500) +
            ", R 1k " + std::to_string(right_1k) + ")");
  } else {
    Expect(left_1k > 0.1, name, "carries the 1 kHz tone");
  }
  if (rate >= 32000) {
    const double high = HighBand(left, rate);
    Expect(expected.high_band ? high > 0.004 : true, name,
           "12-20 kHz energy " + std::to_string(high));
  }
}

void ExpectMacOsDecoding(const std::string& name,
                         const Output& output,
                         const Pcm& expected) {
  const bool decoded = output.initialized && output.decoded;
  const size_t frames = output.pcm.empty() ? 0 : output.pcm[0].size();
  const size_t expected_frames = expected.empty() ? 0 : expected[0].size();
  float worst = 0;
  bool same_shape = decoded && !expected.empty() &&
                    output.pcm.size() == expected.size() &&
                    frames == expected_frames;
  for (size_t channel = 0; same_shape && channel < expected.size();
       ++channel) {
    for (size_t frame = 0; frame < expected_frames; ++frame) {
      worst = std::max(worst, std::fabs(output.pcm[channel][frame] -
                                        expected[channel][frame]));
    }
  }
  Expect(same_shape && worst == 0, name,
         "matches macOS's own decoding: " + std::to_string(frames) +
             " frames for " + std::to_string(expected_frames) +
             ", largest difference " + std::to_string(worst));
}

Pcm Without(const Pcm& pcm, size_t begin, size_t end) {
  Pcm result;
  for (const auto& channel : pcm) {
    result.emplace_back(channel.begin(), channel.begin() + begin);
    result.back().insert(result.back().end(), channel.begin() + end,
                         channel.end());
  }
  return result;
}

std::vector<uint8_t> ShortAdts(const std::vector<uint8_t>& frame, bool crc) {
  std::vector<uint8_t> result(frame.begin(), frame.begin() + 7);
  if (crc) {
    result[1] &= 0xfe;
    result.push_back(0);
  } else {
    result[1] |= 0x01;
  }
  const size_t length = result.size();
  result[3] = (result[3] & 0xfc) | ((length >> 11) & 0x03);
  result[4] = (length >> 3) & 0xff;
  result[5] = ((length & 0x07) << 5) | (result[5] & 0x1f);
  return result;
}

std::vector<uint8_t> AdtsFrame(const std::vector<uint8_t>& frame,
                               const std::vector<uint8_t>& payload) {
  std::vector<uint8_t> result(frame.begin(), frame.begin() + 7);
  result[1] |= 0x01;
  result.insert(result.end(), payload.begin(), payload.end());
  const size_t length = result.size();
  result[3] = (result[3] & 0xfc) | ((length >> 11) & 0x03);
  result[4] = (length >> 3) & 0xff;
  result[5] = ((length & 0x07) << 5) | (result[5] & 0x1f);
  return result;
}

std::vector<uint8_t> AdtsPayload(const std::vector<uint8_t>& frame) {
  return std::vector<uint8_t>(frame.begin() + ((frame[1] & 0x01) ? 7 : 9),
                              frame.end());
}

Packets Concatenate(Packets first, const Packets& second) {
  first.insert(first.end(), second.begin(), second.end());
  return first;
}

bool RendererTakesRateChange(const media::AudioDecoderConfig& config) {
  const auto& asc = config.extra_data();
  if (config.codec() != media::AudioCodec::kAAC ||
      config.profile() == media::AudioCodecProfile::kXHE_AAC ||
      config.samples_per_second() > 24000) {
    return false;
  }
  if (asc.empty()) {
    return true;
  }
  constexpr int kCoreRates[] = {24000, 22050, 16000, 12000, 11025, 8000};
  const int frequency_index =
      asc.size() == 2 ? ((asc[0] & 0x07) << 1) | (asc[1] >> 7) : 0;
  return asc.size() == 2 && asc[0] >> 3 == 2 && frequency_index >= 6 &&
         frequency_index <= 11 && ((asc[1] >> 3) & 0x0f) >= 1 &&
         ((asc[1] >> 3) & 0x0f) <= 7 && (asc[1] & 0x07) == 0 &&
         kCoreRates[frequency_index - 6] == config.samples_per_second();
}

media::AudioDecoderConfig Config(int rate,
                                 media::ChannelLayout layout,
                                 std::vector<uint8_t> extra_data) {
  return media::AudioDecoderConfig(
      media::AudioCodec::kAAC, media::kSampleFormatF32,
      media::ChannelLayoutConfig(layout,
                                 media::ChannelLayoutToChannelCount(layout)),
      rate, extra_data, media::EncryptionScheme::kUnencrypted);
}

}

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr,
                 "usage: %s <fixture directory> [--seatbelt <profile> "
                 "[--expect-blocked] [NAME VALUE]...]\n",
                 argv[0]);
    return 2;
  }
  base::AtExitManager exit_manager;
  base::SingleThreadTaskExecutor executor;
  const std::string dir = argv[1];
  const Stream lc_mp4 = ReadMp4Packets(dir + "/lc.mp4packets");
  const Stream he_mp4 = ReadMp4Packets(dir + "/he.mp4packets");
  const Stream hev2_mp4 = ReadMp4Packets(dir + "/hev2.mp4packets");
  const Stream he_implicit_mp4 = ReadMp4Packets(dir + "/he_implicit.mp4packets");
  const Stream hev2_implicit_mp4 =
      ReadMp4Packets(dir + "/hev2_implicit.mp4packets");
  const Stream lc_adts = ReadAdts(dir + "/lc.aac");
  const Stream he_adts = ReadAdts(dir + "/he.aac");
  const Stream hev2_adts = ReadAdts(dir + "/hev2.aac");
  const Stream he_mono_adts = ReadAdts(dir + "/he_mono.aac");
  const Stream he51_adts = ReadAdts(dir + "/he51.aac");
  const Stream mono_adts = ReadAdts(dir + "/lc_mono.aac");
  const Stream lc22_adts = ReadAdts(dir + "/lc22.aac");
  const Stream lc22_mono_adts = ReadAdts(dir + "/lc22_mono.aac");
  const Pcm he_adts_macos = ReadPcm(dir + "/he.aac.pcm");
  const Pcm hev2_adts_macos = ReadPcm(dir + "/hev2.aac.pcm");
  const Pcm he_mp4_macos = ReadPcm(dir + "/he.m4a.pcm");
  const Pcm hev2_mp4_macos = ReadPcm(dir + "/hev2.m4a.pcm");
  const Pcm lc_mp4_macos = ReadPcm(dir + "/lc.m4a.pcm");
  constexpr double kCore44 = 1024.0 / 44100;
  constexpr double kCore22 = 1024.0 / 22050;
  struct SourceCase {
    const char* file;
    int reported_rate;
    int expected_rate;
    int expected_channels;
    bool high_band;
    bool stereo_source;
    double packet_seconds;
    Demuxed demuxed;
  };
  SourceCase source_cases[] = {
      {"lc.m4a", 44100, 44100, 2, true, true, kCore44, {}},
      {"he.m4a", 44100, 44100, 2, true, true, kCore22, {}},
      {"hev2.m4a", 44100, 44100, 2, true, true, kCore22, {}},
      {"he_implicit.m4a", 22050, 44100, 2, true, true, kCore22, {}},
      {"hev2_implicit.m4a", 22050, 44100, 2, true, true, kCore22, {}},
      {"lc.aac", 44100, 44100, 2, true, true, kCore44, {}},
      {"he.aac", 22050, 44100, 2, true, true, kCore22, {}},
      {"hev2.aac", 22050, 44100, 2, true, true, kCore22, {}},
      {"he_mono.aac", 22050, 44100, 2, true, false, kCore22, {}},
      {"he51.aac", 22050, 44100, 6, true, false, kCore22, {}},
      {"lc_mono.aac", 44100, 44100, 1, true, false, kCore44, {}},
      {"lc22.aac", 22050, 22050, 2, false, true, kCore22, {}},
  };
  for (auto& source : source_cases) {
    source.demuxed = DemuxWithFFmpeg(dir + "/" + source.file);
  }
  using media::CHANNEL_LAYOUT_MONO;
  using media::CHANNEL_LAYOUT_STEREO;

  if (argc > 3 && std::string(argv[2]) == "--seatbelt") {
    std::ifstream file(argv[3]);
    const std::string profile((std::istreambuf_iterator<char>(file)), {});
    int first_parameter = 4;
    const bool expect_blocked =
        argc > 4 && std::string(argv[4]) == "--expect-blocked";
    if (expect_blocked) {
      ++first_parameter;
    }
    std::vector<const char*> parameters(argv + first_parameter, argv + argc);
    parameters.push_back(nullptr);
    char* error = nullptr;
    if (profile.empty() ||
        sandbox_init_with_parameters(profile.c_str(), 0, parameters.data(),
                                     &error) != 0) {
      std::fprintf(stderr, "seatbelt: %s\n", error ? error : "no profile");
      return 3;
    }
    std::printf("Applied seatbelt profile %s\n", argv[3]);
    if (expect_blocked) {
      const Output blocked = Decode(
          Config(44100, CHANNEL_LAYOUT_STEREO, lc_mp4.audio_specific_config),
          lc_mp4.packets, kCore44);
      Expect(!blocked.initialized, "mp4 AAC-LC",
             "AudioToolbox refuses the stream under this profile");
      std::printf("%s: %d failure(s)\n", g_failures ? "FAILED" : "PASSED",
                  g_failures);
      return g_failures ? 1 : 0;
    }
  }

  Check(
      "mp4 AAC-LC",
      Decode(Config(44100, CHANNEL_LAYOUT_STEREO, lc_mp4.audio_specific_config),
             lc_mp4.packets, kCore44),
      {44100, 2, true, true}, lc_mp4.packets.size(), kCore44);
  Check(
      "mp4 HE-AAC",
      Decode(Config(44100, CHANNEL_LAYOUT_STEREO, he_mp4.audio_specific_config),
             he_mp4.packets, kCore22),
      {44100, 2, true, true}, he_mp4.packets.size(), kCore22);
  Check(
      "mp4 HE-AAC v2 (mono core config, stereo output)",
      Decode(Config(44100, CHANNEL_LAYOUT_MONO, hev2_mp4.audio_specific_config),
             hev2_mp4.packets, kCore22),
      {44100, 2, true, true}, hev2_mp4.packets.size(), kCore22);

  Check("adts AAC-LC",
        Decode(
            Config(44100, CHANNEL_LAYOUT_STEREO, lc_adts.audio_specific_config),
            lc_adts.packets, kCore44),
        {44100, 2, true, true}, lc_adts.packets.size(), kCore44);
  Check("adts HE-AAC with mp4a.40.5",
        Decode(
            Config(44100, CHANNEL_LAYOUT_STEREO, he_adts.audio_specific_config),
            he_adts.packets, kCore22),
        {44100, 2, true, true}, he_adts.packets.size(), kCore22);
  Check("adts HE-AAC v2 with mp4a.40.29",
        Decode(
            Config(44100, CHANNEL_LAYOUT_MONO, hev2_adts.audio_specific_config),
            hev2_adts.packets, kCore22),
        {44100, 2, true, true}, hev2_adts.packets.size(), kCore22);
  Check("adts mono AAC-LC stays mono",
        Decode(
            Config(44100, CHANNEL_LAYOUT_MONO, mono_adts.audio_specific_config),
            mono_adts.packets, kCore44),
        {44100, 1, true, false}, mono_adts.packets.size(), kCore44);

  Check("adts HE-AAC without an SBR hint finds SBR in the bitstream",
        Decode(
            Config(22050, CHANNEL_LAYOUT_STEREO, he_adts.audio_specific_config),
            he_adts.packets, kCore22),
        {44100, 2, true, true}, he_adts.packets.size(), kCore22);
  Check("adts HE-AAC v2 without an SBR hint",
        Decode(
            Config(22050, CHANNEL_LAYOUT_MONO, hev2_adts.audio_specific_config),
            hev2_adts.packets, kCore22),
        {44100, 2, true, true}, hev2_adts.packets.size(), kCore22);
  {
    const Output mono_he = Decode(
        Config(22050, CHANNEL_LAYOUT_MONO, he_mono_adts.audio_specific_config),
        he_mono_adts.packets, kCore22);
    Check("adts mono HE-AAC without PS plays as stereo, as in FFmpeg", mono_he,
          {44100, 2, true, false}, he_mono_adts.packets.size(), kCore22);
    double difference = 0;
    double level = 0;
    if (mono_he.pcm.size() == 2) {
      for (size_t i = 0; i < mono_he.pcm[0].size(); ++i) {
        difference += std::fabs(mono_he.pcm[0][i] - mono_he.pcm[1][i]);
        level += std::fabs(mono_he.pcm[0][i]);
      }
    }
    Expect(level > 0 && difference < 0.01 * level,
           "adts mono HE-AAC without PS", "both channels carry the mono signal");
  }
  Check("adts 5.1 HE-AAC without an SBR hint",
        Decode(Config(22050, media::CHANNEL_LAYOUT_5_1_BACK,
                      he51_adts.audio_specific_config),
               he51_adts.packets, kCore22),
        {44100, 6, true, false}, he51_adts.packets.size(), kCore22);
  Check("mp4 implicitly signalled HE-AAC",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO,
                      he_implicit_mp4.audio_specific_config),
               he_implicit_mp4.packets, kCore22),
        {44100, 2, true, true}, he_implicit_mp4.packets.size(), kCore22);
  Check("mp4 implicitly signalled HE-AAC v2",
        Decode(Config(22050, CHANNEL_LAYOUT_MONO,
                      hev2_implicit_mp4.audio_specific_config),
               hev2_implicit_mp4.packets, kCore22),
        {44100, 2, true, true}, hev2_implicit_mp4.packets.size(), kCore22);

  Check("adts AAC-LC at 22.05 kHz stays AAC-LC",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO,
                      lc22_adts.audio_specific_config),
               lc22_adts.packets, kCore22),
        {22050, 2, false, true}, lc22_adts.packets.size(), kCore22);
  Check("adts mono AAC-LC at 22.05 kHz stays mono AAC-LC",
        Decode(Config(22050, CHANNEL_LAYOUT_MONO,
                      lc22_mono_adts.audio_specific_config),
               lc22_mono_adts.packets, kCore22),
        {22050, 1, false, false}, lc22_mono_adts.packets.size(), kCore22);
  const std::vector<uint8_t> sbr_absent = {0x13, 0x90, 0x56, 0xe5, 0x00};
  const Output core =
      Decode(Config(22050, CHANNEL_LAYOUT_STEREO, sbr_absent), he_adts.packets,
             kCore22);
  Check("adts HE-AAC with SBR signalled absent keeps the AAC-LC core", core,
        {22050, 2, false, true}, he_adts.packets.size(), kCore22);
  Check("adts AAC-LC frames, then HE-AAC frames, stay AAC-LC",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO,
                      lc22_adts.audio_specific_config),
               Concatenate(Packets(lc22_adts.packets.begin(),
                                   lc22_adts.packets.begin() + 3),
                           he_adts.packets),
               kCore22),
        {22050, 2, false, true, false}, 3 + he_adts.packets.size(), kCore22);

  {
    const Output implicit = Decode(
        Config(22050, CHANNEL_LAYOUT_STEREO, he_adts.audio_specific_config),
        he_adts.packets, kCore22);
    const Output hinted = Decode(
        Config(44100, CHANNEL_LAYOUT_STEREO, he_adts.audio_specific_config),
        he_adts.packets, kCore22);
    const std::string name = "adts implicitly signalled HE-AAC";
    Expect(implicit.pcm == hinted.pcm && implicit.timestamps == hinted.timestamps,
           name, "decodes exactly as with an mp4a.40.5 hint");
    Expect(!implicit.timestamps.empty() &&
               implicit.timestamps.front() == base::TimeDelta(),
           name, "starts at the first packet's timestamp");
    if (!implicit.pcm.empty() && implicit.sample_rate == 44100 &&
        core.pcm.size() == 2) {
      const double left = ToneLagMs(implicit.pcm[0], 44100, core.pcm[0], 22050,
                                    1000);
      const double right = ToneLagMs(implicit.pcm[1], 44100, core.pcm[1],
                                     22050, 500);
      Expect(std::fabs(left) < 0.05 && std::fabs(right) < 0.05, name,
             "core tones line up with the AAC-LC core (lag " +
                 std::to_string(left) + " ms at 1 kHz, " +
                 std::to_string(right) + " ms at 500 Hz; first buffer " +
                 std::to_string(implicit.buffer_frames.front()) + " frames)");
    }
  }

  Check("webcodecs ADTS HE-AAC without description",
        Decode(Config(44100, CHANNEL_LAYOUT_STEREO, {}), he_adts.packets,
               kCore22),
        {44100, 2, true, true}, he_adts.packets.size(), kCore22);
  Check("webcodecs ADTS HE-AAC v2 without description at the core rate",
        Decode(Config(22050, CHANNEL_LAYOUT_MONO, {}), hev2_adts.packets,
               kCore22),
        {44100, 2, true, true}, hev2_adts.packets.size(), kCore22);
  const Output raw_without_config =
      Decode(Config(44100, CHANNEL_LAYOUT_STEREO, {}), lc_mp4.packets, kCore44);
  Expect(raw_without_config.initialized && !raw_without_config.decoded,
         "webcodecs raw AAC without description",
         "is refused at the first chunk");

  for (const auto& source : source_cases) {
    const std::string name = std::string("src= ") + source.file;
    const Demuxed& demuxed = source.demuxed;
    Expect(
        demuxed.opened && demuxed.sample_format_unset && demuxed.valid_config,
        name,
        "FFmpeg demuxes it without a decoder and Chromium's config is "
        "valid");
    if (!demuxed.valid_config) {
      continue;
    }
    Expect(demuxed.config.samples_per_second() == source.reported_rate, name,
           "FFmpeg reports " +
               std::to_string(demuxed.config.samples_per_second()) + " Hz");
    Expect(source.expected_rate == demuxed.config.samples_per_second() ||
               RendererTakesRateChange(demuxed.config),
           name,
           "any rate change is one the renderer accepts (" +
               std::to_string(demuxed.config.extra_data().size()) +
               "-byte config)");
    Expect(demuxed.timestamps_defined_and_increasing, name,
           "every packet has a defined, increasing PTS");
    Check(name,
          Decode(demuxed.config, demuxed.packets, source.packet_seconds,
                 std::nullopt, &demuxed.times),
          {source.expected_rate, source.expected_channels, source.high_band,
           source.stereo_source},
          demuxed.packets.size(), source.packet_seconds);
  }

  const Output reset =
      Decode(Config(44100, CHANNEL_LAYOUT_STEREO, lc_mp4.audio_specific_config),
             lc_mp4.packets, kCore44, lc_mp4.packets.size() / 2);
  Check("mp4 AAC-LC across Reset()", reset, {44100, 2, true, true, false},
        lc_mp4.packets.size(), kCore44);

  const auto he_core =
      Config(22050, CHANNEL_LAYOUT_STEREO, he_adts.audio_specific_config);
  Check("adts implicit HE-AAC with Reset() before the first access unit",
        Decode(he_core, he_adts.packets, kCore22, 0), {44100, 2, true, true},
        he_adts.packets.size(), kCore22);
  Check("adts implicit HE-AAC decodes across Reset()",
        Decode(he_core, he_adts.packets, kCore22, he_adts.packets.size() / 2),
        {44100, 2, true, true, false}, he_adts.packets.size(), kCore22);
  Check("adts AAC-LC frames, Reset(), then HE-AAC frames, stay AAC-LC",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO,
                      lc22_adts.audio_specific_config),
               Concatenate(Packets(lc22_adts.packets.begin(),
                                   lc22_adts.packets.begin() + 3),
                           he_adts.packets),
               kCore22, 3),
        {22050, 2, false, true, false}, 3 + he_adts.packets.size(), kCore22);
  Check("adts implicit HE-AAC after an empty buffer",
        Decode(he_core, Concatenate(Packets(1), he_adts.packets), kCore22),
        {44100, 2, true, true}, 1 + he_adts.packets.size(), kCore22);
  {
    Packets gap = {he_adts.packets[0], {}};
    gap.insert(gap.end(), he_adts.packets.begin() + 1, he_adts.packets.end());
    const Output output = Decode(he_core, gap, kCore22);
    Expect(output.initialized && output.decoded && !output.timestamps.empty() &&
               output.timestamps.front() == base::TimeDelta(),
           "adts implicit HE-AAC with an empty second buffer",
           "starts at the first access unit's timestamp");
  }
  Check("adts implicit HE-AAC after end of stream and Reset()",
        Decode(he_core, he_adts.packets, kCore22, std::nullopt, nullptr, true),
        {44100, 2, true, true}, he_adts.packets.size(), kCore22);
  Check("webcodecs ADTS HE-AAC after end of stream and Reset()",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO, {}), he_adts.packets,
               kCore22, std::nullopt, nullptr, true),
        {44100, 2, true, true}, he_adts.packets.size(), kCore22);

  Check("adts one-byte first access unit, then HE-AAC",
        Decode(he_core,
               Concatenate(Packets{AdtsFrame(he_adts.packets[0], {0x01})},
                           he_adts.packets),
               kCore22),
        {44100, 2, true, true, false}, 1 + he_adts.packets.size(), kCore22);
  Check("adts header-only first frame, then HE-AAC",
        Decode(he_core,
               Concatenate(Packets{ShortAdts(he_adts.packets[0], false)},
                           he_adts.packets),
               kCore22),
        {44100, 2, true, true, false}, 1 + he_adts.packets.size(), kCore22);
  Check("webcodecs one-byte first access unit, then HE-AAC",
        Decode(Config(22050, CHANNEL_LAYOUT_STEREO, {}),
               Concatenate(Packets{AdtsFrame(he_adts.packets[0], {0x01})},
                           he_adts.packets),
               kCore22),
        {44100, 2, true, true, false}, 1 + he_adts.packets.size(), kCore22);
  {
    const auto& unit = he_implicit_mp4.packets[5];
    Check("mp4 truncated first access unit, then HE-AAC",
          Decode(Config(22050, CHANNEL_LAYOUT_STEREO,
                        he_implicit_mp4.audio_specific_config),
                 Concatenate(Packets{std::vector<uint8_t>(
                                 unit.begin(), unit.begin() + unit.size() / 2)},
                             he_implicit_mp4.packets),
                 kCore22),
          {44100, 2, true, true, false}, 1 + he_implicit_mp4.packets.size(),
          kCore22);
  }

  ExpectMacOsDecoding("adts implicit HE-AAC",
                      Decode(he_core, he_adts.packets, kCore22), he_adts_macos);
  ExpectMacOsDecoding(
      "webcodecs ADTS HE-AAC without description",
      Decode(Config(22050, CHANNEL_LAYOUT_STEREO, {}), he_adts.packets,
             kCore22),
      he_adts_macos);
  {
    const Output v2 = Decode(
        Config(22050, CHANNEL_LAYOUT_MONO, hev2_adts.audio_specific_config),
        hev2_adts.packets, kCore22);
    ExpectMacOsDecoding("adts implicit HE-AAC v2", v2, hev2_adts_macos);
    float peak = 0;
    for (const auto& channel : v2.pcm) {
      for (const float sample : channel) {
        peak = std::max(peak, std::fabs(sample));
      }
    }
    Expect(peak > 1.0f, "adts implicit HE-AAC v2",
           "keeps its peaks above 1.0 (" + std::to_string(peak) + ")");
  }

  for (const auto& [file, expected] :
       {std::pair{"he.m4a", &he_mp4_macos},
        std::pair{"hev2.m4a", &hev2_mp4_macos},
        std::pair{"lc.m4a", &lc_mp4_macos},
        std::pair{"he_implicit.m4a", &he_mp4_macos}}) {
    const auto source = std::ranges::find_if(
        source_cases, [file](const SourceCase& item) {
          return std::string(item.file) == file;
        });
    const Demuxed& demuxed = source->demuxed;
    ExpectMacOsDecoding(
        std::string("src= ") + file + " with FFmpeg's priming and remainder",
        Decode(demuxed.config, demuxed.packets, source->packet_seconds,
               std::nullopt, &demuxed.times, false, &demuxed.discards),
        *expected);
  }
  {
    const size_t frames = he_adts_macos.empty() ? 0 : he_adts_macos[0].size();
    Discards trims(he_adts.packets.size());
    trims.front() = media::DecoderBuffer::DiscardPadding(
        media::AudioTimestampHelper::FramesToTime(3000, 44100),
        base::TimeDelta());
    trims.back() = media::DecoderBuffer::DiscardPadding(
        base::TimeDelta(), media::AudioTimestampHelper::FramesToTime(500, 44100));
    ExpectMacOsDecoding(
        "adts implicit HE-AAC, 3,000 frames of priming and 500 of remainder",
        Decode(he_core, he_adts.packets, kCore22, std::nullopt, nullptr, false,
               &trims),
        Without(Without(he_adts_macos, frames - 500, frames), 0, 3000));
    Discards second(he_adts.packets.size());
    second[1] = media::DecoderBuffer::DiscardPadding(media::kInfiniteDuration,
                                                     base::TimeDelta());
    ExpectMacOsDecoding("adts implicit HE-AAC without its second access unit",
                        Decode(he_core, he_adts.packets, kCore22, std::nullopt,
                               nullptr, false, &second),
                        Without(he_adts_macos, 2048, 4096));
  }

  {
    std::vector<uint8_t> noise(300);
    uint32_t seed = 1;
    for (auto& byte : noise) {
      seed = seed * 1664525 + 1013904223;
      byte = seed >> 24;
    }
    const std::vector<uint8_t> payload = AdtsPayload(he_adts.packets[5]);
    const std::vector<uint8_t> half(payload.begin(),
                                    payload.begin() + payload.size() / 2);
    std::vector<uint8_t> flipped = payload;
    flipped[flipped.size() / 3] ^= 0x5a;
    struct Damaged {
      const char* name;
      std::vector<uint8_t> first;
    };
    const Damaged damaged[] = {
        {"random bytes", AdtsFrame(he_adts.packets[0], noise)},
        {"a truncated access unit", AdtsFrame(he_adts.packets[0], half)},
        {"a bit-damaged access unit", AdtsFrame(he_adts.packets[0], flipped)},
        {"a one-byte access unit", AdtsFrame(he_adts.packets[0], {0x01})},
        {"8,184 bytes, the longest ADTS payload",
         AdtsFrame(he_adts.packets[0], std::vector<uint8_t>(8184, 0x21))},
    };
    auto survives = [](const std::string& name, const Output& output) {
      Expect(output.initialized &&
                 (!output.decoded ||
                  (output.consistent && (output.sample_rate == 22050 ||
                                         output.sample_rate == 44100))),
             name,
             std::string("survives (") +
                 (output.decoded ? "decoded" : "decode failed") + ", " +
                 std::to_string(output.sample_rate) + " Hz)");
    };
    for (const auto& item : damaged) {
      for (const bool described : {true, false}) {
        survives(std::string(described ? "adts" : "webcodecs") +
                     " first access unit of " + item.name,
                 Decode(described ? he_core
                                  : Config(22050, CHANNEL_LAYOUT_STEREO, {}),
                        Concatenate(Packets{item.first}, he_adts.packets),
                        kCore22));
      }
    }
    const auto mp4_core = Config(22050, CHANNEL_LAYOUT_STEREO,
                                 he_implicit_mp4.audio_specific_config);
    survives("mp4 first access unit of random bytes",
             Decode(mp4_core, Concatenate(Packets{noise}, he_implicit_mp4.packets),
                    kCore22));
    survives("mp4 first access unit of 8,185 bytes",
             Decode(mp4_core,
                    Concatenate(Packets{std::vector<uint8_t>(8185, 0x21)},
                                he_implicit_mp4.packets),
                    kCore22));
  }

  Packets multi_block = lc_adts.packets;
  multi_block[0][6] |= 0x01;
  const Output rejected = Decode(
      Config(44100, CHANNEL_LAYOUT_STEREO, lc_adts.audio_specific_config),
      multi_block, kCore44);
  Expect(rejected.initialized && !rejected.decoded,
         "adts frame with two raw data blocks", "fails to decode");

  for (const bool crc : {true, false}) {
    const std::string frame =
        crc ? "8-byte CRC ADTS frame" : "7-byte ADTS frame";
    const Packets short_frame = {ShortAdts(lc_adts.packets[0], crc)};
    const Output without_description =
        Decode(Config(44100, CHANNEL_LAYOUT_STEREO, {}), short_frame, kCore44);
    Expect(without_description.initialized && !without_description.decoded,
           "webcodecs " + frame, "is refused without a description");
    const Output with_config = Decode(
        Config(44100, CHANNEL_LAYOUT_STEREO, lc_adts.audio_specific_config),
        short_frame, kCore44);
    Expect(with_config.initialized, "configured decoder, " + frame,
           std::string("survives it (") +
               (with_config.decoded ? "decoded" : "decode failed") + ")");
  }

  {
    auto xhe = Config(48000, CHANNEL_LAYOUT_STEREO, {});
    xhe.set_profile(media::AudioCodecProfile::kXHE_AAC);
    const media::AudioDecoderConfig ac3(
        media::AudioCodec::kAC3, media::kSampleFormatF32,
        media::ChannelLayoutConfig::Stereo(), 48000, {},
        media::EncryptionScheme::kUnencrypted);
    using media::AudioToolboxAudioDecoder;
    Expect(AudioToolboxAudioDecoder::DrainsAtEndOfStreamForTesting(he_core) &&
               AudioToolboxAudioDecoder::DrainsAtEndOfStreamForTesting(
                   Config(44100, CHANNEL_LAYOUT_STEREO, {})) &&
               !AudioToolboxAudioDecoder::DrainsAtEndOfStreamForTesting(xhe) &&
               !AudioToolboxAudioDecoder::DrainsAtEndOfStreamForTesting(ac3),
           "end of stream", "drains AAC-LC and HE-AAC, not xHE-AAC or AC-3");
  }

  {
    media::AudioToolboxAudioDecoder decoder(
        std::make_unique<media::NullMediaLog>());
    std::optional<media::DecoderStatus> init_status;
    std::optional<media::DecoderStatus> decode_status;
    bool reset_done = false;
    auto record = [](std::optional<media::DecoderStatus>* out,
                     media::DecoderStatus result) { *out = std::move(result); };
    decoder.Initialize(Config(44100, CHANNEL_LAYOUT_STEREO, {0x0a, 0x10}),
                       nullptr, base::BindOnce(record, &init_status),
                       base::DoNothing(), base::DoNothing());
    base::RunLoop().RunUntilIdle();
    auto buffer = media::DecoderBuffer::CopyFrom(lc_mp4.packets[0]);
    buffer->set_timestamp(base::TimeDelta());
    decoder.Decode(buffer, base::BindOnce(record, &decode_status));
    decoder.Reset(
        base::BindOnce([](bool* done) { *done = true; }, &reset_done));
    base::RunLoop().RunUntilIdle();
    Expect(init_status && !init_status->is_ok() && decode_status &&
               decode_status->code() ==
                   media::DecoderStatus::Codes::kNotInitialized &&
               reset_done,
           "AAC Main after a failed Initialize()",
           "Decode() fails and Reset() completes");
  }

  std::printf("%s: %d failure(s)\n", g_failures ? "FAILED" : "PASSED",
              g_failures);
  return g_failures ? 1 : 0;
}

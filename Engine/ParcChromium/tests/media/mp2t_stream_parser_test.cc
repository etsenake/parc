// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/mp2t_stream_parser_test.cc. The fixture is derived from
// Chromium's mp2t_stream_parser_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

#include "media/formats/mp2t/mp2t_stream_parser.h"

#include <stddef.h>
#include <stdint.h>

#include <algorithm>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/stringprintf.h"
#include "base/time/time.h"
#include "base/test/bind.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/decoder_buffer.h"
#include "media/base/encryption_pattern.h"
#include "media/base/media_track.h"
#include "media/base/media_tracks.h"
#include "media/base/media_util.h"
#include "media/base/stream_parser.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/test_data_util.h"
#include "media/base/video_decoder_config.h"
#include "media/media_buildflags.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {
namespace mp2t {

namespace {

bool IsMonotonic(const StreamParser::BufferQueue& buffers) {
  if (buffers.empty())
    return true;

  StreamParser::BufferQueue::const_iterator it1 = buffers.begin();
  StreamParser::BufferQueue::const_iterator it2 = ++it1;
  for ( ; it2 != buffers.end(); ++it1, ++it2) {
    if ((*it2)->GetDecodeTimestamp() < (*it1)->GetDecodeTimestamp())
      return false;
  }
  return true;
}

}  // namespace

class ParcMp2tStreamParserTest : public testing::Test {
 public:
  ParcMp2tStreamParserTest()
      : config_count_(0),
        audio_frame_count_(0),
        video_frame_count_(0),
        has_audio_(true),
        has_video_(true),
        audio_min_dts_(kNoDecodeTimestamp),
        audio_max_dts_(kNoDecodeTimestamp),
        video_min_dts_(kNoDecodeTimestamp),
        video_max_dts_(kNoDecodeTimestamp),
        audio_track_id_(0),
        video_track_id_(0),
        current_audio_config_(),
        current_video_config_(),
        capture_buffers(false) {
    CreateStrictParser();
  }

 protected:
  NullMediaLog media_log_;
  std::unique_ptr<Mp2tStreamParser> parser_;
  int config_count_;
  int audio_frame_count_;
  int video_frame_count_;
  bool has_audio_;
  bool has_video_;
  DecodeTimestamp audio_min_dts_;
  DecodeTimestamp audio_max_dts_;
  DecodeTimestamp video_min_dts_;
  DecodeTimestamp video_max_dts_;
  StreamParser::TrackId audio_track_id_;
  StreamParser::TrackId video_track_id_;

  AudioDecoderConfig current_audio_config_;
  VideoDecoderConfig current_video_config_;
  std::vector<scoped_refptr<StreamParserBuffer>> audio_buffer_capture_;
  std::vector<scoped_refptr<StreamParserBuffer>> video_buffer_capture_;
  bool capture_buffers;
  std::vector<std::pair<EmeInitDataType, std::string>> init_data_;

  void CreateNonStrictParser() {
    bool has_sbr = false;
    parser_ = std::make_unique<Mp2tStreamParser>(std::nullopt, has_sbr);
  }

  void CreateStrictParser() {
    bool has_sbr = false;
    const std::string codecs[] = {"avc1.64001e", "mp3", "aac"};
    parser_ = std::make_unique<Mp2tStreamParser>(codecs, has_sbr);
  }

  void ResetStats() {
    config_count_ = 0;
    audio_frame_count_ = 0;
    video_frame_count_ = 0;
    audio_min_dts_ = kNoDecodeTimestamp;
    audio_max_dts_ = kNoDecodeTimestamp;
    video_min_dts_ = kNoDecodeTimestamp;
    video_max_dts_ = kNoDecodeTimestamp;
  }

  // Note this is similar to a StreamParserTestBase method, so may benefit from
  // utility method or inheritance if they don't diverge.
  bool AppendAllDataThenParseInPieces(base::span<const uint8_t> data,
                                      size_t piece_size) {
    if (!parser_->AppendToParseBuffer(data)) {
      return false;
    }

    // Also verify that the expected number of pieces is needed to fully parse
    // `data`.
    size_t expected_remaining_data = data.size();
    bool has_more_data = true;

    // A zero-length append still needs a single iteration of parse.
    while (has_more_data) {
      StreamParser::ParseStatus parse_result = parser_->Parse(piece_size);
      if (parse_result == StreamParser::ParseStatus::kFailed) {
        return false;
      }

      has_more_data =
          parse_result == StreamParser::ParseStatus::kSuccessHasMoreData;

      EXPECT_EQ(piece_size < expected_remaining_data, has_more_data);

      if (has_more_data) {
        expected_remaining_data -= piece_size;
      } else {
        EXPECT_EQ(parse_result, StreamParser::ParseStatus::kSuccess);
      }
    }

    return true;
  }

  void OnInit(const StreamParser::InitParameters& params) {
    DVLOG(1) << "OnInit: dur=" << params.duration.InMilliseconds();
  }

  bool OnNewConfig(std::unique_ptr<MediaTracks> tracks) {
    DVLOG(1) << "OnNewConfig: got " << tracks->tracks().size() << " tracks";
    size_t audio_track_count = 0;
    size_t video_track_count = 0;
    for (const auto& track : tracks->tracks()) {
      const auto& track_id = track->stream_id();
      if (track->type() == MediaTrack::Type::kAudio) {
        audio_track_id_ = track_id;
        audio_track_count++;
        EXPECT_TRUE(tracks->getAudioConfig(track_id).IsValidConfig());
        current_audio_config_ = tracks->getAudioConfig(track_id);
      } else if (track->type() == MediaTrack::Type::kVideo) {
        video_track_id_ = track_id;
        video_track_count++;
        EXPECT_TRUE(tracks->getVideoConfig(track_id).IsValidConfig());
        current_video_config_ = tracks->getVideoConfig(track_id);
      } else {
        // Unexpected track type.
        LOG(ERROR) << "Unexpected track type "
                   << std::to_underlying(track->type());
        EXPECT_TRUE(false);
      }
    }
    EXPECT_EQ(has_audio_, audio_track_count > 0);
    EXPECT_EQ(has_video_, video_track_count > 0);
    EXPECT_EQ(tracks->GetAudioConfigs().size(), audio_track_count);
    EXPECT_EQ(tracks->GetVideoConfigs().size(), video_track_count);
    config_count_++;
    return true;
  }

  void CaptureVideoBuffers(const StreamParser::BufferQueue& video_buffers) {
    for (const auto& buffer : video_buffers) {
      video_buffer_capture_.push_back(buffer);
    }
  }

  void CaptureAudioBuffers(const StreamParser::BufferQueue& audio_buffers) {
    for (const auto& buffer : audio_buffers) {
      audio_buffer_capture_.push_back(buffer);
    }
  }

  bool OnNewBuffers(const StreamParser::BufferQueueMap& buffer_queue_map) {
    EXPECT_GT(config_count_, 0);
    // Ensure that track ids are properly assigned on all emitted buffers.
    for (const auto& [track_id, buffer] : buffer_queue_map) {
      DVLOG(3) << "Buffers for track_id=" << track_id;
      for (const auto& buf : buffer) {
        DVLOG(3) << "  track_id=" << buf->track_id() << ", size=" << buf->size()
                 << ", pts=" << buf->timestamp().InSecondsF()
                 << ", dts=" << buf->GetDecodeTimestamp().InSecondsF()
                 << ", dur=" << buf->duration().InSecondsF();
        EXPECT_EQ(track_id, buf->track_id());
      }
    }

    const StreamParser::BufferQueue empty_buffers;
    const auto& itr_audio = buffer_queue_map.find(audio_track_id_);
    const StreamParser::BufferQueue& audio_buffers =
        (itr_audio == buffer_queue_map.end()) ? empty_buffers
                                              : itr_audio->second;

    const auto& itr_video = buffer_queue_map.find(video_track_id_);
    const StreamParser::BufferQueue& video_buffers =
        (itr_video == buffer_queue_map.end()) ? empty_buffers
                                              : itr_video->second;

    if (capture_buffers) {
      CaptureVideoBuffers(video_buffers);
      CaptureAudioBuffers(audio_buffers);
    }

    // Verify monotonicity.
    if (!IsMonotonic(video_buffers))
      return false;
    if (!IsMonotonic(audio_buffers))
      return false;

    if (!video_buffers.empty()) {
      DecodeTimestamp first_dts = video_buffers.front()->GetDecodeTimestamp();
      DecodeTimestamp last_dts = video_buffers.back()->GetDecodeTimestamp();
      if (video_max_dts_ != kNoDecodeTimestamp && first_dts < video_max_dts_)
        return false;
      if (video_min_dts_ == kNoDecodeTimestamp)
        video_min_dts_ = first_dts;
      video_max_dts_ = last_dts;
    }
    if (!audio_buffers.empty()) {
      DecodeTimestamp first_dts = audio_buffers.front()->GetDecodeTimestamp();
      DecodeTimestamp last_dts = audio_buffers.back()->GetDecodeTimestamp();
      if (audio_max_dts_ != kNoDecodeTimestamp && first_dts < audio_max_dts_)
        return false;
      if (audio_min_dts_ == kNoDecodeTimestamp)
        audio_min_dts_ = first_dts;
      audio_max_dts_ = last_dts;
    }

    audio_frame_count_ += audio_buffers.size();
    video_frame_count_ += video_buffers.size();
    return true;
  }

  void OnKeyNeeded(EmeInitDataType type,
                   const std::vector<uint8_t>& init_data) {
    init_data_.emplace_back(type, std::string(init_data.begin(), init_data.end()));
  }

  void OnNewSegment() {
    DVLOG(1) << "OnNewSegment";
  }

  void OnEndOfSegment() {
    LOG(ERROR) << "OnEndOfSegment not expected in the Mpeg2 TS parser";
    EXPECT_TRUE(false);
  }

  void InitializeParser() {
    parser_->Init(
        base::BindOnce(&ParcMp2tStreamParserTest::OnInit, base::Unretained(this)),
        base::BindRepeating(&ParcMp2tStreamParserTest::OnNewConfig,
                            base::Unretained(this)),
        base::BindRepeating(&ParcMp2tStreamParserTest::OnNewBuffers,
                            base::Unretained(this)),
        base::BindRepeating(&ParcMp2tStreamParserTest::OnKeyNeeded,
                            base::Unretained(this)),
        base::BindRepeating(&ParcMp2tStreamParserTest::OnNewSegment,
                            base::Unretained(this)),
        base::BindRepeating(&ParcMp2tStreamParserTest::OnEndOfSegment,
                            base::Unretained(this)),
        &media_log_);
  }

  // Note this is also similar to a StreamParserTestBase method.
  bool ParseMpeg2TsFile(const std::string& filename, int append_bytes) {
    CHECK_GE(append_bytes, 0);
    scoped_refptr<DecoderBuffer> buffer = ReadTestDataFile(filename);

    size_t start = 0;
    size_t end = buffer->size();
    do {
      size_t chunk_size = std::min(static_cast<size_t>(append_bytes),
                                   static_cast<size_t>(end - start));
      // Attempt to incrementally parse each appended chunk to test out the
      // parser's internal management of input queue and pending data bytes.
      EXPECT_TRUE(AppendAllDataThenParseInPieces(
          (*buffer).subspan(start, chunk_size),
          (chunk_size > 7) ? (chunk_size - 7) : chunk_size));
      start += chunk_size;
    } while (start < end);

    return true;
  }
};

TEST(ParcMp2tSafariTracksTest, SafariKeepsBothAudioPidsChromeKeepsLowest) {
  for (bool safari : {false, true}) {
    Mp2tStreamParser parser(std::nullopt, false);
    if (safari) {
      parser.ParcIgnoreDeclaredCodecs();
    }
    NullMediaLog log;
    std::map<int, size_t> counts;
    size_t configs = 0;
    parser.Init(base::BindOnce([](const StreamParser::InitParameters& p) {}),
        base::BindLambdaForTesting([&](std::unique_ptr<MediaTracks> tracks) {
          configs = tracks->GetAudioConfigs().size();
          EXPECT_EQ(configs, safari ? 2u : 1u);
          for (const auto& [id, config] : tracks->GetAudioConfigs()) {
            EXPECT_TRUE(config.IsValidConfig());
            counts.try_emplace(id, 0);
          }
          return true;
        }),
        base::BindLambdaForTesting([&](const StreamParser::BufferQueueMap& buffers) {
          for (const auto& [id, queue] : buffers) {
            EXPECT_TRUE(counts.contains(id));
            for (const auto& buffer : queue) {
              EXPECT_EQ(buffer->track_id(), id);
              ++counts[id];
            }
          }
          return true;
        }), base::BindRepeating([](EmeInitDataType, const std::vector<uint8_t>&) {}),
        base::DoNothing(), base::DoNothing(), &log);
    const auto data = ReadTestDataFile("parc-two-audio.ts");
    for (size_t start = 0; start < data->size();) {
      const size_t size = std::min(size_t{188}, data->size() - start);
      ASSERT_TRUE(parser.AppendToParseBuffer(base::span(*data).subspan(start, size)));
      ASSERT_NE(parser.Parse(size), StreamParser::ParseStatus::kFailed);
      start += size;
    }
    parser.MarkEndOfStream();
    parser.Flush();
    // After abort/reset, each returning PID still requires its own config.
    ASSERT_TRUE(parser.AppendToParseBuffer(base::span(*data)));
    ASSERT_NE(parser.Parse(data->size()), StreamParser::ParseStatus::kFailed);
    parser.MarkEndOfStream();
    EXPECT_EQ(configs, safari ? 2u : 1u);
    EXPECT_EQ(counts.size(), safari ? 2u : 1u);
    for (const auto& [id, count] : counts) {
      EXPECT_GT(count, 1u);
    }
  }
}

// Parc: with ParcIgnoreDeclaredCodecs(), as on a document presenting Safari's
// identity (SourceBufferState::ParcSetSafariInitSegmentRules()), streams of
// codecs the type didn't name are parsed too.
TEST_F(ParcMp2tStreamParserTest, ParcKeepsUndeclaredAudioStream) {
  const std::string codecs[] = {"avc1.64001e"};
  parser_ = std::make_unique<Mp2tStreamParser>(codecs, false);
  parser_->ParcIgnoreDeclaredCodecs();

  InitializeParser();
  ParseMpeg2TsFile("bear-1280x720.ts", 512);
  parser_->Flush();
  EXPECT_EQ(audio_frame_count_, 119);
  EXPECT_EQ(video_frame_count_, 82);
  EXPECT_EQ(config_count_, 1);
}

TEST_F(ParcMp2tStreamParserTest, ParcKeepsUndeclaredVideoStream) {
  const std::string codecs[] = {"mp4a.40.2"};
  parser_ = std::make_unique<Mp2tStreamParser>(codecs, false);
  parser_->ParcIgnoreDeclaredCodecs();

  InitializeParser();
  ParseMpeg2TsFile("bear-1280x720.ts", 512);
  parser_->Flush();
  EXPECT_EQ(audio_frame_count_, 119);
  EXPECT_EQ(video_frame_count_, 82);
  EXPECT_EQ(config_count_, 1);
}

// Parc: MPEG-2 video (stream type 0x02), which AVStreamDataParser reads,
// under ParcIgnoreDeclaredCodecs() only. The file holds twelve 64x48 16:9
// pictures in three GOPs, the first closed, at 25 frames per second, one per
// PES packet; the second file is the same pictures two per PES packet, so
// every other one has no timestamp of its own. AVStreamDataParser gives both
// the same timestamps, a 4:3 pixel aspect ratio, and one sync sample.
TEST_F(ParcMp2tStreamParserTest, ParcMpeg2VideoStreamUnderSafariRules) {
  for (const char* file :
       {"parc-mpeg2-video.ts", "parc-mpeg2-video-shared-pes.ts"}) {
    SCOPED_TRACE(file);
    CreateNonStrictParser();
    parser_->ParcIgnoreDeclaredCodecs();
    has_audio_ = false;
    capture_buffers = true;
    video_buffer_capture_.clear();
    ResetStats();

    InitializeParser();
    ParseMpeg2TsFile(file, 512);
    parser_->Flush();
    EXPECT_EQ(config_count_, 1);
    EXPECT_EQ(current_video_config_.codec(), VideoCodec::kMPEG2);
    EXPECT_EQ(current_video_config_.coded_size(), gfx::Size(64, 48));
    EXPECT_EQ(current_video_config_.natural_size(), gfx::Size(85, 48));
    EXPECT_EQ(current_video_config_.aspect_ratio(),
              VideoAspectRatio::PAR(768, 576));
    ASSERT_EQ(current_video_config_.extra_data().size(), 22u);
    EXPECT_EQ(current_video_config_.extra_data()[3], 0xB3);

    // Presentation/decode milliseconds, K for a key frame.
    std::vector<std::string> frames;
    for (const auto& buffer : video_buffer_capture_) {
      frames.push_back(
          base::NumberToString(buffer->timestamp().InMilliseconds()) + "/" +
          base::NumberToString(
              buffer->GetDecodeTimestamp().InMilliseconds()) +
          (buffer->is_key_frame() ? "K" : ""));
    }
    const std::vector<std::string> expected_frames = {
        "1440/1400K", "1560/1440", "1480/1480", "1520/1520",
        "1680/1560",  "1600/1600", "1640/1640", "1800/1680",
        "1720/1720",  "1760/1760", "1880/1800", "1840/1840"};
    EXPECT_EQ(frames, expected_frames);
    EXPECT_EQ(video_buffer_capture_.front()->size(), 2034u);
  }
}

TEST_F(ParcMp2tStreamParserTest, ParcMpeg2VideoStreamIgnoredOtherwise) {
  CreateNonStrictParser();

  InitializeParser();
  ParseMpeg2TsFile("parc-mpeg2-video.ts", 512);
  parser_->Flush();
  EXPECT_EQ(config_count_, 0);
  EXPECT_EQ(video_frame_count_, 0);
}

#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
// Parc: AC-3 (stream type 0x81) and E-AC-3 (0x87), which AVStreamDataParser
// reads, under ParcIgnoreDeclaredCodecs() only. Each file holds the first ten
// syncframes of bear.ac3 or bear.eac3, one per PES packet.
TEST_F(ParcMp2tStreamParserTest, ParcAc3StreamUnderSafariRules) {
  CreateNonStrictParser();
  parser_->ParcIgnoreDeclaredCodecs();
  has_video_ = false;

  InitializeParser();
  ParseMpeg2TsFile("parc-bear-ac3.ts", 512);
  parser_->Flush();
  EXPECT_EQ(config_count_, 1);
  EXPECT_EQ(audio_frame_count_, 10);
  EXPECT_EQ(current_audio_config_.codec(), AudioCodec::kAC3);
  EXPECT_EQ(current_audio_config_.samples_per_second(), 44100);
}

TEST_F(ParcMp2tStreamParserTest, ParcEac3StreamUnderSafariRules) {
  CreateNonStrictParser();
  parser_->ParcIgnoreDeclaredCodecs();
  has_video_ = false;

  InitializeParser();
  ParseMpeg2TsFile("parc-bear-eac3.ts", 512);
  parser_->Flush();
  EXPECT_EQ(config_count_, 1);
  EXPECT_EQ(audio_frame_count_, 10);
  EXPECT_EQ(current_audio_config_.codec(), AudioCodec::kEAC3);
}

TEST_F(ParcMp2tStreamParserTest, ParcAc3StreamIgnoredOtherwise) {
  CreateNonStrictParser();
  has_video_ = false;

  InitializeParser();
  ParseMpeg2TsFile("parc-bear-ac3.ts", 512);
  parser_->Flush();
  EXPECT_EQ(config_count_, 0);
  EXPECT_EQ(audio_frame_count_, 0);
}
#endif  // BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)

// Parc: HLS SAMPLE-AES under ParcIgnoreDeclaredCodecs(), as Safari's Media
// Source takes it through AVStreamDataParser: each stream reports "mpts" init
// data once (AVStreamDataParser's key specifier bytes for the file, macOS
// 27.2), configs are protected, AAC takes the audio setup's
// AudioSpecificConfig, and samples stay as carried (emulation prevention
// kept), each marked with WebKit's mpts key ID. Chromium's rules report the
// file's CENC pssh (its CAT) and no mpts.
TEST_F(ParcMp2tStreamParserTest, ParcSampleAesUnderSafariRules) {
  size_t chrome_video_bytes = 0;
  size_t chrome_video_buffers = 0;
  InitializeParser();
  capture_buffers = true;
  ParseMpeg2TsFile("bear-1280x720-hls-sample-aes.ts", 2048);
  parser_->Flush();
  ASSERT_EQ(init_data_.size(), 1u);
  EXPECT_EQ(init_data_[0].first, EmeInitDataType::CENC);
  init_data_.clear();
  for (const auto& buffer : video_buffer_capture_) {
    chrome_video_bytes += buffer->size();
  }
  chrome_video_buffers = video_buffer_capture_.size();

  CreateNonStrictParser();
  parser_->ParcIgnoreDeclaredCodecs();
  ResetStats();
  video_buffer_capture_.clear();
  audio_buffer_capture_.clear();
  InitializeParser();
  ParseMpeg2TsFile("bear-1280x720-hls-sample-aes.ts", 2048);
  parser_->Flush();
  const std::vector<std::pair<EmeInitDataType, std::string>> expected_init_data =
      {{EmeInitDataType::MPTS,
        "{\n  \"cont\" : \"mpts\",\n  \"codc\" : 2053207651,\n"
        "  \"mtyp\" : 1986618469\n}"},
       {EmeInitDataType::MPTS,
        "{\n  \"cont\" : \"mpts\",\n  \"codc\" : 2053202275,\n"
        "  \"mtyp\" : 1936684398\n}"}};
  EXPECT_EQ(init_data_, expected_init_data);
  EXPECT_EQ(current_video_config_.encryption_scheme(), EncryptionScheme::kCbcs);
  EXPECT_EQ(current_audio_config_.encryption_scheme(), EncryptionScheme::kCbcs);
  EXPECT_EQ(current_audio_config_.parc_ts_audio_type(), 0x7a616163u);
  EXPECT_EQ(current_audio_config_.extra_data(),
            std::vector<uint8_t>({0x12, 0x10}));
  ASSERT_EQ(video_buffer_capture_.size(), chrome_video_buffers);
  ASSERT_FALSE(audio_buffer_capture_.empty());
  size_t safari_video_bytes = 0;
  for (const auto* buffers : {&video_buffer_capture_, &audio_buffer_capture_}) {
    for (const auto& buffer : *buffers) {
      ASSERT_TRUE(buffer->decrypt_config());
      EXPECT_EQ(buffer->decrypt_config()->key_id(), "TransportStreamIdentifier");
      EXPECT_EQ(buffer->decrypt_config()->iv(), std::string(16, '\0'));
      EXPECT_TRUE(buffer->decrypt_config()->subsamples().empty());
    }
  }
  for (const auto& buffer : video_buffer_capture_) {
    safari_video_bytes += buffer->size();
  }
  // Chromium's SAMPLE-AES parser removes the slices' emulation prevention.
  EXPECT_GT(safari_video_bytes, chrome_video_bytes);

  // Reported once per stream, aborts included.
  ResetStats();
  ParseMpeg2TsFile("bear-1280x720-hls-sample-aes.ts", 2048);
  parser_->Flush();
  EXPECT_EQ(init_data_.size(), 2u);
}

#if BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)
// Parc: HLS SAMPLE-AES AC-3 (0xc1, 'ac3d') and E-AC-3 (0xc2, 'ec3d') under
// Safari's rules only. The files are parc-bear-ac3.ts and parc-bear-eac3.ts
// relabeled with an audio setup ('zac3' with the first syncframe's first ten
// bytes, 'zec3' with the 'dec3' payload), which AVStreamDataParser reads as
// zac3 and zec3; E-AC-3's config takes that 'dec3' payload as its format does.
TEST_F(ParcMp2tStreamParserTest, ParcSampleAesAc3UnderSafariRules) {
  struct Case {
    const char* file;
    AudioCodec codec;
    uint32_t format_type;
    std::vector<uint8_t> extra_data;
  };
  for (const Case& test : {Case{"parc-bear-ac3-sample-aes.ts", AudioCodec::kAC3,
                                0x7a616333, {}},
                           Case{"parc-bear-eac3-sample-aes.ts",
                                AudioCodec::kEAC3, 0x7a656333,
                                {0x06, 0x38, 0x20, 0x04, 0x00}}}) {
    SCOPED_TRACE(test.file);
    has_video_ = false;
    CreateNonStrictParser();
    ResetStats();
    init_data_.clear();
    InitializeParser();
    ParseMpeg2TsFile(test.file, 512);
    parser_->Flush();
    EXPECT_EQ(config_count_, 0);
    EXPECT_TRUE(init_data_.empty());

    CreateNonStrictParser();
    parser_->ParcIgnoreDeclaredCodecs();
    ResetStats();
    capture_buffers = true;
    audio_buffer_capture_.clear();
    InitializeParser();
    ParseMpeg2TsFile(test.file, 512);
    parser_->Flush();
    EXPECT_EQ(config_count_, 1);
    EXPECT_EQ(audio_frame_count_, 10);
    EXPECT_EQ(current_audio_config_.codec(), test.codec);
    EXPECT_EQ(current_audio_config_.encryption_scheme(),
              EncryptionScheme::kCbcs);
    EXPECT_EQ(current_audio_config_.extra_data(), test.extra_data);
    ASSERT_EQ(init_data_.size(), 1u);
    EXPECT_EQ(init_data_[0].first, EmeInitDataType::MPTS);
    EXPECT_EQ(init_data_[0].second,
              base::StringPrintf("{\n  \"cont\" : \"mpts\",\n  \"codc\" : %u,\n"
                                 "  \"mtyp\" : 1936684398\n}",
                                 test.format_type));
    for (const auto& buffer : audio_buffer_capture_) {
      ASSERT_TRUE(buffer->decrypt_config());
      EXPECT_EQ(buffer->decrypt_config()->key_id(), "TransportStreamIdentifier");
    }
  }
}
#endif  // BUILDFLAG(ENABLE_PLATFORM_AC3_EAC3_AUDIO)

}  // namespace mp2t
}  // namespace media

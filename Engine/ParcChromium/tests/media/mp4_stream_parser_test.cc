// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/mp4_stream_parser_test.cc. The fixture is derived from
// Chromium's mp4_stream_parser_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

#include "media/formats/mp4/mp4_stream_parser.h"

#include <stddef.h>
#include <stdint.h>

#include <algorithm>
#include <array>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/time/time.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_track.h"
#include "media/base/media_tracks.h"
#include "media/base/mock_media_log.h"
#include "media/base/stream_parser.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/test_data_util.h"
#include "media/base/test_helpers.h"
#include "media/base/video_decoder_config.h"
#include "media/media_buildflags.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::testing::InSequence;
using ::testing::StrictMock;

namespace media {
namespace mp4 {
MATCHER_P(ErrorLog, error_string, "") {
  return arg.contains(error_string) && arg.contains("error");
}

class ParcMP4StreamParserTest : public testing::Test {
 public:
  ParcMP4StreamParserTest() {
    base::flat_set<int> audio_object_types;
    audio_object_types.insert(kISO_14496_3);
    parser_.reset(
        new MP4StreamParser(audio_object_types, false, false, false, false));
  }

 protected:
  StrictMock<MockMediaLog> media_log_;
  std::unique_ptr<MP4StreamParser> parser_;
  std::unique_ptr<MediaTracks> media_tracks_;
  AudioDecoderConfig audio_decoder_config_;
  VideoDecoderConfig video_decoder_config_;
  DecodeTimestamp lower_bound_ = kMaxDecodeTimestamp;
  StreamParser::TrackId audio_track_id_ = 0;

  bool capture_pcm_buffers_ = false;
  std::vector<scoped_refptr<StreamParserBuffer>> pcm_buffers_;

  // Note this is similar to a StreamParserTestBase method, so may benefit from
  // utility method or inheritance if they don't diverge.
  bool AppendAllDataThenParseInPieces(base::span<const uint8_t> data,
                                      size_t piece_size) {
    EXPECT_TRUE(parser_->AppendToParseBuffer(data));

    // Also verify the expected number of pieces is needed to fully parse
    // `data`.
    size_t expected_remaining_data = data.size();
    bool has_more_data = true;

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

  void InitF(const StreamParser::InitParameters& expected_params,
             const StreamParser::InitParameters& params) {
    DVLOG(1) << "InitF: dur=" << params.duration.InMicroseconds();
    EXPECT_EQ(expected_params.duration, params.duration);
    EXPECT_EQ(expected_params.timeline_offset, params.timeline_offset);
    EXPECT_EQ(expected_params.liveness, params.liveness);
    EXPECT_EQ(expected_params.detected_audio_track_count,
              params.detected_audio_track_count);
    EXPECT_EQ(expected_params.detected_video_track_count,
              params.detected_video_track_count);
    EXPECT_EQ(expected_params.detected_metadata_track_count,
              params.detected_metadata_track_count);
  }

  bool NewConfigF(std::unique_ptr<MediaTracks> tracks) {
    size_t audio_config_count = 0;
    size_t video_config_count = 0;
    CHECK(tracks.get());
    DVLOG(1) << "NewConfigF: got " << tracks->tracks().size() << " tracks";
    for (const auto& track : tracks->tracks()) {
      const auto& track_id = track->stream_id();
      if (track->type() == MediaTrack::Type::kAudio) {
        audio_track_id_ = track_id;
        audio_decoder_config_ = tracks->getAudioConfig(track_id);
        DVLOG(1) << "track_id=" << track_id << " audio config="
                 << (audio_decoder_config_.IsValidConfig()
                         ? audio_decoder_config_.AsHumanReadableString()
                         : "INVALID");
        audio_config_count++;
      } else if (track->type() == MediaTrack::Type::kVideo) {
        video_decoder_config_ = tracks->getVideoConfig(track_id);
        DVLOG(1) << "track_id=" << track_id << " video config="
                 << (video_decoder_config_.IsValidConfig()
                         ? video_decoder_config_.AsHumanReadableString()
                         : "INVALID");
        video_config_count++;
      }
    }
    EXPECT_EQ(tracks->GetAudioConfigs().size(), audio_config_count);
    EXPECT_EQ(tracks->GetVideoConfigs().size(), video_config_count);
    media_tracks_ = std::move(tracks);
    return true;
  }

  bool NewBuffersF(const StreamParser::BufferQueueMap& buffer_queue_map) {
    DecodeTimestamp lowest_end_dts = kNoDecodeTimestamp;
    for (const auto& [track_id, buffer_queue] : buffer_queue_map) {
      DVLOG(3) << "Buffers for track_id=" << track_id;
      DCHECK(!buffer_queue.empty());

      if (lowest_end_dts == kNoDecodeTimestamp ||
          lowest_end_dts > buffer_queue.back()->GetDecodeTimestamp())
        lowest_end_dts = buffer_queue.back()->GetDecodeTimestamp();

      for (const auto& buf : buffer_queue) {
        DVLOG(3) << "  track_id=" << buf->track_id() << ", size=" << buf->size()
                 << ", pts=" << buf->timestamp().InSecondsF()
                 << ", dts=" << buf->GetDecodeTimestamp().InSecondsF()
                 << ", dur=" << buf->duration().InSecondsF();
        // Ensure that track ids are properly assigned on all emitted buffers.
        EXPECT_EQ(track_id, buf->track_id());

        if (track_id == audio_track_id_ && capture_pcm_buffers_)
          pcm_buffers_.push_back(buf);

      }
    }

    EXPECT_NE(lowest_end_dts, kNoDecodeTimestamp);

    if (lower_bound_ != kNoDecodeTimestamp && lowest_end_dts < lower_bound_) {
      return false;
    }

    lower_bound_ = lowest_end_dts;
    return true;
  }

  void KeyNeededF(EmeInitDataType type, const std::vector<uint8_t>& init_data) {
    DVLOG(1) << "KeyNeededF: " << init_data.size();
    EXPECT_EQ(EmeInitDataType::CENC, type);
    EXPECT_FALSE(init_data.empty());
  }

  void NewSegmentF() {
    DVLOG(1) << "NewSegmentF";
    lower_bound_ = kNoDecodeTimestamp;
  }

  void EndOfSegmentF() {
    DVLOG(1) << "EndOfSegmentF()";
    lower_bound_ = kMaxDecodeTimestamp;
  }

  void InitializeParserWithInitParametersExpectations(
      StreamParser::InitParameters params) {
    parser_->Init(base::BindOnce(&ParcMP4StreamParserTest::InitF,
                                 base::Unretained(this), params),
                  base::BindRepeating(&ParcMP4StreamParserTest::NewConfigF,
                                      base::Unretained(this)),
                  base::BindRepeating(&ParcMP4StreamParserTest::NewBuffersF,
                                      base::Unretained(this)),
                  base::BindRepeating(&ParcMP4StreamParserTest::KeyNeededF,
                                      base::Unretained(this)),
                  base::BindRepeating(&ParcMP4StreamParserTest::NewSegmentF,
                                      base::Unretained(this)),
                  base::BindRepeating(&ParcMP4StreamParserTest::EndOfSegmentF,
                                      base::Unretained(this)),
                  &media_log_);
  }

  StreamParser::InitParameters GetDefaultInitParametersExpectations() {
    // Most unencrypted test mp4 files have zero duration and are treated as
    // live streams.
    StreamParser::InitParameters params(kInfiniteDuration);
    params.liveness = StreamLiveness::kLive;
    params.detected_audio_track_count = 1;
    params.detected_video_track_count = 1;
    return params;
  }

  void InitializeParser() {
    InitializeParserWithInitParametersExpectations(
        GetDefaultInitParametersExpectations());
  }

  // Note this is also similar to a StreamParserTestBase method.
  bool ParseMP4File(const std::string& filename, int append_bytes) {
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

TEST_F(ParcMP4StreamParserTest, ParcPCMInitNeedsSafariRules) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(testing::_)).Times(testing::AnyNumber());
  for (bool safari : {false, true}) {
    for (bool little_endian : {false, true}) {
    for (bool floating : {false, true}) {
      for (uint8_t bits : {16, 24, 32, 64}) {
        if (floating ? bits < 32 : bits == 64)
          continue;
        auto original = ReadTestDataFile("bear-mpeg2-aac-only_frag.mp4");
        std::vector<uint8_t> data(original->begin(), original->end());
        auto find_box = [&data](const std::string& name) {
          return std::search(data.begin(), data.end(), name.begin(), name.end())
                 - data.begin();
        };
        const size_t entry = find_box("mp4a");
        ASSERT_LT(entry + 4, data.size());
        const std::string name = floating ? "fpcm" : "ipcm";
        std::copy(name.begin(), name.end(), data.begin() + entry);
        const size_t config = find_box("esds") - 4;
        ASSERT_LT(config + 22, data.size());
        const uint32_t size = (data[config] << 24) | (data[config+1] << 16) |
                              (data[config+2] << 8) | data[config+3];
        ASSERT_GE(size, 22u);
        std::fill(data.begin() + config, data.begin() + config + size, 0);
        data[config+3] = 14;
        std::copy_n("pcmC", 4, data.begin() + config + 4);
        data[config+12] = little_endian;
        data[config+13] = bits;
        const uint32_t padding = size - 14;
        for (int i = 0; i < 4; ++i)
          data[config+14+i] = (padding >> (24-i*8)) & 255;
        std::copy_n("free", 4, data.begin() + config + 18);
        data.resize(find_box("moof") - 4);
        parser_ = std::make_unique<MP4StreamParser>(std::nullopt, false,
                                                   false, false, false);
        if (safari)
          parser_->ParcIgnoreDeclaredCodecs();
        auto params = GetDefaultInitParametersExpectations();
        params.detected_video_track_count = 0;
        lower_bound_ = kNoDecodeTimestamp;
        InitializeParserWithInitParametersExpectations(params);
        EXPECT_EQ(AppendAllDataThenParseInPieces(data, data.size()), safari);
        if (safari) {
          EXPECT_EQ(audio_decoder_config_.codec(), AudioCodec::kPCM);
          EXPECT_EQ(audio_decoder_config_.sample_format(),
                    floating ? kSampleFormatF32 : bits == 16 ? kSampleFormatS16
                        : bits == 24 ? kSampleFormatS24 : kSampleFormatS32);
          std::vector<uint8_t> fragment = {
              0,0,0,92,'m','o','o','f',0,0,0,16,'m','f','h','d',0,0,0,0,0,0,0,1,
              0,0,0,68,'t','r','a','f',0,0,0,16,'t','f','h','d',0,2,0,0,0,0,0,1,
              0,0,0,16,'t','f','d','t',0,0,0,0,0,0,0,0,
              0,0,0,28,'t','r','u','n',0,0,3,1,0,0,0,1,0,0,0,100,
              0,0,0,1,0,0,0,48,0,0,0,56,'m','d','a','t'};
          const size_t width = bits / 8;
          std::vector<uint8_t> sample(width, 0);
          if (floating) {
            sample[width - 1] = bits == 64 ? 0x3f : 0x3f;
            sample[width - 2] = bits == 64 ? 0xf0 : 0x80;
          } else {
            for (size_t i = 0; i < width; ++i)
              sample[i] = i + 1;
          }
          std::vector<uint8_t> expected;
          if (bits == 64)
            expected = {0, 0, 0x80, 0x3f};
          else
            expected = sample;
          if (!little_endian)
            std::reverse(sample.begin(), sample.end());
          for (size_t i = 0; i < 48 / width; ++i)
            fragment.insert(fragment.end(), sample.begin(), sample.end());
          pcm_buffers_.clear();
          capture_pcm_buffers_ = true;
          ASSERT_TRUE(AppendAllDataThenParseInPieces(fragment, fragment.size()));
          ASSERT_EQ(pcm_buffers_.size(), 1u);
          auto bytes = base::span(*pcm_buffers_[0]);
          ASSERT_EQ(bytes.size(), bits == 64 ? 24u : 48u);
          for (size_t i = 0; i < bytes.size(); ++i)
            EXPECT_EQ(bytes[i], expected[i % expected.size()]);
        }
      }
    }
    }
  }
}

// Parc: `file`'s init segment with its `entry` sample entry renamed
// `new_entry`, and the entry's `config` box replaced by `box` (none if empty)
// and a 'free' box filling the rest of it.
std::vector<uint8_t> ParcRewriteSampleEntry(const std::string& file,
                                            const std::string& entry,
                                            const std::string& new_entry,
                                            const std::string& config,
                                            const std::vector<uint8_t>& box) {
  scoped_refptr<DecoderBuffer> original = ReadTestDataFile(file);
  std::vector<uint8_t> data(original->begin(), original->end());
  auto find = [&data](const std::string& name, size_t start) {
    return static_cast<size_t>(
        std::search(data.begin() + start, data.end(), name.begin(),
                    name.end()) -
        data.begin());
  };
  const size_t entry_type = find(entry, find("stsd", 0));
  CHECK_LT(entry_type, data.size());
  std::ranges::copy(new_entry, data.begin() + entry_type);
  const size_t at = find(config, entry_type) - 4;
  CHECK_LT(at, data.size());
  const size_t size = uint32_t{data[at]} << 24 | uint32_t{data[at + 1]} << 16 |
                      uint32_t{data[at + 2]} << 8 | data[at + 3];
  CHECK_GE(size, box.size() + 8);
  std::ranges::copy(box, data.begin() + at);
  const size_t free_size = size - box.size();
  for (size_t i = 0; i < 4; ++i) {
    data[at + box.size() + i] =
        static_cast<uint8_t>(free_size >> (24 - 8 * i));
  }
  std::ranges::copy(std::string("free"), data.begin() + at + box.size() + 4);
  data.resize(find("moof", 0) - 4);
  return data;
}

// Parc: AVStreamDataParser takes 3GPP's AMR, and refuses an AMR sample entry
// without its AMRSpecificBox, as Safari's Media Source does.
TEST_F(ParcMP4StreamParserTest, ParcAmrNeedsSafariRulesAndDamr) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(testing::_))
      .Times(testing::AnyNumber());
  // vendor, decoder version, mode set, mode change period, frames per sample.
  const std::vector<uint8_t> kDamr = {0,   0,   0,    17,   'd', 'a',
                                      'm', 'r', 'F',  'F',  'M', 'P',
                                      0,   0x81, 0xff, 0x00, 1};
  for (const bool wideband : {false, true}) {
    for (const bool safari : {false, true}) {
      for (const bool damr : {false, true}) {
        SCOPED_TRACE(testing::Message() << "wideband " << wideband
                                        << " safari " << safari << " damr "
                                        << damr);
        const std::vector<uint8_t> init = ParcRewriteSampleEntry(
            "bear-mpeg2-aac-only_frag.mp4", "mp4a", wideband ? "sawb" : "samr",
            "esds", damr ? kDamr : std::vector<uint8_t>());
        parser_ = std::make_unique<MP4StreamParser>(std::nullopt, false, false,
                                                    false, false);
        if (safari) {
          parser_->ParcIgnoreDeclaredCodecs();
        }
        auto params = GetDefaultInitParametersExpectations();
        params.detected_video_track_count = 0;
        lower_bound_ = kNoDecodeTimestamp;
        InitializeParserWithInitParametersExpectations(params);
        ASSERT_EQ(AppendAllDataThenParseInPieces(init, init.size()),
                  safari && damr);
        if (!safari || !damr) {
          continue;
        }
        // The entry's rate and channel fields don't count.
        EXPECT_EQ(audio_decoder_config_.codec(),
                  wideband ? AudioCodec::kAMR_WB : AudioCodec::kAMR_NB);
        EXPECT_EQ(audio_decoder_config_.samples_per_second(),
                  wideband ? 16000 : 8000);
        EXPECT_EQ(audio_decoder_config_.channel_layout(), CHANNEL_LAYOUT_MONO);

        // One sample of two frames, a 12.2 kbit/s (AMR-WB 23.85) frame and a
        // NO_DATA one, passes as it is.
        std::vector<uint8_t> sample(wideband ? 61 : 32, 0x5a);
        sample[0] = wideband ? 0x44 : 0x3c;
        sample.push_back(0x7c);
        const auto sample_size = static_cast<uint8_t>(sample.size());
        std::vector<uint8_t> fragment = {
            0, 0, 0, 92, 'm', 'o', 'o', 'f', 0, 0, 0, 16, 'm', 'f', 'h', 'd',
            0, 0, 0, 0, 0, 0, 0, 1,
            0, 0, 0, 68, 't', 'r', 'a', 'f', 0, 0, 0, 16, 't', 'f', 'h', 'd',
            0, 2, 0, 0, 0, 0, 0, 1,
            0, 0, 0, 16, 't', 'f', 'd', 't', 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 28, 't', 'r', 'u', 'n', 0, 0, 3, 1, 0, 0, 0, 1,
            0, 0, 0, 100, 0, 0, 0, 1, 0, 0, 0, sample_size,
            0, 0, 0, static_cast<uint8_t>(8 + sample_size), 'm', 'd', 'a', 't'};
        fragment.insert(fragment.end(), sample.begin(), sample.end());
        pcm_buffers_.clear();
        capture_pcm_buffers_ = true;
        ASSERT_TRUE(AppendAllDataThenParseInPieces(fragment, fragment.size()));
        ASSERT_EQ(pcm_buffers_.size(), 1u);
        EXPECT_TRUE(std::ranges::equal(base::span(*pcm_buffers_[0]), sample));
      }
    }
  }
}

// Parc: AVStreamDataParser takes 3GPP's H.263; without its H263SpecificBox the
// track can't be decoded, which fails the init segment here.
TEST_F(ParcMP4StreamParserTest, ParcH263NeedsSafariRulesAndD263) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(testing::_))
      .Times(testing::AnyNumber());
  // vendor, decoder version, level 45, profile 0.
  const std::vector<uint8_t> kD263 = {0,   0,   0,   15,  'd', '2', '6', '3',
                                      'F', 'F', 'M', 'P', 0,   45,  0};
  for (const bool safari : {false, true}) {
    for (const bool d263 : {false, true}) {
      SCOPED_TRACE(testing::Message() << "safari " << safari << " d263 "
                                      << d263);
      const std::vector<uint8_t> init = ParcRewriteSampleEntry(
          "bear-1280x720-av_frag.mp4", "avc1", "s263", "avcC",
          d263 ? kD263 : std::vector<uint8_t>());
      parser_ = std::make_unique<MP4StreamParser>(std::nullopt, false, false,
                                                  false, false);
      if (safari) {
        parser_->ParcIgnoreDeclaredCodecs();
      }
      lower_bound_ = kNoDecodeTimestamp;
      InitializeParser();
      ASSERT_EQ(AppendAllDataThenParseInPieces(init, init.size()),
                safari && d263);
      if (safari && d263) {
        EXPECT_EQ(video_decoder_config_.codec(), VideoCodec::kH263);
        EXPECT_EQ(video_decoder_config_.profile(), VIDEO_CODEC_PROFILE_UNKNOWN);
        EXPECT_EQ(video_decoder_config_.level(), 45u);
        EXPECT_EQ(video_decoder_config_.coded_size(), gfx::Size(1280, 720));
        EXPECT_EQ(audio_decoder_config_.codec(), AudioCodec::kAAC);
      }
    }
  }
}

// Parc: a type naming only video (codecs="avc1...") fails an init segment
// that also has AAC, unless the parser ignores the declared codecs, as on a
// document presenting Safari's identity
// (SourceBufferState::ParcSetSafariInitSegmentRules()).
TEST_F(ParcMP4StreamParserTest, UndeclaredAudioObjectTypeRejected) {
  InSequence s;
  parser_.reset(new MP4StreamParser(base::flat_set<int>(), false, false,
                                    false, false));
  InitializeParser();
  scoped_refptr<DecoderBuffer> buffer =
      ReadTestDataFile("bear-1280x720-av_frag.mp4");
  EXPECT_MEDIA_LOG(
      ErrorLog("does not match what is specified in the mimetype"));
  EXPECT_FALSE(AppendAllDataThenParseInPieces(*buffer, 512));
}

TEST_F(ParcMP4StreamParserTest, ParcIgnoresDeclaredAudioObjectTypes) {
  parser_.reset(new MP4StreamParser(base::flat_set<int>(), false, false,
                                    false, false));
  parser_->ParcIgnoreDeclaredCodecs();
  InitializeParser();
  ParseMP4File("bear-1280x720-av_frag.mp4", 512);
  EXPECT_EQ(audio_decoder_config_.codec(), AudioCodec::kAAC);
}

#if BUILDFLAG(ENABLE_PLATFORM_HEVC)
// Parc: the profile 8.1 stream, its hvc1 sample entry now configured as
// profile 7 with an HDR10 base layer (compatibility id 6, which Chromium
// doesn't count as backward compatible) in a dvcC box.
scoped_refptr<DecoderBuffer> ReadParcDVProfile7InHvc1() {
  scoped_refptr<DecoderBuffer> file =
      ReadTestDataFile("glass-blowing2-dolby-vision-profile-8-1-frag.mp4");
  std::vector<uint8_t> data(file->begin(), file->end());
  constexpr std::array<uint8_t, 4> kDvvC = {'d', 'v', 'v', 'C'};
  auto box = std::ranges::search(data, kDvvC).begin();
  CHECK(box != data.end());
  box[2] = 'c';
  // dv_profile 7, dv_level 5, RPU and base layer present; compatibility 6.
  box[6] = 0x0e;
  box[7] = 0x2d;
  box[8] = 0x60 | (box[8] & 0x0f);
  return DecoderBuffer::CopyFrom(data);
}

#endif  // BUILDFLAG(ENABLE_PLATFORM_HEVC)

class ParcMP4StreamParserDVTest : public ParcMP4StreamParserTest {
 protected:
  void ParseDolbyVision(scoped_refptr<DecoderBuffer> buffer,
                        bool parc_safari,
                        bool has_dv = true,
                        bool live = false) {
    parser_.reset(new MP4StreamParser(base::flat_set<int>(), false, false,
                                      false, has_dv));
    if (parc_safari) {
      parser_->ParcIgnoreDeclaredCodecs();
    }
    auto params = GetDefaultInitParametersExpectations();
    if (!live) {
      params.duration = base::Microseconds(2000000);
      params.liveness = StreamLiveness::kRecorded;
    }
    params.detected_audio_track_count = 0;
    InitializeParserWithInitParametersExpectations(params);
    EXPECT_TRUE(AppendAllDataThenParseInPieces(*buffer, 512));
  }
};

#if BUILDFLAG(ENABLE_PLATFORM_HEVC)

TEST_F(ParcMP4StreamParserDVTest, Profile7StaysDolbyVisionOutsideSafariRules) {
  ParseDolbyVision(ReadParcDVProfile7InHvc1(), /*parc_safari=*/false);
  EXPECT_EQ(VideoCodec::kDolbyVision, video_decoder_config_.codec());
  EXPECT_EQ(DOLBYVISION_PROFILE7, video_decoder_config_.profile());
}

// AVFoundation can't decode profile 7; its HEVC base layer plays.
TEST_F(ParcMP4StreamParserDVTest, SafariRulesPlayProfile7BaseLayer) {
  ParseDolbyVision(ReadParcDVProfile7InHvc1(), /*parc_safari=*/true);
  EXPECT_EQ(VideoCodec::kHEVC, video_decoder_config_.codec());
  EXPECT_EQ(HEVCPROFILE_MAIN10, video_decoder_config_.profile());
}

TEST_F(ParcMP4StreamParserDVTest, SafariRulesKeepProfile8AsDolbyVision) {
  ParseDolbyVision(
      ReadTestDataFile("glass-blowing2-dolby-vision-profile-8-1-frag.mp4"),
      /*parc_safari=*/true);
  EXPECT_EQ(VideoCodec::kDolbyVision, video_decoder_config_.codec());
  EXPECT_EQ(DOLBYVISION_PROFILE8, video_decoder_config_.profile());
}

// Safari's renderer decodes the hvc1 entry's dvvC profile 8.1 as Dolby Vision
// even when the codecs named HEVC.
TEST_F(ParcMP4StreamParserDVTest, SafariRulesPlayProfile8InHvc1AsDolbyVision) {
  ParseDolbyVision(
      ReadTestDataFile("glass-blowing2-dolby-vision-profile-8-1-frag.mp4"),
      /*parc_safari=*/true, /*has_dv=*/false);
  EXPECT_EQ(VideoCodec::kDolbyVision, video_decoder_config_.codec());
  EXPECT_EQ(DOLBYVISION_PROFILE8, video_decoder_config_.profile());
  EXPECT_EQ(VideoColorSpace::TransferID::SMPTEST2084,
            video_decoder_config_.color_space_info().transfer());
}

TEST_F(ParcMP4StreamParserDVTest, OnlySafariMarksProfile8SDRBaseLayer) {
  for (bool safari : {false, true}) {
    auto buffer = ReadTestDataFile("glass-blowing2-dolby-vision-profile-8-1-frag.mp4");
    auto bytes = buffer->writable_span();
    const std::array<uint8_t, 4> box = {'d', 'v', 'v', 'C'};
    auto it = std::ranges::search(bytes, box).begin();
    ASSERT_NE(it, bytes.end());
    *(it + 8) = 0x20;  // dv_bl_signal_compatibility_id = 2 (SDR).
    ParseDolbyVision(buffer, safari);
    EXPECT_EQ(safari, video_decoder_config_.parc_dolby_vision_sdr());
    EXPECT_EQ(VideoColorSpace::REC709(), video_decoder_config_.color_space_info());
  }
}

TEST_F(ParcMP4StreamParserDVTest, Profile8InHvc1StaysHevcOutsideSafariRules) {
  ParseDolbyVision(
      ReadTestDataFile("glass-blowing2-dolby-vision-profile-8-1-frag.mp4"),
      /*parc_safari=*/false, /*has_dv=*/false);
  EXPECT_EQ(VideoCodec::kHEVC, video_decoder_config_.codec());
}
#endif  // BUILDFLAG(ENABLE_PLATFORM_HEVC)

#if BUILDFLAG(ENABLE_AV1_DECODER) && BUILDFLAG(USE_PROPRIETARY_CODECS)
// Parc: the 10-bit AV1 stream with its av01 sample entry made dav1 and a dvvC
// box (profile 10, level 5, RPU and base layer) after it, as Dolby Vision
// profile 10 streams carry it.
scoped_refptr<DecoderBuffer> ReadParcDVProfile10InDav1(
    uint8_t compatibility_id) {
  scoped_refptr<DecoderBuffer> file =
      ReadTestDataFile("bear-av1-320x180-10bit.mp4");
  std::vector<uint8_t> data(file->begin(), file->end());
  constexpr uint8_t kDvvCSize = 32;
  std::vector<uint8_t> dvvc(kDvvCSize, 0);
  dvvc[3] = kDvvCSize;
  std::ranges::copy(std::string_view("dvvC"), dvvc.begin() + 4);
  dvvc[8] = 1;
  dvvc[10] = 0x14;
  dvvc[11] = 0x2d;
  dvvc[12] = static_cast<uint8_t>(compatibility_id << 4);
  // Each box from moov to the sample entry grows by the new box.
  size_t entry_end = 0;
  size_t from = 0;
  for (std::string_view type :
       {"moov", "trak", "mdia", "minf", "stbl", "stsd", "av01"}) {
    auto it = std::ranges::search(data.begin() + from, data.end(), type.begin(),
                                  type.end())
                  .begin();
    CHECK(it != data.end());
    const size_t pos = it - data.begin() - 4;
    uint32_t size = (data[pos] << 24) | (data[pos + 1] << 16) |
                    (data[pos + 2] << 8) | data[pos + 3];
    entry_end = pos + size;
    size += kDvvCSize;
    for (size_t i = 0; i < 4; ++i) {
      data[pos + i] = static_cast<uint8_t>(size >> (24 - 8 * i));
    }
    from = pos + 8;
  }
  std::ranges::copy(std::string_view("dav1"), data.begin() + from - 4);
  data.insert(data.begin() + entry_end, dvvc.begin(), dvvc.end());
  return DecoderBuffer::CopyFrom(data);
}

// Safari decodes a dav1 sample entry as Dolby Vision, whatever the codecs
// named, with the transfer function its compatibility ID gives.
TEST_F(ParcMP4StreamParserDVTest, SafariRulesPlayProfile10InDav1) {
  ParseDolbyVision(ReadParcDVProfile10InDav1(/*compatibility_id=*/1),
                   /*parc_safari=*/true, /*has_dv=*/false, /*live=*/true);
  EXPECT_EQ(VideoCodec::kDolbyVision, video_decoder_config_.codec());
  EXPECT_EQ(DOLBYVISION_PROFILE10, video_decoder_config_.profile());
  EXPECT_EQ(VideoColorSpace::TransferID::SMPTEST2084,
            video_decoder_config_.color_space_info().transfer());
}

TEST_F(ParcMP4StreamParserDVTest, SafariRulesKeepProfile10HlgCompatibility) {
  ParseDolbyVision(ReadParcDVProfile10InDav1(/*compatibility_id=*/4),
                   /*parc_safari=*/true, /*has_dv=*/true, /*live=*/true);
  EXPECT_EQ(VideoCodec::kDolbyVision, video_decoder_config_.codec());
  EXPECT_EQ(DOLBYVISION_PROFILE10, video_decoder_config_.profile());
  EXPECT_EQ(VideoColorSpace::TransferID::ARIB_STD_B67,
            video_decoder_config_.color_space_info().transfer());
}

TEST_F(ParcMP4StreamParserDVTest, OnlySafariMarksProfile10SDRBaseLayer) {
  for (bool safari : {false, true}) {
    ParseDolbyVision(ReadParcDVProfile10InDav1(/*compatibility_id=*/2),
                     safari, /*has_dv=*/false, /*live=*/true);
    EXPECT_EQ(safari, video_decoder_config_.parc_dolby_vision_sdr());
    if (safari) {
      EXPECT_EQ(VideoColorSpace::REC709(), video_decoder_config_.color_space_info());
    }
  }
}

TEST_F(ParcMP4StreamParserDVTest, Profile10InDav1StaysAv1OutsideSafariRules) {
  ParseDolbyVision(ReadParcDVProfile10InDav1(/*compatibility_id=*/1),
                   /*parc_safari=*/false, /*has_dv=*/false, /*live=*/true);
  EXPECT_EQ(VideoCodec::kAV1, video_decoder_config_.codec());
}
#endif  // BUILDFLAG(ENABLE_AV1_DECODER) && BUILDFLAG(USE_PROPRIETARY_CODECS)

#if (BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || BUILDFLAG(ENABLE_IAMF_TOOLS)) && \
    BUILDFLAG(USE_PROPRIETARY_CODECS)
TEST_F(ParcMP4StreamParserTest, IamfTrackWithDeclaredCodec) {
  parser_.reset(new MP4StreamParser(std::nullopt, false, false,
                                    /*has_iamf=*/true, false));
  InitializeParser();
  ParseMP4File("iamf_alternating_sine_waves_stereo.mp4", 512);
  EXPECT_EQ(AudioCodec::kIAMF, audio_decoder_config_.codec());
  EXPECT_EQ(VideoCodec::kH264, video_decoder_config_.codec());
}

// Parc: under Safari's init segment rules an IAMF track is left out, as
// AVStreamDataParser leaves it out of the init segment Safari's SourceBuffer
// gets; the video track plays on.
TEST_F(ParcMP4StreamParserTest, ParcSafariRulesLeaveOutIamfTrack) {
  parser_.reset(new MP4StreamParser(std::nullopt, false, false,
                                    /*has_iamf=*/true, false));
  parser_->ParcIgnoreDeclaredCodecs();
  auto params = GetDefaultInitParametersExpectations();
  params.detected_audio_track_count = 0;
  InitializeParserWithInitParametersExpectations(params);
  ParseMP4File("iamf_alternating_sine_waves_stereo.mp4", 512);
  ASSERT_TRUE(media_tracks_);
  EXPECT_EQ(media_tracks_->tracks().size(), 1u);
  EXPECT_FALSE(audio_decoder_config_.IsValidConfig());
  EXPECT_EQ(VideoCodec::kH264, video_decoder_config_.codec());
}
#endif  // (BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || ...

}  // namespace mp4
}  // namespace media

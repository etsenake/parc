// Copyright 2026 Parc contributors.

#include "media/filters/source_buffer_stream.h"

#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/numerics/safe_conversions.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/test/scoped_feature_list.h"
#include "base/time/time.h"
#include "media/base/data_buffer.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_log.h"
#include "media/base/media_switches.h"
#include "media/base/media_util.h"
#include "media/base/mock_media_log.h"
#include "media/base/test_helpers.h"
#include "media/base/timestamp_constants.h"
#include "media/filters/parc_source_buffer_stream_state.h"
#include "media/filters/source_buffer_range.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::testing::InSequence;
using ::testing::StrictMock;

namespace {

enum class TimeGranularity { kMicrosecond, kMillisecond };

static constexpr int kSampleRate = 3000;

}

namespace media {

typedef StreamParser::BufferQueue BufferQueue;

static const int kDefaultFramesPerSecond = 30;
static const int kDefaultKeyframesPerSecond = 6;
static std::array<const uint8_t, 1> kDataA = {0x11};

MATCHER_P(ContainsTrackBufferExhaustionSkipLog, skip_milliseconds, "") {
  return arg.contains(
      "Media append that overlapped current playback "
      "position may cause time gap in playing VIDEO stream "
      "because the next keyframe is " +
      base::NumberToString(skip_milliseconds) +
      "ms beyond last overlapped frame. Media may "
      "appear temporarily frozen.");
}

#define EXPECT_STATUS_FOR_STREAM_OP(status_suffix, operation) \
  { EXPECT_EQ(SourceBufferStreamStatus::status_suffix, stream_->operation); }

class ParcSourceBufferStreamTest : public testing::Test {
 public:
  ParcSourceBufferStreamTest(const ParcSourceBufferStreamTest&) = delete;
  ParcSourceBufferStreamTest& operator=(const ParcSourceBufferStreamTest&) = delete;

 protected:
  ParcSourceBufferStreamTest() {
    video_config_ = TestVideoConfig::Normal();
    SetStreamInfo(kDefaultFramesPerSecond, kDefaultKeyframesPerSecond);
    ResetStream<>(video_config_);
  }

  template <typename ConfigT>
  void ResetStream(const ConfigT& config) {
    stream_ = std::make_unique<SourceBufferStream>(config, &media_log_);
  }

  void SetStreamInfo(int frames_per_second, int keyframes_per_second) {
    frames_per_second_ = frames_per_second;
    keyframes_per_second_ = keyframes_per_second;
    frame_duration_ = ConvertToFrameDuration(frames_per_second);
  }

  void SetAudioStream() {
    video_config_ = TestVideoConfig::Invalid();
    audio_config_.Initialize(AudioCodec::kVorbis, kSampleFormatPlanarF32,
                             ChannelLayoutConfig::Stereo(), kSampleRate,
                             EmptyExtraData(), EncryptionScheme::kUnencrypted,
                             base::TimeDelta(), 0);
    ResetStream<>(audio_config_);

    SetStreamInfo(500, 500);
  }

  void NewCodedFrameGroupAppend(int starting_position, int number_of_buffers) {
    AppendBuffers(starting_position, number_of_buffers, true, base::TimeDelta(),
                  kDataA);
  }

  void NewCodedFrameGroupAppend(int starting_position,
                                int number_of_buffers,
                                base::span<const uint8_t> data) {
    AppendBuffers(starting_position, number_of_buffers, true, base::TimeDelta(),
                  data);
  }

  void NewCodedFrameGroupAppend_OffsetFirstBuffer(
      int starting_position,
      int number_of_buffers,
      base::TimeDelta first_buffer_offset) {
    AppendBuffers(starting_position, number_of_buffers, true,
                  first_buffer_offset, kDataA);
  }

  void AppendBuffers(int starting_position, int number_of_buffers) {
    AppendBuffers(starting_position, number_of_buffers, false,
                  base::TimeDelta(), kDataA);
  }

  void AppendBuffers(int starting_position,
                     int number_of_buffers,
                     base::span<const uint8_t> data) {
    AppendBuffers(starting_position, number_of_buffers, false,
                  base::TimeDelta(), data);
  }

  void NewCodedFrameGroupAppend(const std::string& buffers_to_append) {
    AppendBuffers(buffers_to_append, true, kNoTimestamp, false);
  }

  void NewCodedFrameGroupAppend(base::TimeDelta start_timestamp,
                                const std::string& buffers_to_append) {
    AppendBuffers(buffers_to_append, true, start_timestamp, false);
  }

  void AppendBuffers(const std::string& buffers_to_append) {
    AppendBuffers(buffers_to_append, false, kNoTimestamp, false);
  }

  void NewCodedFrameGroupAppendOneByOne(const std::string& buffers_to_append) {
    AppendBuffers(buffers_to_append, true, kNoTimestamp, true);
  }

  void AppendBuffersOneByOne(const std::string& buffers_to_append) {
    AppendBuffers(buffers_to_append, false, kNoTimestamp, true);
  }

  void Seek(int position) { stream_->Seek(position * frame_duration_); }

  void SeekToTimestampMs(int64_t timestamp_ms) {
    stream_->Seek(base::Milliseconds(timestamp_ms));
  }

  bool GarbageCollect(base::TimeDelta media_time, int new_data_size) {
    return stream_->GarbageCollectIfNeeded(media_time, new_data_size);
  }

  bool GarbageCollectWithPlaybackAtBuffer(int position, int new_data_buffers) {
    return GarbageCollect(position * frame_duration_,
                          new_data_buffers * kDataA.size());
  }

  void RemoveInMs(int start, int end, int duration) {
    Remove(base::Milliseconds(start), base::Milliseconds(end),
           base::Milliseconds(duration));
  }

  void Remove(base::TimeDelta start, base::TimeDelta end,
              base::TimeDelta duration) {
    stream_->Remove(start, end, duration);
  }

  void SignalStartOfCodedFrameGroup(base::TimeDelta start_timestamp) {
    stream_->OnStartOfCodedFrameGroup(start_timestamp);
  }

  int GetRemovalRangeInMs(int start, int end, int bytes_to_free,
                          int* removal_end) {
    base::TimeDelta removal_end_timestamp = base::Milliseconds(*removal_end);
    int bytes_removed = stream_->GetRemovalRange(
        base::Milliseconds(start), base::Milliseconds(end), bytes_to_free,
        &removal_end_timestamp);
    *removal_end = removal_end_timestamp.InMilliseconds();
    return bytes_removed;
  }

  void CheckExpectedRanges(const std::string& expected) {
    Ranges<base::TimeDelta> r = stream_->GetBufferedTime();

    std::stringstream ss;
    ss << "{ ";
    for (size_t i = 0; i < r.size(); ++i) {
      int64_t start = r.start(i).IntDiv(frame_duration_);
      int64_t end = r.end(i).IntDiv(frame_duration_) - 1;
      ss << "[" << start << "," << end << ") ";
    }
    ss << "}";
    EXPECT_EQ(expected, ss.str());
  }

  void CheckExpectedRangesByTimestamp(
      const std::string& expected,
      TimeGranularity granularity = TimeGranularity::kMillisecond) {
    Ranges<base::TimeDelta> r = stream_->GetBufferedTime();

    std::stringstream ss;
    ss << "{ ";
    for (size_t i = 0; i < r.size(); ++i) {
      auto conversion = (granularity == TimeGranularity::kMillisecond)
                            ? &base::TimeDelta::InMilliseconds
                            : &base::TimeDelta::InMicroseconds;
      int64_t start = (r.start(i).*conversion)();
      int64_t end = (r.end(i).*conversion)();
      ss << "[" << start << "," << end << ") ";
    }
    ss << "}";
    EXPECT_EQ(expected, ss.str());
  }

  void CheckExpectedRangeEndTimes(const std::string& expected) {
    std::stringstream ss;
    ss << "{ ";
    for (const auto& r : stream_->ranges_) {
      base::TimeDelta highest_pts = r->GetEndTimestamp();
      base::TimeDelta end_time = r->GetBufferedEndTimestamp();
      ss << "<" << highest_pts.InMilliseconds() << ","
         << end_time.InMilliseconds() << "> ";
    }
    ss << "}";
    EXPECT_EQ(expected, ss.str());
  }

  void CheckIsNextInPTSSequenceWithFirstRange(int64_t pts_in_ms,
                                              bool expectation) {
    ASSERT_GE(stream_->ranges_.size(), 1u);
    const auto& range_ptr = *(stream_->ranges_.begin());
    EXPECT_EQ(expectation, range_ptr->IsNextInPresentationSequence(
                               base::Milliseconds(pts_in_ms)));
  }

  void CheckExpectedBuffers(
      int starting_position, int ending_position) {
    CheckExpectedBuffers(starting_position, ending_position, false,
                         std::nullopt);
  }

  void CheckExpectedBuffers(
      int starting_position, int ending_position, bool expect_keyframe) {
    CheckExpectedBuffers(starting_position, ending_position, expect_keyframe,
                         std::nullopt);
  }

  void CheckExpectedBuffers(int starting_position,
                            int ending_position,
                            base::span<const uint8_t> data) {
    CheckExpectedBuffers(starting_position, ending_position, false, data);
  }

  void CheckExpectedBuffers(int starting_position,
                            int ending_position,
                            base::span<const uint8_t> data,
                            bool expect_keyframe) {
    CheckExpectedBuffers(starting_position, ending_position, expect_keyframe,
                         data);
  }

  void CheckExpectedBuffers(
      int starting_position,
      int ending_position,
      bool expect_keyframe,
      std::optional<base::span<const uint8_t>> expected_data) {
    int current_position = starting_position;
    for (; current_position <= ending_position; current_position++) {
      scoped_refptr<StreamParserBuffer> buffer;
      SourceBufferStreamStatus status = stream_->GetNextBuffer(&buffer);
      EXPECT_NE(status, SourceBufferStreamStatus::kConfigChange);
      if (status != SourceBufferStreamStatus::kSuccess)
        break;

      if (expect_keyframe && current_position == starting_position)
        EXPECT_TRUE(buffer->is_key_frame());

      if (expected_data) {
        EXPECT_EQ(base::span(*expected_data), base::span(*buffer));
      }

      EXPECT_EQ(
          base::ClampFloor(buffer->GetDecodeTimestamp() / frame_duration_),
          current_position);
    }

    EXPECT_EQ(ending_position + 1, current_position);
  }

  void CheckExpectedBuffers(
      const std::string& expected,
      TimeGranularity granularity = TimeGranularity::kMillisecond) {
    std::vector<std::string> timestamps = base::SplitString(
        expected, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL);
    std::stringstream ss;
    const SourceBufferStreamType type = stream_->GetType();
    for (size_t i = 0; i < timestamps.size(); i++) {
      scoped_refptr<StreamParserBuffer> buffer;
      SourceBufferStreamStatus status = stream_->GetNextBuffer(&buffer);

      if (i > 0)
        ss << " ";

      if (status == SourceBufferStreamStatus::kConfigChange) {
        switch (type) {
          case SourceBufferStreamType::kVideo:
            stream_->GetCurrentVideoDecoderConfig();
            break;
          case SourceBufferStreamType::kAudio:
            stream_->GetCurrentAudioDecoderConfig();
            break;
        }

        EXPECT_EQ("C", timestamps[i]);
        ss << "C";
        continue;
      }

      EXPECT_EQ(SourceBufferStreamStatus::kSuccess, status);
      if (status != SourceBufferStreamStatus::kSuccess)
        break;

      if (granularity == TimeGranularity::kMillisecond)
        ss << buffer->timestamp().InMilliseconds();
      else
        ss << buffer->timestamp().InMicroseconds();

      if (buffer->GetDecodeTimestamp() !=
          DecodeTimestamp::FromPresentationTime(buffer->timestamp())) {
        if (granularity == TimeGranularity::kMillisecond)
          ss << "|" << buffer->GetDecodeTimestamp().InMilliseconds();
        else
          ss << "|" << buffer->GetDecodeTimestamp().InMicroseconds();
      }

      if (timestamps[i].contains('D')) {
        ss << "D" << buffer->duration().InMilliseconds();
      }

      if (timestamps[i].contains('E') && buffer->is_duration_estimated()) {
        ss << "E";
      }

      if (timestamps[i].ends_with("P")) {
        ASSERT_TRUE(buffer->is_key_frame());
        scoped_refptr<StreamParserBuffer> preroll_buffer;
        preroll_buffer.swap(buffer);

        EXPECT_STATUS_FOR_STREAM_OP(kSuccess, GetNextBuffer(&buffer));
        ASSERT_EQ(buffer->GetConfigId(), preroll_buffer->GetConfigId());
        ASSERT_EQ(buffer->track_id(), preroll_buffer->track_id());
        ASSERT_EQ(buffer->timestamp(), preroll_buffer->timestamp());
        ASSERT_EQ(buffer->GetDecodeTimestamp(),
                  preroll_buffer->GetDecodeTimestamp());
        auto preroll_discard = preroll_buffer->discard_padding();
        ASSERT_TRUE(preroll_discard.has_value());
        ASSERT_EQ(kInfiniteDuration, preroll_discard->first);
        ASSERT_EQ(base::TimeDelta(), preroll_discard->second);
        ASSERT_TRUE(buffer->is_key_frame());

        ss << "P";
      } else if (buffer->is_key_frame()) {
        ss << "K";
      }
    }
    EXPECT_EQ(expected, ss.str());
  }

  void CheckNoNextBuffer() {
    scoped_refptr<StreamParserBuffer> buffer;
    EXPECT_STATUS_FOR_STREAM_OP(kNeedBuffer, GetNextBuffer(&buffer));
  }

  void CheckAudioConfig(const AudioDecoderConfig& config) {
    const AudioDecoderConfig& actual = stream_->GetCurrentAudioDecoderConfig();
    EXPECT_TRUE(actual.Matches(config))
        << "Expected: " << config.AsHumanReadableString()
        << "\nActual: " << actual.AsHumanReadableString();
  }

  int GetMemoryUsagePerBuffer() const {
    return kDataA.size() + sizeof(StreamParserBuffer);
  }

  base::TimeDelta frame_duration() const { return frame_duration_; }

  StrictMock<MockMediaLog> media_log_;
  std::unique_ptr<SourceBufferStream> stream_;

  VideoDecoderConfig video_config_;
  AudioDecoderConfig audio_config_;

 private:
  DemuxerStream::Type GetStreamType() {
    switch (stream_->GetType()) {
      case SourceBufferStreamType::kAudio:
        return DemuxerStream::AUDIO;
      case SourceBufferStreamType::kVideo:
        return DemuxerStream::VIDEO;
    }
    NOTREACHED();
  }

  base::TimeDelta ConvertToFrameDuration(int frames_per_second) {
    return base::Seconds(1) / frames_per_second;
  }

  void AppendBuffers(int starting_position,
                     int number_of_buffers,
                     bool begin_coded_frame_group,
                     base::TimeDelta first_buffer_offset,
                     base::span<const uint8_t> data) {
    if (begin_coded_frame_group) {
      stream_->OnStartOfCodedFrameGroup(starting_position * frame_duration_);
    }

    int keyframe_interval = frames_per_second_ / keyframes_per_second_;

    BufferQueue queue;
    for (int i = 0; i < number_of_buffers; i++) {
      int position = starting_position + i;
      bool is_keyframe = position % keyframe_interval == 0;
      scoped_refptr<StreamParserBuffer> buffer =
          StreamParserBuffer::CopyFrom(data, is_keyframe, GetStreamType(), 0);
      base::TimeDelta timestamp = frame_duration_ * position;

      if (i == 0)
        timestamp += first_buffer_offset;
      buffer->SetDecodeTimestamp(
          DecodeTimestamp::FromPresentationTime(timestamp));

      base::TimeDelta presentation_timestamp;
      if (is_keyframe) {
        presentation_timestamp = timestamp;
      } else if ((position - 1) % keyframe_interval == 0) {
        presentation_timestamp =
            (timestamp + frame_duration_ * (keyframe_interval - 2));
      } else {
        presentation_timestamp = timestamp - frame_duration_;
      }
      buffer->set_timestamp(presentation_timestamp);
      buffer->set_duration(frame_duration_);

      queue.push_back(buffer);
    }
    if (!queue.empty())
      stream_->Append(queue);
  }

  void UpdateLastBufferDuration(DecodeTimestamp current_dts,
                                BufferQueue* buffers) {
    if (buffers->empty() || buffers->back()->duration().is_positive())
      return;

    DecodeTimestamp last_dts = buffers->back()->GetDecodeTimestamp();
    DCHECK(current_dts >= last_dts);
    buffers->back()->set_duration(current_dts - last_dts);
  }

  BufferQueue StringToBufferQueue(const std::string& buffers_to_append) {
    std::vector<std::string> timestamps = base::SplitString(
        buffers_to_append, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL);

    CHECK_GT(timestamps.size(), 0u);

    BufferQueue buffers;
    for (size_t i = 0; i < timestamps.size(); i++) {
      bool is_keyframe = false;
      bool has_preroll = false;
      bool is_duration_estimated = false;

      if (timestamps[i].ends_with("K")) {
        is_keyframe = true;
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }
      if (timestamps[i].ends_with("P")) {
        is_keyframe = true;
        has_preroll = true;
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }

      if (timestamps[i].ends_with("E")) {
        is_duration_estimated = true;
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }

      int duration_in_us = -1;
      size_t duration_pos = timestamps[i].find('D');
      if (duration_pos != std::string::npos) {
        bool is_duration_us = false;
        if (timestamps[i].ends_with("u")) {
          is_duration_us = true;
          timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
        }
        CHECK(base::StringToInt(timestamps[i].substr(duration_pos + 1),
                                &duration_in_us));
        if (!is_duration_us)
          duration_in_us *= base::Time::kMicrosecondsPerMillisecond;
        timestamps[i] = timestamps[i].substr(0, duration_pos);
      }

      std::vector<std::string> buffer_timestamp_strings = base::SplitString(
          timestamps[i], "|", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL);

      if (buffer_timestamp_strings.size() == 1)
        buffer_timestamp_strings.push_back(buffer_timestamp_strings[0]);

      CHECK_EQ(2u, buffer_timestamp_strings.size());

      std::vector<base::TimeDelta> buffer_timestamps;

      for (size_t j = 0; j < 2; ++j) {
        int us = 0;
        bool is_us = false;

        if (buffer_timestamp_strings[j].ends_with("u")) {
          is_us = true;
          buffer_timestamp_strings[j] = buffer_timestamp_strings[j].substr(
              0, buffer_timestamp_strings[j].length() - 1);
        }
        CHECK(base::StringToInt(buffer_timestamp_strings[j], &us));
        if (!is_us)
          us *= base::Time::kMicrosecondsPerMillisecond;

        buffer_timestamps.push_back(base::Microseconds(us));
      }

      scoped_refptr<StreamParserBuffer> buffer =
          StreamParserBuffer::CopyFrom(kDataA, is_keyframe, GetStreamType(), 0);
      buffer->set_timestamp(buffer_timestamps[0]);
      if (is_duration_estimated)
        buffer->set_is_duration_estimated(true);

      if (buffer_timestamps[1] != buffer_timestamps[0]) {
        buffer->SetDecodeTimestamp(
            DecodeTimestamp::FromPresentationTime(buffer_timestamps[1]));
      }

      if (duration_in_us >= 0)
        buffer->set_duration(base::Microseconds(duration_in_us));

      if (has_preroll) {
        scoped_refptr<StreamParserBuffer> preroll_buffer =
            StreamParserBuffer::CopyFrom(kDataA, is_keyframe, GetStreamType(),
                                         0);
        preroll_buffer->set_duration(frame_duration_);
        buffer->SetPrerollBuffer(preroll_buffer);
      }

      UpdateLastBufferDuration(buffer->GetDecodeTimestamp(), &buffers);
      buffers.push_back(buffer);
    }

    if (buffers.size() >= 2 && buffers.back()->duration() == kNoTimestamp) {
      buffers.back()->set_duration(
          buffers[buffers.size() - 2]->duration());
    }

    return buffers;
  }

  void AppendBuffers(const std::string& buffers_to_append,
                     bool start_new_coded_frame_group,
                     base::TimeDelta coded_frame_group_start_timestamp,
                     bool one_by_one) {
    BufferQueue buffers = StringToBufferQueue(buffers_to_append);

    if (start_new_coded_frame_group) {
      base::TimeDelta start_timestamp = coded_frame_group_start_timestamp;

      base::TimeDelta buffers_start_timestamp = buffers[0]->timestamp();

      if (start_timestamp == kNoTimestamp)
        start_timestamp = buffers_start_timestamp;
      else
        ASSERT_TRUE(start_timestamp <= buffers_start_timestamp);

      stream_->OnStartOfCodedFrameGroup(start_timestamp);
    }

    if (!one_by_one) {
      stream_->Append(buffers);
      return;
    }

    for (size_t i = 0; i < buffers.size(); i++) {
      BufferQueue wrapper;
      wrapper.push_back(buffers[i]);
      stream_->Append(wrapper);
    }
  }

  int frames_per_second_;
  int keyframes_per_second_;
  base::TimeDelta frame_duration_;
};

TEST_F(ParcSourceBufferStreamTest, ParcRemovalSize_IsWhatParcRemoveFrees) {
  NewCodedFrameGroupAppend("0K 30 60 90K 120 150 180K 210 240");
  NewCodedFrameGroupAppend("600K 630 660 690K 720 750");
  CheckExpectedRangesByTimestamp("{ [0,270) [600,780) }");
  const auto remove = [this](int start_ms, int end_ms) {
    const base::TimeDelta start = base::Milliseconds(start_ms);
    const base::TimeDelta end = base::Milliseconds(end_ms);
    const base::TimeDelta duration = base::Milliseconds(1000);
    const size_t expected = ParcSourceBufferStreamState::RemovalSize(*stream_, start, end, duration);
    const size_t before = stream_->GetMemoryUsage();
    ParcSourceBufferStreamState::Remove(*stream_, start, end, duration);
    EXPECT_EQ(expected, before - stream_->GetMemoryUsage());
    EXPECT_GT(expected, 0u);
  };

  remove(100, 130);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,270) [600,780) }");

  remove(700, 710);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,270) [600,720) }");

  remove(200, 650);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,210) [690,720) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_ChromeKeepsSmallGaps) {
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,132) [202,334) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariFillsGapsUnderTimeFudgeFactor) {
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  NewCodedFrameGroupAppend("434K 467");
  CheckExpectedRangesByTimestamp("{ [0,334) [434,500) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariFilledGapLeavesWithTheFramesBesideIt) {
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  RemoveInMs(202, 334, 334);
  CheckExpectedRangesByTimestamp("{ [0,132) }");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  RemoveInMs(0, 132, 334);
  CheckExpectedRangesByTimestamp("{ [202,334) }");
  NewCodedFrameGroupAppend("0K 33 66 99");
  CheckExpectedRangesByTimestamp("{ [0,132) [202,334) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_ChromeVideoStopsAtGaps) {
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("232K 265");
  SeekToTimestampMs(0);
  CheckExpectedBuffers("0K 33 66 99");
  CheckNoNextBuffer();
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariVideoPlaysAcrossGapsWithinTolerance) {
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("232K 265");
  NewCodedFrameGroupAppend("432K 465");
  CheckExpectedRangesByTimestamp("{ [0,132) [232,298) [432,498) }");
  SeekToTimestampMs(0);
  CheckExpectedBuffers("0K 33 66 99 232K 265");
  CheckNoNextBuffer();

  Ranges<base::TimeDelta> audio;
  audio.Add(base::TimeDelta(), base::Seconds(1));
  ParcSourceBufferStreamState::ShareMediaSourceBuffered(*stream_, base::TimeDelta(), audio);
  CheckExpectedBuffers("432K 465");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariVideoBridgesAfterTrackBuffer) {
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("100K 133 166 199");
  NewCodedFrameGroupAppend("342K 375");
  SeekToTimestampMs(100);
  CheckExpectedBuffers("100K");
  NewCodedFrameGroupAppend("0K 33 66 100K");
  CheckExpectedBuffers("133 166 199");
  EXPECT_MEDIA_LOG(ContainsTrackBufferExhaustionSkipLog(143));
  CheckExpectedBuffers("342K 375");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariAudioStopsAtGaps) {
  SetAudioStream();
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("0K 2K 4K 6K");
  NewCodedFrameGroupAppend("60K 62K");
  SeekToTimestampMs(0);
  CheckExpectedBuffers("0K 2K 4K 6K");
  CheckNoNextBuffer();
}

TEST_F(ParcSourceBufferStreamTest, Parc_ChromeSeekIntoGapWaits) {
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("300K 333");
  SeekToTimestampMs(180);
  EXPECT_TRUE(stream_->IsSeekPending());
  CheckNoNextBuffer();
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariSeekIntoGapStartsAtNextRange) {
  ParcSourceBufferStreamState::UseSafariMediaSource(*stream_, true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("300K 333");

  SeekToTimestampMs(160);
  EXPECT_TRUE(stream_->IsSeekPending());
  SeekToTimestampMs(180);
  EXPECT_FALSE(stream_->IsSeekPending());
  CheckExpectedBuffers("300K 333");

  SeekToTimestampMs(160);
  EXPECT_TRUE(stream_->IsSeekPending());
  Ranges<base::TimeDelta> audio;
  audio.Add(base::TimeDelta(), base::Seconds(1));
  ParcSourceBufferStreamState::ShareMediaSourceBuffered(*stream_, base::TimeDelta(), audio);
  EXPECT_FALSE(stream_->IsSeekPending());
  CheckExpectedBuffers("300K 333");
}

}

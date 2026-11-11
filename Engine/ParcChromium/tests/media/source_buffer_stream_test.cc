// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/source_buffer_stream_test.cc. The fixture is derived from
// Chromium's source_buffer_stream_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

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
#include "media/base/webvtt_util.h"
#include "media/filters/source_buffer_range.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::testing::InSequence;
using ::testing::StrictMock;

namespace {

enum class TimeGranularity { kMicrosecond, kMillisecond };

static constexpr int kSampleRate = 3000;

}  // namespace

namespace media {

typedef StreamParser::BufferQueue BufferQueue;

static const int kDefaultFramesPerSecond = 30;
static const int kDefaultKeyframesPerSecond = 6;
static std::array<const uint8_t, 1> kDataA = {0x11};

// Matchers for verifying common media log entry strings.
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

    // Equivalent to 2ms per frame.
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

      // Check duration if expected timestamp contains it.
      if (timestamps[i].contains('D')) {
        ss << "D" << buffer->duration().InMilliseconds();
      }

      // Check duration estimation if expected timestamp contains it.
      if (timestamps[i].contains('E') && buffer->is_duration_estimated()) {
        ss << "E";
      }

      // Handle preroll buffers.
      if (timestamps[i].ends_with("P")) {
        ASSERT_TRUE(buffer->is_key_frame());
        scoped_refptr<StreamParserBuffer> preroll_buffer;
        preroll_buffer.swap(buffer);

        // When a preroll buffer is encountered we should be able to request one
        // more buffer.  The first buffer should match the timestamp and config
        // of the second buffer, except that its discard_padding() should be its
        // duration.
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
      // Track ID is meaningless to these tests.
      scoped_refptr<StreamParserBuffer> buffer =
          StreamParserBuffer::CopyFrom(data, is_keyframe, GetStreamType(), 0);
      base::TimeDelta timestamp = frame_duration_ * position;

      if (i == 0)
        timestamp += first_buffer_offset;
      buffer->SetDecodeTimestamp(
          DecodeTimestamp::FromPresentationTime(timestamp));

      // Simulate an IBB...BBP pattern in which all B-frames reference both
      // the I- and P-frames. For a GOP with playback order 12345, this would
      // result in a decode timestamp order of 15234.
      base::TimeDelta presentation_timestamp;
      if (is_keyframe) {
        presentation_timestamp = timestamp;
      } else if ((position - 1) % keyframe_interval == 0) {
        // This is the P-frame (first frame following the I-frame)
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

  // StringToBufferQueue() allows for the generation of StreamParserBuffers from
  // coded strings of timestamps separated by spaces.
  //
  // Supported syntax (options must be in this order):
  // pp[u][|dd[u]][Dzz][E][P][K]
  //
  // pp:
  // Generates a StreamParserBuffer with decode and presentation timestamp xx.
  // E.g., "0 1 2 3".
  // pp is interpreted as milliseconds, unless suffixed with "u", in which case
  // pp is interpreted as microseconds.
  //
  // pp|dd:
  // Generates a StreamParserBuffer with presentation timestamp pp and decode
  // timestamp dd. E.g., "0|0 3|1 1|2 2|3". dd is interpreted as milliseconds,
  // unless suffixed with "u", in which case dd is interpreted as microseconds.
  //
  // Dzz[u]
  // Explicitly describe the duration of the buffer. zz specifies the duration
  // in milliseconds (or in microseconds if suffixed with "u"). If the duration
  // isn't specified with this syntax, the duration is derived using the
  // timestamp delta between this buffer and the next buffer. If not specified,
  // the final buffer will simply copy the duration of the previous buffer. If
  // the queue only contains 1 buffer then the duration must be explicitly
  // specified with this format.
  // E.g. "0D10 10D20"
  //
  // E:
  // Indicates that the buffer should be marked as containing an *estimated*
  // duration. E.g., "0D20E 20 25E 30"
  //
  // P:
  // Indicates the buffer with will also have a preroll buffer
  // associated with it. The preroll buffer will just be dummy data.
  // E.g. "0P 5 10"
  //
  // K:
  // Indicates the buffer is a keyframe. E.g., "0K 1|2K 2|4D2K 6 8".
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
        // Remove the "K" off of the token.
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }
      // Handle preroll buffers.
      if (timestamps[i].ends_with("P")) {
        is_keyframe = true;
        has_preroll = true;
        // Remove the "P" off of the token.
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }

      if (timestamps[i].ends_with("E")) {
        is_duration_estimated = true;
        // Remove the "E" off of the token.
        timestamps[i] = timestamps[i].substr(0, timestamps[i].length() - 1);
      }

      int duration_in_us = -1;
      size_t duration_pos = timestamps[i].find('D');
      if (duration_pos != std::string::npos) {
        bool is_duration_us = false;  // Default to millisecond interpretation.
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

      // Parse PTS, then DTS into TimeDeltas.
      for (size_t j = 0; j < 2; ++j) {
        int us = 0;
        bool is_us = false;  // Default to millisecond interpretation.

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

      // Create buffer. Track ID is meaningless to these tests
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

      // Simulate preroll buffers by just generating another buffer and sticking
      // it as the preroll.
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

    // If the last buffer doesn't have a duration, assume it is the
    // same as the second to last buffer.
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

    // Append each buffer one by one.
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


// Using position based test API:
// DTS  :  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
// PTS  :  0  4  1  2  3  5  9  6  7  8 10 14 11 12 13 15 19 16 17 18 20
// old  :                                A  a  a  a  a  A  a  a  a  a
// new  :                 B  b  b  b  b  B  b  b
// after:                 B  b  b  b  b  B  b  b        A  a  a  a  a

// Test an end overlap edge case where a single buffer overlaps the
// beginning of a range.
// old  : 0K   30   60   90   120K  150
// new  : 0K
// after: 0K                  120K  150
// track:

// Using position based test API:
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :            A a                 A a                 A a
// new  :  B b b b b B b b b b B b b b b B b b b b B b b b b B b b b b
// after == new

// Using position based test API:
// DTS:0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6
// PTS:0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9
// old:          A a                 A a                 A a                 A a
// new:B b b b b B b b b b B b b b b B b b b b B b b b b B b b b b B b b b b


// This test is testing that a client can append data to SourceBufferStream that
// overlaps the range from which the client is currently grabbing buffers. We
// would expect that the SourceBufferStream would return old data until it hits
// the keyframe of the new data, after which it will return the new data.


// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer is a keyframe that's being overlapped by new
// buffers.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :           *A*a a a a A a a a a
// new  :  B b b b b B b b b b
// after:  B b b b b*B*b b b b A a a a a

// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is after the newly appended buffers.
//
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :           |A a a a a A a a*a*a|
// new  :  B b b b b B b b b b
// after: |B b b b b B b b b b A a a*a*a|

// Using position based test API:
// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is after the newly appended buffers.
//
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :            A a a a a A a a*a*a
// new  :  B b b b b B b b
// after:  B b b b b B b b     A a a*a*a

// Using position based test API:
// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is after the newly appended buffers.
//
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :            A a a*a*a A a a a a
// new  :  B b b b b B b b
// after:  B b b b b B b b     A a a a a
// track:                  a a

// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is overlapped by the new buffers.
//
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :           |A a a*a*a A a a a a|
// new  :  B b b b b B b b b b
// after: |B b b b b B b b b b A a a a a|
// track:                 |a a|

// Using position based test API:
// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is overlapped by the new buffers.
//
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :            A*a*a a a A a a a a
// new  :  B b b b b B b
// after:  B b b b b B b       A a a a a
// track:              a a a a

// Using position based test API:
// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next buffer in the range is overlapped by the new buffers.
// In this particular case, the next keyframe after the track buffer is in the
// range with the new buffers.
//
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :            A*a*a a a A a a a a A a a a a
// new  :  B b b b b B b b b b B
// after:  B b b b b B b b b b B         A a a a a
// track:              a a a a

// This test covers the case where new buffers end-overlap an existing, selected
// range, and there is no keyframe after the end of the new buffers.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :           |A*a*a a a|
// new  :  B b b b b B
// after: |B b b b b B|
// track:             |a a a a|

// Using position based test API:
// This test covers the case where new buffers end-overlap an existing, selected
// range, and there is no keyframe after the end of the new buffers, then more
// buffers end-overlap the beginning.
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// PTS :   0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0
// old  :                      A a a a a A*a*
// new  :            B b b b b B b b b b B
// after:            B b b b b B b b b b B
// new  :  A a a a a A
// after:  A a a a a A         B b b b b B
// track:                                  a
// new  :                                B b b b b B
// after:  A a a a a A         B b b b b B b b b b B

// This test covers the case where new buffers end-overlap an existing, selected
// range, and the next keyframe in a separate range.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :           |A*a*a a a|         |A a a a a|
// new  :  B b b b b B
// after: |B b b b b B|                 |A a a a a|
// track:             |a a a a|

// This test covers the case when new buffers overlap the middle of a selected
// range. This tests the case when there is precise overlap of an existing GOP,
// and the next buffer is a keyframe.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :  A a a a a*A*a a a a A a a a a
// new  :            B b b b b
// after:  A a a a a*B*b b b b A a a a a

// This test covers the case when new buffers overlap the middle of a selected
// range. This tests the case when there is precise overlap of an existing GOP,
// and the next buffer is a non-keyframe in a GOP after the new buffers.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :  A a a a a A a a a a A*a*a a a
// new  :            B b b b b
// after:  A a a a a B b b b b A*a*a a a

// This test covers the case when new buffers overlap the middle of a selected
// range. This tests the case when only a partial GOP is appended, that append
// is merged into the overlapped range, and the next buffer is before the new
// buffers.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :  A a*a*a a A a a a a A a a a a
// new  :            B
// after:  A a*a*a a B         A a a a a

// This test covers the case when new buffers overlap the middle of a selected
// range. This tests the case when only a partial GOP is appended, and the next
// buffer is after the new buffers, and comes from the track buffer until the
// next GOP in the original buffers.
// index:  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
// old  :  A a a a a A a a*a*a A a a a a
// new  :            B
// after:  A a a a a B         A a a a a
// track:                  a a


// old  :   10K  40  *70*  100K  125  130K
// new  : 0K   30   60   90   120K
// after: 0K   30   60   90  *120K*   130K

// Overlap the next keyframe after the end of the track buffer with a new
// keyframe.
// old  :   10K  40  *70*  100K  125  130K
// new  : 0K   30   60   90   120K
// after: 0K   30   60   90  *120K*   130K
// track:             70
// new  :                     110K    130
// after: 0K   30   60   90  *110K*   130

// Overlap the next keyframe after the end of the track buffer without a
// new keyframe.
// old  :   10K  40  *70*  100K  125  130K
// new  : 0K   30   60   90   120K
// after: 0K   30   60   90  *120K*   130K
// track:             70
// new  :        50K   80   110          140
// after: 0K   30   50K   80   110   140 * (waiting for keyframe)
// track:             70

// Overlap the next keyframe after the end of the track buffer with a keyframe
// that comes before the end of the track buffer.
// old  :   10K  40  *70*  100K  125  130K
// new  : 0K   30   60   90   120K
// after: 0K   30   60   90  *120K*   130K
// track:             70
// new  :              80K  110          140
// after: 0K   30   60   *80K*  110   140
// track:               70

// Overlap the next keyframe after the end of the track buffer with a keyframe
// that comes before the end of the track buffer, when the selected stream was
// waiting for the next keyframe.
// old  :   10K  40  *70*  100K
// new  : 0K   30   60   90   120
// after: 0K   30   60   90   120 * (waiting for keyframe)
// track:             70
// new  :              80K  110          140
// after: 0K   30   60   *80K*  110   140
// track:               70

// Test that appending to a different range while there is data in
// the track buffer doesn't affect the selected range or track buffer state.
// old  :   10K  40  *70*  100K  125  130K ... 200K 230
// new  : 0K   30   60   90   120K
// after: 0K   30   60   90  *120K*   130K ... 200K 230
// track:             70
// old  : 0K   30   60   90  *120K*   130K ... 200K 230
// new  :                                               260K 290
// after: 0K   30   60   90  *120K*   130K ... 200K 230 260K 290
// track:             70

// Test that overlap-appending with a GOP that begins with time of next track
// buffer frame drops that track buffer frame and buffers the new GOP correctly.
// append :    10K   40    70     100
// read the first two buffers
// after  :    10K   40   *70*    100
//
// append : 0K    30    60    90    120
// after  : 0K    30    60    90    120
// track  :               *70*    100
//
// read the buffer at 70ms from track
// after  : 0K    30    60    90    120
// track  :                      *100*
//
// append :                       100K   130
// after  : 0K    30    60    90 *100K*  130
// track  : (empty)
// 100K, not 100, should be the next buffer read.


// This test will do a complete overlap of an existing range in order to add
// buffers to the track buffers. Then the test does a seek to another part of
// the stream. The SourceBufferStream should clear its internal track buffer in
// response to the Seek().


// This test covers the case where new buffers start-overlap a range whose next
// buffer is not buffered.

// Tests a start overlap that occurs right at the timestamp of the last output
// buffer that was returned by GetNextBuffer(). This test verifies that
// GetNextBuffer() skips to second GOP in the newly appended data instead
// of returning two buffers with the same timestamp.

// This test covers the case where new buffers completely overlap a range
// whose next buffer is not buffered.

// This test covers the case where a range is stalled waiting for its next
// buffer, then an end-overlap causes the end of the range to be deleted.

// This test is testing the "next buffer" logic after a complete overlap. In
// this scenario, when the track buffer is exhausted, there is no buffered data
// to fulfill the request. The SourceBufferStream should be able to fulfill the
// request when the data is later appended, and should not lose track of the
// "next buffer" position.


// Using position based test API:
// DTS  :  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4
// PTS  :  0 4 1 2 3 5 9 6 7 8 0 4 1 2 3 5 9 6 7 8 0 4 1 2 3
// old  :  A a a a a A a a a a A a a a a*A*a a
//       -- Garbage Collect --
// after:                                A a a
//       -- Read one buffer --
// after:                                A*a*a
// new  :  B b b b b B b b b b B b b b b B b b b b
// track:                                 *a*a
//       -- Garbage Collect --
// after:                                B b b b b
// track:                                 *a*a
//       -- Read 2 buffers -> exhausts track buffer
// after:                                B b b b b
//       (awaiting next keyframe after GOP at position 15)
// new  :                                         *B*b b b b
// after:                                B b b b b*B*b b b b
//       -- Garbage Collect --
// after:                                         *B*b b b b

// Test GC preserves data starting at first GOP containing playback position.

// Test saving the last GOP appended when this GOP is the only GOP in its range.

// Test saving the last GOP appended when this GOP is in the middle of a
// non-selected range.

// Parc: the removals of SourceBufferState::ParcEvictFrames(), and the
// estimate ParcComputeEvictionData() makes of them.
TEST_F(ParcSourceBufferStreamTest, ParcRemovalSize_IsWhatParcRemoveFrees) {
  NewCodedFrameGroupAppend("0K 30 60 90K 120 150 180K 210 240");
  NewCodedFrameGroupAppend("600K 630 660 690K 720 750");
  CheckExpectedRangesByTimestamp("{ [0,270) [600,780) }");
  const auto remove = [this](int start_ms, int end_ms) {
    const base::TimeDelta start = base::Milliseconds(start_ms);
    const base::TimeDelta end = base::Milliseconds(end_ms);
    const base::TimeDelta duration = base::Milliseconds(1000);
    const size_t expected = stream_->ParcRemovalSize(start, end, duration);
    const size_t before = stream_->GetMemoryUsage();
    stream_->ParcRemove(start, end, duration);
    EXPECT_EQ(expected, before - stream_->GetMemoryUsage());
    EXPECT_GT(expected, 0u);
  };

  // Frame by frame from |start|, on to the next keyframe after |end|.
  remove(100, 130);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,270) [600,780) }");

  // To the end of the range when no keyframe follows |end| there.
  remove(700, 710);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,270) [600,720) }");

  // Across ranges, up to the keyframe after |end|.
  remove(200, 650);
  CheckExpectedRangesByTimestamp("{ [0,120) [180,210) [690,720) }");
}

// Test saving the last GOP appended when the GOP containing the next buffer is
// adjacent to the last GOP appended.

// Test saving the last GOP appended when it is at the beginning or end of the
// selected range. This tests when the last GOP appended is before or after the
// GOP containing the next buffer, but not directly adjacent to this GOP.

// Test saving the last GOP appended when it is the same as the GOP containing
// the next buffer.

// Test the performance of garbage collection.


// Test the case where duration is set while the stream parser buffers
// already start passing the data to decoding pipeline. Selected range,
// when invalidated by getting truncated, should be updated to NULL
// accordingly so that successive append operations keep working.


// Test the case were the current playback position is at the end of the
// buffered data and several overlaps occur.

// Verify that a single coded frame at the current read position unblocks the
// read even if the frame is buffered after the previously read position is
// removed.

// Verify that multiple short (relative to max-inter-buffer-distance * 2) coded
// frames at the current read position unblock the read even if the frames are
// buffered after the previously read position is removed.

// Verify that multiple short (relative to max-inter-buffer-distance * 2) coded
// frames starting at the fudge room boundary unblock the read even if the
// frames are buffered after the previously read position is removed.

// Verify that coded frames starting after the fudge room boundary do not
// unblock the read when buffered after the previously read position is removed.

// Verify that non-keyframes with the same timestamp in the same
// append are handled correctly.

// Verify that a non-keyframe followed by a keyframe with the same timestamp
// is allowed.

// Verify that non-keyframes with the same timestamp can occur
// in different appends.

// Verify that a non-keyframe followed by a keyframe with the same timestamp
// is allowed.

// Verify that a keyframe followed by a non-keyframe with the same timestamp
// is allowed.


// Test all the valid same timestamp cases for audio.

// If seeking past any existing range and the seek is pending
// because no data has been provided for that position,
// the stream position can be considered as the end of stream.

// If there is a pending seek between 2 existing ranges,
// the end of the stream has not been reached.

// Removing exact start & end of a range.

// Removal range starts before range and ends exactly at end.

// Removal range starts at the start of a range and ends beyond the
// range end.

// Removal range starts before range start and ends after the range end.

// Removes multiple ranges.

// Verifies a [0-infinity) range removes everything.

// Removal range starts at the beginning of the range and ends in the
// middle of the range. This test verifies that full GOPs are removed.

// Removal range starts in the middle of a range and ends at the exact
// end of the range.

// Removal range starts and ends within a range.

// Removal range starts in the middle of one range and ends in the
// middle of another range.

// Test behavior when the current position is removed and new buffers
// are appended over the removal range.

// Test behavior when buffers in the selected range before the current position
// are removed.

// Test removing the preliminary portion for the current coded frame group being
// appended.

// Test removing the current GOP being appended, while not removing
// the entire range the GOP belongs to.


// Test that a splice is not created if an end timestamp and start timestamp
// perfectly overlap.


// Parc: a Safari-identity page's Media Source
// (SourceBufferStream::ParcSetSafariMediaSource()) reports buffered ranges as
// WebKit's TrackBuffer does: a frame appended within 2002/24000 s of a range
// fills the gap. A 70 ms gap in 30 fps video is two ranges in Chromium.
TEST_F(ParcSourceBufferStreamTest, Parc_ChromeKeepsSmallGaps) {
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,132) [202,334) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariFillsGapsUnderTimeFudgeFactor) {
  stream_->ParcSetSafariMediaSource(true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  // A 100 ms gap stays.
  NewCodedFrameGroupAppend("434K 467");
  CheckExpectedRangesByTimestamp("{ [0,334) [434,500) }");
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariFilledGapLeavesWithTheFramesBesideIt) {
  stream_->ParcSetSafariMediaSource(true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  // TrackBuffer::removeSamples() erases the filled gap with the frames after
  // it; appended again, the first of them fills it again.
  RemoveInMs(202, 334, 334);
  CheckExpectedRangesByTimestamp("{ [0,132) }");
  NewCodedFrameGroupAppend("202K 235 268 301");
  CheckExpectedRangesByTimestamp("{ [0,334) }");

  // And with the frames before it. Appended again, their last frame ends
  // nearer its own start than the next range (PlatformTimeRanges::nearest()),
  // so the gap stays open.
  RemoveInMs(0, 132, 334);
  CheckExpectedRangesByTimestamp("{ [202,334) }");
  NewCodedFrameGroupAppend("0K 33 66 99");
  CheckExpectedRangesByTimestamp("{ [0,132) [202,334) }");
}

// Parc: WebKit's playback crosses a gap of up to 125 ms, or 250 ms where the
// media source's audio covers its start (MediaSourcePrivate::
// gapToleranceAtTime()); Chromium's stops where a range ends.
TEST_F(ParcSourceBufferStreamTest, Parc_ChromeVideoStopsAtGaps) {
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("232K 265");
  SeekToTimestampMs(0);
  CheckExpectedBuffers("0K 33 66 99");
  CheckNoNextBuffer();
}

TEST_F(ParcSourceBufferStreamTest, Parc_SafariVideoPlaysAcrossGapsWithinTolerance) {
  stream_->ParcSetSafariMediaSource(true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("232K 265");
  NewCodedFrameGroupAppend("432K 465");
  CheckExpectedRangesByTimestamp("{ [0,132) [232,298) [432,498) }");
  SeekToTimestampMs(0);
  CheckExpectedBuffers("0K 33 66 99 232K 265");
  CheckNoNextBuffer();

  Ranges<base::TimeDelta> audio;
  audio.Add(base::TimeDelta(), base::Seconds(1));
  stream_->ParcSetMediaSourceBuffered(base::TimeDelta(), audio);
  CheckExpectedBuffers("432K 465");
}

// The overlapping append moves 133-199 to the track buffer and leaves no
// range selected once it runs out. The gap counts from where 199 ends (232),
// as WebKit measures from the end of the last sample it enqueued.
TEST_F(ParcSourceBufferStreamTest, Parc_SafariVideoBridgesAfterTrackBuffer) {
  stream_->ParcSetSafariMediaSource(true);
  NewCodedFrameGroupAppend("100K 133 166 199");
  NewCodedFrameGroupAppend("342K 375");
  SeekToTimestampMs(100);
  CheckExpectedBuffers("100K");
  NewCodedFrameGroupAppend("0K 33 66 100K");
  CheckExpectedBuffers("133 166 199");
  EXPECT_MEDIA_LOG(ContainsTrackBufferExhaustionSkipLog(143));
  CheckExpectedBuffers("342K 375");
}

// Chromium's audio renderer plays buffers back to back, so audio reads still
// stop at a gap; skipping it would shift audio against video.
TEST_F(ParcSourceBufferStreamTest, Parc_SafariAudioStopsAtGaps) {
  SetAudioStream();
  stream_->ParcSetSafariMediaSource(true);
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
  stream_->ParcSetSafariMediaSource(true);
  NewCodedFrameGroupAppend("0K 33 66 99");
  NewCodedFrameGroupAppend("300K 333");

  // TrackBuffer::reenqueueMediaForTime() starts from a frame up to the
  // tolerance after the target.
  SeekToTimestampMs(160);
  EXPECT_TRUE(stream_->IsSeekPending());
  SeekToTimestampMs(180);
  EXPECT_FALSE(stream_->IsSeekPending());
  CheckExpectedBuffers("300K 333");

  // 250 ms where the media source's audio covers the target.
  SeekToTimestampMs(160);
  EXPECT_TRUE(stream_->IsSeekPending());
  Ranges<base::TimeDelta> audio;
  audio.Add(base::TimeDelta(), base::Seconds(1));
  stream_->ParcSetMediaSourceBuffered(base::TimeDelta(), audio);
  EXPECT_FALSE(stream_->IsSeekPending());
  CheckExpectedBuffers("300K 333");
}

}  // namespace media

// Copyright 2026 Parc contributors.

#include <optional>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_util.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/test_helpers.h"
#include "media/base/timestamp_constants.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/parc_chunk_demuxer_hand_off.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

class ParcChunkDemuxerHandOffTest : public testing::Test {
 protected:
  ParcChunkDemuxerHandOffTest()
      : stream_(DemuxerStream::VIDEO, MediaTrack::Id("1")) {
    EXPECT_TRUE(stream_.UpdateVideoConfig(TestVideoConfig::Normal(),
                                          /*allow_codec_change=*/false,
                                          &media_log_));
    stream_.Seek(base::TimeDelta());
  }

  void Append(const std::string& frames) {
    StreamParser::BufferQueue buffers;
    for (const std::string& frame : base::SplitString(
             frames, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY)) {
      const bool key_frame = frame.ends_with("K");
      int milliseconds = 0;
      ASSERT_TRUE(base::StringToInt(
          key_frame ? frame.substr(0, frame.size() - 1) : frame,
          &milliseconds));
      const uint8_t data[] = {0};
      scoped_refptr<StreamParserBuffer> buffer = StreamParserBuffer::CopyFrom(
          data, key_frame, DemuxerStream::VIDEO, 0);
      const base::TimeDelta timestamp = base::Milliseconds(milliseconds);
      buffer->SetDecodeTimestamp(DecodeTimestamp::FromPresentationTime(timestamp));
      buffer->set_timestamp(timestamp);
      buffer->set_duration(base::Milliseconds(30));
      buffers.push_back(std::move(buffer));
    }
    stream_.OnStartOfCodedFrameGroup(buffers.front()->GetDecodeTimestamp(),
                                     buffers.front()->timestamp());
    ASSERT_TRUE(stream_.Append(buffers));
  }

  std::optional<std::string> ReadOne(DemuxerStream* reader) {
    read_.reset();
    reader->Read(1, base::BindOnce(
                        [](std::optional<std::string>* out,
                           DemuxerStream::Status status,
                           DemuxerStream::DecoderBufferVector buffers) {
                          if (status == DemuxerStream::kConfigChanged) {
                            *out = "config";
                          } else if (status == DemuxerStream::kAborted) {
                            *out = "aborted";
                          } else if (buffers[0]->end_of_stream()) {
                            *out = "EOS";
                          } else {
                            *out = base::NumberToString(
                                       buffers[0]->timestamp().InMilliseconds()) +
                                   (buffers[0]->is_key_frame() ? "K" : "");
                          }
                        },
                        &read_));
    base::RunLoop().RunUntilIdle();
    return read_;
  }

  std::string ReadAll(DemuxerStream* reader) {
    std::vector<std::string> results;
    while (results.empty() || (results.back() != "EOS" &&
                               results.back() != "config" &&
                               results.back() != "aborted")) {
      std::optional<std::string> result = ReadOne(reader);
      if (!result) {
        break;
      }
      results.push_back(*result);
    }
    return base::JoinString(results, " ");
  }

  base::test::SingleThreadTaskEnvironment task_environment_;
  NullMediaLog media_log_;
  std::optional<std::string> read_;
  ChunkDemuxerStream stream_;
};

TEST_F(ParcChunkDemuxerHandOffTest, SplitsAtAConfigChange) {
  Append("0K 30 60");
  ASSERT_TRUE(stream_.UpdateVideoConfig(TestVideoConfig::Large(),
                                        /*allow_codec_change=*/false,
                                        &media_log_));
  Append("90K 120");
  stream_.MarkEndOfStream();
  stream_.StartReturningData();
  DemuxerStream* incoming = ParcStreamHandOff::ReaderOf(stream_);

  bool reader_there = true;
  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(100), /*unread=*/false,
                                &reader_there),
            base::Milliseconds(90));
  EXPECT_FALSE(reader_there);
  EXPECT_EQ(ReadAll(&stream_), "0K 30 60 EOS");
  EXPECT_EQ(ReadAll(incoming), "config");
  EXPECT_TRUE(incoming->video_decoder_config().Matches(
      TestVideoConfig::Large()));
  EXPECT_EQ(ReadAll(incoming), "90K 120 EOS");
}

TEST_F(ParcChunkDemuxerHandOffTest, EndOfStreamPlacesAWaitingSplit) {
  Append("0K 30");
  stream_.StartReturningData();
  DemuxerStream* incoming = ParcStreamHandOff::ReaderOf(stream_);

  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(40), /*unread=*/false),
            std::nullopt);
  stream_.MarkEndOfStream();
  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(40), /*unread=*/false),
            base::Milliseconds(60));
  EXPECT_EQ(ReadAll(&stream_), "0K 30 EOS");
  EXPECT_EQ(ReadAll(incoming), "EOS");
}

TEST_F(ParcChunkDemuxerHandOffTest, SeekAfterTheSplitLeavesOneReader) {
  Append("0K 30 60K 90 120K");
  stream_.MarkEndOfStream();
  stream_.StartReturningData();
  DemuxerStream* incoming = ParcStreamHandOff::ReaderOf(stream_);
  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(40), /*unread=*/false),
            base::Milliseconds(60));
  EXPECT_EQ(ReadOne(&stream_), "0K");

  stream_.AbortReads();
  stream_.Seek(base::Milliseconds(30));
  stream_.StartReturningData();
  EXPECT_EQ(ReadAll(&stream_), "EOS");
  EXPECT_EQ(ReadAll(incoming), "0K 30 60K 90 120K EOS");
}

TEST_F(ParcChunkDemuxerHandOffTest, UnreadStreamStartsAtTheSplit) {
  Append("0K 30 60K 90");
  stream_.MarkEndOfStream();
  stream_.StartReturningData();
  DemuxerStream* incoming = ParcStreamHandOff::ReaderOf(stream_);

  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(60), /*unread=*/true),
            base::Milliseconds(60));
  EXPECT_EQ(ReadAll(incoming), "60K 90 EOS");
}

TEST_F(ParcChunkDemuxerHandOffTest, SplitMovesLaterUntilItsEndWasRead) {
  Append("0K 30 60K 90 120K 150 180K");
  stream_.MarkEndOfStream();
  stream_.StartReturningData();
  DemuxerStream* incoming = ParcStreamHandOff::ReaderOf(stream_);

  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(40), /*unread=*/false),
            base::Milliseconds(60));
  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(100), /*unread=*/false),
            base::Milliseconds(120));
  EXPECT_EQ(ReadAll(&stream_), "0K 30 60K 90 EOS");
  EXPECT_EQ(ParcStreamHandOff::SplitStreamAt(stream_, base::Milliseconds(160), /*unread=*/false),
            base::Milliseconds(120));
  EXPECT_EQ(ReadAll(incoming), "120K 150 180K EOS");
}

}

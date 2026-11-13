// Copyright 2026 Parc contributors.

#include "media/filters/chunk_demuxer.h"

#include <stddef.h>
#include <stdint.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <memory>
#include <queue>
#include <string>
#include <utility>
#include <vector>

#include "base/command_line.h"
#include "base/compiler_specific.h"
#include "base/containers/heap_array.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/numerics/safe_conversions.h"
#include "base/run_loop.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/synchronization/waitable_event.h"
#include "base/test/bind.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "build/build_config.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decrypt_config.h"
#include "media/base/media.h"
#include "media/base/media_switches.h"
#include "media/base/media_tracks.h"
#include "media/base/mock_demuxer_host.h"
#include "media/base/mock_media_log.h"
#include "media/base/parc_demuxer_extension.h"
#include "media/base/test_data_util.h"
#include "media/base/test_helpers.h"
#include "media/base/timestamp_constants.h"
#include "media/filters/parc_source_buffer_eviction.h"
#include "media/formats/webm/cluster_builder.h"
#include "media/formats/webm/webm_cluster_parser.h"
#include "media/formats/webm/webm_constants.h"
#include "media/media_buildflags.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::testing::AnyNumber;
using ::testing::Exactly;
using ::testing::InSequence;
using ::testing::StrictMock;
using ::testing::_;

namespace media {

const uint8_t kTracksHeader[] = {
    0x16, 0x54, 0xAE, 0x6B,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

const auto kEncryptedMediaInitData = std::to_array<uint8_t>({
    0x68,
    0xFE,
    0xF9,
    0xA1,
    0xB3,
    0x0D,
    0x6B,
    0x4D,
    0xF2,
    0x22,
    0xB5,
    0x0B,
    0x4D,
    0xE9,
    0xE9,
    0x95,
});

const int kTracksHeaderSize = sizeof(kTracksHeader);
const int kTracksSizeOffset = 4;

const int kAudioTrackSizeOffset = 1;
const int kAudioTrackSizeWidth = 8;
const int kAudioTrackEntryHeaderSize =
    kAudioTrackSizeOffset + kAudioTrackSizeWidth;

const int kVideoTrackSizeOffset = 1;
const int kVideoTrackSizeWidth = 8;
const int kVideoTrackEntryHeaderSize =
    kVideoTrackSizeOffset + kVideoTrackSizeWidth;

const int kVideoTrackNum = 1;
const int kAudioTrackNum = 2;
const int kAlternateVideoTrackNum = 4;
const int kAlternateAudioTrackNum = 5;
const int kAlternateTextTrackNum = 6;

const int kAudioBlockDuration = 23;
const int kVideoBlockDuration = 33;
const int kTextBlockDuration = 100;
const int kBlockSize = 10;

const char kSourceId[] = "SourceId";

static base::TimeDelta kDefaultDuration() {
  return base::Milliseconds(201224);
}

static void WriteInt64(base::span<uint8_t> buffer, int64_t number) {
  DCHECK(number >= 0 && number < 0x00FFFFFFFFFFFFFFLL);
  buffer[0] = 0x01;
  int64_t tmp = number;
  for (int i = 7; i > 0; i--) {
    buffer[i] = tmp & 0xff;
    tmp >>= 8;
  }
}

static void CheckBuffers(base::TimeDelta expected_start_time,
                         const int expected_duration_time_ms,
                         const DemuxerStream::DecoderBufferVector& buffers) {
  for (const auto& buffer : buffers) {
    EXPECT_EQ(expected_start_time, buffer->timestamp());
    expected_start_time += base::Milliseconds(expected_duration_time_ms);
  }
}

static void OnReadDone_Ok(base::TimeDelta expected_start_time,
                          const int expected_duration_time_ms,
                          const size_t expected_read_count,
                          bool* called,
                          DemuxerStream::Status status,
                          DemuxerStream::DecoderBufferVector buffers) {
  EXPECT_EQ(status, DemuxerStream::kOk);
  DVLOG(3) << __func__ << "buffers.size=" << buffers.size();
  EXPECT_EQ(buffers.size(), expected_read_count);
  CheckBuffers(expected_start_time, expected_duration_time_ms, buffers);

  *called = true;
}

static void StoreStatusAndBuffers(
    DemuxerStream::Status* status_out,
    DemuxerStream::DecoderBufferVector* buffers_out,
    DemuxerStream::Status status,
    DemuxerStream::DecoderBufferVector buffers) {
  *status_out = status;
  *buffers_out = std::move(buffers);
}

class ParcChunkDemuxerTest : public ::testing::Test {
 public:
  MOCK_METHOD1(DemuxerInitialized, void(PipelineStatus));

 protected:
  enum CodecsIndex {
    AUDIO,
    VIDEO,
    MAX_CODECS_INDEX
  };

  std::unique_ptr<Cluster> kDefaultFirstCluster() {
    return GenerateCluster(0, 4);
  }

  std::unique_ptr<Cluster> kDefaultSecondCluster() {
    return GenerateCluster(46, 66, 5);
  }

  ParcChunkDemuxerTest()
      : did_progress_(false),
        append_window_end_for_next_append_(kInfiniteDuration) {
    init_segment_received_cb_ = base::BindRepeating(
        &ParcChunkDemuxerTest::InitSegmentReceived, base::Unretained(this));
    CreateNewDemuxer();
  }

  ParcChunkDemuxerTest(const ParcChunkDemuxerTest&) = delete;
  ParcChunkDemuxerTest& operator=(const ParcChunkDemuxerTest&) = delete;

  void CreateNewDemuxer() {
    base::OnceClosure open_cb = base::BindOnce(&ParcChunkDemuxerTest::DemuxerOpened,
                                               base::Unretained(this));
    base::RepeatingClosure progress_cb = base::BindRepeating(
        &ParcChunkDemuxerTest::OnProgress, base::Unretained(this));
    Demuxer::EncryptedMediaInitDataCB encrypted_media_init_data_cb =
        base::BindRepeating(&ParcChunkDemuxerTest::OnEncryptedMediaInitData,
                            base::Unretained(this));
    EXPECT_MEDIA_LOG(ChunkDemuxerCtor());
    demuxer_ = std::make_unique<ChunkDemuxer>(std::move(open_cb), progress_cb,
                                              encrypted_media_init_data_cb,
                                              &media_log_);
  }

  ~ParcChunkDemuxerTest() override { ShutdownDemuxer(); }

  void CreateInitSegment(int stream_flags,
                         bool is_audio_encrypted,
                         bool is_video_encrypted,
                         base::HeapArray<uint8_t>* buffer) {
    bool has_audio = (stream_flags & HAS_AUDIO) != 0;
    bool has_video = (stream_flags & HAS_VIDEO) != 0;
    scoped_refptr<DecoderBuffer> ebml_header;
    scoped_refptr<DecoderBuffer> info;
    scoped_refptr<DecoderBuffer> audio_track_entry;
    scoped_refptr<DecoderBuffer> video_track_entry;
    scoped_refptr<DecoderBuffer> audio_content_encodings;
    scoped_refptr<DecoderBuffer> video_content_encodings;
    scoped_refptr<DecoderBuffer> text_track_entry;

    ebml_header = ReadTestDataFile("webm_ebml_element");

    info = ReadTestDataFile("webm_info_element");

    int tracks_element_size = 0;

    if (has_audio) {
      audio_track_entry = ReadTestDataFile("webm_vorbis_track_entry");
      auto audio_track_entry_span = base::span(*audio_track_entry);
      tracks_element_size += audio_track_entry_span.size();
      DCHECK_EQ(audio_track_entry_span[9], kWebMIdTrackNumber);
      DCHECK_EQ(audio_track_entry_span[10], 0x81);
      DCHECK_EQ(audio_track_entry_span[11], kAudioTrackNum);
      if (stream_flags & USE_ALTERNATE_AUDIO_TRACK_ID)
        UNSAFE_TODO(audio_track_entry->writable_data()[11]) =
            kAlternateAudioTrackNum;
      if (is_audio_encrypted) {
        audio_content_encodings = ReadTestDataFile("webm_content_encodings");
        tracks_element_size += audio_content_encodings->size();
      }
    }

    if (has_video) {
      video_track_entry = ReadTestDataFile("webm_vp8_track_entry");
      auto video_track_entry_span = base::span(*video_track_entry);
      tracks_element_size += video_track_entry_span.size();
      DCHECK_EQ(video_track_entry_span[9], kWebMIdTrackNumber);
      DCHECK_EQ(video_track_entry_span[10], 0x81);
      DCHECK_EQ(video_track_entry_span[11], kVideoTrackNum);
      if (stream_flags & USE_ALTERNATE_VIDEO_TRACK_ID)
        UNSAFE_TODO(video_track_entry->writable_data()[11]) =
            kAlternateVideoTrackNum;
      if (is_video_encrypted) {
        video_content_encodings = ReadTestDataFile("webm_content_encodings");
        tracks_element_size += video_content_encodings->size();
      }
    }

    size_t size = ebml_header->size() + info->size() + kTracksHeaderSize +
                  tracks_element_size;

    *buffer = base::HeapArray<uint8_t>::Uninit(size);

    base::span<uint8_t> buf = *buffer;
    auto ebml_header_span = base::span(*ebml_header);
    buf.copy_prefix_from(ebml_header_span);
    buf = buf.subspan(ebml_header_span.size());

    auto info_span = base::span(*info);
    buf.copy_prefix_from(info_span);
    buf = buf.subspan(info_span.size());

    buf.copy_prefix_from(kTracksHeader);
    WriteInt64(buf.subspan(base::checked_cast<size_t>(kTracksSizeOffset)),
               tracks_element_size);
    buf = buf.subspan(base::checked_cast<size_t>(kTracksHeaderSize));

    if (has_video) {
      auto video_track_entry_span = base::span(*video_track_entry);
      buf.copy_prefix_from(video_track_entry_span);
      if (is_video_encrypted) {
        auto video_content_encodings_span =
            base::span(*video_content_encodings);
        buf.subspan(video_track_entry_span.size())
            .copy_prefix_from(video_content_encodings_span);
        WriteInt64(
            buf.subspan(base::checked_cast<size_t>(kVideoTrackSizeOffset)),
            video_track_entry_span.size() +
                video_content_encodings_span.size() -
                kVideoTrackEntryHeaderSize);
        buf = buf.subspan(video_content_encodings_span.size());
      }
      buf = buf.subspan(video_track_entry_span.size());
    }

    if (has_audio) {
      auto audio_track_entry_span = base::span(*audio_track_entry);
      buf.copy_prefix_from(audio_track_entry_span);
      if (is_audio_encrypted) {
        auto audio_content_encodings_span =
            base::span(*audio_content_encodings);
        buf.subspan(audio_track_entry_span.size())
            .copy_prefix_from(audio_content_encodings_span);
        WriteInt64(
            buf.subspan(base::checked_cast<size_t>(kAudioTrackSizeOffset)),
            audio_track_entry_span.size() +
                audio_content_encodings_span.size() -
                kAudioTrackEntryHeaderSize);
        buf = buf.subspan(audio_content_encodings_span.size());
      }
      buf = buf.subspan(audio_track_entry_span.size());
    }
  }

  ChunkDemuxer::Status AddId() {
    return AddId(kSourceId, HAS_AUDIO | HAS_VIDEO);
  }

  ChunkDemuxer::Status AddId(const std::string& source_id, int stream_flags) {
    bool has_audio = (stream_flags & HAS_AUDIO) != 0;
    bool has_video = (stream_flags & HAS_VIDEO) != 0;
    std::string codecs;
    std::string type;

    if (has_audio) {
      codecs += "vorbis";
      type = "audio/webm";
    }

    if (has_video) {
      if (codecs == "")
        codecs = "vp8";
      else
        codecs += ",vp8";
      type = "video/webm";
    }

    if (!has_audio && !has_video) {
      return AddId(kSourceId, HAS_AUDIO | HAS_VIDEO);
    }

    return AddId(source_id, type, codecs);
  }

  ChunkDemuxer::Status AddId(const std::string& source_id,
                             const std::string& mime_type,
                             const std::string& codecs) {
    ChunkDemuxer::Status status = demuxer_->AddId(source_id, mime_type, codecs);
    if (status == ChunkDemuxer::kOk) {
      demuxer_->SetTracksWatcher(source_id, init_segment_received_cb_);
      demuxer_->SetParseWarningCallback(
          source_id, base::BindRepeating(&ParcChunkDemuxerTest::OnParseWarningMock,
                                         base::Unretained(this)));
    }
    return status;
  }

#if BUILDFLAG(ENABLE_HLS_DEMUXER)
  void AddAutoDetectedCodecsId_Checked(const std::string& id,
                                       RelaxedParserSupportedType mime_type) {
    CHECK_EQ(demuxer_->AddAutoDetectedCodecsId(id, mime_type),
             ChunkDemuxer::kOk);
    demuxer_->SetTracksWatcher(id, init_segment_received_cb_);
    demuxer_->SetParseWarningCallback(
        id, base::BindRepeating(&ParcChunkDemuxerTest::OnParseWarningMock,
                                base::Unretained(this)));
  }
#endif

  bool AppendData(base::span<const uint8_t> data) {
    return AppendData(kSourceId, data);
  }

  bool AppendCluster(const std::string& source_id,
                     std::unique_ptr<Cluster> cluster) {
    return AppendData(source_id, cluster->AsSpan());
  }

  bool AppendCluster(std::unique_ptr<Cluster> cluster) {
    return AppendCluster(kSourceId, std::move(cluster));
  }

  bool AppendCluster(int timecode, int block_count) {
    return AppendCluster(GenerateCluster(timecode, block_count));
  }

  void AppendSingleStreamCluster(const std::string& source_id, int track_number,
                                 int timecode, int block_count) {
    int block_duration = 0;
    switch (track_number) {
      case kVideoTrackNum:
      case kAlternateVideoTrackNum:
        block_duration = kVideoBlockDuration;
        break;
      case kAudioTrackNum:
      case kAlternateAudioTrackNum:
        block_duration = kAudioBlockDuration;
        break;
      case kAlternateTextTrackNum:
        block_duration = kTextBlockDuration;
        break;
    }
    ASSERT_NE(block_duration, 0);
    int end_timecode = timecode + block_count * block_duration;
    ASSERT_TRUE(AppendCluster(
        source_id, GenerateSingleStreamCluster(timecode, end_timecode,
                                               track_number, block_duration)));
  }

  struct BlockInfo {
    BlockInfo()
        : track_number(0),
          timestamp_in_ms(0),
          flags(0),
          duration(0) {
    }

    BlockInfo(int tn, int ts, int f, int d)
        : track_number(tn),
          timestamp_in_ms(ts),
          flags(f),
          duration(d) {
    }

    int track_number;
    int timestamp_in_ms;
    int flags;
    int duration;

    bool operator< (const BlockInfo& rhs) const {
      return timestamp_in_ms < rhs.timestamp_in_ms;
    }
  };

  void ParseBlockDescriptions(int track_number,
                              const std::string block_descriptions,
                              std::vector<BlockInfo>* blocks) {
    std::vector<std::string> timestamps = base::SplitString(
        block_descriptions, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL);

    for (size_t i = 0; i < timestamps.size(); ++i) {
      std::string timestamp_str = timestamps[i];
      BlockInfo block_info;
      block_info.track_number = track_number;
      block_info.flags = 0;
      block_info.duration = 0;

      if (timestamp_str.ends_with("K")) {
        block_info.flags = kWebMFlagKeyframe;
        timestamp_str = timestamp_str.substr(0, timestamps[i].length() - 1);
      }

      size_t duration_pos = timestamp_str.find('D');
      const bool explicit_duration = duration_pos != std::string::npos;
      const bool is_last_block = i == timestamps.size() - 1;
      CHECK(!explicit_duration || is_last_block);
      if (explicit_duration) {
        CHECK(base::StringToInt(timestamp_str.substr(duration_pos + 1),
                                &block_info.duration));
        timestamp_str = timestamp_str.substr(0, duration_pos);
      }

      CHECK(base::StringToInt(timestamp_str, &block_info.timestamp_in_ms));

      if (track_number == kAlternateTextTrackNum) {
        block_info.duration = kTextBlockDuration;
        ASSERT_EQ(kWebMFlagKeyframe, block_info.flags)
            << "Text block with timestamp " << block_info.timestamp_in_ms
            << " was not marked as a key frame."
            << " All text blocks must be key frames";
      }

      if (track_number == kAudioTrackNum ||
          track_number == kAlternateAudioTrackNum)
        ASSERT_TRUE(block_info.flags & kWebMFlagKeyframe);

      blocks->push_back(block_info);
    }
  }

  std::unique_ptr<Cluster> GenerateCluster(const std::vector<BlockInfo>& blocks,
                                           bool unknown_size) {
    DCHECK_GT(blocks.size(), 0u);
    ClusterBuilder cb;

    std::vector<uint8_t> data(block_size_);

    for (size_t i = 0; i < blocks.size(); ++i) {
      if (i == 0)
        cb.SetClusterTimecode(blocks[i].timestamp_in_ms);

      if (blocks[i].duration) {
        cb.AddBlockGroup(blocks[i].track_number, blocks[i].timestamp_in_ms,
                         blocks[i].duration, blocks[i].flags,
                         blocks[i].flags & kWebMFlagKeyframe, data);
      } else {
        cb.AddSimpleBlock(blocks[i].track_number, blocks[i].timestamp_in_ms,
                          blocks[i].flags, data);
      }
    }

    return unknown_size ? cb.FinishWithUnknownSize() : cb.Finish();
  }

  std::unique_ptr<Cluster> GenerateCluster(
      std::priority_queue<BlockInfo> block_queue,
      bool unknown_size) {
    std::vector<BlockInfo> blocks(block_queue.size());
    for (size_t i = block_queue.size() - 1; !block_queue.empty(); --i) {
      blocks[i] = block_queue.top();
      block_queue.pop();
    }

    return GenerateCluster(blocks, unknown_size);
  }

  void AppendSingleStreamCluster(const std::string& source_id, int track_number,
                                 const std::string& block_descriptions) {
    std::vector<BlockInfo> blocks;
    ParseBlockDescriptions(track_number, block_descriptions, &blocks);
    ASSERT_TRUE(AppendCluster(source_id, GenerateCluster(blocks, false)));
  }

  void ParcAppendFiveSecondAudioFrames(int first_second, int count) {
    for (int i = 0; i < count; i += 7) {
      const int end = std::min(i + 7, count);
      std::string frames;
      for (int j = i; j < end; ++j) {
        if (j > i) {
          frames += " ";
        }
        frames += base::NumberToString((first_second + 5 * j) * 1000);
        if (j + 1 == end) {
          frames += "D5000";
        }
        frames += "K";
      }
      AppendSingleStreamCluster(kSourceId, kAudioTrackNum, frames);
    }
  }

  struct MuxedStreamInfo {
    MuxedStreamInfo()
        : track_number(0),
          block_descriptions(""),
          last_blocks_estimated_duration(-1) {}

    MuxedStreamInfo(int track_num, const char* block_desc)
        : track_number(track_num),
          block_descriptions(block_desc),
          last_blocks_estimated_duration(-1) {}

    MuxedStreamInfo(int track_num,
                    const char* block_desc,
                    int last_block_duration_estimate)
        : track_number(track_num),
          block_descriptions(block_desc),
          last_blocks_estimated_duration(last_block_duration_estimate) {}

    int track_number;
    const char* block_descriptions;

    int last_blocks_estimated_duration;
  };

  void AppendMuxedCluster(const MuxedStreamInfo& msi_1,
                          const MuxedStreamInfo& msi_2) {
    std::vector<MuxedStreamInfo> msi(2);
    msi[0] = msi_1;
    msi[1] = msi_2;
    AppendMuxedCluster(msi);
  }

  void AppendMuxedCluster(const MuxedStreamInfo& msi_1,
                          const MuxedStreamInfo& msi_2,
                          const MuxedStreamInfo& msi_3) {
    std::vector<MuxedStreamInfo> msi(3);
    msi[0] = msi_1;
    msi[1] = msi_2;
    msi[2] = msi_3;
    AppendMuxedCluster(msi);
  }

  std::unique_ptr<Cluster> GenerateMuxedCluster(
      const std::vector<MuxedStreamInfo> msi) {
    std::priority_queue<BlockInfo> block_queue;
    for (size_t i = 0; i < msi.size(); ++i) {
      std::vector<BlockInfo> track_blocks;
      ParseBlockDescriptions(msi[i].track_number, msi[i].block_descriptions,
                             &track_blocks);

      for (size_t j = 0; j < track_blocks.size(); ++j) {
        block_queue.push(track_blocks[j]);
      }

      if (msi[i].last_blocks_estimated_duration != -1) {
        EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(
            msi[i].last_blocks_estimated_duration));
      }
    }
    return GenerateCluster(block_queue, false);
  }

  void AppendMuxedCluster(const std::vector<MuxedStreamInfo> msi) {
    ASSERT_TRUE(AppendCluster(kSourceId, GenerateMuxedCluster(msi)));
  }

  bool AppendData(const std::string& source_id,
                  base::span<const uint8_t> data) {
    EXPECT_CALL(host_, OnBufferedTimeRangesChanged(_)).Times(AnyNumber());

    if (!demuxer_->AppendToParseBuffer(source_id, data)) {
      return false;
    }

    StreamParser::ParseStatus result =
        StreamParser::ParseStatus::kSuccessHasMoreData;
    while (result == StreamParser::ParseStatus::kSuccessHasMoreData) {
      result = demuxer_->RunSegmentParserLoop(
          source_id, append_window_start_for_next_append_,
          append_window_end_for_next_append_,
          &timestamp_offset_map_[source_id]);
    }
    return result == StreamParser::ParseStatus::kSuccess;
  }

  bool AppendDataInPieces(base::span<const uint8_t> data) {
    return AppendDataInPieces(data, 7);
  }

  bool AppendDataInPieces(base::span<const uint8_t> data, size_t piece_size) {
    size_t start = 0;
    size_t end = data.size();
    while (start < end) {
      size_t append_size = std::min(piece_size, end - start);
      if (!AppendData(data.subspan(start, append_size))) {
        return false;
      }
      start += append_size;
    }
    return true;
  }

  bool AppendInitSegment(int stream_flags) {
    return AppendInitSegmentWithSourceId(kSourceId, stream_flags);
  }

  bool AppendInitSegmentWithSourceId(const std::string& source_id,
                                     int stream_flags) {
    return AppendInitSegmentWithEncryptedInfo(source_id, stream_flags, false,
                                              false);
  }

  bool AppendInitSegmentWithEncryptedInfo(const std::string& source_id,
                                          int stream_flags,
                                          bool is_audio_encrypted,
                                          bool is_video_encrypted) {
    base::HeapArray<uint8_t> info_tracks;
    CreateInitSegment(stream_flags, is_audio_encrypted, is_video_encrypted,
                      &info_tracks);
    return AppendData(source_id, info_tracks);
  }

  void AppendGarbage() {
    int garbage_cluster_size = 10;
    auto garbage_cluster =
        base::HeapArray<uint8_t>::Uninit(garbage_cluster_size);
    for (int i = 0; i < garbage_cluster_size; ++i)
      garbage_cluster[i] = i;
    ASSERT_FALSE(AppendData(garbage_cluster));
  }

  PipelineStatusCallback CreateInitDoneCallback(
      base::TimeDelta expected_duration,
      PipelineStatus expected_status) {
    if (expected_duration != kNoTimestamp)
      EXPECT_CALL(host_, SetDuration(expected_duration));
    return CreateInitDoneCallback(expected_status);
  }

  PipelineStatusCallback CreateInitDoneCallback(
      PipelineStatus expected_status) {
    EXPECT_CALL(*this, DemuxerInitialized(expected_status));
    return base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                          base::Unretained(this));
  }

  enum StreamFlags {
    HAS_AUDIO = 1 << 0,
    HAS_VIDEO = 1 << 1,
    USE_ALTERNATE_AUDIO_TRACK_ID = 1 << 3,
    USE_ALTERNATE_VIDEO_TRACK_ID = 1 << 4,
    USE_ALTERNATE_TEXT_TRACK_ID = 1 << 5,
  };

  bool InitDemuxer(int stream_flags) {
    return InitDemuxerWithEncryptionInfo(stream_flags, false, false);
  }

  void ExpectInitMediaLogs(int stream_flags) {
    if (stream_flags & HAS_VIDEO)
      EXPECT_FOUND_CODEC_NAME(Video, "vp8");
    if (stream_flags & HAS_AUDIO)
      EXPECT_FOUND_CODEC_NAME(Audio, "vorbis");
  }

  bool InitDemuxerWithEncryptionInfo(
      int stream_flags, bool is_audio_encrypted, bool is_video_encrypted) {
    PipelineStatus expected_status =
        (stream_flags != 0) ? PIPELINE_OK : CHUNK_DEMUXER_ERROR_APPEND_FAILED;

    base::TimeDelta expected_duration = kNoTimestamp;
    if (expected_status == PIPELINE_OK)
      expected_duration = kDefaultDuration();

    EXPECT_CALL(*this, DemuxerOpened());

    if (is_audio_encrypted || is_video_encrypted) {
      DCHECK(!is_audio_encrypted || stream_flags & HAS_AUDIO);
      DCHECK(!is_video_encrypted || stream_flags & HAS_VIDEO);

      int need_key_count =
          (is_audio_encrypted ? 1 : 0) + (is_video_encrypted ? 1 : 0);

      EXPECT_CALL(*this,
                  OnEncryptedMediaInitData(
                      EmeInitDataType::WEBM,
                      std::vector<uint8_t>(
                          kEncryptedMediaInitData.data(),
                          base::span(kEncryptedMediaInitData)
                              .subspan(std::size(kEncryptedMediaInitData))
                              .data())))
          .Times(Exactly(need_key_count));
    }

    if (stream_flags != 0) {
      ExpectInitMediaLogs(stream_flags);
      EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    } else {
      EXPECT_MEDIA_LOG(InitSegmentMissesExpectedTrack("vorbis"));
      EXPECT_MEDIA_LOG(InitSegmentMissesExpectedTrack("vp8"));
      EXPECT_MEDIA_LOG(StreamParsingFailed());
    }

    demuxer_->Initialize(
        &host_, CreateInitDoneCallback(expected_duration, expected_status));

    if (AddId(kSourceId, stream_flags) != ChunkDemuxer::kOk)
      return false;

    return AppendInitSegmentWithEncryptedInfo(
        kSourceId, stream_flags, is_audio_encrypted, is_video_encrypted);
  }

  bool InitDemuxerAudioAndVideoSourcesText(const std::string& audio_id,
                                           const std::string& video_id) {
    EXPECT_CALL(*this, DemuxerOpened());
    demuxer_->Initialize(
        &host_, CreateInitDoneCallback(kDefaultDuration(), PIPELINE_OK));

    if (AddId(audio_id, HAS_AUDIO) != ChunkDemuxer::kOk)
      return false;
    if (AddId(video_id, HAS_VIDEO) != ChunkDemuxer::kOk)
      return false;

    int audio_flags = HAS_AUDIO;
    int video_flags = HAS_VIDEO;

    ExpectInitMediaLogs(audio_flags);
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    EXPECT_TRUE(AppendInitSegmentWithSourceId(audio_id, audio_flags));

    ExpectInitMediaLogs(video_flags);
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    EXPECT_TRUE(AppendInitSegmentWithSourceId(video_id, video_flags));
    return true;
  }

  bool InitDemuxerAudioAndVideoSources(const std::string& audio_id,
                                       const std::string& video_id) {
    return InitDemuxerAudioAndVideoSourcesText(audio_id, video_id);
  }

  bool InitDemuxerWithConfigChangeData() {
    scoped_refptr<DecoderBuffer> bear1 = ReadTestDataFile("bear-320x240.webm");
    scoped_refptr<DecoderBuffer> bear2 = ReadTestDataFile("bear-640x360.webm");

    auto bear_span1 = base::span(*bear1);
    auto bear_span2 = base::span(*bear2);

    EXPECT_CALL(*this, DemuxerOpened());

    ExpectInitMediaLogs(HAS_AUDIO | HAS_VIDEO);
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    demuxer_->Initialize(
        &host_, CreateInitDoneCallback(base::Milliseconds(2744), PIPELINE_OK));

    if (AddId(kSourceId, HAS_AUDIO | HAS_VIDEO) != ChunkDemuxer::kOk)
      return false;

    EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(24)).Times(3);
    EXPECT_CALL(host_, OnBufferedTimeRangesChanged(_));
    EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(24)).Times(4);
    EXPECT_CALL(host_, SetDuration(base::Milliseconds(2768)));
    EXPECT_TRUE(AppendData(bear_span1));
    CheckExpectedRanges("{ [0,2736) }");

    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    EXPECT_TRUE(AppendData(bear_span2.first(4340u)));

    EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(24));
    EXPECT_MEDIA_LOG(TrimmedSpliceOverlap(527000, 524000, 20000));
    EXPECT_TRUE(AppendData(bear_span2.subspan(55290u, 18785u)));
    CheckExpectedRanges("{ [0,2736) }");

    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    EXPECT_TRUE(AppendData(bear_span1.first(4370u)));
    EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(24));
    EXPECT_MEDIA_LOG(TrimmedSpliceOverlap(779000, 759000, 3000));
    EXPECT_TRUE(AppendData(bear_span1.subspan(72737u, 28183u)));
    CheckExpectedRanges("{ [0,2736) }");

    MarkEndOfStream(PIPELINE_OK);
    return true;
  }

  void ShutdownDemuxer() {
    if (demuxer_) {
      demuxer_->Shutdown();
      base::RunLoop().RunUntilIdle();
    }
  }

  void AddSimpleBlock(ClusterBuilder* cb, int track_num, int64_t timecode) {
    uint8_t data[] = {0x00};
    cb->AddSimpleBlock(track_num, timecode, 0, data);
  }

  std::unique_ptr<Cluster> GenerateCluster(int timecode, int block_count) {
    return GenerateCluster(timecode, timecode, block_count);
  }

  std::unique_ptr<Cluster> GenerateCluster(int first_audio_timecode,
                                           int first_video_timecode,
                                           int block_count) {
    return GenerateCluster(first_audio_timecode, first_video_timecode,
                           block_count, false);
  }
  std::unique_ptr<Cluster> GenerateCluster(int first_audio_timecode,
                                           int first_video_timecode,
                                           int block_count,
                                           bool unknown_size) {
    CHECK_GT(block_count, 0);

    std::priority_queue<BlockInfo> block_queue;

    if (block_count == 1) {
      block_queue.push(BlockInfo(kAudioTrackNum,
                                 first_audio_timecode,
                                 kWebMFlagKeyframe,
                                 kAudioBlockDuration));
      return GenerateCluster(block_queue, unknown_size);
    }

    int audio_timecode = first_audio_timecode;
    int video_timecode = first_video_timecode;

    uint8_t video_flag = kWebMFlagKeyframe;
    for (int i = 0; i < block_count - 2; i++) {
      if (audio_timecode <= video_timecode) {
        block_queue.push(BlockInfo(kAudioTrackNum,
                                   audio_timecode,
                                   kWebMFlagKeyframe,
                                   0));
        audio_timecode += kAudioBlockDuration;
        continue;
      }

      block_queue.push(BlockInfo(kVideoTrackNum,
                                 video_timecode,
                                 video_flag,
                                 0));
      video_timecode += kVideoBlockDuration;
      video_flag = 0;
    }

    block_queue.push(BlockInfo(kAudioTrackNum,
                               audio_timecode,
                               kWebMFlagKeyframe,
                               kAudioBlockDuration));
    block_queue.push(BlockInfo(kVideoTrackNum,
                               video_timecode,
                               video_flag,
                               kVideoBlockDuration));

    return GenerateCluster(block_queue, unknown_size);
  }

  std::unique_ptr<Cluster> GenerateSingleStreamCluster(int timecode,
                                                       int end_timecode,
                                                       int track_number,
                                                       int block_duration) {
    CHECK_GT(end_timecode, timecode);

    std::vector<uint8_t> data(block_size_);

    ClusterBuilder cb;
    cb.SetClusterTimecode(timecode);

    while (timecode < (end_timecode - block_duration)) {
      cb.AddSimpleBlock(track_number, timecode, kWebMFlagKeyframe, data);
      timecode += block_duration;
    }

    cb.AddBlockGroup(track_number, timecode, block_duration, kWebMFlagKeyframe,
                     static_cast<bool>(kWebMFlagKeyframe), data);

    return cb.Finish();
  }

  DemuxerStream* GetStream(DemuxerStream::Type type) {
    std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
    for (media::DemuxerStream* stream : streams) {
      if (stream->type() == type)
        return stream;
    }
    return nullptr;
  }

  void Read(uint32_t count,
            DemuxerStream::Type type,
            DemuxerStream::ReadCB read_cb) {
    GetStream(type)->Read(count, std::move(read_cb));
    base::RunLoop().RunUntilIdle();
  }

  void ReadAudio(uint32_t count, DemuxerStream::ReadCB read_cb) {
    Read(count, DemuxerStream::AUDIO, std::move(read_cb));
  }

  void ReadVideo(uint32_t count, DemuxerStream::ReadCB read_cb) {
    Read(count, DemuxerStream::VIDEO, std::move(read_cb));
  }

  void GenerateExpectedReads(int timecode, int block_count) {
    GenerateExpectedReads(timecode, timecode, block_count);
  }

  void GenerateExpectedReads(int start_audio_timecode,
                             int start_video_timecode,
                             int block_count) {
    CHECK_GT(block_count, 0);

    if (block_count == 1) {
      ExpectRead(DemuxerStream::AUDIO, start_audio_timecode);
      return;
    }

    int audio_timecode = start_audio_timecode;
    int video_timecode = start_video_timecode;

    for (int i = 0; i < block_count; i++) {
      if (audio_timecode <= video_timecode) {
        ExpectRead(DemuxerStream::AUDIO, audio_timecode);
        audio_timecode += kAudioBlockDuration;
        continue;
      }

      ExpectRead(DemuxerStream::VIDEO, video_timecode);
      video_timecode += kVideoBlockDuration;
    }
  }

  void GenerateSingleStreamExpectedReads(int timecode,
                                         int block_count,
                                         DemuxerStream::Type type,
                                         int block_duration) {
    CHECK_GT(block_count, 0);
    int stream_timecode = timecode;

    for (int i = 0; i < block_count; i++) {
      ExpectRead(type, stream_timecode);
      stream_timecode += block_duration;
    }
  }

  void GenerateAudioStreamExpectedReads(int timecode, int block_count) {
    GenerateSingleStreamExpectedReads(
        timecode, block_count, DemuxerStream::AUDIO, kAudioBlockDuration);
  }

  void GenerateVideoStreamExpectedReads(int timecode, int block_count) {
    GenerateSingleStreamExpectedReads(
        timecode, block_count, DemuxerStream::VIDEO, kVideoBlockDuration);
  }

  std::unique_ptr<Cluster> GenerateEmptyCluster(int timecode) {
    ClusterBuilder cb;
    cb.SetClusterTimecode(timecode);
    return cb.Finish();
  }

  void CheckExpectedRangesForMediaSource(const std::string& expected) {
    CheckExpectedRanges(demuxer_->GetBufferedRanges(), expected);
  }

  void CheckExpectedRanges(const std::string& expected) {
    CheckExpectedRanges(kSourceId, expected);
    CheckExpectedRangesForMediaSource(expected);
  }

  void CheckExpectedRanges(const std::string& id, const std::string& expected) {
    CheckExpectedRanges(demuxer_->GetBufferedRanges(id), expected);
  }

  void CheckExpectedRanges(DemuxerStream::Type type,
                           const std::string& expected) {
    ChunkDemuxerStream* stream =
        static_cast<ChunkDemuxerStream*>(GetStream(type));
    CheckExpectedRanges(stream->GetBufferedRanges(kDefaultDuration()),
                        expected);
  }

  void CheckExpectedRanges(const Ranges<base::TimeDelta>& r,
                           const std::string& expected) {
    std::stringstream ss;
    ss << "{ ";
    for (size_t i = 0; i < r.size(); ++i) {
      ss << "[" << r.start(i).InMilliseconds() << ","
         << r.end(i).InMilliseconds() << ") ";
    }
    ss << "}";
    EXPECT_EQ(expected, ss.str());
  }

  MOCK_METHOD2(ReadDone,
               void(DemuxerStream::Status status,
                    DemuxerStream::DecoderBufferVector buffers));

  void ReadUntilNotOkOrEndOfStream(DemuxerStream::Type type,
                                   DemuxerStream::Status* status,
                                   base::TimeDelta* last_timestamp) {
    DemuxerStream* stream = GetStream(type);
    DemuxerStream::DecoderBufferVector buffers;

    *last_timestamp = kNoTimestamp;
    do {
      stream->Read(1, base::BindOnce(StoreStatusAndBuffers, status, &buffers));
      EXPECT_LE(buffers.size(), 1u);
      base::RunLoop().RunUntilIdle();
      if (*status == DemuxerStream::kOk && !buffers[0]->end_of_stream())
        *last_timestamp = buffers[0]->timestamp();
    } while (*status == DemuxerStream::kOk && !buffers[0]->end_of_stream());
  }

  void ExpectEndOfStream(DemuxerStream::Type type) {
    EXPECT_CALL(*this, ReadDone(DemuxerStream::kOk, ReadOneAndIsEndOfStream()));
    GetStream(type)->Read(
        1, base::BindOnce(&ParcChunkDemuxerTest::ReadDone, base::Unretained(this)));
    base::RunLoop().RunUntilIdle();
  }

  void ExpectRead(DemuxerStream::Type type, int64_t timestamp_in_ms) {
    EXPECT_CALL(*this, ReadDone(DemuxerStream::kOk,
                                ReadOneAndHasTimestamp(timestamp_in_ms)));
    GetStream(type)->Read(
        1, base::BindOnce(&ParcChunkDemuxerTest::ReadDone, base::Unretained(this)));
    base::RunLoop().RunUntilIdle();
  }

  void ParcStartRead(DemuxerStream::Type type) {
    GetStream(type)->Read(
        1, base::BindOnce(&ParcChunkDemuxerTest::ReadDone, base::Unretained(this)));
  }

  void ExpectConfigChanged(DemuxerStream::Type type) {
    EXPECT_CALL(*this, ReadDone(DemuxerStream::kConfigChanged, _));
    GetStream(type)->Read(
        1, base::BindOnce(&ParcChunkDemuxerTest::ReadDone, base::Unretained(this)));
    base::RunLoop().RunUntilIdle();
  }

  void CheckExpectedBuffers(DemuxerStream* stream,
                            const std::string& expected) {
    std::vector<std::string> timestamps = base::SplitString(
        expected, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL);
    std::stringstream ss;
    for (size_t i = 0; i < timestamps.size(); ++i) {
      DemuxerStream::Status status = DemuxerStream::kAborted;
      DemuxerStream::DecoderBufferVector buffers;
      stream->Read(1, base::BindOnce(StoreStatusAndBuffers, &status, &buffers));
      EXPECT_LE(buffers.size(), 1u);
      base::RunLoop().RunUntilIdle();
      if (status != DemuxerStream::kOk || buffers[0]->end_of_stream())
        break;

      if (i > 0)
        ss << " ";
      ss << buffers[0]->timestamp().InMilliseconds();

      if (buffers[0]->is_key_frame())
        ss << "K";

      if (timestamps[i].ends_with("P")) {
        auto discard_padding = buffers[0]->discard_padding();
        ASSERT_TRUE(discard_padding.has_value());
        ASSERT_EQ(kInfiniteDuration, discard_padding->first);
        ASSERT_EQ(base::TimeDelta(), discard_padding->second);
        ss << "P";
      }
    }
    EXPECT_EQ(expected, ss.str());
  }

  MOCK_METHOD1(Checkpoint, void(int id));

  struct BufferTimestamps {
    int video_time_ms;
    int audio_time_ms;
  };
  static const int kSkip = -1;

  bool ParseWebMFile(const std::string& filename,
                     base::span<const BufferTimestamps> timestamps,
                     const base::TimeDelta& duration) {
    return ParseWebMFile(filename, timestamps, duration, HAS_AUDIO | HAS_VIDEO);
  }

  bool ParseWebMFile(const std::string& filename,
                     base::span<const BufferTimestamps> timestamps,
                     const base::TimeDelta& duration,
                     int stream_flags) {
    EXPECT_CALL(*this, DemuxerOpened());
    demuxer_->Initialize(&host_, CreateInitDoneCallback(duration, PIPELINE_OK));

    if (AddId(kSourceId, stream_flags) != ChunkDemuxer::kOk)
      return false;

    scoped_refptr<DecoderBuffer> buffer = ReadTestDataFile(filename);
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));

    EXPECT_TRUE(AppendDataInPieces(base::span(*buffer), 512));

    for (size_t i = 0;
         (timestamps[i].audio_time_ms != kSkip ||
          timestamps[i].video_time_ms != kSkip);
         i++) {
      bool audio_read_done = false;
      bool video_read_done = false;

      if (timestamps[i].audio_time_ms != kSkip) {
        ReadAudio(
            1, base::BindOnce(&OnReadDone_Ok,
                              base::Milliseconds(timestamps[i].audio_time_ms),
                              kAudioBlockDuration, 1, &audio_read_done));
        EXPECT_TRUE(audio_read_done);
      }

      if (timestamps[i].video_time_ms != kSkip) {
        ReadVideo(
            1, base::BindOnce(&OnReadDone_Ok,
                              base::Milliseconds(timestamps[i].video_time_ms),
                              kVideoBlockDuration, 1, &video_read_done));
        EXPECT_TRUE(video_read_done);
      }
    }

    return true;
  }

  MOCK_METHOD0(DemuxerOpened, void());
  MOCK_METHOD2(OnEncryptedMediaInitData,
               void(EmeInitDataType init_data_type,
                    const std::vector<uint8_t>& init_data));

  MOCK_METHOD1(InitSegmentReceivedMock, void(std::unique_ptr<MediaTracks>&));
  MOCK_METHOD1(OnParseWarningMock, void(const SourceBufferParseWarning));

  void OnProgress() { did_progress_ = true; }

  bool DidProgress() {
    bool result = did_progress_;
    did_progress_ = false;
    return result;
  }

  void Seek(base::TimeDelta seek_time) {
    demuxer_->StartWaitingForSeek(seek_time);
    demuxer_->Seek(seek_time, NewExpectedStatusCB(PIPELINE_OK));
    base::RunLoop().RunUntilIdle();
  }

  void MarkEndOfStream(PipelineStatus status) {
    demuxer_->MarkEndOfStream(status);
    base::RunLoop().RunUntilIdle();
  }

  bool SetTimestampOffset(const std::string& id,
                          base::TimeDelta timestamp_offset) {
    if (demuxer_->IsParsingMediaSegment(id))
      return false;

    timestamp_offset_map_[id] = timestamp_offset;
    return true;
  }

  base::test::TaskEnvironment task_environment_;

  StrictMock<MockMediaLog> media_log_;

  MockDemuxerHost host_;

  std::unique_ptr<ChunkDemuxer> demuxer_;
  Demuxer::MediaTracksUpdatedCB init_segment_received_cb_;

  bool did_progress_;

  base::TimeDelta append_window_start_for_next_append_;
  base::TimeDelta append_window_end_for_next_append_;

  size_t block_size_ = kBlockSize;

  std::map<std::string, base::TimeDelta> timestamp_offset_map_;

 public:
  void InitSegmentReceived(std::unique_ptr<MediaTracks> tracks) {
    DCHECK(tracks.get());
    DCHECK_GT(tracks->tracks().size(), 0u);

    std::set<MediaTrack::Id> track_ids;
    for (const auto& track : tracks->tracks()) {
      EXPECT_EQ(track_ids.end(), track_ids.find(track->track_id()));
      track_ids.insert(track->track_id());
    }

    InitSegmentReceivedMock(tracks);
  }
};






















TEST_F(ParcChunkDemuxerTest, ParcAddIdAfterInitialization) {
  std::vector<PipelineMetadata> added;
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<PipelineMetadata>* added, const PipelineMetadata& metadata,
         const std::vector<ChunkDemuxer::ParcAddedTrack>&) {
        added->push_back(metadata);
      },
      &added));
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, 0, 4);
  CheckExpectedRangesForMediaSource("{ [0,132) }");

  ASSERT_EQ(AddId("audio", HAS_AUDIO), ChunkDemuxer::kOk);
  CheckExpectedRangesForMediaSource("{ [0,132) }");
  EXPECT_EQ(demuxer_->GetAllStreams().size(), 1u);

  ExpectInitMediaLogs(HAS_AUDIO);
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  ASSERT_TRUE(AppendInitSegmentWithSourceId("audio", HAS_AUDIO));
  ASSERT_EQ(added.size(), 1u);
  EXPECT_TRUE(added[0].has_audio);
  EXPECT_FALSE(added[0].has_video);
  EXPECT_EQ(added[0].audio_decoder_config.codec(), AudioCodec::kVorbis);
  EXPECT_EQ(demuxer_->GetAllStreams().size(), 2u);
  ChunkDemuxerStream* audio_stream =
      static_cast<ChunkDemuxerStream*>(GetStream(DemuxerStream::AUDIO));
  ASSERT_TRUE(audio_stream);
  EXPECT_TRUE(audio_stream->IsEnabled());
  CheckExpectedRangesForMediaSource("{ }");

  AppendSingleStreamCluster("audio", kAudioTrackNum, 0, 4);
  CheckExpectedRangesForMediaSource("{ [0,92) }");

  CheckExpectedBuffers(audio_stream, "0K 23K 46K 69K");
}

TEST_F(ParcChunkDemuxerTest, ParcAddIdReplacingRemovedSourceBuffer) {
  std::vector<PipelineMetadata> added;
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<PipelineMetadata>* added, const PipelineMetadata& metadata,
         const std::vector<ChunkDemuxer::ParcAddedTrack>&) {
        added->push_back(metadata);
      },
      &added));
  ASSERT_TRUE(InitDemuxerAudioAndVideoSources("audio", "video"));
  demuxer_->RemoveId("audio");

  ASSERT_EQ(AddId("audio2", HAS_AUDIO), ChunkDemuxer::kOk);
  ExpectInitMediaLogs(HAS_AUDIO);
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  ASSERT_TRUE(AppendInitSegmentWithSourceId("audio2", HAS_AUDIO));
  ASSERT_EQ(added.size(), 1u);
  EXPECT_TRUE(added[0].has_audio);
  EXPECT_FALSE(added[0].has_video);
}

TEST_F(ParcChunkDemuxerTest, ParcAddIdAfterInitializationSecondAudio) {
  std::vector<PipelineMetadata> added;
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<PipelineMetadata>* added, const PipelineMetadata& metadata,
         const std::vector<ChunkDemuxer::ParcAddedTrack>&) {
        added->push_back(metadata);
      },
      &added));
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum, 0, 4);

  ASSERT_EQ(AddId("audio2", HAS_AUDIO), ChunkDemuxer::kOk);
  ExpectInitMediaLogs(HAS_AUDIO);
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  ASSERT_TRUE(AppendInitSegmentWithSourceId("audio2", HAS_AUDIO));
  EXPECT_TRUE(added.empty());
  std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
  ASSERT_EQ(streams.size(), 2u);
  ChunkDemuxerStream* second = static_cast<ChunkDemuxerStream*>(streams[1].get());
  EXPECT_FALSE(second->IsEnabled());
  CheckExpectedRangesForMediaSource("{ }");

  AppendSingleStreamCluster("audio2", kAudioTrackNum, 0, 2);
  CheckExpectedRangesForMediaSource("{ [0,46) }");

  DemuxerStream* enabled = nullptr;
  demuxer_->OnTracksChanged(
      DemuxerStream::AUDIO, second->media_track_id(), base::TimeDelta(),
      base::BindOnce([](DemuxerStream** out,
                        DemuxerStream* stream) { *out = stream; },
                     &enabled));
  EXPECT_EQ(enabled, second);
  CheckExpectedBuffers(second, "0K 23K");
}

TEST_F(ParcChunkDemuxerTest, ParcLateStreamStartsAtItsTrackChange) {
  std::vector<std::vector<ChunkDemuxer::ParcAddedTrack>> reported;
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<std::vector<ChunkDemuxer::ParcAddedTrack>>* reported,
         const PipelineMetadata&,
         const std::vector<ChunkDemuxer::ParcAddedTrack>& tracks) {
        reported->push_back(tracks);
      },
      &reported));
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, 0, 4);

  ASSERT_EQ(AddId("audio", HAS_AUDIO), ChunkDemuxer::kOk);
  ExpectInitMediaLogs(HAS_AUDIO);
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  ASSERT_TRUE(AppendInitSegmentWithSourceId("audio", HAS_AUDIO));
  AppendSingleStreamCluster("audio", kAudioTrackNum, 0, 4);
  ASSERT_EQ(reported.size(), 1u);
  ASSERT_EQ(reported[0].size(), 1u);
  EXPECT_EQ(reported[0][0].type, DemuxerStream::AUDIO);

  DemuxerStream* enabled = nullptr;
  demuxer_->OnTracksChanged(
      DemuxerStream::AUDIO, reported[0][0].id, base::Milliseconds(46),
      base::BindOnce([](DemuxerStream** out,
                        DemuxerStream* stream) { *out = stream; },
                     &enabled));
  ASSERT_EQ(enabled, GetStream(DemuxerStream::AUDIO));
  CheckExpectedBuffers(enabled, "46K 69K");
}

TEST_F(ParcChunkDemuxerTest, ParcHandOffSplitsAtAVideoKeyframe) {
  ShutdownDemuxer();
  CreateNewDemuxer();
  demuxer_->ParcSetSafariMediaSource(true);
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  DemuxerStream* audio = GetStream(DemuxerStream::AUDIO);
  DemuxerStream* video = GetStream(DemuxerStream::VIDEO);
  AppendMuxedCluster(
      MuxedStreamInfo(kAudioTrackNum, "0K 23K 46K 69K 92K 115K", 23),
      MuxedStreamInfo(kVideoTrackNum, "0K 30 60K 90 120K", 30));
  CheckExpectedBuffers(audio, "0K");
  CheckExpectedBuffers(video, "0K");

  MediaResource* handoff = demuxer_->GetParcExtension()->ParcBeginHandOff();
  ASSERT_TRUE(handoff);
  DemuxerStream* incoming_audio = nullptr;
  DemuxerStream* incoming_video = nullptr;
  for (DemuxerStream* stream : handoff->GetAllStreams()) {
    (stream->type() == DemuxerStream::AUDIO ? incoming_audio : incoming_video) =
        stream;
  }
  ASSERT_TRUE(incoming_audio && incoming_video);
  EXPECT_EQ(ParcStreamHandOffSource(incoming_audio), audio);
  EXPECT_EQ(ParcStreamHandOffSource(incoming_video), video);

  base::TimeDelta split = kNoTimestamp;
  demuxer_->GetParcExtension()->ParcSplitForHandOff(
      base::Milliseconds(40),
      base::BindOnce([](base::TimeDelta* out, base::TimeDelta time) { *out = time; },
                     &split));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, base::Milliseconds(60));
  CheckExpectedBuffers(audio, "23K 46K");
  ExpectEndOfStream(DemuxerStream::AUDIO);
  CheckExpectedBuffers(video, "30");
  ExpectEndOfStream(DemuxerStream::VIDEO);
  CheckExpectedBuffers(incoming_audio, "69K 92K 115K");
  CheckExpectedBuffers(incoming_video, "60K 90 120K");

  demuxer_->GetParcExtension()->ParcEndHandOff();
}

TEST_F(ParcChunkDemuxerTest, ParcHandOffSplitWaitsForItsKeyframe) {
  ShutdownDemuxer();
  CreateNewDemuxer();
  demuxer_->ParcSetSafariMediaSource(true);
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  DemuxerStream* video = GetStream(DemuxerStream::VIDEO);
  EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(30)).Times(2);
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, "0K 30");
  ASSERT_TRUE(demuxer_->GetParcExtension()->ParcBeginHandOff());
  base::TimeDelta split = kNoTimestamp;
  demuxer_->GetParcExtension()->ParcSplitForHandOff(
      base::Milliseconds(40),
      base::BindOnce([](base::TimeDelta* out, base::TimeDelta time) { *out = time; },
                     &split));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, kNoTimestamp);
  CheckExpectedBuffers(video, "0K 30");

  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, "60 90K 120");
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, base::Milliseconds(90));
  CheckExpectedBuffers(video, "60");
  ExpectEndOfStream(DemuxerStream::VIDEO);

  demuxer_->GetParcExtension()->ParcEndHandOff();
}

TEST_F(ParcChunkDemuxerTest, ParcHandOffEndedBeforeItsSplitGivesBuffersBack) {
  ShutdownDemuxer();
  CreateNewDemuxer();
  demuxer_->ParcSetSafariMediaSource(true);
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  DemuxerStream* video = GetStream(DemuxerStream::VIDEO);
  EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(30)).Times(2);
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, "0K 30 60");
  CheckExpectedBuffers(video, "0K");
  ASSERT_TRUE(demuxer_->GetParcExtension()->ParcBeginHandOff());
  demuxer_->GetParcExtension()->ParcSplitForHandOff(base::Milliseconds(40), base::DoNothing());
  base::RunLoop().RunUntilIdle();

  demuxer_->GetParcExtension()->ParcEndHandOff();
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, "90 120K");
  CheckExpectedBuffers(video, "30 60 90 120K");
}

TEST_F(ParcChunkDemuxerTest, ParcHandOffSplitAtTheEndOfStream) {
  ShutdownDemuxer();
  CreateNewDemuxer();
  demuxer_->ParcSetSafariMediaSource(true);
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  DemuxerStream* video = GetStream(DemuxerStream::VIDEO);
  EXPECT_MEDIA_LOG(WebMSimpleBlockDurationEstimated(30));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, "0K 30");
  ASSERT_TRUE(demuxer_->GetParcExtension()->ParcBeginHandOff());
  base::TimeDelta split = kNoTimestamp;
  demuxer_->GetParcExtension()->ParcSplitForHandOff(
      base::Milliseconds(40),
      base::BindOnce([](base::TimeDelta* out, base::TimeDelta time) { *out = time; },
                     &split));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, kNoTimestamp);

  MarkEndOfStream(PIPELINE_OK);
  EXPECT_EQ(split, base::Milliseconds(60));
  CheckExpectedBuffers(video, "0K 30");
  ExpectEndOfStream(DemuxerStream::VIDEO);

  demuxer_->GetParcExtension()->ParcEndHandOff();
}

TEST_F(ParcChunkDemuxerTest, ParcHandOffSplitWaitsForASeek) {
  ShutdownDemuxer();
  CreateNewDemuxer();
  demuxer_->ParcSetSafariMediaSource(true);
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  AppendMuxedCluster(
      MuxedStreamInfo(kAudioTrackNum, "0K 23K 46K 69K 92K 115K 138K", 23),
      MuxedStreamInfo(kVideoTrackNum, "0K 30 60K 90 120K 150", 30));
  MediaResource* handoff = demuxer_->GetParcExtension()->ParcBeginHandOff();
  ASSERT_TRUE(handoff);
  DemuxerStream* incoming_audio = nullptr;
  DemuxerStream* incoming_video = nullptr;
  for (DemuxerStream* stream : handoff->GetAllStreams()) {
    (stream->type() == DemuxerStream::AUDIO ? incoming_audio : incoming_video) =
        stream;
  }
  ASSERT_TRUE(incoming_audio && incoming_video);

  demuxer_->StartWaitingForSeek(base::Milliseconds(60));
  base::TimeDelta split = kNoTimestamp;
  demuxer_->GetParcExtension()->ParcSplitForHandOff(
      base::TimeDelta(),
      base::BindOnce([](base::TimeDelta* out, base::TimeDelta time) { *out = time; },
                     &split));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, kNoTimestamp);

  demuxer_->Seek(base::Milliseconds(60), NewExpectedStatusCB(PIPELINE_OK));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(split, base::Milliseconds(60));
  CheckExpectedBuffers(GetStream(DemuxerStream::AUDIO), "46K");
  ExpectEndOfStream(DemuxerStream::AUDIO);
  ExpectEndOfStream(DemuxerStream::VIDEO);
  CheckExpectedBuffers(incoming_audio, "69K 92K 115K 138K");
  CheckExpectedBuffers(incoming_video, "60K 90 120K 150");

  demuxer_->GetParcExtension()->ParcEndHandOff();
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEachSourceBufferEnablesItsAudio) {
  for (bool safari : {false, true}) {
    SCOPED_TRACE(safari ? "Safari's identity" : "Chrome's");
    if (safari) {
      ShutdownDemuxer();
      CreateNewDemuxer();
    }
    demuxer_->ParcSetSafariMediaSource(safari);
    EXPECT_CALL(*this, DemuxerOpened());
    demuxer_->Initialize(
        &host_, CreateInitDoneCallback(kDefaultDuration(), PIPELINE_OK));
    ASSERT_EQ(AddId("audio1", HAS_AUDIO), ChunkDemuxer::kOk);
    ASSERT_EQ(AddId("audio2", HAS_AUDIO), ChunkDemuxer::kOk);
    for (const char* id : {"audio1", "audio2"}) {
      ExpectInitMediaLogs(HAS_AUDIO);
      EXPECT_CALL(*this, InitSegmentReceivedMock(_));
      ASSERT_TRUE(AppendInitSegmentWithSourceId(id, HAS_AUDIO));
    }
    std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
    ASSERT_EQ(streams.size(), 2u);
    EXPECT_TRUE(static_cast<ChunkDemuxerStream*>(streams[0].get())->IsEnabled());
    EXPECT_EQ(static_cast<ChunkDemuxerStream*>(streams[1].get())->IsEnabled(),
              safari);
    EXPECT_EQ(ParcStreamIsEnabled(streams[1]), safari);
  }
}

TEST_F(ParcChunkDemuxerTest, ParcSafariLateSecondAudioMixes) {
  std::vector<PipelineMetadata> added;
  std::vector<ChunkDemuxer::ParcAddedTrack> tracks;
  demuxer_->ParcSetSafariMediaSource(true);
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<PipelineMetadata>* added,
         std::vector<ChunkDemuxer::ParcAddedTrack>* tracks,
         const PipelineMetadata& metadata,
         const std::vector<ChunkDemuxer::ParcAddedTrack>& reported) {
        added->push_back(metadata);
        *tracks = reported;
      },
      &added, &tracks));
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum, 0, 4);

  ASSERT_EQ(AddId("audio2", HAS_AUDIO), ChunkDemuxer::kOk);
  ExpectInitMediaLogs(HAS_AUDIO);
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  ASSERT_TRUE(AppendInitSegmentWithSourceId("audio2", HAS_AUDIO));
  AppendSingleStreamCluster("audio2", kAudioTrackNum, 0, 4);
  ASSERT_EQ(added.size(), 1u);
  EXPECT_FALSE(added[0].has_audio);
  ASSERT_EQ(tracks.size(), 1u);

  std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
  ASSERT_EQ(streams.size(), 2u);
  auto* first = static_cast<ChunkDemuxerStream*>(streams[0].get());
  auto* second = static_cast<ChunkDemuxerStream*>(streams[1].get());
  ASSERT_EQ(second->media_track_id(), tracks[0].id);
  EXPECT_TRUE(second->IsEnabled());

  DemuxerStream* enabled = nullptr;
  demuxer_->OnTracksChanged(
      DemuxerStream::AUDIO, tracks[0].id, base::Milliseconds(23),
      base::BindOnce([](DemuxerStream** out,
                        DemuxerStream* stream) { *out = stream; },
                     &enabled));
  EXPECT_EQ(enabled, first);
  EXPECT_TRUE(first->IsEnabled());
  EXPECT_TRUE(second->IsEnabled());
  CheckExpectedBuffers(second, "23K 46K 69K");
}

TEST_F(ParcChunkDemuxerTest, ParcCoalescedJoinsStartEveryTrack) {
  std::vector<MediaTrack::Id> ids;
  demuxer_->ParcSetSafariMediaSource(true);
  demuxer_->ParcAllowSourceBuffersAfterInit(base::BindRepeating(
      [](std::vector<MediaTrack::Id>* ids, const PipelineMetadata&,
         const std::vector<ChunkDemuxer::ParcAddedTrack>& tracks) {
        for (const ChunkDemuxer::ParcAddedTrack& track : tracks) {
          ids->push_back(track.id);
        }
      },
      &ids));
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum, 0, 4);
  for (const char* id : {"audio1", "audio2"}) {
    ASSERT_EQ(AddId(id, HAS_AUDIO), ChunkDemuxer::kOk);
    ExpectInitMediaLogs(HAS_AUDIO);
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    ASSERT_TRUE(AppendInitSegmentWithSourceId(id, HAS_AUDIO));
    AppendSingleStreamCluster(id, kAudioTrackNum, 0, 4);
  }
  ASSERT_EQ(ids.size(), 2u);

  demuxer_->OnTracksChanged(DemuxerStream::AUDIO, ids[1],
                            base::Milliseconds(46), base::DoNothing());
  std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
  ASSERT_EQ(streams.size(), 3u);
  std::vector<ChunkDemuxerStream*> audio;
  for (DemuxerStream* stream : streams) {
    EXPECT_TRUE(static_cast<ChunkDemuxerStream*>(stream)->IsEnabled());
    if (stream->type() == DemuxerStream::AUDIO) {
      audio.push_back(static_cast<ChunkDemuxerStream*>(stream));
      CheckExpectedBuffers(stream, "46K 69K");
    }
  }
  ASSERT_EQ(audio.size(), 2u);

  demuxer_->ParcSetEnabledAudioTracks({ids[0]});
  demuxer_->OnTracksChanged(DemuxerStream::AUDIO, ids[0],
                            base::Milliseconds(92), base::DoNothing());
  for (ChunkDemuxerStream* stream : audio) {
    EXPECT_EQ(stream->IsEnabled(), stream->media_track_id() == ids[0]);
  }
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEnablesTheElementsAudioTracks) {
  for (bool safari : {false, true}) {
    SCOPED_TRACE(safari ? "Safari's identity" : "Chrome's");
    if (safari) {
      ShutdownDemuxer();
      CreateNewDemuxer();
    }
    demuxer_->ParcSetSafariMediaSource(safari);
    EXPECT_CALL(*this, DemuxerOpened());
    demuxer_->Initialize(
        &host_, CreateInitDoneCallback(kDefaultDuration(), PIPELINE_OK));
    for (const char* id : {"audio1", "audio2"}) {
      ASSERT_EQ(AddId(id, HAS_AUDIO), ChunkDemuxer::kOk);
    }
    for (const char* id : {"audio1", "audio2"}) {
      ExpectInitMediaLogs(HAS_AUDIO);
      EXPECT_CALL(*this, InitSegmentReceivedMock(_));
      ASSERT_TRUE(AppendInitSegmentWithSourceId(id, HAS_AUDIO));
      AppendSingleStreamCluster(id, kAudioTrackNum, 0, 4);
    }
    std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
    ASSERT_EQ(streams.size(), 2u);
    auto* first = static_cast<ChunkDemuxerStream*>(streams[0].get());
    auto* second = static_cast<ChunkDemuxerStream*>(streams[1].get());
    const MediaTrack::Id first_id = first->media_track_id();
    const MediaTrack::Id second_id = second->media_track_id();
    DemuxerStream* enabled = nullptr;
    auto change = [&](const MediaTrack::Id& named, base::TimeDelta time) {
      demuxer_->OnTracksChanged(
          DemuxerStream::AUDIO, named, time,
          base::BindOnce([](DemuxerStream** out,
                            DemuxerStream* stream) { *out = stream; },
                         &enabled));
    };

    demuxer_->ParcSetEnabledAudioTracks({second_id});
    demuxer_->ParcSetEnabledAudioTracks({first_id});
    change(first_id, base::Milliseconds(23));
    EXPECT_EQ(enabled, first);
    EXPECT_TRUE(first->IsEnabled());
    EXPECT_FALSE(second->IsEnabled());

    demuxer_->ParcSetEnabledAudioTracks({second_id});
    change(second_id, base::Milliseconds(23));
    EXPECT_EQ(enabled, second);
    EXPECT_FALSE(first->IsEnabled());
    EXPECT_TRUE(second->IsEnabled());

    change(first_id, base::Milliseconds(46));
    EXPECT_EQ(enabled, safari ? second : first);
    EXPECT_EQ(first->IsEnabled(), !safari);
    EXPECT_EQ(second->IsEnabled(), safari);

    if (safari) {
      demuxer_->ParcSetEnabledAudioTracks({first_id, second_id});
      change(second_id, base::Milliseconds(69));
      EXPECT_EQ(enabled, first);
      EXPECT_TRUE(first->IsEnabled());
      EXPECT_TRUE(second->IsEnabled());
      CheckExpectedBuffers(first, "69K");
    }
  }
}

TEST_F(ParcChunkDemuxerTest, ParcSourceKeyRemovalRetainsBufferIdentity) {
  ASSERT_TRUE(InitDemuxerAudioAndVideoSources("audio", "video"));
  std::vector<std::string> removed;
  demuxer_->ParcSetSourceKeyCallback(base::BindRepeating(
      [](std::vector<std::string>* removed, const std::string& id,
         EmeInitDataType, const std::vector<uint8_t>& data) {
        EXPECT_TRUE(data.empty());
        removed->push_back(id);
      }, &removed));
  demuxer_->RemoveId("audio");
  EXPECT_EQ((std::vector<std::string>{"audio"}), removed);
  demuxer_->RemoveId("video");
  EXPECT_EQ((std::vector<std::string>{"audio", "video"}), removed);
}













TEST_F(ParcChunkDemuxerTest, ParcTypesWithoutCodecsNeedSafariIdentity) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));

  for (const char* type :
       {"video/webm", "audio/webm", "video/mp4", "audio/mp4", "video/mp2t"}) {
    EXPECT_EQ(AddId(kSourceId, type, ""), ChunkDemuxer::kNotSupported)
        << type;
  }
  ASSERT_EQ(AddId(kSourceId, "video/webm", "vorbis,vp8"), ChunkDemuxer::kOk);
  EXPECT_FALSE(demuxer_->CanChangeType(kSourceId, "video/mp4", ""));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariIdentityAddsTypesWithoutCodecs) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));

  std::vector<std::string> types = {"video/webm", "audio/webm", "video/mp4",
                                    "audio/mp4"};
#if BUILDFLAG(USE_PROPRIETARY_CODECS) && \
    BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
  types.push_back("video/mp2t");
#endif
  for (const std::string& type : types) {
    ChunkDemuxer::Status result = AddId(kSourceId, type, "");
    EXPECT_EQ(result, ChunkDemuxer::kOk) << type;
    if (result == ChunkDemuxer::kOk) {
      demuxer_->RemoveId(kSourceId);
    }
  }
  EXPECT_EQ(AddId(kSourceId, "video/x-unknown", ""),
            ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "video/webm", "bogus"),
            ChunkDemuxer::kNotSupported);
}

TEST_F(ParcChunkDemuxerTest, ParcTypeWithoutCodecsTakesTheStreamsCodecs) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  EXPECT_CALL(host_, SetDuration(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  EXPECT_CALL(*this, DemuxerOpened());
  demuxer_->Initialize(&host_, CreateInitDoneCallback(PIPELINE_OK));
  ASSERT_EQ(AddId(kSourceId, "video/webm", ""), ChunkDemuxer::kOk);

  scoped_refptr<DecoderBuffer> webm = ReadTestDataFile("bear-320x240.webm");
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  EXPECT_TRUE(AppendData(kSourceId, base::span(*webm)));
  EXPECT_TRUE(GetStream(DemuxerStream::AUDIO));
  EXPECT_TRUE(GetStream(DemuxerStream::VIDEO));

#if BUILDFLAG(USE_PROPRIETARY_CODECS)
  ASSERT_TRUE(demuxer_->CanChangeType(kSourceId, "video/mp4", ""));
  demuxer_->ResetParserState(kSourceId, append_window_start_for_next_append_,
                             append_window_end_for_next_append_,
                             &timestamp_offset_map_[kSourceId]);
  demuxer_->ChangeType(kSourceId, "video/mp4", "");
  scoped_refptr<DecoderBuffer> mp4 =
      ReadTestDataFile("bear-640x360-av_frag.mp4");
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  EXPECT_TRUE(AppendData(kSourceId, base::span(*mp4)));
#endif
}

TEST_F(ParcChunkDemuxerTest, ParcPCMNeedsSafariRules) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->Initialize(&host_,
      base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized, base::Unretained(this)));
  for (bool safari : {false, true}) {
    demuxer_->ParcSetSafariInitSegmentRules(safari);
    for (const char* codec : {"ipcm", "fpcm", "ipcm.16", "fpcm.abc"}) {
      EXPECT_EQ(AddId(kSourceId, "audio/mp4", codec),
                safari ? ChunkDemuxer::kOk : ChunkDemuxer::kNotSupported);
      if (safari)
        demuxer_->RemoveId(kSourceId);
    }
  }
}

TEST_F(ParcChunkDemuxerTest, ParcSafariContainerTypesNeedSafariRules) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));

  EXPECT_EQ(AddId(kSourceId, "video/quicktime", ""),
            ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "audio/x-m4a", "opus"),
            ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "audio/mp4", "vp09.00.10.08"),
            ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "audio/x-mpeg", ""), ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "video/mp4", "samr"), ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "video/mp4", "s263"), ChunkDemuxer::kNotSupported);
  EXPECT_EQ(AddId(kSourceId, "audio/ogg", "opus"),
            ChunkDemuxer::kNotSupported);
  ASSERT_EQ(AddId(kSourceId, "audio/webm", "opus"), ChunkDemuxer::kOk);
  EXPECT_FALSE(demuxer_->CanChangeType(kSourceId, "audio/ogg", "opus"));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariRulesTakeSafariContainerTypes) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));

  struct {
    const char* type;
    const char* codecs;
    ChunkDemuxer::Status status;
  } kCases[] = {
      {"video/quicktime", "", ChunkDemuxer::kOk},
      {"Video/QuickTime", "", ChunkDemuxer::kOk},
      {"application/mp4", "", ChunkDemuxer::kOk},
      {"audio/x-m4a", "", ChunkDemuxer::kOk},
      {"audio/x-m4a", "opus", ChunkDemuxer::kOk},
      {"audio/mp4", "vp09.00.10.08", ChunkDemuxer::kOk},
      {"video/x-m4v", "", ChunkDemuxer::kOk},
      {"audio/3gpp", "", ChunkDemuxer::kOk},
      {"video/3gpp2", "", ChunkDemuxer::kOk},
      {"audio/mp3", "", ChunkDemuxer::kOk},
      {"audio/x-mpeg", "mp3", ChunkDemuxer::kOk},
      {"audio/mpeg", "mp3", ChunkDemuxer::kOk},
      {"audio/mpeg", "mp4a.6B", ChunkDemuxer::kNotSupported},
      {"video/3gpp", "s263,samr", ChunkDemuxer::kOk},
      {"audio/3gpp", "sawb", ChunkDemuxer::kOk},
      {"video/quicktime", "samr", ChunkDemuxer::kOk},
      {"video/quicktime", "s263", ChunkDemuxer::kNotSupported},
      {"audio/x-quicktime", "s263.1", ChunkDemuxer::kNotSupported},
      {"video/3gpp", "SAMR", ChunkDemuxer::kNotSupported},
      {"audio/mpeg", "samr", ChunkDemuxer::kNotSupported},
      {"audio/ogg", "", ChunkDemuxer::kOk},
      {"audio/ogg", "opus", ChunkDemuxer::kOk},
      {"audio/ogg", "vorbis,flac", ChunkDemuxer::kOk},
      {"application/ogg", "", ChunkDemuxer::kOk},
      {"audio/ogg", "Opus", ChunkDemuxer::kNotSupported},
      {"audio/ogg", "speex", ChunkDemuxer::kNotSupported},
      {"application/ogg", "opus", ChunkDemuxer::kNotSupported},
      {"video/ogg", "", ChunkDemuxer::kNotSupported},
      {"text/vtt", "", ChunkDemuxer::kNotSupported},
#if BUILDFLAG(USE_PROPRIETARY_CODECS)
      {"audio/aacp", "", ChunkDemuxer::kOk},
      {"audio/aac", "mp4a.40.2", ChunkDemuxer::kOk},
      {"audio/aacp", "mp4a.40.2", ChunkDemuxer::kNotSupported},
#endif
#if BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || BUILDFLAG(ENABLE_IAMF_TOOLS)
      {"audio/mp4", "iamf.001.001.Opus", ChunkDemuxer::kNotSupported},
      {"video/mp4", "avc1.640028,iamf", ChunkDemuxer::kNotSupported},
#endif
#if BUILDFLAG(USE_PROPRIETARY_CODECS)
      {"video/mp4", "s263.1,mp4a.40.2", ChunkDemuxer::kOk},
#endif
  };
  for (const auto& test_case : kCases) {
    ChunkDemuxer::Status result =
        AddId(kSourceId, test_case.type, test_case.codecs);
    EXPECT_EQ(result, test_case.status)
        << test_case.type << "; codecs=" << test_case.codecs;
    if (result == ChunkDemuxer::kOk) {
      demuxer_->RemoveId(kSourceId);
    }
  }
}

TEST_F(ParcChunkDemuxerTest, ParcSafariAudioContainerTypeTakesMp4Video) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  EXPECT_CALL(host_, SetDuration(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  EXPECT_CALL(*this, DemuxerOpened());
  demuxer_->Initialize(&host_, CreateInitDoneCallback(PIPELINE_OK));
  ASSERT_EQ(AddId(kSourceId, "audio/x-m4a", ""), ChunkDemuxer::kOk);

  scoped_refptr<DecoderBuffer> mp4 =
      ReadTestDataFile("bear-320x240-v_frag-vp9.mp4");
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  EXPECT_TRUE(AppendData(kSourceId, base::span(*mp4)));
  EXPECT_TRUE(GetStream(DemuxerStream::VIDEO));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariOggBuffers) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  EXPECT_CALL(host_, SetDuration(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  EXPECT_CALL(*this, DemuxerOpened());
  demuxer_->Initialize(&host_, CreateInitDoneCallback(PIPELINE_OK));
  ASSERT_EQ(AddId(kSourceId, "audio/ogg", "opus"), ChunkDemuxer::kOk);

  scoped_refptr<DecoderBuffer> ogg = ReadTestDataFile("sfx-opus.ogg");
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  EXPECT_TRUE(AppendData(kSourceId, base::span(*ogg)));
  ASSERT_TRUE(GetStream(DemuxerStream::AUDIO));
  EXPECT_EQ(GetStream(DemuxerStream::AUDIO)->audio_decoder_config().codec(),
            AudioCodec::kOpus);
  CheckExpectedRanges("{ [0,300) }");

  ASSERT_TRUE(demuxer_->CanChangeType(kSourceId, "audio/ogg", "vorbis"));
  demuxer_->ResetParserState(kSourceId, append_window_start_for_next_append_,
                             append_window_end_for_next_append_,
                             &timestamp_offset_map_[kSourceId]);
  demuxer_->ChangeType(kSourceId, "audio/ogg", "vorbis");
  scoped_refptr<DecoderBuffer> vorbis = ReadTestDataFile("sfx.ogg");
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  EXPECT_TRUE(AppendData(kSourceId, base::span(*vorbis)));
  CheckExpectedRanges("{ [0,364) }");
  EXPECT_FALSE(demuxer_->CanChangeType(kSourceId, "video/ogg", ""));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariChangeTypeFilterSeesTheParserType) {
  EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
  demuxer_->ParcSetSafariInitSegmentRules(true);
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));
  ASSERT_EQ(AddId(kSourceId, "video/webm", "vp8"), ChunkDemuxer::kOk);

  std::vector<std::pair<std::string, std::string>> filtered;
  demuxer_->RestrictCanChangeType(base::BindLambdaForTesting(
      [&filtered](const std::string& content_type, const std::string& codecs) {
        filtered.emplace_back(content_type, codecs);
        return true;
      }));
  EXPECT_TRUE(demuxer_->CanChangeType(kSourceId, "audio/x-m4a", "opus"));
  EXPECT_TRUE(demuxer_->CanChangeType(kSourceId, "audio/x-mpeg", "mp3"));
  EXPECT_THAT(filtered, testing::ElementsAre(testing::Pair("video/mp4", "opus"),
                                             testing::Pair("audio/mpeg", "")));
}

#if (BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || BUILDFLAG(ENABLE_IAMF_TOOLS)) && \
    BUILDFLAG(USE_PROPRIETARY_CODECS)
class ParcChunkDemuxerIamfTest : public ParcChunkDemuxerTest {
 protected:
  void AppendIamfAndH264(bool safari, const std::string& codecs) {
    EXPECT_CALL(media_log_, DoAddLogRecordLogString(_)).Times(AnyNumber());
    EXPECT_CALL(host_, SetDuration(_)).Times(AnyNumber());
    demuxer_->ParcSetSafariInitSegmentRules(safari);
    EXPECT_CALL(*this, DemuxerOpened());
    demuxer_->Initialize(&host_, CreateInitDoneCallback(PIPELINE_OK));
    ASSERT_EQ(AddId(kSourceId, "video/mp4", codecs), ChunkDemuxer::kOk);

    scoped_refptr<DecoderBuffer> mp4 =
        ReadTestDataFile("iamf_alternating_sine_waves_stereo.mp4");
    EXPECT_CALL(*this, InitSegmentReceivedMock(_));
    EXPECT_TRUE(AppendData(kSourceId, base::span(*mp4)));
    EXPECT_TRUE(GetStream(DemuxerStream::VIDEO));
  }
};

TEST_F(ParcChunkDemuxerIamfTest, IamfTrackPlaysOutsideSafariRules) {
  ASSERT_NO_FATAL_FAILURE(
      AppendIamfAndH264(/*safari=*/false, "avc1.640028,iamf"));
  EXPECT_TRUE(GetStream(DemuxerStream::AUDIO));
}

TEST_F(ParcChunkDemuxerIamfTest, SafariRulesLeaveOutIamfTrack) {
  ASSERT_NO_FATAL_FAILURE(AppendIamfAndH264(/*safari=*/true, ""));
  EXPECT_FALSE(GetStream(DemuxerStream::AUDIO));
}
#endif




#if BUILDFLAG(USE_PROPRIETARY_CODECS)
#if BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
namespace {
const char* kMp2tMimeType = "video/mp2t";
}

TEST_F(ParcChunkDemuxerTest, ParcSafariTsAudioTrackSwitchAndDisable) {
  EXPECT_FOUND_CODEC_NAME(Audio, "mp3").Times(2);
  demuxer_->ParcSetSafariMediaSource(true);
  EXPECT_CALL(*this, DemuxerOpened());
  demuxer_->Initialize(&host_,
      CreateInitDoneCallback(kInfiniteDuration, PIPELINE_OK));
  ASSERT_EQ(ChunkDemuxer::kOk, AddId(kSourceId, kMp2tMimeType, "mp3"));
  EXPECT_CALL(*this, InitSegmentReceivedMock(_));
  const auto data = ReadTestDataFile("parc-two-audio.ts");
  ASSERT_TRUE(AppendData(kSourceId, base::span(*data)));
  const auto streams = demuxer_->GetAllStreams();
  ASSERT_EQ(streams.size(), 2u);
  auto* first = static_cast<ChunkDemuxerStream*>(streams[0].get());
  auto* second = static_cast<ChunkDemuxerStream*>(streams[1].get());
  ASSERT_EQ(first->type(), DemuxerStream::AUDIO);
  ASSERT_EQ(second->type(), DemuxerStream::AUDIO);
  EXPECT_TRUE(first->IsEnabled());
  EXPECT_FALSE(second->IsEnabled());
  DemuxerStream* selected = nullptr;
  demuxer_->OnTracksChanged(DemuxerStream::AUDIO, second->media_track_id(),
      base::Seconds(1), base::BindOnce([](DemuxerStream** out, DemuxerStream* s) {
        *out = s;
      }, &selected));
  EXPECT_EQ(selected, second);
  EXPECT_FALSE(first->IsEnabled());
  EXPECT_TRUE(second->IsEnabled());
  demuxer_->OnTracksChanged(DemuxerStream::AUDIO, std::nullopt,
      base::Seconds(1), base::DoNothing());
  EXPECT_FALSE(first->IsEnabled());
  EXPECT_FALSE(second->IsEnabled());
}


#endif
#endif





namespace {

constexpr size_t kParcChromiumAudioLimit = 12 * 1024 * 1024;

size_t ParcAppendFullAt(size_t bytes, bool video) {
  return ParcSourceBufferEviction::MaximumBufferSize(video) - bytes;
}

std::string ParcOneSecondFrames(int first_second,
                                int last_second,
                                int keyframe_seconds) {
  std::string frames;
  for (int second = first_second; second <= last_second; ++second) {
    if (second > first_second) {
      frames += " ";
    }
    frames += base::NumberToString(second * 1000);
    if (second == last_second) {
      frames += "D1000";
    }
    if (second % keyframe_seconds == 0) {
      frames += "K";
    }
  }
  return frames;
}

}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_WebKitBudget) {
  EXPECT_EQ(15938355u, ParcSourceBufferEviction::MaximumBufferSize(false));
  EXPECT_EQ(318767091u, ParcSourceBufferEviction::MaximumBufferSize(true));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_HoldsUpToTheBudget) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(0, 15);
  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 900000));
  CheckExpectedRanges("{ [0,75000) }");

  EXPECT_FALSE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 1000000));
  CheckExpectedRanges("{ [0,75000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_Off_ChromiumLimitHolds) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->SetMemoryLimitsForTest(DemuxerStream::AUDIO,
                                   kParcChromiumAudioLimit);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(0, 15);
  EXPECT_FALSE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 900000));
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_OneBudgetAcrossTracks) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  EXPECT_MEDIA_LOG(SegmentMissingFrames("1")).Times(3);
  ParcAppendFiveSecondAudioFrames(0, 16);
  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 1000000));
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,80000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_BudgetBeforeInitSegment) {
  EXPECT_CALL(*this, DemuxerOpened());
  demuxer_->Initialize(&host_,
                       base::BindOnce(&ParcChunkDemuxerTest::DemuxerInitialized,
                                      base::Unretained(this)));
  ASSERT_EQ(AddId(kSourceId, HAS_AUDIO | HAS_VIDEO), ChunkDemuxer::kOk);
  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 20000000));

  demuxer_->ParcSetSafariEviction(true);
  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 15938355));
  EXPECT_FALSE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 15938356));

  ShutdownDemuxer();
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_EarliestChunkBeforeCurrentTime) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(0, 15);
  const base::TimeDelta current_time = base::Seconds(60);
  Seek(current_time);

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, current_time, 2000000));
  CheckExpectedRanges("{ [30000,75000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_Off_FreesOnlyWhatTheAppendNeeds) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->SetMemoryLimitsForTest(DemuxerStream::AUDIO,
                                   kParcChromiumAudioLimit);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(0, 15);
  const base::TimeDelta current_time = base::Seconds(60);
  Seek(current_time);

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, current_time, 2000000));
  CheckExpectedRanges("{ [25000,75000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_DataAfterThePlayableSegment) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(50, 5);
  ParcAppendFiveSecondAudioFrames(0, 8);
  CheckExpectedRanges("{ [0,40000) [50000,75000) }");
  Seek(base::TimeDelta());

  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 3000000));
  CheckExpectedRanges("{ [0,40000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_Off_DataAfterTheCurrentRange) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->SetMemoryLimitsForTest(DemuxerStream::AUDIO,
                                   kParcChromiumAudioLimit);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(50, 5);
  ParcAppendFiveSecondAudioFrames(0, 8);
  Seek(base::TimeDelta());

  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 3000000));
  CheckExpectedRanges("{ [0,40000) [50000,55000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_PastTheLastAppendedGOP) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(0, 4);
  ParcAppendFiveSecondAudioFrames(50, 14);
  CheckExpectedRanges("{ [0,20000) [50000,120000) }");
  Seek(base::TimeDelta());

  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 4000000));
  CheckExpectedRanges("{ [0,20000) [50000,60000) }");

  ParcAppendFiveSecondAudioFrames(120, 1);
  CheckExpectedRanges("{ [0,20000) [50000,60000) [120000,125000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_LongerTrackKeepsItsTail) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendMuxedCluster(MuxedStreamInfo(kAudioTrackNum, "0K 5000D5000K"),
                     MuxedStreamInfo(kVideoTrackNum, "0K 5000D5000K"));
  AppendMuxedCluster(
      MuxedStreamInfo(kAudioTrackNum, "20000K 25000K 30000K 35000D5000K"),
      MuxedStreamInfo(kVideoTrackNum, "20000K 25000K 30000K 35000D5000K"));
  EXPECT_MEDIA_LOG(SegmentMissingFrames("1"));
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum, "40000K 45000D5000K");
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) [20000,50000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) [20000,40000) }");
  Seek(base::TimeDelta());

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(),
                                         ParcAppendFullAt(7000000, true)));
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) [40000,50000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcMemoryPressure_SafariKeepsLongerAudioTail) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendMuxedCluster(MuxedStreamInfo(kAudioTrackNum, "0K 5000D5000K"),
                     MuxedStreamInfo(kVideoTrackNum, "0K 5000D5000K"));
  AppendMuxedCluster(
      MuxedStreamInfo(kAudioTrackNum, "20000K 25000K 30000K 35000D5000K"),
      MuxedStreamInfo(kVideoTrackNum, "20000K 25000K 30000K 35000D5000K"));
  EXPECT_MEDIA_LOG(SegmentMissingFrames("1"));
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum, "40000K 45000D5000K");
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) [20000,50000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) [20000,40000) }");
  Seek(base::TimeDelta());

  demuxer_->ParcPurgeForMemoryPressure(kSourceId, base::TimeDelta(), true);
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) [40000,50000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcMemoryPressure_ChromePurgeUnchanged) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO | HAS_VIDEO));
  demuxer_->ParcSetSafariEviction(false);
  block_size_ = 1000000;
  AppendMuxedCluster(MuxedStreamInfo(kAudioTrackNum, "0K 5000D5000K"),
                     MuxedStreamInfo(kVideoTrackNum, "0K 5000D5000K"));
  AppendMuxedCluster(
      MuxedStreamInfo(kAudioTrackNum, "20000K 25000K 30000K 35000D5000K"),
      MuxedStreamInfo(kVideoTrackNum, "20000K 25000K 30000K 35000D5000K"));
  EXPECT_MEDIA_LOG(SegmentMissingFrames("1"));
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum, "40000K 45000D5000K");
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) [20000,50000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) [20000,40000) }");
  Seek(base::TimeDelta());

  demuxer_->ParcPurgeForMemoryPressure(kSourceId, base::TimeDelta(), true);
  CheckExpectedRanges(DemuxerStream::AUDIO, "{ [0,10000) }");
  CheckExpectedRanges(DemuxerStream::VIDEO, "{ [0,10000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_RemovesFramesNotWholeGOPs) {
  ASSERT_TRUE(InitDemuxer(HAS_VIDEO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum,
                            ParcOneSecondFrames(0, 9, 10));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum,
                            ParcOneSecondFrames(20, 39, 10));
  AppendSingleStreamCluster(kSourceId, kVideoTrackNum,
                            ParcOneSecondFrames(40, 64, 10));
  CheckExpectedRanges("{ [0,10000) [20000,65000) }");
  Seek(base::TimeDelta());

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(),
                                         ParcAppendFullAt(30000000, true)));
  CheckExpectedRanges("{ [0,10000) [20000,35000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_EstimateLetsTheRetryAppend) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum,
                            ParcOneSecondFrames(0, 14, 1));
  const base::TimeDelta current_time = base::Milliseconds(14500);
  const size_t append = ParcAppendFullAt(3500000, false);

  EXPECT_FALSE(demuxer_->EvictCodedFrames(kSourceId, current_time, append));
  CheckExpectedRanges("{ [11000,15000) }");

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, current_time, append));
  CheckExpectedRanges("{ [11000,15000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_EstimateAfterAppend) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum,
                            ParcOneSecondFrames(0, 14, 1));
  const base::TimeDelta current_time = base::Milliseconds(14500);
  demuxer_->ParcUpdateEvictionData(kSourceId, current_time);

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, current_time,
                                         ParcAppendFullAt(3500000, false)));
  CheckExpectedRanges("{ [11000,15000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_EstimateAtSeek) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  AppendSingleStreamCluster(kSourceId, kAudioTrackNum,
                            ParcOneSecondFrames(0, 14, 1));
  const base::TimeDelta current_time = base::Milliseconds(14500);
  Seek(current_time);

  EXPECT_TRUE(demuxer_->EvictCodedFrames(kSourceId, current_time,
                                         ParcAppendFullAt(3500000, false)));
  CheckExpectedRanges("{ [11000,15000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_KeepsThePlayableSegment) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->ParcSetSafariEviction(true);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(10, 13);
  ParcAppendFiveSecondAudioFrames(0, 2);
  Seek(base::TimeDelta());

  EXPECT_FALSE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 1000000));
  CheckExpectedRanges("{ [0,75000) }");
}

TEST_F(ParcChunkDemuxerTest, ParcSafariEviction_Off_EvictsFromThePlayableSegment) {
  ASSERT_TRUE(InitDemuxer(HAS_AUDIO));
  demuxer_->SetMemoryLimitsForTest(DemuxerStream::AUDIO,
                                   kParcChromiumAudioLimit);
  block_size_ = 1000000;
  ParcAppendFiveSecondAudioFrames(10, 13);
  ParcAppendFiveSecondAudioFrames(0, 2);
  Seek(base::TimeDelta());

  EXPECT_TRUE(
      demuxer_->EvictCodedFrames(kSourceId, base::TimeDelta(), 1000000));
  CheckExpectedRanges("{ [0,55000) }");
}





TEST_F(ParcChunkDemuxerTest, Parc_ChromeMediaSourceKeepsSmallGaps) {
  std::string audio_id = "audio1";
  std::string video_id = "video1";
  ASSERT_TRUE(InitDemuxerAudioAndVideoSources(audio_id, video_id));

  AppendSingleStreamCluster(video_id, kVideoTrackNum, "0K 33 66 99D33");
  AppendSingleStreamCluster(video_id, kVideoTrackNum, "202K 235D33");
  CheckExpectedRanges(video_id, "{ [0,132) [202,268) }");
}

TEST_F(ParcChunkDemuxerTest, Parc_SafariMediaSourceGaps) {
  demuxer_->ParcSetSafariMediaSource(true);
  std::string audio_id = "audio1";
  std::string video_id = "video1";
  ASSERT_TRUE(InitDemuxerAudioAndVideoSources(audio_id, video_id));
  DemuxerStream* video_stream = GetStream(DemuxerStream::VIDEO);

  AppendSingleStreamCluster(video_id, kVideoTrackNum, "0K 33 66 99D33");
  AppendSingleStreamCluster(video_id, kVideoTrackNum, "202K 235D33");
  AppendSingleStreamCluster(video_id, kVideoTrackNum, "468K 501D33");
  CheckExpectedRanges(video_id, "{ [0,268) [468,534) }");

  CheckExpectedBuffers(video_stream, "0K 33 66 99");
  ExpectRead(DemuxerStream::VIDEO, 202);
  ExpectRead(DemuxerStream::VIDEO, 235);

  {
    InSequence s;
    EXPECT_CALL(*this, Checkpoint(1));
    EXPECT_CALL(*this, ReadDone(DemuxerStream::kOk,
                                ReadOneAndHasTimestamp(468)));
  }
  ParcStartRead(DemuxerStream::VIDEO);
  base::RunLoop().RunUntilIdle();
  Checkpoint(1);
  AppendSingleStreamCluster(audio_id, kAudioTrackNum,
                            "0K 100K 200K 300K 400K 500D100K");
  base::RunLoop().RunUntilIdle();
  ExpectRead(DemuxerStream::VIDEO, 501);
}

}

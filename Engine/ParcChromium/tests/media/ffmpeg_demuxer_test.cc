// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/ffmpeg_demuxer_test.cc. The fixture is derived from
// Chromium's ffmpeg_demuxer_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

#include "media/filters/ffmpeg_demuxer.h"

#include <stddef.h>
#include <stdint.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/path_service.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/decoder_buffer.h"
#include "media/base/demuxer_stream.h"
#include "media/base/media_tracks.h"
#include "media/base/mock_demuxer_host.h"
#include "media/base/mock_media_log.h"
#include "media/base/supported_types.h"
#include "media/base/test_helpers.h"
#include "media/filters/file_data_source.h"
#include "media/media_buildflags.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "ui/gfx/geometry/size.h"

using ::testing::_;
using ::testing::AnyNumber;

namespace media {

class ParcFFmpegDemuxerTest : public testing::Test {
 public:
  ParcFFmpegDemuxerTest(const ParcFFmpegDemuxerTest&) = delete;
  ParcFFmpegDemuxerTest& operator=(const ParcFFmpegDemuxerTest&) = delete;

 protected:
  ParcFFmpegDemuxerTest() { AddSupplementalCodecsForTesting(); }

  ~ParcFFmpegDemuxerTest() override { Shutdown(); }

  void Shutdown() {
    if (demuxer_)
      demuxer_->Stop();
    demuxer_.reset();
    task_environment_.RunUntilIdle();
    data_source_.reset();
  }

  void CreateDemuxer(const std::string& name) {
    CreateDemuxerInternal(name, &dummy_media_log_);
  }

  DemuxerStream* GetStream(DemuxerStream::Type type) {
    std::vector<raw_ptr<DemuxerStream>> streams = demuxer_->GetAllStreams();
    for (media::DemuxerStream* stream : streams) {
      if (stream->type() == type)
        return stream;
    }
    return nullptr;
  }

  void InitializeDemuxerAndExpectPipelineStatus(
      media::PipelineStatus expected_pipeline_status) {
    if (expected_pipeline_status == PIPELINE_OK)
      EXPECT_CALL(host_, SetDuration(_)).Times(AnyNumber());
    WaitableMessageLoopEvent event;
    demuxer_->Initialize(&host_, event.GetPipelineStatusCB());
    event.RunAndWaitForStatus(expected_pipeline_status);
  }

  void InitializeDemuxer() {
    InitializeDemuxerAndExpectPipelineStatus(PIPELINE_OK);
  }

  struct ReadExpectation {
    std::optional<size_t> size;
    std::optional<int64_t> timestamp_us;
    base::TimeDelta discard_front_padding;
    bool is_key_frame = true;
    DemuxerStream::Status status = DemuxerStream::Status::kOk;
    bool has_agtm_side_data = false;
  };

  void OnReadDone(const base::Location& location,
                  const ReadExpectation& read_expectation,
                  base::OnceClosure quit_closure,
                  DemuxerStream::Status status,
                  DemuxerStream::DecoderBufferVector buffers) {
    // TODO(crbug.com/40232931): add multi read unit tests in next CL.
    CHECK_LE(buffers.size(), 1u)
        << "ParcFFmpegDemuxerTest only reads a single-buffer.";
    SCOPED_TRACE(location.ToString() + "\n");
    EXPECT_EQ(read_expectation.status, status);
    if (status == DemuxerStream::kOk) {
      CHECK_EQ(buffers.size(), 1u);
      CHECK(buffers[0]);
      const DecoderBuffer& buffer = *(buffers[0]);

      if (read_expectation.size) {
        EXPECT_EQ(read_expectation.size.value(), buffer.size());
      }
      if (read_expectation.timestamp_us) {
        EXPECT_EQ(read_expectation.timestamp_us.value(),
                  buffer.timestamp().InMicroseconds());
      }
      const auto discard_padding = buffer.discard_padding();
      EXPECT_EQ(read_expectation.discard_front_padding,
                discard_padding.has_value() ? discard_padding->first
                                            : base::TimeDelta());
      EXPECT_EQ(read_expectation.is_key_frame, buffer.is_key_frame());
      const bool has_agtm_side_data =
          buffer.side_data() != nullptr &&
          buffer.side_data()->hdr_metadata.HasAgtm();
      EXPECT_EQ(read_expectation.has_agtm_side_data, has_agtm_side_data);
    }
    std::move(quit_closure).Run();
  }

  void Read(DemuxerStream* stream,
            const base::Location& location,
            int size,
            int64_t timestamp_us,
            bool is_key_frame,
            DemuxerStream::Status status = DemuxerStream::Status::kOk,
            base::TimeDelta discard_front_padding = base::TimeDelta(),
            bool has_agtm_side_data = false) {
    Read(stream, location,
         ReadExpectation{size, timestamp_us, discard_front_padding,
                         is_key_frame, status, has_agtm_side_data});
  }

  void Read(DemuxerStream* stream,
            const base::Location& location,
            const ReadExpectation& expectation) {
    base::RunLoop run_loop;
    stream->Read(1, base::BindOnce(&ParcFFmpegDemuxerTest::OnReadDone,
                                   base::Unretained(this), location,
                                   expectation, run_loop.QuitClosure()));
    run_loop.Run();

    // Ensure tasks posted after the ReadCB is satisfied run. These are always
    // tasks posted to FFmpegDemuxer's internal |blocking_task_runner_|, which
    // the RunLoop above won't pump.
    task_environment_.RunUntilIdle();
  }

  base::test::TaskEnvironment task_environment_;
  NullMediaLog dummy_media_log_;

  std::unique_ptr<FileDataSource> data_source_;
  std::unique_ptr<FFmpegDemuxer> demuxer_;
  testing::StrictMock<MockDemuxerHost> host_;

 private:
  void CreateDemuxerInternal(const std::string& name, MediaLog* media_log) {
    CHECK(!demuxer_);

    EXPECT_CALL(host_, OnBufferedTimeRangesChanged(_)).Times(AnyNumber());

    CreateDataSource(name);

    Demuxer::EncryptedMediaInitDataCB encrypted_media_init_data_cb =
        base::BindRepeating([](EmeInitDataType, const std::vector<uint8_t>&) {});
    Demuxer::MediaTracksUpdatedCB tracks_updated_cb =
        base::BindRepeating([](std::unique_ptr<MediaTracks>) {});

    demuxer_ = std::make_unique<FFmpegDemuxer>(
        base::SingleThreadTaskRunner::GetCurrentDefault(), data_source_.get(),
        encrypted_media_init_data_cb, tracks_updated_cb, media_log, false);
  }

  void CreateDataSource(const std::string& name) {
    CHECK(!data_source_);

    base::FilePath file_path;
    EXPECT_TRUE(
        base::PathService::Get(base::DIR_SRC_TEST_DATA_ROOT, &file_path));

    file_path = file_path.Append(FILE_PATH_LITERAL("media"))
                    .Append(FILE_PATH_LITERAL("test"))
                    .Append(FILE_PATH_LITERAL("data"))
                    .AppendASCII(name);

    data_source_ = std::make_unique<FileDataSource>();
    EXPECT_TRUE(data_source_->Initialize(file_path));
  }
};

#if BUILDFLAG(USE_PROPRIETARY_CODECS)
// Parc: 3GPP's H.263 video and AMR audio (parc-h263-amr.3gp, two seconds
// written by FFmpeg's 3gp muxer) play only on Safari-identity pages, where
// VideoToolbox and AudioToolbox decode them.
TEST_F(ParcFFmpegDemuxerTest, ParcSafariCodecsIn3gpp) {
  CreateDemuxer("parc-h263-amr.3gp");
  InitializeDemuxerAndExpectPipelineStatus(DEMUXER_ERROR_NO_SUPPORTED_STREAMS);
  Shutdown();

  CreateDemuxer("parc-h263-amr.3gp");
  demuxer_->ParcSetSafariCodecs(true);
  InitializeDemuxer();

  DemuxerStream* video = GetStream(DemuxerStream::VIDEO);
  ASSERT_TRUE(video);
  EXPECT_EQ(video->video_decoder_config().codec(), VideoCodec::kH263);
  EXPECT_EQ(video->video_decoder_config().coded_size(), gfx::Size(176, 144));
  DemuxerStream* audio = GetStream(DemuxerStream::AUDIO);
  ASSERT_TRUE(audio);
  EXPECT_EQ(audio->audio_decoder_config().codec(), AudioCodec::kAMR_NB);
  EXPECT_EQ(audio->audio_decoder_config().samples_per_second(), 8000);
  EXPECT_EQ(audio->audio_decoder_config().channel_layout(),
            CHANNEL_LAYOUT_MONO);
  EXPECT_EQ(audio->audio_decoder_config().sample_format(),
            kSampleFormatPlanarF32);

  Read(audio, FROM_HERE, 32, 0, true);
  Read(video, FROM_HERE, 2296, 0, true);
}

#endif  // BUILDFLAG(USE_PROPRIETARY_CODECS)

}  // namespace media

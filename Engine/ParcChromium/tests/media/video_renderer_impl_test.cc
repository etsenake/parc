// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/video_renderer_impl_test.cc. The fixture is
// derived from Chromium's video_renderer_impl_unittest.cc (Chromium Authors;
// BSD-style license in Chromium's LICENSE) and contains only Parc regressions.

#include "media/renderers/video_renderer_impl.h"

#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/containers/circular_deque.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/location.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/notreached.h"
#include "base/run_loop.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/stringprintf.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/bind.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/simple_test_tick_clock.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/decoder_buffer.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/null_video_sink.h"
#include "media/base/test_helpers.h"
#include "media/base/video_frame.h"
#include "media/base/wall_clock_time_source.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::base::test::RunOnceCallback;
using ::testing::_;
using ::testing::AnyNumber;
using ::testing::DoAll;
using ::testing::Invoke;
using ::testing::Mock;
using ::testing::NiceMock;
using ::testing::Return;
using ::testing::SaveArg;
using ::testing::StrictMock;

namespace media {

MATCHER_P(HasTimestampMatcher, ms, "") {
  *result_listener << "has timestamp " << arg->timestamp().InMilliseconds();
  return arg->timestamp().InMilliseconds() == ms;
}

class ParcVideoRendererImplTest : public testing::Test {
 public:
  std::vector<std::unique_ptr<VideoDecoder>> CreateVideoDecodersForTest() {
    decoder_ = new NiceMock<MockVideoDecoder>();
    std::vector<std::unique_ptr<VideoDecoder>> decoders;
    decoders.push_back(base::WrapUnique(decoder_.get()));
    ON_CALL(*decoder_, Initialize_(_, _, _, _, _, _))
        .WillByDefault(
            DoAll(SaveArg<4>(&output_cb_),
                  RunOnceCallback<3>(DecoderStatus::Codes::kOk)));
    // Monitor decodes from the decoder.
    ON_CALL(*decoder_, Decode_(_, _))
        .WillByDefault(
            Invoke(this, &ParcVideoRendererImplTest::DecodeRequested));
    ON_CALL(*decoder_, Reset_(_))
        .WillByDefault(
            Invoke(this, &ParcVideoRendererImplTest::FlushRequested));
    ON_CALL(*decoder_, GetMaxDecodeRequests()).WillByDefault(Return(1));
    return decoders;
  }

  ParcVideoRendererImplTest()
      : task_environment_(base::test::TaskEnvironment::TimeSource::MOCK_TIME),
        decoder_(nullptr),
        demuxer_stream_(DemuxerStream::VIDEO),
        simulate_decode_delay_(false),
        time_source_(&tick_clock_) {
    null_video_sink_ = std::make_unique<NullVideoSink>(
        false, base::Seconds(1.0 / 60),
        base::BindRepeating(&MockCB::FrameReceived,
                            base::Unretained(&mock_cb_)),
        base::SingleThreadTaskRunner::GetCurrentDefault());

    renderer_ = std::make_unique<VideoRendererImpl>(
        base::SingleThreadTaskRunner::GetCurrentDefault(),
        null_video_sink_.get(),
        base::BindRepeating(
            &ParcVideoRendererImplTest::CreateVideoDecodersForTest,
            base::Unretained(this)),
        true, &media_log_, nullptr, MediaPlayerLoggingID(0));
    renderer_->SetTickClockForTesting(&tick_clock_);
    null_video_sink_->set_tick_clock_for_testing(&tick_clock_);

    // Start wallclock time at a non-zero value.
    AdvanceWallclockTimeInMs(12345);

    demuxer_stream_.set_video_decoder_config(TestVideoConfig::Normal());

    // We expect these to be called but we don't care how/when. Tests can
    // customize the provided buffer returned via OnDemuxerRead().
    ON_CALL(demuxer_stream_, OnRead(_))
        .WillByDefault(Invoke(this, &ParcVideoRendererImplTest::OnDemuxerRead));
  }

  ParcVideoRendererImplTest(const ParcVideoRendererImplTest&) = delete;
  ParcVideoRendererImplTest& operator=(const ParcVideoRendererImplTest&) =
      delete;

  ~ParcVideoRendererImplTest() override = default;

  void Initialize() { InitializeRenderer(&demuxer_stream_); }

  void InitializeRenderer(MockDemuxerStream* demuxer_stream) {
    WaitableMessageLoopEvent event;
    EXPECT_CALL(mock_cb_, OnWaiting(_)).Times(0);
    EXPECT_CALL(mock_cb_, OnAudioConfigChange(_)).Times(0);
    EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_)).Times(AnyNumber());
    renderer_->Initialize(
        demuxer_stream, nullptr, &mock_cb_,
        base::BindRepeating(&WallClockTimeSource::GetWallClockTimes,
                            base::Unretained(&time_source_)),
        event.GetPipelineStatusCB());
    event.RunAndWaitForStatus(PIPELINE_OK);
  }

  void StartPlayingFrom(int milliseconds) {
    SCOPED_TRACE(base::StringPrintf("StartPlayingFrom(%d)", milliseconds));
    const base::TimeDelta media_time = base::Milliseconds(milliseconds);
    time_source_.SetMediaTime(media_time);
    renderer_->StartPlayingFrom(media_time);
    base::RunLoop().RunUntilIdle();
  }

  void Destroy() {
    SCOPED_TRACE("Destroy()");
    renderer_.reset();
    base::RunLoop().RunUntilIdle();
  }

  void OnDemuxerRead(DemuxerStream::ReadCB& read_cb) {
    auto buffer = base::MakeRefCounted<DecoderBuffer>(0);
    buffer->set_timestamp(kNoTimestamp);
    std::move(read_cb).Run(DemuxerStream::kOk, {std::move(buffer)});
  }

  // Parses a string representation of video frames and generates corresponding
  // VideoFrame objects in |decode_results_|.
  //
  // Syntax:
  //   nn - Queue a decoder buffer with timestamp nn * 1000us
  //   nndmm - Queue a decoder buffer with timestamp nn * 1000us
  //           and mm * 1000us duration
  //   abort - Queue an aborted read
  //   error - Queue a decoder error
  //
  // Examples:
  //   A clip that is four frames long: "0 10 20 30"
  //   A clip that has a decode error: "60 70 error"
  void QueueFrames(const std::string& str) {
    for (std::string_view token : base::SplitString(
             str, " ", base::TRIM_WHITESPACE, base::SPLIT_WANT_ALL)) {
      if (token == "abort") {
        scoped_refptr<VideoFrame> null_frame;
        QueueFrame(DecoderStatus::Codes::kAborted, null_frame);
        continue;
      }

      if (token == "error") {
        scoped_refptr<VideoFrame> null_frame;
        QueueFrame(DecoderStatus::Codes::kFailed, null_frame);
        continue;
      }

      auto ts_tokens = base::SplitStringPiece(token, "d", base::TRIM_WHITESPACE,
                                              base::SPLIT_WANT_ALL);
      if (ts_tokens.size() > 1) {
        token = ts_tokens[0];
      }

      int timestamp_in_ms = 0;
      if (base::StringToInt(token, &timestamp_in_ms)) {
        gfx::Size natural_size = TestVideoConfig::NormalCodedSize();
        scoped_refptr<VideoFrame> frame = VideoFrame::CreateFrame(
            PIXEL_FORMAT_I420, natural_size, gfx::Rect(natural_size),
            natural_size, base::Milliseconds(timestamp_in_ms));

        int duration_in_ms = 0;
        if (ts_tokens.size() > 1 &&
            base::StringToInt(ts_tokens[1], &duration_in_ms)) {
          frame->metadata().frame_duration = base::Milliseconds(duration_in_ms);
        }

        QueueFrame(DecoderStatus::Codes::kOk, frame);
        continue;
      }

      NOTREACHED() << "Unrecognized decoder buffer token: " << token;
    }
  }

  // Queues video frames to be served by the decoder during rendering.
  void QueueFrame(DecoderStatus status, scoped_refptr<VideoFrame> frame) {
    decode_results_.push_back(std::make_pair(status, frame));
  }

  void WaitForPendingDecode() {
    SCOPED_TRACE("WaitForPendingDecode()");
    if (decode_cb_)
      return;

    DCHECK(!wait_for_pending_decode_cb_);

    WaitableMessageLoopEvent event;
    wait_for_pending_decode_cb_ = event.GetClosure();
    event.RunAndWait();

    DCHECK(decode_cb_);
    DCHECK(!wait_for_pending_decode_cb_);
  }

  void SatisfyPendingDecode() {
    CHECK(decode_cb_);
    CHECK(!decode_results_.empty());

    // Post tasks for OutputCB and DecodeCB.
    scoped_refptr<VideoFrame> frame = decode_results_.front().second;
    if (frame.get())
      task_environment_.GetMainThreadTaskRunner()->PostTask(
          FROM_HERE, base::BindOnce(output_cb_, frame));
    task_environment_.GetMainThreadTaskRunner()->PostTask(
        FROM_HERE,
        base::BindOnce(std::move(decode_cb_), decode_results_.front().first));
    decode_results_.pop_front();
  }

  void SatisfyPendingDecodeWithEndOfStream() {
    DCHECK(decode_cb_);

    // Return EOS buffer to trigger EOS frame.
    DemuxerStream::DecoderBufferVector buffers;
    buffers.emplace_back(DecoderBuffer::CreateEOSBuffer());
    EXPECT_CALL(demuxer_stream_, OnRead(_))
        .WillOnce(RunOnceCallback<0>(DemuxerStream::kOk, buffers));

    // Satisfy pending |decode_cb_| to trigger a new DemuxerStream::Read().
    task_environment_.GetMainThreadTaskRunner()->PostTask(
        FROM_HERE,
        base::BindOnce(std::move(decode_cb_), DecoderStatus::Codes::kOk));

    WaitForPendingDecode();

    task_environment_.GetMainThreadTaskRunner()->PostTask(
        FROM_HERE,
        base::BindOnce(std::move(decode_cb_), DecoderStatus::Codes::kOk));
  }

  void AdvanceWallclockTimeInMs(int time_ms) {
    EXPECT_TRUE(
        task_environment_.GetMainThreadTaskRunner()->BelongsToCurrentThread());
    tick_clock_.Advance(base::Milliseconds(time_ms));
  }

  MOCK_METHOD0(OnSimulateDecodeDelay, base::TimeDelta(void));

  // Parc: what ParcRewind() saw.
  struct ParcRewound {
    // The frames shown, in order.
    std::vector<base::TimeDelta> shown;
    // How often time waited for frames, and when it first started.
    int holds = 0;
    base::TimeDelta started;
    // Media time at the end.
    base::TimeDelta time;
    PipelineStatistics statistics;
  };

  // Parc: rewinds a file with a frame every `frame` and a keyframe every
  // `gop` from `start` at `rate` for `run`, all in mock time. A demuxer seek
  // takes `seek` and goes to the keyframe at or before its time; the decoder
  // outputs each frame `decode` after its input.
  // As RendererImpl does, time stops on BUFFERING_HAVE_NOTHING.
  ParcRewound ParcRewind(const gfx::Size& size,
                         base::TimeDelta frame,
                         base::TimeDelta gop,
                         base::TimeDelta decode,
                         base::TimeDelta seek,
                         base::TimeDelta start,
                         double rate,
                         base::TimeDelta run) {
    const base::TickClock* clock = task_environment_.GetMockTickClock();
    WallClockTimeSource time_source(clock);
    renderer_->SetTickClockForTesting(clock);
    null_video_sink_->set_tick_clock_for_testing(clock);
    parc_size_ = size;
    parc_frame_ = frame;
    parc_gop_ = gop;
    parc_decode_ = decode;
    parc_seek_ = seek;

    EXPECT_CALL(mock_cb_, OnWaiting(_)).Times(0);
    EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_)).Times(AnyNumber());
    EXPECT_CALL(mock_cb_, OnVideoNaturalSizeChange(_)).Times(AnyNumber());
    EXPECT_CALL(mock_cb_, OnVideoOpacityChange(_)).Times(AnyNumber());
    WaitableMessageLoopEvent initialized;
    renderer_->Initialize(
        &demuxer_stream_, nullptr, &mock_cb_,
        base::BindRepeating(&WallClockTimeSource::GetWallClockTimes,
                            base::Unretained(&time_source)),
        initialized.GetPipelineStatusCB());
    initialized.RunAndWaitForStatus(PIPELINE_OK);
    ON_CALL(demuxer_stream_, OnRead(_))
        .WillByDefault(
            Invoke(this, &ParcVideoRendererImplTest::ParcDemuxerRead));
    ON_CALL(*decoder_, Decode_(_, _))
        .WillByDefault(Invoke(this, &ParcVideoRendererImplTest::ParcDecode));
    ON_CALL(*decoder_, Reset_(_))
        .WillByDefault(
            Invoke(this, &ParcVideoRendererImplTest::ParcResetDecoder));

    ParcRewound rewound;
    EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_))
        .WillRepeatedly([&](const PipelineStatistics& stats) {
          rewound.statistics.video_frames_decoded += stats.video_frames_decoded;
          rewound.statistics.video_frames_dropped += stats.video_frames_dropped;
        });
    const base::TimeTicks began = clock->NowTicks();
    bool ticking = false;
    EXPECT_CALL(mock_cb_, FrameReceived(_))
        .WillRepeatedly([&](scoped_refptr<VideoFrame> shown) {
          rewound.shown.push_back(shown->timestamp());
        });
    EXPECT_CALL(mock_cb_, OnBufferingStateChange(_, _))
        .WillRepeatedly([&](BufferingState state, BufferingStateChangeReason) {
          if (state == BUFFERING_HAVE_ENOUGH && !ticking) {
            if (rewound.started.is_zero()) {
              rewound.started = clock->NowTicks() - began;
            }
            ticking = true;
            time_source.StartTicking();
            renderer_->OnTimeProgressing();
          } else if (state == BUFFERING_HAVE_NOTHING && ticking) {
            ++rewound.holds;
            ticking = false;
            time_source.StopTicking();
            renderer_->OnTimeStopped();
          }
        });

    time_source.SetMediaTime(start);
    time_source.SetPlaybackRate(-rate);
    renderer_->ParcStartPlayingBackwardFrom(
        start, base::BindRepeating(&ParcVideoRendererImplTest::ParcSeekDemuxer,
                                   base::Unretained(this)));
    task_environment_.FastForwardBy(run);
    rewound.time = time_source.CurrentMediaTime();

    ++parc_generation_;
    Destroy();
    Mock::VerifyAndClearExpectations(&mock_cb_);
    return rewound;
  }

 protected:
  base::test::TaskEnvironment task_environment_;
  NullMediaLog media_log_;

  // Fixture members.
  std::unique_ptr<VideoRendererImpl> renderer_;
  base::SimpleTestTickClock tick_clock_;
  raw_ptr<NiceMock<MockVideoDecoder>, DanglingUntriaged>
      decoder_;  // Owned by |renderer_|.
  NiceMock<MockDemuxerStream> demuxer_stream_;
  bool simulate_decode_delay_;

  // Use StrictMock<T> to catch missing/extra callbacks.
  class MockCB : public MockRendererClient {
   public:
    MOCK_METHOD1(FrameReceived, void(scoped_refptr<VideoFrame>));
  };
  StrictMock<MockCB> mock_cb_;

  // Must be destroyed before |renderer_| since they share |tick_clock_|.
  std::unique_ptr<NullVideoSink> null_video_sink_;

  WallClockTimeSource time_source_;

 private:
  void DecodeRequested(scoped_refptr<DecoderBuffer>,
                       VideoDecoder::DecodeCB& decode_cb) {
    EXPECT_TRUE(
        task_environment_.GetMainThreadTaskRunner()->BelongsToCurrentThread());
    CHECK(!decode_cb_);
    decode_cb_ = std::move(decode_cb);

    // Wake up WaitForPendingDecode() if needed.
    if (wait_for_pending_decode_cb_)
      std::move(wait_for_pending_decode_cb_).Run();

    if (decode_results_.empty())
      return;

    if (simulate_decode_delay_)
      tick_clock_.Advance(OnSimulateDecodeDelay());

    SatisfyPendingDecode();
  }

  void FlushRequested(base::OnceClosure& callback) {
    EXPECT_TRUE(
        task_environment_.GetMainThreadTaskRunner()->BelongsToCurrentThread());
    decode_results_.clear();
    if (decode_cb_) {
      QueueFrames("abort");
      SatisfyPendingDecode();
    }

    task_environment_.GetMainThreadTaskRunner()->PostTask(FROM_HERE,
                                                          std::move(callback));
  }

  void ParcSeekDemuxer(base::TimeDelta time, base::OnceClosure done) {
    task_environment_.GetMainThreadTaskRunner()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(&ParcVideoRendererImplTest::ParcSeekDone,
                       base::Unretained(this),
                       parc_gop_ * time.IntDiv(parc_gop_),
                       std::move(done)),
        parc_seek_);
  }

  void ParcSeekDone(base::TimeDelta keyframe, base::OnceClosure done) {
    parc_next_ = keyframe;
    std::move(done).Run();
  }

  void ParcDemuxerRead(DemuxerStream::ReadCB& read_cb) {
    auto buffer = base::MakeRefCounted<DecoderBuffer>(0);
    buffer->set_timestamp(parc_next_);
    buffer->set_duration(parc_frame_);
    buffer->set_is_key_frame((parc_next_ % parc_gop_).is_zero());
    parc_next_ += parc_frame_;
    std::move(read_cb).Run(DemuxerStream::kOk, {std::move(buffer)});
  }

  void ParcDecode(scoped_refptr<DecoderBuffer> buffer,
                  VideoDecoder::DecodeCB& decode_cb) {
    CHECK(!parc_decode_cb_);
    parc_decode_cb_ = std::move(decode_cb);
    scoped_refptr<VideoFrame> frame = VideoFrame::CreateFrame(
        PIXEL_FORMAT_I420, parc_size_, gfx::Rect(parc_size_), parc_size_,
        buffer->timestamp());
    task_environment_.GetMainThreadTaskRunner()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(&ParcVideoRendererImplTest::ParcDecoded,
                       base::Unretained(this), parc_generation_,
                       std::move(frame)),
        parc_decode_);
  }

  void ParcDecoded(int generation, scoped_refptr<VideoFrame> frame) {
    if (generation != parc_generation_ || !parc_decode_cb_) {
      return;
    }
    output_cb_.Run(std::move(frame));
    std::move(parc_decode_cb_).Run(DecoderStatus::Codes::kOk);
  }

  void ParcResetDecoder(base::OnceClosure& done) {
    ++parc_generation_;
    if (parc_decode_cb_) {
      task_environment_.GetMainThreadTaskRunner()->PostTask(
          FROM_HERE, base::BindOnce(std::move(parc_decode_cb_),
                                    DecoderStatus::Codes::kAborted));
    }
    task_environment_.GetMainThreadTaskRunner()->PostTask(FROM_HERE,
                                                          std::move(done));
  }

  // ParcRewind()'s file and decoder.
  gfx::Size parc_size_;
  base::TimeDelta parc_frame_;
  base::TimeDelta parc_gop_;
  base::TimeDelta parc_decode_;
  base::TimeDelta parc_seek_;
  base::TimeDelta parc_next_;
  int parc_generation_ = 0;
  VideoDecoder::DecodeCB parc_decode_cb_;

  // Used for satisfying reads.
  VideoDecoder::OutputCB output_cb_;
  VideoDecoder::DecodeCB decode_cb_;

  // Run during DecodeRequested() to unblock WaitForPendingDecode().
  base::OnceClosure wait_for_pending_decode_cb_;

  base::circular_deque<std::pair<DecoderStatus, scoped_refptr<VideoFrame>>>
      decode_results_;
};

TEST_F(ParcVideoRendererImplTest, ParcPlaysBackwardWindowByWindow) {
  Initialize();
  std::vector<base::TimeDelta> seeks;
  base::OnceClosure seek_done;
  auto seek_demuxer = base::BindLambdaForTesting(
      [&](base::TimeDelta time, base::OnceClosure done) {
        seeks.push_back(time);
        seek_done = std::move(done);
      });
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnVideoNaturalSizeChange(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnVideoOpacityChange(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));

  renderer_->ParcStartPlayingBackwardFrom(base::Milliseconds(35),
                                          seek_demuxer);
  base::RunLoop().RunUntilIdle();
  ASSERT_EQ(seeks, std::vector<base::TimeDelta>{base::Milliseconds(35)});
  std::move(seek_done).Run();
  WaitForPendingDecode();
  // The frame after the end closes the window.
  QueueFrames("20 30 40");
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();

  ASSERT_EQ(seeks.size(), 2u);
  EXPECT_EQ(seeks[1], base::Milliseconds(20) - base::Microseconds(1));
  std::move(seek_done).Run();
  WaitForPendingDecode();
  QueueFrames("0 10 20");
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();

  {
    testing::InSequence in_sequence;
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(30)));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(20)));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(10)));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(0)));
  }
  time_source_.SetMediaTime(base::Milliseconds(35));
  time_source_.SetPlaybackRate(-0.25);
  time_source_.StartTicking();
  renderer_->OnTimeProgressing();
  base::RunLoop().RunUntilIdle();
  for (int i = 0; i < 8; ++i) {
    AdvanceWallclockTimeInMs(17);
    task_environment_.FastForwardBy(base::Milliseconds(17));
  }
  // Nothing comes before 0.
  EXPECT_EQ(seeks.size(), 2u);
  Destroy();
}

// Parc: when time passes a window before the one before it is decoded, time
// waits for it (RendererImpl stops its clock on BUFFERING_HAVE_NOTHING).
TEST_F(ParcVideoRendererImplTest, ParcBackwardWaitsForTheWindowBefore) {
  Initialize();
  std::vector<base::TimeDelta> seeks;
  base::OnceClosure seek_done;
  auto seek_demuxer = base::BindLambdaForTesting(
      [&](base::TimeDelta time, base::OnceClosure done) {
        seeks.push_back(time);
        seek_done = std::move(done);
      });
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnVideoNaturalSizeChange(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnVideoOpacityChange(_)).Times(AnyNumber());
  {
    testing::InSequence in_sequence;
    EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(30)));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(20)));
    EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_NOTHING, _));
    EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
    EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(10)));
  }

  renderer_->ParcStartPlayingBackwardFrom(base::Milliseconds(35),
                                          seek_demuxer);
  base::RunLoop().RunUntilIdle();
  std::move(seek_done).Run();
  WaitForPendingDecode();
  QueueFrames("20 30 40");
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();
  ASSERT_EQ(seeks.size(), 2u);

  time_source_.SetMediaTime(base::Milliseconds(35));
  time_source_.SetPlaybackRate(-1);
  time_source_.StartTicking();
  renderer_->OnTimeProgressing();
  base::RunLoop().RunUntilIdle();
  AdvanceWallclockTimeInMs(17);
  task_environment_.FastForwardBy(base::Milliseconds(17));
  time_source_.StopTicking();
  renderer_->OnTimeStopped();

  std::move(seek_done).Run();
  WaitForPendingDecode();
  QueueFrames("0 10 20");
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();
  time_source_.StartTicking();
  renderer_->OnTimeProgressing();
  base::RunLoop().RunUntilIdle();
  Destroy();
}

// Parc: a window keeps only the frames closest to its end, so a long group
// of pictures is decoded again from its keyframe for the window before.
TEST_F(ParcVideoRendererImplTest, ParcBackwardWindowIsBounded) {
  Initialize();
  std::vector<base::TimeDelta> seeks;
  base::OnceClosure seek_done;
  auto seek_demuxer = base::BindLambdaForTesting(
      [&](base::TimeDelta time, base::OnceClosure done) {
        seeks.push_back(time);
        seek_done = std::move(done);
      });
  PipelineStatistics statistics;
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_))
      .WillRepeatedly([&](const PipelineStatistics& stats) {
        statistics.video_frames_decoded += stats.video_frames_decoded;
        statistics.video_frames_dropped += stats.video_frames_dropped;
      });
  EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));

  renderer_->ParcStartPlayingBackwardFrom(base::Milliseconds(685),
                                          seek_demuxer);
  base::RunLoop().RunUntilIdle();
  std::move(seek_done).Run();
  WaitForPendingDecode();
  std::string frames;
  for (int ms = 0; ms <= 690; ms += 10) {
    frames += base::NumberToString(ms) + " ";
  }
  QueueFrames(frames);
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();

  // 70 decoded frames: 64 retained, five evicted and one past the end.
  EXPECT_EQ(statistics.video_frames_decoded, 70u);
  EXPECT_EQ(statistics.video_frames_dropped, 6u);
  // 64 frames, 50 to 680.
  ASSERT_EQ(seeks.size(), 2u);
  EXPECT_EQ(seeks[1], base::Milliseconds(50) - base::Microseconds(1));
  Destroy();
}

// Parc: each window is sized from the measured seek and decode times so it
// lasts until the window before it is decoded. A 1080p file with keyframes
// 10 seconds apart, decoded at 8x its frame rate, rewinds every frame without
// time ever waiting.
TEST_F(ParcVideoRendererImplTest, ParcBackwardDecodesAheadWithoutHolding) {
  const ParcRewound rewound = ParcRewind(
      gfx::Size(1920, 1080), base::Milliseconds(40), base::Seconds(10),
      base::Milliseconds(5), base::Milliseconds(30), base::Milliseconds(59500),
      1, base::Seconds(20));

  EXPECT_EQ(rewound.holds, 0);
  EXPECT_LT(rewound.started, base::Seconds(2));
  EXPECT_EQ(rewound.time,
            base::Milliseconds(59500) - (base::Seconds(20) - rewound.started));
  ASSERT_GT(rewound.shown.size(), 400u);
  EXPECT_EQ(rewound.shown.front(), base::Milliseconds(59480));
  for (size_t i = 1; i < rewound.shown.size(); ++i) {
    EXPECT_EQ(rewound.shown[i - 1] - rewound.shown[i], base::Milliseconds(40))
        << rewound.shown[i];
  }
}

// Parc: a window of 4K frames holds 16 of them, too few to last while 10
// seconds from a keyframe are decoded at 5x the frame rate. Frames are kept a
// stride apart instead, as AVPlayer drops frames, and time never waits.
TEST_F(ParcVideoRendererImplTest, ParcBackwardDropsFramesFor4K) {
  const ParcRewound rewound = ParcRewind(
      gfx::Size(3840, 2160), base::Milliseconds(40), base::Seconds(10),
      base::Milliseconds(8), base::Milliseconds(30), base::Milliseconds(59500),
      1, base::Seconds(20));

  EXPECT_EQ(rewound.holds, 0);
  EXPECT_EQ(rewound.time,
            base::Milliseconds(59500) - (base::Seconds(20) - rewound.started));
  ASSERT_GT(rewound.shown.size(), 40u);
  for (size_t i = 1; i < rewound.shown.size(); ++i) {
    EXPECT_GT(rewound.shown[i - 1], rewound.shown[i]);
    EXPECT_LE(rewound.shown[i - 1] - rewound.shown[i],
              base::Milliseconds(400))
        << rewound.shown[i];
  }
  EXPECT_GT(rewound.statistics.video_frames_dropped, 100u);
  EXPECT_GT(rewound.statistics.video_frames_decoded,
            rewound.statistics.video_frames_dropped);
}

// Parc: at -4x, frames are dropped rather than time waiting for them.
TEST_F(ParcVideoRendererImplTest, ParcBackwardDropsFramesAtFastRates) {
  const ParcRewound rewound = ParcRewind(
      gfx::Size(1920, 1080), base::Milliseconds(40), base::Seconds(4),
      base::Milliseconds(5), base::Milliseconds(30), base::Milliseconds(39500),
      4, base::Seconds(8));

  EXPECT_EQ(rewound.holds, 0);
  EXPECT_EQ(rewound.time, base::Milliseconds(39500) -
                              (base::Seconds(8) - rewound.started) * 4);
  ASSERT_GT(rewound.shown.size(), 100u);
  // Most frames are kept three apart (120 ms), more than the display drops.
  size_t strided = 0;
  for (size_t i = 1; i < rewound.shown.size(); ++i) {
    EXPECT_GT(rewound.shown[i - 1], rewound.shown[i]);
    EXPECT_LE(rewound.shown[i - 1] - rewound.shown[i],
              base::Milliseconds(400))
        << rewound.shown[i];
    if (rewound.shown[i - 1] - rewound.shown[i] >= base::Milliseconds(120)) {
      ++strided;
    }
  }
  EXPECT_GT(strided, rewound.shown.size() / 2);
  EXPECT_GT(rewound.statistics.video_frames_dropped, 100u);
  EXPECT_GT(rewound.statistics.video_frames_decoded,
            rewound.statistics.video_frames_dropped);
}

// Parc: rewinding from just after a keyframe, before any keyframe interval is
// known, time starts once the window before that keyframe is decoded too, so
// it doesn't wait there.
TEST_F(ParcVideoRendererImplTest, ParcBackwardStartsAfterTheKeyframeBefore) {
  const ParcRewound rewound = ParcRewind(
      gfx::Size(1920, 1080), base::Milliseconds(40), base::Seconds(10),
      base::Milliseconds(5), base::Milliseconds(30), base::Milliseconds(50300),
      1, base::Seconds(12));

  EXPECT_EQ(rewound.holds, 0);
  EXPECT_EQ(rewound.time,
            base::Milliseconds(50300) - (base::Seconds(12) - rewound.started));
  ASSERT_GT(rewound.shown.size(), 200u);
  for (size_t i = 1; i < rewound.shown.size(); ++i) {
    EXPECT_EQ(rewound.shown[i - 1] - rewound.shown[i], base::Milliseconds(40))
        << rewound.shown[i];
  }
}

TEST_F(ParcVideoRendererImplTest, ParcBackwardReportsByteBudgetDrops) {
  Initialize();
  base::OnceClosure seek_done;
  auto seek_demuxer = base::BindLambdaForTesting(
      [&](base::TimeDelta, base::OnceClosure done) {
        seek_done = std::move(done);
      });
  PipelineStatistics statistics;
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_))
      .WillRepeatedly([&](const PipelineStatistics& stats) {
        statistics.video_frames_decoded += stats.video_frames_decoded;
        statistics.video_frames_dropped += stats.video_frames_dropped;
      });
  EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
  renderer_->ParcStartPlayingBackwardFrom(base::Milliseconds(175), seek_demuxer);
  base::RunLoop().RunUntilIdle();
  std::move(seek_done).Run();
  WaitForPendingDecode();
  const gfx::Size size(3840, 2160);
  for (int i = 0; i < 19; ++i) {
    QueueFrame(DecoderStatus::Codes::kOk,
               VideoFrame::CreateFrame(PIXEL_FORMAT_I420, size, gfx::Rect(size),
                                       size, base::Milliseconds(i * 10)));
  }
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();
  const size_t retained = (192 * 1024 * 1024) /
      VideoFrame::AllocationSize(PIXEL_FORMAT_I420, size);
  EXPECT_EQ(statistics.video_frames_decoded, 19u);
  EXPECT_EQ(statistics.video_frames_dropped, 19u - retained);
  Destroy();
}

TEST_F(ParcVideoRendererImplTest, ParcForwardStatisticsUnchanged) {
  Initialize();
  PipelineStatistics statistics;
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_))
      .WillRepeatedly([&](const PipelineStatistics& stats) {
        statistics.video_frames_decoded += stats.video_frames_decoded;
        statistics.video_frames_dropped += stats.video_frames_dropped;
      });
  EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
  EXPECT_CALL(mock_cb_, OnVideoNaturalSizeChange(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, OnVideoOpacityChange(_)).Times(AnyNumber());
  EXPECT_CALL(mock_cb_, FrameReceived(HasTimestampMatcher(0)));
  QueueFrames("0 10 20 30");
  StartPlayingFrom(0);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(statistics.video_frames_decoded, 4u);
  EXPECT_EQ(statistics.video_frames_dropped, 0u);
  Destroy();
}

TEST_F(ParcVideoRendererImplTest, ParcBackwardReportsStrideDropsButNotEOS) {
  Initialize();
  simulate_decode_delay_ = true;
  EXPECT_CALL(*this, OnSimulateDecodeDelay())
      .WillRepeatedly(Return(base::Milliseconds(1)));
  time_source_.SetPlaybackRate(-4);
  base::OnceClosure seek_done;
  auto seek_demuxer = base::BindLambdaForTesting(
      [&](base::TimeDelta, base::OnceClosure done) {
        seek_done = std::move(done);
      });
  PipelineStatistics statistics;
  EXPECT_CALL(mock_cb_, OnStatisticsUpdate(_))
      .WillRepeatedly([&](const PipelineStatistics& stats) {
        statistics.video_frames_decoded += stats.video_frames_decoded;
        statistics.video_frames_dropped += stats.video_frames_dropped;
      });
  EXPECT_CALL(mock_cb_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
  renderer_->ParcStartPlayingBackwardFrom(base::Milliseconds(175), seek_demuxer);
  base::RunLoop().RunUntilIdle();
  std::move(seek_done).Run();
  WaitForPendingDecode();
  QueueFrames("0 10 20 30 40 50 60 70 80 90 100 110 120 130 140 150 160 170");
  SatisfyPendingDecode();
  base::RunLoop().RunUntilIdle();
  SatisfyPendingDecodeWithEndOfStream();
  base::RunLoop().RunUntilIdle();
  // At sample eight, the 4x display stride is 60 ms. Keep 0..60 and 120;
  // ten frames are discarded with neither budget reached. EOS adds neither.
  EXPECT_EQ(statistics.video_frames_decoded, 18u);
  EXPECT_EQ(statistics.video_frames_dropped, 10u);
  Destroy();
}

}  // namespace media

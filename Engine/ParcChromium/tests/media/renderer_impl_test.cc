// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/renderer_impl_test.cc. The fixture is derived
// from Chromium's renderer_impl_unittest.cc (Chromium Authors; BSD-style
// license in Chromium's LICENSE) and contains only Parc regressions.

#include "media/renderers/renderer_impl.h"

#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/run_loop.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/media_client.h"
#include "media/base/mock_filters.h"
#include "media/base/parc_demuxer_stream_extension.h"
#include "media/base/test_helpers.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::base::test::RunClosure;
using ::base::test::RunOnceCallback;
using ::base::test::RunOnceClosure;
using ::testing::_;
using ::testing::DoAll;
using ::testing::InSequence;
using ::testing::Mock;
using ::testing::Return;
using ::testing::SaveArg;
using ::testing::StrictMock;

namespace media {

constexpr int kStartPlayingTimeInMs = 100;

ACTION_P3(SetBufferingState, renderer_client, buffering_state, reason) {
  (*renderer_client)->OnBufferingStateChange(buffering_state, reason);
}

class ParcRendererImplTest : public ::testing::Test {
 public:
  class CallbackHelper : public MockRendererClient {
   public:
    CallbackHelper() = default;

    CallbackHelper(const CallbackHelper&) = delete;
    CallbackHelper& operator=(const CallbackHelper&) = delete;

    virtual ~CallbackHelper() = default;

    // Completion callbacks.
    MOCK_METHOD1(OnInitialize, void(PipelineStatus));
    MOCK_METHOD0(OnFlushed, void());
    MOCK_METHOD1(OnCdmAttached, void(bool));
    MOCK_METHOD0(OnVideoTrackChangeComplete, void());
    MOCK_METHOD0(OnAudioTrackChangeComplete, void());
  };

  ParcRendererImplTest()
      : video_renderer_(new StrictMock<MockVideoRenderer>()),
        audio_renderer_(new StrictMock<MockAudioRenderer>()),
        renderer_impl_(
            new RendererImpl(task_environment_.GetMainThreadTaskRunner(),
                             std::unique_ptr<AudioRenderer>(audio_renderer_),
                             std::unique_ptr<VideoRenderer>(video_renderer_))),
        cdm_context_(new StrictMock<MockCdmContext>()),
        demuxer_(new StrictMock<MockDemuxer>()),
        video_renderer_client_(nullptr),
        audio_renderer_client_(nullptr) {
    // CreateAudioStream() and CreateVideoStream() overrides expectations for
    // expected non-NULL streams.
    EXPECT_CALL(*demuxer_, GetAllStreams()).WillRepeatedly(Return(streams_));

    SetMediaClient(&media_client_);
    EXPECT_CALL(media_client_, ShouldSuppressAudioTracks())
        .WillRepeatedly(Return(false));
  }

  ParcRendererImplTest(const ParcRendererImplTest&) = delete;
  ParcRendererImplTest& operator=(const ParcRendererImplTest&) = delete;

  ~ParcRendererImplTest() override {
    Destroy();
    SetMediaClient(nullptr);
  }

 protected:
  void Destroy() {
    renderer_impl_.reset();
    base::RunLoop().RunUntilIdle();
  }

  std::unique_ptr<StrictMock<MockDemuxerStream>> CreateStream(
      DemuxerStream::Type type) {
    std::unique_ptr<StrictMock<MockDemuxerStream>> stream(
        new StrictMock<MockDemuxerStream>(type));
    return stream;
  }

  // Sets up expectations to allow the audio renderer to initialize.
  void SetAudioRendererInitializeExpectations(PipelineStatus status) {
    EXPECT_CALL(*audio_renderer_, OnInitialize(audio_stream_.get(), _, _, _))
        .WillOnce(DoAll(SaveArg<2>(&audio_renderer_client_),
                        RunOnceCallback<3>(status)));
  }

  // Sets up expectations to allow the video renderer to initialize.
  void SetVideoRendererInitializeExpectations(PipelineStatus status) {
    EXPECT_CALL(*video_renderer_, OnInitialize(video_stream_.get(), _, _, _, _))
        .WillOnce(DoAll(SaveArg<2>(&video_renderer_client_),
                        RunOnceCallback<4>(status)));
  }

  void InitializeAndExpect() {
    EXPECT_CALL(callbacks_, OnInitialize(PIPELINE_OK));
    EXPECT_CALL(*audio_renderer_, GetTimeSource())
        .WillOnce(Return(&time_source_));

    renderer_impl_->Initialize(demuxer_.get(), &callbacks_,
                               base::BindOnce(&CallbackHelper::OnInitialize,
                                              base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();

    ON_CALL(*audio_renderer_, Flush(_))
        .WillByDefault([this](base::OnceClosure on_done) {
          audio_renderer_client_->OnBufferingStateChange(
              BUFFERING_HAVE_NOTHING, BUFFERING_CHANGE_REASON_UNKNOWN);
          std::move(on_done).Run();
        });
    ON_CALL(*audio_renderer_, StartPlaying())
        .WillByDefault(SetBufferingState(&audio_renderer_client_,
                                         BUFFERING_HAVE_ENOUGH,
                                         BUFFERING_CHANGE_REASON_UNKNOWN));
    ON_CALL(*video_renderer_, Flush(_))
        .WillByDefault([this](base::OnceClosure on_done) {
          video_renderer_client_->OnBufferingStateChange(
              BUFFERING_HAVE_NOTHING, BUFFERING_CHANGE_REASON_UNKNOWN);
          std::move(on_done).Run();
        });
    ON_CALL(*video_renderer_, StartPlayingFrom(_))
        .WillByDefault(SetBufferingState(&video_renderer_client_,
                                         BUFFERING_HAVE_ENOUGH,
                                         BUFFERING_CHANGE_REASON_UNKNOWN));
  }

  void CreateAudioStream() {
    audio_stream_ = CreateStream(DemuxerStream::AUDIO);
    EXPECT_CALL(*audio_stream_, ManagesTrackSwitchesInternally())
        .WillRepeatedly(Return(false));
    streams_.push_back(audio_stream_.get());
    EXPECT_CALL(*demuxer_, GetAllStreams()).WillRepeatedly(Return(streams_));
  }

  void CreateVideoStream() {
    video_stream_ = CreateStream(DemuxerStream::VIDEO);
    video_stream_->set_video_decoder_config(TestVideoConfig::Normal());
    EXPECT_CALL(*video_stream_, ManagesTrackSwitchesInternally())
        .WillRepeatedly(Return(false));
    streams_.push_back(video_stream_.get());
    EXPECT_CALL(*demuxer_, GetAllStreams()).WillRepeatedly(Return(streams_));
  }

  void CreateAudioAndVideoStream() {
    CreateAudioStream();
    CreateVideoStream();
  }

  void InitializeWithAudioAndVideo() {
    CreateAudioAndVideoStream();
    SetAudioRendererInitializeExpectations(PIPELINE_OK);
    SetVideoRendererInitializeExpectations(PIPELINE_OK);
    InitializeAndExpect();
  }

  void Play(bool expect_audio = true) {
    DCHECK((audio_stream_ && expect_audio) || video_stream_);
    EXPECT_CALL(callbacks_,
                OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));

    base::TimeDelta start_time(base::Milliseconds(kStartPlayingTimeInMs));
    EXPECT_CALL(time_source_, SetMediaTime(start_time));
    EXPECT_CALL(time_source_, StartTicking());

    if (audio_stream_ && expect_audio) {
      EXPECT_CALL(*audio_renderer_, StartPlaying());
    }

    if (video_stream_) {
      EXPECT_CALL(*video_renderer_, StartPlayingFrom(start_time));
    }

    renderer_impl_->StartPlayingFrom(start_time);
    base::RunLoop().RunUntilIdle();
  }

  void SetFlushExpectationsForAVRenderers() {
    if (audio_stream_)
      EXPECT_CALL(*audio_renderer_, Flush(_));

    if (video_stream_)
      EXPECT_CALL(*video_renderer_, Flush(_));
  }

  void Flush(bool underflowed) {
    if (!underflowed)
      EXPECT_CALL(time_source_, StopTicking());

    SetFlushExpectationsForAVRenderers();
    EXPECT_CALL(callbacks_, OnFlushed());

    renderer_impl_->Flush(base::BindOnce(&CallbackHelper::OnFlushed,
                                         base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();
  }

  void SetPlaybackRate(double playback_rate) {
    EXPECT_CALL(time_source_, SetPlaybackRate(playback_rate));
    renderer_impl_->SetPlaybackRate(playback_rate);
    base::RunLoop().RunUntilIdle();
  }

  void SetCdmAndExpect(bool expected_result) {
    EXPECT_CALL(callbacks_, OnCdmAttached(expected_result));
    renderer_impl_->SetCdm(cdm_context_.get(),
                           base::BindOnce(&CallbackHelper::OnCdmAttached,
                                          base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();
  }

  // Fixture members.
  base::test::SingleThreadTaskEnvironment task_environment_;
  StrictMock<CallbackHelper> callbacks_;

  raw_ptr<StrictMock<MockVideoRenderer>, DanglingUntriaged> video_renderer_;
  raw_ptr<StrictMock<MockAudioRenderer>, DanglingUntriaged> audio_renderer_;
  std::unique_ptr<RendererImpl> renderer_impl_;
  std::unique_ptr<StrictMock<MockCdmContext>> cdm_context_;

  StrictMock<MockTimeSource> time_source_;
  std::unique_ptr<StrictMock<MockDemuxerStream>> audio_stream_;
  std::unique_ptr<StrictMock<MockDemuxerStream>> video_stream_;
  std::vector<raw_ptr<DemuxerStream>> streams_;
  std::unique_ptr<StrictMock<MockDemuxer>> demuxer_;
  raw_ptr<RendererClient, DanglingUntriaged> video_renderer_client_;
  raw_ptr<RendererClient, DanglingUntriaged> audio_renderer_client_;
  StrictMock<MockMediaClient> media_client_;
};

// Parc: playing backward (Safari's AVPlayer rewinding a file), audio stays
// flushed and silent, time waits for the video renderer's earlier frames
// without the page hearing it, and the start ends playback, as WebKit hears
// AVPlayerItemDidPlayToEndTime there (MediaPlayerPrivateAVFoundation::didEnd).
TEST_F(ParcRendererImplTest, ParcPlaysBackwardSilentlyAndEndsAtTheStart) {
  InitializeWithAudioAndVideo();
  Play();
  Flush(false);

  EXPECT_CALL(*audio_renderer_, StartPlaying()).Times(0);
  EXPECT_CALL(*video_renderer_, OnTimeProgressing()).Times(3);
  EXPECT_CALL(*video_renderer_, OnTimeStopped()).Times(3);
  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _))
      .Times(2);
  EXPECT_CALL(*video_renderer_,
              ParcStartPlayingBackwardFrom(base::Milliseconds(50), _));
  renderer_impl_->ParcStartPlayingBackwardFrom(base::Milliseconds(50), -1,
                                               base::DoNothing());
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(base::Milliseconds(50), renderer_impl_->GetMediaTime());

  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  EXPECT_LE(renderer_impl_->GetMediaTime(), base::Milliseconds(50));
  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_NOTHING, BUFFERING_CHANGE_REASON_UNKNOWN);
  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);

  // A flush gives the audio clock the time backward playback reached.
  EXPECT_CALL(time_source_, SetMediaTime(testing::Le(base::Milliseconds(50))));
  EXPECT_CALL(*video_renderer_, Flush(_));
  EXPECT_CALL(callbacks_, OnFlushed());
  renderer_impl_->Flush(base::BindOnce(&CallbackHelper::OnFlushed,
                                       base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();

  // Time goes back to 0, where playback ends once.
  EXPECT_CALL(*video_renderer_,
              ParcStartPlayingBackwardFrom(base::Milliseconds(10), _));
  renderer_impl_->ParcStartPlayingBackwardFrom(base::Milliseconds(10), -1,
                                               base::DoNothing());
  base::RunLoop ended;
  EXPECT_CALL(callbacks_, OnEnded()).WillOnce(RunClosure(ended.QuitClosure()));
  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  ended.Run();
  EXPECT_EQ(base::TimeDelta(), renderer_impl_->GetMediaTime());
  renderer_impl_->SetPlaybackRate(-2);
  base::RunLoop().RunUntilIdle();
}

// Parc: a demuxer whose streams may join a playing renderer (Safari's Media
// Source, MediaResource::ParcMayAddStreams()).
class ParcLateStreamsDemuxer : public MockDemuxer {
 public:
  bool ParcMayAddStreams() override { return true; }
};

// Parc: a SourceBuffer's audio added while video plays joins this renderer,
// as WebKit adds an audio renderer to its synchronizer: the video renderer
// stays, the clock waits at the current time (HAVE_NOTHING) for the audio,
// whose renderer then drives it.
TEST_F(ParcRendererImplTest, ParcAudioJoinsPlayingVideo) {
  StrictMock<ParcLateStreamsDemuxer> demuxer;
  CreateVideoStream();
  EXPECT_CALL(demuxer, GetAllStreams()).WillRepeatedly(Return(streams_));
  SetVideoRendererInitializeExpectations(PIPELINE_OK);
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->set_time_source_for_testing(&time_source_);
  renderer_impl_->Initialize(&demuxer, &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ON_CALL(*video_renderer_, StartPlayingFrom(_))
      .WillByDefault(SetBufferingState(&video_renderer_client_,
                                       BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
  Play();
  EXPECT_CALL(*video_renderer_, OnTimeProgressing());
  SetPlaybackRate(1.0);

  std::unique_ptr<StrictMock<MockDemuxerStream>> audio =
      CreateStream(DemuxerStream::AUDIO);
  StrictMock<MockTimeSource> audio_time_source;
  const base::TimeDelta now = base::Seconds(1);
  {
    InSequence join;
    EXPECT_CALL(*audio_renderer_, OnInitialize(audio.get(), _, _, _))
        .WillOnce(DoAll(SaveArg<2>(&audio_renderer_client_),
                        RunOnceCallback<3>(PIPELINE_OK)));
    EXPECT_CALL(time_source_, CurrentMediaTime()).WillOnce(Return(now));
    EXPECT_CALL(time_source_, StopTicking());
    EXPECT_CALL(*video_renderer_, OnTimeStopped());
    EXPECT_CALL(*audio_renderer_, GetTimeSource())
        .WillOnce(Return(&audio_time_source));
    EXPECT_CALL(audio_time_source, SetMediaTime(now));
    EXPECT_CALL(audio_time_source, SetPlaybackRate(1.0));
    EXPECT_CALL(*audio_renderer_, StartPlaying());
    EXPECT_CALL(callbacks_,
                OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
    EXPECT_CALL(*audio_renderer_, ParcSetOwnAudioMuted(false));
    EXPECT_CALL(callbacks_, OnAudioTrackChangeComplete());
  }
  renderer_impl_->OnTracksChanged(
      DemuxerStream::AUDIO, audio.get(),
      base::BindOnce(&CallbackHelper::OnAudioTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Mock::VerifyAndClearExpectations(&time_source_);

  EXPECT_CALL(audio_time_source, StartTicking());
  EXPECT_CALL(*video_renderer_, OnTimeProgressing());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  audio_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(audio_time_source, CurrentMediaTime())
      .WillOnce(Return(base::Seconds(2)));
  EXPECT_EQ(renderer_impl_->GetMediaTime(), base::Seconds(2));
  Destroy();
}

// Parc: so does video added while audio plays, as WebKit adds a display
// layer; it starts at the current time and the clock waits for its frame.
TEST_F(ParcRendererImplTest, ParcVideoJoinsPlayingAudio) {
  StrictMock<ParcLateStreamsDemuxer> demuxer;
  CreateAudioStream();
  EXPECT_CALL(demuxer, GetAllStreams()).WillRepeatedly(Return(streams_));
  SetAudioRendererInitializeExpectations(PIPELINE_OK);
  EXPECT_CALL(*audio_renderer_, GetTimeSource())
      .WillOnce(Return(&time_source_));
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->Initialize(&demuxer, &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ON_CALL(*audio_renderer_, StartPlaying())
      .WillByDefault(SetBufferingState(&audio_renderer_client_,
                                       BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
  Play();
  SetPlaybackRate(1.0);

  std::unique_ptr<StrictMock<MockDemuxerStream>> video =
      CreateStream(DemuxerStream::VIDEO);
  const base::TimeDelta now = base::Seconds(1);
  {
    InSequence join;
    EXPECT_CALL(*video_renderer_, OnInitialize(video.get(), _, _, _, _))
        .WillOnce(DoAll(SaveArg<2>(&video_renderer_client_),
                        RunOnceCallback<4>(PIPELINE_OK)));
    EXPECT_CALL(time_source_, CurrentMediaTime()).WillOnce(Return(now));
    EXPECT_CALL(time_source_, StopTicking());
    EXPECT_CALL(*video_renderer_, OnTimeStopped());
    EXPECT_CALL(*video_renderer_, StartPlayingFrom(now));
    EXPECT_CALL(callbacks_,
                OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
    EXPECT_CALL(callbacks_, OnVideoTrackChangeComplete());
  }
  renderer_impl_->OnTracksChanged(
      DemuxerStream::VIDEO, video.get(),
      base::BindOnce(&CallbackHelper::OnVideoTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(*video_renderer_, OnTimeProgressing());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  Destroy();
}

// Parc: a Media Source stream the page can turn off
// (ChunkDemuxerStream::ParcIsEnabled()).
class ParcTogglableStream : public MockDemuxerStream,
                            public ParcDemuxerStreamExtension {
 public:
  explicit ParcTogglableStream(const AudioDecoderConfig& config)
      : MockDemuxerStream(DemuxerStream::AUDIO) {
    set_audio_decoder_config(config);
  }
  ParcDemuxerStreamExtension* GetParcExtension() override { return this; }
  bool ParcIsEnabled() const override { return enabled; }
  DemuxerStream* ParcHandOffSource() override { return this; }

  bool enabled = true;
};

// Parc: every enabled audio stream of Safari's Media Source plays, as WebKit
// keeps a renderer per enabled audio track: the second one mixed into the
// first's output, its time started with the first's and only once both have
// enough. Turning tracks off removes the second and silences the first, which
// stays the clock; turning the first on again restarts it where playback is.
TEST_F(ParcRendererImplTest, ParcEveryEnabledAudioStreamPlaysMixed) {
  StrictMock<ParcLateStreamsDemuxer> demuxer;
  ParcTogglableStream first(TestAudioConfig::Normal());
  ParcTogglableStream second(TestAudioConfig::Normal());
  EXPECT_CALL(demuxer, GetAllStreams())
      .WillRepeatedly(
          Return(std::vector<raw_ptr<DemuxerStream>>{&first, &second}));
  EXPECT_CALL(*audio_renderer_, OnInitialize(&first, _, _, _))
      .WillOnce(DoAll(SaveArg<2>(&audio_renderer_client_),
                      RunOnceCallback<3>(PIPELINE_OK)));
  EXPECT_CALL(*audio_renderer_, GetTimeSource())
      .WillOnce(Return(&time_source_));
  auto owned_mixed = std::make_unique<StrictMock<MockAudioRenderer>>();
  StrictMock<MockAudioRenderer>* mixed = owned_mixed.get();
  RendererClient* mixed_client = nullptr;
  StrictMock<MockTimeSource> mixed_time_source;
  EXPECT_CALL(*mixed, GetTimeSource())
      .WillRepeatedly(Return(&mixed_time_source));
  EXPECT_CALL(*audio_renderer_, ParcCreateMixedRenderer())
      .WillOnce(Return(testing::ByMove(std::move(owned_mixed))));
  EXPECT_CALL(*mixed, SetLatencyHint(_));
  EXPECT_CALL(*mixed, SetPreservesPitch(true));
  EXPECT_CALL(*mixed, OnInitialize(&second, _, _, _))
      .WillOnce(
          DoAll(SaveArg<2>(&mixed_client), RunOnceCallback<3>(PIPELINE_OK)));
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->Initialize(&demuxer, &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(mixed_client);

  const base::TimeDelta start = base::Milliseconds(kStartPlayingTimeInMs);
  EXPECT_CALL(time_source_, SetMediaTime(start));
  EXPECT_CALL(*audio_renderer_, StartPlaying());
  EXPECT_CALL(mixed_time_source, SetMediaTime(start));
  EXPECT_CALL(mixed_time_source, SetPlaybackRate(0));
  EXPECT_CALL(*mixed, StartPlaying());
  renderer_impl_->StartPlayingFrom(start);
  audio_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(mixed_time_source, StartTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  mixed_client->OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(time_source_, SetPlaybackRate(1.0));
  EXPECT_CALL(mixed_time_source, SetPlaybackRate(1.0));
  renderer_impl_->SetPlaybackRate(1.0);

  first.enabled = false;
  EXPECT_CALL(*audio_renderer_, ParcSetOwnAudioMuted(true));
  EXPECT_CALL(callbacks_, OnAudioTrackChangeComplete());
  renderer_impl_->OnTracksChanged(
      DemuxerStream::AUDIO, &second,
      base::BindOnce(&CallbackHelper::OnAudioTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Mock::VerifyAndClearExpectations(audio_renderer_);
  Mock::VerifyAndClearExpectations(mixed);

  second.enabled = false;
  EXPECT_CALL(callbacks_, OnAudioTrackChangeComplete());
  renderer_impl_->OnTracksChanged(
      DemuxerStream::AUDIO, nullptr,
      base::BindOnce(&CallbackHelper::OnAudioTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Mock::VerifyAndClearExpectations(audio_renderer_);

  first.enabled = true;
  {
    InSequence restart;
    EXPECT_CALL(time_source_, CurrentMediaTime()).Times(2);
    EXPECT_CALL(time_source_, StopTicking());
    EXPECT_CALL(*audio_renderer_, Flush(_))
        .WillOnce(RunOnceClosure<0>());
    EXPECT_CALL(time_source_, SetMediaTime(_));
    EXPECT_CALL(*audio_renderer_, ParcSetOwnAudioMuted(false));
    EXPECT_CALL(*audio_renderer_, StartPlaying());
    EXPECT_CALL(callbacks_, OnAudioTrackChangeComplete());
  }
  renderer_impl_->OnTracksChanged(
      DemuxerStream::AUDIO, &first,
      base::BindOnce(&CallbackHelper::OnAudioTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Destroy();
}

// Parc: Chrome's identity keeps Chromium's one audio stream.
TEST_F(ParcRendererImplTest, ParcChromePlaysFirstEnabledAudioStreamOnly) {
  ParcTogglableStream first(TestAudioConfig::Normal());
  ParcTogglableStream second(TestAudioConfig::Normal());
  EXPECT_CALL(*demuxer_, GetAllStreams())
      .WillRepeatedly(
          Return(std::vector<raw_ptr<DemuxerStream>>{&first, &second}));
  EXPECT_CALL(*audio_renderer_, OnInitialize(&first, _, _, _))
      .WillOnce(DoAll(SaveArg<2>(&audio_renderer_client_),
                      RunOnceCallback<3>(PIPELINE_OK)));
  EXPECT_CALL(*audio_renderer_, GetTimeSource())
      .WillOnce(Return(&time_source_));
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->Initialize(demuxer_.get(), &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();

  const base::TimeDelta start = base::Milliseconds(kStartPlayingTimeInMs);
  EXPECT_CALL(time_source_, SetMediaTime(start));
  EXPECT_CALL(*audio_renderer_, StartPlaying());
  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  renderer_impl_->StartPlayingFrom(start);
  audio_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  Destroy();
}

// Parc: an encrypted audio stream enabled before any CDM is set waits for
// one, time held as WebKit's synchronizer holds it for samples it can't
// decrypt yet; it then joins the playing renderer with that CDM, no restart.
TEST_F(ParcRendererImplTest, ParcEncryptedAudioJoinsOnceCdmIsSet) {
  StrictMock<ParcLateStreamsDemuxer> demuxer;
  ParcTogglableStream first(TestAudioConfig::Normal());
  ParcTogglableStream second(TestAudioConfig::NormalEncrypted());
  EXPECT_CALL(demuxer, GetAllStreams())
      .WillRepeatedly(Return(std::vector<raw_ptr<DemuxerStream>>{&first}));
  EXPECT_CALL(*audio_renderer_, OnInitialize(&first, _, _, _))
      .WillOnce(DoAll(SaveArg<2>(&audio_renderer_client_),
                      RunOnceCallback<3>(PIPELINE_OK)));
  EXPECT_CALL(*audio_renderer_, GetTimeSource())
      .WillOnce(Return(&time_source_));
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->Initialize(&demuxer, &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  const base::TimeDelta start = base::Milliseconds(kStartPlayingTimeInMs);
  EXPECT_CALL(time_source_, SetMediaTime(start));
  EXPECT_CALL(*audio_renderer_, StartPlaying());
  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  renderer_impl_->StartPlayingFrom(start);
  audio_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(demuxer, GetAllStreams())
      .WillRepeatedly(
          Return(std::vector<raw_ptr<DemuxerStream>>{&first, &second}));
  EXPECT_CALL(callbacks_, OnWaiting(WaitingReason::kNoCdm));
  EXPECT_CALL(time_source_, StopTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  EXPECT_CALL(callbacks_, OnAudioTrackChangeComplete());
  renderer_impl_->OnTracksChanged(
      DemuxerStream::AUDIO, &first,
      base::BindOnce(&CallbackHelper::OnAudioTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Mock::VerifyAndClearExpectations(&time_source_);

  auto owned_mixed = std::make_unique<StrictMock<MockAudioRenderer>>();
  StrictMock<MockAudioRenderer>* mixed = owned_mixed.get();
  RendererClient* mixed_client = nullptr;
  StrictMock<MockTimeSource> mixed_time_source;
  const base::TimeDelta now = base::Seconds(1);
  EXPECT_CALL(*mixed, GetTimeSource())
      .WillRepeatedly(Return(&mixed_time_source));
  EXPECT_CALL(*audio_renderer_, ParcCreateMixedRenderer())
      .WillOnce(Return(testing::ByMove(std::move(owned_mixed))));
  EXPECT_CALL(*mixed, SetLatencyHint(_));
  EXPECT_CALL(*mixed, SetPreservesPitch(true));
  EXPECT_CALL(*mixed, OnInitialize(&second, cdm_context_.get(), _, _))
      .WillOnce(
          DoAll(SaveArg<2>(&mixed_client), RunOnceCallback<3>(PIPELINE_OK)));
  EXPECT_CALL(time_source_, CurrentMediaTime()).WillOnce(Return(now));
  EXPECT_CALL(mixed_time_source, SetMediaTime(now));
  EXPECT_CALL(mixed_time_source, SetPlaybackRate(0));
  EXPECT_CALL(*mixed, StartPlaying());
  SetCdmAndExpect(true);
  ASSERT_TRUE(mixed_client);

  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(mixed_time_source, StartTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  mixed_client->OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  Destroy();
}

// Parc: so does encrypted video joining playing audio.
TEST_F(ParcRendererImplTest, ParcEncryptedVideoJoinsOnceCdmIsSet) {
  StrictMock<ParcLateStreamsDemuxer> demuxer;
  CreateAudioStream();
  EXPECT_CALL(demuxer, GetAllStreams()).WillRepeatedly(Return(streams_));
  SetAudioRendererInitializeExpectations(PIPELINE_OK);
  EXPECT_CALL(*audio_renderer_, GetTimeSource())
      .WillOnce(Return(&time_source_));
  EXPECT_CALL(callbacks_, OnInitialize(_));
  renderer_impl_->Initialize(&demuxer, &callbacks_,
                             base::BindOnce(&CallbackHelper::OnInitialize,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ON_CALL(*audio_renderer_, StartPlaying())
      .WillByDefault(SetBufferingState(&audio_renderer_client_,
                                       BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
  Play();
  SetPlaybackRate(1.0);

  std::unique_ptr<StrictMock<MockDemuxerStream>> video =
      CreateStream(DemuxerStream::VIDEO);
  video->set_video_decoder_config(TestVideoConfig::NormalEncrypted());
  EXPECT_CALL(callbacks_, OnWaiting(WaitingReason::kNoCdm));
  EXPECT_CALL(time_source_, StopTicking());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  EXPECT_CALL(callbacks_, OnVideoTrackChangeComplete());
  renderer_impl_->OnTracksChanged(
      DemuxerStream::VIDEO, video.get(),
      base::BindOnce(&CallbackHelper::OnVideoTrackChangeComplete,
                     base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  Mock::VerifyAndClearExpectations(&time_source_);

  const base::TimeDelta now = base::Seconds(1);
  {
    InSequence join;
    EXPECT_CALL(*video_renderer_,
                OnInitialize(video.get(), cdm_context_.get(), _, _, _))
        .WillOnce(DoAll(SaveArg<2>(&video_renderer_client_),
                        RunOnceCallback<4>(PIPELINE_OK)));
    EXPECT_CALL(time_source_, CurrentMediaTime()).WillOnce(Return(now));
    EXPECT_CALL(*video_renderer_, StartPlayingFrom(now));
  }
  SetCdmAndExpect(true);

  EXPECT_CALL(time_source_, StartTicking());
  EXPECT_CALL(*video_renderer_, OnTimeProgressing());
  EXPECT_CALL(callbacks_,
              OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                     BUFFERING_CHANGE_REASON_UNKNOWN));
  video_renderer_client_->OnBufferingStateChange(
      BUFFERING_HAVE_ENOUGH, BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  Destroy();
}

}  // namespace media

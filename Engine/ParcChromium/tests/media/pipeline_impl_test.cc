// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/pipeline_impl_test.cc. The fixture is
// derived from Chromium's pipeline_impl_unittest.cc (Chromium Authors;
// BSD-style license in Chromium's LICENSE) and contains only Parc regressions.

#include "media/base/pipeline_impl.h"

#include <stddef.h>

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/mock_callback.h"
#include "base/test/task_environment.h"
#include "base/time/time.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/parc_native_hls_source.h"
#include "media/base/test_helpers.h"
#include "testing/gtest/include/gtest/gtest.h"

using ::base::test::RunClosure;
using ::base::test::RunOnceCallback;
using ::base::test::RunOnceClosure;
using ::testing::_;
using ::testing::AnyNumber;
using ::testing::DeleteArg;
using ::testing::DoAll;
using ::testing::Invoke;
using ::testing::InvokeWithoutArgs;
using ::testing::Mock;
using ::testing::NiceMock;
using ::testing::Return;
using ::testing::SaveArg;
using ::testing::StrictMock;

namespace media {

ACTION_P(SetDemuxerProperties, duration) {
  arg0->SetDuration(duration);
}

ACTION_P3(SetBufferingState, renderer_client, buffering_state, reason) {
  (*renderer_client)->OnBufferingStateChange(buffering_state, reason);
}

ACTION_TEMPLATE(PostCallback,
                HAS_1_TEMPLATE_PARAMS(int, k),
                AND_1_VALUE_PARAMS(p0)) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(std::get<k>(args)), p0));
}

// TODO(scherkus): even though some filters are initialized on separate
// threads these test aren't flaky... why?  It's because filters' Initialize()
// is executed on |message_loop_| and the mock filters instantly call
// InitializationComplete(), which keeps the pipeline humming along.  If
// either filters don't call InitializationComplete() immediately or filter
// initialization is moved to a separate thread this test will become flaky.
// Pipeline tests use a mock renderer, so of the native source only the CDM
// the pipeline hands over is used: it keeps the last offer.
class ParcFakeNativeHlsSource : public parc::fairplay::NativeHlsSource {
 public:
  void SetCdm(CdmContext* cdm_context, CdmAttachedCB cdm_attached_cb) override {
    cdm_offer = std::move(cdm_attached_cb);
  }
  base::OnceCallback<void(bool)> cdm_offer;

  void SetClient(Client* client) override {}
  void Play(double rate) override {}
  void Pause() override {}
  void SetVolume(float volume) override {}
  void SetPreservesPitch(bool preserves_pitch) override {}
  void SetAudioOutputDevice(const std::string& sink_id) override {}
  BufferingState GetBufferingState() const override {
    return BUFFERING_HAVE_NOTHING;
  }
  base::TimeDelta GetMediaTime() override { return base::TimeDelta(); }
  Timeline GetTimeline() const override { return Timeline(); }
  void ProvideClearKey(const std::string& key_id,
                       const std::vector<uint8_t>& key) override {}
  void PrepareToPlay() override {}
  void SetPlaybackTarget(const std::string& output_context_id,
                         bool should_play) override {}
  void SetWirelessVideoPlaybackDisabled(bool disabled) override {}
  void SelectFileTracks(const FileTracks& tracks) override {}
  base::WeakPtr<NativeHlsSource> GetWeakPtr() override {
    return weak_factory_.GetWeakPtr();
  }

 private:
  base::WeakPtrFactory<ParcFakeNativeHlsSource> weak_factory_{this};
};

class ParcRateDemuxer : public MockDemuxer {
 public:
  parc::fairplay::NativeHlsSource* GetParcNativeHlsSource() override {
    return native_hls ? &native_source : nullptr;
  }
  ParcFakeNativeHlsSource native_source;
  bool native_hls = false;

  // A hand-off (Demuxer::ParcBeginHandOff()) whose split the test makes.
  MediaResource* ParcBeginHandOff() override { return handoff ? this : nullptr; }
  void ParcSplitForHandOff(
      base::TimeDelta not_before,
      base::OnceCallback<void(base::TimeDelta)> split_cb) override {
    split_asked = not_before;
    split = std::move(split_cb);
  }
  void ParcEndHandOff() override { ++handoff_ends; }
  bool handoff = false;
  base::TimeDelta split_asked;
  base::OnceCallback<void(base::TimeDelta)> split;
  int handoff_ends = 0;
};

// Parc: a FairPlay CDM, which needs the FairPlay Renderer.
class ParcFairPlayCdmContext : public MockCdmContext {
 public:
  bool RequiresFairPlayRenderer() override { return true; }
};

class ParcPipelineImplTest : public ::testing::Test {
 public:
  // Used for setting expectations on pipeline callbacks.  Using a StrictMock
  // also lets us test for missing callbacks.
  class CallbackHelper : public MockPipelineClient {
   public:
    CallbackHelper() = default;

    CallbackHelper(const CallbackHelper&) = delete;
    CallbackHelper& operator=(const CallbackHelper&) = delete;

    virtual ~CallbackHelper() = default;

    MOCK_METHOD1(OnStart, void(PipelineStatus));
    MOCK_METHOD1(OnSeek, void(PipelineStatus));
    MOCK_METHOD1(OnSuspend, void(PipelineStatus));
    MOCK_METHOD1(OnResume, void(PipelineStatus));
    MOCK_METHOD1(OnCdmAttached, void(bool));
  };

  ParcPipelineImplTest()
      : scoped_renderer_(std::make_unique<StrictMock<MockRenderer>>()),
        renderer_(scoped_renderer_->AsWeakPtr()),
        demuxer_(std::make_unique<StrictMock<ParcRateDemuxer>>()) {
    pipeline_ = std::make_unique<PipelineImpl>(
        task_environment_.GetMainThreadTaskRunner(),
        task_environment_.GetMainThreadTaskRunner(),
        base::BindRepeating(&ParcPipelineImplTest::TakeRenderer,
                            base::Unretained(this)),
        &media_log_);

    // SetDemuxerExpectations() adds overriding expectations for expected
    // non-NULL streams.
    std::vector<raw_ptr<DemuxerStream>> empty;
    EXPECT_CALL(*demuxer_, GetAllStreams()).WillRepeatedly(Return(empty));

    EXPECT_CALL(*demuxer_, GetTimelineOffset())
        .WillRepeatedly(Return(base::Time()));

    EXPECT_CALL(*renderer_, GetMediaTime())
        .WillRepeatedly(Return(base::TimeDelta()));

    EXPECT_CALL(*demuxer_, GetStartTime()).WillRepeatedly(Return(start_time_));

    EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  }

  ParcPipelineImplTest(const ParcPipelineImplTest&) = delete;
  ParcPipelineImplTest& operator=(const ParcPipelineImplTest&) = delete;

  ~ParcPipelineImplTest() override {
    if (pipeline_->IsRunning()) {
      ExpectDemuxerStop();

      pipeline_->Stop();
    }

    pipeline_.reset();
    base::RunLoop().RunUntilIdle();
  }

 protected:
  // Sets up expectations to allow the demuxer to initialize.
  void SetDemuxerExpectations(base::TimeDelta duration) {
    EXPECT_CALL(callbacks_, OnDurationChange());
    EXPECT_CALL(*demuxer_, OnInitialize(_, _))
        .WillOnce(DoAll(SaveArg<0>(&demuxer_host_),
                        SetDemuxerProperties(duration),
                        PostCallback<1>(PIPELINE_OK)));
    EXPECT_CALL(*demuxer_, GetAllStreams()).WillRepeatedly(Return(streams_));
  }

  void SetDemuxerExpectations() {
    // Initialize with a default non-zero duration.
    SetDemuxerExpectations(base::Seconds(10));
  }

  std::unique_ptr<StrictMock<MockDemuxerStream>> CreateStream(
      DemuxerStream::Type type) {
    return std::make_unique<StrictMock<MockDemuxerStream>>(type);
  }

  // Sets up expectations to allow the renderer to initialize.
  void ExpectRendererInitialization() {
    EXPECT_CALL(*renderer_, OnInitialize(_, _, _))
        .WillOnce(
            DoAll(SaveArg<1>(&renderer_client_), PostCallback<2>(PIPELINE_OK)));
  }

  void StartPipeline(
      Pipeline::StartType start_type = Pipeline::StartType::kNormal) {
    EXPECT_CALL(callbacks_, OnWaiting(_)).Times(0);
    pipeline_->Start(start_type, demuxer_.get(), &callbacks_,
                     base::BindOnce(&CallbackHelper::OnStart,
                                    base::Unretained(&callbacks_)));
  }

  void SetRendererPostStartExpectations() {
    EXPECT_CALL(*renderer_, SetPlaybackRate(0.0));
    EXPECT_CALL(*renderer_, SetVolume(1.0f));
    EXPECT_CALL(*renderer_,
                SetWasPlayedWithUserActivationAndHighMediaEngagement(false));
    EXPECT_CALL(*renderer_, StartPlayingFrom(start_time_))
        .WillOnce(SetBufferingState(&renderer_client_, BUFFERING_HAVE_ENOUGH,
                                    BUFFERING_CHANGE_REASON_UNKNOWN));
    EXPECT_CALL(callbacks_,
                OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
  }

  // Suspension status of the pipeline post Start().
  enum class PostStartStatus {
    kNormal,
    kSuspended,
  };

  // Sets up expectations on the callback and initializes the pipeline. Called
  // after tests have set expectations any filters they wish to use.
  void StartPipelineAndExpect(
      PipelineStatus start_status,
      Pipeline::StartType start_type = Pipeline::StartType::kNormal,
      PostStartStatus post_start_status = PostStartStatus::kNormal) {
    EXPECT_CALL(callbacks_, OnStart(SameStatusCode(start_status)));

    if (start_status == PIPELINE_OK) {
      EXPECT_CALL(callbacks_, OnMetadata(_)).WillOnce(SaveArg<0>(&metadata_));

      if (start_type == Pipeline::StartType::kNormal)
        ExpectRendererInitialization();

      if (post_start_status == PostStartStatus::kNormal)
        SetRendererPostStartExpectations();
    }

    StartPipeline(start_type);
    base::RunLoop().RunUntilIdle();

    if (start_status == PIPELINE_OK)
      EXPECT_TRUE(pipeline_->IsRunning());

    if (post_start_status != PostStartStatus::kNormal)
      EXPECT_TRUE(pipeline_->IsSuspended());
  }

  void CreateAudioStream() {
    audio_stream_ = CreateStream(DemuxerStream::AUDIO);
    streams_.push_back(audio_stream_.get());
  }

  void CreateVideoStream(bool is_encrypted = false) {
    video_stream_ = CreateStream(DemuxerStream::VIDEO);
    video_stream_->set_video_decoder_config(
        is_encrypted ? TestVideoConfig::NormalEncrypted()
                     : TestVideoConfig::Normal());
    streams_.push_back(video_stream_.get());
  }

  void CreateAudioAndVideoStream() {
    CreateAudioStream();
    CreateVideoStream();
  }

  void CreateEncryptedVideoStream() { CreateVideoStream(true); }

  void SetCdmAndExpect(bool expected_result) {
    EXPECT_CALL(*renderer_, OnSetCdm(_, _)).WillOnce(RunOnceCallback<1>(true));
    EXPECT_CALL(callbacks_, OnCdmAttached(expected_result));
    pipeline_->SetCdm(&cdm_context_,
                      base::BindOnce(&CallbackHelper::OnCdmAttached,
                                     base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();
  }

  void ExpectSeek(const base::TimeDelta& seek_time, bool underflowed) {
    EXPECT_CALL(*demuxer_, AbortPendingReads());
    EXPECT_CALL(*demuxer_, OnSeek(seek_time, _))
        .WillOnce(RunOnceCallback<1>(PIPELINE_OK));

    EXPECT_CALL(*renderer_, OnFlush(_)).WillOnce(RunOnceClosure<0>());
    EXPECT_CALL(*renderer_, SetPlaybackRate(_));
    EXPECT_CALL(*renderer_, StartPlayingFrom(seek_time))
        .WillOnce(SetBufferingState(&renderer_client_, BUFFERING_HAVE_ENOUGH,
                                    BUFFERING_CHANGE_REASON_UNKNOWN));

    // We expect a successful seek callback followed by a buffering update.
    EXPECT_CALL(callbacks_, OnSeek(HasStatusCode(PIPELINE_OK)));
    EXPECT_CALL(callbacks_,
                OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                       BUFFERING_CHANGE_REASON_UNKNOWN));
  }

  void DoSeek(const base::TimeDelta& seek_time) {
    pipeline_->Seek(seek_time, base::BindOnce(&CallbackHelper::OnSeek,
                                              base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();
  }

  void ExpectSuspend() {
    EXPECT_CALL(*demuxer_, AbortPendingReads());
    EXPECT_CALL(*renderer_, SetPlaybackRate(0));
    EXPECT_CALL(callbacks_, OnSuspend(HasStatusCode(PIPELINE_OK)));
  }

  void DoSuspend() {
    pipeline_->Suspend(base::BindOnce(&CallbackHelper::OnSuspend,
                                      base::Unretained(&callbacks_)));
    base::RunLoop().RunUntilIdle();
    ResetRenderer();
  }

  std::unique_ptr<Renderer> TakeRenderer(
      std::optional<RendererType> /* renderer_type */) {
    return std::move(scoped_renderer_);
  }

  void ResetRenderer() {
    // |renderer_| has been deleted, replace it.
    scoped_renderer_ = std::make_unique<StrictMock<MockRenderer>>();
    renderer_ = scoped_renderer_->AsWeakPtr();
    EXPECT_CALL(*renderer_, SetPreservesPitch(_)).Times(AnyNumber());
  }

  void ExpectDemuxerStop() {
    if (demuxer_)
      EXPECT_CALL(*demuxer_, Stop());
  }

  // Fixture members.
  StrictMock<CallbackHelper> callbacks_;
  base::test::SingleThreadTaskEnvironment task_environment_;
  NullMediaLog media_log_;
  std::unique_ptr<PipelineImpl> pipeline_;
  NiceMock<MockCdmContext> cdm_context_;

  std::unique_ptr<StrictMock<MockRenderer>> scoped_renderer_;
  base::WeakPtr<MockRenderer> renderer_;
  std::unique_ptr<StrictMock<MockDemuxerStream>> audio_stream_;
  std::unique_ptr<StrictMock<MockDemuxerStream>> video_stream_;
  std::vector<raw_ptr<DemuxerStream>> streams_;
  std::unique_ptr<StrictMock<ParcRateDemuxer>> demuxer_;
  raw_ptr<DemuxerHost, DanglingUntriaged> demuxer_host_ = nullptr;
  raw_ptr<RendererClient, DanglingUntriaged> renderer_client_ = nullptr;
  PipelineMetadata metadata_;
  base::TimeDelta start_time_;
};

TEST_F(ParcPipelineImplTest, ParcEarlyCdmCompletesOnStopAndSurvivesTheNextStart) {
  demuxer_->native_hls = true;
  EXPECT_CALL(*demuxer_, OnInitialize(_, _));
  StartPipeline();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(callbacks_, OnCdmAttached(_)).Times(0);
  pipeline_->SetCdm(&cdm_context_, base::BindOnce(
      &CallbackHelper::OnCdmAttached, base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(demuxer_->native_source.cdm_offer);
  Mock::VerifyAndClearExpectations(&callbacks_);
  EXPECT_CALL(callbacks_, OnCdmAttached(true));
  EXPECT_CALL(*demuxer_, Stop()).WillOnce([&] {
    std::move(demuxer_->native_source.cdm_offer).Run(true);
  });
  pipeline_->Stop();
  base::RunLoop().RunUntilIdle();
  scoped_renderer_ = std::make_unique<StrictMock<MockRenderer>>(
      RendererType::kFairPlayHls);
  renderer_ = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::TimeDelta()));
  EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  EXPECT_CALL(*renderer_, OnSetCdm(&cdm_context_, _))
      .WillOnce(RunOnceCallback<1>(true));
  CreateAudioStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);
}

TEST_F(ParcPipelineImplTest, ParcRefusedEarlyCdmIsNotUsedOnTheNextStart) {
  demuxer_->native_hls = true;
  EXPECT_CALL(*demuxer_, OnInitialize(_, _));
  StartPipeline();
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(callbacks_, OnCdmAttached(_)).Times(0);
  pipeline_->SetCdm(&cdm_context_, base::BindOnce(
      &CallbackHelper::OnCdmAttached, base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(demuxer_->native_source.cdm_offer);
  Mock::VerifyAndClearExpectations(&callbacks_);
  EXPECT_CALL(callbacks_, OnCdmAttached(false));
  std::move(demuxer_->native_source.cdm_offer).Run(false);
  base::RunLoop().RunUntilIdle();
  ExpectDemuxerStop();
  pipeline_->Stop();
  base::RunLoop().RunUntilIdle();
  scoped_renderer_ = std::make_unique<StrictMock<MockRenderer>>(
      RendererType::kFairPlayHls);
  renderer_ = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::TimeDelta()));
  EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  EXPECT_CALL(*renderer_, OnSetCdm(_, _)).Times(0);
  CreateAudioStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);
}

// Parc: Chromium's renderer hands over to the FairPlay Renderer without a
// restart: the FairPlay Renderer reads the demuxer's hand-off streams,
// prerolls paused at the split, and takes over when the playing renderer
// reaches the end of its part there, which the page doesn't hear as ended.
TEST_F(ParcPipelineImplTest, ParcHandOffTakesOverAtTheSplit) {
  demuxer_->handoff = true;
  CreateAudioAndVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  scoped_renderer_ =
      std::make_unique<StrictMock<MockRenderer>>(RendererType::kFairPlay);
  base::WeakPtr<MockRenderer> fairplay = scoped_renderer_->AsWeakPtr();
  RendererClient* fairplay_client = nullptr;
  EXPECT_CALL(*fairplay, GetMediaTime())
      .WillRepeatedly(Return(base::TimeDelta()));
  EXPECT_CALL(*fairplay, SetPreservesPitch(_)).Times(AnyNumber());
  EXPECT_CALL(*fairplay, SetVolume(_)).Times(AnyNumber());
  EXPECT_CALL(*fairplay,
              SetWasPlayedWithUserActivationAndHighMediaEngagement(_))
      .Times(AnyNumber());
  EXPECT_CALL(*fairplay, OnInitialize(_, _, _))
      .WillOnce(
          DoAll(SaveArg<1>(&fairplay_client), PostCallback<2>(PIPELINE_OK)));
  std::optional<bool> handed_off;
  pipeline_->ParcHandOffToFairPlay(base::BindOnce(
      [](std::optional<bool>* out, bool done) { *out = done; }, &handed_off));
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(demuxer_->split);
  EXPECT_EQ(demuxer_->split_asked, base::Milliseconds(500));
  EXPECT_FALSE(handed_off);

  EXPECT_CALL(*fairplay, StartPlayingFrom(base::Seconds(1)));
  std::move(demuxer_->split).Run(base::Seconds(1));
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(*renderer_, SetPlaybackRate(1.0));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(1.0));
  pipeline_->SetPlaybackRate(1.0);
  base::RunLoop().RunUntilIdle();

  // Prerolled, it runs on the playing renderer's clock, so the two meet at
  // the split: at that renderer's rate, and stopped while it is.
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::Milliseconds(700)));
  EXPECT_CALL(*fairplay,
              ParcSetPlaybackRateAt(1.0, base::Milliseconds(700), _));
  fairplay_client->OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                          BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(*renderer_, SetPlaybackRate(0.0));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(0.0));
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::Milliseconds(750)));
  EXPECT_CALL(*fairplay,
              ParcSetPlaybackRateAt(0.0, base::Milliseconds(750), _));
  pipeline_->SetPlaybackRate(0.0);
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(*renderer_, SetPlaybackRate(1.0));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(1.0));
  EXPECT_CALL(*fairplay,
              ParcSetPlaybackRateAt(1.0, base::Milliseconds(750), _));
  pipeline_->SetPlaybackRate(1.0);
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_NOTHING, _));
  EXPECT_CALL(*fairplay,
              ParcSetPlaybackRateAt(0.0, base::Milliseconds(750), _));
  renderer_client_->OnBufferingStateChange(BUFFERING_HAVE_NOTHING,
                                           BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();
  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
  EXPECT_CALL(*fairplay,
              ParcSetPlaybackRateAt(1.0, base::Milliseconds(750), _));
  renderer_client_->OnBufferingStateChange(BUFFERING_HAVE_ENOUGH,
                                           BUFFERING_CHANGE_REASON_UNKNOWN);
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(callbacks_, OnEnded()).Times(0);
  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_ENOUGH, _));
  EXPECT_CALL(*fairplay, SetPlaybackRate(_));
  renderer_client_->OnEnded();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(renderer_);
  EXPECT_EQ(handed_off, true);
  EXPECT_EQ(demuxer_->handoff_ends, 0);

  // Afterwards the FairPlay Renderer is the pipeline's, its end the page's.
  EXPECT_CALL(callbacks_, OnEnded());
  fairplay_client->OnEnded();
  base::RunLoop().RunUntilIdle();
}

// Parc: a FairPlay Renderer that fails before the split leaves the playing
// renderer as it was and the caller restarts.
TEST_F(ParcPipelineImplTest, ParcHandOffFailureLeavesThePlayingRenderer) {
  demuxer_->handoff = true;
  CreateAudioAndVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  scoped_renderer_ =
      std::make_unique<StrictMock<MockRenderer>>(RendererType::kFairPlay);
  base::WeakPtr<MockRenderer> fairplay = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*fairplay, SetPreservesPitch(_)).Times(AnyNumber());
  EXPECT_CALL(*fairplay, SetVolume(_)).Times(AnyNumber());
  EXPECT_CALL(*fairplay,
              SetWasPlayedWithUserActivationAndHighMediaEngagement(_))
      .Times(AnyNumber());
  EXPECT_CALL(*fairplay, OnInitialize(_, _, _))
      .WillOnce(PostCallback<2>(PIPELINE_ERROR_INITIALIZATION_FAILED));
  std::optional<bool> handed_off;
  pipeline_->ParcHandOffToFairPlay(base::BindOnce(
      [](std::optional<bool>* out, bool done) { *out = done; }, &handed_off));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(handed_off, false);
  EXPECT_FALSE(fairplay);
  EXPECT_TRUE(renderer_);
  EXPECT_EQ(demuxer_->handoff_ends, 1);
}

// Parc: where the demuxer can't hand off (not Safari's Media Source), the
// caller restarts and nothing changes.
TEST_F(ParcPipelineImplTest, ParcHandOffRefusedWithoutHandOffStreams) {
  CreateAudioAndVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);
  std::optional<bool> handed_off;
  pipeline_->ParcHandOffToFairPlay(base::BindOnce(
      [](std::optional<bool>* out, bool done) { *out = done; }, &handed_off));
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(handed_off, false);
  EXPECT_TRUE(renderer_);
}

// Parc: what ends a hand-off, or completes it, before the playing renderer
// reaches its split: a seek, a suspend, a new CDM, a turn of direction, and
// the FairPlay Renderer's own end.
class ParcPipelineHandOffTest : public ParcPipelineImplTest {
 protected:
  // A hand-off whose FairPlay Renderer initialized; the demuxer holds the
  // split asked for.
  void StartHandOff() {
    demuxer_->handoff = true;
    CreateAudioAndVideoStream();
    SetDemuxerExpectations();
    StartPipelineAndExpect(PIPELINE_OK);

    scoped_renderer_ =
        std::make_unique<StrictMock<MockRenderer>>(RendererType::kFairPlay);
    fairplay_ = scoped_renderer_->AsWeakPtr();
    EXPECT_CALL(*fairplay_, GetMediaTime())
        .WillRepeatedly(Return(base::TimeDelta()));
    EXPECT_CALL(*fairplay_, SetPreservesPitch(_)).Times(AnyNumber());
    EXPECT_CALL(*fairplay_, SetVolume(_)).Times(AnyNumber());
    EXPECT_CALL(*fairplay_,
                SetWasPlayedWithUserActivationAndHighMediaEngagement(_))
        .Times(AnyNumber());
    EXPECT_CALL(*fairplay_, OnInitialize(_, _, _))
        .WillOnce(DoAll(SaveArg<1>(&fairplay_client_),
                        PostCallback<2>(PIPELINE_OK)));
    pipeline_->ParcHandOffToFairPlay(base::BindOnce(
        [](std::optional<bool>* out, bool done) { *out = done; },
        &handed_off_));
    base::RunLoop().RunUntilIdle();
    ASSERT_TRUE(demuxer_->split);
  }

  // The demuxer splits at |time|, where the FairPlay Renderer starts.
  void Split(base::TimeDelta time) {
    EXPECT_CALL(*fairplay_, StartPlayingFrom(time));
    std::move(demuxer_->split).Run(time);
    base::RunLoop().RunUntilIdle();
  }

  base::WeakPtr<MockRenderer> fairplay_;
  raw_ptr<RendererClient, DanglingUntriaged> fairplay_client_ = nullptr;
  std::optional<bool> handed_off_;
};

// The playing renderer can't go on past the split, so the FairPlay Renderer
// takes over at once and the seek is its.
TEST_F(ParcPipelineHandOffTest, SeekAfterTheSplitTakesOver) {
  StartHandOff();
  Split(base::Seconds(1));

  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_NOTHING, _));
  EXPECT_CALL(*fairplay_, SetPlaybackRate(0.0)).Times(2);
  EXPECT_CALL(*demuxer_, AbortPendingReads());
  EXPECT_CALL(*fairplay_, OnFlush(_)).WillOnce(RunOnceClosure<0>());
  EXPECT_CALL(*demuxer_, OnSeek(base::Seconds(2), _))
      .WillOnce(RunOnceCallback<1>(PIPELINE_OK));
  EXPECT_CALL(*fairplay_, StartPlayingFrom(base::Seconds(2)));
  EXPECT_CALL(callbacks_, OnSeek(HasStatusCode(PIPELINE_OK)));
  DoSeek(base::Seconds(2));
  EXPECT_FALSE(renderer_);
  EXPECT_EQ(handed_off_, true);
  EXPECT_EQ(demuxer_->handoff_ends, 0);
}

// Before the split the seek ends the hand-off: the playing renderer seeks and
// the caller restarts.
TEST_F(ParcPipelineHandOffTest, SeekBeforeTheSplitEndsIt) {
  StartHandOff();

  ExpectSeek(base::Seconds(2), false);
  DoSeek(base::Seconds(2));
  EXPECT_FALSE(fairplay_);
  EXPECT_TRUE(renderer_);
  EXPECT_EQ(handed_off_, false);
  EXPECT_EQ(demuxer_->handoff_ends, 1);
}

// A suspend ends the hand-off without a restart: the resume makes the
// renderer the CDM or the demuxer picks.
TEST_F(ParcPipelineHandOffTest, SuspendEndsItForTheResume) {
  StartHandOff();

  ExpectSuspend();
  DoSuspend();
  EXPECT_FALSE(fairplay_);
  EXPECT_EQ(handed_off_, true);
  EXPECT_EQ(demuxer_->handoff_ends, 1);
}

TEST_F(ParcPipelineHandOffTest, NewCdmEndsIt) {
  StartHandOff();

  SetCdmAndExpect(true);
  EXPECT_FALSE(fairplay_);
  EXPECT_EQ(handed_off_, false);
  EXPECT_EQ(demuxer_->handoff_ends, 1);
}

// Turning backward ends it; Chromium's test renderer, which can't play
// backward, stops.
TEST_F(ParcPipelineHandOffTest, TurningBackwardEndsIt) {
  StartHandOff();

  EXPECT_CALL(*renderer_, SetPlaybackRate(0.0));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(-1.0));
  pipeline_->SetPlaybackRate(-1.0);
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(fairplay_);
  EXPECT_EQ(handed_off_, false);
  EXPECT_EQ(demuxer_->handoff_ends, 1);
}

// The FairPlay Renderer ended before it took over (a split at the end of the
// stream): the page hears that end once, after the swap.
TEST_F(ParcPipelineHandOffTest, EndBeforeTheSwapReachesThePageAfterIt) {
  StartHandOff();
  Split(base::Seconds(1));
  fairplay_client_->OnEnded();
  base::RunLoop().RunUntilIdle();

  EXPECT_CALL(callbacks_, OnBufferingStateChange(BUFFERING_HAVE_NOTHING, _));
  EXPECT_CALL(callbacks_, OnEnded());
  EXPECT_CALL(*fairplay_, SetPlaybackRate(0.0));
  renderer_client_->OnEnded();
  base::RunLoop().RunUntilIdle();
  EXPECT_FALSE(renderer_);
  EXPECT_EQ(handed_off_, true);
}

// Parc: MediaKeys replacing a FairPlay Renderer's FairPlay ones reach that
// renderer, which takes them in place (new renderers in their key session, on
// the same clock) instead of waiting for a restart into a renderer made with
// them.
TEST_F(ParcPipelineImplTest, ParcFairPlayRendererTakesReplacedCdm) {
  scoped_renderer_ =
      std::make_unique<StrictMock<MockRenderer>>(RendererType::kFairPlay);
  renderer_ = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::TimeDelta()));
  EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  NiceMock<ParcFairPlayCdmContext> first;
  NiceMock<ParcFairPlayCdmContext> second;
  EXPECT_CALL(callbacks_, OnCdmAttached(true)).Times(2);
  pipeline_->SetCdm(&first, base::BindOnce(&CallbackHelper::OnCdmAttached,
                                           base::Unretained(&callbacks_)));
  EXPECT_CALL(*renderer_, OnSetCdm(&first, _))
      .WillOnce(RunOnceCallback<1>(true));
  CreateEncryptedVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  EXPECT_CALL(*renderer_, OnSetCdm(&second, _))
      .WillOnce(RunOnceCallback<1>(true));
  pipeline_->SetCdm(&second, base::BindOnce(&CallbackHelper::OnCdmAttached,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
}

// Parc: a renderer that can't take another CDM (Chromium's, while
// WebMediaPlayerImpl restarts it into the FairPlay Renderer) leaves a
// replacement FairPlay CDM for the next renderer.
TEST_F(ParcPipelineImplTest, ParcOtherRendererLeavesReplacedCdmForTheNext) {
  NiceMock<ParcFairPlayCdmContext> first;
  NiceMock<ParcFairPlayCdmContext> second;
  EXPECT_CALL(callbacks_, OnCdmAttached(true)).Times(2);
  pipeline_->SetCdm(&first, base::BindOnce(&CallbackHelper::OnCdmAttached,
                                           base::Unretained(&callbacks_)));
  EXPECT_CALL(*renderer_, OnSetCdm(&first, _))
      .WillOnce(RunOnceCallback<1>(true));
  CreateEncryptedVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  EXPECT_CALL(*renderer_, OnSetCdm(&second, _)).Times(0);
  pipeline_->SetCdm(&second, base::BindOnce(&CallbackHelper::OnCdmAttached,
                                            base::Unretained(&callbacks_)));
  base::RunLoop().RunUntilIdle();
}


// Parc: a player's real jump back (Safari's native HLS route) passes the clamp
// once.
TEST_F(ParcPipelineImplTest, ParcResetMediaTimeClampLetsTimeGoBackOnce) {
  CreateAudioStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::Seconds(2)));
  EXPECT_EQ(base::Seconds(2), pipeline_->GetMediaTime());
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::Seconds(1)));
  EXPECT_EQ(base::Seconds(2), pipeline_->GetMediaTime());

  pipeline_->ParcResetMediaTimeClamp();
  EXPECT_EQ(base::Seconds(1), pipeline_->GetMediaTime());
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::Milliseconds(500)));
  EXPECT_EQ(base::Seconds(1), pipeline_->GetMediaTime());
}

// Parc: a negative rate turns a file's renderer backward through a flush the
// page doesn't hear as a seek; the demuxer seeks backward playback asks for
// stay in the pipeline, and a rate of 0 or more turns it forward again from
// where time stopped.
TEST_F(ParcPipelineImplTest, ParcFileTurnsBackwardAndForward) {
  scoped_renderer_ = std::make_unique<StrictMock<MockRenderer>>(
      RendererType::kRendererImpl);
  renderer_ = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  CreateAudioStream();
  CreateVideoStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);

  const base::TimeDelta kTime = base::Seconds(5);
  EXPECT_CALL(*renderer_, GetMediaTime()).WillRepeatedly(Return(kTime));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(_)).Times(AnyNumber());
  ParcSeekDemuxerCB seek_demuxer;
  {
    testing::InSequence s;
    EXPECT_CALL(*renderer_, SetPlaybackRate(0.0));
    EXPECT_CALL(*demuxer_, AbortPendingReads());
    EXPECT_CALL(*renderer_, OnFlush(_)).WillOnce(RunOnceClosure<0>());
    EXPECT_CALL(*renderer_, ParcStartPlayingBackwardFrom(kTime, -1.0, _))
        .WillOnce(DoAll(SaveArg<2>(&seek_demuxer),
                        SetBufferingState(&renderer_client_,
                                          BUFFERING_HAVE_ENOUGH,
                                          BUFFERING_CHANGE_REASON_UNKNOWN)));
  }
  pipeline_->SetPlaybackRate(-1);
  base::RunLoop().RunUntilIdle();
  ASSERT_TRUE(seek_demuxer);

  base::MockOnceClosure seeked;
  EXPECT_CALL(*demuxer_, AbortPendingReads());
  EXPECT_CALL(*demuxer_, OnSeek(base::Seconds(4), _))
      .WillOnce(RunOnceCallback<1>(PIPELINE_OK));
  EXPECT_CALL(seeked, Run());
  seek_demuxer.Run(base::Seconds(4), seeked.Get());
  base::RunLoop().RunUntilIdle();

  // A pause stays backward.
  EXPECT_CALL(*renderer_, SetPlaybackRate(0.0));
  pipeline_->SetPlaybackRate(0);
  base::RunLoop().RunUntilIdle();

  {
    testing::InSequence s;
    EXPECT_CALL(*renderer_, SetPlaybackRate(1.0));
    EXPECT_CALL(*demuxer_, AbortPendingReads());
    EXPECT_CALL(*renderer_, OnFlush(_)).WillOnce(RunOnceClosure<0>());
    EXPECT_CALL(*demuxer_, OnSeek(kTime, _))
        .WillOnce(RunOnceCallback<1>(PIPELINE_OK));
    EXPECT_CALL(*renderer_, StartPlayingFrom(kTime));
    EXPECT_CALL(*renderer_, SetPlaybackRate(1.0));
  }
  pipeline_->SetPlaybackRate(1);
  base::RunLoop().RunUntilIdle();
}

TEST_F(ParcPipelineImplTest, ParcNativeHlsReverseRateAndClock) {
  scoped_renderer_ = std::make_unique<StrictMock<MockRenderer>>(
      RendererType::kFairPlayHls);
  renderer_ = scoped_renderer_->AsWeakPtr();
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillRepeatedly(Return(base::TimeDelta()));
  EXPECT_CALL(*renderer_, SetPreservesPitch(true)).Times(AnyNumber());
  demuxer_->native_hls = true;
  CreateAudioStream();
  SetDemuxerExpectations();
  StartPipelineAndExpect(PIPELINE_OK);
  EXPECT_CALL(*renderer_, SetPlaybackRate(-2));
  EXPECT_CALL(*demuxer_, SetPlaybackRate(-2));
  pipeline_->SetPlaybackRate(-2);
  base::RunLoop().RunUntilIdle();
  EXPECT_EQ(-2, pipeline_->GetPlaybackRate());
  EXPECT_CALL(*renderer_, GetMediaTime())
      .WillOnce(Return(base::Seconds(5)))
      .WillOnce(Return(base::Seconds(3)));
  EXPECT_EQ(base::Seconds(5), pipeline_->GetMediaTime());
  EXPECT_EQ(base::Seconds(3), pipeline_->GetMediaTime());
}

}  // namespace media

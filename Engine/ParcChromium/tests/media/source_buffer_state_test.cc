// Copyright 2026 Parc contributors.

#include "media/filters/source_buffer_state.h"

#include <optional>
#include <string_view>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/ptr_util.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/string_number_conversions.h"
#include "base/test/gmock_callback_support.h"
#include "base/test/scoped_feature_list.h"
#include "base/time/time.h"
#include "media/base/media_switches.h"
#include "media/base/media_util.h"
#include "media/base/mock_filters.h"
#include "media/base/mock_media_log.h"
#include "media/base/stream_parser.h"
#include "media/base/test_helpers.h"
#include "media/filters/chunk_demuxer.h"
#include "media/filters/frame_processor.h"
#include "media/filters/parc_source_buffer_eviction.h"
#include "media/media_buildflags.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

using testing::_;
using testing::DoAll;
using testing::InvokeWithoutArgs;
using testing::Return;
using testing::SaveArg;

namespace {

static constexpr int kSampleRate = 3000;

AudioDecoderConfig CreateAudioConfig(AudioCodec codec) {
  return AudioDecoderConfig(codec, kSampleFormatPlanarF32,
                            ChannelLayoutConfig::Stereo(), kSampleRate,
                            EmptyExtraData(), EncryptionScheme::kUnencrypted);
}

VideoDecoderConfig CreateVideoConfig(VideoCodec codec, int w, int h) {
  gfx::Size size(w, h);
  gfx::Rect visible_rect(size);
  return VideoDecoderConfig(codec, VIDEO_CODEC_PROFILE_UNKNOWN,
                            VideoDecoderConfig::AlphaMode::kIsOpaque,
                            VideoColorSpace::REC709(), kNoTransformation, size,
                            visible_rect, size, EmptyExtraData(),
                            EncryptionScheme::kUnencrypted);
}

void AddAudioTrack(std::unique_ptr<MediaTracks>& t, AudioCodec codec, int id) {
  t->AddAudioTrack(CreateAudioConfig(codec), true, id, MediaTrack::Kind(),
                   MediaTrack::Label(), MediaTrack::Language());
}

void AddVideoTrack(std::unique_ptr<MediaTracks>& t, VideoCodec codec, int id) {
  t->AddVideoTrack(CreateVideoConfig(codec, 16, 16), true, id,
                   MediaTrack::Kind(), MediaTrack::Label(),
                   MediaTrack::Language());
}

}

class ParcSourceBufferStateTest : public ::testing::Test {
 public:
  ParcSourceBufferStateTest() : mock_stream_parser_(nullptr) {}

  std::unique_ptr<SourceBufferState> CreateSourceBufferState() {
    std::unique_ptr<FrameProcessor> frame_processor =
        std::make_unique<FrameProcessor>(
            base::BindRepeating(&ParcSourceBufferStateTest::OnUpdateDuration,
                                base::Unretained(this)),
            &media_log_);
    mock_stream_parser_ = new testing::StrictMock<MockStreamParser>();
    return base::WrapUnique(new SourceBufferState(
        base::WrapUnique(mock_stream_parser_.get()), std::move(frame_processor),
        base::BindRepeating(&ParcSourceBufferStateTest::CreateDemuxerStream,
                            base::Unretained(this)),
        &media_log_));
  }

  std::unique_ptr<SourceBufferState> CreateAndInitSourceBufferState(
      std::optional<std::string_view> expected_codecs,
      bool parc_safari = false) {
    std::unique_ptr<SourceBufferState> sbs = CreateSourceBufferState();
    ParcSourceBufferEviction::SetSafariInitSegmentRules(*sbs, parc_safari);
    EXPECT_CALL(*mock_stream_parser_, Init(_, _, _, _, _, _, _))
        .WillOnce([&](auto init_cb, auto config_cb, auto new_buffers_cb,
                      auto encrypted_media_init_data_cb, auto new_segment_cb,
                      auto end_of_segment_cb,
                      auto media_log) { new_config_cb_ = config_cb; });
    sbs->Init(base::BindOnce(&ParcSourceBufferStateTest::SourceInitDone,
                             base::Unretained(this)),
              expected_codecs,
              base::BindRepeating(
                  &ParcSourceBufferStateTest::StreamParserEncryptedInitData,
                  base::Unretained(this)));

    sbs->SetTracksWatcher(base::BindRepeating(
        &ParcSourceBufferStateTest::OnMediaTracksUpdated, base::Unretained(this)));

    EXPECT_CALL(*this, OnParseWarningMock(_)).Times(0);

    sbs->SetParseWarningCallback(base::BindRepeating(
        &ParcSourceBufferStateTest::OnParseWarningMock, base::Unretained(this)));

    return sbs;
  }

  bool AppendDataAndReportTracks(const std::unique_ptr<SourceBufferState>& sbs,
                                 std::unique_ptr<MediaTracks> tracks) {
    const uint8_t kStreamData[] = "stream_data";
    base::span<const uint8_t> stream_data = base::span(kStreamData);
    base::TimeDelta t;

    CHECK_GT(StreamParser::kMaxPendingBytesPerParse,
             static_cast<int>(stream_data.size_bytes()));

    bool new_configs_result = false;

    EXPECT_CALL(*mock_stream_parser_, AppendToParseBuffer(stream_data))
        .WillOnce(Return(true));
    EXPECT_CALL(*mock_stream_parser_,
                Parse(StreamParser::kMaxPendingBytesPerParse))
        .WillOnce(
            DoAll(InvokeWithoutArgs([&] {
                    new_configs_result = new_config_cb_.Run(std::move(tracks));
                  }),
                  Return(StreamParser::ParseStatus::kSuccess)));

    EXPECT_TRUE(sbs->AppendToParseBuffer(stream_data));
    EXPECT_EQ(StreamParser::ParseStatus::kSuccess,
              sbs->RunSegmentParserLoop(t, t, &t));

    return new_configs_result;
  }

  MOCK_METHOD1(OnParseWarningMock, void(const SourceBufferParseWarning));
  MOCK_METHOD1(OnUpdateDuration, void(base::TimeDelta));

  MOCK_METHOD1(SourceInitDone, void(const StreamParser::InitParameters&));
  MOCK_METHOD2(StreamParserEncryptedInitData,
               void(EmeInitDataType, const std::vector<uint8_t>&));

  MOCK_METHOD1(MediaTracksUpdatedMock, void(std::unique_ptr<MediaTracks>&));
  void OnMediaTracksUpdated(std::unique_ptr<MediaTracks> tracks) {
    MediaTracksUpdatedMock(tracks);
  }

  ChunkDemuxerStream* CreateDemuxerStream(DemuxerStream::Type type) {
    static unsigned track_id = 0;
    demuxer_streams_.push_back(base::WrapUnique(new ChunkDemuxerStream(
        type, MediaTrack::Id(base::NumberToString(++track_id)))));
    return demuxer_streams_.back().get();
  }

  testing::StrictMock<MockMediaLog> media_log_;
  std::vector<std::unique_ptr<ChunkDemuxerStream>> demuxer_streams_;
  raw_ptr<MockStreamParser, DanglingUntriaged> mock_stream_parser_;
  StreamParser::NewConfigCB new_config_cb_;
};

#if BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION)
class ParcSourceBufferStateClearDolbyVisionTest : public ParcSourceBufferStateTest {
 public:
  ParcSourceBufferStateClearDolbyVisionTest() {
    feature_list_.InitWithFeatures(
        {kPlatformEncryptedDolbyVision},
        {kAllowClearDolbyVisionInMseWhenPlatformEncryptedDvEnabled});
  }

  bool AppendClearDolbyVision(bool allowed, VideoCodecProfile profile) {
    std::unique_ptr<SourceBufferState> sbs = CreateSourceBufferState();
    EXPECT_CALL(*mock_stream_parser_, Init(_, _, _, _, _, _, _))
        .WillOnce([&](auto init_cb, auto config_cb, auto new_buffers_cb,
                      auto encrypted_media_init_data_cb, auto new_segment_cb,
                      auto end_of_segment_cb,
                      auto media_log) { new_config_cb_ = config_cb; });
    sbs->Init(base::BindOnce(&ParcSourceBufferStateTest::SourceInitDone,
                             base::Unretained(this)),
              std::nullopt,
              base::BindRepeating(
                  &ParcSourceBufferStateTest::StreamParserEncryptedInitData,
                  base::Unretained(this)));
    sbs->SetTracksWatcher(base::BindRepeating(
        &ParcSourceBufferStateTest::OnMediaTracksUpdated, base::Unretained(this)));
    EXPECT_CALL(*this, OnParseWarningMock(_)).Times(0);
    sbs->SetParseWarningCallback(base::BindRepeating(
        &ParcSourceBufferStateTest::OnParseWarningMock, base::Unretained(this)));
    ParcSourceBufferEviction::SetClearDolbyVisionAllowed(*sbs, allowed);
    ParcSourceBufferEviction::SetDolbyVisionCallback(*sbs, base::BindRepeating(
        [](int* count) { ++*count; }, &dolby_vision_taken_));

    const gfx::Size size(16, 16);
    auto tracks = std::make_unique<MediaTracks>();
    tracks->AddVideoTrack(
        VideoDecoderConfig(VideoCodec::kDolbyVision, profile,
                           VideoDecoderConfig::AlphaMode::kIsOpaque,
                           VideoColorSpace::REC709(), kNoTransformation, size,
                           gfx::Rect(size), size, EmptyExtraData(),
                           EncryptionScheme::kUnencrypted),
        true, 1, MediaTrack::Kind(), MediaTrack::Label(),
        MediaTrack::Language());
    return AppendDataAndReportTracks(sbs, std::move(tracks));
  }

  int dolby_vision_taken_ = 0;

 private:
  base::test::ScopedFeatureList feature_list_;
};

TEST_F(ParcSourceBufferStateClearDolbyVisionTest, RejectedWhereNotAllowed) {
  EXPECT_MEDIA_LOG(
      testing::HasSubstr("the provided DV track is not encrypted"));
  EXPECT_FALSE(AppendClearDolbyVision(false, DOLBYVISION_PROFILE5));
  EXPECT_EQ(dolby_vision_taken_, 0);
}

TEST_F(ParcSourceBufferStateClearDolbyVisionTest, Profile5PlaysWhereAllowed) {
  EXPECT_FOUND_CODEC_NAME(Video, "dolbyvision");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendClearDolbyVision(true, DOLBYVISION_PROFILE5));
  EXPECT_EQ(dolby_vision_taken_, 1);
}

TEST_F(ParcSourceBufferStateClearDolbyVisionTest, Profile8PlaysWhereAllowed) {
  EXPECT_FOUND_CODEC_NAME(Video, "dolbyvision");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendClearDolbyVision(true, DOLBYVISION_PROFILE8));
  EXPECT_EQ(dolby_vision_taken_, 1);
}

TEST_F(ParcSourceBufferStateClearDolbyVisionTest, OtherProfilesStayRejected) {
  EXPECT_MEDIA_LOG(
      testing::HasSubstr("the provided DV track is not encrypted"));
  EXPECT_FALSE(AppendClearDolbyVision(true, DOLBYVISION_PROFILE9));
  EXPECT_EQ(dolby_vision_taken_, 0);
}
#endif


TEST_F(ParcSourceBufferStateTest, ParcSafariTakesCodecTheTypeDidNotName) {
  {
    std::unique_ptr<SourceBufferState> sbs =
        CreateAndInitSourceBufferState("vp9");
    std::unique_ptr<MediaTracks> tracks(new MediaTracks());
    AddVideoTrack(tracks, VideoCodec::kVP8, 1);
    EXPECT_MEDIA_LOG(InitSegmentMismatchesMimeType("Video", "vp8"));
    EXPECT_FALSE(AppendDataAndReportTracks(sbs, std::move(tracks)));
  }

  std::unique_ptr<SourceBufferState> sbs =
      CreateAndInitSourceBufferState("vp9", /*parc_safari=*/true);
  std::unique_ptr<MediaTracks> tracks(new MediaTracks());
  AddVideoTrack(tracks, VideoCodec::kVP8, 1);
  EXPECT_FOUND_CODEC_NAME(Video, "vp8");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));
}

TEST_F(ParcSourceBufferStateTest, ParcSafariTakesSegmentMissingANamedCodec) {
  {
    std::unique_ptr<SourceBufferState> sbs =
        CreateAndInitSourceBufferState("opus,vp9");
    std::unique_ptr<MediaTracks> tracks(new MediaTracks());
    AddVideoTrack(tracks, VideoCodec::kVP9, 1);
    EXPECT_FOUND_CODEC_NAME(Video, "vp9");
    EXPECT_MEDIA_LOG(InitSegmentMissesExpectedTrack("opus"));
    EXPECT_FALSE(AppendDataAndReportTracks(sbs, std::move(tracks)));
  }

  std::unique_ptr<SourceBufferState> sbs =
      CreateAndInitSourceBufferState("opus,vp9", /*parc_safari=*/true);
  std::unique_ptr<MediaTracks> tracks(new MediaTracks());
  AddVideoTrack(tracks, VideoCodec::kVP9, 1);
  EXPECT_FOUND_CODEC_NAME(Video, "vp9");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));
}

TEST_F(ParcSourceBufferStateTest, ParcSafariRejectsLaterSegmentWithFewerTracks) {
  {
    std::unique_ptr<SourceBufferState> sbs =
        CreateAndInitSourceBufferState(std::nullopt);
    std::unique_ptr<MediaTracks> tracks(new MediaTracks());
    AddAudioTrack(tracks, AudioCodec::kOpus, 1);
    AddVideoTrack(tracks, VideoCodec::kVP9, 2);
    EXPECT_FOUND_CODEC_NAME(Audio, "opus");
    EXPECT_FOUND_CODEC_NAME(Video, "vp9");
    EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
    EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

    std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
    AddVideoTrack(tracks2, VideoCodec::kVP9, 2);
    EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
    EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
  }

  std::unique_ptr<SourceBufferState> sbs =
      CreateAndInitSourceBufferState(std::nullopt, /*parc_safari=*/true);
  std::unique_ptr<MediaTracks> tracks(new MediaTracks());
  AddAudioTrack(tracks, AudioCodec::kOpus, 1);
  AddVideoTrack(tracks, VideoCodec::kVP9, 2);
  EXPECT_FOUND_CODEC_NAME(Audio, "opus");
  EXPECT_FOUND_CODEC_NAME(Video, "vp9");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

  std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
  AddVideoTrack(tracks2, VideoCodec::kVP9, 2);
  EXPECT_MEDIA_LOG(testing::HasSubstr(
      "has 0 audio and 1 video tracks; the first had 1 and 1"));
  EXPECT_FALSE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
}

TEST_F(ParcSourceBufferStateTest, ParcSafariRejectsLaterSegmentWithMoreTracks) {
  {
    std::unique_ptr<SourceBufferState> sbs =
        CreateAndInitSourceBufferState(std::nullopt);
    std::unique_ptr<MediaTracks> tracks(new MediaTracks());
    AddAudioTrack(tracks, AudioCodec::kOpus, 1);
    AddVideoTrack(tracks, VideoCodec::kVP9, 2);
    EXPECT_FOUND_CODEC_NAME(Audio, "opus");
    EXPECT_FOUND_CODEC_NAME(Video, "vp9");
    EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
    EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

    std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
    AddAudioTrack(tracks2, AudioCodec::kOpus, 1);
    AddAudioTrack(tracks2, AudioCodec::kOpus, 3);
    AddVideoTrack(tracks2, VideoCodec::kVP9, 2);
    EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
    EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
  }

  std::unique_ptr<SourceBufferState> sbs =
      CreateAndInitSourceBufferState(std::nullopt, /*parc_safari=*/true);
  std::unique_ptr<MediaTracks> tracks(new MediaTracks());
  AddAudioTrack(tracks, AudioCodec::kOpus, 1);
  AddVideoTrack(tracks, VideoCodec::kVP9, 2);
  EXPECT_FOUND_CODEC_NAME(Audio, "opus");
  EXPECT_FOUND_CODEC_NAME(Video, "vp9");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

  std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
  AddAudioTrack(tracks2, AudioCodec::kOpus, 1);
  AddAudioTrack(tracks2, AudioCodec::kOpus, 3);
  AddVideoTrack(tracks2, VideoCodec::kVP9, 2);
  EXPECT_MEDIA_LOG(testing::HasSubstr(
      "has 2 audio and 1 video tracks; the first had 1 and 1"));
  EXPECT_FALSE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
}

TEST_F(ParcSourceBufferStateTest, ParcSafariTakesCodecChangeInLaterSegment) {
  {
    std::unique_ptr<SourceBufferState> sbs =
        CreateAndInitSourceBufferState(std::nullopt);
    std::unique_ptr<MediaTracks> tracks(new MediaTracks());
    AddVideoTrack(tracks, VideoCodec::kVP9, 1);
    EXPECT_FOUND_CODEC_NAME(Video, "vp9");
    EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
    EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

    std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
    AddVideoTrack(tracks2, VideoCodec::kVP8, 1);
    EXPECT_MEDIA_LOG(testing::HasSubstr("Video codec changes not allowed"));
    EXPECT_FALSE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
  }

  std::unique_ptr<SourceBufferState> sbs =
      CreateAndInitSourceBufferState(std::nullopt, /*parc_safari=*/true);
  std::unique_ptr<MediaTracks> tracks(new MediaTracks());
  AddVideoTrack(tracks, VideoCodec::kVP9, 1);
  EXPECT_FOUND_CODEC_NAME(Video, "vp9");
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks)));

  std::unique_ptr<MediaTracks> tracks2(new MediaTracks());
  AddVideoTrack(tracks2, VideoCodec::kVP8, 1);
  EXPECT_CALL(*this, MediaTracksUpdatedMock(_));
  EXPECT_TRUE(AppendDataAndReportTracks(sbs, std::move(tracks2)));
}


}

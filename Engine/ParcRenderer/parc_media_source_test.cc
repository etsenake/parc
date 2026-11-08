// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/mediasource/parc_media_source_test.cc
// (blink_unittests). Tests what a MediaSource tells a page and its media
// engine under Safari's identity (parc_safari_identity.h) and under Chrome's:
// types named without codecs, MPEG-2 TS types, Safari's other types and
// codecs (3GPP's AMR and H.263 among them), Ogg, and a duration set below
// the buffered end.

#include "base/test/scoped_command_line.h"
#include "media/base/parc_av1_support.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_tester.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_decoding_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_audio_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_video_configuration.h"
#include "third_party/blink/renderer/bindings/modules/v8/v8_media_capabilities_decoding_info.h"
#include "third_party/blink/renderer/modules/media_capabilities/media_capabilities.h"

#include "third_party/blink/renderer/core/frame/navigator.h"

#include "third_party/blink/renderer/bindings/core/v8/v8_can_play_type_result.h"

#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"

#include <limits>
#include <memory>
#include <optional>

#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/video_decoder_config.h"
#include "media/media_buildflags.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/platform/web_media_source.h"
#include "third_party/blink/public/platform/web_source_buffer.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_time_range.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/frame/settings.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/track/audio_track.h"
#include "third_party/blink/renderer/core/html/track/audio_track_list.h"
#include "third_party/blink/renderer/core/html/media/media_source_attachment.h"
#include "third_party/blink/renderer/core/html/media/media_source_tracer.h"
#include "third_party/blink/renderer/core/loader/empty_clients.h"
#include "third_party/blink/renderer/core/testing/page_test_base.h"
#include "third_party/blink/renderer/modules/mediasource/media_source.h"
#include "third_party/blink/renderer/modules/mediasource/source_buffer.h"
#include "third_party/blink/renderer/modules/mediasource/url_media_source.h"
#include "third_party/blink/renderer/platform/bindings/exception_code.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"
#include "third_party/blink/renderer/core/typed_arrays/dom_array_buffer.h"

namespace blink {
namespace {

constexpr char kSafariUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/27.2 Safari/605.1.15";
constexpr char kChromeUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

constexpr const char* kTypesWithoutCodecs[] = {"video/mp4", "audio/mp4",
                                               "video/webm", "audio/webm"};

// What the MediaSource told the media engine, and what the engine reports.
struct FakeEngine {
  std::vector<WebSourceBufferClient::MediaTrackInfo> tracks;
  int add_source_buffer_calls = 0;
  String added_type;
  String added_codecs;
  String changed_type;
  String changed_codecs;
  WebTimeRanges buffered;
  double highest_presentation_timestamp = 0;
  double duration = std::numeric_limits<double>::quiet_NaN();
};
using FakeEngineRef = scoped_refptr<base::RefCountedData<FakeEngine>>;

class FakeWebSourceBuffer final : public WebSourceBuffer {
 public:
  explicit FakeWebSourceBuffer(FakeEngineRef engine)
      : engine_(std::move(engine)) {}

  void SetClient(WebSourceBufferClient* client) override { client_ = client; }
  bool SetMode(AppendMode) override { return true; }
  bool GetGenerateTimestampsFlag() override { return false; }
  WebTimeRanges Buffered() override { return engine_->data.buffered; }
  double HighestPresentationTimestamp() override {
    return engine_->data.highest_presentation_timestamp;
  }
  bool EvictCodedFrames(double, size_t) override { return true; }
  bool AppendToParseBuffer(base::span<const unsigned char>) override {
    return true;
  }
  media::StreamParser::ParseStatus RunSegmentParserLoop(double*) override {
    if (!engine_->data.tracks.empty()) {
      EXPECT_TRUE(client_->InitializationSegmentReceived(engine_->data.tracks));
    }
    return media::StreamParser::ParseStatus::kSuccess;
  }
  bool AppendChunks(std::unique_ptr<media::StreamParser::BufferQueue>,
                    double*) override {
    return true;
  }
  void ResetParserState() override {}
  void Remove(double, double) override {}
  bool CanChangeType(const WebString&, const WebString&) override {
    return true;
  }
  void ChangeType(const WebString& content_type,
                  const WebString& codecs) override {
    engine_->data.changed_type = content_type;
    engine_->data.changed_codecs = codecs;
  }
  bool SetTimestampOffset(double) override { return true; }
  void SetAppendWindowStart(double) override {}
  void SetAppendWindowEnd(double) override {}
  void RemovedFromMediaSource() override {}

 private:
  WebSourceBufferClient* client_ = nullptr;
  FakeEngineRef engine_;
};

class FakeWebMediaSource final : public WebMediaSource {
 public:
  explicit FakeWebMediaSource(FakeEngineRef engine)
      : engine_(std::move(engine)) {}

  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      const WebString& content_type,
      const WebString& codecs,
      AddStatus& out_status) override {
    ++engine_->data.add_source_buffer_calls;
    engine_->data.added_type = content_type;
    engine_->data.added_codecs = codecs;
    out_status = kAddStatusOk;
    return std::make_unique<FakeWebSourceBuffer>(engine_);
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::AudioDecoderConfig>,
      AddStatus& out_status) override {
    out_status = kAddStatusReachedIdLimit;
    return nullptr;
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::VideoDecoderConfig>,
      AddStatus& out_status) override {
    out_status = kAddStatusReachedIdLimit;
    return nullptr;
  }
  double Duration() override { return engine_->data.duration; }
  void SetDuration(double duration) override {
    engine_->data.duration = duration;
  }
  void MarkEndOfStream(EndOfStreamStatus) override {}
  void UnmarkEndOfStream() override {}

 private:
  FakeEngineRef engine_;
};

class UserAgentFrameClient final : public EmptyLocalFrameClient {
 public:
  String UserAgent() override { return user_agent_; }
  void set_user_agent(const char* user_agent) {
    user_agent_ = String(user_agent);
  }

 private:
  String user_agent_;
};

class ParcMediaSourceTest : public PageTestBase {
 protected:
  void SetUp() override {
    frame_client_ = MakeGarbageCollected<UserAgentFrameClient>();
    SetupPageWithClients(nullptr, frame_client_, [](Settings& settings) {
      settings.SetScriptEnabled(true);
    });
    engine_ = base::MakeRefCounted<base::RefCountedData<FakeEngine>>();
    video_ = MakeGarbageCollected<HTMLVideoElement>(GetDocument());
  }

  void SetUserAgent(const char* user_agent) {
    frame_client_->set_user_agent(user_agent);
  }

  ExecutionContext* Context() { return GetFrame().DomWindow(); }

  // A MediaSource attached to video_ and open, as at sourceopen.
  MediaSource* OpenMediaSource() {
    MediaSource* media_source = MediaSource::Create(Context());
    attachment_ = MediaSourceAttachment::LookupMediaSource(
        URLMediaSource::createObjectURL(ToScriptStateForMainWorld(&GetFrame()),
                                        media_source));
    CHECK(attachment_);
    bool success = false;
    tracer_ = attachment_->StartAttachingToMediaElement(video_, &success);
    CHECK(success);
    attachment_->CompleteAttachingToMediaElement(
        tracer_, std::make_unique<FakeWebMediaSource>(engine_));
    CHECK(media_source->IsOpen());
    media_source_ = media_source;
    return media_source;
  }

  // A SourceBuffer holding [0, 10.04) whose last frame starts at 10, in a
  // MediaSource 20 seconds long.
  MediaSource* MediaSourceWithBufferedEnd() {
    MediaSource* media_source = OpenMediaSource();
    DummyExceptionStateForTesting exception_state;
    CHECK(media_source->addSourceBuffer("video/webm; codecs=\"vp8\"",
                                        exception_state));
    engine_->data.duration = 20;
    engine_->data.buffered = WebTimeRanges(0, 10.04);
    engine_->data.highest_presentation_timestamp = 10;
    return media_source;
  }

  Persistent<UserAgentFrameClient> frame_client_;
  FakeEngineRef engine_;
  Persistent<HTMLVideoElement> video_;
  Persistent<MediaSource> media_source_;
  Persistent<MediaSourceTracer> tracer_;
  scoped_refptr<MediaSourceAttachment> attachment_;
};

TEST_F(ParcMediaSourceTest, AV1HardwareGateAcrossIdentitiesAndAPIs) {
  for (bool hardware : {false, true}) {
    base::test::ScopedCommandLine command_line;
    command_line.GetProcessCommandLine()->AppendSwitchASCII(
        media::kParcAV1HardwareDecoder, hardware ? "1" : "0");
    for (const char* agent : {kSafariUserAgent, kChromeUserAgent}) {
      SetUserAgent(agent);
      const bool supported = hardware || agent == kChromeUserAgent;
      for (const char* type : {"video/mp4; codecs=\"av01.0.08M.08\"",
                               "video/webm; codecs=\"av01.0.08M.08\""}) {
        EXPECT_EQ(MediaSource::isTypeSupported(Context(), type), supported);
        EXPECT_EQ(video_->canPlayType(type).AsString().empty(), !supported);
        auto* source = OpenMediaSource();
        DummyExceptionStateForTesting add_exception;
        auto* added = source->addSourceBuffer(type, add_exception);
        EXPECT_EQ(added != nullptr, supported);
        EXPECT_EQ(add_exception.HadException(), !supported);
        DummyExceptionStateForTesting vp9_exception;
        auto* buffer = source->addSourceBuffer(
            "video/webm; codecs=\"vp09.00.10.08\"", vp9_exception);
        ASSERT_TRUE(buffer);
        DummyExceptionStateForTesting change_exception;
        buffer->changeType(type, change_exception);
        EXPECT_EQ(change_exception.HadException(), !supported);
      }
    }
  }
}

class AV1PerfHistory final : public media::mojom::blink::VideoDecodePerfHistory {
 public:
  void GetPerfInfo(media::mojom::blink::PredictionFeaturesPtr,
                   GetPerfInfoCallback callback) override {
    std::move(callback).Run(true, true);
  }
};

TEST_F(ParcMediaSourceTest, AV1DecodingInfoHardwareAndIdentity) {
  auto* script_state = ToScriptStateForMainWorld(&GetFrame());
  ScriptState::Scope scope(script_state);
  ASSERT_TRUE(Context()->GetBrowserInterfaceBroker().SetBinderForTesting(
      media::mojom::blink::VideoDecodePerfHistory::Name_,
      base::BindRepeating([](mojo::ScopedMessagePipeHandle pipe) {
        mojo::MakeSelfOwnedReceiver(std::make_unique<AV1PerfHistory>(),
            mojo::PendingReceiver<media::mojom::blink::VideoDecodePerfHistory>(
                std::move(pipe)));
      })));
  for (bool hardware : {false, true}) {
    base::test::ScopedCommandLine command_line;
    command_line.GetProcessCommandLine()->AppendSwitchASCII(
        media::kParcAV1HardwareDecoder, hardware ? "1" : "0");
    for (const char* agent : {kSafariUserAgent, kChromeUserAgent}) {
      SetUserAgent(agent);
      const bool supported = hardware || agent == kChromeUserAgent;
      for (auto type : {V8MediaDecodingType::Enum::kFile,
                        V8MediaDecodingType::Enum::kMediaSource}) {
        auto* config = MediaDecodingConfiguration::Create();
        config->setType(type);
        auto* video = VideoConfiguration::Create();
        video->setContentType("video/mp4; codecs=\"av01.0.08M.08\"");
        video->setWidth(1920);
        video->setHeight(1080);
        video->setBitrate(4000000);
        video->setFramerate(60);
        config->setVideo(video);
        DummyExceptionStateForTesting exception;
        auto* capabilities = MediaCapabilities::mediaCapabilities(
            *GetFrame().DomWindow()->navigator());
        ScriptPromiseTester tester(script_state,
            capabilities->decodingInfo(script_state, config, exception));
        tester.WaitUntilSettled();
        ASSERT_TRUE(tester.IsFulfilled());
        auto* info = NativeValueTraits<MediaCapabilitiesDecodingInfo>::NativeValue(
            script_state->GetIsolate(), tester.Value().V8Value(), exception);
        ASSERT_TRUE(info);
        EXPECT_EQ(info->supported(), supported);
        if (!supported) {
          EXPECT_FALSE(info->smooth());
          EXPECT_FALSE(info->powerEfficient());
        }
      }
    }
  }
  Context()->GetBrowserInterfaceBroker().SetBinderForTesting(
      media::mojom::blink::VideoDecodePerfHistory::Name_, {});
}

TEST_F(ParcMediaSourceTest, SafariTsSourceBufferExposesEveryAudioTrack) {
  SetUserAgent(kSafariUserAgent);
  auto* source = OpenMediaSource();
  DummyExceptionStateForTesting exception_state;
  auto* buffer = source->addSourceBuffer("video/mp2t", exception_state);
  ASSERT_NE(buffer, nullptr);
  using Info = WebSourceBufferClient::MediaTrackInfo;
  std::vector<Info> tracks = {
      {WebMediaPlayer::kAudioTrack, WebMediaPlayer::TrackId("1"),
       WebString::FromUtf8("258"), WebString::FromUtf8("main"),
       WebString(), WebString()},
      {WebMediaPlayer::kAudioTrack, WebMediaPlayer::TrackId("2"),
       WebString::FromUtf8("259"), WebString::FromUtf8("main"),
       WebString(), WebString()}};
  engine_->data.tracks = tracks;
  buffer->appendBuffer(DOMArrayBuffer::Create(1, 1), exception_state);
  ASSERT_FALSE(exception_state.HadException());
  test::RunPendingTasks();
  ASSERT_EQ(buffer->audioTracks().length(), 2u);
  ASSERT_EQ(video_->audioTracks().length(), 2u);
  EXPECT_NE(buffer->audioTracks().AnonymousIndexedGetter(0)->id(),
            buffer->audioTracks().AnonymousIndexedGetter(1)->id());
  engine_->data.tracks = tracks;
  buffer->appendBuffer(DOMArrayBuffer::Create(1, 1), exception_state);
  ASSERT_FALSE(exception_state.HadException());
  test::RunPendingTasks();
  EXPECT_EQ(video_->audioTracks().length(), 2u);
}

// WebKit's MediaSource::isTypeSupported: without codecs, anything but
// IsNotSupported is supported.
TEST_F(ParcMediaSourceTest, SafariIsTypeSupportedWithoutCodecs) {
  SetUserAgent(kSafariUserAgent);
  for (const char* type : kTypesWithoutCodecs) {
    EXPECT_TRUE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  EXPECT_FALSE(MediaSource::isTypeSupported(Context(), "video/x-unknown"));
  EXPECT_FALSE(
      MediaSource::isTypeSupported(Context(), "video/webm; codecs=\"bogus\""));
}

TEST_F(ParcMediaSourceTest, ChromeIsTypeSupportedNeedsCodecs) {
  SetUserAgent(kChromeUserAgent);
  for (const char* type : kTypesWithoutCodecs) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  EXPECT_TRUE(
      MediaSource::isTypeSupported(Context(), "video/webm; codecs=\"vp8\""));
}

// WebKit's SourceBufferParserAVFObjC::isContentTypeSupported: every type
// AVStreamDataParser lists, with the codecs its family takes.
TEST_F(ParcMediaSourceTest, PCMOnlyOnSafariMP4Pages) {
  for (const char* agent : {kChromeUserAgent, kSafariUserAgent}) {
    SetUserAgent(agent);
    const bool safari = agent == kSafariUserAgent;
    for (const char* type : {"Audio/MP4; codecs=\"ipcm\"",
                             "audio/mp4; codecs=\"ipcm\"",
                             "video/mp4; codecs=\"fpcm\"",
                             "audio/x-m4a; codecs=\"ipcm.16\"",
                             "video/3gpp; codecs=\"fpcm.abc\""})
      EXPECT_EQ(MediaSource::isTypeSupported(Context(), type), safari) << type;
    for (const char* type : {"audio/mp4; codecs=\"IPCM\"",
                             "audio/mp4; codecs=\"ipcmXYZ\"",
                             "video/quicktime; codecs=\"ipcm\"",
                             "audio/x-quicktime; codecs=\"fpcm\"",
                             "audio/mp4; codecs=\"ipcm,bogus\"",
                             "audio/webm; codecs=\"fpcm\""})
      EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

// AVStreamDataParser's answers for 3GPP's AMR and H.263: yes in every MP4
// family type, but not H.263 in QuickTime.
TEST_F(ParcMediaSourceTest, AmrAndH263OnlyOnSafariPages) {
  for (const char* agent : {kChromeUserAgent, kSafariUserAgent}) {
    SetUserAgent(agent);
    const bool safari = agent == kSafariUserAgent;
    for (const char* type : {"video/3gpp; codecs=\"s263\"",
                             "audio/3gpp; codecs=\"samr\"",
                             "audio/3gpp2; codecs=\"sawb\"",
                             "video/mp4; codecs=\"s263,samr\"",
                             "audio/mp4; codecs=\"s263\"",
                             "audio/x-m4a; codecs=\"samr.abc\"",
                             "video/quicktime; codecs=\"sawb\""})
      EXPECT_EQ(MediaSource::isTypeSupported(Context(), type), safari) << type;
#if BUILDFLAG(USE_PROPRIETARY_CODECS)
    EXPECT_EQ(MediaSource::isTypeSupported(
                  Context(), "video/3gpp; codecs=\"s263.1,mp4a.40.2\""),
              safari);
#endif  // BUILDFLAG(USE_PROPRIETARY_CODECS)
    for (const char* type : {"video/3gpp; codecs=\"SAMR\"",
                             "video/3gpp; codecs=\"s263x\"",
                             "video/quicktime; codecs=\"s263\"",
                             "audio/x-quicktime; codecs=\"s263.1\"",
                             "video/3gpp; codecs=\"s263,bogus\"",
                             "audio/mpeg; codecs=\"samr\"",
                             "audio/aac; codecs=\"sawb\"",
                             "video/webm; codecs=\"s263\""})
      EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

TEST_F(ParcMediaSourceTest, SafariAmrAndH263SourceBuffer) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  SourceBuffer* source_buffer = media_source->addSourceBuffer(
      "video/3gpp; codecs=\"s263, samr\"", add_exception);
  EXPECT_FALSE(add_exception.HadException());
  ASSERT_TRUE(source_buffer);
  EXPECT_EQ(engine_->data.added_type, "video/3gpp");

  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/3gpp; codecs=\"sawb\"", change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_type, "audio/3gpp");

  DummyExceptionStateForTesting quicktime_exception;
  source_buffer->changeType("video/quicktime; codecs=\"s263\"",
                            quicktime_exception);
  EXPECT_EQ(quicktime_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
}

TEST_F(ParcMediaSourceTest, ChromeSourceBufferRefusesAmrAndH263) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  EXPECT_FALSE(media_source->addSourceBuffer("video/mp4; codecs=\"s263\"",
                                             add_exception));
  EXPECT_EQ(add_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_EQ(engine_->data.add_source_buffer_calls, 0);
}

TEST_F(ParcMediaSourceTest, SafariIsTypeSupportedSafariContainers) {
  SetUserAgent(kSafariUserAgent);
  for (const char* type :
       {"video/quicktime", "audio/x-m4a", "video/x-m4v", "audio/3gpp",
        "video/3gpp", "application/mp4", "audio/mp3", "audio/x-mpeg",
        "audio/mpeg; codecs=\"mp3\"", "audio/x-m4a; codecs=\"opus\"",
        "audio/mp4; codecs=\"vp09.00.10.08\"",
        "video/quicktime; codecs=\"vp09.00.10.08,opus\""}) {
    EXPECT_TRUE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  for (const char* type :
       {"audio/mpeg; codecs=\"mp4a.6B\"", "text/vtt",
        "audio/x-m4a; codecs=\"bogus\""}) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
#if BUILDFLAG(USE_PROPRIETARY_CODECS)
  EXPECT_TRUE(MediaSource::isTypeSupported(Context(), "audio/aacp"));
  EXPECT_TRUE(MediaSource::isTypeSupported(Context(),
                                           "audio/aac; codecs=\"mp4a.40.2\""));
  EXPECT_FALSE(MediaSource::isTypeSupported(
      Context(), "audio/aacp; codecs=\"mp4a.40.2\""));
#endif  // BUILDFLAG(USE_PROPRIETARY_CODECS)
#if BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || BUILDFLAG(ENABLE_IAMF_TOOLS)
  EXPECT_FALSE(MediaSource::isTypeSupported(
      Context(), "audio/mp4; codecs=\"iamf.001.001.Opus\""));
#endif  // BUILDFLAG(ENABLE_PLATFORM_IAMF_AUDIO) || ...
}

TEST_F(ParcMediaSourceTest, ChromeIsTypeSupportedChromeContainers) {
  SetUserAgent(kChromeUserAgent);
  for (const char* type :
       {"video/quicktime", "audio/mp3", "audio/mpeg; codecs=\"mp3\"",
        "audio/x-m4a; codecs=\"opus\"",
        "audio/mp4; codecs=\"vp09.00.10.08\""}) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  EXPECT_TRUE(MediaSource::isTypeSupported(Context(), "audio/mpeg"));
}

// AVStreamDataParser's answers for Ogg (canParseExtendedMIMEType), which
// WebKit's MediaSource::isTypeSupported takes; without codecs, any type it
// lists.
TEST_F(ParcMediaSourceTest, SafariIsTypeSupportedOgg) {
  SetUserAgent(kSafariUserAgent);
  for (const char* type :
       {"audio/ogg", "application/ogg", "audio/ogg; codecs=\"opus\"",
        "audio/ogg; codecs=\"vorbis\"", "audio/ogg; codecs=\"flac\"",
        "audio/ogg; codecs=\"opus,vorbis\""}) {
    EXPECT_TRUE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  for (const char* type :
       {"audio/ogg; codecs=\"Opus\"", "audio/ogg; codecs=\"fLaC\"",
        "audio/ogg; codecs=\"speex\"", "application/ogg; codecs=\"opus\"",
        "video/ogg", "video/ogg; codecs=\"theora\""}) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

TEST_F(ParcMediaSourceTest, ChromeIsTypeSupportedRefusesOgg) {
  SetUserAgent(kChromeUserAgent);
  for (const char* type : {"audio/ogg", "audio/ogg; codecs=\"opus\"",
                           "application/ogg"}) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

TEST_F(ParcMediaSourceTest, SafariOggSourceBufferAndChangeType) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  SourceBuffer* source_buffer =
      media_source->addSourceBuffer("audio/ogg; codecs=\"opus\"", add_exception);
  EXPECT_FALSE(add_exception.HadException());
  ASSERT_TRUE(source_buffer);
  EXPECT_EQ(engine_->data.added_type, "audio/ogg");
  EXPECT_EQ(engine_->data.added_codecs, "opus");

  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/ogg; codecs=\"flac\"", change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_type, "audio/ogg");
  EXPECT_EQ(engine_->data.changed_codecs, "flac");

  DummyExceptionStateForTesting refused_exception;
  source_buffer->changeType("video/ogg", refused_exception);
  EXPECT_EQ(refused_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
}

TEST_F(ParcMediaSourceTest, ChromeSourceBufferRefusesOgg) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  EXPECT_FALSE(media_source->addSourceBuffer("audio/ogg; codecs=\"opus\"",
                                             add_exception));
  EXPECT_EQ(add_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_EQ(engine_->data.add_source_buffer_calls, 0);

  DummyExceptionStateForTesting webm_exception;
  SourceBuffer* source_buffer = media_source->addSourceBuffer(
      "audio/webm; codecs=\"opus\"", webm_exception);
  ASSERT_TRUE(source_buffer);
  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/ogg; codecs=\"opus\"", change_exception);
  EXPECT_EQ(change_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_TRUE(engine_->data.changed_type.empty());
}

// WebKit's decodingInfo for a media-source audio configuration:
// MediaPlayer::supportsType() == IsSupported, so Ogg naming its codec.
TEST_F(ParcMediaSourceTest, OggDecodingInfoAcrossIdentities) {
  auto* script_state = ToScriptStateForMainWorld(&GetFrame());
  ScriptState::Scope scope(script_state);
  struct {
    const char* agent;
    const char* type;
    bool supported;
  } kCases[] = {
      {kSafariUserAgent, "audio/ogg; codecs=\"opus\"", true},
      {kSafariUserAgent, "audio/ogg; codecs=\"vorbis\"", true},
      {kSafariUserAgent, "audio/ogg", false},
      {kChromeUserAgent, "audio/ogg; codecs=\"opus\"", false},
  };
  for (const auto& test_case : kCases) {
    SetUserAgent(test_case.agent);
    auto* config = MediaDecodingConfiguration::Create();
    config->setType(V8MediaDecodingType::Enum::kMediaSource);
    auto* audio = AudioConfiguration::Create();
    audio->setContentType(test_case.type);
    config->setAudio(audio);
    DummyExceptionStateForTesting exception;
    auto* capabilities = MediaCapabilities::mediaCapabilities(
        *GetFrame().DomWindow()->navigator());
    ScriptPromiseTester tester(
        script_state,
        capabilities->decodingInfo(script_state, config, exception));
    tester.WaitUntilSettled();
    ASSERT_TRUE(tester.IsFulfilled()) << test_case.type;
    auto* info = NativeValueTraits<MediaCapabilitiesDecodingInfo>::NativeValue(
        script_state->GetIsolate(), tester.Value().V8Value(), exception);
    ASSERT_TRUE(info);
    EXPECT_EQ(info->supported(), test_case.supported)
        << test_case.agent << " " << test_case.type;
  }
}

TEST_F(ParcMediaSourceTest, SafariPCMSourceBufferAndChangeType) {
  SetUserAgent(kSafariUserAgent);
  auto* source = OpenMediaSource();
  DummyExceptionStateForTesting add_exception;
  auto* buffer = source->addSourceBuffer("audio/mp4; codecs=\"ipcm\"", add_exception);
  ASSERT_FALSE(add_exception.HadException());
  ASSERT_TRUE(buffer);
  EXPECT_EQ(engine_->data.added_codecs, "ipcm");
  DummyExceptionStateForTesting change_exception;
  buffer->changeType("audio/mp4; codecs=\"fpcm\"", change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_codecs, "fpcm");
#if BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION) && BUILDFLAG(ENABLE_PLATFORM_HEVC)
  DummyExceptionStateForTesting fairplay_exception;
  buffer->changeType("video/mp4; codecs=\"dvh1.05.06,ipcm\"", fairplay_exception);
  EXPECT_FALSE(fairplay_exception.HadException());
#endif
}

TEST_F(ParcMediaSourceTest, SafariSourceBufferSafariContainer) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  SourceBuffer* source_buffer = media_source->addSourceBuffer(
      "video/quicktime; codecs=\"vp09.00.10.08\"", add_exception);
  EXPECT_FALSE(add_exception.HadException());
  ASSERT_TRUE(source_buffer);
  EXPECT_EQ(engine_->data.added_type, "video/quicktime");
  EXPECT_EQ(engine_->data.added_codecs, "vp09.00.10.08");

  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/x-mpeg", change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_type, "audio/x-mpeg");
}

TEST_F(ParcMediaSourceTest, ChromeSourceBufferRefusesSafariContainer) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  EXPECT_FALSE(media_source->addSourceBuffer(
      "video/quicktime; codecs=\"vp09.00.10.08\"", add_exception));
  EXPECT_EQ(add_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_EQ(engine_->data.add_source_buffer_calls, 0);
}

#if BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION) && \
    BUILDFLAG(ENABLE_PLATFORM_HEVC)
// WebKit's MediaSource::addSourceBuffer runs isTypeSupported, which refuses
// Dolby Vision profile 7; profiles 5 and 8 play through the FairPlay Renderer.
class DolbyVisionToolbox final : public media::mojom::blink::ParcVideoToolboxDecoding {
 public:
  DolbyVisionToolbox(bool support, bool hardware) : support_(support), hardware_(hardware) {}
  void GetFacts(GetFactsCallback callback) override {
    auto facts = media::mojom::blink::ParcVideoToolboxDecodingFacts::New();
    facts->hevc_decoder = support_;
    facts->dolby_vision_profiles = Vector<uint16_t>{5, 10, 20};
    facts->dolby_vision_levels = Vector<uint16_t>{6};
    facts->dolby_vision_hardware = hardware_;
    if (!support_) {
      facts->dolby_vision_profiles.reset();
      facts->dolby_vision_levels.reset();
    }
    std::move(callback).Run(std::move(facts));
  }
  void GetSpatialAudioSources(bool, GetSpatialAudioSourcesCallback callback) override {
    std::move(callback).Run({});
  }
  void CanPlayAVFoundationType(const String&, CanPlayAVFoundationTypeCallback callback) override {
    std::move(callback).Run(false);
  }
  void IsPlayableExtendedMIMEType(const String&, IsPlayableExtendedMIMETypeCallback callback) override {
    std::move(callback).Run(false);
  }
 private:
  bool support_;
  bool hardware_;
};

class ParcDolbyVisionCapabilitiesTest : public ParcMediaSourceTest {
 protected:
 void CheckCapabilities(bool vt_support, bool vt_hardware) {
  auto* script_state = ToScriptStateForMainWorld(&GetFrame());
  ScriptState::Scope scope(script_state);
  ASSERT_TRUE(Context()->GetBrowserInterfaceBroker().SetBinderForTesting(
      media::mojom::blink::ParcVideoToolboxDecoding::Name_,
      base::BindRepeating([](bool support, bool hardware, mojo::ScopedMessagePipeHandle pipe) {
        mojo::MakeSelfOwnedReceiver(std::make_unique<DolbyVisionToolbox>(support, hardware),
            mojo::PendingReceiver<media::mojom::blink::ParcVideoToolboxDecoding>(std::move(pipe)));
      }, vt_support, vt_hardware)));
  for (bool hardware : {false, true}) {
    base::test::ScopedCommandLine command_line;
    command_line.GetProcessCommandLine()->AppendSwitchASCII(
        media::kParcAV1HardwareDecoder, hardware ? "1" : "0");
    for (const char* agent : {kSafariUserAgent, kChromeUserAgent}) {
      SetUserAgent(agent);
      for (const char* codec : {"dav1.10.06", "dvh1.20.06", "dvhe.20.06", "dvh1.08.06", "dvh1.20.6",
                                "dvh1.20.06.extra", "dav1.10.06.extra"}) {
        auto* config = MediaDecodingConfiguration::Create();
        config->setType(V8MediaDecodingType::Enum::kMediaSource);
        auto* video = VideoConfiguration::Create();
        video->setContentType(String("video/mp4; codecs=\"") + codec + "\"");
        video->setWidth(1920);
        video->setHeight(1080);
        video->setBitrate(4000000);
        video->setFramerate(60);
        config->setVideo(video);
        DummyExceptionStateForTesting exception;
        auto* capabilities = MediaCapabilities::mediaCapabilities(*GetFrame().DomWindow()->navigator());
        ScriptPromiseTester tester(script_state, capabilities->decodingInfo(script_state, config, exception));
        tester.WaitUntilSettled();
        ASSERT_TRUE(tester.IsFulfilled());
        auto* info = NativeValueTraits<MediaCapabilitiesDecodingInfo>::NativeValue(
            script_state->GetIsolate(), tester.Value().V8Value(), exception);
        ASSERT_TRUE(info);
        const bool expected = agent == kSafariUserAgent &&
            (String(codec) == "dvh1.20.06" || String(codec) == "dvhe.20.06" ||
             (String(codec) == "dav1.10.06" && hardware));
        EXPECT_EQ(expected, info->supported()) << codec;
        EXPECT_EQ(expected && vt_support, info->smooth()) << codec;
        EXPECT_EQ(expected && vt_support && vt_hardware, info->powerEfficient()) << codec;
      }
    }
  }
  Context()->GetBrowserInterfaceBroker().SetBinderForTesting(
      media::mojom::blink::ParcVideoToolboxDecoding::Name_, {});
 }
};

TEST_F(ParcDolbyVisionCapabilitiesTest, MatchesMediaSourceWithHardwareFacts) {
  CheckCapabilities(true, true);
}
TEST_F(ParcDolbyVisionCapabilitiesTest, SupportedWithoutDolbyVisionFacts) {
  CheckCapabilities(false, false);
}
TEST_F(ParcDolbyVisionCapabilitiesTest, SoftwareFactsAreSmoothButNotPowerEfficient) {
  CheckCapabilities(true, false);
}

TEST_F(ParcMediaSourceTest, SafariSourceBufferDolbyVisionProfiles) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting profile7_exception;
  EXPECT_FALSE(media_source->addSourceBuffer(
      "video/mp4; codecs=\"dvh1.07.06\"", profile7_exception));
  EXPECT_EQ(profile7_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_EQ(engine_->data.add_source_buffer_calls, 0);

  DummyExceptionStateForTesting profile8_exception;
  EXPECT_TRUE(media_source->addSourceBuffer("video/mp4; codecs=\"dvh1.08.06\"",
                                            profile8_exception));
  EXPECT_FALSE(profile8_exception.HadException());
}

// AVStreamDataParser's canParseExtendedMIMEType takes profiles 10 (dav1, on
// AV1 hardware) and 20, and refuses 4 and 7.
TEST_F(ParcMediaSourceTest, SafariIsTypeSupportedDolbyVisionProfiles10And20) {
  for (bool hardware : {false, true}) {
    base::test::ScopedCommandLine command_line;
    command_line.GetProcessCommandLine()->AppendSwitchASCII(
        media::kParcAV1HardwareDecoder, hardware ? "1" : "0");
    for (const char* agent : {kSafariUserAgent, kChromeUserAgent}) {
      SetUserAgent(agent);
      const bool safari = agent == kSafariUserAgent;
      EXPECT_EQ(MediaSource::isTypeSupported(
                    Context(), "video/mp4; codecs=\"dav1.10.06\""),
                safari && hardware);
      EXPECT_EQ(MediaSource::isTypeSupported(
                    Context(), "video/mp4; codecs=\"dvh1.20.06\""),
                safari);
      EXPECT_EQ(MediaSource::isTypeSupported(
                    Context(), "video/mp4; codecs=\"dvhe.20.06,mp4a.40.2\""),
                safari);
      EXPECT_FALSE(MediaSource::isTypeSupported(
          Context(), "video/mp4; codecs=\"dvh1.07.06\""));
      EXPECT_FALSE(MediaSource::isTypeSupported(
          Context(), "video/mp4; codecs=\"dvh1.04.06\""));
      if (safari) {
        auto* source = OpenMediaSource();
        DummyExceptionStateForTesting exception_state;
        EXPECT_EQ(source->addSourceBuffer("video/mp4; codecs=\"dav1.10.06\"",
                                          exception_state) != nullptr,
                  hardware);
      }
    }
  }
}

TEST_F(ParcMediaSourceTest, ChromeSourceBufferTakesDolbyVisionProfile7) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting exception_state;
  EXPECT_TRUE(media_source->addSourceBuffer("video/mp4; codecs=\"dvh1.07.06\"",
                                            exception_state));
  EXPECT_FALSE(exception_state.HadException());
}
#endif  // BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION) && ...

TEST_F(ParcMediaSourceTest, SafariSourceBufferWithoutCodecs) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  SourceBuffer* source_buffer =
      media_source->addSourceBuffer("video/mp4", add_exception);
  EXPECT_FALSE(add_exception.HadException());
  ASSERT_TRUE(source_buffer);
  EXPECT_EQ(engine_->data.added_type, "video/mp4");
  EXPECT_TRUE(engine_->data.added_codecs.empty());

  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/mp4", change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_type, "audio/mp4");
  EXPECT_TRUE(engine_->data.changed_codecs.empty());
}

TEST_F(ParcMediaSourceTest, ChromeSourceBufferNeedsCodecs) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  EXPECT_FALSE(media_source->addSourceBuffer("video/mp4", add_exception));
  EXPECT_EQ(add_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_EQ(engine_->data.add_source_buffer_calls, 0);

  DummyExceptionStateForTesting add_with_codecs_exception;
  SourceBuffer* source_buffer = media_source->addSourceBuffer(
      "video/webm; codecs=\"vp8\"", add_with_codecs_exception);
  ASSERT_TRUE(source_buffer);
  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("audio/webm", change_exception);
  EXPECT_EQ(change_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);
  EXPECT_TRUE(engine_->data.changed_type.IsNull());
}

// WebKit's MediaSource::setDurationInternal, step 4.1.
TEST_F(ParcMediaSourceTest, SafariDurationBelowBufferedEndBecomesIt) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = MediaSourceWithBufferedEnd();

  DummyExceptionStateForTesting exception_state;
  media_source->setDuration(10.02, exception_state);
  EXPECT_FALSE(exception_state.HadException());
  EXPECT_EQ(engine_->data.duration, 10.04);
  EXPECT_EQ(media_source->duration(), 10.04);
  EXPECT_EQ(video_->duration(), 10.04);

  media_source->setDuration(12, exception_state);
  EXPECT_FALSE(exception_state.HadException());
  EXPECT_EQ(media_source->duration(), 12);
  EXPECT_EQ(video_->duration(), 12);

  DummyExceptionStateForTesting below_last_frame_exception;
  media_source->setDuration(9, below_last_frame_exception);
  EXPECT_EQ(below_last_frame_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kInvalidStateError);
  EXPECT_EQ(media_source->duration(), 12);
}

TEST_F(ParcMediaSourceTest, ChromeDurationBelowBufferedEndStaysAsSet) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = MediaSourceWithBufferedEnd();

  DummyExceptionStateForTesting exception_state;
  media_source->setDuration(10.02, exception_state);
  EXPECT_FALSE(exception_state.HadException());
  EXPECT_EQ(engine_->data.duration, 10.02);
  EXPECT_EQ(media_source->duration(), 10.02);
  EXPECT_EQ(video_->duration(), 10.02);
}

#if BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)
// +[AVStreamDataParser canParseExtendedMIMEType:] on macOS 27.2, for codecs
// Chromium's TS parser reads and Parc plays.
TEST_F(ParcMediaSourceTest, SafariMp2tTypesAsSafari) {
  SetUserAgent(kSafariUserAgent);
  for (const char* type : {
           "video/mp2t",
           "video/mp2t; codecs=\"\"",
           "video/mp2t; codecs=\"avc1.64001F,mp4a.40.2\"",
           "video/mp2t; codecs=\"avc1\"",
           "video/mp2t; codecs=\"avc3\"",
           "video/mp2t; codecs=\"avc1.\"",
           "video/mp2t; codecs=\"avc1.42E0\"",
           "video/mp2t; codecs=\"avc3.ZZZZZZ\"",
           "video/mp2t; codecs=\"avc1.F4003E\"",
           "video/mp2t; codecs=\"avc1.420063\"",
           "video/mp2t; codecs=\"avc1.42e01e\"",
           "video/mp2t; codecs=\"avc1.000000.foo\"",
           "video/mp2t; codecs=\"mp4a.40.02\"",
           "video/mp2t; codecs=\"mp4a.40.5\"",
           "video/mp2t; codecs=\"mp4a.40.29\"",
           "video/mp2t; codecs=\"mp4a.40.42\"",
           "video/mp2t; codecs=\"mp4a.40.32\"",
           "video/mp2t; codecs=\"mp4a.40.033\"",
           "video/mp2t; codecs=\"mp4a.0040.002\"",
           "video/mp2t; codecs=\"mp4a.0x40.+2\"",
           "video/mp2t; codecs=\"mp4a.67\"",
           "video/mp2t; codecs=\"mp4a.67x\"",
           "video/mp2t; codecs=\"ac-3\"",
           "video/mp2t; codecs=\"ac-3.a.b\"",
           "video/mp2t; codecs=\"ec-3\"",
           "video/mp2t; codecs=\"ec-3.20\"",
           "video/mp2t; codecs=\"avc1.64001F mp4a.40.5\"",
           "video/mp2t; codecs=\",avc1.64001F,,ac-3,\"",
           "video/x-mp2t; codecs=\"avc1.64001F\"",
           "video/m2ts; codecs=\"mp4a.40.2\"",
           "video/x-m2ts; codecs=\"avc1.4D401F,ec-3\"",
           "video/mp2t; codecs=\"mp2v\"",
           "video/mp2t; codecs=\"mp2v.60\"",
           "video/mp2t; codecs=\"mp2v.61\"",
           "video/mp2t; codecs=\"mp2v.65\"",
           "video/mp2t; codecs=\"mp2v.0x61\"",
           "video/mp2t; codecs=\"mp2v.061\"",
           "video/mp2t; codecs=\"mp2v.+61\"",
           "video/mp2t; codecs=\"mp2v,mp4a.40.2\"",
           "video/mp2t; codecs=\"mp2v ac-3\"",
           "video/mp2t; codecs=\"mp1v\"",
           "video/mp2t; codecs=\"mp1v.\"",
           "video/mp2t; codecs=\"mp1v.x.y\"",
           "video/mp2t; codecs=\"mp1v,mp4a.40.33\"",
       }) {
    EXPECT_TRUE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
  for (const char* type : {
           // Safari refuses these.
           "video/mp2t; codecs=\"mp3\"",
           "video/mp2t; codecs=\"mp4a.69\"",
           "video/mp2t; codecs=\"mp4a.6B\"",
           "video/mp2t; codecs=\"mp4a.66\"",
           "video/mp2t; codecs=\"mp4a.68\"",
           "video/mp2t; codecs=\"mp4a.40.1\"",
           "video/mp2t; codecs=\"mp4a.40.34\"",
           "video/mp2t; codecs=\"mp4a.40\"",
           "video/mp2t; codecs=\"mp4a.40.2x\"",
           "video/mp2t; codecs=\"mp4a.67.2\"",
           "video/mp2t; codecs=\"MP4A.40.2\"",
           "video/mp2t; codecs=\"AVC1.42E01E\"",
           "video/mp2t; codecs=\"avc1x\"",
           "video/mp2t; codecs=\"avc1.000000\"",
           "video/mp2t; codecs=\"avc1.10001E\"",
           "video/mp2t; codecs=\"avc1.420064\"",
           "video/mp2t; codecs=\"avc1.0x6400\"",
           "video/mp2t; codecs=\"avc1.6400 1F\"",
           "video/mp2t; codecs=\"avc1.64001F,mp3\"",
           "video/mp2t; codecs=\"AC-3\"",
           "video/mp2t; codecs=\"ac3\"",
           "video/mp2t; codecs=\"ac-3x\"",
           "video/mp2t; codecs=\"hvc1.1.6.L93.B0\"",
           "video/mp2t; codecs=\",\"",
           "video/mp2t; codecs=\", ,\"",
           "VIDEO/MP2T",
           "audio/mp2t; codecs=\"mp4a.40.2\"",
           "video/mp2t; codecs=\"mp2v.\"",
           "video/mp2t; codecs=\"mp2v.62\"",
           "video/mp2t; codecs=\"mp2v.63\"",
           "video/mp2t; codecs=\"mp2v.64\"",
           "video/mp2t; codecs=\"mp2v.6A\"",
           "video/mp2t; codecs=\"mp2v.-61\"",
           "video/mp2t; codecs=\"mp2v.61x\"",
           "video/mp2t; codecs=\"mp2v.61.0\"",
           "video/mp2t; codecs=\"mp2vx\"",
           "video/mp2t; codecs=\"MP2V\"",
           "video/mp2t; codecs=\"mp1vx\"",
           "video/mp2t; codecs=\"MP1V\"",
           "video/mp2t; codecs=\"mp2v,mp4a.40.34\"",
       }) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

TEST_F(ParcMediaSourceTest, ChromeMp2tTypesUnchanged) {
  SetUserAgent(kChromeUserAgent);
  EXPECT_TRUE(MediaSource::isTypeSupported(
      Context(), "video/mp2t; codecs=\"avc1.64001F,mp4a.40.2\""));
  EXPECT_TRUE(
      MediaSource::isTypeSupported(Context(), "video/mp2t; codecs=\"mp3\""));
  EXPECT_TRUE(MediaSource::isTypeSupported(Context(),
                                           "video/mp2t; codecs=\"mp4a.69\""));
  for (const char* type : {
           "video/mp2t; codecs=\"avc1\"",
           "video/mp2t; codecs=\"ac-3\"",
           "video/mp2t; codecs=\"ec-3\"",
           "video/mp2t; codecs=\"mp2v\"",
           "video/mp2t; codecs=\"mp1v\"",
           "video/x-mp2t; codecs=\"avc1.64001F\"",
           "video/m2ts; codecs=\"avc1.64001F\"",
       }) {
    EXPECT_FALSE(MediaSource::isTypeSupported(Context(), type)) << type;
  }
}

// addSourceBuffer and changeType hand Chromium's TS parser video/mp2t with
// codecs its factory takes; it parses every stream whatever they name.
TEST_F(ParcMediaSourceTest, SafariMp2tSourceBuffer) {
  SetUserAgent(kSafariUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  SourceBuffer* source_buffer = media_source->addSourceBuffer(
      "video/x-m2ts; codecs=\"avc1.64001F, ac-3\"", add_exception);
  EXPECT_FALSE(add_exception.HadException());
  ASSERT_TRUE(source_buffer);
  EXPECT_EQ(engine_->data.added_type, "video/mp2t");
  EXPECT_EQ(engine_->data.added_codecs, "avc1.42E01E");

  DummyExceptionStateForTesting change_exception;
  source_buffer->changeType("video/mp2t; codecs=\"ec-3,mp4a.40.33\"",
                            change_exception);
  EXPECT_FALSE(change_exception.HadException());
  EXPECT_EQ(engine_->data.changed_type, "video/mp2t");
  EXPECT_EQ(engine_->data.changed_codecs, "mp4a.69");

  DummyExceptionStateForTesting change_to_ac3_exception;
  source_buffer->changeType("video/mp2t; codecs=\"ac-3\"",
                            change_to_ac3_exception);
  EXPECT_FALSE(change_to_ac3_exception.HadException());
  EXPECT_TRUE(engine_->data.changed_codecs.empty());
}

TEST_F(ParcMediaSourceTest, ChromeMp2tSourceBufferUnchanged) {
  SetUserAgent(kChromeUserAgent);
  MediaSource* media_source = OpenMediaSource();

  DummyExceptionStateForTesting add_exception;
  EXPECT_FALSE(media_source->addSourceBuffer(
      "video/x-m2ts; codecs=\"avc1.64001F\"", add_exception));
  EXPECT_EQ(add_exception.CodeAs<DOMExceptionCode>(),
            DOMExceptionCode::kNotSupportedError);

  DummyExceptionStateForTesting add_mp2t_exception;
  ASSERT_TRUE(media_source->addSourceBuffer(
      "video/mp2t; codecs=\"avc1.64001F,mp4a.40.2\"", add_mp2t_exception));
  EXPECT_EQ(engine_->data.added_type, "video/mp2t");
  EXPECT_EQ(engine_->data.added_codecs, "avc1.64001F,mp4a.40.2");
}
#endif  // BUILDFLAG(ENABLE_MSE_MPEG2TS_STREAM_PARSER)

TEST_F(ParcMediaSourceTest, SafariMp2tParserCodecs) {
  EXPECT_EQ(ParcSafariMp2tParserCodecs(""), "");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("avc3.ZZ, mp4a.40.05"),
            "avc1.42E01E,mp4a.40.5");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("mp4a.40.029 mp4a.067"),
            "mp4a.40.29,mp4a.67");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("avc1.64001F,,"), "avc1.42E01E");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("ac-3,mp4a.40.2"), "mp4a.40.2");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("ac-3 ec-3.20"), "");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("mp2v.61,mp4a.40.2"), "mp4a.40.2");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("mp1v mp2v"), "");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("mp4a.40.32,mp4a.40.033"),
            "mp4a.69,mp4a.69");
  EXPECT_EQ(ParcSafariMp2tParserCodecs("  "), "");
  EXPECT_EQ(ParcSafariMp2tParserCodecs(", ,"), std::nullopt);
  EXPECT_EQ(ParcSafariMp2tParserCodecs(","), std::nullopt);
  EXPECT_EQ(ParcSafariMp2tParserCodecs("avc1.64001F,mp3"), std::nullopt);
}

TEST_F(ParcMediaSourceTest, SafariMp2tParserType) {
  String mime_type = "video/x-m2ts";
  String codecs = "avc1";
  ParcUseSafariMp2tParser(kSafariUserAgent, mime_type, codecs);
  EXPECT_EQ(mime_type, "video/mp2t");
  EXPECT_EQ(codecs, "avc1.42E01E");

  mime_type = "video/x-m2ts";
  codecs = "avc1";
  ParcUseSafariMp2tParser(kChromeUserAgent, mime_type, codecs);
  EXPECT_EQ(mime_type, "video/x-m2ts");
  EXPECT_EQ(codecs, "avc1");

  mime_type = "video/mp4";
  codecs = "avc1.64001F";
  ParcUseSafariMp2tParser(kSafariUserAgent, mime_type, codecs);
  EXPECT_EQ(mime_type, "video/mp4");
  EXPECT_EQ(codecs, "avc1.64001F");
}

}  // namespace
}  // namespace blink

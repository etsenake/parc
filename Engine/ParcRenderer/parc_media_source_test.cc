// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/mediasource/parc_media_source_test.cc
// (blink_unittests). Tests what a MediaSource tells a page and its media
// engine under Safari's identity (parc_safari_identity.h) and under Chrome's:
// types named without codecs, and a duration set below the buffered end.

#include <limits>
#include <memory>

#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/video_decoder_config.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/platform/web_media_source.h"
#include "third_party/blink/public/platform/web_source_buffer.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_time_range.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/settings.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
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

  void SetClient(WebSourceBufferClient*) override {}
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

}  // namespace
}  // namespace blink

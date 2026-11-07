// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/mediasource/parc_media_source_error_test.cc
// (blink_unittests). A failed append on a Safari-identity page closes the
// MediaSource before the page's handlers run, as WebKit's
// SourceBuffer::appendError and MediaSource::streamEndedWithError do.
#include <cmath>
#include <memory>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/video_decoder_config.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/platform/web_media_player_client.h"
#include "third_party/blink/public/platform/web_media_source.h"
#include "third_party/blink/public/platform/web_source_buffer.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/events/native_event_listener.h"
#include "third_party/blink/renderer/core/event_type_names.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/media_error.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/core/loader/empty_clients.h"
#include "third_party/blink/renderer/core/testing/dummy_page_holder.h"
#include "third_party/blink/renderer/core/typed_arrays/dom_array_buffer.h"
#include "third_party/blink/renderer/modules/mediasource/media_source.h"
#include "third_party/blink/renderer/modules/mediasource/source_buffer.h"
#include "third_party/blink/renderer/modules/mediasource/source_buffer_list.h"
#include "third_party/blink/renderer/modules/mediasource/url_media_source.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/media/media_player_client.h"
#include "third_party/blink/renderer/platform/testing/empty_web_media_player.h"
#include "third_party/blink/renderer/platform/testing/task_environment.h"
#include "third_party/blink/renderer/platform/testing/unit_test_helpers.h"
#include "third_party/blink/renderer/platform/weborigin/security_origin.h"

namespace blink {

namespace {

constexpr char kSafariUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/27.2 Safari/605.1.15";
constexpr char kChromeUserAgent[] =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

// Every append fails to parse.
class FailingWebSourceBuffer final : public WebSourceBuffer {
 public:
  void SetClient(WebSourceBufferClient*) override {}
  bool SetMode(AppendMode) override { return true; }
  bool GetGenerateTimestampsFlag() override { return false; }
  WebTimeRanges Buffered() override { return {}; }
  double HighestPresentationTimestamp() override { return 0; }
  bool EvictCodedFrames(double, size_t) override { return true; }
  bool AppendToParseBuffer(base::span<const unsigned char>) override {
    return true;
  }
  media::StreamParser::ParseStatus RunSegmentParserLoop(double*) override {
    return media::StreamParser::ParseStatus::kFailed;
  }
  bool AppendChunks(std::unique_ptr<media::StreamParser::BufferQueue>,
                    double*) override {
    return false;
  }
  void ResetParserState() override {}
  void Remove(double, double) override {}
  bool CanChangeType(const WebString&, const WebString&) override {
    return true;
  }
  void ChangeType(const WebString&, const WebString&) override {}
  bool SetTimestampOffset(double) override { return true; }
  void SetAppendWindowStart(double) override {}
  void SetAppendWindowEnd(double) override {}
  void RemovedFromMediaSource() override {}
};

class FakeWebMediaSource final : public WebMediaSource {
 public:
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      const WebString&,
      const WebString&,
      AddStatus& out_status) override {
    out_status = kAddStatusOk;
    return std::make_unique<FailingWebSourceBuffer>();
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::AudioDecoderConfig>,
      AddStatus& out_status) override {
    out_status = kAddStatusNotSupported;
    return nullptr;
  }
  std::unique_ptr<WebSourceBuffer> AddSourceBuffer(
      std::unique_ptr<media::VideoDecoderConfig>,
      AddStatus& out_status) override {
    out_status = kAddStatusNotSupported;
    return nullptr;
  }
  double Duration() override { return 10; }
  void SetDuration(double) override {}
  void MarkEndOfStream(EndOfStreamStatus) override {}
  void UnmarkEndOfStream() override {}
};

// Opens the MediaSource and reports states as the pipeline would.
class MediaSourcePlayer final : public EmptyWebMediaPlayer {
 public:
  explicit MediaSourcePlayer(WebMediaPlayerClient* client)
      : client_(static_cast<MediaPlayerClient*>(client)) {}

  void OpenMediaSource() {
    client_->MediaSourceOpened(std::make_unique<FakeWebMediaSource>());
  }
  void SetReadyState(ReadyState state) {
    ready_state_ = state;
    client_->ReadyStateChanged();
  }
  void ReportDecodeError() {
    network_state_ = kNetworkStateDecodeError;
    client_->NetworkStateChanged();
  }

  NetworkState GetNetworkState() const override { return network_state_; }
  ReadyState GetReadyState() const override { return ready_state_; }

 private:
  raw_ptr<MediaPlayerClient> client_;
  NetworkState network_state_ = kNetworkStateLoading;
  ReadyState ready_state_ = kReadyStateHaveNothing;
};

class MediaSourceFrameClient final : public EmptyLocalFrameClient {
 public:
  explicit MediaSourceFrameClient(const char* user_agent)
      : user_agent_(user_agent) {}

  std::unique_ptr<WebMediaPlayer> CreateWebMediaPlayer(
      HTMLMediaElement&,
      const WebMediaPlayerSource&,
      WebMediaPlayerClient* client) override {
    auto player = std::make_unique<MediaSourcePlayer>(client);
    player_ = player.get();
    return player;
  }
  String UserAgent() override { return user_agent_; }

  MediaSourcePlayer* player() const { return player_; }

 private:
  String user_agent_;
  raw_ptr<MediaSourcePlayer, DanglingUntriaged> player_ = nullptr;
};

class CountingListener final : public NativeEventListener {
 public:
  void Invoke(ExecutionContext*, Event*) override { ++count_; }
  int count() const { return count_; }

 private:
  int count_ = 0;
};

// What the page sees in its first SourceBuffer error handler, which appends
// again.
class ErrorHandlerState final : public NativeEventListener {
 public:
  ErrorHandlerState(HTMLMediaElement* media,
                    MediaSource* source,
                    SourceBuffer* buffer)
      : media_(media), source_(source), buffer_(buffer) {}

  void Invoke(ExecutionContext*, Event*) override {
    if (++count > 1) {
      return;
    }
    media_error = media_->error() ? media_->error()->code() : 0;
    ready_state = source_->readyState();
    source_buffers = source_->sourceBuffers()->length();
    DummyExceptionStateForTesting exception_state;
    buffer_->appendBuffer(DOMArrayBuffer::Create(4u, 1u), exception_state);
    append_threw_invalid_state =
        exception_state.HadException() &&
        exception_state.CodeAs<DOMExceptionCode>() ==
            DOMExceptionCode::kInvalidStateError;
  }

  void Trace(Visitor* visitor) const override {
    visitor->Trace(media_);
    visitor->Trace(source_);
    visitor->Trace(buffer_);
    NativeEventListener::Trace(visitor);
  }

  int count = 0;
  int media_error = -1;
  AtomicString ready_state;
  unsigned source_buffers = 0;
  bool append_threw_invalid_state = false;

 private:
  Member<HTMLMediaElement> media_;
  Member<MediaSource> source_;
  Member<SourceBuffer> buffer_;
};

class ParcMediaSourceErrorTest : public testing::Test {
 protected:
  // Attaches a MediaSource with one SourceBuffer to a video element that has
  // its metadata, then appends.
  void AppendFailingSegment(const char* user_agent) {
    frame_client_ = MakeGarbageCollected<MediaSourceFrameClient>(user_agent);
    page_holder_ = std::make_unique<DummyPageHolder>(gfx::Size(), nullptr,
                                                     frame_client_);
    Document& document = page_holder_->GetDocument();
    const KURL origin("https://example.com/");
    document.SetURL(origin);
    document.domWindow()->GetSecurityContext().SetSecurityOriginForTesting(
        nullptr);
    document.domWindow()->GetSecurityContext().SetSecurityOrigin(
        SecurityOrigin::Create(origin));

    video_ = MakeGarbageCollected<HTMLVideoElement>(document);
    source_ = MediaSource::Create(document.domWindow());
    String url;
    {
      ScriptState* script_state =
          ToScriptStateForMainWorld(&page_holder_->GetFrame());
      ScriptState::Scope scope(script_state);
      url = URLMediaSource::createObjectURL(script_state, source_);
    }
    video_->setAttribute(html_names::kSrcAttr, AtomicString(url));
    test::RunPendingTasks();
    ASSERT_TRUE(frame_client_->player());
    frame_client_->player()->OpenMediaSource();
    ASSERT_EQ(source_->readyState(), "open");

    buffer_ = source_->addSourceBuffer("video/webm; codecs=\"vp8\"",
                                       ASSERT_NO_EXCEPTION);
    ASSERT_TRUE(buffer_);
    frame_client_->player()->SetReadyState(
        WebMediaPlayer::kReadyStateHaveMetadata);
    test::RunPendingTasks();

    media_errors_ = MakeGarbageCollected<CountingListener>();
    video_->addEventListener(event_type_names::kError, media_errors_);
    handler_ = MakeGarbageCollected<ErrorHandlerState>(video_, source_,
                                                       buffer_);
    buffer_->addEventListener(event_type_names::kError, handler_);
    buffer_->appendBuffer(DOMArrayBuffer::Create(4u, 1u),
                          ASSERT_NO_EXCEPTION);
    test::RunPendingTasks();
  }

  test::TaskEnvironment task_environment_;
  Persistent<MediaSourceFrameClient> frame_client_;
  std::unique_ptr<DummyPageHolder> page_holder_;
  Persistent<HTMLVideoElement> video_;
  Persistent<MediaSource> source_;
  Persistent<SourceBuffer> buffer_;
  Persistent<CountingListener> media_errors_;
  Persistent<ErrorHandlerState> handler_;
};

TEST_F(ParcMediaSourceErrorTest, SafariAppendErrorClosesSourceFirst) {
  ASSERT_NO_FATAL_FAILURE(AppendFailingSegment(kSafariUserAgent));
  ASSERT_EQ(handler_->count, 1);
  EXPECT_EQ(handler_->media_error, MediaError::kMediaErrDecode);
  EXPECT_EQ(handler_->ready_state, "closed");
  EXPECT_EQ(handler_->source_buffers, 0u);
  EXPECT_TRUE(handler_->append_threw_invalid_state);
  EXPECT_TRUE(std::isnan(source_->duration()));

  // The pipeline's own report of the error comes later and changes nothing.
  frame_client_->player()->ReportDecodeError();
  test::RunPendingTasks();
  EXPECT_EQ(media_errors_->count(), 1);
  EXPECT_EQ(handler_->count, 1);
}

TEST_F(ParcMediaSourceErrorTest, ChromeAppendErrorWaitsForPipeline) {
  ASSERT_NO_FATAL_FAILURE(AppendFailingSegment(kChromeUserAgent));
  EXPECT_EQ(handler_->media_error, 0);
  EXPECT_EQ(handler_->ready_state, "ended");
  EXPECT_EQ(handler_->source_buffers, 1u);
  EXPECT_FALSE(handler_->append_threw_invalid_state);
  // The handler's append was accepted and failed again.
  EXPECT_EQ(handler_->count, 2);
  EXPECT_EQ(source_->readyState(), "ended");
  EXPECT_EQ(media_errors_->count(), 0);

  frame_client_->player()->ReportDecodeError();
  test::RunPendingTasks();
  ASSERT_TRUE(video_->error());
  EXPECT_EQ(video_->error()->code(), MediaError::kMediaErrDecode);
  EXPECT_EQ(media_errors_->count(), 1);
  EXPECT_NE(source_->readyState(), "closed");
}

}  // namespace

}  // namespace blink

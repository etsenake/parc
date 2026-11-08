// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/fairplay_hls_loader_unittest.cc
// (blink_platform_unittests). Tests the native HLS route's render-process
// loader: which request goes out, how redirects and responses come back,
// body streaming with back pressure, and every way a load is cancelled.
#include "third_party/blink/renderer/platform/media/fairplay_hls_loader.h"

#include <stdint.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/string_util.h"
#include "base/test/scoped_feature_list.h"
#include "base/test/task_environment.h"
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "net/base/net_errors.h"
#include "services/network/public/mojom/cors.mojom-shared.h"
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/blink/public/mojom/fetch/fetch_api_request.mojom-shared.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/public/platform/web_url_error.h"
#include "third_party/blink/public/platform/web_url_request.h"
#include "third_party/blink/public/platform/web_url_response.h"
#include "third_party/blink/public/web/web_associated_url_loader_client.h"
#include "third_party/blink/public/web/web_associated_url_loader_options.h"
#include "third_party/blink/renderer/platform/media/testing/mock_resource_fetch_context.h"
#include "third_party/blink/renderer/platform/media/resource_multi_buffer_data_provider.h"
#include "third_party/blink/renderer/platform/media/testing/mock_web_associated_url_loader.h"
#include "third_party/blink/renderer/platform/weborigin/kurl.h"
#include "url/gurl.h"

namespace blink {

namespace {

using ::testing::_;
using ::testing::Invoke;
using ::testing::NiceMock;

constexpr char kPlaylistUrl[] = "https://media.example/hls/master.m3u8";
constexpr char kCdnUrl[] = "https://cdn.example/hls/master.m3u8";
constexpr char kFinalUrl[] = "https://edge.cdn.example/v1/master.m3u8";

// The GPU side of one load.
class FakeLoadClient : public media::mojom::FairPlayHlsLoadClient {
 public:
  void OnResponse(media::mojom::FairPlayHlsResponsePtr response,
                  mojo::ScopedDataPipeConsumerHandle body) override {
    EXPECT_FALSE(response_);
    EXPECT_FALSE(completed_);
    response_ = std::move(response);
    body_ = std::move(body);
  }

  void OnComplete(int32_t net_error) override {
    EXPECT_FALSE(completed_);
    completed_ = true;
    net_error_ = net_error;
  }

  // Everything readable now. Sets |body_closed_| once the producer is gone
  // and the pipe is empty.
  std::string Drain() {
    std::string out;
    while (body_.is_valid()) {
      char buffer[4096];
      size_t read = 0;
      MojoResult result = body_->ReadData(
          MOJO_READ_DATA_FLAG_NONE, base::as_writable_byte_span(buffer), read);
      if (result == MOJO_RESULT_SHOULD_WAIT) {
        break;
      }
      if (result != MOJO_RESULT_OK) {
        body_closed_ = true;
        break;
      }
      out.append(buffer, read);
    }
    return out;
  }

  mojo::Receiver<media::mojom::FairPlayHlsLoadClient> receiver_{this};
  bool disconnected_ = false;
  media::mojom::FairPlayHlsResponsePtr response_;
  mojo::ScopedDataPipeConsumerHandle body_;
  bool body_closed_ = false;
  bool completed_ = false;
  int32_t net_error_ = 1;
};

// What the loader asked WebAssociatedURLLoader for.
struct CapturedRequest {
  GURL url;
  std::string method;
  std::string range;
  std::string accept_encoding;
  bool has_user_agent = false;
  bool has_session_id = false;
  bool has_accept = false;
  mojom::RequestContextType context = mojom::RequestContextType::UNSPECIFIED;
  network::mojom::RequestDestination destination =
      network::mojom::RequestDestination::kEmpty;
  network::mojom::RequestMode mode = network::mojom::RequestMode::kNoCors;
  network::mojom::CredentialsMode credentials =
      network::mojom::CredentialsMode::kInclude;
  WebAssociatedURLLoaderOptions options;
};

class FairPlayHlsLoaderTest : public testing::Test {
 public:
  FairPlayHlsLoaderTest() {
    ON_CALL(fetch_context_, CreateUrlLoader(_))
        .WillByDefault(Invoke(this, &FairPlayHlsLoaderTest::CreateUrlLoader));
  }

  void MakeLoader(UrlData::CorsMode cors_mode = UrlData::CORS_UNSPECIFIED,
                  bool is_audio_element = false) {
    loader_ = std::make_unique<FairPlayHlsLoader>(&fetch_context_, cors_mode,
                                                  is_audio_element);
  }

  static media::mojom::FairPlayHlsRequestPtr Request(
      const char* url = kPlaylistUrl,
      const char* method = "GET") {
    auto request = media::mojom::FairPlayHlsRequest::New();
    request->url = GURL(url);
    request->method = method;
    return request;
  }

  // Starts |request| with fresh pipes and runs the posted work.
  void Start(media::mojom::FairPlayHlsRequestPtr request) {
    load_.reset();
    client_ = std::make_unique<FakeLoadClient>();
    client_->receiver_.set_disconnect_handler(base::BindOnce(
        [](FakeLoadClient* client) { client->disconnected_ = true; },
        base::Unretained(client_.get())));
    loader_->StartLoad(std::move(request), load_.BindNewPipeAndPassReceiver(),
                       client_->receiver_.BindNewPipeAndPassRemote());
    task_environment_.RunUntilIdle();
  }

  void Respond(int status,
               const char* mime_type,
               int64_t content_length,
               const char* content_encoding = nullptr,
               const char* content_range = nullptr) {
    WebURLResponse response{WebURL(KURL(kPlaylistUrl))};
    response.SetHttpStatusCode(status);
    response.SetMimeType(WebString::FromAscii(mime_type));
    response.SetExpectedContentLength(content_length);
    if (content_length >= 0) {
      response.SetHttpHeaderField(
          WebString::FromAscii("Content-Length"),
          WebString::FromAscii(std::to_string(content_length)));
    }
    if (content_encoding) {
      response.SetHttpHeaderField(WebString::FromAscii("Content-Encoding"),
                                  WebString::FromAscii(content_encoding));
    }
    if (content_range) {
      response.SetHttpHeaderField(WebString::FromAscii("Content-Range"),
                                  WebString::FromAscii(content_range));
    }
    response.SetHttpHeaderField(WebString::FromAscii("Cache-Control"),
                                WebString::FromAscii("max-age=2"));
    if (etag_) {
      response.SetHttpHeaderField(WebString::FromAscii("ETag"),
                                  WebString::FromAscii(etag_));
    }
    url_client_->DidReceiveResponse(response);
    task_environment_.RunUntilIdle();
  }

  void Data(const std::string& bytes) {
    url_client_->DidReceiveData(base::span(bytes));
    task_environment_.RunUntilIdle();
  }

 protected:
  std::unique_ptr<WebAssociatedURLLoader> CreateUrlLoader(
      const WebAssociatedURLLoaderOptions& options) {
    auto url_loader = std::make_unique<NiceMock<MockWebAssociatedURLLoader>>();
    url_loader_ = url_loader.get();
    captured_ = CapturedRequest();
    captured_->options = options;
    EXPECT_CALL(*url_loader, LoadAsynchronously(_, _))
        .WillOnce([this](const WebURLRequest& request,
                         WebAssociatedURLLoaderClient* client) {
          url_client_ = client;
          CapturedRequest& c = *captured_;
          c.url = GURL(KURL(request.Url()));
          c.method = request.HttpMethod().Utf8();
          c.range = request.HttpHeaderField(WebString::FromAscii("Range"))
                        .Utf8();
          c.accept_encoding =
              request.HttpHeaderField(WebString::FromAscii("Accept-Encoding"))
                  .Utf8();
          c.has_user_agent =
              !request.HttpHeaderField(WebString::FromAscii("User-Agent"))
                   .IsEmpty();
          c.has_session_id = !request
                                  .HttpHeaderField(WebString::FromAscii(
                                      "X-Playback-Session-Id"))
                                  .IsEmpty();
          c.has_accept =
              !request.HttpHeaderField(WebString::FromAscii("Accept"))
                   .IsEmpty();
          c.context = request.GetRequestContext();
          c.destination = request.GetRequestDestination();
          c.mode = request.GetMode();
          c.credentials = request.GetCredentialsMode();
        });
    return url_loader;
  }

  base::test::TaskEnvironment task_environment_;
  NiceMock<MockResourceFetchContext> fetch_context_;
  std::unique_ptr<FairPlayHlsLoader> loader_;
  mojo::Remote<media::mojom::FairPlayHlsLoad> load_;
  std::unique_ptr<FakeLoadClient> client_;
  // Owned by the load under test; valid until it finishes or stops.
  raw_ptr<MockWebAssociatedURLLoader, DanglingUntriaged> url_loader_ =
      nullptr;
  raw_ptr<WebAssociatedURLLoaderClient, DanglingUntriaged> url_client_ =
      nullptr;
  std::optional<CapturedRequest> captured_;
  // Every response's ETag, if any.
  const char* etag_ = nullptr;
};

TEST_F(FairPlayHlsLoaderTest, ForwardsOnlyRangeAsAMediaRequest) {
  MakeLoader();
  auto request = Request();
  request->headers = {
      {"range", "bytes=100-199"},
      {"User-Agent", "AppleCoreMedia/1.0.0.24A335 (Macintosh; U; Intel Mac)"},
      {"X-Playback-Session-Id", "7C1A2E61-4A3B-4F7B-9C4E-6E2B2B1C0D11"},
      {"Accept", "*/*"},
  };
  Start(std::move(request));

  ASSERT_TRUE(captured_);
  EXPECT_EQ(GURL(kPlaylistUrl), captured_->url);
  EXPECT_EQ("GET", captured_->method);
  EXPECT_EQ("bytes=100-199", captured_->range);
  // The network layer adds the identity encoding, as for <video src>.
  EXPECT_TRUE(captured_->accept_encoding.empty());
  EXPECT_FALSE(captured_->has_user_agent);
  EXPECT_FALSE(captured_->has_session_id);
  EXPECT_FALSE(captured_->has_accept);
  EXPECT_EQ(mojom::RequestContextType::VIDEO, captured_->context);
  EXPECT_EQ(network::mojom::RequestDestination::kVideo,
            captured_->destination);
  EXPECT_EQ(network::mojom::RequestMode::kNoCors, captured_->mode);
  EXPECT_EQ(network::mojom::CredentialsMode::kInclude, captured_->credentials);
  EXPECT_FALSE(captured_->options.expose_all_response_headers);
  EXPECT_EQ(1u, loader_->load_count_for_testing());
}

TEST_F(FairPlayHlsLoaderTest, RangeAsksForIdentityWhenTheLoaderMustAddIt) {
  base::test::ScopedFeatureList features;
  features.InitAndDisableFeature(kDeferMediaAcceptEncodingInjection);
  MakeLoader();
  auto request = Request();
  request->headers = {{"Range", "bytes=0-1"}};
  Start(std::move(request));
  ASSERT_TRUE(captured_);
  EXPECT_EQ("bytes=0-1", captured_->range);
  EXPECT_EQ("identity;q=1, *;q=0", captured_->accept_encoding);
}

TEST_F(FairPlayHlsLoaderTest, NoRangeLeavesTheEncodingToTheNetworkStack) {
  MakeLoader();
  Start(Request(kPlaylistUrl, "HEAD"));
  ASSERT_TRUE(captured_);
  EXPECT_EQ("HEAD", captured_->method);
  EXPECT_TRUE(captured_->range.empty());
  EXPECT_TRUE(captured_->accept_encoding.empty());
}

TEST_F(FairPlayHlsLoaderTest, DropsAMalformedRange) {
  MakeLoader();
  auto request = Request();
  request->headers = {{"Range", "bytes=0-1\r\nX-Injected: 1"}};
  Start(std::move(request));
  ASSERT_TRUE(captured_);
  EXPECT_TRUE(captured_->range.empty());
  EXPECT_TRUE(captured_->accept_encoding.empty());
}

TEST_F(FairPlayHlsLoaderTest, AnonymousCorsSendsSameOriginCredentials) {
  MakeLoader(UrlData::CORS_ANONYMOUS);
  Start(Request());
  ASSERT_TRUE(captured_);
  EXPECT_EQ(network::mojom::RequestMode::kCors, captured_->mode);
  EXPECT_EQ(network::mojom::CredentialsMode::kSameOrigin,
            captured_->credentials);
  EXPECT_TRUE(captured_->options.expose_all_response_headers);
  EXPECT_EQ(network::mojom::CorsPreflightPolicy::kPreventPreflight,
            captured_->options.preflight_policy);
}

TEST_F(FairPlayHlsLoaderTest, UseCredentialsCorsIncludesCredentials) {
  MakeLoader(UrlData::CORS_USE_CREDENTIALS, /*is_audio_element=*/true);
  Start(Request());
  ASSERT_TRUE(captured_);
  EXPECT_EQ(network::mojom::RequestMode::kCors, captured_->mode);
  EXPECT_EQ(network::mojom::CredentialsMode::kInclude, captured_->credentials);
  EXPECT_EQ(mojom::RequestContextType::AUDIO, captured_->context);
  EXPECT_EQ(network::mojom::RequestDestination::kAudio,
            captured_->destination);
}

TEST_F(FairPlayHlsLoaderTest, ReportsTheUrlAfterRedirects) {
  MakeLoader();
  Start(Request());
  ASSERT_TRUE(url_client_);
  WebURLResponse redirect{WebURL(KURL(kPlaylistUrl))};
  redirect.SetHttpStatusCode(302);
  EXPECT_TRUE(url_client_->WillFollowRedirect(WebURL(KURL(kCdnUrl)), redirect));
  EXPECT_TRUE(
      url_client_->WillFollowRedirect(WebURL(KURL(kFinalUrl)), redirect));
  Respond(200, "application/vnd.apple.mpegurl", 120);

  ASSERT_TRUE(client_->response_);
  EXPECT_EQ(GURL(kFinalUrl), client_->response_->final_url);
  EXPECT_EQ(200, client_->response_->http_status);
  EXPECT_EQ("application/vnd.apple.mpegurl", client_->response_->mime_type);
  EXPECT_EQ(120, client_->response_->content_length);
  EXPECT_EQ("max-age=2", client_->response_->headers["Cache-Control"]);
  EXPECT_EQ("120", client_->response_->headers["Content-Length"]);
  EXPECT_FALSE(client_->completed_);
}

TEST_F(FairPlayHlsLoaderTest, WithoutRedirectsTheFinalUrlIsTheRequestUrl) {
  MakeLoader();
  Start(Request());
  Respond(206, "video/mp2t", 100);
  ASSERT_TRUE(client_->response_);
  EXPECT_EQ(GURL(kPlaylistUrl), client_->response_->final_url);
  EXPECT_EQ(206, client_->response_->http_status);
}

TEST_F(FairPlayHlsLoaderTest, ADecodedBodyHasAnUnknownLength) {
  MakeLoader();
  Start(Request());
  Respond(200, "application/vnd.apple.mpegurl", 50, "gzip");
  ASSERT_TRUE(client_->response_);
  EXPECT_EQ(-1, client_->response_->content_length);
  for (const auto& [name, value] : client_->response_->headers) {
    EXPECT_NE("content-length", base::ToLowerASCII(name));
    EXPECT_NE("content-encoding", base::ToLowerASCII(name));
  }
  EXPECT_EQ("max-age=2", client_->response_->headers["Cache-Control"]);
}

TEST_F(FairPlayHlsLoaderTest, AnIdentityEncodingKeepsItsLength) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp2t", 50, "identity");
  ASSERT_TRUE(client_->response_);
  EXPECT_EQ(50, client_->response_->content_length);
}

TEST_F(FairPlayHlsLoaderTest, StreamsTheBodyThenCompletes) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp2t", 6);
  Data("abc");
  Data("def");
  EXPECT_EQ("abcdef", client_->Drain());
  EXPECT_FALSE(client_->completed_);

  url_client_->DidFinishLoading();
  task_environment_.RunUntilIdle();
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::OK, client_->net_error_);
  EXPECT_EQ("", client_->Drain());
  EXPECT_TRUE(client_->body_closed_);
  EXPECT_EQ(0u, loader_->load_count_for_testing());
}

TEST_F(FairPlayHlsLoaderTest, PausesLoadingWhileTheBodyPipeIsFull) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp4", -1);

  const std::string big(FairPlayHlsLoader::kBodyPipeCapacity + 1000, 'x');
  EXPECT_CALL(*url_loader_, SetDefersLoading(true));
  Data(big);
  testing::Mock::VerifyAndClearExpectations(url_loader_.get());

  // Completion waits for the bytes still held back.
  url_client_->DidFinishLoading();
  task_environment_.RunUntilIdle();
  EXPECT_FALSE(client_->completed_);

  std::string body;
  for (int i = 0; i < 100 && !client_->body_closed_; ++i) {
    body += client_->Drain();
    task_environment_.RunUntilIdle();
  }
  EXPECT_EQ(big.size(), body.size());
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::OK, client_->net_error_);
}

TEST_F(FairPlayHlsLoaderTest, ResumesLoadingOnceThePipeDrains) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp4", -1);

  const std::string big(FairPlayHlsLoader::kBodyPipeCapacity + 1000, 'y');
  EXPECT_CALL(*url_loader_, SetDefersLoading(true));
  Data(big);
  EXPECT_CALL(*url_loader_, SetDefersLoading(false));
  std::string body = client_->Drain();
  task_environment_.RunUntilIdle();
  body += client_->Drain();
  EXPECT_EQ(big.size(), body.size());
  EXPECT_FALSE(client_->completed_);
}

TEST_F(FairPlayHlsLoaderTest, AFailureBeforeAResponseOnlyCompletes) {
  MakeLoader();
  Start(Request());
  url_client_->DidFail(
      WebURLError(net::ERR_CONNECTION_REFUSED, WebURL(KURL(kPlaylistUrl))));
  task_environment_.RunUntilIdle();
  EXPECT_FALSE(client_->response_);
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_CONNECTION_REFUSED, client_->net_error_);
  EXPECT_EQ(0u, loader_->load_count_for_testing());
}

// A load the old frame ends before any response, after the element moved its
// player to another frame, is made again through that frame's fetch context;
// one that already answered reports the failure.
TEST_F(FairPlayHlsLoaderTest, AFailureBeforeAResponseAfterAMoveLoadsAgain) {
  MakeLoader();
  Start(Request());
  NiceMock<MockResourceFetchContext> moved_fetch_context;
  EXPECT_CALL(moved_fetch_context, CreateUrlLoader(_))
      .WillOnce([this](const WebAssociatedURLLoaderOptions& options) {
        return CreateUrlLoader(options);
      });
  loader_->SetFetchContext(&moved_fetch_context);
  url_client_->DidFail(
      WebURLError(net::ERR_ABORTED, WebURL(KURL(kPlaylistUrl))));
  task_environment_.RunUntilIdle();
  EXPECT_FALSE(client_->completed_);
  EXPECT_EQ(GURL(kPlaylistUrl), captured_->url);
  EXPECT_EQ(1u, loader_->load_count_for_testing());

  Respond(200, "application/vnd.apple.mpegurl", 4);
  url_client_->DidFail(
      WebURLError(net::ERR_CONNECTION_RESET, WebURL(KURL(kPlaylistUrl))));
  task_environment_.RunUntilIdle();
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_CONNECTION_RESET, client_->net_error_);
  loader_.reset();
}

TEST_F(FairPlayHlsLoaderTest, AFailureMidBodyReportsTheError) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp2t", 100);
  Data("partial");
  url_client_->DidFail(
      WebURLError(net::ERR_CONNECTION_RESET, WebURL(KURL(kPlaylistUrl))));
  task_environment_.RunUntilIdle();
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_CONNECTION_RESET, client_->net_error_);
  EXPECT_EQ("partial", client_->Drain());
  EXPECT_TRUE(client_->body_closed_);
}

// Parc: a load the old frame ends mid-body, once the element moved its player
// to another frame, goes on there from the next byte.
class FairPlayHlsLoaderMovedTest : public FairPlayHlsLoaderTest {
 public:
  FairPlayHlsLoaderMovedTest() { etag_ = "\"v1\""; }
  ~FairPlayHlsLoaderMovedTest() override { loader_.reset(); }

 protected:
  // Starts |request| and answers it, gives "partial" of its body, then moves
  // the player and ends the load as the old frame going does. Only the new
  // frame makes a request after that.
  void LoadPartlyThenMove(media::mojom::FairPlayHlsRequestPtr request,
                          int status,
                          int64_t content_length,
                          const char* content_encoding = nullptr,
                          const char* content_range = nullptr) {
    MakeLoader();
    Start(std::move(request));
    Respond(status, "video/mp2t", content_length, content_encoding,
            content_range);
    Data("partial");
    EXPECT_EQ("partial", client_->Drain());
    EXPECT_CALL(fetch_context_, CreateUrlLoader(_)).Times(0);
    ON_CALL(moved_fetch_context_, CreateUrlLoader(_))
        .WillByDefault(
            Invoke(this, &FairPlayHlsLoaderMovedTest::CreateUrlLoader));
    loader_->SetFetchContext(&moved_fetch_context_);
    url_client_->DidFail(
        WebURLError(net::ERR_ABORTED, WebURL(KURL(kPlaylistUrl))));
    task_environment_.RunUntilIdle();
  }

  NiceMock<MockResourceFetchContext> moved_fetch_context_;
};

TEST_F(FairPlayHlsLoaderMovedTest, APartialAnswerGoesOnFromTheNextByte) {
  EXPECT_CALL(moved_fetch_context_, CreateUrlLoader(_));
  LoadPartlyThenMove(Request(), 200, 14);
  EXPECT_FALSE(client_->completed_);
  EXPECT_EQ("bytes=7-13", captured_->range);

  Respond(206, "video/mp2t", 7, nullptr, "bytes 7-13/*");
  Data("-rest!!");
  url_client_->DidFinishLoading();
  task_environment_.RunUntilIdle();
  EXPECT_EQ("-rest!!", client_->Drain());
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::OK, client_->net_error_);
  EXPECT_TRUE(client_->body_closed_);
}

TEST_F(FairPlayHlsLoaderMovedTest, AWholeAnswerIsReadPastWhatWasGiven) {
  LoadPartlyThenMove(Request(), 200, 14);
  Respond(200, "video/mp2t", 14);
  Data("partial-rest!!");
  url_client_->DidFinishLoading();
  task_environment_.RunUntilIdle();
  EXPECT_EQ("-rest!!", client_->Drain());
  EXPECT_EQ(net::OK, client_->net_error_);
  EXPECT_TRUE(client_->body_closed_);
}

TEST_F(FairPlayHlsLoaderMovedTest, ARangeGoesOnWithinItself) {
  media::mojom::FairPlayHlsRequestPtr request = Request();
  request->headers["Range"] = "bytes=100-199";
  LoadPartlyThenMove(std::move(request), 206, 100, nullptr,
                     "bytes 100-199/1000");
  EXPECT_EQ("bytes=107-199", captured_->range);

  // An answer from elsewhere can't go on.
  Respond(206, "video/mp2t", 100, nullptr, "bytes 100-199/1000");
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_FAILED, client_->net_error_);
}

TEST_F(FairPlayHlsLoaderMovedTest, ALoadWithEveryByteCompletes) {
  EXPECT_CALL(moved_fetch_context_, CreateUrlLoader(_)).Times(0);
  LoadPartlyThenMove(Request(), 200, 7);
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::OK, client_->net_error_);
}

TEST_F(FairPlayHlsLoaderMovedTest, AnUnversionedBodyFails) {
  etag_ = nullptr;
  EXPECT_CALL(moved_fetch_context_, CreateUrlLoader(_)).Times(0);
  LoadPartlyThenMove(Request(), 200, 14);
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_ABORTED, client_->net_error_);
}

TEST_F(FairPlayHlsLoaderMovedTest, AnEncodedBodyFails) {
  EXPECT_CALL(moved_fetch_context_, CreateUrlLoader(_)).Times(0);
  LoadPartlyThenMove(Request(), 200, -1, "gzip");
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_ABORTED, client_->net_error_);
}

TEST_F(FairPlayHlsLoaderTest, CancelStopsTheLoad) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp2t", 100);
  EXPECT_CALL(*url_loader_, Cancel());
  load_->Cancel();
  task_environment_.RunUntilIdle();
  EXPECT_EQ(0u, loader_->load_count_for_testing());
  EXPECT_FALSE(client_->completed_);
  EXPECT_TRUE(client_->disconnected_);
  EXPECT_EQ("", client_->Drain());
  EXPECT_TRUE(client_->body_closed_);
}

TEST_F(FairPlayHlsLoaderTest, ClosingTheLoadPipeCancels) {
  MakeLoader();
  Start(Request());
  EXPECT_CALL(*url_loader_, Cancel());
  load_.reset();
  task_environment_.RunUntilIdle();
  EXPECT_EQ(0u, loader_->load_count_for_testing());
  EXPECT_FALSE(client_->completed_);
}

TEST_F(FairPlayHlsLoaderTest, AGoneClientCancels) {
  MakeLoader();
  Start(Request());
  EXPECT_CALL(*url_loader_, Cancel());
  client_->receiver_.reset();
  task_environment_.RunUntilIdle();
  EXPECT_EQ(0u, loader_->load_count_for_testing());
}

TEST_F(FairPlayHlsLoaderTest, ClosingTheBodyPipeEarlyCancels) {
  MakeLoader();
  Start(Request());
  Respond(200, "video/mp4", -1);
  client_->body_.reset();
  task_environment_.RunUntilIdle();
  EXPECT_CALL(*url_loader_, Cancel());
  Data("more");
  EXPECT_EQ(0u, loader_->load_count_for_testing());
  EXPECT_FALSE(client_->completed_);
}

TEST_F(FairPlayHlsLoaderTest, DestroyingTheLoaderCancelsEveryLoad) {
  MakeLoader();
  Start(Request());
  EXPECT_CALL(*url_loader_, Cancel());
  loader_.reset();
  task_environment_.RunUntilIdle();
  EXPECT_TRUE(client_->disconnected_);
  EXPECT_FALSE(client_->completed_);
}

TEST_F(FairPlayHlsLoaderTest, RefusesOtherSchemesAndMethods) {
  MakeLoader();
  EXPECT_CALL(fetch_context_, CreateUrlLoader(_)).Times(0);

  Start(Request("skd://key-id"));
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_DISALLOWED_URL_SCHEME, client_->net_error_);
  EXPECT_FALSE(client_->response_);

  Start(Request("blob:https://media.example/7c1a2e61"));
  EXPECT_EQ(net::ERR_DISALLOWED_URL_SCHEME, client_->net_error_);

  Start(Request(kPlaylistUrl, "POST"));
  EXPECT_TRUE(client_->completed_);
  EXPECT_EQ(net::ERR_METHOD_NOT_SUPPORTED, client_->net_error_);
  EXPECT_EQ(0u, loader_->load_count_for_testing());
}

TEST_F(FairPlayHlsLoaderTest, TheStartLoadCallbackPostsAndDiesWithTheLoader) {
  MakeLoader();
  FairPlayHlsLoader::StartLoadCallback start = loader_->GetStartLoadCallback();

  client_ = std::make_unique<FakeLoadClient>();
  start.Run(Request(), load_.BindNewPipeAndPassReceiver(),
            client_->receiver_.BindNewPipeAndPassRemote());
  EXPECT_EQ(0u, loader_->load_count_for_testing());
  task_environment_.RunUntilIdle();
  EXPECT_EQ(1u, loader_->load_count_for_testing());

  loader_.reset();
  task_environment_.RunUntilIdle();
  load_.reset();
  auto late_client = std::make_unique<FakeLoadClient>();
  late_client->receiver_.set_disconnect_handler(base::BindOnce(
      [](FakeLoadClient* client) { client->disconnected_ = true; },
      base::Unretained(late_client.get())));
  start.Run(Request(), load_.BindNewPipeAndPassReceiver(),
            late_client->receiver_.BindNewPipeAndPassRemote());
  task_environment_.RunUntilIdle();
  EXPECT_TRUE(late_client->disconnected_);
}

}  // namespace

}  // namespace blink

// Installed by the reviewed overlay at
// //third_party/blink/renderer/platform/media/fairplay_hls_loader.cc.
// See fairplay_hls_loader.h.
#include "third_party/blink/renderer/platform/media/fairplay_hls_loader.h"

#include <algorithm>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/containers/flat_map.h"
#include "base/containers/span.h"
#include "base/numerics/safe_conversions.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ref.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/task/bind_post_task.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "mojo/public/cpp/system/simple_watcher.h"
#include "net/base/net_errors.h"
#include "net/http/http_byte_range.h"
#include "net/http/http_request_headers.h"
#include "net/http/http_util.h"
#include "services/network/public/mojom/cors.mojom-shared.h"
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
#include "third_party/blink/public/mojom/fetch/fetch_api_request.mojom-shared.h"
#include "third_party/blink/public/platform/web_http_header_visitor.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/public/platform/web_url_error.h"
#include "third_party/blink/public/platform/web_url_request.h"
#include "third_party/blink/public/platform/web_url_response.h"
#include "third_party/blink/public/web/web_associated_url_loader.h"
#include "third_party/blink/public/web/web_associated_url_loader_client.h"
#include "third_party/blink/public/web/web_associated_url_loader_options.h"
#include "third_party/blink/renderer/platform/media/resource_fetch_context.h"
#include "third_party/blink/renderer/platform/media/resource_multi_buffer_data_provider.h"
#include "third_party/blink/renderer/platform/weborigin/kurl.h"
#include "url/gurl.h"

namespace blink {

namespace {

using Headers = base::flat_map<std::string, std::string>;

// What ResourceMultiBufferDataProvider asks for with a byte range when the
// network layer doesn't add it (kDeferMediaAcceptEncodingInjection off).
constexpr char kIdentityAcceptEncoding[] = "identity;q=1, *;q=0";
constexpr char kContentEncoding[] = "Content-Encoding";
constexpr char kContentLength[] = "Content-Length";

// Copies a response's headers, which Blink keeps combined per name.
class HeaderCollector final : public WebHTTPHeaderVisitor {
 public:
  explicit HeaderCollector(Headers& headers) : headers_(headers) {}
  ~HeaderCollector() override = default;

  void VisitHeader(const WebString& name, const WebString& value) override {
    headers_->insert_or_assign(name.Utf8(), value.Utf8());
  }

 private:
  const raw_ref<Headers> headers_;
};

// Parc: the first byte and, if known, the last of a 206's Content-Range
// ("bytes first-last/length", the length may be "*").
std::optional<std::pair<int64_t, int64_t>> ContentRangeBytes(
    const WebURLResponse& response) {
  std::string value =
      response.HttpHeaderField(WebString::FromAscii("Content-Range")).Utf8();
  std::string_view spec = base::TrimWhitespaceASCII(value, base::TRIM_ALL);
  if (!base::StartsWith(spec, "bytes", base::CompareCase::INSENSITIVE_ASCII)) {
    return std::nullopt;
  }
  spec = base::TrimWhitespaceASCII(spec.substr(5), base::TRIM_LEADING);
  const size_t dash = spec.find('-');
  const size_t slash = spec.find('/');
  int64_t first = 0;
  int64_t last = 0;
  int64_t length = 0;
  if (dash == std::string_view::npos || slash == std::string_view::npos ||
      slash < dash || !base::StringToInt64(spec.substr(0, dash), &first) ||
      !base::StringToInt64(spec.substr(dash + 1, slash - dash - 1), &last) ||
      first < 0 || last < first ||
      last == std::numeric_limits<int64_t>::max() ||
      (spec.substr(slash + 1) != "*" &&
       !base::StringToInt64(spec.substr(slash + 1), &length))) {
    return std::nullopt;
  }
  return std::make_pair(first, last);
}

void EraseHeader(Headers& headers, const char* name) {
  for (auto it = headers.begin(); it != headers.end();) {
    if (base::EqualsCaseInsensitiveASCII(it->first, name)) {
      it = headers.erase(it);
    } else {
      ++it;
    }
  }
}

}  // namespace

// One load: its WebAssociatedURLLoader, its FairPlayHlsLoad receiver, the GPU
// side's FairPlayHlsLoadClient and the body pipe. It stops by asking the
// owner to destroy it; every path that does returns at once.
class FairPlayHlsLoader::Load final : public WebAssociatedURLLoaderClient,
                                      public media::mojom::FairPlayHlsLoad {
 public:
  Load(FairPlayHlsLoader* owner,
       mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
       mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> client)
      : owner_(owner),
        receiver_(this, std::move(load)),
        client_(std::move(client)),
        watcher_(FROM_HERE,
                 mojo::SimpleWatcher::ArmingPolicy::MANUAL,
                 owner->task_runner_) {
    // Either side going away cancels the load. Unretained: |this| owns both.
    receiver_.set_disconnect_handler(
        base::BindOnce(&Load::Stop, base::Unretained(this)));
    client_.set_disconnect_handler(
        base::BindOnce(&Load::Stop, base::Unretained(this)));
  }

  Load(const Load&) = delete;
  Load& operator=(const Load&) = delete;

  ~Load() override {
    // An unfinished load is cancelled; WebAssociatedURLLoader::Cancel()
    // calls no client method.
    if (loader_) {
      loader_->Cancel();
    }
  }

  // Makes the request, or answers OnComplete with why it can't be made.
  void Start(const media::mojom::FairPlayHlsRequest& request,
             ResourceFetchContext& fetch_context,
             UrlData::CorsMode cors_mode,
             bool is_audio_element) {
    const GURL& url = request.url;
    if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS()) {
      Complete(net::ERR_DISALLOWED_URL_SCHEME);
      return;
    }
    if (request.method != net::HttpRequestHeaders::kGetMethod &&
        request.method != net::HttpRequestHeaders::kHeadMethod) {
      Complete(net::ERR_METHOD_NOT_SUPPORTED);
      return;
    }
    final_url_ = url;
    request_ = request.Clone();
    fetch_context_ = &fetch_context;
    MakeRequest(request, fetch_context, cors_mode, is_audio_element);
  }

  // media::mojom::FairPlayHlsLoad:
  void Cancel() override { Stop(); }

  // WebAssociatedURLLoaderClient:
  bool WillFollowRedirect(const WebURL& new_url,
                          const WebURLResponse& redirect_response) override {
    final_url_ = GURL(KURL(new_url));
    return true;
  }

  void DidReceiveResponse(const WebURLResponse& response) override {
    if (going_on_) {
      going_on_ = false;
      if (!ParcResponseGoesOn(response)) {
        Complete(net::ERR_FAILED);
      }
      return;
    }
    auto head = media::mojom::FairPlayHlsResponse::New();
    head->http_status = response.HttpStatusCode();
    head->mime_type = response.MimeType().Utf8();
    head->final_url = final_url_;
    HeaderCollector collector(head->headers);
    response.VisitHttpHeaderFields(&collector);

    // The network stack hands Blink decoded bodies, so an encoded response's
    // Content-Length is not the body's length.
    const std::string encoding =
        response.HttpHeaderField(WebString::FromAscii(kContentEncoding))
            .Utf8();
    if (!encoding.empty() &&
        !base::EqualsCaseInsensitiveASCII(encoding, "identity")) {
      head->content_length = -1;
      EraseHeader(head->headers, kContentEncoding);
      EraseHeader(head->headers, kContentLength);
    } else {
      head->content_length = std::max<int64_t>(
          response.ExpectedContentLength(), -1);
      // Parc: where the body starts and ends in the resource, for going on
      // from its next byte. An encoded body's bytes aren't the server's,
      // which a range counts.
      if (request_->method == net::HttpRequestHeaders::kGetMethod) {
        ParcRememberBody(response, head->content_length);
      }
    }

    mojo::ScopedDataPipeConsumerHandle body;
    if (mojo::CreateDataPipe(kBodyPipeCapacity, producer_, body) !=
        MOJO_RESULT_OK) {
      Complete(net::ERR_INSUFFICIENT_RESOURCES);
      return;
    }
    // Unretained: |this| owns the watcher.
    watcher_.Watch(producer_.get(),
                   MOJO_HANDLE_SIGNAL_WRITABLE | MOJO_HANDLE_SIGNAL_PEER_CLOSED,
                   MOJO_WATCH_CONDITION_SATISFIED,
                   base::BindRepeating(&Load::OnBodyPipeReady,
                                       base::Unretained(this)));
    client_->OnResponse(std::move(head), std::move(body));
  }

  void DidReceiveData(base::span<const char> data) override {
    if (!producer_) {
      return;
    }
    base::span<const uint8_t> bytes = base::as_bytes(data);
    const size_t repeated = std::min<size_t>(
        bytes.size(), base::checked_cast<size_t>(bytes_to_skip_));
    bytes = bytes.subspan(repeated);
    bytes_to_skip_ -= repeated;
    if (bytes.empty()) {
      return;
    }
    body_bytes_ += bytes.size();
    if (pending_offset_ == pending_.size()) {
      size_t written = 0;
      if (!WriteToPipe(bytes, written)) {
        Stop();
        return;
      }
      bytes = bytes.subspan(written);
    }
    if (bytes.empty()) {
      return;
    }
    // The pipe is full: keep the rest and pause loading until it drains.
    pending_.insert(pending_.end(), bytes.begin(), bytes.end());
    if (!deferred_) {
      deferred_ = true;
      loader_->SetDefersLoading(true);
    }
    watcher_.ArmOrNotify();
  }

  void DidFinishLoading() override {
    loader_.reset();
    // Parc: an answer that ended before the bytes it repeats.
    if (bytes_to_skip_ > 0) {
      Complete(net::ERR_FAILED);
      return;
    }
    finished_ = true;
    if (pending_offset_ == pending_.size()) {
      Complete(net::OK);
    }
    // Otherwise OnBodyPipeReady completes once the rest is in the pipe.
  }

  void DidFail(const WebURLError& error) override {
    loader_.reset();
    // A load the old frame ended before any response, once the element moved
    // its player to another frame (SetFetchContext), is made again there.
    if (!producer_ && owner_->fetch_context_ != fetch_context_) {
      // Start() replaces `request_`.
      media::mojom::FairPlayHlsRequestPtr request = std::move(request_);
      Start(*request, *owner_->fetch_context_, owner_->cors_mode_,
            owner_->is_audio_element_);
      return;
    }
    // Parc: so is one it ended mid-body, from its next byte, so the player
    // doesn't see it fail.
    if (producer_ && owner_->fetch_context_ != fetch_context_ &&
        ParcGoOnInNewFrame()) {
      return;
    }
    Complete(error.reason() < 0 ? error.reason() : net::ERR_FAILED);
  }

 private:
  void ParcRememberBody(const WebURLResponse& response,
                        int64_t content_length) {
    if (response.HttpStatusCode() == 200) {
      body_start_ = 0;
      body_end_ = content_length >= 0 ? content_length : -1;
    } else if (response.HttpStatusCode() == 206) {
      std::optional<std::pair<int64_t, int64_t>> range =
          ContentRangeBytes(response);
      if (!range) {
        return;
      }
      body_start_ = range->first;
      body_end_ = range->second + 1;
    } else {
      return;
    }
    whole_body_ = response.HttpStatusCode() == 200;
    etag_ = response.HttpHeaderField(WebString::FromAscii("ETag")).Utf8();
    last_modified_ =
        response.HttpHeaderField(WebString::FromAscii("Last-Modified")).Utf8();
    // Only a resource that says which version it is can be read on from
    // another response: a live playlist may have changed since.
    can_go_on_ = (!etag_.empty() && !base::StartsWith(etag_, "W/")) ||
                 !last_modified_.empty();
  }

  // Asks the new frame for the body from the byte after the last one given,
  // or finishes a load that has them all.
  bool ParcGoOnInNewFrame() {
    if (!can_go_on_) {
      return false;
    }
    const int64_t next = body_start_ + body_bytes_;
    if (body_end_ >= 0 && next >= body_end_) {
      finished_ = true;
      if (pending_offset_ == pending_.size()) {
        Complete(net::OK);
      }
      return true;
    }
    media::mojom::FairPlayHlsRequestPtr request = request_.Clone();
    EraseHeader(request->headers, net::HttpRequestHeaders::kRange);
    request->headers[net::HttpRequestHeaders::kRange] =
        (body_end_ >= 0 ? net::HttpByteRange::Bounded(next, body_end_ - 1)
                        : net::HttpByteRange::RightUnbounded(next))
            .GetHeaderValue();
    fetch_context_ = owner_->fetch_context_;
    going_on_ = true;
    MakeRequest(*request, *fetch_context_, owner_->cors_mode_,
                owner_->is_audio_element_);
    // As DidReceiveData() pauses for a full pipe.
    deferred_ = pending_offset_ < pending_.size();
    if (deferred_) {
      loader_->SetDefersLoading(true);
    }
    return true;
  }

  // The same resource's next bytes, unencoded: a 206 from the next byte, or a
  // 200 where the body was the whole resource, read past what was given.
  bool ParcResponseGoesOn(const WebURLResponse& response) {
    const std::string encoding =
        response.HttpHeaderField(WebString::FromAscii(kContentEncoding))
            .Utf8();
    if (!encoding.empty() &&
        !base::EqualsCaseInsensitiveASCII(encoding, "identity")) {
      return false;
    }
    if (response.HttpHeaderField(WebString::FromAscii("ETag")).Utf8() !=
            etag_ ||
        response.HttpHeaderField(WebString::FromAscii("Last-Modified"))
                .Utf8() != last_modified_) {
      return false;
    }
    const int64_t next = body_start_ + body_bytes_;
    if (response.HttpStatusCode() == 206) {
      std::optional<std::pair<int64_t, int64_t>> range =
          ContentRangeBytes(response);
      return range && range->first == next &&
             (body_end_ < 0 || range->second + 1 == body_end_);
    }
    if (response.HttpStatusCode() == 200 && whole_body_) {
      const int64_t length = response.ExpectedContentLength();
      if (body_end_ >= 0 && length >= 0 && length != body_end_) {
        return false;
      }
      bytes_to_skip_ = next;
      return true;
    }
    return false;
  }

  // The request for |request| through |fetch_context|.
  void MakeRequest(const media::mojom::FairPlayHlsRequest& request,
                   ResourceFetchContext& fetch_context,
                   UrlData::CorsMode cors_mode,
                   bool is_audio_element) {
    WebURLRequest web_request{WebURL(KURL(request.url))};
    web_request.SetHttpMethod(WebString::FromAscii(request.method));
    web_request.SetRequestContext(is_audio_element
                                      ? mojom::RequestContextType::AUDIO
                                      : mojom::RequestContextType::VIDEO);
    web_request.SetRequestDestination(
        is_audio_element ? network::mojom::RequestDestination::kAudio
                         : network::mojom::RequestDestination::kVideo);
    // AVFoundation's other headers stay behind (see the header comment).
    for (const auto& [name, value] : request.headers) {
      if (!base::EqualsCaseInsensitiveASCII(name,
                                            net::HttpRequestHeaders::kRange) ||
          !base::IsStringASCII(value) ||
          !net::HttpUtil::IsValidHeaderValue(value)) {
        continue;
      }
      web_request.SetHttpHeaderField(
          WebString::FromAscii(net::HttpRequestHeaders::kRange),
          WebString::FromAscii(value));
      // As ResourceMultiBufferDataProvider: by default the network layer
      // adds the identity encoding after any service worker has run.
      if (!base::FeatureList::IsEnabled(kDeferMediaAcceptEncodingInjection)) {
        web_request.SetHttpHeaderField(
            WebString::FromAscii(net::HttpRequestHeaders::kAcceptEncoding),
            WebString::FromAscii(kIdentityAcceptEncoding));
      }
    }

    // The element's CORS mode, exactly as ResourceMultiBufferDataProvider
    // applies it.
    WebAssociatedURLLoaderOptions options;
    if (cors_mode != UrlData::CORS_UNSPECIFIED) {
      options.expose_all_response_headers = true;
      // The author header set is empty: no preflight.
      options.preflight_policy =
          network::mojom::CorsPreflightPolicy::kPreventPreflight;
      web_request.SetMode(network::mojom::RequestMode::kCors);
      if (cors_mode != UrlData::CORS_USE_CREDENTIALS) {
        web_request.SetCredentialsMode(
            network::mojom::CredentialsMode::kSameOrigin);
      }
    }

    loader_ = fetch_context.CreateUrlLoader(options);
    loader_->LoadAsynchronously(web_request, this);
  }

  // Writes as much of |bytes| as the pipe takes. False when the GPU side
  // closed the body pipe.
  bool WriteToPipe(base::span<const uint8_t> bytes, size_t& written) {
    written = 0;
    while (written < bytes.size()) {
      size_t chunk = 0;
      MojoResult result = producer_->WriteData(
          bytes.subspan(written), MOJO_WRITE_DATA_FLAG_NONE, chunk);
      if (result == MOJO_RESULT_SHOULD_WAIT) {
        return true;
      }
      if (result != MOJO_RESULT_OK) {
        return false;
      }
      written += chunk;
    }
    return true;
  }

  void OnBodyPipeReady(MojoResult result,
                       const mojo::HandleSignalsState& state) {
    // The GPU side closed the body before its end: it gave the load up.
    if (result != MOJO_RESULT_OK || state.peer_closed()) {
      Stop();
      return;
    }
    size_t written = 0;
    if (!WriteToPipe(base::span(pending_).subspan(pending_offset_),
                     written)) {
      Stop();
      return;
    }
    pending_offset_ += written;
    if (pending_offset_ < pending_.size()) {
      watcher_.ArmOrNotify();
      return;
    }
    pending_.clear();
    pending_offset_ = 0;
    if (finished_) {
      Complete(net::OK);
      return;
    }
    if (deferred_) {
      deferred_ = false;
      loader_->SetDefersLoading(false);
    }
  }

  // Closes the body after its last byte, reports |net_error| and stops.
  void Complete(int net_error) {
    watcher_.Cancel();
    producer_.reset();
    client_->OnComplete(net_error);
    Stop();
  }

  // Destroys |this|.
  void Stop() { owner_->RemoveLoad(this); }

  const raw_ptr<FairPlayHlsLoader> owner_;
  mojo::Receiver<media::mojom::FairPlayHlsLoad> receiver_;
  mojo::Remote<media::mojom::FairPlayHlsLoadClient> client_;
  std::unique_ptr<WebAssociatedURLLoader> loader_;
  GURL final_url_;
  // What Start() made the request from.
  media::mojom::FairPlayHlsRequestPtr request_;
  raw_ptr<ResourceFetchContext> fetch_context_ = nullptr;

  mojo::ScopedDataPipeProducerHandle producer_;
  mojo::SimpleWatcher watcher_;
  // Body bytes the pipe had no room for, from |pending_offset_| on.
  std::vector<uint8_t> pending_;
  size_t pending_offset_ = 0;
  bool deferred_ = false;
  bool finished_ = false;
  // Parc: the body bytes given; where the body starts and ends (-1: unknown)
  // in the resource and whether it is all of it; its validators; whether it
  // can be asked for from the next byte (not an encoded one); whether that
  // request is out; and the bytes its 200 response repeats.
  int64_t body_bytes_ = 0;
  int64_t body_start_ = 0;
  int64_t body_end_ = -1;
  bool whole_body_ = false;
  std::string etag_;
  std::string last_modified_;
  bool can_go_on_ = false;
  bool going_on_ = false;
  int64_t bytes_to_skip_ = 0;
};

FairPlayHlsLoader::FairPlayHlsLoader(ResourceFetchContext* fetch_context,
                                     UrlData::CorsMode cors_mode,
                                     bool is_audio_element)
    : fetch_context_(fetch_context),
      cors_mode_(cors_mode),
      is_audio_element_(is_audio_element),
      task_runner_(base::SequencedTaskRunner::GetCurrentDefault()) {
  DCHECK(fetch_context_);
}

FairPlayHlsLoader::~FairPlayHlsLoader() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Cancels every load. Moved out first so nothing can reach |loads_| while
  // they go.
  std::vector<std::unique_ptr<Load>> loads = std::move(loads_);
  loads_.clear();
  loads.clear();
}

void FairPlayHlsLoader::StartLoad(
    media::mojom::FairPlayHlsRequestPtr request,
    mojo::PendingReceiver<media::mojom::FairPlayHlsLoad> load,
    mojo::PendingRemote<media::mojom::FairPlayHlsLoadClient> client) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!request || !load.is_valid() || !client.is_valid()) {
    return;
  }
  auto owned = std::make_unique<Load>(this, std::move(load), std::move(client));
  Load* raw = owned.get();
  loads_.push_back(std::move(owned));
  // May destroy |raw| (a request that can't be made answers at once).
  raw->Start(*request, *fetch_context_, cors_mode_, is_audio_element_);
}

FairPlayHlsLoader::StartLoadCallback FairPlayHlsLoader::GetStartLoadCallback() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  return base::BindPostTask(
      task_runner_, base::BindRepeating(&FairPlayHlsLoader::StartLoad,
                                        weak_factory_.GetWeakPtr()));
}

void FairPlayHlsLoader::SetFetchContext(ResourceFetchContext* fetch_context) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  DCHECK(fetch_context);
  fetch_context_ = fetch_context;
}

void FairPlayHlsLoader::RemoveLoad(Load* load) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto it = std::find_if(loads_.begin(), loads_.end(),
                         [load](const std::unique_ptr<Load>& candidate) {
                           return candidate.get() == load;
                         });
  if (it == loads_.end()) {
    return;
  }
  // Out of the list before it is destroyed.
  std::unique_ptr<Load> doomed = std::move(*it);
  loads_.erase(it);
}

}  // namespace blink

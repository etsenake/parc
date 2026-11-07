// Proof for the core's native HLS player (Engine/ParcNative/fairplay/
// fairplay_hls_player.mm), run by scripts/test-fairplay-hls.sh.
//
// The player runs on a serial dispatch queue with no run loop, like Chromium's
// GPU media thread. Its loader serves the streams under a made-up host,
// parc-hls.invalid, that only the loader knows how to reach: anything
// AVFoundation tried to fetch by itself would fail, so playing proves that
// every load went through HlsLoader.
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_hls_player.h"
#include "fairplay_hls_player_internal.h"

namespace fp = parc::fairplay;

namespace {

int g_failures = 0;

void Check(bool ok, const std::string& what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what.c_str());
  std::fflush(stdout);
  if (!ok) {
    g_failures++;
  }
}

dispatch_queue_t Owner() {
  static dispatch_queue_t queue = dispatch_queue_create("parc.hls-harness.owner", DISPATCH_QUEUE_SERIAL);
  return queue;
}

fp::PostTask OwnerPoster() {
  return [](std::function<void()> task) {
    dispatch_async(Owner(), ^{
      task();
    });
  };
}

// Runs |task| on the owner queue and waits for it.
void OnOwner(const std::function<void()>& task) {
  dispatch_sync(Owner(), ^{
    task();
  });
}

// Spins the main run loop (AVFoundation posts some KVO there) until |done|
// or |seconds| pass.
bool WaitFor(const std::function<bool()>& done, double seconds) {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0) {
    __block bool finished = false;
    dispatch_sync(Owner(), ^{
      finished = done();
    });
    if (finished) {
      return true;
    }
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  return false;
}

constexpr const char* kFakeHost = "parc-hls.invalid";

}  // namespace

// NSURLSession stand-in for Chromium's loader: maps parc-hls.invalid/<host>/…
// to https://<host>/… and back.
@interface HarnessFetcher : NSObject <NSURLSessionDataDelegate>
@property(atomic) int requests;
@property(atomic) int skdRequests;
@property(atomic) int liveLoads;
- (NSURLSessionDataTask*)start:(NSURLRequest*)request
                    onResponse:(void (^)(NSHTTPURLResponse*))onResponse
                        onData:(void (^)(NSData*))onData
                    onComplete:(void (^)(NSError*))onComplete;
@end

@implementation HarnessFetcher {
  NSURLSession* _session;
  NSMutableDictionary<NSNumber*, NSArray*>* _handlers;
}

- (instancetype)init {
  if ((self = [super init])) {
    _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                             delegate:self
                                        delegateQueue:nil];
    _handlers = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSURLSessionDataTask*)start:(NSURLRequest*)request
                    onResponse:(void (^)(NSHTTPURLResponse*))onResponse
                        onData:(void (^)(NSData*))onData
                    onComplete:(void (^)(NSError*))onComplete {
  NSURLSessionDataTask* task = [_session dataTaskWithRequest:request];
  @synchronized(self) {
    _handlers[@(task.taskIdentifier)] = @[ onResponse, onData, onComplete ];
  }
  [task resume];
  return task;
}

- (NSArray*)handlers:(NSURLSessionTask*)task {
  @synchronized(self) {
    return _handlers[@(task.taskIdentifier)];
  }
}

- (void)URLSession:(NSURLSession*)session
              dataTask:(NSURLSessionDataTask*)dataTask
    didReceiveResponse:(NSURLResponse*)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
  void (^onResponse)(NSHTTPURLResponse*) = [self handlers:dataTask][0];
  onResponse((NSHTTPURLResponse*)response);
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
  void (^onData)(NSData*) = [self handlers:dataTask][1];
  onData(data);
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
  NSArray* handlers = [self handlers:task];
  void (^onComplete)(NSError*) = handlers[2];
  onComplete(error);
  @synchronized(self) {
    [_handlers removeObjectForKey:@(task.taskIdentifier)];
  }
}

@end

namespace {

std::string ToReal(const std::string& url) {
  // https://parc-hls.invalid/<host>/<path> -> https://<host>/<path>
  std::string prefix = std::string("https://") + kFakeHost + "/";
  if (url.rfind(prefix, 0) != 0) {
    return "";
  }
  return "https://" + url.substr(prefix.size());
}

std::string ToFake(const std::string& url) {
  std::string prefix = "https://";
  if (url.rfind(prefix, 0) != 0) {
    return url;
  }
  return prefix + kFakeHost + "/" + url.substr(prefix.size());
}

class Loader : public fp::HlsLoader {
 public:
  Loader() : fetcher_([HarnessFetcher new]) {}

  class Load : public fp::HlsLoad {
   public:
    explicit Load(std::shared_ptr<std::atomic<bool>> alive, NSURLSessionDataTask* task)
        : alive_(std::move(alive)), task_(task) {}
    ~Load() override {
      *alive_ = false;
      [task_ cancel];
      live_loads_--;
    }
    static std::atomic<int> live_loads_;

   private:
    std::shared_ptr<std::atomic<bool>> alive_;
    NSURLSessionDataTask* task_;
  };

  std::unique_ptr<fp::HlsLoad> StartLoad(const fp::HlsLoadRequest& request,
                                         fp::HlsLoadClient* client) override {
    starts_++;
    urls_.push_back(request.url);
    std::string real = ToReal(request.url);
    auto alive = std::make_shared<std::atomic<bool>>(true);
    if (real.empty() && request.url.rfind("https://", 0) == 0) {
      // An absolute URL inside a playlist the loader served: still a load
      // through HlsLoader, fetched as is.
      real = request.url;
      absolute_++;
    }
    if (real.empty()) {
      // Never http(s): AVFoundation must not hand the loader anything else.
      foreign_++;
      dispatch_async(Owner(), ^{
        if (*alive) {
          client->OnComplete(-302);
        }
      });
      Load::live_loads_++;
      return std::make_unique<Load>(alive, nil);
    }
    NSMutableURLRequest* ns_request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@(real.c_str())]];
    ns_request.HTTPMethod = @(request.method.c_str());
    for (const auto& [name, value] : request.headers) {
      if (name == "Range" || name == "range") {
        ranged_++;
      }
      [ns_request setValue:@(value.c_str()) forHTTPHeaderField:@(name.c_str())];
    }
    NSURLSessionDataTask* task = [fetcher_ start:ns_request
        onResponse:^(NSHTTPURLResponse* response) {
          fp::HlsLoadResponse r;
          r.http_status = static_cast<int>(response.statusCode);
          r.mime_type = response.MIMEType.UTF8String ?: "";
          r.content_length = response.expectedContentLength;
          r.final_url = ToFake(response.URL.absoluteString.UTF8String ?: "");
          dispatch_async(Owner(), ^{
            if (*alive) {
              client->OnResponse(r);
            }
          });
        }
        onData:^(NSData* data) {
          dispatch_async(Owner(), ^{
            if (*alive) {
              client->OnData(static_cast<const uint8_t*>(data.bytes), data.length);
            }
          });
        }
        onComplete:^(NSError* error) {
          int net_error = error ? (error.code == NSURLErrorCancelled ? -3 : -2) : 0;
          dispatch_async(Owner(), ^{
            if (*alive) {
              client->OnComplete(net_error);
            }
          });
        }];
    Load::live_loads_++;
    return std::make_unique<Load>(alive, task);
  }

  int starts_ = 0;
  int foreign_ = 0;
  int absolute_ = 0;
  int ranged_ = 0;
  std::vector<std::string> urls_;

 private:
  HarnessFetcher* fetcher_;
};

std::atomic<int> Loader::Load::live_loads_{0};

struct Client : fp::HlsPlayerClient {
  void OnMetadata(const fp::HlsMetadata& m) override {
    metadata = m;
    metadata_count++;
  }
  void OnBufferingStateChange(bool have_enough) override {
    buffering.push_back(have_enough);
  }
  void OnLoadedRangesChange(const std::vector<fp::HlsTimeRange>& r) override { loaded = r; }
  void OnSeekableRangesChange(const std::vector<fp::HlsTimeRange>& r) override {
    seekable = r;
    seekable_changes++;
  }
  void OnDurationChange(double seconds) override { duration_changes.push_back(seconds); }
  void OnNaturalSizeChange(int32_t w, int32_t h) override {
    width = w;
    height = h;
  }
  void OnEnded() override { ended++; }
  void OnError(fp::HlsError e, const std::string& message) override {
    error = static_cast<int>(e);
    error_message = message;
    errors++;
  }
  void OnKeyRequest(const std::string& uri) override { key_uris.push_back(uri); }

  std::optional<fp::HlsMetadata> metadata;
  int metadata_count = 0;
  std::vector<bool> buffering;
  std::vector<fp::HlsTimeRange> loaded, seekable;
  int seekable_changes = 0;
  std::vector<double> duration_changes;
  int32_t width = 0, height = 0;
  int ended = 0;
  int error = -1;
  int errors = 0;
  std::string error_message;
  std::vector<std::string> key_uris;
};

struct Rig {
  Rig() {
    OnOwner([this] { player = std::make_unique<fp::FairPlayHlsPlayer>(&client, &loader, OwnerPoster()); });
  }
  ~Rig() {
    OnOwner([this] { player.reset(); });
  }
  fp::Result Load(const std::string& url) {
    fp::Result result;
    OnOwner([&] {
      result = player->Load(url, "");
      player->SetMuted(true);
    });
    return result;
  }
  double Time() { return player->CurrentTime(); }

  Client client;
  Loader loader;
  std::unique_ptr<fp::FairPlayHlsPlayer> player;
};

std::string Fake(const char* real_without_scheme) {
  return std::string("https://") + kFakeHost + "/" + real_without_scheme;
}

void VodTs() {
  std::printf("-- clear TS VOD (Apple bipbop)\n");
  Rig rig;
  Check(rig.Load(Fake("devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")).ok(),
        "Load accepts the URL");
  int early_seek = -1;
  OnOwner([&] { rig.player->Seek(10, [&](bool finished) { early_seek = finished; }); });
  WaitFor([&] { return early_seek != -1; }, 5);
  Check(early_seek == 0, "a seek before metadata reports unfinished instead of throwing");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata.has_value(), "metadata arrives (readyToPlay)");
  if (!rig.client.metadata) {
    return;
  }
  const fp::HlsMetadata& m = *rig.client.metadata;
  Check(m.has_video && m.natural_width > 0 && m.natural_height > 0, "video with a natural size");
  Check(m.has_audio, "audio");
  Check(!m.is_live && std::fabs(m.duration - 600) < 2, "finite duration about 600 s");
  Check(!m.seekable.empty() && m.seekable[0].end > 500, "seekable covers the stream");
  OnOwner([&] { rig.player->SetRate(1); });
  bool playing = WaitFor([&] { return rig.Time() > 3; }, 20);
  Check(playing, "time advances past 3 s");
  Check(!rig.client.buffering.empty() && rig.client.buffering.back(), "buffering reports enough");
  Check(!rig.client.loaded.empty(), "loaded ranges reported");
  OnOwner([&] { rig.player->SetRate(0); });
  WaitFor([] { return false; }, 0.5);
  double paused_at = rig.Time();
  WaitFor([] { return false; }, 1.5);
  Check(std::fabs(rig.Time() - paused_at) < 0.05, "pause holds the clock");
  int seek_result = -1;
  OnOwner([&] { rig.player->Seek(300, [&](bool finished) { seek_result = finished; }); });
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(seek_result == 1 && std::fabs(rig.Time() - 300) < 0.1, "exact seek to 300 s finishes there");
  OnOwner([&] { rig.player->SetRate(1); });
  Check(WaitFor([&] { return rig.Time() > 302; }, 20), "plays on after the seek");
  // Ended: seek to two seconds before the end and play through.
  seek_result = -1;
  OnOwner([&] { rig.player->Seek(m.duration - 2, [&](bool finished) { seek_result = finished; }); });
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(WaitFor([&] { return rig.client.ended > 0; }, 20), "ended fires at the end");
  Check(rig.loader.foreign_ == 0 && rig.loader.absolute_ == 0, "every load named the loader's host");
  Check(rig.loader.starts_ > 10, "playlists and segments went through HlsLoader (" +
                                     std::to_string(rig.loader.starts_) + " loads)");
  fp::FairPlayHlsPlayer::Status status = rig.player->GetStatus();
  Check(status.bytes_received > 1000000 && status.key_requests == 0, "bytes delivered, no key requests");
  Check(rig.client.errors == 0, "no error");
}

void VodFmp4() {
  std::printf("-- clear fMP4 VOD with alternate audio and subtitles (Axinom CMAF)\n");
  Rig rig;
  Check(rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/manifest.m3u8")).ok(), "Load");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata && rig.client.metadata->has_video, "metadata with video");
  OnOwner([&] { rig.player->SetRate(1); });
  Check(WaitFor([&] { return rig.Time() > 2; }, 20), "time advances past 2 s");
  Check(rig.loader.foreign_ == 0 && rig.client.errors == 0, "only the loader's host, no error");
  AVPlayerLayer* layer = nil;
  OnOwner([&] { layer = fp::HlsPlayerLayer(rig.player->impl()); });
  Check(layer && layer.player == fp::HlsPlayerAVPlayer(rig.player->impl()), "player layer shows the player");
}

void Live() {
  std::printf("-- live with a DVR window (Unified Streaming demo)\n");
  Rig rig;
  Check(rig.Load(Fake("demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8")).ok(), "Load");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 25);
  Check(ready && rig.client.metadata, "metadata");
  if (!rig.client.metadata) {
    for (const std::string& url : rig.loader.urls_) {
      std::printf("   load %s\n", url.c_str());
    }
    return;
  }
  Check(rig.client.metadata->is_live && std::isinf(rig.client.metadata->duration), "live: infinite duration");
  OnOwner([&] { rig.player->SetRate(1); });
  double start = 0;
  WaitFor([&] { return rig.Time() > 0; }, 15);
  start = rig.Time();
  Check(WaitFor([&] { return rig.Time() > start + 2; }, 20), "live time advances");
  Check(!rig.client.seekable.empty() || !rig.client.metadata->seekable.empty(), "seekable window reported");
  std::printf("   seekable %s, start date %s\n",
              rig.client.seekable.empty() ? "none"
                                          : (std::to_string(rig.client.seekable.back().start) + "-" +
                                             std::to_string(rig.client.seekable.back().end)).c_str(),
              rig.client.metadata->start_date_ms ? std::to_string(*rig.client.metadata->start_date_ms).c_str() : "none");
  Check(rig.loader.foreign_ == 0 && rig.client.errors == 0, "only the loader's host, no error");
}

void BadUrl() {
  std::printf("-- refused URLs\n");
  Rig rig;
  Check(!rig.Load("file:///etc/hosts").ok(), "a file URL is refused");
  Rig rig2;
  Check(!rig2.Load(std::string("https://") + kFakeHost + "/\xff\xfe.m3u8").ok(), "a URL that isn't UTF-8 is refused");
}

void Missing() {
  std::printf("-- missing playlist\n");
  Rig rig;
  rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/does-not-exist.m3u8"));
  WaitFor([&] { return rig.client.errors > 0 || rig.client.metadata_count > 0; }, 20);
  Check(rig.client.errors == 1 && rig.client.metadata_count == 0, "a 404 playlist fails before metadata");
  Check(rig.client.error == static_cast<int>(fp::HlsError::kNetwork) ||
            rig.client.error == static_cast<int>(fp::HlsError::kNotSupported),
        "reported as a network or unsupported-source error (" + rig.client.error_message.substr(0, 80) + ")");
}

void Skd() {
  std::printf("-- FairPlay HLS: skd key request reaches the client\n");
  Rig rig;
  rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/manifest.m3u8"));
  OnOwner([&] { rig.player->SetRate(1); });
  bool asked = WaitFor([&] { return !rig.client.key_uris.empty() || rig.client.errors; }, 20);
  Check(asked && !rig.client.key_uris.empty() && rig.client.key_uris[0].rfind("skd://", 0) == 0,
        "OnKeyRequest with the skd URI (" + (rig.client.key_uris.empty() ? std::string("none") : rig.client.key_uris[0]) + ")");
  bool skd_loaded = false;
  for (const std::string& url : rig.loader.urls_) {
    skd_loaded |= url.rfind("skd:", 0) == 0;
  }
  Check(!skd_loaded, "skd never went to the loader");
  WaitFor([] { return false; }, 2);
  Check(rig.client.key_uris.size() == 1, "one notification per pending URI");
  Check(rig.Time() < 0.5, "no key, no playback");
  OnOwner([&] { rig.player->FailKeyRequests(rig.client.key_uris[0], "no license in this harness"); });
  bool failed = WaitFor([&] { return rig.client.errors > 0 || rig.client.key_uris.size() > 1; }, 20);
  std::printf("   after FailKeyRequests: errors=%d key requests=%zu (%s)\n", rig.client.errors,
              rig.client.key_uris.size(), rig.client.error_message.substr(0, 120).c_str());
  Check(failed && rig.client.key_uris.size() > 1,
        "a failed key request is asked for again (AVFoundation retries; the element keeps waiting, as in Safari)");
}

void Teardown() {
  std::printf("-- teardown with loads in flight\n");
  {
    Rig rig;
    rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/manifest.m3u8"));
    OnOwner([&] { rig.player->SetRate(1); });
    WaitFor([&] { return Loader::Load::live_loads_ > 0; }, 10);
  }
  WaitFor([] { return Loader::Load::live_loads_ == 0; }, 5);
  Check(Loader::Load::live_loads_ == 0, "every HlsLoad is destroyed with the player");
  WaitFor([] { return false; }, 1);
  Check(true, "no callback after destruction crashed");
}

}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    std::string only = argc > 1 ? argv[1] : "";
    Check(fp::FairPlayHlsPlayer::IsSupported(), "client URL loading is available on this macOS");
    std::vector<std::pair<std::string, void (*)()>> scenarios = {
        {"ts", VodTs}, {"fmp4", VodFmp4}, {"live", Live}, {"missing", Missing}, {"bad-url", BadUrl}, {"skd", Skd}, {"teardown", Teardown}};
    for (auto& [name, run] : scenarios) {
      if (only.empty() || only == name) {
        run();
      }
    }
    std::printf("%s (%d failures)\n", g_failures ? "FAILED" : "ALL PASSED", g_failures);
    return g_failures ? 1 : 0;
  }
}

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
#include "fairplay_hls_timeline.h"

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
  // http(s)://parc-hls.invalid/<host>/<path> -> https://<host>/<path>
  for (const char* scheme : {"https://", "http://"}) {
    std::string prefix = std::string(scheme) + kFakeHost + "/";
    if (url.rfind(prefix, 0) == 0) {
      return "https://" + url.substr(prefix.size());
    }
  }
  return "";
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
  void OnStartDateChange(std::optional<double> start_date_ms) override {
    start_date_changes.push_back(start_date_ms);
  }
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
  void OnVideoFrameCounts(uint32_t decoded, uint32_t dropped) override {
    frames_decoded += decoded;
    frames_dropped += dropped;
  }

  std::optional<fp::HlsMetadata> metadata;
  int64_t frames_decoded = 0;
  int64_t frames_dropped = 0;
  int metadata_count = 0;
  std::vector<bool> buffering;
  std::vector<fp::HlsTimeRange> loaded, seekable;
  int seekable_changes = 0;
  std::vector<double> duration_changes;
  std::vector<std::optional<double>> start_date_changes;
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
  Check(m.seekable.size() == 1 && m.seekable[0].start == 0 && m.seekable[0].end > 500,
        "seekable is one range covering the stream");
  Check(!m.start_date_ms, "no EXT-X-PROGRAM-DATE-TIME: no start date");
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
  NSString* algorithm = nil;
  BOOL interstitials = YES;
  auto read_item = [&] {
    AVPlayerItem* item = fp::HlsPlayerAVPlayer(rig.player->impl()).currentItem;
    algorithm = item.audioTimePitchAlgorithm;
    interstitials = item.automaticallyHandlesInterstitialEvents;
  };
  OnOwner(read_item);
  Check([algorithm isEqualToString:AVAudioTimePitchAlgorithmVarispeed] && !interstitials,
        "rate 1: Varispeed; AVFoundation doesn't run interstitials");
  OnOwner([&] {
    rig.player->SetRate(1.5);
    read_item();
  });
  Check([algorithm isEqualToString:AVAudioTimePitchAlgorithmSpectral], "rate 1.5 keeps pitch (Spectral)");
  OnOwner([&] {
    rig.player->SetPreservesPitch(false);
    read_item();
  });
  Check([algorithm isEqualToString:AVAudioTimePitchAlgorithmVarispeed], "preservesPitch false: Varispeed");
  double before = rig.Time();
  Check(WaitFor([&] { return rig.Time() > before + 2; }, 10), "plays on at 1.5x");
  // The layer is in no window here, so AVFoundation may count nothing; the
  // presentation harness checks the counts on a layer on screen.
  std::printf("       video frame counts reported: %lld decoded, %lld dropped\n",
              static_cast<long long>(rig.client.frames_decoded),
              static_cast<long long>(rig.client.frames_dropped));
}

// WebKit's rules (fairplay_hls_timeline.h), no network.
void Timeline() {
  std::printf("-- live and DVR timing rules (WebKit's)\n");
  using fp::HlsSeekableRangeInput;
  using fp::HlsSeekableWindow;
  using fp::HlsTime;
  using fp::HlsTimeKind;
  const HlsTime live{HlsTimeKind::kIndefinite, 0};
  const HlsTime invalid{HlsTimeKind::kInvalid, 0};
  auto numeric = [](double seconds) { return HlsTime{HlsTimeKind::kNumeric, seconds}; };
  auto range = [](double start, double end) { return HlsSeekableRangeInput{true, end == start, start, end}; };
  auto is = [](const std::optional<HlsSeekableWindow>& window, double start, double end) {
    return window && window->start == start && window->end == end;
  };

  Check(fp::HlsDurationSeconds(numeric(600)) == 600, "numeric duration");
  Check(std::isinf(fp::HlsDurationSeconds(live)) && fp::HlsDurationSeconds(live) > 0, "indefinite duration is +Infinity");
  Check(fp::HlsDurationSeconds(invalid) == 0, "invalid duration is 0");

  Check(is(fp::HlsSeekable({range(1000, 1300)}, INFINITY), 1000, 1300), "live DVR window");
  Check(is(fp::HlsSeekable({range(30, 40), range(10, 20)}, 600), 10, 40),
        "disjoint ranges make one window from the smallest start to the largest end");
  Check(is(fp::HlsSeekable({HlsSeekableRangeInput{false, false, 0, 900}, range(50, 50), range(100, 200)}, 600), 100, 200),
        "invalid and empty ranges are skipped");
  Check(is(fp::HlsSeekable({}, 600), 0, 600), "no range: up to the duration");
  Check(is(fp::HlsSeekable({}, INFINITY), 0, INFINITY), "no range on a live stream: [0, Infinity)");
  Check(!fp::HlsSeekable({}, 0), "no range and no duration: nothing seekable");
  Check(!fp::HlsSeekable({HlsSeekableRangeInput{false, false, 5, 9}, range(7, 7)}, 600),
        "only invalid or empty ranges: nothing seekable (the end is 0)");
  Check(is(fp::HlsSeekable({range(0, 0.5)}, 600), 0, 0.5), "a window ending after 0 is kept");

  Check(!fp::HlsStartDate(0, 12), "currentDate 0 (nil): no start date");
  Check(fp::HlsStartDate(1762480000.4, 10.3) == 1762479990.0, "start date rounds date − currentTime");
  Check(fp::HlsStartDate(1762480000.5, 0) == 1762480001.0, "a half second rounds away from zero");
  Check(!fp::HlsStartDate(1762480000, NAN), "an invalid currentTime: no start date");

  fp::HlsTimeline timeline;
  timeline.Start(live, {range(1000, 1300)}, std::nullopt);
  Check(std::isinf(timeline.duration()) && is(timeline.seekable(), 1000, 1300) && !timeline.start_date(),
        "live start: Infinity, one window, no date yet");
  Check(!timeline.DurationChanged(live), "the same live duration: no durationchange");
  Check(!timeline.SeekableChanged({range(1000, 1300)}), "the same window: no change");
  Check(timeline.SeekableChanged({range(1002, 1302)}) && is(timeline.seekable(), 1002, 1302), "the window slides");
  Check(timeline.ReadyStateChanged(1762480000) && timeline.start_date() == 1762480000.0,
        "a ready-state change samples the start date");
  Check(!timeline.ReadyStateChanged(1762480000), "the same start date: no change");
  Check(timeline.DurationChanged(numeric(3600)) && timeline.duration() == 3600,
        "live becoming VOD (EXT-X-ENDLIST) fires durationchange");
  Check(!timeline.DurationChanged(numeric(3600)), "the same duration again: no durationchange");
  Check(timeline.SeekableRanges().size() == 1, "seekable is one range");

  fp::HlsTimeline from_invalid;
  from_invalid.Start(invalid, {}, std::nullopt);
  Check(!from_invalid.seekable(), "invalid duration, no range: nothing seekable");
  Check(!from_invalid.DurationChanged(numeric(10)) && from_invalid.duration() == 10,
        "a duration arriving from invalid fires no durationchange (WebKit's durationDidChange)");

  // WebKit caches the window's ends and computes them again only when the
  // ranges change or, at a ready-state change, while the end is 0.
  fp::HlsTimeline cached;
  cached.Start(numeric(0), {}, std::nullopt);
  Check(!cached.seekable(), "duration 0, no range: nothing seekable");
  Check(cached.DurationChanged(numeric(50)) && !cached.seekable(), "a duration change alone leaves seekable");
  Check(cached.ReadyStateChanged(std::nullopt) && is(cached.seekable(), 0, 50),
        "the next ready-state change computes the empty window again");
  Check(cached.DurationChanged(numeric(60)) && !cached.ReadyStateChanged(std::nullopt) && is(cached.seekable(), 0, 50),
        "a cached window keeps its end across ready-state changes");
  Check(cached.SeekableChanged({}) && is(cached.seekable(), 0, 60), "a ranges change computes it again");
}

// The window the page sees now: the last change, or the metadata's.
std::vector<fp::HlsTimeRange> CurrentSeekable(const Client& client) {
  return client.seekable_changes ? client.seekable : client.metadata->seekable;
}

std::optional<double> CurrentStartDate(const Client& client) {
  return client.start_date_changes.empty() ? client.metadata->start_date_ms : client.start_date_changes.back();
}

void Live() {
  std::printf("-- live with a DVR window and EXT-X-PROGRAM-DATE-TIME (Unified Streaming demo)\n");
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
  std::vector<fp::HlsTimeRange> window;
  OnOwner([&] { window = CurrentSeekable(rig.client); });
  Check(window.size() == 1 && window[0].start < window[0].end && window[0].end > 0,
        "seekable is one DVR window");
  std::optional<double> date;
  OnOwner([&] { date = CurrentStartDate(rig.client); });
  double now = [[NSDate date] timeIntervalSince1970];
  std::printf("   seekable %s, start date %s, at %.3f\n",
              window.empty() ? "none"
                             : (std::to_string(window[0].start) + "-" + std::to_string(window[0].end)).c_str(),
              date ? std::to_string(*date).c_str() : "none", rig.Time());
  Check(date && std::fmod(*date, 1000) == 0, "getStartDate is a whole second (WebKit rounds)");
  Check(date && std::fabs(*date / 1000 + rig.Time() - now) < 120,
        "start date + currentTime is the wall-clock time of the live picture");
  if (window.size() != 1) {
    return;
  }
  // Within the DVR window.
  double target = window[0].start + (window[0].end - window[0].start) / 2;
  int seek_result = -1;
  OnOwner([&] { rig.player->Seek(target, [&](bool finished) { seek_result = finished; }); });
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(seek_result == 1 && std::fabs(rig.Time() - target) < 1, "an exact seek into the DVR window lands there");
  // To the live edge (the window's end, where the element's seek clamps
  // anything later, Infinity included).
  OnOwner([&] { window = CurrentSeekable(rig.client); });
  seek_result = -1;
  OnOwner([&] { rig.player->Seek(window[0].end, [&](bool finished) { seek_result = finished; }); });
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(seek_result == 1 && rig.Time() > window[0].end - 3, "a seek to the window's end reaches the live edge");
  Check(WaitFor([&] { return rig.Time() > window[0].end + 1; }, 20), "plays on from the live edge");
  Check(rig.client.duration_changes.empty(), "no durationchange while live");
  Check(rig.client.seekable_changes > 0 && rig.client.seekable.size() == 1, "the sliding window is reported as one range");
  Check(rig.loader.foreign_ == 0 && rig.client.errors == 0, "only the loader's host, no error");
}

void BadUrl() {
  std::printf("-- refused URLs\n");
  Rig rig;
  Check(!rig.Load("file:///etc/hosts").ok(), "a file URL is refused");
  Rig rig2;
  Check(!rig2.Load(std::string("https://") + kFakeHost + "/\xff\xfe.m3u8").ok(), "a URL that isn't UTF-8 is refused");
}

void PlainHttp() {
  std::printf("-- an http:// playlist (App Transport Security)\n");
  Rig rig;
  Check(rig.Load(std::string("http://") + kFakeHost +
                 "/devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
            .ok(),
        "Load");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  std::printf("   loads %d, first %s, error %s\n", rig.loader.starts_,
              rig.loader.urls_.empty() ? "none" : rig.loader.urls_[0].c_str(), rig.client.error_message.substr(0, 160).c_str());
  Check(ready && rig.client.metadata_count == 1, "http:// plays through the loader (ATS doesn't apply to client loads)");
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
  Check(rig.client.key_uris.size() == 1, "one notification for AVFoundation's one request");
  Check(rig.Time() < 0.5, "no key, no playback");
  OnOwner([&] { rig.player->FailKeyRequests(rig.client.key_uris[0], "no license in this harness"); });
  bool failed = WaitFor([&] { return rig.client.errors > 0 || rig.client.key_uris.size() > 1; }, 20);
  std::printf("   after FailKeyRequests: errors=%d key requests=%zu (%s)\n", rig.client.errors,
              rig.client.key_uris.size(), rig.client.error_message.substr(0, 120).c_str());
  Check(failed && rig.client.key_uris.size() > 1,
        "a failed key request is asked for again (AVFoundation retries; the element keeps waiting, as in Safari)");
}

// The CDM's key loader takes skd requests itself: installed between
// CreateAsset and Start, it gets the loading request, and the client's
// OnKeyRequest never fires for it.
struct RecordingKeyHandler : fp::HlsKeyRequestHandler {
  void HandleLoadingRequest(AVAssetResourceLoadingRequest* request) override {
    uris.push_back(request.request.URL.absoluteString.UTF8String ?: "");
    [request finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
  }
  void HandleCancelledLoadingRequest(AVAssetResourceLoadingRequest*) override { cancelled++; }
  std::vector<std::string> uris;
  int cancelled = 0;
};

void SkdHandler() {
  std::printf("-- FairPlay HLS: skd requests go to an installed key handler\n");
  Rig rig;
  RecordingKeyHandler handler;
  fp::Result created, started;
  OnOwner([&] {
    created = rig.player->CreateAsset(Fake("media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/manifest.m3u8"), "");
    Check(fp::HlsPlayerAsset(rig.player->impl()) != nil && fp::HlsPlayerAVPlayer(rig.player->impl()) == nil,
          "CreateAsset makes the asset but no player yet");
    fp::SetHlsKeyRequestHandler(rig.player->impl(), &handler);
    started = rig.player->Start();
    rig.player->SetMuted(true);
    rig.player->SetRate(1);
  });
  Check(created.ok() && started.ok(), "CreateAsset then Start");
  bool asked = WaitFor([&] { return !handler.uris.empty() || rig.client.errors; }, 20);
  Check(asked && !handler.uris.empty() && handler.uris[0].rfind("skd://", 0) == 0, "the handler gets the skd request");
  Check(rig.client.key_uris.empty(), "the client's OnKeyRequest doesn't fire for it");
  OnOwner([&] { fp::SetHlsKeyRequestHandler(rig.player->impl(), nullptr); });
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
        {"timeline", Timeline}, {"ts", VodTs}, {"fmp4", VodFmp4}, {"live", Live}, {"missing", Missing}, {"http", PlainHttp}, {"bad-url", BadUrl}, {"skd", Skd}, {"skd-handler", SkdHandler}, {"teardown", Teardown}};
    for (auto& [name, run] : scenarios) {
      if (only.empty() || only == name) {
        run();
      }
    }
    std::printf("%s (%d failures)\n", g_failures ? "FAILED" : "ALL PASSED", g_failures);
    return g_failures ? 1 : 0;
  }
}

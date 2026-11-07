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
#import <objc/runtime.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_hls_keys.h"
#include "fairplay_hls_player.h"
#include "fairplay_hls_player_internal.h"
#include "fairplay_hls_timeline.h"
#include "fairplay_key_session.h"

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
    if (on_metadata) {
      on_metadata();
    }
  }
  void OnBufferingStateChange(bool have_enough) override {
    buffering.push_back(have_enough);
  }
  void OnReadyStateChange(fp::HlsReadyState state) override { ready_states.push_back(state); }
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
  void OnTimeJumped() override { time_jumps++; }
  void OnEnded() override { ended++; }
  void OnError(fp::HlsError e, const std::string& message) override {
    error = static_cast<int>(e);
    error_message = message;
    errors++;
  }
  void OnKeyRequest(const std::string& uri) override { key_uris.push_back(uri); }
  void OnPlaybackTargetIsWirelessChange(bool wireless) override { wireless_changes.push_back(wireless); }
  void OnVideoFrameCounts(uint32_t decoded, uint32_t dropped) override {
    frames_decoded += decoded;
    frames_dropped += dropped;
  }

  std::optional<fp::HlsMetadata> metadata;
  // The element's loadedmetadata handler, run inside OnMetadata.
  std::function<void()> on_metadata;
  int64_t frames_decoded = 0;
  int64_t frames_dropped = 0;
  int metadata_count = 0;
  std::vector<bool> buffering;
  std::vector<fp::HlsReadyState> ready_states;
  std::vector<fp::HlsTimeRange> loaded, seekable;
  int seekable_changes = 0;
  std::vector<double> duration_changes;
  std::vector<std::optional<double>> start_date_changes;
  int32_t width = 0, height = 0;
  int ended = 0;
  int time_jumps = 0;
  int error = -1;
  int errors = 0;
  std::string error_message;
  std::vector<std::string> key_uris;
  std::vector<bool> wireless_changes;
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
  Check(ready && rig.client.metadata.has_value(), "metadata arrives from the asset (HAVE_METADATA)");
  if (!rig.client.metadata) {
    return;
  }
  const fp::HlsMetadata& m = *rig.client.metadata;
  Check(m.has_video, "video (the variants name their codecs)");
  Check(m.has_audio, "audio");
  Check(!m.is_live && std::fabs(m.duration - 600) < 2, "finite duration about 600 s");
  Check(m.seekable.size() == 1 && m.seekable[0].start == 0 && m.seekable[0].end > 500,
        "seekable is one range covering the stream");
  Check(!m.start_date_ms, "no EXT-X-PROGRAM-DATE-TIME: no start date");
  OnOwner([&] { rig.player->SetRate(1); });
  bool playing = WaitFor([&] { return rig.Time() > 3; }, 20);
  Check(playing, "time advances past 3 s");
  Check(rig.client.width > 0 && rig.client.height > 0, "the natural size follows from the item");
  Check(!rig.client.buffering.empty() && rig.client.buffering.back(), "buffering reports enough");
  Check(!rig.client.ready_states.empty() && rig.client.ready_states.back() == fp::HlsReadyState::kHaveEnoughData,
        "WebKit's readyState reaches HAVE_ENOUGH_DATA");
  Check(!rig.client.loaded.empty(), "loaded ranges reported");
  // Each KVO notification carries its own value, as WebKit caches them: a dip
  // to an empty buffer and back, all notified before the owner sequence runs,
  // still reaches the client (underflow, then enough data again).
  size_t buffering_before_dip = 0;
  size_t ready_before_dip = 0;
  OnOwner([&] {
    buffering_before_dip = rig.client.buffering.size();
    ready_before_dip = rig.client.ready_states.size();
    fp::FairPlayHlsPlayer::Impl* impl = rig.player->impl();
    for (auto [key, value] : std::vector<std::pair<NSString*, BOOL>>{{@"playbackBufferFull", NO},
                                                                   {@"playbackLikelyToKeepUp", NO},
                                                                   {@"playbackBufferEmpty", YES},
                                                                   {@"playbackBufferEmpty", NO},
                                                                   {@"playbackLikelyToKeepUp", YES}}) {
      fp::HlsPlayerDeliverItemChangeForTesting(impl, key, nil, true);
      fp::HlsPlayerDeliverItemChangeForTesting(impl, key, @(value), false);
    }
  });
  Check(WaitFor(
            [&] {
              const std::vector<bool>& b = rig.client.buffering;
              return b.size() >= buffering_before_dip + 2 && !b[buffering_before_dip] && b.back();
            },
            5),
        "a buffer dip quicker than the owner sequence reaches the client, then its recovery");
  OnOwner([&] {
    const std::vector<fp::HlsReadyState>& r = rig.client.ready_states;
    bool dipped = r.size() > ready_before_dip && r[ready_before_dip] == fp::HlsReadyState::kHaveCurrentData;
    Check(dipped && r.back() == fp::HlsReadyState::kHaveEnoughData,
          "WebKit's readyState follows it: HAVE_CURRENT_DATA, then HAVE_ENOUGH_DATA");
  });
  OnOwner([&] { rig.player->SetRate(0); });
  WaitFor([] { return false; }, 0.5);
  double paused_at = rig.Time();
  WaitFor([] { return false; }, 1.5);
  Check(std::fabs(rig.Time() - paused_at) < 0.05, "pause holds the clock");
  int seek_result = -1;
  size_t buffering_before_seek = 0;
  int jumps_before_seek = 0;
  OnOwner([&] {
    buffering_before_seek = rig.client.buffering.size();
    jumps_before_seek = rig.client.time_jumps;
    rig.player->Seek(300, [&](bool finished) { seek_result = finished; });
  });
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(seek_result == 1 && std::fabs(rig.Time() - 300) < 0.1, "exact seek to 300 s finishes there");
  Check(WaitFor([&] { return rig.client.time_jumps > jumps_before_seek; }, 5),
        "the time jump reaches the client while paused");
  // Chromium finishes a seek only at HAVE_ENOUGH; AVFoundation's dip and
  // recovery within the seek is too quick to show as a change.
  Check(WaitFor([&] { return rig.client.buffering.size() > buffering_before_seek && rig.client.buffering.back(); }, 10),
        "after the seek the client hears enough data again");
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
  // The layer takes its player once it has a size (fairplay_hls_player_layer.h),
  // here the size the compositor gives it when it first draws the layer.
  OnOwner([&] { layer.bounds = CGRectMake(0, 0, 640, 360); });
  Check(layer && layer.player == fp::HlsPlayerAVPlayer(rig.player->impl()), "player layer shows the player once sized");
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
  Rig rig3;
  Check(!rig3.Load("blob:https://parc-hls.invalid/0b5b0a5e-3f0e-4bd3-9a5e-6d1b8c1c2f11").ok(),
        "a blob: URL is refused (AVFoundation reports it unsupported before any load)");
}

// A data: media playlist of byte ranges in one file, as Spotify's player
// writes them: |ranges| are the init segment, then each 6 s segment.
std::string DataPlaylist(const std::string& file, const std::vector<std::string>& ranges) {
  std::string playlist = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:0\n"
                         "#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"" + file + "\",BYTERANGE=\"" + ranges[0] + "\"\n";
  for (size_t i = 1; i < ranges.size(); ++i) {
    playlist += "#EXTINF:5.99467,\n#EXT-X-BYTERANGE:" + ranges[i] + "\n" + file + "\n";
  }
  playlist += "#EXT-X-ENDLIST\n";
  NSString* base64 = [[@(playlist.c_str()) dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
  return std::string("data:application/vnd.apple.mpegurl;base64,") + base64.UTF8String;
}

constexpr const char* kBipbopFmp4 = "devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/";

// Spotify's player under Safari's identity plays a FairPlay audio file as a
// data: playlist of its byte ranges (a blob: URL only without MediaSource).
void DataUrl() {
  std::printf("-- a data: playlist of byte ranges in one audio file (Spotify's shape)\n");
  std::string file = Fake((std::string(kBipbopFmp4) + "a1/main.mp4").c_str());
  Rig rig;
  fp::Result result;
  OnOwner([&] {
    result = rig.player->Load(DataPlaylist(file, {"616@0", "121090@616", "121201@121706"}),
                              "application/vnd.apple.mpegurl");
    rig.player->SetMuted(true);
  });
  Check(result.ok(), "Load accepts the data: URL");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata && std::fabs(rig.client.metadata->duration - 11.99) < 0.1,
        "metadata from the decoded playlist: two segments, about 12 s");
  OnOwner([&] { rig.player->SetRate(1); });
  Check(WaitFor([&] { return rig.Time() > 3; }, 20), "audio plays past 3 s");
  bool only_segments = !rig.loader.urls_.empty();
  for (const std::string& url : rig.loader.urls_) {
    only_segments = only_segments && url == file;
  }
  Check(only_segments, "AVFoundation decoded the playlist; only the file's ranges went through HlsLoader");
  Check(rig.loader.ranged_ > 0 && rig.loader.foreign_ == 0 && rig.client.errors == 0, "ranged loads, no error");
}

// Its video podcasts: a data: master playlist whose audio rendition and
// variants are data: media playlists.
void DataUrlVideo() {
  std::printf("-- a data: master playlist of data: media playlists (Spotify's video)\n");
  std::string audio = Fake((std::string(kBipbopFmp4) + "a1/main.mp4").c_str());
  std::string video = Fake((std::string(kBipbopFmp4) + "v2/main.mp4").c_str());
  std::string master = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",LANGUAGE=\"eng\",NAME=\"English\",AUTOSELECT=YES,URI=\"" +
                       DataPlaylist(audio, {"616@0", "121090@616", "121201@121706"}) +
                       "\"\n#EXT-X-STREAM-INF:BANDWIDTH=541052,RESOLUTION=480x270,CODECS=\"mp4a.40.2, avc1.640015\",AUDIO=\"audio\"\n" +
                       DataPlaylist(video, {"719@0", "274201@719", "280451@274920"}) + "\n";
  NSString* base64 = [[@(master.c_str()) dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
  Rig rig;
  fp::Result result;
  OnOwner([&] {
    result = rig.player->Load(std::string("data:application/vnd.apple.mpegurl;base64,") + base64.UTF8String,
                              "application/vnd.apple.mpegurl");
    rig.player->SetMuted(true);
  });
  Check(result.ok(), "Load accepts the data: master playlist");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata && rig.client.metadata->has_video && rig.client.metadata->has_audio,
        "metadata with video and audio: " + rig.client.error_message.substr(0, 160));
  OnOwner([&] { rig.player->SetRate(1); });
  Check(WaitFor([&] { return rig.Time() > 3; }, 20), "plays past 3 s");
  Check(rig.client.width == 480 && rig.client.height == 270, "the variant's picture size");
  bool only_files = !rig.loader.urls_.empty();
  for (const std::string& url : rig.loader.urls_) {
    only_files = only_files && (url == audio || url == video);
  }
  Check(only_files && rig.loader.foreign_ == 0 && rig.client.errors == 0,
        "every playlist decoded by AVFoundation; only the two files' ranges loaded, no error");
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

// FairPlay keys (Engine/ParcNative/fairplay/README.md, "HLS assets"): a
// stand-in page answers the player's key requests with skd sessions on a
// FairPlayCdm sharing the player's owner queue, and Axinom's license service
// (the vectors, service, certificate and tokens tests/FairPlay/harness.mm
// uses; MultiKey has separate audio and video skd keys).
NSString* const kLicenseUrl = @"https://drm-fairplay-licensing.axprod.net/AcquireLicense";
NSString* const kCertificateUrl = @"https://tools.axinom.com/FPScert/fairplay.cer";
NSString* const kSingleKeyToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjMwMmY4MGRkLTQxMWUtNDg4Ni1iY2E1LWJiMWY4MDE4YTAyNCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiMWVYeWhGWmNGVjljemNtZG5BREpMdz09IiwKICAgICAgICAiaXYiOiAiZC8wWWlhcjBGRHNJVlVpendQbGJtZz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.5VxBJQsgGVissi9WCNpT7IoykEAmxaEcif6F3SeLvzU";
NSString* const kMultiKeyToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogImI1NGVjOTE0LTE5MmQtNGVhMS1hYzE5LWY0MjllYjQ5ODI2OCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiUldKemlSUDRqQkhjd2tJYzRTd1h5QT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9LAogICAgICB7CiAgICAgICAgImlkIjogImM4M2M0ZWE4LTBmMmEtNDUyMy04NTFjLWZiZWNjZGMwZjIwMiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiSHFoK1BCNVU1OStvclMzVGVZQ2lOUT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9LAogICAgICB7CiAgICAgICAgImlkIjogImM4NjhjNzAyLWM3MWItNDA2NC1hZTJiLWMyNGY3Y2MxMDc5MiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiLy9nM2pmdktjUlliaHBwRW04c3BqUT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.09GZO7pokr1k24NXKxIV7qyEZ2lhtbpfMoKfP7vzSns";
const char* const kSingleKeyMaster = "media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/manifest.m3u8";
const char* const kMultiKeyMaster = "media.axprod.net/TestVectors/MultiKey/Cmaf_h264_1080p_cbcs/manifest.m3u8";
// The SingleKey playlists' EXT-X-KEY URI.
const std::string kSkd = "skd://302f80dd-411e-4886-bca5-bb1f8018a024:77FD1889AAF4143B085548B3C0F95B9A";

std::vector<uint8_t> Bytes(const std::string& text) {
  return std::vector<uint8_t>(text.begin(), text.end());
}

std::vector<uint8_t> Bytes(NSData* data) {
  const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
  return std::vector<uint8_t>(bytes, bytes + data.length);
}

// Blocking; never on the owner queue.
NSData* Fetch(NSURLRequest* request, NSInteger* status) {
  __block NSData* result = nil;
  __block NSInteger code = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                   completionHandler:^(NSData* data, NSURLResponse* response, NSError*) {
                                     result = data;
                                     if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                                       code = [(NSHTTPURLResponse*)response statusCode];
                                     }
                                     dispatch_semaphore_signal(done);
                                   }] resume];
  dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
  *status = code;
  return result;
}

NSData* Certificate() {
  static NSData* certificate = [] {
    NSInteger status = 0;
    NSData* data = Fetch([NSURLRequest requestWithURL:[NSURL URLWithString:kCertificateUrl]], &status);
    return status == 200 ? data : nil;
  }();
  return certificate;
}

// The page and its media element: MediaKeys, sessions and the element's
// encrypted events (the key loader's needs). Everything but the license POST
// runs on the owner queue. Declare it before the KeyRig.
struct KeyPage : fp::FairPlayCdmClient, fp::FairPlayHlsKeyLoaderClient {
  explicit KeyPage(NSString* token) : token_(token) {}
  ~KeyPage() {
    OnOwner([this] { cdm.reset(); });
  }

  void Create() {
    NSData* certificate = Certificate();
    OnOwner([this, certificate] {
      cdm = std::make_unique<fp::FairPlayCdm>(this, OwnerPoster());
      cdm->SetServerCertificate(Bytes(certificate), [](const fp::Result&) {});
    });
  }

  // generateRequest("skd", init_data); call on the owner queue.
  void GenerateOnOwner(const std::string& init_data) {
    std::weak_ptr<int> alive = alive_;
    cdm->CreateSessionAndGenerateRequest(
        fp::InitDataType::kSkd, Bytes(init_data), [this, alive](const fp::Result& result, const std::string& id) {
          if (alive.expired()) {
            return;
          }
          std::printf("   generateRequest -> %s\n", result.ok() ? id.c_str() : result.message.c_str());
          if (result.ok()) {
            sessions.push_back(id);
          } else {
            generate_failures++;
            generate_error = result.exception;
          }
        });
  }
  void Generate(const std::string& init_data) {
    OnOwner([&] { GenerateOnOwner(init_data); });
  }

  void OnSessionMessage(const std::string& session_id,
                        fp::MessageType type,
                        const std::vector<uint8_t>& message) override {
    messages++;
    message_types.push_back(type);
    if (hold_messages) {
      held.push_back(session_id);
      return;
    }
    std::weak_ptr<int> alive = alive_;
    std::string session = session_id;
    NSData* body = [NSData dataWithBytes:message.data() length:message.size()];
    NSString* token = token_;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSMutableURLRequest* post = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLicenseUrl]];
      post.HTTPMethod = @"POST";
      post.HTTPBody = body;
      [post setValue:token forHTTPHeaderField:@"X-AxDRM-Message"];
      [post setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
      NSInteger status = 0;
      NSData* ckc = Fetch(post, &status);
      dispatch_async(Owner(), ^{
        if (alive.expired() || !cdm) {
          return;
        }
        std::printf("   SPC %lu bytes -> HTTP %ld, CKC %lu bytes\n", (unsigned long)body.length, (long)status,
                    (unsigned long)ckc.length);
        if (status != 200 || !ckc.length) {
          license_failures++;
          return;
        }
        cdm->UpdateSession(session, Bytes(ckc), [this, alive](const fp::Result& result) {
          if (!alive.expired()) {
            (result.ok() ? updates_ok : updates_failed)++;
          }
        });
      });
    });
  }

  void OnSessionKeysChange(const std::string&, bool, const std::vector<fp::KeyInfo>& keys) override {
    for (const fp::KeyInfo& key : keys) {
      statuses[std::string(key.key_id.begin(), key.key_id.end())] = key.status;
    }
  }
  void OnSessionClosed(const std::string&) override {}

  // Every skd request the loader is handed (legacy pages' webkitneedkey).
  void OnKeyLoadingRequest(const std::string& url) override {
    loading_requests.push_back(url);
    if (on_loading_request) {
      on_loading_request(url);
    }
  }

  // The element's encrypted(skd) event, and its waitingforkey without a CDM.
  void OnKeyNeeded(const std::string& uri, bool cdm_attached) override {
    needs.push_back(uri);
    need_cdm_attached.push_back(cdm_attached);
    if (on_need) {
      on_need(uri);
    }
  }

  bool Is(const std::string& key_id, fp::KeyStatus status) const {
    auto it = statuses.find(key_id);
    return it != statuses.end() && it->second == status;
  }
  bool Usable(const std::string& key_id) const { return Is(key_id, fp::KeyStatus::kUsable); }

  std::unique_ptr<fp::FairPlayCdm> cdm;
  std::function<void(const std::string&)> on_need;  // The encrypted handler.
  std::function<void(const std::string&)> on_loading_request;  // webkitneedkey.
  std::vector<std::string> needs;
  std::vector<bool> need_cdm_attached;  // Each need's, in order.
  std::vector<std::string> loading_requests;
  std::vector<std::string> sessions;
  std::vector<fp::MessageType> message_types;
  std::map<std::string, fp::KeyStatus> statuses;
  std::vector<std::string> held;
  bool hold_messages = false;
  int messages = 0;
  int generate_failures = 0;
  fp::Exception generate_error = fp::Exception::kNotSupported;
  int license_failures = 0;
  int updates_ok = 0;
  int updates_failed = 0;

 private:
  NSString* token_;
  std::shared_ptr<int> alive_ = std::make_shared<int>(0);
};

// The GPU service's order: CreateAsset, the key loader for the asset (with
// the element's CDM if it has one), the handler, Start.
struct KeyRig {
  explicit KeyRig(fp::FairPlayHlsKeyLoaderClient* client) : client(client) {}
  ~KeyRig() {
    OnOwner([this] {
      fp::SetHlsKeyRequestHandler(rig.player->impl(), nullptr);
      keys.reset();
    });
  }
  // Call on the owner queue.
  void LoadOnOwner(const char* master, fp::FairPlayCdm* cdm) {
    rig.player->CreateAsset(Fake(master), "");
    keys = std::make_unique<fp::FairPlayHlsKeyLoader>(fp::HlsPlayerAsset(rig.player->impl()), cdm, client,
                                                      OwnerPoster());
    fp::SetHlsKeyRequestHandler(rig.player->impl(), keys.get());
    rig.player->Start();
    rig.player->SetMuted(true);
  }
  void Load(const char* master, fp::FairPlayCdm* cdm) {
    OnOwner([&] { LoadOnOwner(master, cdm); });
  }
  void Play() {
    OnOwner([&] { rig.player->SetRate(1); });
  }
  fp::Result SetCdm(fp::FairPlayCdm* cdm) {
    fp::Result result;
    OnOwner([&] { result = keys->SetCdm(cdm); });
    return result;
  }
  bool PlaysTo5s() {
    bool plays = WaitFor([&] { return rig.Time() >= 5 || rig.client.errors > 0; }, 25) && rig.client.errors == 0;
    std::printf("   clock %.2f s, errors %d %s\n", rig.Time(), rig.client.errors,
                rig.client.error_message.substr(0, 120).c_str());
    return plays;
  }

  Rig rig;
  std::unique_ptr<fp::FairPlayHlsKeyLoader> keys;
  fp::FairPlayHlsKeyLoaderClient* client;
};

// Force the system factory to fail, without adding a production test hook.
IMP g_session_factory = nullptr;
bool g_fail_session = false;
int g_session_attempts = 0;
id SessionFactory(id cls, SEL selector, NSString* key_system) {
  ++g_session_attempts;
  if (g_fail_session)
    return nil;
  return reinterpret_cast<id (*)(id, SEL, NSString*)>(g_session_factory)(cls, selector, key_system);
}

void KeysSessionFailure() {
  KeyPage page(kSingleKeyToken);
  page.Create();
  Method factory = class_getClassMethod([AVContentKeySession class], @selector(contentKeySessionWithKeySystem:));
  OnOwner([&] {
    g_session_attempts = 0;
    g_fail_session = true;
    g_session_factory = method_setImplementation(factory, reinterpret_cast<IMP>(SessionFactory));
  });
  {
    KeyRig kr(&page);
    page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
    kr.Load(kSingleKeyMaster, page.cdm.get());
    OnOwner([&] { Check(g_session_attempts == 0, "attachment does not create a key session"); });
    kr.Play();
    Check(WaitFor([&] { return page.generate_failures > 0; }, 25), "failed key session completes generateRequest");
    OnOwner([&] {
      Check(page.generate_failures == 1 && page.generate_error == fp::Exception::kNotSupported,
            "generateRequest rejects with NotSupportedError");
      Check(page.sessions.empty() && page.messages == 0, "failed generation leaves no session or license message");
      Check(page.need_cdm_attached == std::vector<bool>{true}, "CDM stays attached: encrypted without waitingforkey");
      Check(kr.rig.client.errors == 0, "no MediaError for a key-session creation failure");
      g_fail_session = false;
      page.GenerateOnOwner(kSkd);
    });
    Check(kr.PlaysTo5s(), "a fresh generateRequest retries the held key and plays");
    OnOwner([&] { Check(page.sessions.size() == 1 && page.updates_ok == 1, "retry has one licensed session"); });
  }
  OnOwner([&] { method_setImplementation(factory, g_session_factory); });
}

// MediaKeys before the load (Shaka): the request still comes through the
// resource loader, raising webkitneedkey and encrypted as in Safari, and the
// attached CDM answers the page's session with the request's own SPC.
void KeysMediaKeysFirst() {
  std::printf("-- FairPlay HLS keys: MediaKeys before the load\n");
  KeyPage page(kSingleKeyToken);
  page.Create();
  page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
  KeyRig kr(&page);
  kr.Load(kSingleKeyMaster, page.cdm.get());
  kr.Play();
  bool plays = kr.PlaysTo5s();
  Check(page.loading_requests.size() == 1 && page.loading_requests[0] == kSkd,
        "the loading request is reported (legacy webkitneedkey)");
  Check(page.needs == std::vector<std::string>{kSkd}, "one encrypted(skd) with the playlist's URI");
  Check(page.need_cdm_attached == std::vector<bool>{true}, "the request came with the CDM attached: no waitingforkey");
  Check(page.messages == 1 && page.updates_ok == 1 && page.Usable(kSkd),
        "one SPC/CKC exchange; key status usable under the URI");
  Check(plays, "protected HLS plays");
  Check(kr.SetCdm(nullptr).ok(), "setMediaKeys(null) detaches the CDM");
}

// MediaKeys after the key request (Apple's sample): the resource loader holds
// the request, and the session answers it with the request's own SPC.
void KeysLoaderRoute() {
  std::printf("-- FairPlay HLS keys: key request first, MediaKeys after\n");
  KeyPage page(kSingleKeyToken);
  KeyRig kr(&page);
  kr.Load(kSingleKeyMaster, nullptr);
  kr.Play();
  bool asked = WaitFor([&] { return !page.needs.empty(); }, 20);
  Check(asked && page.needs[0] == kSkd, "encrypted(skd) with the URI before MediaKeys exist");
  Check(asked && !page.need_cdm_attached[0], "the request came with no CDM: waitingforkey");
  Check(!page.loading_requests.empty() && page.loading_requests[0] == kSkd,
        "the loading request is reported first (legacy webkitneedkey)");
  page.Create();
  Check(kr.SetCdm(page.cdm.get()).ok(), "setMediaKeys after the load attaches the CDM");
  page.Generate(kSkd);
  bool plays = kr.PlaysTo5s();
  Check(page.messages == 1 && page.updates_ok == 1 && page.Usable(kSkd) && page.needs.size() == 1,
        "one encrypted event, one SPC/CKC exchange; key status usable under the URI");
  Check(plays, "protected HLS plays");
  OnOwner([&] { kr.keys->SetOutputObscured(true); });
  WaitFor([&] { return page.Is(kSkd, fp::KeyStatus::kOutputRestricted); }, 3);
  Check(page.Is(kSkd, fp::KeyStatus::kOutputRestricted), "obscured output reports output-restricted");
  OnOwner([&] { kr.keys->SetOutputObscured(false); });
  WaitFor([&] { return page.Usable(kSkd); }, 3);
  Check(page.Usable(kSkd), "usable again once output is no longer obscured");
}

// MediaKeys attached after AVFoundation's request but before the loader
// reports its need (here in the page's webkitneedkey handler, which comes
// first): the request came with no CDM, so the element waits for the key, as
// WebKit decides when AVFoundation asks (shouldWaitForLoadingOfResource).
void KeysAttachAtRequest() {
  std::printf("-- FairPlay HLS keys: MediaKeys attached between the request and its report\n");
  KeyPage page(kSingleKeyToken);
  page.Create();
  KeyRig kr(&page);
  KeyRig* krp = &kr;
  KeyPage* pagep = &page;
  page.on_loading_request = [krp, pagep](const std::string&) {
    if (pagep->loading_requests.size() == 1) {
      krp->keys->SetCdm(pagep->cdm.get());
    }
  };
  page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
  kr.Load(kSingleKeyMaster, nullptr);
  kr.Play();
  bool plays = kr.PlaysTo5s();
  Check(page.needs == std::vector<std::string>{kSkd} && page.need_cdm_attached == std::vector<bool>{false},
        "one encrypted(skd), reported as a request made with no CDM: waitingforkey");
  Check(page.messages == 1 && page.updates_ok == 1 && page.Usable(kSkd),
        "the attached CDM's session licenses the held request");
  Check(plays, "protected HLS plays");
}

// Separate audio and video keys, MediaKeys before the load and after.
void KeysMultiKey() {
  std::printf("-- FairPlay HLS keys: MultiKey (audio and video keys)\n");
  for (bool keys_first : {false, true}) {
    KeyPage page(kMultiKeyToken);
    KeyRig kr(&page);
    if (keys_first) {
      page.Create();
      page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
      kr.Load(kMultiKeyMaster, page.cdm.get());
    } else {
      kr.Load(kMultiKeyMaster, nullptr);
    }
    kr.Play();
    if (!keys_first) {
      WaitFor([&] { return page.needs.size() >= 2; }, 20);
      page.Create();
      OnOwner([&] {
        kr.keys->SetCdm(page.cdm.get());
        for (const std::string& uri : page.needs) {
          page.GenerateOnOwner(uri);
        }
        page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
      });
    }
    bool plays = kr.PlaysTo5s();
    std::string order = keys_first ? "MediaKeys first" : "MediaKeys after the requests";
    Check(page.needs.size() >= 2 && page.updates_ok == static_cast<int>(page.needs.size()),
          order + ": an encrypted event and a license per key");
    Check(plays, order + ": protected HLS plays");
  }
}

// The session first: it waits for the asset's request. Everything runs in one
// owner task, before any request can arrive.
void KeysAwait() {
  std::printf("-- FairPlay HLS keys: session waiting for the asset's request\n");
  KeyPage page(kSingleKeyToken);
  page.Create();
  KeyRig kr(&page);
  OnOwner([&] {
    kr.LoadOnOwner(kSingleKeyMaster, nullptr);
    kr.keys->SetCdm(page.cdm.get());
    page.GenerateOnOwner(kSkd);
    kr.rig.player->SetRate(1);
  });
  bool plays = kr.PlaysTo5s();
  Check(page.needs.empty() && page.messages == 1 && page.updates_ok == 1,
        "the waiting session takes the asset's request; no encrypted event");
  Check(plays, "protected HLS plays");
}

// A session made before any asset was attached plans for the MSE route; the
// asset's request reaches it as a second license request, whether the CDM
// comes with the loader or later.
void KeysEarlySession() {
  std::printf("-- FairPlay HLS keys: session made before MediaKeys were attached\n");
  for (bool cdm_first : {true, false}) {
    KeyPage page(kSingleKeyToken);
    page.Create();
    page.Generate(kSkd);
    WaitFor([&] { return page.updates_ok == 1; }, 15);
    KeyRig kr(&page);
    kr.Load(kSingleKeyMaster, cdm_first ? page.cdm.get() : nullptr);
    kr.Play();
    if (!cdm_first) {
      WaitFor([&] { return !page.needs.empty(); }, 20);
      kr.SetCdm(page.cdm.get());
    }
    bool plays = kr.PlaysTo5s();
    std::string route = cdm_first ? "CDM at creation" : "CDM after the request";
    Check(page.sessions.size() == 1 && page.messages == 2 &&
              page.message_types.back() == fp::MessageType::kLicenseRequest && page.updates_ok == 2,
          route + ": the earlier session sends the asset's request as a second license request");
    Check(plays, route + ": protected HLS plays");
  }
}

// Closing a session before it answered leaves its loading request pending,
// as WebKit leaves a closed session's key requests: AVFoundation doesn't ask
// again (no second encrypted event) and playback waits.
void KeysClose() {
  std::printf("-- FairPlay HLS keys: session closed before its answer\n");
  KeyPage page(kSingleKeyToken);
  KeyRig kr(&page);
  kr.Load(kSingleKeyMaster, nullptr);
  kr.Play();
  WaitFor([&] { return !page.needs.empty(); }, 20);
  page.Create();
  OnOwner([&] {
    kr.keys->SetCdm(page.cdm.get());
    page.hold_messages = true;
    page.GenerateOnOwner(kSkd);
  });
  WaitFor([&] { return !page.held.empty(); }, 15);
  OnOwner([&] {
    page.hold_messages = false;
    page.on_need = [&](const std::string& uri) { page.GenerateOnOwner(uri); };
    page.cdm->CloseSession(page.held.front(), [](const fp::Result&) {});
  });
  WaitFor([] { return false; }, 8);
  std::printf("   clock %.2f s, encrypted events %zu, errors %d\n", kr.rig.Time(), page.needs.size(),
              kr.rig.client.errors);
  Check(page.needs.size() == 1 && page.updates_ok == 0 && kr.rig.client.errors == 0,
        "the request stays pending after the close: no second encrypted event, no error");
  Check(kr.rig.Time() < 0.5, "playback waits for the key");
}

// Legacy WebKitMediaKeys sessions: {"skd", "contentId"} names the SPC by the
// page's content ID (here the URI, which Axinom's service expects).
void KeysLegacy() {
  std::printf("-- FairPlay HLS keys: legacy content ID\n");
  KeyPage page(kSingleKeyToken);
  KeyRig kr(&page);
  kr.Load(kSingleKeyMaster, nullptr);
  kr.Play();
  WaitFor([&] { return !page.needs.empty(); }, 20);
  page.Create();
  NSString* content_id = [[NSData dataWithBytes:kSkd.data() length:kSkd.size()] base64EncodedStringWithOptions:0];
  std::string init_data = std::string("{\"skd\": \"") + kSkd + "\", \"contentId\": \"" + content_id.UTF8String + "\"}";
  OnOwner([&] {
    kr.keys->SetCdm(page.cdm.get());
    page.GenerateOnOwner(init_data);
  });
  bool plays = kr.PlaysTo5s();
  Check(page.updates_ok == 1 && page.Usable(kSkd), "the legacy session licenses the held request");
  Check(plays, "protected HLS plays");
}

// WebKit's order (MediaPlayerPrivateAVFoundation::updateStates): HAVE_METADATA
// from the asset before the item is on the player; a seek made then waits for
// the item and lands; the natural size follows from the item.
void MetadataFirst() {
  std::printf("-- metadata from the asset before the item (WebKit's order)\n");
  Rig rig;
  Rig* r = &rig;
  bool item_on_player = true;
  int seek_result = -1;
  int* seek = &seek_result;
  rig.client.on_metadata = [r, &item_on_player, seek] {
    item_on_player = fp::HlsPlayerAVPlayer(r->player->impl()).currentItem != nil;
    r->player->Seek(10, [seek](bool finished) { *seek = finished; });
  };
  Check(rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/manifest.m3u8")).ok(), "Load");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata && !item_on_player,
        "HAVE_METADATA comes from the asset before the item is on the player");
  Check(rig.client.metadata && rig.client.metadata->duration > 0 && !rig.client.metadata->is_live &&
            rig.client.metadata->loaded.empty(),
        "the asset's duration, nothing buffered yet");
  WaitFor([&] { return seek_result != -1; }, 20);
  Check(seek_result == 1 && std::fabs(rig.Time() - 10) < 0.1,
        "a seek made before the item was ready waits for it and lands");
  Check(WaitFor([&] { return rig.client.width > 0; }, 10), "the natural size follows from the item");
  Check(rig.client.errors == 0, "no error");
}

// A legacy page's order (WebKitMediaKeys made before the load, attached only
// once readyState reaches HAVE_METADATA, a session made at webkitneedkey):
// Safari reports HAVE_METADATA from the asset before the item exists, so the
// keys are attached before any key request, and the session made then (with a
// player behind it) licenses the request. A session made before the keys are
// attached would have no player and never answer, as in WebKit.
void KeysLegacyOrder() {
  std::printf("-- FairPlay HLS keys: legacy page order (attach at loadedmetadata, session at webkitneedkey)\n");
  KeyPage page(kSingleKeyToken);
  page.Create();
  KeyRig kr(&page);
  KeyRig* krp = &kr;
  KeyPage* pagep = &page;
  NSString* content_id = [[NSData dataWithBytes:kSkd.data() length:kSkd.size()] base64EncodedStringWithOptions:0];
  std::string init_data = std::string("{\"skd\": \"") + kSkd + "\", \"contentId\": \"" + content_id.UTF8String + "\"}";
  bool item_before_metadata = false;
  bool request_before_metadata = false;
  bool request_before_attach = false;
  bool attached = false;
  int requests = 0;
  kr.rig.client.on_metadata = [&, krp, pagep] {
    item_before_metadata = fp::HlsPlayerAVPlayer(krp->rig.player->impl()).currentItem != nil;
    // The page's loadedmetadata handler runs later, as a task.
    bool* attached_flag = &attached;
    dispatch_async(Owner(), ^{
      krp->keys->SetCdm(pagep->cdm.get());
      *attached_flag = true;
    });
  };
  page.on_loading_request = [&, pagep](const std::string&) {
    request_before_metadata |= krp->rig.client.metadata_count == 0;
    request_before_attach |= !attached;
    if (requests++ == 0) {
      std::string data = init_data;
      dispatch_async(Owner(), ^{
        pagep->GenerateOnOwner(data);
      });
    }
  };
  kr.Load(kSingleKeyMaster, nullptr);
  kr.Play();
  bool plays = kr.PlaysTo5s();
  Check(!item_before_metadata, "HAVE_METADATA comes before the item is on the player");
  Check(!page.loading_requests.empty() && !request_before_metadata && !request_before_attach,
        "webkitneedkey comes after loadedmetadata and the keys' attach");
  Check(page.sessions.size() == 1 && page.updates_ok == 1 && page.Usable(kSkd),
        "the session made at webkitneedkey licenses the request");
  Check(plays, "protected HLS plays");
}

// AirPlay (WebKit's setWirelessPlaybackTarget / setShouldPlayToPlaybackTarget
// / setWirelessVideoPlaybackDisabled). The browser names its route picker's
// AVOutputContext by ID; the media server knows it, so the player finds it
// from any process (the harness uses its own iTunes audio context, the one
// WebKit's AVRoutePickerViewTargetPicker uses). With no device picked in it,
// AVPlayer stays local and nothing reports wireless; that it becomes wireless
// once a device is picked needs an AirPlay receiver.
void AirPlay() {
  std::printf("-- AirPlay target and disabled flag\n");
  id context = [NSClassFromString(@"AVOutputContext") valueForKey:@"iTunesAudioContext"];
  NSString* context_id = [context valueForKey:@"contextID"];
  Check(context_id.length > 0, "this macOS has the AVOutputContext SPI (iTunes audio context)");
  if (!context_id.length) {
    return;
  }
  const std::string id_string = context_id.UTF8String;
  Rig rig;
  // Set before the player exists: applied when it is made.
  OnOwner([&] { rig.player->SetPlaybackTarget(id_string, true); });
  Check(rig.Load(Fake("media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/manifest.m3u8")).ok(), "Load");
  bool ready = WaitFor([&] { return rig.client.metadata_count > 0 || rig.client.errors; }, 20);
  Check(ready && rig.client.metadata, "metadata");
  auto output_context_id = [&] {
    NSString* result = nil;
    OnOwner([&] { result = [[fp::HlsPlayerAVPlayer(rig.player->impl()) valueForKey:@"outputContext"] valueForKey:@"contextID"]; });
    return result;
  };
  auto allows_external = [&] {
    BOOL result = NO;
    OnOwner([&] { result = fp::HlsPlayerAVPlayer(rig.player->impl()).allowsExternalPlayback; });
    return result;
  };
  Check([output_context_id() isEqualToString:context_id], "a target set before the player is on it once made");
  Check(allows_external(), "external playback allowed by default (WebKit's m_allowsWirelessVideoPlayback)");
  OnOwner([&] { rig.player->SetRate(1); });
  Check(WaitFor([&] { return rig.Time() > 2; }, 20), "plays locally while the context has no device");
  Check(rig.client.wireless_changes.empty(), "not wireless without a device: nothing reported");
  OnOwner([&] { rig.player->SetPlaybackTarget(id_string, false); });
  // Once ours is off, AVPlayer answers a default context of its own.
  auto ours = [&] { return [output_context_id() isEqualToString:context_id]; };
  Check(!ours(), "should-play off takes the context off the player");
  OnOwner([&] { rig.player->SetPlaybackTarget(id_string, true); });
  Check([output_context_id() isEqualToString:context_id], "and on again");
  OnOwner([&] { rig.player->SetPlaybackTarget("00000000-0000-0000-0000-000000000000", true); });
  // Not the context-less object outputContextForID answers for it.
  Check(!ours() && output_context_id().length > 0, "an ID the media server doesn't know plays locally");
  OnOwner([&] { rig.player->SetPlaybackTarget("", true); });
  OnOwner([&] { rig.player->SetPlaybackTarget(id_string, true); });
  OnOwner([&] { rig.player->SetPlaybackTarget("", true); });
  Check(!ours(), "no target: the context comes off");
  OnOwner([&] { rig.player->SetWirelessVideoPlaybackDisabled(true); });
  Check(!allows_external(), "disabled (x-webkit-airplay=deny): allowsExternalPlayback NO");
  OnOwner([&] { rig.player->SetWirelessVideoPlaybackDisabled(false); });
  Check(allows_external(), "enabled again");
  double before = rig.Time();
  Check(WaitFor([&] { return rig.Time() > before + 1; }, 10), "still playing after the target changes");
  Check(rig.client.errors == 0 && rig.client.wireless_changes.empty(), "no error, never wireless");
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
        {"timeline", Timeline}, {"ts", VodTs}, {"fmp4", VodFmp4}, {"live", Live}, {"missing", Missing}, {"http", PlainHttp}, {"bad-url", BadUrl}, {"data-url", DataUrl}, {"data-url-video", DataUrlVideo}, {"skd", Skd}, {"skd-handler", SkdHandler}, {"teardown", Teardown},
        {"keys-session-failure", KeysSessionFailure}, {"keys-first", KeysMediaKeysFirst}, {"keys-loader", KeysLoaderRoute},
        {"keys-attach-at-request", KeysAttachAtRequest}, {"keys-multikey", KeysMultiKey},
        {"keys-await", KeysAwait}, {"keys-early", KeysEarlySession},
        {"keys-close", KeysClose}, {"keys-legacy", KeysLegacy}, {"metadata-first", MetadataFirst},
        {"keys-legacy-order", KeysLegacyOrder}, {"airplay", AirPlay}};
    for (auto& [name, run] : scenarios) {
      if (only.empty() || only == name) {
        run();
      }
    }
    std::printf("%s (%d failures)\n", g_failures ? "FAILED" : "ALL PASSED", g_failures);
    return g_failures ? 1 : 0;
  }
}

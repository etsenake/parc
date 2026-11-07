#include "fairplay_hls_player.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#include <dlfcn.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <map>
#include <mutex>
#include <set>

#include "fairplay_hls_frame_stats.h"
#include "fairplay_hls_player_internal.h"
#include "fairplay_hls_timeline.h"

using parc::fairplay::FairPlayHlsPlayer;
using parc::fairplay::HlsError;
using parc::fairplay::HlsLoad;
using parc::fairplay::HlsLoadClient;
using parc::fairplay::HlsLoadRequest;
using parc::fairplay::HlsLoadResponse;
using parc::fairplay::HlsMetadata;
using parc::fairplay::HlsSeekableRangeInput;
using parc::fairplay::HlsSeekableWindow;
using parc::fairplay::HlsStartDate;
using parc::fairplay::HlsTime;
using parc::fairplay::HlsTimeKind;
using parc::fairplay::HlsTimeline;
using parc::fairplay::HlsTimeRange;
using parc::fairplay::PostTask;

// AVFoundation SPI WebKit declares in AVFoundationSPI.h: the resource loader's
// URL session, and the delegate and queue AVFoundation wants that session to
// report to.
@interface AVAssetResourceLoader (ParcClientURLLoading)
@property(nonatomic, readonly) id<NSURLSessionDataDelegate> URLSessionDataDelegate;
@property(nonatomic, readonly) NSOperationQueue* URLSessionDataDelegateQueue;
@property(nonatomic, strong) NSURLSession* URLSession;
@end

namespace {

// AVFoundation SPI that WebKit uses for the same purpose
// (MediaPlayerPrivateAVFoundationObjC::createAVAssetForURL): the asset loads
// only through the URL session set on its resource loader.
NSString* ClientURLLoadingOnlyKey() {
  static NSString* key = [] () -> NSString* {
    void* symbol = dlsym(RTLD_DEFAULT, "AVURLAssetUseClientURLLoadingExclusively");
    return symbol ? *static_cast<NSString* __unsafe_unretained*>(symbol) : nil;
  }();
  return key;
}

// The element's <source type>, as WebKit passes it (SPI; skipped if absent).
NSString* OutOfBandMIMETypeKey() {
  static NSString* key = [] () -> NSString* {
    void* symbol = dlsym(RTLD_DEFAULT, "AVURLAssetOutOfBandMIMETypeKey");
    return symbol ? *static_cast<NSString* __unsafe_unretained*>(symbol) : nil;
  }();
  return key;
}

bool ResourceLoaderTakesURLSession() {
  return [AVAssetResourceLoader instancesRespondToSelector:@selector(setURLSession:)] &&
         [AVAssetResourceLoader instancesRespondToSelector:@selector(URLSessionDataDelegate)] &&
         [AVAssetResourceLoader instancesRespondToSelector:@selector(URLSessionDataDelegateQueue)];
}

std::vector<HlsTimeRange> Ranges(NSArray<NSValue*>* values) {
  std::vector<HlsTimeRange> ranges;
  for (NSValue* value in values) {
    CMTimeRange range = value.CMTimeRangeValue;
    if (!CMTIMERANGE_IS_VALID(range) || CMTIMERANGE_IS_EMPTY(range)) {
      continue;
    }
    double start = CMTimeGetSeconds(range.start);
    double end = CMTimeGetSeconds(CMTimeRangeGetEnd(range));
    if (std::isfinite(start) && std::isfinite(end) && end > start) {
      ranges.push_back({start, end});
    }
  }
  return ranges;
}

// nil for bytes that aren't UTF-8 (|@(c_str)| would be nil too, and a nil
// in a dictionary literal throws).
NSString* NSStringOrNil(const std::string& value) {
  return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
}

// A CMTime as WebKit's platformDuration tells them apart.
HlsTime TimeOf(CMTime time) {
  if (CMTIME_IS_NUMERIC(time)) {
    return {HlsTimeKind::kNumeric, CMTimeGetSeconds(time)};
  }
  if (CMTIME_IS_INDEFINITE(time)) {
    return {HlsTimeKind::kIndefinite, 0};
  }
  return {HlsTimeKind::kInvalid, 0};
}

// seekableTimeRanges as WebKit's platformMin/MaxTimeSeekable read them.
std::vector<HlsSeekableRangeInput> SeekableInputs(NSArray<NSValue*>* values) {
  std::vector<HlsSeekableRangeInput> inputs;
  for (NSValue* value in values) {
    CMTimeRange range = value.CMTimeRangeValue;
    inputs.push_back({static_cast<bool>(CMTIMERANGE_IS_VALID(range)),
                      static_cast<bool>(CMTIMERANGE_IS_EMPTY(range)), CMTimeGetSeconds(range.start),
                      CMTimeGetSeconds(CMTimeRangeGetEnd(range))});
  }
  return inputs;
}

std::vector<HlsTimeRange> RangesOf(const std::vector<HlsSeekableWindow>& windows) {
  std::vector<HlsTimeRange> ranges;
  for (const HlsSeekableWindow& window : windows) {
    ranges.push_back({window.start, window.end});
  }
  return ranges;
}

std::optional<double> Milliseconds(const std::optional<double>& seconds) {
  if (!seconds) {
    return std::nullopt;
  }
  return *seconds * 1000.0;
}

// net::ERR_* values the embedder reports, mapped onto the NSURLError codes
// AVFoundation expects from a URL session.
NSInteger URLErrorCode(int net_error) {
  switch (net_error) {
    case -3:    // ERR_ABORTED
      return NSURLErrorCancelled;
    case -7:    // ERR_TIMED_OUT
    case -118:  // ERR_CONNECTION_TIMED_OUT
      return NSURLErrorTimedOut;
    case -105:  // ERR_NAME_NOT_RESOLVED
      return NSURLErrorCannotFindHost;
    case -106:  // ERR_INTERNET_DISCONNECTED
      return NSURLErrorNotConnectedToInternet;
    case -102:  // ERR_CONNECTION_REFUSED
      return NSURLErrorCannotConnectToHost;
    case -101:  // ERR_CONNECTION_RESET
    case -100:  // ERR_CONNECTION_CLOSED
      return NSURLErrorNetworkConnectionLost;
    case -301:  // ERR_DISALLOWED_URL_SCHEME
    case -302:  // ERR_UNKNOWN_URL_SCHEME
      return NSURLErrorUnsupportedURL;
    case -310:  // ERR_TOO_MANY_REDIRECTS
      return NSURLErrorHTTPTooManyRedirects;
    case -20:   // ERR_BLOCKED_BY_CLIENT
    case -27:   // ERR_BLOCKED_BY_RESPONSE
    case -10:   // ERR_ACCESS_DENIED
      return NSURLErrorNoPermissionsToReadFile;
    default:
      return NSURLErrorUnknown;
  }
}

}  // namespace

namespace parc::fairplay {
class HlsTaskBridge;
}

@class PCHlsURLSession;

// What AVFoundation sees as an NSURLSessionDataTask. AVFoundation only asks a
// task for these and calls resume/cancel (WebKit's WebCoreNSURLSessionDataTask
// covers the same surface).
@interface PCHlsDataTask : NSObject <NSCopying>
@property(nonatomic, readonly, weak) PCHlsURLSession* session;
@property(nonatomic, readonly) NSUInteger taskIdentifier;
@property(atomic, copy) NSURLRequest* originalRequest;
@property(atomic, copy) NSURLRequest* currentRequest;
@property(atomic, strong) NSURLResponse* response;
@property(atomic, strong) NSError* error;
@property(atomic, copy) NSString* taskDescription;
@property(atomic) NSURLSessionTaskState state;
@property(atomic) int64_t countOfBytesReceived;
@property(atomic) int64_t countOfBytesSent;
@property(atomic) int64_t countOfBytesExpectedToSend;
@property(atomic) int64_t countOfBytesExpectedToReceive;
@property(atomic) float priority;
@property(atomic, strong) NSDate* earliestBeginDate;
@property(atomic) int64_t countOfBytesClientExpectsToSend;
@property(atomic) int64_t countOfBytesClientExpectsToReceive;
@property(atomic, readonly) NSProgress* progress;
- (instancetype)initWithSession:(PCHlsURLSession*)session
                     identifier:(NSUInteger)identifier
                        request:(NSURLRequest*)request;
@end

// What AVFoundation sees as the asset's NSURLSession. Its tasks are loads on
// the embedder's HlsLoader, run on the player's owner sequence; results go to
// AVFoundation's data delegate on its delegate queue.
@interface PCHlsURLSession : NSObject <NSCopying>
- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster
                    delegate:(id<NSURLSessionDataDelegate>)delegate
                       queue:(NSOperationQueue*)queue;
- (void)deliver:(void (^)(id<NSURLSessionDataDelegate> delegate))block;
- (void)taskFinished:(PCHlsDataTask*)task;
- (void)invalidate;
@property(nonatomic, readonly) std::weak_ptr<FairPlayHlsPlayer::Impl> impl;
@property(nonatomic, readonly) std::shared_ptr<const PostTask> poster;
@end

// Answers skd:// requests (AVFoundation can't load the scheme); everything
// else is loaded through the URL session.
@interface PCHlsResourceLoaderDelegate : NSObject <AVAssetResourceLoaderDelegate>
- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster;
@end

// KVO and notifications of the player and its item, posted to the owner
// sequence.
@interface PCHlsObserver : NSObject
- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster;
- (void)observePlayer:(AVPlayer*)player item:(AVPlayerItem*)item;
- (void)stop;
@end

namespace parc::fairplay {

class FairPlayHlsPlayer::Impl : public std::enable_shared_from_this<FairPlayHlsPlayer::Impl> {
 public:
  Impl(HlsPlayerClient* client, HlsLoader* loader, PostTask post_task)
      : client_(client),
        loader_(loader),
        poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() { Shutdown(); }

  void Shutdown() {
    if (shut_down_) {
      return;
    }
    shut_down_ = true;
    frame_stats_.reset();
    key_handler_ = nullptr;
    [observer_ stop];
    observer_ = nil;
    for (auto& [identifier, load] : loads_) {
      load->MarkFinished();
    }
    loads_.clear();
    finished_loads_.clear();
    [session_ invalidate];
    for (auto& [uri, requests] : key_requests_) {
      for (AVAssetResourceLoadingRequest* request in requests) {
        [request finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                            code:NSURLErrorCancelled
                                                        userInfo:nil]];
      }
    }
    key_requests_.clear();
    [player_ pause];
    [player_ replaceCurrentItemWithPlayerItem:nil];
    [asset_.resourceLoader setDelegate:nil queue:nil];
    [asset_ cancelLoading];
    if (player_layer_) {
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      player_layer_.player = nil;
      [CATransaction commit];
    }
  }

  Result CreateAsset(const std::string& url, const std::string& mime_type) {
    if (asset_ || shut_down_) {
      return Result::Error(Exception::kInvalidState, "already loading");
    }
    if (!FairPlayHlsPlayer::IsSupported()) {
      return Result::Error(Exception::kNotSupported, "client URL loading is unavailable");
    }
    NSString* url_string = NSStringOrNil(url);
    NSURL* ns_url = url_string ? [NSURL URLWithString:url_string] : nil;
    NSString* scheme = ns_url.scheme.lowercaseString;
    if (!ns_url || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) {
      return Result::Error(Exception::kNotSupported, "not an http(s) URL");
    }
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    options[ClientURLLoadingOnlyKey()] = @YES;
    // WebKit's restrictions: a remote playlist can't name local files.
    options[AVURLAssetReferenceRestrictionsKey] =
        @(AVAssetReferenceRestrictionForbidRemoteReferenceToLocal |
          AVAssetReferenceRestrictionForbidLocalReferenceToRemote);
    NSString* ns_mime_type = NSStringOrNil(mime_type);
    if (ns_mime_type.length && OutOfBandMIMETypeKey()) {
      options[OutOfBandMIMETypeKey()] = ns_mime_type;
    }
    asset_ = [AVURLAsset URLAssetWithURL:ns_url options:options];
    if (!asset_) {
      return Result::Error(Exception::kNotSupported, "AVURLAsset refused the URL");
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    AVAssetResourceLoader* resource_loader = asset_.resourceLoader;
    id<NSURLSessionDataDelegate> data_delegate = resource_loader.URLSessionDataDelegate;
    NSOperationQueue* data_queue = resource_loader.URLSessionDataDelegateQueue;
    if (!data_delegate || !data_queue) {
      asset_ = nil;
      return Result::Error(Exception::kNotSupported, "no URL session delegate");
    }
    session_ = [[PCHlsURLSession alloc] initWithImpl:weak
                                              poster:poster_
                                            delegate:data_delegate
                                               queue:data_queue];
    resource_loader.URLSession = (NSURLSession*)session_;
    loader_delegate_ = [[PCHlsResourceLoaderDelegate alloc] initWithImpl:weak poster:poster_];
    [resource_loader setDelegate:loader_delegate_ queue:DelegateQueue()];
    return Result::Ok();
  }

  Result Start() {
    if (!asset_ || item_ || shut_down_) {
      return Result::Error(Exception::kInvalidState, asset_ ? "already started" : "no asset");
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    item_ = [AVPlayerItem playerItemWithAsset:asset_];
    // WebKit's setting: the page, not AVFoundation, schedules HLS interstitials.
    item_.automaticallyHandlesInterstitialEvents = NO;
    UpdatePitchAlgorithm();
    player_ = [AVPlayer playerWithPlayerItem:item_];
    // WebKit's settings: the page picks media options, the browser manages
    // display sleep, and there's no AirPlay route from here.
    player_.appliesMediaSelectionCriteriaAutomatically = NO;
    player_.preventsDisplaySleepDuringVideoPlayback = NO;
    player_.allowsExternalPlayback = NO;
    player_.volume = volume_;
    player_.muted = muted_;
    observer_ = [[PCHlsObserver alloc] initWithImpl:weak poster:poster_];
    [observer_ observePlayer:player_ item:item_];
    // A rate set before the player existed (play() before the item) applies
    // now, as volume, mute and pitch do.
    if (rate_ > 0) {
      SetRate(rate_);
    }
    return Result::Ok();
  }

  void SetRate(double rate) {
    rate_ = rate;
    UpdateFrameStats();
    if (!player_) {
      return;
    }
    UpdatePitchAlgorithm();
    if (rate > 0) {
      player_.defaultRate = static_cast<float>(rate);
      player_.rate = static_cast<float>(rate);
    } else {
      [player_ pause];
    }
  }

  void Seek(double seconds, double tolerance_before, std::function<void(bool)> done) {
    // AVFoundation throws on a seek with a completion handler before the
    // item is ready to play (or after it failed).
    if (shut_down_ || !item_ || !reported_metadata_ || item_.status != AVPlayerItemStatusReadyToPlay) {
      std::weak_ptr<Impl> weak = weak_from_this();
      (*poster_)([weak, done = std::move(done)] {
        if (weak.lock()) {
          done(false);
        }
      });
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    auto shared_done = std::make_shared<std::function<void(bool)>>(std::move(done));
    // AVFoundation throws on a negative tolerance.
    CMTime before = kCMTimeZero;
    if (std::isinf(tolerance_before) && tolerance_before > 0) {
      before = kCMTimePositiveInfinity;
    } else if (tolerance_before > 0) {
      before = CMTimeMakeWithSeconds(tolerance_before, 90000);
    }
    [item_ seekToTime:CMTimeMakeWithSeconds(seconds, 90000)
        toleranceBefore:before
         toleranceAfter:kCMTimeZero
      completionHandler:^(BOOL finished) {
        (*poster)([weak, shared_done, finished] {
          if (weak.lock()) {
            (*shared_done)(finished);
          }
        });
      }];
  }

  void SetVolume(float volume) {
    volume_ = volume;
    player_.volume = volume;
  }

  void SetMuted(bool muted) {
    muted_ = muted;
    player_.muted = muted;
  }

  void SetPreservesPitch(bool preserves_pitch) {
    preserves_pitch_ = preserves_pitch;
    UpdatePitchAlgorithm();
  }

  // MediaSessionManagerCocoa::audioTimePitchAlgorithmForMediaPlayerPitchCorrectionAlgorithm.
  void UpdatePitchAlgorithm() {
    if (!item_) {
      return;
    }
    item_.audioTimePitchAlgorithm = (!preserves_pitch_ || rate_ == 0 || rate_ == 1)
                                        ? AVAudioTimePitchAlgorithmVarispeed
                                        : AVAudioTimePitchAlgorithmSpectral;
  }

  double CurrentTime() const {
    std::lock_guard<std::mutex> lock(timebase_lock_);
    if (!timebase_) {
      return 0;
    }
    double time = CMTimeGetSeconds(CMTimebaseGetTime(timebase_));
    return std::isfinite(time) ? time : 0;
  }

  double Rate() const {
    std::lock_guard<std::mutex> lock(timebase_lock_);
    return timebase_ ? CMTimebaseGetRate(timebase_) : 0;
  }

  // Loads (from PCHlsURLSession, on the owner sequence).

  class TaskLoad : public HlsLoadClient {
   public:
    TaskLoad(Impl* impl, PCHlsDataTask* task) : impl_(impl), task_(task) {}

    PCHlsDataTask* task() const { return task_; }
    void MarkFinished() { finished_ = true; }

    void Start(HlsLoader* loader) {
      HlsLoadRequest request;
      NSURLRequest* ns_request = task_.originalRequest;
      request.url = ns_request.URL.absoluteString.UTF8String ?: "";
      request.method = ns_request.HTTPMethod.UTF8String ?: "GET";
      NSDictionary<NSString*, NSString*>* fields = ns_request.allHTTPHeaderFields;
      for (NSString* name in fields) {
        request.headers.emplace_back(name.UTF8String ?: "", fields[name].UTF8String ?: "");
      }
      load_ = loader->StartLoad(request, this);
    }

    void OnResponse(const HlsLoadResponse& response) override {
      if (finished_ || responded_) {
        return;
      }
      responded_ = true;
      NSString* final_url = NSStringOrNil(response.final_url);
      NSURL* url = final_url.length ? [NSURL URLWithString:final_url] : nil;
      if (!url) {
        url = task_.originalRequest.URL;
      }
      NSMutableDictionary* headers = [NSMutableDictionary dictionary];
      for (const auto& [name, value] : response.headers) {
        NSString* ns_name = NSStringOrNil(name);
        NSString* ns_value = NSStringOrNil(value);
        if (ns_name.length && ns_value) {
          headers[ns_name] = ns_value;
        }
      }
      if (NSString* mime = NSStringOrNil(response.mime_type); mime.length) {
        headers[@"Content-Type"] = mime;
      }
      if (response.content_length >= 0) {
        headers[@"Content-Length"] = [NSString stringWithFormat:@"%lld", response.content_length];
      }
      NSHTTPURLResponse* ns_response = [[NSHTTPURLResponse alloc] initWithURL:url
                                                                   statusCode:response.http_status
                                                                  HTTPVersion:@"HTTP/1.1"
                                                                 headerFields:headers];
      if (![url isEqual:task_.originalRequest.URL]) {
        NSMutableURLRequest* current = [task_.originalRequest mutableCopy];
        current.URL = url;
        task_.currentRequest = current;
      }
      task_.response = ns_response;
      task_.countOfBytesExpectedToReceive = response.content_length;
      PCHlsDataTask* task = task_;
      std::weak_ptr<Impl> weak = impl_->weak_from_this();
      std::shared_ptr<const PostTask> poster = impl_->poster_;
      NSUInteger identifier = task.taskIdentifier;
      // Like a real session, nothing more is delivered until AVFoundation
      // allows the response; data that arrives meanwhile is held.
      [impl_->session_ deliver:^(id<NSURLSessionDataDelegate> delegate) {
        if (![delegate respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)]) {
          (*poster)([weak, identifier] {
            if (auto impl = weak.lock()) {
              impl->OnResponseDisposition(identifier, true);
            }
          });
          return;
        }
        [delegate URLSession:(NSURLSession*)task.session
                      dataTask:(NSURLSessionDataTask*)task
            didReceiveResponse:ns_response
             completionHandler:^(NSURLSessionResponseDisposition disposition) {
               bool allow = disposition != NSURLSessionResponseCancel;
               (*poster)([weak, identifier, allow] {
                 if (auto impl = weak.lock()) {
                   impl->OnResponseDisposition(identifier, allow);
                 }
               });
             }];
      }];
    }

    // AVFoundation's answer to the response: deliver what was held, and a
    // completion that arrived meanwhile.
    void Allow() {
      if (finished_ || allowed_) {
        return;
      }
      allowed_ = true;
      if (held_.length) {
        DeliverData(held_);
        held_ = nil;
      }
      if (held_completion_) {
        OnComplete(*held_completion_);
      }
    }

    void OnData(const uint8_t* data, size_t size) override {
      if (finished_ || !responded_ || size == 0) {
        return;
      }
      if (!allowed_) {
        if (!held_) {
          held_ = [NSMutableData data];
        }
        [held_ appendBytes:data length:size];
        return;
      }
      DeliverData([NSData dataWithBytes:data length:size]);
    }

    void DeliverData(NSData* chunk) {
      size_t size = chunk.length;
      task_.countOfBytesReceived = task_.countOfBytesReceived + static_cast<int64_t>(size);
      impl_->status_.bytes_received += static_cast<int64_t>(size);
      PCHlsDataTask* task = task_;
      [impl_->session_ deliver:^(id<NSURLSessionDataDelegate> delegate) {
        [delegate URLSession:(NSURLSession*)task.session
                    dataTask:(NSURLSessionDataTask*)task
              didReceiveData:chunk];
      }];
    }

    void OnComplete(int net_error) override {
      if (finished_) {
        return;
      }
      if (responded_ && !allowed_) {
        held_completion_ = net_error;
        return;
      }
      NSError* error = nil;
      if (net_error != 0) {
        error = [NSError errorWithDomain:NSURLErrorDomain
                                    code:URLErrorCode(net_error)
                                userInfo:@{@"ParcNetError" : @(net_error),
                                           NSURLErrorFailingURLErrorKey : task_.originalRequest.URL}];
        impl_->status_.loads_failed++;
      } else {
        impl_->status_.loads_completed++;
      }
      impl_->FinishLoad(task_, error);
    }

   private:
    Impl* impl_;
    PCHlsDataTask* task_;
    std::unique_ptr<HlsLoad> load_;
    bool responded_ = false;
    bool allowed_ = false;
    bool finished_ = false;
    NSMutableData* held_ = nil;
    std::optional<int> held_completion_;
  };

  void StartLoad(PCHlsDataTask* task) {
    if (shut_down_ || loads_.count(task.taskIdentifier)) {
      return;
    }
    status_.loads_started++;
    auto load = std::make_unique<TaskLoad>(this, task);
    TaskLoad* raw = load.get();
    loads_[task.taskIdentifier] = std::move(load);
    raw->Start(loader_);
  }

  void OnResponseDisposition(NSUInteger identifier, bool allow) {
    auto it = loads_.find(identifier);
    if (it == loads_.end()) {
      return;
    }
    if (allow) {
      it->second->Allow();
    } else {
      CancelLoad(identifier);
    }
  }

  void CancelLoad(NSUInteger identifier) {
    auto it = loads_.find(identifier);
    if (it == loads_.end()) {
      return;
    }
    status_.loads_cancelled++;
    PCHlsDataTask* task = it->second->task();
    FinishLoad(task, [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorCancelled
                                     userInfo:@{NSURLErrorFailingURLErrorKey : task.originalRequest.URL}]);
  }

  // Completes |task| for AVFoundation. Its TaskLoad (if any) stops reporting
  // and is destroyed in a later task, which cancels a load still in flight:
  // the loader may be inside a call to the TaskLoad right now.
  void FinishLoad(PCHlsDataTask* task, NSError* error) {
    task.error = error;
    task.state = NSURLSessionTaskStateCompleted;
    [session_ taskFinished:task];
    [session_ deliver:^(id<NSURLSessionDataDelegate> delegate) {
      if ([delegate respondsToSelector:@selector(URLSession:task:didCompleteWithError:)]) {
        [delegate URLSession:(NSURLSession*)task.session
                        task:(NSURLSessionTask*)task
        didCompleteWithError:error];
      }
    }];
    auto it = loads_.find(task.taskIdentifier);
    if (it == loads_.end()) {
      return;
    }
    it->second->MarkFinished();
    finished_loads_.push_back(std::move(it->second));
    loads_.erase(it);
    if (finished_loads_.size() == 1) {
      std::weak_ptr<Impl> weak = weak_from_this();
      (*poster_)([weak] {
        if (auto impl = weak.lock()) {
          impl->finished_loads_.clear();
        }
      });
    }
  }

  // Keys (from PCHlsResourceLoaderDelegate, on the owner sequence).

  void OnKeyRequest(AVAssetResourceLoadingRequest* request) {
    if (shut_down_) {
      [request finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                          code:NSURLErrorCancelled
                                                      userInfo:nil]];
      return;
    }
    status_.key_requests++;
    if (key_handler_ && IsSkdRequest(request)) {
      key_handler_->HandleLoadingRequest(request);
      return;
    }
    std::string uri = request.request.URL.absoluteString.UTF8String ?: "";
    if (auto key = fulfilled_keys_.find(uri); key != fulfilled_keys_.end()) {
      FulfillWithKey(request, key->second);
      return;
    }
    NSMutableArray<AVAssetResourceLoadingRequest*>* pending = key_requests_[uri];
    if (!pending) {
      pending = [NSMutableArray array];
      key_requests_[uri] = pending;
    }
    [pending addObject:request];
    // Every request, repeats of a URI included, as WebKit's keyNeeded
    // (shouldWaitForLoadingOfResource): each one raises webkitneedkey.
    client_->OnKeyRequest(uri);
  }

  void OnKeyRequestCancelled(AVAssetResourceLoadingRequest* request) {
    if (key_handler_ && IsSkdRequest(request)) {
      key_handler_->HandleCancelledLoadingRequest(request);
      return;
    }
    std::string uri = request.request.URL.absoluteString.UTF8String ?: "";
    auto it = key_requests_.find(uri);
    if (it != key_requests_.end()) {
      [it->second removeObject:request];
      if (it->second.count == 0) {
        key_requests_.erase(it);
      }
    }
  }

  void FulfillKeyRequests(const std::string& uri, const std::vector<uint8_t>& key) {
    if (uri.empty() || key.empty()) {
      return;
    }
    fulfilled_keys_[uri] = key;
    auto it = key_requests_.find(uri);
    if (it == key_requests_.end()) {
      return;
    }
    NSArray<AVAssetResourceLoadingRequest*>* requests = it->second;
    key_requests_.erase(it);
    for (AVAssetResourceLoadingRequest* request in requests) {
      FulfillWithKey(request, key);
    }
  }

  void FailKeyRequests(const std::string& uri, const std::string& message) {
    auto it = key_requests_.find(uri);
    if (it == key_requests_.end()) {
      return;
    }
    NSError* error = [NSError errorWithDomain:@"ParcFairPlayHls"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey : NSStringOrNil(message) ?: @"key request failed"}];
    for (AVAssetResourceLoadingRequest* request in it->second) {
      [request finishLoadingWithError:error];
    }
    key_requests_.erase(it);
  }

  // Observations (from PCHlsObserver, on the owner sequence).

  void OnItemStatus() {
    if (shut_down_ || !item_) {
      return;
    }
    if (item_.status == AVPlayerItemStatusFailed) {
      ReportFailure(item_.error);
      return;
    }
    if (item_.status != AVPlayerItemStatusReadyToPlay || reported_metadata_) {
      return;
    }
    reported_metadata_ = true;
    {
      std::lock_guard<std::mutex> lock(timebase_lock_);
      timebase_ = item_.timebase;
      if (timebase_) {
        CFRetain(timebase_);
      }
    }
    HlsMetadata metadata;
    for (AVPlayerItemTrack* track in item_.tracks) {
      AVAssetTrack* asset_track = track.assetTrack;
      NSString* type = asset_track.mediaType;
      id description = asset_track.formatDescriptions.firstObject;
      uint32_t fourcc =
          description ? CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)description) : 0;
      if ([type isEqualToString:AVMediaTypeVideo]) {
        metadata.has_video = true;
        if (!metadata.video_fourcc) {
          metadata.video_fourcc = fourcc;
        }
      } else if ([type isEqualToString:AVMediaTypeAudio]) {
        metadata.has_audio = true;
        if (!metadata.audio_fourcc) {
          metadata.audio_fourcc = fourcc;
        }
      }
    }
    CGSize size = item_.presentationSize;
    if (size.width > 0 && size.height > 0) {
      metadata.has_video = true;
      metadata.natural_width = static_cast<int32_t>(std::lround(size.width));
      metadata.natural_height = static_cast<int32_t>(std::lround(size.height));
    }
    if (!metadata.has_video && !metadata.has_audio) {
      // An HLS item with no track list yet: AVFoundation fills it in as it
      // plays. Video is assumed, as Safari's element does until it knows.
      metadata.has_video = true;
      metadata.has_audio = true;
    }
    natural_width_ = metadata.natural_width;
    natural_height_ = metadata.natural_height;
    timeline_.Start(TimeOf(item_.duration), SeekableInputs(item_.seekableTimeRanges), StartDate());
    metadata.duration = timeline_.duration();
    metadata.is_live = std::isinf(metadata.duration);
    metadata.start_date_ms = Milliseconds(timeline_.start_date());
    metadata.seekable = RangesOf(timeline_.SeekableRanges());
    metadata.loaded = Ranges(item_.loadedTimeRanges);
    client_->OnMetadata(metadata);
    // The client may have destroyed the player in OnMetadata.
    if (!shut_down_) {
      OnBuffering();
    }
  }

  void OnBuffering() {
    if (shut_down_ || !reported_metadata_ || !item_) {
      return;
    }
    bool have_enough = item_.playbackLikelyToKeepUp || item_.playbackBufferFull;
    if (!have_enough && !item_.playbackBufferEmpty && last_have_enough_.has_value()) {
      return;  // Between the two: keep the last state.
    }
    if (last_have_enough_ == have_enough) {
      return;
    }
    last_have_enough_ = have_enough;
    // The element's ready state follows: Safari's GPU process samples the
    // start date and the seekable window for the page then, and the page has
    // them before the ready-state events.
    std::optional<double> start_date = timeline_.start_date();
    std::optional<HlsSeekableWindow> window = timeline_.seekable();
    if (timeline_.ReadyStateChanged(StartDate())) {
      if (timeline_.start_date() != start_date) {
        client_->OnStartDateChange(Milliseconds(timeline_.start_date()));
      }
      if (!shut_down_ && timeline_.seekable() != window) {
        client_->OnSeekableRangesChange(RangesOf(timeline_.SeekableRanges()));
      }
      if (shut_down_) {
        return;
      }
    }
    client_->OnBufferingStateChange(have_enough);
  }

  void OnLoadedRanges() {
    if (!shut_down_ && reported_metadata_ && item_) {
      client_->OnLoadedRangesChange(Ranges(item_.loadedTimeRanges));
    }
  }

  void OnSeekableRanges() {
    if (!shut_down_ && reported_metadata_ && item_ &&
        timeline_.SeekableChanged(SeekableInputs(item_.seekableTimeRanges))) {
      client_->OnSeekableRangesChange(RangesOf(timeline_.SeekableRanges()));
    }
  }

  void OnDuration() {
    if (!shut_down_ && reported_metadata_ && item_ && timeline_.DurationChanged(TimeOf(item_.duration))) {
      client_->OnDurationChange(timeline_.duration());
    }
  }

  void OnPresentationSize() {
    if (shut_down_ || !reported_metadata_ || !item_) {
      return;
    }
    CGSize size = item_.presentationSize;
    int32_t width = static_cast<int32_t>(std::lround(size.width));
    int32_t height = static_cast<int32_t>(std::lround(size.height));
    if (width > 0 && height > 0 && (width != natural_width_ || height != natural_height_)) {
      natural_width_ = width;
      natural_height_ = height;
      client_->OnNaturalSizeChange(width, height);
    }
  }

  void OnEnded() {
    if (!shut_down_) {
      client_->OnEnded();
    }
  }

  // Counted while the rate is above 0 (WebKit reads the same counts, from its
  // AVPlayerLayer, whenever the page asks); stopping counts once more. At the
  // end AVFoundation pauses by itself, and readings that add nothing are
  // never reported, until the element pauses too.
  void UpdateFrameStats() {
    if (frame_stats_) {
      frame_stats_->SetPlaying(!shut_down_ && rate_ > 0);
    }
  }

  void OnFrameCounts(const FrameCountDelta& delta) {
    if (!shut_down_) {
      client_->OnVideoFrameCounts(delta.decoded, delta.dropped);
    }
  }

  void OnFailedToPlayToEnd(NSError* error) { ReportFailure(error); }

  // WebKit's getStartDate, in seconds.
  std::optional<double> StartDate() const {
    return HlsStartDate(item_.currentDate.timeIntervalSince1970, CMTimeGetSeconds(item_.currentTime));
  }

  void SetKeyRequestHandler(HlsKeyRequestHandler* handler) {
    if (!shut_down_) {
      key_handler_ = handler;
    }
  }

  void OnOutputObscured() {
    if (shut_down_ || !player_) {
      return;
    }
    bool obscured = player_.outputObscuredDueToInsufficientExternalProtection;
    if (obscured != output_obscured_) {
      output_obscured_ = obscured;
      client_->OnOutputObscuredChange(obscured);
    }
  }

  AVURLAsset* asset() const { return asset_; }
  AVPlayer* player() const { return player_; }

  AVPlayerLayer* PlayerLayer() {
    if (!player_layer_ && player_ && !shut_down_) {
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      player_layer_ = [AVPlayerLayer playerLayerWithPlayer:player_];
      player_layer_.videoGravity = AVLayerVideoGravityResize;
      [CATransaction commit];
      // Frame counts come from the layer (WebKit's source for an AVPlayer).
      std::weak_ptr<Impl> weak = weak_from_this();
      std::shared_ptr<const PostTask> poster = poster_;
      frame_stats_ = std::make_unique<HlsFrameStats>(
          player_layer_, [poster](std::function<void()> task) { (*poster)(std::move(task)); },
          [weak](const FrameCountDelta& delta) {
            if (std::shared_ptr<Impl> impl = weak.lock()) {
              impl->OnFrameCounts(delta);
            }
          });
      UpdateFrameStats();
    }
    return player_layer_;
  }

  FairPlayHlsPlayer::Status status() const { return status_; }

  static dispatch_queue_t DelegateQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("parc.fairplay.hls-resource-loader", DISPATCH_QUEUE_SERIAL);
    return queue;
  }

  void ReleaseTimebase() {
    std::lock_guard<std::mutex> lock(timebase_lock_);
    if (timebase_) {
      CFRelease(timebase_);
      timebase_ = nullptr;
    }
  }

 private:
  static bool IsSkdRequest(AVAssetResourceLoadingRequest* request) {
    return [request.request.URL.scheme.lowercaseString isEqualToString:@"skd"];
  }

  // WebKit's fulfillRequestWithKeyData: the requested range of the key.
  static void FulfillWithKey(AVAssetResourceLoadingRequest* request, const std::vector<uint8_t>& key) {
    long long length = static_cast<long long>(key.size());
    if (AVAssetResourceLoadingContentInformationRequest* info = request.contentInformationRequest) {
      info.contentLength = length;
      info.byteRangeAccessSupported = YES;
    }
    if (AVAssetResourceLoadingDataRequest* data = request.dataRequest) {
      long long start = data.currentOffset;
      long long requested = data.requestedLength;
      if (start < 0 || start >= length || requested <= 0) {
        [request finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                            code:NSURLErrorDataLengthExceedsMaximum
                                                        userInfo:nil]];
        return;
      }
      long long count = std::min<long long>(length - start, requested);
      [data respondWithData:[NSData dataWithBytes:key.data() + start length:static_cast<NSUInteger>(count)]];
    }
    [request finishLoading];
  }

  void ReportFailure(NSError* error) {
    if (shut_down_ || reported_error_) {
      return;
    }
    reported_error_ = true;
    HlsError kind;
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
      kind = HlsError::kNetwork;
    } else if (!reported_metadata_) {
      kind = HlsError::kNotSupported;
    } else {
      kind = HlsError::kDecode;
    }
    // An underlying URL error behind an AVFoundation error is a network error.
    NSError* underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying.domain isEqualToString:NSURLErrorDomain]) {
      kind = HlsError::kNetwork;
    }
    std::string message = error ? std::string(error.description.UTF8String ?: "") : "playback failed";
    client_->OnError(kind, message);
  }

  HlsPlayerClient* client_;
  HlsLoader* loader_;
  std::shared_ptr<const PostTask> poster_;
  bool shut_down_ = false;

  AVURLAsset* asset_ = nil;
  AVPlayerItem* item_ = nil;
  AVPlayer* player_ = nil;
  AVPlayerLayer* player_layer_ = nil;
  // With the layer; destroyed first in Shutdown.
  std::unique_ptr<HlsFrameStats> frame_stats_;
  PCHlsURLSession* session_ = nil;
  PCHlsResourceLoaderDelegate* loader_delegate_ = nil;
  PCHlsObserver* observer_ = nil;

  std::map<NSUInteger, std::unique_ptr<TaskLoad>> loads_;
  // Finished loads, destroyed in a later task (or by Shutdown), never while
  // the loader may be inside a call to them.
  std::vector<std::unique_ptr<TaskLoad>> finished_loads_;
  std::map<std::string, NSMutableArray<AVAssetResourceLoadingRequest*>*> key_requests_;
  std::map<std::string, std::vector<uint8_t>> fulfilled_keys_;
  HlsKeyRequestHandler* key_handler_ = nullptr;

  mutable std::mutex timebase_lock_;
  CMTimebaseRef timebase_ = nullptr;

  double rate_ = 0;
  float volume_ = 1;
  bool muted_ = false;
  bool preserves_pitch_ = true;
  bool output_obscured_ = false;
  bool reported_metadata_ = false;
  bool reported_error_ = false;
  std::optional<bool> last_have_enough_;
  HlsTimeline timeline_;
  int32_t natural_width_ = 0;
  int32_t natural_height_ = 0;
  FairPlayHlsPlayer::Status status_;
};

AVURLAsset* HlsPlayerAsset(FairPlayHlsPlayer::Impl* impl) {
  return impl ? impl->asset() : nil;
}

AVPlayer* HlsPlayerAVPlayer(FairPlayHlsPlayer::Impl* impl) {
  return impl ? impl->player() : nil;
}

AVPlayerLayer* HlsPlayerLayer(FairPlayHlsPlayer::Impl* impl) {
  return impl ? impl->PlayerLayer() : nil;
}

void SetHlsKeyRequestHandler(FairPlayHlsPlayer::Impl* impl, HlsKeyRequestHandler* handler) {
  if (impl) {
    impl->SetKeyRequestHandler(handler);
  }
}

}  // namespace parc::fairplay

@implementation PCHlsDataTask {
  __weak PCHlsURLSession* _session;
}

@synthesize taskIdentifier = _taskIdentifier;
@synthesize progress = _progress;

- (instancetype)initWithSession:(PCHlsURLSession*)session
                     identifier:(NSUInteger)identifier
                        request:(NSURLRequest*)request {
  if ((self = [super init])) {
    _session = session;
    _taskIdentifier = identifier;
    self.originalRequest = request;
    self.currentRequest = request;
    self.state = NSURLSessionTaskStateSuspended;
    self.priority = NSURLSessionTaskPriorityDefault;
    self.countOfBytesExpectedToReceive = NSURLSessionTransferSizeUnknown;
    _progress = [NSProgress progressWithTotalUnitCount:-1];
  }
  return self;
}

- (PCHlsURLSession*)session {
  return _session;
}

- (id)copyWithZone:(NSZone*)zone {
  return self;
}

- (BOOL)isKindOfClass:(Class)cls {
  return cls == [NSURLSessionDataTask class] || cls == [NSURLSessionTask class] ||
         [super isKindOfClass:cls];
}

- (void)resume {
  if (self.state != NSURLSessionTaskStateSuspended) {
    return;
  }
  self.state = NSURLSessionTaskStateRunning;
  PCHlsURLSession* session = _session;
  if (!session) {
    return;
  }
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = session.impl;
  (*session.poster)([weak, task = self] {
    if (auto impl = weak.lock()) {
      impl->StartLoad(task);
    }
  });
}

- (void)suspend {
  // Loads can't pause; AVFoundation doesn't suspend media tasks.
}

// AVFoundation may call a session or task method this stand-in doesn't
// implement on a path the harness never took; answer nil/0 instead of
// throwing in the GPU process.
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
  return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
  if (invocation.methodSignature.methodReturnLength) {
    std::vector<uint8_t> zero(invocation.methodSignature.methodReturnLength, 0);
    [invocation setReturnValue:zero.data()];
  }
}


- (void)cancel {
  NSURLSessionTaskState state = self.state;
  if (state == NSURLSessionTaskStateCompleted || state == NSURLSessionTaskStateCanceling) {
    return;
  }
  self.state = NSURLSessionTaskStateCanceling;
  PCHlsURLSession* session = _session;
  if (!session) {
    return;
  }
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = session.impl;
  NSUInteger identifier = _taskIdentifier;
  PCHlsDataTask* task = self;
  bool started = state == NSURLSessionTaskStateRunning;
  (*session.poster)([weak, identifier, task, started] {
    auto impl = weak.lock();
    if (!impl) {
      return;
    }
    if (started) {
      impl->CancelLoad(identifier);
    } else {
      // Never resumed: complete it as cancelled without a load.
      impl->FinishLoad(task, [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorCancelled
                                             userInfo:nil]);
    }
  });
}

@end

@implementation PCHlsURLSession {
  std::weak_ptr<FairPlayHlsPlayer::Impl> _impl;
  std::shared_ptr<const PostTask> _poster;
  id<NSURLSessionDataDelegate> _delegate;
  NSOperationQueue* _queue;
  std::atomic<NSUInteger> _nextIdentifier;
  NSMutableDictionary<NSNumber*, PCHlsDataTask*>* _tasks;
  NSString* _sessionDescription;
  BOOL _invalidated;
}

- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster
                    delegate:(id<NSURLSessionDataDelegate>)delegate
                       queue:(NSOperationQueue*)queue {
  if ((self = [super init])) {
    _impl = std::move(impl);
    _poster = std::move(poster);
    _delegate = delegate;
    _queue = queue;
    _nextIdentifier = 1;
    _tasks = [NSMutableDictionary dictionary];
  }
  return self;
}

- (std::weak_ptr<FairPlayHlsPlayer::Impl>)impl {
  return _impl;
}

- (std::shared_ptr<const PostTask>)poster {
  return _poster;
}

- (BOOL)isKindOfClass:(Class)cls {
  return cls == [NSURLSession class] || [super isKindOfClass:cls];
}

- (id)copyWithZone:(NSZone*)zone {
  return self;
}

- (id<NSURLSessionDelegate>)delegate {
  return _delegate;
}

- (NSOperationQueue*)delegateQueue {
  return _queue;
}

- (NSURLSessionConfiguration*)configuration {
  return [NSURLSessionConfiguration ephemeralSessionConfiguration];
}

- (NSString*)sessionDescription {
  @synchronized(self) {
    return _sessionDescription;
  }
}

- (void)setSessionDescription:(NSString*)description {
  @synchronized(self) {
    _sessionDescription = [description copy];
  }
}

- (NSURLSessionDataTask*)dataTaskWithURL:(NSURL*)url {
  return [self dataTaskWithRequest:[NSURLRequest requestWithURL:url]];
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
  PCHlsDataTask* task = [[PCHlsDataTask alloc] initWithSession:self
                                                    identifier:_nextIdentifier++
                                                       request:request];
  @synchronized(self) {
    if (_invalidated) {
      return nil;
    }
    _tasks[@(task.taskIdentifier)] = task;
  }
  return (NSURLSessionDataTask*)task;
}

- (void)taskFinished:(PCHlsDataTask*)task {
  @synchronized(self) {
    [_tasks removeObjectForKey:@(task.taskIdentifier)];
  }
}

- (void)deliver:(void (^)(id<NSURLSessionDataDelegate> delegate))block {
  id<NSURLSessionDataDelegate> delegate = _delegate;
  @synchronized(self) {
    if (_invalidated || !delegate) {
      return;
    }
  }
  // A barrier keeps response, data and completion in order even if
  // AVFoundation's queue runs operations concurrently.
  [_queue addBarrierBlock:^{
    block(delegate);
  }];
}

- (NSArray<PCHlsDataTask*>*)allTasks {
  @synchronized(self) {
    return _tasks.allValues;
  }
}

- (void)getTasksWithCompletionHandler:(void (^)(NSArray<NSURLSessionDataTask*>*,
                                                NSArray<NSURLSessionUploadTask*>*,
                                                NSArray<NSURLSessionDownloadTask*>*))handler {
  NSArray* tasks = [self allTasks];
  [_queue addOperationWithBlock:^{
    handler(tasks, @[], @[]);
  }];
}

- (void)getAllTasksWithCompletionHandler:(void (^)(NSArray<__kindof NSURLSessionTask*>*))handler {
  NSArray* tasks = [self allTasks];
  [_queue addOperationWithBlock:^{
    handler(tasks);
  }];
}

- (void)finishTasksAndInvalidate {
  @synchronized(self) {
    _invalidated = YES;
  }
}

- (void)invalidateAndCancel {
  for (PCHlsDataTask* task in [self allTasks]) {
    [task cancel];
  }
  [self finishTasksAndInvalidate];
}

- (void)resetWithCompletionHandler:(void (^)(void))handler {
  [_queue addOperationWithBlock:handler];
}

- (void)flushWithCompletionHandler:(void (^)(void))handler {
  [_queue addOperationWithBlock:handler];
}

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))handler {
  return nil;  // AVFoundation uses delegate-based tasks only.
}

// AVFoundation may call a session or task method this stand-in doesn't
// implement on a path the harness never took; answer nil/0 instead of
// throwing in the GPU process.
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
  return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
  if (invocation.methodSignature.methodReturnLength) {
    std::vector<uint8_t> zero(invocation.methodSignature.methodReturnLength, 0);
    [invocation setReturnValue:zero.data()];
  }
}


- (void)invalidate {
  @synchronized(self) {
    _invalidated = YES;
    [_tasks removeAllObjects];
  }
  _delegate = nil;
}

@end

@implementation PCHlsResourceLoaderDelegate {
  std::weak_ptr<FairPlayHlsPlayer::Impl> _impl;
  std::shared_ptr<const PostTask> _poster;
}

- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster {
  if ((self = [super init])) {
    _impl = std::move(impl);
    _poster = std::move(poster);
  }
  return self;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader*)resourceLoader
    shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest*)request {
  NSString* scheme = request.request.URL.scheme.lowercaseString;
  if (![scheme isEqualToString:@"skd"] && ![scheme isEqualToString:@"clearkey"]) {
    // Everything else goes through the URL session; a request that ends up
    // here (an unknown scheme) can't be loaded.
    return NO;
  }
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = _impl;
  (*_poster)([weak, request] {
    if (auto impl = weak.lock()) {
      impl->OnKeyRequest(request);
    } else {
      [request finishLoadingWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                          code:NSURLErrorCancelled
                                                      userInfo:nil]];
    }
  });
  return YES;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader*)resourceLoader
    shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest*)request {
  return [self resourceLoader:resourceLoader shouldWaitForLoadingOfRequestedResource:request];
}

- (void)resourceLoader:(AVAssetResourceLoader*)resourceLoader
    didCancelLoadingRequest:(AVAssetResourceLoadingRequest*)request {
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = _impl;
  (*_poster)([weak, request] {
    if (auto impl = weak.lock()) {
      impl->OnKeyRequestCancelled(request);
    }
  });
}

@end

static void* const kItemStatus = (void*)&kItemStatus;
static void* const kItemBuffering = (void*)&kItemBuffering;
static void* const kItemLoaded = (void*)&kItemLoaded;
static void* const kItemSeekable = (void*)&kItemSeekable;
static void* const kItemDuration = (void*)&kItemDuration;
static void* const kItemSize = (void*)&kItemSize;
static void* const kPlayerObscured = (void*)&kPlayerObscured;

@implementation PCHlsObserver {
  std::weak_ptr<FairPlayHlsPlayer::Impl> _impl;
  std::shared_ptr<const PostTask> _poster;
  AVPlayerItem* _item;
  AVPlayer* _player;
  NSArray<NSString*>* _bufferingKeys;
  BOOL _stopped;
}

- (instancetype)initWithImpl:(std::weak_ptr<FairPlayHlsPlayer::Impl>)impl
                      poster:(std::shared_ptr<const PostTask>)poster {
  if ((self = [super init])) {
    _impl = std::move(impl);
    _poster = std::move(poster);
    _bufferingKeys = @[ @"playbackLikelyToKeepUp", @"playbackBufferEmpty", @"playbackBufferFull" ];
  }
  return self;
}

- (void)observePlayer:(AVPlayer*)player item:(AVPlayerItem*)item {
  _item = item;
  _player = player;
  [player addObserver:self
           forKeyPath:@"outputObscuredDueToInsufficientExternalProtection"
              options:0
              context:kPlayerObscured];
  NSKeyValueObservingOptions options = NSKeyValueObservingOptionInitial;
  [item addObserver:self forKeyPath:@"status" options:options context:kItemStatus];
  for (NSString* key in _bufferingKeys) {
    [item addObserver:self forKeyPath:key options:0 context:kItemBuffering];
  }
  [item addObserver:self forKeyPath:@"loadedTimeRanges" options:0 context:kItemLoaded];
  [item addObserver:self forKeyPath:@"seekableTimeRanges" options:0 context:kItemSeekable];
  [item addObserver:self forKeyPath:@"duration" options:0 context:kItemDuration];
  [item addObserver:self forKeyPath:@"presentationSize" options:0 context:kItemSize];
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center addObserver:self
             selector:@selector(itemDidPlayToEnd:)
                 name:AVPlayerItemDidPlayToEndTimeNotification
               object:item];
  [center addObserver:self
             selector:@selector(itemFailedToPlayToEnd:)
                 name:AVPlayerItemFailedToPlayToEndTimeNotification
               object:item];
}

- (void)stop {
  @synchronized(self) {
    if (_stopped || !_item) {
      _stopped = YES;
      return;
    }
    _stopped = YES;
  }
  [_item removeObserver:self forKeyPath:@"status" context:kItemStatus];
  for (NSString* key in _bufferingKeys) {
    [_item removeObserver:self forKeyPath:key context:kItemBuffering];
  }
  [_item removeObserver:self forKeyPath:@"loadedTimeRanges" context:kItemLoaded];
  [_item removeObserver:self forKeyPath:@"seekableTimeRanges" context:kItemSeekable];
  [_item removeObserver:self forKeyPath:@"duration" context:kItemDuration];
  [_item removeObserver:self forKeyPath:@"presentationSize" context:kItemSize];
  [_player removeObserver:self
               forKeyPath:@"outputObscuredDueToInsufficientExternalProtection"
                  context:kPlayerObscured];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _item = nil;
  _player = nil;
}

- (void)post:(void (FairPlayHlsPlayer::Impl::*)())method {
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = _impl;
  (*_poster)([weak, method] {
    if (auto impl = weak.lock()) {
      ((*impl).*method)();
    }
  });
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  if (context == kItemStatus) {
    [self post:&FairPlayHlsPlayer::Impl::OnItemStatus];
  } else if (context == kItemBuffering) {
    [self post:&FairPlayHlsPlayer::Impl::OnBuffering];
  } else if (context == kItemLoaded) {
    [self post:&FairPlayHlsPlayer::Impl::OnLoadedRanges];
  } else if (context == kItemSeekable) {
    [self post:&FairPlayHlsPlayer::Impl::OnSeekableRanges];
  } else if (context == kItemDuration) {
    [self post:&FairPlayHlsPlayer::Impl::OnDuration];
  } else if (context == kItemSize) {
    [self post:&FairPlayHlsPlayer::Impl::OnPresentationSize];
  } else if (context == kPlayerObscured) {
    [self post:&FairPlayHlsPlayer::Impl::OnOutputObscured];
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)itemDidPlayToEnd:(NSNotification*)notification {
  [self post:&FairPlayHlsPlayer::Impl::OnEnded];
}

- (void)itemFailedToPlayToEnd:(NSNotification*)notification {
  NSError* error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
  std::weak_ptr<FairPlayHlsPlayer::Impl> weak = _impl;
  (*_poster)([weak, error] {
    if (auto impl = weak.lock()) {
      impl->OnFailedToPlayToEnd(error);
    }
  });
}

@end

namespace parc::fairplay {

FairPlayHlsPlayer::FairPlayHlsPlayer(HlsPlayerClient* client, HlsLoader* loader, PostTask post_task)
    : impl_(std::make_shared<Impl>(client, loader, std::move(post_task))) {}

FairPlayHlsPlayer::~FairPlayHlsPlayer() {
  impl_->Shutdown();
  impl_->ReleaseTimebase();
}

bool FairPlayHlsPlayer::IsSupported() {
  return ClientURLLoadingOnlyKey() != nil && ResourceLoaderTakesURLSession();
}

Result FairPlayHlsPlayer::CreateAsset(const std::string& url, const std::string& mime_type) {
  return impl_->CreateAsset(url, mime_type);
}

Result FairPlayHlsPlayer::Start() {
  return impl_->Start();
}

Result FairPlayHlsPlayer::Load(const std::string& url, const std::string& mime_type) {
  Result result = impl_->CreateAsset(url, mime_type);
  return result.ok() ? impl_->Start() : result;
}

void FairPlayHlsPlayer::SetRate(double rate) {
  impl_->SetRate(rate);
}

void FairPlayHlsPlayer::Seek(double seconds, std::function<void(bool)> done) {
  impl_->Seek(seconds, 0, std::move(done));
}

void FairPlayHlsPlayer::Seek(double seconds,
                             double tolerance_before,
                             std::function<void(bool)> done) {
  impl_->Seek(seconds, tolerance_before, std::move(done));
}

void FairPlayHlsPlayer::SetVolume(float volume) {
  impl_->SetVolume(volume);
}

void FairPlayHlsPlayer::SetMuted(bool muted) {
  impl_->SetMuted(muted);
}

void FairPlayHlsPlayer::SetPreservesPitch(bool preserves_pitch) {
  impl_->SetPreservesPitch(preserves_pitch);
}

double FairPlayHlsPlayer::CurrentTime() const {
  return impl_->CurrentTime();
}

double FairPlayHlsPlayer::Rate() const {
  return impl_->Rate();
}

void FairPlayHlsPlayer::FulfillKeyRequests(const std::string& clearkey_uri, const std::vector<uint8_t>& key) {
  impl_->FulfillKeyRequests(clearkey_uri, key);
}

void FairPlayHlsPlayer::FailKeyRequests(const std::string& uri, const std::string& message) {
  impl_->FailKeyRequests(uri, message);
}

std::string HlsClearKeyId(const std::string& clearkey_uri) {
  NSString* string = NSStringOrNil(clearkey_uri);
  NSURL* url = string ? [NSURL URLWithString:string] : nil;
  NSString* specifier = url.resourceSpecifier;
  return specifier ? std::string(specifier.UTF8String ?: "") : std::string();
}

FairPlayHlsPlayer::Status FairPlayHlsPlayer::GetStatus() const {
  return impl_->status();
}

}  // namespace parc::fairplay

#include "fairplay_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>

#include <algorithm>
#include <atomic>
#include <deque>
#include <map>

#include "fairplay_bitstream.h"
#include "fairplay_key_session.h"
#include "fairplay_key_session_internal.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

using parc::fairplay::FairPlayRenderer;
using parc::fairplay::PostTask;

// Format description and sample attachment keys. CoreMedia exports these
// strings but its headers name only some of them; the values below are what
// AVStreamDataParser produces for CMAF cbcs content (and what WebKit writes
// when it rebuilds protected samples in its GPU process, CMUtilities.mm).
// kCMFormatDescriptionExtension_ProtectedContentOriginalFormat is
// "CommonEncryptionOriginalFormat" and is used through its public symbol.
static const CFStringRef kCommonEncryptionProtected = CFSTR("CommonEncryptionProtected");
static const CFStringRef kCommonEncryptionTrackEncryptionBox =
    CFSTR("CommonEncryptionTrackEncryptionBox");
// kCMSampleAttachmentKey_CryptorInitializationVector (exported, no header).
static const CFStringRef kCryptorIV = CFSTR("CryptorIV");
// Sum of the sample's clear bytes; AVStreamDataParser sets it with the
// subsample data.
static const CFStringRef kBytesOfClearDataCount = CFSTR("BytesOfClearDataCount");

@interface PCFairPlayRendererObserver : NSObject
- (instancetype)initWithHandler:(std::function<void(NSString*)>)handler;
@end

namespace parc::fairplay {
namespace {

// FairPlay protected sample entry types, as AVStreamDataParser reports them.
constexpr uint32_t kProtectedAVC = FourCC('q', 'a', 'v', 'c');
constexpr uint32_t kProtectedHEVC = FourCC('q', 'h', 'v', 'c');
constexpr uint32_t kProtectedAAC = FourCC('q', 'a', 'a', 'c');
// Unverified: no FairPlay AC-3/E-AC-3 vector was available.
constexpr uint32_t kProtectedAC3 = FourCC('q', 'a', 'c', '3');
constexpr uint32_t kProtectedEAC3 = FourCC('q', 'e', 'c', '3');

class ScopedFormat {
 public:
  ScopedFormat() = default;
  ~ScopedFormat() { Reset(nullptr); }
  ScopedFormat(const ScopedFormat&) = delete;
  ScopedFormat& operator=(const ScopedFormat&) = delete;
  void Reset(CMFormatDescriptionRef format) {
    if (format_) {
      CFRelease(format_);
    }
    format_ = format;
  }
  CMFormatDescriptionRef get() const { return format_; }

 private:
  CMFormatDescriptionRef format_ = nullptr;
};

NSData* ToNSData(const std::vector<uint8_t>& bytes) {
  return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

std::string Describe(NSError* error) {
  std::string text;
  for (int depth = 0; error && depth < 4; ++depth) {
    if (depth) {
      text += " <- ";
    }
    text += std::string(error.domain.UTF8String) + " " + std::to_string(error.code);
    if (error.localizedDescription.length) {
      text += " (" + std::string(error.localizedDescription.UTF8String) + ")";
    }
    error = error.userInfo[NSUnderlyingErrorKey];
  }
  return text;
}

CMTime ToCMTime(MediaTime time) {
  return time.IsValid() ? CMTimeMake(time.value, time.timescale) : kCMTimeInvalid;
}

MediaTime FromCMTime(CMTime time) {
  if (!CMTIME_IS_NUMERIC(time)) {
    return MediaTime::Invalid();
  }
  if (time.timescale <= 0) {
    return MediaTime::Invalid();
  }
  return {time.value, time.timescale};
}

// Extensions shared by protected video and audio format descriptions.
void AddProtectionExtensions(NSMutableDictionary* extensions,
                             NSMutableDictionary* atoms,
                             uint32_t original_format,
                             const TrackEncryption& encryption) {
  extensions[(__bridge NSString*)kCMFormatDescriptionExtension_ProtectedContentOriginalFormat] =
      @(original_format);
  extensions[(__bridge NSString*)kCommonEncryptionProtected] = @YES;
  extensions[(__bridge NSString*)kCommonEncryptionTrackEncryptionBox] =
      ToNSData(TrackEncryptionBoxPayload(encryption));
  atoms[@"sinf"] = ToNSData(ProtectionSchemeInfoPayload(original_format, encryption));
}

bool IsEncrypted(const TrackEncryption& encryption) {
  return encryption.scheme != EncryptionScheme::kUnencrypted;
}

}  // namespace

class FairPlayRenderer::Impl : public std::enable_shared_from_this<FairPlayRenderer::Impl> {
 public:
  Impl(FairPlayRendererClient* client, PostTask post_task)
      : client_(client), poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() { Shutdown(); }

  void Shutdown() {
    SetCdm(nullptr);
    for (id token : notification_tokens_) {
      [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
    notification_tokens_.clear();
    if (observer_) {
      for (auto& [object, key_path] : observed_) {
        [object removeObserver:observer_ forKeyPath:key_path];
      }
      observed_.clear();
      observer_ = nil;
    }
    RemoveEndObserver();
    if (clock_observer_) {
      [synchronizer_ removeTimeObserver:clock_observer_];
      clock_observer_ = nil;
    }
    [video_renderer_ stopRequestingMediaData];
    [audio_ stopRequestingMediaData];
    synchronizer_.rate = 0;
  }

  Result Initialize(const std::optional<VideoConfig>& video,
                    const std::optional<AudioConfig>& audio) {
    if (synchronizer_) {
      return Result::Error(Exception::kInvalidState, "already initialized");
    }
    if (!video && !audio) {
      return Result::Error(Exception::kTypeError, "no stream to render");
    }
    video_config_ = video;
    audio_config_ = audio;
    std::string error;
    if (video) {
      CMFormatDescriptionRef clear = nullptr;
      if (Result result = CreateVideoFormat(*video, nullptr, &clear); !result.ok()) {
        return result;
      }
      video_clear_format_.Reset(clear);
      if (IsEncrypted(video->encryption) &&
          !ProtectedFormat(StreamType::kVideo, video->encryption.default_key_id, &error)) {
        return Result::Error(Exception::kNotSupported, error);
      }
    }
    if (audio) {
      CMFormatDescriptionRef clear = nullptr;
      if (Result result = CreateAudioFormat(*audio, nullptr, &clear); !result.ok()) {
        return result;
      }
      audio_clear_format_.Reset(clear);
      if (IsEncrypted(audio->encryption) &&
          !ProtectedFormat(StreamType::kAudio, audio->encryption.default_key_id, &error)) {
        return Result::Error(Exception::kNotSupported, error);
      }
    }
    synchronizer_ = [[AVSampleBufferRenderSynchronizer alloc] init];
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    clock_observer_ = [synchronizer_ addPeriodicTimeObserverForInterval:CMTimeMake(1, 10)
                                                                  queue:RequestQueue()
                                                             usingBlock:^(CMTime) {
                                                               (*poster)([weak] {
                                                                 if (auto impl = weak.lock()) {
                                                                   impl->CheckUnderflow();
                                                                 }
                                                               });
                                                             }];
    observer_ = [[PCFairPlayRendererObserver alloc] initWithHandler:[weak, poster](NSString*) {
      (*poster)([weak] {
        if (auto impl = weak.lock()) {
          impl->CheckRendererStatus();
        }
      });
    }];
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (video) {
      layer_ = [AVSampleBufferDisplayLayer layer];
      layer_.videoGravity = AVLayerVideoGravityResizeAspect;
      NSNotificationName decode_failed = AVSampleBufferDisplayLayerFailedToDecodeNotification;
      NSString* decode_error_key = AVSampleBufferDisplayLayerFailedToDecodeNotificationErrorKey;
      NSNotificationName requires_flush =
          AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChangeNotification;
      if (@available(macOS 14.0, *)) {
        video_renderer_ = layer_.sampleBufferRenderer;
        decode_failed = AVSampleBufferVideoRendererDidFailToDecodeNotification;
        decode_error_key = AVSampleBufferVideoRendererDidFailToDecodeNotificationErrorKey;
        requires_flush = AVSampleBufferVideoRendererRequiresFlushToResumeDecodingDidChangeNotification;
      } else {
        video_renderer_ = layer_;
      }
      [synchronizer_ addRenderer:video_renderer_];
      Observe(video_renderer_, @"status");
      Observe(video_renderer_, @"error");
      AddNotification(center,
                      AVSampleBufferDisplayLayerOutputObscuredDueToInsufficientExternalProtectionDidChangeNotification,
                      layer_, [](Impl& impl, NSNotification*) { impl.CheckRendererStatus(); });
      AddNotification(center, decode_failed, video_renderer_, [decode_error_key](Impl& impl,
                                                                                 NSNotification* note) {
        impl.OnDecodeFailed(note.userInfo[decode_error_key]);
      });
      AddNotification(center, requires_flush, video_renderer_,
                      [](Impl& impl, NSNotification*) { impl.CheckRendererStatus(); });
      int32_t width = video->natural_width ? video->natural_width : video->coded_width;
      int32_t height = video->natural_height ? video->natural_height : video->coded_height;
      Post([width, height](Impl& impl) {
        impl.client_->OnVideoNaturalSizeChange(width, height);
      });
    }
    if (audio) {
      audio_ = [[AVSampleBufferAudioRenderer alloc] init];
      [synchronizer_ addRenderer:audio_];
      Observe(audio_, @"status");
      Observe(audio_, @"error");
      AddNotification(center, AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification,
                      audio_, [](Impl& impl, NSNotification*) {
                        ++impl.status_.audio_automatic_flushes;
                      });
    }
    return Result::Ok();
  }

  // The renderers join the key system's AVContentKeySession as content key
  // recipients. AVSampleBufferAttachContentKey would attach keys per sample
  // instead, but on macOS it needs the private
  // com.apple.private.coremedia.allow-fps-attachment entitlement (WebKit's GPU
  // process has it; other processes get -11836 <- -12161, "not authorized").
  Result SetCdm(FairPlayCdm* cdm) {
    if (cdm == cdm_) {
      return Result::Ok();
    }
    if (cdm && (cdm_ || status_.video_enqueued || status_.audio_enqueued)) {
      return Result::Error(Exception::kInvalidState,
                           "the CDM must be set once, before the first sample");
    }
    if (cdm_) {
      cdm_->RemoveKeysChangedObserver(observer_id_);
      observer_id_ = 0;
      for (id<AVContentKeyRecipient> recipient : recipients_) {
        DetachContentKeyRecipient(cdm_->impl(), recipient);
      }
      recipients_.clear();
    }
    cdm_ = cdm;
    if (!cdm_) {
      return Result::Ok();
    }
    for (id object : {(id)layer_, (id)audio_}) {
      if (!object) {
        continue;
      }
      if (![object conformsToProtocol:@protocol(AVContentKeyRecipient)]) {
        return Result::Error(Exception::kNotSupported,
                             "renderer is not an AVContentKeyRecipient on this OS");
      }
      Result result = AttachContentKeyRecipient(cdm_->impl(), (id<AVContentKeyRecipient>)object);
      if (!result.ok()) {
        return result;
      }
      recipients_.push_back((id<AVContentKeyRecipient>)object);
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    observer_id_ = cdm_->AddKeysChangedObserver([weak] {
      if (auto impl = weak.lock()) {
        impl->OnKeysChanged();
      }
    });
    OnKeysChanged();
    return Result::Ok();
  }

  void* display_layer() const { return (__bridge void*)layer_; }

  bool IsReadyForMoreData(StreamType stream) const {
    const Stream& state = StreamFor(stream);
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    return renderer && !state.end_of_stream && state.held.empty() &&
           renderer.readyForMoreMediaData;
  }

  EnqueueResult Enqueue(StreamType stream, const EncodedSample& sample) {
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    Stream& state = StreamFor(stream);
    if (!renderer || state.end_of_stream) {
      return EnqueueResult::kRejected;
    }
    if (stream == StreamType::kAudio && start_time_.IsValid() && sample.duration.IsValid() &&
        sample.pts.InSeconds() + sample.duration.InSeconds() <= start_time_.InSeconds()) {
      // Entirely before the start time: dropped, as Chromium's audio renderer
      // discards preroll before its start timestamp.
      return EnqueueResult::kEnqueued;
    }
    Held held;
    std::string error;
    if (!BuildSample(stream, sample, &held, &error)) {
      Post([error](Impl& impl) { impl.client_->OnError(RendererError::kConfiguration, error); });
      return EnqueueResult::kRejected;
    }
    MediaTime end = sample.pts;
    if (sample.duration.IsValid()) {
      end.value += static_cast<int64_t>(static_cast<__int128>(sample.duration.value) *
                                        sample.pts.timescale / sample.duration.timescale);
    }
    if (!state.last_end.IsValid() || end.InSeconds() > state.last_end.InSeconds()) {
      state.last_end = end;
    }
    held.end = end.InSeconds();
    if (!state.held.empty() || !Submit(stream, held)) {
      state.held.push_back(std::move(held));
      if (!waiting_reported_) {
        waiting_reported_ = true;
        Post([](Impl& impl) { impl.client_->OnWaitingForKey(); });
      }
      return EnqueueResult::kWaitingForKey;
    }
    if (!renderer.readyForMoreMediaData) {
      ArmRequest(stream);
    }
    UpdateBuffering();
    return EnqueueResult::kEnqueued;
  }

  void SetEndOfStream(StreamType stream) {
    Stream& state = StreamFor(stream);
    if (state.end_of_stream || !RendererFor(stream)) {
      return;
    }
    state.end_of_stream = true;
    [RendererFor(stream) stopRequestingMediaData];
    state.armed = false;
    ScheduleEndIfComplete();
  }

  void StartPlayingFrom(MediaTime time) {
    start_time_ = time;
    ended_ = false;
    [synchronizer_ setRate:0 time:ToCMTime(time)];
    status_.rate = 0;
    NotifyNeedData(StreamType::kVideo);
    NotifyNeedData(StreamType::kAudio);
  }

  void SetPlaybackRate(double rate) {
    status_.rate = static_cast<float>(rate);
    if (!underflowed_) {
      synchronizer_.rate = static_cast<float>(rate);
    }
  }

  void SetVolume(float volume) { audio_.volume = volume; }
  void SetMuted(bool muted) { audio_.muted = muted; }

  void Flush(std::function<void()> done) {
    synchronizer_.rate = 0;
    status_.rate = 0;
    RemoveEndObserver();
    for (StreamType stream : {StreamType::kVideo, StreamType::kAudio}) {
      id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
      Stream& state = StreamFor(stream);
      [renderer stopRequestingMediaData];
      [renderer flush];
      state = Stream();
    }
    waiting_reported_ = false;
    ended_ = false;
    // Like RendererImpl::Flush: back to HAVE_NOTHING without a callback; the
    // next HAVE_ENOUGH follows StartPlayingFrom.
    have_enough_ = false;
    underflowed_ = false;
    Post([done](Impl&) { done(); });
  }

  MediaTime GetMediaTime() const {
    return synchronizer_ ? FromCMTime(CMTimebaseGetTime(synchronizer_.timebase))
                         : MediaTime::Invalid();
  }

  RendererStatus GetStatus() const {
    RendererStatus status = status_;
    status.time = GetMediaTime();
    if (video_renderer_) {
      if (@available(macOS 14.0, *)) {
        AVSampleBufferVideoRenderer* renderer = layer_.sampleBufferRenderer;
        status.video = Map(renderer.status);
        status.video_error = renderer.error ? Describe(renderer.error) : "";
        status.video_requires_flush = renderer.requiresFlushToResumeDecoding;
      } else {
        status.video = Map(layer_.status);
        status.video_error = layer_.error ? Describe(layer_.error) : "";
        status.video_requires_flush = layer_.requiresFlushToResumeDecoding;
      }
      if (@available(macOS 14.4, *)) {
        status.video_ready_for_display = layer_.readyForDisplay;
      }
      status.output_obscured = layer_.outputObscuredDueToInsufficientExternalProtection;
      status.video_has_enough = video_renderer_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    if (audio_) {
      status.audio = Map(audio_.status);
      status.audio_error = audio_.error ? Describe(audio_.error) : "";
      status.audio_has_enough = audio_.hasSufficientMediaDataForReliablePlaybackStart;
      status.audio_volume = audio_.volume;
      status.audio_muted = audio_.muted;
    }
    return status;
  }

  void LoadVideoMetrics(std::function<void(const VideoMetrics&)> done) const {
    if (@available(macOS 14.4, *)) {
      if (layer_) {
        std::shared_ptr<const PostTask> poster = poster_;
        [layer_.sampleBufferRenderer
            loadVideoPerformanceMetricsWithCompletionHandler:^(AVVideoPerformanceMetrics* metrics) {
              VideoMetrics result;
              if (metrics) {
                result.available = true;
                result.total_frames = metrics.totalNumberOfFrames;
                result.dropped_frames = metrics.numberOfDroppedFrames;
                result.corrupted_frames = metrics.numberOfCorruptedFrames;
                result.optimized_composited_frames =
                    metrics.numberOfFramesDisplayedUsingOptimizedCompositing;
                result.accumulated_frame_delay = metrics.totalAccumulatedFrameDelay;
              }
              (*poster)([done, result] { done(result); });
            }];
        return;
      }
    }
    (*poster_)([done] { done(VideoMetrics()); });
  }

 private:
  struct Held {
    CMSampleBufferRef buffer = nullptr;  // Owned.
    bool encrypted = false;
    std::vector<uint8_t> key_id;
    double end = 0;  // Presentation end, seconds.

    Held() = default;
    Held(Held&& other) noexcept
        : buffer(other.buffer),
          encrypted(other.encrypted),
          key_id(std::move(other.key_id)),
          end(other.end) {
      other.buffer = nullptr;
    }
    Held& operator=(Held&& other) noexcept {
      if (this != &other) {
        if (buffer) {
          CFRelease(buffer);
        }
        buffer = other.buffer;
        encrypted = other.encrypted;
        key_id = std::move(other.key_id);
        end = other.end;
        other.buffer = nullptr;
      }
      return *this;
    }
    ~Held() {
      if (buffer) {
        CFRelease(buffer);
      }
    }
  };

  struct Stream {
    std::deque<Held> held;
    bool end_of_stream = false;
    bool armed = false;
    MediaTime last_end;
    double enqueued_end = -1;  // End of the last sample given to AVFoundation.
  };

  static RenderingStatus Map(AVQueuedSampleBufferRenderingStatus status) {
    switch (status) {
      case AVQueuedSampleBufferRenderingStatusUnknown:
        return RenderingStatus::kUnknown;
      case AVQueuedSampleBufferRenderingStatusRendering:
        return RenderingStatus::kRendering;
      case AVQueuedSampleBufferRenderingStatusFailed:
        return RenderingStatus::kFailed;
    }
    return RenderingStatus::kUnknown;
  }

  Stream& StreamFor(StreamType stream) {
    return stream == StreamType::kVideo ? video_ : audio_stream_;
  }
  const Stream& StreamFor(StreamType stream) const {
    return stream == StreamType::kVideo ? video_ : audio_stream_;
  }
  id<AVQueuedSampleBufferRendering> RendererFor(StreamType stream) const {
    return stream == StreamType::kVideo ? video_renderer_ : audio_;
  }

  void Post(std::function<void(Impl&)> task) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, task] {
      if (auto impl = weak.lock()) {
        task(*impl);
      }
    });
  }

  void Observe(NSObject* object, NSString* key_path) {
    [object addObserver:observer_ forKeyPath:key_path options:0 context:nullptr];
    observed_.push_back({object, key_path});
  }

  void AddNotification(NSNotificationCenter* center,
                       NSNotificationName name,
                       id object,
                       std::function<void(Impl&, NSNotification*)> handler) {
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    id token = [center addObserverForName:name
                                   object:object
                                    queue:nil
                               usingBlock:^(NSNotification* note) {
                                 (*poster)([weak, handler, note] {
                                   if (auto impl = weak.lock()) {
                                     handler(*impl, note);
                                   }
                                 });
                               }];
    notification_tokens_.push_back(token);
  }

  // Clear format description when |encryption| is null; otherwise the
  // protected form AVStreamDataParser produces for CMAF: a FairPlay protected
  // sample entry type, the original format, the 'tenc' payload and a 'sinf'
  // atom. Content key recipients match keys by the 'tenc' key ID.
  static Result CreateVideoFormat(const VideoConfig& config,
                                  const TrackEncryption* encryption,
                                  CMFormatDescriptionRef* out) {
    if (config.extra_data.empty() || config.coded_width <= 0 || config.coded_height <= 0) {
      return Result::Error(Exception::kTypeError, "video config needs a decoder record and size");
    }
    const bool hevc = config.codec == VideoCodec::kHEVC;
    const uint32_t clear_type = hevc ? FourCC('h', 'v', 'c', '1') : FourCC('a', 'v', 'c', '1');
    NSMutableDictionary* atoms =
        [@{(hevc ? @"hvcC" : @"avcC") : ToNSData(config.extra_data)} mutableCopy];
    NSMutableDictionary* extensions = [NSMutableDictionary dictionary];
    if (encryption) {
      AddProtectionExtensions(extensions, atoms, clear_type, *encryption);
    }
    extensions[(__bridge NSString*)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] =
        atoms;
    uint32_t type = encryption ? (hevc ? kProtectedHEVC : kProtectedAVC) : clear_type;
    OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, type, config.coded_width,
                                                     config.coded_height,
                                                     (__bridge CFDictionaryRef)extensions, out);
    if (status != noErr) {
      return Result::Error(Exception::kNotSupported, "CMVideoFormatDescriptionCreate failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  static Result CreateAudioFormat(const AudioConfig& config,
                                  const TrackEncryption* encryption,
                                  CMFormatDescriptionRef* out) {
    AudioStreamBasicDescription asbd = {};
    std::vector<uint8_t> cookie;
    uint32_t clear_type = 0;
    uint32_t protected_type = 0;
    NSMutableDictionary* atoms = [NSMutableDictionary dictionary];
    switch (config.codec) {
      case AudioCodec::kAAC: {
        if (config.extra_data.empty()) {
          return Result::Error(Exception::kTypeError, "AAC config needs an AudioSpecificConfig");
        }
        cookie = AacMagicCookie(config.extra_data);
        asbd.mFormatID = kAudioFormatMPEG4AAC;
        UInt32 size = sizeof(asbd);
        if (AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                   static_cast<UInt32>(cookie.size()), cookie.data(), &size,
                                   &asbd) != noErr) {
          asbd = {};
          asbd.mFormatID = kAudioFormatMPEG4AAC;
          asbd.mSampleRate = config.sample_rate;
          asbd.mChannelsPerFrame = static_cast<UInt32>(config.channels);
          asbd.mFramesPerPacket = 1024;
        }
        clear_type = FourCC('m', 'p', '4', 'a');
        protected_type = kProtectedAAC;
        break;
      }
      case AudioCodec::kAC3:
      case AudioCodec::kEAC3: {
        const bool enhanced = config.codec == AudioCodec::kEAC3;
        asbd.mFormatID = enhanced ? kAudioFormatEnhancedAC3 : kAudioFormatAC3;
        asbd.mSampleRate = config.sample_rate;
        asbd.mChannelsPerFrame = static_cast<UInt32>(config.channels);
        asbd.mFramesPerPacket = 1536;
        if (!config.extra_data.empty()) {
          atoms[enhanced ? @"dec3" : @"dac3"] = ToNSData(config.extra_data);
        }
        clear_type = enhanced ? FourCC('e', 'c', '-', '3') : FourCC('a', 'c', '-', '3');
        protected_type = enhanced ? kProtectedEAC3 : kProtectedAC3;
        break;
      }
    }
    AudioChannelLayout layout = {};
    size_t layout_size = 0;
    if (asbd.mChannelsPerFrame == 1 || asbd.mChannelsPerFrame == 2) {
      layout.mChannelLayoutTag =
          asbd.mChannelsPerFrame == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo;
      layout_size = sizeof(layout);
    }
    NSMutableDictionary* extensions = [NSMutableDictionary dictionary];
    if (encryption) {
      AddProtectionExtensions(extensions, atoms, clear_type, *encryption);
      asbd.mFormatID = protected_type;
    }
    if (atoms.count) {
      extensions[(__bridge NSString*)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] =
          atoms;
    }
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault, &asbd, layout_size, layout_size ? &layout : nullptr, cookie.size(),
        cookie.empty() ? nullptr : cookie.data(),
        extensions.count ? (__bridge CFDictionaryRef)extensions : nullptr, out);
    if (status != noErr) {
      return Result::Error(Exception::kNotSupported, "CMAudioFormatDescriptionCreate failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  // The protected format description for samples encrypted with |key_id|;
  // keys are matched by the format description's 'tenc' key ID, so each key
  // gets its own.
  CMFormatDescriptionRef ProtectedFormat(StreamType stream, const std::vector<uint8_t>& key_id,
                                         std::string* error) {
    auto& cache = stream == StreamType::kVideo ? video_protected_formats_ : audio_protected_formats_;
    auto it = cache.find(key_id);
    if (it != cache.end()) {
      return it->second->get();
    }
    TrackEncryption encryption = stream == StreamType::kVideo ? video_config_->encryption
                                                               : audio_config_->encryption;
    encryption.default_key_id = key_id;
    CMFormatDescriptionRef format = nullptr;
    Result result = stream == StreamType::kVideo
                        ? CreateVideoFormat(*video_config_, &encryption, &format)
                        : CreateAudioFormat(*audio_config_, &encryption, &format);
    if (!result.ok()) {
      *error = result.message;
      return nullptr;
    }
    auto holder = std::make_unique<ScopedFormat>();
    holder->Reset(format);
    CMFormatDescriptionRef raw = holder->get();
    cache[key_id] = std::move(holder);
    return raw;
  }

  bool BuildSample(StreamType stream, const EncodedSample& sample, Held* held, std::string* error) {
    if (!sample.data || !sample.size || !sample.pts.IsValid()) {
      *error = "empty sample or invalid timestamp";
      return false;
    }
    const TrackEncryption& encryption = stream == StreamType::kVideo
                                            ? video_config_->encryption
                                            : audio_config_->encryption;
    const bool encrypted = sample.decrypt.has_value();
    if (encrypted && !IsEncrypted(encryption)) {
      *error = "encrypted sample on a track configured as clear";
      return false;
    }
    std::vector<SubsampleEntry> subsamples;
    if (encrypted) {
      subsamples = sample.decrypt->subsamples;
    }

    // Reframe into what the format description declares.
    std::vector<uint8_t> converted;
    const uint8_t* bytes = sample.data;
    size_t size = sample.size;
    if (stream == StreamType::kVideo && video_config_->format == BitstreamFormat::kAnnexB) {
      if (!ConvertAnnexBToLengthPrefixed(sample.data, sample.size, encrypted ? &subsamples : nullptr,
                                         &converted)) {
        *error = "malformed Annex B access unit";
        return false;
      }
      bytes = converted.data();
      size = converted.size();
    } else if (stream == StreamType::kAudio && audio_config_->framing == AudioFraming::kADTS) {
      size_t header = AdtsHeaderSize(sample.data, sample.size);
      if (!header) {
        *error = "missing ADTS header";
        return false;
      }
      bytes += header;
      size -= header;
      if (encrypted && !RemoveLeadingClearBytes(header, size, &subsamples)) {
        *error = "ADTS header not covered by clear subsample bytes";
        return false;
      }
    }
    if (encrypted && !subsamples.empty()) {
      uint64_t total = 0;
      for (const SubsampleEntry& entry : subsamples) {
        total += static_cast<uint64_t>(entry.clear_bytes) + entry.cypher_bytes;
      }
      if (total != size) {
        *error = "subsamples don't cover the sample";
        return false;
      }
    }

    CMBlockBufferRef block = nullptr;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault, nullptr, size, kCFAllocatorDefault, nullptr, 0, size,
        kCMBlockBufferAssureMemoryNowFlag, &block);
    if (status == noErr) {
      status = CMBlockBufferReplaceDataBytes(bytes, block, 0, size);
    }
    if (status != noErr) {
      if (block) {
        CFRelease(block);
      }
      *error = "CMBlockBuffer allocation failed: " + std::to_string(status);
      return false;
    }
    std::vector<uint8_t> key_id;
    if (encrypted) {
      key_id = sample.decrypt->key_id.empty() ? encryption.default_key_id : sample.decrypt->key_id;
    }
    CMFormatDescriptionRef format =
        encrypted ? ProtectedFormat(stream, key_id, error)
                  : (stream == StreamType::kVideo ? video_clear_format_.get()
                                                  : audio_clear_format_.get());
    if (!format) {
      CFRelease(block);
      return false;
    }
    CMSampleTimingInfo timing = {ToCMTime(sample.duration), ToCMTime(sample.pts),
                                 sample.dts.IsValid() ? ToCMTime(sample.dts) : ToCMTime(sample.pts)};
    if (!sample.duration.IsValid()) {
      timing.duration = kCMTimeInvalid;
    }
    CMSampleBufferRef buffer = nullptr;
    status = CMSampleBufferCreateReady(kCFAllocatorDefault, block, format, 1, 1, &timing, 1, &size,
                                       &buffer);
    CFRelease(block);
    if (status != noErr) {
      *error = "CMSampleBufferCreateReady failed: " + std::to_string(status);
      return false;
    }
    held->buffer = buffer;

    CFArrayRef attachments_array = CMSampleBufferGetSampleAttachmentsArray(buffer, true);
    CFMutableDictionaryRef attachments =
        attachments_array && CFArrayGetCount(attachments_array)
            ? (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments_array, 0)
            : nullptr;
    if (!attachments) {
      *error = "sample buffer has no attachment dictionary";
      return false;
    }
    if (stream == StreamType::kVideo) {
      if (!sample.is_keyframe) {
        CFDictionarySetValue(attachments, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
      }
      if (start_time_.IsValid() && sample.pts.InSeconds() < start_time_.InSeconds()) {
        CFDictionarySetValue(attachments, kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanTrue);
      }
    }
    if (!encrypted) {
      return true;
    }
    held->encrypted = true;
    held->key_id = key_id;
    if (!subsamples.empty()) {
      std::vector<uint8_t> aux = SubsampleAuxiliaryData(subsamples);
      CFDictionarySetValue(attachments, kCMSampleAttachmentKey_CryptorSubsampleAuxiliaryData,
                           (__bridge CFDataRef)ToNSData(aux));
      int32_t clear_total = 0;
      for (const SubsampleEntry& entry : subsamples) {
        clear_total += static_cast<int32_t>(entry.clear_bytes);
      }
      CFDictionarySetValue(attachments, kBytesOfClearDataCount,
                           (__bridge CFNumberRef)@(clear_total));
    }
    // Per-sample IVs only. AVStreamDataParser attaches none for a constant
    // IV, and Chromium repeats the constant IV in every DecryptConfig.
    std::vector<uint8_t> iv = sample.decrypt->iv;
    if (encryption.default_per_sample_iv_size == 8 && iv.size() == 16 &&
        std::all_of(iv.begin() + 8, iv.end(), [](uint8_t b) { return b == 0; })) {
      iv.resize(8);
    }
    if (!iv.empty() && iv != encryption.default_constant_iv) {
      CFDictionarySetValue(attachments, kCryptorIV, (__bridge CFDataRef)ToNSData(iv));
    }
    return true;
  }

  // Enqueues once the key system holds a usable key for an encrypted sample:
  // a protected sample enqueued without one fails the renderer with
  // AVFoundationErrorDomain -11800 "no content key present".
  bool Submit(StreamType stream, Held& held) {
    if (held.encrypted) {
      if (!cdm_ || !cdm_->HasUsableKey(held.key_id)) {
        return false;
      }
      ++status_.protected_enqueued;
    }
    [RendererFor(stream) enqueueSampleBuffer:held.buffer];
    ++(stream == StreamType::kVideo ? status_.video_enqueued : status_.audio_enqueued);
    Stream& state = StreamFor(stream);
    state.enqueued_end = std::max(state.enqueued_end, held.end);
    return true;
  }

  void OnKeysChanged() {
    bool any_held = false;
    for (StreamType stream : {StreamType::kVideo, StreamType::kAudio}) {
      Stream& state = StreamFor(stream);
      while (!state.held.empty() && Submit(stream, state.held.front())) {
        state.held.pop_front();
      }
      any_held |= !state.held.empty();
    }
    if (any_held) {
      return;
    }
    if (waiting_reported_) {
      waiting_reported_ = false;
      ScheduleEndIfComplete();
      NotifyNeedData(StreamType::kVideo);
      NotifyNeedData(StreamType::kAudio);
    }
    UpdateBuffering();
  }

  // Asks AVFoundation to say when |stream| can take more. The block runs
  // repeatedly while the renderer is ready, so it stops itself on first call
  // and hands over to the owner sequence.
  void ArmRequest(StreamType stream) {
    Stream& state = StreamFor(stream);
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || state.armed || state.end_of_stream) {
      return;
    }
    state.armed = true;
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    auto fired = std::make_shared<std::atomic<bool>>(false);
    [renderer requestMediaDataWhenReadyOnQueue:RequestQueue()
                                    usingBlock:^{
                                      if (fired->exchange(true)) {
                                        return;
                                      }
                                      [renderer stopRequestingMediaData];
                                      (*poster)([weak, stream] {
                                        if (auto impl = weak.lock()) {
                                          impl->StreamFor(stream).armed = false;
                                          impl->DeliverNeedData(stream);
                                        }
                                      });
                                    }];
  }

  // Client callbacks are posted, never made from inside a renderer call.
  void NotifyNeedData(StreamType stream) {
    if (!RendererFor(stream) || StreamFor(stream).end_of_stream) {
      return;
    }
    Post([stream](Impl& impl) { impl.DeliverNeedData(stream); });
  }

  void DeliverNeedData(StreamType stream) {
    if (!RendererFor(stream) || StreamFor(stream).end_of_stream) {
      return;
    }
    if (IsReadyForMoreData(stream)) {
      client_->OnNeedData(stream);
    } else if (StreamFor(stream).held.empty()) {
      ArmRequest(stream);
    }
  }

  // HAVE_ENOUGH once every configured renderer reports enough data for a
  // reliable start; then latched, because that property toggles as queues
  // drain and refill. Only CheckUnderflow drops back to HAVE_NOTHING.
  void UpdateBuffering() {
    if (have_enough_) {
      return;
    }
    bool have_enough = true;
    if (video_renderer_ && !video_.end_of_stream) {
      have_enough &= video_renderer_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    if (audio_ && !audio_stream_.end_of_stream) {
      have_enough &= audio_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    if (!have_enough) {
      return;
    }
    have_enough_ = true;
    if (underflowed_) {
      underflowed_ = false;
      synchronizer_.rate = status_.rate;
    }
    Post([](Impl& impl) { impl.client_->OnBufferingStateChange(true); });
  }

  // Underflow, as RendererImpl handles it: when the clock reaches the end of
  // what a stream without end of stream has been given, stop the clock and
  // report HAVE_NOTHING; UpdateBuffering restarts it once data is back.
  void CheckUnderflow() {
    if (!have_enough_ || status_.rate == 0) {
      return;
    }
    double now = GetMediaTime().InSeconds();
    for (StreamType stream : {StreamType::kVideo, StreamType::kAudio}) {
      const Stream& state = StreamFor(stream);
      if (!RendererFor(stream) || state.end_of_stream || state.enqueued_end < 0) {
        continue;
      }
      if (state.enqueued_end - now < 0.05) {
        have_enough_ = false;
        underflowed_ = true;
        synchronizer_.rate = 0;
        client_->OnBufferingStateChange(false);
        return;
      }
    }
  }

  void ScheduleEndIfComplete() {
    if ((video_renderer_ && !video_.end_of_stream) || (audio_ && !audio_stream_.end_of_stream) ||
        !video_.held.empty() || !audio_stream_.held.empty() || end_observer_) {
      return;
    }
    MediaTime end = video_.last_end;
    if (audio_stream_.last_end.IsValid() &&
        (!end.IsValid() || audio_stream_.last_end.InSeconds() > end.InSeconds())) {
      end = audio_stream_.last_end;
    }
    if (!end.IsValid() || GetMediaTime().InSeconds() >= end.InSeconds()) {
      Post([](Impl& impl) { impl.FireEnded(); });
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    end_observer_ = [synchronizer_
        addBoundaryTimeObserverForTimes:@[ [NSValue valueWithCMTime:ToCMTime(end)] ]
                                  queue:RequestQueue()
                             usingBlock:^{
                               (*poster)([weak] {
                                 if (auto impl = weak.lock()) {
                                   impl->FireEnded();
                                 }
                               });
                             }];
  }

  void FireEnded() {
    if (ended_) {
      return;
    }
    ended_ = true;
    RemoveEndObserver();
    client_->OnEnded();
  }

  void RemoveEndObserver() {
    if (end_observer_) {
      [synchronizer_ removeTimeObserver:end_observer_];
      end_observer_ = nil;
    }
  }

  void OnDecodeFailed(NSError* error) {
    ++status_.decode_failures;
    client_->OnError(RendererError::kDecode, "video decode failed: " + Describe(error));
  }

  void CheckRendererStatus() {
    RendererStatus status = GetStatus();
    if (status.video == RenderingStatus::kFailed && !video_failure_reported_) {
      video_failure_reported_ = true;
      client_->OnError(RendererError::kDecode, "video renderer failed: " + status.video_error);
    }
    if (status.audio == RenderingStatus::kFailed && !audio_failure_reported_) {
      audio_failure_reported_ = true;
      client_->OnError(RendererError::kDecode, "audio renderer failed: " + status.audio_error);
    }
  }

  static dispatch_queue_t RequestQueue() {
    static dispatch_queue_t queue =
        dispatch_queue_create("parc.fairplay.renderer", DISPATCH_QUEUE_SERIAL);
    return queue;
  }

  FairPlayRendererClient* client_;
  std::shared_ptr<const PostTask> poster_;
  FairPlayCdm* cdm_ = nullptr;
  uint64_t observer_id_ = 0;

  std::optional<VideoConfig> video_config_;
  std::optional<AudioConfig> audio_config_;
  ScopedFormat video_clear_format_;
  ScopedFormat audio_clear_format_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> video_protected_formats_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> audio_protected_formats_;
  std::vector<id<AVContentKeyRecipient>> recipients_;

  AVSampleBufferRenderSynchronizer* synchronizer_ = nil;
  AVSampleBufferDisplayLayer* layer_ = nil;
  id<AVQueuedSampleBufferRendering> video_renderer_ = nil;
  AVSampleBufferAudioRenderer* audio_ = nil;
  PCFairPlayRendererObserver* observer_ = nil;
  std::vector<std::pair<NSObject*, NSString*>> observed_;
  std::vector<id> notification_tokens_;
  id end_observer_ = nil;
  id clock_observer_ = nil;

  Stream video_;
  Stream audio_stream_;
  MediaTime start_time_;
  bool waiting_reported_ = false;
  bool have_enough_ = false;
  bool underflowed_ = false;
  bool ended_ = false;
  bool video_failure_reported_ = false;
  bool audio_failure_reported_ = false;
  RendererStatus status_;
};

FairPlayRenderer::FairPlayRenderer(FairPlayRendererClient* client, PostTask post_task)
    : impl_(std::make_shared<Impl>(client, std::move(post_task))) {}

FairPlayRenderer::~FairPlayRenderer() {
  impl_->Shutdown();
}

Result FairPlayRenderer::Initialize(const std::optional<VideoConfig>& video,
                                    const std::optional<AudioConfig>& audio) {
  return impl_->Initialize(video, audio);
}

Result FairPlayRenderer::SetCdm(FairPlayCdm* cdm) {
  return impl_->SetCdm(cdm);
}

void* FairPlayRenderer::display_layer() const {
  return impl_->display_layer();
}

bool FairPlayRenderer::IsReadyForMoreData(StreamType stream) const {
  return impl_->IsReadyForMoreData(stream);
}

EnqueueResult FairPlayRenderer::Enqueue(StreamType stream, const EncodedSample& sample) {
  return impl_->Enqueue(stream, sample);
}

void FairPlayRenderer::SetEndOfStream(StreamType stream) {
  impl_->SetEndOfStream(stream);
}

void FairPlayRenderer::StartPlayingFrom(MediaTime time) {
  impl_->StartPlayingFrom(time);
}

void FairPlayRenderer::SetPlaybackRate(double rate) {
  impl_->SetPlaybackRate(rate);
}

void FairPlayRenderer::SetVolume(float volume) {
  impl_->SetVolume(volume);
}

void FairPlayRenderer::SetMuted(bool muted) {
  impl_->SetMuted(muted);
}

void FairPlayRenderer::Flush(std::function<void()> done) {
  impl_->Flush(std::move(done));
}

MediaTime FairPlayRenderer::GetMediaTime() const {
  return impl_->GetMediaTime();
}

RendererStatus FairPlayRenderer::GetStatus() const {
  return impl_->GetStatus();
}

void FairPlayRenderer::LoadVideoMetrics(std::function<void(const VideoMetrics&)> done) const {
  impl_->LoadVideoMetrics(std::move(done));
}

}  // namespace parc::fairplay

@implementation PCFairPlayRendererObserver {
  std::function<void(NSString*)> _handler;
}

- (instancetype)initWithHandler:(std::function<void(NSString*)>)handler {
  if ((self = [super init])) {
    _handler = std::move(handler);
  }
  return self;
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  _handler(keyPath);
}

@end

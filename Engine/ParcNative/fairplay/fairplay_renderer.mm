#include "fairplay_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

#include <algorithm>
#include <limits>
#include <atomic>
#include <deque>
#include <iterator>
#include <map>
#include <mutex>
#include <queue>
#include <utility>

#include "fairplay_bitstream.h"
#include "fairplay_key_session.h"
#include "fairplay_key_session_internal.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

using parc::fairplay::FairPlayRenderer;
using parc::fairplay::PostTask;

@interface AVSampleBufferDisplayLayer (ParcPrerollDecode)
- (void)prerollDecodeWithCompletionHandler:(void (^)(BOOL success))handler;
@end

static const CFStringRef kCryptorIV = CFSTR("CryptorIV");
static const CFStringRef kBytesOfClearDataCount = CFSTR("BytesOfClearDataCount");

@interface PCFairPlayRendererObserver : NSObject
- (instancetype)initWithHandler:(std::function<void(NSString*)>)handler;
@end

@interface PCFairPlayVideoHost : CALayer
@end

namespace parc::fairplay {
namespace {

constexpr double kEnoughAheadSeconds = 3;
constexpr double kHeldAheadSeconds = 4;
constexpr double kStallArmSeconds = 0.25;
constexpr double kAudioHandOffLeadSeconds = 0.25;
constexpr double kLateAnchorSeconds = 0.02;
constexpr size_t kUpcomingWindow = 16;

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
  void Swap(ScopedFormat& other) { std::swap(format_, other.format_); }

 private:
  CMFormatDescriptionRef format_ = nullptr;
};

struct RequestGate {
  std::mutex mutex;
  uint64_t current = 0;
};

NSString* DefaultOutputDeviceUid() {
  AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
                                        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioDeviceID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, &device) != noErr ||
      device == kAudioObjectUnknown) {
    return nil;
  }
  address.mSelector = kAudioDevicePropertyDeviceUID;
  CFStringRef uid = nullptr;
  size = sizeof(uid);
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &uid) != noErr || !uid) {
    return nil;
  }
  return (__bridge_transfer NSString*)uid;
}

bool AudioDeviceExists(NSString* uid) {
  AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslateUIDToDevice,
                                        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  CFStringRef qualifier = (__bridge CFStringRef)uid;
  AudioObjectID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  return AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof(qualifier), &qualifier, &size,
                                    &device) == noErr &&
         device != kAudioObjectUnknown;
}

constexpr AudioObjectPropertyAddress kAudioDeviceChanges[] = {
    {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
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

uint32_t DefaultSampleEntry(VideoCodec codec) {
  switch (codec) {
    case VideoCodec::kH264:
      return FourCC('a', 'v', 'c', '1');
    case VideoCodec::kHEVC:
      return FourCC('h', 'v', 'c', '1');
    case VideoCodec::kDolbyVision:
      return FourCC('d', 'v', 'h', '1');
    case VideoCodec::kAV1:
      return FourCC('a', 'v', '0', '1');
    case VideoCodec::kVP9:
      return FourCC('v', 'p', '0', '9');
  }
  return 0;
}

bool SampleEntryMatches(VideoCodec codec, uint32_t entry) {
  switch (codec) {
    case VideoCodec::kH264:
      return entry == FourCC('a', 'v', 'c', '1') || entry == FourCC('a', 'v', 'c', '3');
    case VideoCodec::kHEVC:
      return entry == FourCC('h', 'v', 'c', '1') || entry == FourCC('h', 'e', 'v', '1');
    case VideoCodec::kDolbyVision:
      return entry == FourCC('d', 'v', 'h', '1') || entry == FourCC('d', 'v', 'h', 'e');
    case VideoCodec::kAV1:
      return entry == FourCC('a', 'v', '0', '1') || entry == FourCC('d', 'a', 'v', '1');
    case VideoCodec::kVP9:
      return entry == FourCC('v', 'p', '0', '9');
  }
  return false;
}

uint32_t DecodableSampleEntry(uint32_t entry) {
  if (entry == FourCC('h', 'e', 'v', '1')) return FourCC('h', 'v', 'c', '1');
  if (entry == FourCC('a', 'v', 'c', '3')) return FourCC('a', 'v', 'c', '1');
  if (entry == FourCC('d', 'v', 'h', 'e')) return FourCC('d', 'v', 'h', '1');
  return entry;
}

bool RecordHasParameterSets(VideoCodec codec, const std::vector<uint8_t>& record) {
  if (codec == VideoCodec::kAV1 || codec == VideoCodec::kVP9) {
    return !record.empty();
  }
  if (codec == VideoCodec::kH264) {
    return record.size() >= 7 && (record[5] & 0x1f) > 0;
  }
  if (record.size() < 23) {
    return false;
  }
  bool vps = false, sps = false, pps = false;
  size_t pos = 23;
  for (uint8_t a = 0; a < record[22] && pos + 3 <= record.size(); ++a) {
    uint8_t type = record[pos] & 0x3f;
    uint32_t count = (uint32_t(record[pos + 1]) << 8) | record[pos + 2];
    vps |= type == 32 && count;
    sps |= type == 33 && count;
    pps |= type == 34 && count;
    pos += 3;
    for (uint32_t k = 0; k < count && pos + 2 <= record.size(); ++k) {
      pos += 2 + ((uint32_t(record[pos]) << 8) | record[pos + 1]);
    }
  }
  return vps && sps && pps;
}

std::vector<std::vector<uint8_t>> ParameterSetsInRecord(VideoCodec codec, const std::vector<uint8_t>& record) {
  std::vector<std::vector<uint8_t>> sets;
  auto take = [&](size_t* pos) {
    if (*pos + 2 > record.size()) return false;
    size_t length = (size_t(record[*pos]) << 8) | record[*pos + 1];
    if (*pos + 2 + length > record.size()) return false;
    sets.emplace_back(record.begin() + *pos + 2, record.begin() + *pos + 2 + length);
    *pos += 2 + length;
    return true;
  };
  if (codec == VideoCodec::kH264) {
    if (record.size() < 7) return sets;
    size_t pos = 6;
    for (int k = 0; k < (record[5] & 0x1f); ++k) {
      if (!take(&pos)) return sets;
    }
    if (pos >= record.size()) return sets;
    int pps = record[pos++];
    for (int k = 0; k < pps; ++k) {
      if (!take(&pos)) return sets;
    }
    return sets;
  }
  if (record.size() < 23) return sets;
  size_t pos = 23;
  for (uint8_t a = 0; a < record[22] && pos + 3 <= record.size(); ++a) {
    const uint8_t type = record[pos] & 0x3f;
    const uint32_t count = (uint32_t(record[pos + 1]) << 8) | record[pos + 2];
    pos += 3;
    for (uint32_t k = 0; k < count; ++k) {
      size_t before = sets.size();
      if (!take(&pos)) return sets;
      if (type < 32 || type > 34) sets.resize(before);
    }
  }
  return sets;
}

std::vector<std::vector<uint8_t>> ParameterSetsInSample(VideoCodec codec, const uint8_t* data, size_t size,
                                                        size_t length_size) {
  const bool avc = codec == VideoCodec::kH264;
  std::vector<std::vector<uint8_t>> sets;
  for (size_t pos = 0; pos + length_size <= size;) {
    size_t length = 0;
    for (size_t k = 0; k < length_size; ++k) length = (length << 8) | data[pos + k];
    pos += length_size;
    if (!length || length > size - pos) break;
    const uint8_t type = avc ? (data[pos] & 0x1f) : ((data[pos] >> 1) & 0x3f);
    if (avc ? (type == 7 || type == 8) : (type >= 32 && type <= 34)) {
      sets.emplace_back(data + pos, data + pos + length);
    }
    pos += length;
  }
  return sets;
}

uint32_t ConfigBox(VideoCodec codec) {
  switch (codec) {
    case VideoCodec::kH264:
      return FourCC('a', 'v', 'c', 'C');
    case VideoCodec::kHEVC:
    case VideoCodec::kDolbyVision:
      return FourCC('h', 'v', 'c', 'C');
    case VideoCodec::kAV1:
      return FourCC('a', 'v', '1', 'C');
    case VideoCodec::kVP9:
      return FourCC('v', 'p', 'c', 'C');
  }
  return 0;
}

bool IsEncrypted(const TrackEncryption& encryption) {
  return encryption.scheme != EncryptionScheme::kUnencrypted;
}

bool IsTransportStreamKeyId(const std::vector<uint8_t>& key_id) {
  return std::equal(key_id.begin(), key_id.end(), std::begin(kTransportStreamKeyId),
                    std::end(kTransportStreamKeyId) - 1);
}

uint32_t TransportStreamFormatType(VideoCodec codec) {
  return codec == VideoCodec::kH264 ? FourCC('z', 'a', 'v', 'c') : 0;
}

uint32_t TransportStreamFormatType(const AudioConfig& config) {
  if (config.ts_audio_type)
    return config.ts_audio_type;
  switch (config.codec) {
    case AudioCodec::kAAC: {
      const int type = AacSignaledObjectType(config.extra_data);
      return type == 5 ? FourCC('z', 'a', 'c', 'h') : type == 29 ? FourCC('z', 'a', 'c', 'p') : FourCC('z', 'a', 'a', 'c');
    }
    case AudioCodec::kAC3:
      return FourCC('z', 'a', 'c', '3');
    case AudioCodec::kEAC3:
      return FourCC('z', 'e', 'c', '3');
    default:
      return 0;
  }
}

NSDictionary* TransportStreamExtensions(CMFormatDescriptionRef clear, uint32_t type, uint32_t media_type) {
  NSMutableDictionary* extensions =
      [(__bridge NSDictionary*)CMFormatDescriptionGetExtensions(clear) mutableCopy] ?: [NSMutableDictionary dictionary];
  extensions[@"TransportStreamEncryptionInitData"] =
      ToNSData(TransportStreamEncryptionInitData(type, media_type));
  return extensions;
}

}

class FairPlayRenderer::Impl : public std::enable_shared_from_this<FairPlayRenderer::Impl> {
 public:
  Impl(FairPlayRendererClient* client, PostTask post_task)
      : client_(client), poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() {
    Shutdown();
    if (CMTimebaseRef timebase = timebase_.exchange(nullptr)) {
      CFRelease(timebase);
    }
  }

  void Shutdown() {
    pending_cdm_ = nullptr;
    AttachCdm(nullptr);
    ReleaseOutgoingRecipients(nil);
    for (auto& [object, token] : notification_tokens_) {
      [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
    notification_tokens_.clear();
    if (audio_devices_listener_) {
      for (const AudioObjectPropertyAddress& address : kAudioDeviceChanges) {
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address, RequestQueue(),
                                               audio_devices_listener_);
      }
      audio_devices_listener_ = nil;
    }
    if (observer_) {
      for (auto& [object, key_path] : observed_) {
        [object removeObserver:observer_ forKeyPath:key_path];
      }
      observed_.clear();
      observer_ = nil;
    }
    for (auto& [track, audio] : audio_) {
      if (audio.flushed_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:audio.flushed_token];
        audio.flushed_token = nil;
      }
    }
    RemoveEndObserver();
    RemoveSizeObservers();
    RemoveStallObserver();
    if (clock_observer_) {
      [synchronizer_ removeTimeObserver:clock_observer_];
      clock_observer_ = nil;
    }
    for (StreamId stream : Streams()) {
      StopRequest(stream);
    }
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
    ++initialize_attempt_;
    natural_width_ = 0;
    natural_height_ = 0;
    reported_width_ = 0;
    reported_height_ = 0;
    size_change_pending_ = false;
    video_config_ = video;
    audio_.clear();
    next_audio_track_ = 0;
    std::string error;
    if (video) {
      if (Result result = ConfigureVideo(*video, &error); !result.ok()) {
        return result;
      }
    }
    if (audio) {
      if (Result result = ConfigureAudio(audio_[next_audio_track_++], *audio, &error); !result.ok()) {
        return result;
      }
    }
    synchronizer_ = [[AVSampleBufferRenderSynchronizer alloc] init];
    if (CMTimebaseRef timebase = synchronizer_.timebase) {
      CFRetain(timebase);
      timebase_.store(timebase);
    }
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
    if (video) {
      if (Result result = CreateVideoRenderer(); !result.ok()) {
        AbandonInitialize();
        return result;
      }
    }
    if (audio) {
      if (Result result = CreateAudioRenderer(0); !result.ok()) {
        AbandonInitialize();
        return result;
      }
    }
    if (FairPlayCdm* cdm = pending_cdm_) {
      pending_cdm_ = nullptr;
      if (Result result = AttachCdm(cdm); !result.ok()) {
        return result;
      }
    }
    return Result::Ok();
  }

  Result AddVideo(const VideoConfig& config) {
    if (!synchronizer_ || video_renderer_) {
      return Result::Error(Exception::kInvalidState, synchronizer_ ? "there is video already" : "not initialized");
    }
    std::string error;
    Result result = ConfigureVideo(config, &error);
    if (result.ok()) {
      result = CreateVideoRenderer();
    }
    if (!result.ok()) {
      video_config_.reset();
      video_clear_format_.Reset(nullptr);
      video_protected_formats_.clear();
      return result;
    }
    ResetVideoFrameAvailability();
    video_reset_pending_ = true;
    OnStreamAdded(StreamType::kVideo);
    return JoinCdm(layer_);
  }

  Result ReplaceVideo(const VideoConfig& config) {
    if (!video_renderer_) {
      return Result::Error(Exception::kInvalidState, "no video stream");
    }
    std::string error;
    if (Result result = ConfigureVideo(config, &error); !result.ok()) {
      return result;
    }
    CountPassedVideo();
    video_due_ = {};
    StopRequest(StreamType::kVideo);
    [video_renderer_ flush];
    video_upcoming_.clear();
    [outgoing_video_renderer_ flush];
    RemoveSizeObservers();
    size_change_pending_ = natural_width_ != reported_width_ || natural_height_ != reported_height_;
    video_ = Stream();
    video_.start = GetMediaTime().InSeconds();
    const auto streams = Streams();
    if (waiting_reported_ && std::none_of(streams.begin(), streams.end(), [this](StreamId stream) {
          return StreamFor(stream) && !StreamFor(stream)->held.empty();
        })) {
      waiting_reported_ = false;
    }
    ResetVideoFrameAvailability();
    video_reset_pending_ = true;
    RemoveEndObserver();
    UpdateBuffering();
    NotifyNeedData(StreamType::kVideo);
    return Result::Ok();
  }

  Result AddAudio(const AudioConfig& config, uint32_t* track) {
    if (!synchronizer_) {
      return Result::Error(Exception::kInvalidState, "not initialized");
    }
    const uint32_t id = next_audio_track_++;
    std::string error;
    Result result = ConfigureAudio(audio_[id], config, &error);
    if (result.ok()) {
      result = CreateAudioRenderer(id);
    }
    if (!result.ok()) {
      audio_.erase(id);
      return result;
    }
    *track = id;
    OnStreamAdded({StreamType::kAudio, id});
    return JoinCdm(audio_[id].renderer);
  }

  void RemoveAudio(uint32_t track) {
    AudioTrack* audio = Audio(track);
    if (!audio) {
      return;
    }
    AVSampleBufferAudioRenderer* renderer = audio->renderer;
    StopRequest({StreamType::kAudio, track});
    if (renderer) {
      [renderer flush];
      [synchronizer_ removeRenderer:renderer atTime:CMTimebaseGetTime(synchronizer_.timebase) completionHandler:nil];
      StopObserving(renderer);
    }
    if (auto outgoing = outgoing_audio_.find(track); outgoing != outgoing_audio_.end()) {
      for (AVSampleBufferAudioRenderer* leaving : outgoing->second) {
        [leaving flush];
      }
    }
    if (audio->flushed_token) {
      [[NSNotificationCenter defaultCenter] removeObserver:audio->flushed_token];
    }
    auto recipient = std::find(recipients_.begin(), recipients_.end(), (id<AVContentKeyRecipient>)renderer);
    if (recipient != recipients_.end()) {
      DetachContentKeyRecipient(cdm_->impl(), *recipient);
      recipients_.erase(recipient);
    }
    audio_.erase(track);
    RemoveEndObserver();
    UpdateBuffering();
    ScheduleEndIfComplete();
  }

  void OnStreamAdded(StreamId stream) {
    StreamFor(stream)->start = GetMediaTime().InSeconds();
    renderers_have_samples_ = false;
    RemoveEndObserver();
    if (std::exchange(have_enough_, false)) {
      PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(false); });
    }
    UpdateBuffering();
    NotifyNeedData(stream);
  }

  Result JoinCdm(id renderer) {
    if (!cdm_) {
      return Result::Ok();
    }
    if (![renderer conformsToProtocol:@protocol(AVContentKeyRecipient)]) {
      return Result::Error(Exception::kNotSupported, "renderer is not an AVContentKeyRecipient on this OS");
    }
    Result result = AttachContentKeyRecipient(cdm_->impl(), (id<AVContentKeyRecipient>)renderer);
    if (result.ok()) {
      recipients_.push_back((id<AVContentKeyRecipient>)renderer);
      renderers_were_recipients_ = true;
    }
    return result;
  }

  Result CreateVideoRenderer() {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!host_) {
      host_ = [PCFairPlayVideoHost layer];
    }
    layer_ = [AVSampleBufferDisplayLayer layer];
    video_upcoming_.clear();
    layer_.videoGravity = AVLayerVideoGravityResize;
    layer_.preventsCapture = YES;
    layer_.geometryFlipped = YES;
    layer_.frame = host_.bounds;
    [host_ insertSublayer:layer_ atIndex:0];
    [host_ setNeedsLayout];
    [CATransaction commit];
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
    if (Result result = AddToSynchronizer(video_renderer_, "video"); !result.ok()) {
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      [layer_ removeFromSuperlayer];
      [CATransaction commit];
      layer_ = nil;
      video_renderer_ = nil;
      return result;
    }
    Observe(video_renderer_, @"status");
    Observe(video_renderer_, @"error");
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    AddNotification(center,
                    AVSampleBufferDisplayLayerOutputObscuredDueToInsufficientExternalProtectionDidChangeNotification,
                    layer_, [](Impl& impl, NSNotification*) { impl.CheckRendererStatus(); });
    AddNotification(center, decode_failed, video_renderer_, [decode_error_key](Impl& impl,
                                                                               NSNotification* note) {
      impl.OnDecodeFailed(note.userInfo[decode_error_key]);
    });
    AddNotification(center, requires_flush, video_renderer_, [](Impl& impl, NSNotification*) {
      impl.ResumeVideoDecoding();
      impl.CheckRendererStatus();
    });
    if (UsesDisplayReadinessNotification()) {
      if (@available(macOS 14.4, *)) {
        AddNotification(center, AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification, layer_,
                        [](Impl& impl, NSNotification*) { impl.UpdateBuffering(); });
      }
    }
    return Result::Ok();
  }

  Result CreateAudioRenderer(uint32_t track) {
    AudioTrack& audio = audio_[track];
    audio.renderer = [[AVSampleBufferAudioRenderer alloc] init];
    audio.renderer.volume = volume_;
    audio.renderer.muted = muted_;
    if (output_device_uid_) {
      audio.renderer.audioOutputDeviceUniqueID = output_device_uid_;
    }
    UpdatePitchAlgorithm();
    if (Result result = AddToSynchronizer(audio.renderer, "audio"); !result.ok()) {
      audio.renderer = nil;
      return result;
    }
    Observe(audio.renderer, @"status");
    Observe(audio.renderer, @"error");
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    std::shared_ptr<std::atomic<uint64_t>> flushes = flush_count_;
    audio.flushed_token = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification
                    object:audio.renderer
                     queue:nil
                usingBlock:^(NSNotification* note) {
                  const uint64_t generation = flushes->load();
                  NSValue* value = note.userInfo[AVSampleBufferAudioRendererFlushTimeKey];
                  const CMTime time = value ? value.CMTimeValue : kCMTimeInvalid;
                  (*poster)([weak, generation, time, track] {
                    auto impl = weak.lock();
                    if (impl && impl->generation_ == generation) {
                      impl->OnAudioFlushedAutomatically(
                          track, CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : impl->GetMediaTime().InSeconds());
                    }
                  });
                }];
    return Result::Ok();
  }

  Result AddToSynchronizer(id<AVQueuedSampleBufferRendering> renderer, const char* kind) {
    NSString* reason = nil;
    @try {
      [synchronizer_ addRenderer:renderer];
    } @catch (NSException* exception) {
      reason = exception.reason ?: exception.name;
    }
    if (!reason) {
      return Result::Ok();
    }
    return Result::Error(Exception::kNotSupported,
                         std::string("the synchronizer refused the ") + kind + " renderer: " + reason.UTF8String);
  }

  void AbandonInitialize() {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer_ removeFromSuperlayer];
    [CATransaction commit];
    layer_ = nil;
    video_renderer_ = nil;
    for (auto& [track, audio] : audio_) {
      audio.renderer = nil;
    }
    FairPlayCdm* pending_cdm = pending_cdm_;
    Shutdown();
    pending_cdm_ = pending_cdm;
    audio_.clear();
    synchronizer_ = nil;
    if (CMTimebaseRef timebase = timebase_.exchange(nullptr)) {
      CFRelease(timebase);
    }
  }

  Result SetCdm(FairPlayCdm* cdm) {
    Result result = Result::Ok();
    if (!synchronizer_) {
      pending_cdm_ = cdm;
    } else {
      result = AttachCdm(cdm);
    }
    if (result.ok() && cdm && cdm_detached_) {
      cdm_detached_ = false;
      if (cdm_) {
        OnKeysChanged();
      }
    }
    return result;
  }

  void DetachCdm() { cdm_detached_ = true; }

  Result AttachCdm(FairPlayCdm* cdm) {
    if (cdm == cdm_) {
      return Result::Ok();
    }
    const bool replacing = cdm && cdm_;
    if (cdm_) {
      cdm_->RemoveKeysChangedObserver(observer_id_);
      observer_id_ = 0;
      for (id<AVContentKeyRecipient> recipient : recipients_) {
        if (replacing) {
          outgoing_recipients_.push_back({cdm_, recipient});
        } else {
          DetachContentKeyRecipient(cdm_->impl(), recipient);
        }
      }
      recipients_.clear();
      cdm_ = nullptr;
    }
    if (!cdm) {
      ReleaseOutgoingRecipients(nil);
      return Result::Ok();
    }
    const bool hand_off =
        replacing || renderers_were_recipients_ || status_.video_enqueued || status_.audio_enqueued;
    if (hand_off) {
      if (Result result = ReplaceRenderers(); !result.ok()) {
        RetireLeavingAudio(GetMediaTime().InSeconds());
        return result;
      }
    }
    std::vector<id<AVContentKeyRecipient>> joined;
    Result result = Result::Ok();
    std::vector<id> renderers{layer_};
    for (auto& [track, audio] : audio_) {
      renderers.push_back(audio.renderer);
    }
    for (id object : renderers) {
      if (!object) {
        continue;
      }
      if (![object conformsToProtocol:@protocol(AVContentKeyRecipient)]) {
        result = Result::Error(Exception::kNotSupported,
                               "renderer is not an AVContentKeyRecipient on this OS");
        break;
      }
      result = AttachContentKeyRecipient(cdm->impl(), (id<AVContentKeyRecipient>)object);
      if (!result.ok()) {
        break;
      }
      joined.push_back((id<AVContentKeyRecipient>)object);
      renderers_were_recipients_ = true;
    }
    if (!result.ok()) {
      for (id<AVContentKeyRecipient> recipient : joined) {
        DetachContentKeyRecipient(cdm->impl(), recipient);
      }
      RetireLeavingAudio(GetMediaTime().InSeconds());
      return result;
    }
    cdm_ = cdm;
    recipients_ = std::move(joined);
    std::weak_ptr<Impl> weak = weak_from_this();
    observer_id_ = cdm_->AddKeysChangedObserver([weak] {
      if (auto impl = weak.lock()) {
        impl->OnKeysChanged();
      }
    });
    if (hand_off) {
      Replay();
    }
    OnKeysChanged();
    if (hand_off) {
      for (StreamId stream : Streams()) {
        NotifyNeedData(stream);
      }
    }
    return Result::Ok();
  }

  Result ReplaceRenderers() {
    for (StreamId stream : Streams()) {
      StopRequest(stream);
      StreamFor(stream)->armed = false;
    }
    renderers_were_recipients_ = false;
    Result result = Result::Ok();
    if (layer_) {
      StopObserving(video_renderer_);
      StopObserving(layer_);
      if (outgoing_layer_ && !LayerHasFrame()) {
        RemoveLayer(layer_, video_renderer_);
      } else {
        RetireOutgoingLayer();
        outgoing_layer_ = layer_;
        outgoing_video_renderer_ = video_renderer_;
      }
      video_replayed_ = 0;
      result = CreateVideoRenderer();
      ResetVideoFrameAvailability();
    }
    for (auto& [track, audio] : audio_) {
      StopObserving(audio.renderer);
      if (audio.flushed_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:audio.flushed_token];
        audio.flushed_token = nil;
      }
      if (audio.renderer) {
        outgoing_audio_[track].push_back(audio.renderer);
        leaving_audio_.push_back({track, audio.renderer});
      }
      audio.renderer = nil;
      if (result.ok()) {
        result = CreateAudioRenderer(track);
      }
    }
    return result;
  }

  void Replay() {
    const double now = GetMediaTime().InSeconds();
    if (video_renderer_) {
      bool from_keyframe = false;
      for (size_t i = 0; i < video_.submitted.size(); ++i) {
        const Submitted& entry = video_.submitted[i];
        from_keyframe |= entry.keyframe;
        if (!from_keyframe) {
          continue;
        }
        if (HoldRedelivered(StreamType::kVideo, i)) {
          break;
        }
        if (entry.end <= now) {
          SetDoNotDisplay(entry.buffer);
        }
        EnqueueVideo(entry.buffer);
        RequestVideoFrameAvailability(entry.buffer);
        ++status_.redelivered;
        ++video_replayed_;
      }
    }
    std::map<uint32_t, double> leaves;
    for (auto& [track, audio] : audio_) {
      Stream& state = audio.stream;
      auto earlier = audio_outgoing_end_.find(track);
      const double from = std::max(now + kAudioHandOffLeadSeconds,
                                   earlier == audio_outgoing_end_.end() ? now : earlier->second);
      double leave = std::max(from, state.enqueued_end);
      bool replaying = false;
      state.queued_end = -std::numeric_limits<double>::infinity();
      for (size_t i = 0; i < state.submitted.size(); ++i) {
        const Submitted& entry = state.submitted[i];
        if (!replaying && entry.start < from) {
          continue;
        }
        if (!replaying) {
          leave = entry.start;
          replaying = true;
        }
        if (HoldRedelivered({StreamType::kAudio, track}, i)) {
          break;
        }
        [audio.renderer enqueueSampleBuffer:entry.buffer];
        NoteAudioQueued(state, entry.start, entry.end);
        ++status_.redelivered;
      }
      leaves[track] = leave;
      audio_outgoing_end_[track] = std::min(leave, state.enqueued_end);
    }
    for (auto& [track, renderer] : std::exchange(leaving_audio_, {})) {
      RetireOutgoingAudio(track, renderer, leaves.contains(track) ? leaves[track] : now);
    }
  }

  void RetireOutgoingAudio(uint32_t track, AVSampleBufferAudioRenderer* renderer, double leave) {
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    [synchronizer_ removeRenderer:renderer
                           atTime:ToCMTime(MediaTime::FromMicroseconds(int64_t(leave * 1e6)))
                completionHandler:^(BOOL removed) {
                  if (!removed) {
                    return;
                  }
                  (*poster)([weak, track, renderer] {
                    if (auto impl = weak.lock()) {
                      impl->DropOutgoingAudio(track, renderer);
                    }
                  });
                }];
  }

  void RetireLeavingAudio(double now) {
    for (auto& [track, renderer] : std::exchange(leaving_audio_, {})) {
      RetireOutgoingAudio(track, renderer, now);
    }
  }

  void ReleaseOutgoingRecipients(id renderer) {
    for (auto it = outgoing_recipients_.begin(); it != outgoing_recipients_.end();) {
      if (!renderer || it->second == renderer) {
        DetachContentKeyRecipient(it->first->impl(), it->second);
        it = outgoing_recipients_.erase(it);
      } else {
        ++it;
      }
    }
  }

  void DropOutgoingAudio(uint32_t track, AVSampleBufferAudioRenderer* renderer) {
    ReleaseOutgoingRecipients(renderer);
    auto it = outgoing_audio_.find(track);
    if (it == outgoing_audio_.end()) {
      return;
    }
    std::erase(it->second, renderer);
    if (it->second.empty()) {
      outgoing_audio_.erase(it);
      audio_outgoing_end_.erase(track);
    }
  }

  void RemoveLayer(AVSampleBufferDisplayLayer* layer, id<AVQueuedSampleBufferRendering> renderer) {
    [synchronizer_ removeRenderer:renderer atTime:CMTimebaseGetTime(synchronizer_.timebase) completionHandler:nil];
    ReleaseOutgoingRecipients(layer);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer removeFromSuperlayer];
    [CATransaction commit];
  }

  void RetireOutgoingLayer() {
    if (!outgoing_layer_) {
      return;
    }
    AVSampleBufferDisplayLayer* layer = std::exchange(outgoing_layer_, nil);
    RemoveLayer(layer, std::exchange(outgoing_video_renderer_, nil));
    if (@available(macOS 14.4, *)) {
      const int64_t replayed = static_cast<int64_t>(std::exchange(video_replayed_, 0));
      std::weak_ptr<Impl> weak = weak_from_this();
      std::shared_ptr<const PostTask> poster = poster_;
      [layer.sampleBufferRenderer loadVideoPerformanceMetricsWithCompletionHandler:^(AVVideoPerformanceMetrics* metrics) {
        (void)layer;
        if (!metrics) {
          return;
        }
        VideoMetrics retired;
        retired.total_frames = std::max<int64_t>(0, metrics.totalNumberOfFrames - replayed);
        retired.dropped_frames = metrics.numberOfDroppedFrames;
        retired.corrupted_frames = metrics.numberOfCorruptedFrames;
        retired.optimized_composited_frames = metrics.numberOfFramesDisplayedUsingOptimizedCompositing;
        retired.accumulated_frame_delay = metrics.totalAccumulatedFrameDelay;
        (*poster)([weak, retired] {
          if (auto impl = weak.lock()) {
            VideoMetrics& base = impl->retired_video_metrics_;
            base.total_frames += retired.total_frames;
            base.dropped_frames += retired.dropped_frames;
            base.corrupted_frames += retired.corrupted_frames;
            base.optimized_composited_frames += retired.optimized_composited_frames;
            base.accumulated_frame_delay += retired.accumulated_frame_delay;
          }
        });
      }];
    }
  }

  Result Reconfigure(const VideoConfig& config) {
    if (!video_renderer_) {
      return Result::Error(Exception::kInvalidState, "no video stream");
    }
    std::string error;
    return ConfigureVideo(config, &error);
  }

  Result Reconfigure(const AudioConfig& config, uint32_t track) {
    AudioTrack* audio = Audio(track);
    if (!audio) {
      return Result::Error(Exception::kInvalidState, "no audio stream");
    }
    std::string error;
    return ConfigureAudio(*audio, config, &error);
  }

  void* display_layer() const { return (__bridge void*)host_; }

  void RemoveDisplayedImage() {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (AVSampleBufferDisplayLayer* layer : {layer_, outgoing_layer_}) {
      if (@available(macOS 14.0, *)) {
        [layer.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
      } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [layer flushAndRemoveImage];
#pragma clang diagnostic pop
      }
    }
    [CATransaction commit];
    video_upcoming_.clear();
  }

  bool IsReadyForMoreData(StreamId stream) {
    const Stream* state = StreamFor(stream);
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || state->end_of_stream) {
      return false;
    }
    if (!state->held.empty()) {
      return state->given_end - GetMediaTime().InSeconds() < kHeldAheadSeconds;
    }
    const bool ready = renderer.readyForMoreMediaData;
    if (!ready) {
      ArmRequest(stream);
    }
    return ready;
  }

  EnqueueResult Enqueue(StreamId stream, const EncodedSample& sample) {
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || StreamFor(stream)->end_of_stream) {
      return EnqueueResult::kRejected;
    }
    Stream& state = *StreamFor(stream);
    if (stream.type == StreamType::kAudio && sample.duration.IsValid() &&
        sample.pts.InSeconds() + sample.duration.InSeconds() <= state.start) {
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
    held.start = sample.pts.InSeconds();
    held.end = end.InSeconds();
    held.keyframe = stream.type == StreamType::kAudio || sample.is_keyframe;
    if (stream.type == StreamType::kVideo && size_change_pending_) {
      ArmSizeObserver(sample.pts);
    }
    state.given_end = std::max(state.given_end, held.end);
    if (!state.held.empty() || !Submit(stream, held)) {
      state.held.push_back(std::move(held));
      if (!waiting_reported_) {
        waiting_reported_ = true;
        PostInGeneration([](Impl& impl) { impl.client_->OnWaitingForKey(); });
      }
      UpdateBuffering();
      return EnqueueResult::kWaitingForKey;
    }
    if (!renderer.readyForMoreMediaData) {
      ArmRequest(stream);
    }
    UpdateBuffering();
    return EnqueueResult::kEnqueued;
  }

  void SetEndOfStream(StreamId stream) {
    if (!RendererFor(stream) || StreamFor(stream)->end_of_stream) {
      return;
    }
    Stream& state = *StreamFor(stream);
    state.end_of_stream = true;
    StopRequest(stream);
    state.armed = false;
    UpdateBuffering();
    ScheduleEndIfComplete();
  }

  void StartPlayingFrom(MediaTime time) {
    start_time_ = time;
    anchor_.reset();
    follows_ = true;
    clock_ran_ = false;
    ended_ = false;
    have_enough_ = false;
    renderers_have_samples_ = false;
    ResetVideoFrameAvailability();
    video_reset_pending_ = video_renderer_ != nil;
    clock_held_ = true;
    RemoveStallObserver();
    [synchronizer_ setRate:0 time:ToCMTime(time)];
    for (const Submitted& sample : video_.submitted) {
      RequestVideoFrameAvailability(sample.buffer);
    }
    for (StreamId stream : Streams()) {
      StreamFor(stream)->start = time.InSeconds();
      StreamFor(stream)->has_samples = false;
      NotifyNeedData(stream);
    }
    UpdateBuffering();
  }

  void SetPlaybackRate(double rate) {
    anchor_.reset();
    follows_ = false;
    SetRate(rate);
  }

  bool SetPlaybackRateAt(double rate, MediaTime time, int64_t host_time_us) {
    if (!follows_) {
      return false;
    }
    anchor_ = Anchor{ToCMTime(time), CMTimeMake(host_time_us, 1000000)};
    SetRate(rate);
    return true;
  }

  void SetRate(double rate) {
    status_.rate = static_cast<float>(rate);
    UpdatePitchAlgorithm();
    if (!clock_held_) {
      RunClock();
    }
  }

  void RunClock() {
    std::optional<Anchor> anchor = std::exchange(anchor_, std::nullopt);
    if (anchor && !clock_ran_ && status_.rate > 0) {
      const double now = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()));
      const double at = CMTimeGetSeconds(anchor->time) +
                        (now - CMTimeGetSeconds(anchor->host_time)) * status_.rate;
      if (at > start_time_.InSeconds() + kLateAnchorSeconds) {
        anchor.reset();
      }
    }
    clock_ran_ |= status_.rate > 0;
    if (anchor) {
      [synchronizer_ setRate:status_.rate time:anchor->time atHostTime:anchor->host_time];
    } else if (synchronizer_.rate != status_.rate) {
      synchronizer_.rate = status_.rate;
    }
  }

  void SetPreservesPitch(bool preserves_pitch) {
    preserves_pitch_ = preserves_pitch;
    UpdatePitchAlgorithm();
  }

  void UpdatePitchAlgorithm() {
    const float rate = status_.rate;
    NSString* algorithm = (!preserves_pitch_ || rate == 0 || rate == 1)
                              ? AVAudioTimePitchAlgorithmVarispeed
                              : AVAudioTimePitchAlgorithmSpectral;
    for (auto& [track, audio] : audio_) {
      if (audio.renderer && ![audio.renderer.audioTimePitchAlgorithm isEqualToString:algorithm]) {
        audio.renderer.audioTimePitchAlgorithm = algorithm;
      }
    }
  }

  void SetVolume(float volume) {
    volume_ = volume;
    for (AVSampleBufferAudioRenderer* renderer : AudioRenderers()) {
      renderer.volume = volume;
    }
  }
  void SetMuted(bool muted) {
    muted_ = muted;
    for (AVSampleBufferAudioRenderer* renderer : AudioRenderers()) {
      renderer.muted = muted;
    }
  }

  std::vector<AVSampleBufferAudioRenderer*> AudioRenderers() const {
    std::vector<AVSampleBufferAudioRenderer*> renderers;
    for (const auto& [track, audio] : audio_) {
      renderers.push_back(audio.renderer);
    }
    for (const auto& [track, outgoing] : outgoing_audio_) {
      renderers.insert(renderers.end(), outgoing.begin(), outgoing.end());
    }
    return renderers;
  }
  Result SetAudioOutputDevice(const std::string& unique_id) {
    if (unique_id.empty() && !output_device_uid_) {
      return Result::Ok();
    }
    NSString* uid = unique_id.empty() ? DefaultOutputDeviceUid() : @(unique_id.c_str());
    if (!uid.length) {
      return Result::Error(Exception::kNotSupported, "no default audio output device");
    }
    follows_default_output_ = unique_id.empty();
    RouteAudio(uid);
    WatchAudioDevices();
    OnAudioDevicesChanged();
    return Result::Ok();
  }

  void RouteAudio(NSString* uid) {
    output_device_uid_ = uid;
    for (AVSampleBufferAudioRenderer* renderer : AudioRenderers()) {
      renderer.audioOutputDeviceUniqueID = uid;
    }
  }

  void WatchAudioDevices() {
    if (audio_devices_listener_) {
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    audio_devices_listener_ = ^(UInt32, const AudioObjectPropertyAddress*) {
      (*poster)([weak] {
        if (auto impl = weak.lock()) {
          impl->OnAudioDevicesChanged();
        }
      });
    };
    for (const AudioObjectPropertyAddress& address : kAudioDeviceChanges) {
      AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address, RequestQueue(), audio_devices_listener_);
    }
  }

  void OnAudioDevicesChanged() {
    if (!output_device_uid_ || (!follows_default_output_ && AudioDeviceExists(output_device_uid_))) {
      return;
    }
    follows_default_output_ = true;
    NSString* uid = DefaultOutputDeviceUid();
    if (uid.length && ![uid isEqualToString:output_device_uid_]) {
      RouteAudio(uid);
    }
  }

  void Flush(std::function<void()> done) {
    CountPassedVideo();
    video_due_ = {};
    synchronizer_.rate = 0;
    status_.rate = 0;
    anchor_.reset();
    follows_ = false;
    RemoveEndObserver();
    RemoveSizeObservers();
    size_change_pending_ = natural_width_ != reported_width_ || natural_height_ != reported_height_;
    for (StreamId stream : Streams()) {
      StopRequest(stream);
      [RendererFor(stream) flush];
      *StreamFor(stream) = Stream();
    }
    video_upcoming_.clear();
    [outgoing_video_renderer_ flush];
    for (const auto& [track, outgoing] : outgoing_audio_) {
      for (AVSampleBufferAudioRenderer* renderer : outgoing) {
        [renderer flush];
      }
    }
    audio_outgoing_end_.clear();
    waiting_reported_ = false;
    ended_ = false;
    ++generation_;
    flush_count_->store(generation_);
    have_enough_ = false;
    renderers_have_samples_ = false;
    ResetVideoFrameAvailability();
    video_reset_pending_ = false;
    clock_held_ = true;
    RemoveStallObserver();
    Post([done](Impl&) { done(); });
  }

  MediaTime GetMediaTime() const {
    CMTimebaseRef timebase = timebase_.load();
    return timebase ? FromCMTime(CMTimebaseGetTime(timebase)) : MediaTime::Invalid();
  }

  RendererStatus GetStatus() const {
    RendererStatus status = status_;
    status.time = GetMediaTime();
    auto subtype = [](CMFormatDescriptionRef format) {
      return format ? CMFormatDescriptionGetMediaSubType(format) : 0;
    };
    status.video_format = subtype(video_clear_format_.get());
    auto last_protected = [](const auto& cache, const std::vector<uint8_t>& key) -> CMFormatDescriptionRef {
      auto it = cache.find(key);
      return it == cache.end() ? nullptr : it->second->get();
    };
    status.video_protected_format = subtype(last_protected(video_protected_formats_, video_protected_key_));
    if (video_renderer_) {
      if (@available(macOS 14.0, *)) {
        AVSampleBufferVideoRenderer* renderer = layer_.sampleBufferRenderer;
        status.video = Map(renderer.status);
        status.video_error = renderer.error ? Describe(renderer.error) : "";
        status.video_requires_flush = renderer.requiresFlushToResumeDecoding;
      } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status.video = Map(layer_.status);
        status.video_error = layer_.error ? Describe(layer_.error) : "";
        status.video_requires_flush = layer_.requiresFlushToResumeDecoding;
#pragma clang diagnostic pop
      }
      status.video_ready_for_display = legacy_video_frame_available_;
      if (UsesDisplayReadinessNotification()) {
        if (@available(macOS 14.4, *)) {
          status.video_ready_for_display = layer_.readyForDisplay;
        }
      }
      status.output_obscured = layer_.outputObscuredDueToInsufficientExternalProtection;
      status.video_has_enough = video_renderer_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    status.audio_renderers = audio_.size();
    for (AVSampleBufferAudioRenderer* renderer : AudioRenderers()) {
      NSString* uid = renderer.audioOutputDeviceUniqueID;
      status.audio_output_devices.push_back(uid ? uid.UTF8String : "");
    }
    if (!audio_.empty()) {
      const AudioTrack& audio = audio_.begin()->second;
      status.audio_format = subtype(audio.clear_format.get());
      status.audio_protected_format = subtype(last_protected(audio.protected_formats, audio.protected_key));
      status.audio = Map(audio.renderer.status);
      status.audio_error = audio.renderer.error ? Describe(audio.renderer.error) : "";
      status.audio_has_enough = audio.renderer.hasSufficientMediaDataForReliablePlaybackStart;
      status.audio_volume = audio.renderer.volume;
      status.audio_muted = audio.renderer.muted;
    }
    return status;
  }

  void LoadVideoMetrics(std::function<void(const VideoMetrics&)> done) {
    const int64_t frames_passed = static_cast<int64_t>(CountPassedVideo());
    if (@available(macOS 14.4, *)) {
      if (layer_) {
        std::shared_ptr<const PostTask> poster = poster_;
        std::weak_ptr<Impl> weak = weak_from_this();
        [layer_.sampleBufferRenderer
            loadVideoPerformanceMetricsWithCompletionHandler:^(AVVideoPerformanceMetrics* metrics) {
              VideoMetrics result;
              result.frames_passed = frames_passed;
              if (metrics) {
                result.available = true;
                result.total_frames = metrics.totalNumberOfFrames;
                result.dropped_frames = metrics.numberOfDroppedFrames;
                result.corrupted_frames = metrics.numberOfCorruptedFrames;
                result.optimized_composited_frames =
                    metrics.numberOfFramesDisplayedUsingOptimizedCompositing;
                result.accumulated_frame_delay = metrics.totalAccumulatedFrameDelay;
              }
              (*poster)([weak, done, result]() mutable {
                if (auto impl = weak.lock(); impl && result.available) {
                  const VideoMetrics& base = impl->retired_video_metrics_;
                  result.total_frames += base.total_frames;
                  result.dropped_frames += base.dropped_frames;
                  result.corrupted_frames += base.corrupted_frames;
                  result.optimized_composited_frames += base.optimized_composited_frames;
                  result.accumulated_frame_delay += base.accumulated_frame_delay;
                }
                done(result);
              });
            }];
        return;
      }
    }
    VideoMetrics result;
    result.frames_passed = frames_passed;
    (*poster_)([done, result] { done(result); });
  }

 private:
  struct Held {
    CMSampleBufferRef buffer = nullptr;
    bool encrypted = false;
    std::vector<uint8_t> key_id;
    double start = 0;
    double end = 0;
    bool keyframe = true;
    bool redelivered = false;

    Held() = default;
    Held(Held&& other) noexcept
        : buffer(other.buffer),
          encrypted(other.encrypted),
          key_id(std::move(other.key_id)),
          start(other.start),
          end(other.end),
          keyframe(other.keyframe),
          redelivered(other.redelivered) {
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
        start = other.start;
        end = other.end;
        keyframe = other.keyframe;
        redelivered = other.redelivered;
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

  struct Submitted {
    CMSampleBufferRef buffer = nullptr;
    double start = 0;
    double end = 0;
    bool keyframe = true;
    bool encrypted = false;
    std::vector<uint8_t> key_id;

    Submitted(CMSampleBufferRef retained, double start, double end, bool keyframe, bool encrypted,
              std::vector<uint8_t> key_id)
        : buffer(retained),
          start(start),
          end(end),
          keyframe(keyframe),
          encrypted(encrypted),
          key_id(std::move(key_id)) {}
    Submitted(const Submitted&) = delete;
    Submitted& operator=(const Submitted&) = delete;
    Submitted(Submitted&& other) noexcept
        : buffer(other.buffer),
          start(other.start),
          end(other.end),
          keyframe(other.keyframe),
          encrypted(other.encrypted),
          key_id(std::move(other.key_id)) {
      other.buffer = nullptr;
    }
    Submitted& operator=(Submitted&& other) noexcept {
      if (this != &other) {
        if (buffer) {
          CFRelease(buffer);
        }
        buffer = other.buffer;
        start = other.start;
        end = other.end;
        keyframe = other.keyframe;
        encrypted = other.encrypted;
        key_id = std::move(other.key_id);
        other.buffer = nullptr;
      }
      return *this;
    }
    ~Submitted() {
      if (buffer) {
        CFRelease(buffer);
      }
    }
  };

  struct Stream {
    std::deque<Held> held;
    std::deque<Submitted> submitted;
    bool end_of_stream = false;
    bool armed = false;
    MediaTime last_end;
    double enqueued_end = -1;
    double given_end = -1;
    double queued_end = -std::numeric_limits<double>::infinity();
    double start = -std::numeric_limits<double>::infinity();
    bool has_samples = false;
  };

  struct AudioTrack {
    AVSampleBufferAudioRenderer* renderer = nil;
    AudioConfig config;
    Stream stream;
    const std::shared_ptr<RequestGate> gate = std::make_shared<RequestGate>();
    ScopedFormat clear_format;
    std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> protected_formats;
    std::vector<uint8_t> protected_key;
    bool awaiting_config = false;
    bool failure_reported = false;
    id flushed_token = nil;
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

  AudioTrack* Audio(uint32_t track) {
    auto it = audio_.find(track);
    return it == audio_.end() ? nullptr : &it->second;
  }
  const AudioTrack* Audio(uint32_t track) const {
    auto it = audio_.find(track);
    return it == audio_.end() ? nullptr : &it->second;
  }
  Stream* StreamFor(StreamId stream) {
    if (stream.type == StreamType::kVideo) {
      return &video_;
    }
    AudioTrack* audio = Audio(stream.audio_track);
    return audio ? &audio->stream : nullptr;
  }
  const Stream* StreamFor(StreamId stream) const { return const_cast<Impl*>(this)->StreamFor(stream); }
  id<AVQueuedSampleBufferRendering> RendererFor(StreamId stream) const {
    if (stream.type == StreamType::kVideo) {
      return video_renderer_;
    }
    const AudioTrack* audio = Audio(stream.audio_track);
    return audio ? audio->renderer : nil;
  }
  std::vector<StreamId> Streams() const {
    std::vector<StreamId> streams{StreamType::kVideo};
    for (const auto& [track, audio] : audio_) {
      streams.push_back({StreamType::kAudio, track});
    }
    return streams;
  }

  void Post(std::function<void(Impl&)> task) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, task] {
      if (auto impl = weak.lock()) {
        task(*impl);
      }
    });
  }

  void PostInGeneration(std::function<void(Impl&)> task) {
    std::weak_ptr<Impl> weak = weak_from_this();
    uint64_t generation = generation_;
    (*poster_)([weak, task, generation] {
      if (auto impl = weak.lock(); impl && impl->generation_ == generation) {
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
    notification_tokens_.push_back({object, token});
  }

  void StopObserving(id object) {
    for (auto it = observed_.begin(); it != observed_.end();) {
      if (it->first == object) {
        [object removeObserver:observer_ forKeyPath:it->second];
        it = observed_.erase(it);
      } else {
        ++it;
      }
    }
    for (auto it = notification_tokens_.begin(); it != notification_tokens_.end();) {
      if (it->first == object) {
        [[NSNotificationCenter defaultCenter] removeObserver:it->second];
        it = notification_tokens_.erase(it);
      } else {
        ++it;
      }
    }
  }

  static Result CreateVideoFormat(const VideoConfig& config,
                                  const TrackEncryption* encryption,
                                  CMFormatDescriptionRef* out) {
    if (config.extra_data.empty() || config.coded_width <= 0 || config.coded_height <= 0 ||
        config.coded_width > 0xffff || config.coded_height > 0xffff) {
      return Result::Error(Exception::kTypeError, "video config needs a decoder record and size");
    }
    const uint32_t declared = config.sample_entry ? config.sample_entry
                                                  : DefaultSampleEntry(config.codec);
    if (!SampleEntryMatches(config.codec, declared)) {
      return Result::Error(Exception::kTypeError, "sample entry type doesn't match the codec");
    }
    const uint32_t entry_type = DecodableSampleEntry(declared);
    if ((config.codec == VideoCodec::kAV1 || config.codec == VideoCodec::kVP9) &&
        config.format == BitstreamFormat::kAnnexB) {
      return Result::Error(Exception::kTypeError, "AV1 and VP9 samples are never Annex B");
    }
    if (config.codec == VideoCodec::kVP9) {
      if (encryption) {
        return Result::Error(Exception::kNotSupported, "VP9 is never protected");
      }
      static std::once_flag vp9_decoder;
      std::call_once(vp9_decoder, [] { VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9); });
    }
    std::vector<std::vector<uint8_t>> children{MakeBox(ConfigBox(config.codec), config.extra_data)};
    if (config.dolby_vision_config.size() >= 3) {
      const uint8_t profile = config.dolby_vision_config[2] >> 1;
      children.push_back(MakeBox(profile > 7 ? FourCC('d', 'v', 'v', 'C') : FourCC('d', 'v', 'c', 'C'),
                                 config.dolby_vision_config));
    }
    std::vector<uint8_t> entry =
        VisualSampleEntry(entry_type, static_cast<uint16_t>(config.coded_width),
                          static_cast<uint16_t>(config.coded_height), children);
    if (encryption) {
      entry = ProtectSampleEntry(entry, true, *encryption);
    }
    OSStatus status = CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
        kCFAllocatorDefault, entry.data(), entry.size(), kCFStringEncodingUTF8,
        kCMImageDescriptionFlavor_ISOFamily, out);
    if (status != noErr || !*out) {
      return Result::Error(Exception::kNotSupported,
                           "CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  static Result CreateAudioFormat(const AudioConfig& config,
                                  const TrackEncryption* encryption,
                                  CMFormatDescriptionRef* out) {
    if (config.codec == AudioCodec::kVorbis) {
      return CreateVorbisFormat(config, encryption, out);
    }
    uint32_t entry_type = 0;
    std::vector<std::vector<uint8_t>> children;
    switch (config.codec) {
      case AudioCodec::kAAC:
        if (config.extra_data.empty()) {
          return Result::Error(Exception::kTypeError, "AAC config needs an AudioSpecificConfig");
        }
        entry_type = FourCC('m', 'p', '4', 'a');
        children.push_back(MakeBox(FourCC('e', 's', 'd', 's'), AacEsdsPayload(config.extra_data)));
        break;
      case AudioCodec::kAC3:
        entry_type = FourCC('a', 'c', '-', '3');
        children.push_back(MakeBox(FourCC('d', 'a', 'c', '3'), config.extra_data));
        break;
      case AudioCodec::kEAC3:
        entry_type = FourCC('e', 'c', '-', '3');
        children.push_back(MakeBox(FourCC('d', 'e', 'c', '3'), config.extra_data));
        break;
      case AudioCodec::kFLAC: {
        std::optional<std::vector<uint8_t>> dfla = FlacSpecificBoxPayload(config.extra_data);
        if (!dfla) {
          return Result::Error(Exception::kTypeError, "FLAC config needs its 34-byte STREAMINFO");
        }
        entry_type = FourCC('f', 'L', 'a', 'C');
        children.push_back(MakeBox(FourCC('d', 'f', 'L', 'a'), *dfla));
        break;
      }
      case AudioCodec::kOpus: {
        std::optional<std::vector<uint8_t>> dops = OpusSpecificBoxPayload(config.extra_data);
        if (!dops) {
          return Result::Error(Exception::kTypeError, "Opus config needs an OpusHead");
        }
        entry_type = FourCC('O', 'p', 'u', 's');
        children.push_back(MakeBox(FourCC('d', 'O', 'p', 's'), *dops));
        break;
      }
      case AudioCodec::kALAC: {
        std::optional<std::vector<uint8_t>> alac = AlacSpecificBoxPayload(config.extra_data);
        if (!alac) {
          return Result::Error(Exception::kTypeError, "ALAC config needs its ALACSpecificConfig");
        }
        entry_type = FourCC('a', 'l', 'a', 'c');
        children.push_back(MakeBox(FourCC('a', 'l', 'a', 'c'), *alac));
        break;
      }
      case AudioCodec::kPCM: {
        if (config.channels <= 0 ||
            (config.pcm_float ? config.pcm_bits != 32
                              : config.pcm_bits != 16 && config.pcm_bits != 24 && config.pcm_bits != 32)) {
          return Result::Error(Exception::kTypeError, "PCM config needs channels and a 16, 24 or 32-bit sample");
        }
        entry_type = config.pcm_float ? FourCC('f', 'p', 'c', 'm') : FourCC('i', 'p', 'c', 'm');
        children.push_back(MakeBox(FourCC('p', 'c', 'm', 'C'),
                                   {0, 0, 0, 0, 1, static_cast<uint8_t>(config.pcm_bits)}));
        break;
      }
      case AudioCodec::kVorbis:
        break;
    }
    const uint32_t entry_rate =
        config.codec == AudioCodec::kOpus ? 48000 : static_cast<uint32_t>(config.sample_rate);
    std::vector<uint8_t> entry =
        AudioSampleEntry(entry_type, static_cast<uint16_t>(config.channels), entry_rate, children);
    if (encryption) {
      entry = ProtectSampleEntry(entry, false, *encryption);
    }
    OSStatus status = CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(
        kCFAllocatorDefault, entry.data(), entry.size(), kCMSoundDescriptionFlavor_ISOFamily, out);
    if (status != noErr || !*out) {
      return Result::Error(Exception::kNotSupported,
                           "CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  static Result CreateTransportStreamFormat(const VideoConfig& config, CMFormatDescriptionRef* out) {
    const uint32_t type = TransportStreamFormatType(config.codec);
    if (!type) {
      return Result::Error(Exception::kNotSupported, "MPEG-2 TS SAMPLE-AES carries no such video codec");
    }
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateVideoFormat(config, nullptr, &clear); !result.ok()) {
      return result;
    }
    ScopedFormat holder;
    holder.Reset(clear);
    const CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(clear);
    OSStatus status = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault, type, size.width, size.height,
        (__bridge CFDictionaryRef)TransportStreamExtensions(clear, type, kCMMediaType_Video), out);
    if (status != noErr || !*out) {
      return Result::Error(Exception::kNotSupported, "CMVideoFormatDescriptionCreate failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  static Result CreateTransportStreamFormat(const AudioConfig& config, CMFormatDescriptionRef* out) {
    const uint32_t type = TransportStreamFormatType(config);
    if (!type) {
      return Result::Error(Exception::kNotSupported, "MPEG-2 TS SAMPLE-AES carries no such audio codec");
    }
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateAudioFormat(config, nullptr, &clear); !result.ok()) {
      return result;
    }
    ScopedFormat holder;
    holder.Reset(clear);
    AudioStreamBasicDescription description = *CMAudioFormatDescriptionGetStreamBasicDescription(clear);
    description.mFormatID = type;
    size_t layout_size = 0;
    const AudioChannelLayout* layout = CMAudioFormatDescriptionGetChannelLayout(clear, &layout_size);
    size_t cookie_size = 0;
    const void* cookie = CMAudioFormatDescriptionGetMagicCookie(clear, &cookie_size);
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault, &description, layout ? layout_size : 0, layout, cookie ? cookie_size : 0, cookie,
        (__bridge CFDictionaryRef)TransportStreamExtensions(clear, type, kCMMediaType_Audio), out);
    if (status != noErr || !*out) {
      return Result::Error(Exception::kNotSupported, "CMAudioFormatDescriptionCreate failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  static Result CreateVorbisFormat(const AudioConfig& config,
                                   const TrackEncryption* encryption,
                                   CMFormatDescriptionRef* out) {
    if (encryption) {
      return Result::Error(Exception::kNotSupported, "Vorbis is never protected");
    }
    if (config.extra_data.empty() || config.sample_rate <= 0 || config.channels <= 0) {
      return Result::Error(Exception::kTypeError, "Vorbis config needs its headers, rate and channels");
    }
    AudioStreamBasicDescription description = {};
    description.mSampleRate = config.sample_rate;
    description.mFormatID = FourCC('v', 'o', 'r', 'b');
    description.mChannelsPerFrame = static_cast<UInt32>(config.channels);
    OSStatus status =
        CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &description, 0, nullptr, config.extra_data.size(),
                                       config.extra_data.data(), nullptr, out);
    if (status != noErr || !*out) {
      return Result::Error(Exception::kNotSupported, "CMAudioFormatDescriptionCreate failed",
                           static_cast<uint32_t>(status));
    }
    return Result::Ok();
  }

  Result CreateVideoFormats(std::string* error) {
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateVideoFormat(*video_config_, nullptr, &clear); !result.ok()) {
      return result;
    }
    ScopedFormat previous_clear;
    previous_clear.Swap(video_clear_format_);
    video_clear_format_.Reset(clear);
    auto previous_protected = std::move(video_protected_formats_);
    video_protected_formats_.clear();
    const TrackEncryption& encryption = video_config_->encryption;
    if (IsEncrypted(encryption) && !encryption.default_key_id.empty() &&
        !ProtectedVideoFormat(encryption.default_key_id, std::nullopt, error)) {
      video_clear_format_.Swap(previous_clear);
      video_protected_formats_ = std::move(previous_protected);
      return Result::Error(Exception::kNotSupported, *error);
    }
    return Result::Ok();
  }

  Result CreateAudioFormats(AudioTrack& audio, std::string* error) {
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateAudioFormat(audio.config, nullptr, &clear); !result.ok()) {
      return result;
    }
    ScopedFormat previous_clear;
    previous_clear.Swap(audio.clear_format);
    audio.clear_format.Reset(clear);
    auto previous_protected = std::move(audio.protected_formats);
    audio.protected_formats.clear();
    const TrackEncryption& encryption = audio.config.encryption;
    if (IsEncrypted(encryption) && !encryption.default_key_id.empty() &&
        !ProtectedAudioFormat(audio, encryption.default_key_id, std::nullopt, error)) {
      audio.clear_format.Swap(previous_clear);
      audio.protected_formats = std::move(previous_protected);
      return Result::Error(Exception::kNotSupported, *error);
    }
    return Result::Ok();
  }

  Result ConfigureVideo(const VideoConfig& config, std::string* error) {
    if (config.coded_width <= 0 || config.coded_height <= 0 || config.coded_width > 0xffff ||
        config.coded_height > 0xffff) {
      return Result::Error(Exception::kTypeError, "video config needs a coded size");
    }
    video_config_ = config;
    if (config.dolby_vision_config.empty() && config.dolby_vision_profile >= 0) {
      const int compatibility_id = config.dolby_vision_compatibility_id >= 0
                                       ? config.dolby_vision_compatibility_id
                                       : DefaultDolbyVisionCompatibilityId(config.dolby_vision_profile);
      video_config_->dolby_vision_config = DolbyVisionConfigurationRecord(
          config.dolby_vision_profile, config.dolby_vision_level, compatibility_id);
    }
    parameter_sets_.clear();
    av1_sequence_header_.clear();
    video_clear_format_.Reset(nullptr);
    video_protected_formats_.clear();
    const bool complete = RecordHasParameterSets(config.codec, config.extra_data);
    awaiting_video_config_ = !complete;
    if (complete) {
      if (config.codec != VideoCodec::kAV1 && config.codec != VideoCodec::kVP9) {
        parameter_sets_ = ParameterSetsInRecord(config.codec, config.extra_data);
      }
      if (Result result = CreateVideoFormats(error); !result.ok()) {
        return result;
      }
    }
    int32_t width = config.natural_width ? config.natural_width : config.coded_width;
    int32_t height = config.natural_height ? config.natural_height : config.coded_height;
    ReportNaturalSize(width, height);
    return Result::Ok();
  }

  Result ConfigureAudio(AudioTrack& audio, const AudioConfig& config, std::string* error) {
    audio.config = config;
    audio.clear_format.Reset(nullptr);
    audio.protected_formats.clear();
    audio.awaiting_config = config.extra_data.empty() &&
                            (config.codec == AudioCodec::kAC3 || config.codec == AudioCodec::kEAC3);
    if (audio.awaiting_config) {
      return Result::Ok();
    }
    return CreateAudioFormats(audio, error);
  }

  void ReportNaturalSize(int32_t width, int32_t height) {
    if (width == natural_width_ && height == natural_height_) {
      return;
    }
    natural_width_ = width;
    natural_height_ = height;
    if (!reported_width_ && !reported_height_) {
      PostNaturalSize(width, height);
      return;
    }
    size_change_pending_ = true;
  }

  void PostNaturalSize(int32_t width, int32_t height) {
    if (width == reported_width_ && height == reported_height_) {
      return;
    }
    reported_width_ = width;
    reported_height_ = height;
    const uint64_t attempt = initialize_attempt_;
    Post([width, height, attempt](Impl& impl) {
      if (impl.synchronizer_ && impl.initialize_attempt_ == attempt) {
        impl.client_->OnVideoNaturalSizeChange(width, height);
      }
    });
  }

  void ArmSizeObserver(MediaTime time) {
    size_change_pending_ = false;
    const int32_t width = natural_width_;
    const int32_t height = natural_height_;
    if (!synchronizer_ || !time.IsValid() || GetMediaTime().InSeconds() >= time.InSeconds()) {
      PostNaturalSize(width, height);
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    uint64_t generation = generation_;
    size_observers_.push_back([synchronizer_
        addBoundaryTimeObserverForTimes:@[ [NSValue valueWithCMTime:ToCMTime(time)] ]
                                  queue:RequestQueue()
                             usingBlock:^{
                               (*poster)([weak, generation, width, height] {
                                 auto impl = weak.lock();
                                 if (impl && impl->generation_ == generation) {
                                   impl->PostNaturalSize(width, height);
                                 }
                               });
                             }]);
  }

  void RemoveSizeObservers() {
    for (id observer : size_observers_) {
      [synchronizer_ removeTimeObserver:observer];
    }
    size_observers_.clear();
  }

  bool UpdateVideoConfigFromKeyframe(const uint8_t* data, size_t size, std::string* error) {
    const VideoCodec codec = video_config_->codec;
    if (codec == VideoCodec::kVP9) {
      std::optional<std::vector<uint8_t>> record =
          Vp9CodecConfigurationRecord(data, size, video_config_->color);
      if (!record) {
        *error = "no VP9 keyframe header before the first frame";
        return !awaiting_video_config_;
      }
      if (!awaiting_video_config_ && *record == video_config_->extra_data) {
        return true;
      }
      std::vector<uint8_t> previous = std::move(video_config_->extra_data);
      video_config_->extra_data = *record;
      if (Result result = CreateVideoFormats(error); !result.ok()) {
        video_config_->extra_data = std::move(previous);
        *error = result.message;
        return false;
      }
      awaiting_video_config_ = false;
      return true;
    }
    if (codec == VideoCodec::kAV1) {
      std::optional<std::vector<uint8_t>> obu = Av1SequenceHeaderObu(data, size);
      if (!obu) {
        *error = "no AV1 sequence header before the first frame";
        return !awaiting_video_config_;
      }
      if (!awaiting_video_config_ && *obu == av1_sequence_header_) {
        return true;
      }
      std::optional<std::vector<uint8_t>> record = Av1CodecConfigurationRecord(*obu);
      if (!record) {
        *error = "malformed AV1 sequence header";
        return false;
      }
      if (!awaiting_video_config_ && *record == video_config_->extra_data) {
        av1_sequence_header_ = *obu;
        return true;
      }
      std::vector<uint8_t> previous = std::move(video_config_->extra_data);
      video_config_->extra_data = *record;
      if (Result result = CreateVideoFormats(error); !result.ok()) {
        video_config_->extra_data = std::move(previous);
        *error = result.message;
        return false;
      }
      av1_sequence_header_ = *obu;
      awaiting_video_config_ = false;
      return true;
    }
    const bool avc = codec == VideoCodec::kH264;
    const std::vector<uint8_t>& record = video_config_->extra_data;
    size_t length_size = 4;
    if (video_config_->format == BitstreamFormat::kLengthPrefixed && record.size() > (avc ? 4u : 21u)) {
      length_size = (record[avc ? 4 : 21] & 3) + 1;
    }
    std::vector<std::vector<uint8_t>> sets = ParameterSetsInSample(codec, data, size, length_size);
    if (sets.empty()) {
      *error = "no parameter sets in the config record or before the first frame";
      return !awaiting_video_config_;
    }
    auto kind = [avc](const std::vector<uint8_t>& nal) {
      return avc ? (nal[0] & 0x1f) : ((nal[0] >> 1) & 0x3f);
    };
    auto same_slot = [&](const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
      return kind(a) == kind(b) &&
             ParameterSetId(!avc, a.data(), a.size()) == ParameterSetId(!avc, b.data(), b.size());
    };
    for (const std::vector<uint8_t>& earlier : parameter_sets_) {
      if (!earlier.empty() && std::none_of(sets.begin(), sets.end(), [&](const std::vector<uint8_t>& set) {
            return same_slot(set, earlier);
          })) {
        sets.push_back(earlier);
      }
    }
    auto sorted = [](std::vector<std::vector<uint8_t>> v) {
      std::sort(v.begin(), v.end());
      return v;
    };
    if (!awaiting_video_config_ && sorted(sets) == sorted(parameter_sets_)) {
      return true;
    }
    std::stable_sort(sets.begin(), sets.end(), [&](const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
      return kind(a) < kind(b);
    });
    std::vector<const uint8_t*> pointers;
    std::vector<size_t> sizes;
    for (const auto& set : sets) {
      pointers.push_back(set.data());
      sizes.push_back(set.size());
    }
    CMFormatDescriptionRef format = nullptr;
    OSStatus status =
        avc ? CMVideoFormatDescriptionCreateFromH264ParameterSets(
                  kCFAllocatorDefault, pointers.size(), pointers.data(), sizes.data(),
                  static_cast<int>(length_size), &format)
            : CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                  kCFAllocatorDefault, pointers.size(), pointers.data(), sizes.data(),
                  static_cast<int>(length_size), nullptr, &format);
    if (status != noErr || !format) {
      *error = "in-band parameter sets rejected: " + std::to_string(status);
      return false;
    }
    NSDictionary* atoms = (__bridge NSDictionary*)CMFormatDescriptionGetExtension(
        format, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
    NSData* built = atoms[avc ? @"avcC" : @"hvcC"];
    CMVideoDimensions coded = CMVideoFormatDescriptionGetDimensions(format);
    CGSize presentation = CMVideoFormatDescriptionGetPresentationDimensions(format, true, true);
    CFRelease(format);
    if (!built) {
      *error = "CoreMedia built no decoder record from the parameter sets";
      return false;
    }
    const VideoConfig previous = *video_config_;
    const uint8_t* bytes = static_cast<const uint8_t*>(built.bytes);
    video_config_->extra_data.assign(bytes, bytes + built.length);
    if (coded.width > 0 && coded.height > 0) {
      video_config_->coded_width = coded.width;
      video_config_->coded_height = coded.height;
    }
    if (Result result = CreateVideoFormats(error); !result.ok()) {
      *video_config_ = previous;
      *error = result.message;
      return false;
    }
    parameter_sets_ = std::move(sets);
    awaiting_video_config_ = false;
    if (!video_config_->natural_width || !video_config_->natural_height) {
      ReportNaturalSize(static_cast<int32_t>(presentation.width), static_cast<int32_t>(presentation.height));
    }
    return true;
  }

  bool UpdateAudioConfigFromSyncframe(AudioTrack& audio, const uint8_t* data, size_t size,
                                      const std::vector<SubsampleEntry>* subsamples, std::string* error) {
    AudioConfig& config = audio.config;
    const bool eac3 = config.codec == AudioCodec::kEAC3;
    std::optional<std::vector<uint8_t>> payload =
        eac3 ? Eac3SpecificBoxPayload(data, size, subsamples) : Ac3SpecificBoxPayload(data, size, subsamples);
    const int32_t channels = config.channels;
    if (!payload && subsamples) {
      payload = eac3 ? Eac3SpecificBoxFromConfig(config.sample_rate, channels)
                     : Ac3SpecificBoxFromConfig(config.sample_rate, channels);
      if (payload && channels > 6 && (!eac3 || channels != 8)) {
        config.channels = 6;
      }
    }
    if (!payload) {
      *error = subsamples ? "AC-3/E-AC-3 config needs a 48, 44.1 or 32 kHz rate and 1-8 channels"
                          : "no AC-3/E-AC-3 syncframe at the start of the first audio sample";
      return false;
    }
    config.extra_data = *payload;
    if (Result result = CreateAudioFormats(audio, error); !result.ok()) {
      config.extra_data.clear();
      config.channels = channels;
      *error = result.message;
      return false;
    }
    audio.awaiting_config = false;
    return true;
  }

  CMFormatDescriptionRef ProtectedVideoFormat(const std::vector<uint8_t>& key_id,
                                              const std::optional<EncryptionPattern>& pattern, std::string* error) {
    return ProtectedFormat(*video_config_, video_protected_formats_, video_protected_key_, key_id, pattern, error);
  }
  CMFormatDescriptionRef ProtectedAudioFormat(AudioTrack& audio, const std::vector<uint8_t>& key_id,
                                              const std::optional<EncryptionPattern>& pattern, std::string* error) {
    return ProtectedFormat(audio.config, audio.protected_formats, audio.protected_key, key_id, pattern, error);
  }

  template <typename Config>
  static CMFormatDescriptionRef ProtectedFormat(const Config& config,
                                                std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>>& cache,
                                                std::vector<uint8_t>& last_key, const std::vector<uint8_t>& key_id,
                                                const std::optional<EncryptionPattern>& pattern, std::string* error) {
    std::vector<uint8_t> cache_key = key_id;
    if (pattern) {
      cache_key.push_back(pattern->crypt_byte_block);
      cache_key.push_back(pattern->skip_byte_block);
    }
    last_key = cache_key;
    auto it = cache.find(cache_key);
    if (it != cache.end()) {
      return it->second->get();
    }
    TrackEncryption encryption = config.encryption;
    encryption.default_key_id = key_id;
    if (pattern) {
      encryption.default_pattern = *pattern;
    }
    if (encryption.default_constant_iv.empty() && encryption.default_per_sample_iv_size == 0) {
      encryption.default_per_sample_iv_size = 16;
    }
    CMFormatDescriptionRef format = nullptr;
    Result result = Result::Ok();
    if (IsTransportStreamKeyId(key_id)) {
      result = CreateTransportStreamFormat(config, &format);
    } else if constexpr (std::is_same_v<Config, VideoConfig>) {
      result = CreateVideoFormat(config, &encryption, &format);
    } else {
      result = CreateAudioFormat(config, &encryption, &format);
    }
    if (!result.ok()) {
      *error = result.message;
      return nullptr;
    }
    auto holder = std::make_unique<ScopedFormat>();
    holder->Reset(format);
    CMFormatDescriptionRef raw = holder->get();
    cache[cache_key] = std::move(holder);
    return raw;
  }

  bool BuildSample(StreamId stream, const EncodedSample& sample, Held* held, std::string* error) {
    if (!sample.data || !sample.size || !sample.pts.IsValid()) {
      *error = "empty sample or invalid timestamp";
      return false;
    }
    const bool video = stream.type == StreamType::kVideo;
    AudioTrack* audio = video ? nullptr : Audio(stream.audio_track);
    const TrackEncryption& encryption = video ? video_config_->encryption : audio->config.encryption;
    const bool encrypted = sample.decrypt.has_value();
    if (encrypted && !IsEncrypted(encryption)) {
      *error = "encrypted sample on a track configured as clear";
      return false;
    }
    const bool transport_stream = encrypted && IsTransportStreamKeyId(sample.decrypt->key_id);
    std::vector<SubsampleEntry> subsamples;
    if (encrypted) {
      subsamples = sample.decrypt->subsamples;
    }
    std::vector<SubsampleEntry>* clear_ranges = encrypted && !transport_stream ? &subsamples : nullptr;

    std::vector<uint8_t> converted;
    const uint8_t* bytes = sample.data;
    size_t size = sample.size;
    if (video && video_config_->format == BitstreamFormat::kAnnexB) {
      if (!ConvertAnnexBToLengthPrefixed(sample.data, sample.size, clear_ranges, &converted)) {
        *error = "malformed Annex B access unit";
        return false;
      }
      bytes = converted.data();
      size = converted.size();
    } else if (!video && audio->config.framing == AudioFraming::kADTS &&
               AdtsHeaderSize(sample.data, sample.size)) {
      size_t header = AdtsHeaderSize(sample.data, sample.size);
      bytes += header;
      size -= header;
      if (clear_ranges && !RemoveLeadingClearBytes(header, size, clear_ranges)) {
        *error = "ADTS header not covered by clear subsample bytes";
        return false;
      }
    }
    if (video && transport_stream) {
      if (converted.empty()) {
        converted.assign(bytes, bytes + size);
      }
      if (!UnescapeSampleAesSlices(&converted)) {
        *error = "malformed H.264 access unit";
        return false;
      }
      bytes = converted.data();
      size = converted.size();
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
    if (video && (awaiting_video_config_ || sample.is_keyframe) &&
        !UpdateVideoConfigFromKeyframe(bytes, size, error)) {
      CFRelease(block);
      return false;
    }
    if (!video && audio->awaiting_config &&
        !UpdateAudioConfigFromSyncframe(*audio, bytes, size, clear_ranges, error)) {
      CFRelease(block);
      return false;
    }
    CMFormatDescriptionRef format = nullptr;
    if (encrypted) {
      format = video ? ProtectedVideoFormat(key_id, sample.decrypt->pattern, error)
                     : ProtectedAudioFormat(*audio, key_id, sample.decrypt->pattern, error);
    } else {
      format = video ? video_clear_format_.get() : audio->clear_format.get();
    }
    if (!format) {
      CFRelease(block);
      return false;
    }
    CMSampleTimingInfo timing = {ToCMTime(sample.duration), ToCMTime(sample.pts),
                                 sample.dts.IsValid() ? ToCMTime(sample.dts) : kCMTimeInvalid};
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
    if (video) {
      if (!sample.is_keyframe) {
        CFDictionarySetValue(attachments, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
      }
      const double start = video_.start;
      const bool before = sample.duration.IsValid()
                              ? sample.pts.InSeconds() + sample.duration.InSeconds() <= start
                              : sample.pts.InSeconds() < start;
      if (before) {
        CFDictionarySetValue(attachments, kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanTrue);
      }
    }
    if (!encrypted) {
      return true;
    }
    held->encrypted = true;
    held->key_id = key_id;
    if (transport_stream) {
      return true;
    }
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

  bool Submit(StreamId stream, Held& held) {
    if (held.encrypted) {
      if (!cdm_ || cdm_detached_ || !cdm_->HasUsableKey(held.key_id)) {
        return false;
      }
      if (!held.redelivered) {
        ++status_.protected_enqueued;
      }
    }
    if (stream == StreamType::kVideo) {
      EnqueueVideo(held.buffer);
      RequestVideoFrameAvailability(held.buffer);
    } else {
      [RendererFor(stream) enqueueSampleBuffer:held.buffer];
    }
    if (held.redelivered) {
      ++status_.redelivered;
    } else {
      ++(stream.type == StreamType::kVideo ? status_.video_enqueued : status_.audio_enqueued);
    }
    if (stream.type == StreamType::kVideo) {
      if (!held.redelivered) {
        video_due_.push(held.start);
      }
    } else {
      NoteAudioQueued(*StreamFor(stream), held.start, held.end);
    }
    Stream& state = *StreamFor(stream);
    state.enqueued_end = std::max(state.enqueued_end, held.end);
    CFRetain(held.buffer);
    state.submitted.emplace_back(held.buffer, held.start, held.end, held.keyframe, held.encrypted, held.key_id);
    TrimSubmitted(stream);
    return true;
  }

  uint64_t CountPassedVideo() {
    const double now = GetMediaTime().InSeconds();
    while (!video_due_.empty() && video_due_.top() <= now) {
      video_due_.pop();
      ++video_frames_passed_;
    }
    return video_frames_passed_;
  }

  void TrimSubmitted(StreamId stream) {
    std::deque<Submitted>& submitted = StreamFor(stream)->submitted;
    const double now = GetMediaTime().InSeconds();
    if (stream.type == StreamType::kAudio) {
      while (!submitted.empty() && submitted.front().end < now - 0.5) {
        submitted.pop_front();
      }
      return;
    }
    size_t keep_from = 0;
    for (size_t i = 0; i < submitted.size() && submitted[i].start <= now; ++i) {
      if (submitted[i].keyframe) {
        keep_from = i;
      }
    }
    submitted.erase(submitted.begin(), submitted.begin() + static_cast<std::ptrdiff_t>(keep_from));
  }

  void OnAudioFlushedAutomatically(uint32_t track, double flush_time) {
    AudioTrack* audio = Audio(track);
    if (!audio) {
      return;
    }
    ++status_.audio_automatic_flushes;
    Stream& state = audio->stream;
    const std::deque<Submitted>& submitted = state.submitted;
    if (submitted.empty() || flush_time + 1e-6 < submitted.front().start ||
        flush_time > state.enqueued_end + 1e-6) {
      return;
    }
    const StreamId stream{StreamType::kAudio, track};
    StopRequest(stream);
    state.armed = false;
    [audio->renderer flush];
    state.queued_end = -std::numeric_limits<double>::infinity();
    const auto outgoing = audio_outgoing_end_.find(track);
    const double from = outgoing == audio_outgoing_end_.end() ? -std::numeric_limits<double>::infinity()
                                                              : outgoing->second - 1e-6;
    const double now = GetMediaTime().InSeconds();
    for (size_t i = 0; i < submitted.size(); ++i) {
      const Submitted& entry = submitted[i];
      if (entry.end > now && entry.start >= from) {
        if (HoldRedelivered(stream, i)) {
          break;
        }
        [audio->renderer enqueueSampleBuffer:entry.buffer];
        NoteAudioQueued(state, entry.start, entry.end);
        ++status_.redelivered;
      }
    }
    NotifyNeedData(stream);
  }

  bool HoldRedelivered(StreamId stream, size_t from) {
    Stream& state = *StreamFor(stream);
    std::deque<Submitted>& submitted = state.submitted;
    const Submitted& first = submitted[from];
    if (!first.encrypted || (!cdm_detached_ && cdm_ && cdm_->HasUsableKey(first.key_id))) {
      return false;
    }
    std::deque<Held> again;
    for (size_t i = from; i < submitted.size(); ++i) {
      Submitted& entry = submitted[i];
      Held held;
      held.buffer = std::exchange(entry.buffer, nullptr);
      held.encrypted = entry.encrypted;
      held.key_id = std::move(entry.key_id);
      held.start = entry.start;
      held.end = entry.end;
      held.keyframe = entry.keyframe;
      held.redelivered = true;
      again.push_back(std::move(held));
    }
    submitted.erase(submitted.begin() + static_cast<std::ptrdiff_t>(from), submitted.end());
    state.held.insert(state.held.begin(), std::make_move_iterator(again.begin()),
                      std::make_move_iterator(again.end()));
    if (!waiting_reported_) {
      waiting_reported_ = true;
      PostInGeneration([](Impl& impl) { impl.client_->OnWaitingForKey(); });
    }
    return true;
  }

  void NoteAudioQueued(Stream& audio, double start, double end) {
    if (start + (end - start) / 2 < audio.queued_end) {
      ++status_.audio_double_enqueues;
    }
    audio.queued_end = std::max(audio.queued_end, end);
  }

  void ResumeVideoDecoding() {
    if (!video_renderer_ || !GetStatus().video_requires_flush) {
      return;
    }
    StopRequest(StreamType::kVideo);
    video_.armed = false;
    [video_renderer_ flush];
    video_upcoming_.clear();
    ResetVideoFrameAvailability();
    ++status_.video_decoder_resets;
    const double now = GetMediaTime().InSeconds();
    bool from_keyframe = false;
    for (size_t i = 0; i < video_.submitted.size(); ++i) {
      const Submitted& entry = video_.submitted[i];
      from_keyframe |= entry.keyframe;
      if (!from_keyframe) {
        continue;
      }
      if (HoldRedelivered(StreamType::kVideo, i)) {
        break;
      }
      if (entry.end <= now) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(entry.buffer, true);
        if (attachments && CFArrayGetCount(attachments)) {
          CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0),
                               kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanTrue);
        }
      }
      EnqueueVideo(entry.buffer);
      RequestVideoFrameAvailability(entry.buffer);
      ++status_.redelivered;
    }
    video_reset_pending_ = true;
    UpdateClock();
    NotifyNeedData(StreamType::kVideo);
  }

  static bool UsesDisplayReadinessNotification() {
#if defined(PARC_FAIRPLAY_FORCE_LEGACY_PREROLL)
    return false;
#else
    if (@available(macOS 14.4, *)) {
      return true;
    }
    return false;
#endif
  }

  void ResetVideoFrameAvailability() {
    ++video_frame_epoch_;
    legacy_video_frame_available_ = false;
  }

  static bool IsDisplayableVideoSample(CMSampleBufferRef buffer) {
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, false);
    if (!attachments || !CFArrayGetCount(attachments)) {
      return true;
    }
    CFTypeRef hidden = CFDictionaryGetValue((CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0),
                                          kCMSampleAttachmentKey_DoNotDisplay);
    return !hidden || !CFEqual(hidden, kCFBooleanTrue);
  }

  void RequestVideoFrameAvailability(CMSampleBufferRef buffer) {
    if (UsesDisplayReadinessNotification() || legacy_video_frame_available_) {
      return;
    }
    if (!IsDisplayableVideoSample(buffer)) {
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    auto poster = poster_;
    const uint64_t epoch = video_frame_epoch_;
    [layer_ prerollDecodeWithCompletionHandler:^(BOOL success) {
      (*poster)([weak, epoch, success] {
        if (auto impl = weak.lock(); impl && impl->video_frame_epoch_ == epoch && success) {
          impl->legacy_video_frame_available_ = true;
          impl->UpdateBuffering();
        }
      });
    }];
  }

  bool VideoFrameAvailable() const {
    const bool ended_without_picture = Complete(video_) &&
        std::none_of(video_.submitted.begin(), video_.submitted.end(), [](const Submitted& sample) {
          return IsDisplayableVideoSample(sample.buffer);
        });
    return !video_reset_pending_ || ended_without_picture || LayerHasFrame();
  }

  bool LayerHasFrame() const {
    if (UsesDisplayReadinessNotification()) {
      if (@available(macOS 14.4, *)) {
        return layer_.readyForDisplay;
      }
    }
    return legacy_video_frame_available_;
  }

  void OnKeysChanged() {
    bool any_held = false;
    const double now = GetMediaTime().InSeconds();
    for (StreamId stream : Streams()) {
      Stream& state = *StreamFor(stream);
      PruneHeld(stream, now);
      while (!state.held.empty()) {
        Held& held = state.held.front();
        if (stream.type == StreamType::kVideo && held.end <= now) {
          SetDoNotDisplay(held.buffer);
        }
        if (!Submit(stream, held)) {
          break;
        }
        state.held.pop_front();
      }
      any_held |= !state.held.empty();
    }
    if (!any_held && waiting_reported_) {
      waiting_reported_ = false;
      ScheduleEndIfComplete();
    }
    for (StreamId stream : Streams()) {
      NotifyNeedData(stream);
    }
    UpdateBuffering();
  }

  static void SetDoNotDisplay(CMSampleBufferRef buffer) {
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, true);
    if (attachments && CFArrayGetCount(attachments)) {
      CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0),
                           kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanTrue);
    }
  }

  void EnqueueVideo(CMSampleBufferRef buffer) {
    [video_renderer_ enqueueSampleBuffer:buffer];
    const CMTime pts = CMSampleBufferGetPresentationTimeStamp(buffer);
    size_t later = 0;
    for (const CMTime& earlier : video_upcoming_) {
      later += CMTimeCompare(earlier, pts) > 0;
    }
    video_reorder_depth_ = std::max(video_reorder_depth_, later);
    video_upcoming_.push_back(pts);
    if (video_upcoming_.size() > kUpcomingWindow) {
      video_upcoming_.pop_front();
    }
    const size_t rank = video_reorder_depth_ + 1;
    if (!video_reorder_depth_ || video_upcoming_.size() <= rank) {
      return;
    }
    std::vector<CMTime> latest(video_upcoming_.begin(), video_upcoming_.end());
    std::nth_element(latest.begin(), latest.begin() + rank, latest.end(),
                     [](const CMTime& a, const CMTime& b) { return CMTimeCompare(a, b) > 0; });
    if (@available(macOS 14.4, *)) {
      [layer_.sampleBufferRenderer expectMinimumUpcomingSampleBufferPresentationTime:latest[rank]];
    }
  }

  void ArmRequest(StreamId stream) {
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || StreamFor(stream)->armed || StreamFor(stream)->end_of_stream) {
      return;
    }
    Stream& state = *StreamFor(stream);
    state.armed = true;
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    std::shared_ptr<RequestGate> gate = GateFor(stream);
    uint64_t generation = generation_;
    std::lock_guard<std::mutex> lock(gate->mutex);
    const uint64_t request = ++gate->current;
    [renderer requestMediaDataWhenReadyOnQueue:RequestQueue()
                                    usingBlock:^{
                                      std::unique_lock<std::mutex> held(gate->mutex, std::try_to_lock);
                                      if (!held.owns_lock() || gate->current != request) {
                                        return;
                                      }
                                      ++gate->current;
                                      [renderer stopRequestingMediaData];
                                      held.unlock();
                                      (*poster)([weak, stream, generation] {
                                        auto impl = weak.lock();
                                        if (impl && impl->generation_ == generation &&
                                            impl->StreamFor(stream)) {
                                          impl->StreamFor(stream)->armed = false;
                                          impl->DeliverNeedData(stream);
                                        }
                                      });
                                    }];
    CheckRequestLater(stream, request);
  }

  void CheckRequestLater(StreamId stream, uint64_t request) {
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    const uint64_t generation = generation_;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), RequestQueue(), ^{
      (*poster)([weak, stream, request, generation] {
        auto impl = weak.lock();
        if (!impl || impl->generation_ != generation || !impl->RendererFor(stream) ||
            !impl->StreamFor(stream)->armed) {
          return;
        }
        id<AVQueuedSampleBufferRendering> renderer = impl->RendererFor(stream);
        bool answer = false;
        {
          std::shared_ptr<RequestGate> gate = impl->GateFor(stream);
          std::lock_guard<std::mutex> lock(gate->mutex);
          if (gate->current != request) {
            return;
          }
          answer = renderer.readyForMoreMediaData;
          if (answer) {
            ++gate->current;
            [renderer stopRequestingMediaData];
          }
        }
        if (!answer) {
          impl->CheckRequestLater(stream, request);
          return;
        }
        impl->StreamFor(stream)->armed = false;
        impl->DeliverNeedData(stream);
      });
    });
  }

  void StopRequest(StreamId stream) {
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer) {
      return;
    }
    std::shared_ptr<RequestGate> gate = GateFor(stream);
    std::lock_guard<std::mutex> lock(gate->mutex);
    ++gate->current;
    [renderer stopRequestingMediaData];
  }

  std::shared_ptr<RequestGate> GateFor(StreamId stream) const {
    return stream.type == StreamType::kVideo ? video_gate_ : Audio(stream.audio_track)->gate;
  }

  void NotifyNeedData(StreamId stream) {
    if (!RendererFor(stream) || StreamFor(stream)->end_of_stream) {
      return;
    }
    PostInGeneration([stream](Impl& impl) { impl.DeliverNeedData(stream); });
  }

  void DeliverNeedData(StreamId stream) {
    if (!RendererFor(stream) || StreamFor(stream)->end_of_stream) {
      return;
    }
    if (IsReadyForMoreData(stream)) {
      client_->OnNeedData(stream);
    } else if (StreamFor(stream)->held.empty()) {
      ArmRequest(stream);
    }
  }

  static bool Complete(const Stream& state) { return state.end_of_stream && state.held.empty(); }

  void UpdateBuffering() {
    if (outgoing_layer_ && LayerHasFrame()) {
      RetireOutgoingLayer();
    }
    if (!renderers_have_samples_) {
      bool ready = true;
      for (StreamId stream : Streams()) {
        id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
        Stream& state = *StreamFor(stream);
        if (renderer) {
          state.has_samples = state.has_samples || Complete(state) ||
                              renderer.hasSufficientMediaDataForReliablePlaybackStart;
          ready &= state.has_samples;
        }
      }
      renderers_have_samples_ = ready;
    }
    if (!have_enough_ && (video_renderer_ || !audio_.empty())) {
      const double now = GetMediaTime().InSeconds();
      auto enough = [now](const Stream& state, id<AVQueuedSampleBufferRendering> renderer) {
        return state.end_of_stream || state.given_end - now >= kEnoughAheadSeconds ||
               (state.given_end > now && renderer.hasSufficientMediaDataForReliablePlaybackStart);
      };
      bool have_enough = true;
      if (video_renderer_) {
        have_enough &= enough(video_, video_renderer_);
      }
      for (const auto& [track, audio] : audio_) {
        have_enough &= enough(audio.stream, audio.renderer);
      }
      if (have_enough && VideoFrameAvailable()) {
        have_enough_ = true;
        PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(true); });
      }
    }
    UpdateClock();
  }

  void UpdateClock() {
    if (video_reset_pending_ && VideoFrameAvailable()) {
      video_reset_pending_ = false;
    }
    const bool run = have_enough_ && renderers_have_samples_ && !video_reset_pending_;
    if (run != clock_held_) {
      return;
    }
    clock_held_ = !run;
    if (run) {
      RunClock();
    } else {
      synchronizer_.rate = 0;
    }
  }

  void CheckUnderflow() {
    if (status_.rate == 0) {
      return;
    }
    const double now = GetMediaTime().InSeconds();
    for (StreamId stream : Streams()) {
      PruneHeld(stream, now);
      if (!StreamFor(stream)->held.empty()) {
        NotifyNeedData(stream);
      }
    }
    ArmStall(now);
  }

  void PruneHeld(StreamId stream, double now) {
    std::deque<Held>& held = StreamFor(stream)->held;
    if (stream.type == StreamType::kAudio) {
      while (!held.empty() && held.front().end <= now) {
        held.pop_front();
      }
      return;
    }
    size_t keep_from = 0;
    for (size_t i = 0; i < held.size() && held[i].start <= now; ++i) {
      if (held[i].keyframe) {
        keep_from = i;
      }
    }
    held.erase(held.begin(), held.begin() + static_cast<std::ptrdiff_t>(keep_from));
  }

  double StallTime() const {
    double stall = -1;
    for (StreamId stream : Streams()) {
      const Stream& state = *StreamFor(stream);
      if (RendererFor(stream) && !state.end_of_stream && state.given_end >= 0 &&
          (stall < 0 || state.given_end < stall)) {
        stall = state.given_end;
      }
    }
    return stall;
  }

  void ArmStall(double now) {
    const double stall = StallTime();
    if (clock_held_ || stall < 0 || stall - now > kStallArmSeconds) {
      RemoveStallObserver();
      return;
    }
    if (now >= stall) {
      Stall(stall);
      return;
    }
    if (stall_observer_ && stall_time_ == stall) {
      return;
    }
    RemoveStallObserver();
    stall_time_ = stall;
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    uint64_t generation = generation_;
    stall_observer_ = [synchronizer_
        addBoundaryTimeObserverForTimes:@[ [NSValue
                                            valueWithCMTime:ToCMTime(MediaTime::FromMicroseconds(
                                                                int64_t(stall * 1e6)))] ]
                                  queue:RequestQueue()
                             usingBlock:^{
                               (*poster)([weak, generation] {
                                 auto impl = weak.lock();
                                 if (impl && impl->generation_ == generation) {
                                   impl->OnStallBoundary();
                                 }
                               });
                             }];
  }

  void OnStallBoundary() {
    const double stall = StallTime();
    RemoveStallObserver();
    if (clock_held_ || stall < 0) {
      return;
    }
    if (GetMediaTime().InSeconds() >= stall - 1e-3) {
      Stall(stall);
    } else {
      ArmStall(GetMediaTime().InSeconds());
    }
  }

  void Stall(double stall) {
    RemoveStallObserver();
    have_enough_ = false;
    clock_held_ = true;
    anchor_.reset();
    if (start_time_.IsValid()) {
      stall = std::max(stall, start_time_.InSeconds());
    }
    if (GetMediaTime().InSeconds() > stall) {
      [synchronizer_ setRate:0 time:ToCMTime(MediaTime::FromMicroseconds(int64_t(stall * 1e6)))];
    } else {
      synchronizer_.rate = 0;
    }
    PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(false); });
  }

  void RemoveStallObserver() {
    if (stall_observer_) {
      [synchronizer_ removeTimeObserver:stall_observer_];
      stall_observer_ = nil;
    }
    stall_time_ = -1;
  }

  void ScheduleEndIfComplete() {
    if (!video_renderer_ && audio_.empty()) {
      return;
    }
    MediaTime end;
    for (StreamId stream : Streams()) {
      const Stream& state = *StreamFor(stream);
      if (!RendererFor(stream)) {
        continue;
      }
      if (!state.end_of_stream) {
        return;
      }
      if (state.last_end.IsValid() && (!end.IsValid() || state.last_end.InSeconds() > end.InSeconds())) {
        end = state.last_end;
      }
    }
    if (end_observer_) {
      return;
    }
    if (!end.IsValid() || GetMediaTime().InSeconds() >= end.InSeconds()) {
      PostInGeneration([](Impl& impl) { impl.FireEnded(); });
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    std::shared_ptr<const PostTask> poster = poster_;
    uint64_t generation = generation_;
    end_observer_ = [synchronizer_
        addBoundaryTimeObserverForTimes:@[ [NSValue valueWithCMTime:ToCMTime(end)] ]
                                  queue:RequestQueue()
                             usingBlock:^{
                               (*poster)([weak, generation] {
                                 auto impl = weak.lock();
                                 if (impl && impl->generation_ == generation) {
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
    if (status.video == RenderingStatus::kFailed && !status.video_requires_flush &&
        !video_failure_reported_) {
      video_failure_reported_ = true;
      client_->OnError(RendererError::kDecode, "video renderer failed: " + status.video_error);
    }
    for (auto& [track, audio] : audio_) {
      if (audio.renderer.status == AVQueuedSampleBufferRenderingStatusFailed && !audio.failure_reported) {
        audio.failure_reported = true;
        client_->OnError(RendererError::kDecode,
                         "audio renderer failed: " + (audio.renderer.error ? Describe(audio.renderer.error) : ""));
      }
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
  FairPlayCdm* pending_cdm_ = nullptr;
  bool cdm_detached_ = false;
  uint64_t observer_id_ = 0;

  std::optional<VideoConfig> video_config_;
  const std::shared_ptr<RequestGate> video_gate_ = std::make_shared<RequestGate>();
  ScopedFormat video_clear_format_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> video_protected_formats_;
  NSString* output_device_uid_ = nil;
  bool follows_default_output_ = false;
  AudioObjectPropertyListenerBlock audio_devices_listener_ = nil;
  float volume_ = 1;
  bool muted_ = false;
  uint64_t initialize_attempt_ = 0;
  std::vector<uint8_t> video_protected_key_;
  std::vector<id<AVContentKeyRecipient>> recipients_;

  AVSampleBufferRenderSynchronizer* synchronizer_ = nil;
  PCFairPlayVideoHost* host_ = nil;
  AVSampleBufferDisplayLayer* layer_ = nil;
  AVSampleBufferDisplayLayer* outgoing_layer_ = nil;
  id<AVQueuedSampleBufferRendering> outgoing_video_renderer_ = nil;
  std::map<uint32_t, std::vector<AVSampleBufferAudioRenderer*>> outgoing_audio_;
  std::vector<std::pair<FairPlayCdm*, id<AVContentKeyRecipient>>> outgoing_recipients_;
  std::vector<std::pair<uint32_t, AVSampleBufferAudioRenderer*>> leaving_audio_;
  std::map<uint32_t, double> audio_outgoing_end_;
  bool renderers_were_recipients_ = false;
  uint64_t video_replayed_ = 0;
  VideoMetrics retired_video_metrics_;
  id<AVQueuedSampleBufferRendering> video_renderer_ = nil;
  std::map<uint32_t, AudioTrack> audio_;
  uint32_t next_audio_track_ = 0;
  bool preserves_pitch_ = true;
  PCFairPlayRendererObserver* observer_ = nil;
  std::vector<std::pair<NSObject*, NSString*>> observed_;
  std::vector<std::pair<id, id>> notification_tokens_;
  id end_observer_ = nil;
  id stall_observer_ = nil;
  double stall_time_ = -1;
  id clock_observer_ = nil;

  Stream video_;
  MediaTime start_time_;
  bool waiting_reported_ = false;
  bool have_enough_ = false;
  bool renderers_have_samples_ = false;
  bool video_reset_pending_ = false;
  bool legacy_video_frame_available_ = false;
  uint64_t video_frame_epoch_ = 0;
  bool clock_held_ = true;
  struct Anchor {
    CMTime time;
    CMTime host_time;
  };
  std::optional<Anchor> anchor_;
  bool follows_ = false;
  bool clock_ran_ = false;
  bool awaiting_video_config_ = false;
  std::vector<std::vector<uint8_t>> parameter_sets_;
  std::vector<uint8_t> av1_sequence_header_;
  int32_t natural_width_ = 0;
  int32_t natural_height_ = 0;
  int32_t reported_width_ = 0;
  int32_t reported_height_ = 0;
  bool size_change_pending_ = false;
  std::vector<id> size_observers_;
  uint64_t generation_ = 0;
  const std::shared_ptr<std::atomic<uint64_t>> flush_count_ = std::make_shared<std::atomic<uint64_t>>(0);
  std::atomic<CMTimebaseRef> timebase_{nullptr};
  bool ended_ = false;
  bool video_failure_reported_ = false;
  RendererStatus status_;
  std::priority_queue<double, std::vector<double>, std::greater<double>> video_due_;
  std::deque<CMTime> video_upcoming_;
  size_t video_reorder_depth_ = 0;
  uint64_t video_frames_passed_ = 0;
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

Result FairPlayRenderer::Reconfigure(const VideoConfig& config) {
  return impl_->Reconfigure(config);
}

Result FairPlayRenderer::Reconfigure(const AudioConfig& config, uint32_t audio_track) {
  return impl_->Reconfigure(config, audio_track);
}

Result FairPlayRenderer::AddVideo(const VideoConfig& config) {
  return impl_->AddVideo(config);
}

Result FairPlayRenderer::ReplaceVideo(const VideoConfig& config) {
  return impl_->ReplaceVideo(config);
}

Result FairPlayRenderer::AddAudio(const AudioConfig& config, uint32_t* track) {
  return impl_->AddAudio(config, track);
}

void FairPlayRenderer::RemoveAudio(uint32_t track) {
  impl_->RemoveAudio(track);
}

Result FairPlayRenderer::SetCdm(FairPlayCdm* cdm) {
  return impl_->SetCdm(cdm);
}

void FairPlayRenderer::DetachCdm() {
  impl_->DetachCdm();
}

void* FairPlayRenderer::display_layer() const {
  return impl_->display_layer();
}

void FairPlayRenderer::RemoveDisplayedImage() {
  impl_->RemoveDisplayedImage();
}

bool FairPlayRenderer::IsReadyForMoreData(StreamId stream) const {
  return impl_->IsReadyForMoreData(stream);
}

EnqueueResult FairPlayRenderer::Enqueue(StreamId stream, const EncodedSample& sample) {
  return impl_->Enqueue(stream, sample);
}

void FairPlayRenderer::SetEndOfStream(StreamId stream) {
  impl_->SetEndOfStream(stream);
}

void FairPlayRenderer::StartPlayingFrom(MediaTime time) {
  impl_->StartPlayingFrom(time);
}

void FairPlayRenderer::SetPlaybackRate(double rate) {
  impl_->SetPlaybackRate(rate);
}

bool FairPlayRenderer::SetPlaybackRateAt(double rate, MediaTime time, int64_t host_time_us) {
  return impl_->SetPlaybackRateAt(rate, time, host_time_us);
}

void FairPlayRenderer::SetPreservesPitch(bool preserves_pitch) {
  impl_->SetPreservesPitch(preserves_pitch);
}

void FairPlayRenderer::SetVolume(float volume) {
  impl_->SetVolume(volume);
}

void FairPlayRenderer::SetMuted(bool muted) {
  impl_->SetMuted(muted);
}

Result FairPlayRenderer::SetAudioOutputDevice(const std::string& unique_id) {
  return impl_->SetAudioOutputDevice(unique_id);
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

void FairPlayRenderer::LoadVideoMetrics(std::function<void(const VideoMetrics&)> done) {
  impl_->LoadVideoMetrics(std::move(done));
}

}

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

@implementation PCFairPlayVideoHost

- (void)layoutSublayers {
  for (CALayer* sublayer in self.sublayers) {
    sublayer.frame = self.bounds;
  }
}

@end

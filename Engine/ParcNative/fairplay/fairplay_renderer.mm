#include "fairplay_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMedia/CoreMedia.h>

#include <algorithm>
#include <atomic>
#include <deque>
#include <map>
#include <mutex>

#include "fairplay_bitstream.h"
#include "fairplay_key_session.h"
#include "fairplay_key_session_internal.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

using parc::fairplay::FairPlayRenderer;
using parc::fairplay::PostTask;

// Sample attachment keys. CoreMedia exports these strings without naming
// them in its headers; they are what AVStreamDataParser attaches to protected
// samples (and what WebKit writes when it rebuilds protected samples in its GPU
// process, CMUtilities.mm).
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

// Serializes stopping a renderer's media-data request between the owner
// sequence and the request block. |current| names the live request; the
// owner bumps it whenever it stops or re-arms, so a block from an older
// request never stops a newer one.
struct RequestGate {
  std::mutex mutex;
  uint64_t current = 0;
};

// The system default output device's Core Audio UID, nil if unavailable.
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
      return entry == FourCC('a', 'v', '0', '1');
  }
  return false;
}

// The entry type CoreMedia decodes. hev1, avc3 and dvhe mark parameter sets
// that travel in-band, but VideoToolbox configures its decoder only from the
// format description's record: AVSampleBufferDisplayLayer rejects every frame
// of an 'hev1' description (-12906) that it decodes as 'hvc1'. Chromium
// re-inserts parameter sets before keyframes anyway, so the out-of-band type
// is always used (and the record built from in-band sets when it has none).
uint32_t DecodableSampleEntry(uint32_t entry) {
  if (entry == FourCC('h', 'e', 'v', '1')) return FourCC('h', 'v', 'c', '1');
  if (entry == FourCC('a', 'v', 'c', '3')) return FourCC('a', 'v', 'c', '1');
  if (entry == FourCC('d', 'v', 'h', 'e')) return FourCC('d', 'v', 'h', '1');
  return entry;
}

// Whether a decoder configuration record carries the parameter sets
// VideoToolbox needs (SPS for avcC; VPS, SPS and PPS for hvcC).
bool RecordHasParameterSets(VideoCodec codec, const std::vector<uint8_t>& record) {
  if (codec == VideoCodec::kAV1) {
    return true;
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

// The parameter set NAL units in an avcC (SPS, PPS) or hvcC (VPS, SPS, PPS).
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
      if (type < 32 || type > 34) sets.resize(before);  // Only VPS/SPS/PPS.
    }
  }
  return sets;
}

// Parameter set NAL units in a length-prefixed access unit.
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
  }
  return 0;
}

bool IsEncrypted(const TrackEncryption& encryption) {
  return encryption.scheme != EncryptionScheme::kUnencrypted;
}

}  // namespace

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
    StopRequest(StreamType::kVideo);
    StopRequest(StreamType::kAudio);
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
      if (Result result = ConfigureVideo(*video, &error); !result.ok()) {
        return result;
      }
    }
    if (audio) {
      if (Result result = ConfigureAudio(*audio, &error); !result.ok()) {
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
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (video) {
      // The owner sequence may have no run loop to commit an implicit
      // transaction, so the layer's setup is committed explicitly.
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      layer_ = [AVSampleBufferDisplayLayer layer];
      layer_.videoGravity = AVLayerVideoGravityResizeAspect;
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
      AddNotification(center, requires_flush, video_renderer_, [](Impl& impl, NSNotification*) {
        impl.CheckRendererStatus();
        impl.ResumeVideoDecoding();
      });
    }
    if (audio) {
      audio_ = [[AVSampleBufferAudioRenderer alloc] init];
      [synchronizer_ addRenderer:audio_];
      Observe(audio_, @"status");
      Observe(audio_, @"error");
      // The flush time belongs to the timeline of the moment AVFoundation
      // posts it, so the generation is read then, not when the task runs.
      std::shared_ptr<std::atomic<uint64_t>> flushes = flush_count_;
      id token = [center addObserverForName:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification
                                     object:audio_
                                      queue:nil
                                 usingBlock:^(NSNotification* note) {
                                   const uint64_t generation = flushes->load();
                                   NSValue* value = note.userInfo[AVSampleBufferAudioRendererFlushTimeKey];
                                   const CMTime time = value ? value.CMTimeValue : kCMTimeInvalid;
                                   (*poster)([weak, generation, time] {
                                     auto impl = weak.lock();
                                     if (impl && impl->generation_ == generation) {
                                       impl->OnAudioFlushedAutomatically(
                                           CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time)
                                                                   : impl->GetMediaTime().InSeconds());
                                     }
                                   });
                                 }];
      notification_tokens_.push_back(token);
    }
    if (FairPlayCdm* cdm = pending_cdm_) {
      pending_cdm_ = nullptr;
      if (Result result = AttachCdm(cdm); !result.ok()) {
        return result;
      }
    }
    return Result::Ok();
  }

  // The renderers join the key system's AVContentKeySession as content key
  // recipients. AVSampleBufferAttachContentKey would attach keys per sample
  // instead, but on macOS it needs the private
  // com.apple.private.coremedia.allow-fps-attachment entitlement (WebKit's GPU
  // process has it; other processes get -11836 <- -12161, "not authorized").
  //
  // Chromium's pipeline calls SetCdm before Initialize when MediaKeys were
  // attached first (the usual EME order); the CDM is then kept and attached
  // when Initialize creates the renderers.
  Result SetCdm(FairPlayCdm* cdm) {
    if (!synchronizer_) {
      pending_cdm_ = cdm;
      return Result::Ok();
    }
    return AttachCdm(cdm);
  }

  // Joins both renderers to |cdm|'s key session; cdm_ is set only once every
  // recipient joined. A null |cdm| detaches.
  Result AttachCdm(FairPlayCdm* cdm) {
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
      cdm_ = nullptr;
    }
    if (!cdm) {
      return Result::Ok();
    }
    std::vector<id<AVContentKeyRecipient>> joined;
    Result result = Result::Ok();
    for (id object : {(id)layer_, (id)audio_}) {
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
    }
    if (!result.ok()) {
      for (id<AVContentKeyRecipient> recipient : joined) {
        DetachContentKeyRecipient(cdm->impl(), recipient);
      }
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
    OnKeysChanged();
    return Result::Ok();
  }

  // A new decoder config mid-stream (Chromium's DemuxerStream kConfigChanged)
  // for the samples enqueued from now on; encrypted-ness can't change.
  Result Reconfigure(const VideoConfig& config) {
    if (!video_renderer_) {
      return Result::Error(Exception::kInvalidState, "no video stream");
    }
    std::string error;
    return ConfigureVideo(config, &error);
  }

  Result Reconfigure(const AudioConfig& config) {
    if (!audio_) {
      return Result::Error(Exception::kInvalidState, "no audio stream");
    }
    std::string error;
    return ConfigureAudio(config, &error);
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
    held.start = sample.pts.InSeconds();
    held.end = end.InSeconds();
    held.keyframe = stream == StreamType::kAudio || sample.is_keyframe;
    if (!state.held.empty() || !Submit(stream, held)) {
      state.held.push_back(std::move(held));
      if (!waiting_reported_) {
        waiting_reported_ = true;
        PostInGeneration([](Impl& impl) { impl.client_->OnWaitingForKey(); });
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
    StopRequest(stream);
    state.armed = false;
    // A stream that ends before AVFoundation considers it sufficient (a short
    // clip, the last segment) counts as enough from here on, once none of its
    // samples wait for a key.
    UpdateBuffering();
    ScheduleEndIfComplete();
  }

  // The clock stays at |time| until both renderers have enough data, whatever
  // rate is set meanwhile: Chromium's CompleteSeek calls StartPlayingFrom and
  // SetPlaybackRate in one task, and RendererImpl starts its time source only
  // on HAVE_ENOUGH. The requested rate is kept and applied then.
  void StartPlayingFrom(MediaTime time) {
    start_time_ = time;
    ended_ = false;
    have_enough_ = false;
    clock_held_ = true;
    [synchronizer_ setRate:0 time:ToCMTime(time)];
    NotifyNeedData(StreamType::kVideo);
    NotifyNeedData(StreamType::kAudio);
    UpdateBuffering();
  }

  void SetPlaybackRate(double rate) {
    status_.rate = static_cast<float>(rate);
    if (!clock_held_) {
      synchronizer_.rate = static_cast<float>(rate);
    }
  }

  void SetVolume(float volume) { audio_.volume = volume; }
  void SetMuted(bool muted) { audio_.muted = muted; }
  // AVSampleBufferAudioRenderer throws on a nil device ID, so "the system
  // default" is the default device's UID at the time of the call.
  Result SetAudioOutputDevice(const std::string& unique_id) {
    if (!audio_) {
      return Result::Error(Exception::kInvalidState, "no audio stream");
    }
    if (unique_id.empty() && !output_device_set_) {
      return Result::Ok();  // Still following the system default.
    }
    NSString* uid = unique_id.empty() ? DefaultOutputDeviceUid() : @(unique_id.c_str());
    if (!uid.length) {
      return Result::Error(Exception::kNotSupported, "no default audio output device");
    }
    audio_.audioOutputDeviceUniqueID = uid;
    // Once a device was named the renderer stays pinned to one, so every
    // later "" names the default of that moment.
    output_device_set_ = true;
    return Result::Ok();
  }

  void Flush(std::function<void()> done) {
    synchronizer_.rate = 0;
    status_.rate = 0;
    RemoveEndObserver();
    for (StreamType stream : {StreamType::kVideo, StreamType::kAudio}) {
      id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
      Stream& state = StreamFor(stream);
      StopRequest(stream);
      [renderer flush];
      state = Stream();
    }
    waiting_reported_ = false;
    ended_ = false;
    ++generation_;
    flush_count_->store(generation_);
    // Like RendererImpl::Flush: back to HAVE_NOTHING without a callback; the
    // next HAVE_ENOUGH follows StartPlayingFrom.
    have_enough_ = false;
    clock_held_ = true;
    Post([done](Impl&) { done(); });
  }

  // Any thread: CMTimebase reads are thread-safe, and the timebase is
  // retained for the renderer's lifetime.
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
    status.audio_format = subtype(audio_clear_format_.get());
    auto last_protected = [](const auto& cache, const std::vector<uint8_t>& key) -> CMFormatDescriptionRef {
      auto it = cache.find(key);
      return it == cache.end() ? nullptr : it->second->get();
    };
    status.video_protected_format = subtype(last_protected(video_protected_formats_, video_protected_key_));
    status.audio_protected_format = subtype(last_protected(audio_protected_formats_, audio_protected_key_));
    if (video_renderer_) {
      if (@available(macOS 14.0, *)) {
        AVSampleBufferVideoRenderer* renderer = layer_.sampleBufferRenderer;
        status.video = Map(renderer.status);
        status.video_error = renderer.error ? Describe(renderer.error) : "";
        status.video_requires_flush = renderer.requiresFlushToResumeDecoding;
      } else {
// macOS 13 has only the layer's own queue state (deprecated from 15).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status.video = Map(layer_.status);
        status.video_error = layer_.error ? Describe(layer_.error) : "";
        status.video_requires_flush = layer_.requiresFlushToResumeDecoding;
#pragma clang diagnostic pop
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
    double start = 0;  // Presentation start, seconds.
    double end = 0;    // Presentation end, seconds.
    bool keyframe = true;

    Held() = default;
    Held(Held&& other) noexcept
        : buffer(other.buffer),
          encrypted(other.encrypted),
          key_id(std::move(other.key_id)),
          start(other.start),
          end(other.end),
          keyframe(other.keyframe) {
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

  // A buffer already given to AVFoundation, kept for re-delivery.
  struct Submitted {
    CMSampleBufferRef buffer = nullptr;  // Retained.
    double start = 0;
    double end = 0;
    bool keyframe = true;

    Submitted(CMSampleBufferRef retained, double start, double end, bool keyframe)
        : buffer(retained), start(start), end(end), keyframe(keyframe) {}
    Submitted(const Submitted&) = delete;
    Submitted& operator=(const Submitted&) = delete;
    Submitted(Submitted&& other) noexcept
        : buffer(other.buffer), start(other.start), end(other.end), keyframe(other.keyframe) {
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
    // What AVFoundation holds or may need again: audio from the playback
    // position on, video from the last keyframe at or before it.
    std::deque<Submitted> submitted;
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

  // Posts |task| for the current flush generation only: anything about the
  // media before a Flush (end reached, more data wanted, buffering) is
  // dropped if it lands after it.
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
    notification_tokens_.push_back(token);
  }

  // Format descriptions come from the ISO sample entry the stream would have
  // carried, converted by CoreMedia's public sample-description parser
  // (kCMImageDescriptionFlavor_ISOFamily). For a protected entry ('encv'/'enca'
  // with 'sinf') that yields exactly what AVStreamDataParser produces: Apple's
  // FairPlay type for the codec (qavc, qhvc, qdh1, qav1, qaac, qach,
  // qusa, ...), CommonEncryptionOriginalFormat, CommonEncryptionProtected, the
  // 'tenc' payload and the config and 'sinf' atoms. Content key recipients
  // match keys by that 'tenc' key ID.
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
    if (config.codec == VideoCodec::kAV1 && config.format == BitstreamFormat::kAnnexB) {
      return Result::Error(Exception::kTypeError, "AV1 samples are never Annex B");
    }
    std::vector<std::vector<uint8_t>> children{MakeBox(ConfigBox(config.codec), config.extra_data)};
    if (config.codec == VideoCodec::kDolbyVision && config.dolby_vision_config.size() >= 3) {
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
    }
    std::vector<uint8_t> entry =
        AudioSampleEntry(entry_type, static_cast<uint16_t>(config.channels),
                         static_cast<uint32_t>(config.sample_rate), children);
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

  // (Re)creates the clear video format and drops the protected ones, which
  // are rebuilt per key ID; one is built up front when the key ID is known.
  Result CreateVideoFormats(std::string* error) {
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateVideoFormat(*video_config_, nullptr, &clear); !result.ok()) {
      return result;
    }
    // Nothing changes unless every format builds.
    ScopedFormat previous_clear;
    previous_clear.Swap(video_clear_format_);
    video_clear_format_.Reset(clear);
    auto previous_protected = std::move(video_protected_formats_);
    video_protected_formats_.clear();
    const TrackEncryption& encryption = video_config_->encryption;
    if (IsEncrypted(encryption) && !encryption.default_key_id.empty() &&
        !ProtectedFormat(StreamType::kVideo, encryption.default_key_id, std::nullopt, error)) {
      video_clear_format_.Swap(previous_clear);
      video_protected_formats_ = std::move(previous_protected);
      return Result::Error(Exception::kNotSupported, *error);
    }
    return Result::Ok();
  }

  Result CreateAudioFormats(std::string* error) {
    CMFormatDescriptionRef clear = nullptr;
    if (Result result = CreateAudioFormat(*audio_config_, nullptr, &clear); !result.ok()) {
      return result;
    }
    // Nothing changes unless every format builds.
    ScopedFormat previous_clear;
    previous_clear.Swap(audio_clear_format_);
    audio_clear_format_.Reset(clear);
    auto previous_protected = std::move(audio_protected_formats_);
    audio_protected_formats_.clear();
    const TrackEncryption& encryption = audio_config_->encryption;
    if (IsEncrypted(encryption) && !encryption.default_key_id.empty() &&
        !ProtectedFormat(StreamType::kAudio, encryption.default_key_id, std::nullopt, error)) {
      audio_clear_format_.Swap(previous_clear);
      audio_protected_formats_ = std::move(previous_protected);
      return Result::Error(Exception::kNotSupported, *error);
    }
    return Result::Ok();
  }

  // Takes |config| for the samples enqueued from now on. A record that isn't
  // complete yet (empty, or without parameter sets) waits for the next
  // keyframe.
  Result ConfigureVideo(const VideoConfig& config, std::string* error) {
    if (config.coded_width <= 0 || config.coded_height <= 0 || config.coded_width > 0xffff ||
        config.coded_height > 0xffff) {
      return Result::Error(Exception::kTypeError, "video config needs a coded size");
    }
    video_config_ = config;
    if (config.codec == VideoCodec::kDolbyVision && config.dolby_vision_config.empty() &&
        config.dolby_vision_profile >= 0) {
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
    const bool complete = config.codec == VideoCodec::kAV1
                              ? !config.extra_data.empty()
                              : RecordHasParameterSets(config.codec, config.extra_data);
    awaiting_video_config_ = !complete;
    if (complete) {
      if (config.codec != VideoCodec::kAV1) {
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

  Result ConfigureAudio(const AudioConfig& config, std::string* error) {
    audio_config_ = config;
    audio_clear_format_.Reset(nullptr);
    audio_protected_formats_.clear();
    awaiting_audio_config_ = config.extra_data.empty() && config.codec != AudioCodec::kAAC;
    if (awaiting_audio_config_) {
      return Result::Ok();
    }
    return CreateAudioFormats(error);
  }

  void ReportNaturalSize(int32_t width, int32_t height) {
    if (width == natural_width_ && height == natural_height_) {
      return;
    }
    natural_width_ = width;
    natural_height_ = height;
    Post([width, height](Impl& impl) { impl.client_->OnVideoNaturalSizeChange(width, height); });
  }

  // Keyframes carry the decoder configuration in-band (Chromium re-inserts
  // SPS/PPS/VPS before each one; AV1 keyframes start with a sequence header).
  // Builds the record from it when the config had none, and rebuilds it when
  // it changes (an adaptive-streaming switch). A failed rebuild leaves the
  // previous record, sets and formats in place.
  bool UpdateVideoConfigFromKeyframe(const uint8_t* data, size_t size, std::string* error) {
    const VideoCodec codec = video_config_->codec;
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
    size_t length_size = 4;  // Annex B input is rewritten with 4-byte lengths.
    if (video_config_->format == BitstreamFormat::kLengthPrefixed && record.size() > (avc ? 4u : 21u)) {
      length_size = (record[avc ? 4 : 21] & 3) + 1;
    }
    std::vector<std::vector<uint8_t>> sets = ParameterSetsInSample(codec, data, size, length_size);
    if (sets.empty()) {
      *error = "no parameter sets in the config record or before the first frame";
      return !awaiting_video_config_;
    }
    // A keyframe may repeat only some sets (a new SPS and PPS under the same
    // VPS, or PPS 0 but not PPS 1): earlier sets whose kind and ID it doesn't
    // carry stay as they were.
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
    // CoreMedia takes them in kind order: (VPS,) SPS, PPS.
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
    // The config's natural size (Chromium's, from tkhd and pasp) wins; the
    // stream's own display size is used only when the config has none.
    if (!video_config_->natural_width || !video_config_->natural_height) {
      ReportNaturalSize(static_cast<int32_t>(presentation.width), static_cast<int32_t>(presentation.height));
    }
    return true;
  }

  // dac3/dec3 from the first syncframe's clear header; when the syncframes
  // are encrypted (whole-sample audio encryption), from the config's sample
  // rate and channel count.
  bool UpdateAudioConfigFromSyncframe(const uint8_t* data, size_t size,
                                      const std::vector<SubsampleEntry>* subsamples, std::string* error) {
    const bool eac3 = audio_config_->codec == AudioCodec::kEAC3;
    std::optional<std::vector<uint8_t>> payload =
        eac3 ? Eac3SpecificBoxPayload(data, size, subsamples) : Ac3SpecificBoxPayload(data, size, subsamples);
    const int32_t channels = audio_config_->channels;
    if (!payload && subsamples) {
      payload = eac3 ? Eac3SpecificBoxFromConfig(audio_config_->sample_rate, channels)
                     : Ac3SpecificBoxFromConfig(audio_config_->sample_rate, channels);
      // A 6.1/7.1 config gets the box of its 5.1 core; the sample entry
      // says 6 channels to match it.
      if (payload && channels > 6) {
        audio_config_->channels = 6;
      }
    }
    if (!payload) {
      *error = subsamples ? "AC-3/E-AC-3 config needs a 48, 44.1 or 32 kHz rate and 1-8 channels"
                          : "no AC-3/E-AC-3 syncframe at the start of the first audio sample";
      return false;
    }
    audio_config_->extra_data = *payload;
    if (Result result = CreateAudioFormats(error); !result.ok()) {
      audio_config_->extra_data.clear();
      audio_config_->channels = channels;
      *error = result.message;
      return false;
    }
    awaiting_audio_config_ = false;
    return true;
  }

  // The protected format description for samples encrypted with |key_id|
  // (and |pattern|): recipients match keys by the format description's 'tenc'
  // key ID, so each key gets its own. Fields the config lacks come from the
  // sample: its pattern, and per-sample 16-byte IVs when no constant IV is
  // known (Chromium copies the constant IV into every DecryptConfig).
  CMFormatDescriptionRef ProtectedFormat(StreamType stream, const std::vector<uint8_t>& key_id,
                                         const std::optional<EncryptionPattern>& pattern,
                                         std::string* error) {
    auto& cache = stream == StreamType::kVideo ? video_protected_formats_ : audio_protected_formats_;
    std::vector<uint8_t> cache_key = key_id;
    if (pattern) {
      cache_key.push_back(pattern->crypt_byte_block);
      cache_key.push_back(pattern->skip_byte_block);
    }
    (stream == StreamType::kVideo ? video_protected_key_ : audio_protected_key_) = cache_key;
    auto it = cache.find(cache_key);
    if (it != cache.end()) {
      return it->second->get();
    }
    TrackEncryption encryption = stream == StreamType::kVideo ? video_config_->encryption
                                                               : audio_config_->encryption;
    encryption.default_key_id = key_id;
    if (pattern) {
      encryption.default_pattern = *pattern;
    }
    if (encryption.default_constant_iv.empty() && encryption.default_per_sample_iv_size == 0) {
      encryption.default_per_sample_iv_size = 16;
    }
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
    cache[cache_key] = std::move(holder);
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
    } else if (stream == StreamType::kAudio && audio_config_->framing == AudioFraming::kADTS &&
               AdtsHeaderSize(sample.data, sample.size)) {
      size_t header = AdtsHeaderSize(sample.data, sample.size);
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
    if (stream == StreamType::kVideo && (awaiting_video_config_ || sample.is_keyframe) &&
        !UpdateVideoConfigFromKeyframe(bytes, size, error)) {
      CFRelease(block);
      return false;
    }
    if (stream == StreamType::kAudio && awaiting_audio_config_ &&
        !UpdateAudioConfigFromSyncframe(bytes, size, encrypted ? &subsamples : nullptr, error)) {
      CFRelease(block);
      return false;
    }
    CMFormatDescriptionRef format =
        encrypted ? ProtectedFormat(stream, key_id, sample.decrypt->pattern, error)
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
    CFRetain(held.buffer);
    state.submitted.emplace_back(held.buffer, held.start, held.end, held.keyframe);
    TrimSubmitted(stream);
    return true;
  }

  void TrimSubmitted(StreamType stream) {
    std::deque<Submitted>& submitted = StreamFor(stream).submitted;
    const double now = GetMediaTime().InSeconds();
    if (stream == StreamType::kAudio) {
      // A little behind the clock, for a flush reported as it plays.
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

  // AVSampleBufferAudioRenderer flushes itself when the output changes (a
  // route or device switch) and reports the start of the first sample it
  // dropped; without re-delivery the queued duration would play as silence.
  void OnAudioFlushedAutomatically(double flush_time) {
    ++status_.audio_automatic_flushes;
    // A flush of the previous timeline whose notice arrives after Flush
    // carries a time outside what was enqueued since; acting on it would
    // queue the new audio twice.
    const std::deque<Submitted>& submitted = audio_stream_.submitted;
    if (submitted.empty() || flush_time + 1e-6 < submitted.front().start ||
        flush_time > audio_stream_.enqueued_end + 1e-6) {
      return;
    }
    for (const Submitted& entry : submitted) {
      if (entry.start + 1e-6 >= flush_time) {
        [audio_ enqueueSampleBuffer:entry.buffer];
        ++status_.redelivered;
      }
    }
  }

  // A video decoder that lost its state (requiresFlushToResumeDecoding) is
  // flushed and fed again from the last keyframe at or before the clock;
  // frames already due are decoded but not displayed.
  void ResumeVideoDecoding() {
    if (!video_renderer_ || !GetStatus().video_requires_flush) {
      return;
    }
    StopRequest(StreamType::kVideo);
    video_.armed = false;
    [video_renderer_ flush];
    ++status_.video_decoder_resets;
    const double now = GetMediaTime().InSeconds();
    bool from_keyframe = false;
    for (const Submitted& entry : video_.submitted) {
      from_keyframe |= entry.keyframe;
      if (!from_keyframe) {
        continue;
      }
      if (entry.end <= now) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(entry.buffer, true);
        if (attachments && CFArrayGetCount(attachments)) {
          CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0),
                               kCMSampleAttachmentKey_DoNotDisplay, kCFBooleanTrue);
        }
      }
      [video_renderer_ enqueueSampleBuffer:entry.buffer];
      ++status_.redelivered;
    }
    NotifyNeedData(StreamType::kVideo);
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

  // Asks AVFoundation to say when |stream| can take more. AVFoundation calls
  // the block repeatedly while the renderer is ready, so the first call stops
  // the request right there (Apple's documented pattern) and hands over to the
  // owner sequence. The gate keeps that stop from landing on a newer request:
  // the owner holds it around every request and stop call, and a block that
  // finds it taken returns and is called again.
  void ArmRequest(StreamType stream) {
    Stream& state = StreamFor(stream);
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || state.armed || state.end_of_stream) {
      return;
    }
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
                                        if (impl && impl->generation_ == generation) {
                                          impl->StreamFor(stream).armed = false;
                                          impl->DeliverNeedData(stream);
                                        }
                                      });
                                    }];
  }

  void StopRequest(StreamType stream) {
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer) {
      return;
    }
    std::shared_ptr<RequestGate> gate = GateFor(stream);
    std::lock_guard<std::mutex> lock(gate->mutex);
    ++gate->current;
    [renderer stopRequestingMediaData];
  }

  std::shared_ptr<RequestGate> GateFor(StreamType stream) const {
    return stream == StreamType::kVideo ? video_gate_ : audio_gate_;
  }

  // Client callbacks are posted, never made from inside a renderer call.
  void NotifyNeedData(StreamType stream) {
    if (!RendererFor(stream) || StreamFor(stream).end_of_stream) {
      return;
    }
    PostInGeneration([stream](Impl& impl) { impl.DeliverNeedData(stream); });
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

  // A stream that reached end of stream with every sample in its renderer
  // has all it will get. Samples still held for a key are not there yet.
  static bool Complete(const Stream& state) { return state.end_of_stream && state.held.empty(); }

  // HAVE_ENOUGH once every configured renderer reports enough data for a
  // reliable start, or is complete; then latched, because that property
  // toggles as queues drain and refill. Only CheckUnderflow drops back to
  // HAVE_NOTHING. OnKeysChanged re-evaluates once no sample is held. The
  // property is read, not observed: AVFoundation posts no KVO for it, and it
  // turns true on the enqueue that fills the renderer's preroll; every Submit
  // is followed by this call.
  void UpdateBuffering() {
    if (have_enough_) {
      return;
    }
    bool have_enough = true;
    if (video_renderer_ && !Complete(video_)) {
      have_enough &= video_renderer_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    if (audio_ && !Complete(audio_stream_)) {
      have_enough &= audio_.hasSufficientMediaDataForReliablePlaybackStart;
    }
    if (!have_enough) {
      return;
    }
    have_enough_ = true;
    if (clock_held_) {
      clock_held_ = false;
      synchronizer_.rate = status_.rate;
    }
    PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(true); });
  }

  // Underflow, as RendererImpl handles it: when the clock reaches the end of
  // what an incomplete stream (no end of stream yet, or samples held for a
  // key) has been given, stop the clock and report HAVE_NOTHING;
  // UpdateBuffering restarts it once data is back.
  void CheckUnderflow() {
    if (!have_enough_ || status_.rate == 0) {
      return;
    }
    double now = GetMediaTime().InSeconds();
    for (StreamType stream : {StreamType::kVideo, StreamType::kAudio}) {
      const Stream& state = StreamFor(stream);
      if (!RendererFor(stream) || Complete(state) || state.enqueued_end < 0) {
        continue;
      }
      if (state.enqueued_end - now < 0.05) {
        have_enough_ = false;
        clock_held_ = true;
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
  FairPlayCdm* pending_cdm_ = nullptr;  // Set before Initialize.
  uint64_t observer_id_ = 0;

  std::optional<VideoConfig> video_config_;
  std::optional<AudioConfig> audio_config_;
  const std::shared_ptr<RequestGate> video_gate_ = std::make_shared<RequestGate>();
  const std::shared_ptr<RequestGate> audio_gate_ = std::make_shared<RequestGate>();
  ScopedFormat video_clear_format_;
  ScopedFormat audio_clear_format_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> video_protected_formats_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> audio_protected_formats_;
  bool output_device_set_ = false;  // SetAudioOutputDevice named a device.
  // Cache keys of the protected formats last used (GetStatus reports them).
  std::vector<uint8_t> video_protected_key_;
  std::vector<uint8_t> audio_protected_key_;
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
  // The clock waits for HAVE_ENOUGH (start, seek or underflow).
  bool clock_held_ = true;
  bool awaiting_video_config_ = false;  // Record comes from the next keyframe.
  bool awaiting_audio_config_ = false;  // dac3/dec3 from the next syncframe.
  std::vector<std::vector<uint8_t>> parameter_sets_;  // Behind the current record.
  std::vector<uint8_t> av1_sequence_header_;
  int32_t natural_width_ = 0;
  int32_t natural_height_ = 0;
  uint64_t generation_ = 0;  // Bumped by Flush; stale posted tasks compare it.
  // generation_ for threads other than the owner's (notification blocks).
  const std::shared_ptr<std::atomic<uint64_t>> flush_count_ = std::make_shared<std::atomic<uint64_t>>(0);
  // Retained synchronizer timebase, read by GetMediaTime from any thread.
  std::atomic<CMTimebaseRef> timebase_{nullptr};
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

Result FairPlayRenderer::Reconfigure(const VideoConfig& config) {
  return impl_->Reconfigure(config);
}

Result FairPlayRenderer::Reconfigure(const AudioConfig& config) {
  return impl_->Reconfigure(config);
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

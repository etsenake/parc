#include "fairplay_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreMedia/CoreMedia.h>

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

// WebKit's SourceBufferPrivateAVFObjC::enqueueSampleBuffer, before the
// readyForDisplay notification became public in macOS 14.4.
@interface AVSampleBufferDisplayLayer (ParcPrerollDecode)
- (void)prerollDecodeWithCompletionHandler:(void (^)(BOOL success))handler;
@end

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

// The layer the compositor places (display_layer()). It holds the display
// layer, and while a replacement joins the key session (SetCdm after media
// was processed) the outgoing one above it, each filling its bounds.
@interface PCFairPlayVideoHost : CALayer
@end

namespace parc::fairplay {
namespace {

// WebKit's MediaSource::monitorSourceBuffers: HAVE_ENOUGH_DATA once the
// buffered ranges hold 3 s past the current time.
constexpr double kEnoughAheadSeconds = 3;
// How far past the clock samples held for a key are taken, a little beyond
// kEnoughAheadSeconds so held data can reach it.
constexpr double kHeldAheadSeconds = 4;
// The stall boundary is armed once the clock is this close to it; the clock
// observer polls every 0.1 s.
constexpr double kStallArmSeconds = 0.25;
// How far ahead of the clock an audio renderer replacing another starts: its
// first sample must reach it before the clock does (ReplaceRenderers).
constexpr double kAudioHandOffLeadSeconds = 0.25;

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

// Whether Core Audio still has a device with |uid|: an unplugged headset or a
// disconnected Bluetooth device leaves the list.
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

// The system's device list and default output device.
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

bool IsTransportStreamKeyId(const std::vector<uint8_t>& key_id) {
  return std::equal(key_id.begin(), key_id.end(), std::begin(kTransportStreamKeyId),
                    std::end(kTransportStreamKeyId) - 1);
}

// The format type AVStreamDataParser gives an MPEG-2 TS SAMPLE-AES stream:
// zavc for H.264, and for audio the PMT's audio_type: zaac, zach or zacp as
// the AAC setup data signals AAC, HE-AAC or HE-AACv2, zac3 or zec3. 0 for
// codecs TS SAMPLE-AES doesn't carry.
uint32_t TransportStreamFormatType(VideoCodec codec) {
  return codec == VideoCodec::kH264 ? FourCC('z', 'a', 'v', 'c') : 0;
}

uint32_t TransportStreamFormatType(const AudioConfig& config) {
  if (config.ts_audio_type)
    return config.ts_audio_type;  // AVStreamDataParser uses the PMT declaration.
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

// The clear format's extensions plus the TransportStreamEncryptionInitData
// extension that marks the format as SAMPLE-AES protected.
NSDictionary* TransportStreamExtensions(CMFormatDescriptionRef clear, uint32_t type, uint32_t media_type) {
  NSMutableDictionary* extensions =
      [(__bridge NSDictionary*)CMFormatDescriptionGetExtensions(clear) mutableCopy] ?: [NSMutableDictionary dictionary];
  extensions[@"TransportStreamEncryptionInitData"] =
      ToNSData(TransportStreamEncryptionInitData(type, media_type));
  return extensions;
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
    // Each attempt reports its own natural size; a failed attempt's queued
    // report is dropped (ReportNaturalSize checks the attempt).
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

  // As AudioVideoRendererAVFObjC::addTrack does for a video track selected
  // while another plays: the renderer is flushed, keeping its picture, and
  // the clock waits for a frame of the new track (flushVideo, then
  // updateAllRenderersHaveAvailableSamples). The new track's samples before
  // the current time are decoded, not shown.
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
    [outgoing_video_renderer_ flush];
    RemoveSizeObservers();
    // A size not shown yet waits for the new track's first sample.
    size_change_pending_ = natural_width_ != reported_width_ || natural_height_ != reported_height_;
    video_ = Stream();
    video_.start = GetMediaTime().InSeconds();
    // The old track's samples held for a key went with it.
    const auto streams = Streams();
    if (waiting_reported_ && std::none_of(streams.begin(), streams.end(), [this](StreamId stream) {
          return StreamFor(stream) && !StreamFor(stream)->held.empty();
        })) {
      waiting_reported_ = false;
    }
    ResetVideoFrameAvailability();
    video_reset_pending_ = true;
    // The end moves to the new track's.
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
    [renderer flush];
    [synchronizer_ removeRenderer:renderer atTime:CMTimebaseGetTime(synchronizer_.timebase) completionHandler:nil];
    StopObserving(renderer);
    if (auto outgoing = outgoing_audio_.find(track); outgoing != outgoing_audio_.end()) {
      // Silent until it leaves at the time it was given.
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
    // The end moves with the streams that remain.
    RemoveEndObserver();
    UpdateBuffering();
    ScheduleEndIfComplete();
  }

  // A stream added during playback: the clock waits for its samples
  // (AudioVideoRendererAVFObjC::updateAllRenderersHaveAvailableSamples) and
  // HAVE_ENOUGH for its data; samples before the current time aren't shown.
  void OnStreamAdded(StreamId stream) {
    StreamFor(stream)->start = GetMediaTime().InSeconds();
    renderers_have_samples_ = false;
    // The end moves to the new stream's, unless it was reported already.
    RemoveEndObserver();
    if (std::exchange(have_enough_, false)) {
      PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(false); });
    }
    UpdateBuffering();
    NotifyNeedData(stream);
  }

  // A renderer created after AttachCdm joins its key session: it hasn't
  // processed media yet, so AVFoundation takes it.
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
    // The owner sequence may have no run loop to commit an implicit
    // transaction, so the layer's setup is committed explicitly.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!host_) {
      host_ = [PCFairPlayVideoHost layer];
    }
    layer_ = [AVSampleBufferDisplayLayer layer];
    // What CARendererLayerTree::FillProtectedLayer gives a display layer it
    // places itself; it places the host instead. cc lays the video out at its
    // display aspect ratio, protected video is never captured, and the flip is
    // Chromium's workaround for transformed HDR content (crbug.com/398425794).
    layer_.videoGravity = AVLayerVideoGravityResize;
    layer_.preventsCapture = YES;
    layer_.geometryFlipped = YES;
    layer_.frame = host_.bounds;
    // Below an outgoing layer, which covers it until it has a frame.
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
    // readyForDisplay isn't key-value observable (VideoFrameAvailable).
    if (UsesDisplayReadinessNotification()) {
      if (@available(macOS 14.4, *)) {
        AddNotification(center, AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification, layer_,
                        [](Impl& impl, NSNotification*) { impl.UpdateBuffering(); });
      }
    }
    return Result::Ok();
  }

  // With the volume, mute, pitch and output device the others have
  // (AudioVideoRendererAVFObjC::addAudioRenderer).
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
    // The flush time belongs to the timeline of the moment AVFoundation
    // posts it, so the generation is read then, not when the task runs.
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

  // -addRenderer: throws for a renderer AVFoundation couldn't set up (an
  // AVSampleBufferAudioRenderer is invalid when Core Audio's services are out
  // of reach, as in a sandbox that denies them). Initialize then fails and
  // leaves the renderer uninitialized instead of taking the process down; a
  // stream added later fails alone.
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
    // Renderers go first, so Shutdown sends nothing more to an invalid one;
    // it still removes what was observed through its own records.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer_ removeFromSuperlayer];
    [CATransaction commit];
    layer_ = nil;
    video_renderer_ = nil;
    for (auto& [track, audio] : audio_) {
      audio.renderer = nil;
    }
    // A CDM set before Initialize waits for the next attempt.
    FairPlayCdm* pending_cdm = pending_cdm_;
    Shutdown();
    pending_cdm_ = pending_cdm;
    audio_.clear();
    synchronizer_ = nil;
    if (CMTimebaseRef timebase = timebase_.exchange(nullptr)) {
      CFRelease(timebase);
    }
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
    Result result = Result::Ok();
    if (!synchronizer_) {
      pending_cdm_ = cdm;
    } else {
      result = AttachCdm(cdm);
    }
    if (result.ok() && cdm && cdm_detached_) {
      // WebKit's setCDMInstance then attemptToDecrypt: the held samples go.
      cdm_detached_ = false;
      if (cdm_) {
        OnKeysChanged();
      }
    }
    return result;
  }

  void DetachCdm() { cdm_detached_ = true; }

  // Joins every renderer to |cdm|'s key session; cdm_ is set only once every
  // recipient joined. A null |cdm| detaches.
  Result AttachCdm(FairPlayCdm* cdm) {
    if (cdm == cdm_) {
      return Result::Ok();
    }
    // A recipient can't join another key session once it left one, so a new
    // CDM always takes new renderers; the outgoing ones keep the old CDM's
    // keys until they leave (ReleaseOutgoingRecipients).
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

  // AVFoundation takes content key recipients only before they process media,
  // and Safari attaches each sample's key itself instead
  // (AVSampleBufferAttachContentKey, a private entitlement). So renderers that
  // played without a CDM hand over to new ones that join its key session
  // first, in the same synchronizer, as WebKit's stageVideoRenderer swaps
  // video renderers on one timeline: the clock and the page see nothing. The
  // outgoing display layer stays above its replacement, showing its picture,
  // until the replacement has a frame (RetireOutgoingLayer); each outgoing
  // audio renderer plays on until the first sample replayed into the new one
  // (Replay). Nothing is enqueued into the new renderers before AttachCdm
  // joins them.
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
        // An earlier hand-off's layer has no frame yet: it goes, and the one
        // still showing the picture stays above the new one.
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

  // Feeds the replacements what the outgoing renderers hold (see
  // ReplaceRenderers): video from the last keyframe at or before the clock,
  // hidden up to it; audio from the first sample kAudioHandOffLeadSeconds
  // ahead, where the outgoing renderer leaves the synchronizer.
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
        [video_renderer_ enqueueSampleBuffer:entry.buffer];
        RequestVideoFrameAvailability(entry.buffer);
        ++status_.redelivered;
        ++video_replayed_;
      }
    }
    std::map<uint32_t, double> leaves;
    for (auto& [track, audio] : audio_) {
      Stream& state = audio.stream;
      // After an earlier hand-off's outgoing renderer leaves, so no stretch
      // plays twice.
      auto earlier = audio_outgoing_end_.find(track);
      const double from = std::max(now + kAudioHandOffLeadSeconds,
                                   earlier == audio_outgoing_end_.end() ? now : earlier->second);
      // One that ran dry still leaves only once the new one plays: taking the
      // synchronizer's last audio renderer away first moves its clock back.
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
      // What the outgoing renderer plays: until it leaves, or its last sample.
      audio_outgoing_end_[track] = std::min(leave, state.enqueued_end);
    }
    for (auto& [track, renderer] : std::exchange(leaving_audio_, {})) {
      RetireOutgoingAudio(track, renderer, leaves.contains(track) ? leaves[track] : now);
    }
  }

  // An outgoing audio renderer leaves the synchronizer at |leave| on its
  // timeline, as WebKit's removeRendererFromSynchronizerIfNeeded removes one.
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

  // A hand-off that failed: the renderers it replaced leave at once.
  void RetireLeavingAudio(double now) {
    for (auto& [track, renderer] : std::exchange(leaving_audio_, {})) {
      RetireOutgoingAudio(track, renderer, now);
    }
  }

  // Detaches outgoing renderers from the key session of the CDM they kept
  // (every one when |renderer| is nil); the CDM's owner keeps it alive for
  // this renderer (FairPlayRendererAdapter::SetCdm).
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

  // The replacement display layer has a frame: the outgoing one above it
  // leaves, with its counts kept for LoadVideoMetrics.
  void RetireOutgoingLayer() {
    if (!outgoing_layer_) {
      return;
    }
    AVSampleBufferDisplayLayer* layer = std::exchange(outgoing_layer_, nil);
    RemoveLayer(layer, std::exchange(outgoing_video_renderer_, nil));
    if (@available(macOS 14.4, *)) {
      // Frames replayed into the new layer were counted by the outgoing one
      // too (most of them; never below zero).
      const int64_t replayed = static_cast<int64_t>(std::exchange(video_replayed_, 0));
      std::weak_ptr<Impl> weak = weak_from_this();
      std::shared_ptr<const PostTask> poster = poster_;
      [layer.sampleBufferRenderer loadVideoPerformanceMetricsWithCompletionHandler:^(AVVideoPerformanceMetrics* metrics) {
        (void)layer;  // Kept until the answer.
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

  // A new decoder config mid-stream (Chromium's DemuxerStream kConfigChanged,
  // also a new codec after MSE changeType) for the samples enqueued from now
  // on. Clear and protected samples may follow either way: each sample's
  // DecryptInfo picks its format, as with clear lead.
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
  }

  bool IsReadyForMoreData(StreamId stream) {
    const Stream* state = StreamFor(stream);
    id<AVQueuedSampleBufferRendering> renderer = RendererFor(stream);
    if (!renderer || state->end_of_stream) {
      return false;
    }
    // Samples held for a key queue up to kHeldAheadSeconds past the clock,
    // as WebKit keeps taking samples into its blocked queue, so held data
    // counts towards HAVE_ENOUGH (UpdateBuffering).
    if (!state->held.empty()) {
      return state->given_end - GetMediaTime().InSeconds() < kHeldAheadSeconds;
    }
    const bool ready = renderer.readyForMoreMediaData;
    if (!ready) {
      // Capacity can turn false between Enqueue's check and the caller's
      // next read. Register at the check that actually stops the producer.
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
    // A stream that ends before AVFoundation considers it sufficient (a short
    // clip, the last segment) counts as enough from here on, once none of its
    // samples wait for a key.
    UpdateBuffering();
    ScheduleEndIfComplete();
  }

  // The clock stays at |time| until HAVE_ENOUGH and every renderer has
  // samples to play (UpdateClock), whatever rate is set meanwhile: Chromium's
  // CompleteSeek calls StartPlayingFrom and SetPlaybackRate in one task, and
  // RendererImpl starts its time source only on HAVE_ENOUGH. The requested
  // rate is kept and applied then.
  void StartPlayingFrom(MediaTime time) {
    start_time_ = time;
    ended_ = false;
    have_enough_ = false;
    renderers_have_samples_ = false;
    // WebKit's flushVideo: after a start or seek no video frame is available
    // until one decodes at the new time, and the clock waits for it
    // (updateAllRenderersHaveAvailableSamples). Releasing it on enqueued data
    // alone starts the clock while decoding still runs from the keyframe
    // before |time|, so the first frames arrive late and are dropped.
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
    status_.rate = static_cast<float>(rate);
    UpdatePitchAlgorithm();
    if (!clock_held_) {
      synchronizer_.rate = static_cast<float>(rate);
    }
  }

  void SetPreservesPitch(bool preserves_pitch) {
    preserves_pitch_ = preserves_pitch;
    UpdatePitchAlgorithm();
  }

  // WebKit's AudioVideoRendererAVFObjC (setRate, addAudioRenderer,
  // setPreservesPitchAndCorrectionAlgorithm) with MediaSessionManagerCocoa::
  // audioTimePitchAlgorithmForMediaPlayerPitchCorrectionAlgorithm: Varispeed
  // at the requested rate 0 or 1 or without pitch preservation, else
  // Spectral. The SDK's default (TimeDomain) would apply otherwise.
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

  // Every audio renderer still playing, outgoing ones included.
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
  // AVSampleBufferAudioRenderer throws on a nil device ID, so once a device
  // was named the renderers stay pinned to one, and "the system default" is
  // the default device's UID, followed as it changes. Kept for audio
  // renderers made later, as AudioVideoRendererAVFObjC::setOutputDeviceId
  // keeps m_audioOutputDeviceId.
  Result SetAudioOutputDevice(const std::string& unique_id) {
    if (unique_id.empty() && !output_device_uid_) {
      return Result::Ok();  // Still following the system default.
    }
    NSString* uid = unique_id.empty() ? DefaultOutputDeviceUid() : @(unique_id.c_str());
    if (!uid.length) {
      return Result::Error(Exception::kNotSupported, "no default audio output device");
    }
    follows_default_output_ = unique_id.empty();
    RouteAudio(uid);
    WatchAudioDevices();
    OnAudioDevicesChanged();  // The device may have gone already.
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

  // A named device that went away would stop the clock or fail the audio
  // renderers (WebKit leaves that to AVFoundation); every audio renderer
  // moves to the default device instead and plays on, as Chromium's audio
  // output falls back to it, and then follows the default.
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
    // Samples already due stay counted; the rest never will be.
    CountPassedVideo();
    video_due_ = {};
    synchronizer_.rate = 0;
    status_.rate = 0;
    RemoveEndObserver();
    // A size not shown yet waits for the next sample queued.
    RemoveSizeObservers();
    size_change_pending_ = natural_width_ != reported_width_ || natural_height_ != reported_height_;
    for (StreamId stream : Streams()) {
      StopRequest(stream);
      [RendererFor(stream) flush];
      *StreamFor(stream) = Stream();
    }
    // Outgoing renderers play nothing more; a layer's picture stays until
    // its replacement has a frame at the new time.
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
    // Like RendererImpl::Flush: back to HAVE_NOTHING without a callback; the
    // next HAVE_ENOUGH follows StartPlayingFrom.
    have_enough_ = false;
    renderers_have_samples_ = false;
    ResetVideoFrameAvailability();
    video_reset_pending_ = false;
    clock_held_ = true;
    RemoveStallObserver();
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
// macOS 13 has only the layer's own queue state (deprecated from 15).
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
              // The replaced layers' counts are added on the owner sequence,
              // where they are kept.
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
    CMSampleBufferRef buffer = nullptr;  // Owned.
    bool encrypted = false;
    std::vector<uint8_t> key_id;
    double start = 0;  // Presentation start, seconds.
    double end = 0;    // Presentation end, seconds.
    bool keyframe = true;
    // Given to AVFoundation before, and held again (HoldRedelivered).
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

  // A buffer already given to AVFoundation, kept for re-delivery.
  struct Submitted {
    CMSampleBufferRef buffer = nullptr;  // Retained.
    double start = 0;
    double end = 0;
    bool keyframe = true;
    // For holding it again after DetachCdm (HoldRedelivered).
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
    // What AVFoundation holds or may need again: audio from the playback
    // position on, video from the last keyframe at or before it.
    std::deque<Submitted> submitted;
    bool end_of_stream = false;
    bool armed = false;
    MediaTime last_end;
    double enqueued_end = -1;  // End of the last sample given to AVFoundation.
    // End of the last sample this stream was given, enqueued or held for a
    // key: the end of its buffered data as far as the renderer knows.
    double given_end = -1;
    // Audio: end of the latest sample in the renderer since it was flushed.
    double queued_end = -std::numeric_limits<double>::infinity();
    // Samples ending before it aren't shown: the start time, or for a stream
    // added during playback the time it joined.
    double start = -std::numeric_limits<double>::infinity();
    // See UpdateBuffering.
    bool has_samples = false;
  };

  // An audio track's renderer, formats and samples (see StreamId).
  struct AudioTrack {
    AVSampleBufferAudioRenderer* renderer = nil;
    AudioConfig config;
    Stream stream;
    const std::shared_ptr<RequestGate> gate = std::make_shared<RequestGate>();
    ScopedFormat clear_format;
    std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> protected_formats;
    std::vector<uint8_t> protected_key;  // Of the protected format used last.
    bool awaiting_config = false;        // dac3/dec3 from the next syncframe.
    bool failure_reported = false;
    id flushed_token = nil;  // AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification.
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
  // Null for an audio track that doesn't exist (removed).
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
  // Video and every audio track.
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
    notification_tokens_.push_back({object, token});
  }

  // Ends the key-value and notification observation of |object|.
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
        // Apple's 'alac' sample entry with its ALACSpecificBox; protected,
        // CoreMedia makes it 'qlac'.
        std::optional<std::vector<uint8_t>> alac = AlacSpecificBoxPayload(config.extra_data);
        if (!alac) {
          return Result::Error(Exception::kTypeError, "ALAC config needs its ALACSpecificConfig");
        }
        entry_type = FourCC('a', 'l', 'a', 'c');
        children.push_back(MakeBox(FourCC('a', 'l', 'a', 'c'), *alac));
        break;
      }
      case AudioCodec::kPCM: {
        // ISO 23003-5 'ipcm' or 'fpcm' with its 'pcmC' (little-endian), which
        // CoreMedia makes 'lpcm', as AVStreamDataParser does. Protected, it
        // stays 'enca': CoreAudio has no protected PCM decoder, so it fails at
        // the first enqueue, as it does in Safari.
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
    }
    // Opus in ISO-BMFF states 48 kHz in the sample entry whatever the input
    // rate ('dOps' carries that).
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

  // What AVStreamDataParser gives an MPEG-2 TS SAMPLE-AES stream: the clear
  // format under the stream's SAMPLE-AES type, with its extensions (and for
  // audio its cookie and channel layout) and TransportStreamEncryptionInitData.
  // Recipients decrypt those with the mpts request's key and the IV its CKC
  // carries; samples bring no IV or subsamples.
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
    // Nothing changes unless every format builds.
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

  // Takes |config| for the samples enqueued from now on. A record that isn't
  // complete yet (empty, or without parameter sets) waits for the next
  // keyframe.
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

  Result ConfigureAudio(AudioTrack& audio, const AudioConfig& config, std::string* error) {
    audio.config = config;
    audio.clear_format.Reset(nullptr);
    audio.protected_formats.clear();
    // Only AC-3/E-AC-3 build their box from the first syncframe.
    audio.awaiting_config = config.extra_data.empty() &&
                            (config.codec == AudioCodec::kAC3 || config.codec == AudioCodec::kEAC3);
    if (audio.awaiting_config) {
      return Result::Ok();
    }
    return CreateAudioFormats(audio, error);
  }

  // The first size is reported at once (metadata). A later one, from a new
  // config or a keyframe's own size, is reported when the clock reaches the
  // first sample in that size, as WebKit's AudioVideoRendererAVFObjC::
  // sizeWillChangeAtTime does with a boundary observer per change, not when
  // samples in it are queued ahead of playback.
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
    size_change_pending_ = true;  // Armed at the next sample, its first.
  }

  void PostNaturalSize(int32_t width, int32_t height) {
    if (width == reported_width_ && height == reported_height_) {
      return;
    }
    reported_width_ = width;
    reported_height_ = height;
    // Only for the Initialize attempt that queued it, and only if that
    // attempt succeeded (a synchronizer exists).
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
      // A box of the 5.1 core (AC-3 6.1/7.1, E-AC-3 6.1) gets a sample
      // entry of 6 channels to match it; E-AC-3 7.1 keeps its 8.
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

  // The protected format description for samples encrypted with |key_id|
  // (and |pattern|): recipients match keys by the format description's 'tenc'
  // key ID, so each key gets its own. Fields the config lacks come from the
  // sample: its pattern, and per-sample 16-byte IVs when no constant IV is
  // known (Chromium copies the constant IV into every DecryptConfig).
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
    // TS SAMPLE-AES leaves NAL unit headers, start codes, ADTS headers and
    // syncframe headers clear and has no subsamples: its samples reframe as
    // clear ones.
    const bool transport_stream = encrypted && IsTransportStreamKeyId(sample.decrypt->key_id);
    std::vector<SubsampleEntry> subsamples;
    if (encrypted) {
      subsamples = sample.decrypt->subsamples;
    }
    std::vector<SubsampleEntry>* clear_ranges = encrypted && !transport_stream ? &subsamples : nullptr;

    // Reframe into what the format description declares.
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
    // Chromium's DecoderBuffer has no decode timestamp. Copying the PTS would
    // make it run backwards across reordered frames, so it stays invalid and
    // AVFoundation decodes in enqueue order.
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
      // WebKit's reenqueueMediaForTime: samples before the one containing the
      // start time decode without display; that one is shown, so a frame is
      // ready at the start time (VideoFrameAvailable) and the clock can run.
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
  // AVFoundationErrorDomain -11800 "no content key present". After DetachCdm
  // none is enqueued (AudioVideoRendererAVFObjC::canEnqueueSample without a
  // CDM).
  bool Submit(StreamId stream, Held& held) {
    if (held.encrypted) {
      if (!cdm_ || cdm_detached_ || !cdm_->HasUsableKey(held.key_id)) {
        return false;
      }
      if (!held.redelivered) {
        ++status_.protected_enqueued;
      }
    }
    [RendererFor(stream) enqueueSampleBuffer:held.buffer];
    if (stream == StreamType::kVideo) {
      RequestVideoFrameAvailability(held.buffer);
    }
    // A sample given again is counted, and its video due, from the first time.
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

  // Moves the video samples the clock has reached from video_due_ into
  // video_frames_passed_ (VideoMetrics::frames_passed).
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
  // As WebKit's SourceBufferPrivate::reenqueSamples (NeedsFlush::Yes) does:
  // flush the renderer first, then enqueue again, in order, every submitted
  // sample from the one containing the clock. The renderer is empty when the
  // first goes in and nothing else enqueues meanwhile (one sequence), so each
  // sample is in it once, including any the pipeline enqueued between
  // AVFoundation's flush and this notice, which |submitted| holds too.
  void OnAudioFlushedAutomatically(uint32_t track, double flush_time) {
    AudioTrack* audio = Audio(track);
    if (!audio) {
      return;
    }
    ++status_.audio_automatic_flushes;
    // A flush of the previous timeline whose notice arrives after Flush
    // carries a time outside what was enqueued since; acting on it would
    // flush the new audio for nothing.
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
    // An outgoing renderer still plays what comes before its end (Replay).
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

  // A flush's re-delivery after DetachCdm, or a replay into renderers of a
  // new CDM without that sample's key: WebKit enqueues the samples again
  // through enqueueSample, which holds protected ones without a CDM or key
  // (canEnqueueSample). So the submitted samples from |from|, a protected
  // one, go back to the front of the held queue, in order, and wait as
  // Enqueue's do.
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

  // Audio enters the renderer in presentation order, so a sample more than
  // half queued already plays twice (RendererStatus::audio_double_enqueues).
  // Appends overlapping audio already read, in a misaligned frame grid, count
  // too; the harness's content has none.
  void NoteAudioQueued(Stream& audio, double start, double end) {
    if (start + (end - start) / 2 < audio.queued_end) {
      ++status_.audio_double_enqueues;
    }
    audio.queued_end = std::max(audio.queued_end, end);
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
      [video_renderer_ enqueueSampleBuffer:entry.buffer];
      RequestVideoFrameAvailability(entry.buffer);
      ++status_.redelivered;
    }
    // WebKit's flushVideo: no frame is available until one decodes again, and
    // the clock waits for it (updateAllRenderersHaveAvailableSamples). Only
    // video's availability changes; audio's stays as it was.
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
    // As WebKit's pre-14.4 enqueueSampleBuffer: only successful preroll of a
    // displayable sample supplies the first frame. Queue capacity is not it.
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

  // Since the last ResetVideoFrameAvailability.
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
        // Video the clock already passed while it waited (time runs on over
        // a frozen picture) is decoded, not shown, from the keyframe kept.
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

  // Asks AVFoundation to say when |stream| can take more. AVFoundation calls
  // the block repeatedly while the renderer is ready, so the first call stops
  // the request right there (Apple's documented pattern) and hands over to the
  // owner sequence. The gate keeps that stop from landing on a newer request:
  // the owner holds it around every request and stop call, and a block that
  // finds it taken returns and is called again.
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

  // AVFoundation sometimes never runs a request's block (seen with a muted
  // audio renderer armed before the clock started), which would stall the
  // clock at the end of what the renderer has. So a request still live once
  // the renderer is ready again is answered here.
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
          // Decided under the gate, so the request's own block can't answer
          // it too.
          std::shared_ptr<RequestGate> gate = impl->GateFor(stream);
          std::lock_guard<std::mutex> lock(gate->mutex);
          if (gate->current != request) {
            return;  // Answered, stopped or replaced.
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

  // Only for a stream that has a renderer.
  std::shared_ptr<RequestGate> GateFor(StreamId stream) const {
    return stream.type == StreamType::kVideo ? video_gate_ : Audio(stream.audio_track)->gate;
  }

  // Client callbacks are posted, never made from inside a renderer call.
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

  // A stream that reached end of stream with every sample in its renderer
  // has all it will get. Samples still held for a key are not there yet.
  static bool Complete(const Stream& state) { return state.end_of_stream && state.held.empty(); }

  // HAVE_ENOUGH: every configured stream has reached end of stream, or was
  // given samples (enqueued or held for a key) reaching kEnoughAheadSeconds
  // past the clock, or its renderer has enough for a reliable start; and
  // after a start or seek a video frame decoded (VideoFrameAvailable), which
  // the player takes as WebKit's available video frame (the element's
  // readyState itself comes from the buffered ranges). Latched; only a stall
  // drops back to HAVE_NOTHING. Every enqueue, key change and readyForDisplay
  // change calls this; AVFoundation posts no KVO for its sufficiency
  // property, which turns true on the enqueue that fills the renderer's
  // preroll.
  void UpdateBuffering() {
    if (outgoing_layer_ && LayerHasFrame()) {
      RetireOutgoingLayer();
    }
    if (!renderers_have_samples_) {
      // WebKit's allRenderersHaveAvailableSamples over its per-track flags:
      // every renderer has had samples to play, or its stream is complete.
      // Latched per stream until Flush or StartPlayingFrom, so samples later
      // held for a key don't stop the clock (the picture freezes and time
      // runs on, as in Safari), and a stream added during playback waits for
      // its own samples only.
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
    // Nothing to have enough of while every stream is removed.
    if (!have_enough_ && (video_renderer_ || !audio_.empty())) {
      const double now = GetMediaTime().InSeconds();
      // The renderer's own sufficiency counts only while the stream still
      // has data ahead of the clock, so a stall isn't undone at its own point.
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

  // The clock runs at the requested rate once HAVE_ENOUGH and the renderers
  // have samples, as WebKit's synchronizer runs while shouldBePlaying().
  void UpdateClock() {
    if (video_reset_pending_ && VideoFrameAvailable()) {
      video_reset_pending_ = false;
    }
    const bool run = have_enough_ && renderers_have_samples_ && !video_reset_pending_;
    if (run != clock_held_) {
      return;
    }
    clock_held_ = !run;
    synchronizer_.rate = run ? status_.rate : 0;
  }

  // From the clock observer (every 0.1 s of media time while it runs).
  void CheckUnderflow() {
    if (status_.rate == 0) {
      return;
    }
    const double now = GetMediaTime().InSeconds();
    for (StreamId stream : Streams()) {
      PruneHeld(stream, now);
      if (!StreamFor(stream)->held.empty()) {
        NotifyNeedData(stream);  // The held window moved with the clock.
      }
    }
    ArmStall(now);
  }

  // Samples held for a key that the clock passed are never shown; drop them,
  // keeping video from the last keyframe at or before the clock, which
  // decoding resumes from once the key arrives.
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

  // Where the clock stalls, as WebKit's resetStallForTime places it: at the
  // end of what a stream that hasn't ended was given (its buffered end), and
  // nowhere else; a stream at end of stream ends there instead
  // (ScheduleEndIfComplete). Negative when nothing bounds the clock.
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

  // Arms a boundary observer at the stall time once the running clock is
  // near it, like WebKit's notifyTimeReachedAndStall, so it stops there
  // rather than up to a poll late.
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

  // The boundary was reached; data that arrived since moves the stall later.
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

  // Stops the clock at |stall| and reports HAVE_NOTHING; the clock is put
  // back to |stall| if the synchronizer ran past it, as WebKit's stall cap
  // masks that overshoot. UpdateBuffering resumes once data is back.
  void Stall(double stall) {
    RemoveStallObserver();
    have_enough_ = false;
    clock_held_ = true;
    // Never back before where playback started or seeked to.
    if (start_time_.IsValid()) {
      stall = std::max(stall, start_time_.InSeconds());
    }
    if (GetMediaTime().InSeconds() > stall) {
      [synchronizer_ setRate:0 time:ToCMTime(MediaTime::FromMicroseconds(int64_t(stall * 1e6)))];
    } else {
      synchronizer_.rate = 0;
    }
    // Posted like HAVE_ENOUGH (UpdateBuffering), so the two reach the client
    // in the order they happened.
    PostInGeneration([](Impl& impl) { impl.client_->OnBufferingStateChange(false); });
  }

  void RemoveStallObserver() {
    if (stall_observer_) {
      [synchronizer_ removeTimeObserver:stall_observer_];
      stall_observer_ = nil;
    }
    stall_time_ = -1;
  }

  // The clock ends at the last sample's end once every stream reached end of
  // stream, samples still held for a key or not: WebKit pauses and ends when
  // the clock reaches the duration, over a frozen picture if keys never came.
  void ScheduleEndIfComplete() {
    // An empty renderer (its last audio track removed) hasn't ended.
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
    // A renderer that must flush to resume decoding also reports Failed;
    // ResumeVideoDecoding recovers it, so it isn't a decode error.
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
  FairPlayCdm* pending_cdm_ = nullptr;  // Set before Initialize.
  bool cdm_detached_ = false;           // See DetachCdm.
  uint64_t observer_id_ = 0;

  std::optional<VideoConfig> video_config_;
  const std::shared_ptr<RequestGate> video_gate_ = std::make_shared<RequestGate>();
  ScopedFormat video_clear_format_;
  std::map<std::vector<uint8_t>, std::unique_ptr<ScopedFormat>> video_protected_formats_;
  NSString* output_device_uid_ = nil;  // The device the audio renderers play to.
  bool follows_default_output_ = false;
  AudioObjectPropertyListenerBlock audio_devices_listener_ = nil;
  float volume_ = 1;
  bool muted_ = false;
  uint64_t initialize_attempt_ = 0;  // Bumped by every Initialize call.
  // Cache key of the protected format last used (GetStatus reports it).
  std::vector<uint8_t> video_protected_key_;
  std::vector<id<AVContentKeyRecipient>> recipients_;

  AVSampleBufferRenderSynchronizer* synchronizer_ = nil;
  PCFairPlayVideoHost* host_ = nil;  // Created with the first video renderer.
  AVSampleBufferDisplayLayer* layer_ = nil;
  // Renderers replaced by ReplaceRenderers, until they leave.
  AVSampleBufferDisplayLayer* outgoing_layer_ = nil;
  id<AVQueuedSampleBufferRendering> outgoing_video_renderer_ = nil;
  std::map<uint32_t, std::vector<AVSampleBufferAudioRenderer*>> outgoing_audio_;
  // Outgoing renderers still recipients of the CDM they played with.
  std::vector<std::pair<FairPlayCdm*, id<AVContentKeyRecipient>>> outgoing_recipients_;
  // Audio renderers ReplaceRenderers replaced, until Replay schedules their
  // leaving, and where the audio of each track's latest outgoing one ends.
  std::vector<std::pair<uint32_t, AVSampleBufferAudioRenderer*>> leaving_audio_;
  std::map<uint32_t, double> audio_outgoing_end_;
  // The renderers joined a key session, which they can't join again.
  bool renderers_were_recipients_ = false;
  // Video samples replayed into the current layer, and the counts of the
  // layers it replaced (LoadVideoMetrics).
  uint64_t video_replayed_ = 0;
  VideoMetrics retired_video_metrics_;
  id<AVQueuedSampleBufferRendering> video_renderer_ = nil;
  // By track (StreamId::audio_track); Initialize's is 0.
  std::map<uint32_t, AudioTrack> audio_;
  uint32_t next_audio_track_ = 0;
  // HTMLMediaElement.preservesPitch, true by default.
  bool preserves_pitch_ = true;
  PCFairPlayRendererObserver* observer_ = nil;
  std::vector<std::pair<NSObject*, NSString*>> observed_;
  std::vector<std::pair<id, id>> notification_tokens_;  // Observed object, token.
  id end_observer_ = nil;
  id stall_observer_ = nil;  // See ArmStall.
  double stall_time_ = -1;
  id clock_observer_ = nil;

  Stream video_;
  MediaTime start_time_;
  bool waiting_reported_ = false;
  bool have_enough_ = false;
  // See UpdateBuffering.
  bool renderers_have_samples_ = false;
  // A start, seek or decoder reset waits for a decoded frame
  // (VideoFrameAvailable).
  bool video_reset_pending_ = false;
  bool legacy_video_frame_available_ = false;
  uint64_t video_frame_epoch_ = 0;
  // The clock waits for HAVE_ENOUGH and renderers with samples (start, seek
  // or stall).
  bool clock_held_ = true;
  bool awaiting_video_config_ = false;  // Record comes from the next keyframe.
  std::vector<std::vector<uint8_t>> parameter_sets_;  // Behind the current record.
  std::vector<uint8_t> av1_sequence_header_;
  int32_t natural_width_ = 0;   // The size of the samples queued last.
  int32_t natural_height_ = 0;
  int32_t reported_width_ = 0;  // The size last reported to the client.
  int32_t reported_height_ = 0;
  // A new size waits for its first sample to be queued, then for the clock
  // to reach it (one boundary observer per change, removed by Flush).
  bool size_change_pending_ = false;
  std::vector<id> size_observers_;
  uint64_t generation_ = 0;  // Bumped by Flush; stale posted tasks compare it.
  // generation_ for threads other than the owner's (notification blocks).
  const std::shared_ptr<std::atomic<uint64_t>> flush_count_ = std::make_shared<std::atomic<uint64_t>>(0);
  // Retained synchronizer timebase, read by GetMediaTime from any thread.
  std::atomic<CMTimebaseRef> timebase_{nullptr};
  bool ended_ = false;
  bool video_failure_reported_ = false;
  RendererStatus status_;
  // Presentation starts of the video samples given to AVFoundation (once
  // each; re-deliveries aren't counted again) that the clock hasn't reached,
  // earliest first; Flush drops them.
  std::priority_queue<double, std::vector<double>, std::greater<double>> video_due_;
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

@implementation PCFairPlayVideoHost

- (void)layoutSublayers {
  for (CALayer* sublayer in self.sublayers) {
    sublayer.frame = self.bounds;
  }
}

@end

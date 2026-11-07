// Installed by the reviewed overlay at
// //content/browser/media/parc_video_toolbox_decoding.mm.
#include "content/browser/media/parc_video_toolbox_decoding.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <dlfcn.h>

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/thread_pool.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"

namespace content {

namespace {

// AVVideoCodecTypeHEVCWithAlpha ("muxa"), which WebKit turns into a FourCC
// for VTSelectAndCreateVideoDecoderInstance when a configuration asks for an
// alpha channel.
constexpr CMVideoCodecType kHevcWithAlphaCodecType = 'muxa';

// VideoToolbox, opened the way WebKit soft-links it (VideoToolboxSoftLink.h):
// a symbol that isn't there reads as WebKit's canLoad_ failing. Several of
// these are SPI (pal/spi/cocoa/VideoToolboxSPI.h), so none is linked.
class VideoToolbox {
 public:
  VideoToolbox()
      : handle_(dlopen(
            "/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox",
            RTLD_LAZY | RTLD_LOCAL)) {}
  ~VideoToolbox() {
    if (handle_) {
      dlclose(handle_);
    }
  }
  VideoToolbox(const VideoToolbox&) = delete;
  VideoToolbox& operator=(const VideoToolbox&) = delete;

  void* Symbol(const char* name) const {
    return handle_ ? dlsym(handle_, name) : nullptr;
  }
  // A CFStringRef constant, or null.
  CFStringRef Key(const char* name) const {
    auto* key = static_cast<const CFStringRef*>(Symbol(name));
    return key ? *key : nullptr;
  }

 private:
  void* const handle_;
};

// WebKit's VTSelectAndCreateVideoDecoderInstance(codec, kCFAllocatorDefault,
// nullptr, nullptr) == noErr: a decoder for `codec` exists.
bool DecoderExists(const VideoToolbox& vt, CMVideoCodecType codec) {
  using SelectAndCreate =
      OSStatus (*)(CMVideoCodecType, CFAllocatorRef, CFDictionaryRef, void*);
  auto select = reinterpret_cast<SelectAndCreate>(
      vt.Symbol("VTSelectAndCreateVideoDecoderInstance"));
  return select &&
         select(codec, kCFAllocatorDefault, nullptr, nullptr) == noErr;
}

std::optional<int16_t> Int16Value(CFTypeRef value) {
  CFNumberRef number = base::apple::CFCast<CFNumberRef>(value);
  int16_t result = 0;
  if (!number || !CFNumberGetValue(number, kCFNumberSInt16Type, &result)) {
    return std::nullopt;
  }
  return result;
}

// HEVCUtilitiesCocoa.mm's validateHEVCParameters reads, per profile IDC in
// kVTHEVCDecoderCapability_SupportedProfiles, the entry under its decimal
// string in kVTHEVCDecoderCapability_PerProfileSupport. A profile that
// can't pass there (no entry, or a level that isn't an int16) is left out.
std::optional<std::vector<media::mojom::ParcHevcProfileSupportPtr>>
HevcProfiles(const VideoToolbox& vt, CFDictionaryRef capabilities) {
  const CFStringRef supported_key =
      vt.Key("kVTHEVCDecoderCapability_SupportedProfiles");
  const CFStringRef per_profile_key =
      vt.Key("kVTHEVCDecoderCapability_PerProfileSupport");
  const CFStringRef hardware_key =
      vt.Key("kVTHEVCDecoderProfileCapability_IsHardwareAccelerated");
  const CFStringRef max_decode_key =
      vt.Key("kVTHEVCDecoderProfileCapability_MaxDecodeLevel");
  const CFStringRef max_playback_key =
      vt.Key("kVTHEVCDecoderProfileCapability_MaxPlaybackLevel");
  if (!capabilities || !supported_key || !per_profile_key || !hardware_key ||
      !max_decode_key || !max_playback_key) {
    return std::nullopt;
  }
  CFArrayRef supported = base::apple::CFCast<CFArrayRef>(
      CFDictionaryGetValue(capabilities, supported_key));
  if (!supported) {
    return std::nullopt;
  }
  CFDictionaryRef per_profile = base::apple::CFCast<CFDictionaryRef>(
      CFDictionaryGetValue(capabilities, per_profile_key));
  std::vector<media::mojom::ParcHevcProfileSupportPtr> profiles;
  if (!per_profile) {
    return profiles;  // Every profile fails WebKit's lookup.
  }
  for (CFIndex i = 0; i < CFArrayGetCount(supported); ++i) {
    const std::optional<int16_t> idc =
        Int16Value(CFArrayGetValueAtIndex(supported, i));
    if (!idc) {
      continue;
    }
    const base::apple::ScopedCFTypeRef<CFStringRef> name =
        base::SysUTF8ToCFStringRef(base::NumberToString(int{*idc}));
    CFDictionaryRef support = base::apple::CFCast<CFDictionaryRef>(
        CFDictionaryGetValue(per_profile, name.get()));
    if (!support) {
      continue;
    }
    auto profile = media::mojom::ParcHevcProfileSupport::New();
    profile->profile_idc = *idc;
    profile->hardware_accelerated =
        CFDictionaryGetValue(support, hardware_key) == kCFBooleanTrue;
    if (CFTypeRef level = CFDictionaryGetValue(support, max_decode_key)) {
      const std::optional<int16_t> value = Int16Value(level);
      if (!value) {
        continue;
      }
      profile->has_max_decode_level = true;
      profile->max_decode_level = *value;
    }
    if (CFTypeRef level = CFDictionaryGetValue(support, max_playback_key)) {
      const std::optional<int16_t> value = Int16Value(level);
      if (!value) {
        continue;
      }
      profile->has_max_playback_level = true;
      profile->max_playback_level = *value;
    }
    profiles.push_back(std::move(profile));
  }
  return profiles;
}

// validateDoViParameters's parseStringArrayFromDictionaryToUInt16Vector: an
// array of decimal strings, all of which must parse.
std::optional<std::vector<uint16_t>> UInt16Strings(CFTypeRef value) {
  CFArrayRef array = base::apple::CFCast<CFArrayRef>(value);
  if (!array) {
    return std::nullopt;
  }
  std::vector<uint16_t> result;
  for (CFIndex i = 0; i < CFArrayGetCount(array); ++i) {
    CFStringRef string =
        base::apple::CFCast<CFStringRef>(CFArrayGetValueAtIndex(array, i));
    unsigned parsed = 0;
    if (!string ||
        !base::StringToUint(base::SysCFStringRefToUTF8(string), &parsed) ||
        parsed > 0xffff) {
      return std::nullopt;
    }
    result.push_back(static_cast<uint16_t>(parsed));
  }
  return result;
}

media::mojom::ParcVideoToolboxDecodingFactsPtr ReadFacts() {
  auto facts = media::mojom::ParcVideoToolboxDecodingFacts::New();
  const VideoToolbox vt;

  using IsHardwareDecodeSupported = Boolean (*)(CMVideoCodecType);
  auto is_hardware = reinterpret_cast<IsHardwareDecodeSupported>(
      vt.Symbol("VTIsHardwareDecodeSupported"));
  facts->hardware_decode_query = is_hardware != nullptr;
  facts->h264_hardware = is_hardware && is_hardware(kCMVideoCodecType_H264);

  facts->h264_decoder = DecoderExists(vt, kCMVideoCodecType_H264);
  facts->hevc_decoder = DecoderExists(vt, kCMVideoCodecType_HEVC);
  facts->hevc_with_alpha_decoder = DecoderExists(vt, kHevcWithAlphaCodecType);

  using CopyCapabilities = CFDictionaryRef (*)();
  auto copy_capabilities = reinterpret_cast<CopyCapabilities>(
      vt.Symbol("VTCopyHEVCDecoderCapabilitiesDictionary"));
  base::apple::ScopedCFTypeRef<CFDictionaryRef> capabilities(
      copy_capabilities ? copy_capabilities() : nullptr);
  facts->hevc_profiles = HevcProfiles(vt, capabilities.get());

  const CFStringRef dv_profiles_key =
      vt.Key("kVTDolbyVisionDecoderCapability_SupportedProfiles");
  const CFStringRef dv_levels_key =
      vt.Key("kVTDolbyVisionDecoderCapability_SupportedLevels");
  const CFStringRef dv_hardware_key =
      vt.Key("kVTDolbyVisionDecoderCapability_IsHardwareAccelerated");
  if (capabilities && dv_profiles_key && dv_levels_key && dv_hardware_key) {
    std::optional<std::vector<uint16_t>> dv_profiles = UInt16Strings(
        CFDictionaryGetValue(capabilities.get(), dv_profiles_key));
    std::optional<std::vector<uint16_t>> dv_levels = UInt16Strings(
        CFDictionaryGetValue(capabilities.get(), dv_levels_key));
    if (dv_profiles && dv_levels) {
      facts->dolby_vision_profiles = std::move(*dv_profiles);
      facts->dolby_vision_levels = std::move(*dv_levels);
      facts->dolby_vision_hardware =
          CFDictionaryGetValue(capabilities.get(), dv_hardware_key) ==
          kCFBooleanTrue;
    }
  }
  return facts;
}

// Read once per browser process; the decoders a Mac has don't change while
// it runs.
media::mojom::ParcVideoToolboxDecodingFactsPtr CachedFacts() {
  static const base::NoDestructor<media::mojom::ParcVideoToolboxDecodingFactsPtr>
      facts(ReadFacts());
  return (*facts)->Clone();
}

// AudioToolbox's SpatialAudioPreferences, laid out as WebKit declares it
// (pal/spi/cocoa/AudioToolboxSPI.h).
struct SpatialAudioPreferences {
  Boolean prefers_head_tracked_spatialization;
  Boolean prefers_lossy_audio_sources;
  Boolean always_spatialize;
  Boolean pad[5];
  UInt32 max_spatializable_channels;
  UInt32 spatial_audio_source_count;
  UInt32 spatial_audio_sources[3];
};

// WebKit's SpatialAudioPlaybackHelperMac: the default output device's spatial
// audio preferences for audiovisual ('moov') or audio-only ('soun') content,
// through AudioGetDeviceSpatialPreferencesForContentType (SPI, soft-linked
// there, so looked up here). Empty when it is missing, fails or names none.
std::vector<uint32_t> ReadSpatialAudioSources(bool audiovisual) {
  constexpr UInt32 kAudiovisual = 0x6d6f6f76;  // 'moov'
  constexpr UInt32 kAudioOnly = 0x736f756e;    // 'soun'
  std::vector<uint32_t> sources;
  void* const audio_toolbox = dlopen(
      "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",
      RTLD_LAZY | RTLD_LOCAL);
  if (!audio_toolbox) {
    return sources;
  }
  using GetPreferences =
      OSStatus (*)(CFStringRef, UInt32, SpatialAudioPreferences*);
  auto get_preferences = reinterpret_cast<GetPreferences>(
      dlsym(audio_toolbox, "AudioGetDeviceSpatialPreferencesForContentType"));
  SpatialAudioPreferences preferences = {};
  if (get_preferences &&
      get_preferences(nullptr, audiovisual ? kAudiovisual : kAudioOnly,
                      &preferences) == noErr) {
    const UInt32 count =
        std::min<UInt32>(preferences.spatial_audio_source_count, 3);
    for (UInt32 i = 0; i < count; ++i) {
      sources.push_back(preferences.spatial_audio_sources[i]);
    }
  }
  dlclose(audio_toolbox);
  return sources;
}

class ParcVideoToolboxDecodingImpl
    : public media::mojom::ParcVideoToolboxDecoding {
 public:
  void GetFacts(GetFactsCallback callback) override {
    base::ThreadPool::PostTaskAndReplyWithResult(
        FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&CachedFacts), std::move(callback));
  }

  // Read at every call: the preferences follow the output device.
  void GetSpatialAudioSources(bool audiovisual,
                              GetSpatialAudioSourcesCallback callback) override {
    base::ThreadPool::PostTaskAndReplyWithResult(
        FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&ReadSpatialAudioSources, audiovisual),
        std::move(callback));
  }
};

}  // namespace

void BindParcVideoToolboxDecoding(
    mojo::PendingReceiver<media::mojom::ParcVideoToolboxDecoding> receiver) {
  mojo::MakeSelfOwnedReceiver(std::make_unique<ParcVideoToolboxDecodingImpl>(),
                              std::move(receiver));
}

}  // namespace content

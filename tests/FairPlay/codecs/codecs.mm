// FairPlay protected-codec proof. No public FairPlay content exists for
// Dolby Vision, AV1, HE-AAC, xHE-AAC, AC-3 or E-AC-3, so this program makes
// its own: it encrypts clear samples in memory with a content key that
// Axinom's FairPlay license service licenses, then plays them through
// FairPlayCdm and FairPlayRenderer the way Chromium hands them over.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <OSLog/OSLog.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "fairplay_bitstream.h"
#include "fairplay_init_data.h"
#include "fairplay_key_session.h"
#include "fairplay_renderer.h"
#include "fmp4_parser.h"
#include "sample_encryptor.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

namespace fp = parc::fairplay;
namespace ft = parc::fairplay::test;

namespace {

// Axinom public test vectors v10, "CMAF H264 SingleKey (cbcs)", the vector the
// core harness licenses (tests/FairPlay/harness.mm). Axinom publishes its
// content key next to the key ID and the X-AxDRM-Message entitlement token in
// https://github.com/Axinom/public-test-vectors/blob/master/ContentKeys/Axinom-Encoding-Cmaf-H264-protected-SingleKey.txt
// so Axinom's FairPlay service licenses a key this program can encrypt with.
// The token's inline key carries the FairPlay IV the service requires.
NSString* const kLicenseUrl = @"https://drm-fairplay-licensing.axprod.net/AcquireLicense";
NSString* const kCertificateUrl = @"https://tools.axinom.com/FPScert/fairplay.cer";
const char* const kKeyIdHex = "302f80dd411e4886bca5bb1f8018a024";
const char* const kKeyBase64 = "FbKq+Qbr7GMJ1A+RKJEnuA==";
NSString* const kToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjMwMmY4MGRkLTQxMWUtNDg4Ni1iY2E1LWJiMWY4MDE4YTAyNCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiMWVYeWhGWmNGVjljemNtZG5BREpMdz09IiwKICAgICAgICAiaXYiOiAiZC8wWWlhcjBGRHNJVlVpendQbGJtZz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.5VxBJQsgGVissi9WCNpT7IoykEAmxaEcif6F3SeLvzU";

// Chromium's media/test/data at the pinned tag. Its encrypted files use the
// test key in that directory's README ("[1] Test key ID", "[2] Test key").
NSString* const kChromiumTestData =
    @"https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/media/test/data/";
const char* const kChromiumKeyHex = "ebdd62f16814d27b68ef122afce4ae3c";

// ---------------------------------------------------------------- reporting

double g_start = 0;
int g_checks = 0;
int g_failures = 0;
std::vector<std::string> g_failed;

double Now() { return CFAbsoluteTimeGetCurrent() - g_start; }

void Log(const char* format, ...) __attribute__((format(printf, 1, 2)));
void Log(const char* format, ...) {
  char buffer[4096];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  printf("[%8.3f] %s\n", Now(), buffer);
  fflush(stdout);
}

bool Check(bool ok, const std::string& name, const std::string& detail = "") {
  ++g_checks;
  if (!ok) {
    ++g_failures;
    g_failed.push_back(name);
  }
  Log("%s %s%s%s", ok ? "PASS" : "FAIL", name.c_str(), detail.empty() ? "" : " -- ", detail.c_str());
  return ok;
}

std::string Format(const char* format, ...) __attribute__((format(printf, 1, 2)));
std::string Format(const char* format, ...) {
  char buffer[2048];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  return buffer;
}

std::vector<uint8_t> Bytes(NSData* data) {
  const uint8_t* p = static_cast<const uint8_t*>(data.bytes);
  return std::vector<uint8_t>(p, p + data.length);
}


NSData* Data(const std::vector<uint8_t>& v) { return [NSData dataWithBytes:v.data() length:v.size()]; }

std::vector<uint8_t> FromHex(const char* hex) {
  std::vector<uint8_t> out;
  for (size_t i = 0; hex[i] && hex[i + 1]; i += 2) {
    out.push_back(uint8_t(std::stoi(std::string(hex + i, 2), nullptr, 16)));
  }
  return out;
}

const char* StatusName(fp::RenderingStatus s) {
  switch (s) {
    case fp::RenderingStatus::kUnknown: return "unknown";
    case fp::RenderingStatus::kRendering: return "rendering";
    case fp::RenderingStatus::kFailed: return "failed";
  }
  return "?";
}

// --------------------------------------------------------------------- HTTP

struct Http {
  long status = 0;
  NSData* body = nil;
  NSDictionary* headers = nil;
  std::string error;
};

// Blocking, with a 60 s request timeout; called off the main thread only.
Http Fetch(NSString* url, NSString* method, NSData* body, NSDictionary* headers) {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  request.HTTPMethod = method;
  request.HTTPBody = body;
  request.timeoutInterval = 60;
  for (NSString* key in headers) [request setValue:headers[key] forHTTPHeaderField:key];
  __block Http result;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[[NSURLSession sharedSession]
      dataTaskWithRequest:request
        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
          NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
          result.status = http.statusCode;
          result.body = data;
          result.headers = http.allHeaderFields;
          if (error) result.error = error.localizedDescription.UTF8String;
          dispatch_semaphore_signal(done);
        }] resume];
  dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC));
  return result;
}

NSString* g_cache_dir = nil;

NSData* CachedGet(NSString* url, NSString* name, bool base64, std::string* error) {
  NSString* path = [g_cache_dir stringByAppendingPathComponent:name];
  if (NSData* cached = [NSData dataWithContentsOfFile:path]) return cached;
  Http http = Fetch(url, @"GET", nil, @{});
  NSData* data = http.status == 200 ? http.body : nil;
  if (data && base64) {
    data = [[NSData alloc] initWithBase64EncodedData:data options:NSDataBase64DecodingIgnoreUnknownCharacters];
  }
  if (!data.length) {
    *error = Format("GET %s -> %ld %s", url.UTF8String, http.status, http.error.c_str());
    return nil;
  }
  [data writeToFile:path atomically:YES];
  return data;
}


void Finish();

// One byte range of a static file (a CMAF segment of an HLS playlist).
NSData* CachedRange(NSString* url, NSString* name, uint64_t offset, uint64_t length, std::string* error) {
  NSString* path = [g_cache_dir stringByAppendingPathComponent:name];
  if (NSData* cached = [NSData dataWithContentsOfFile:path]) return cached;
  Http http = Fetch(url, @"GET", nil,
                    @{@"Range" : [NSString stringWithFormat:@"bytes=%llu-%llu", offset, offset + length - 1]});
  if (http.status != 206 || http.body.length != length) {
    *error = Format("GET %s range %llu+%llu -> %ld, %lu bytes %s", url.UTF8String, offset, length, http.status,
                    (unsigned long)http.body.length, http.error.c_str());
    return nil;
  }
  [http.body writeToFile:path atomically:YES];
  return http.body;
}

// ------------------------------------------------------------ media loading

struct Media {
  ft::TrackInfo info;
  std::vector<ft::Sample> samples;
};

bool ParseFile(NSData* data, const std::string& name, Media* media, std::string* error) {
  if (!ft::ParseInitSegment(Bytes(data), &media->info, error) ||
      !ft::ParseMediaSegment(Bytes(data), media->info, &media->samples, error) ||
      (media->samples.empty() && !ft::ParseProgressiveFile(Bytes(data), media->info, &media->samples, error))) {
    *error = name + ": " + *error;
    return false;
  }
  return true;
}

// One fragmented (or progressive) MP4 from Chromium's media/test/data; the
// cache name matches the core harness's so both share downloads.
bool LoadChromiumFile(NSString* name, Media* media, std::string* error) {
  NSData* data = CachedGet([NSString stringWithFormat:@"%@%@?format=TEXT", kChromiumTestData, name],
                           [@"chromium_" stringByAppendingString:name], true, error);
  return data && ParseFile(data, name.UTF8String, media, error);
}

struct EncodeState {
  double phase_l = 0;
  double phase_r = 0;
  int64_t remaining = 0;
  std::vector<float> buffer;
};

OSStatus ProvidePcm(AudioConverterRef, UInt32* packets, AudioBufferList* data, AudioStreamPacketDescription**,
                    void* user) {
  auto* state = static_cast<EncodeState*>(user);
  UInt32 frames = std::min<UInt32>(*packets, UInt32(std::min<int64_t>(state->remaining, 4096)));
  state->buffer.resize(size_t(frames) * 2);
  for (UInt32 i = 0; i < frames; ++i) {
    state->buffer[2 * i] = float(0.3 * std::sin(state->phase_l));
    state->buffer[2 * i + 1] = float(0.3 * std::sin(state->phase_r));
    state->phase_l += 2 * M_PI * 440 / 44100;
    state->phase_r += 2 * M_PI * 660 / 44100;
  }
  state->remaining -= frames;
  *packets = frames;
  data->mBuffers[0].mData = state->buffer.data();
  data->mBuffers[0].mDataByteSize = frames * 8;
  data->mBuffers[0].mNumberChannels = 2;
  return noErr;
}

// AAC-LC, HE-AAC and HE-AACv2 tracks encoded with AudioToolbox (Chromium's
// test data has no HE-AAC MP4): 44.1 kHz stereo tones, packets and the
// encoder's AudioSpecificConfig, as an MP4 parser would hand them over.
// AAC from Apple's encoder, or ALAC (kAudioFormatAppleLossless) as Apple's
// 'alac' sample entry carries it.
bool EncodeAac(AudioFormatID format, double seconds, Media* media, std::string* error) {
  const bool alac = format == kAudioFormatAppleLossless;
  AudioStreamBasicDescription in = {44100, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                    8,     1,
                                    8,     2,
                                    32,    0};
  AudioStreamBasicDescription out = {};
  out.mFormatID = format;
  out.mSampleRate = 44100;
  out.mChannelsPerFrame = 2;
  if (alac) {
    out.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData;
    out.mFramesPerPacket = 4096;
  }
  UInt32 size = sizeof(out);
  AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nullptr, &size, &out);
  AudioConverterRef converter = nullptr;
  OSStatus status = AudioConverterNew(&in, &out, &converter);
  if (status != noErr) {
    *error = Format("AudioConverterNew %d", int(status));
    return false;
  }
  size = sizeof(out);
  AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &out);
  UInt32 max_packet = 0;
  size = sizeof(max_packet);
  AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &max_packet);
  EncodeState state;
  state.remaining = int64_t(seconds * 44100);
  std::vector<uint8_t> buffer(size_t(max_packet) * 16);
  std::vector<AudioStreamPacketDescription> descriptions(16);
  int64_t pts = 0;
  for (;;) {
    UInt32 packets = 16;
    AudioBufferList list = {1, {{2, UInt32(buffer.size()), buffer.data()}}};
    status = AudioConverterFillComplexBuffer(converter, ProvidePcm, &state, &packets, &list, descriptions.data());
    if (status != noErr || packets == 0) break;
    for (UInt32 i = 0; i < packets; ++i) {
      const AudioStreamPacketDescription& d = descriptions[i];
      ft::Sample sample;
      sample.data.assign(buffer.begin() + d.mStartOffset, buffer.begin() + d.mStartOffset + d.mDataByteSize);
      sample.pts = sample.dts = pts;
      // ALAC's last packet holds only the frames left (its header says so).
      const int64_t frames = alac ? std::min<int64_t>(out.mFramesPerPacket, int64_t(seconds * 44100) - pts)
                                  : int64_t(out.mFramesPerPacket);
      sample.duration = frames;
      sample.is_keyframe = true;
      pts += frames;
      media->samples.push_back(std::move(sample));
    }
  }
  UInt32 cookie_size = 0;
  AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookie_size, nullptr);
  std::vector<uint8_t> cookie(cookie_size);
  AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookie_size, cookie.data());
  AudioConverterDispose(converter);
  media->info.is_video = false;
  media->info.timescale = uint32_t(out.mSampleRate);
  media->info.sample_entry = media->info.original_format =
      alac ? fp::FourCC('a', 'l', 'a', 'c') : fp::FourCC('m', 'p', '4', 'a');
  media->info.channels = 2;
  media->info.sample_rate = uint32_t(out.mSampleRate);
  if (alac) {
    // The 'alac' child box's payload, as the parser keeps it from a file.
    media->info.codec_config = fp::AlacSpecificBoxPayload(cookie).value_or(std::vector<uint8_t>());
  } else {
    media->info.codec_config = ft::AscFromDescriptor(cookie.data(), cookie.size());
  }
  if (media->info.codec_config.empty() || media->samples.empty()) {
    *error = Format("encoder produced %zu packets, %zu-byte cookie", media->samples.size(), cookie.size());
    return false;
  }
  return true;
}

// ISO 23003-5 PCM as Chromium's MP4 parser hands it over: 'ipcm' (16, 24 or
// 32-bit integer) or 'fpcm' (32-bit float), little-endian interleaved 44.1 kHz
// stereo tones in 1024-frame samples, the 'pcmC' payload as the config.
void MakePcm(bool floating, int bits, double seconds, Media* media) {
  const int64_t total = int64_t(seconds * 44100);
  for (int64_t pts = 0; pts < total; pts += 1024) {
    const int64_t frames = std::min<int64_t>(1024, total - pts);
    ft::Sample sample;
    for (int64_t i = pts; i < pts + frames; ++i) {
      for (double hz : {440.0, 660.0}) {
        const double value = 0.3 * std::sin(2 * M_PI * hz * double(i) / 44100);
        uint32_t word;
        if (floating) {
          const float f = float(value);
          memcpy(&word, &f, 4);
        } else {
          word = uint32_t(int32_t(std::lround(value * double((int64_t(1) << (bits - 1)) - 1))));
        }
        for (int byte = 0; byte < bits / 8; ++byte) sample.data.push_back(uint8_t(word >> (8 * byte)));
      }
    }
    sample.pts = sample.dts = pts;
    sample.duration = frames;
    sample.is_keyframe = true;
    media->samples.push_back(std::move(sample));
  }
  media->info.is_video = false;
  media->info.timescale = 44100;
  media->info.sample_entry = media->info.original_format =
      floating ? fp::FourCC('f', 'p', 'c', 'm') : fp::FourCC('i', 'p', 'c', 'm');
  media->info.channels = 2;
  media->info.sample_rate = 44100;
  media->info.codec_config = {0, 0, 0, 0, 1, uint8_t(bits)};
}

double EndSeconds(const Media& media) {
  double end = 0;
  for (const ft::Sample& s : media.samples) end = std::max(end, double(s.pts + s.duration) / media.info.timescale);
  return end;
}

// Channel count Chromium's MP4 parser reports for AC-3/E-AC-3 (from the
// dac3/dec3 box: acmod, lfeon and, for E-AC-3, the dependent substreams'
// chan_loc). The sample entry's channelcount is often just 2.
int DolbyChannels(const ft::TrackInfo& info) {
  static const int kAcmodChannels[8] = {2, 1, 2, 3, 3, 4, 4, 5};
  const std::vector<uint8_t>& c = info.codec_config;
  if (info.original_format == fp::FourCC('a', 'c', '-', '3') && c.size() >= 3) {
    return kAcmodChannels[(c[1] >> 3) & 7] + ((c[1] >> 2) & 1);
  }
  if (info.original_format == fp::FourCC('e', 'c', '-', '3') && c.size() >= 5) {
    const int acmod = (c[3] >> 1) & 7, lfeon = c[3] & 1, dependents = (c[4] >> 1) & 15;
    int channels = kAcmodChannels[acmod] + lfeon;
    if (dependents && c.size() >= 6) {
      const int chan_loc = ((c[4] & 1) << 8) | c[5];
      static const int kLocationChannels[9] = {2, 2, 1, 1, 2, 2, 2, 1, 1};  // Lc/Rc, Lrs/Rrs, Cs, Ts, ...
      for (int bit = 0; bit < 9; ++bit) channels += (chan_loc >> bit) & 1 ? kLocationChannels[bit] : 0;
    }
    return channels;
  }
  return info.channels;
}

// Decrypts a Chromium test file (encrypted with its README's test key) into
// clear samples, keeping each sample's subsample layout as the packager made
// it.
bool DecryptReference(const Media& encrypted, const std::vector<uint8_t>& key, Media* clear,
                      std::vector<std::vector<fp::SubsampleEntry>>* layouts, std::string* error) {
  *clear = encrypted;
  clear->info.sample_entry = clear->info.original_format;
  clear->info.encryption = {};
  clear->info.scheme_type = 0;
  layouts->clear();
  for (ft::Sample& sample : clear->samples) {
    if (!sample.decrypt) {
      *error = "a reference sample is clear";
      return false;
    }
    std::vector<uint8_t> iv =
        sample.decrypt->iv.empty() ? encrypted.info.encryption.default_constant_iv : sample.decrypt->iv;
    fp::EncryptionPattern pattern = sample.decrypt->pattern.value_or(encrypted.info.encryption.default_pattern);
    if (!ft::CencCrypt(false, sample.decrypt->scheme, key, iv, pattern, sample.decrypt->subsamples, &sample.data,
                       error)) {
      return false;
    }
    layouts->push_back(sample.decrypt->subsamples);
    sample.decrypt.reset();
  }
  return true;
}

bool SameSamples(const Media& a, const Media& b) {
  if (a.samples.size() != b.samples.size()) return false;
  for (size_t i = 0; i < a.samples.size(); ++i) {
    if (a.samples[i].data != b.samples[i].data) return false;
  }
  return true;
}

bool SameLayout(const std::vector<fp::SubsampleEntry>& a, const std::vector<fp::SubsampleEntry>& b) {
  if (a.size() != b.size()) return false;
  for (size_t i = 0; i < a.size(); ++i) {
    if (a[i].clear_bytes != b[i].clear_bytes || a[i].cypher_bytes != b[i].cypher_bytes) return false;
  }
  return true;
}

std::string LayoutText(const std::vector<fp::SubsampleEntry>& layout) {
  std::string text;
  for (const fp::SubsampleEntry& e : layout) text += Format("%s%u/%u", text.empty() ? "" : " ", e.clear_bytes, e.cypher_bytes);
  return text.empty() ? "whole sample" : text;
}

// ---------------------------------------------------------------- protection

// How samples are split into clear and protected bytes.
enum class Layout {
  kNal,               // H.264/HEVC/Dolby Vision: slice data protected (NalLayout).
  kReference,         // AV1: the layout Shaka Packager gave the same stream.
  kAv1ObuPayloads,    // AV1 probe: every frame, frame header and tile group OBU
                      // protected after its header and size field (frame
                      // headers included, which a packager never does).
  kWholeSample,       // Audio, CMAF style: the whole sample is protected.
  kSyncframeHeaders,  // AC-3/E-AC-3: each syncframe's first 16 bytes clear.
};

// IVs. FairPlay's CKC carries an IV with the key, and Axinom's service
// requires one in the entitlement token ("iv" of the token's inline key:
// d/0Yiar0FDsIVUizwPlbmg==, the constant IV Axinom's own content uses).
// kOtherIv is an IV the license doesn't carry.
const uint8_t kLicenseIv[16] = {0x77, 0xfd, 0x18, 0x89, 0xaa, 0xf4, 0x14, 0x3b,
                                0x08, 0x55, 0x48, 0xb3, 0xc0, 0xf9, 0x5b, 0x9a};
const uint8_t kOtherIv[16] = {'p', 'a', 'r', 'c', '-', 'f', 'a', 'i', 'r', 'p', 'l', 'a', 'y', '-', 'i', 'v'};
const uint8_t kCencIvBase[8] = {0x70, 0x61, 0x72, 0x63, 0x00, 0x00, 0x00, 0x00};

enum class IvMode {
  kLicense,    // cbcs: the license's IV as the tenc constant IV. cenc: the
               // license's IV as every sample's 16-byte IV.
  kOther,      // cbcs only: a constant IV the license doesn't carry.
  kPerSample,  // cenc only: 8-byte IVs counting up per sample, as packagers write.
};

std::vector<fp::SubsampleEntry> SyncframeLayout(const std::vector<uint8_t>& data, bool eac3) {
  std::vector<fp::SubsampleEntry> out;
  size_t pos = 0;
  while (pos + 16 <= data.size() && data[pos] == 0x0b && data[pos + 1] == 0x77) {
    size_t size = eac3 ? ((size_t((data[pos + 2] & 7) << 8) | data[pos + 3]) + 1) * 2 : data.size() - pos;
    if (pos + size > data.size() || size < 16) break;
    out.push_back({16, uint32_t(size - 16)});
    pos += size;
  }
  if (pos != data.size()) out.clear();  // Not syncframe-aligned: fall back to the whole sample.
  return out;
}

// Low-overhead AV1 OBUs (each with obu_has_size_field): header and size field
// clear, payload protected for frame (6), frame header (3) and tile group (4)
// OBUs, everything else clear.
bool Av1ObuPayloadLayout(const std::vector<uint8_t>& data, std::vector<fp::SubsampleEntry>* out) {
  out->clear();
  uint32_t pending_clear = 0;
  for (size_t pos = 0; pos < data.size();) {
    const uint8_t header = data[pos];
    const int type = (header >> 3) & 15;
    size_t q = pos + 1 + ((header & 4) ? 1 : 0);
    if (!(header & 2)) return false;
    uint64_t size = 0;
    for (int shift = 0;; shift += 7) {
      if (q >= data.size() || shift > 56) return false;
      const uint8_t b = data[q++];
      size |= uint64_t(b & 0x7f) << shift;
      if (!(b & 0x80)) break;
    }
    if (q + size > data.size()) return false;
    if ((type == 3 || type == 4 || type == 6) && size > 0) {
      out->push_back({pending_clear + uint32_t(q - pos), uint32_t(size)});
      pending_clear = 0;
    } else {
      pending_clear += uint32_t(q - pos + size);
    }
    pos = q + size;
  }
  if (pending_clear) out->push_back({pending_clear, 0});
  return true;
}

struct ProtectOptions {
  fp::EncryptionScheme scheme = fp::EncryptionScheme::kCbcs;
  Layout layout = Layout::kNal;
  IvMode iv = IvMode::kLicense;
  const std::vector<std::vector<fp::SubsampleEntry>>* reference = nullptr;  // kReference.
  std::optional<fp::EncryptionPattern> pattern;  // Instead of CMAF's.
};

ProtectOptions Options(fp::EncryptionScheme scheme, Layout layout, IvMode iv,
                       const std::vector<std::vector<fp::SubsampleEntry>>* reference) {
  ProtectOptions options;
  options.scheme = scheme;
  options.layout = layout;
  options.iv = iv;
  options.reference = reference;
  return options;
}

struct ProtectionStats {
  size_t samples = 0;
  size_t protected_samples = 0;  // With at least one complete encrypted block.
  size_t bytes = 0;
  size_t cypher_bytes = 0;
  size_t changed_bytes = 0;
  bool round_trip = true;
};

// Encrypts every sample of |clear| with |key| under |key_id| and gives each
// the DecryptConfig Chromium's MP4 parser would build from the resulting
// senc/tenc: key ID, per-sample IV (cenc) or none with the tenc constant IV
// (cbcs), subsamples and the cbcs pattern.
bool Protect(const Media& clear, const ProtectOptions& options, const std::vector<uint8_t>& key,
             const std::vector<uint8_t>& key_id, Media* out, ProtectionStats* stats, std::string* error) {
  const bool video = clear.info.is_video;
  const bool cbcs = options.scheme == fp::EncryptionScheme::kCbcs;
  if ((cbcs && options.iv == IvMode::kPerSample) || (!cbcs && options.iv == IvMode::kOther)) {
    *error = "IV mode doesn't fit the scheme";
    return false;
  }
  *out = clear;
  out->info.sample_entry = video ? fp::FourCC('e', 'n', 'c', 'v') : fp::FourCC('e', 'n', 'c', 'a');
  out->info.scheme_type = cbcs ? fp::FourCC('c', 'b', 'c', 's') : fp::FourCC('c', 'e', 'n', 'c');
  out->info.encryption.scheme = options.scheme;
  out->info.encryption.default_key_id = key_id;
  // CMAF: 1:9 pattern for video, whole blocks for audio.
  out->info.encryption.default_pattern =
      options.pattern ? *options.pattern : cbcs && video ? fp::EncryptionPattern{1, 9} : fp::EncryptionPattern{0, 0};
  const std::vector<uint8_t> license_iv(kLicenseIv, kLicenseIv + 16), other_iv(kOtherIv, kOtherIv + 16);
  out->info.encryption.default_per_sample_iv_size = cbcs ? 0 : options.iv == IvMode::kPerSample ? 8 : 16;
  out->info.encryption.default_constant_iv =
      cbcs ? (options.iv == IvMode::kLicense ? license_iv : other_iv) : std::vector<uint8_t>();
  std::unique_ptr<ft::NalLayout> nal;
  if (options.layout == Layout::kNal) {
    const uint32_t f = clear.info.original_format;
    const bool avc = f == fp::FourCC('a', 'v', 'c', '1') || f == fp::FourCC('a', 'v', 'c', '3');
    nal = std::make_unique<ft::NalLayout>(avc ? ft::NalCodec::kH264 : ft::NalCodec::kHevc, clear.info.codec_config);
    if (!nal->ok()) {
      *error = nal->error();
      return false;
    }
  }
  if (options.layout == Layout::kReference &&
      (!options.reference || options.reference->size() != clear.samples.size())) {
    *error = "no reference layout for every sample";
    return false;
  }
  *stats = {};
  for (size_t i = 0; i < out->samples.size(); ++i) {
    ft::Sample& sample = out->samples[i];
    fp::DecryptInfo info;
    info.scheme = options.scheme;
    info.key_id = key_id;
    switch (options.layout) {
      case Layout::kNal:
        if (!nal->Subsamples(sample.data, options.scheme, &info.subsamples, error)) {
          *error = Format("sample %zu: ", i) + *error;
          return false;
        }
        break;
      case Layout::kReference:
        info.subsamples = (*options.reference)[i];
        break;
      case Layout::kAv1ObuPayloads:
        if (!Av1ObuPayloadLayout(sample.data, &info.subsamples)) {
          *error = Format("sample %zu: unparsable OBUs", i);
          return false;
        }
        break;
      case Layout::kWholeSample:
        break;
      case Layout::kSyncframeHeaders:
        info.subsamples = SyncframeLayout(sample.data, clear.info.original_format == fp::FourCC('e', 'c', '-', '3'));
        break;
    }
    std::vector<uint8_t> iv;
    if (cbcs) {
      info.pattern = out->info.encryption.default_pattern;
      iv = out->info.encryption.default_constant_iv;
    } else if (options.iv == IvMode::kPerSample) {
      info.iv.assign(kCencIvBase, kCencIvBase + 8);
      for (int k = 0; k < 4; ++k) info.iv[7 - k] = uint8_t(i >> (8 * k));
      iv = info.iv;
    } else {
      info.iv = license_iv;
      iv = info.iv;
    }
    const std::vector<uint8_t> original = sample.data;
    if (!ft::CencCrypt(true, options.scheme, key, iv, info.pattern.value_or(fp::EncryptionPattern{}),
                       info.subsamples, &sample.data, error)) {
      *error = Format("sample %zu: ", i) + *error;
      return false;
    }
    std::vector<uint8_t> back = sample.data;
    std::string ignored;
    ft::CencCrypt(false, options.scheme, key, iv, info.pattern.value_or(fp::EncryptionPattern{}), info.subsamples,
                  &back, &ignored);
    stats->round_trip &= back == original;
    ++stats->samples;
    stats->bytes += sample.data.size();
    size_t cypher = 0;
    bool full_block = false;
    if (info.subsamples.empty()) {
      cypher = sample.data.size();
      full_block = cypher >= 16;
    }
    for (const fp::SubsampleEntry& e : info.subsamples) {
      cypher += e.cypher_bytes;
      full_block |= e.cypher_bytes >= 16;
    }
    stats->cypher_bytes += cypher;
    stats->protected_samples += full_block;
    for (size_t k = 0; k < original.size(); ++k) stats->changed_bytes += original[k] != sample.data[k];
    // Stored as the senc would hold it: cbcs carries no per-sample IV.
    if (cbcs) info.iv.clear();
    sample.decrypt = info;
  }
  return true;
}

// ------------------------------------------------------------- async steps

using Done = std::function<void()>;
using Step = std::function<void(Done)>;

void After(double seconds, Done done) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    done();
  });
}

void RunSteps(std::shared_ptr<std::vector<Step>> steps, size_t index, Done done) {
  if (index >= steps->size()) {
    done();
    return;
  }
  (*steps)[index]([steps, index, done] {
    dispatch_async(dispatch_get_main_queue(), ^{
      RunSteps(steps, index + 1, done);
    });
  });
}

void Sequence(std::vector<Step> steps, Done done) {
  RunSteps(std::make_shared<std::vector<Step>>(std::move(steps)), 0, std::move(done));
}

// Runs |done| once: with true from the returned callback, or with false
// after |timeout| seconds (recorded as a failed check when |label| is set).
std::function<void(bool)> Once(double timeout, const std::string& label, std::function<void(bool)> done) {
  auto fired = std::make_shared<bool>(false);
  auto finish = [fired, done](bool ok) {
    if (*fired) return;
    *fired = true;
    done(ok);
  };
  After(timeout, [fired, finish, label] {
    if (*fired) return;
    if (!label.empty()) Check(false, label + " within time limit");
    finish(false);
  });
  return finish;
}

fp::PostTask MainPoster() {
  return [](std::function<void()> task) {
    dispatch_async(dispatch_get_main_queue(), ^{
      task();
    });
  };
}

Step Section(const std::string& title) {
  return [title](Done done) {
    Log("== %s", title.c_str());
    done();
  };
}

// ----------------------------------------------------------- license flow

std::string KeysText(const std::vector<fp::KeyInfo>& keys) {
  std::string text;
  for (const fp::KeyInfo& key : keys) {
    if (!text.empty()) text += ", ";
    text += (key.key_id.size() == 16 ? ft::Hex(key.key_id) : std::string(key.key_id.begin(), key.key_id.end())) +
            "=" + fp::KeyStatusName(key.status);
    if (key.system_code) text += Format("(%u)", key.system_code);
  }
  return text;
}

// The page's side of EME for a cenc session: each JSON message entry's SPC
// goes to Axinom with the entitlement token; the CKCs go back in one update().
class LicenseClient : public fp::FairPlayCdmClient {
 public:
  fp::FairPlayCdm* cdm = nullptr;
  std::vector<fp::KeyInfo> keys;
  std::function<void(bool, const std::string&)> on_update;

  void OnSessionMessage(const std::string& session_id, fp::MessageType type,
                        const std::vector<uint8_t>& message) override {
    Log("license: message type=%d, %zu bytes of JSON", int(type), message.size());
    NSData* body = Data(message);
    std::string session = session_id;
    fp::FairPlayCdm* target = cdm;
    auto on_update_copy = on_update;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray* entries = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
      NSMutableArray* answers = [NSMutableArray array];
      std::string failure;
      for (NSDictionary* entry in entries) {
        NSData* spc = [[NSData alloc] initWithBase64EncodedString:entry[@"payload"] options:0];
        Http http = Fetch(kLicenseUrl, @"POST", spc,
                          @{@"X-AxDRM-Message" : kToken, @"Content-Type" : @"application/octet-stream"});
        Log("license: POST SPC %lu bytes -> HTTP %ld, %lu bytes %s", (unsigned long)spc.length, http.status,
            (unsigned long)http.body.length, http.error.c_str());
        if (http.status == 200 && http.body.length) {
          [answers addObject:@{@"keyID" : entry[@"keyID"], @"payload" : [http.body base64EncodedStringWithOptions:0]}];
        } else {
          NSString* message = http.headers[@"X-AxDRM-ErrorMessage"];
          failure = Format("HTTP %ld %s %s", http.status, message.UTF8String ?: "", http.error.c_str());
          [answers addObject:@{@"keyID" : entry[@"keyID"], @"error" : @(1)}];
        }
      }
      std::vector<uint8_t> response = Bytes([NSJSONSerialization dataWithJSONObject:answers options:0 error:nil]);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!failure.empty()) {
          if (on_update_copy) on_update_copy(false, "license server: " + failure);
          return;
        }
        target->UpdateSession(session, response, [on_update_copy](const fp::Result& result) {
          if (on_update_copy) on_update_copy(result.ok(), result.message);
        });
      });
    });
  }

  void OnSessionKeysChange(const std::string&, bool, const std::vector<fp::KeyInfo>& new_keys) override {
    keys = new_keys;
    Log("license: keys change [%s]", KeysText(new_keys).c_str());
  }

  void OnSessionClosed(const std::string&) override {}
};

// A version 1 'pssh' of the W3C common system (1077efec-...), naming |key_id|:
// what a CMAF packager puts in the moov and Chromium's MP4 parser passes on
// as "cenc" init data. With no FairPlay pssh, the CDM requests the key IDs it
// names.
std::vector<uint8_t> CommonPssh(const std::vector<uint8_t>& key_id) {
  static const uint8_t kCommonSystemId[16] = {0x10, 0x77, 0xef, 0xec, 0xc0, 0xb2, 0x4d, 0x02,
                                              0xac, 0xe3, 0x3c, 0x1e, 0x52, 0xe2, 0xfb, 0x4b};
  std::vector<uint8_t> payload = {1, 0, 0, 0};  // Version 1, no flags.
  payload.insert(payload.end(), kCommonSystemId, kCommonSystemId + 16);
  payload.insert(payload.end(), {0, 0, 0, 1});  // KID_count.
  payload.insert(payload.end(), key_id.begin(), key_id.end());
  payload.insert(payload.end(), {0, 0, 0, 0});  // DataSize.
  return fp::MakeBox(fp::FourCC('p', 's', 's', 'h'), payload);
}

// --------------------------------------------------------- decoder errors

struct DecoderLog {
  int errors = 0;      // -1 when the log can't be read.
  std::string common;  // The three most frequent, with counts.
};

// Errors Apple's audio and video decoders and the content protection layer
// logged in this process since |since|. The renderers report none of them:
// an audio decoder that fails every packet still shows status rendering and
// the clock still reaches the end, and some AV1 garbage decodes without a
// corrupted frame. The current process's log needs no entitlement. Slow on
// a long log, so callers run it off the main thread.
DecoderLog DecoderErrorsSince(NSDate* since) {
  DecoderLog out;
  NSError* error = nil;
  OSLogStore* store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:&error];
  NSPredicate* decoders = [NSPredicate
      predicateWithFormat:@"sender == 'AudioCodecs' OR sender == 'AppleVideoDecoder' OR "
                          @"composedMessage CONTAINS[c] 'decod' OR composedMessage CONTAINS 'Cryptor'"];
  OSLogEnumerator* entries = store ? [store entriesEnumeratorWithOptions:0
                                                                position:[store positionWithDate:since]
                                                               predicate:decoders
                                                                   error:&error]
                                   : nil;
  if (!entries) {
    out.errors = -1;
    out.common = error.localizedDescription.UTF8String ?: "no log store";
    return out;
  }
  std::map<std::string, int> counts;
  for (OSLogEntry* entry in entries) {
    if (![entry isKindOfClass:OSLogEntryLog.class]) continue;
    OSLogEntryLog* log = (OSLogEntryLog*)entry;
    if (log.level < OSLogEntryLogLevelError || [log.date compare:since] == NSOrderedAscending) continue;
    NSString* sender = log.sender ?: @"";
    NSString* message = log.composedMessage ?: @"";
    if (![sender isEqualToString:@"AudioCodecs"] && ![sender isEqualToString:@"AppleVideoDecoder"] &&
        ![message localizedCaseInsensitiveContainsString:@"decod"] && ![message containsString:@"Cryptor"]) {
      continue;
    }
    ++out.errors;
    const std::string line = std::string(sender.UTF8String) + ": " + message.UTF8String;
    ++counts[line.substr(0, 200)];
  }
  std::vector<std::pair<int, std::string>> sorted;
  for (const auto& [message, count] : counts) sorted.push_back({count, message});
  std::sort(sorted.begin(), sorted.end(), [](const auto& a, const auto& b) { return a.first > b.first; });
  for (size_t i = 0; i < sorted.size() && i < 3; ++i) {
    out.common += Format("%s%dx \"%s\"", i ? ", " : "", sorted[i].first, sorted[i].second.c_str());
  }
  return out;
}

// ------------------------------------------------------------------ player

// Chromium's decoder configs (MP4StreamParser at the pinned tag, as the
// FairPlay renderer adapter passes them): no video decoder record, Dolby
// Vision as profile and level, AAC with its AudioSpecificConfig and ADTS
// framing where it fits, no dac3/dec3, encryption as the scheme alone.
fp::VideoConfig ChromiumVideoConfig(const ft::TrackInfo& info) {
  fp::VideoConfig vc;
  const uint32_t f = info.original_format;
  if (f == fp::FourCC('h', 'v', 'c', '1') || f == fp::FourCC('h', 'e', 'v', '1')) {
    vc.codec = fp::VideoCodec::kHEVC;
  } else if (f == fp::FourCC('d', 'v', 'h', '1') || f == fp::FourCC('d', 'v', 'h', 'e')) {
    vc.codec = fp::VideoCodec::kDolbyVision;
  } else if (f == fp::FourCC('a', 'v', '0', '1')) {
    vc.codec = fp::VideoCodec::kAV1;
  } else {
    vc.codec = fp::VideoCodec::kH264;
  }
  vc.sample_entry = f;
  const std::vector<uint8_t>& dv = info.dolby_vision_config;
  if (dv.size() >= 5) {
    vc.dolby_vision_profile = dv[2] >> 1;
    vc.dolby_vision_level = ((dv[2] & 1) << 5) | (dv[3] >> 3);
  }
  vc.format = vc.codec == fp::VideoCodec::kAV1 ? fp::BitstreamFormat::kLengthPrefixed : fp::BitstreamFormat::kAnnexB;
  vc.coded_width = info.width;
  vc.coded_height = info.height;
  vc.encryption.scheme = info.encryption.scheme;
  return vc;
}

// --muted: every audio renderer muted at volume 0, nothing out of the speakers.
bool g_muted = false;

fp::AudioConfig ChromiumAudioConfig(const ft::TrackInfo& info) {
  fp::AudioConfig ac;
  const uint32_t f = info.original_format;
  const bool aac = f == fp::FourCC('m', 'p', '4', 'a');
  ac.codec = aac ? fp::AudioCodec::kAAC : f == fp::FourCC('e', 'c', '-', '3') ? fp::AudioCodec::kEAC3 : fp::AudioCodec::kAC3;
  if (aac) ac.extra_data = info.codec_config;
  ac.framing = aac && ft::AacObjectType(info.codec_config, true) <= 4 ? fp::AudioFraming::kADTS : fp::AudioFraming::kRaw;
  ac.sample_rate = int32_t(info.sample_rate);
  ac.channels = aac ? info.channels : DolbyChannels(info);
  const std::vector<uint8_t>& c = info.codec_config;
  if (f == fp::FourCC('f', 'L', 'a', 'C')) {
    // MP4StreamParser: the STREAMINFO block of 'dfLa' (a short box leaves the
    // config empty, which the renderer refuses).
    ac.codec = fp::AudioCodec::kFLAC;
    ac.extra_data.clear();
    if (c.size() >= 8 + 34) ac.extra_data.assign(c.begin() + 8, c.begin() + 8 + 34);
    ac.channels = info.channels;
  } else if (f == fp::FourCC('a', 'l', 'a', 'c')) {
    // fairplay-media.patch's ALACSpecificBox: the 24-byte ALACSpecificConfig
    // after the box's version and flags; channels and rate from it.
    ac.codec = fp::AudioCodec::kALAC;
    ac.extra_data.clear();
    if (c.size() >= 4 + 24) {
      ac.extra_data.assign(c.begin() + 4, c.begin() + 4 + 24);
      ac.channels = c[4 + 9];
      ac.sample_rate = int32_t(uint32_t(c[24]) << 24 | uint32_t(c[25]) << 16 | uint32_t(c[26]) << 8 | c[27]);
    }
  } else if (f == fp::FourCC('i', 'p', 'c', 'm') || f == fp::FourCC('f', 'p', 'c', 'm')) {
    // fairplay-media.patch: kPCM, the sample format from 'pcmC'.
    ac.codec = fp::AudioCodec::kPCM;
    ac.extra_data.clear();
    ac.channels = info.channels;
    ac.pcm_bits = c.size() >= 6 ? c[5] : 0;
    ac.pcm_float = f == fp::FourCC('f', 'p', 'c', 'm');
  } else if (f == fp::FourCC('O', 'p', 'u', 's')) {
    // OpusSpecificBox::Parse: "OpusHead" and the 'dOps' fields, little-endian.
    ac.codec = fp::AudioCodec::kOpus;
    ac.extra_data.clear();
    if (c.size() >= 11) {
      ac.extra_data = {'O', 'p', 'u', 's', 'H', 'e', 'a', 'd', c[0], c[1], c[3], c[2], c[7], c[6], c[5], c[4],
                       c[9], c[8]};
      ac.extra_data.insert(ac.extra_data.end(), c.begin() + 10, c.end());
      ac.channels = c[1];
      ac.sample_rate = int32_t(uint32_t(c[4]) << 24 | uint32_t(c[5]) << 16 | uint32_t(c[6]) << 8 | c[7]);
    }
  }
  ac.encryption.scheme = info.encryption.scheme;
  return ac;
}


class Player : public fp::FairPlayRendererClient {
 public:
  Player(std::string name, const Media* media, fp::FairPlayCdm* cdm, NSView* host, bool file_audio_config = false)
      : name_(std::move(name)), media_(media), video_(media->info.is_video), renderer_(this, MainPoster()), host_(host) {
    std::optional<fp::VideoConfig> vc;
    std::optional<fp::AudioConfig> ac;
    if (video_) vc = ChromiumVideoConfig(media->info);
    else ac = ChromiumAudioConfig(media->info);
    if (ac && file_audio_config) ac->extra_data = media->info.codec_config;
    // Chromium's order when the page set MediaKeys before playback.
    fp::Result result = renderer_.SetCdm(cdm);
    if (!result.ok()) errors.push_back("SetCdm: " + result.message);
    result = renderer_.Initialize(vc, ac);
    if (!result.ok()) errors.push_back("Initialize: " + result.message);
    if (g_muted && result.ok() && ac) {
      // Silent runs: AVFoundation still decodes every packet.
      renderer_.SetMuted(true);
      renderer_.SetVolume(0);
    }
    initialized_ = result.ok();
    layer_ = (__bridge AVSampleBufferDisplayLayer*)renderer_.display_layer();
    if (layer_) {
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      layer_.frame = host_.layer.bounds;
      layer_.backgroundColor = NSColor.blackColor.CGColor;
      [host_.layer addSublayer:layer_];
      [CATransaction commit];
    }
    monitor_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(monitor_, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
    Player* self = this;
    dispatch_source_set_event_handler(monitor_, ^{
      self->LogStatus("tick");
    });
    dispatch_resume(monitor_);
  }

  ~Player() override {
    dispatch_source_cancel(monitor_);
    renderer_.SetCdm(nullptr);
    [layer_ removeFromSuperlayer];
  }

  fp::FairPlayRenderer& renderer() { return renderer_; }
  bool initialized() const { return initialized_; }

  // Whether AVFoundation hands back the frame on screen (it can't for
  // protected output), and its size and pixel format.
  std::string DisplayedFrame() {
    if (@available(macOS 14.4, *)) {
      CVPixelBufferRef frame = layer_ ? [layer_.sampleBufferRenderer copyDisplayedPixelBuffer] : nullptr;
      if (!frame) return "no displayed pixel buffer";
      std::string text = Format("displayed frame %zux%zu '%s'", CVPixelBufferGetWidth(frame),
                                CVPixelBufferGetHeight(frame),
                                ft::FourCCString(CVPixelBufferGetPixelFormatType(frame)).c_str());
      CVPixelBufferRelease(frame);
      return text;
    }
    return "no displayed pixel buffer API";
  }
  double Time() { return renderer_.GetMediaTime().InSeconds(); }

  std::vector<std::string> errors;
  int waiting_events = 0;
  size_t enqueued = 0;
  bool ended = false;
  std::function<void()> on_have_enough;
  std::function<void()> on_ended;

  void Start() {
    renderer_.Flush([this] {
      index_ = 0;
      end_sent_ = false;
      renderer_.StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
      Pump();
    });
  }

  void LogStatus(const char* why) {
    fp::RendererStatus s = renderer_.GetStatus();
    Log("%s %s: t=%.3f rate=%.2f video=%s audio=%s enq v/a=%llu/%llu protected=%llu enough v/a=%d/%d "
        "obscured=%d decodeFail=%llu %s%s",
        name_.c_str(), why, s.time.InSeconds(), s.rate, StatusName(s.video), StatusName(s.audio), s.video_enqueued,
        s.audio_enqueued, s.protected_enqueued, s.video_has_enough, s.audio_has_enough, s.output_obscured,
        s.decode_failures, s.video_error.c_str(), s.audio_error.c_str());
  }

  void OnNeedData(fp::StreamId) override { Pump(); }
  void OnWaitingForKey() override {
    ++waiting_events;
    Log("%s: waiting for key", name_.c_str());
  }
  void OnEnded() override {
    ended = true;
    Log("%s: ended at t=%.3f", name_.c_str(), Time());
    if (on_ended) {
      auto f = std::move(on_ended);
      on_ended = nullptr;
      f();
    }
  }
  void OnError(fp::RendererError error, const std::string& description) override {
    errors.push_back(Format("%s: %s", error == fp::RendererError::kDecode ? "decode" : "configuration",
                            description.c_str()));
    if (errors.size() <= 3) Log("%s: ERROR %s", name_.c_str(), errors.back().c_str());
  }
  void OnVideoNaturalSizeChange(int32_t width, int32_t height) override {
    Log("%s: natural size %dx%d", name_.c_str(), width, height);
  }
  void OnBufferingStateChange(bool enough) override {
    Log("%s: buffering %s at t=%.3f", name_.c_str(), enough ? "HAVE_ENOUGH" : "HAVE_NOTHING", Time());
    if (enough && on_have_enough) {
      auto f = std::move(on_have_enough);
      on_have_enough = nullptr;
      f();
    }
  }

 private:
  // DemuxerStream reads: each sample in Chromium's DecoderBuffer form (Annex B
  // with parameter sets on keyframes, ADTS, microseconds, 16-byte IVs, no
  // decode timestamp), then end of stream.
  void Pump() {
    const fp::StreamType stream = video_ ? fp::StreamType::kVideo : fp::StreamType::kAudio;
    while (initialized_ && renderer_.IsReadyForMoreData(stream)) {
      if (index_ >= media_->samples.size()) {
        if (!end_sent_) {
          end_sent_ = true;
          renderer_.SetEndOfStream(stream);
        }
        return;
      }
      const ft::Sample& sample = media_->samples[index_++];
      fp::EncodedSample buffer = ft::ChromiumBuffer(media_->info, sample, &storage_, &decrypt_storage_);
      buffer.dts = fp::MediaTime::Invalid();
      fp::EnqueueResult result = renderer_.Enqueue(stream, buffer);
      if (result == fp::EnqueueResult::kRejected) {
        errors.push_back(Format("enqueue of sample %zu rejected", index_ - 1));
        return;
      }
      ++enqueued;
      if (result == fp::EnqueueResult::kWaitingForKey) return;
    }
  }

  std::string name_;
  const Media* media_;
  bool video_;
  bool initialized_ = false;
  fp::FairPlayRenderer renderer_;
  NSView* host_;
  AVSampleBufferDisplayLayer* layer_ = nil;
  dispatch_source_t monitor_ = nil;
  size_t index_ = 0;
  bool end_sent_ = false;
  std::vector<uint8_t> storage_;
  fp::DecryptInfo decrypt_storage_;
};

// ------------------------------------------------------------------- world

// What a clip's playback is expected to show.
enum class Expect {
  kPlays,     // Decrypts and decodes: every check must pass.
  kGarbage,   // Control (wrong key): must not look like healthy playback,
              // or healthy playback proves nothing for this codec.
  kFails,     // Documented platform behaviour: must not play correctly.
  kReport,    // Reported only (a control whose result is information).
  kDecodeError,  // Safari's outcome: AVFoundation takes the protected format
                 // (expected_types) and fails the renderer once the key is
                 // usable, which a page sees as MEDIA_ERR_DECODE.
};

struct Clip {
  std::string label;
  Media media;                 // Protected samples.
  std::string expected_types;  // Apple's protected format subtype(s), '|'-separated.
  Expect expect = Expect::kPlays;
  // AC-3/E-AC-3: hand the renderer the file's dac3/dec3, which Chromium
  // doesn't (isolates the core's own box building).
  bool file_audio_config = false;
};

struct ClipResult {
  std::string label;
  std::string verdict;  // OK, FAIL, or INFO.
  std::string evidence;
};

struct World {
  std::vector<uint8_t> certificate;
  std::vector<uint8_t> key_id;
  std::vector<uint8_t> key;
  NSView* host = nil;
  LicenseClient license;
  std::unique_ptr<fp::FairPlayCdm> cdm;
  std::string session;
  std::shared_ptr<Player> player;
  std::vector<std::shared_ptr<Clip>> clips;
  std::vector<ClipResult> results;
  // Loaded media.
  Media h264, h264_cbcs_ref, hevc, dv5_dvh1, dv5_dvhe, av1_ref, av1, av1_10bit_ref, av1_10bit, xhe_aac, ac3, eac3,
      eac3_71, eac3_71_full, aac_lc, he_aac, he_aac_v2, axinom_h264, axinom_hevc, flac, opus, alac, ipcm16,
      ipcm24, fpcm32;
  // The Dolby Vision dvhe test file's own cenc layout (dv5_dvhe holds it
  // decrypted).
  std::vector<std::vector<fp::SubsampleEntry>> dv5_dvhe_layout;
  // Shaka Packager's subsample layouts of the AV1 streams (av1_ref and
  // av1_10bit_ref hold those streams decrypted).
  std::vector<std::vector<fp::SubsampleEntry>> av1_layout, av1_10bit_layout;
};

World* g_world = nullptr;
std::string g_only;

Step AcquireLicense() {
  return [](Done done) {
    World* w = g_world;
    w->cdm = std::make_unique<fp::FairPlayCdm>(&w->license, MainPoster());
    w->license.cdm = w->cdm.get();
    w->cdm->SetServerCertificate(w->certificate, [](const fp::Result& r) {
      Check(r.ok(), "license: SetServerCertificate resolves", r.message);
    });
    auto finish = Once(40, "license: key usable", [done](bool ok) {
      if (!ok) {
        Log("license: no usable key; nothing can play");
        Finish();
      }
      done();
    });
    w->license.on_update = [w, finish](bool ok, const std::string& detail) {
      Check(ok, "license: update() resolves with Axinom's CKC", detail);
      bool usable = w->cdm->HasUsableKey(w->key_id);
      Check(usable, "license: key " + ft::Hex(w->key_id) + " is usable", KeysText(w->license.keys));
      finish(ok && usable);
    };
    w->cdm->CreateSessionAndGenerateRequest(fp::InitDataType::kCenc, CommonPssh(w->key_id),
                                            [w, finish](const fp::Result& r, const std::string& id) {
                                              w->session = id;
                                              Check(r.ok(), "license: generateRequest with cenc init data",
                                                    r.ok() ? id : r.message);
                                              if (!r.ok()) finish(false);
                                            });
  };
}

// Plays one protected clip from the start to OnEnded and judges it by the
// clock, renderer status and (video) AVFoundation's frame counts.
std::vector<Step> PlayClip(std::shared_ptr<Clip> clip) {
  World* w = g_world;
  const double end = EndSeconds(clip->media);
  const bool video = clip->media.info.is_video;
  auto wall_start = std::make_shared<double>(0);
  auto have_enough = std::make_shared<bool>(false);
  auto ended_at = std::make_shared<double>(-1);
  auto ended_wall = std::make_shared<double>(0);
  auto started = std::make_shared<NSDate*>(nil);
  auto decoder_log = std::make_shared<DecoderLog>();
  std::vector<Step> steps;
  steps.push_back(Section(clip->label));
  steps.push_back([=](Done done) {
    const ft::TrackInfo& info = clip->media.info;
    Log("%s: %s/%s, %zu samples, %.3f s, %s, config %zu bytes", clip->label.c_str(),
        ft::FourCCString(info.sample_entry).c_str(), ft::FourCCString(info.original_format).c_str(),
        clip->media.samples.size(), end, ft::FourCCString(info.scheme_type).c_str(), info.codec_config.size());
    *started = [NSDate date];
    w->player = std::make_shared<Player>(clip->label, &clip->media, w->cdm.get(), w->host, clip->file_audio_config);
    const bool must_play = clip->expect == Expect::kPlays;
    auto go = Once(15, must_play ? clip->label + ": HAVE_ENOUGH" : "", [=](bool ok) {
      *have_enough = ok;
      *wall_start = CFAbsoluteTimeGetCurrent();
      w->player->renderer().SetPlaybackRate(1);
      done();
    });
    w->player->on_have_enough = [go] { go(true); };
    w->player->Start();
  });
  steps.push_back([=](Done done) {
    auto finish = Once(end + 10, clip->expect == Expect::kPlays ? clip->label + ": OnEnded" : "", [=](bool ok) {
      if (ok) {
        *ended_at = w->player->Time();
        *ended_wall = CFAbsoluteTimeGetCurrent() - *wall_start;
      }
      done();
    });
    if (w->player->ended) finish(true);
    else w->player->on_ended = [finish] { finish(true); };
  });
  // The log store can trail by a moment.
  steps.push_back([=](Done done) {
    After(1, [=] {
      NSDate* since = *started;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        DecoderLog log = DecoderErrorsSince(since);
        dispatch_async(dispatch_get_main_queue(), ^{
          *decoder_log = log;
          done();
        });
      });
    });
  });
  steps.push_back([=](Done done) {
    auto judge = [=](const fp::VideoMetrics& m) {
      fp::RendererStatus s = w->player->renderer().GetStatus();
      const double wall = *ended_wall;
      const size_t count = clip->media.samples.size();
      // A clip that is clear as given (a baseline) plays clear: nothing
      // protected, and the expected type is the clear format's.
      const bool clear_given = clip->media.info.encryption.scheme == fp::EncryptionScheme::kUnencrypted;
      const std::string type = ft::FourCCString(clear_given ? (video ? s.video_format : s.audio_format)
                                                            : (video ? s.video_protected_format : s.audio_protected_format));
      const fp::RenderingStatus status = video ? s.video : s.audio;
      const std::string apple_error = video ? s.video_error : s.audio_error;
      const bool on_time = *ended_at >= 0 && std::fabs(*ended_at - end) < 0.3;
      const bool rendering = status == fp::RenderingStatus::kRendering;
      const bool clean = w->player->errors.empty() && s.decode_failures == 0;
      const bool all_protected = clear_given ? s.protected_enqueued == 0 : s.protected_enqueued == count;
      const bool frames_ok = !video || (m.available && m.total_frames >= int64_t(count * 9 / 10) &&
                                        m.corrupted_frames == 0);
      const bool type_ok = ("|" + clip->expected_types + "|").find("|" + type + "|") != std::string::npos;
      std::string evidence =
          Format("%s; ended %s; %llu/%zu samples enqueued protected; status %s%s%s; decode failures %llu",
                 type.c_str(),
                 *ended_at >= 0 ? Format("at t=%.3f for a %.3f s end, %.3f s wall", *ended_at, end, wall).c_str()
                                : "never",
                 s.protected_enqueued, count, StatusName(status), apple_error.empty() ? "" : " ", apple_error.c_str(),
                 s.decode_failures);
      if (video) {
        evidence += Format("; AVFoundation frames %lld (dropped %lld, corrupted %lld)", m.total_frames,
                           m.dropped_frames, m.corrupted_frames);
      }
      if (!w->player->errors.empty()) evidence += "; renderer error: " + w->player->errors.front();
      const bool quiet_log = decoder_log->errors == 0;
      evidence += decoder_log->errors < 0 ? "; decoder log unreadable: " + decoder_log->common
                  : quiet_log             ? "; no decoder errors in the unified log"
                                          : Format("; %d decoder errors in the unified log: %s",
                                                   decoder_log->errors, decoder_log->common.c_str());
      if (s.output_obscured) evidence += "; output obscured (screen capture)";
      if (video) Log("%s: %s", clip->label.c_str(), w->player->DisplayedFrame().c_str());
      const bool healthy = on_time && rendering && clean && frames_ok && quiet_log;
      if (clip->expect == Expect::kGarbage) {
        // If garbage looks like healthy playback, frame counts and statuses
        // prove nothing about decryption for this codec.
        Check(!healthy, clip->label + ": decoding garbage is detected", evidence);
        w->results.push_back({clip->label, healthy ? "FAIL" : "OK", evidence});
      } else if (clip->expect == Expect::kFails) {
        Check(!healthy, clip->label + ": doesn't play, as documented", evidence);
        w->results.push_back({clip->label, healthy ? "FAIL" : "OK", "fails as documented: " + evidence});
      } else if (clip->expect == Expect::kDecodeError) {
        // -11800 over 'fmt?' (kAudioFormatUnsupportedFormatError, 1718449215):
        // no decoder for the format, after the protected samples went in.
        const bool as_safari = type_ok && status == fp::RenderingStatus::kFailed && s.protected_enqueued > 0 &&
                               apple_error.find("-11800") != std::string::npos &&
                               apple_error.find("1718449215") != std::string::npos &&
                               !w->player->errors.empty() && w->player->errors.front().rfind("decode: ", 0) == 0;
        Check(as_safari,
              clip->label + ": protected format '" + clip->expected_types +
                  "', then AVFoundation's renderer fails with a decode error, as in Safari",
              evidence);
        w->results.push_back({clip->label, as_safari ? "OK" : "FAIL", "decode error: " + evidence});
      } else if (clip->expect == Expect::kReport) {
        Log("%s: %s", clip->label.c_str(), healthy ? "looks healthy" : "fails");
        w->results.push_back({clip->label, "INFO", std::string(healthy ? "looks healthy: " : "fails: ") + evidence});
      } else {
        Check(*have_enough && on_time, clip->label + ": reached HAVE_ENOUGH and played to OnEnded at the clip's end",
              evidence);
        Check(rendering && clean, clip->label + ": renderer status rendering, no decode or renderer errors", evidence);
        Check(all_protected,
              clip->label + (clear_given ? ": every sample went to AVFoundation clear"
                                         : ": every sample went to AVFoundation as a protected sample buffer"),
              Format("%llu of %zu", s.protected_enqueued, count));
        Check(type_ok,
              clip->label + (clear_given ? ": format description is Apple's '" : ": protected format description is Apple's '") +
                  clip->expected_types + "'",
              "'" + type + "'");
        if (video) {
          Check(frames_ok, clip->label + ": AVFoundation decoded at least 90% of the frames, none corrupted",
                Format("%lld of %zu, corrupted %lld", m.total_frames, count, m.corrupted_frames));
        }
        Check(quiet_log, clip->label + ": Apple's decoders logged no errors while it played",
              decoder_log->errors < 0 ? decoder_log->common
                                      : Format("%d errors %s", decoder_log->errors, decoder_log->common.c_str()));
        const bool ok =
            *have_enough && on_time && rendering && clean && all_protected && type_ok && frames_ok && quiet_log;
        w->results.push_back({clip->label, ok ? "OK" : "FAIL", evidence});
      }
      w->player.reset();
      done();
    };
    if (video) {
      w->player->renderer().LoadVideoMetrics(judge);
    } else {
      judge(fp::VideoMetrics());
    }
  });
  return steps;
}

// --------------------------------------------------------------- self tests

// The cipher and the layouts against packagers' own output, before any of it
// reaches FairPlay.
void SelfTests() {
  World* w = g_world;
  const std::vector<uint8_t> chromium_key = FromHex(kChromiumKeyHex);
  std::string error;
  // AES-CBC with the 1:9 pattern and the H.264 layout against Shaka
  // Packager's bear-640x360-v_frag-cbcs.mp4 (the clear file, encrypted with
  // the README's test key after a clear lead). The parser doesn't expose that
  // file's subsamples, so each of its samples must equal either the clear
  // sample or this program's encryption of it.
  {
    ft::NalLayout nal(ft::NalCodec::kH264, w->h264.info.codec_config);
    size_t identical = 0, clear_lead = 0;
    const size_t count = std::min(w->h264.samples.size(), w->h264_cbcs_ref.samples.size());
    for (size_t i = 0; i < count; ++i) {
      const std::vector<uint8_t>& theirs = w->h264_cbcs_ref.samples[i].data;
      std::vector<uint8_t> ours = w->h264.samples[i].data;
      std::vector<fp::SubsampleEntry> layout;
      if (!nal.Subsamples(ours, fp::EncryptionScheme::kCbcs, &layout, &error)) break;
      if (theirs == ours) {
        ++clear_lead;
        continue;
      }
      ft::CencCrypt(true, fp::EncryptionScheme::kCbcs, chromium_key, w->h264_cbcs_ref.info.encryption.default_constant_iv,
                    {1, 9}, layout, &ours, &error);
      identical += ours == theirs;
    }
    Check(count == w->h264.samples.size() && identical > 0 && identical + clear_lead == count,
          "cipher and layout: cbcs (AES-CBC, 1:9) H.264 encryption equals Shaka Packager's byte for byte",
          Format("%zu identical, %zu clear lead, of %zu samples", identical, clear_lead, count));
  }
  // Slice header ends against Axinom's own cbcs vectors (H.264 and HEVC):
  // their clear bytes per NAL unit must equal ours exactly.
  for (const Media* m : {&w->axinom_h264, &w->axinom_hevc}) {
    const bool hevc = m == &w->axinom_hevc;
    ft::NalLayout nal(hevc ? ft::NalCodec::kHevc : ft::NalCodec::kH264, m->info.codec_config);
    size_t same = 0;
    std::string first_difference;
    for (size_t i = 0; i < m->samples.size(); ++i) {
      std::vector<fp::SubsampleEntry> mine;
      const std::vector<fp::SubsampleEntry> theirs =
          m->samples[i].decrypt ? m->samples[i].decrypt->subsamples : std::vector<fp::SubsampleEntry>();
      if (nal.Subsamples(m->samples[i].data, fp::EncryptionScheme::kCbcs, &mine, &error) && SameLayout(mine, theirs)) {
        ++same;
      } else if (first_difference.empty()) {
        first_difference = Format("; sample %zu: ours %s, Axinom's %s %s", i, LayoutText(mine).c_str(),
                                  LayoutText(theirs).c_str(), error.c_str());
      }
    }
    Check(nal.ok() && !m->samples.empty() && same == m->samples.size(),
          std::string("layout: ") + (hevc ? "HEVC" : "H.264") + " cbcs subsamples equal Axinom's packager's",
          Format("%zu/%zu samples", same, m->samples.size()) + first_difference);
  }
  // HEVC cenc layout (16-byte aligned) against the Dolby Vision dvhe test
  // file's own, and AES-CTR against that file and Shaka's AV1 files: each
  // decrypts to the clear stream.
  {
    ft::NalLayout nal(ft::NalCodec::kHevc, w->dv5_dvhe.info.codec_config);
    size_t same = 0;
    std::string first_difference;
    for (size_t i = 0; i < w->dv5_dvhe.samples.size(); ++i) {
      std::vector<fp::SubsampleEntry> mine;
      if (nal.Subsamples(w->dv5_dvhe.samples[i].data, fp::EncryptionScheme::kCenc, &mine, &error) &&
          SameLayout(mine, w->dv5_dvhe_layout[i])) {
        ++same;
      } else if (first_difference.empty()) {
        first_difference = Format("; sample %zu: ours %s, file's %s %s", i, LayoutText(mine).c_str(),
                                  LayoutText(w->dv5_dvhe_layout[i]).c_str(), error.c_str());
      }
    }
    Check(!w->dv5_dvhe.samples.empty() && same == w->dv5_dvhe.samples.size(),
          "layout: HEVC cenc subsamples equal the Dolby Vision dvhe test file's",
          Format("%zu/%zu samples", same, w->dv5_dvhe.samples.size()) + first_difference);
  }
  for (auto [ref, clear_file, name] : {std::tuple{&w->av1_ref, &w->av1, "AV1"},
                                      std::tuple{&w->av1_10bit_ref, &w->av1_10bit, "AV1 10-bit"}}) {
    Check(SameSamples(*ref, *clear_file),
          std::string("cipher: cenc (AES-CTR) decrypts Shaka's ") + name + " samples to Chromium's clear file",
          Format("%zu samples", ref->samples.size()));
  }
}

// Apple's view of a dec3: the channels and layout of each layer CoreMedia
// lists for it (the first is the richest, as with HE-AAC).
std::string Dec3Layers(const std::vector<uint8_t>& dec3, uint32_t sample_rate, AudioChannelLayoutTag* top,
                       UInt32* top_channels) {
  *top = 0;
  *top_channels = 0;
  std::vector<uint8_t> entry = fp::AudioSampleEntry(fp::FourCC('e', 'c', '-', '3'), 2, sample_rate,
                                                    {fp::MakeBox(fp::FourCC('d', 'e', 'c', '3'), dec3)});
  CMAudioFormatDescriptionRef format = nullptr;
  OSStatus status = CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(
      nullptr, entry.data(), entry.size(), kCMSoundDescriptionFlavor_ISOFamily, &format);
  if (status != noErr || !format) return Format("CoreMedia error %d", int(status));
  size_t size = 0;
  const AudioFormatListItem* list = CMAudioFormatDescriptionGetFormatList(format, &size);
  std::string text = "dec3 " + ft::Hex(dec3) + ", layers";
  for (size_t i = 0; list && i < size / sizeof(AudioFormatListItem); ++i) {
    if (i == 0) {
      *top = list[i].mChannelLayoutTag;
      *top_channels = list[i].mASBD.mChannelsPerFrame;
    }
    text += Format(" %u ch (layout tag %u|%u)", list[i].mASBD.mChannelsPerFrame, list[i].mChannelLayoutTag >> 16,
                   list[i].mChannelLayoutTag & 0xffff);
  }
  CFRelease(format);
  return text;
}

// The 7.1 stream (channel configuration FA01: L R C LFE Ls Rs Lrs Rrs):
// Apple's E-AC-3 decoder on the clear frames, then the layouts Apple derives
// from the file's dec3 and from the two dec3 the core can build (from clear
// syncframe headers, and from rate and channel count when the headers are
// encrypted).
void ChannelLayoutChecks() {
  World* w = g_world;
  const ft::TrackInfo& info = w->eac3_71_full.info;
  AudioChannelLayoutTag file_tag = 0, tag = 0;
  UInt32 file_channels = 0, channels = 0;
  const std::string file_text = Dec3Layers(info.codec_config, info.sample_rate, &file_tag, &file_channels);
  Check(file_channels == 8 && file_tag == kAudioChannelLayoutTag_EAC3_7_1_A,
        "7.1: CoreMedia's top layer for the file's dec3 is 8 channels, EAC3_7_1_A (L C R Ls Rs LFE Rls Rrs)",
        file_text);

  // Apple's decoder on all 30 s of clear frames, asked for that top layer.
  std::vector<uint8_t> entry = fp::AudioSampleEntry(fp::FourCC('e', 'c', '-', '3'), 2, info.sample_rate,
                                                    {fp::MakeBox(fp::FourCC('d', 'e', 'c', '3'), info.codec_config)});
  CMAudioFormatDescriptionRef format = nullptr;
  CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(nullptr, entry.data(), entry.size(),
                                                                 kCMSoundDescriptionFlavor_ISOFamily, &format);
  size_t list_size = 0;
  const AudioFormatListItem* list = format ? CMAudioFormatDescriptionGetFormatList(format, &list_size) : nullptr;
  std::string decoded = "no format list";
  std::vector<double> energy;
  AudioChannelLayoutTag out_tag = 0;
  if (list && list_size >= sizeof(AudioFormatListItem)) {
    const AudioStreamBasicDescription in = list[0].mASBD;
    AudioStreamBasicDescription out = {};
    out.mSampleRate = in.mSampleRate;
    out.mFormatID = kAudioFormatLinearPCM;
    out.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    out.mChannelsPerFrame = in.mChannelsPerFrame;
    out.mBitsPerChannel = 32;
    out.mBytesPerFrame = out.mBytesPerPacket = 4 * out.mChannelsPerFrame;
    out.mFramesPerPacket = 1;
    AudioConverterRef converter = nullptr;
    OSStatus status = AudioConverterNew(&in, &out, &converter);
    if (status == noErr) {
      size_t cookie_size = 0;
      const void* cookie = CMAudioFormatDescriptionGetMagicCookie(format, &cookie_size);
      if (cookie) {
        AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, UInt32(cookie_size), cookie);
      }
      UInt32 size = 0;
      if (AudioConverterGetPropertyInfo(converter, kAudioConverterOutputChannelLayout, &size, nullptr) == noErr &&
          size >= sizeof(AudioChannelLayout)) {
        std::vector<uint8_t> storage(size);
        if (AudioConverterGetProperty(converter, kAudioConverterOutputChannelLayout, &size, storage.data()) == noErr) {
          out_tag = reinterpret_cast<AudioChannelLayout*>(storage.data())->mChannelLayoutTag;
        }
      }
      struct Feed {
        const std::vector<ft::Sample>* samples;
        size_t index = 0;
        AudioStreamPacketDescription description = {};
      } feed{&w->eac3_71_full.samples};
      auto provide = [](AudioConverterRef, UInt32* packets, AudioBufferList* data,
                        AudioStreamPacketDescription** descriptions, void* user) -> OSStatus {
        auto* f = static_cast<Feed*>(user);
        if (f->index >= f->samples->size()) {
          *packets = 0;
          return noErr;
        }
        const ft::Sample& s = (*f->samples)[f->index++];
        data->mBuffers[0].mData = const_cast<uint8_t*>(s.data.data());
        data->mBuffers[0].mDataByteSize = UInt32(s.data.size());
        f->description = {0, 0, UInt32(s.data.size())};
        if (descriptions) *descriptions = &f->description;
        *packets = 1;
        return noErr;
      };
      energy.assign(out.mChannelsPerFrame, 0);
      std::vector<float> pcm(size_t(4096) * out.mChannelsPerFrame);
      uint64_t total = 0;
      OSStatus fill = noErr;
      while (true) {
        AudioBufferList buffers = {1, {{out.mChannelsPerFrame, UInt32(pcm.size() * 4), pcm.data()}}};
        UInt32 frames = 4096;
        fill = AudioConverterFillComplexBuffer(converter, provide, &feed, &frames, &buffers, nullptr);
        for (size_t i = 0; i < size_t(frames) * out.mChannelsPerFrame; ++i) {
          energy[i % out.mChannelsPerFrame] += double(pcm[i]) * pcm[i];
        }
        total += frames;
        if (fill != noErr || frames == 0) break;
      }
      std::string per_channel;
      for (double e : energy) per_channel += Format(" %.3g", total ? std::sqrt(e / double(total)) : 0.0);
      decoded = Format("%llu frames x %u channels decoded (status %d), output layout tag %u|%u; RMS per channel%s",
                       total, out.mChannelsPerFrame, int(fill), out_tag >> 16, out_tag & 0xffff, per_channel.c_str());
      AudioConverterDispose(converter);
    } else {
      decoded = Format("AudioConverterNew %d", int(status));
    }
  }
  if (format) CFRelease(format);
  size_t live = 0;
  for (double e : energy) live += e > 0;
  // The LFE channel of a voice-identification stream may be silent.
  Check(energy.size() == 8 && live >= 7 && out_tag == kAudioChannelLayoutTag_EAC3_7_1_A,
        "7.1: Apple's E-AC-3 decoder outputs 8 discrete channels (EAC3_7_1_A) from the clear stream", decoded);

  // The core's dec3 from the first sample's clear syncframe headers.
  const ft::Sample& first = w->eac3_71_full.samples.front();
  std::optional<std::vector<uint8_t>> core = fp::Eac3SpecificBoxPayload(first.data.data(), first.data.size(), nullptr);
  std::string core_text = core ? Dec3Layers(*core, info.sample_rate, &tag, &channels) : "none";
  Check(core && tag == file_tag && channels == file_channels,
        "7.1: the dec3 the core builds from clear syncframe headers gives Apple's layout of the file's dec3",
        "core " + core_text + "; file " + file_text);
  // ... and from rate and channel count (encrypted headers).
  core = fp::Eac3SpecificBoxFromConfig(int(info.sample_rate), DolbyChannels(info));
  core_text = core ? Dec3Layers(*core, info.sample_rate, &tag, &channels)
                   : Format("Eac3SpecificBoxFromConfig(%u, %d) returns nothing", info.sample_rate, DolbyChannels(info));
  Check(core && tag == file_tag && channels == file_channels,
        "7.1: the dec3 the core builds from rate and channels gives Apple's layout of the file's dec3",
        "core " + core_text + "; file " + file_text);
}

// -------------------------------------------------------------------- main

std::atomic<double> g_heartbeat{0};
double g_time_limit = 600;

// Watchdog: the run must never wait forever. A main-queue heartbeat is
// checked from a background queue; if the main thread stalls for 15 s, or the
// whole run exceeds its time limit, the main thread's stack is sampled into
// the log and the process exits with status 3 (stall) or 4 (time limit).
void StartWatchdog() {
  static dispatch_source_t beat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(beat, DISPATCH_TIME_NOW, NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
  dispatch_source_set_event_handler(beat, ^{
    g_heartbeat = Now();
  });
  dispatch_resume(beat);
  static dispatch_source_t check =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
  dispatch_source_set_timer(check, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
  dispatch_source_set_event_handler(check, ^{
    double now = Now();
    double stalled = now - g_heartbeat.load();
    bool stall = g_heartbeat.load() > 0 && stalled > 15;
    bool over = now > g_time_limit;
    if (!stall && !over) return;
    if (stall) {
      Log("WATCHDOG: main thread stalled for %.0f s; sampling its stack", stalled);
    } else {
      Log("WATCHDOG: run exceeded its %.0f s limit; sampling the main thread", g_time_limit);
    }
    std::string path = std::string(NSTemporaryDirectory().UTF8String) + Format("fairplay-codecs-sample-%d.txt", getpid());
    std::string command = Format("/usr/bin/sample %d 2 -file '%s' >/dev/null 2>&1", getpid(), path.c_str());
    if (system(command.c_str()) == 0) {
      NSString* text = [NSString stringWithContentsOfFile:@(path.c_str()) encoding:NSUTF8StringEncoding error:nil];
      bool main_thread = false;
      int printed = 0;
      for (NSString* line in [text componentsSeparatedByString:@"\n"]) {
        if ([line containsString:@"com.apple.main-thread"]) main_thread = true;
        else if (main_thread && [line containsString:@"Thread_"]) break;
        if (main_thread && printed++ < 80) printf("    %s\n", line.UTF8String);
      }
      Log("WATCHDOG: full sample in %s", path.c_str());
    }
    Log("== summary: %d checks, %d failed, then %s", g_checks, g_failures, stall ? "STALLED" : "TIMED OUT");
    fflush(stdout);
    _exit(stall ? 3 : 4);
  });
  dispatch_resume(check);
}

void Finish() {
  World* w = g_world;
  if (w && !w->results.empty()) {
    Log("== per-codec results");
    for (const ClipResult& r : w->results) Log("%-4s %s -- %s", r.verdict.c_str(), r.label.c_str(), r.evidence.c_str());
  }
  Log("== summary: %d checks, %d failed", g_checks, g_failures);
  for (const std::string& name : g_failed) Log("   failed: %s", name.c_str());
  fflush(stdout);
  exit(g_failures ? 1 : 0);
}

// Adds a protected clip: |clear| encrypted as |options| say, with Axinom's
// key or, when |wrong_key|, another key under the same key ID.
// |wrong_key| XORs every key byte with it (0: Axinom's key).
void AddClip(const std::string& label, const Media& clear, ProtectOptions options, const std::string& expected_types,
             Expect expect = Expect::kPlays, uint8_t wrong_key = 0, bool file_audio_config = false) {
  World* w = g_world;
  if (!g_only.empty() && label.find(g_only) == std::string::npos) return;
  auto clip = std::make_shared<Clip>();
  clip->label = label;
  clip->expected_types = expected_types;
  clip->expect = expect;
  clip->file_audio_config = file_audio_config;
  std::vector<uint8_t> key = w->key;
  for (uint8_t& b : key) b ^= wrong_key;
  ProtectionStats stats;
  std::string error;
  bool ok = Protect(clear, options, key, w->key_id, &clip->media, &stats, &error);
  Check(ok && stats.round_trip && stats.protected_samples > 0,
        label + ": encrypted in memory" + (wrong_key ? " with a different key under the same key ID" : ""),
        ok ? Format("%zu samples, %zu with whole encrypted blocks; %zu of %zu bytes in protected ranges, %zu changed",
                    stats.samples, stats.protected_samples, stats.cypher_bytes, stats.bytes, stats.changed_bytes)
           : error);
  if (ok) w->clips.push_back(clip);
}

void RunAll() {
  World* w = g_world;
  SelfTests();
  ChannelLayoutChecks();
  const auto cbcs = fp::EncryptionScheme::kCbcs, cenc = fp::EncryptionScheme::kCenc;
  const ProtectOptions nal = Options(cbcs, Layout::kNal, IvMode::kLicense, nullptr);
  const ProtectOptions nal_cenc = Options(cenc, Layout::kNal, IvMode::kPerSample, nullptr);
  const ProtectOptions audio = Options(cbcs, Layout::kWholeSample, IvMode::kLicense, nullptr);
  const ProtectOptions syncframes = Options(cbcs, Layout::kSyncframeHeaders, IvMode::kLicense, nullptr);
  const ProtectOptions av1 = Options(cbcs, Layout::kReference, IvMode::kLicense, &w->av1_layout);
  const ProtectOptions av1_probe = Options(cbcs, Layout::kAv1ObuPayloads, IvMode::kLicense, nullptr);
  auto with_iv = [](ProtectOptions o, IvMode iv) {
    o.iv = iv;
    return o;
  };

  // Controls: Axinom's own segment, then this program's encryption of what
  // already plays (H.264, HEVC, AAC-LC) through the same path, and garbage.
  auto add_loaded = [w](const std::string& label, const Media& media, const std::string& types, Expect expect) {
    if (!g_only.empty() && label.find(g_only) == std::string::npos) return;
    auto clip = std::make_shared<Clip>();
    clip->label = label;
    clip->expected_types = types;
    clip->media = media;
    clip->expect = expect;
    w->clips.push_back(clip);
  };
  add_loaded("H.264 Axinom vector segment as served", w->axinom_h264, "qavc", Expect::kPlays);
  AddClip("H.264 avc1 cbcs", w->h264, nal, "qavc");
  AddClip("H.264 avc1 cbcs, wrong key (control)", w->h264, nal, "qavc", Expect::kGarbage, 0x5a);
  // FairPlay decrypts qavc, qhvc and qdh1 with the CKC's IV: a content IV the
  // license doesn't carry fails, in the tenc and in CryptorIV alike.
  AddClip("H.264 avc1 cbcs, constant IV not the license's", w->h264, with_iv(nal, IvMode::kOther), "qavc",
          Expect::kFails);
  // WebKit's FairPlay takes cbcs only, and Parc refuses cenc on Safari pages:
  // AES-CTR content isn't expected to play.
  AddClip("H.264 avc1 cenc, 8-byte per-sample IVs", w->h264, nal_cenc, "cavc", Expect::kFails);
  AddClip("H.264 avc1 cenc, every IV the license's", w->h264, with_iv(nal_cenc, IvMode::kLicense), "cavc",
          Expect::kReport);
  AddClip("HEVC hev1 cbcs", w->hevc, nal, "qhvc");
  AddClip("AAC-LC cbcs", w->aac_lc, audio, "qaac");
  AddClip("AAC-LC cenc, 8-byte per-sample IVs", w->aac_lc, Options(cenc, Layout::kWholeSample, IvMode::kPerSample, nullptr),
          "qaac", Expect::kFails);
  AddClip("AAC-LC cbcs, wrong key (control)", w->aac_lc, audio, "qaac", Expect::kGarbage, 0x5a);

  // The codecs no public FairPlay content covers.
  AddClip("Dolby Vision profile 5 dvh1 cbcs", w->dv5_dvh1, nal, "qdh1");
  AddClip("Dolby Vision profile 5 dvh1 cbcs, wrong key (control)", w->dv5_dvh1, nal, "qdh1", Expect::kGarbage, 0x5a);
  AddClip("Dolby Vision profile 5 dvhe cbcs", w->dv5_dvhe, nal, "qdh1");
  AddClip("Dolby Vision profile 5 dvhe cenc, 8-byte per-sample IVs", w->dv5_dvhe, nal_cenc, "cdh1", Expect::kFails);
  add_loaded("AV1 8-bit av01 clear (baseline)", w->av1, "", Expect::kReport);
  AddClip("AV1 8-bit av01 cbcs", w->av1, av1, "qav1");
  // Garbage tile data mostly decodes without a word, so the control runs
  // under several wrong keys: at least one must trip the decoder.
  for (uint8_t k : {0x5a, 0x01, 0x80, 0xff, 0x33, 0xc4}) {
    AddClip(Format("AV1 8-bit av01 cbcs, wrong key %02x (control)", k), w->av1, av1, "qav1", Expect::kReport, k);
  }
  ProtectOptions av1_10bit = av1;
  av1_10bit.reference = &w->av1_10bit_layout;
  AddClip("AV1 10-bit av01 cbcs", w->av1_10bit, av1_10bit, "qav1");
  // Video protected with every block encrypted (pattern 0:0, not CMAF's 1:9)
  // doesn't decrypt correctly: about half the frames fail with the right key.
  ProtectOptions av1_all = av1;
  av1_all.pattern = fp::EncryptionPattern{0, 0};
  AddClip("AV1 8-bit av01 cbcs, every tile block encrypted (pattern 0:0)", w->av1, av1_all, "qav1", Expect::kFails);
  // Apple parses AV1 frame headers before decrypting: encrypted ones fail.
  AddClip("AV1 8-bit av01 cbcs, frame headers encrypted", w->av1, av1_probe, "qav1", Expect::kFails);
  // Apple has no cenc AV1 type: the description stays 'encv'.
  AddClip("AV1 8-bit av01 cenc", w->av1, Options(cenc, Layout::kReference, IvMode::kPerSample, &w->av1_layout), "qav1",
          Expect::kFails);
  AddClip("HE-AAC mp4a.40.5 cbcs", w->he_aac, audio, "qaac");
  AddClip("HE-AACv2 mp4a.40.29 cbcs", w->he_aac_v2, audio, "qaac");
  add_loaded("xHE-AAC mp4a.40.42 clear (decoder log baseline)", w->xhe_aac, "", Expect::kReport);
  AddClip("xHE-AAC mp4a.40.42 cbcs", w->xhe_aac, audio, "qusa");
  AddClip("xHE-AAC mp4a.40.42 cbcs, wrong key (control)", w->xhe_aac, audio, "qusa", Expect::kGarbage, 0x5a);
  AddClip("AC-3 cbcs, whole sample", w->ac3, audio, "qac3");
  // Apple's AC-3/E-AC-3 decryption fails with a subsample layout, exactly
  // like a wrong key; whole-sample (CMAF) works.
  AddClip("AC-3 cbcs, clear syncframe headers", w->ac3, syncframes, "qac3", Expect::kFails);
  AddClip("AC-3 cbcs, wrong key (control)", w->ac3, syncframes, "qac3", Expect::kGarbage, 0x5a);
  AddClip("E-AC-3 cbcs, whole sample", w->eac3, audio, "qec3");
  AddClip("E-AC-3 cbcs, clear syncframe headers", w->eac3, syncframes, "qec3", Expect::kFails);
  AddClip("E-AC-3 cbcs, wrong key (control)", w->eac3, syncframes, "qec3", Expect::kGarbage, 0x5a);
  AddClip("E-AC-3 7.1 cbcs, whole sample", w->eac3_71, audio, "qec3");
  AddClip("E-AC-3 7.1 cbcs, whole sample, the file's dec3 given to the renderer", w->eac3_71, audio, "qec3",
          Expect::kPlays, 0, true);
  AddClip("E-AC-3 7.1 cbcs, clear syncframe headers", w->eac3_71, syncframes, "qec3", Expect::kFails);
  // FLAC and Opus as Chromium's MP4 parser gives them (STREAMINFO, OpusHead).
  add_loaded("FLAC fLaC clear", w->flac, "flac", Expect::kPlays);
  AddClip("FLAC fLaC cbcs, whole sample", w->flac, audio, "qflc");
  AddClip("FLAC fLaC cbcs, wrong key (control)", w->flac, audio, "qflc", Expect::kGarbage, 0x5a);
  add_loaded("Opus clear", w->opus, "opus", Expect::kPlays);
  // CoreAudio has no protected Opus decoder (its list has qflc and qlac, no
  // Opus one), so FairPlay can't carry Opus.
  AddClip("Opus cbcs, whole sample", w->opus, audio, "", Expect::kFails);
  // ALAC from Apple's encoder, as Chromium's MP4 parser gives it (the
  // ALACSpecificConfig).
  add_loaded("ALAC alac clear", w->alac, "alac", Expect::kPlays);
  AddClip("ALAC alac cbcs, whole sample", w->alac, audio, "qlac");
  AddClip("ALAC alac cbcs, wrong key (control)", w->alac, audio, "qlac", Expect::kGarbage, 0x5a);
  // PCM, as Safari's AVStreamDataParser makes 'ipcm' and 'fpcm': clear as
  // 'lpcm'; protected the format stays 'enca' (CoreAudio has no protected PCM
  // decoder) and AVSampleBufferAudioRenderer fails with -11800.
  add_loaded("PCM ipcm 16-bit clear", w->ipcm16, "lpcm", Expect::kPlays);
  add_loaded("PCM ipcm 24-bit clear", w->ipcm24, "lpcm", Expect::kPlays);
  add_loaded("PCM fpcm 32-bit float clear", w->fpcm32, "lpcm", Expect::kPlays);
  AddClip("PCM ipcm 16-bit cbcs, whole sample", w->ipcm16, audio, "enca", Expect::kDecodeError);
  AddClip("PCM fpcm 32-bit float cbcs, whole sample", w->fpcm32, audio, "enca", Expect::kDecodeError);

  std::vector<Step> steps;
  steps.push_back(Section("FairPlay license for Axinom's published key"));
  steps.push_back(AcquireLicense());
  for (const auto& clip : w->clips) {
    std::vector<Step> play = PlayClip(clip);
    steps.insert(steps.end(), play.begin(), play.end());
  }
  steps.push_back([w](Done done) {
    size_t controls = 0, tripped = 0;
    for (const ClipResult& r : w->results) {
      if (r.label.rfind("AV1 8-bit av01 cbcs, wrong key ", 0) != 0) continue;
      ++controls;
      tripped += r.evidence.rfind("fails", 0) == 0;
    }
    if (controls) {
      Check(tripped > 0, "AV1: the decoder notices garbage under at least one of the wrong keys",
            Format("%zu of %zu wrong keys gave decode errors or corrupted frames", tripped, controls));
    }
    done();
  });
  Sequence(steps, Finish);
}

// Axinom's v10 CMAF vectors, first media segment of each (byte ranges from
// their HLS playlists): H.264 288p and HEVC 720p, for the layout checks.
NSString* const kAxinomH264 =
    @"https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/video-H264-288-400k-video-avc1.mp4";
NSString* const kAxinomHevc =
    @"https://media.axprod.net/TestVectors/H265/protected_cmaf_1080p_h265_singlekey/video-H265-720-2100k-video-hvc1.mp4";
// DASH-IF multichannel audio test vector (Dolby): 7.1 E-AC-3 at 768 kb/s,
// channel configuration FA01 (L R C LFE Ls Rs Lrs Rrs), channel ID voices.
NSString* const kEac371 =
    @"https://dash.akamaized.net/dash264/TestCasesMCA/dolby/2/1/ChID_voices_71_768_ddp_A.mp4";

bool LoadAll(World* w, std::string* error) {
  NSData* certificate = CachedGet(kCertificateUrl, @"axinom_fairplay.cer", false, error);
  if (!certificate) return false;
  w->certificate = Bytes(certificate);
  if (!LoadChromiumFile(@"bear-640x360-v_frag.mp4", &w->h264, error) ||
      !LoadChromiumFile(@"bear-640x360-v_frag-cbcs.mp4", &w->h264_cbcs_ref, error) ||
      !LoadChromiumFile(@"bear-320x240-v_frag-hevc.mp4", &w->hevc, error) ||
      !LoadChromiumFile(@"glass-blowing2-dolby-vision-profile-5-frag.mp4", &w->dv5_dvh1, error) ||
      !LoadChromiumFile(@"color_pattern_24_dvhe_05_1920x1080-3sec-frag-cenc.mp4", &w->dv5_dvhe, error) ||
      !LoadChromiumFile(@"bear-av1.mp4", &w->av1, error) ||
      !LoadChromiumFile(@"bear-av1-cenc.mp4", &w->av1_ref, error) ||
      !LoadChromiumFile(@"bear-av1-320x180-10bit.mp4", &w->av1_10bit, error) ||
      !LoadChromiumFile(@"bear-av1-320x180-10bit-cenc.mp4", &w->av1_10bit_ref, error) ||
      !LoadChromiumFile(@"noise-xhe-aac.mp4", &w->xhe_aac, error) ||
      !LoadChromiumFile(@"bear-ac3-only-frag.mp4", &w->ac3, error) ||
      !LoadChromiumFile(@"bear-eac3-only-frag.mp4", &w->eac3, error) ||
      !LoadChromiumFile(@"bear-flac_frag.mp4", &w->flac, error) ||
      !LoadChromiumFile(@"bear-opus.mp4", &w->opus, error) ||
      !EncodeAac(kAudioFormatMPEG4AAC, 3, &w->aac_lc, error) ||
      !EncodeAac(kAudioFormatMPEG4AAC_HE, 3, &w->he_aac, error) ||
      !EncodeAac(kAudioFormatMPEG4AAC_HE_V2, 3, &w->he_aac_v2, error) ||
      !EncodeAac(kAudioFormatAppleLossless, 3, &w->alac, error)) {
    return false;
  }
  MakePcm(false, 16, 2, &w->ipcm16);
  MakePcm(false, 24, 2, &w->ipcm24);
  MakePcm(true, 32, 2, &w->fpcm32);
  // Chromium's cenc test files decrypted with its test key: the AV1 ones
  // must equal Chromium's clear files (SelfTests) and give Shaka's layout;
  // the Dolby Vision dvhe one is the only dvhe stream in the test data.
  for (auto [ref, layout] : {std::pair{&w->av1_ref, &w->av1_layout}, std::pair{&w->av1_10bit_ref, &w->av1_10bit_layout},
                             std::pair{&w->dv5_dvhe, &w->dv5_dvhe_layout}}) {
    Media clear;
    if (!DecryptReference(*ref, FromHex(kChromiumKeyHex), &clear, layout, error)) return false;
    *ref = clear;
  }
  NSData* eac3 = CachedGet(kEac371, @"dashif_ChID_voices_71_768_ddp_A.mp4", false, error);
  if (!eac3 || !ParseFile(eac3, "ChID_voices_71_768_ddp_A.mp4", &w->eac3_71_full, error)) return false;
  // Playback uses the first 6 s of the 30 s stream.
  w->eac3_71 = w->eac3_71_full;
  auto& s = w->eac3_71.samples;
  s.erase(std::remove_if(s.begin(), s.end(),
                         [&](const ft::Sample& x) { return x.pts >= int64_t(6 * w->eac3_71.info.timescale); }),
          s.end());
  auto load_segment = [&](NSString* url, uint64_t init_length, uint64_t offset, uint64_t length, NSString* name,
                          Media* media) {
    NSData* init = CachedRange(url, [name stringByAppendingString:@"_init"], 0, init_length, error);
    NSData* segment = init ? CachedRange(url, [name stringByAppendingString:@"_1"], offset, length, error) : nil;
    return segment && ft::ParseInitSegment(Bytes(init), &media->info, error) &&
           ft::ParseMediaSegment(Bytes(segment), media->info, &media->samples, error);
  };
  return load_segment(kAxinomH264, 1532, 3040, 19101, @"axinom_h264_288", &w->axinom_h264) &&
         load_segment(kAxinomHevc, 3625, 5133, 41261, @"axinom_hevc_720", &w->axinom_hevc);
}

}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    g_start = CFAbsoluteTimeGetCurrent();
    setvbuf(stdout, nullptr, _IOLBF, 0);
    static World world;
    g_world = &world;
    StartWatchdog();
    g_cache_dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"parc-fairplay-cache"];
    for (int i = 1; i < argc; ++i) {
      std::string flag = argv[i];
      if (flag == "--muted") {
        g_muted = true;
        continue;
      }
      if (i + 1 >= argc) break;
      if (flag == "--cache") g_cache_dir = @(argv[i + 1]);
      else if (flag == "--time-limit") g_time_limit = atof(argv[i + 1]);
      else if (flag == "--only") g_only = argv[i + 1];
      ++i;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:g_cache_dir withIntermediateDirectories:YES attributes:nil
                                                    error:nil];
    world.key_id = FromHex(kKeyIdHex);
    world.key = Bytes([[NSData alloc] initWithBase64EncodedString:@(kKeyBase64) options:0]);

    NSApplication* app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Parc FairPlay codec proof";
    window.releasedWhenClosed = NO;
    [window center];
    world.host = window.contentView;
    world.host.wantsLayer = YES;
    world.host.layer.backgroundColor = NSColor.darkGrayColor.CGColor;
    [window makeKeyAndOrderFront:nil];
    [app activateIgnoringOtherApps:YES];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      std::string error;
      bool ok = LoadAll(&world, &error);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!Check(ok, "download and parse the test media", error)) Finish();
        RunAll();
      });
    });
    [app run];
  }
  return 0;
}

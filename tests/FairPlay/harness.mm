// FairPlay M0 proof: the engine-independent key session and renderer in
// Engine/ParcNative/fairplay play Axinom's public "CMAF H264 SingleKey (cbcs)"
// test vector with a real FairPlay license exchange, in a visible window.
// Protected video can't be captured, so playback is proven through the
// synchronizer clock, renderer status and AVFoundation's frame metrics.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_bitstream.h"
#include "fairplay_init_data.h"
#include "fairplay_key_session.h"
#include "fairplay_renderer.h"
#include "fmp4_parser.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

namespace fp = parc::fairplay;
namespace ft = parc::fairplay::test;

namespace {

// Axinom public test vectors v10, "CMAF H264 SingleKey (cbcs)": the FairPlay
// player link in https://github.com/Axinom/public-test-vectors (README) gives
// the license URL, certificate URL and this entitlement token, which the
// license service takes in the X-AxDRM-Message header with the raw SPC as the
// POST body; it answers with the raw CKC.
NSString* const kProtectedBase = @"https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/";
NSString* const kClearBase = @"https://media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/";
NSString* const kLicenseUrl = @"https://drm-fairplay-licensing.axprod.net/AcquireLicense";
NSString* const kCertificateUrl = @"https://tools.axinom.com/FPScert/fairplay.cer";
NSString* const kToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjMwMmY4MGRkLTQxMWUtNDg4Ni1iY2E1LWJiMWY4MDE4YTAyNCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiMWVYeWhGWmNGVjljemNtZG5BREpMdz09IiwKICAgICAgICAiaXYiOiAiZC8wWWlhcjBGRHNJVlVpendQbGJtZz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.5VxBJQsgGVissi9WCNpT7IoykEAmxaEcif6F3SeLvzU";
// EXT-X-KEY URI in the vector's HLS playlists (KEYFORMAT com.apple.streamingkeydelivery).
const char* const kSkd = "skd://302f80dd-411e-4886-bca5-bb1f8018a024:77FD1889AAF4143B085548B3C0F95B9A";
// "CMAF H264 MultiKey (cbcs)": three keys (audio, SD video, HD video) under
// one token, the shape of Netflix's three-key FairPlay licenses.
NSString* const kMultiKeyBase = @"https://media.axprod.net/TestVectors/MultiKey/Cmaf_h264_1080p_cbcs/";
NSString* const kMultiKeyToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogImI1NGVjOTE0LTE5MmQtNGVhMS1hYzE5LWY0MjllYjQ5ODI2OCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiUldKemlSUDRqQkhjd2tJYzRTd1h5QT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9LAogICAgICB7CiAgICAgICAgImlkIjogImM4M2M0ZWE4LTBmMmEtNDUyMy04NTFjLWZiZWNjZGMwZjIwMiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiSHFoK1BCNVU1OStvclMzVGVZQ2lOUT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9LAogICAgICB7CiAgICAgICAgImlkIjogImM4NjhjNzAyLWM3MWItNDA2NC1hZTJiLWMyNGY3Y2MxMDc5MiIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiLy9nM2pmdktjUlliaHBwRW04c3BqUT09IiwKICAgICAgICAiaXYiOiAiT3VrQWE1L3ZtTWlOQ05jamlsL09QQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.09GZO7pokr1k24NXKxIV7qyEZ2lhtbpfMoKfP7vzSns";
// "CMAF H265 SingleKey" from the same table, for the HEVC check.
NSString* const kHevcBase = @"https://media.axprod.net/TestVectors/H265/protected_cmaf_1080p_h265_singlekey/";
NSString* const kHevcToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogImFiY2M0NGU1LWMxMjItNDVhYi1hYzgwLWE1YjM1MjJhMGEzMSIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAibGs1aERneXl1NXl6a3QzMWlVWmF4UT09IiwKICAgICAgICAiaXYiOiAiczhnNHNFemp4Yml2R1pDVGxxU3pQQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.lAwTqoU-rkmyk8QtSn0RrsleMefe2Y5-E5YGoala7yM";
const char* const kHevcSkd = "skd://abcc44e5-c122-45ab-ac80-a5b3522a0a31:B3C838B04CE3C5B8AF19909396A4B33C";

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
  Log("%s %s%s%s", ok ? "PASS" : "FAIL", name.c_str(), detail.empty() ? "" : " -- ",
      detail.c_str());
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

std::vector<uint8_t> Bytes(const std::string& s) { return std::vector<uint8_t>(s.begin(), s.end()); }

NSData* Data(const std::vector<uint8_t>& v) { return [NSData dataWithBytes:v.data() length:v.size()]; }

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

// Blocking; called off the main thread only.
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
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  return result;
}

NSString* g_cache_dir = nil;

NSData* CachedGet(NSString* url, uint64_t offset, uint64_t length, std::string* error) {
  NSString* key = [NSString stringWithFormat:@"%@_%llu_%llu", url, offset, length];
  NSCharacterSet* bad = [NSCharacterSet characterSetWithCharactersInString:@":/?&=%"];
  key = [[key componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
  NSString* path = [g_cache_dir stringByAppendingPathComponent:key];
  if (NSData* cached = [NSData dataWithContentsOfFile:path]) return cached;
  NSDictionary* headers =
      length ? @{@"Range" : [NSString stringWithFormat:@"bytes=%llu-%llu", offset, offset + length - 1]}
             : @{};
  Http http = Fetch(url, @"GET", nil, headers);
  if (http.status != 200 && http.status != 206) {
    *error = Format("GET %s -> %ld %s", url.UTF8String, http.status, http.error.c_str());
    return nil;
  }
  if (length && http.body.length != length) {
    *error = Format("GET %s returned %lu bytes, expected %llu", url.UTF8String,
                    (unsigned long)http.body.length, length);
    return nil;
  }
  [http.body writeToFile:path atomically:YES];
  return http.body;
}

// ------------------------------------------------------------ media loading

struct Range {
  std::string uri;
  uint64_t offset = 0;
  uint64_t length = 0;
};

struct Playlist {
  Range init;
  std::vector<Range> segments;
};

bool ParsePlaylist(NSString* text, Playlist* playlist) {
  uint64_t next_offset = 0;
  std::string last_uri;
  Range pending;
  bool have_range = false;
  for (NSString* raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    std::string line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].UTF8String;
    if (line.rfind("#EXT-X-MAP:", 0) == 0) {
      size_t uri = line.find("URI=\"") + 5;
      playlist->init.uri = line.substr(uri, line.find('"', uri) - uri);
      size_t br = line.find("BYTERANGE=\"");
      if (br != std::string::npos) {
        std::string v = line.substr(br + 11, line.find('"', br + 11) - br - 11);
        playlist->init.length = std::stoull(v.substr(0, v.find('@')));
        playlist->init.offset = std::stoull(v.substr(v.find('@') + 1));
      }
    } else if (line.rfind("#EXT-X-BYTERANGE:", 0) == 0) {
      std::string v = line.substr(17);
      pending.length = std::stoull(v.substr(0, v.find('@')));
      pending.offset = v.find('@') != std::string::npos ? std::stoull(v.substr(v.find('@') + 1))
                                                        : next_offset;
      have_range = true;
    } else if (!line.empty() && line[0] != '#') {
      pending.uri = line;
      if (!have_range) pending.offset = pending.length = 0;
      next_offset = pending.offset + pending.length;
      playlist->segments.push_back(pending);
      have_range = false;
    }
  }
  return !playlist->init.uri.empty() && !playlist->segments.empty();
}

struct Media {
  ft::TrackInfo info;
  std::vector<std::vector<ft::Sample>> segments;
};

bool LoadMedia(NSString* base, NSString* playlist_name, int count, Media* media, std::string* error) {
  NSData* text_data = CachedGet([base stringByAppendingString:playlist_name], 0, 0, error);
  if (!text_data) return false;
  Playlist playlist;
  if (!ParsePlaylist([[NSString alloc] initWithData:text_data encoding:NSUTF8StringEncoding], &playlist)) {
    *error = "unparsable playlist " + std::string(playlist_name.UTF8String);
    return false;
  }
  NSData* init = CachedGet([base stringByAppendingString:@(playlist.init.uri.c_str())],
                           playlist.init.offset, playlist.init.length, error);
  if (!init || !ft::ParseInitSegment(Bytes(init), &media->info, error)) return false;
  for (int i = 0; i < count && i < int(playlist.segments.size()); ++i) {
    const Range& r = playlist.segments[i];
    NSData* segment = CachedGet([base stringByAppendingString:@(r.uri.c_str())], r.offset, r.length, error);
    std::vector<ft::Sample> samples;
    if (!segment || !ft::ParseMediaSegment(Bytes(segment), media->info, &samples, error)) return false;
    media->segments.push_back(std::move(samples));
  }
  return true;
}

// Chromium's own media test files (media/test/data at the pinned tag): one
// fragmented MP4 holding the init segment and its fragments.
NSString* const kChromiumTestData =
    @"https://chromium.googlesource.com/chromium/src/+/refs/tags/156.0.8078.48/media/test/data/";

bool LoadChromiumFile(NSString* name, Media* media, std::string* error) {
  NSString* path = [g_cache_dir stringByAppendingPathComponent:[@"chromium_" stringByAppendingString:name]];
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (!data) {
    Http http = Fetch([NSString stringWithFormat:@"%@%@?format=TEXT", kChromiumTestData, name], @"GET", nil, @{});
    data = http.status == 200 ? [[NSData alloc] initWithBase64EncodedData:http.body
                                                                  options:NSDataBase64DecodingIgnoreUnknownCharacters]
                              : nil;
    if (!data) {
      *error = Format("GET %s -> %ld", name.UTF8String, http.status);
      return false;
    }
    [data writeToFile:path atomically:YES];
  }
  std::vector<ft::Sample> samples;
  if (!ft::ParseInitSegment(Bytes(data), &media->info, error) ||
      !ft::ParseMediaSegment(Bytes(data), media->info, &samples, error) ||
      (samples.empty() && !ft::ParseProgressiveFile(Bytes(data), media->info, &samples, error))) {
    *error = std::string(name.UTF8String) + ": " + *error;
    return false;
  }
  media->segments.push_back(std::move(samples));
  return true;
}

struct EncodeState {
  double phase_l = 0;
  double phase_r = 0;
  int64_t remaining = 0;
  std::vector<float> buffer;
};

OSStatus ProvidePcm(AudioConverterRef, UInt32* packets, AudioBufferList* data,
                    AudioStreamPacketDescription**, void* user) {
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

// HE-AAC / HE-AACv2 track encoded with AudioToolbox (no such MP4 sample is in
// Chromium's test data): 44.1 kHz stereo tones, packets and the encoder's
// AudioSpecificConfig, as an MP4 parser would hand them over.
bool EncodeAac(AudioFormatID format, double seconds, Media* media, std::string* error) {
  AudioStreamBasicDescription in = {44100, kAudioFormatLinearPCM,
                                    kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
  AudioStreamBasicDescription out = {};
  out.mFormatID = format;
  out.mSampleRate = 44100;
  out.mChannelsPerFrame = 2;
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
  std::vector<ft::Sample> samples;
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
      sample.duration = out.mFramesPerPacket;
      sample.is_keyframe = true;
      pts += out.mFramesPerPacket;
      samples.push_back(std::move(sample));
    }
  }
  UInt32 cookie_size = 0;
  AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie, &cookie_size, nullptr);
  std::vector<uint8_t> cookie(cookie_size);
  AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie, &cookie_size, cookie.data());
  AudioConverterDispose(converter);
  media->info.is_video = false;
  media->info.timescale = uint32_t(out.mSampleRate);
  media->info.sample_entry = media->info.original_format = fp::FourCC('m', 'p', '4', 'a');
  media->info.channels = 2;
  media->info.sample_rate = uint32_t(out.mSampleRate);
  media->info.codec_config = ft::AscFromDescriptor(cookie.data(), cookie.size());
  if (media->info.codec_config.empty() || samples.empty()) {
    *error = Format("encoder produced %zu packets, %zu-byte cookie", samples.size(), cookie.size());
    return false;
  }
  media->segments.push_back(std::move(samples));
  return true;
}

// -------------------------------------------------------- async sequencing

using Done = std::function<void()>;
using Step = std::function<void(Done)>;

void After(double seconds, Done done) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(seconds * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
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

// Runs |done| once, either from |attempt| or after |timeout| seconds.
std::function<void(bool)> Once(double timeout, const std::string& label, std::function<void(bool)> done) {
  auto fired = std::make_shared<bool>(false);
  auto finish = [fired, done](bool ok) {
    if (*fired) return;
    *fired = true;
    done(ok);
  };
  After(timeout, [fired, finish, label] {
    if (!*fired) {
      Check(false, label + " within time limit");
      finish(false);
    }
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

// ----------------------------------------------------------- license flow

std::string KeysText(const std::vector<fp::KeyInfo>& keys) {
  std::string text;
  for (const fp::KeyInfo& key : keys) {
    if (!text.empty()) text += ", ";
    std::string id = key.key_id.size() == 16 ? ft::Hex(key.key_id)
                                             : std::string(key.key_id.begin(), key.key_id.end());
    text += id + "=" + fp::KeyStatusName(key.status);
    if (key.system_code) text += Format("(%u)", key.system_code);
  }
  return text;
}

class LicenseClient : public fp::FairPlayCdmClient {
 public:
  LicenseClient(std::string name, NSString* token) : name_(std::move(name)), token_(token) {}

  fp::FairPlayCdm* cdm = nullptr;
  bool json = false;
  // With |hold|, messages wait in held_* until Respond() is called.
  bool hold = false;
  std::string held_session;
  std::vector<uint8_t> held_message;
  std::function<void()> on_message;
  int messages = 0;
  int keys_events = 0;
  bool closed = false;
  std::vector<fp::KeyInfo> keys;
  std::function<void(bool, const std::string&)> on_update;

  void OnSessionMessage(const std::string& session_id,
                        fp::MessageType type,
                        const std::vector<uint8_t>& message) override {
    ++messages;
    Log("%s: message %s type=%d %zu bytes%s", name_.c_str(), session_id.c_str(), int(type),
        message.size(), json ? " (JSON)" : " (raw SPC)");
    if (json) {
      Log("%s: message JSON %.*s...", name_.c_str(), int(std::min<size_t>(message.size(), 120)),
          reinterpret_cast<const char*>(message.data()));
    }
    if (hold) {
      held_session = session_id;
      held_message = message;
      if (on_message) on_message();
      return;
    }
    Respond(session_id, message);
  }

  // The page's license round trip: POST each SPC, then update().
  void Respond(const std::string& session_id, const std::vector<uint8_t>& message) {
    NSData* body = Data(message);
    std::string session = session_id;  // Blocks capture reference parameters by reference.
    std::string name = name_;
    bool is_json = json;
    fp::FairPlayCdm* target = cdm;
    auto on_update_copy = on_update;
    NSString* token = token_;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      std::vector<uint8_t> response;
      std::string failure;
      if (!is_json) {
        response = Post(body, name, token, &failure);
      } else {
        NSArray* entries = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        NSMutableArray* answers = [NSMutableArray array];
        for (NSDictionary* entry in entries) {
          NSData* spc = [[NSData alloc] initWithBase64EncodedString:entry[@"payload"] options:0];
          std::vector<uint8_t> ckc = Post(spc, name, token, &failure);
          if (ckc.empty()) {
            [answers addObject:@{@"keyID" : entry[@"keyID"], @"error" : @(1)}];
          } else {
            [answers addObject:@{@"keyID" : entry[@"keyID"],
                                 @"payload" : [Data(ckc) base64EncodedStringWithOptions:0]}];
          }
        }
        response = Bytes([NSJSONSerialization dataWithJSONObject:answers options:0 error:nil]);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (response.empty()) {
          if (on_update_copy) on_update_copy(false, "license server: " + failure);
          return;
        }
        target->UpdateSession(session, response, [on_update_copy, name](const fp::Result& result) {
          Log("%s: update -> %s %s", name.c_str(), result.ok() ? "resolved" : "rejected",
              result.message.c_str());
          if (on_update_copy) on_update_copy(result.ok(), result.message);
        });
      });
    });
  }

  void OnSessionKeysChange(const std::string& session_id,
                           bool has_additional_usable_key,
                           const std::vector<fp::KeyInfo>& new_keys) override {
    ++keys_events;
    keys = new_keys;
    Log("%s: keys change %s additional=%d [%s]", name_.c_str(), session_id.c_str(),
        has_additional_usable_key, KeysText(new_keys).c_str());
  }

  void OnSessionClosed(const std::string& session_id) override {
    closed = true;
    Log("%s: session %s closed", name_.c_str(), session_id.c_str());
  }

 private:
  static std::vector<uint8_t> Post(NSData* spc, const std::string& name, NSString* token,
                                   std::string* failure) {
    Http http = Fetch(kLicenseUrl, @"POST", spc,
                      @{@"X-AxDRM-Message" : token, @"Content-Type" : @"application/octet-stream"});
    Log("%s: POST SPC %lu bytes -> HTTP %ld, %lu bytes%s%s", name.c_str(),
        (unsigned long)spc.length, http.status, (unsigned long)http.body.length,
        http.error.empty() ? "" : " error ", http.error.c_str());
    if (http.status != 200) {
      NSString* message = http.headers[@"X-AxDRM-ErrorMessage"];
      *failure = Format("HTTP %ld %s", http.status, message.UTF8String ?: "");
      return {};
    }
    return Bytes(http.body);
  }

  std::string name_;
  NSString* token_;
};

struct KeySystem {
  std::unique_ptr<LicenseClient> client;
  std::unique_ptr<fp::FairPlayCdm> cdm;
  std::string session;
};

std::vector<uint8_t> g_certificate;
std::vector<uint8_t> g_key_id;

std::unique_ptr<KeySystem> MakeKeySystem(const std::string& name, NSString* token = kToken) {
  auto ks = std::make_unique<KeySystem>();
  ks->client = std::make_unique<LicenseClient>(name, token);
  ks->cdm = std::make_unique<fp::FairPlayCdm>(ks->client.get(), MainPoster());
  ks->client->cdm = ks->cdm.get();
  bool resolved = false;
  ks->cdm->SetServerCertificate(g_certificate, [&](const fp::Result& r) { resolved = r.ok(); });
  Check(resolved, name + ": SetServerCertificate resolves");
  return ks;
}

// Session from |init_data|, the page-side license round trip, then a check
// that the renderer can find a key for the content's key ID.
void AcquireLicense(KeySystem* ks, fp::InitDataType type, std::vector<uint8_t> init_data,
                    const std::string& label, std::function<void(bool)> done,
                    std::vector<std::vector<uint8_t>> key_ids = {g_key_id}) {
  auto finish = Once(30, label + ": license", done);
  ks->client->json = type == fp::InitDataType::kCenc || type == fp::InitDataType::kKeyIds;
  ks->client->on_update = [ks, label, finish, key_ids](bool ok, const std::string& detail) {
    Check(ok, label + ": update resolves after the license server round trip", detail);
    bool usable = true;
    std::string names;
    for (const auto& key_id : key_ids) {
      usable &= ks->cdm->HasUsableKey(key_id);
      names += (names.empty() ? "" : ", ") + ft::Hex(key_id);
    }
    Check(usable, label + ": renderer-side key lookup finds every content key (" + names + ")",
          KeysText(ks->client->keys));
    finish(ok && usable);
  };
  ks->cdm->CreateSessionAndGenerateRequest(
      type, std::move(init_data), [ks, label, finish](const fp::Result& r, const std::string& id) {
        ks->session = id;
        Check(r.ok(), label + ": generateRequest resolves with a session ID",
              r.ok() ? id : r.message);
        if (!r.ok()) finish(false);
      });
}

// ------------------------------------------------------------------ player

enum class Framing { kChromium, kIso };

using SegmentList = std::vector<const std::vector<ft::Sample>*>;

fp::VideoConfig VideoConfigFor(const ft::TrackInfo& info, Framing framing) {
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
  vc.extra_data = info.codec_config;
  vc.dolby_vision_config = info.dolby_vision_config;
  // Chromium hands AV1 over as stored, everything else as Annex B.
  vc.format = framing == Framing::kChromium && vc.codec != fp::VideoCodec::kAV1
                  ? fp::BitstreamFormat::kAnnexB
                  : fp::BitstreamFormat::kLengthPrefixed;
  vc.coded_width = info.width;
  vc.coded_height = info.height;
  vc.encryption = info.encryption;
  return vc;
}

fp::AudioConfig AudioConfigFor(const ft::TrackInfo& info, Framing framing) {
  fp::AudioConfig ac;
  ac.codec = fp::AudioCodec::kAAC;
  ac.extra_data = info.codec_config;
  ac.framing = framing == Framing::kChromium && ft::AacObjectType(info.codec_config, true) <= 4
                   ? fp::AudioFraming::kADTS
                   : fp::AudioFraming::kRaw;
  ac.sample_rate = int32_t(info.sample_rate);
  ac.channels = info.channels;
  ac.encryption = info.encryption;
  return ac;
}

class Player : public fp::FairPlayRendererClient {
 public:
  // Either stream may be null (single-stream codec checks).
  // |cdm_first| calls SetCdm before Initialize, Chromium's order when
  // MediaKeys were attached before playback.
  Player(std::string name, Framing framing, const Media* video, const Media* audio,
         fp::FairPlayCdm* cdm, NSView* host, bool cdm_first = false)
      : name_(std::move(name)),
        framing_(framing),
        has_video_(video != nullptr),
        has_audio_(audio != nullptr),
        video_info_(video ? video->info : ft::TrackInfo()),
        audio_info_(audio ? audio->info : ft::TrackInfo()),
        renderer_(this, MainPoster()),
        host_(host) {
    std::optional<fp::VideoConfig> vc;
    if (has_video_) vc = VideoConfigFor(video_info_, framing);
    std::optional<fp::AudioConfig> ac;
    if (has_audio_) ac = AudioConfigFor(audio_info_, framing);
    fp::Result result = fp::Result::Ok();
    if (cdm_first) {
      result = renderer_.SetCdm(cdm);
      Check(result.ok(), name_ + ": SetCdm before Initialize is accepted", result.message);
    }
    result = renderer_.Initialize(vc, ac);
    Check(result.ok(), name_ + ": renderer Initialize", result.message);
    result = renderer_.SetCdm(cdm);
    Check(result.ok(), name_ + (cdm_first ? ": SetCdm with the same CDM after Initialize is a no-op"
                                          : ": SetCdm joins the display layer and audio renderer to the "
                                            "key system's AVContentKeySession as content key recipients"),
          result.message);
    layer_ = (__bridge AVSampleBufferDisplayLayer*)renderer_.display_layer();
    if (has_video_) Check(layer_ != nil, name_ + ": display layer exists");
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer_.frame = host_.layer.bounds;
    layer_.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer_.backgroundColor = NSColor.blackColor.CGColor;
    [host_.layer addSublayer:layer_];
    [CATransaction commit];
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
  const std::string& name() const { return name_; }
  bool has_video() const { return has_video_; }
  bool has_audio() const { return has_audio_; }
  std::vector<std::string> errors;
  int waiting_events = 0;
  int waiting_results = 0;
  int enqueued = 0;
  bool ended = false;
  bool have_enough = false;
  int32_t natural_width = 0;
  int32_t natural_height = 0;
  std::function<void()> on_have_enough;
  std::function<void()> on_have_nothing;
  std::function<void()> on_ended;
  int underflows = 0;

  double Time() { return renderer_.GetMediaTime().InSeconds(); }

  void SetFeeds(SegmentList video, SegmentList audio, bool end_of_stream) {
    video_feed_ = Feed{std::move(video), 0, 0, end_of_stream, false};
    audio_feed_ = Feed{std::move(audio), 0, 0, end_of_stream, false};
  }

  // More data arrives (as from the network): append and push it.
  void AppendFeeds(const SegmentList& video, const SegmentList& audio) {
    video_feed_.segments.insert(video_feed_.segments.end(), video.begin(), video.end());
    audio_feed_.segments.insert(audio_feed_.segments.end(), audio.begin(), audio.end());
    Pump(fp::StreamType::kVideo);
    Pump(fp::StreamType::kAudio);
  }

  void LogStatus(const char* why) {
    fp::RendererStatus s = renderer_.GetStatus();
    Log("%s %s: t=%.3f rate=%.2f video=%s audio=%s enq v/a=%llu/%llu protected=%llu "
        "enough v/a=%d/%d ready=%d obscured=%d decodeFail=%llu %s%s",
        name_.c_str(), why, s.time.InSeconds(), s.rate, StatusName(s.video), StatusName(s.audio),
        s.video_enqueued, s.audio_enqueued, s.protected_enqueued,
        s.video_has_enough, s.audio_has_enough, s.video_ready_for_display, s.output_obscured,
        s.decode_failures, s.video_error.c_str(), s.audio_error.c_str());
  }

  // media::RendererClient side.
  void OnNeedData(fp::StreamType stream) override { Pump(stream); }
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
    errors.push_back(Format("%d: %s", int(error), description.c_str()));
    Log("%s: ERROR %d %s", name_.c_str(), int(error), description.c_str());
  }
  void OnVideoNaturalSizeChange(int32_t width, int32_t height) override {
    natural_width = width;
    natural_height = height;
  }
  void OnBufferingStateChange(bool enough) override {
    have_enough = enough;
    Log("%s: buffering %s at t=%.3f", name_.c_str(), enough ? "HAVE_ENOUGH" : "HAVE_NOTHING", Time());
    if (enough && on_have_enough) {
      auto f = std::move(on_have_enough);
      on_have_enough = nullptr;
      f();
    }
    if (!enough) {
      ++underflows;
      if (on_have_nothing) {
        auto f = std::move(on_have_nothing);
        on_have_nothing = nullptr;
        f();
      }
    }
  }

 private:
  struct Feed {
    SegmentList segments;
    size_t segment = 0;
    size_t index = 0;
    bool end_of_stream = false;
    bool end_sent = false;
  };

  void Pump(fp::StreamType stream) {
    if (!(stream == fp::StreamType::kVideo ? has_video_ : has_audio_)) return;
    Feed& feed = stream == fp::StreamType::kVideo ? video_feed_ : audio_feed_;
    const ft::TrackInfo& info = stream == fp::StreamType::kVideo ? video_info_ : audio_info_;
    while (renderer_.IsReadyForMoreData(stream)) {
      while (feed.segment < feed.segments.size() && feed.index >= feed.segments[feed.segment]->size()) {
        ++feed.segment;
        feed.index = 0;
      }
      if (feed.segment >= feed.segments.size()) {
        if (feed.end_of_stream && !feed.end_sent) {
          feed.end_sent = true;
          renderer_.SetEndOfStream(stream);
        }
        return;
      }
      const ft::Sample& sample = (*feed.segments[feed.segment])[feed.index++];
      if (sample.pts + sample.duration <= 0) {
        continue;  // Before zero: MSE's append window drops it in Chromium.
      }
      fp::EncodedSample buffer = framing_ == Framing::kChromium
                                     ? ft::ChromiumBuffer(info, sample, &storage_, &decrypt_storage_)
                                     : ft::IsoBuffer(info, sample);
      fp::EnqueueResult result = renderer_.Enqueue(stream, buffer);
      if (result == fp::EnqueueResult::kWaitingForKey) {
        ++waiting_results;
        return;
      }
      if (result == fp::EnqueueResult::kRejected) {
        errors.push_back("enqueue rejected");
        return;
      }
      ++enqueued;
    }
  }

  std::string name_;
  Framing framing_;
  bool has_video_;
  bool has_audio_;
  ft::TrackInfo video_info_;
  ft::TrackInfo audio_info_;
  fp::FairPlayRenderer renderer_;
  NSView* host_;
  AVSampleBufferDisplayLayer* layer_ = nil;
  dispatch_source_t monitor_ = nil;
  Feed video_feed_;
  Feed audio_feed_;
  std::vector<uint8_t> storage_;
  fp::DecryptInfo decrypt_storage_;
};

SegmentList Segments(const Media& media, size_t first, size_t end) {
  SegmentList list;
  for (size_t i = first; i < end && i < media.segments.size(); ++i) list.push_back(&media.segments[i]);
  return list;
}

// Flush, feed from |first| segment, start at |time|, wait for HAVE_ENOUGH,
// then play at |rate|.
Step StartAt(std::shared_ptr<Player> player, const Media* video, const Media* audio, size_t first,
             size_t end, double time, double rate, bool end_of_stream) {
  return [=](Done done) {
    player->renderer().Flush([=] {
      player->SetFeeds(Segments(*video, first, end), Segments(*audio, first, end), end_of_stream);
      player->have_enough = false;
      auto go = Once(10, player->name() + Format(": HAVE_ENOUGH after start at %.1fs", time),
                     [=](bool) {
                       player->renderer().SetPlaybackRate(rate);
                       Log("%s: playing at rate %.2f from t=%.3f", player->name().c_str(), rate,
                           player->Time());
                       done();
                     });
      player->on_have_enough = [go] { go(true); };
      player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(int64_t(time * 1e6)));
    });
  };
}

void CheckHealthy(Player& player, const std::string& label) {
  fp::RendererStatus s = player.renderer().GetStatus();
  if (player.has_video()) {
    Check(s.video == fp::RenderingStatus::kRendering, label + ": video renderer status is rendering",
          StatusName(s.video) + std::string(" ") + s.video_error);
  }
  if (player.has_audio()) {
    Check(s.audio == fp::RenderingStatus::kRendering, label + ": audio renderer status is rendering",
          StatusName(s.audio) + std::string(" ") + s.audio_error);
  }
  Check(s.decode_failures == 0 && player.errors.empty(),
        label + ": no decode, key or enqueue errors",
        player.errors.empty() ? Format("decode failures %llu", s.decode_failures) : player.errors.front());
  // Screen capture or an unprotected display makes AVFoundation obscure
  // protected output; that's protection working, not a playback failure.
  if (s.output_obscured) {
    Log("%s: NOTE output obscured for insufficient external protection (screen capture or display)",
        label.c_str());
  }
}

// Plays for |seconds| and checks the synchronizer clock moved by rate * seconds.
Step Run(std::shared_ptr<Player> player, double seconds, double rate, const std::string& label) {
  return [=](Done done) {
    double t0 = player->Time();
    double wall0 = CFAbsoluteTimeGetCurrent();
    After(seconds, [=] {
      double t1 = player->Time();
      double wall = CFAbsoluteTimeGetCurrent() - wall0;
      double expected = wall * rate;
      double tolerance = rate == 0 ? 0.01 : 0.35;
      player->LogStatus(label.c_str());
      Check(std::fabs((t1 - t0) - expected) <= tolerance,
            label + Format(": media time %.3f -> %.3f (moved %.3fs over %.3fs wall at rate %.2f)",
                           t0, t1, t1 - t0, wall, rate));
      if (rate != 0) CheckHealthy(*player, label);
      done();
    });
  };
}

Step Metrics(std::shared_ptr<Player> player, const std::string& label, int64_t min_frames,
             std::shared_ptr<int64_t> previous) {
  return [=](Done done) {
    player->renderer().LoadVideoMetrics([=](const fp::VideoMetrics& m) {
      int64_t added = m.total_frames - *previous;
      *previous = m.total_frames;
      Check(m.available && added >= min_frames && m.corrupted_frames == 0,
            label + Format(": AVFoundation video metrics total=%lld (+%lld) dropped=%lld "
                           "corrupted=%lld optimized=%lld delay=%.3fs",
                           m.total_frames, added, m.dropped_frames, m.corrupted_frames,
                           m.optimized_composited_frames, m.accumulated_frame_delay));
      done();
    });
  };
}

// -------------------------------------------------------------- self tests

void SelfTests(const Media& video, const Media& audio) {
  Log("== self tests (offline, on the downloaded vector)");
  const ft::TrackInfo& v = video.info;
  const ft::TrackInfo& a = audio.info;
  Check(ft::FourCCString(v.sample_entry) == "encv" && ft::FourCCString(v.original_format) == "avc1" &&
            ft::FourCCString(v.scheme_type) == "cbcs",
        "parser: video sample entry encv/avc1/cbcs",
        Format("%ux%u timescale %u", v.width, v.height, v.timescale));
  Check(ft::FourCCString(a.sample_entry) == "enca" && ft::FourCCString(a.original_format) == "mp4a",
        "parser: audio sample entry enca/mp4a",
        Format("%u Hz %u ch, ASC %s, elst media_time %lld", a.sample_rate, a.channels,
               ft::Hex(a.codec_config).c_str(), a.edit_media_time));
  Check(v.encryption.default_key_id == g_key_id && v.encryption.default_constant_iv.size() == 16 &&
            v.encryption.default_pattern.crypt_byte_block == 1 &&
            v.encryption.default_pattern.skip_byte_block == 9,
        "parser: video tenc KID, 1:9 pattern, 16-byte constant IV",
        "IV " + ft::Hex(v.encryption.default_constant_iv));
  Check(a.encryption.default_pattern.crypt_byte_block == 0 &&
            a.encryption.default_pattern.skip_byte_block == 0,
        "parser: audio tenc pattern 0:0 (whole-block encryption)");

  // The core's box builders reproduce the file's protection boxes byte for byte.
  Check(fp::ProtectionSchemeInfoPayload(v.original_format, v.encryption) == v.sinf_payload,
        "core: sinf payload built from tenc fields equals the video init segment's sinf",
        Format("%zu bytes", v.sinf_payload.size()));
  Check(fp::ProtectionSchemeInfoPayload(a.original_format, a.encryption) == a.sinf_payload,
        "core: sinf payload equals the audio init segment's sinf");
  std::vector<uint8_t> tenc = fp::TrackEncryptionBoxPayload(v.encryption);
  Check(tenc.size() == 41 &&
            std::equal(tenc.begin(), tenc.end(), v.sinf_payload.end() - 41),
        "core: tenc payload is the 41 bytes AVStreamDataParser reports");

  // The core's synthesized protected sample entries, through CoreMedia's
  // public converter, give the same format descriptions as the file's own
  // encv/enca entries.
  auto same_format = [&](const ft::TrackInfo& t, const char* label) {
    CMFormatDescriptionRef ours = nullptr;
    CMFormatDescriptionRef file = nullptr;
    std::vector<uint8_t> entry;
    if (t.is_video) {
      entry = fp::ProtectSampleEntry(
          fp::VisualSampleEntry(t.original_format, t.width, t.height,
                                {fp::MakeBox(fp::FourCC('a', 'v', 'c', 'C'), t.codec_config)}),
          true, t.encryption);
      CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
          nullptr, entry.data(), entry.size(), kCFStringEncodingUTF8, kCMImageDescriptionFlavor_ISOFamily, &ours);
      CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
          nullptr, t.sample_entry_box.data(), t.sample_entry_box.size(), kCFStringEncodingUTF8,
          kCMImageDescriptionFlavor_ISOFamily, &file);
    } else {
      entry = fp::ProtectSampleEntry(
          fp::AudioSampleEntry(t.original_format, t.channels, t.sample_rate,
                               {fp::MakeBox(fp::FourCC('e', 's', 'd', 's'), fp::AacEsdsPayload(t.codec_config))}),
          false, t.encryption);
      CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(
          nullptr, entry.data(), entry.size(), kCMSoundDescriptionFlavor_ISOFamily, &ours);
      CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(
          nullptr, t.sample_entry_box.data(), t.sample_entry_box.size(), kCMSoundDescriptionFlavor_ISOFamily, &file);
    }
    bool same = ours && file && CMFormatDescriptionGetMediaSubType(ours) == CMFormatDescriptionGetMediaSubType(file);
    for (NSString* key in @[ @"CommonEncryptionOriginalFormat", @"CommonEncryptionProtected",
                             @"CommonEncryptionTrackEncryptionBox" ]) {
      same = same && [(__bridge id)CMFormatDescriptionGetExtension(ours, (__bridge CFStringRef)key)
                         isEqual:(__bridge id)CMFormatDescriptionGetExtension(file, (__bridge CFStringRef)key)];
    }
    NSDictionary* a = ours ? (__bridge NSDictionary*)CMFormatDescriptionGetExtension(
                                 ours, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                           : nil;
    NSDictionary* b = file ? (__bridge NSDictionary*)CMFormatDescriptionGetExtension(
                                 file, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                           : nil;
    same = same && [a[@"sinf"] isEqual:b[@"sinf"]] && (!t.is_video || [a[@"avcC"] isEqual:b[@"avcC"]]);
    if (same && !t.is_video) {
      const AudioStreamBasicDescription* x = CMAudioFormatDescriptionGetStreamBasicDescription(ours);
      const AudioStreamBasicDescription* y = CMAudioFormatDescriptionGetStreamBasicDescription(file);
      same = x->mFormatID == y->mFormatID && x->mSampleRate == y->mSampleRate &&
             x->mChannelsPerFrame == y->mChannelsPerFrame && x->mFramesPerPacket == y->mFramesPerPacket;
    }
    Check(same, std::string("core: synthesized protected ") + label +
                    " sample entry converts to the same format description as the file's own entry",
          ours ? ft::FourCCString(CMFormatDescriptionGetMediaSubType(ours)) : "no format description");
    if (ours) CFRelease(ours);
    if (file) CFRelease(file);
  };
  same_format(v, "video");
  same_format(a, "audio");

  // Parser: senc and saiz/saio agree (ParseMediaSegment refuses otherwise),
  // subsamples cover every video sample.
  size_t covered = 0, protected_samples = 0;
  bool saio = true;
  for (const ft::Sample& s : video.segments[0]) {
    if (!s.decrypt) continue;
    ++protected_samples;
    saio &= s.aux_from_saio;
    uint64_t total = 0;
    for (auto& e : s.decrypt->subsamples) total += e.clear_bytes + e.cypher_bytes;
    covered += total == s.data.size();
  }
  Check(protected_samples == video.segments[0].size() && covered == protected_samples && saio,
        "parser: every video sample protected, aux info read via saiz/saio matches senc, "
        "subsamples cover each sample",
        Format("%zu samples in segment 0", protected_samples));
  Check(audio.segments[0].front().pts == -1024 && audio.segments[0].front().decrypt &&
            audio.segments[0].front().decrypt->subsamples.empty(),
        "parser: audio edit list shifts the first sample to -1024 ticks; whole-sample encryption");

  // Chromium framing round trip through the core's Annex B conversion.
  int round_trips = 0, keyframes = 0;
  for (size_t i = 0; i < 48 && i < video.segments[0].size(); ++i) {
    const ft::Sample& s = video.segments[0][i];
    std::vector<uint8_t> storage;
    fp::DecryptInfo decrypt;
    fp::EncodedSample chromium = ft::ChromiumBuffer(v, s, &storage, &decrypt);
    std::vector<fp::SubsampleEntry> subsamples = chromium.decrypt->subsamples;
    std::vector<uint8_t> back;
    bool ok = fp::ConvertAnnexBToLengthPrefixed(chromium.data, chromium.size, &subsamples, &back);
    std::vector<uint8_t> expected;
    uint32_t inserted = 0;
    if (s.is_keyframe) {
      ++keyframes;
      // avcC: one SPS, one PPS.
      const std::vector<uint8_t>& r = v.codec_config;
      size_t sps_len = (r[6] << 8) | r[7];
      size_t pps_len = (r[8 + sps_len + 1] << 8) | r[8 + sps_len + 2];
      expected.insert(expected.end(), {0, 0, uint8_t(sps_len >> 8), uint8_t(sps_len)});
      expected.insert(expected.end(), r.begin() + 8, r.begin() + 8 + sps_len);
      expected.insert(expected.end(), {0, 0, uint8_t(pps_len >> 8), uint8_t(pps_len)});
      expected.insert(expected.end(), r.begin() + 8 + sps_len + 3, r.begin() + 8 + sps_len + 3 + pps_len);
      inserted = uint32_t(expected.size());
    }
    expected.insert(expected.end(), s.data.begin(), s.data.end());
    std::vector<fp::SubsampleEntry> want = s.decrypt->subsamples;
    want[0].clear_bytes += inserted;
    bool same_subsamples = subsamples.size() == want.size();
    for (size_t k = 0; same_subsamples && k < want.size(); ++k) {
      same_subsamples = subsamples[k].clear_bytes == want[k].clear_bytes &&
                        subsamples[k].cypher_bytes == want[k].cypher_bytes;
    }
    round_trips += ok && back == expected && same_subsamples &&
                   chromium.decrypt->iv == v.encryption.default_constant_iv;
  }
  Check(round_trips == 48 && keyframes >= 1,
        "core: Chromium Annex B buffers (SPS/PPS re-inserted, subsamples grown, constant IV per "
        "sample) convert back to the ISO sample plus in-band parameter sets",
        Format("%d/48 samples, %d keyframes", round_trips, keyframes));

  // ADTS.
  {
    const ft::Sample& s = audio.segments[0][1];
    std::vector<uint8_t> storage;
    fp::DecryptInfo decrypt;
    fp::EncodedSample chromium = ft::ChromiumBuffer(a, s, &storage, &decrypt);
    size_t header = fp::AdtsHeaderSize(chromium.data, chromium.size);
    std::vector<fp::SubsampleEntry> subsamples = chromium.decrypt->subsamples;
    bool ok = header == 7 && subsamples.size() == 1 && subsamples[0].clear_bytes == 7 &&
              fp::RemoveLeadingClearBytes(header, chromium.size - header, &subsamples) &&
              subsamples.empty();
    Check(ok, "core: Chromium ADTS buffer -> 7-byte header stripped, {7, n} subsample becomes "
              "whole-sample protection (no aux data), as AVStreamDataParser emits");
  }

  // Init data planning.
  auto pssh_json = [](const std::vector<uint8_t>& json) -> std::vector<uint8_t> {
    NSDictionary* root = [NSJSONSerialization JSONObjectWithData:Data(json) options:0 error:nil];
    NSString* base64 = [root isKindOfClass:[NSDictionary class]] ? root[@"pssh"] : nil;
    NSData* box = base64 ? [[NSData alloc] initWithBase64EncodedString:base64 options:0] : nil;
    return box ? Bytes(box) : std::vector<uint8_t>();
  };
  std::vector<uint8_t> synthesized = fp::FairPlayPsshForKeyId(g_key_id);
  auto parsed = fp::ParsePsshBoxes(synthesized);
  Check(parsed && parsed->size() == 1 &&
            std::equal(fp::kFairPlaySystemId, fp::kFairPlaySystemId + 16, (*parsed)[0].system_id.begin()),
        "init data: synthesized FairPlay pssh for the key ID", ft::Hex(synthesized));
  auto skd = fp::PlanContentKeyRequests(fp::InitDataType::kSkd, Bytes(std::string(kSkd)));
  Check(skd.error.empty() && !skd.json_messages && skd.calls.size() == 1 &&
            skd.calls[0].identifier.empty() && skd.calls[0].key_ids.size() == 1 &&
            skd.calls[0].key_ids[0] == g_key_id &&
            skd.calls[0].content_identifier == Bytes(std::string(kSkd)) &&
            pssh_json(skd.calls[0].initialization_data) == synthesized,
        "init data: skd -> request through a FairPlay pssh for the URI's key ID, whole URI as "
        "the SPC content identifier");
  auto opaque = fp::PlanContentKeyRequests(fp::InitDataType::kSkd, Bytes(std::string("skd://asset-42")));
  Check(opaque.error.empty() && opaque.calls.size() == 1 && opaque.calls[0].identifier == "skd://asset-42" &&
            opaque.calls[0].key_ids.empty(),
        "init data: skd URI without a key ID -> request named by the URI (no renderer can use its key)");
  auto boxes = fp::ParsePsshBoxes(v.pssh_boxes);
  Check(boxes && boxes->size() == 2, "init data: init segment carries 2 pssh boxes",
        boxes ? Format("%s, %s", ft::Hex((*boxes)[0].system_id).c_str(),
                       ft::Hex((*boxes)[1].system_id).c_str())
              : "unparsable");
  auto cenc = fp::PlanContentKeyRequests(fp::InitDataType::kCenc, v.pssh_boxes);
  Check(cenc.error.empty() && cenc.json_messages && cenc.calls.size() == 1 &&
            cenc.calls[0].key_ids.size() == 1 && cenc.calls[0].key_ids[0] == g_key_id &&
            cenc.calls[0].content_identifier == g_key_id &&
            pssh_json(cenc.calls[0].initialization_data) == synthesized,
        "init data: cenc without a FairPlay pssh -> the Widevine pssh's key ID, requested "
        "through a synthesized FairPlay pssh");
  NSString* kid64 = [[[Data(g_key_id) base64EncodedStringWithOptions:0]
      stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  kid64 = [kid64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
  auto keyids = fp::PlanContentKeyRequests(
      fp::InitDataType::kKeyIds, Bytes(Format("{\"kids\":[\"%s\"]}", kid64.UTF8String)));
  Check(keyids.error.empty() && keyids.calls.size() == 1 && keyids.calls[0].key_ids[0] == g_key_id,
        "init data: keyids JSON (base64url) -> one request for the key ID");
  std::string sinf_json =
      Format("{\"sinf\":[\"%s\"]}", [Data(v.sinf_payload) base64EncodedStringWithOptions:0].UTF8String);
  auto sinf = fp::PlanContentKeyRequests(fp::InitDataType::kSinf, Bytes(sinf_json));
  Check(sinf.error.empty() && sinf.calls.size() == 1 && sinf.calls[0].key_ids[0] == g_key_id,
        "init data: sinf JSON -> tenc key ID");
  Check(!fp::PlanContentKeyRequests(fp::InitDataType::kKeyIds, Bytes(std::string("{\"kids\":[\"AAA\"]}"))).error.empty() &&
            !fp::PlanContentKeyRequests(fp::InitDataType::kCenc, Bytes(std::string("junk"))).error.empty() &&
            !fp::PlanContentKeyRequests(fp::InitDataType::kSkd, {}).error.empty(),
        "init data: malformed keyids/cenc/skd rejected");
}

// A FairPlay 'pssh' for the vector's key, laid out as WebKit's
// ISOFairPlayStreamingPsshBox parses it: fpsd { fpsi(scheme), fpsk { fkri(key
// ID), fkai(asset ID), fkvl(versions) } }. The vector itself carries only
// PlayReady and Widevine boxes.
std::vector<uint8_t> FairPlayPssh(const std::vector<std::vector<uint8_t>>& key_ids, uint32_t scheme) {
  auto full = [](uint32_t type, std::vector<uint8_t> payload) {
    payload.insert(payload.begin(), {0, 0, 0, 0});
    return fp::MakeBox(type, payload);
  };
  auto be32 = [](uint32_t v) {
    return std::vector<uint8_t>{uint8_t(v >> 24), uint8_t(v >> 16), uint8_t(v >> 8), uint8_t(v)};
  };
  auto cat = [](std::vector<uint8_t> a, const std::vector<uint8_t>& b) {
    a.insert(a.end(), b.begin(), b.end());
    return a;
  };
  std::vector<uint8_t> fpsd_payload = full(fp::FourCC('f', 'p', 's', 'i'), be32(scheme));
  for (const auto& key_id : key_ids) {
    std::string asset = ft::Hex(key_id);
    std::vector<uint8_t> fpsk = cat(cat(full(fp::FourCC('f', 'k', 'r', 'i'), key_id),
                                        fp::MakeBox(fp::FourCC('f', 'k', 'a', 'i'), Bytes(asset))),
                                    fp::MakeBox(fp::FourCC('f', 'k', 'v', 'l'), be32(1)));
    fpsd_payload = cat(fpsd_payload, fp::MakeBox(fp::FourCC('f', 'p', 's', 'k'), fpsk));
  }
  std::vector<uint8_t> fpsd = fp::MakeBox(fp::FourCC('f', 'p', 's', 'd'), fpsd_payload);
  std::vector<uint8_t> payload(fp::kFairPlaySystemId, fp::kFairPlaySystemId + 16);
  payload = cat(cat(payload, be32(uint32_t(fpsd.size()))), fpsd);
  return full(fp::FourCC('p', 's', 's', 'h'), payload);
}

std::vector<uint8_t> FairPlayPssh(const std::vector<uint8_t>& key_id, uint32_t scheme) {
  return FairPlayPssh(std::vector<std::vector<uint8_t>>{key_id}, scheme);
}

// --------------------------------------------------------------- scenarios

struct World {
  Media video, audio, clear_video, clear_audio, hevc_video, hevc_audio, multi_video, multi_audio;
  Media hev1, hev1_in_band, dolby_vision, av1, xhe_aac, he_aac, he_aac_v2;
  NSView* host = nil;
  std::unique_ptr<KeySystem> main_keys;
  std::vector<std::unique_ptr<KeySystem>> retired;
  std::shared_ptr<Player> player;
  int segments = 13;
};

World* g_world = nullptr;
std::string g_only;

Step Section(const std::string& title) {
  return [title](Done done) {
    Log("== %s", title.c_str());
    done();
  };
}

std::vector<Step> MainScenario(Framing framing, bool full) {
  World* w = g_world;
  std::string name = framing == Framing::kChromium ? "chromium" : "iso";
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section(name + " framing: play / pause / rate / seek / end of stream"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>(name, framing, &w->video, &w->audio, w->main_keys->cdm.get(), w->host);
    done();
  });
  auto& p = w->player;  // Captured by reference to the World slot below.
  (void)p;
  auto player = [w] { return w->player; };
  steps.push_back([=](Done done) {
    StartAt(player(), &w->video, &w->audio, 0, w->segments, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(player(), 8, 1, name + " play 8s")(done); });
  steps.push_back([=](Done done) { Metrics(player(), name + " after 8s", 150, frames)(done); });
  steps.push_back([=](Done done) {
    Check(player()->underflows == 0, name + ": no HAVE_NOTHING during steady playback",
          Format("%d", player()->underflows));
    done();
  });
  steps.push_back([=](Done done) {
    Check(player()->natural_width == w->video.info.width && player()->natural_height == w->video.info.height,
          name + ": natural size reported", Format("%dx%d", player()->natural_width, player()->natural_height));
    done();
  });
  if (full) {
    steps.push_back([=](Done done) {
      player()->renderer().SetPlaybackRate(0);
      Run(player(), 2, 0, name + " paused 2s")(done);
    });
    steps.push_back([=](Done done) {
      player()->renderer().SetPlaybackRate(1);
      Run(player(), 2, 1, name + " resumed 2s")(done);
    });
    steps.push_back([=](Done done) {
      player()->renderer().SetPlaybackRate(1.5);
      Run(player(), 2, 1.5, name + " rate 1.5 for 2s")(done);
    });
    steps.push_back([=](Done done) {
      player()->renderer().SetVolume(0.25f);
      player()->renderer().SetMuted(true);
      fp::RendererStatus s = player()->renderer().GetStatus();
      Check(std::fabs(s.audio_volume - 0.25f) < 1e-6 && s.audio_muted, name + ": volume 0.25 and mute reach the audio renderer");
      player()->renderer().SetMuted(false);
      player()->renderer().SetVolume(1);
      done();
    });
  }
  // Seek into the middle of a segment: preceding video decodes without
  // display, preceding audio is dropped.
  steps.push_back([=](Done done) {
    StartAt(player(), &w->video, &w->audio, 6, w->segments, 40, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    double t = player()->Time();
    Check(t >= 39.9 && t <= 40.6, name + Format(": seek lands at 40s (t=%.3f)", t));
    done();
  });
  steps.push_back([=](Done done) { Run(player(), 4, 1, name + " after seek 4s")(done); });
  steps.push_back([=](Done done) { Metrics(player(), name + " after seek", 60, frames)(done); });
  if (full) {
    double end = 6.0 * w->segments;
    steps.push_back([=](Done done) {
      StartAt(player(), &w->video, &w->audio, w->segments - 2, w->segments, 6.0 * (w->segments - 2), 1, true)(done);
    });
    steps.push_back([=](Done done) {
      auto finish = Once(20, name + ": OnEnded at end of stream", [=](bool ok) {
        double t = player()->Time();
        if (ok) {
          Check(std::fabs(t - end) < 0.3, name + Format(": ended at the last sample's end (t=%.3f, end %.3f)", t, end));
        }
        done();
      });
      if (player()->ended) {
        finish(true);
      } else {
        player()->on_ended = [finish] { finish(true); };
      }
    });
    steps.push_back([=](Done done) {
      CheckHealthy(*player(), name + " at end of stream");
      done();
    });
  }
  steps.push_back([=](Done done) {
    w->player.reset();
    done();
  });
  return steps;
}

std::vector<Step> MixedScenario() {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("clear lead: segment 0 from the clear variant, then protected samples"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("mixed", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    w->player->renderer().Flush([=] {
      SegmentList video{&w->clear_video.segments[0], &w->video.segments[1], &w->video.segments[2]};
      SegmentList audio{&w->clear_audio.segments[0], &w->audio.segments[1], &w->audio.segments[2]};
      w->player->SetFeeds(video, audio, false);
      auto go = Once(10, "mixed: HAVE_ENOUGH", [=](bool) {
        w->player->renderer().SetPlaybackRate(1);
        done();
      });
      w->player->on_have_enough = [go] { go(true); };
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    });
  });
  steps.push_back([=](Done done) { Run(w->player, 5, 1, "mixed clear part 5s")(done); });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(s.video_enqueued > s.protected_enqueued, "mixed: clear samples enqueued before protected ones",
          Format("video %llu audio %llu protected %llu", s.video_enqueued, s.audio_enqueued, s.protected_enqueued));
    done();
  });
  steps.push_back([=](Done done) { Run(w->player, 6, 1, "mixed into protected part 6s")(done); });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(s.protected_enqueued > 0 && s.time.InSeconds() > 6.5,
          "mixed: playback crossed from clear to protected samples",
          Format("t=%.3f protected enqueued %llu", s.time.InSeconds(), s.protected_enqueued));
    done();
  });
  steps.push_back([=](Done done) { Metrics(w->player, "mixed", 200, frames)(done); });
  steps.push_back([=](Done done) {
    w->player.reset();
    done();
  });
  return steps;
}

std::vector<Step> UnderflowScenario() {
  World* w = g_world;
  auto stalled_at = std::make_shared<double>(0);
  std::vector<Step> steps;
  steps.push_back(Section("underflow: data runs out mid-playback, then more arrives"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("underflow", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 1, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    auto finish = Once(12, "underflow: HAVE_NOTHING when the 6s of data runs out", [=](bool ok) {
      *stalled_at = w->player->Time();
      if (ok) {
        Check(*stalled_at > 5.6 && *stalled_at < 6.1,
              Format("underflow: reported at t=%.3f, the end of the enqueued data (6.0)", *stalled_at));
      }
      done();
    });
    w->player->on_have_nothing = [finish] { finish(true); };
  });
  steps.push_back([=](Done done) {
    After(1.5, [=] {
      double t = w->player->Time();
      Check(std::fabs(t - *stalled_at) < 0.02,
            Format("underflow: clock stopped while starved (%.3f -> %.3f over 1.5s)", *stalled_at, t));
      done();
    });
  });
  steps.push_back([=](Done done) {
    auto finish = Once(10, "underflow: HAVE_ENOUGH after more data arrives", [=](bool) { done(); });
    w->player->on_have_enough = [finish] { finish(true); };
    w->player->AppendFeeds(Segments(w->video, 1, 3), Segments(w->audio, 1, 3));
  });
  steps.push_back([=](Done done) { Run(w->player, 3, 1, "underflow recovered, play 3s")(done); });
  steps.push_back([=](Done done) {
    Check(w->player->underflows == 1, "underflow: exactly one HAVE_NOTHING (no flapping)",
          Format("%d", w->player->underflows));
    w->player.reset();
    done();
  });
  return steps;
}

// Chromium's order when MediaKeys come first: SetCdm, then Initialize. The
// renderers must still join the key session (protected samples would
// otherwise fail with -11800 "no content key present").
// Responses a page could send: each must be rejected (TypeError) without
// touching AVFoundation, then the real response still works.
std::vector<Step> ResponseValidationScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("malformed JSON license responses from the page"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("responses");
    KeySystem* ks = keys->get();
    ks->client->json = true;
    ks->client->hold = true;
    ks->client->on_message = [=] { done(); };
    NSString* kid64 = [[[[Data(g_key_id) base64EncodedStringWithOptions:0]
        stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
        stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
        stringByReplacingOccurrencesOfString:@"=" withString:@""];
    ks->cdm->CreateSessionAndGenerateRequest(
        fp::InitDataType::kKeyIds, Bytes(Format("{\"kids\":[\"%s\"]}", kid64.UTF8String)),
        [ks](const fp::Result& r, const std::string& id) {
          ks->session = id;
          Check(r.ok(), "responses: generateRequest resolves", r.ok() ? id : r.message);
        });
  });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    std::string k = [[Data(g_key_id) base64EncodedStringWithOptions:0] UTF8String];
    std::vector<std::pair<std::string, std::string>> cases = {
        {"top-level {\"error\":null}", "{\"error\":null}"},
        {"empty array", "[]"},
        {"empty object", "{}"},
        {"payload with error null", "[{\"keyID\":\"" + k + "\",\"payload\":\"AAAA\",\"error\":null}]"},
        {"error null only", "[{\"keyID\":\"" + k + "\",\"error\":null}]"},
        {"error as a string", "[{\"keyID\":\"" + k + "\",\"error\":\"x\"}]"},
        {"payload as a number", "[{\"keyID\":\"" + k + "\",\"payload\":5}]"},
        {"keyID listed twice", "[{\"keyID\":\"" + k + "\",\"payload\":\"AAAA\"},{\"keyID\":\"" + k +
                                   "\",\"payload\":\"AAAA\"}]"},
        {"entry not an object", "[1]"},
        {"keyID not base64", "[{\"keyID\":\"!!\",\"payload\":\"AAAA\"}]"},
        {"not JSON", "license"},
    };
    int rejected = 0;
    std::string failures;
    for (const auto& [name, body] : cases) {
      bool type_error = false;
      ks->cdm->UpdateSession(ks->session, Bytes(body), [&](const fp::Result& r) {
        type_error = r.exception == fp::Exception::kTypeError;
      });
      if (type_error) {
        ++rejected;
      } else {
        failures += (failures.empty() ? "" : ", ") + name;
      }
    }
    Check(rejected == int(cases.size()),
          Format("responses: %d malformed JSON responses each rejected with TypeError, no crash",
                 int(cases.size())),
          failures.empty() ? "" : "accepted: " + failures);
    Check(!ks->cdm->HasUsableKey(g_key_id), "responses: no key from a malformed response");
    // The real license still goes through afterwards.
    auto finish = Once(30, "responses: real license after the malformed ones", [=](bool) { done(); });
    ks->client->on_update = [=](bool ok, const std::string& detail) {
      Check(ok && ks->cdm->HasUsableKey(g_key_id),
            "responses: the real response is accepted afterwards and the key is usable", detail);
      finish(true);
    };
    ks->client->hold = false;
    ks->client->Respond(ks->client->held_session, ks->client->held_message);
  });
  steps.push_back([=](Done done) {
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

std::vector<Step> CdmFirstScenario() {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("SetCdm before Initialize (Chromium's order with MediaKeys attached first)"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("cdm-first", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host, true);
    StartAt(w->player, &w->video, &w->audio, 0, 2, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(w->player, 3, 1, "cdm-first play 3s")(done); });
  steps.push_back([=](Done done) { Metrics(w->player, "cdm-first", 50, frames)(done); });
  steps.push_back([=](Done done) {
    w->player.reset();
    done();
  });
  return steps;
}

std::vector<Step> WaitingForKeyScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("samples before keys: renderer holds them, then attaches keys when they arrive"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("late-keys");
    w->player = std::make_shared<Player>("late", Framing::kChromium, &w->video, &w->audio, (*keys)->cdm.get(), w->host);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(Segments(w->video, 0, 3), Segments(w->audio, 0, 3), false);
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
      After(1.5, done);
    });
  });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(w->player->waiting_events == 1 && w->player->waiting_results >= 1 && s.video_enqueued == 0 &&
              s.audio_enqueued == 0,
          "late keys: encrypted samples held, OnWaitingForKey once, nothing enqueued",
          Format("waiting events %d, held results %d, enqueued v/a %llu/%llu", w->player->waiting_events,
                 w->player->waiting_results, s.video_enqueued, s.audio_enqueued));
    Check(!w->player->renderer().IsReadyForMoreData(fp::StreamType::kVideo),
          "late keys: backpressure while held");
    AcquireLicense(keys->get(), fp::InitDataType::kSkd, Bytes(std::string(kSkd)), "late keys", [=](bool) {
      done();
    });
  });
  steps.push_back([=](Done done) {
    auto go = Once(10, "late keys: HAVE_ENOUGH after keys", [=](bool) {
      w->player->renderer().SetPlaybackRate(1);
      done();
    });
    if (w->player->have_enough) {
      go(true);
    } else {
      w->player->on_have_enough = [go] { go(true); };
    }
  });
  steps.push_back([=](Done done) { Run(w->player, 4, 1, "late keys play 4s")(done); });
  steps.push_back([=](Done done) {
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

std::vector<Step> InitDataScenario(fp::InitDataType type, std::vector<uint8_t> init_data) {
  World* w = g_world;
  std::string label = std::string("init data ") + fp::InitDataTypeName(type);
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  auto acquired = std::make_shared<bool>(false);
  std::vector<Step> steps;
  steps.push_back(Section(label + ": license exchange, then 3s of playback with its key"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem(label);
    AcquireLicense(keys->get(), type, init_data, label, [=](bool ok) {
      *acquired = ok;
      done();
    });
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    w->player = std::make_shared<Player>(label, Framing::kChromium, &w->video, &w->audio, (*keys)->cdm.get(), w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 2, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    Run(w->player, 3, 1, label + " play 3s")(done);
  });
  steps.push_back([=](Done done) {
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// Netflix's flow: one generateRequest("cenc") naming three keys, one JSON
// message carrying three SPCs, one JSON response with three CKCs, then video
// and audio under different keys. |with_fairplay| adds a FairPlay pssh for the
// three keys to the vector's PlayReady/Widevine boxes (Netflix's init data
// carries one); without it the core falls back to the Widevine key IDs.
std::vector<Step> MultiKeyScenario(bool with_fairplay) {
  World* w = g_world;
  std::string label = with_fairplay ? "multikey cenc+fairplay pssh" : "multikey cenc (widevine key IDs)";
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  auto acquired = std::make_shared<bool>(false);
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section(label + ": three keys in one session, video and audio under different keys"));
  steps.push_back([=](Done done) {
    std::vector<std::vector<uint8_t>> key_ids;
    auto boxes = fp::ParsePsshBoxes(w->multi_video.info.pssh_boxes);
    for (const auto& box : *boxes) {
      for (const auto& id : fp::KeyIdsFromPssh(box)) key_ids.push_back(id);
    }
    const auto& video_key = w->multi_video.info.encryption.default_key_id;
    const auto& audio_key = w->multi_audio.info.encryption.default_key_id;
    Check(key_ids.size() == 3 && video_key != audio_key,
          label + ": vector names three key IDs; video and audio use different ones",
          "video " + ft::Hex(video_key) + ", audio " + ft::Hex(audio_key));
    std::vector<uint8_t> init_data = w->multi_video.info.pssh_boxes;
    if (with_fairplay) {
      std::vector<uint8_t> fairplay = FairPlayPssh(key_ids, fp::FourCC('c', 'b', 'c', 's'));
      init_data.insert(init_data.end(), fairplay.begin(), fairplay.end());
    }
    Log("%s: cenc init data %zu bytes", label.c_str(), init_data.size());
    *keys = MakeKeySystem(label, kMultiKeyToken);
    int messages_before = 0;
    AcquireLicense(keys->get(), fp::InitDataType::kCenc, init_data, label,
                   [=](bool ok) {
                     *acquired = ok;
                     KeySystem* ks = keys->get();
                     Check(ks->client->messages == messages_before + 1 && ks->client->keys.size() == 3,
                           label + ": one license message for all three keys, three keys reported",
                           Format("%d message(s), [%s]", ks->client->messages, KeysText(ks->client->keys).c_str()));
                     done();
                   },
                   key_ids);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    w->player = std::make_shared<Player>(label, Framing::kChromium, &w->multi_video, &w->multi_audio,
                                         (*keys)->cdm.get(), w->host);
    StartAt(w->player, &w->multi_video, &w->multi_audio, 0, 2, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    Run(w->player, 4, 1, label + " play 4s")(done);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    Metrics(w->player, label, 80, frames)(done);
  });
  steps.push_back([=](Done done) {
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

std::vector<Step> HevcScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  auto acquired = std::make_shared<bool>(false);
  auto frames = std::make_shared<int64_t>(0);
  std::vector<uint8_t> key_id = {0xab, 0xcc, 0x44, 0xe5, 0xc1, 0x22, 0x45, 0xab,
                                 0xac, 0x80, 0xa5, 0xb3, 0x52, 0x2a, 0x0a, 0x31};
  std::vector<Step> steps;
  steps.push_back(Section("HEVC: CMAF H265 SingleKey (cbcs), Chromium framing (Annex B with VPS/SPS/PPS)"));
  steps.push_back([=](Done done) {
    Check(ft::FourCCString(w->hevc_video.info.original_format) == "hvc1" &&
              w->hevc_video.info.encryption.default_key_id == key_id,
          "hevc: parser reads hvc1/hvcC and the H265 vector's key ID",
          Format("%ux%u", w->hevc_video.info.width, w->hevc_video.info.height));
    *keys = MakeKeySystem("hevc", kHevcToken);
    AcquireLicense(keys->get(), fp::InitDataType::kSkd, Bytes(std::string(kHevcSkd)), "hevc skd",
                   [=](bool ok) {
                     *acquired = ok;
                     done();
                   },
                   {key_id});
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    w->player = std::make_shared<Player>("hevc", Framing::kChromium, &w->hevc_video, &w->hevc_audio,
                                         (*keys)->cdm.get(), w->host);
    StartAt(w->player, &w->hevc_video, &w->hevc_audio, 0, 2, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    Run(w->player, 5, 1, "hevc play 5s")(done);
  });
  steps.push_back([=](Done done) {
    if (!*acquired) {
      done();
      return;
    }
    Metrics(w->player, "hevc", 100, frames)(done);
  });
  steps.push_back([=](Done done) {
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// An hev1 stream whose hvcC has no parameter sets: the VPS/SPS/PPS move into
// every keyframe, as such streams carry them.
Media InBandParameterSetsOnly(const Media& media) {
  Media out = media;
  const std::vector<uint8_t>& record = media.info.codec_config;
  size_t length_size = (record[21] & 3) + 1;
  std::vector<uint8_t> prefix;
  size_t pos = 23;
  for (uint8_t a = 0; a < record[22] && pos + 3 <= record.size(); ++a) {
    uint8_t type = record[pos] & 0x3f;
    uint32_t count = (record[pos + 1] << 8) | record[pos + 2];
    pos += 3;
    for (uint32_t k = 0; k < count; ++k) {
      size_t len = (record[pos] << 8) | record[pos + 1];
      if (type >= 32 && type <= 34) {
        for (size_t b = length_size; b-- > 0;) prefix.push_back(uint8_t(len >> (8 * b)));
        prefix.insert(prefix.end(), record.begin() + pos + 2, record.begin() + pos + 2 + len);
      }
      pos += 2 + len;
    }
  }
  out.info.codec_config.assign(record.begin(), record.begin() + 23);
  out.info.codec_config[22] = 0;
  for (auto& segment : out.segments) {
    for (ft::Sample& sample : segment) {
      if (sample.is_keyframe) sample.data.insert(sample.data.begin(), prefix.begin(), prefix.end());
    }
  }
  return out;
}

double EndSeconds(const Media& media) {
  double end = 0;
  for (const auto& segment : media.segments) {
    for (const ft::Sample& s : segment) end = std::max(end, double(s.pts + s.duration) / media.info.timescale);
  }
  return end;
}

size_t SampleCount(const Media& media) {
  size_t count = 0;
  for (const auto& segment : media.segments) count += segment.size();
  return count;
}

// A codec Netflix uses, through the renderer's clear path with Chromium's
// framing, played to OnEnded; then the protected format description the
// renderer builds for it (Apple's FairPlay type). No FairPlay-protected sample
// of these codecs is public, so protected decode stays unproven.
std::vector<Step> CodecScenario(const std::string& label, const Media* video, const Media* audio,
                                const std::string& protected_type) {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  const Media* media = video ? video : audio;
  double end = EndSeconds(*media);
  std::vector<Step> steps;
  steps.push_back(Section(label + " (clear path, Chromium framing, played to the end)"));
  steps.push_back([=](Done done) {
    const ft::TrackInfo& info = media->info;
    Log("%s: entry %s, config %zu bytes%s, %zu samples, %.3fs", label.c_str(),
        ft::FourCCString(info.sample_entry).c_str(), info.codec_config.size(),
        info.dolby_vision_config.empty() ? "" : Format(", dovi %s", ft::Hex(info.dolby_vision_config).c_str()).c_str(),
        SampleCount(*media), end);
    w->player = std::make_shared<Player>(label, Framing::kChromium, video, audio, nullptr, w->host);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(video ? Segments(*video, 0, 1) : SegmentList(),
                          audio ? Segments(*audio, 0, 1) : SegmentList(), true);
      auto go = Once(10, label + ": HAVE_ENOUGH", [=](bool) {
        w->player->renderer().SetPlaybackRate(1);
        done();
      });
      w->player->on_have_enough = [go] { go(true); };
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    });
  });
  steps.push_back([=](Done done) {
    auto finish = Once(end + 8, label + ": OnEnded", [=](bool ok) {
      double t = w->player->Time();
      if (ok) {
        Check(std::fabs(t - end) < 0.3, label + Format(": ended at the clip's end (t=%.3f, end %.3f)", t, end));
      }
      CheckHealthy(*w->player, label);
      fp::RendererStatus s = w->player->renderer().GetStatus();
      Log("%s: formats video '%s' audio '%s'", label.c_str(), ft::FourCCString(s.video_format).c_str(),
          ft::FourCCString(s.audio_format).c_str());
      done();
    });
    if (w->player->ended) {
      finish(true);
    } else {
      w->player->on_ended = [finish] { finish(true); };
    }
  });
  if (video) {
    steps.push_back([=](Done done) {
      Metrics(w->player, label, int64_t(SampleCount(*video) * 9 / 10), frames)(done);
    });
  }
  steps.push_back([=](Done done) {
    w->player.reset();
    if (protected_type.empty()) {
      done();
      return;
    }
    // The protected form: same config with a cbcs track encryption.
    fp::TrackEncryption tenc;
    tenc.scheme = fp::EncryptionScheme::kCbcs;
    tenc.default_pattern = video ? fp::EncryptionPattern{1, 9} : fp::EncryptionPattern{0, 0};
    tenc.default_key_id = g_key_id;
    tenc.default_constant_iv = std::vector<uint8_t>(16, 0x5a);
    struct NullClient : fp::FairPlayRendererClient {
      void OnNeedData(fp::StreamType) override {}
      void OnWaitingForKey() override {}
      void OnEnded() override {}
      void OnError(fp::RendererError, const std::string&) override {}
      void OnVideoNaturalSizeChange(int32_t, int32_t) override {}
      void OnBufferingStateChange(bool) override {}
    } client;
    fp::FairPlayRenderer renderer(&client, [](std::function<void()>) {});
    std::optional<fp::VideoConfig> vc;
    std::optional<fp::AudioConfig> ac;
    if (video) {
      vc = VideoConfigFor(video->info, Framing::kChromium);
      vc->encryption = tenc;
    } else {
      ac = AudioConfigFor(audio->info, Framing::kChromium);
      ac->encryption = tenc;
    }
    fp::Result result = renderer.Initialize(vc, ac);
    fp::RendererStatus s = renderer.GetStatus();
    std::string type = ft::FourCCString(video ? s.video_protected_format : s.audio_protected_format);
    std::string layers;
    if (audio) {
      // The format list says which AAC layers the protected description
      // carries (HE-AAC rides in 'qaac' with an SBR/PS layer listed).
      std::vector<uint8_t> entry = fp::ProtectSampleEntry(
          fp::AudioSampleEntry(fp::FourCC('m', 'p', '4', 'a'), audio->info.channels, audio->info.sample_rate,
                               {fp::MakeBox(fp::FourCC('e', 's', 'd', 's'), fp::AacEsdsPayload(audio->info.codec_config))}),
          false, tenc);
      CMFormatDescriptionRef format = nullptr;
      CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData(nullptr, entry.data(), entry.size(),
                                                                     kCMSoundDescriptionFlavor_ISOFamily, &format);
      size_t list_size = 0;
      const AudioFormatListItem* list = format ? CMAudioFormatDescriptionGetFormatList(format, &list_size) : nullptr;
      for (size_t i = 0; list && i < list_size / sizeof(AudioFormatListItem); ++i) {
        layers += (layers.empty() ? "" : ",") + ft::FourCCString(list[i].mASBD.mFormatID) +
                  Format("@%.0f", list[i].mASBD.mSampleRate);
      }
      if (format) CFRelease(format);
    }
    bool ok = result.ok() && (protected_type.find(',') == std::string::npos
                                  ? type == protected_type
                                  : protected_type.substr(0, 4) == type &&
                                        layers.find(protected_type.substr(5)) != std::string::npos);
    Check(ok, label + ": protected format description is Apple's '" + protected_type + "'",
          result.ok() ? "'" + type + "'" + (layers.empty() ? "" : " layers " + layers) : result.message);
    done();
  });
  return steps;
}

std::vector<Step> CloseScenario() {
  World* w = g_world;
  std::vector<Step> steps;
  steps.push_back(Section("session close and remove"));
  steps.push_back([=](Done done) {
    KeySystem* ks = w->main_keys.get();
    bool removed = false;
    ks->cdm->RemoveSession(ks->session, [&](const fp::Result& r) { removed = r.ok(); });
    Check(removed && !ks->cdm->HasUsableKey(g_key_id) && !ks->client->keys.empty() &&
              ks->client->keys[0].status == fp::KeyStatus::kReleased,
          "remove: keys reported released and no longer attachable", KeysText(ks->client->keys));
    bool closed = false;
    ks->cdm->CloseSession(ks->session, [&](const fp::Result& r) { closed = r.ok(); });
    Check(closed && ks->client->closed, "close: promise resolves and OnSessionClosed fires");
    bool rejected = false;
    ks->cdm->UpdateSession(ks->session, {1, 2, 3}, [&](const fp::Result& r) {
      rejected = r.exception == fp::Exception::kInvalidState;
    });
    Check(rejected, "close: update on a closed session is rejected (InvalidStateError)");
    done();
  });
  return steps;
}

void Finish() {
  Log("== summary: %d checks, %d failed", g_checks, g_failures);
  for (const std::string& name : g_failed) Log("   failed: %s", name.c_str());
  fflush(stdout);
  exit(g_failures ? 1 : 0);
}

void RunAll() {
  World* w = g_world;
  Check(fp::FairPlayCdm::IsKeySystemSupported("com.apple.fps") &&
            fp::FairPlayCdm::IsKeySystemSupported("com.apple.fps.1_0") &&
            fp::FairPlayCdm::IsKeySystemSupported("com.apple.fps.2_0") &&
            fp::FairPlayCdm::IsKeySystemSupported("com.apple.fps.3_0") &&
            !fp::FairPlayCdm::IsKeySystemSupported("com.apple.fps.") &&
            !fp::FairPlayCdm::IsKeySystemSupported("com.apple.fpsx") &&
            !fp::FairPlayCdm::IsKeySystemSupported("COM.APPLE.FPS") &&
            !fp::FairPlayCdm::IsKeySystemSupported("com.widevine.alpha") &&
            fp::FairPlayCdm::IsInitDataTypeSupported("cenc") &&
            !fp::FairPlayCdm::IsInitDataTypeSupported("webm"),
        "key system names: com.apple.fps and com.apple.fps.<version> (case-sensitive); cenc init data");
  Check(fp::FairPlayCdm::IsSupported(), "FairPlayCdm::IsSupported on this Mac",
        NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
  SelfTests(w->video, w->audio);
  {
    std::vector<uint8_t> boxes = w->video.info.pssh_boxes;
    std::vector<uint8_t> fairplay =
        FairPlayPssh(g_key_id, fp::FourCC('c', 'b', 'c', 's'));
    boxes.insert(boxes.end(), fairplay.begin(), fairplay.end());
    auto plan = fp::PlanContentKeyRequests(fp::InitDataType::kCenc, boxes);
    NSDictionary* json = plan.calls.size() == 1
                             ? [NSJSONSerialization JSONObjectWithData:Data(plan.calls[0].initialization_data)
                                                               options:0
                                                                 error:nil]
                             : nil;
    NSData* forwarded = [[NSData alloc] initWithBase64EncodedString:json[@"pssh"] ?: @"" options:0];
    Check(plan.error.empty() && plan.json_messages && forwarded && Bytes(forwarded) == fairplay,
          "init data: cenc with a FairPlay pssh among others forwards that box alone as {\"pssh\": ...}");
  }

  std::vector<Step> steps;
  // --only <text> keeps the scenario groups whose call names contain <text>.
  auto add = [&steps](const std::string& name, std::vector<Step> group) {
    if (!g_only.empty() && name.find(g_only) == std::string::npos) return;
    steps.insert(steps.end(), group.begin(), group.end());
  };
  steps.push_back(Section("license exchange (skd init data) for the playback scenarios"));
  steps.push_back([=](Done done) {
    w->main_keys = MakeKeySystem("main");
    AcquireLicense(w->main_keys.get(), fp::InitDataType::kSkd, Bytes(std::string(kSkd)), "skd", [=](bool ok) {
      if (!ok) Finish();
      done();
    });
  });
  add("MainScenario(Framing::kChromium, true)", MainScenario(Framing::kChromium, true));
  add("MainScenario(Framing::kIso, false)", MainScenario(Framing::kIso, false));
  add("MixedScenario()", MixedScenario());
  add("UnderflowScenario()", UnderflowScenario());
  add("CdmFirstScenario()", CdmFirstScenario());
  add("ResponseValidationScenario()", ResponseValidationScenario());
  add("WaitingForKeyScenario()", WaitingForKeyScenario());

  std::string sinf_json = Format("{\"sinf\":[\"%s\"]}",
                                 [Data(w->video.info.sinf_payload) base64EncodedStringWithOptions:0].UTF8String);
  NSString* kid64 = [[[[Data(g_key_id) base64EncodedStringWithOptions:0]
      stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
      stringByReplacingOccurrencesOfString:@"=" withString:@""];
  add("InitDataScenario(fp::InitDataType::kSinf, Bytes(sinf_json))", InitDataScenario(fp::InitDataType::kSinf, Bytes(sinf_json)));
  add("InitDataScenario(fp::InitDataType::kKeyIds, Bytes(Format({kids:[%s]}, kid64.UTF8String)))", InitDataScenario(fp::InitDataType::kKeyIds, Bytes(Format("{\"kids\":[\"%s\"]}", kid64.UTF8String))));
  add("InitDataScenario(fp::InitDataType::kCenc, w->video.info.pssh_boxes)", InitDataScenario(fp::InitDataType::kCenc, w->video.info.pssh_boxes));
  // Chromium's cenc init data is every pssh in the moov; put a FairPlay box
  // among the vector's own so the WebKit path (FairPlay pssh to AVFoundation
  // as {"pssh": ...}) runs.
  std::vector<uint8_t> with_fairplay = w->video.info.pssh_boxes;
  std::vector<uint8_t> fairplay =
      FairPlayPssh(g_key_id, fp::FourCC('c', 'b', 'c', 's'));
  with_fairplay.insert(with_fairplay.end(), fairplay.begin(), fairplay.end());
  add("InitDataScenario(fp::InitDataType::kCenc, with_fairplay)", InitDataScenario(fp::InitDataType::kCenc, with_fairplay));
  add("MultiKeyScenario(true)", MultiKeyScenario(true));
  add("MultiKeyScenario(false)", MultiKeyScenario(false));
  add("HevcScenario()", HevcScenario());
  // hev1 decodes only when presented as hvc1, so its protected form is qhvc
  // (Apple's own parser would label the entry qhev).
  add("CodecScenario(hev1 (HEVC), &w->hev1, nullptr, qhvc)", CodecScenario("hev1 (HEVC)", &w->hev1, nullptr, "qhvc"));
  add("CodecScenario(hev1 with parameter sets only in-band, &w->hev1_in_band, nullptr, )", CodecScenario("hev1 with parameter sets only in-band", &w->hev1_in_band, nullptr, ""));
  add("CodecScenario(Dolby Vision profile 5 (dvh1), &w->dolby_vision, nullptr, qdh1)", CodecScenario("Dolby Vision profile 5 (dvh1)", &w->dolby_vision, nullptr, "qdh1"));
  add("CodecScenario(AV1 (av01), &w->av1, nullptr, qav1)", CodecScenario("AV1 (av01)", &w->av1, nullptr, "qav1"));
  add("CodecScenario(xHE-AAC (mp4a.40.42), nullptr, &w->xhe_aac, qusa)", CodecScenario("xHE-AAC (mp4a.40.42)", nullptr, &w->xhe_aac, "qusa"));
  add("CodecScenario(HE-AAC (mp4a.40.5), nullptr, &w->he_aac, qaac,qach)", CodecScenario("HE-AAC (mp4a.40.5)", nullptr, &w->he_aac, "qaac,qach"));
  add("CodecScenario(HE-AACv2 (mp4a.40.29), nullptr, &w->he_aac_v2, qaac,qacp)", CodecScenario("HE-AACv2 (mp4a.40.29)", nullptr, &w->he_aac_v2, "qaac,qacp"));
  add("CloseScenario()", CloseScenario());
  Sequence(steps, Finish);
}

}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    g_start = CFAbsoluteTimeGetCurrent();
    setvbuf(stdout, nullptr, _IOLBF, 0);
    static World world;
    g_world = &world;
    NSString* video_playlist = @"video-H264-720-2100k.m3u8";
    g_cache_dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"parc-fairplay-cache"];
    for (int i = 1; i + 1 < argc; i += 2) {
      std::string flag = argv[i];
      if (flag == "--cache") g_cache_dir = @(argv[i + 1]);
      else if (flag == "--video-playlist") video_playlist = @(argv[i + 1]);
      else if (flag == "--segments") world.segments = std::max(10, atoi(argv[i + 1]));
      else if (flag == "--only") g_only = argv[i + 1];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:g_cache_dir withIntermediateDirectories:YES
                                               attributes:nil error:nil];
    g_key_id = {0x30, 0x2f, 0x80, 0xdd, 0x41, 0x1e, 0x48, 0x86, 0xbc, 0xa5, 0xbb, 0x1f, 0x80, 0x18, 0xa0, 0x24};

    NSApplication* app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 540)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Parc FairPlay M0 proof";
    window.releasedWhenClosed = NO;
    [window center];
    NSView* host = window.contentView;
    host.wantsLayer = YES;
    host.layer.backgroundColor = NSColor.darkGrayColor.CGColor;
    world.host = host;
    [window makeKeyAndOrderFront:nil];
    [app activateIgnoringOtherApps:YES];

    Log("cache %s, video %s, %d segments", g_cache_dir.UTF8String, video_playlist.UTF8String, world.segments);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      std::string error;
      NSData* certificate = CachedGet(kCertificateUrl, 0, 0, &error);
      bool ok = certificate &&
                LoadMedia(kProtectedBase, video_playlist, world.segments, &world.video, &error) &&
                LoadMedia(kProtectedBase, @"audio-en.m3u8", world.segments, &world.audio, &error) &&
                LoadMedia(kClearBase, video_playlist, 1, &world.clear_video, &error) &&
                LoadMedia(kClearBase, @"audio-en.m3u8", 1, &world.clear_audio, &error) &&
                LoadMedia(kHevcBase, @"video-H265-720-2100k.m3u8", 2, &world.hevc_video, &error) &&
                LoadMedia(kHevcBase, @"audio-en.m3u8", 2, &world.hevc_audio, &error) &&
                LoadMedia(kMultiKeyBase, video_playlist, 2, &world.multi_video, &error) &&
                LoadMedia(kMultiKeyBase, @"audio-en.m3u8", 2, &world.multi_audio, &error) &&
                LoadChromiumFile(@"bear-320x240-v_frag-hevc.mp4", &world.hev1, &error) &&
                LoadChromiumFile(@"glass-blowing2-dolby-vision-profile-5-frag.mp4", &world.dolby_vision, &error) &&
                LoadChromiumFile(@"bear-av1.mp4", &world.av1, &error) &&
                LoadChromiumFile(@"noise-xhe-aac-44kHz.mp4", &world.xhe_aac, &error) &&
                EncodeAac(kAudioFormatMPEG4AAC_HE, 4, &world.he_aac, &error) &&
                EncodeAac(kAudioFormatMPEG4AAC_HE_V2, 4, &world.he_aac_v2, &error);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!Check(ok, "download and parse the Axinom vector", error)) Finish();
        g_certificate = Bytes(certificate);
        if (ok) world.hev1_in_band = InBandParameterSetsOnly(world.hev1);
        Log("certificate %zu bytes; video %zu segments, audio %zu segments", g_certificate.size(),
            world.video.segments.size(), world.audio.segments.size());
        RunAll();
      });
    });
    [app run];
  }
  return 0;
}

// FairPlay M0 proof: the engine-independent key session and renderer in
// Engine/ParcNative/fairplay play Axinom's public "CMAF H264 SingleKey (cbcs)"
// test vector with a real FairPlay license exchange, in a visible window.
// Protected video can't be captured, so playback is proven through the
// synchronizer clock, renderer status and AVFoundation's frame metrics.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <functional>
#include <memory>
#include <mutex>
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

// A whole MP4 (fragmented or progressive) from |url|, cached as |cache_name|;
// |base64| for Gitiles' ?format=TEXT.
bool LoadMp4File(NSString* url, NSString* cache_name, bool base64, Media* media, std::string* error) {
  NSString* name = cache_name;
  NSString* path = [g_cache_dir stringByAppendingPathComponent:cache_name];
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (!data) {
    Http http = Fetch(url, @"GET", nil, @{});
    data = http.status != 200 ? nil
           : base64           ? [[NSData alloc] initWithBase64EncodedData:http.body
                                                            options:NSDataBase64DecodingIgnoreUnknownCharacters]
                              : http.body;
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

bool LoadChromiumFile(NSString* name, Media* media, std::string* error) {
  return LoadMp4File([NSString stringWithFormat:@"%@%@?format=TEXT", kChromiumTestData, name],
                     [@"chromium_" stringByAppendingString:name], true, media, error);
}

// DASH-IF's 7.1 Dolby Digital Plus channel-ID stream (Dolby Media Generator):
// an independent 5.1 substream plus a dependent one with Lrs/Rrs.
NSString* const kDdp71 = @"https://dash.akamaized.net/dash264/TestCasesMCA/dolby/2/1/ChID_voices_71_768_ddp_A.mp4";

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

void PollUntil(double deadline, std::function<bool()> ready, std::function<void(bool)> done) {
  if (ready()) {
    done(true);
    return;
  }
  if (CFAbsoluteTimeGetCurrent() >= deadline) {
    done(false);
    return;
  }
  After(0.01, [=] { PollUntil(deadline, ready, done); });
}

// Calls |done(true)| once |ready| holds (checked every 10 ms), or
// |done(false)| once |timeout| seconds have passed.
void WaitUntil(double timeout, std::function<bool()> ready, std::function<void(bool)> done) {
  PollUntil(CFAbsoluteTimeGetCurrent() + timeout, std::move(ready), std::move(done));
}

// The core's posted tasks can be held back, to line up a callback the
// renderer has already queued against a Flush. Never destroyed: AVFoundation
// threads may still post while exit() runs static destructors.
struct PostHold {
  std::mutex mutex;
  bool holding = false;
  std::vector<std::function<void()>> tasks;
};
PostHold& Hold() {
  static PostHold* hold = new PostHold;
  return *hold;
}

fp::PostTask MainPoster() {
  return [](std::function<void()> task) {
    PostHold& hold = Hold();
    std::lock_guard<std::mutex> lock(hold.mutex);
    if (hold.holding) {
      hold.tasks.push_back(std::move(task));
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      task();
    });
  };
}

void HoldPosts() {
  std::lock_guard<std::mutex> lock(Hold().mutex);
  Hold().holding = true;
}

// Queues the held tasks on the main queue, in order, and stops holding.
void ReleasePosts() {
  PostHold& hold = Hold();
  std::lock_guard<std::mutex> lock(hold.mutex);
  hold.holding = false;
  for (std::function<void()>& task : hold.tasks) {
    std::function<void()> run = std::move(task);
    dispatch_async(dispatch_get_main_queue(), ^{
      run();
    });
  }
  hold.tasks.clear();
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
  std::vector<fp::MessageType> message_types;
  // Closes the session from inside OnSessionKeysChange (re-entrancy check).
  bool close_on_keys_change = false;
  int messages = 0;
  int keys_events = 0;
  bool closed = false;
  std::vector<fp::KeyInfo> keys;
  std::function<void(bool, const std::string&)> on_update;

  void OnSessionMessage(const std::string& session_id,
                        fp::MessageType type,
                        const std::vector<uint8_t>& message) override {
    ++messages;
    message_types.push_back(type);
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
    if (close_on_keys_change) {
      close_on_keys_change = false;
      cdm->CloseSession(session_id, [](const fp::Result&) {});
    }
  }

  void OnSessionClosed(const std::string& session_id) override {
    closed = true;
    Log("%s: session %s closed", name_.c_str(), session_id.c_str());
  }

  // POSTs one SPC to the license service (blocking; off the main thread).
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

  NSString* token() const { return token_; }

 private:
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
  ks->cdm->SetServerCertificate(g_certificate, [name](const fp::Result& r) {
    Check(r.ok(), name + ": SetServerCertificate resolves", r.message);
  });
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

// What Chromium hands a renderer (MP4StreamParser): no video decoder record,
// Dolby Vision as profile and level only, no dac3/dec3, and encryption as
// the scheme alone.
bool g_chromium_inputs_default = false;

fp::VideoConfig VideoConfigFor(const ft::TrackInfo& info, Framing framing, bool chromium_inputs);
fp::AudioConfig AudioConfigFor(const ft::TrackInfo& info, Framing framing, bool chromium_inputs);

fp::VideoConfig VideoConfigFor(const ft::TrackInfo& info, Framing framing) {
  return VideoConfigFor(info, framing, false);
}

fp::AudioConfig AudioConfigFor(const ft::TrackInfo& info, Framing framing) {
  return AudioConfigFor(info, framing, false);
}

fp::VideoConfig VideoConfigFor(const ft::TrackInfo& info, Framing framing, bool chromium_inputs) {
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
  if (chromium_inputs) {
    vc.extra_data.clear();
    const std::vector<uint8_t>& dv = info.dolby_vision_config;
    if (dv.size() >= 5) {
      vc.dolby_vision_profile = dv[2] >> 1;
      vc.dolby_vision_level = ((dv[2] & 1) << 5) | (dv[3] >> 3);
      // Chromium has no compatibility ID; the renderer's default applies.
    }
    vc.dolby_vision_config.clear();
    vc.encryption = fp::TrackEncryption{info.encryption.scheme, {}, {}, 0, {}};
  }
  return vc;
}

fp::AudioConfig AudioConfigFor(const ft::TrackInfo& info, Framing framing, bool chromium_inputs) {
  fp::AudioConfig ac;
  const uint32_t f = info.original_format;
  const bool aac = f == fp::FourCC('m', 'p', '4', 'a');
  ac.codec = aac ? fp::AudioCodec::kAAC
                 : f == fp::FourCC('e', 'c', '-', '3') ? fp::AudioCodec::kEAC3 : fp::AudioCodec::kAC3;
  ac.extra_data = info.codec_config;
  if (chromium_inputs && !aac) ac.extra_data.clear();
  ac.framing = framing == Framing::kChromium && aac && ft::AacObjectType(info.codec_config, true) <= 4
                   ? fp::AudioFraming::kADTS
                   : fp::AudioFraming::kRaw;
  ac.sample_rate = int32_t(info.sample_rate);
  ac.channels = info.channels;
  ac.encryption = info.encryption;
  if (chromium_inputs) ac.encryption = fp::TrackEncryption{info.encryption.scheme, {}, {}, 0, {}};
  return ac;
}

// Edits a scenario's configs before Initialize.
using ConfigAdjust = std::function<void(std::optional<fp::VideoConfig>*, std::optional<fp::AudioConfig>*)>;

class Player : public fp::FairPlayRendererClient {
 public:
  // Either stream may be null (single-stream codec checks).
  // |cdm_first| calls SetCdm before Initialize, Chromium's order when
  // MediaKeys were attached before playback.
  Player(std::string name, Framing framing, const Media* video, const Media* audio,
         fp::FairPlayCdm* cdm, NSView* host, bool cdm_first = false,
         bool chromium_inputs = g_chromium_inputs_default, ConfigAdjust adjust = nullptr)
      : chromium_inputs_(chromium_inputs),
        name_(std::move(name)),
        framing_(framing),
        has_video_(video != nullptr),
        has_audio_(audio != nullptr),
        video_info_(video ? video->info : ft::TrackInfo()),
        audio_info_(audio ? audio->info : ft::TrackInfo()),
        renderer_(this, MainPoster()),
        host_(host) {
    std::optional<fp::VideoConfig> vc;
    if (has_video_) vc = VideoConfigFor(video_info_, framing, chromium_inputs_);
    std::optional<fp::AudioConfig> ac;
    if (has_audio_) ac = AudioConfigFor(audio_info_, framing, chromium_inputs_);
    if (adjust) adjust(&vc, &ac);
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
  AVSampleBufferDisplayLayer* layer() const { return layer_; }
  NSView* host() const { return host_; }
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
  int need_data_calls = 0;
  int reconfigures = 0;
  std::vector<std::pair<int32_t, int32_t>> natural_sizes;
  // Flushes in the same task as the end of stream that completes both
  // streams (whose OnEnded is then already queued).
  bool flush_at_end_of_stream = false;
  // Like a batched DemuxerStream read: keeps enqueuing behind a sample held
  // for a key, through end of stream, instead of waiting for readiness.
  bool batch_reads = false;
  int ends_sent = 0;

  double Time() { return renderer_.GetMediaTime().InSeconds(); }
  bool EndOfStreamSent() const {
    return (!has_video_ || video_feed_.end_sent) && (!has_audio_ || audio_feed_.end_sent);
  }

  void SetFeeds(SegmentList video, SegmentList audio, bool end_of_stream) {
    video_feed_ = Feed{std::move(video), 0, 0, end_of_stream, false, {}, nullptr};
    audio_feed_ = Feed{std::move(audio), 0, 0, end_of_stream, false, {}, nullptr};
  }

  // Segments that each come with their own track (an adaptive-streaming
  // switch). Chromium converts each with its own init segment; a new audio
  // track reaches the renderer as Reconfigure (DemuxerStream kConfigChanged),
  // video as different in-band parameter sets.
  void SetFeedsWithTracks(SegmentList video, std::vector<const ft::TrackInfo*> video_tracks, SegmentList audio,
                          std::vector<const ft::TrackInfo*> audio_tracks, bool end_of_stream) {
    video_feed_ = Feed{std::move(video), 0, 0, end_of_stream, false, std::move(video_tracks), nullptr};
    audio_feed_ = Feed{std::move(audio), 0, 0, end_of_stream, false, std::move(audio_tracks), nullptr};
  }

  // More data arrives (as from the network): append and push it; with
  // |end_of_stream| it is the last.
  void AppendFeeds(const SegmentList& video, const SegmentList& audio, bool end_of_stream = false) {
    video_feed_.segments.insert(video_feed_.segments.end(), video.begin(), video.end());
    audio_feed_.segments.insert(audio_feed_.segments.end(), audio.begin(), audio.end());
    video_feed_.end_of_stream |= end_of_stream;
    audio_feed_.end_of_stream |= end_of_stream;
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
  void OnNeedData(fp::StreamType stream) override {
    ++need_data_calls;
    Pump(stream);
  }
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
    natural_sizes.push_back({width, height});
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
    std::vector<const ft::TrackInfo*> tracks;  // Per segment, or empty.
    const ft::TrackInfo* current = nullptr;
  };

  void Pump(fp::StreamType stream) {
    if (!(stream == fp::StreamType::kVideo ? has_video_ : has_audio_)) return;
    Feed& feed = stream == fp::StreamType::kVideo ? video_feed_ : audio_feed_;
    const ft::TrackInfo& default_info = stream == fp::StreamType::kVideo ? video_info_ : audio_info_;
    while (batch_reads || renderer_.IsReadyForMoreData(stream)) {
      while (feed.segment < feed.segments.size() && feed.index >= feed.segments[feed.segment]->size()) {
        ++feed.segment;
        feed.index = 0;
      }
      if (feed.segment >= feed.segments.size()) {
        if (feed.end_of_stream && !feed.end_sent) {
          feed.end_sent = true;
          ++ends_sent;
          renderer_.SetEndOfStream(stream);
          if (flush_at_end_of_stream && (!has_video_ || video_feed_.end_sent) &&
              (!has_audio_ || audio_feed_.end_sent)) {
            flush_at_end_of_stream = false;
            renderer_.Flush([] {});
          }
        }
        return;
      }
      const ft::TrackInfo& info = feed.tracks.empty() ? default_info : *feed.tracks[feed.segment];
      if (!feed.tracks.empty() && feed.current && feed.current != &info) {
        // A different track: audio needs Reconfigure; video signals itself
        // in-band (and gets Reconfigure too when full configs are in use).
        fp::Result result = stream == fp::StreamType::kAudio
                                ? renderer_.Reconfigure(AudioConfigFor(info, framing_, chromium_inputs_))
                                : (chromium_inputs_ ? fp::Result::Ok()
                                                    : renderer_.Reconfigure(VideoConfigFor(info, framing_, false)));
        ++reconfigures;
        if (!result.ok()) errors.push_back("Reconfigure: " + result.message);
      }
      feed.current = &info;
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
        if (batch_reads) continue;
        return;
      }
      if (result == fp::EnqueueResult::kRejected) {
        errors.push_back("enqueue rejected");
        return;
      }
      ++enqueued;
    }
  }

  bool chromium_inputs_;
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
  Media eac3_71;  // First 5 s of kDdp71.
  Media hev1, hev1_in_band, hev1_vps_once, dolby_vision, av1, av1_10bit, xhe_aac, he_aac, he_aac_v2, ac3, eac3, video_288,
      he_aac_after_clear;
  NSView* host = nil;
  std::unique_ptr<KeySystem> main_keys;
  std::vector<std::unique_ptr<KeySystem>> retired;
  std::shared_ptr<Player> player;
  int segments = 13;
};

World* g_world = nullptr;
std::string g_only;
// Set when the harness runs in a sandbox that denies Core Audio's services.
bool g_audio_unavailable = false;

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
      // A rate change may make the audio renderer flush itself; whatever it
      // dropped must have been enqueued again.
      fp::RendererStatus s = player()->renderer().GetStatus();
      Check(s.audio_automatic_flushes == 0 || s.redelivered > 0,
            name + ": automatic audio flushes during the rate steps were re-delivered",
            Format("%llu automatic flushes, %llu samples re-delivered",
                   (unsigned long long)s.audio_automatic_flushes, (unsigned long long)s.redelivered));
      done();
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

// |chromium_inputs|: Chromium's configs, so the protected formats must be
// built from the first encrypted sample's key ID, after clear ones.
std::vector<Step> MixedScenario(bool chromium_inputs = false) {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section(std::string("clear lead: segment 0 from the clear variant, then protected samples") +
                          (chromium_inputs ? " (Chromium inputs: empty record, scheme-only encryption)" : "")));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("mixed", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host, false, chromium_inputs);
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

// The default output device's Core Audio UID.
std::string DefaultOutputDeviceUid() {
  AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
                                        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioDeviceID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, &device) != noErr) {
    return "";
  }
  address.mSelector = kAudioDevicePropertyDeviceUID;
  CFStringRef uid = nullptr;
  size = sizeof(uid);
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &uid) != noErr || !uid) {
    return "";
  }
  std::string result = ((__bridge NSString*)uid).UTF8String;
  CFRelease(uid);
  return result;
}

// A page that loses its compositor has its display layer taken out of every
// layer tree, then put back. Playback must carry on without a seek; if the
// layer reports requiresFlushToResumeDecoding, the renderer re-feeds it from
// the last keyframe itself.
std::vector<Step> LayerDetachScenario() {
  World* w = g_world;
  auto before = std::make_shared<fp::RendererStatus>();
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("layer detach: the display layer leaves its tree mid-playback for 3 s, then returns"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("layer-detach", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 6, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(w->player, 2, 1, "layer-detach before detaching")(done); });
  steps.push_back([=](Done done) { Metrics(w->player, "layer-detach before detaching", 40, frames)(done); });
  steps.push_back([=](Done done) {
    *before = w->player->renderer().GetStatus();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [w->player->layer() removeFromSuperlayer];
    [CATransaction commit];
    Log("layer-detach: display layer removed from its tree");
    Run(w->player, 3, 1, "layer-detach while detached")(done);
  });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Log("layer-detach: while detached requires-flush=%d resets=%llu re-delivered=%llu", s.video_requires_flush,
        (unsigned long long)(s.video_decoder_resets - before->video_decoder_resets),
        (unsigned long long)(s.redelivered - before->redelivered));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    w->player->layer().frame = w->player->host().layer.bounds;
    [w->player->host().layer addSublayer:w->player->layer()];
    [CATransaction commit];
    Log("layer-detach: display layer back in its tree");
    Run(w->player, 3, 1, "layer-detach after reattaching")(done);
  });
  steps.push_back([=](Done done) { Metrics(w->player, "layer-detach after reattaching", 120, frames)(done); });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Log("layer-detach: in all requires-flush=%d resets=%llu re-delivered=%llu", s.video_requires_flush,
        (unsigned long long)(s.video_decoder_resets - before->video_decoder_resets),
        (unsigned long long)(s.redelivered - before->redelivered));
    Check(!s.video_requires_flush, "layer-detach: the video renderer doesn't still need a flush");
    Check(w->player->underflows == 0, "layer-detach: no HAVE_NOTHING across detach and reattach",
          Format("%d", w->player->underflows));
    w->player.reset();
    done();
  });
  return steps;
}

// Run inside a sandbox that denies Core Audio's services: the audio
// renderer is invalid and the synchronizer refuses it, which must fail
// Initialize with an error instead of throwing out of it.
std::vector<Step> AudioUnavailableScenario() {
  World* w = g_world;
  std::vector<Step> steps;
  steps.push_back(Section("Core Audio unavailable (sandboxed): Initialize fails instead of throwing"));
  steps.push_back([=](Done done) {
    struct NullClient : fp::FairPlayRendererClient {
      void OnNeedData(fp::StreamType) override {}
      void OnWaitingForKey() override {}
      void OnEnded() override {}
      void OnError(fp::RendererError, const std::string&) override {}
      void OnVideoNaturalSizeChange(int32_t, int32_t) override {}
      void OnBufferingStateChange(bool) override {}
    } client;
    const fp::VideoConfig vc = VideoConfigFor(w->video.info, Framing::kChromium, true);
    const fp::AudioConfig ac = AudioConfigFor(w->audio.info, Framing::kChromium, true);
    struct Case {
      bool video, audio;
      const char* label;
    };
    for (Case c : {Case{false, true, "audio only"}, Case{true, true, "video and audio"}, Case{true, false, "video only"}}) {
      fp::FairPlayRenderer renderer(&client, [](std::function<void()>) {});
      fp::Result result = renderer.Initialize(c.video ? std::optional<fp::VideoConfig>(vc) : std::nullopt,
                                              c.audio ? std::optional<fp::AudioConfig>(ac) : std::nullopt);
      if (c.audio) {
        Check(!result.ok() && result.message.find("audio renderer") != std::string::npos,
              std::string("audio unavailable: Initialize with ") + c.label + " returns an error",
              result.ok() ? "succeeded" : result.message);
        fp::Result again = renderer.Initialize(std::nullopt, ac);
        Check(!again.ok() && again.exception != fp::Exception::kInvalidState,
              std::string("audio unavailable: after the failure (") + c.label + ") the renderer is still uninitialized",
              again.message);
      } else {
        Check(result.ok(), std::string("audio unavailable: Initialize with ") + c.label + " still succeeds",
              result.message);
      }
    }
    done();
  });
  return steps;
}

// Moving audio to another output (setSinkId) makes AVSampleBufferAudioRenderer
// flush itself; the renderer must enqueue what was dropped again, or the
// queued duration plays as silence and the clock runs ahead of the audio.
std::vector<Step> AudioDeviceSwitchScenario() {
  World* w = g_world;
  auto before = std::make_shared<fp::RendererStatus>();
  std::vector<Step> steps;
  steps.push_back(Section("audio output switch: protected playback while audio moves to another device and back"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("device-switch", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 5, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(w->player, 2, 1, "device-switch before the switch")(done); });
  // "" first is a no-op (still following the default). Naming the device in
  // use flushes the audio renderer on this Mac, which must be re-delivered.
  // "" afterwards names the default device again (no flush expected).
  enum class Expect { kNoFlush, kFlush, kEither };
  struct Switch {
    bool explicit_device;
    Expect expect;
    const char* label;
  };
  for (Switch change : {Switch{false, Expect::kNoFlush, "the system default before any device"},
                        Switch{true, Expect::kFlush, "the explicit device"},
                        Switch{false, Expect::kEither, "the system default again"}}) {
    steps.push_back([=](Done done) {
      *before = w->player->renderer().GetStatus();
      std::string uid = change.explicit_device ? DefaultOutputDeviceUid() : "";
      Log("device-switch: audio output -> %s", uid.empty() ? "system default" : uid.c_str());
      fp::Result result = w->player->renderer().SetAudioOutputDevice(uid);
      Check(result.ok(), std::string("device-switch: SetAudioOutputDevice(") + (uid.empty() ? "default" : uid) + ")",
            result.message);
      Run(w->player, 3, 1, std::string("device-switch after switching to ") + change.label)(done);
    });
    steps.push_back([=](Done done) {
      fp::RendererStatus s = w->player->renderer().GetStatus();
      const uint64_t flushes = s.audio_automatic_flushes - before->audio_automatic_flushes;
      const uint64_t redelivered = s.redelivered - before->redelivered;
      Log("device-switch: %llu automatic flushes, %llu samples re-delivered", (unsigned long long)flushes,
          (unsigned long long)redelivered);
      const std::string counts =
          Format("%llu flushes, %llu re-delivered", (unsigned long long)flushes, (unsigned long long)redelivered);
      if (change.expect == Expect::kNoFlush) {
        Check(flushes == 0, std::string("device-switch: switching to ") + change.label + " changes nothing", counts);
      } else if (change.expect == Expect::kFlush) {
        Check(flushes >= 1 && redelivered > 0,
              std::string("device-switch: switching to ") + change.label +
                  " flushes the audio renderer and the dropped audio is re-delivered",
              counts);
      } else {
        Check(flushes == 0 || redelivered > 0, "device-switch: an automatic audio flush is followed by re-delivery",
              counts);
      }
      Check(w->player->underflows == 0, "device-switch: no HAVE_NOTHING across the switch",
            Format("%d", w->player->underflows));
      done();
    });
  }
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
    auto rejected = std::make_shared<int>(0);
    auto answered = std::make_shared<int>(0);
    auto failures = std::make_shared<std::string>();
    auto all_answered = std::make_shared<Done>();
    for (const auto& [name, body] : cases) {
      std::string case_name = name;
      size_t total = cases.size();
      ks->cdm->UpdateSession(ks->session, Bytes(body), [=](const fp::Result& r) {
        if (r.exception == fp::Exception::kTypeError) {
          ++*rejected;
        } else {
          *failures += (failures->empty() ? "" : ", ") + case_name;
        }
        if (size_t(++*answered) == total && *all_answered) (*all_answered)();
      });
    }
    *all_answered = [=] {
    Check(*rejected == int(cases.size()),
          Format("responses: %d malformed JSON responses each rejected with TypeError, no crash",
                 int(cases.size())),
          failures->empty() ? "" : "accepted: " + *failures);
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
    };
  });
  steps.push_back([=](Done done) {
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// Chromium's CompleteSeek: StartPlayingFrom and SetPlaybackRate in one task.
// The clock must stay at the seek time until HAVE_ENOUGH, then run.
std::vector<Step> SeekOrderScenario() {
  World* w = g_world;
  struct Probe {
    double max_before = -1;
    double at_enough = -1;
    int samples = 0;
    dispatch_source_t timer = nil;
  };
  auto probe = std::make_shared<Probe>();
  std::vector<Step> steps;
  steps.push_back(Section("Chromium seek order: StartPlayingFrom + SetPlaybackRate(1) in one task"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("seek-order", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(Segments(w->video, 6, 10), Segments(w->audio, 6, 10), false);
      auto finish = Once(10, "seek-order: HAVE_ENOUGH", [=](bool) {
        dispatch_source_cancel(probe->timer);
        done();
      });
      w->player->on_have_enough = [=] {
        probe->at_enough = w->player->Time();
        finish(true);
      };
      probe->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
      dispatch_source_set_timer(probe->timer, DISPATCH_TIME_NOW, NSEC_PER_MSEC * 10, NSEC_PER_MSEC);
      dispatch_source_set_event_handler(probe->timer, ^{
        if (w->player && !w->player->have_enough) {
          probe->max_before = std::max(probe->max_before, w->player->Time());
          ++probe->samples;
        }
      });
      dispatch_resume(probe->timer);
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(40000000));
      w->player->renderer().SetPlaybackRate(1);
    });
  });
  steps.push_back([=](Done done) {
    Check(probe->max_before >= 0 && std::fabs(probe->max_before - 40.0) < 0.001 &&
              std::fabs(probe->at_enough - 40.0) < 0.001,
          Format("seek-order: clock held at 40.000 until HAVE_ENOUGH (max %.3f over %d samples, %.3f at HAVE_ENOUGH)",
                 probe->max_before, probe->samples, probe->at_enough));
    done();
  });
  steps.push_back([=](Done done) { Run(w->player, 3, 1, "seek-order after HAVE_ENOUGH 3s")(done); });
  steps.push_back([=](Done done) {
    Check(w->player->underflows == 0, "seek-order: no underflow after the start",
          Format("%d", w->player->underflows));
    w->player.reset();
    done();
  });
  return steps;
}

// A short final chunk after an underflow (or a short ad, or a seek into the
// last second): too little for AVFoundation's sufficiency test, so end of
// stream must count as HAVE_ENOUGH or the clock never restarts.
std::vector<Step> ShortEndScenario() {
  World* w = g_world;
  auto tail_video = std::make_shared<std::vector<ft::Sample>>();
  auto tail_audio = std::make_shared<std::vector<ft::Sample>>();
  const double tail_end = 6.5;
  for (const ft::Sample& sample : w->video.segments[1]) {
    if (double(sample.pts + sample.duration) / w->video.info.timescale <= tail_end) tail_video->push_back(sample);
  }
  for (const ft::Sample& sample : w->audio.segments[1]) {
    if (double(sample.pts + sample.duration) / w->audio.info.timescale <= tail_end) tail_audio->push_back(sample);
  }
  std::vector<Step> steps;
  steps.push_back(Section("underflow, then a 0.5 s final chunk with end of stream"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("short-end", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 1, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    auto finish = Once(12, "short-end: underflow at 6 s", [=](bool) { done(); });
    w->player->on_have_nothing = [finish] { finish(true); };
  });
  steps.push_back([=](Done done) {
    auto enough = std::make_shared<bool>(false);
    w->player->on_have_enough = [enough] { *enough = true; };
    auto finish = Once(8, "short-end: OnEnded after the final chunk", [=](bool ok) {
      double t = w->player->Time();
      Check(*enough, "short-end: end of stream counts as HAVE_ENOUGH for the short chunk");
      if (ok) {
        double end = 0;
        for (const ft::Sample& sample : *tail_audio) end = std::max(end, double(sample.pts + sample.duration) / w->audio.info.timescale);
        for (const ft::Sample& sample : *tail_video) end = std::max(end, double(sample.pts + sample.duration) / w->video.info.timescale);
        Check(std::fabs(t - end) < 0.3, Format("short-end: ended at the chunk's end (t=%.3f, end %.3f)", t, end));
      }
      done();
    });
    w->player->on_ended = [finish] { finish(true); };
    Log("short-end: appending %zu video and %zu audio samples (to %.1f s) with end of stream",
        tail_video->size(), tail_audio->size(), tail_end);
    w->player->AppendFeeds({tail_video.get()}, {tail_audio.get()}, true);
  });
  steps.push_back([=](Done done) {
    CheckHealthy(*w->player, "short-end");
    w->player.reset();
    done();
  });
  return steps;
}

double EndSeconds(const Media& media);

// Tasks queued before a Flush must not land after it: an OnEnded queued by
// the end of stream (a seek near the end) or by the end-time observer, and
// OnNeedData queued by StartPlayingFrom or by an answered media request. Each
// held callback also gets a control run without the Flush, which must
// deliver it.
std::vector<Step> FlushRaceScenario() {
  World* w = g_world;
  const double end = std::max(EndSeconds(w->video), EndSeconds(w->audio));
  // Holds the core's posts until a media request has been answered (a
  // renderer ready again, its hand-over held), then releases them, after a
  // Flush when |flush|.
  auto held_request = [w](bool flush) -> Step {
    return [w, flush](Done done) {
      const std::string run = flush ? "with a Flush" : "control, no Flush";
      HoldPosts();
      auto fired = [w] {
        return w->player->renderer().IsReadyForMoreData(fp::StreamType::kVideo) ||
               w->player->renderer().IsReadyForMoreData(fp::StreamType::kAudio);
      };
      // Hand-overs queued before the hold run first and refill the renderers.
      After(0.3, [=] {
        const int at_hold = w->player->need_data_calls;
        WaitUntil(5, fired, [=](bool ok) {
          Check(ok, "flush-race: a renderer asks for more data while the hand-over is held (" + run + ")");
          After(0.2, [=] {
            int before = w->player->need_data_calls;
            Check(before == at_hold, "flush-race: no OnNeedData while the hand-over is held (" + run + ")",
                  Format("%d call(s)", before - at_hold));
            if (flush) w->player->renderer().Flush([] {});
            ReleasePosts();
            After(0.5, [=] {
              int calls = w->player->need_data_calls - before;
              if (flush) {
                Check(calls == 0, "flush-race: a media request answered before a Flush gives no OnNeedData after it",
                      Format("%d call(s)", calls));
              } else {
                Check(calls > 0, "flush-race: control: the held hand-over, released without a Flush, gives OnNeedData",
                      Format("%d call(s)", calls));
              }
              done();
            });
          });
        });
      });
    };
  };
  // Starts 3 s before the end with end of stream, so the end time is
  // watched; holds the core's posts across it, then releases them, after a
  // Flush when |flush|.
  auto near_end = [w, end](Done done) {
    w->player->ended = false;
    StartAt(w->player, &w->video, &w->audio, w->segments - 1, w->segments, end - 3, 1, true)(done);
  };
  auto held_end = [w, end](bool flush) -> Step {
    return [w, end, flush](Done done) {
      const std::string run = flush ? "with a Flush" : "control, no Flush";
      WaitUntil(2.5, [w] { return w->player->EndOfStreamSent(); }, [=](bool sent) {
        Check(sent && w->player->Time() < end - 0.2,
              "flush-race: both streams reach end of stream before the end time (" + run + ")",
              Format("sent %d at t=%.3f, end %.3f", sent, w->player->Time(), end));
        HoldPosts();
        WaitUntil(5, [w, end] { return w->player->Time() > end + 0.2; }, [=](bool ok) {
          Check(ok, Format("flush-race: the clock passes the end (%.3f) while the end callback is held (%s)", end,
                           run.c_str()),
                Format("t=%.3f", w->player->Time()));
          if (flush) w->player->renderer().Flush([] {});
          ReleasePosts();
          After(0.5, [=] {
            if (flush) {
              Check(!w->player->ended, "flush-race: an end time reached before a Flush gives no OnEnded after it");
            } else {
              Check(w->player->ended, "flush-race: control: the held end callback, released without a Flush, gives OnEnded");
            }
            done();
          });
        });
      });
    };
  };
  std::vector<Step> steps;
  steps.push_back(Section("Flush racing queued OnEnded and OnNeedData"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("flush-race", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host);
    w->player->renderer().Flush([=] {
      // Nothing to play: end of stream on both, then Flush in that same task.
      w->player->SetFeeds({}, {}, true);
      w->player->flush_at_end_of_stream = true;
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
      After(1.0, [=] {
        Check(!w->player->ended, "flush-race: no OnEnded after a Flush that followed the end of stream");
        done();
      });
    });
  });
  steps.push_back([=](Done done) {
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(Segments(w->video, 0, 1), Segments(w->audio, 0, 1), false);
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
      int before = w->player->need_data_calls;
      w->player->renderer().Flush([] {});
      After(0.5, [=] {
        Check(w->player->need_data_calls == before,
              "flush-race: no OnNeedData between Flush and the next StartPlayingFrom",
              Format("%d call(s)", w->player->need_data_calls - before));
        done();
      });
    });
  });
  // A media request AVFoundation already answered (its hand-over queued)
  // when the Flush comes: dropped, and the next start still gets data.
  steps.push_back([=](Done done) {
    StartAt(w->player, &w->video, &w->audio, 0, w->segments, 0, 1, false)(done);
  });
  steps.push_back(held_request(false));
  steps.push_back(held_request(true));
  steps.push_back([=](Done done) {
    w->player->SetFeeds(Segments(w->video, 0, w->segments), Segments(w->audio, 0, w->segments), false);
    auto go = Once(10, "flush-race: HAVE_ENOUGH after the dropped request", [=](bool) {
      w->player->renderer().SetPlaybackRate(1);
      done();
    });
    w->player->on_have_enough = [go] { go(true); };
    w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
  });
  steps.push_back([=](Done done) {
    int before = w->player->need_data_calls;
    Run(w->player, 4, 1, "flush-race: play 4s after the dropped request")([=] {
      Check(w->player->need_data_calls > before, "flush-race: media requests keep coming after the dropped one",
            Format("%d call(s) in 4s", w->player->need_data_calls - before));
      done();
    });
  });
  // The end-of-stream boundary observer fired before a Flush (its OnEnded
  // queued): dropped after it.
  steps.push_back(near_end);
  steps.push_back(held_end(false));
  steps.push_back(near_end);
  steps.push_back(held_end(true));
  steps.push_back([=](Done done) {
    w->player.reset();
    done();
  });
  return steps;
}

// Callbacks never run inside a call into the key system, so a client can
// re-enter it: here the session is closed from inside OnSessionKeysChange.
std::vector<Step> ReentrancyScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("callbacks: posted, and safe to re-enter (close inside OnSessionKeysChange)"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("reentry");
    KeySystem* ks = keys->get();
    bool ran = false;
    ks->cdm->SetServerCertificate(g_certificate, [&ran](const fp::Result&) { ran = true; });
    Check(!ran, "reentry: promise callbacks run in a later task, not inside the call");
    ks->client->close_on_keys_change = true;
    auto finish = Once(30, "reentry: session closed from inside OnSessionKeysChange", [=](bool) { done(); });
    ks->client->on_update = [=](bool ok, const std::string& detail) {
      Check(ok, "reentry: update resolves", detail);
      After(0.5, [=] {
        Check(ks->client->closed && !ks->cdm->HasUsableKey(g_key_id),
              "reentry: closing inside the keys callback completes (OnSessionClosed, key gone), no crash");
        finish(true);
      });
    };
    ks->cdm->CreateSessionAndGenerateRequest(fp::InitDataType::kSkd, Bytes(std::string(kSkd)),
                                             [ks](const fp::Result& r, const std::string& id) {
                                               ks->session = id;
                                               Check(r.ok(), "reentry: generateRequest resolves");
                                             });
  });
  steps.push_back([=](Done done) {
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// Two update() calls back to back (licenses fetched in parallel): the second
// waits for the first instead of being rejected.
std::vector<Step> QueuedUpdateScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("update() twice in a row on a three-key session"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("queued", kMultiKeyToken);
    KeySystem* ks = keys->get();
    ks->client->json = true;
    ks->client->hold = true;
    ks->client->on_message = [=] { done(); };
    ks->cdm->CreateSessionAndGenerateRequest(fp::InitDataType::kCenc, w->multi_video.info.pssh_boxes,
                                             [ks](const fp::Result& r, const std::string& id) {
                                               ks->session = id;
                                               Check(r.ok(), "queued: generateRequest resolves");
                                             });
  });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    NSData* body = Data(ks->client->held_message);
    NSString* token = ks->client->token();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray* entries = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
      NSMutableArray* answers = [NSMutableArray array];
      for (NSDictionary* entry in entries) {
        std::string failure;
        NSData* spc = [[NSData alloc] initWithBase64EncodedString:entry[@"payload"] options:0];
        std::vector<uint8_t> ckc = LicenseClient::Post(spc, "queued", token, &failure);
        [answers addObject:@{@"keyID" : entry[@"keyID"], @"payload" : [Data(ckc) base64EncodedStringWithOptions:0]}];
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        auto first = Bytes([NSJSONSerialization dataWithJSONObject:@[ answers.firstObject ] options:0 error:nil]);
        auto rest = Bytes([NSJSONSerialization
            dataWithJSONObject:[answers subarrayWithRange:NSMakeRange(1, answers.count - 1)]
                       options:0
                         error:nil]);
        auto results = std::make_shared<std::vector<bool>>();
        auto check = [=](const fp::Result& r) {
          results->push_back(r.ok());
          if (results->size() < 2) return;
          After(0.3, [=] {
            bool all = true;
            for (const auto& key : ks->client->keys) all &= key.status == fp::KeyStatus::kUsable;
            Check((*results)[0] && (*results)[1] && ks->client->keys.size() == 3 && all,
                  "queued: both updates resolve, in order, and all three keys are usable",
                  KeysText(ks->client->keys));
            done();
          });
        };
        ks->cdm->UpdateSession(ks->session, first, check);
        ks->cdm->UpdateSession(ks->session, rest, check);
      });
    });
  });
  steps.push_back([=](Done done) {
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// A request AVFoundation can't serve (a FairPlay pssh with no key entry):
// generateRequest must settle, through the failure path or the timeout.
std::vector<Step> NoHangScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("generateRequest that AVFoundation can't serve settles (3 s timeout)"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("no-hang");
    KeySystem* ks = keys->get();
    ks->cdm->SetRequestTimeout(3);
    std::vector<uint8_t> pssh = FairPlayPssh(std::vector<std::vector<uint8_t>>{}, fp::FourCC('c', 'b', 'c', 's'));
    double started = Now();
    auto finish = Once(8, "no-hang: generateRequest settles", [=](bool) { done(); });
    ks->cdm->CreateSessionAndGenerateRequest(fp::InitDataType::kCenc, pssh,
                                             [=](const fp::Result& r, const std::string&) {
                                               Check(!r.ok(), Format("no-hang: rejected after %.1f s", Now() - started),
                                                     r.message);
                                               finish(true);
                                             });
  });
  steps.push_back([=](Done done) {
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// License renewal while playing: the answered key stays usable while the
// renewal is in flight, after it succeeds, and after a failed one.
std::vector<Step> RenewalScenario() {
  World* w = g_world;
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  std::vector<Step> steps;
  steps.push_back(Section("license renewal during playback"));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("renewal");
    AcquireLicense(keys->get(), fp::InitDataType::kSkd, Bytes(std::string(kSkd)), "renewal", [=](bool) { done(); });
  });
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("renewal", Framing::kChromium, &w->video, &w->audio, (*keys)->cdm.get(),
                                         w->host);
    StartAt(w->player, &w->video, &w->audio, 0, 4, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    ks->client->hold = true;
    auto finish = Once(10, "renewal: renewal message", [=](bool) { done(); });
    ks->client->on_message = [finish] { finish(true); };
    ks->cdm->UpdateSession(ks->session, Bytes(std::string("renew")), [](const fp::Result& r) {
      Check(r.ok(), "renewal: update(\"renew\") resolves", r.message);
    });
  });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    Check(!ks->client->message_types.empty() && ks->client->message_types.back() == fp::MessageType::kLicenseRenewal,
          "renewal: a license-renewal message is sent");
    Check(ks->cdm->HasUsableKey(g_key_id), "renewal: key still usable while the renewal is in flight");
    Run(w->player, 2, 1, "renewal in flight, playing 2s")(done);
  });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    auto finish = Once(30, "renewal: response processed", [=](bool) { done(); });
    ks->client->on_update = [=](bool ok, const std::string& detail) {
      Check(ok && ks->cdm->HasUsableKey(g_key_id), "renewal: renewal response accepted, key usable", detail);
      finish(true);
    };
    ks->client->hold = false;
    ks->client->Respond(ks->client->held_session, ks->client->held_message);
  });
  steps.push_back([=](Done done) { Run(w->player, 2, 1, "renewal answered, playing 2s")(done); });
  steps.push_back([=](Done done) {
    KeySystem* ks = keys->get();
    ks->client->hold = true;
    ks->client->on_message = [=] {
      ks->cdm->UpdateSession(ks->client->held_session, Bytes(std::string("not a ckc")), [=](const fp::Result& r) {
        Check(!r.ok(), "renewal: a bad renewal response is rejected", r.message);
        After(0.3, [=] {
          Check(ks->cdm->HasUsableKey(g_key_id) && w->player->waiting_events == 0,
                "renewal: the answered key stays usable after a failed renewal, no OnWaitingForKey");
          done();
        });
      });
    };
    ks->cdm->UpdateSession(ks->session, Bytes(std::string("renew")), [](const fp::Result&) {});
  });
  steps.push_back([=](Done done) { Run(w->player, 2, 1, "renewal failed, still playing 2s")(done); });
  steps.push_back([=](Done done) {
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// Chromium's order when MediaKeys come first: SetCdm, then Initialize. The
// renderers must still join the key session (protected samples would
// otherwise fail with -11800 "no content key present").
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

// Whole GOPs from the start of |segment|: video in decode order up to the
// first keyframe at least |min_seconds| in (so every frame decodes), and the
// audio that ends by the last video frame's end.
struct Clip {
  std::vector<ft::Sample> video, audio;
  double start = 0, end = 0;
};

Clip ClipFrom(const Media& video, const Media& audio, size_t segment, double min_seconds) {
  Clip clip;
  const std::vector<ft::Sample>& frames = video.segments[segment];
  const double scale = video.info.timescale;
  clip.start = frames.empty() ? 0 : double(frames.front().pts) / scale;
  for (size_t i = 0; i < frames.size(); ++i) {
    if (i && frames[i].is_keyframe && double(frames[i].pts) / scale >= clip.start + min_seconds) break;
    clip.video.push_back(frames[i]);
    clip.end = std::max(clip.end, double(frames[i].pts + frames[i].duration) / scale);
  }
  for (const ft::Sample& sample : audio.segments[segment]) {
    if (double(sample.pts + sample.duration) / audio.info.timescale <= clip.end + 1e-6) clip.audio.push_back(sample);
  }
  return clip;
}

// Timeline of one player's buffering and end, for checks made after the fact.
struct Timeline {
  double enough_time = -1;  // Media time at the last HAVE_ENOUGH.
  double enough_wall = 0;
  bool enough_before_key = false;
  int enough_after_key = 0;
  double nothing_time = -1;
  double ended_time = -1;
  double ended_wall = 0;
  bool key_requested = false;
  std::function<void()> on_enough, on_nothing, on_ended;
};

// Records every HAVE_ENOUGH, HAVE_NOTHING and OnEnded of |player| into
// |line|. The player's hooks fire once, so each re-arms them.
void Record(Player* player, std::shared_ptr<Timeline> line) {
  player->on_have_enough = [player, line] {
    line->enough_time = player->Time();
    line->enough_wall = CFAbsoluteTimeGetCurrent();
    line->enough_before_key |= !line->key_requested;
    line->enough_after_key += line->key_requested;
    Record(player, line);
    if (auto f = std::move(line->on_enough)) f();
  };
  player->on_have_nothing = [player, line] {
    line->nothing_time = player->Time();
    Record(player, line);
    if (auto f = std::move(line->on_nothing)) f();
  };
  player->on_ended = [player, line] {
    line->ended_time = player->Time();
    line->ended_wall = CFAbsoluteTimeGetCurrent();
    if (auto f = std::move(line->on_ended)) f();
  };
}

// Runs |done| now if |happened|, else when |slot| fires (or after |timeout|).
void WaitFor(bool happened, std::function<void()>* slot, double timeout, const std::string& label,
             std::function<void(bool)> done) {
  auto finish = Once(timeout, label, done);
  if (happened) {
    finish(true);
  } else {
    *slot = [finish] { finish(true); };
  }
}

// A short clip (an ad, or a seek into the last seconds) enqueued in full
// with end of stream on both streams before its license arrives. Nothing
// counts as enough while its samples wait for the key, so the clock stays at
// the start despite rate 1; once the key arrives it plays from the start and
// ends at the clip's end, on time.
std::vector<Step> EndBeforeKeyScenario() {
  World* w = g_world;
  auto clip = std::make_shared<Clip>(ClipFrom(w->video, w->audio, 0, 2.0));
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  auto line = std::make_shared<Timeline>();
  struct Probe {
    double max_time = -1;
    int samples = 0;
    dispatch_source_t timer = nil;
  };
  auto probe = std::make_shared<Probe>();
  auto frames = std::make_shared<int64_t>(0);
  const double hold = clip->end - clip->start + 1.0;
  std::vector<Step> steps;
  steps.push_back(Section(Format("%.3f s clip with end of stream enqueued %.1f s before its license",
                                 clip->end - clip->start, hold)));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("eos-before-key");
    w->player = std::make_shared<Player>("eos-before-key", Framing::kChromium, &w->video, &w->audio,
                                         (*keys)->cdm.get(), w->host);
    w->player->batch_reads = true;
    Record(w->player.get(), line);
    w->player->renderer().Flush([=] {
      Log("eos-before-key: %zu video and %zu audio samples, %.3f-%.3f s, then end of stream",
          clip->video.size(), clip->audio.size(), clip->start, clip->end);
      w->player->SetFeeds({&clip->video}, {&clip->audio}, true);
      probe->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
      dispatch_source_set_timer(probe->timer, DISPATCH_TIME_NOW, NSEC_PER_MSEC * 10, NSEC_PER_MSEC);
      dispatch_source_set_event_handler(probe->timer, ^{
        if (w->player) {
          probe->max_time = std::max(probe->max_time, w->player->Time());
          ++probe->samples;
        }
      });
      dispatch_resume(probe->timer);
      // Chromium's CompleteSeek order.
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(int64_t(clip->start * 1e6)));
      w->player->renderer().SetPlaybackRate(1);
      After(hold, done);
    });
  });
  steps.push_back([=](Done done) {
    dispatch_source_cancel(probe->timer);
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(w->player->ends_sent == 2 && w->player->waiting_events == 1 && s.video_enqueued == 0 &&
              s.audio_enqueued == 0,
          "eos-before-key: every sample held for the key, end of stream on both streams",
          Format("ends %d, waiting events %d, held results %d, enqueued v/a %llu/%llu", w->player->ends_sent,
                 w->player->waiting_events, w->player->waiting_results, s.video_enqueued, s.audio_enqueued));
    Check(!line->enough_before_key && !w->player->have_enough && !w->player->ended,
          Format("eos-before-key: no HAVE_ENOUGH and no OnEnded during the %.1f s without the key", hold));
    Check(probe->samples > 0 && std::fabs(probe->max_time - clip->start) < 0.001,
          Format("eos-before-key: clock held at %.3f at rate 1 without the key (max %.3f over %d samples)",
                 clip->start, probe->max_time, probe->samples));
    line->key_requested = true;
    AcquireLicense(keys->get(), fp::InitDataType::kSkd, Bytes(std::string(kSkd)), "eos-before-key",
                   [=](bool) { done(); });
  });
  steps.push_back([=](Done done) {
    WaitFor(line->enough_after_key > 0, &line->on_enough, 10,
            "eos-before-key: HAVE_ENOUGH once the key arrives", [=](bool ok) {
              if (ok) {
                Check(line->enough_time - clip->start < 0.1,
                      Format("eos-before-key: playback starts from the clip's start (t=%.3f at HAVE_ENOUGH)",
                             line->enough_time));
              }
              done();
            });
  });
  steps.push_back([=](Done done) {
    WaitFor(line->ended_time >= 0, &line->on_ended, clip->end - clip->start + 5,
            "eos-before-key: OnEnded at the clip's end", [=](bool ok) {
              if (ok) {
                double played = line->ended_wall - line->enough_wall;
                double expected = clip->end - std::max(line->enough_time, clip->start);
                Check(std::fabs(line->ended_time - clip->end) < 0.3,
                      Format("eos-before-key: ended at the clip's end (t=%.3f, end %.3f)", line->ended_time,
                             clip->end));
                Check(line->enough_time >= 0 && std::fabs(played - expected) < 0.35,
                      Format("eos-before-key: no skip, %.3f s of wall time from HAVE_ENOUGH to OnEnded for "
                             "%.3f s of media",
                             played, expected));
              }
              done();
            });
  });
  steps.push_back([=](Done done) {
    Metrics(w->player, "eos-before-key", int64_t(clip->video.size() / 2), frames)(done);
  });
  steps.push_back([=](Done done) {
    CheckHealthy(*w->player, "eos-before-key");
    w->player.reset();
    w->retired.push_back(std::move(*keys));
    done();
  });
  return steps;
}

// A clear lead, then a protected tail whose key hasn't arrived, then end of
// stream (a key change in the last period). The clock stops where the
// enqueued data ends instead of running on past the held samples, and
// resumes from there once the key arrives. Video only: resuming audio from an
// underflow onto protected samples after clear ones moves the synchronizer's
// clock back to about zero whether or not a key was held, a separate defect.
std::vector<Step> HeldTailScenario() {
  World* w = g_world;
  auto tail = std::make_shared<Clip>(ClipFrom(w->video, w->audio, 1, 1.5));
  auto keys = std::make_shared<std::unique_ptr<KeySystem>>();
  auto line = std::make_shared<Timeline>();
  std::vector<Step> steps;
  steps.push_back(Section(Format("clear video lead, then a %.3f s protected tail and end of stream before its license",
                                 tail->end - tail->start)));
  steps.push_back([=](Done done) {
    *keys = MakeKeySystem("held-tail");
    w->player = std::make_shared<Player>("held-tail", Framing::kChromium, &w->video, nullptr,
                                         (*keys)->cdm.get(), w->host);
    Record(w->player.get(), line);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds({&w->clear_video.segments[0]}, {}, false);
      WaitFor(false, &line->on_enough, 10, "held-tail: HAVE_ENOUGH on the clear lead", [=](bool) {
        // The rest arrives in one batch: the protected tail, held for its
        // key, then end of stream.
        w->player->batch_reads = true;
        w->player->AppendFeeds({&tail->video}, {}, true);
        done();
      });
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
      w->player->renderer().SetPlaybackRate(1);
    });
  });
  steps.push_back([=](Done done) {
    WaitFor(false, &line->on_nothing, 12, "held-tail: HAVE_NOTHING where the clear lead ends", [=](bool ok) {
      if (ok) {
        Check(line->nothing_time > 5.6 && line->nothing_time < 6.1,
              Format("held-tail: stopped at t=%.3f, the end of the enqueued data (6.0)", line->nothing_time));
      }
      done();
    });
  });
  steps.push_back([=](Done done) {
    double before = w->player->Time();
    After(1.0, [=] {
      double t = w->player->Time();
      fp::RendererStatus s = w->player->renderer().GetStatus();
      Check(w->player->ends_sent == 1 && std::fabs(t - before) < 0.02 && !w->player->ended,
            Format("held-tail: clock stopped while the tail waits for its key (%.3f -> %.3f over 1 s), "
                   "end of stream sent",
                   before, t),
            Format("ends %d, protected enqueued %llu", w->player->ends_sent, s.protected_enqueued));
      line->key_requested = true;
      AcquireLicense(keys->get(), fp::InitDataType::kSkd, Bytes(std::string(kSkd)), "held-tail",
                     [=](bool) { done(); });
    });
  });
  steps.push_back([=](Done done) {
    WaitFor(line->enough_after_key > 0, &line->on_enough, 10, "held-tail: HAVE_ENOUGH once the key arrives",
            [=](bool) { done(); });
  });
  steps.push_back([=](Done done) {
    WaitFor(line->ended_time >= 0, &line->on_ended, tail->end - tail->start + 5,
            "held-tail: OnEnded at the tail's end", [=](bool ok) {
              if (ok) {
                double played = line->ended_wall - line->enough_wall;
                double expected = tail->end - line->enough_time;
                Check(std::fabs(line->ended_time - tail->end) < 0.3,
                      Format("held-tail: ended at the tail's end (t=%.3f, end %.3f)", line->ended_time, tail->end));
                Check(std::fabs(played - expected) < 0.35,
                      Format("held-tail: no skip, %.3f s of wall time from HAVE_ENOUGH (t=%.3f) to OnEnded for "
                             "%.3f s of media",
                             played, line->enough_time, expected));
              }
              done();
            });
  });
  steps.push_back([=](Done done) {
    CheckHealthy(*w->player, "held-tail");
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
    // The message is held to check it names each key once, and that a
    // response naming a key twice is still rejected before anything reaches
    // AVFoundation; then the real exchange runs.
    (*keys)->client->hold = true;
    (*keys)->client->on_message = [=] {
      KeySystem* ks = keys->get();
      NSArray* entries = [NSJSONSerialization JSONObjectWithData:Data(ks->client->held_message) options:0 error:nil];
      std::vector<std::vector<uint8_t>> named;
      std::vector<NSString*> named64;
      if ([entries isKindOfClass:[NSArray class]]) {
        for (NSDictionary* entry in entries) {
          NSString* key64 = [entry isKindOfClass:[NSDictionary class]] ? entry[@"keyID"] : nil;
          NSData* key = [key64 isKindOfClass:[NSString class]]
                            ? [[NSData alloc] initWithBase64EncodedString:key64 options:0]
                            : nil;
          named.push_back(key ? Bytes(key) : std::vector<uint8_t>());
          named64.push_back(key64);
        }
      }
      bool each_once = named.size() == key_ids.size();
      std::string names;
      for (const auto& id : key_ids) each_once &= std::count(named.begin(), named.end(), id) == 1;
      for (const auto& id : named) names += (names.empty() ? "" : ", ") + ft::Hex(id);
      Check(each_once, label + ": the license message has one SPC per key, each named by its own key ID",
            "[" + names + "]");
      // Two responses that name a key twice: alone, and among all three.
      // Each must be rejected before any entry reaches AVFoundation. If an
      // entry got through, its request would no longer await a response, and
      // the real exchange that follows could not complete.
      std::vector<std::string> cases;
      if (each_once) {
        auto entry = [&](size_t i) {
          return "{\"keyID\":\"" + std::string(named64[i].UTF8String) + "\",\"payload\":\"AAAA\"}";
        };
        cases = {"[" + entry(0) + "," + entry(0) + "]",
                 "[" + entry(0) + "," + entry(1) + "," + entry(2) + "," + entry(1) + "]"};
      }
      auto respond = [=] {
        KeySystem* ks = keys->get();
        ks->client->hold = false;
        ks->client->Respond(ks->client->held_session, ks->client->held_message);
      };
      if (cases.empty()) {
        respond();
        return;
      }
      auto rejected = std::make_shared<int>(0);
      auto answered = std::make_shared<size_t>(0);
      for (const std::string& body : cases) {
        size_t total = cases.size();
        ks->cdm->UpdateSession(ks->client->held_session, Bytes(body), [=](const fp::Result& r) {
          *rejected += r.exception == fp::Exception::kTypeError;
          if (++*answered < total) return;
          Check(*rejected == int(total),
                label + ": a response naming a key twice (alone, or among all three) is rejected with TypeError",
                Format("%d of %zu rejected", *rejected, total));
          respond();
        });
      }
    };
    AcquireLicense(keys->get(), fp::InitDataType::kCenc, init_data, label,
                   [=](bool ok) {
                     *acquired = ok;
                     KeySystem* ks = keys->get();
                     size_t usable = 0;
                     for (const fp::KeyInfo& key : ks->client->keys) usable += key.status == fp::KeyStatus::kUsable;
                     Check(ks->client->messages == messages_before + 1 && ks->client->keys.size() == 3 && usable == 3,
                           label + ": one license message for all three keys, three keys reported usable",
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

// The protected H.264 vector's first |segments| with SPS and PPS only
// in-band: the avcC keeps its length size but lists none, and each keyframe
// starts with them, length-prefixed, inside its first subsample's clear bytes.
Media InBandAvcParameterSetsOnly(const Media& media, size_t segments) {
  Media out;
  out.info = media.info;
  out.segments.assign(media.segments.begin(), media.segments.begin() + std::min(segments, media.segments.size()));
  const std::vector<uint8_t>& record = media.info.codec_config;
  if (!Check(record.size() >= 7, "in-band-protected: the vector's avcC has a full header")) return out;
  const size_t length_size = (record[4] & 3) + 1;
  std::vector<uint8_t> prefix;
  size_t pos = 6;
  bool ok = true;
  auto take = [&] {
    if (pos + 2 > record.size()) return ok = false;
    const size_t len = (size_t(record[pos]) << 8) | record[pos + 1];
    if (pos + 2 + len > record.size()) return ok = false;
    for (size_t b = length_size; b-- > 0;) prefix.push_back(uint8_t(len >> (8 * b)));
    prefix.insert(prefix.end(), record.begin() + pos + 2, record.begin() + pos + 2 + len);
    pos += 2 + len;
    return true;
  };
  for (int k = 0; ok && k < (record[5] & 0x1f); ++k) take();
  ok = ok && pos < record.size();
  for (int k = 0, pps = ok ? record[pos++] : 0; ok && k < pps; ++k) take();
  if (!Check(ok && !prefix.empty(), "in-band-protected: SPS and PPS read from the vector's avcC")) return out;
  out.info.codec_config.assign(record.begin(), record.begin() + 5);
  out.info.codec_config.push_back(0xe0);  // No SPS.
  out.info.codec_config.push_back(0);     // No PPS.
  for (auto& segment : out.segments) {
    for (ft::Sample& sample : segment) {
      if (!sample.is_keyframe) continue;
      const size_t size = sample.data.size();
      sample.data.insert(sample.data.begin(), prefix.begin(), prefix.end());
      if (!sample.decrypt) continue;
      std::vector<fp::SubsampleEntry>& subsamples = sample.decrypt->subsamples;
      if (subsamples.empty()) {
        subsamples.push_back({uint32_t(prefix.size()), uint32_t(size)});
      } else {
        subsamples[0].clear_bytes += uint32_t(prefix.size());
      }
    }
  }
  return out;
}

// The in-band stream played twice in a row, the second copy's keyframes
// without their VPS: a later keyframe that repeats only SPS and PPS, which
// must merge with the VPS already known instead of replacing it.
Media VpsOnFirstKeyframeOnly(const Media& media) {
  Media out = media;
  const size_t length_size = (media.info.codec_config[21] & 3) + 1;
  const int64_t shift = int64_t(EndSeconds(media) * media.info.timescale + 0.5);
  int stripped = 0;
  for (std::vector<ft::Sample> segment : media.segments) {
    for (ft::Sample& sample : segment) {
      sample.pts += shift;
      sample.dts += shift;
      if (!sample.is_keyframe) continue;
      std::vector<uint8_t> kept;
      for (size_t pos = 0; pos + length_size < sample.data.size();) {
        size_t length = 0;
        for (size_t k = 0; k < length_size; ++k) length = (length << 8) | sample.data[pos + k];
        const size_t end = std::min(sample.data.size(), pos + length_size + length);
        if (((sample.data[pos + length_size] >> 1) & 0x3f) != 32) {
          kept.insert(kept.end(), sample.data.begin() + pos, sample.data.begin() + end);
        }
        pos = end;
      }
      stripped += kept.size() != sample.data.size();
      sample.data = std::move(kept);
    }
    out.segments.push_back(std::move(segment));
  }
  Check(stripped > 0, Format("hev1 VPS dropped from %d keyframes of the second copy", stripped));
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
struct CodecOptions {
  ConfigAdjust adjust;
  // When set, every natural size reported must be this one.
  std::pair<int32_t, int32_t> natural_size{0, 0};
};

std::vector<Step> CodecScenario(const std::string& label, const Media* video, const Media* audio,
                                const std::string& protected_type, CodecOptions options = {}) {
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
    w->player = std::make_shared<Player>(label, Framing::kChromium, video, audio, nullptr, w->host, false, true,
                                         options.adjust);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(video ? Segments(*video, 0, video->segments.size()) : SegmentList(),
                          audio ? Segments(*audio, 0, audio->segments.size()) : SegmentList(), true);
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
      if (options.natural_size.first) {
        std::string sizes;
        bool all = !w->player->natural_sizes.empty();
        for (auto [width, height] : w->player->natural_sizes) {
          sizes += Format("%s%dx%d", sizes.empty() ? "" : ", ", width, height);
          all &= width == options.natural_size.first && height == options.natural_size.second;
        }
        Check(all, label + Format(": only the config's natural size %dx%d is reported", options.natural_size.first,
                                  options.natural_size.second),
              sizes);
      }
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

// The core rebuilds what Chromium leaves out; each must equal the box the
// file itself carries.
void BuilderSelfTests() {
  World* w = g_world;
  auto first_keyframe_av1 = [](const Media& m) -> std::optional<std::vector<uint8_t>> {
    for (const ft::Sample& sample : m.segments[0]) {
      if (!sample.is_keyframe) continue;
      if (auto obu = fp::Av1SequenceHeaderObu(sample.data.data(), sample.data.size())) {
        return fp::Av1CodecConfigurationRecord(*obu);
      }
    }
    return std::nullopt;
  };
  for (const Media* m : {&w->av1, &w->av1_10bit}) {
    auto built = first_keyframe_av1(*m);
    Check(built && *built == m->info.codec_config,
          "builders: av1C from the first keyframe's sequence header equals the file's",
          "file " + ft::Hex(m->info.codec_config) + (built ? ", built " + ft::Hex(*built) : ", none"));
  }
  const std::vector<uint8_t>& dv = w->dolby_vision.info.dolby_vision_config;
  Check(fp::DolbyVisionConfigurationRecord(5, 5, 0) == dv,
        "builders: Dolby Vision record from profile 5, level 5, compatibility 0 equals the file's dvcC",
        ft::Hex(dv));
  auto dac3 = fp::Ac3SpecificBoxPayload(w->ac3.segments[0][0].data.data(), w->ac3.segments[0][0].data.size());
  Check(dac3 && *dac3 == w->ac3.info.codec_config, "builders: dac3 from the first AC-3 syncframe equals the file's",
        "file " + ft::Hex(w->ac3.info.codec_config) + (dac3 ? ", built " + ft::Hex(*dac3) : ", none"));
  auto dec3 = fp::Eac3SpecificBoxPayload(w->eac3.segments[0][0].data.data(), w->eac3.segments[0][0].data.size());
  const std::vector<uint8_t>& file = w->eac3.info.codec_config;
  // data_rate (13 bits) is informational: computed from the frames it is the
  // true rate; the file's muxer wrote another. The substream fields must match.
  bool same = dec3 && file.size() >= dec3->size() && dec3->size() >= 5 && ((*dec3)[1] & 0x07) == (file[1] & 0x07) &&
              std::equal(dec3->begin() + 2, dec3->end(), file.begin() + 2);
  Check(same, "builders: dec3 from the first E-AC-3 syncframe matches the file's substream fields",
        "file " + ft::Hex(file) + (dec3 ? ", built " + ft::Hex(*dec3) : ", none"));

  // Synthetic E-AC-3 access units: 48 kHz, bsid 16.
  auto frame = [](int strmtyp, int substreamid, int numblkscod, int acmod, int lfeon, int chanmap, size_t bytes) {
    std::vector<uint8_t> out;
    uint64_t acc = 0;
    int count = 0;
    auto put = [&](uint64_t value, int bits) {
      for (int i = bits - 1; i >= 0; --i) {
        acc = (acc << 1) | ((value >> i) & 1);
        if (++count == 8) {
          out.push_back(uint8_t(acc));
          acc = count = 0;
        }
      }
    };
    put(0x0b77, 16);
    put(strmtyp, 2);
    put(substreamid, 3);
    put(bytes / 2 - 1, 11);
    put(0, 2);  // fscod 48 kHz
    put(numblkscod, 2);
    put(acmod, 3);
    put(lfeon, 1);
    put(16, 5);  // bsid
    put(31, 5);  // dialnorm
    put(0, 1);   // compre
    if (strmtyp == 1) {
      put(chanmap >= 0, 1);
      if (chanmap >= 0) put(chanmap, 16);
    }
    while (count) put(0, 1);
    out.resize(bytes, 0);
    return out;
  };
  auto join = [](std::vector<std::vector<uint8_t>> parts) {
    std::vector<uint8_t> out;
    for (auto& part : parts) out.insert(out.end(), part.begin(), part.end());
    return out;
  };
  // Two 3-block syncframes of one independent substream: one dec3 entry, its
  // 192 kb/s counted once.
  std::vector<uint8_t> halves = join({frame(0, 0, 2, 7, 1, -1, 384), frame(0, 0, 2, 7, 1, -1, 384)});
  auto grouped = fp::Eac3SpecificBoxPayload(halves.data(), halves.size());
  const std::vector<uint8_t> grouped_expected = {0x06, 0x00, 0x20, 0x0f, 0x00};
  Check(grouped && *grouped == grouped_expected,
        "builders: dec3 groups an independent substream's syncframes into one entry",
        grouped ? ft::Hex(*grouped) : "none");
  // 5.1 independent plus a dependent substream adding Lrs/Rrs (7.1): one
  // dependent, chan_loc Lrs/Rrs, 320 kb/s.
  std::vector<uint8_t> seven_one = join({frame(0, 0, 3, 7, 1, -1, 768), frame(1, 0, 3, 2, 0, 0x0200, 512)});
  auto dependent = fp::Eac3SpecificBoxPayload(seven_one.data(), seven_one.size());
  const std::vector<uint8_t> dependent_expected = {0x0a, 0x00, 0x20, 0x0f, 0x02, 0x02};
  Check(dependent && *dependent == dependent_expected,
        "builders: dec3 counts dependent substreams and writes their chan_loc",
        dependent ? ft::Hex(*dependent) : "none");
  // Encrypted samples: only clear headers are read.
  const std::vector<fp::SubsampleEntry> all_protected;
  const std::vector<fp::SubsampleEntry> clear_header = {{12, uint32_t(halves.size() - 12)}};
  auto from_protected = fp::Eac3SpecificBoxPayload(halves.data(), halves.size(), &all_protected);
  auto from_clear_header = fp::Eac3SpecificBoxPayload(halves.data(), halves.size(), &clear_header);
  Check(!from_protected && from_clear_header && *from_clear_header == grouped_expected,
        "builders: dec3 reads only syncframe headers in clear bytes",
        Format("whole-sample protected: %s; clear header: %s", from_protected ? ft::Hex(*from_protected).c_str() : "none",
               from_clear_header ? ft::Hex(*from_clear_header).c_str() : "none"));
  const std::vector<uint8_t>& ac3_sample = w->ac3.segments[0][0].data;
  const std::vector<fp::SubsampleEntry> ac3_clear8 = {{8, uint32_t(ac3_sample.size() - 8)}};
  const std::vector<fp::SubsampleEntry> ac3_clear4 = {{4, uint32_t(ac3_sample.size() - 4)}};
  auto ac3_ok = fp::Ac3SpecificBoxPayload(ac3_sample.data(), ac3_sample.size(), &ac3_clear8);
  Check(ac3_ok && *ac3_ok == w->ac3.info.codec_config &&
            !fp::Ac3SpecificBoxPayload(ac3_sample.data(), ac3_sample.size(), &ac3_clear4) &&
            !fp::Ac3SpecificBoxPayload(ac3_sample.data(), ac3_sample.size(), &all_protected),
        "builders: dac3 reads the syncframe only when its header is in clear bytes");
  // From the decoder config: the same layout fields as the files' boxes (the
  // bit rate is unknown and written as 0).
  auto ac3_config = fp::Ac3SpecificBoxFromConfig(int(w->ac3.info.sample_rate), w->ac3.info.channels);
  const std::vector<uint8_t>& ac3_file = w->ac3.info.codec_config;
  Check(ac3_config && ac3_config->size() == 3 && ac3_file.size() == 3 && (*ac3_config)[0] == ac3_file[0] &&
            ((*ac3_config)[1] & 0xfc) == (ac3_file[1] & 0xfc),
        "builders: dac3 from rate and channels has the file's fscod, bsid, bsmod, acmod and lfeon",
        "file " + ft::Hex(ac3_file) + (ac3_config ? ", built " + ft::Hex(*ac3_config) : ", none") +
            Format(" (%u Hz, %u channels)", w->ac3.info.sample_rate, w->ac3.info.channels));
  auto eac3_config = fp::Eac3SpecificBoxFromConfig(int(w->eac3.info.sample_rate), w->eac3.info.channels);
  Check(eac3_config && eac3_config->size() >= 5 && file.size() >= eac3_config->size() &&
            ((*eac3_config)[1] & 0x07) == (file[1] & 0x07) &&
            std::equal(eac3_config->begin() + 2, eac3_config->end(), file.begin() + 2),
        "builders: dec3 from rate and channels has the file's substream fields",
        "file " + ft::Hex(file) + (eac3_config ? ", built " + ft::Hex(*eac3_config) : ", none") +
            Format(" (%u Hz, %u channels)", w->eac3.info.sample_rate, w->eac3.info.channels));
  Check(fp::DefaultDolbyVisionCompatibilityId(5) == 0 && fp::DefaultDolbyVisionCompatibilityId(8) == 1 &&
            fp::DefaultDolbyVisionCompatibilityId(9) == 2,
        "builders: Dolby Vision compatibility ID defaults to 0 for profile 5, 1 (HDR10) for 8 and 2 (SDR) for 9");
  // Two programs whose 3-block frames interleave (I0 D0 I1 D1 I0 D0): each
  // dependent belongs to the independent frame just before it.
  std::vector<uint8_t> programs = join({frame(0, 0, 2, 7, 1, -1, 384), frame(1, 0, 2, 2, 0, 0x0200, 256),
                                        frame(0, 1, 2, 2, 0, -1, 256), frame(1, 0, 2, 2, 0, 0x0100, 256),
                                        frame(0, 0, 2, 7, 1, -1, 384), frame(1, 0, 2, 2, 0, 0x0200, 256)});
  auto two = fp::Eac3SpecificBoxPayload(programs.data(), programs.size());
  std::string layout;
  if (two) {
    // num_ind_sub, then per substream: dependents and chan_loc.
    size_t bit = 13;
    auto read = [&](int n) {
      uint32_t v = 0;
      for (int i = 0; i < n; ++i, ++bit) v = (v << 1) | (((*two)[bit / 8] >> (7 - bit % 8)) & 1);
      return v;
    };
    const uint32_t count = read(3) + 1;
    for (uint32_t i = 0; i < count && bit + 23 <= two->size() * 8; ++i) {
      read(2 + 5 + 1 + 1 + 3 + 3 + 1 + 3);
      const uint32_t dependents = read(4);
      const uint32_t chan_loc = dependents ? read(9) : (read(1), 0u);
      layout += Format("%s%u:%03x", layout.empty() ? "" : " ", dependents, chan_loc);
    }
  }
  Check(layout == "1:002 1:004", "builders: dec3 credits each dependent substream to its own program",
        two ? ft::Hex(*two) + " -> " + layout : "none");
  // A real 7.1 stream from Dolby's muxer: the box built from its first
  // syncframes must equal the file's, chan_loc included.
  const std::vector<uint8_t>& au71 = w->eac3_71.segments[0][0].data;
  auto built71 = fp::Eac3SpecificBoxPayload(au71.data(), au71.size());
  Check(built71 && *built71 == w->eac3_71.info.codec_config,
        "builders: dec3 from a 7.1 Dolby Digital Plus access unit equals the file's (Lrs/Rrs in chan_loc)",
        "file " + ft::Hex(w->eac3_71.info.codec_config) + (built71 ? ", built " + ft::Hex(*built71) : ", none"));
  // Parameter set IDs: the files' own sets declare 0; synthetic PPS with ID 1.
  std::string ids;
  auto add_ids = [&](bool hevc, const std::vector<uint8_t>& record) {
    std::vector<uint8_t> data;
    // Parameter sets from the record, through the Annex B conversion.
    ft::AvcToAnnexB(record, hevc, true, &data, nullptr);
    for (size_t i = 0; i + 4 < data.size();) {
      size_t next = i + 4;
      while (next + 4 <= data.size() && !(data[next] == 0 && data[next + 1] == 0 && data[next + 2] == 0 &&
                                          data[next + 3] == 1)) {
        ++next;
      }
      if (next + 4 > data.size()) next = data.size();
      auto id = fp::ParameterSetId(hevc, data.data() + i + 4, next - i - 4);
      ids += id ? Format("%u", *id) : "-";
      i = next;
    }
  };
  add_ids(false, w->video.info.codec_config);
  ids += "/";
  add_ids(true, w->hev1.info.codec_config);
  const uint8_t avc_pps1[] = {0x68, 0x40}, hevc_pps1[] = {0x44, 0x01, 0x40};
  auto avc1 = fp::ParameterSetId(false, avc_pps1, sizeof(avc_pps1));
  auto hevc1 = fp::ParameterSetId(true, hevc_pps1, sizeof(hevc_pps1));
  // H.264 PPS 200: ue(200) = 7 zeros, 1, then 7 bits of 201 - 128 = 73.
  const uint8_t avc_pps200[] = {0x68, 0x01, 0x92, 0x80};
  auto avc200 = fp::ParameterSetId(false, avc_pps200, sizeof(avc_pps200));
  // HEVC SPS 3 with one sub-layer (level present), emulation-prevented: the
  // 96-bit general profile_tier_level of zeros needs 0x03 after each 00 00.
  std::vector<uint8_t> rbsp = {0x03};                 // VPS 0, max_sub_layers_minus1 1, nesting 1
  rbsp.insert(rbsp.end(), 12, 0x00);                  // general profile, tier, level
  rbsp.insert(rbsp.end(), {0x40, 0x00, 0x00, 0x24});  // flags 0 1, reserved, level, ue(3), stop
  std::vector<uint8_t> sps3 = {0x42, 0x01};
  int zeros = 0;
  for (uint8_t b : rbsp) {
    if (zeros == 2 && b <= 3) {
      sps3.push_back(0x03);
      zeros = 0;
    }
    sps3.push_back(b);
    zeros = b == 0 ? zeros + 1 : 0;
  }
  auto hevc_sps3 = fp::ParameterSetId(true, sps3.data(), sps3.size());
  Check(ids == "00/000" && avc1 == 1u && hevc1 == 1u && avc200 == 200u && hevc_sps3 == 3u,
        "builders: parameter set IDs read from H.264 SPS/PPS and HEVC VPS/SPS/PPS",
        ids + Format(", PPS 1: %d %d, H.264 PPS 200: %d, HEVC SPS 3 with a sub-layer: %d", avc1 ? int(*avc1) : -1,
                     hevc1 ? int(*hevc1) : -1, avc200 ? int(*avc200) : -1, hevc_sps3 ? int(*hevc_sps3) : -1));
  auto core = fp::Eac3SpecificBoxFromConfig(48000, 8);
  Check(core && core == fp::Eac3SpecificBoxFromConfig(48000, 6),
        "builders: dec3 from a 7.1 config describes its 5.1 core", core ? ft::Hex(*core) : "none");

  // Chromium's whole-sample-encrypted AC-3/E-AC-3: no dac3/dec3 in the config
  // and no clear syncframe, so the renderer builds the box from rate and
  // channels and the protected format comes out as Apple's.
  if (g_audio_unavailable) {
    Log("builders: renderer audio checks skipped (Core Audio is denied in this run)");
    return;
  }
  struct Fallback {
    const Media* media;
    const char* type;
    int channels;  // 0: the file's.
  };
  for (Fallback fallback : {Fallback{&w->ac3, "qac3", 0}, Fallback{&w->eac3, "qec3", 0}, Fallback{&w->eac3, "qec3", 8}}) {
    const Media* media = fallback.media;
    const char* type = fallback.type;
    struct NullClient : fp::FairPlayRendererClient {
      void OnNeedData(fp::StreamType) override {}
      void OnWaitingForKey() override {}
      void OnEnded() override {}
      void OnError(fp::RendererError, const std::string&) override {}
      void OnVideoNaturalSizeChange(int32_t, int32_t) override {}
      void OnBufferingStateChange(bool) override {}
    } client;
    fp::FairPlayRenderer renderer(&client, [](std::function<void()>) {});
    fp::AudioConfig ac = AudioConfigFor(media->info, Framing::kChromium, true);
    ac.encryption.scheme = fp::EncryptionScheme::kCbcs;
    if (fallback.channels) ac.channels = fallback.channels;
    fp::Result result = renderer.Initialize(std::nullopt, ac);
    const ft::Sample& first = media->segments[0][0];
    fp::EncodedSample sample;
    sample.data = first.data.data();
    sample.size = first.data.size();
    sample.pts = fp::MediaTime::FromMicroseconds(0);
    sample.duration = fp::MediaTime::FromMicroseconds(32000);
    sample.is_keyframe = true;
    sample.decrypt = fp::DecryptInfo{fp::EncryptionScheme::kCbcs, g_key_id, std::vector<uint8_t>(16, 0x5a), {},
                                     fp::EncryptionPattern{0, 0}};
    fp::EnqueueResult enqueued = result.ok() ? renderer.Enqueue(fp::StreamType::kAudio, sample)
                                             : fp::EnqueueResult::kRejected;
    fp::RendererStatus s = renderer.GetStatus();
    Check(enqueued == fp::EnqueueResult::kWaitingForKey && ft::FourCCString(s.audio_protected_format) == type,
          std::string("renderer: whole-sample-encrypted ") + (media == &w->ac3 ? "AC-3" : "E-AC-3") +
              Format(" (%d channels)", ac.channels) + " with no config box gets '" + type +
              "' built from rate and channels",
          Format("Initialize %s, enqueue %d, protected '%s'", result.ok() ? "ok" : result.message.c_str(),
                 int(enqueued), ft::FourCCString(s.audio_protected_format).c_str()));
  }
}

// Chromium's configs for protected playback: no decoder record (built from
// in-band SPS/PPS) and only the encryption scheme (protected formats built
// from each sample's key ID, pattern and 16-byte IV).
std::vector<Step> ChromiumInputsScenario() {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("Chromium inputs: protected playback with an empty record and scheme-only encryption"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("chromium-inputs", Framing::kChromium, &w->video, &w->audio,
                                         w->main_keys->cdm.get(), w->host, false, true);
    StartAt(w->player, &w->video, &w->audio, 0, 3, 0, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(w->player, 5, 1, "chromium-inputs play 5s")(done); });
  steps.push_back([=](Done done) { Metrics(w->player, "chromium-inputs", 90, frames)(done); });
  steps.push_back([=](Done done) {
    StartAt(w->player, &w->video, &w->audio, 6, 9, 40, 1, false)(done);
  });
  steps.push_back([=](Done done) { Run(w->player, 3, 1, "chromium-inputs after seek 3s")(done); });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(ft::FourCCString(s.video_format) == "avc1" && ft::FourCCString(s.video_protected_format) == "qavc" &&
              ft::FourCCString(s.audio_protected_format) == "qaac",
          "chromium-inputs: formats built from the bitstream and the samples' key ID",
          Format("video '%s'/'%s', audio '%s'", ft::FourCCString(s.video_format).c_str(),
                 ft::FourCCString(s.video_protected_format).c_str(),
                 ft::FourCCString(s.audio_protected_format).c_str()));
    w->player.reset();
    done();
  });
  return steps;
}

// Protected samples whose SPS and PPS travel only in-band, length-prefixed
// (ChromiumInputsScenario covers Annex B): the record comes from the first
// protected keyframe, and the protected format is rebuilt on it.
std::vector<Step> ProtectedInBandScenario() {
  World* w = g_world;
  auto media = std::make_shared<Media>();
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("protected samples with SPS and PPS only in-band (length-prefixed)"));
  steps.push_back([=](Done done) {
    *media = InBandAvcParameterSetsOnly(w->video, 2);
    // Video only, so every protected sample counted is video.
    w->player = std::make_shared<Player>("in-band-protected", Framing::kIso, media.get(), nullptr,
                                         w->main_keys->cdm.get(), w->host);
    w->player->renderer().Flush([=] {
      w->player->SetFeeds(Segments(*media, 0, 2), {}, false);
      auto go = Once(10, "in-band-protected: HAVE_ENOUGH", [=](bool) {
        w->player->renderer().SetPlaybackRate(1);
        done();
      });
      w->player->on_have_enough = [go] { go(true); };
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    });
  });
  steps.push_back([=](Done done) { Run(w->player, 4, 1, "in-band-protected play 4s")(done); });
  steps.push_back([=](Done done) { Metrics(w->player, "in-band-protected", 70, frames)(done); });
  steps.push_back([=](Done done) {
    fp::RendererStatus s = w->player->renderer().GetStatus();
    Check(s.protected_enqueued > 0 && s.protected_enqueued == s.video_enqueued &&
              ft::FourCCString(s.video_format) == "avc1" &&
              ft::FourCCString(s.video_protected_format) == "qavc",
          "in-band-protected: protected samples played on a record built from in-band SPS and PPS",
          Format("protected %llu of %llu, video '%s'/'%s'", s.protected_enqueued, s.video_enqueued,
                 ft::FourCCString(s.video_format).c_str(),
                 ft::FourCCString(s.video_protected_format).c_str()));
    w->player.reset();
    done();
  });
  return steps;
}

// An adaptive-streaming switch, as Chromium delivers it: 288p, 720p, 288p
// segments (one key), each converted with its own init segment, no record in
// the config. The renderer must rebuild its formats from each new keyframe.
std::vector<Step> QualitySwitchScenario() {
  World* w = g_world;
  auto frames = std::make_shared<int64_t>(0);
  std::vector<Step> steps;
  steps.push_back(Section("quality switch 288p -> 720p -> 288p (Chromium inputs, protected)"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("switch", Framing::kChromium, &w->video_288, &w->audio,
                                         w->main_keys->cdm.get(), w->host, false, true);
    w->player->renderer().Flush([=] {
      w->player->SetFeedsWithTracks({&w->video_288.segments[0], &w->video.segments[1], &w->video_288.segments[2]},
                                    {&w->video_288.info, &w->video.info, &w->video_288.info},
                                    Segments(w->audio, 0, 3), {}, true);
      auto go = Once(10, "switch: HAVE_ENOUGH", [=](bool) {
        w->player->renderer().SetPlaybackRate(1);
        done();
      });
      w->player->on_have_enough = [go] { go(true); };
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    });
  });
  steps.push_back([=](Done done) {
    auto finish = Once(26, "switch: OnEnded after the third segment", [=](bool) { done(); });
    if (w->player->ended) finish(true);
    else w->player->on_ended = [finish] { finish(true); };
  });
  steps.push_back([=](Done done) {
    std::string sizes;
    for (auto& [width, height] : w->player->natural_sizes) sizes += Format("%s%dx%d", sizes.empty() ? "" : " -> ", width, height);
    const auto& n = w->player->natural_sizes;
    bool sequence = n.size() >= 3 && n[0] == std::make_pair(512, 288) &&
                    std::find(n.begin(), n.end(), std::make_pair(1280, 720)) != n.end() && n.back() == std::make_pair(512, 288);
    Check(sequence, "switch: natural size follows the segments", sizes);
    CheckHealthy(*w->player, "switch");
    Metrics(w->player, "switch", 380, frames)(done);
  });
  steps.push_back([=](Done done) {
    w->player.reset();
    done();
  });
  return steps;
}

// A new AudioSpecificConfig mid-stream (AAC-LC, then HE-AAC), which only
// Reconfigure can signal.
std::vector<Step> AudioReconfigureScenario() {
  World* w = g_world;
  double end = EndSeconds(w->he_aac_after_clear);
  std::vector<Step> steps;
  steps.push_back(Section("audio Reconfigure: AAC-LC, then HE-AAC (Chromium's kConfigChanged)"));
  steps.push_back([=](Done done) {
    w->player = std::make_shared<Player>("audio-switch", Framing::kChromium, nullptr, &w->clear_audio, nullptr,
                                         w->host, false, true);
    w->player->renderer().Flush([=] {
      w->player->SetFeedsWithTracks({}, {}, {&w->clear_audio.segments[0], &w->he_aac_after_clear.segments[0]},
                                    {&w->clear_audio.info, &w->he_aac_after_clear.info}, true);
      auto go = Once(10, "audio-switch: HAVE_ENOUGH", [=](bool) {
        w->player->renderer().SetPlaybackRate(1);
        done();
      });
      w->player->on_have_enough = [go] { go(true); };
      w->player->renderer().StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    });
  });
  steps.push_back([=](Done done) {
    auto finish = Once(end + 8, "audio-switch: OnEnded", [=](bool ok) {
      double t = w->player->Time();
      if (ok) Check(std::fabs(t - end) < 0.3, Format("audio-switch: ended at the end (t=%.3f, end %.3f)", t, end));
      Check(w->player->reconfigures == 1, "audio-switch: one Reconfigure, accepted",
            Format("%d", w->player->reconfigures));
      CheckHealthy(*w->player, "audio-switch");
      done();
    });
    if (w->player->ended) finish(true);
    else w->player->on_ended = [finish] { finish(true); };
  });
  steps.push_back([=](Done done) {
    w->player.reset();
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
    ks->cdm->RemoveSession(ks->session, [=](const fp::Result& r) {
      After(0.2, [=] {
        Check(r.ok() && !ks->cdm->HasUsableKey(g_key_id) && !ks->client->keys.empty() &&
                  ks->client->keys[0].status == fp::KeyStatus::kReleased,
              "remove: keys reported released and no longer attachable", KeysText(ks->client->keys));
        ks->cdm->CloseSession(ks->session, [=](const fp::Result& closed) {
          After(0.2, [=] {
            Check(closed.ok() && ks->client->closed, "close: promise resolves and OnSessionClosed fires");
            ks->cdm->UpdateSession(ks->session, {1, 2, 3}, [=](const fp::Result& update) {
              Check(update.exception == fp::Exception::kInvalidState,
                    "close: update on a closed session is rejected (InvalidStateError)");
              done();
            });
          });
        });
      });
    });
  });
  return steps;
}

// Watchdog: the run must never wait forever. A main-queue heartbeat is
// checked from a background queue; if the main thread stalls for 15 s, or the
// whole run exceeds its time limit, the main thread's stack is sampled into
// the log and the process exits with status 3 (stall) or 4 (time limit).
std::atomic<double> g_heartbeat{0};
double g_time_limit = 480;

void StartWatchdog() {
  static dispatch_source_t beat =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(beat, DISPATCH_TIME_NOW, NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
  dispatch_source_set_event_handler(beat, ^{
    g_heartbeat = Now();
  });
  dispatch_resume(beat);
  static dispatch_source_t check = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
  dispatch_source_set_timer(check, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC,
                            NSEC_PER_SEC / 10);
  dispatch_source_set_event_handler(check, ^{
    double now = Now();
    double stalled = now - g_heartbeat.load();
    bool stall = g_heartbeat.load() > 0 && stalled > 15;
    bool over = now > g_time_limit;
    // Short stalls (the heartbeat beats every 0.5 s) delay callbacks enough to
    // fail timing checks; the first few are sampled while still in progress,
    // without stopping the run, to show what holds the main thread.
    static std::atomic<bool> sampling{false};
    static std::atomic<int> short_samples{0};
    if (!stall && !over && g_heartbeat.load() > 0 && stalled > 1.2 && short_samples.load() < 4 &&
        !sampling.exchange(true)) {
      const int index = ++short_samples;
      std::string path = std::string(NSTemporaryDirectory().UTF8String) +
                         Format("fairplay-proof-stall-%d-%d.txt", getpid(), index);
      Log("WATCHDOG: main thread late by %.1f s; sampling it (%s)", stalled, path.c_str());
      std::string command =
          Format("/usr/bin/sample %d 1 1 -mayDie -file '%s' >/dev/null 2>&1", getpid(), path.c_str());
      if (system(command.c_str()) == 0) {
        NSString* text = [NSString stringWithContentsOfFile:@(path.c_str()) encoding:NSUTF8StringEncoding error:nil];
        bool main_thread = false;
        int printed = 0;
        for (NSString* line in [text componentsSeparatedByString:@"\n"]) {
          if ([line containsString:@"com.apple.main-thread"]) main_thread = true;
          else if (main_thread && [line containsString:@"Thread_"]) break;
          if (main_thread && printed++ < 60) printf("    %s\n", line.UTF8String);
        }
        fflush(stdout);
      }
      sampling.store(false);
      return;
    }
    if (!stall && !over) return;
    if (stall) {
      Log("WATCHDOG: main thread stalled for %.0f s; sampling its stack", stalled);
    } else {
      Log("WATCHDOG: run exceeded its %.0f s limit; sampling the main thread", g_time_limit);
    }
    std::string path = std::string(NSTemporaryDirectory().UTF8String) +
                       Format("fairplay-proof-sample-%d.txt", getpid());
    std::string command = Format("/usr/bin/sample %d 2 -file '%s' >/dev/null 2>&1", getpid(), path.c_str());
    if (system(command.c_str()) == 0) {
      NSString* text = [NSString stringWithContentsOfFile:@(path.c_str()) encoding:NSUTF8StringEncoding error:nil];
      NSArray* lines = [text componentsSeparatedByString:@"\n"];
      bool main_thread = false;
      int printed = 0;
      for (NSString* line in lines) {
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
  BuilderSelfTests();
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
  add("MixedScenario(chromium)", MixedScenario(true));
  add("ChromiumInputsScenario()", ChromiumInputsScenario());
  add("ProtectedInBandScenario()", ProtectedInBandScenario());
  add("QualitySwitchScenario()", QualitySwitchScenario());
  add("UnderflowScenario()", UnderflowScenario());
  add("AudioDeviceSwitchScenario()", AudioDeviceSwitchScenario());
  add("LayerDetachScenario()", LayerDetachScenario());
  if (g_audio_unavailable) add("AudioUnavailableScenario()", AudioUnavailableScenario());
  add("CdmFirstScenario()", CdmFirstScenario());
  add("SeekOrderScenario()", SeekOrderScenario());
  add("ShortEndScenario()", ShortEndScenario());
  add("FlushRaceScenario()", FlushRaceScenario());
  add("ResponseValidationScenario()", ResponseValidationScenario());
  add("ReentrancyScenario()", ReentrancyScenario());
  add("QueuedUpdateScenario()", QueuedUpdateScenario());
  add("NoHangScenario()", NoHangScenario());
  add("RenewalScenario()", RenewalScenario());
  add("WaitingForKeyScenario()", WaitingForKeyScenario());
  add("EndBeforeKeyScenario()", EndBeforeKeyScenario());
  add("HeldTailScenario()", HeldTailScenario());

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
  add("CodecScenario(AC-3)", CodecScenario("AC-3 (ac-3)", nullptr, &w->ac3, "qac3"));
  add("CodecScenario(E-AC-3)", CodecScenario("E-AC-3 (ec-3)", nullptr, &w->eac3, "qec3"));
  add("CodecScenario(E-AC-3 7.1)", CodecScenario("E-AC-3 7.1 (DASH-IF channel ID, dec3 built from syncframes)",
                                                 nullptr, &w->eac3_71, "qec3"));
  add("CodecScenario(AV1 10-bit)", CodecScenario("AV1 10-bit (av01)", &w->av1_10bit, nullptr, "qav1"));
  add("CodecScenario(hev1 VPS once)",
      CodecScenario("hev1 with the VPS on the first keyframe only", &w->hev1_vps_once, nullptr, ""));
  {
    const std::pair<int32_t, int32_t> natural{int32_t(w->hev1_in_band.info.width) * 4 / 3,
                                              int32_t(w->hev1_in_band.info.height)};
    add("CodecScenario(config natural size)",
        CodecScenario("hev1 in-band with a config natural size", &w->hev1_in_band, nullptr, "",
                      {[natural](std::optional<fp::VideoConfig>* vc, std::optional<fp::AudioConfig>*) {
                         (*vc)->natural_width = natural.first;
                         (*vc)->natural_height = natural.second;
                       },
                       natural}));
  }
  auto from_config = [](bool eac3) {
    return [eac3](std::optional<fp::VideoConfig>*, std::optional<fp::AudioConfig>* ac) {
      auto box = eac3 ? fp::Eac3SpecificBoxFromConfig((*ac)->sample_rate, (*ac)->channels)
                      : fp::Ac3SpecificBoxFromConfig((*ac)->sample_rate, (*ac)->channels);
      Check(box.has_value(), std::string(eac3 ? "dec3" : "dac3") + " from rate and channels is built");
      if (box) (*ac)->extra_data = *box;
    };
  };
  add("CodecScenario(AC-3 config box)",
      CodecScenario("AC-3 with dac3 from rate and channels", nullptr, &w->ac3, "", {from_config(false)}));
  add("CodecScenario(E-AC-3 config box)",
      CodecScenario("E-AC-3 with dec3 from rate and channels", nullptr, &w->eac3, "", {from_config(true)}));
  add("AudioReconfigureScenario()", AudioReconfigureScenario());
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
    // A covered window that plays no audio (the video-only codec clips) is
    // App Napped: timers, time observers and callbacks then arrive seconds
    // late and timing checks fail. The proof opts out for its whole run.
    static id<NSObject> no_app_nap = [[NSProcessInfo processInfo]
        beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical
                          reason:@"FairPlay proof timing"];
    (void)no_app_nap;
    StartWatchdog();
    NSString* video_playlist = @"video-H264-720-2100k.m3u8";
    g_cache_dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"parc-fairplay-cache"];
    for (int i = 1; i + 1 < argc; i += 2) {
      std::string flag = argv[i];
      if (flag == "--cache") g_cache_dir = @(argv[i + 1]);
      else if (flag == "--video-playlist") video_playlist = @(argv[i + 1]);
      else if (flag == "--segments") world.segments = std::max(10, atoi(argv[i + 1]));
      else if (flag == "--only") g_only = argv[i + 1];
      else if (flag == "--time-limit") g_time_limit = atof(argv[i + 1]);
      else if (flag == "--audio-unavailable") g_audio_unavailable = atoi(argv[i + 1]) != 0;
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
                EncodeAac(kAudioFormatMPEG4AAC_HE_V2, 4, &world.he_aac_v2, &error) &&
                LoadChromiumFile(@"bear-av1-320x180-10bit.mp4", &world.av1_10bit, &error) &&
                LoadChromiumFile(@"bear-ac3-only-frag.mp4", &world.ac3, &error) &&
                LoadChromiumFile(@"bear-eac3-only-frag.mp4", &world.eac3, &error) &&
                LoadMp4File(kDdp71, @"dashif_ChID_voices_71_768_ddp_A.mp4", false, &world.eac3_71, &error) &&
                LoadMedia(kProtectedBase, @"video-H264-288-400k.m3u8", 3, &world.video_288, &error);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!Check(ok, "download and parse the Axinom vector", error)) Finish();
        g_certificate = Bytes(certificate);
        if (ok) {
          world.hev1_in_band = InBandParameterSetsOnly(world.hev1);
          {
            std::vector<ft::Sample>& samples = world.eac3_71.segments[0];
            const int64_t limit = int64_t(world.eac3_71.info.timescale) * 5;
            samples.erase(std::remove_if(samples.begin(), samples.end(),
                                         [limit](const ft::Sample& sample) { return sample.pts >= limit; }),
                          samples.end());
          }
          world.hev1_vps_once = VpsOnFirstKeyframeOnly(world.hev1_in_band);
          // HE-AAC continuing the clear AAC-LC segment, for an audio Reconfigure.
          world.he_aac_after_clear = world.he_aac;
          int64_t shift = int64_t(EndSeconds(world.clear_audio) * world.he_aac.info.timescale + 0.5);
          for (ft::Sample& sample : world.he_aac_after_clear.segments[0]) {
            sample.pts += shift;
            sample.dts += shift;
          }
        }
        Log("certificate %zu bytes; video %zu segments, audio %zu segments", g_certificate.size(),
            world.video.segments.size(), world.audio.segments.size());
        RunAll();
      });
    });
    [app run];
  }
  return 0;
}

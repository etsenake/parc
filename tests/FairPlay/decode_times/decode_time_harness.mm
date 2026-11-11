#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <memory>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>

#include "fairplay_bitstream.h"
#include "fairplay_key_session.h"
#include "fairplay_renderer.h"
#include "sample_encryptor.h"

namespace fp = parc::fairplay;
namespace ft = parc::fairplay::test;

namespace {

constexpr int kBits = 16;
constexpr int kFps = 24;

uint32_t g_rng = 0x9e3779b9;
inline uint32_t Next() {
  g_rng ^= g_rng << 13;
  g_rng ^= g_rng >> 17;
  g_rng ^= g_rng << 5;
  return g_rng;
}

int WriteYuv(int frames, int width, int height) {
  const int pad = 1024;
  const int tw = width + pad, th = height + pad;
  std::vector<uint8_t> texture(size_t(tw) * th);
  for (auto& v : texture) v = uint8_t(Next());
  for (int pass = 0; pass < 2; ++pass) {
    for (int y = 0; y < th; ++y) {
      for (int x = 1; x < tw - 1; ++x) {
        uint8_t* p = &texture[size_t(y) * tw + x];
        *p = uint8_t((p[-1] + 2 * p[0] + p[1]) / 4);
      }
    }
  }
  std::vector<uint8_t> frame(size_t(width) * height * 3 / 2);
  const int block_w = width / kBits, block_h = height / 12;
  for (int n = 0; n < frames; ++n) {
    const int dx = (n * 5) % pad, dy = (n * 2) % pad;
    for (int y = 0; y < height; ++y) {
      const uint8_t* row = &texture[size_t(y + dy) * tw + dx];
      uint8_t* out = &frame[size_t(y) * width];
      for (int x = 0; x < width; ++x) {
        int v = row[x] + int(Next() % 25) - 12;
        out[x] = uint8_t(std::clamp(v, 16, 235));
      }
    }
    for (int b = 0; b < kBits; ++b) {
      const bool bit = (n >> (kBits - 1 - b)) & 1;
      for (int r = 0; r < 2; ++r) {
        const uint8_t v = (bit != (r == 1)) ? 235 : 16;
        for (int y = r * block_h; y < (r + 1) * block_h; ++y) {
          memset(&frame[size_t(y) * width + b * block_w], v, block_w);
        }
      }
    }
    memset(&frame[size_t(width) * height], 128, size_t(width) * height / 2);
    if (fwrite(frame.data(), 1, frame.size(), stdout) != frame.size()) return 1;
  }
  return 0;
}

struct Sample {
  std::vector<uint8_t> data;
  std::vector<fp::SubsampleEntry> subsamples;
  int64_t display = 0;
  int64_t decode = 0;
  bool keyframe = false;
};

int NalType(const uint8_t* nal) { return (nal[0] >> 1) & 0x3f; }

std::vector<Sample> ReadAccessUnits(const std::vector<uint8_t>& bytes) {
  std::vector<size_t> starts;
  std::vector<size_t> nals;
  for (size_t i = 0; i + 3 < bytes.size(); ++i) {
    if (bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1) {
      starts.push_back(i > 0 && bytes[i - 1] == 0 ? i - 1 : i);
      nals.push_back(i + 3);
      i += 2;
    }
  }
  std::vector<Sample> samples;
  for (size_t k = 0; k < nals.size(); ++k) {
    const size_t end = k + 1 < nals.size() ? starts[k + 1] : bytes.size();
    if (NalType(&bytes[nals[k]]) == 35) {
      samples.emplace_back();
      continue;
    }
    if (samples.empty()) samples.emplace_back();
    Sample& s = samples.back();
    const int type = NalType(&bytes[nals[k]]);
    s.keyframe |= type >= 16 && type <= 21;
    s.data.insert(s.data.end(), {0, 0, 0, 1});
    s.data.insert(s.data.end(), bytes.begin() + nals[k], bytes.begin() + end);
  }
  samples.erase(std::remove_if(samples.begin(), samples.end(), [](const Sample& s) { return s.data.empty(); }),
                samples.end());
  return samples;
}

bool ReadOrder(const std::string& path, std::vector<Sample>* samples) {
  std::ifstream in(path);
  std::string line;
  std::map<int64_t, std::pair<std::string, int64_t>> rows;
  bool header = false;
  while (std::getline(in, line)) {
    if (!header) {
      header = line.find("Encode Order") != std::string::npos;
      continue;
    }
    std::stringstream ss(line);
    std::string layer, order, type, poc;
    if (!std::getline(ss, layer, ',') || !std::getline(ss, order, ',') || !std::getline(ss, type, ',') ||
        !std::getline(ss, poc, ',')) {
      break;
    }
    char* end = nullptr;
    const long long o = strtoll(order.c_str(), &end, 10);
    if (end == order.c_str()) break;
    rows[o] = {type, strtoll(poc.c_str(), nullptr, 10)};
  }
  if (rows.size() != samples->size()) {
    fprintf(stderr, "CSV has %zu frames, clip %zu access units\n", rows.size(), samples->size());
    return false;
  }
  int64_t base = 0, gop_max = -1, i = 0;
  for (auto& [order, row] : rows) {
    Sample& s = (*samples)[size_t(i)];
    if (row.first.find("I-SLICE") != std::string::npos && row.second == 0 && i > 0) {
      base += gop_max + 1;
      gop_max = -1;
    }
    s.display = base + row.second;
    s.decode = i++;
    gop_max = std::max(gop_max, row.second);
  }
  return true;
}

struct Options {
  bool real_dts = true;
  int dts_shift = 4;
  double feed_delay_ms = -1;
  double seconds = 0;
  double start = 0;
  int width = 1920, height = 1080;
  bool protect = false;
};

NSString* const kLicenseUrl = @"https://drm-fairplay-licensing.axprod.net/AcquireLicense";
NSString* const kCertificateUrl = @"https://tools.axinom.com/FPScert/fairplay.cer";
const uint8_t kKeyId[16] = {0x30, 0x2f, 0x80, 0xdd, 0x41, 0x1e, 0x48, 0x86,
                            0xbc, 0xa5, 0xbb, 0x1f, 0x80, 0x18, 0xa0, 0x24};
const char* const kKeyBase64 = "FbKq+Qbr7GMJ1A+RKJEnuA==";
const uint8_t kIv[16] = {0x77, 0xfd, 0x18, 0x89, 0xaa, 0xf4, 0x14, 0x3b,
                         0x08, 0x55, 0x48, 0xb3, 0xc0, 0xf9, 0x5b, 0x9a};
NSString* const kToken = @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjMwMmY4MGRkLTQxMWUtNDg4Ni1iY2E1LWJiMWY4MDE4YTAyNCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiMWVYeWhGWmNGVjljemNtZG5BREpMdz09IiwKICAgICAgICAiaXYiOiAiZC8wWWlhcjBGRHNJVlVpendQbGJtZz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.5VxBJQsgGVissi9WCNpT7IoykEAmxaEcif6F3SeLvzU";

bool Protect(std::vector<Sample>* samples) {
  std::vector<uint8_t> record(23, 0);
  record[0] = 1;
  record[21] = 3;
  ft::NalLayout layout(ft::NalCodec::kHevc, record);
  NSData* key_data = [[NSData alloc] initWithBase64EncodedString:@(kKeyBase64) options:0];
  const std::vector<uint8_t> key((const uint8_t*)key_data.bytes, (const uint8_t*)key_data.bytes + key_data.length);
  const std::vector<uint8_t> iv(kIv, kIv + 16);
  for (Sample& s : *samples) {
    std::vector<size_t> starts;
    for (size_t i = 0; i + 4 <= s.data.size(); ++i) {
      if (s.data[i] == 0 && s.data[i + 1] == 0 && s.data[i + 2] == 0 && s.data[i + 3] == 1) {
        starts.push_back(i);
        i += 3;
      }
    }
    for (size_t k = 0; k < starts.size(); ++k) {
      const size_t end = k + 1 < starts.size() ? starts[k + 1] : s.data.size();
      const uint32_t length = uint32_t(end - starts[k] - 4);
      for (int b = 0; b < 4; ++b) s.data[starts[k] + b] = uint8_t(length >> (24 - 8 * b));
    }
    std::string error;
    if (!layout.Subsamples(s.data, fp::EncryptionScheme::kCbcs, &s.subsamples, &error) ||
        !ft::CencCrypt(true, fp::EncryptionScheme::kCbcs, key, iv, {1, 9}, s.subsamples, &s.data, &error)) {
      fprintf(stderr, "protect: %s\n", error.c_str());
      return false;
    }
    for (size_t start : starts) {
      s.data[start] = s.data[start + 1] = s.data[start + 2] = 0;
      s.data[start + 3] = 1;
    }
  }
  return true;
}

std::vector<uint8_t> CommonPssh() {
  static const uint8_t kCommonSystemId[16] = {0x10, 0x77, 0xef, 0xec, 0xc0, 0xb2, 0x4d, 0x02,
                                              0xac, 0xe3, 0x3c, 0x1e, 0x52, 0xe2, 0xfb, 0x4b};
  std::vector<uint8_t> payload = {1, 0, 0, 0};
  payload.insert(payload.end(), kCommonSystemId, kCommonSystemId + 16);
  payload.insert(payload.end(), {0, 0, 0, 1});
  payload.insert(payload.end(), kKeyId, kKeyId + 16);
  payload.insert(payload.end(), {0, 0, 0, 0});
  return fp::MakeBox(fp::FourCC('p', 's', 's', 'h'), payload);
}

NSData* Fetch(NSString* url, NSData* body, NSDictionary* headers, long* status) {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  request.HTTPMethod = body ? @"POST" : @"GET";
  request.HTTPBody = body;
  request.timeoutInterval = 60;
  for (NSString* name in headers) [request setValue:headers[name] forHTTPHeaderField:name];
  __block NSData* result = nil;
  __block long code = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                   completionHandler:^(NSData* data, NSURLResponse* response, NSError*) {
                                     code = ((NSHTTPURLResponse*)response).statusCode;
                                     result = data;
                                     dispatch_semaphore_signal(done);
                                   }] resume];
  dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC));
  *status = code;
  return result;
}

class License : public fp::FairPlayCdmClient {
 public:
  explicit License(std::function<void()> ready) : ready_(std::move(ready)) {}

  void Start(fp::PostTask poster) {
    cdm_ = std::make_unique<fp::FairPlayCdm>(this, poster);
    NSString* cache = [NSString stringWithFormat:@"%@/axinom_fairplay.cer",
                                                 NSProcessInfo.processInfo.environment[@"PARC_FAIRPLAY_CACHE"]
                                                     ?: [NSTemporaryDirectory() stringByAppendingString:
                                                                                    @"parc-fairplay-cache"]];
    NSData* certificate = [NSData dataWithContentsOfFile:cache];
    if (!certificate.length) {
      long status = 0;
      certificate = Fetch(kCertificateUrl, nil, @{}, &status);
    }
    cdm_->SetServerCertificate(std::vector<uint8_t>((const uint8_t*)certificate.bytes,
                                                    (const uint8_t*)certificate.bytes + certificate.length),
                               [](const fp::Result& r) {
                                 if (!r.ok()) Fail("certificate: " + r.message);
                               });
    cdm_->CreateSessionAndGenerateRequest(fp::InitDataType::kCenc, CommonPssh(),
                                          [](const fp::Result& r, const std::string&) {
                                            if (!r.ok()) Fail("generateRequest: " + r.message);
                                          });
  }

  fp::FairPlayCdm* cdm() { return cdm_.get(); }

  void OnSessionMessage(const std::string& session_id, fp::MessageType,
                        const std::vector<uint8_t>& message) override {
    NSData* body = [NSData dataWithBytes:message.data() length:message.size()];
    std::string session = session_id;
    fp::FairPlayCdm* cdm = cdm_.get();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray* entries = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
      NSMutableArray* answers = [NSMutableArray array];
      for (NSDictionary* entry in entries) {
        NSData* spc = [[NSData alloc] initWithBase64EncodedString:entry[@"payload"] options:0];
        long status = 0;
        NSData* ckc = Fetch(kLicenseUrl, spc, @{@"X-AxDRM-Message" : kToken,
                                                @"Content-Type" : @"application/octet-stream"}, &status);
        if (status != 200 || !ckc.length) Fail("license server HTTP " + std::to_string(status));
        [answers addObject:@{@"keyID" : entry[@"keyID"], @"payload" : [ckc base64EncodedStringWithOptions:0]}];
      }
      NSData* json = [NSJSONSerialization dataWithJSONObject:answers options:0 error:nil];
      std::vector<uint8_t> response((const uint8_t*)json.bytes, (const uint8_t*)json.bytes + json.length);
      dispatch_async(dispatch_get_main_queue(), ^{
        cdm->UpdateSession(session, response, [](const fp::Result& r) {
          if (!r.ok()) Fail("update: " + r.message);
        });
      });
    });
  }

  void OnSessionKeysChange(const std::string&, bool, const std::vector<fp::KeyInfo>&) override {
    if (!ready_sent_ && cdm_->HasUsableKey(std::vector<uint8_t>(kKeyId, kKeyId + 16))) {
      ready_sent_ = true;
      ready_();
    }
  }
  void OnSessionClosed(const std::string&) override {}

  static void Fail(const std::string& what) {
    fprintf(stderr, "license: %s\n", what.c_str());
    exit(1);
  }

 private:
  std::function<void()> ready_;
  std::unique_ptr<fp::FairPlayCdm> cdm_;
  bool ready_sent_ = false;
};

fp::MediaTime FrameTime(int64_t index) {
  return fp::MediaTime::FromMicroseconds(int64_t(std::llround(index * 1e6 / kFps)));
}

struct Poll {
  double wall;
  double clock;
  int frame;
};

struct Metrics {
  double wall, clock;
  int64_t total, dropped;
  double delay;
};

class Harness : public fp::FairPlayRendererClient {
 public:
  Harness(std::vector<Sample> samples, Options options)
      : samples_(std::move(samples)), options_(options) {
    for (const Sample& s : samples_) {
      pts_sorted_.push_back(FrameTime(s.display).InSeconds());
    }
    std::sort(pts_sorted_.begin(), pts_sorted_.end());
  }

  void Start() {
    fp::PostTask poster = [](std::function<void()> task) { dispatch_async(dispatch_get_main_queue(), ^{ task(); }); };
    if (options_.protect && !license_) {
      if (!Protect(&samples_)) exit(1);
      license_ = std::make_unique<License>([this] { Start(); });
      license_->Start(poster);
      return;
    }
    renderer_ = std::make_unique<fp::FairPlayRenderer>(this, poster);
    if (license_) renderer_->SetCdm(license_->cdm());
    fp::VideoConfig config;
    if (options_.protect) config.encryption.scheme = fp::EncryptionScheme::kCbcs;
    config.codec = fp::VideoCodec::kHEVC;
    config.format = fp::BitstreamFormat::kAnnexB;
    config.coded_width = options_.width;
    config.coded_height = options_.height;
    fp::Result result = renderer_->Initialize(config, std::nullopt);
    if (!result.ok()) {
      fprintf(stderr, "Initialize failed: %s\n", result.message.c_str());
      exit(1);
    }
    window_ = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 960, 540)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    window_.title = @"decode-time-harness (silent)";
    window_.contentView.wantsLayer = YES;
    CALayer* layer = (__bridge CALayer*)renderer_->display_layer();
    layer.frame = window_.contentView.bounds;
    [window_.contentView.layer addSublayer:layer];
    [window_ orderFrontRegardless];
    start_wall_ = CACurrentMediaTime();
    if (options_.start > 0) {
      for (size_t i = 0; i < samples_.size(); ++i) {
        if (samples_[i].keyframe && FrameTime(samples_[i].display).InSeconds() <= options_.start + 1e-9) next_ = i;
      }
    }
    renderer_->StartPlayingFrom(fp::MediaTime::FromMicroseconds(int64_t(std::llround(options_.start * 1e6))));
    OnNeedData(fp::StreamType::kVideo);
    StartPolling();
  }

  void OnNeedData(fp::StreamType) override {
    if (options_.feed_delay_ms < 0) {
      while (next_ < samples_.size() && renderer_->IsReadyForMoreData(fp::StreamType::kVideo)) {
        EnqueueNext();
      }
      MaybeEnd();
      return;
    }
    if (read_pending_ || next_ >= samples_.size() || !renderer_->IsReadyForMoreData(fp::StreamType::kVideo)) {
      MaybeEnd();
      return;
    }
    read_pending_ = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, int64_t(options_.feed_delay_ms * 1e6)), dispatch_get_main_queue(),
                   ^{
                     read_pending_ = false;
                     EnqueueNext();
                     MaybeEnd();
                     OnNeedData(fp::StreamType::kVideo);
                   });
  }
  void OnWaitingForKey() override {}
  void OnEnded() override { Finish("ended"); }
  void OnError(fp::RendererError, const std::string& description) override {
    fprintf(stderr, "renderer error: %s\n", description.c_str());
    exit(1);
  }
  void OnVideoNaturalSizeChange(int32_t, int32_t) override {}
  void OnBufferingStateChange(bool have_enough) override {
    if (have_enough && !playing_) {
      playing_ = true;
      play_wall_ = CACurrentMediaTime();
      renderer_->SetPlaybackRate(1);
    } else if (!have_enough) {
      ++underflows_;
    }
  }

 private:
  void EnqueueNext() {
    if (next_ >= samples_.size()) return;
    const Sample& s = samples_[next_++];
    fp::EncodedSample sample;
    sample.data = s.data.data();
    sample.size = s.data.size();
    sample.pts = FrameTime(s.display);
    sample.dts = options_.real_dts ? FrameTime(s.decode - options_.dts_shift) : fp::MediaTime::Invalid();
    sample.duration = fp::MediaTime::FromMicroseconds(int64_t(std::llround(1e6 / kFps)));
    sample.is_keyframe = s.keyframe;
    if (options_.protect) {
      fp::DecryptInfo decrypt;
      decrypt.scheme = fp::EncryptionScheme::kCbcs;
      decrypt.key_id.assign(kKeyId, kKeyId + 16);
      decrypt.iv.assign(kIv, kIv + 16);
      decrypt.subsamples = s.subsamples;
      decrypt.pattern = fp::EncryptionPattern{1, 9};
      sample.decrypt = std::move(decrypt);
    }
    if (renderer_->Enqueue(fp::StreamType::kVideo, sample) != fp::EnqueueResult::kEnqueued) {
      fprintf(stderr, "sample %zu not enqueued\n", next_ - 1);
      exit(1);
    }
    max_enqueued_pts_ = std::max(max_enqueued_pts_, sample.pts.InSeconds());
    if (playing_) {
      leads_.push_back(max_enqueued_pts_ - renderer_->GetMediaTime().InSeconds());
    }
  }

  void MaybeEnd() {
    if (next_ >= samples_.size() && !ended_sent_) {
      ended_sent_ = true;
      renderer_->SetEndOfStream(fp::StreamType::kVideo);
    }
  }

  void StartPolling() {
    timer_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer_, DISPATCH_TIME_NOW, 4 * NSEC_PER_MSEC, NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer_, ^{ Tick(); });
    dispatch_resume(timer_);
  }

  void Tick() {
    if (finished_) return;
    const double wall = CACurrentMediaTime();
    const double clock = renderer_->GetMediaTime().InSeconds();
    if (playing_) {
      if (first_move_ < 0 && clock > options_.start + 0.0005) first_move_ = wall;
      polls_.push_back({wall, clock, DisplayedFrame()});
      if (wall - last_metrics_ >= 0.05 && !metrics_pending_) {
        last_metrics_ = wall;
        metrics_pending_ = true;
        renderer_->LoadVideoMetrics([this, wall, clock](const fp::VideoMetrics& m) {
          metrics_pending_ = false;
          metrics_.push_back({wall, clock, m.total_frames, m.dropped_frames, m.accumulated_frame_delay});
          last_ = m;
        });
      }
      if (options_.seconds > 0 && wall - play_wall_ >= options_.seconds) Finish("time");
    }
    if (wall - start_wall_ > 600) Finish("timeout");
  }

  int DisplayedFrame() {
    if (@available(macOS 14.4, *)) {
      AVSampleBufferVideoRenderer* video =
          ((__bridge AVSampleBufferDisplayLayer*)renderer_->display_layer()).sampleBufferRenderer;
      CVPixelBufferRef shown = [video copyDisplayedPixelBuffer];
      if (!shown) return -1;
      if (shown == last_shown_) {
        CVPixelBufferRelease(shown);
        return last_frame_;
      }
      if (!transfer_) VTPixelTransferSessionCreate(nullptr, &transfer_);
      if (!small_) {
        NSDictionary* attributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
        CVPixelBufferCreate(nullptr, 320, 180, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            (__bridge CFDictionaryRef)attributes, &small_);
      }
      int frame = -1;
      if (VTPixelTransferSessionTransferImage(transfer_, shown, small_) == noErr &&
          CVPixelBufferLockBaseAddress(small_, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess) {
        const uint8_t* luma = (const uint8_t*)CVPixelBufferGetBaseAddressOfPlane(small_, 0);
        const size_t stride = CVPixelBufferGetBytesPerRowOfPlane(small_, 0);
        const double block_w = 320.0 / kBits, block_h = 180.0 / 12;
        frame = 0;
        for (int b = 0; b < kBits && frame >= 0; ++b) {
          const size_t x = size_t((b + 0.5) * block_w);
          const bool one = luma[size_t(0.5 * block_h) * stride + x] > 125;
          const bool inverse = luma[size_t(1.5 * block_h) * stride + x] > 125;
          frame = one == inverse ? -1 : (frame << 1) | int(one);
        }
        CVPixelBufferUnlockBaseAddress(small_, kCVPixelBufferLock_ReadOnly);
      }
      if (last_shown_) CVPixelBufferRelease(last_shown_);
      last_shown_ = shown;
      last_frame_ = frame;
      return frame;
    }
    return -1;
  }

  size_t DueAt(double clock) const {
    return size_t(std::upper_bound(pts_sorted_.begin(), pts_sorted_.end(), clock + 1e-6) - pts_sorted_.begin());
  }

  static double Percentile(std::vector<double> v, double p) {
    if (v.empty()) return NAN;
    std::sort(v.begin(), v.end());
    return v[std::min(v.size() - 1, size_t(p * (v.size() - 1) + 0.5))];
  }

  void Finish(const char* why) {
    if (finished_) return;
    finished_ = true;
    dispatch_source_cancel(timer_);
    renderer_->LoadVideoMetrics([this, why](const fp::VideoMetrics& m) {
      Report(why, m);
      exit(0);
    });
  }

  void Report(const char* why, const fp::VideoMetrics& m) {
    const double frame = 1.0 / kFps;
    const double played_wall = CACurrentMediaTime() - play_wall_;
    printf("%sdts=%s shift=%d feed=%s stop=%s wall=%.2fs clock=%.3fs samples=%zu enqueued=%zu underflows=%d\n",
           options_.protect ? "protected " : "", options_.real_dts ? "real" : "invalid", options_.dts_shift,
           options_.feed_delay_ms < 0 ? "eager" : (std::to_string(options_.feed_delay_ms) + "ms").c_str(), why,
           played_wall, renderer_->GetMediaTime().InSeconds(), samples_.size(), next_, underflows_);
    printf("start=%.3fs clock started %.0f ms after StartPlayingFrom\n", options_.start,
           first_move_ < 0 ? NAN : 1000 * (first_move_ - start_wall_));
    printf("metrics: total=%lld dropped=%lld corrupted=%lld accumulated_delay=%.3fs\n", m.total_frames,
           m.dropped_frames, m.corrupted_frames, m.accumulated_frame_delay);
    std::vector<double> ahead;
    for (const Metrics& r : metrics_) {
      if (r.clock > 0.5 && DueAt(r.clock) + 2 * kFps < samples_.size()) {
        ahead.push_back(double(r.total) - double(DueAt(r.clock)));
      }
    }
    printf("decoded ahead of clock (frames): min=%.0f p10=%.0f median=%.0f (n=%zu)\n",
           ahead.empty() ? NAN : *std::min_element(ahead.begin(), ahead.end()), Percentile(ahead, 0.1),
           Percentile(ahead, 0.5), ahead.size());
    if (!leads_.empty()) {
      printf("enqueue lead over clock (ms): min=%.0f p10=%.0f median=%.0f\n",
             1000 * *std::min_element(leads_.begin(), leads_.end()), 1000 * Percentile(leads_, 0.1),
             1000 * Percentile(leads_, 0.5));
    }
    struct Shown {
      int frame;
      double first, last;
    };
    std::vector<Shown> shown;
    int unreadable = 0;
    for (const Poll& p : polls_) {
      if (p.frame < 0) {
        ++unreadable;
        continue;
      }
      if (shown.empty() || shown.back().frame != p.frame) {
        shown.push_back({p.frame, p.wall, p.wall});
      } else {
        shown.back().last = p.wall;
      }
    }
    int holds = 0, skipped = 0, backwards = 0;
    double hold_time = 0, longest = 0;
    std::map<int, int> hold_phase;
    std::vector<double> hold_gaps;
    double last_hold_at = -1;
    for (size_t i = 0; i + 1 < shown.size(); ++i) {
      const double up = shown[i + 1].first - shown[i].first;
      const int step = shown[i + 1].frame - shown[i].frame;
      if (step > 1) skipped += step - 1;
      if (step < 0) ++backwards;
      if (step > 1 || (i > 0 && up >= 2.5 * frame)) {
        printf("  frame %d up %.0f ms at wall %.3f, next %d\n", shown[i].frame, up * 1000,
               shown[i].first - play_wall_, shown[i + 1].frame);
      }
      if (i > 0 && up >= 2.5 * frame) {
        ++holds;
        hold_time += up - frame;
        longest = std::max(longest, up);
        ++hold_phase[shown[i].frame % 8];
        if (last_hold_at >= 0) hold_gaps.push_back(shown[i].first - last_hold_at);
        last_hold_at = shown[i].first;
      }
    }
    printf("displayed: %zu pictures read (%d unreadable polls), %d skipped, %d backwards\n", shown.size(), unreadable,
           skipped, backwards);
    printf("holds >= %.0f ms: %d, extra time %.0f ms, longest %.0f ms, median gap between holds %.0f ms\n",
           2.5 * frame * 1000, holds, hold_time * 1000, longest * 1000, 1000 * Percentile(hold_gaps, 0.5));
    if (!hold_phase.empty()) {
      printf("hold frame number mod 8:");
      for (auto& [phase, count] : hold_phase) printf(" %d:%d", phase, count);
      printf("\n");
    }
    fflush(stdout);
  }

  std::vector<Sample> samples_;
  Options options_;
  std::vector<double> pts_sorted_;
  std::unique_ptr<License> license_;
  std::unique_ptr<fp::FairPlayRenderer> renderer_;
  NSWindow* window_ = nil;
  dispatch_source_t timer_ = nullptr;
  size_t next_ = 0;
  bool read_pending_ = false;
  bool ended_sent_ = false;
  bool playing_ = false;
  bool finished_ = false;
  bool metrics_pending_ = false;
  int underflows_ = 0;
  double start_wall_ = 0, play_wall_ = 0, last_metrics_ = 0, first_move_ = -1;
  double max_enqueued_pts_ = -1;
  std::vector<double> leads_;
  std::vector<Poll> polls_;
  std::vector<Metrics> metrics_;
  fp::VideoMetrics last_;
  VTPixelTransferSessionRef transfer_ = nullptr;
  CVPixelBufferRef small_ = nullptr;
  CVPixelBufferRef last_shown_ = nullptr;
  int last_frame_ = -1;
};

std::vector<uint8_t> ReadFile(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

}

int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc == 5 && std::string(argv[1]) == "--write-yuv") {
      return WriteYuv(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
    }
    if (argc < 4 || std::string(argv[1]) != "--play") {
      fprintf(stderr, "usage: see the comment at the top of decode_time_harness.mm\n");
      return 2;
    }
    Options options;
    for (int i = 4; i + 1 < argc; i += 2) {
      const std::string flag = argv[i], value = argv[i + 1];
      if (flag == "--dts") options.real_dts = value == "real";
      else if (flag == "--dts-shift") options.dts_shift = atoi(value.c_str());
      else if (flag == "--feed") options.feed_delay_ms = value == "eager" ? -1 : atof(value.c_str());
      else if (flag == "--start") options.start = atof(value.c_str());
      else if (flag == "--seconds") options.seconds = atof(value.c_str());
      else if (flag == "--protected") options.protect = value == "1";
      else if (flag == "--size") sscanf(value.c_str(), "%dx%d", &options.width, &options.height);
    }
    std::vector<Sample> samples = ReadAccessUnits(ReadFile(argv[2]));
    if (samples.empty() || !ReadOrder(argv[3], &samples)) return 1;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    id activity = [NSProcessInfo.processInfo
        beginActivityWithOptions:NSActivityUserInitiated | NSActivityLatencyCritical
                          reason:@"decode-time-harness"];
    (void)activity;
    auto* harness = new Harness(std::move(samples), options);
    dispatch_async(dispatch_get_main_queue(), ^{ harness->Start(); });
    [NSApp run];
  }
  return 0;
}

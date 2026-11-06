// The FairPlay sandbox probe's player: libfpsbplayer.dylib, opened by
// probe_main.cc after the GPU profile is applied. It does what Parc's GPU
// process does for a FairPlay player: a FairPlayCdm session and a
// FairPlayRenderer joined to it, fed Chromium-shaped buffers (Annex B, ADTS,
// scheme-only encryption, 16-byte IVs). The license exchange goes through the
// host's unsandboxed helper.
//
// PASS needs more than the clock (audio drives it): the stream played to its
// target, every present stream rendering, protected formats on every stream
// of a protected scenario, no decode failure, and for video AVFoundation's
// metrics, counted halfway and at the end: as many frames as came due (at
// least 80%), and between the two counts at least 80% of those that came due
// and were still to decode, a frame ready for display, none corrupted and at
// most 10% dropped.

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_bitstream.h"
#include "fairplay_init_data.h"
#include "fairplay_key_session.h"
#include "fairplay_renderer.h"
#include "probe_host.h"

namespace fp = parc::fairplay;
namespace ft = parc::fairplay::test;

namespace {

const fpsb::Host* g_host = nullptr;

void Log(const char* format, ...) __attribute__((format(printf, 1, 2)));
void Log(const char* format, ...) {
  char buffer[4096];
  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  g_host->log(buffer);
}

void SetStage(const char* stage) { g_host->stage->store(stage); }

std::vector<uint8_t> Bytes(NSData* data) {
  const uint8_t* p = static_cast<const uint8_t*>(data.bytes);
  return std::vector<uint8_t>(p, p + data.length);
}

NSData* Data(const std::vector<uint8_t>& v) { return [NSData dataWithBytes:v.data() length:v.size()]; }

// What Chromium's MP4StreamParser hands a renderer, as the GPU adapter
// passes it on: no video decoder record, Dolby Vision as profile and level,
// no dac3/dec3, AAC with ADTS, encryption as the scheme alone.
fp::VideoConfig VideoConfigFor(const ft::TrackInfo& info) {
  fp::VideoConfig vc;
  const uint32_t f = info.original_format;
  if (f == fp::FourCC('h', 'v', 'c', '1') || f == fp::FourCC('h', 'e', 'v', '1')) {
    vc.codec = fp::VideoCodec::kHEVC;
  } else if (f == fp::FourCC('d', 'v', 'h', '1') || f == fp::FourCC('d', 'v', 'h', 'e')) {
    vc.codec = fp::VideoCodec::kDolbyVision;
    const std::vector<uint8_t>& dv = info.dolby_vision_config;
    if (dv.size() >= 5) {
      vc.dolby_vision_profile = dv[2] >> 1;
      vc.dolby_vision_level = ((dv[2] & 1) << 5) | (dv[3] >> 3);
    }
  } else {
    vc.codec = fp::VideoCodec::kH264;
  }
  vc.format = fp::BitstreamFormat::kAnnexB;
  vc.coded_width = info.width;
  vc.coded_height = info.height;
  vc.encryption.scheme = info.encryption.scheme;
  return vc;
}

fp::AudioConfig AudioConfigFor(const ft::TrackInfo& info) {
  fp::AudioConfig ac;
  const uint32_t f = info.original_format;
  const bool aac = f == fp::FourCC('m', 'p', '4', 'a');
  ac.codec = aac ? fp::AudioCodec::kAAC
                 : f == fp::FourCC('e', 'c', '-', '3') ? fp::AudioCodec::kEAC3 : fp::AudioCodec::kAC3;
  if (aac) ac.extra_data = info.codec_config;
  ac.framing = aac && ft::AacObjectType(info.codec_config, true) <= 4 ? fp::AudioFraming::kADTS
                                                                     : fp::AudioFraming::kRaw;
  ac.sample_rate = int32_t(info.sample_rate);
  ac.channels = info.channels;
  ac.encryption.scheme = info.encryption.scheme;
  return ac;
}

double Seconds(const fpsb::Track& track, int64_t ticks) {
  return track.info.timescale ? double(ticks) / track.info.timescale : 0;
}

double EndSeconds(const fpsb::Track& track) {
  double end = 0;
  for (const ft::Sample& s : track.samples) end = std::max(end, Seconds(track, s.pts + s.duration));
  return end;
}

fp::PostTask MainPoster() {
  return [](std::function<void()> task) {
    dispatch_async(dispatch_get_main_queue(), ^{
      task();
    });
  };
}

class Player : public fp::FairPlayCdmClient, public fp::FairPlayRendererClient {
 public:
  explicit Player(const fpsb::Scenario& s) : s_(s), cdm_(this, MainPoster()), renderer_(this, MainPoster()) {
    // The clear clips are shorter than the target; play them to their end.
    double end = 1e9;
    if (s_.video.present) end = std::min(end, EndSeconds(s_.video));
    if (s_.audio.present) end = std::min(end, EndSeconds(s_.audio));
    target_ = std::min(s_.play_seconds, end - 0.3);
  }

  void Start() {
    if (s_.protected_media) {
      SetStage("SetServerCertificate");
      cdm_.SetServerCertificate(s_.certificate, [](const fp::Result& r) {
        if (!r.ok()) Fail("SetServerCertificate: " + r.message);
      });
      SetStage("generateRequest");
      const fp::InitDataType type = s_.init_data_type == "skd" ? fp::InitDataType::kSkd : fp::InitDataType::kCenc;
      cdm_.CreateSessionAndGenerateRequest(type, s_.init_data, [this](const fp::Result& r, const std::string& id) {
        if (!r.ok()) Fail("generateRequest rejected: " + r.message);
        session_ = id;
        Log("session %s created", id.c_str());
      });
      // Chromium's order when MediaKeys come first: SetCdm, then Initialize.
      SetStage("SetCdm");
      fp::Result r = renderer_.SetCdm(&cdm_);
      if (!r.ok()) Fail("SetCdm: " + r.message);
    }
    SetStage("renderer Initialize");
    std::optional<fp::VideoConfig> vc;
    std::optional<fp::AudioConfig> ac;
    if (s_.video.present) vc = VideoConfigFor(s_.video.info);
    if (s_.audio.present) ac = AudioConfigFor(s_.audio.info);
    fp::Result r = renderer_.Initialize(vc, ac);
    if (!r.ok()) Fail("renderer Initialize: " + r.message);
    renderer_.StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    renderer_.SetPlaybackRate(1);
    SetStage(s_.protected_media ? "license" : "playback");
    Poll();
  }

  // FairPlayCdmClient
  void OnSessionMessage(const std::string& session_id, fp::MessageType,
                        const std::vector<uint8_t>& message) override {
    Log("license message %zu bytes", message.size());
    SetStage("license server");
    NSData* body = Data(message);
    std::string session = session_id;
    const bool skd = s_.init_data_type == "skd";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      // cenc sessions exchange [{keyID, payload}] JSON, skd sessions the raw
      // SPC and CKC; the license service takes and returns raw ones.
      NSArray* entries = skd ? @[ @{@"payload" : [body base64EncodedStringWithOptions:0]} ]
                             : [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
      NSMutableArray* answers = [NSMutableArray array];
      NSData* raw_answer = nil;
      std::string failure;
      for (NSDictionary* entry in entries) {
        NSData* spc = [[NSData alloc] initWithBase64EncodedString:entry[@"payload"] options:0];
        fpsb::HttpRequest request{"POST", s_.license_url,
                                  {{"X-AxDRM-Message", s_.license_token},
                                   {"Content-Type", "application/octet-stream"}},
                                  Bytes(spc)};
        fpsb::HttpResponse response;
        g_host->request(request, &response);
        Log("POST SPC %lu bytes -> HTTP %ld, %zu bytes %s", (unsigned long)spc.length, response.status,
            response.body.size(), response.error_header.c_str());
        if (response.status != 200) {
          failure = "license HTTP " + std::to_string(response.status) + " " + response.error + " " +
                    response.error_header;
          break;
        }
        raw_answer = Data(response.body);
        if (!skd) {
          [answers addObject:@{@"keyID" : entry[@"keyID"],
                               @"payload" : [raw_answer base64EncodedStringWithOptions:0]}];
        }
      }
      NSData* update = skd ? raw_answer : [NSJSONSerialization dataWithJSONObject:answers options:0 error:nil];
      dispatch_async(dispatch_get_main_queue(), ^{
        // The server or the network, not the sandbox (the helper is outside it).
        if (!failure.empty()) g_host->finish(fpsb::Outcome::kInconclusive, failure + State());
        SetStage("update");
        cdm_.UpdateSession(session, Bytes(update), [](const fp::Result& r) {
          if (!r.ok()) Fail("update rejected: " + r.message);
          Log("update resolved");
        });
      });
    });
  }

  void OnSessionKeysChange(const std::string&, bool, const std::vector<fp::KeyInfo>& keys) override {
    bool usable = false;
    for (const fp::KeyInfo& key : keys) {
      Log("key %s %s system_code=%u", ft::Hex(key.key_id).c_str(), fp::KeyStatusName(key.status),
          key.system_code);
      usable = usable || key.status == fp::KeyStatus::kUsable;
    }
    usable_ = usable;
    if (usable_) SetStage("playback");
  }

  void OnSessionClosed(const std::string&) override {}

  // FairPlayRendererClient
  void OnNeedData(fp::StreamType stream) override { Feed(stream); }
  void OnWaitingForKey() override { Log("waiting for key"); }
  void OnEnded() override { ended_ = true; }
  void OnError(fp::RendererError, const std::string& description) override {
    Fail("renderer error: " + description);
  }
  void OnVideoNaturalSizeChange(int32_t width, int32_t height) override {
    Log("natural size %dx%d", width, height);
  }
  void OnBufferingStateChange(bool have_enough) override {
    Log("buffering %s", have_enough ? "HAVE_ENOUGH" : "HAVE_NOTHING");
  }

  static void Fail(const std::string& reason);
  std::string State() const {
    fp::RendererStatus s = renderer_.GetStatus();
    return std::string(" stage=") + g_host->stage->load() + " key_usable=" + (usable_ ? "yes" : "no") +
           " media_time=" + std::to_string(renderer_.GetMediaTime().InSeconds()) +
           " target=" + std::to_string(target_) + " video_enqueued=" + std::to_string(s.video_enqueued) +
           " audio_enqueued=" + std::to_string(s.audio_enqueued) +
           " protected_enqueued=" + std::to_string(s.protected_enqueued) +
           " decode_failures=" + std::to_string(s.decode_failures) +
           " video_format=" + ft::FourCCString(s.video_protected_format ? s.video_protected_format : s.video_format) +
           " audio_format=" + ft::FourCCString(s.audio_protected_format ? s.audio_protected_format : s.audio_format);
  }

 private:
  void Feed(fp::StreamType stream) {
    const bool video = stream == fp::StreamType::kVideo;
    const fpsb::Track& track = video ? s_.video : s_.audio;
    size_t& next = video ? next_video_ : next_audio_;
    while (next < track.samples.size() && renderer_.IsReadyForMoreData(stream)) {
      std::vector<uint8_t> storage;
      fp::DecryptInfo decrypt;
      fp::EncodedSample sample = ft::ChromiumBuffer(track.info, track.samples[next], &storage, &decrypt);
      if (renderer_.Enqueue(stream, sample) == fp::EnqueueResult::kRejected) {
        Fail(std::string("enqueue rejected (") + (video ? "video" : "audio") + ")");
      }
      ++next;
    }
    bool& ended = video ? video_ended_ : audio_ended_;
    if (next == track.samples.size() && !ended) {
      ended = true;
      renderer_.SetEndOfStream(stream);
    }
  }

  void Poll() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      fp::RendererStatus s = renderer_.GetStatus();
      if (s.video == fp::RenderingStatus::kFailed) Fail("video renderer failed: " + s.video_error);
      if (s.audio == fp::RenderingStatus::kFailed) Fail("audio renderer failed: " + s.audio_error);
      const bool keys_ready = !s_.protected_media || usable_;
      const double now = renderer_.GetMediaTime().InSeconds();
      // Video frames are counted twice, halfway and at the end: the frames
      // decoded between the two samples must keep up with the media time
      // (a single count includes the frames decoded ahead of it).
      if (keys_ready && s_.video.present && !first_requested_ && (now >= target_ / 2 || ended_)) {
        first_requested_ = true;
        renderer_.LoadVideoMetrics([this](const fp::VideoMetrics& m) {
          first_metrics_ = m;
          first_time_ = renderer_.GetMediaTime().InSeconds();
          have_first_ = true;
        });
      }
      if (keys_ready && (now >= target_ || ended_) && (!s_.video.present || have_first_)) {
        SetStage("evaluate");
        if (s_.video.present) {
          renderer_.LoadVideoMetrics([this](const fp::VideoMetrics& m) { Evaluate(&m); });
        } else {
          Evaluate(nullptr);
        }
        return;
      }
      Poll();
    });
  }

  // Video samples presented before |time|.
  int64_t FramesDue(double time) const {
    int64_t due = 0;
    for (const ft::Sample& sample : s_.video.samples) {
      if (Seconds(s_.video, sample.pts) < time) ++due;
    }
    return due;
  }

  void Evaluate(const fp::VideoMetrics* metrics) {
    const fp::RendererStatus s = renderer_.GetStatus();
    const double media_time = renderer_.GetMediaTime().InSeconds();
    std::vector<std::string> failures;
    if (media_time < target_ && !ended_) failures.push_back("media time short of the target");
    if (s.decode_failures) failures.push_back(std::to_string(s.decode_failures) + " decode failures");
    if (s_.video.present && s.video != fp::RenderingStatus::kRendering) failures.push_back("video not rendering");
    if (s_.audio.present && s.audio != fp::RenderingStatus::kRendering) failures.push_back("audio not rendering");
    if (s_.protected_media) {
      if (!usable_) failures.push_back("key not usable");
      if (s_.video.present && !s.video_protected_format) failures.push_back("no protected video format");
      if (s_.audio.present && !s.audio_protected_format) failures.push_back("no protected audio format");
    }
    std::string detail;
    bool metrics_missing = false;
    if (metrics) {
      metrics_missing = !metrics->available || !first_metrics_.available;
      if (!metrics_missing) {
        const int64_t due = FramesDue(media_time);
        // Frames that came due between the counts, but no more than were still
        // left to decode at the first (a short clip decodes whole up front).
        const int64_t left = std::max<int64_t>(
            0, int64_t(s_.video.samples.size()) - first_metrics_.total_frames);
        const int64_t expected_between = std::min(due - FramesDue(first_time_), left);
        const int64_t decoded_between = metrics->total_frames - first_metrics_.total_frames;
        detail = " frames " + std::to_string(metrics->total_frames) + " (" + std::to_string(due) +
                 " due), between samples " + std::to_string(decoded_between) + "/" +
                 std::to_string(expected_between) + ", dropped " + std::to_string(metrics->dropped_frames) +
                 " corrupted " + std::to_string(metrics->corrupted_frames);
        if (metrics->total_frames * 10 < due * 8) failures.push_back("too few frames");
        if (decoded_between * 10 < expected_between * 8) {
          failures.push_back("video didn't keep up between samples");
        }
        if (!s.video_ready_for_display) failures.push_back("no video frame ready for display");
        if (metrics->corrupted_frames) failures.push_back("corrupted frames");
        if (metrics->dropped_frames * 10 > std::max<int64_t>(due, 1)) failures.push_back("too many dropped frames");
      }
    }
    if (!failures.empty()) {
      std::string list;
      for (const std::string& f : failures) list += (list.empty() ? "" : ", ") + f;
      Fail(list + detail);
    }
    if (metrics_missing) {
      g_host->finish(fpsb::Outcome::kInconclusive, "no video metrics (macOS 14.4+)" + State());
    }
    if (s.output_obscured) {
      // Screen capture by another process does this; the frames above decoded.
      g_host->finish(fpsb::Outcome::kInconclusive, "output obscured" + detail + State());
    }
    g_host->finish(fpsb::Outcome::kPass, s_.name + detail + State());
  }

  const fpsb::Scenario& s_;
  fp::FairPlayCdm cdm_;
  fp::FairPlayRenderer renderer_;
  double target_ = 0;
  std::string session_;
  bool usable_ = false;
  bool ended_ = false;
  size_t next_video_ = 0;
  size_t next_audio_ = 0;
  bool video_ended_ = false;
  bool audio_ended_ = false;
  bool first_requested_ = false;
  bool have_first_ = false;
  fp::VideoMetrics first_metrics_;
  double first_time_ = 0;
};

Player* g_player = nullptr;

void Player::Fail(const std::string& reason) {
  g_host->finish(fpsb::Outcome::kFail, reason + (g_player ? g_player->State() : ""));
}

}  // namespace

extern "C" __attribute__((visibility("default"))) void FpsbRunPlayer(const fpsb::Scenario* scenario,
                                                                     const fpsb::Host* host) {
  g_host = host;
  // AVFoundation reports some failures as exceptions (an invalid renderer
  // passed to the synchronizer when CoreAudio is unreachable).
  NSSetUncaughtExceptionHandler([](NSException* exception) {
    const char* name = exception.name.UTF8String;
    const char* reason = exception.reason.UTF8String;
    g_host->finish(fpsb::Outcome::kFail, std::string("uncaught exception ") + (name ? name : "?") + ": " +
                                             (reason ? reason : "") + " stage=" + g_host->stage->load());
  });
  g_player = new Player(*scenario);
  g_player->Start();
  CFRunLoopRun();
}

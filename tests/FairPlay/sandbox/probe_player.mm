#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_bitstream.h"
#include "fairplay_hls_player.h"
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

const ft::TrackInfo& InfoFor(const fpsb::Track& track, size_t i) {
  return track.parts.empty() ? track.info : track.parts[track.part_of_sample[i]];
}

size_t PartOf(const fpsb::Track& track, size_t i) {
  return track.parts.empty() ? 0 : track.part_of_sample[i];
}

double PtsSeconds(const fpsb::Track& track, size_t i) {
  const uint32_t timescale = InfoFor(track, i).timescale;
  return timescale ? double(track.samples[i].pts) / timescale : 0;
}

double EndSeconds(const fpsb::Track& track) {
  double end = 0;
  for (size_t i = 0; i < track.samples.size(); ++i) {
    const uint32_t timescale = InfoFor(track, i).timescale;
    if (timescale) {
      end = std::max(end, double(track.samples[i].pts + track.samples[i].duration) / timescale);
    }
  }
  return end;
}

std::string ClearFormatFor(const ft::TrackInfo& info) {
  const uint32_t f = info.original_format;
  if (f == fp::FourCC('m', 'p', '4', 'a')) return "aac ";
  if (f == fp::FourCC('h', 'e', 'v', '1')) return "hvc1";
  return ft::FourCCString(f);
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
    renderer_.SetMuted(true);
    renderer_.StartPlayingFrom(fp::MediaTime::FromMicroseconds(0));
    renderer_.SetPlaybackRate(1);
    SetStage(s_.protected_media ? "license" : "playback");
    Poll();
  }

  void OnSessionMessage(const std::string& session_id, fp::MessageType,
                        const std::vector<uint8_t>& message) override {
    Log("license message %zu bytes", message.size());
    SetStage("license server");
    NSData* body = Data(message);
    std::string session = session_id;
    const bool skd = s_.init_data_type == "skd";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
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
    Log("buffering %s at %.3f", have_enough ? "HAVE_ENOUGH" : "HAVE_NOTHING",
        renderer_.GetMediaTime().InSeconds());
    if (have_enough) {
      had_enough_ = true;
    } else if (had_enough_) {
      ++underflows_;
    }
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
    std::vector<std::string>& formats = video ? video_formats_ : audio_formats_;
    while (next < track.samples.size() && renderer_.IsReadyForMoreData(stream)) {
      const ft::TrackInfo& info = InfoFor(track, next);
      const bool first_of_part = next == 0 || PartOf(track, next) != PartOf(track, next - 1);
      if (first_of_part && next > 0) {
        fp::Result r = video ? renderer_.Reconfigure(VideoConfigFor(info)) : renderer_.Reconfigure(AudioConfigFor(info));
        if (!r.ok()) Fail(std::string("Reconfigure (") + (video ? "video" : "audio") + "): " + r.message);
        Log("%s switched to %s at %.3f (media time %.3f)", video ? "video" : "audio",
            ft::FourCCString(info.original_format).c_str(), PtsSeconds(track, next),
            renderer_.GetMediaTime().InSeconds());
      }
      std::vector<uint8_t> storage;
      fp::DecryptInfo decrypt;
      fp::EncodedSample sample = ft::ChromiumBuffer(info, track.samples[next], &storage, &decrypt);
      if (renderer_.Enqueue(stream, sample) == fp::EnqueueResult::kRejected) {
        Fail(std::string("enqueue rejected (") + (video ? "video" : "audio") + ")");
      }
      if (first_of_part && !track.parts.empty()) {
        const fp::RendererStatus status = renderer_.GetStatus();
        formats.push_back(ft::FourCCString(video ? status.video_format : status.audio_format));
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

  int64_t FramesDue(double time) const {
    int64_t due = 0;
    for (size_t i = 0; i < s_.video.samples.size(); ++i) {
      if (PtsSeconds(s_.video, i) < time) ++due;
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
    std::string switches;
    for (const fpsb::Track* track : {&s_.video, &s_.audio}) {
      if (track->parts.empty()) continue;
      const std::vector<std::string>& seen = track == &s_.video ? video_formats_ : audio_formats_;
      std::string expected;
      for (const ft::TrackInfo& part : track->parts) expected += (expected.empty() ? "" : ">") + ClearFormatFor(part);
      std::string got;
      for (const std::string& f : seen) got += (got.empty() ? "" : ">") + f;
      switches += std::string(" ") + (track == &s_.video ? "video" : "audio") + " formats " + got;
      if (got != expected) failures.push_back("formats " + got + ", expected " + expected);
      double last_switch = 0;
      for (size_t i = 1; i < track->samples.size(); ++i) {
        if (PartOf(*track, i) != PartOf(*track, i - 1)) last_switch = PtsSeconds(*track, i);
      }
      if (media_time < last_switch + 0.5) failures.push_back("played no further than the last switch");
    }
    if (!switches.empty()) {
      switches += " underflows " + std::to_string(underflows_);
      if (underflows_) failures.push_back(std::to_string(underflows_) + " underflows around the switches");
    }
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
      g_host->finish(fpsb::Outcome::kInconclusive, "output obscured" + detail + State());
    }
    g_host->finish(fpsb::Outcome::kPass, s_.name + switches + detail + State());
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
  bool had_enough_ = false;
  int underflows_ = 0;
  std::vector<std::string> video_formats_;
  std::vector<std::string> audio_formats_;
  bool first_requested_ = false;
  bool have_first_ = false;
  fp::VideoMetrics first_metrics_;
  double first_time_ = 0;
};

Player* g_player = nullptr;

class HlsProbe : public fp::HlsPlayerClient, public fp::HlsLoader {
 public:
  explicit HlsProbe(const fpsb::Scenario& s)
      : s_(s), owner_(dispatch_queue_create("parc.fpsb.hls-owner", DISPATCH_QUEUE_SERIAL)) {}

  void Start() {
    dispatch_async(owner_, ^{
      SetStage("hls Load");
      dispatch_queue_t owner = owner_;
      player_ = std::make_unique<fp::FairPlayHlsPlayer>(this, this, [owner](std::function<void()> task) {
        dispatch_async(owner, ^{
          task();
        });
      });
      player_->SetMuted(true);
      fp::Result r = player_->Load(s_.hls_url, "");
      if (!r.ok()) Finish(fpsb::Outcome::kFail, "Load: " + r.message);
      SetStage("hls metadata");
    });
  }

  class Load : public fp::HlsLoad {
   public:
    explicit Load(std::shared_ptr<std::atomic<bool>> alive) : alive_(std::move(alive)) {}
    ~Load() override { *alive_ = false; }

   private:
    std::shared_ptr<std::atomic<bool>> alive_;
  };

  std::unique_ptr<fp::HlsLoad> StartLoad(const fp::HlsLoadRequest& request, fp::HlsLoadClient* client) override {
    loads_++;
    auto alive = std::make_shared<std::atomic<bool>>(true);
    fpsb::HttpRequest http;
    http.method = request.method;
    http.url = request.url;
    for (const auto& [name, value] : request.headers) {
      if (name == "Range" || name == "range") http.headers.emplace_back(name, value);
    }
    dispatch_queue_t owner = owner_;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      auto response = std::make_shared<fpsb::HttpResponse>();
      bool ok = g_host->request(http, response.get());
      dispatch_async(owner, ^{
        if (!*alive) return;
        if (!ok || !response->error.empty()) {
          client->OnComplete(-2);
          return;
        }
        fp::HlsLoadResponse r;
        r.http_status = static_cast<int>(response->status);
        r.mime_type = MimeFor(http.url);
        r.content_length = static_cast<int64_t>(response->body.size());
        client->OnResponse(r);
        if (!*alive) return;
        if (!response->body.empty()) client->OnData(response->body.data(), response->body.size());
        if (!*alive) return;
        client->OnComplete(0);
      });
    });
    return std::make_unique<Load>(alive);
  }

  void OnMetadata(const fp::HlsMetadata& m) override {
    Log("hls metadata: video=%d %dx%d audio=%d duration=%.1f", m.has_video, m.natural_width, m.natural_height,
        m.has_audio, m.duration);
    width_ = m.natural_width;
    SetStage("hls playback");
    player_->SetRate(1);
    Poll();
  }
  void OnBufferingStateChange(bool have_enough) override {
    if (!have_enough) underflows_++;
  }
  void OnLoadedRangesChange(const std::vector<fp::HlsTimeRange>&) override {}
  void OnSeekableRangesChange(const std::vector<fp::HlsTimeRange>&) override {}
  void OnDurationChange(double) override {}
  void OnStartDateChange(std::optional<double>) override {}
  void OnNaturalSizeChange(int32_t w, int32_t) override { width_ = w; }
  void OnEnded() override {}
  void OnError(fp::HlsError error, const std::string& message) override {
    Finish(fpsb::Outcome::kFail, "player error " + std::to_string(static_cast<int>(error)) + ": " + message);
  }
  void OnKeyRequest(const std::string& uri) override {
    Finish(fpsb::Outcome::kFail, "unexpected key request " + uri);
  }

 private:
  static std::string MimeFor(const std::string& url) {
    std::string path = url.substr(0, url.find('?'));
    auto ends = [&](const char* ext) {
      size_t n = strlen(ext);
      return path.size() >= n && path.compare(path.size() - n, n, ext) == 0;
    };
    if (ends(".m3u8")) return "application/vnd.apple.mpegurl";
    if (ends(".ts")) return "video/mp2t";
    if (ends(".aac")) return "audio/aac";
    if (ends(".vtt") || ends(".webvtt")) return "text/vtt";
    if (ends(".mp4") || ends(".m4s") || ends(".m4v") || ends(".m4a") || ends(".cmfv") || ends(".cmfa")) return "video/mp4";
    return "";
  }

  void Poll() {
    double t = player_->CurrentTime();
    if (t >= s_.play_seconds) {
      Finish(fpsb::Outcome::kPass, "played " + std::to_string(t) + " s of native HLS, " + std::to_string(loads_) +
                                       " loads through the helper, width " + std::to_string(width_) +
                                       ", underflows " + std::to_string(underflows_));
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), owner_, ^{
      Poll();
    });
  }

  static void Finish(fpsb::Outcome outcome, const std::string& detail) { g_host->finish(outcome, detail); }

  const fpsb::Scenario& s_;
  dispatch_queue_t owner_;
  std::unique_ptr<fp::FairPlayHlsPlayer> player_;
  int loads_ = 0;
  int underflows_ = 0;
  int32_t width_ = 0;
};

HlsProbe* g_hls_probe = nullptr;

void Player::Fail(const std::string& reason) {
  g_host->finish(fpsb::Outcome::kFail, reason + (g_player ? g_player->State() : ""));
}

}

extern "C" __attribute__((visibility("default"))) void FpsbRunPlayer(const fpsb::Scenario* scenario,
                                                                     const fpsb::Host* host) {
  g_host = host;
  NSSetUncaughtExceptionHandler([](NSException* exception) {
    const char* name = exception.name.UTF8String;
    const char* reason = exception.reason.UTF8String;
    g_host->finish(fpsb::Outcome::kFail, std::string("uncaught exception ") + (name ? name : "?") + ": " +
                                             (reason ? reason : "") + " stage=" + g_host->stage->load());
  });
  if (!scenario->hls_url.empty()) {
    g_hls_probe = new HlsProbe(*scenario);
    g_hls_probe->Start();
    CFRunLoopRun();
    return;
  }
  g_player = new Player(*scenario);
  g_player->Start();
  CFRunLoopRun();
}

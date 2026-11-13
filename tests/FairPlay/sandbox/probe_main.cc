#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "probe_host.h"

extern "C" int sandbox_init_with_parameters(const char* profile,
                                            uint64_t flags,
                                            const char* const parameters[],
                                            char** errorbuf);
extern "C" void sandbox_free_error(char* errorbuf);
extern char** environ;

namespace ft = parc::fairplay::test;

namespace {

const char kLicenseUrl[] = "https://drm-fairplay-licensing.axprod.net/AcquireLicense";
const char kCertificateUrl[] = "https://tools.axinom.com/FPScert/fairplay.cer";
const char kH264Base[] = "https://media.axprod.net/TestVectors/Cmaf/protected_1080p_h264_cbcs/";
const char kH264Token[] =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogIjMwMmY4MGRkLTQxMWUtNDg4Ni1iY2E1LWJiMWY4MDE4YTAyNCIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAiMWVYeWhGWmNGVjljemNtZG5BREpMdz09IiwKICAgICAgICAiaXYiOiAiZC8wWWlhcjBGRHNJVlVpendQbGJtZz09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.5VxBJQsgGVissi9WCNpT7IoykEAmxaEcif6F3SeLvzU";
const char kHevcBase[] = "https://media.axprod.net/TestVectors/H265/protected_cmaf_1080p_h265_singlekey/";
const char kHevcToken[] =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ2ZXJzaW9uIjogMSwKImNvbV9rZXlfaWQiOiAiZjM0ZjgzZWMtZTQyNS00OTYzLWExODMtYjRkNDAwYmNlNDQ0IiwKIm1lc3NhZ2UiOiB7CiAgInR5cGUiOiAiZW50aXRsZW1lbnRfbWVzc2FnZSIsCiAgInZlcnNpb24iOiAyLAogICJsaWNlbnNlIjogewogICAgImFsbG93X3BlcnNpc3RlbmNlIjogdHJ1ZQogIH0sCiAgImNvbnRlbnRfa2V5c19zb3VyY2UiOiB7CiAgICAiaW5saW5lIjogWwogICAgICB7CiAgICAgICAgImlkIjogImFiY2M0NGU1LWMxMjItNDVhYi1hYzgwLWE1YjM1MjJhMGEzMSIsCiAgICAgICAgImVuY3J5cHRlZF9rZXkiOiAibGs1aERneXl1NXl6a3QzMWlVWmF4UT09IiwKICAgICAgICAiaXYiOiAiczhnNHNFemp4Yml2R1pDVGxxU3pQQT09IiwKICAgICAgICAidXNhZ2VfcG9saWN5IjogIlBvbGljeSBBIgogICAgICB9CiAgICBdCiAgfSwKICAiY29udGVudF9rZXlfdXNhZ2VfcG9saWNpZXMiOiBbCiAgICB7CiAgICAgICJuYW1lIjogIlBvbGljeSBBIiwKICAgICAgInBsYXlyZWFkeSI6IHsKICAgICAgICAibWluX2RldmljZV9zZWN1cml0eV9sZXZlbCI6IDE1MCwKICAgICAgICAicGxheV9lbmFibGVycyI6IFsKICAgICAgICAgICI3ODY2MjdEOC1DMkE2LTQ0QkUtOEY4OC0wOEFFMjU1QjAxQTciCiAgICAgICAgXQogICAgICB9CiAgICB9CiAgXQp9fQ.lAwTqoU-rkmyk8QtSn0RrsleMefe2Y5-E5YGoala7yM";
const char kHevcSkd[] = "skd://abcc44e5-c122-45ab-ac80-a5b3522a0a31:B3C838B04CE3C5B8AF19909396A4B33C";

std::mutex g_log_mutex;

void LogLine(const std::string& line) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  std::fwrite(line.data(), 1, line.size(), stdout);
  std::fputc('\n', stdout);
  std::fflush(stdout);
}

void Log(const char* format, ...) __attribute__((format(printf, 1, 2)));
void Log(const char* format, ...) {
  char buffer[4096];
  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  LogLine(buffer);
}

std::atomic<const char*> g_stage{"start"};
std::atomic<bool> g_finished{false};

__attribute__((noreturn)) void Finish(fpsb::Outcome outcome, const std::string& detail) {
  {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    if (g_finished.exchange(true)) {
      while (true) pause();
    }
    std::string line = std::string("RESULT ") + fpsb::OutcomeName(outcome) + " " + detail + "\n";
    std::fwrite(line.data(), 1, line.size(), stdout);
    std::fflush(stdout);
  }
  _exit(int(outcome));
}

std::atomic<int64_t> g_deadline_ms{0};
std::atomic<bool> g_sandboxed{false};

int64_t NowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

void StartWatchdog() {
  std::thread([] {
    while (NowMs() < g_deadline_ms.load()) std::this_thread::sleep_for(std::chrono::milliseconds(100));
    if (g_sandboxed) {
      Finish(fpsb::Outcome::kTimeout,
             std::string("no result in time (main thread blocked or no progress) stage=") + g_stage.load());
    }
    Finish(fpsb::Outcome::kSetup, std::string("setup timed out stage=") + g_stage.load());
  }).detach();
}

int g_helper = -1;
std::mutex g_helper_mutex;

bool Request(const fpsb::HttpRequest& request, fpsb::HttpResponse* response) {
  std::lock_guard<std::mutex> lock(g_helper_mutex);
  std::vector<uint8_t> message;
  if (!fpsb::SendMessage(g_helper, fpsb::EncodeRequest(request))) {
    response->error = "helper write failed";
    return false;
  }
  if (!fpsb::ReceiveMessage(g_helper, &message) || !fpsb::DecodeResponse(message, response)) {
    response->error = "helper read failed";
    return false;
  }
  return true;
}

bool Get(const std::string& url, uint64_t offset, uint64_t length, std::vector<uint8_t>* body,
         std::string* error) {
  std::string key = url + "_" + std::to_string(offset) + "_" + std::to_string(length);
  for (char& c : key) {
    if (std::string(":/?&=%").find(c) != std::string::npos) c = '_';
  }
  fpsb::HttpRequest request{"GET", url, {{"X-Fpsb-Cache", key}}, {}};
  if (length) {
    request.headers.emplace_back(
        "Range", "bytes=" + std::to_string(offset) + "-" + std::to_string(offset + length - 1));
  }
  fpsb::HttpResponse response;
  Request(request, &response);
  if ((response.status != 200 && response.status != 206) || !response.error.empty() || response.body.empty() ||
      (length && response.body.size() != length)) {
    *error = "GET " + url + " -> " + std::to_string(response.status) + " " + response.error;
    return false;
  }
  *body = std::move(response.body);
  return true;
}

struct ByteRange {
  std::string uri;
  uint64_t offset = 0;
  uint64_t length = 0;
};

std::string Trim(const std::string& s) {
  size_t a = s.find_first_not_of(" \t\r");
  size_t b = s.find_last_not_of(" \t\r");
  return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

bool ParseByteRange(const std::string& v, uint64_t next_offset, ByteRange* range) {
  char* end = nullptr;
  range->length = std::strtoull(v.c_str(), &end, 10);
  range->offset = *end == '@' ? std::strtoull(end + 1, nullptr, 10) : next_offset;
  return end != v.c_str();
}

bool ParsePlaylist(const std::string& text, ByteRange* init, std::vector<ByteRange>* segments) {
  std::istringstream lines(text);
  std::string raw;
  uint64_t next_offset = 0;
  ByteRange pending;
  bool have_range = false;
  while (std::getline(lines, raw)) {
    const std::string line = Trim(raw);
    if (line.rfind("#EXT-X-MAP:", 0) == 0) {
      size_t uri = line.find("URI=\"");
      if (uri == std::string::npos) return false;
      uri += 5;
      init->uri = line.substr(uri, line.find('"', uri) - uri);
      size_t br = line.find("BYTERANGE=\"");
      if (br != std::string::npos) {
        br += 11;
        ParseByteRange(line.substr(br, line.find('"', br) - br), 0, init);
      }
    } else if (line.rfind("#EXT-X-BYTERANGE:", 0) == 0) {
      have_range = ParseByteRange(line.substr(17), next_offset, &pending);
    } else if (!line.empty() && line[0] != '#') {
      pending.uri = line;
      if (!have_range) pending.offset = pending.length = 0;
      next_offset = pending.offset + pending.length;
      segments->push_back(pending);
      have_range = false;
    }
  }
  return !init->uri.empty() && !segments->empty();
}

bool LoadHls(const std::string& base, const std::string& playlist, int max_segments, fpsb::Track* track,
             std::string* error) {
  std::vector<uint8_t> text, init_data, segment;
  if (!Get(base + playlist, 0, 0, &text, error)) return false;
  ByteRange init;
  std::vector<ByteRange> segments;
  if (!ParsePlaylist(std::string(text.begin(), text.end()), &init, &segments)) {
    *error = "unparsable playlist " + playlist;
    return false;
  }
  if (!Get(base + init.uri, init.offset, init.length, &init_data, error) ||
      !ft::ParseInitSegment(init_data, &track->info, error)) {
    return false;
  }
  for (int i = 0; i < max_segments && i < int(segments.size()); ++i) {
    std::vector<ft::Sample> samples;
    if (!Get(base + segments[size_t(i)].uri, segments[size_t(i)].offset, segments[size_t(i)].length, &segment,
             error) ||
        !ft::ParseMediaSegment(segment, track->info, &samples, error)) {
      return false;
    }
    track->samples.insert(track->samples.end(), samples.begin(), samples.end());
  }
  track->present = true;
  return true;
}

void Splice(fpsb::Track* to, const fpsb::Track& from, std::vector<ft::Sample> samples, double shift_seconds) {
  if (to->parts.empty()) {
    to->parts.push_back(to->info);
    to->part_of_sample.assign(to->samples.size(), 0);
  }
  const int64_t shift = int64_t(shift_seconds * from.info.timescale);
  for (ft::Sample& s : samples) {
    s.pts += shift;
    s.dts += shift;
    to->samples.push_back(std::move(s));
    to->part_of_sample.push_back(uint8_t(to->parts.size()));
  }
  to->parts.push_back(from.info);
}

double Seconds(const fpsb::Track& track, int64_t ticks) {
  return double(ticks) / track.info.timescale;
}

double EndOf(const fpsb::Track& track, const std::vector<ft::Sample>& samples) {
  double end = 0;
  for (const ft::Sample& s : samples) end = std::max(end, Seconds(track, s.pts + s.duration));
  return end;
}

bool LoadFile(const std::string& path, fpsb::Track* track, std::string* error) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    *error = "can't read " + path;
    return false;
  }
  std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
  if (!ft::ParseInitSegment(data, &track->info, error) ||
      !ft::ParseMediaSegment(data, track->info, &track->samples, error) ||
      (track->samples.empty() && !ft::ParseProgressiveFile(data, track->info, &track->samples, error))) {
    *error = path + ": " + *error;
    return false;
  }
  track->present = true;
  return true;
}

bool LoadScenario(const std::string& name, const std::string& media_dir, fpsb::Scenario* s,
                  std::string* error) {
  s->name = name;
  auto protected_vector = [&](const char* base, const char* video_playlist, int segments, const char* token) {
    s->protected_media = true;
    s->license_url = kLicenseUrl;
    s->license_token = token;
    return LoadHls(base, video_playlist, segments, &s->video, error) &&
           LoadHls(base, "audio-en.m3u8", segments, &s->audio, error) &&
           Get(kCertificateUrl, 0, 0, &s->certificate, error);
  };
  if (name == "h264") {
    if (!protected_vector(kH264Base, "video-H264-720-2100k.m3u8", 3, kH264Token)) return false;
    s->init_data_type = "cenc";
    s->init_data = s->video.info.pssh_boxes;
    return true;
  }
  if (name == "hevc") {
    if (!protected_vector(kHevcBase, "video-H265-720-2100k.m3u8", 3, kHevcToken)) return false;
    s->init_data_type = "skd";
    s->init_data.assign(kHevcSkd, kHevcSkd + sizeof(kHevcSkd) - 1);
    return true;
  }
  if (name == "audio-switch") {
    if (!protected_vector(kH264Base, "video-H264-720-2100k.m3u8", 3, kH264Token)) return false;
    s->init_data_type = "cenc";
    s->init_data = s->video.info.pssh_boxes;
    fpsb::Track aac = std::move(s->audio), eac3;
    if (!LoadFile(media_dir + "/bear-eac3-only-frag.mp4", &eac3, error)) return false;
    std::vector<ft::Sample> first, last;
    for (const ft::Sample& x : aac.samples) {
      if (Seconds(aac, x.pts) < 2.0) first.push_back(x);
    }
    const double switch_back = EndOf(aac, first) + EndOf(eac3, eac3.samples);
    for (const ft::Sample& x : aac.samples) {
      if (Seconds(aac, x.pts) >= switch_back) last.push_back(x);
    }
    s->audio = fpsb::Track{true, aac.info, first, {}, {}};
    Splice(&s->audio, eac3, eac3.samples, EndOf(aac, first));
    Splice(&s->audio, aac, last, 0);
    return true;
  }
  if (name == "video-switch") {
    fpsb::Track h264, hevc;
    if (!LoadFile(media_dir + "/bear-640x360-v_frag.mp4", &h264, error) ||
        !LoadFile(media_dir + "/bear-320x240-v_frag-hevc.mp4", &hevc, error)) {
      return false;
    }
    std::vector<ft::Sample> first;
    for (const ft::Sample& x : h264.samples) {
      if (Seconds(h264, x.pts) < 1.5) first.push_back(x);
    }
    const double hevc_start = EndOf(h264, first);
    s->video = fpsb::Track{true, h264.info, first, {}, {}};
    Splice(&s->video, hevc, hevc.samples, hevc_start);
    Splice(&s->video, h264, h264.samples, hevc_start + EndOf(hevc, hevc.samples));
    return true;
  }
  if (name == "hls-ts") {
    s->hls_url = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8";
    return true;
  }
  if (name == "hls-fmp4") {
    s->hls_url = "https://media.axprod.net/TestVectors/Cmaf/clear_1080p_h264/manifest.m3u8";
    return true;
  }
  if (name == "dolby-vision") return LoadFile(media_dir + "/glass-blowing2-dolby-vision-profile-5-frag.mp4", &s->video, error);
  if (name == "eac3") return LoadFile(media_dir + "/bear-eac3-only-frag.mp4", &s->audio, error);
  if (name == "ac3") return LoadFile(media_dir + "/bear-ac3-only-frag.mp4", &s->audio, error);
  *error = "unknown scenario " + name;
  return false;
}

std::string Canonical(const std::string& path) {
  char resolved[PATH_MAX];
  return realpath(path.c_str(), resolved) ? std::string(resolved) : path;
}

std::string DarwinDir(int name) {
  char buffer[PATH_MAX];
  size_t n = confstr(name, buffer, sizeof(buffer));
  if (n == 0 || n > sizeof(buffer)) return "";
  return Canonical(buffer);
}

std::string OsVersion() {
  char version[64] = {};
  size_t size = sizeof(version);
  if (sysctlbyname("kern.osproductversion", version, &size, nullptr, 0) != 0) return "";
  int major = 0, minor = 0;
  std::sscanf(version, "%d.%d", &major, &minor);
  return std::to_string(major * 100 + minor);
}

std::vector<std::string> GpuSandboxParameters(const std::string& executable, const std::string& log) {
  const char* home = std::getenv("HOME");
  return {
      "EXECUTABLE_PATH", executable,
      "ENABLE_LOGGING", "TRUE",
      "DISABLE_SANDBOX_DENIAL_LOGGING", "FALSE",
      "BUNDLE_PATH", executable.substr(0, executable.rfind('/')),
      "BUNDLE_ID", "org.parc.fairplay-sandbox-probe",
      "BROWSER_PID", std::to_string(getppid()),
      "LOG_FILE_PATH", log,
      "OS_VERSION", OsVersion(),
      "USER_HOMEDIR_AS_LITERAL", Canonical(home ? home : ""),
      "DARWIN_USER_DIR", DarwinDir(_CS_DARWIN_USER_DIR),
      "DARWIN_USER_CACHE_DIR", DarwinDir(_CS_DARWIN_USER_CACHE_DIR),
      "DARWIN_USER_TEMP_DIR", DarwinDir(_CS_DARWIN_USER_TEMP_DIR),
      "DISABLE_METAL_SHADER_CACHE", "FALSE",
      "RESTRICT_GPU_DARWIN_USER_DIRS", "TRUE",
      "WEBNN_COMPILER_PROCESS", "TRUE",
  };
}

bool NetworkAllowed() {
  int s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0) return false;
  sockaddr_in address = {};
  address.sin_family = AF_INET;
  address.sin_port = htons(443);
  address.sin_addr.s_addr = htonl(0x01010101);
  int rv = connect(s, reinterpret_cast<sockaddr*>(&address), sizeof(address));
  close(s);
  return rv == 0;
}

std::string ExecutablePath() {
  char buffer[PATH_MAX];
  uint32_t size = sizeof(buffer);
  if (_NSGetExecutablePath(buffer, &size) != 0) return "";
  return Canonical(buffer);
}

}

int main(int argc, char** argv) {
  std::string profile_path, scenario_name, cache = "/tmp/parc-fairplay-cache", media_dir, log_path = "/dev/null";
  double play_seconds = 5, timeout = 60, setup_timeout = 180;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    auto value = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
    if (arg == "--profile") profile_path = value();
    else if (arg == "--scenario") scenario_name = value();
    else if (arg == "--cache") cache = value();
    else if (arg == "--media-dir") media_dir = value();
    else if (arg == "--play-seconds") play_seconds = std::atof(value().c_str());
    else if (arg == "--timeout") timeout = std::atof(value().c_str());
    else if (arg == "--setup-timeout") setup_timeout = std::atof(value().c_str());
    else if (arg == "--log") log_path = value();
  }
  if (profile_path.empty() || scenario_name.empty()) {
    Log("usage: %s --profile <sb> --scenario <name> [--cache dir] [--media-dir dir]", argv[0]);
    return int(fpsb::Outcome::kSetup);
  }
  Log("pid %d scenario %s", getpid(), scenario_name.c_str());
  g_deadline_ms = NowMs() + int64_t(setup_timeout * 1000);
  StartWatchdog();

  const std::string executable = ExecutablePath();
  const std::string directory = executable.substr(0, executable.rfind('/'));
  const std::string helper_path = directory + "/fpsbhelper";
  int fds[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) Finish(fpsb::Outcome::kSetup, "socketpair");
  std::string fd_text = std::to_string(fds[1]);
  const char* helper_argv[] = {helper_path.c_str(), fd_text.c_str(), cache.c_str(), nullptr};
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_addclose(&actions, fds[0]);
  pid_t helper = 0;
  int spawned = posix_spawn(&helper, helper_path.c_str(), &actions, nullptr, const_cast<char**>(helper_argv),
                            environ);
  posix_spawn_file_actions_destroy(&actions);
  if (spawned != 0) Finish(fpsb::Outcome::kSetup, "helper spawn failed");
  close(fds[1]);
  g_helper = fds[0];

  g_stage = "download";
  auto* scenario = new fpsb::Scenario();
  scenario->play_seconds = play_seconds;
  std::string error;
  if (!LoadScenario(scenario_name, media_dir, scenario, &error)) Finish(fpsb::Outcome::kSetup, error);
  Log("media: %zu video and %zu audio samples, %zu-byte init data, %zu-byte certificate",
      scenario->video.samples.size(), scenario->audio.samples.size(), scenario->init_data.size(),
      scenario->certificate.size());

  std::ifstream profile_file(profile_path);
  std::string profile((std::istreambuf_iterator<char>(profile_file)), std::istreambuf_iterator<char>());
  if (profile.empty()) Finish(fpsb::Outcome::kSetup, "unreadable profile " + profile_path);
  std::vector<std::string> parameters = GpuSandboxParameters(executable, log_path);
  std::vector<const char*> c_parameters;
  for (const std::string& p : parameters) c_parameters.push_back(p.c_str());
  c_parameters.push_back(nullptr);
  char* sandbox_error = nullptr;
  g_stage = "sandbox_init";
  if (sandbox_init_with_parameters(profile.c_str(), 0, c_parameters.data(), &sandbox_error) != 0) {
    std::string message = sandbox_error ? sandbox_error : "?";
    sandbox_free_error(sandbox_error);
    Finish(fpsb::Outcome::kSetup, "sandbox_init_with_parameters: " + message);
  }
  g_deadline_ms = NowMs() + int64_t(timeout * 1000);
  g_sandboxed = true;
  if (NetworkAllowed()) Finish(fpsb::Outcome::kSetup, "outbound network allowed in the sandbox");
  Log("sandboxed; outbound network denied");

  g_stage = "dlopen player";
  const std::string player_path = directory + "/libfpsbplayer.dylib";
  void* player = dlopen(player_path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (!player) Finish(fpsb::Outcome::kFail, std::string("player failed to load in the sandbox: ") + dlerror());
  auto run = reinterpret_cast<fpsb::RunPlayerFunction>(dlsym(player, fpsb::kRunPlayerSymbol));
  if (!run) Finish(fpsb::Outcome::kSetup, "player has no FpsbRunPlayer");
  static const fpsb::Host host = {&LogLine, &g_stage, &Request, &Finish};
  run(scenario, &host);
  Finish(fpsb::Outcome::kFail, "player returned");
}

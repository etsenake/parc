// The interface between the sandboxed probe (probe_main.cc, plain C++) and
// the player it opens after the sandbox is applied (libfpsbplayer.dylib,
// probe_player.mm, which links AVFoundation and the FairPlay core). Parc's GPU
// helper does the same: it applies its sandbox before it loads the engine
// framework, so every framework initializer runs sandboxed.
#ifndef PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_HOST_H_
#define PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_HOST_H_

#include <atomic>
#include <string>
#include <vector>

#include "fmp4_parser.h"
#include "probe_wire.h"

namespace fpsb {

// Exit codes are the enum values. run.py treats only kFail and kTimeout as
// evidence about the profile; kSetup and kInconclusive say nothing about it.
enum class Outcome : int {
  kPass = 0,
  kFail = 1,          // Playback (or opening the player) failed in the sandbox.
  kSetup = 2,         // Before the sandbox (download, parse, sandbox_init), or
                      // a broken probe build.
  kInconclusive = 3,  // In the sandbox, but not the profile's doing (license
                      // server down, output obscured by screen capture).
  kTimeout = 4,       // No result in time; a denied service can do this.
};

inline const char* OutcomeName(Outcome outcome) {
  switch (outcome) {
    case Outcome::kPass: return "PASS";
    case Outcome::kFail: return "FAIL";
    case Outcome::kSetup: return "SETUP-FAIL";
    case Outcome::kInconclusive: return "INCONCLUSIVE";
    case Outcome::kTimeout: return "TIMEOUT";
  }
  return "?";
}

struct Track {
  bool present = false;
  parc::fairplay::test::TrackInfo info;
  std::vector<parc::fairplay::test::Sample> samples;
};

struct Scenario {
  std::string name;
  Track video;
  Track audio;
  bool protected_media = false;
  // Protected only: "cenc" (the init data is the vector's pssh boxes; the
  // session exchanges WebKit's [{keyID, payload}] JSON) or "skd" (an skd URI;
  // raw SPC and CKC).
  std::string init_data_type;
  std::vector<uint8_t> init_data;
  std::vector<uint8_t> certificate;
  std::string license_url;
  std::string license_token;
  double play_seconds = 5;
};

struct Host {
  // Writes one whole line to stdout; safe from any thread.
  void (*log)(const std::string& line);
  // What the player is doing, for the timeout report. String literals only.
  std::atomic<const char*>* stage;
  // A request through the unsandboxed helper; safe from any thread.
  bool (*request)(const HttpRequest& request, HttpResponse* response);
  // Prints "RESULT <outcome> <detail>" and exits with the outcome's code.
  void (*finish)(Outcome outcome, const std::string& detail) __attribute__((noreturn));
};

// Exported by the player; never returns.
using RunPlayerFunction = void (*)(const Scenario* scenario, const Host* host);
inline constexpr char kRunPlayerSymbol[] = "FpsbRunPlayer";

}  // namespace fpsb

#endif  // PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_HOST_H_

#ifndef PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_HOST_H_
#define PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_HOST_H_

#include <atomic>
#include <string>
#include <vector>

#include "fmp4_parser.h"
#include "probe_wire.h"

namespace fpsb {

enum class Outcome : int {
  kPass = 0,
  kFail = 1,
  kSetup = 2,
  kInconclusive = 3,
  kTimeout = 4,
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
  std::vector<parc::fairplay::test::TrackInfo> parts;
  std::vector<uint8_t> part_of_sample;
};

struct Scenario {
  std::string name;
  Track video;
  Track audio;
  bool protected_media = false;
  std::string init_data_type;
  std::vector<uint8_t> init_data;
  std::vector<uint8_t> certificate;
  std::string license_url;
  std::string license_token;
  double play_seconds = 5;
  std::string hls_url;
};

struct Host {
  void (*log)(const std::string& line);
  std::atomic<const char*>* stage;
  bool (*request)(const HttpRequest& request, HttpResponse* response);
  void (*finish)(Outcome outcome, const std::string& detail) __attribute__((noreturn));
};

using RunPlayerFunction = void (*)(const Scenario* scenario, const Host* host);
inline constexpr char kRunPlayerSymbol[] = "FpsbRunPlayer";

}

#endif

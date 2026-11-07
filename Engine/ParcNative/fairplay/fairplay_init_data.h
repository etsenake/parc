// EME initialization data for the FairPlay key system. Formats follow WebKit's
// FairPlay CDM (CDMFairPlayStreaming.cpp, CDMInstanceFairPlayStreamingAVFObjC.mm)
// so pages written for Safari's modern EME work unchanged.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace parc::fairplay {

// Renderers find keys by the 16-byte key ID in each sample's format
// description (see fairplay_renderer.h), so every request is made through init
// data that AVFoundation turns into a request named by that key ID: sinf JSON
// or a FairPlay 'pssh' as {"pssh": "<base64>"}. Requests named any other way
// (an skd URI, mpts) produce licenses no renderer can use.
enum class InitDataType {
  // UTF-8 "skd://..." URI from an HLS EXT-X-KEY. The whole URI is the SPC
  // content identifier (WebKit). This plan is the MSE route's: when the URI's
  // host is the key ID (a UUID or 32 hex digits), the request goes through a
  // FairPlay pssh for that key ID; otherwise it is named by the URI and its key
  // can't be used by a renderer. With an HLS asset attached, FairPlayCdm names
  // the request by the URI instead (fairplay_hls_keys.h).
  // Parc extension for WebKit's legacy AVFoundation-player sessions:
  // {"skd": "<URI>", "contentId": "<base64>"} is that URI's request with the
  // SPC named by contentId.
  kSkd,
  // JSON {"sinf": ["<base64 sinf payload>"]}: frma/schm/schi boxes, the form
  // AVStreamDataParser emits. Passed through; the 'tenc' key ID is the SPC
  // content identifier (WebKit). Parc extension for WebKit's legacy
  // com.apple.fps.2_N sessions: a "contentId" member (base64) names the SPC
  // instead, and AVFoundation gets the sinf entries alone.
  kSinf,
  // Concatenated 'pssh' boxes (Chromium's MP4 parser output). The FairPlay
  // pssh alone goes to AVFoundation (WebKit). Parc extension: without one, the
  // key IDs the other boxes name are requested as for kKeyIds.
  kCenc,
  // JSON {"kids": ["<base64url key ID>", ...]} (W3C). Parc extension, not in
  // WebKit: one request per key ID through a FairPlay pssh naming it, with the
  // raw key ID as the SPC content identifier, as WebKit names sinf requests.
  kKeyIds,
  // JSON {"codc": <number>, "mtyp": <number>, "cont": "mpts"}: MPEG-2 TS
  // content (WebKit on macOS, HAVE(FAIRPLAYSTREAMING_MTPS_INITDATA)). Passed
  // through as the request's init data with no identifier. It names no key
  // ID, so WebKit names the request "TransportStreamIdentifier"
  // (extractKeyIDsMpts): that is the SPC content identifier and the key ID
  // key statuses report. Its key can't be used by a renderer.
  kMpts,
};

std::optional<InitDataType> InitDataTypeFromName(const std::string& name);
const char* InitDataTypeName(InitDataType type);

// One -processContentKeyRequestWithIdentifier:initializationData:options: call.
struct ContentKeyRequestPlan {
  std::string identifier;                     // NSString identifier, or empty.
  std::vector<uint8_t> initialization_data;   // Or empty.
  // SPC content identifier. Empty means the request's own key ID (WebKit's
  // rule for requests AVFoundation names by key ID).
  std::vector<uint8_t> content_identifier;
  // 16-byte key IDs this call is expected to produce keys for. Empty when the
  // init data names none (an opaque skd URI, mpts).
  std::vector<std::vector<uint8_t>> key_ids;
};

struct InitDataPlan {
  std::vector<ContentKeyRequestPlan> calls;
  // skd init data (either form): the URI. An HLS asset asks for its key by
  // this URI, so with one attached FairPlayCdm names the request by it.
  std::string skd_uri;
  // cenc/keyids sessions exchange JSON arrays of {keyID, payload} entries;
  // skd/sinf/mpts sessions exchange the raw SPC and CKC.
  bool json_messages = false;
  std::string error;  // Non-empty: the init data is malformed or unsupported.
};

InitDataPlan PlanContentKeyRequests(InitDataType type,
                                    const std::vector<uint8_t>& init_data);

// The key ID embedded in an skd URI host, if it is a UUID or 32 hex digits
// (skd://302f80dd-411e-4886-bca5-bb1f8018a024:77FD...). Key IDs are opaque in
// skd URIs generally, so this may return nullopt.
std::optional<std::vector<uint8_t>> KeyIdFromSkdUri(const std::string& uri);

// Default key IDs in the 'tenc' boxes of a sinf payload, as WebKit's
// extractKeyIDsSinf reads them (top-level schm/schi boxes).
std::vector<std::vector<uint8_t>> KeyIdsFromSinfPayload(const std::vector<uint8_t>& sinf);

struct PsshBox {
  std::vector<uint8_t> system_id;  // 16 bytes.
  uint8_t version = 0;
  std::vector<std::vector<uint8_t>> key_ids;  // Version 1 only.
  std::vector<uint8_t> data;
  std::vector<uint8_t> box;  // The whole box.
};

// Parses concatenated 'pssh' boxes. Returns nullopt if any box is malformed.
std::optional<std::vector<PsshBox>> ParsePsshBoxes(const std::vector<uint8_t>& data);

// A minimal FairPlay 'pssh' naming |key_id|, in the layout WebKit's
// ISOFairPlayStreamingPsshBox reads: fpsd { fpsi(scheme), fpsk { fkri(key ID) } }.
// AVFoundation makes one request named by the key ID from it; the scheme field
// doesn't affect the key (a 'cenc' box keys 'cbcs' content).
std::vector<uint8_t> FairPlayPsshForKeyId(const std::vector<uint8_t>& key_id);

// Key IDs a non-FairPlay PSSH names: the version 1 list, or for Widevine
// version 0 the key_id fields (2) of its WidevinePsshData protobuf.
std::vector<std::vector<uint8_t>> KeyIdsFromPssh(const PsshBox& box);

extern const uint8_t kFairPlaySystemId[16];
extern const uint8_t kWidevineSystemId[16];

}  // namespace parc::fairplay

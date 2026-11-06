// FairPlay Streaming key sessions over AVContentKeySession, shaped like
// media::ContentDecryptionModule: one object per MediaKeys, sessions created
// from EME init data, license messages passed through the page.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_init_data.h"
#include "fairplay_types.h"

namespace parc::fairplay {

// media::CdmMessageType.
enum class MessageType { kLicenseRequest, kLicenseRenewal, kLicenseRelease };

// media::CdmKeyInformation::KeyStatus.
enum class KeyStatus {
  kUsable,
  kInternalError,
  kExpired,
  kOutputRestricted,
  kOutputDownscaled,
  kStatusPending,
  kReleased,
};

const char* KeyStatusName(KeyStatus status);

struct KeyInfo {
  // The 16-byte key ID when the init data or request names one; otherwise
  // the request's identifier bytes (the skd URI), as WebKit reports it.
  std::vector<uint8_t> key_id;
  KeyStatus status = KeyStatus::kStatusPending;
  uint32_t system_code = 0;
};

// media::ContentDecryptionModule's session callbacks.
class FairPlayCdmClient {
 public:
  virtual ~FairPlayCdmClient() = default;
  virtual void OnSessionMessage(const std::string& session_id,
                                MessageType type,
                                const std::vector<uint8_t>& message) = 0;
  virtual void OnSessionKeysChange(const std::string& session_id,
                                   bool has_additional_usable_key,
                                   const std::vector<KeyInfo>& keys) = 0;
  virtual void OnSessionClosed(const std::string& session_id) = 0;
};

// Messages. skd and sinf sessions send the raw SPC and take the raw CKC.
// cenc and keyids sessions send and take a JSON array, one entry per key:
//   message  [{"keyID": "<base64>", "payload": "<base64 SPC>"}, ...]
//   response [{"keyID": "<base64>", "payload": "<base64 CKC>"} or
//             {"keyID": "<base64>", "error": <integer>}, ...]
// keyID is the KeyInfo key ID. As in WebKit, an UpdateSession with the
// literal "renew" asks for a renewal message for the session's last key.
class FairPlayCdm {
 public:
  using ResultCallback = std::function<void(const Result&)>;
  using SessionCallback = std::function<void(const Result&, const std::string& session_id)>;
  using KeysChangedCallback = std::function<void()>;

  // FairPlay Streaming through AVContentKeySession, with
  // AVSampleBufferDisplayLayer and AVSampleBufferAudioRenderer usable as
  // content key recipients (FairPlayRenderer's key path).
  static bool IsSupported();

  FairPlayCdm(FairPlayCdmClient* client, PostTask post_task);
  ~FairPlayCdm();
  FairPlayCdm(const FairPlayCdm&) = delete;
  FairPlayCdm& operator=(const FairPlayCdm&) = delete;

  // Required before CreateSessionAndGenerateRequest; it is the app
  // identifier of every SPC.
  void SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done);

  // Resolves with the session ID once the license request is ready, then
  // sends it through OnSessionMessage (kLicenseRequest).
  void CreateSessionAndGenerateRequest(InitDataType type,
                                       std::vector<uint8_t> init_data,
                                       SessionCallback done);

  // Resolves once AVFoundation has accepted (or rejected) every CKC in
  // |response|; key statuses follow through OnSessionKeysChange.
  void UpdateSession(const std::string& session_id,
                     std::vector<uint8_t> response,
                     ResultCallback done);

  // Expires the session's keys, then reports OnSessionClosed.
  void CloseSession(const std::string& session_id, ResultCallback done);

  // Temporary sessions only: expires the keys and reports them released,
  // leaving the session open until CloseSession.
  void RemoveSession(const std::string& session_id, ResultCallback done);

  // True if some open session holds a usable key for |key_id|.
  bool HasUsableKey(const std::vector<uint8_t>& key_id) const;

  // Called on the owner sequence after any key status change in any session.
  uint64_t AddKeysChangedObserver(KeysChangedCallback callback);
  void RemoveKeysChangedObserver(uint64_t id);

  // Implementation access for FairPlayRenderer (fairplay_key_session_internal.h).
  class Impl;
  Impl* impl() const { return impl_.get(); }

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay

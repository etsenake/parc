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

// The EME session types WebKit's FairPlay CDM serves on macOS
// (CDMInstanceSessionFairPlayStreamingAVFObjC::isLicenseTypeSupported):
// "temporary" and Safari's "persistent-usage-record". "persistent-license" is
// iOS-only there.
enum class SessionType { kTemporary, kPersistentUsageRecord };

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

// Every promise callback and client callback runs in a later task posted to the
// owner sequence, never inside a call into this class.
//
// Messages. skd and sinf sessions send the raw SPC and take the raw CKC.
// cenc and keyids sessions send and take a JSON array, one entry per key:
//   message  [{"keyID": "<base64>", "payload": "<base64 SPC>"}, ...]
//   response [{"keyID": "<base64>", "payload": "<base64 CKC>"} or
//             {"keyID": "<base64>", "error": <integer>}, ...]
// keyID is the KeyInfo key ID; each response entry goes to the request whose
// message entry carried that keyID, and a response naming a keyID twice is
// rejected. As in WebKit, an UpdateSession with the
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

  // EME key system names this CDM serves, as WebKit's
  // CDMFactoryFairPlayStreaming::supportsKeySystem: "com.apple.fps" and
  // anything starting with "com.apple.fps." ("com.apple.fps.3_0", or the bare
  // prefix). Matching is case-sensitive. The prefixed legacy WebKitMediaKeys API that pages also
  // probe ("com.apple.fps.2_0") has no Chromium counterpart.
  static bool IsKeySystemSupported(const std::string& key_system);

  // "cenc", "sinf", "skd", "mpts" and, as a Parc extension, "keyids".
  static bool IsInitDataTypeSupported(const std::string& init_data_type);

  FairPlayCdm(FairPlayCdmClient* client, PostTask post_task);
  ~FairPlayCdm();
  FairPlayCdm(const FairPlayCdm&) = delete;
  FairPlayCdm& operator=(const FairPlayCdm&) = delete;

  // Required before CreateSessionAndGenerateRequest; it is the app
  // identifier of every SPC.
  void SetServerCertificate(std::vector<uint8_t> certificate, ResultCallback done);

  // Whether the MediaKeys' configuration allows persistent state (its
  // persistentState is "required"), as WebKit's
  // CDMInstanceFairPlayStreamingAVFObjC::initializeWithConfiguration records
  // it. persistent-usage-record sessions need it. Off by default; set before
  // the first session.
  void SetPersistentStateAllowed(bool allowed);

  // The MediaKeys' storage directory, as WebKit's
  // CDMInstanceFairPlayStreamingAVFObjC::setStorageDirectory: created if
  // missing, and AVFoundation keeps its expired-session reports in
  // "SecureStop.plist" there. Empty: none (a private window). With persistent
  // state allowed and a directory, the shared AVContentKeySession is created
  // with that storage. Set before the first session.
  void SetStorageDirectory(const std::string& directory);

  // The document's MediaKeys hash salt (WebKit's per document origin and
  // top-level origin salt, which clearing site data replaces): every SPC an
  // AVContentKeyRequest makes then carries a device identifier randomized
  // from it, as WebKit's optionsForKeyRequestWithHashSalt. Empty: AVFoundation's
  // own identifier. Set before the first session.
  void SetDeviceIdentifierSalt(const std::string& salt);

  // Resolves with the session ID once the license request is ready, then
  // sends it through OnSessionMessage (kLicenseRequest). As in WebKit, the ID
  // is the uppercase hex of the session's random 16-byte identifier
  // (WebAVContentKeyGroup's UUID). A persistent-usage-record session is
  // refused (kNotSupported) unless persistent state is allowed.
  //
  // skd with an HLS asset attached (FairPlayHlsKeyLoader): the request
  // is named by the URI, with the URI (or a legacy session's contentId) as the
  // SPC content identifier (WebKit). It takes the asset's held loading request
  // for that URI (the asset reported the key as needed), or waits for the
  // asset to ask. Without an asset, skd plans as PlanContentKeyRequests says
  // (the MSE route).
  void CreateSessionAndGenerateRequest(SessionType session_type,
                                       InitDataType type,
                                       std::vector<uint8_t> init_data,
                                       SessionCallback done);
  // A temporary session.
  void CreateSessionAndGenerateRequest(InitDataType type,
                                       std::vector<uint8_t> init_data,
                                       SessionCallback done);

  // As WebKit's loadSession: a persistent-usage-record session loads the
  // expired-session reports AVFoundation keeps under |session_id| (their
  // PlaybackSessionID). Resolves with |session_id| and then reports one
  // released key with an empty key ID per report when there are any; resolves
  // with an empty ID (EME's false) when there are none or no server
  // certificate. Rejects with kTypeError without persistent state or storage,
  // kQuotaExceeded if a session with that ID is open, and kNotSupported for
  // other session types. The loaded session's remove() then sends the reports.
  void LoadSession(SessionType session_type,
                   const std::string& session_id,
                   SessionCallback done);

  // Resolves once AVFoundation has accepted (or rejected) every CKC in
  // |response|; key statuses follow through OnSessionKeysChange. Calls made
  // while an update is in flight run in order after it. During a renewal the
  // answered key stays usable until the renewal's response settles.
  void UpdateSession(const std::string& session_id,
                     std::vector<uint8_t> response,
                     ResultCallback done);

  // Expires the session's keys, then reports OnSessionClosed.
  void CloseSession(const std::string& session_id, ResultCallback done);

  // As WebKit's removeSessionData: revokes the session's keys and leaves it
  // open until CloseSession. A persistent-usage-record session (with
  // persistent state, storage and a server certificate) then reports one
  // released key with an empty key ID per expired-session report of
  // AVFoundation's whose PlaybackSessionID is its session ID, sends those
  // reports as a kLicenseRelease message (a binary property list: the report,
  // or an array of them) when there are any, and resolves. Any other session
  // reports no keys and rejects with kNotSupported. UpdateSession with the
  // literal "acknowledged" then removes the reports from the storage.
  void RemoveSession(const std::string& session_id, ResultCallback done);

  // True if some open session holds a usable key for |key_id|.
  bool HasUsableKey(const std::vector<uint8_t>& key_id) const;

  // True if some open session has a key request, answered or not, for a key
  // ID |init_data| names (WebKit's CDMInstanceFairPlayStreamingAVFObjC::
  // sessionForKeyIDs over the requests' key IDs). A removed session keeps its
  // requests; a closed one has none. False when |init_data| names no key ID.
  // Safari's Media Source fires `encrypted` only when this is false for its
  // MediaKeys (AudioVideoRendererAVFObjC::setInitData).
  bool HasSessionForInitData(InitDataType type,
                             const std::vector<uint8_t>& init_data) const;

  // Called on the owner sequence after any key status change in any session.
  uint64_t AddKeysChangedObserver(KeysChangedCallback callback);
  void RemoveKeysChangedObserver(uint64_t id);

  // Implementation access for FairPlayRenderer and FairPlayHlsKeyLoader
  // (fairplay_key_session_internal.h).
  class Impl;
  Impl* impl() const { return impl_.get(); }
  std::weak_ptr<Impl> weak_impl() const { return impl_; }

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay

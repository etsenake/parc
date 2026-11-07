// media::ContentDecryptionModule over the FairPlay core's FairPlayCdm
// (AVContentKeySession), served by the GPU process's media service through
// MojoCdmService. Its CdmContext hands the key session to the FairPlay
// media::Renderer of the same media service, which joins it as a content key
// recipient; there is no media::Decryptor.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_ADAPTER_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_ADAPTER_H_

#include <stdint.h>

#include <memory>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/callback_registry.h"
#include "media/base/cdm_context.h"
#include "media/base/cdm_promise.h"
#include "media/base/cdm_promise_adapter.h"
#include "media/base/content_decryption_module.h"
#include "third_party/parc_fairplay/core/fairplay_key_session.h"

namespace media {

class FairPlayCdmAdapter final : public ContentDecryptionModule,
                                 public CdmContext,
                                 public parc::fairplay::FairPlayCdmClient {
 public:
  // Returns null if |key_system| isn't a FairPlay key system or this macOS
  // lacks the AVFoundation support the core needs. Must be called on the
  // sequence the CDM will live on (the media service's).
  // |allow_persistent_state| is the CdmConfig's (the configuration's
  // persistentState is "required"); persistent-usage-record sessions need it.
  // |storage_directory| is the frame's FairPlay storage from the browser
  // (empty: none), where AVFoundation keeps expired-session reports.
  // |device_id_salt| is the frame's media device ID salt from the browser
  // (WebKit's MediaKeys hash salt; empty: none), which randomizes the device
  // identifier in every SPC.
  static scoped_refptr<FairPlayCdmAdapter> Create(
      const std::string& key_system,
      bool allow_persistent_state,
      const base::FilePath& storage_directory,
      const std::string& device_id_salt,
      const SessionMessageCB& session_message_cb,
      const SessionClosedCB& session_closed_cb,
      const SessionKeysChangeCB& session_keys_change_cb,
      const SessionExpirationUpdateCB& session_expiration_update_cb);

  FairPlayCdmAdapter(
      bool allow_persistent_state,
      const base::FilePath& storage_directory,
      const std::string& device_id_salt,
      const SessionMessageCB& session_message_cb,
      const SessionClosedCB& session_closed_cb,
      const SessionKeysChangeCB& session_keys_change_cb,
      const SessionExpirationUpdateCB& session_expiration_update_cb);
  FairPlayCdmAdapter(const FairPlayCdmAdapter&) = delete;
  FairPlayCdmAdapter& operator=(const FairPlayCdmAdapter&) = delete;

  // ContentDecryptionModule implementation.
  void SetServerCertificate(const std::vector<uint8_t>& certificate,
                            std::unique_ptr<SimpleCdmPromise> promise) override;
  void CreateSessionAndGenerateRequest(
      CdmSessionType session_type,
      EmeInitDataType init_data_type,
      const std::vector<uint8_t>& init_data,
      std::unique_ptr<NewSessionCdmPromise> promise) override;
  void LoadSession(CdmSessionType session_type,
                   const std::string& session_id,
                   std::unique_ptr<NewSessionCdmPromise> promise) override;
  void UpdateSession(const std::string& session_id,
                     const std::vector<uint8_t>& response,
                     std::unique_ptr<SimpleCdmPromise> promise) override;
  void CloseSession(const std::string& session_id,
                    std::unique_ptr<SimpleCdmPromise> promise) override;
  void RemoveSession(const std::string& session_id,
                     std::unique_ptr<SimpleCdmPromise> promise) override;
  CdmContext* GetCdmContext() override;
  void DeleteOnCorrectThread() const override;

  // CdmContext implementation.
  std::unique_ptr<CallbackRegistration> RegisterEventCB(
      EventCB event_cb) override;
  bool RequiresFairPlayRenderer() override;
  parc::fairplay::FairPlayCdm* GetFairPlayCdm() override;
  void ParcHasSessionForInitData(EmeInitDataType init_data_type,
                                 const std::vector<uint8_t>& init_data,
                                 ParcHasSessionForInitDataCB done) override;

  // parc::fairplay::FairPlayCdmClient implementation.
  void OnSessionMessage(const std::string& session_id,
                        parc::fairplay::MessageType type,
                        const std::vector<uint8_t>& message) override;
  void OnSessionKeysChange(
      const std::string& session_id,
      bool has_additional_usable_key,
      const std::vector<parc::fairplay::KeyInfo>& keys) override;
  void OnSessionClosed(const std::string& session_id) override;

 private:
  friend class base::DeleteHelper<FairPlayCdmAdapter>;
  ~FairPlayCdmAdapter() override;

  void OnPromiseResult(uint32_t promise_id,
                       const parc::fairplay::Result& result);
  void OnNewSessionResult(uint32_t promise_id,
                          const parc::fairplay::Result& result,
                          const std::string& session_id);

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  const SessionMessageCB session_message_cb_;
  const SessionClosedCB session_closed_cb_;
  const SessionKeysChangeCB session_keys_change_cb_;
  // FairPlay licenses carry no expiration the page can read, so this is never
  // run (EME reports NaN).
  const SessionExpirationUpdateCB session_expiration_update_cb_;

  CdmPromiseAdapter promises_;
  CallbackRegistry<EventCB::RunType> event_callbacks_;

  // Declared after the callbacks it calls into, so it's destroyed first; the
  // core drops pending work when destroyed.
  std::unique_ptr<parc::fairplay::FairPlayCdm> cdm_;

  SEQUENCE_CHECKER(sequence_checker_);

  base::WeakPtrFactory<FairPlayCdmAdapter> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_ADAPTER_H_

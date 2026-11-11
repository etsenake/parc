// Parc's FairPlay media service's CdmFactory: creates FairPlay CDMs and
// refuses every other key system (library CDMs such as Widevine run in their
// own CdmService process and never reach it).
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

#include <string>

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "media/base/cdm_factory.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"

namespace media {

class FairPlayCdmFactory final : public CdmFactory {
 public:
  // |frame_host| (the document's browser end) gives every FairPlay CDM the
  // document's device ID salt and names the storage of one whose
  // configuration allows persistent state. It outlives this factory (both
  // belong to the document's FairPlayFrameMedia).
  explicit FairPlayCdmFactory(mojom::FairPlayFrameHost* frame_host);
  FairPlayCdmFactory(const FairPlayCdmFactory&) = delete;
  FairPlayCdmFactory& operator=(const FairPlayCdmFactory&) = delete;
  ~FairPlayCdmFactory() override;

  // CdmFactory implementation. |cdm_created_cb| runs asynchronously.
  void Create(const CdmConfig& cdm_config,
              const SessionMessageCB& session_message_cb,
              const SessionClosedCB& session_closed_cb,
              const SessionKeysChangeCB& session_keys_change_cb,
              const SessionExpirationUpdateCB& session_expiration_update_cb,
              CdmCreatedCB cdm_created_cb) override;

 private:
  void CreateWithSalt(
      const CdmConfig& cdm_config,
      const SessionMessageCB& session_message_cb,
      const SessionClosedCB& session_closed_cb,
      const SessionKeysChangeCB& session_keys_change_cb,
      const SessionExpirationUpdateCB& session_expiration_update_cb,
      CdmCreatedCB cdm_created_cb,
      const std::string& device_id_salt);
  void CreateWithStorage(
      const CdmConfig& cdm_config,
      const SessionMessageCB& session_message_cb,
      const SessionClosedCB& session_closed_cb,
      const SessionKeysChangeCB& session_keys_change_cb,
      const SessionExpirationUpdateCB& session_expiration_update_cb,
      CdmCreatedCB cdm_created_cb,
      const std::string& device_id_salt,
      const base::FilePath& storage_directory);

  const raw_ptr<mojom::FairPlayFrameHost> frame_host_;
  base::WeakPtrFactory<FairPlayCdmFactory> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

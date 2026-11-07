// The GPU process media service's CdmFactory: creates FairPlay CDMs and
// refuses every other key system (library CDMs such as Widevine run in their
// own CdmService process and never reach it).
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

#include "base/files/file_path.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "media/base/cdm_factory.h"
#include "media/mojo/mojom/frame_interface_factory.mojom.h"

namespace media {

class FairPlayCdmFactory final : public CdmFactory {
 public:
  // |frame_interfaces| (the frame's browser services, may be null) names the
  // storage of a CDM whose configuration allows persistent state. It outlives
  // this factory (both belong to the media service's InterfaceFactoryImpl).
  explicit FairPlayCdmFactory(mojom::FrameInterfaceFactory* frame_interfaces);
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
  void CreateWithStorage(
      const CdmConfig& cdm_config,
      const SessionMessageCB& session_message_cb,
      const SessionClosedCB& session_closed_cb,
      const SessionKeysChangeCB& session_keys_change_cb,
      const SessionExpirationUpdateCB& session_expiration_update_cb,
      CdmCreatedCB cdm_created_cb,
      const base::FilePath& storage_directory);

  const raw_ptr<mojom::FrameInterfaceFactory> frame_interfaces_;
  base::WeakPtrFactory<FairPlayCdmFactory> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

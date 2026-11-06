// The GPU process media service's CdmFactory: creates FairPlay CDMs and
// refuses every other key system (library CDMs such as Widevine run in their
// own CdmService process and never reach it).
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

#include "media/base/cdm_factory.h"

namespace media {

class FairPlayCdmFactory final : public CdmFactory {
 public:
  FairPlayCdmFactory();
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
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_CDM_FACTORY_H_

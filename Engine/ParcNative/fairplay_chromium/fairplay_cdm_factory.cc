#include "third_party/parc_fairplay/chromium/fairplay_cdm_factory.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/cdm_config.h"
#include "third_party/parc_fairplay/chromium/fairplay_cdm_adapter.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"

namespace media {

FairPlayCdmFactory::FairPlayCdmFactory() = default;

FairPlayCdmFactory::~FairPlayCdmFactory() = default;

void FairPlayCdmFactory::Create(
    const CdmConfig& cdm_config,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb,
    CdmCreatedCB cdm_created_cb) {
  scoped_refptr<ContentDecryptionModule> cdm;
  CreateCdmStatus status = CreateCdmStatus::kSuccess;
  // The key system comes from the render process; validate it here too.
  if (!parc::fairplay::IsFairPlayKeySystem(cdm_config.key_system)) {
    status = CreateCdmStatus::kUnsupportedKeySystem;
  } else {
    cdm = FairPlayCdmAdapter::Create(
        cdm_config.key_system, session_message_cb, session_closed_cb,
        session_keys_change_cb, session_expiration_update_cb);
    if (!cdm) {
      status = CreateCdmStatus::kCdmNotSupported;
    }
  }
  DVLOG(1) << __func__ << ": " << cdm_config.key_system
           << " status=" << static_cast<int>(status);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(std::move(cdm_created_cb), std::move(cdm),
                                status));
}

}  // namespace media

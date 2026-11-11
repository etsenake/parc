#include "third_party/parc_fairplay/chromium/fairplay_cdm_factory.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/cdm_config.h"
#include "media/mojo/mojom/frame_interface_factory.mojom.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/parc_fairplay/chromium/fairplay_cdm_adapter.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"

namespace media {

FairPlayCdmFactory::FairPlayCdmFactory(
    mojom::FrameInterfaceFactory* frame_interfaces)
    : frame_interfaces_(frame_interfaces), frame_host_(nullptr) {}

FairPlayCdmFactory::FairPlayCdmFactory(mojom::FairPlayFrameHost* frame_host)
    : frame_interfaces_(nullptr), frame_host_(frame_host) {}

FairPlayCdmFactory::~FairPlayCdmFactory() = default;

void FairPlayCdmFactory::Create(
    const CdmConfig& cdm_config,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb,
    CdmCreatedCB cdm_created_cb) {
  // WebKit gives every MediaKeys its document's hash salt
  // (MediaKeySystemRequest::allow, from DeviceIdHashSaltStorage per document
  // origin and top-level origin), which randomizes the device identifier in
  // its SPCs. The browser answers with the frame's media device ID salt, the
  // same per-site salt, replaced when site data is cleared. If it doesn't
  // answer, the CDM goes without, as WebKit's options do without the SPI.
  if ((frame_interfaces_ || frame_host_) &&
      parc::fairplay::IsFairPlayKeySystem(cdm_config.key_system)) {
    auto with_salt = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
        base::BindOnce(&FairPlayCdmFactory::CreateWithSalt,
                       weak_factory_.GetWeakPtr(), cdm_config,
                       session_message_cb, session_closed_cb,
                       session_keys_change_cb, session_expiration_update_cb,
                       std::move(cdm_created_cb)),
        std::string());
    if (frame_host_) {
      frame_host_->GetDeviceIdSalt(std::move(with_salt));
    } else {
      frame_interfaces_->GetFairPlayDeviceIdSalt(std::move(with_salt));
    }
    return;
  }
  CreateWithSalt(cdm_config, session_message_cb, session_closed_cb,
                 session_keys_change_cb, session_expiration_update_cb,
                 std::move(cdm_created_cb), std::string());
}

void FairPlayCdmFactory::CreateWithSalt(
    const CdmConfig& cdm_config,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb,
    CdmCreatedCB cdm_created_cb,
    const std::string& device_id_salt) {
  // WebKit gives every CDM instance its document's MediaKeys storage
  // directory (CDM::createInstance); only a configuration that allows
  // persistent state uses it. The browser names (and creates) the frame's.
  // If it doesn't answer, the CDM goes without, as WebKit's does with an
  // empty directory.
  if (cdm_config.allow_persistent_state &&
      (frame_interfaces_ || frame_host_) &&
      parc::fairplay::IsFairPlayKeySystem(cdm_config.key_system)) {
    auto with_storage = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
        base::BindOnce(&FairPlayCdmFactory::CreateWithStorage,
                       weak_factory_.GetWeakPtr(), cdm_config,
                       session_message_cb, session_closed_cb,
                       session_keys_change_cb, session_expiration_update_cb,
                       std::move(cdm_created_cb), device_id_salt),
        base::FilePath());
    if (frame_host_) {
      frame_host_->GetStorageDirectory(std::move(with_storage));
    } else {
      frame_interfaces_->GetFairPlayStorageDirectory(std::move(with_storage));
    }
    return;
  }
  CreateWithStorage(cdm_config, session_message_cb, session_closed_cb,
                    session_keys_change_cb, session_expiration_update_cb,
                    std::move(cdm_created_cb), device_id_salt,
                    base::FilePath());
}

void FairPlayCdmFactory::CreateWithStorage(
    const CdmConfig& cdm_config,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb,
    CdmCreatedCB cdm_created_cb,
    const std::string& device_id_salt,
    const base::FilePath& storage_directory) {
  scoped_refptr<ContentDecryptionModule> cdm;
  CreateCdmStatus status = CreateCdmStatus::kSuccess;
  // The key system comes from the render process; validate it here too.
  if (!parc::fairplay::IsFairPlayKeySystem(cdm_config.key_system)) {
    status = CreateCdmStatus::kUnsupportedKeySystem;
  } else {
    cdm = FairPlayCdmAdapter::Create(
        cdm_config.key_system, cdm_config.allow_persistent_state,
        storage_directory, device_id_salt, session_message_cb,
        session_closed_cb,
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

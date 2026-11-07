#include "third_party/parc_fairplay/chromium/fairplay_cdm_adapter.h"

#include <optional>
#include <utility>

#include "base/check.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "media/base/cdm_key_information.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"
#include "third_party/parc_fairplay/chromium/fairplay_task_runner.h"

namespace media {

namespace {

namespace fp = parc::fairplay;

std::optional<fp::InitDataType> ToFairPlayInitDataType(
    EmeInitDataType init_data_type) {
  switch (init_data_type) {
    case EmeInitDataType::CENC:
      return fp::InitDataType::kCenc;
    case EmeInitDataType::KEYIDS:
      return fp::InitDataType::kKeyIds;
    case EmeInitDataType::SINF:
      return fp::InitDataType::kSinf;
    case EmeInitDataType::SKD:
      return fp::InitDataType::kSkd;
    case EmeInitDataType::WEBM:
    case EmeInitDataType::UNKNOWN:
      return std::nullopt;
  }
  return std::nullopt;
}

CdmPromise::Exception ToCdmException(fp::Exception exception) {
  switch (exception) {
    case fp::Exception::kNone:
    case fp::Exception::kInvalidState:
      return CdmPromise::Exception::INVALID_STATE_ERROR;
    case fp::Exception::kNotSupported:
      return CdmPromise::Exception::NOT_SUPPORTED_ERROR;
    case fp::Exception::kTypeError:
      return CdmPromise::Exception::TYPE_ERROR;
    case fp::Exception::kQuotaExceeded:
      return CdmPromise::Exception::QUOTA_EXCEEDED_ERROR;
  }
  return CdmPromise::Exception::INVALID_STATE_ERROR;
}

CdmMessageType ToCdmMessageType(fp::MessageType type) {
  switch (type) {
    case fp::MessageType::kLicenseRequest:
      return CdmMessageType::LICENSE_REQUEST;
    case fp::MessageType::kLicenseRenewal:
      return CdmMessageType::LICENSE_RENEWAL;
    case fp::MessageType::kLicenseRelease:
      return CdmMessageType::LICENSE_RELEASE;
  }
  return CdmMessageType::LICENSE_REQUEST;
}

// The session types WebKit's FairPlay CDM serves on macOS; persistent-license
// is iOS-only there.
std::optional<fp::SessionType> ToFairPlaySessionType(
    CdmSessionType session_type) {
  switch (session_type) {
    case CdmSessionType::kTemporary:
      return fp::SessionType::kTemporary;
    case CdmSessionType::kPersistentUsageRecord:
      return fp::SessionType::kPersistentUsageRecord;
    case CdmSessionType::kPersistentLicense:
      return std::nullopt;
  }
  return std::nullopt;
}

CdmKeyInformation::KeyStatus ToCdmKeyStatus(fp::KeyStatus status) {
  switch (status) {
    case fp::KeyStatus::kUsable:
      return CdmKeyInformation::USABLE;
    case fp::KeyStatus::kInternalError:
      return CdmKeyInformation::INTERNAL_ERROR;
    case fp::KeyStatus::kExpired:
      return CdmKeyInformation::EXPIRED;
    case fp::KeyStatus::kOutputRestricted:
      return CdmKeyInformation::OUTPUT_RESTRICTED;
    case fp::KeyStatus::kOutputDownscaled:
      return CdmKeyInformation::OUTPUT_DOWNSCALED;
    case fp::KeyStatus::kStatusPending:
      return CdmKeyInformation::KEY_STATUS_PENDING;
    case fp::KeyStatus::kReleased:
      return CdmKeyInformation::RELEASED;
  }
  return CdmKeyInformation::INTERNAL_ERROR;
}

}  // namespace

// static
scoped_refptr<FairPlayCdmAdapter> FairPlayCdmAdapter::Create(
    const std::string& key_system,
    bool allow_persistent_state,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb) {
  if (!fp::IsFairPlayKeySystem(key_system) ||
      !fp::FairPlayCdm::IsKeySystemSupported(key_system)) {
    DVLOG(1) << __func__ << ": not a FairPlay key system: " << key_system;
    return nullptr;
  }
  if (!fp::FairPlayCdm::IsSupported()) {
    LOG(ERROR) << "FairPlay Streaming is unavailable on this system";
    return nullptr;
  }
  return base::MakeRefCounted<FairPlayCdmAdapter>(
      allow_persistent_state, session_message_cb, session_closed_cb,
      session_keys_change_cb, session_expiration_update_cb);
}

FairPlayCdmAdapter::FairPlayCdmAdapter(
    bool allow_persistent_state,
    const SessionMessageCB& session_message_cb,
    const SessionClosedCB& session_closed_cb,
    const SessionKeysChangeCB& session_keys_change_cb,
    const SessionExpirationUpdateCB& session_expiration_update_cb)
    : task_runner_(base::SequencedTaskRunner::GetCurrentDefault()),
      session_message_cb_(session_message_cb),
      session_closed_cb_(session_closed_cb),
      session_keys_change_cb_(session_keys_change_cb),
      session_expiration_update_cb_(session_expiration_update_cb),
      cdm_(std::make_unique<fp::FairPlayCdm>(this,
                                             fp::PostTaskTo(task_runner_))) {
  DCHECK(session_message_cb_);
  DCHECK(session_closed_cb_);
  DCHECK(session_keys_change_cb_);
  DCHECK(session_expiration_update_cb_);
  cdm_->SetPersistentStateAllowed(allow_persistent_state);
}

FairPlayCdmAdapter::~FairPlayCdmAdapter() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The core rejects nothing on destruction and posts nothing afterwards
  // (its pending callbacks hold weak references), so drop it before
  // rejecting what is still outstanding.
  weak_factory_.InvalidateWeakPtrs();
  cdm_.reset();
  promises_.Clear(CdmPromiseAdapter::ClearReason::kDestruction);
}

void FairPlayCdmAdapter::SetServerCertificate(
    const std::vector<uint8_t>& certificate,
    std::unique_ptr<SimpleCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const uint32_t promise_id =
      promises_.SavePromise(std::move(promise), "SetServerCertificate");
  base::WeakPtr<FairPlayCdmAdapter> weak = weak_factory_.GetWeakPtr();
  cdm_->SetServerCertificate(
      certificate, [weak, promise_id](const fp::Result& result) {
        if (weak) {
          weak->OnPromiseResult(promise_id, result);
        }
      });
}

void FairPlayCdmAdapter::CreateSessionAndGenerateRequest(
    CdmSessionType session_type,
    EmeInitDataType init_data_type,
    const std::vector<uint8_t>& init_data,
    std::unique_ptr<NewSessionCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const std::optional<fp::SessionType> fairplay_session_type =
      ToFairPlaySessionType(session_type);
  if (!fairplay_session_type) {
    promise->reject(CdmPromise::Exception::NOT_SUPPORTED_ERROR, 0,
                    "FairPlay has no persistent-license sessions on macOS");
    return;
  }
  const std::optional<fp::InitDataType> type =
      ToFairPlayInitDataType(init_data_type);
  if (!type) {
    promise->reject(CdmPromise::Exception::NOT_SUPPORTED_ERROR, 0,
                    "Init data type not supported by FairPlay");
    return;
  }
  const uint32_t promise_id =
      promises_.SavePromise(std::move(promise), "CreateSession");
  base::WeakPtr<FairPlayCdmAdapter> weak = weak_factory_.GetWeakPtr();
  cdm_->CreateSessionAndGenerateRequest(
      *fairplay_session_type, *type, init_data,
      [weak, promise_id](const fp::Result& result,
                         const std::string& session_id) {
        if (weak) {
          weak->OnNewSessionResult(promise_id, result, session_id);
        }
      });
}

void FairPlayCdmAdapter::LoadSession(
    CdmSessionType session_type,
    const std::string& session_id,
    std::unique_ptr<NewSessionCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  promise->reject(CdmPromise::Exception::NOT_SUPPORTED_ERROR, 0,
                  "FairPlay has no persistent sessions to load");
}

void FairPlayCdmAdapter::UpdateSession(
    const std::string& session_id,
    const std::vector<uint8_t>& response,
    std::unique_ptr<SimpleCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const uint32_t promise_id =
      promises_.SavePromise(std::move(promise), "UpdateSession");
  base::WeakPtr<FairPlayCdmAdapter> weak = weak_factory_.GetWeakPtr();
  cdm_->UpdateSession(session_id, response,
                      [weak, promise_id](const fp::Result& result) {
                        if (weak) {
                          weak->OnPromiseResult(promise_id, result);
                        }
                      });
}

void FairPlayCdmAdapter::CloseSession(
    const std::string& session_id,
    std::unique_ptr<SimpleCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const uint32_t promise_id =
      promises_.SavePromise(std::move(promise), "CloseSession");
  base::WeakPtr<FairPlayCdmAdapter> weak = weak_factory_.GetWeakPtr();
  scoped_refptr<base::SequencedTaskRunner> task_runner = task_runner_;
  // Blink drops the session when the close promise resolves, so the closed
  // event must reach it first. The core posts the promise result ahead of
  // OnSessionClosed; one more hop puts the resolution after the event.
  cdm_->CloseSession(session_id, [weak, task_runner,
                                  promise_id](const fp::Result& result) {
    task_runner->PostTask(
        FROM_HERE, base::BindOnce(&FairPlayCdmAdapter::OnPromiseResult, weak,
                                  promise_id, result));
  });
}

void FairPlayCdmAdapter::RemoveSession(
    const std::string& session_id,
    std::unique_ptr<SimpleCdmPromise> promise) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const uint32_t promise_id =
      promises_.SavePromise(std::move(promise), "RemoveSession");
  base::WeakPtr<FairPlayCdmAdapter> weak = weak_factory_.GetWeakPtr();
  cdm_->RemoveSession(session_id, [weak, promise_id](const fp::Result& result) {
    if (weak) {
      weak->OnPromiseResult(promise_id, result);
    }
  });
}

CdmContext* FairPlayCdmAdapter::GetCdmContext() {
  return this;
}

void FairPlayCdmAdapter::DeleteOnCorrectThread() const {
  if (!task_runner_->RunsTasksInCurrentSequence()) {
    task_runner_->DeleteSoon(FROM_HERE, this);
    return;
  }
  delete this;
}

std::unique_ptr<CallbackRegistration> FairPlayCdmAdapter::RegisterEventCB(
    EventCB event_cb) {
  return event_callbacks_.Register(std::move(event_cb));
}

bool FairPlayCdmAdapter::RequiresFairPlayRenderer() {
  return true;
}

parc::fairplay::FairPlayCdm* FairPlayCdmAdapter::GetFairPlayCdm() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  return cdm_.get();
}

void FairPlayCdmAdapter::ParcHasSessionForInitData(
    EmeInitDataType init_data_type,
    const std::vector<uint8_t>& init_data,
    ParcHasSessionForInitDataCB done) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  const std::optional<fp::InitDataType> type =
      ToFairPlayInitDataType(init_data_type);
  std::move(done).Run(type && cdm_->HasSessionForInitData(*type, init_data));
}

void FairPlayCdmAdapter::OnSessionMessage(const std::string& session_id,
                                          fp::MessageType type,
                                          const std::vector<uint8_t>& message) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  session_message_cb_.Run(session_id, ToCdmMessageType(type), message);
}

void FairPlayCdmAdapter::OnSessionKeysChange(
    const std::string& session_id,
    bool has_additional_usable_key,
    const std::vector<fp::KeyInfo>& keys) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  CdmKeysInfo keys_info;
  keys_info.reserve(keys.size());
  for (const fp::KeyInfo& key : keys) {
    keys_info.push_back(std::make_unique<CdmKeyInformation>(
        base::span<const uint8_t>(key.key_id), ToCdmKeyStatus(key.status),
        key.system_code));
  }
  session_keys_change_cb_.Run(session_id, has_additional_usable_key,
                              std::move(keys_info));
  if (has_additional_usable_key) {
    event_callbacks_.Notify(Event::kHasAdditionalUsableKey);
  }
}

void FairPlayCdmAdapter::OnSessionClosed(const std::string& session_id) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  session_closed_cb_.Run(session_id, CdmSessionClosedReason::kClose);
}

void FairPlayCdmAdapter::OnPromiseResult(uint32_t promise_id,
                                         const fp::Result& result) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (result.ok()) {
    promises_.ResolvePromise(promise_id);
    return;
  }
  promises_.RejectPromise(promise_id, ToCdmException(result.exception),
                          result.system_code, result.message);
}

void FairPlayCdmAdapter::OnNewSessionResult(uint32_t promise_id,
                                            const fp::Result& result,
                                            const std::string& session_id) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (result.ok()) {
    promises_.ResolvePromise(promise_id, session_id);
    return;
  }
  promises_.RejectPromise(promise_id, ToCdmException(result.exception),
                          result.system_code, result.message);
}

}  // namespace media

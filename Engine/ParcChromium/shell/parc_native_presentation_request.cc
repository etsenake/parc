// Copyright 2020 The Chromium Authors

#include <utility>

#include "chrome/browser/ui/global_media_controls/presentation_request_notification_producer.h"
#include "base/functional/bind.h"
#include "components/global_media_controls/public/supplemental_device_picker_producer.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/media_router/browser/presentation/web_contents_presentation_manager.h"

void PresentationRequestNotificationProducer::ArmNativeRequest(
    base::UnguessableToken token, base::OnceClosure on_disconnect,
    global_media_controls::SupplementalDevicePickerProducer* local_provider) {
  native_request_token_ = token;
  native_disconnect_ = std::move(on_disconnect);

  observer_receiver_.reset();
  local_provider->AddObserver(observer_receiver_.BindNewPipeAndPassRemote());
  if (presentation_manager_)
    presentation_manager_->RemoveObserver(this);
  presentation_manager_ = nullptr;
  is_dialog_open_ = false;
}

void PresentationRequestNotificationProducer::DisarmNativeRequest(
    base::UnguessableToken token) {
  if (native_request_token_ && *native_request_token_ == token) {
    native_request_token_.reset();
    native_disconnect_.Reset();
  }
}

bool PresentationRequestNotificationProducer::WaitForNativePreparation(
    base::UnguessableToken token, base::OnceClosure completion) {
  if (!native_request_token_ || *native_request_token_ != token ||
      !provider_.is_bound())
    return false;

  provider_.QueryVersion(base::BindOnce(
      [](base::WeakPtr<PresentationRequestNotificationProducer> self,
         base::UnguessableToken token, base::OnceClosure completion, uint32_t) {
        if (self && self->native_request_token_ &&
            *self->native_request_token_ == token)
          std::move(completion).Run();
      }, weak_factory_.GetWeakPtr(), token, std::move(completion)));
  return true;
}

void PresentationRequestNotificationProducer::OnNativeUIOpened(
    base::UnguessableToken token) {
  if (native_request_token_ && *native_request_token_ == token)
    is_dialog_open_ = true;
}

void PresentationRequestNotificationProducer::OnNativeUIClosed(
    base::UnguessableToken token) {
  if (!native_request_token_ || *native_request_token_ != token)
    return;
  is_dialog_open_ = false;
  auto context = TakeNativeContext(token);
  if (context)
    context->InvokeErrorCallback(blink::mojom::PresentationError(
        blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
        "Dialog closed."));
}

void PresentationRequestNotificationProducer::OnNativePickerDismissed(
    base::UnguessableToken token) {
  if (!native_request_token_ || *native_request_token_ != token)
    return;
  auto context = TakeNativeContext(token);
  if (context)
    context->InvokeErrorCallback(blink::mojom::PresentationError(
        blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
        "Dialog closed."));
}

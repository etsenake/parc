// Copyright 2023 The Chromium Authors

#include <utility>

#include "components/global_media_controls/public/supplemental_device_picker_producer.h"

namespace global_media_controls {

void SupplementalDevicePickerProducer::WatchPendingNativeLifecycle(
    base::UnguessableToken token, base::OnceClosure on_other_dialog) {
  watched_native_token_ = token;
  on_other_dialog_ = std::move(on_other_dialog);
}

void SupplementalDevicePickerProducer::PrepareNativeLifecycle(
    base::UnguessableToken token, NativeLifecycleCallback callback) {
  if (watched_native_token_ == token) {
    watched_native_token_.reset();
    on_other_dialog_.Reset();
  }
  pending_native_lifecycle_.emplace(NativeLifecycle{token, std::move(callback)});
}

void SupplementalDevicePickerProducer::ClearNativeLifecycle(
    base::UnguessableToken token) {
  if (watched_native_token_ == token) {
    watched_native_token_.reset();
    on_other_dialog_.Reset();
  }
  if (pending_native_lifecycle_ && pending_native_lifecycle_->token == token)
    pending_native_lifecycle_.reset();

}

bool SupplementalDevicePickerProducer::HasPendingNativeLifecycle(
    base::UnguessableToken token) const {
  return pending_native_lifecycle_ && pending_native_lifecycle_->token == token;
}

}

// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_CAPTURE_PICKER_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_CAPTURE_PICKER_H_

#include <memory>
#include "base/functional/callback.h"
#include "chrome/browser/media/webrtc/desktop_media_picker.h"

namespace parc {
// Installed by the native application; ordinary Chrome keeps its own picker.
// The predicate checks the requesting Profile's explicit native route, not the
// currently focused Browser. A detached native page therefore fails closed.
void SetNativeCapturePickerRoute(
    base::RepeatingCallback<bool(content::WebContents&)> route);
std::unique_ptr<DesktopMediaPicker> WrapNativeCapturePicker(
    std::unique_ptr<DesktopMediaPicker> fallback,
    const content::MediaStreamRequest* request);
// Called before a native page changes parent or its host becomes unselected.
void CancelNativeCapturePicker(content::WebContents& contents);
}  // namespace parc
#endif

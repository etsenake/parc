// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_INTENT_PICKER_API_H_
#define PARC_NATIVE_INTENT_PICKER_API_H_
#include "components/apps/link_capturing/intent_picker_info.h"
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace parc {
// Returns false without consuming inputs for a non-native Browser. Native
// requests always consume the callback, including a truthful failure if the
// exact originating page has become inactive/detached. Implemented in the host.
bool MaybeShowNativeIntentPickerForPage(
    BrowserWindowInterface&, content::WebContents&,
    std::vector<apps::IntentPickerAppInfo>& apps, bool show_stay,
    bool show_remember, IntentPickerResponse& callback);
}  // namespace parc
#endif

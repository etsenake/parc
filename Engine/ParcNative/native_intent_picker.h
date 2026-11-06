// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_INTENT_PICKER_H_
#define PARC_NATIVE_INTENT_PICKER_H_
#import <AppKit/AppKit.h>
#include <optional>
#include "base/functional/callback.h"
#include "components/apps/link_capturing/intent_picker_info.h"
#include "url/origin.h"
class BrowserWindowInterface;
namespace content { class WebContents; }
namespace parc {
// The requesting WebContents owns the chooser. Chromium keeps discovery,
// eligibility, persistence and actual launch; this adapter only returns a real
// user decision using its original offered identity and flags.
void ShowNativeIntentPicker(
    BrowserWindowInterface&, content::WebContents&, NSWindow*, NSView*,
    base::RepeatingCallback<bool()> valid,
    std::vector<apps::IntentPickerAppInfo> apps, bool show_stay,
    bool show_remember, apps::IntentPickerBubbleType,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback);
void CloseNativeIntentPicker(content::WebContents&);
}  // namespace parc
#endif

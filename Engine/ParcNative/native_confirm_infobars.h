// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_CONFIRM_INFOBARS_H_
#define PARC_NATIVE_NATIVE_CONFIRM_INFOBARS_H_
namespace content { class WebContents; }
namespace parc {
// Call after registering the real native page. The existing ContentInfoBarManager
// remains the only owner of delegates, priorities and expiration decisions.
void AttachNativeConfirmInfoBars(content::WebContents& contents);
bool FocusNativeConfirmInfoBar(content::WebContents* contents);
}  // namespace parc
#endif

// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_TAB_SHARING_H_
#define PARC_NATIVE_NATIVE_TAB_SHARING_H_
#include <memory>
#include <string>

#include "chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.h"
class Profile;
namespace parc {
// Chromium's tab-sharing hooks. Native pages get Parc's bar and page info;
// any other page Chromium's own. The session profile is a native capturer's
// own, else Chromium's last-used one.
std::unique_ptr<infobars::InfoBar> CreateNativeTabSharingInfoBar(
    content::WebContents* contents,
    std::unique_ptr<TabSharingInfoBarDelegate> delegate,
    content::GlobalRenderFrameHostId shared,
    content::GlobalRenderFrameHostId capturer,
    const std::u16string& shared_name,
    const std::u16string& capturer_name,
    TabSharingInfoBarDelegate::TabRole role,
    TabSharingInfoBarDelegate::TabShareType type,
    base::WeakPtr<ScreensharingControlsHistogramLogger> logger);
Profile* TabSharingCapturerProfile(content::GlobalRenderFrameHostId capturer);
void ShowTabSharingPageInfo(content::WebContents* contents);
bool IsNativeTabSharingInfoBar(infobars::InfoBar* bar);
// The real delegate's Share This Tab Instead button, offered and enabled.
bool NativeTabSharingCanShareInstead(infobars::InfoBar* bar);
// Runs that genuine action (with its histogram) when it is still offered.
bool ShareNativeTabInstead(infobars::InfoBar* bar);
}  // namespace parc
#endif

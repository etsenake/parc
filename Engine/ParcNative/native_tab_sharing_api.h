// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_TAB_SHARING_API_H_
#define PARC_NATIVE_NATIVE_TAB_SHARING_API_H_
#include <memory>
#include <string>
#include "chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.h"
class Profile;
namespace parc {
// Null leaves delegate untouched for the existing non-native presenter.
std::unique_ptr<infobars::InfoBar> CreateNativeTabSharingInfoBar(
    content::WebContents* contents, std::unique_ptr<TabSharingInfoBarDelegate>& delegate,
    content::GlobalRenderFrameHostId shared, content::GlobalRenderFrameHostId capturer,
    const std::u16string& shared_name, const std::u16string& capturer_name,
    TabSharingInfoBarDelegate::TabRole role, TabSharingInfoBarDelegate::TabShareType type,
    base::WeakPtr<ScreensharingControlsHistogramLogger> logger);
// Returns null for non-native capturers. Native profiles come from the actual
// capturer; never from another active or most-recently-used browser profile.
Profile* NativeTabSharingProfile(content::GlobalRenderFrameHostId capturer);
bool IsNativeTabSharingPage(content::WebContents* contents);
}  // namespace parc
#endif

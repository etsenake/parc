// Copyright 2026 Parc contributors.
#include "native_tab_sharing.h"
#include "native_tab_sharing_api.h"

#include <map>
#include <utility>
#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/views/screen_sharing_util.h"
#include "components/infobars/core/infobar.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_page.h"
#include "native_host_route.h"

namespace parc {
namespace {
class NativeSharingBar;
auto& NativeBars() {
  static base::NoDestructor<std::map<infobars::InfoBar*, NativeSharingBar*>> bars;
  return *bars;
}
using Delegate = TabSharingInfoBarDelegate;
using Interaction = GetDisplayMediaUserInteractionWithControls;
content::WebContents* Contents(content::GlobalRenderFrameHostId id) {
  auto* frame = content::RenderFrameHost::FromID(id);
  return frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
}

// The genuine TabSharingInfoBarDelegate stays owned by its page's real
//
// Tab Instead (WEB16, docs/web-interactions.md), so that is the one action.
class NativeSharingBar final : public infobars::InfoBar {
 public:
  NativeSharingBar(std::unique_ptr<Delegate> delegate,
      base::WeakPtr<ScreensharingControlsHistogramLogger> logger)
      : InfoBar(std::move(delegate)), logger_(logger) {
    NativeBars().emplace(this, this);
  }
  ~NativeSharingBar() override { NativeBars().erase(this); }
  Delegate* model() { return static_cast<Delegate*>(delegate()); }
  bool CanShareInstead() {
    return owner() && (model()->GetButtons() & Delegate::kShareThisTabInstead) &&
        model()->IsButtonEnabled(Delegate::kShareThisTabInstead);
  }
  bool ShareInstead() {
    if (!CanShareInstead()) return false;
    if (logger_) logger_->Log(Interaction::kShareThisTabInsteadClicked);
    model()->ShareThisTabInstead();
    return true;
  }
 private:
  const base::WeakPtr<ScreensharingControlsHistogramLogger> logger_;
};
NativeSharingBar* Model(infobars::InfoBar* bar) {
  auto found = NativeBars().find(bar);
  return found == NativeBars().end() ? nullptr : found->second;
}
}  // namespace

bool IsNativeTabSharingPage(content::WebContents* contents) {
  PCNativePage* page = ExistingNativePage(contents);
  return page && !page.closed;
}
Profile* NativeTabSharingProfile(content::GlobalRenderFrameHostId capturer) {
  auto* contents = Contents(capturer);
  if (!contents) return nullptr;
  auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  // Extension/background capturers can have no native page. Their exact
  // registered profile still owns the native capture session and its banners.
  if (!GetNativeRoute(*profile)) return nullptr;
  return profile->IsGuestSession() ? profile : profile->GetOriginalProfile();
}
std::unique_ptr<infobars::InfoBar> CreateNativeTabSharingInfoBar(
    content::WebContents* contents, std::unique_ptr<Delegate>& delegate,
    content::GlobalRenderFrameHostId, content::GlobalRenderFrameHostId,
    const std::u16string&, const std::u16string&,
    Delegate::TabRole, Delegate::TabShareType,
    base::WeakPtr<ScreensharingControlsHistogramLogger> logger) {
  if (!IsNativeTabSharingPage(contents)) return nullptr;
  return std::make_unique<NativeSharingBar>(std::move(delegate), logger);
}
bool IsNativeTabSharingInfoBar(infobars::InfoBar* bar) { return Model(bar); }
bool NativeTabSharingCanShareInstead(infobars::InfoBar* bar) {
  auto* model = Model(bar); return model && model->CanShareInstead();
}
bool ShareNativeTabInstead(infobars::InfoBar* bar) {
  auto* model = Model(bar); return model && model->ShareInstead();
}
}  // namespace parc

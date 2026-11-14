// Copyright 2026 Parc contributors.
#include "native_confirm_infobars.h"
#include "native_tab_sharing.h"

#import <AppKit/AppKit.h>
#include "base/scoped_observation.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_manager.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "native_appkit_page.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
using InfoBar = infobars::InfoBar;
using Manager = infobars::InfoBarManager;

class NativeInfoBars final : public content::WebContentsObserver,
                            public content::WebContentsUserData<NativeInfoBars>,
                            public Manager::Observer {
 public:
  ~NativeInfoBars() override = default;
  void Start() {
    auto* manager = infobars::ContentInfoBarManager::FromWebContents(web_contents());
    if (manager && !observation_.IsObserving()) observation_.Observe(manager);
  }
  // This page's own tab-sharing bar while it offers Share This Tab Instead.
  InfoBar* ShareableBar() const {
    auto* contents = web_contents();
    auto* manager = contents && observation_.IsObserving()
        ? infobars::ContentInfoBarManager::FromWebContents(contents) : nullptr;
    PCNativePage* page = ExistingNativePage(contents);
    NSWindow* window = page.nativeView.window;
    if (!manager || !page || page.closed || contents->IsBeingDestroyed() || !window ||
        window.attachedSheet || PCNativeWindowHasSecurityReservation(window)) return nullptr;
    for (InfoBar* bar : manager->infobars()) {
      if (bar->owner() == manager && NativeTabSharingCanShareInstead(bar)) return bar;
    }
    return nullptr;
  }
  void OnInfoBarAdded(InfoBar* bar) override { Changed(bar); }
  void OnInfoBarRemoved(InfoBar* bar, bool) override { Changed(bar); }
  void OnInfoBarReplaced(InfoBar* old_bar, InfoBar* new_bar) override {
    if (IsNativeTabSharingInfoBar(old_bar) || IsNativeTabSharingInfoBar(new_bar))
      NotifyNativePageChanged(web_contents());
  }
  void OnManagerWillBeDestroyed(Manager*) override { observation_.Reset(); }
  void WebContentsDestroyed() override { observation_.Reset(); }

 private:
  friend class content::WebContentsUserData<NativeInfoBars>;
  explicit NativeInfoBars(content::WebContents* contents)
      : WebContentsObserver(contents), content::WebContentsUserData<NativeInfoBars>(*contents) {}
  void Changed(InfoBar* bar) {
    if (IsNativeTabSharingInfoBar(bar)) NotifyNativePageChanged(web_contents());
  }
  base::ScopedObservation<Manager, Manager::Observer> observation_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeInfoBars);
}  // namespace

void AttachNativeConfirmInfoBars(content::WebContents& contents) {
  NativeInfoBars::CreateForWebContents(&contents);
  NativeInfoBars::FromWebContents(&contents)->Start();
}
bool FocusNativeConfirmInfoBar(content::WebContents*) {
  // No infobar is presented, so the pane cycle has none to focus.
  return false;
}
}  // namespace parc

@implementation PCNativePage (TabSharing)
- (BOOL)canShareThisTabInstead {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents && !self.closed ? parc::NativeInfoBars::FromWebContents(contents) : nullptr;
  return state && state->ShareableBar();
}
- (BOOL)shareThisTabInstead {
  auto* contents = parc::ContentsForNativePage(self);
  auto* state = contents && !self.closed ? parc::NativeInfoBars::FromWebContents(contents) : nullptr;
  auto* bar = state ? state->ShareableBar() : nullptr;
  return bar && parc::ShareNativeTabInstead(bar);
}
@end

// Copyright 2026 Parc contributors.
#include "native_confirm_infobars.h"
#include "native_tab_sharing.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>
#include <string>

#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_delegate.h"
#include "components/infobars/core/infobar_manager.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "native_appkit_page.h"
#import "window_security_reservation.h"

@interface PCNativeDebuggerWarning ()
- (instancetype)initWithMessage:(NSString*)message cancelTitle:(NSString*)cancelTitle;
@end

@implementation PCNativeDebuggerWarning
@synthesize message = _message;
@synthesize cancelTitle = _cancelTitle;
- (instancetype)initWithMessage:(NSString*)message cancelTitle:(NSString*)cancelTitle {
  if ((self = [super init])) {
    _message = [message copy];
    _cancelTitle = [cancelTitle copy];
  }
  return self;
}
@end

namespace parc {
namespace {
using InfoBar = infobars::InfoBar;
using Manager = infobars::InfoBarManager;

ConfirmInfoBarDelegate* DebuggerWarningDelegate(InfoBar* bar) {
  infobars::InfoBarDelegate* delegate = bar ? bar->delegate() : nullptr;
  if (!delegate || delegate->GetIdentifier() !=
                       infobars::InfoBarDelegate::EXTENSION_DEV_TOOLS_INFOBAR_DELEGATE) {
    return nullptr;
  }
  ConfirmInfoBarDelegate* confirm = delegate->AsConfirmInfoBarDelegate();
  return confirm && (confirm->GetButtons() & ConfirmInfoBarDelegate::BUTTON_OK) ? confirm : nullptr;
}

class NativeInfoBars final : public content::WebContentsObserver,
                            public content::WebContentsUserData<NativeInfoBars>,
                            public Manager::Observer {
 public:
  ~NativeInfoBars() override = default;
  void Start() {
    auto* manager = infobars::ContentInfoBarManager::FromWebContents(web_contents());
    if (manager && !observation_.IsObserving()) observation_.Observe(manager);
  }
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
  NSArray<PCNativeDebuggerWarning*>* DebuggerWarnings() {
    Start();
    NSMutableArray<PCNativeDebuggerWarning*>* warnings = [NSMutableArray array];
    Manager* manager = LiveManager();
    if (!manager) return warnings;
    for (InfoBar* bar : manager->infobars()) {
      if (bar->owner() != manager) continue;
      if (PCNativeDebuggerWarning* warning = WarningFor(bar)) [warnings addObject:warning];
    }
    return warnings;
  }
  bool CancelDebuggerWarning(PCNativeDebuggerWarning* warning) {
    InfoBar* bar = ActionableBar(warning);
    ConfirmInfoBarDelegate* delegate = DebuggerWarningDelegate(bar);
    if (!delegate) return false;
    base::WeakPtr<NativeInfoBars> alive = weak_factory_.GetWeakPtr();
    if (!delegate->Accept() || !alive) return true;
    Manager* manager = LiveManager();
    auto found = warnings_.find(bar);
    if (manager && found != warnings_.end() && found->second == warning &&
        std::ranges::find(manager->infobars(), bar) != manager->infobars().end()) {
      bar->RemoveSelf();
    }
    return true;
  }
  bool DismissDebuggerWarning(PCNativeDebuggerWarning* warning) {
    InfoBar* bar = ActionableBar(warning);
    ConfirmInfoBarDelegate* delegate = DebuggerWarningDelegate(bar);
    if (!delegate) return false;
    base::WeakPtr<NativeInfoBars> alive = weak_factory_.GetWeakPtr();
    delegate->InfoBarDismissed();
    if (!alive) return true;
    Manager* manager = LiveManager();
    auto found = warnings_.find(bar);
    if (manager && found != warnings_.end() && found->second == warning &&
        std::ranges::find(manager->infobars(), bar) != manager->infobars().end()) {
      bar->RemoveSelf();
    }
    return true;
  }
  void OnInfoBarAdded(InfoBar* bar) override {
    Changed(bar);
    if (DebuggerWarningDelegate(bar) && WarningFor(bar)) PublishDebuggerWarnings();
  }
  void OnInfoBarRemoved(InfoBar* bar, bool) override {
    Changed(bar);
    if (Forget(bar)) PublishDebuggerWarnings();
  }
  void OnInfoBarReplaced(InfoBar* old_bar, InfoBar* new_bar) override {
    if (IsNativeTabSharingInfoBar(old_bar) || IsNativeTabSharingInfoBar(new_bar))
      NotifyNativePageChanged(web_contents());
    const bool forgot = Forget(old_bar);
    const bool added = DebuggerWarningDelegate(new_bar) && WarningFor(new_bar);
    if (forgot || added) PublishDebuggerWarnings();
  }
  void OnManagerWillBeDestroyed(Manager*) override { Reset(); }
  void WebContentsDestroyed() override { Reset(); }

 private:
  friend class content::WebContentsUserData<NativeInfoBars>;
  explicit NativeInfoBars(content::WebContents* contents)
      : WebContentsObserver(contents), content::WebContentsUserData<NativeInfoBars>(*contents) {}
  void Changed(InfoBar* bar) {
    if (IsNativeTabSharingInfoBar(bar)) NotifyNativePageChanged(web_contents());
  }
  void Reset() {
    observation_.Reset();
    warnings_.clear();
  }
  Manager* LiveManager() const {
    content::WebContents* contents = web_contents();
    if (!contents || contents->IsBeingDestroyed() || !observation_.IsObserving()) return nullptr;
    PCNativePage* page = ExistingNativePage(contents);
    if (!page || page.closed) return nullptr;
    return infobars::ContentInfoBarManager::FromWebContents(contents);
  }
  PCNativeDebuggerWarning* WarningFor(InfoBar* bar) {
    auto found = warnings_.find(bar);
    if (found != warnings_.end()) return found->second;
    ConfirmInfoBarDelegate* delegate = DebuggerWarningDelegate(bar);
    if (!delegate) return nil;
    const std::u16string message = delegate->GetMessageText();
    const std::u16string cancel = delegate->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_OK);
    if (message.empty() || cancel.empty()) return nil;
    PCNativeDebuggerWarning* warning =
        [[PCNativeDebuggerWarning alloc] initWithMessage:base::SysUTF16ToNSString(message)
                                             cancelTitle:base::SysUTF16ToNSString(cancel)];
    warnings_[bar] = warning;
    return warning;
  }
  InfoBar* ActionableBar(PCNativeDebuggerWarning* warning) const {
    Manager* manager = LiveManager();
    PCNativePage* page = ExistingNativePage(web_contents());
    NSWindow* window = page.nativeView.window;
    if (!warning || !manager || !window || window.attachedSheet ||
        PCNativeWindowHasSecurityReservation(window)) return nullptr;
    for (InfoBar* bar : manager->infobars()) {
      auto found = warnings_.find(bar);
      if (bar->owner() == manager && found != warnings_.end() && found->second == warning &&
          DebuggerWarningDelegate(bar)) return bar;
    }
    return nullptr;
  }
  bool Forget(InfoBar* bar) {
    return warnings_.erase(bar) > 0;
  }
  void PublishDebuggerWarnings() {
    if (publish_pending_) return;
    publish_pending_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&NativeInfoBars::PostDebuggerWarnings, weak_factory_.GetWeakPtr()));
  }
  void PostDebuggerWarnings() {
    publish_pending_ = false;
    content::WebContents* contents = web_contents();
    PCNativePage* page = ExistingNativePage(contents);
    if (!contents || contents->IsBeingDestroyed() || !page || page.closed) return;
    [NSNotificationCenter.defaultCenter
        postNotificationName:PCNativePageDebuggerWarningsDidChangeNotification
                      object:page];
  }
  base::ScopedObservation<Manager, Manager::Observer> observation_{this};
  std::map<InfoBar*, PCNativeDebuggerWarning*> warnings_;
  bool publish_pending_ = false;
  base::WeakPtrFactory<NativeInfoBars> weak_factory_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativeInfoBars);

NativeInfoBars* InfoBarsForPage(PCNativePage* page) {
  content::WebContents* contents = ContentsForNativePage(page);
  return contents && !page.closed ? NativeInfoBars::FromWebContents(contents) : nullptr;
}
}

void AttachNativeConfirmInfoBars(content::WebContents& contents) {
  NativeInfoBars::CreateForWebContents(&contents);
  NativeInfoBars::FromWebContents(&contents)->Start();
}
bool FocusNativeConfirmInfoBar(content::WebContents*) {
  return false;
}
}

@implementation PCNativePage (TabSharing)
- (BOOL)canShareThisTabInstead {
  auto* state = parc::InfoBarsForPage(self);
  return state && state->ShareableBar();
}
- (BOOL)shareThisTabInstead {
  auto* state = parc::InfoBarsForPage(self);
  auto* bar = state ? state->ShareableBar() : nullptr;
  return bar && parc::ShareNativeTabInstead(bar);
}
@end

@implementation PCNativePage (DebuggerWarning)
- (NSArray<PCNativeDebuggerWarning*>*)debuggerWarnings {
  auto* state = parc::InfoBarsForPage(self);
  return state ? state->DebuggerWarnings() : @[];
}
- (BOOL)cancelDebuggerWarning:(PCNativeDebuggerWarning*)warning {
  auto* state = parc::InfoBarsForPage(self);
  return state && state->CancelDebuggerWarning(warning);
}
- (BOOL)dismissDebuggerWarning:(PCNativeDebuggerWarning*)warning {
  auto* state = parc::InfoBarsForPage(self);
  return state && state->DismissDebuggerWarning(warning);
}
@end

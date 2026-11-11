// Copyright 2026 Parc contributors.
//
// restores the same native page. Chromium156's SadTabHelper owns our matching
//
#include "sad_tab.h"

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/sad_tab.h"
#include "chrome/browser/ui/sad_tab_controller.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_page.h"
#include "ui/base/base_window.h"
#include "ui/base/l10n/l10n_util.h"

@interface PCNativeRendererCrash ()
- (instancetype)initWithSadTab:(SadTab&)tab
                        status:(base::TerminationStatus)status;
@end
@implementation PCNativeRendererCrash
@synthesize terminationStatus = _terminationStatus;
@synthesize errorCode = _errorCode;
@synthesize title = _title;
@synthesize message = _message;
@synthesize actionTitle = _actionTitle;
- (instancetype)initWithSadTab:(SadTab&)tab
                        status:(base::TerminationStatus)status {
  if ((self = [super init])) {
    _terminationStatus = status;
    _errorCode = tab.GetCrashedErrorCode();
    _title =
        base::SysUTF16ToNSString(l10n_util::GetStringUTF16(tab.GetTitle()));
    NSMutableString* message = [base::SysUTF16ToNSString(
        l10n_util::GetStringUTF16(tab.GetInfoMessage())) mutableCopy];
    // Keep the genuine repeat-crash/profile/OOM policy. The previous snapshot
    // dropped its recovery suggestions even though the controller supplied them.
    for (int resource : tab.GetSubMessages()) {
      [message appendFormat:@"\n• %@", base::SysUTF16ToNSString(
          l10n_util::GetStringUTF16(resource))];
    }
    _message = [message copy];
    _actionTitle = base::SysUTF16ToNSString(
        l10n_util::GetStringUTF16(tab.GetButtonTitle()));
  }
  return self;
}
@end

namespace parc {
namespace {
const char kNativeSadTabStateKey = 0;
class NativeSadTab;
struct State : base::SupportsUserData::Data {
  base::RepeatingCallback<bool()> is_attached;
  base::WeakPtr<NativeSadTab> owner;
  PCNativeRendererCrash* __strong snapshot = nil;
};
State* GetState(content::WebContents* contents) {
  return contents ? static_cast<State*>(
                        contents->GetUserData(&kNativeSadTabStateKey))
                  : nullptr;
}
class NativeSadTab final : public SadTab {
 public:
  NativeSadTab(content::WebContents* contents, SadTabKind kind)
      : SadTab(contents, kind), contents_(contents->GetWeakPtr()) {
    CHECK(NSThread.isMainThread);
    State* state = GetState(contents);
    CHECK(state);
    state->owner = weak_factory_.GetWeakPtr();
    state->snapshot = [[PCNativeRendererCrash alloc]
        initWithSadTab:*this
                status:contents->GetCrashedStatus()];
    NotifyNativePageChanged(contents);
  }
  ~NativeSadTab() override {
    if (State* state = GetState(contents_.get());
        state && state->owner.get() == this) {
      state->owner.reset();
      state->snapshot = nil;
      NotifyNativePageChanged(contents_.get());
    }
  }
  void ReinstallInWebView() override {
    // Native ownership follows the actual contents. Late wrapper adoption and
    // tab moves read this same snapshot; no view or URL is recreated here.
    NotifyNativePageChanged(contents_.get());
  }
  void RequestFocus() {
    State* state = GetState(contents_.get());
    if (state && state->owner.get() == this) {
      RequestNativeRendererCrashFocus(contents_.get(), state->snapshot);
    }
  }
  BrowserWindowInterface* AttachedBrowser() const {
    auto* contents = contents_.get();
    State* state = GetState(contents);
    if (!state || !state->is_attached.Run()) {
      return nullptr;
    }
    auto* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
    auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
    PCNativePage* page = ExistingNativePage(contents);
    NSWindow* window = page.nativeView.window;
    return browser && !browser->IsDeleteScheduled() && browser->GetWindow() &&
                   window && page.observer &&
                   browser->GetWindow()
                           ->GetNativeWindow()
                           .GetNativeNSWindow() == window
               ? browser
               : nullptr;
  }
  bool Presented() {
    auto* browser = AttachedBrowser();
    if (!browser) {
      return false;
    }
    // A hidden renderer remains attached beneath the native crash sibling.
    // Actual drawing is acknowledged by the shell, never inferred from
    // WebContents visibility. Capture owner identity for subsequent actions.
    PCNativePage* page = ExistingNativePage(contents_.get());
    presented_browser_ = browser->GetWeakPtr();
    presented_window_ = page.nativeView.window;
    presented_observer_ = page.observer;
    if (!presented_) {
      presented_ = true;
      RecordFirstPaint();
    }
    return true;
  }
  bool Activate() {
    PCNativePage* page = ExistingNativePage(contents_.get());
    if (!contents_ || !presented_ || !presented_browser_ ||
        AttachedBrowser() != presented_browser_.get() ||
        page.nativeView.window != presented_window_ || !presented_observer_ ||
        page.observer != presented_observer_) {
      return false;
    }
    // The genuine reload/feedback action may synchronously destroy this model.
    // Snapshot is cleared only by the helper's actual reset/destruction.
    PerformAction(Action::kButton);
    return true;
  }

 private:
  base::WeakPtr<content::WebContents> contents_;
  bool presented_ = false;
  base::WeakPtr<BrowserWindowInterface> presented_browser_;
  NSWindow* __weak presented_window_ = nil;
  id<PCNativePageObserver> __weak presented_observer_ = nil;
  base::WeakPtrFactory<NativeSadTab> weak_factory_{this};
};
base::WeakPtr<NativeSadTab> Current(content::WebContents* contents,
                                    PCNativeRendererCrash* snapshot) {
  State* state = GetState(contents);
  return state && snapshot && state->snapshot == snapshot
             ? state->owner
             : base::WeakPtr<NativeSadTab>();
}
}  // namespace

void InstallNativeSadTab(content::WebContents& contents,
                         base::RepeatingCallback<bool()> is_attached) {
  CHECK(NSThread.isMainThread);
  CHECK(!GetState(&contents));
  CHECK(is_attached);
  auto state = std::make_unique<State>();
  state->is_attached = std::move(is_attached);
  contents.SetUserData(&kNativeSadTabStateKey, std::move(state));
}
std::unique_ptr<SadTab> CreateSadTab(content::WebContents* contents,
                                     SadTabKind kind) {
  if (GetState(contents)) {
    return std::make_unique<NativeSadTab>(contents, kind);
  }
  return std::make_unique<SadTabController>(contents, kind);
}
PCNativeRendererCrash* NativeRendererCrash(content::WebContents* contents) {
  State* state = GetState(contents);
  return state && state->owner ? state->snapshot : nil;
}
bool NativeRendererCrashDidPresent(content::WebContents* contents,
                                   PCNativeRendererCrash* snapshot) {
  auto model = Current(contents, snapshot);
  return model && model->Presented();
}
bool PerformNativeRendererCrashAction(content::WebContents* contents,
                                      PCNativeRendererCrash* snapshot) {
  auto model = Current(contents, snapshot);
  return model && model->Activate();
}
bool FocusNativeRendererCrash(content::WebContents* contents) {
  State* state = GetState(contents);
  auto model = state ? state->owner : base::WeakPtr<NativeSadTab>();
  if (!model) {
    return false;
  }
  model->RequestFocus();
  return true;
}
}  // namespace parc

// Copyright 2026 Parc contributors.
#include "native_auxiliary_page.h"

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/supports_user_data.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#import "page_host.h"

namespace parc {
namespace {
constexpr char kAuxiliaryPage[] = "parc-native-auxiliary-page";
struct State : base::SupportsUserData::Data {
  std::weak_ptr<NativeAuxiliaryPage> current;
  base::RepeatingClosureList changed;
  uint64_t generation = 0;
  bool routed = false;
};
State* GetState(content::WebContents& contents) {
  return static_cast<State*>(contents.GetUserData(kAuxiliaryPage));
}
}  // namespace
class NativeAuxiliaryPage::InspectedObserver final
    : public content::WebContentsObserver {
 public:
  InspectedObserver(content::WebContents& contents,
                    std::weak_ptr<NativeAuxiliaryPage> owner)
      : WebContentsObserver(&contents), owner_(std::move(owner)) {}
  void WebContentsDestroyed() override {
    if (auto owner = owner_.lock()) {
      owner->Revoke();
    }
  }

 private:
  std::weak_ptr<NativeAuxiliaryPage> owner_;
};
NativeAuxiliaryPage::NativeAuxiliaryPage(content::WebContents& inspected,
                                         content::WebContents& tools,
                                         BrowserWindowInterface& browser,
                                         NSView* hosted,
                                         NSView* container)
    : WebContentsObserver(&tools),
      inspected_(inspected.GetWeakPtr()),
      browser_(browser.GetWeakPtr()),
      tab_(tabs::TabInterface::GetFromContents(&inspected)->GetWeakPtr()),
      hosted_(hosted),
      container_(container),
      window_(container.window) {}
std::shared_ptr<NativeAuxiliaryPage> NativeAuxiliaryPage::BindDevTools(
    content::WebContents& inspected,
    content::WebContents& tools,
    NSView* hosted,
    NSView* container) {
  CHECK(NSThread.isMainThread);
  auto* tab = tabs::TabInterface::MaybeGetFromContents(&inspected);
  auto* browser = tab ? tab->GetBrowserWindowInterface() : nullptr;
  auto* devtools =
      DevToolsWindow::GetInstanceForInspectedWebContents(&inspected);
  DevToolsContentsResizingStrategy strategy;
  // The real engine supplies identity. A URL or matching Profile alone never
  // authorizes an arbitrary non-tab WebContents.
  if (!browser || browser->IsDeleteScheduled() || !devtools ||
      devtools->GetDevToolsWebContents() != &tools ||
      DevToolsWindow::GetInTabWebContents(&inspected, &strategy) != &tools ||
      tabs::TabInterface::MaybeGetFromContents(&tools) ||
      inspected.GetBrowserContext() != tools.GetBrowserContext()) {
    return {};
  }
  auto lease = std::shared_ptr<NativeAuxiliaryPage>(
      new NativeAuxiliaryPage(inspected, tools, *browser, hosted, container));
  if (!lease->IsValid()) {
    return {};
  }
  if (!GetState(tools)) {
    tools.SetUserData(kAuxiliaryPage, std::make_unique<State>());
  }
  auto* state = GetState(tools);
  const uint64_t generation = ++state->generation;
  auto old = state->current.lock();
  if (old) {
    old->Revoke();
  }
  if (!lease->IsValid() || GetState(tools)->generation != generation) {
    return {};
  }
  state->current = lease;
  state->routed = true;
  std::weak_ptr<NativeAuxiliaryPage> weak = lease;
  lease->inspected_observer_ =
      std::make_unique<InspectedObserver>(inspected, weak);
  lease->tab_detach_ = tab->RegisterWillDetach(base::BindRepeating(
      [](std::weak_ptr<NativeAuxiliaryPage> weak, tabs::TabInterface*,
         tabs::TabInterface::DetachReason) {
        if (auto lease = weak.lock()) {
          lease->Revoke();
        }
      },
      weak));
  lease->tab_discard_ = tab->RegisterWillDiscardContents(base::BindRepeating(
      [](std::weak_ptr<NativeAuxiliaryPage> weak, tabs::TabInterface*,
         content::WebContents*, content::WebContents*) {
        if (auto lease = weak.lock()) {
          lease->Revoke();
        }
      },
      weak));
  lease->window_close_ = [NSNotificationCenter.defaultCenter
      addObserverForName:NSWindowWillCloseNotification
                  object:lease->window_
                   queue:nil
              usingBlock:^(NSNotification*) {
                if (auto current = weak.lock()) {
                  current->Revoke();
                }
              }];
  state->changed.Notify();
  return lease->IsValid() && GetState(tools)->current.lock() == lease ? lease
                                                                      : nullptr;
}
bool NativeAuxiliaryPage::IsValid() const {
  auto* contents = web_contents();
  if (revoked_ || !contents || contents->IsBeingDestroyed() || !inspected_ ||
      inspected_->IsBeingDestroyed() || !browser_ ||
      browser_->IsDeleteScheduled() || !browser_->GetWindow() || !tab_ ||
      tab_->GetContents() != inspected_.get() ||
      tab_->GetBrowserWindowInterface() != browser_.get() ||
      contents->GetBrowserContext() != inspected_->GetBrowserContext() ||
      !window_ || container_.window != window_ ||
      hosted_.superview != container_ ||
      browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window_) {
    return false;
  }
  NSView* actual = contents->GetNativeView().GetNativeNSView();
  if (!actual || actual.window != window_ ||
      !(actual == hosted_ ||
        ([hosted_ isMemberOfClass:PCNativePageHost.class] &&
         ((PCNativePageHost*)hosted_).contentView == actual &&
         actual.superview == hosted_))) {
    return false;
  }
  auto* devtools =
      DevToolsWindow::GetInstanceForInspectedWebContents(inspected_.get());
  DevToolsContentsResizingStrategy strategy;
  return devtools && devtools->GetDevToolsWebContents() == contents &&
         DevToolsWindow::GetInTabWebContents(inspected_.get(), &strategy) ==
             contents &&
         !tabs::TabInterface::MaybeGetFromContents(contents);
}
bool NativeAuxiliaryPage::IsActive() const {
  return IsValid() && tab_->IsActivated();
}
BrowserWindowInterface* NativeAuxiliaryPage::browser() const {
  return IsValid() ? browser_.get() : nullptr;
}
NSWindow* NativeAuxiliaryPage::window() const {
  return IsValid() ? window_ : nil;
}
void NativeAuxiliaryPage::Revoke() {
  CHECK(NSThread.isMainThread);
  if (revoked_) {
    return;
  }
  auto keep = weak_from_this().lock();
  revoked_ = true;
  auto* contents = web_contents();
  if (contents) {
    if (auto* state = GetState(*contents);
        state && state->current.lock().get() == this) {
      state->current.reset();
    }
  }
  // Callbacks can destroy the owner, rebind the tools or run another sheet.
  // Commit rejection before any callback; no raw state survives notification.
  if (contents && web_contents() == contents) {
    if (auto* state = GetState(*contents)) {
      state->changed.Notify();
    }
  }
  invalidated_.Notify();
}
base::CallbackListSubscription NativeAuxiliaryPage::OnInvalidated(
    base::RepeatingClosure callback) {
  CHECK(!revoked_);
  return invalidated_.Add(std::move(callback));
}
void NativeAuxiliaryPage::WebContentsDestroyed() {
  Revoke();
  Observe(nullptr);
}
NativeAuxiliaryPage::~NativeAuxiliaryPage() {
  Revoke();
  if (window_close_) {
    [NSNotificationCenter.defaultCenter removeObserver:window_close_];
  }
}
void MarkNativeAuxiliaryRoute(content::WebContents& contents) {
  if (!GetState(contents)) {
    contents.SetUserData(kAuxiliaryPage, std::make_unique<State>());
  }
  GetState(contents)->routed = true;
}
bool HasNativeAuxiliaryRoute(content::WebContents& contents) {
  auto* state = GetState(contents);
  return state && state->routed;
}
std::shared_ptr<NativeAuxiliaryPage> GetNativeAuxiliaryPage(
    content::WebContents& contents) {
  auto* state = GetState(contents);
  auto lease = state ? state->current.lock() : nullptr;
  return lease && lease->IsValid() ? lease : nullptr;
}
base::CallbackListSubscription ObserveNativeAuxiliaryPage(
    content::WebContents& contents,
    base::RepeatingClosure callback) {
  if (!GetState(contents)) {
    contents.SetUserData(kAuxiliaryPage, std::make_unique<State>());
  }
  return GetState(contents)->changed.Add(std::move(callback));
}
}  // namespace parc

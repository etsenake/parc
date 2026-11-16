// Copyright 2026 Parc contributors.
#include "extension_side_panel.h"
#include "extension_side_panel_input.h"

#include <algorithm>
#include <map>
#include <utility>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/tab_list/tab_list_interface_observer.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_side_panel_coordinator.h"
#include "chrome/browser/ui/extensions/extension_side_panel_manager.h"
#include "chrome/browser/ui/side_panel/side_panel_entry.h"
#include "chrome/browser/ui/side_panel/side_panel_registry.h"
#include "chrome/browser/ui/tabs/public/tab_features.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_util.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/incognito_info.h"
#import "page_host.h"

@interface PCSidePanelPageObserver : NSObject <PCNativePageHostObserver>
@property(copy) void (^changed)(void);
@end
@implementation PCSidePanelPageObserver
@synthesize changed = _changed;
- (void)pageHost:(PCNativePageHost*)page didMoveToWindow:(NSWindow*)window {
  if (_changed)
    _changed();
}
- (void)pageHostDidAttemptDeferredFocus:(PCNativePageHost*)page {

}
@end

namespace parc {
using Coordinator = extensions::ExtensionSidePanelCoordinator;
using Manager = extensions::ExtensionSidePanelManager;

class SidePanelLoadStopObserver final : public content::WebContentsObserver {
 public:
  SidePanelLoadStopObserver(content::WebContents* contents,
                            base::RepeatingClosure stopped)
      : content::WebContentsObserver(contents), stopped_(std::move(stopped)) {}
  void DidStopLoading() override { stopped_.Run(); }

 private:
  base::RepeatingClosure stopped_;
};

class NativeExtensionSidePanel::State final
    : public std::enable_shared_from_this<State>,
      public TabListInterfaceObserver,
      public ProfileObserver {
 public:
  class Session;
  State(BrowserWindowInterface& browser, NativeSidePanelHost& host)
      : browser_(&browser), host_(&host) {}
  ~State() override {
    CHECK(shutdown_);
    CHECK_EQ(retiring_, 0u);
  }
  void Start(SidePanelUI& ui) {
    CHECK(!SidePanelUI::From(browser_));
    CHECK(SidePanelRegistry::From(browser_));
    registration_.emplace(browser_->GetUnownedUserDataHost(), ui);
    Owners()[browser_] = shared_from_this();
    auto* tabs = TabListInterface::From(browser_);
    CHECK(tabs);
    tabs_.Observe(tabs);
    profile_.Observe(browser_->GetProfile());

    CHECK(!Manager::From(browser_));
    manager_ =
        std::make_unique<Manager>(browser_, SidePanelRegistry::From(browser_));
  }
  void Show(const SidePanelEntryKey&, std::optional<SidePanelOpenTrigger>);
  void Close(SidePanelEntryHideReason, bool reset_active = true);
  void Changed();
  void TabChanged();
  void Ready(const std::shared_ptr<Session>&);
  void Cancel(const std::shared_ptr<Session>&);
  void Retire(std::shared_ptr<Session>);
  void AdoptMoved(const std::shared_ptr<Session>&);
  void ClearUnusedCaches(bool all);
  static std::map<BrowserWindowInterface*, std::weak_ptr<State>>& Owners() {
    static base::NoDestructor<
        std::map<BrowserWindowInterface*, std::weak_ptr<State>>>
        owners;
    return *owners;
  }
  void Shutdown(base::OnceClosure);
  void FinishShutdown();
  bool ContextValid() const;
  bool SessionValid(const Session&, bool visible) const;
  bool Pending(const SidePanelEntryKey&) const;
  SidePanelRegistry* Contextual() const {
    if (shutdown_)
      return nullptr;
    auto* tab = TabListInterface::From(browser_)->GetActiveTab();
    return tab ? SidePanelRegistry::From(tab) : nullptr;
  }
  void OnActiveTabChanged(TabListInterface&, tabs::TabInterface*) override {
    TabChanged();
  }
  void OnTabRemoved(TabListInterface&,
                    tabs::TabInterface*,
                    TabRemovedReason) override {
    TabChanged();
  }
  void OnWebContentsReplaced(TabListInterface&,
                             tabs::TabInterface*,
                             content::WebContents*,
                             content::WebContents*) override {
    TabChanged();
  }
  void OnTabListDestroyed(TabListInterface&) override {

    CHECK(shutdown_);
    CHECK_EQ(retiring_, 0u);
    tabs_.Reset();
  }
  void OnProfileWillBeDestroyed(Profile*) override {
    CHECK(shutdown_);
    CHECK_EQ(retiring_, 0u);
    profile_.Reset();
  }
  BrowserWindowInterface* browser_;
  NativeSidePanelHost* host_;
  std::shared_ptr<Session> current_;
  std::map<SidePanelEntry*, std::shared_ptr<Session>> cached_;
  base::RepeatingCallbackList<void()> shown_callbacks_;
  bool shutdown_ = false;
  bool shutting_down_ = false;
  bool drain_queued_ = false;
  size_t retiring_ = 0;
  uint64_t generation_ = 0;
  bool in_close_ = false;
  struct PendingShow {
    SidePanelEntryKey key;
    std::optional<SidePanelOpenTrigger> trigger;
    uint64_t generation;
  };
  std::optional<PendingShow> pending_show_;
  std::optional<SidePanelEntryKey> detached_key_;
  std::vector<base::OnceClosure> drained_;
  std::optional<ui::ScopedUnownedUserData<SidePanelUI>> registration_;
  std::unique_ptr<Manager> manager_;
  base::ScopedObservation<TabListInterface, TabListInterfaceObserver> tabs_{
      this};
  base::ScopedObservation<Profile, ProfileObserver> profile_{this};
};

class NativeExtensionSidePanel::State::Session final
    : public extensions::ExtensionView,
      public std::enable_shared_from_this<Session> {
 public:
  Session(std::weak_ptr<State> owner,
          Coordinator& coordinator,
          SidePanelEntry& entry,
          tabs::TabInterface* tab,
          uint64_t generation)
      : owner_(std::move(owner)),
        coordinator_(coordinator.GetWeakPtr()),
        entry_(entry.GetWeakPtr()),
        key_(entry.key()),
        tab_(tab ? tab->GetWeakPtr() : nullptr),
        for_tab_(tab != nullptr),
        generation_(generation) {}
  ~Session() override { CHECK(!host_); }
  class CallScope {
   public:
    explicit CallScope(Session& s) : s_(s) { ++s_.calls_; }
    ~CallScope() {
      if (--s_.calls_ == 0 && s_.destroy_after_calls_)
        s_.ScheduleDestroy(std::move(s_.destroy_after_calls_));
    }

   private:
    Session& s_;
  };
  void ScheduleDestroy(base::OnceClosure done) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<Session> self, base::OnceClosure done) {
              if (self->calls_) {
                CHECK(!self->destroy_after_calls_);
                self->destroy_after_calls_ = std::move(done);
                return;
              }
              self->DestroyHost();
              std::move(done).Run();
            },
            shared_from_this(), std::move(done)));
  }
  bool Prepare() {
    auto alive = shared_from_this();
    CallScope call(*this);
    std::weak_ptr<Session> weak = alive;
    if (!coordinator_)
      return false;
    const bool reuse = host_ != nullptr;
    if (!reuse)
      host_ = coordinator_->AcquireNativeHost(base::BindOnce(
          [](std::weak_ptr<Session> weak) {
            if (auto self = weak.lock()) {
              CallScope call(*self);
              if (auto owner = self->owner_.lock())
                owner->Cancel(self);
            }
          },
          weak));
    if (!host_ || closed_)
      return false;
    NSView* native = host_->host_contents()->GetNativeView().GetNativeNSView();
    if (!native || native.window ||
        (!reuse && (host_->view() ||
                    [native.superview isMemberOfClass:PCNativePageHost.class])))
      return false;
    if (!reuse) {
      load_stop_ = std::make_unique<SidePanelLoadStopObserver>(
          host_->host_contents(),
          base::BindRepeating(
              [](std::weak_ptr<Session> weak) {
                if (auto self = weak.lock(); self && !self->closed_ &&
                                             !self->shown_ && self->host_ &&
                                             self->host_->has_loaded_once())
                  self->OnLoaded();
              },
              weak));
      observer_ = [[PCSidePanelPageObserver alloc] init];
      observer_.changed = ^{
        if (auto self = weak.lock(); self && !self->closed_) {
          if (auto owner = self->owner_.lock())
            owner->Changed();
        }
      };
      page_ = [PCNativePageHost hostWithContentView:native observer:observer_];
      host_->set_view(this);
      if (tab_) {
        will_detach_ = tab_->RegisterWillDetach(base::BindRepeating(
            [](std::weak_ptr<Session> weak, tabs::TabInterface*,
               tabs::TabInterface::DetachReason reason) {
              if (auto self = weak.lock()) {
                if (auto owner = self->owner_.lock()) {
                  if (reason == tabs::TabInterface::DetachReason::kDelete)
                    owner->Cancel(self);
                  else if (owner->current_ == self) {
                    owner->detached_key_ = self->key_;
                    owner->Close(SidePanelEntryHideReason::kBackgrounded,
                                 false);
                  }
                }
              }
            },
            weak));
        did_insert_ = tab_->RegisterDidInsert(base::BindRepeating(
            [](std::weak_ptr<Session> weak, tabs::TabInterface* tab) {
              if (auto self = weak.lock(); self && !self->closed_) {
                auto found =
                    State::Owners().find(tab->GetBrowserWindowInterface());
                auto destination = found == State::Owners().end()
                                       ? nullptr
                                       : found->second.lock();
                if (destination)
                  destination->AdoptMoved(self);
                else if (auto owner = self->owner_.lock())
                  owner->Cancel(self);
              }
            },
            weak));
      }
    }
    auto owner = owner_.lock();
    if (!owner || !owner->ContextValid())
      return false;

    NSView* container = owner->host_->SidePanelContainer();
    page_.frame = container.bounds;
    page_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    observer_.changed = ^{
      if (auto self = weak.lock(); self && !self->closed_) {
        if (auto state = self->owner_.lock())
          state->Changed();
      }
    };
    [container addSubview:page_];
    if (closed_ || !owner->SessionValid(*this, false))
      return false;
    host_->host_contents()->WasHidden();
    if (closed_)
      return false;
    if (!reuse)
      host_->CreateRendererSoon();
    if (!closed_ && host_->has_loaded_once())
      OnLoaded();
    return !closed_;
  }

  void Suspend(SidePanelEntryHideReason reason, bool terminal = false) {
    if (suspending_ || (closed_ && !terminal))
      return;
    suspending_ = true;
    CallScope call(*this);
    const bool was_shown = std::exchange(shown_, false);
    NSWindow* exact_window = page_.window;
    NSResponder* prior = exact_window.firstResponder;
    NSResponder* normalized = NormalizeResponder(prior);
    const bool owned_focus = NativeExtensionSidePanelOwnsFocus(
        page_, focus_scope_, normalized, exact_window);
    if (host_ && host_->view())
      host_->host_contents()->WasHidden();
    observer_.changed = nil;
    [page_ removeFromSuperview];
    NSResponder* now = exact_window.firstResponder;
    NSResponder* restore = restore_focus_;
    if (owned_focus && exact_window == focus_window_ &&
        (now == prior || now == exact_window || !now) &&
        [restore isKindOfClass:NSView.class] &&
        [(NSView*)restore window] == exact_window &&
        ![(NSView*)restore isHiddenOrHasHiddenAncestor] &&
        (![restore isKindOfClass:NSControl.class] || [(NSControl*)restore isEnabled]))
      [exact_window makeFirstResponder:restore];
    if (entry_) {
      auto entry = entry_;
      if (was_shown)
        entry->OnEntryWillHide(reason);
      if (entry && was_shown)
        entry->OnEntryHidden();
    }
    suspending_ = false;
  }
  void Detach(SidePanelEntryHideReason reason, bool reset_active) {
    if (closed_)
      return;
    CallScope call(*this);
    closed_ = true;
    Suspend(reason, true);
    will_detach_ = {};
    did_insert_ = {};
    load_stop_.reset();
    if (coordinator_) {
      auto coordinator = coordinator_;
      auto* registry = Registry();
      if (reset_active && registry && entry_ &&
          registry->GetActiveEntry() == entry_.get())
        registry->ResetActiveEntry();
      coordinator->ReleaseNativeHost(host_.get());
    }
    coordinator_.reset();
    entry_.reset();
    tab_.reset();
  }
  SidePanelRegistry* Registry() const {
    if (for_tab_)
      return tab_ ? SidePanelRegistry::From(tab_.get()) : nullptr;
    auto owner = owner_.lock();
    return owner && owner->browser_ ? SidePanelRegistry::From(owner->browser_)
                                    : nullptr;
  }
  void Mark() {
    auto* registry = Registry();
    if (!registry || !entry_)
      return;
    if (!for_tab_)
      Displace();
    auto active = registry->GetActiveEntry();
    if (active == entry_.get())
      return;
    if (active && *active)
      replaced_ = (*active)->GetWeakPtr();
    registry->SetActiveEntry(entry_.get());
    marked_ = true;
  }
  void Displace() {
    auto owner = owner_.lock();
    auto* tab = owner && owner->browser_
                    ? TabListInterface::From(owner->browser_)->GetActiveTab()
                    : nullptr;
    auto* contextual = tab ? SidePanelRegistry::From(tab) : nullptr;
    if (!contextual)
      return;
    auto active = contextual->GetActiveEntry();
    if (!active || !*active)
      return;
    displaced_ = (*active)->GetWeakPtr();
    displaced_tab_ = tab->GetWeakPtr();
    contextual->ResetActiveEntry();
  }
  static void Restore(SidePanelRegistry& registry,
                      const base::WeakPtr<SidePanelEntry>& entry) {
    if (entry && registry.GetEntryForKey(entry->key()) == entry.get())
      registry.SetActiveEntry(entry.get());
    else
      registry.ResetActiveEntry();
  }
  void Unmark() {
    if (std::exchange(marked_, false) && entry_) {
      auto* registry = Registry();
      if (registry && registry->GetActiveEntry() == entry_.get())
        Restore(*registry, replaced_);
    }
    RestoreDisplaced();
    Settle();
  }
  void RestoreDisplaced() {
    if (!displaced_ || !displaced_tab_)
      return;
    auto* contextual = SidePanelRegistry::From(displaced_tab_.get());
    if (contextual && !contextual->GetActiveEntry())
      Restore(*contextual, displaced_);
  }
  void Shown() {
    auto owner = owner_.lock();
    auto* active = owner && owner->browser_
                       ? TabListInterface::From(owner->browser_)->GetActiveTab()
                       : nullptr;
    if (displaced_tab_.get() != active)
      RestoreDisplaced();
    Settle();
  }
  void Settle() {
    marked_ = false;
    replaced_.reset();
    displaced_.reset();
    displaced_tab_.reset();
  }
  bool PendingActive() const {
    if (closed_ || shown_ || !entry_)
      return false;
    auto* registry = Registry();
    return registry && registry->GetActiveEntry() == entry_.get();
  }
  static NSResponder* NormalizeResponder(NSResponder* responder) {
    if ([responder isKindOfClass:NSTextView.class] &&
        [(NSTextView*)responder isFieldEditor]) {
      id delegate = [(NSTextView*)responder delegate];
      if ([delegate isKindOfClass:NSView.class])
        return delegate;
    }
    return responder;
  }
  void RememberFocus(NSWindow* window) {
    focus_window_ = window;
    auto owner = owner_.lock();
    NSView* scope = owner && owner->host_
                        ? owner->host_->SidePanelFocusScope() : nil;
    focus_scope_ = scope.window == window && [page_ isDescendantOf:scope]
                       ? scope : page_;
    restore_focus_ = NormalizeResponder(window.firstResponder);
  }
  void DestroyHost() {
    CHECK(closed_);

    host_.reset();
    [page_ invalidate];
    page_ = nil;
    observer_ = nil;
  }
  gfx::NativeView GetNativeView() override {
    return gfx::NativeView(page_.contentView);
  }
  void ResizeDueToAutoResize(content::WebContents* source,
                             const gfx::Size&) override {

    if (!closed_ && host_ && source == host_->host_contents()) {
      if (auto owner = owner_.lock())
        owner->Changed();
    }
  }
  void RenderFrameCreated(content::RenderFrameHost*) override {

  }
  bool HandleKeyboardEvent(
      content::WebContents* source,
      const input::NativeWebKeyboardEvent& event) override {
    auto alive = shared_from_this();
    CallScope call(*this);
    auto owner = owner_.lock();
    if (closed_ || !owner || !host_ || source != host_->host_contents() ||
        event.skip_if_unhandled || !owner->SessionValid(*this, true))
      return false;
    if (event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
        NativeExtensionSidePanelDismissesForKey(event.os_event.Get(),
                                               page_.window)) {

      owner->Close(SidePanelEntryHideReason::kSidePanelClosed);
      return true;
    }
    return owner->host_->HandleSidePanelKey(source, event);
  }
  void OnLoaded() override {

    std::weak_ptr<Session> weak = shared_from_this();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::weak_ptr<Session> weak) {
                         if (auto self = weak.lock(); self && !self->closed_) {
                           if (auto owner = self->owner_.lock())
                             owner->Ready(self);
                         }
                       },
                       weak));
  }
  base::CallbackListSubscription will_detach_;
  base::CallbackListSubscription did_insert_;
  std::unique_ptr<SidePanelLoadStopObserver> load_stop_;
  int calls_ = 0;
  base::OnceClosure destroy_after_calls_;
  std::weak_ptr<State> owner_;
  base::WeakPtr<Coordinator> coordinator_;
  base::WeakPtr<SidePanelEntry> entry_;
  SidePanelEntryKey key_;
  base::WeakPtr<tabs::TabInterface> tab_;
  bool for_tab_;
  uint64_t generation_;
  bool shown_ = false;
  bool marked_ = false;
  base::WeakPtr<SidePanelEntry> replaced_;
  base::WeakPtr<SidePanelEntry> displaced_;
  base::WeakPtr<tabs::TabInterface> displaced_tab_;
  bool closed_ = false;
  bool suspending_ = false;
  std::shared_ptr<extensions::ExtensionViewHost> host_;
  __weak NSWindow* focus_window_ = nil;
  __weak NSView* focus_scope_ = nil;
  __weak NSResponder* restore_focus_ = nil;
  PCNativePageHost* __strong page_ = nil;
  PCSidePanelPageObserver* __strong observer_ = nil;
};

bool NativeExtensionSidePanel::State::ContextValid() const {
  if (shutdown_ || !host_ || !browser_ || !host_->IsSidePanelBrowserSelected())
    return false;
  NSWindow* window = host_->SidePanelWindow();
  NSView* container = host_->SidePanelContainer();
  auto* browser_window = BrowserWindow::FromBrowser(browser_);
  return browser_window && window &&
         browser_window->GetNativeWindow().GetNativeNSWindow() == window &&
         container && window.contentView && container.window == window &&
         (container == window.contentView ||
          [container isDescendantOf:window.contentView]) &&
         window.visible && !NSIsEmptyRect(container.bounds);
}
bool NativeExtensionSidePanel::State::Pending(
    const SidePanelEntryKey& key) const {
  return current_ && !current_->closed_ && !current_->shown_ &&
         current_->key_ == key;
}
bool NativeExtensionSidePanel::State::SessionValid(const Session& s,
                                                   bool visible) const {
  if (!ContextValid() || s.closed_ || current_.get() != &s ||
      generation_ != s.generation_ || !s.entry_ || !s.coordinator_ ||
      !s.host_ || s.coordinator_->profile() != browser_->GetProfile() ||
      s.coordinator_->GetBrowser() != browser_ ||
      s.coordinator_->GetEntry() != s.entry_.get())
    return false;
  Profile* expected = browser_->GetProfile();
  if (expected->IsOffTheRecord()) {
    if (!extensions::util::IsIncognitoEnabled(s.coordinator_->extension()->id(),
                                              expected))
      return false;
    if (!extensions::IncognitoInfo::IsSplitMode(s.coordinator_->extension()))
      expected = expected->GetOriginalProfile();
  }
  if (s.host_->host_contents()->GetBrowserContext() != expected)
    return false;
  if (s.for_tab_ &&
      (!s.tab_ ||
       TabListInterface::From(browser_)->GetActiveTab() != s.tab_.get() ||
       s.tab_->GetBrowserWindowInterface() != browser_))
    return false;
  NSView* container = host_->SidePanelContainer();
  if (s.page_.superview != container ||
      s.page_.window != host_->SidePanelWindow())
    return false;
  return !visible || (s.shown_ && !container.hiddenOrHasHiddenAncestor &&
                      !s.page_.hiddenOrHasHiddenAncestor &&
                      !NSIsEmptyRect(s.page_.visibleRect));
}
void NativeExtensionSidePanel::State::Show(
    const SidePanelEntryKey& key,
    std::optional<SidePanelOpenTrigger> trigger) {
  auto alive = shared_from_this();
  if (in_close_) {
    pending_show_ = PendingShow{key, trigger, ++generation_};
    return;
  }
  if (!ContextValid() || key.id() != SidePanelEntryId::kExtension ||
      !key.extension_id())
    return;
  auto* tab = TabListInterface::From(browser_)->GetActiveTab();
  auto* registry = Contextual();
  auto* entry = registry ? registry->GetEntryForKey(key) : nullptr;
  Manager* manager = nullptr;
  if (entry && tab && tab->GetTabFeatures()) {
    manager = tab->GetTabFeatures()->extension_side_panel_manager();
  } else {
    tab = nullptr;
    registry = SidePanelRegistry::From(browser_);
    entry = registry->GetEntryForKey(key);
    manager = manager_.get();
  }
  if (!entry || !manager)
    return;
  auto* coordinator = manager->GetExtensionCoordinator(*key.extension_id());
  if (!coordinator || coordinator->GetEntry() != entry ||
      coordinator->GetBrowser() != browser_)
    return;
  if (current_ && current_->entry_.get() == entry && !current_->closed_) {
    auto same = current_;
    Changed();
    if (current_ != same && trigger != SidePanelOpenTrigger::kTabChanged)
      Show(key, trigger);
    return;
  }
  auto weak_entry = entry->GetWeakPtr();
  auto weak_coordinator = coordinator->GetWeakPtr();
  const uint64_t before = generation_;
  Close(SidePanelEntryHideReason::kReplaced, false);

  if (shutdown_ || generation_ != before + 1 || current_ || !weak_entry ||
      !weak_coordinator || !ContextValid())
    return;
  if (!host_->SetSidePanelVisible(false) || shutdown_ || current_ ||
      generation_ != before + 1 || !weak_entry || !weak_coordinator ||
      !ContextValid())
    return;
  entry = weak_entry.get();
  entry->set_last_open_trigger(trigger);
  entry->NativeContentRequested();
  std::shared_ptr<Session> session;
  if (auto it = cached_.find(entry); it != cached_.end()) {
    session = std::move(it->second);
    cached_.erase(it);
    session->generation_ = generation_;
  } else {
    session = std::make_shared<Session>(alive, *weak_coordinator, *entry, tab,
                                        generation_);
  }
  current_ = session;
  session->Mark();
  if (!session->Prepare())
    Cancel(session);
}
void NativeExtensionSidePanel::State::Ready(
    const std::shared_ptr<Session>& session) {
  auto alive = shared_from_this();

  if (current_ != session || session->closed_ || session->shown_)
    return;
  if (!SessionValid(*session, false) || !session->host_->has_loaded_once()) {
    Cancel(session);
    return;
  }
  if (session->host_->host_contents()->GetController().GetPendingEntry())
    return;
  Session::CallScope call(*session);
  session->RememberFocus(host_->SidePanelWindow());
  if (!host_->SetSidePanelVisible(true) || !SessionValid(*session, false)) {
    Cancel(session);
    return;
  }
  session->shown_ = true;
  session->Shown();
  if (!SessionValid(*session, true)) {
    Cancel(session);
    return;
  }
  session->host_->host_contents()->WasShown();
  if (!SessionValid(*session, true)) {
    Cancel(session);
    return;
  }

  session->entry_->OnEntryShown();
  if (!SessionValid(*session, true))
    return;
  session->host_->host_contents()->Focus();
  if (!SessionValid(*session, true))
    return;
  shown_callbacks_.Notify();
}
void NativeExtensionSidePanel::State::Cancel(
    const std::shared_ptr<Session>& session) {
  if (current_ == session) {
    Close(SidePanelEntryHideReason::kSidePanelClosed);
    return;
  }
  auto found = std::ranges::find_if(
      cached_, [&](const auto& pair) { return pair.second == session; });
  if (found == cached_.end())
    return;
  cached_.erase(found);
  ++retiring_;
  session->Detach(SidePanelEntryHideReason::kSidePanelClosed, true);
  Retire(session);
}
void NativeExtensionSidePanel::State::Close(SidePanelEntryHideReason reason,
                                            bool reset_active) {
  auto alive = shared_from_this();
  const uint64_t closing_generation = ++generation_;
  if (in_close_)
    return;
  in_close_ = true;
  auto session = std::move(current_);
  if (session)
    session->Unmark();

  const bool cache = session && !reset_active && !shutdown_ &&
                     session->entry_ && session->coordinator_;
  if (session) {
    if (cache) {
      cached_[session->entry_.get()] = session;
      session->Suspend(reason);
    } else {
      ++retiring_;
      session->Detach(reason, reset_active);
    }
  }
  if (reset_active && browser_) {
    SidePanelRegistry::From(browser_)->ResetActiveEntry();
    if (auto* registry = Contextual())
      registry->ResetActiveEntry();
    ClearUnusedCaches(shutdown_);
  }
  if (!current_ && generation_ == closing_generation && host_)
    host_->SetSidePanelVisible(false);
  in_close_ = false;
  if (session && !cache)
    Retire(std::move(session));
  if (pending_show_) {
    auto pending = std::move(*pending_show_);
    pending_show_.reset();
    std::weak_ptr<State> weak = alive;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::weak_ptr<State> weak, PendingShow request) {
                         if (auto self = weak.lock();
                             self && !self->shutdown_ &&
                             self->generation_ == request.generation)
                           self->Show(request.key, request.trigger);
                       },
                       weak, std::move(pending)));
  }
  FinishShutdown();
}
void NativeExtensionSidePanel::State::Retire(std::shared_ptr<Session> session) {
  session->ScheduleDestroy(base::BindOnce(
      [](std::shared_ptr<State> self) {
        --self->retiring_;
        self->FinishShutdown();
      },
      shared_from_this()));
}
void NativeExtensionSidePanel::State::Changed() {
  auto alive = shared_from_this();
  auto session = current_;
  if (!session)
    return;
  Session::CallScope call(*session);

  if (!SessionValid(*session, false)) {
    Cancel(session);
    return;
  }
  session->page_.frame = host_->SidePanelContainer().bounds;
  if (session->shown_ && !SessionValid(*session, true))
    Cancel(session);
}
void NativeExtensionSidePanel::State::TabChanged() {
  auto alive = shared_from_this();
  if (shutdown_)
    return;
  auto* selected = TabListInterface::From(browser_)->GetActiveTab();
  if (selected && selected->GetBrowserWindowInterface() != browser_)
    return;
  auto* contextual = Contextual();
  std::optional<SidePanelEntryKey> next;

  if (contextual && contextual->GetActiveEntry())
    next = (*contextual->GetActiveEntry())->key();
  auto* global = SidePanelRegistry::From(browser_);
  auto previous = current_ ? std::make_optional(current_->key_) : detached_key_;
  if (!next && previous && global->GetEntryForKey(*previous))
    next = previous;
  if (previous && !next && global->GetActiveEntry())
    next = (*global->GetActiveEntry())->key();
  detached_key_.reset();
  if (!current_ && !next)
    return;
  if (current_ && !current_->for_tab_ && next && *next == current_->key_ &&
      (!contextual || !contextual->GetEntryForKey(*next)))
    return;
  if (next)
    Show(*next, SidePanelOpenTrigger::kTabChanged);
  else
    Close(SidePanelEntryHideReason::kBackgrounded, false);
}
void NativeExtensionSidePanel::State::AdoptMoved(
    const std::shared_ptr<Session>& session) {
  auto alive = shared_from_this();
  if (shutdown_ || !session->for_tab_ || !session->tab_ ||
      !session->coordinator_ ||
      session->tab_->GetBrowserWindowInterface() != browser_ ||
      session->coordinator_->profile() != browser_->GetProfile())
    return;
  auto source = session->owner_.lock();
  if (source.get() == this)
    return;
  if (source) {
    if (source->current_ == session)
      source->Close(SidePanelEntryHideReason::kBackgrounded, false);
    if (session->entry_)
      source->cached_.erase(session->entry_.get());
  }
  if (!session->entry_ || session->closed_)
    return;
  session->owner_ = alive;
  cached_[session->entry_.get()] = session;
  TabChanged();
}
void NativeExtensionSidePanel::State::ClearUnusedCaches(bool all) {
  std::vector<std::shared_ptr<Session>> discard;
  for (const auto& [entry, session] : cached_) {
    auto* tab = session->tab_.get();
    auto* registry =
        tab ? SidePanelRegistry::From(tab)
            : (browser_ ? SidePanelRegistry::From(browser_) : nullptr);
    const bool active = session->entry_ && registry &&
                        registry->GetActiveEntry() == session->entry_.get();
    if (all || !active)
      discard.push_back(session);
  }
  for (const auto& session : discard)
    Cancel(session);
}
void NativeExtensionSidePanel::State::Shutdown(base::OnceClosure completion) {
  auto alive = shared_from_this();
  if (completion)
    drained_.push_back(std::move(completion));
  if (!shutdown_) {
    shutdown_ = true;
    shutting_down_ = true;
    Close(SidePanelEntryHideReason::kSidePanelClosed);
    tabs_.Reset();
    profile_.Reset();

    ClearUnusedCaches(true);

    Owners().erase(browser_);
    registration_.reset();
    host_ = nullptr;
    browser_ = nullptr;
    shutting_down_ = false;
  }
  FinishShutdown();
}
void NativeExtensionSidePanel::State::FinishShutdown() {
  if (!shutdown_ || shutting_down_ || in_close_ || retiring_ || drain_queued_ ||
      drained_.empty())
    return;
  drain_queued_ = true;

  base::SequencedTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE,
      base::BindOnce(
          [](std::shared_ptr<State> self) {
            self->drain_queued_ = false;
            if (self->retiring_ || self->shutting_down_ || self->in_close_) {
              self->FinishShutdown();
              return;
            }
            self->manager_.reset();
            auto callbacks = std::move(self->drained_);
            for (auto& callback : callbacks)
              std::move(callback).Run();
          },
          shared_from_this()));
}

NativeExtensionSidePanel::NativeExtensionSidePanel(
    BrowserWindowInterface& browser,
    NativeSidePanelHost& host)
    : state_(std::make_shared<State>(browser, host)) {
  state_->Start(*this);
}
NativeExtensionSidePanel::~NativeExtensionSidePanel() {
  state_->Shutdown(base::DoNothing());
}
void NativeExtensionSidePanel::Shutdown(base::OnceClosure done) {
  state_->Shutdown(std::move(done));
}
void NativeExtensionSidePanel::HostStateChanged() {
  state_->Changed();
}
void NativeExtensionSidePanel::Show(SidePanelEntryId id,
                                    std::optional<SidePanelOpenTrigger> trigger,
                                    bool animations) {
  Show(SidePanelEntryKey(id), trigger, animations);
}
void NativeExtensionSidePanel::Show(SidePanelEntryKey key,
                                    std::optional<SidePanelOpenTrigger> trigger,
                                    bool) {
  state_->Show(key, trigger);
}
void NativeExtensionSidePanel::ShowFrom(SidePanelEntryKey key, gfx::Rect) {

  state_->Show(key, std::nullopt);
}
void NativeExtensionSidePanel::Close(SidePanelEntryHideReason reason, bool) {
  state_->Close(reason);
}
void NativeExtensionSidePanel::Toggle(SidePanelEntryKey key,
                                      SidePanelOpenTrigger trigger) {
  if (IsSidePanelEntryShowing(key) || state_->Pending(key))
    Close();
  else
    state_->Show(key, trigger);
}
std::optional<SidePanelEntryId> NativeExtensionSidePanel::GetCurrentEntryId()
    const {
  return IsSidePanelShowing() ? std::make_optional(state_->current_->key_.id())
                              : std::nullopt;
}
int NativeExtensionSidePanel::GetCurrentEntryDefaultContentWidth() const {
  return state_->current_ && state_->current_->entry_
             ? state_->current_->entry_->GetDefaultContentWidth()
             : SidePanelEntry::kSidePanelDefaultContentWidth;
}
bool NativeExtensionSidePanel::IsSidePanelShowing() const {
  return state_->current_ && state_->SessionValid(*state_->current_, true);
}
bool NativeExtensionSidePanel::IsSidePanelEntryShowing(
    const SidePanelEntryKey& key) const {
  const auto& current = state_->current_;
  return current && current->key_ == key &&
         (IsSidePanelShowing() || current->PendingActive());
}
bool NativeExtensionSidePanel::IsSidePanelEntryShowing(
    const SidePanelEntryKey& key,
    bool for_tab) const {
  return IsSidePanelEntryShowing(key) && state_->current_->for_tab_ == for_tab;
}
bool NativeExtensionSidePanel::UsesNativeExtensionContent() const {
  return !state_->shutdown_;
}
bool NativeExtensionSidePanel::IsSidePanelEntryPending(
    const SidePanelEntryKey& key,
    bool for_tab) const {
  return state_->Pending(key) && state_->current_->for_tab_ == for_tab;
}
base::CallbackListSubscription NativeExtensionSidePanel::RegisterSidePanelShown(
    ShownCallback callback) {
  return state_->shown_callbacks_.Add(std::move(callback));
}
void NativeExtensionSidePanel::OnActiveTabChanged(content::WebContents*,
                                                  content::WebContents*,
                                                  bool) {
  state_->TabChanged();
}
content::WebContents* NativeExtensionSidePanel::GetWebContentsForTest(
    SidePanelEntryId id) {
  return state_->current_ && state_->current_->key_.id() == id &&
                 state_->current_->host_
             ? state_->current_->host_->host_contents()
             : nullptr;
}
void NativeExtensionSidePanel::DisableAnimationsForTesting() {

}
void NativeExtensionSidePanel::SetNoDelaysForTesting(bool) {

}
}

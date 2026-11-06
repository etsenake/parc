// Copyright 2026 Parc contributors.
#include "native_cast.h"
#include "native_gmc_presentation.h"
#import <AppKit/AppKit.h>
#include <memory>
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/media/router/media_router_feature.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/media_router/media_route_starter.h"
#include "chrome/browser/ui/media_router/media_router_ui.h"
#include "chrome/browser/ui/media_router/media_router_ui_service.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/views/media_router/cast_dialog_view.h"
#include "components/media_router/browser/media_router_metrics.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "ui/base/base_window.h"
#include "ui/display/types/display_constants.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
BrowserWindowInterface* Owner(content::WebContents* contents) {
  PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
  auto* browser =
      contents
          ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents)
          : nullptr;
  auto* profile =
      contents ? Profile::FromBrowserContext(contents->GetBrowserContext())
               : nullptr;
  PCNativeBrowserWindow* binding =
      browser ? AppKitBindingForBrowser(browser) : nil;
  NSWindow* window = binding.window;
  if (!page || page.closed || !browser || !profile ||
      profile->ShutdownStarted() || browser->IsDeleteScheduled() ||
      browser->GetProfile() != profile ||
      browser->GetTabStripModel()->GetActiveWebContents() != contents ||
      !chrome::CanRouteMedia(browser) ||
      !AppKitBrowserAcceptsNewPages(*browser) || IsNativePageRetiring(page) ||
      IsLiveTabTransferTarget(contents) ||
      IsNativeProfileRemovalBlocked(profile->GetPath()) || !binding.client ||
      !window || page.nativeView.window != window ||
      page.nativeView.hiddenOrHasHiddenAncestor ||
      [binding.client selectedNativePage] != page ||
      contents->IsBeingDestroyed() || contents->IsCrashed() ||
      !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
      contents->GetVisibility() == content::Visibility::HIDDEN ||
      !window.visible || window.miniaturized || window.attachedSheet ||
      PCNativeWindowHasSecurityReservation(window))
    return nullptr;
  return browser;
}

// The native host supplies only exact ownership and a native anchor. Chromium's
// real model, view, discovery, policies, requests and route results remain in
// use.
class CastSession final : public std::enable_shared_from_this<CastSession>,
                          public content::WebContentsObserver,
                          public ProfileObserver,
                          public media_router::MediaRouterUIService::Observer,
                          public media_router::CastDialogController,
                          public views::WidgetObserver,
                          public TabStripModelObserver {
 public:
  CastSession(content::WebContents* contents, BrowserWindowInterface& browser)
      : content::WebContentsObserver(contents),
        browser_(browser.GetWeakPtr()),
        profile_(browser.GetProfile()->GetWeakPtr()),
        document_(contents->GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        window_(AppKitBindingForBrowser(&browser).window) {}
  ~CastSession() override { Close(); }

  bool Show() {
    auto keep = shared_from_this();
    if (!Current(false) || !window_.keyWindow || !NSApp.active)
      return false;
    // Same security boundary as Chromium's normal Cast dialog, before creating
    // discovery/UI. This can reenter and destroy/change the original owner.
    auto blocker =
        web_contents()->ForSecurityDropFullscreen(display::kInvalidDisplayId);
    if (!blocker || !Current(false) || !window_.keyWindow || !NSApp.active)
      return false;
    fullscreen_blocker_ = std::move(*blocker);
    profile_observation_.Observe(profile_.get());
    browser_->GetTabStripModel()->AddObserver(this);
    service_ = media_router::MediaRouterUIService::Get(profile_.get());
    if (!service_) {
      Close();
      return false;
    }
    service_->AddObserver(this);
    auto ui =
        media_router::MediaRouterUI::CreateWithDefaultMediaSourceAndMirroring(
            web_contents());
    if (!Current(false)) {
      Close();
      return false;
    }
    ui_ = std::move(ui);
    std::weak_ptr<CastSession> weak = weak_from_this();
    ui_->RegisterDestructor(base::BindOnce(
        [](std::weak_ptr<CastSession> weak) {
          if (auto self = weak.lock())
            self->Close();
        },
        weak));
    auto close = ^(NSNotification*) {
      if (auto self = weak.lock())
        self->RequestClose();
    };
    for (NSNotificationName name in @[
           NSWindowWillCloseNotification, NSWindowWillMiniaturizeNotification,
           PCNativeWindowSecurityStateChanged
         ]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
                                    addObserverForName:name
                                                object:window_
                                                 queue:nil
                                            usingBlock:close]];
    }
    if (!Current(false)) {
      Close();
      return false;
    }
    auto dialog = std::make_unique<media_router::CastDialogView>(
        views::BubbleAnchor(), views::BubbleBorder::TOP_CENTER, this,
        profile_.get(), base::Time::Now(),
        media_router::MediaRouterDialogActivationLocation::TOOLBAR, nullptr);
    // The exact original native view supplies a true Cocoa parent. No
    // BrowserView or unrelated frontmost window is fabricated for a native
    // browser.
    dialog->set_parent_window(web_contents()->GetNativeView());
    gfx::Rect bounds = web_contents()->GetContainerBounds();
    bounds.set_height(0);
    dialog->SetAnchorRect(bounds);
    widget_ = views::BubbleDialogDelegateView::CreateBubble(std::move(dialog));
    widget_observation_.Observe(widget_);
    if (!Current(false) || !window_.keyWindow || !NSApp.active) {
      Close();
      return false;
    }
    widget_->Show();
    if (!widget_ || !widget_->IsVisible() || !Current(false)) {
      Close();
      return false;
    }
    return true;
  }
  void RequestClose() {
    if (closed_)
      return;
    closed_ = true;
    // Observers may run inside controller/view methods. Revoke actions now;
    // destroy the actual controller only after the active stack unwinds.
    RequestTearDown();
  }
  void RequestTearDown() {
    auto keep = shared_from_this();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](std::shared_ptr<CastSession> self) { self->TearDown(); },
            std::move(keep)));
  }
  void Close() {
    closed_ = true;
    if (!dispatch_depth_)
      TearDown();
  }
  void OnWidgetDestroying(views::Widget* widget) override {
    if (widget != widget_)
      return;
    widget_observation_.Reset();
    widget_ = nullptr;
    RequestClose();
  }
  void OnTabStripModelChanged(TabStripModel*,
                              const TabStripModelChange&,
                              const TabStripSelectionChange&) override {
    if (!Current(false))
      RequestClose();
  }
  void OnTabStripModelDestroyed(TabStripModel*) override {
    TabStripModelObserver::StopObservingAll(this);
    RequestClose();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    DetachService();
    profile_observation_.Reset();
    Close();
  }
  void OnServiceDisabled() override {
    // Shutdown may destroy the service before a posted close runs.
    DetachService();
    Close();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame() && !navigation->IsSameDocument())
      RequestClose();
  }
  void PrimaryPageChanged(content::Page&) override { RequestClose(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN)
      RequestClose();
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    RequestClose();
  }
  void WebContentsDestroyed() override { Close(); }

  void AddObserver(
      media_router::CastDialogController::Observer* observer) override {
    if (!ui_)
      return;
    auto keep = shared_from_this();
    ++dispatch_depth_;
    ui_->AddObserver(observer);
    --dispatch_depth_;
    if (closed_)
      RequestTearDown();
  }
  void RemoveObserver(
      media_router::CastDialogController::Observer* observer) override {
    if (ui_)
      ui_->RemoveObserver(observer);
  }
  void StartCasting(const media_router::MediaSink::Id& id,
                    media_router::MediaCastMode mode) override {
    Dispatch([&] { ui_->StartCasting(id, mode); });
  }
  void StopCasting(const media_router::MediaRoute::Id& id) override {
    Dispatch([&] { ui_->StopCasting(id); });
  }
  void ClearIssue(const media_router::Issue::Id& id) override {
    Dispatch([&] { ui_->ClearIssue(id); });
  }
  void FreezeRoute(const media_router::MediaRoute::Id& id) override {
    Dispatch([&] { ui_->FreezeRoute(id); });
  }
  void UnfreezeRoute(const media_router::MediaRoute::Id& id) override {
    Dispatch([&] { ui_->UnfreezeRoute(id); });
  }
  std::unique_ptr<media_router::MediaRouteStarter> TakeMediaRouteStarter()
      override {
    std::unique_ptr<media_router::MediaRouteStarter> starter;
    Dispatch([&] { starter = ui_->TakeMediaRouteStarter(); });
    return starter;
  }
  bool HasActiveDispatchOrTeardown() const {
    return dispatch_depth_ || tearing_down_;
  }
  void RegisterDestructor(base::OnceClosure destructor) override {
    CHECK(!destructor_);
    destructor_ = std::move(destructor);
  }

 private:
  bool Current(bool interaction) const {
    auto* contents = web_contents();
    if (closed_ || !contents || !browser_ || !profile_ || !window_ ||
        Owner(contents) != browser_.get() ||
        AppKitBindingForBrowser(browser_.get()).window != window_ ||
        contents->GetBrowserContext() != profile_.get() ||
        document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame())
      return false;
    NSWindow* dialog =
        widget_ ? widget_->GetNativeWindow().GetNativeNSWindow() : nil;
    return !interaction ||
           (NSApp.active && (window_.keyWindow || dialog.keyWindow));
  }
  template <typename F>
  void Dispatch(F action) {
    auto keep = shared_from_this();
    if (!ui_ || !Current(true)) {
      RequestClose();
      return;
    }
    ++dispatch_depth_;
    action();
    --dispatch_depth_;
    if (closed_)
      TearDown();
  }
  void DetachService() {
    if (service_) {
      service_->RemoveObserver(this);
      service_ = nullptr;
    }
  }
  void TearDown() {
    if (dispatch_depth_ || tearing_down_)
      return;
    tearing_down_ = true;
    closed_ = true;
    for (id token in notifications_)
      [NSNotificationCenter.defaultCenter removeObserver:token];
    [notifications_ removeAllObjects];
    widget_observation_.Reset();
    TabStripModelObserver::StopObservingAll(this);
    auto* widget = widget_.get();
    widget_ = nullptr;
    if (widget)
      widget->Close();
    // Notifies the genuine view that its controller is gone before its async
    // destruction; closing discovery does not terminate an established route.
    ui_.reset();
    DetachService();
    profile_observation_.Reset();
    fullscreen_blocker_.RunAndReset();
    Observe(nullptr);
    if (destructor_)
      std::move(destructor_).Run();
    tearing_down_ = false;
  }
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr document_;
  __weak NSWindow* window_ = nil;
  NSMutableArray* notifications_ = [[NSMutableArray alloc] init];
  std::unique_ptr<media_router::MediaRouterUI> ui_;
  raw_ptr<media_router::MediaRouterUIService> service_ = nullptr;
  raw_ptr<views::Widget> widget_ = nullptr;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::ScopedObservation<views::Widget, views::WidgetObserver>
      widget_observation_{this};
  base::ScopedClosureRunner fullscreen_blocker_;
  base::OnceClosure destructor_;
  unsigned dispatch_depth_ = 0;
  bool closed_ = false;
  bool tearing_down_ = false;
};
class CastOwner final : public content::WebContentsUserData<CastOwner> {
 public:
  ~CastOwner() override {
    auto session = std::move(session_);
    if (session)
      session->Close();
  }
  bool Close() {
    auto session = session_;
    if (session) {
      session->Close();
      return !session->HasActiveDispatchOrTeardown();
    }
    return true;
  }
  bool Show(content::WebContents* contents, BrowserWindowInterface& browser) {
    auto weak_contents = contents->GetWeakPtr();
    auto weak_browser = browser.GetWeakPtr();
    auto previous = session_;
    if (previous)
      previous->Close();
    if (!weak_contents || !weak_browser ||
        CastOwner::FromWebContents(weak_contents.get()) != this ||
        session_ != previous ||
        (previous && previous->HasActiveDispatchOrTeardown()) ||
        Owner(weak_contents.get()) != weak_browser.get())
      return false;
    auto session = std::make_shared<CastSession>(weak_contents.get(), *weak_browser);
    session_ = session;
    const bool shown = session->Show();
    if (!shown)
      session->Close();
    return shown;
  }

 private:
  friend class content::WebContentsUserData<CastOwner>;
  explicit CastOwner(content::WebContents* contents)
      : content::WebContentsUserData<CastOwner>(*contents) {}
  std::shared_ptr<CastSession> session_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(CastOwner);
}  // namespace
bool CloseNativeCastForPage(content::WebContents* contents) {
  if (contents) {
    if (auto* owner = CastOwner::FromWebContents(contents))
      return owner->Close();
  }
  return true;
}
bool CanShowNativeCast(content::WebContents* contents) {
  auto* browser = Owner(contents);
  // Read-only eligibility is also used by the original window's command bar.
  // Creating discovery or UI still requires that exact parent to be key.
  return browser && NSApp.active;
}
bool ShowNativeCast(content::WebContents* contents) {
  if (!CanShowNativeCast(contents))
    return false;
  auto weak_contents = contents->GetWeakPtr();
  auto* browser = Owner(contents);
  auto weak_browser = browser ? browser->GetWeakPtr() : nullptr;
  if (!weak_browser || !AppKitBindingForBrowser(browser).window.keyWindow)
    return false;
  const bool closed_gmc = CloseNativeGmcPresentationForPage(contents);
  if (!closed_gmc || !weak_contents || !weak_browser || Owner(weak_contents.get()) != weak_browser.get() ||
      !NSApp.active || !AppKitBindingForBrowser(weak_browser.get()).window.keyWindow)
    return false;
  CastOwner::CreateForWebContents(weak_contents.get());
  return CastOwner::FromWebContents(weak_contents.get())->Show(weak_contents.get(),
                                                               *weak_browser);
}
}  // namespace parc

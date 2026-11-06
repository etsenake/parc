// Copyright 2026 Parc contributors.
#include "native_gmc_presentation.h"
#import <AppKit/AppKit.h>
#include <memory>
#include <utility>
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/unguessable_token.h"
#include "chrome/browser/media/router/media_router_feature.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/global_media_controls/media_notification_service.h"
#include "chrome/browser/ui/global_media_controls/media_notification_service_factory.h"
#include "chrome/browser/ui/media_router/media_router_ui_service.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/views/global_media_controls/media_dialog_view.h"
#include "chrome/browser/ui/views/media_router/media_router_dialog_controller_views.h"
#include "components/media_router/browser/media_router.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/media_router/common/media_route.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "native_appkit_host.h"
#include "native_appkit_page.h"
#include "native_cast.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "third_party/blink/public/mojom/presentation/presentation.mojom.h"
#include "ui/display/types/display_constants.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
BrowserWindowInterface* Owner(content::WebContents* contents) {
  PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
  auto* browser = contents
      ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents)
      : nullptr;
  auto* profile = contents
      ? Profile::FromBrowserContext(contents->GetBrowserContext()) : nullptr;
  PCNativeBrowserWindow* binding = browser ? AppKitBindingForBrowser(browser) : nil;
  NSWindow* window = binding.window;
  if (!page || page.closed || !browser || !profile || profile->ShutdownStarted() ||
      browser->IsDeleteScheduled() || browser->GetProfile() != profile ||
      browser->GetTabStripModel()->GetActiveWebContents() != contents ||
      !chrome::CanRouteMedia(browser) || !AppKitBrowserAcceptsNewPages(*browser) ||
      IsNativePageRetiring(page) || IsLiveTabTransferTarget(contents) ||
      IsNativeProfileRemovalBlocked(profile->GetPath()) || !binding.client ||
      !window || page.nativeView.window != window ||
      page.nativeView.hiddenOrHasHiddenAncestor ||
      [binding.client selectedNativePage] != page || contents->IsBeingDestroyed() ||
      contents->IsCrashed() || !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
      contents->GetVisibility() == content::Visibility::HIDDEN ||
      !window.visible || window.miniaturized || window.attachedSheet ||
      PCNativeWindowHasSecurityReservation(window))
    return nullptr;
  return browser;
}

class NativePresentationSession;
std::weak_ptr<NativePresentationSession>& ActiveSession() {
  static base::NoDestructor<std::weak_ptr<NativePresentationSession>> active;
  return *active;
}

class NativePresentationSession final
    : public std::enable_shared_from_this<NativePresentationSession>,
      public content::WebContentsObserver,
      public ProfileObserver,
      public media_router::MediaRouterUIService::Observer,
      public views::WidgetObserver,
      public TabStripModelObserver {
 public:
  NativePresentationSession(
      content::WebContents* contents, BrowserWindowInterface& browser,
      std::unique_ptr<media_router::StartPresentationContext> context)
      : content::WebContentsObserver(contents),
        browser_(browser.GetWeakPtr()),
        profile_(browser.GetProfile()->GetWeakPtr()),
        main_document_(contents->GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        window_(AppKitBindingForBrowser(&browser).window),
        context_(std::move(context)), token_(base::UnguessableToken::Create()) {
    auto* frame = content::RenderFrameHost::FromID(
        context_->presentation_request().render_frame_host_id);
    if (frame && content::WebContents::FromRenderFrameHost(frame) == contents)
      request_document_ = frame->GetWeakDocumentPtr();
  }
  ~NativePresentationSession() override { Close(); }

  bool Show() {
    auto keep = shared_from_this();
    if (!Current(true))
      return false;
    auto blocker = web_contents()->ForSecurityDropFullscreen(display::kInvalidDisplayId);
    if (!blocker || !Current(true))
      return false;
    fullscreen_blocker_ = std::move(*blocker);
    profile_observation_.Observe(profile_.get());
    browser_->GetTabStripModel()->AddObserver(this);
    router_service_ = media_router::MediaRouterUIService::Get(profile_.get());
    if (!router_service_) {
      Close();
      return false;
    }
    router_service_->AddObserver(this);
    auto* service = MediaNotificationServiceFactory::GetForProfile(profile_.get());
    if (!service || !Current(true)) {
      Close();
      return false;
    }
    service_ = service->GetWeakPtrForNative();
    // Close the old singleton before resetting its observer pipe. Any queued
    // untagged notifications then remain attached to the discarded pipe.
    MediaDialogView::HideDialog();
    if (!Current(true) || !service_ || MediaDialogView::IsShowing()) {
      Close();
      return false;
    }
    auto weak = weak_from_this();
    auto guard = base::BindRepeating([](std::weak_ptr<NativePresentationSession> weak) {
      auto self = weak.lock();
      return self && self->Current(true);
    }, weak);
    context_->SetNativeSuccessValidator(
        base::BindRepeating(
            [](base::WeakPtr<content::WebContents> contents,
               content::WeakDocumentPtr main_document,
               content::WeakDocumentPtr request_document,
               base::WeakPtr<Profile> profile) {
              auto* frame = request_document.AsRenderFrameHostIfValid();
              return contents && !contents->IsBeingDestroyed() && profile &&
                     !profile->ShutdownStarted() && frame && frame->IsActive() &&
                     main_document.AsRenderFrameHostIfValid() ==
                         contents->GetPrimaryMainFrame() &&
                     content::WebContents::FromRenderFrameHost(frame) == contents.get() &&
                     contents->GetBrowserContext() == profile.get();
            }, web_contents()->GetWeakPtr(), main_document_, request_document_, profile_),
        base::BindOnce([](base::WeakPtr<Profile> profile,
                          const media_router::MediaRoute& route) {
          if (!profile || profile->ShutdownStarted() || route.is_local_presentation())
            return;
          auto* router = media_router::MediaRouterFactory::GetApiForBrowserContextIfExists(
              profile.get());
          if (router)
            router->DetachRoute(route.media_route_id());
        }, profile_));
    auto close = ^(NSNotification*) {
      if (auto self = weak.lock())
        self->RequestClose();
    };
    for (NSNotificationName name in @[
           NSWindowWillCloseNotification, NSWindowWillMiniaturizeNotification,
           PCNativeWindowSecurityStateChanged
         ]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
                                    addObserverForName:name object:window_
                                                 queue:nil usingBlock:close]];
    }
    if (!Current(true) || !service_ ||
        !service_->BeginNativePresentation(token_, std::move(context_), guard,
            base::BindOnce([](std::weak_ptr<NativePresentationSession> weak) {
              if (auto self = weak.lock())
                self->RequestClose();
            }, weak))) {
      Close();
      return false;
    }
    if (!Current(true) || !service_ ||
        !service_->WaitForNativePreparation(token_, base::BindOnce(
            [](std::weak_ptr<NativePresentationSession> weak) {
              if (auto self = weak.lock())
                self->ShowPreparedDialog();
            }, weak))) {
      Close();
      return false;
    }
    return true;
  }

  bool Busy() const { return tearing_down_; }
  bool IsFor(content::WebContents* contents) const {
    return web_contents() == contents;
  }
  void RequestClose() {
    auto keep = shared_from_this();
    Close();
  }
  void Close() {
    if (closed_ || tearing_down_)
      return;
    closed_ = true;
    tearing_down_ = true;
    for (id token in notifications_)
      [NSNotificationCenter.defaultCenter removeObserver:token];
    [notifications_ removeAllObjects];
    widget_observation_.Reset();
    TabStripModelObserver::StopObservingAll(this);
    auto* widget = widget_.get();
    widget_ = nullptr;
    if (widget)
      MediaDialogView::CloseNativeDialog(widget);
    if (service_)
      service_->CancelNativePresentation(token_);
    auto pending = std::move(context_);
    if (pending)
      pending->InvokeErrorCallback(blink::mojom::PresentationError(
          blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
          "Dialog closed."));
    DetachRouterService();
    profile_observation_.Reset();
    fullscreen_blocker_.RunAndReset();
    Observe(nullptr);
    tearing_down_ = false;
  }

  void OnWidgetDestroying(views::Widget* widget) override {
    if (widget != widget_)
      return;
    auto keep = shared_from_this();
    widget_observation_.Reset();
    widget_ = nullptr;
    // Widget observers run before the view's WindowClosing callback. Detach
    // this exact singleton while its service is alive, without closing a
    // widget that is already being destroyed.
    MediaDialogView::ForgetNativeDialogForDestroying(widget);
    Close();
  }
  void OnTabStripModelChanged(TabStripModel*, const TabStripModelChange&,
                              const TabStripSelectionChange&) override {
    if (!Current(false))
      RequestClose();
  }
  void OnTabStripModelDestroyed(TabStripModel*) override {
    TabStripModelObserver::StopObservingAll(this);
    RequestClose();
  }
  void OnProfileWillBeDestroyed(Profile*) override {
    DetachRouterService();
    profile_observation_.Reset();
    RequestClose();
  }
  void OnServiceDisabled() override {
    DetachRouterService();
    RequestClose();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsSameDocument())
      return;
    auto* frame = request_document_.AsRenderFrameHostIfValid();
    if (navigation->IsInPrimaryMainFrame() ||
        (frame && navigation->GetFrameTreeNodeId() == frame->GetFrameTreeNodeId()))
      RequestClose();
  }
  void DidFinishNavigation(content::NavigationHandle*) override {
    if (!RequestCurrent())
      RequestClose();
  }
  void PrimaryPageChanged(content::Page&) override { RequestClose(); }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (frame == request_document_.AsRenderFrameHostIfValid() || !RequestCurrent())
      RequestClose();
  }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN)
      RequestClose();
  }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override {
    RequestClose();
  }
  void WebContentsDestroyed() override { RequestClose(); }

 private:
  bool RequestCurrent() const {
    auto* frame = request_document_.AsRenderFrameHostIfValid();
    return frame && frame->IsActive() && web_contents() &&
           content::WebContents::FromRenderFrameHost(frame) == web_contents();
  }
  bool Current(bool interaction) const {
    auto* contents = web_contents();
    if (closed_ || !contents || !browser_ || !profile_ || !window_ ||
        Owner(contents) != browser_.get() ||
        AppKitBindingForBrowser(browser_.get()).window != window_ ||
        contents->GetBrowserContext() != profile_.get() ||
        main_document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
        !RequestCurrent())
      return false;
    if (!interaction)
      return true;
    if (!NSApp.active)
      return false;
    if (!widget_)
      return window_.keyWindow;
    if (!MediaDialogView::IsNativeDialogCurrent(widget_))
      return false;
    NSWindow* dialog = widget_->GetNativeWindow().GetNativeNSWindow();
    return window_.keyWindow || dialog.keyWindow;
  }
  void ShowPreparedDialog() {
    auto keep = shared_from_this();
    if (!Current(true) || !service_ || !service_->HasNativePresentation(token_)) {
      Close();
      return;
    }
    auto weak = weak_from_this();
    auto guard = base::BindRepeating([](std::weak_ptr<NativePresentationSession> weak) {
      auto self = weak.lock();
      return self && self->Current(true);
    }, weak);
    gfx::Rect bounds = web_contents()->GetContainerBounds();
    bounds.set_height(0);
    auto* widget = MediaDialogView::CreateDialogForNativePage(
        web_contents()->GetNativeView(), bounds, service_.get(), profile_.get(),
        web_contents(), token_, std::move(guard));
    if (!widget || !Current(true) || !MediaDialogView::IsNativeDialogCurrent(widget)) {
      if (widget)
        MediaDialogView::CloseNativeDialog(widget);
      Close();
      return;
    }
    widget_ = widget;
    widget_observation_.Observe(widget_);
    widget_->Show();
    if (!widget_ || !widget_->IsVisible() || !Current(true))
      Close();
  }
  void DetachRouterService() {
    if (router_service_) {
      router_service_->RemoveObserver(this);
      router_service_ = nullptr;
    }
  }
  base::WeakPtr<BrowserWindowInterface> browser_;
  base::WeakPtr<Profile> profile_;
  content::WeakDocumentPtr main_document_;
  content::WeakDocumentPtr request_document_;
  __weak NSWindow* window_ = nil;
  std::unique_ptr<media_router::StartPresentationContext> context_;
  const base::UnguessableToken token_;
  base::WeakPtr<MediaNotificationService> service_;
  raw_ptr<media_router::MediaRouterUIService> router_service_ = nullptr;
  raw_ptr<views::Widget> widget_ = nullptr;
  NSMutableArray* notifications_ = [[NSMutableArray alloc] init];
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::ScopedObservation<views::Widget, views::WidgetObserver> widget_observation_{this};
  base::ScopedClosureRunner fullscreen_blocker_;
  bool closed_ = false;
  bool tearing_down_ = false;
};

class NativePresentationOwner final
    : public content::WebContentsUserData<NativePresentationOwner> {
 public:
  ~NativePresentationOwner() override {
    auto session = std::move(session_);
    if (session)
      session->Close();
  }
  bool Show(content::WebContents* contents, BrowserWindowInterface& browser,
            std::unique_ptr<media_router::StartPresentationContext> context) {
    auto weak_contents = contents->GetWeakPtr();
    auto weak_browser = browser.GetWeakPtr();
    auto previous = ActiveSession().lock();
    if (previous)
      previous->Close();
    if (!weak_contents || !weak_browser ||
        NativePresentationOwner::FromWebContents(weak_contents.get()) != this ||
        (previous && previous->Busy()) ||
        (ActiveSession().lock() && ActiveSession().lock() != previous) ||
        Owner(weak_contents.get()) != weak_browser.get()) {
      context->InvokeErrorCallback(blink::mojom::PresentationError(
          blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
          "The requesting page is no longer available."));
      return false;
    }
    auto session = std::make_shared<NativePresentationSession>(
        weak_contents.get(), *weak_browser, std::move(context));
    session_ = session;
    ActiveSession() = session;
    const bool shown = session->Show();
    if (!shown)
      session->Close();
    return shown;
  }
 private:
  friend class content::WebContentsUserData<NativePresentationOwner>;
  explicit NativePresentationOwner(content::WebContents* contents)
      : content::WebContentsUserData<NativePresentationOwner>(*contents) {}
  std::shared_ptr<NativePresentationSession> session_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(NativePresentationOwner);

bool MaybeShowNativePresentation(
    content::WebContents* contents,
    std::unique_ptr<media_router::StartPresentationContext>& context) {
  if (!contents || !ExistingNativePage(contents))
    return false;
  auto* browser = Owner(contents);
  if (!browser || !NSApp.active || !AppKitBindingForBrowser(browser).window.keyWindow) {
    auto rejected = std::move(context);
    rejected->InvokeErrorCallback(blink::mojom::PresentationError(
        blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
        "The requesting page is no longer available."));
    return true;
  }
  auto weak_contents = contents->GetWeakPtr();
  auto weak_browser = browser->GetWeakPtr();
  const bool closed_cast = CloseNativeCastForPage(contents);
  if (!closed_cast || !weak_contents || !weak_browser ||
      Owner(weak_contents.get()) != weak_browser.get() || !NSApp.active ||
      !AppKitBindingForBrowser(weak_browser.get()).window.keyWindow) {
    auto rejected = std::move(context);
    rejected->InvokeErrorCallback(blink::mojom::PresentationError(
        blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
        "The requesting page is no longer available."));
    return true;
  }
  NativePresentationOwner::CreateForWebContents(weak_contents.get());
  NativePresentationOwner::FromWebContents(weak_contents.get())->Show(
      weak_contents.get(), *weak_browser, std::move(context));
  return true;
}
}  // namespace
bool CloseNativeGmcPresentationForPage(content::WebContents* contents) {
  auto session = ActiveSession().lock();
  if (session && session->IsFor(contents)) {
    session->RequestClose();
    return !session->Busy();
  }
  return true;
}
void InstallNativeGmcPresentationHandler() {
  media_router::MediaRouterDialogControllerViews::SetNativePresentationHandler(
      base::BindRepeating(&MaybeShowNativePresentation));
}
}  // namespace parc

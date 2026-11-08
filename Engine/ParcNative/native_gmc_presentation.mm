// Copyright 2026 Parc contributors.
#include "native_gmc_presentation.h"
#import <AppKit/AppKit.h>
#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "base/strings/utf_string_conversions.h"
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
#include "chrome/grit/generated_resources.h"
#include "components/global_media_controls/public/media_item_manager.h"
#include "components/global_media_controls/public/media_item_manager_observer.h"
#include "components/media_router/browser/media_router.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/media_routes_observer.h"
#include "components/media_router/browser/media_sinks_observer.h"
#include "components/media_router/browser/presentation/web_contents_presentation_manager.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/media_router/common/media_route.h"
#include "components/media_router/common/media_source.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/presentation_observer.h"
#include "content/public/browser/presentation_request.h"
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
#include "media/base/audio_codecs.h"
#include "media/base/media_switches.h"
#include "media/base/remoting_constants.h"
#include "media/base/video_codecs.h"
#include "media/remoting/device_capability_checker.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "third_party/blink/public/mojom/presentation/presentation.mojom.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/l10n/l10n_util_mac.h"
#include "ui/display/types/display_constants.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"
#import "window_security_reservation.h"

@interface PCNativeCastMenuTarget : NSObject
@property(nonatomic, readonly) NSInteger chosen;
- (void)choose:(NSMenuItem*)sender;
@end
@implementation PCNativeCastMenuTarget
@synthesize chosen = _chosen;
- (void)choose:(NSMenuItem*)sender {
  _chosen = sender.tag;
}
@end

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

// Safari-identity pages AirPlay instead (native_airplay.h).
bool CastsAsChrome(content::WebContents* contents) {
  PCNativePage* page = ExistingNativePage(contents);
  return page && !page.closed && !page.usesSafariIdentity;
}

// The remote playback source Chrome's media controls cast |contents|' media
// session with (MediaSessionNotificationItem::GetRemotePlaybackMetadata and
// MediaNotificationService's ShouldInitializeWithRemotePlaybackSource): one
// player whose page allows Remote Playback, unencrypted (no FairPlay or
// Widevine), longer than 15 seconds, with codecs a receiver can be asked for,
// and no default presentation request, which Chromium would cast instead.
std::optional<media_router::MediaSource> CastSource(content::WebContents* contents) {
  auto* session = content::MediaSession::GetIfExists(contents);
  if (!CastsAsChrome(contents) || !session ||
      !base::FeatureList::IsEnabled(media::kMediaRemotingWithoutFullscreen))
    return std::nullopt;
  const auto info = session->GetMediaSessionInfoSync();
  if (!info || !info->remote_playback_metadata)
    return std::nullopt;
  const auto& metadata = info->remote_playback_metadata;
  const auto position = session->GetMediaSessionPosition();
  if (metadata->remote_playback_disabled || metadata->is_encrypted_media ||
      (position && position->duration() <=
                       base::Seconds(media::remoting::kMinRemotingMediaDurationInSec)))
    return std::nullopt;
  const auto video = media::remoting::ParseVideoCodec(metadata->video_codec);
  const auto audio = media::remoting::ParseAudioCodec(metadata->audio_codec);
  auto presentation = media_router::WebContentsPresentationManager::Get(contents);
  if (video == media::VideoCodec::kUnknown || audio == media::AudioCodec::kUnknown ||
      (presentation && presentation->HasDefaultPresentationRequest()))
    return std::nullopt;
  return media_router::MediaSource::ForRemotePlayback(
      sessions::SessionTabHelper::IdForTab(contents).id(), video, audio);
}

// Watches the receivers for |contents|' cast and the route casting it
// (MediaNotificationService::ParcCastRouteForWebContents()). A page with a
// default presentation request casts it, as Chrome's media controls and
// toolbar do (CreateWithDefaultMediaSource()), so the site's own receiver app
// plays; any other page casts its session's remote playback source.
class MediaCastWatcher final
    : public content::WebContentsUserData<MediaCastWatcher>,
      public content::PresentationObserver,
      public global_media_controls::MediaItemManagerObserver {
 public:
  ~MediaCastWatcher() override {
    if (presentations_)
      presentations_->RemoveObserver(this);
  }
  // Whether the tab's cast plays from a page the tab has since left.
  bool CastsFromEarlierPage() {
    State();
    return earlier_page_;
  }
  NativeMediaCastState State() {
    earlier_page_ = false;
    Update();
    if (!routes_)
      return {};
    // The tab's route shows on any page, as a cast carries on from a cached
    // Chrome-identity page after the tab moves to a Safari-identity one.
    const auto route = MediaNotificationService::ParcCastRouteForWebContents(
        &GetWebContents(), routes_->router()->GetCurrentRoutes());
    if (route) {
      bool started = !route->is_connecting();
      if (route->media_source().IsRemotePlaybackSource()) {
        auto* frame = GetWebContents().GetPrimaryMainFrame();
        if (route_ != route->media_route_id()) {
          route_ = route->media_route_id();
          route_document_ = frame->GetWeakDocumentPtr();
          route_started_ = false;
          route_reported_ = false;
        }
        // Only the casting page's player reports the route, and a session
        // that dropped it keeps the last report. Once that page has left, or
        // if its player never reported, the route's own state shows.
        auto* session = content::MediaSession::GetIfExists(&GetWebContents());
        const auto info = session ? session->GetMediaSessionInfoSync() : nullptr;
        const bool casting_page = route_document_.AsRenderFrameHostIfValid() == frame;
        if (casting_page && info && info->remote_playback_metadata) {
          route_started_ = info->remote_playback_metadata->remote_playback_started;
          route_reported_ = true;
        }
        started = (casting_page && route_reported_) ? route_started_ : (route_started_ || started);
        earlier_page_ = !casting_page;
      }
      return {static_cast<int>(started ? PCNativeCastStateConnected : PCNativeCastStateConnecting),
              route->media_sink_name()};
    }
    if (!CastsAsChrome(&GetWebContents()))
      return {};
    // Only with media for the chooser's dialog to show, listed now or frozen
    // until the media controls list it again (MediaCastChooser::Show()).
    auto* service = items_.IsObserving() ? Service() : nullptr;
    const bool available =
        service &&
        (service->HasActiveNotificationsForWebContents(&GetWebContents()) ||
         service->ParcHasFrozenSessionForWebContents(&GetWebContents())) &&
        std::ranges::any_of(sinks_, [](const auto& sinks) { return sinks->available(); });
    return {static_cast<int>(available ? PCNativeCastStateAvailable
                                       : PCNativeCastStateUnavailable), {}};
  }

 private:
  friend class content::WebContentsUserData<MediaCastWatcher>;
  class Sinks final : public media_router::MediaSinksObserver {
   public:
    Sinks(media_router::MediaRouter* router, const media_router::MediaSource& source,
          const url::Origin& origin, MediaCastWatcher* owner)
        : MediaSinksObserver(router, source, origin), owner_(owner) {}
    bool available() const { return available_; }
   private:
    void OnSinksReceived(const std::vector<media_router::MediaSink>& sinks) override {
      available_ = !sinks.empty();
      NativeMediaCastChanged(&owner_->GetWebContents());
    }
    const raw_ptr<MediaCastWatcher> owner_;
    bool available_ = false;
  };
  class Routes final : public media_router::MediaRoutesObserver {
   public:
    Routes(media_router::MediaRouter* router, MediaCastWatcher* owner)
        : MediaRoutesObserver(router), owner_(owner) {}
    void OnRoutesUpdated(const std::vector<media_router::MediaRoute>&) override {
      NativeMediaCastChanged(&owner_->GetWebContents());
    }
   private:
    const raw_ptr<MediaCastWatcher> owner_;
  };

  explicit MediaCastWatcher(content::WebContents* contents)
      : content::WebContentsUserData<MediaCastWatcher>(*contents) {}
  void OnPresentationsChanged(bool) override {
    NativeMediaCastChanged(&GetWebContents());
  }
  void OnDefaultPresentationChanged(const content::PresentationRequest*) override {
    NativeMediaCastChanged(&GetWebContents());
  }
  void OnItemListChanged() override { NativeMediaCastChanged(&GetWebContents()); }
  void OnMediaDialogOpened() override {}
  void OnMediaDialogClosed() override {}
  MediaNotificationService* Service() {
    auto* profile = Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
    return profile && !profile->ShutdownStarted()
        ? MediaNotificationServiceFactory::GetForProfile(profile) : nullptr;
  }
  // Never from a router callback: it adds and removes router observers.
  void Update() {
    auto* contents = &GetWebContents();
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    auto* router = profile && !profile->ShutdownStarted() &&
                           media_router::MediaRouterEnabled(profile)
        ? media_router::MediaRouterFactory::GetApiForBrowserContextIfExists(profile)
        : nullptr;
    if (!routes_ || routes_->router() != router) {
      sinks_.clear();
      sources_.clear();
      routes_.reset();
      if (!router)
        return;
      routes_ = std::make_unique<Routes>(router, this);
    }
    if (!CastsAsChrome(contents)) {
      sinks_.clear();
      sources_.clear();
      items_.Reset();
      return;
    }
    if (auto* service = Service(); !service)
      items_.Reset();
    else if (!items_.IsObserving())
      items_.Observe(service->media_item_manager());
    // Only with a router: the presentation manager creates its own.
    if (!presentations_) {
      presentations_ = media_router::WebContentsPresentationManager::Get(contents);
      if (presentations_)
        presentations_->AddObserver(this);
    }
    std::vector<media_router::MediaSource> sources;
    url::Origin origin;
    if (presentations_ && presentations_->HasDefaultPresentationRequest()) {
      const auto& request = presentations_->GetDefaultPresentationRequest();
      for (const auto& url : request.presentation_urls)
        sources.push_back(media_router::MediaSource::ForPresentationUrl(url));
      origin = request.frame_origin;
    } else if (const auto source = CastSource(contents)) {
      sources.push_back(*source);
      origin = contents->GetPrimaryMainFrame()->GetLastCommittedOrigin();
    }
    if (sources == sources_ && origin == origin_)
      return;
    sinks_.clear();
    sources_ = sources;
    origin_ = origin;
    for (const auto& source : sources_) {
      sinks_.push_back(std::make_unique<Sinks>(router, source, origin_, this));
      sinks_.back()->Init();
    }
  }
  base::WeakPtr<media_router::WebContentsPresentationManager> presentations_;
  std::unique_ptr<Routes> routes_;
  std::vector<media_router::MediaSource> sources_;
  url::Origin origin_;
  std::vector<std::unique_ptr<Sinks>> sinks_;
  base::ScopedObservation<global_media_controls::MediaItemManager,
                          global_media_controls::MediaItemManagerObserver>
      items_{this};
  std::string route_;
  content::WeakDocumentPtr route_document_;
  bool route_started_ = false;
  bool route_reported_ = false;
  bool earlier_page_ = false;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(MediaCastWatcher);

// The Mini Player's chooser: Chromium's media controls dialog for one page's
// media session, at the row's Cast button in the presenting window, which may
// show another tab. The session's device list starts the page's default
// presentation, or with none Chromium's media session remote playback
// (CreateCastDialogControllerForSession, then OnMediaRemotingRequested), and
// a casting page shows "Stop casting".
class MediaCastChooser final : public content::WebContentsObserver,
                               public views::WidgetObserver,
                               public global_media_controls::MediaItemManagerObserver {
 public:
  MediaCastChooser(content::WebContents* contents, NSWindow* host,
                   base::RepeatingCallback<bool()> valid, void (^dismissed)(void))
      : content::WebContentsObserver(contents), host_(host),
        valid_(std::move(valid)), pending_dismissed_(dismissed) {}
  ~MediaCastChooser() override { Close(); }

  bool Show(NSView* view, NSRect rect) {
    if (!Current())
      return Fail();
    return Open(view, rect);
  }
  bool Open(NSView* view, NSRect rect) {
    auto* contents = web_contents();
    auto* service = Service();
    const bool dialog = CastsAsChrome(contents) && service &&
                        service->HasActiveNotificationsForWebContents(contents);
    MediaCastWatcher::CreateForWebContents(contents);
    if (dialog && !MediaCastWatcher::FromWebContents(contents)->CastsFromEarlierPage())
      return ShowDialog(view, rect);
    if (!dialog && CastsAsChrome(contents) && service && !Route() &&
        service->ParcHasFrozenSessionForWebContents(contents))
      return WaitForItem(view, rect);
    return OfferStopCasting(view, rect, dialog);
  }
  // The media controls hold a session that lost audio focus, as when its
  // player is replaced, frozen and unlisted for up to 2.5 seconds
  // (MediaSessionNotificationItem's kFreezeTimerDelay); the dialog opens
  // once they list it again.
  bool WaitForItem(NSView* view, NSRect rect) {
    waiting_view_ = view;
    waiting_rect_ = rect;
    dismissed_ = std::exchange(pending_dismissed_, nil);
    WatchHost();
    items_.Observe(Service()->media_item_manager());
    // A cast that starts meanwhile offers Stop casting instead.
    if (auto* router = Router())
      routes_ = std::make_unique<Routes>(router, this);
    wait_.Start(FROM_HERE, base::Seconds(3),
                base::BindOnce(base::IgnoreResult(&MediaCastChooser::Fail), base::Unretained(this)));
    return true;
  }
  class Routes final : public media_router::MediaRoutesObserver {
   public:
    Routes(media_router::MediaRouter* router, MediaCastChooser* owner)
        : MediaRoutesObserver(router), owner_(owner) {}
    void OnRoutesUpdated(const std::vector<media_router::MediaRoute>&) override {
      owner_->OnItemListChanged();
    }
   private:
    const raw_ptr<MediaCastChooser> owner_;
  };
  // Not within the manager's or router's notification: opening registers
  // with them.
  void OnItemListChanged() override {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&MediaCastChooser::ItemsChanged, weak_factory_.GetWeakPtr()));
  }
  void OnMediaDialogOpened() override {}
  void OnMediaDialogClosed() override {}
  void ItemsChanged() {
    if (!items_.IsObserving())
      return;
    auto* service = Service();
    NSView* view = waiting_view_;
    if (!Current() || !service || !view || view.window != host_) {
      Fail();
    } else if (service->HasActiveNotificationsForWebContents(web_contents()) || Route()) {
      items_.Reset();
      routes_.reset();
      wait_.Stop();
      Open(view, waiting_rect_);
    } else if (!service->ParcHasFrozenSessionForWebContents(web_contents())) {
      Fail();
    }
  }
  bool ShowDialog(NSView* view, NSRect rect) {
    auto* contents = web_contents();
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    auto* service = Service();
    if (!service || !service->HasActiveNotificationsForWebContents(contents))
      return Fail();
    WatchHost();
    auto weak = weak_factory_.GetWeakPtr();
    const NSRect screen = [view.window convertRectToScreen:[view convertRect:rect toView:nil]];
    auto* widget = MediaDialogView::CreateDialogForNativePage(
        gfx::NativeView(view), gfx::ScreenRectFromNSRect(screen), service, profile,
        contents, base::UnguessableToken(),
        base::BindRepeating([](base::WeakPtr<MediaCastChooser> self) {
          return self && self->Current();
        }, weak));
    if (!weak || !widget || !MediaDialogView::IsNativeDialogCurrent(widget)) {
      if (widget)
        MediaDialogView::CloseNativeDialog(widget);
      return weak ? Fail() : false;
    }
    widget_ = widget;
    widget_observation_.Observe(widget_);
    widget_->Show();
    if (!weak || !widget_ || !widget_->IsVisible())
      return weak ? Fail() : false;
    // Opened from the menu, which already holds it.
    if (!dismissed_)
      dismissed_ = std::exchange(pending_dismissed_, nil);
    return true;
  }
  bool IsFor(content::WebContents* contents) const { return web_contents() == contents; }
  void Close() {
    if (closed_)
      return;
    closed_ = true;
    items_.Reset();
    routes_.reset();
    wait_.Stop();
    for (id token in notifications_)
      [NSNotificationCenter.defaultCenter removeObserver:token];
    [notifications_ removeAllObjects];
    widget_observation_.Reset();
    [std::exchange(menu_, nil) cancelTracking];
    views::Widget* widget = widget_;
    widget_ = nullptr;
    if (widget)
      MediaDialogView::CloseNativeDialog(widget);
    Observe(nullptr);
    if (auto dismissed = std::exchange(dismissed_, nil))
      dismissed();
  }

  void OnWidgetDestroying(views::Widget* widget) override {
    if (widget != widget_)
      return;
    widget_observation_.Reset();
    widget_ = nullptr;
    MediaDialogView::ForgetNativeDialogForDestroying(widget);
    Close();
  }
  void PrimaryPageChanged(content::Page&) override { Close(); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { Close(); }
  void WebContentsDestroyed() override { Close(); }

 private:
  bool Current() const {
    if (closed_ || !web_contents() || !host_ || !host_.visible || host_.miniaturized ||
        !NSApp.active || !valid_.Run())
      return false;
    return host_.keyWindow ||
           (widget_ && widget_->GetNativeWindow().GetNativeNSWindow().keyWindow);
  }
  bool Fail() {
    Close();
    return false;
  }
  // Closing, hiding or securing the host window ends the chooser at once.
  void WatchHost() {
    if (notifications_.count)
      return;
    auto weak = weak_factory_.GetWeakPtr();
    auto close = ^(NSNotification*) {
      if (weak)
        weak->Close();
    };
    for (NSNotificationName name in @[
           NSWindowWillCloseNotification, NSWindowWillMiniaturizeNotification,
           PCNativeWindowSecurityStateChanged
         ]) {
      [notifications_ addObject:[NSNotificationCenter.defaultCenter
                                    addObserverForName:name object:host_
                                                 queue:nil usingBlock:close]];
    }
  }
  // The dialog can't stop a cast that plays from a page the tab has left, or
  // one whose page has no session or presentation left, and a Safari-identity
  // page never casts from it, so the button offers the tab's route directly,
  // above the dialog when it has the current page's media to cast.
  bool OfferStopCasting(NSView* view, NSRect rect, bool dialog) {
    const auto route = Route();
    if (!route)
      return dialog ? ShowDialog(view, rect) : Fail();
    enum : NSInteger { kStop = 1, kDialog };
    PCNativeCastMenuTarget* target = [[PCNativeCastMenuTarget alloc] init];
    NSMenu* menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    auto add = [&](NSString* title, NSInteger tag) {
      NSMenuItem* item = [menu addItemWithTitle:title action:@selector(choose:) keyEquivalent:@""];
      item.target = target;
      item.tag = tag;
    };
    add(base::SysUTF16ToNSString(l10n_util::GetStringFUTF16(
            IDS_MEDIA_ROUTER_SINK_VIEW_STOP_GENERIC_ACCESSIBLE_NAME,
            base::UTF8ToUTF16(route->media_sink_name()))),
        kStop);
    if (dialog)
      add(l10n_util::GetNSStringWithFixup(IDS_MEDIA_ROUTER_MENU_ITEM_TITLE), kDialog);
    menu_ = menu;
    if (!dismissed_)
      dismissed_ = std::exchange(pending_dismissed_, nil);
    auto weak = weak_factory_.GetWeakPtr();
    __weak NSView* weak_view = view;
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(NSMinX(rect), view.flipped ? NSMaxY(rect) : NSMinY(rect))
                            inView:view];
    if (!weak)
      return true;
    // The menu's loop ran tasks: the page, profile and route may have moved on.
    NSView* anchor = weak_view;
    if (target.chosen == kDialog && Current() && anchor && anchor.window == host_) {
      menu_ = nil;
      ShowDialog(anchor, rect);
      return true;
    }
    const auto current = target.chosen == kStop && Current() ? Route() : std::nullopt;
    if (current && current->media_route_id() == route->media_route_id())
      Router()->TerminateRoute(route->media_route_id());
    Close();
    return true;
  }
  MediaNotificationService* Service() const {
    auto* profile = Profile::FromBrowserContext(web_contents()->GetBrowserContext());
    return profile && !profile->ShutdownStarted()
        ? MediaNotificationServiceFactory::GetForProfile(profile) : nullptr;
  }
  media_router::MediaRouter* Router() const {
    auto* profile = Profile::FromBrowserContext(web_contents()->GetBrowserContext());
    return profile && !profile->ShutdownStarted()
        ? media_router::MediaRouterFactory::GetApiForBrowserContextIfExists(profile)
        : nullptr;
  }
  std::optional<media_router::MediaRoute> Route() const {
    auto* router = Router();
    return router ? MediaNotificationService::ParcCastRouteForWebContents(
                        web_contents(), router->GetCurrentRoutes())
                  : std::nullopt;
  }
  __weak NSWindow* host_ = nil;
  const base::RepeatingCallback<bool()> valid_;
  // Runs on Close() only once Show() has succeeded.
  void (^pending_dismissed_)(void) = nil;
  void (^dismissed_)(void) = nil;
  raw_ptr<views::Widget> widget_ = nullptr;
  NSMutableArray* notifications_ = [[NSMutableArray alloc] init];
  base::ScopedObservation<views::Widget, views::WidgetObserver> widget_observation_{this};
  NSMenu* __strong menu_ = nil;
  __weak NSView* waiting_view_ = nil;
  NSRect waiting_rect_ = NSZeroRect;
  base::ScopedObservation<global_media_controls::MediaItemManager,
                          global_media_controls::MediaItemManagerObserver>
      items_{this};
  std::unique_ptr<Routes> routes_;
  base::OneShotTimer wait_;
  bool closed_ = false;
  base::WeakPtrFactory<MediaCastChooser> weak_factory_{this};
};
std::unique_ptr<MediaCastChooser>& ActiveChooser() {
  static base::NoDestructor<std::unique_ptr<MediaCastChooser>> chooser;
  return *chooser;
}
}  // namespace
bool CloseNativeGmcPresentationForPage(content::WebContents* contents) {
  if (auto& chooser = ActiveChooser(); chooser && chooser->IsFor(contents))
    chooser->Close();
  auto session = ActiveSession().lock();
  if (session && session->IsFor(contents)) {
    session->RequestClose();
    return !session->Busy();
  }
  return true;
}
NativeMediaCastState NativeMediaCastStateForContents(content::WebContents* contents) {
  if (!contents || contents->IsBeingDestroyed())
    return {};
  MediaCastWatcher::CreateForWebContents(contents);
  return MediaCastWatcher::FromWebContents(contents)->State();
}
bool ShowNativeMediaCastChooser(content::WebContents* contents,
                                NSView* view,
                                NSRect rect,
                                base::RepeatingCallback<bool()> valid,
                                void (^dismissed)(void)) {
  if (!contents || !view.window ||
      NativeMediaCastStateForContents(contents).state == PCNativeCastStateUnavailable)
    return false;
  // One media controls dialog at a time: a site's chooser, then this one.
  if (auto session = ActiveSession().lock()) {
    session->RequestClose();
    if (session->Busy())
      return false;
  }
  if (!CloseNativeCastForPage(contents))
    return false;
  auto previous = std::move(ActiveChooser());
  previous.reset();
  auto chooser = std::make_unique<MediaCastChooser>(contents, view.window,
                                                    std::move(valid), dismissed);
  auto* shown = chooser.get();
  ActiveChooser() = std::move(chooser);
  return shown->Show(view, rect);
}
void InstallNativeGmcPresentationHandler() {
  media_router::MediaRouterDialogControllerViews::SetNativePresentationHandler(
      base::BindRepeating(&MaybeShowNativePresentation));
}
}  // namespace parc

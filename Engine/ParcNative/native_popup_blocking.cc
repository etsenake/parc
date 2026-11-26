// Copyright 2026 Parc contributors.
#include "native_popup_blocking.h"

#include <map>
#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/chrome_content_browser_client.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/ui/blocked_content/framebust_block_tab_helper.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/navigator/browser_navigator_params_utils.h"
#include "chrome/common/chrome_render_frame.mojom.h"
#include "components/blocked_content/popup_blocker.h"
#include "components/blocked_content/popup_blocker_tab_helper.h"
#include "components/blocked_content/popup_navigation_delegate.h"
#include "components/blocked_content/popup_tracker.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/page.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "services/network/public/mojom/web_sandbox_flags.mojom.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/mojom/frame/triggering_event_info.mojom-shared.h"
#include "third_party/blink/public/mojom/window_features/window_features.mojom.h"
#include "ui/base/window_open_disposition.h"

namespace parc {
namespace {

void (*g_blocked_content_changed)(content::WebContents&) = nullptr;

class BlockedContentState final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BlockedContentState> {
 public:
  BlockedContentState(const BlockedContentState&) = delete;
  BlockedContentState& operator=(const BlockedContentState&) = delete;
  ~BlockedContentState() override = default;

  uint64_t revision() const { return revision_; }

  void Changed() {
    if (publish_pending_) {
      return;
    }
    publish_pending_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&BlockedContentState::Publish,
                                  weak_factory_.GetWeakPtr()));
  }

  void PrimaryPageChanged(content::Page&) override {
    ++revision_;
    Changed();
  }

 private:
  friend class content::WebContentsUserData<BlockedContentState>;

  explicit BlockedContentState(content::WebContents* contents)
      : content::WebContentsObserver(contents),
        content::WebContentsUserData<BlockedContentState>(*contents) {}

  void Publish() {
    publish_pending_ = false;
    content::WebContents* contents = web_contents();
    if (contents && !contents->IsBeingDestroyed() &&
        g_blocked_content_changed) {
      g_blocked_content_changed(*contents);
    }
  }

  uint64_t revision_ = 1;
  bool publish_pending_ = false;
  base::WeakPtrFactory<BlockedContentState> weak_factory_{this};

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(BlockedContentState);

void NoteBlockedContentChanged(content::WebContents& contents) {
  BlockedContentState::CreateForWebContents(&contents);
  BlockedContentState::FromWebContents(&contents)->Changed();
}

BlockedContentState* CurrentState(content::WebContents& contents,
                                  uint64_t revision) {
  auto* state = BlockedContentState::FromWebContents(&contents);
  return state && state->revision() == revision &&
                 !contents.IsBeingDestroyed()
             ? state
             : nullptr;
}

FramebustBlockTabHelper* Redirects(content::WebContents& contents) {
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(&contents);
  return tab ? FramebustBlockTabHelper::From(tab) : nullptr;
}

network::mojom::WebSandboxFlags PropagatedSandboxFlags(
    content::RenderFrameHost& frame) {
  using Flags = network::mojom::WebSandboxFlags;
  if (!frame.IsSandboxed(Flags::kPropagatesToAuxiliaryBrowsingContexts)) {
    return Flags::kNone;
  }
  int32_t flags = 0;
  for (int bit = 0; bit < 31; ++bit) {
    const int32_t flag = int32_t{1} << bit;
    if (frame.IsSandboxed(static_cast<Flags>(flag))) {
      flags |= flag;
    }
  }
  return static_cast<Flags>(flags);
}

struct WindowRelease {
  WindowRelease(NavigateParams navigate_params,
                base::WeakPtr<content::WebContents> source_contents,
                content::WeakDocumentPtr opener_document,
                network::mojom::WebSandboxFlags flags,
                const blink::mojom::WindowFeatures& window_features)
      : params(std::move(navigate_params)),
        source(std::move(source_contents)),
        opener(opener_document),
        sandbox_flags(flags),
        features(window_features) {}
  WindowRelease(const WindowRelease&) = delete;
  WindowRelease& operator=(const WindowRelease&) = delete;
  ~WindowRelease() = default;

  NavigateParams params;
  base::WeakPtr<content::WebContents> source;
  content::WeakDocumentPtr opener;
  network::mojom::WebSandboxFlags sandbox_flags;
  blink::mojom::WindowFeatures features;
};

content::RenderFrameHost* LiveOpener(const content::WeakDocumentPtr& document,
                                     content::WebContents* source) {
  content::RenderFrameHost* opener = document.AsRenderFrameHostIfValid();
  return opener && source &&
                 content::WebContents::FromRenderFrameHost(opener) == source &&
                 opener->IsActive() && opener->IsRenderFrameLive()
             ? opener
             : nullptr;
}

bool CanReleaseFrom(content::WebContents* source) {
  if (!source || source->IsBeingDestroyed() || !source->GetDelegate()) {
    return false;
  }
  BrowserWindowInterface* browser =
      GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(source);
  return browser && !browser->IsDeleteScheduled();
}

void ReleaseWindowPopup(std::unique_ptr<WindowRelease> release) {
  content::WebContents* source = release->source.get();
  if (!CanReleaseFrom(source)) {
    return;
  }
  NavigateParams& params = release->params;
  const WindowOpenDisposition disposition = params.disposition;
  const bool suppressed = !params.opened_by_another_window;
  content::RenderFrameHost* opener = LiveOpener(release->opener, source);
  content::BrowserContext* context = source->GetBrowserContext();
  scoped_refptr<content::SiteInstance> site_instance =
      opener && !suppressed
          ? scoped_refptr<content::SiteInstance>(opener->GetSiteInstance())
          : content::SiteInstance::CreateForURL(context, params.url);
  content::WebContents::CreateParams create_params(context,
                                                   site_instance.get());
  create_params.main_frame_name = params.frame_name;
  create_params.opener_suppressed = suppressed;
  create_params.opened_by_another_window = !suppressed;
  create_params.initially_hidden =
      disposition == WindowOpenDisposition::kNewBackgroundTab;
  create_params.starting_sandbox_flags = release->sandbox_flags;
  content::GlobalRenderFrameHostId opener_id;
  if (opener) {
    opener_id = opener->GetGlobalId();
    create_params.opener_id = opener_id;
    create_params.initial_popup_url = params.url;
  }
  std::unique_ptr<content::WebContents> created =
      content::WebContents::Create(create_params);
  const base::WeakPtr<content::WebContents> contents = created->GetWeakPtr();
  source->GetDelegate()->WebContentsCreated(source, opener_id,
                                            params.frame_name, params.url,
                                            created.get());
  if (!CanReleaseFrom(release->source.get())) {
    return;
  }
  source = release->source.get();
  bool was_blocked = false;
  source->GetDelegate()->AddNewContents(source, std::move(created), params.url,
                                        disposition, release->features, true,
                                        &was_blocked);
  if (!contents || was_blocked) {
    return;
  }
  if (auto* tracker =
          blocked_content::PopupTracker::FromWebContents(contents.get())) {
    tracker->set_is_trusted(true);
  }
  params.user_gesture = true;
  if (!opener || suppressed) {
    params.source_site_instance = nullptr;
  }
  content::NavigationController::LoadURLParams load_params =
      LoadURLParamsFromNavigateParams(contents.get(), &params);
  contents->GetController().LoadURLWithParams(load_params);
  if (contents && disposition == WindowOpenDisposition::kNewPopup) {
    mojo::AssociatedRemote<chrome::mojom::ChromeRenderFrame> client;
    contents->GetPrimaryMainFrame()
        ->GetRemoteAssociatedInterfaces()
        ->GetInterface(&client);
    client->SetWindowFeatures(release->features.Clone());
  }
}

class NativeWindowPopup final : public blocked_content::PopupNavigationDelegate {
 public:
  explicit NativeWindowPopup(NavigateParams params)
      : params_(std::move(params)),
        url_(params_.url),
        original_user_gesture_(params_.user_gesture) {
    if (params_.source_contents) {
      source_ = params_.source_contents->GetWeakPtr();
    }
    if (params_.initiator_frame_token) {
      if (content::RenderFrameHost* opener =
              content::RenderFrameHost::FromFrameToken(
                  content::GlobalRenderFrameHostToken(
                      params_.initiator_process_id,
                      *params_.initiator_frame_token))) {
        opener_ = opener->GetWeakDocumentPtr();
        sandbox_flags_ = PropagatedSandboxFlags(*opener);
      }
    }
  }
  NativeWindowPopup(const NativeWindowPopup&) = delete;
  NativeWindowPopup& operator=(const NativeWindowPopup&) = delete;
  ~NativeWindowPopup() override = default;

  content::RenderFrameHost* GetOpener() override {
    return LiveOpener(opener_, source_.get());
  }
  bool GetOriginalUserGesture() override { return original_user_gesture_; }
  GURL GetURL() override { return url_; }

  NavigateResult NavigateWithGesture(
      const blink::mojom::WindowFeatures& window_features,
      std::optional<WindowOpenDisposition> updated_disposition) override {
    if (released_ || !CanReleaseFrom(source_.get())) {
      return {};
    }
    released_ = true;
    if (updated_disposition) {
      params_.disposition = *updated_disposition;
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&ReleaseWindowPopup,
                       std::make_unique<WindowRelease>(
                           std::move(params_), source_, opener_,
                           sandbox_flags_, window_features)));
    return {};
  }

  void OnPopupBlocked(content::WebContents* web_contents, int) override {
    if (web_contents) {
      NoteBlockedContentChanged(*web_contents);
    }
  }

 private:
  NavigateParams params_;
  const GURL url_;
  const bool original_user_gesture_;
  bool released_ = false;
  base::WeakPtr<content::WebContents> source_;
  content::WeakDocumentPtr opener_;
  network::mojom::WebSandboxFlags sandbox_flags_ =
      network::mojom::WebSandboxFlags::kNone;
};

class NativeLinkPopup final : public blocked_content::PopupNavigationDelegate {
 public:
  NativeLinkPopup(content::WebContents& source,
                  const content::OpenURLParams& params)
      : source_(source.GetWeakPtr()), params_(params) {}
  NativeLinkPopup(const NativeLinkPopup&) = delete;
  NativeLinkPopup& operator=(const NativeLinkPopup&) = delete;
  ~NativeLinkPopup() override = default;

  content::RenderFrameHost* GetOpener() override { return nullptr; }
  bool GetOriginalUserGesture() override { return params_.user_gesture; }
  GURL GetURL() override { return params_.url; }

  NavigateResult NavigateWithGesture(
      const blink::mojom::WindowFeatures&,
      std::optional<WindowOpenDisposition> updated_disposition) override {
    content::WebContents* source = source_.get();
    if (!source || source->IsBeingDestroyed()) {
      return {};
    }
    content::OpenURLParams params(params_);
    params.user_gesture = true;
    params.triggering_event_info =
        blink::mojom::TriggeringEventInfo::kFromTrustedEvent;
    if (updated_disposition) {
      params.disposition = *updated_disposition;
    }
    content::WebContents* created = source->OpenURL(params, {});
    if (!source_ || created == source_.get()) {
      return {};
    }
    return NavigateResult{created, params.disposition};
  }

  void OnPopupBlocked(content::WebContents* web_contents, int) override {
    if (web_contents) {
      NoteBlockedContentChanged(*web_contents);
    }
  }

 private:
  base::WeakPtr<content::WebContents> source_;
  const content::OpenURLParams params_;
};

std::unique_ptr<blocked_content::PopupNavigationDelegate>
CreateNativeWindowPopup(NavigateParams params) {
  return std::make_unique<NativeWindowPopup>(std::move(params));
}

HostContentSettingsMap* SettingsMap(content::WebContents& contents) {
  return HostContentSettingsMapFactory::GetForProfile(
      contents.GetBrowserContext());
}

bool UserCanAllow(HostContentSettingsMap& map, const GURL& site) {
  content_settings::SettingInfo info;
  map.GetContentSetting(site, site, ContentSettingsType::POPUPS, &info);
  return info.source == content_settings::SettingSource::kUser &&
         map.CanSetNarrowestContentSetting(site, site,
                                           ContentSettingsType::POPUPS);
}

}

NativeBlockedContent::NativeBlockedContent() = default;
NativeBlockedContent::NativeBlockedContent(const NativeBlockedContent&) =
    default;
NativeBlockedContent& NativeBlockedContent::operator=(
    const NativeBlockedContent&) = default;
NativeBlockedContent::~NativeBlockedContent() = default;

void InstallNativePopupBlocking(void (*changed)(content::WebContents&)) {
  g_blocked_content_changed = changed;
  ChromeContentBrowserClient::GetPopupNavigationDelegateFactoryForTesting() =
      &CreateNativeWindowPopup;
}

bool BlockNativeLinkPopup(content::WebContents* source,
                          const content::OpenURLParams& params) {
  if (!source || params.native_route_token ||
      !blocked_content::ConsiderForPopupBlocking(params.disposition)) {
    return false;
  }
  return !blocked_content::MaybeBlockPopup(
      source, nullptr, std::make_unique<NativeLinkPopup>(*source, params),
      &params, blink::mojom::WindowFeatures(), SettingsMap(*source));
}

void NativeNavigationBlocked(content::WebContents& contents) {
  NoteBlockedContentChanged(contents);
}

std::optional<NativeBlockedContent> GetNativeBlockedContent(
    content::WebContents& contents) {
  if (contents.IsBeingDestroyed()) {
    return std::nullopt;
  }
  NativeBlockedContent content;
  if (auto* popups =
          blocked_content::PopupBlockerTabHelper::FromWebContents(&contents)) {
    for (const auto& [id, url] : popups->GetBlockedPopupRequests()) {
      content.items.push_back(
          {NativeBlockedItem::Kind::kPopup, id, url});
    }
  }
  if (FramebustBlockTabHelper* redirects = Redirects(contents)) {
    const std::vector<GURL>& urls = redirects->blocked_urls();
    for (size_t index = 0; index < urls.size(); ++index) {
      content.items.push_back({NativeBlockedItem::Kind::kRedirect,
                               static_cast<int32_t>(index), urls[index]});
    }
  }
  auto* state = BlockedContentState::FromWebContents(&contents);
  HostContentSettingsMap* map = SettingsMap(contents);
  if (content.items.empty() || !state || !map) {
    return std::nullopt;
  }
  content.revision = state->revision();
  content.site = contents.GetPrimaryMainFrame()->GetLastCommittedURL();
  content_settings::SettingInfo info;
  content.allowed = map->GetContentSetting(content.site, content.site,
                                           ContentSettingsType::POPUPS,
                                           &info) == CONTENT_SETTING_ALLOW;
  content.can_allow = !content.allowed && UserCanAllow(*map, content.site);
  return content;
}

bool OpenNativeBlockedItem(content::WebContents& contents,
                           NativeBlockedItem::Kind kind,
                           int32_t id,
                           uint64_t revision) {
  if (!CurrentState(contents, revision)) {
    return false;
  }
  if (kind == NativeBlockedItem::Kind::kRedirect) {
    FramebustBlockTabHelper* redirects = Redirects(contents);
    if (!redirects || id < 0 ||
        static_cast<size_t>(id) >= redirects->blocked_urls().size()) {
      return false;
    }
    redirects->OnBlockedUrlClicked(static_cast<size_t>(id));
    return true;
  }
  auto* popups =
      blocked_content::PopupBlockerTabHelper::FromWebContents(&contents);
  if (!popups || !CanReleaseFrom(&contents) ||
      !popups->GetBlockedPopupRequests().contains(id)) {
    return false;
  }
  const base::WeakPtr<content::WebContents> weak = contents.GetWeakPtr();
  popups->ShowBlockedPopup(id, WindowOpenDisposition::kCurrentTab);
  if (weak) {
    NoteBlockedContentChanged(*weak);
  }
  return true;
}

bool OpenAllNativeBlockedPopups(content::WebContents& contents,
                                uint64_t revision) {
  if (!CurrentState(contents, revision)) {
    return false;
  }
  auto* popups =
      blocked_content::PopupBlockerTabHelper::FromWebContents(&contents);
  if (!popups || !CanReleaseFrom(&contents)) {
    return false;
  }
  const blocked_content::PopupBlockerTabHelper::PopupIdMap requests =
      popups->GetBlockedPopupRequests();
  const base::WeakPtr<content::WebContents> weak = contents.GetWeakPtr();
  bool opened = false;
  for (const auto& request : requests) {
    if (!weak || !CurrentState(*weak, revision)) {
      break;
    }
    auto* helper =
        blocked_content::PopupBlockerTabHelper::FromWebContents(weak.get());
    if (!helper || !CanReleaseFrom(weak.get())) {
      break;
    }
    if (!helper->GetBlockedPopupRequests().contains(request.first)) {
      continue;
    }
    helper->ShowBlockedPopup(request.first,
                             WindowOpenDisposition::kCurrentTab);
    opened = true;
  }
  if (weak) {
    NoteBlockedContentChanged(*weak);
  }
  return opened;
}

bool AllowNativeBlockedPopups(content::WebContents& contents,
                              uint64_t revision) {
  HostContentSettingsMap* map = SettingsMap(contents);
  if (!CurrentState(contents, revision) || !map) {
    return false;
  }
  const GURL site = contents.GetPrimaryMainFrame()->GetLastCommittedURL();
  if (!UserCanAllow(*map, site)) {
    return false;
  }
  map->SetNarrowestContentSetting(site, site, ContentSettingsType::POPUPS,
                                  CONTENT_SETTING_ALLOW);
  NoteBlockedContentChanged(contents);
  return true;
}

}

// Copyright 2026 Parc contributors.
#include "content/browser/media/parc_media_routing.h"

#include <algorithm>
#include <optional>
#include <string>

#include "base/containers/flat_map.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "content/browser/media/media_web_contents_observer.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/browser/web_contents/web_contents_impl.h"
#include "content/public/browser/document_user_data.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/media_player_id.h"
#include "content/public/browser/parc_playback_target.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/web_contents.h"
#include "media/base/cdm_config.h"
#include "media/base/cdm_factory.h"
#include "media/base/key_system_names.h"
#include "mojo/public/cpp/bindings/pending_remote.h"

namespace parc_hooks {
using FairPlayCdmCreator =
    bool (*)(content::RenderFrameHost&,
             const media::CdmConfig&,
             media::mojom::InterfaceFactory::CreateCdmCallback&);
CONTENT_EXPORT void SetFairPlayCdmCreator(FairPlayCdmCreator creator);
}

namespace {

parc::fairplay::WidevineCdmRequestObserver& WidevineCdmRequestObserverSlot() {
  static base::NoDestructor<parc::fairplay::WidevineCdmRequestObserver>
      observer;
  return *observer;
}

constexpr size_t kMaxHeldWidevineCdmRequests = 16;

bool IsWidevineKeySystemName(const std::string& key_system) {
  static constexpr char kWidevineKeySystemName[] = "com.widevine.alpha";
  return key_system == kWidevineKeySystemName ||
         media::IsSubKeySystemOf(key_system, kWidevineKeySystemName);
}

parc::fairplay::SafariIdentityQuery& SafariIdentityQuerySlot() {
  static base::NoDestructor<parc::fairplay::SafariIdentityQuery> query;
  return *query;
}

parc_hooks::FairPlayCdmCreator g_parc_fairplay_cdm_creator = nullptr;

}

namespace parc::fairplay {

void SetWidevineCdmRequestObserver(WidevineCdmRequestObserver observer) {
  WidevineCdmRequestObserverSlot() = std::move(observer);
}

void SetSafariIdentityQuery(SafariIdentityQuery query) {
  SafariIdentityQuerySlot() = std::move(query);
}

bool FramePresentsSafariIdentity(content::RenderFrameHost* frame) {
  if (!frame) {
    return false;
  }
  const SafariIdentityQuery& query = SafariIdentityQuerySlot();
  return query && query.Run(frame);
}

}

void parc_hooks::SetFairPlayCdmCreator(FairPlayCdmCreator creator) {
  g_parc_fairplay_cdm_creator = creator;
}

namespace content {

namespace {

class ParcPlayerGrants : public DocumentUserData<ParcPlayerGrants> {
 public:
  ~ParcPlayerGrants() override = default;

  std::optional<int> TakePlayerGrant(int player_id) {
    std::optional<int> grant_id;
    if (auto released = released_grants_.find(player_id);
        released != released_grants_.end()) {
      grant_id = released->second;
      released_grants_.erase(released);
    } else if (auto pending = std::ranges::find_if(
                   pending_player_grants_,
                   [player_id](const auto& entry) {
                     return entry.second == player_id;
                   });
               pending != pending_player_grants_.end()) {
      grant_id = pending->first;
      pending_player_grants_.erase(pending);
    }
    return grant_id;
  }

  base::flat_map<int, int> pending_player_grants_;
  base::flat_map<MediaPlayerId, int> active_grants_;
  base::flat_map<int, int> released_grants_;

 private:
  explicit ParcPlayerGrants(RenderFrameHost* rfh)
      : DocumentUserData<ParcPlayerGrants>(rfh) {}

  friend class DocumentUserData<ParcPlayerGrants>;
  DOCUMENT_USER_DATA_KEY_DECL();
};

DOCUMENT_USER_DATA_KEY_IMPL(ParcPlayerGrants);

int NextGrantId() {
  static int next_grant_id = 0;
  return ++next_grant_id;
}

base::flat_map<int, GlobalRenderFrameHostId>& GrantHolders() {
  static base::NoDestructor<base::flat_map<int, GlobalRenderFrameHostId>>
      holders;
  return *holders;
}

MediaWebContentsObserver* ObserverFor(RenderFrameHost* rfh) {
  auto* web_contents =
      static_cast<WebContentsImpl*>(WebContents::FromRenderFrameHost(rfh));
  return web_contents ? web_contents->media_web_contents_observer() : nullptr;
}

void RevokePlayerGrant(int grant_id) {
  auto holder = GrantHolders().find(grant_id);
  if (holder == GrantHolders().end()) {
    return;
  }
  auto* rfh = RenderFrameHost::FromID(holder->second);
  GrantHolders().erase(holder);
  if (!rfh) {
    return;
  }
  auto* grants = ParcPlayerGrants::GetForCurrentDocument(rfh);
  if (!grants) {
    return;
  }
  if (grants->pending_player_grants_.erase(grant_id)) {
    return;
  }
  for (auto it = grants->active_grants_.begin();
       it != grants->active_grants_.end(); ++it) {
    if (it->second == grant_id) {
      MediaPlayerId id = it->first;
      grants->active_grants_.erase(it);
      if (MediaWebContentsObserver* observer = ObserverFor(rfh)) {
        observer->OnAudibilityBypassRevoked(id);
      }
      return;
    }
  }
  base::EraseIf(grants->released_grants_, [grant_id](const auto& entry) {
    return entry.second == grant_id;
  });
}

MediaWebContentsObserver* ObserverFor(WebContents* web_contents) {
  return web_contents ? static_cast<WebContentsImpl*>(web_contents)
                            ->media_web_contents_observer()
                      : nullptr;
}

}

base::ScopedClosureRunner ParcAddPlayerGrant(RenderFrameHost* rfh,
                                             int player_id) {
  int grant_id = NextGrantId();
  ParcPlayerGrants::GetOrCreateForCurrentDocument(rfh)
      ->pending_player_grants_[grant_id] = player_id;
  GrantHolders()[grant_id] = rfh->GetGlobalId();
  return base::ScopedClosureRunner(
      base::BindOnce(&RevokePlayerGrant, grant_id));
}

bool ParcClaimPlayerGrant(const MediaPlayerId& id) {
  auto* rfh = RenderFrameHost::FromID(id.frame_routing_id);
  if (!rfh) {
    return false;
  }
  auto* grants = ParcPlayerGrants::GetForCurrentDocument(rfh);
  if (grants && grants->active_grants_.contains(id)) {
    return true;
  }
  std::optional<int> player_grant_id;
  rfh->GetProcess()->ForEachRenderFrameHost([&](RenderFrameHost* other) {
    auto* other_grants = ParcPlayerGrants::GetForCurrentDocument(other);
    if (!player_grant_id && other_grants) {
      player_grant_id = other_grants->TakePlayerGrant(id.player_id);
    }
  });
  if (!player_grant_id) {
    return false;
  }
  ParcPlayerGrants::GetOrCreateForCurrentDocument(rfh)->active_grants_[id] =
      *player_grant_id;
  GrantHolders()[*player_grant_id] = id.frame_routing_id;
  return true;
}

void ParcReleasePlayerGrant(const MediaPlayerId& id) {
  auto* rfh = RenderFrameHost::FromID(id.frame_routing_id);
  if (!rfh) {
    return;
  }
  auto* grants = ParcPlayerGrants::GetForCurrentDocument(rfh);
  if (!grants) {
    return;
  }
  auto active = grants->active_grants_.find(id);
  if (active == grants->active_grants_.end()) {
    return;
  }
  grants->released_grants_[id.player_id] = active->second;
  grants->active_grants_.erase(active);
  rfh->GetProcess()->ForEachRenderFrameHost([&](RenderFrameHost* other) {
    MediaWebContentsObserver* observer = ObserverFor(other);
    if (other != rfh && observer) {
      observer->OnAudibilityBypassRevoked(
          MediaPlayerId(other->GetGlobalId(), id.player_id));
    }
  });
}

void SetParcPlaybackTargetAvailability(WebContents* web_contents,
                                       const MediaPlayerId& player,
                                       bool available) {
  MediaWebContentsObserver* observer = ObserverFor(web_contents);
  if (observer && observer->IsMediaPlayerRemoteAvailable(player)) {
    observer->GetMediaPlayerRemote(player)->ParcSetPlaybackTargetAvailability(
        available);
  }
}

void SetParcPlaybackTarget(WebContents* web_contents,
                           const MediaPlayerId& player,
                           const std::string& output_context_id,
                           const std::string& device_name,
                           bool should_play,
                           uint32_t tint_argb,
                           uint32_t tint_on_light_argb) {
  MediaWebContentsObserver* observer = ObserverFor(web_contents);
  if (observer && observer->IsMediaPlayerRemoteAvailable(player)) {
    observer->GetMediaPlayerRemote(player)->ParcSetPlaybackTarget(
        output_context_id, device_name, should_play, tint_argb,
        tint_on_light_argb);
  }
}

void SetParcPlaybackTargetPickerDismissed(WebContents* web_contents,
                                          const MediaPlayerId& player) {
  MediaWebContentsObserver* observer = ObserverFor(web_contents);
  if (observer && observer->IsMediaPlayerRemoteAvailable(player)) {
    observer->GetMediaPlayerRemote(player)->ParcPlaybackTargetPickerDismissed();
  }
}

bool ParcHandleCdmRequest(
    RenderFrameHost& frame,
    const media::CdmConfig& cdm_config,
    media::mojom::InterfaceFactory::CreateCdmCallback& create_cdm_cb,
    std::vector<media::mojom::InterfaceFactory::CreateCdmCallback>& held,
    base::WeakPtr<MediaInterfaceProxy> proxy) {
  parc::fairplay::WidevineCdmRequestObserver widevine_observer =
      WidevineCdmRequestObserverSlot();
  if (widevine_observer && IsWidevineKeySystemName(cdm_config.key_system)) {
    const bool hold = widevine_observer.Run(&frame, cdm_config.key_system);
    if (!proxy) {
      return true;
    }
    if (hold) {
      if (held.size() >= kMaxHeldWidevineCdmRequests) {
        std::move(create_cdm_cb)
            .Run(mojo::NullRemote(), nullptr,
                 media::CreateCdmStatus::kCdmCreationAborted);
        return true;
      }
      DVLOG(1) << __func__ << ": Widevine CDM request held";
      held.push_back(std::move(create_cdm_cb));
      return true;
    }
  }
  return g_parc_fairplay_cdm_creator &&
         g_parc_fairplay_cdm_creator(frame, cdm_config, create_cdm_cb);
}

}

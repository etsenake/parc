// Copyright 2019 The Chromium Authors

#include "chrome/browser/ui/global_media_controls/media_notification_service.h"
#include <utility>

#include "base/functional/bind.h"
#include "base/task/sequenced_task_runner.h"
#include "components/global_media_controls/public/media_session_item_producer.h"
#include "components/media_router/browser/media_router_factory.h"
#include "components/media_router/browser/presentation/start_presentation_context.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "media/media_buildflags.h"

#if BUILDFLAG(ENABLE_MEDIA_REMOTING)
#include "chrome/browser/media/cast_remoting_connector.h"
#endif

namespace mojom {
using global_media_controls::mojom::DeviceListHost;
}

namespace {
void CancelRequest(
    std::unique_ptr<media_router::StartPresentationContext> context,
    const std::string& message) {
  context->InvokeErrorCallback(blink::mojom::PresentationError(
      blink::mojom::PresentationErrorType::PRESENTATION_REQUEST_CANCELLED,
      message));
}
}

base::OnceCallback<void(bool)>
MediaNotificationService::ParcRequestMediaRemoting(const std::string& item_id) {
  auto* web_contents =
      content::MediaSession::GetWebContentsFromRequestId(item_id);
  if (!web_contents) {
    return {};
  }

  content::MediaSession::Get(web_contents)->RequestMediaRemoting();
  return base::BindOnce(
      &MediaNotificationService::ParcOnMediaRemotingLaunched,
      web_contents->GetWeakPtr(),
      web_contents->GetPrimaryMainFrame()->GetWeakDocumentPtr());
}

void MediaNotificationService::ParcOnMediaRemotingLaunched(
    base::WeakPtr<content::WebContents> web_contents,
    content::WeakDocumentPtr document,
    bool launched) {
  if (!web_contents) {
    return;
  }
  if (!launched) {
#if BUILDFLAG(ENABLE_MEDIA_REMOTING)
    if (auto* connector = CastRemotingConnector::Get(web_contents.get())) {
      connector->ParcDropRemotingRequests();
    }
#endif
    return;
  }
  auto* frame = document.AsRenderFrameHostIfValid();
  if (frame && (frame->IsActive() ||
                frame->IsInLifecycleState(
                    content::RenderFrameHost::LifecycleState::
                        kInBackForwardCache))) {
    return;
  }
  auto* router =
      media_router::MediaRouterFactory::GetApiForBrowserContextIfExists(
          web_contents->GetBrowserContext());
  if (!router) {
    return;
  }
  const int tab_id =
      sessions::SessionTabHelper::IdForTab(web_contents.get()).id();
  for (const auto& route : router->GetCurrentRoutes()) {
    if (route.media_source().IsRemotePlaybackSource() &&
        route.media_source().TabIdFromRemotePlaybackSource() == tab_id) {
      router->TerminateRoute(route.media_route_id());
    }
  }
}

bool MediaNotificationService::BeginNativePresentation(
    base::UnguessableToken token,
    std::unique_ptr<media_router::StartPresentationContext> context,
    base::RepeatingCallback<bool()> guard,
    base::OnceClosure close_surface) {
  const uint64_t sequence = ++presentation_sequence_;
  auto weak_this = weak_ptr_factory_.GetWeakPtr();
  CancelActiveNativePresentation();
  if (!weak_this || shutdown_has_started_ || sequence != presentation_sequence_) {
    CancelRequest(std::move(context), "The presentation is unavailable.");
    return false;
  }
  if (!presentation_request_notification_producer_ ||
      !supplemental_device_picker_producer_) {
    CancelRequest(std::move(context), "The presentation is unavailable.");
    return false;
  }
  context->SetNativeRequestToken(token);
  native_presentation_.emplace(
      NativePresentationState{token, std::move(guard), std::move(close_surface)});
  presentation_request_notification_producer_->ArmNativeRequest(
      token, base::BindOnce(&MediaNotificationService::CancelNativePresentation,
                            weak_ptr_factory_.GetWeakPtr(), token),
      supplemental_device_picker_producer_.get());
  supplemental_device_picker_producer_->WatchPendingNativeLifecycle(
      token, base::BindOnce(&MediaNotificationService::CancelNativePresentation,
                            weak_ptr_factory_.GetWeakPtr(), token));
  StartPresentationContext(std::move(context), sequence);
  if (!weak_this || sequence != presentation_sequence_ || !HasNativePresentation(token))
    return false;
  if (!NativeContextPending(token)) {
    CancelNativePresentation(token);
    return false;
  }
  return true;
}

bool MediaNotificationService::HasNativePresentation(
    const base::UnguessableToken& token) const {
  return native_presentation_ && native_presentation_->token == token &&
         !shutdown_has_started_;
}

bool MediaNotificationService::WaitForNativePreparation(
    base::UnguessableToken token, base::OnceClosure completion) {
  return HasNativePresentation(token) && presentation_request_notification_producer_ &&
         presentation_request_notification_producer_->WaitForNativePreparation(
             token, std::move(completion));
}

bool MediaNotificationService::PrepareNativeDialog(base::UnguessableToken token) {
  if (!HasNativePresentation(token) || !supplemental_device_picker_producer_ ||
      !presentation_request_notification_producer_)
    return false;
  supplemental_device_picker_producer_->PrepareNativeLifecycle(
      token, base::BindRepeating(&MediaNotificationService::OnNativeDialogLifecycle,
                                 weak_ptr_factory_.GetWeakPtr(), token));
  return true;
}

void MediaNotificationService::OnNativeDialogLifecycle(
    base::UnguessableToken token,
    global_media_controls::SupplementalDevicePickerProducer::NativeLifecycleEvent event) {
  if (!presentation_request_notification_producer_)
    return;
  switch (event) {
    case global_media_controls::SupplementalDevicePickerProducer::NativeLifecycleEvent::kOpened:
      presentation_request_notification_producer_->OnNativeUIOpened(token);
      return;
    case global_media_controls::SupplementalDevicePickerProducer::NativeLifecycleEvent::kClosed: {
      auto weak_this = weak_ptr_factory_.GetWeakPtr();
      presentation_request_notification_producer_->OnNativeUIClosed(token);
      if (weak_this)
        weak_this->CancelNativePresentation(token);
      return;
    }
    case global_media_controls::SupplementalDevicePickerProducer::NativeLifecycleEvent::kDismissed: {
      auto weak_this = weak_ptr_factory_.GetWeakPtr();
      presentation_request_notification_producer_->OnNativePickerDismissed(token);
      if (weak_this)
        weak_this->CancelNativePresentation(token);
      return;
    }
  }
}

bool MediaNotificationService::NativeContextPending(
    const base::UnguessableToken& token) const {
  if (context_ && context_->native_request_token() == token)
    return true;
  if (!presentation_request_notification_producer_)
    return false;
  auto item = presentation_request_notification_producer_->GetNotificationItem();
  return item && item->context() && item->context()->native_request_token() == token;
}

base::WeakPtr<MediaNotificationService>
MediaNotificationService::GetWeakPtrForNative() {
  return weak_ptr_factory_.GetWeakPtr();
}

void MediaNotificationService::CancelActiveNativePresentation() {
  if (native_presentation_)
    CancelNativePresentation(native_presentation_->token);
}

void MediaNotificationService::CancelNativePresentation(
    base::UnguessableToken token) {
  if (!native_presentation_ || native_presentation_->token != token)
    return;

  auto old_state = std::move(*native_presentation_);
  native_presentation_.reset();
  auto weak_this = weak_ptr_factory_.GetWeakPtr();
  if (supplemental_device_picker_producer_)
    supplemental_device_picker_producer_->ClearNativeLifecycle(token);
  std::unique_ptr<media_router::StartPresentationContext> pending;
  std::string old_item_id;
  if (context_ && context_->native_request_token() == token) {
    pending = std::move(context_);
    old_item_id = std::exchange(context_item_id_, {});
  }
  std::unique_ptr<media_router::StartPresentationContext> supplemental;
  if (presentation_request_notification_producer_)
    supplemental = presentation_request_notification_producer_->TakeNativeContext(token);
  std::vector<mojo::SelfOwnedReceiverRef<mojom::DeviceListHost>> hosts;
  for (auto it = native_device_hosts_.begin(); it != native_device_hosts_.end();) {
    if (it->second != token) {
      ++it;
      continue;
    }
    auto host = host_receivers_.find(it->first);
    if (host != host_receivers_.end()) {
      hosts.push_back(host->second);
      host_receivers_.erase(host);
    }
    it = native_device_hosts_.erase(it);
  }
  if (!old_item_id.empty())
    media_session_item_producer_->UpdateMediaItemSourceOrigin(old_item_id, std::nullopt);

  for (auto& host : hosts) {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
            [](mojo::SelfOwnedReceiverRef<mojom::DeviceListHost> host) {
              if (host)
                host->Close();
            }, host));
  }
  if (old_state.close_surface)
    std::move(old_state.close_surface).Run();
  if (weak_this && presentation_request_notification_producer_)
    presentation_request_notification_producer_->DisarmNativeRequest(token);
  if (pending)
    CancelRequest(std::move(pending), "Dialog closed.");
  if (supplemental)
    CancelRequest(std::move(supplemental), "Dialog closed.");
}

bool MediaNotificationService::ParcHasFrozenSessionForWebContents(
    content::WebContents* web_contents) const {
  return content::MediaSession::GetIfExists(web_contents) &&
         media_session_item_producer_->ParcIsItemFrozen(
             content::MediaSession::GetRequestIdFromWebContents(web_contents)
                 .ToString());
}

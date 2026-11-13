// Copyright 2026 Parc contributors.
#include "parc/native/fairplay_media_host.h"

#include <memory>
#include <optional>
#include <utility>

#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/thread_pool.h"
#include "base/threading/sequence_local_storage_slot.h"
#include "content/browser/gpu/gpu_process_host.h"
#include "content/browser/media/cdm_registry_impl.h"
#include "content/browser/media/media_devices_util.h"
#include "content/browser/media/media_web_contents_observer.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/browser/media/parc_media_routing.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/gpu_service_registry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/cdm_info.h"
#include "crypto/hash.h"
#include "media/base/cdm_factory.h"
#include "media/base/key_system_names.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "third_party/blink/public/mojom/mediastream/media_devices.mojom-shared.h"
#include "third_party/parc_fairplay/chromium/fairplay_key_system.h"
#include "url/origin.h"

namespace parc {
namespace {

media::mojom::FairPlayMediaService& FairPlayMediaService() {
  static base::SequenceLocalStorageSlot<
      mojo::Remote<media::mojom::FairPlayMediaService>>
      remote_slot;
  mojo::Remote<media::mojom::FairPlayMediaService>& remote =
      remote_slot.GetOrCreateValue();
  if (!remote) {
    auto receiver = remote.BindNewPipeAndPassReceiver();
    remote.reset_on_disconnect();
    if (content::GpuProcessHost::Get()) {
      content::BindInterfaceInGpuProcess(std::move(receiver));
    }
  }
  return *remote.get();
}

class RendererClientExtensionProxy final
    : public media::mojom::FairPlayRendererClientExtension {
 public:
  RendererClientExtensionProxy(
      mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
          client,
      content::AudibilityBypassTracker::ScopedGrant grant)
      : client_(std::move(client)), grant_(std::move(grant)) {}

  void OnLayerRegistered(const base::UnguessableToken& layer_token,
                         const gfx::Size& natural_size) final {
    client_->OnLayerRegistered(layer_token, natural_size);
  }
  void OnRendererExtension(
      mojo::PendingRemote<media::mojom::FairPlayRendererExtension> extension)
      final {
    client_->OnRendererExtension(std::move(extension));
  }

 private:
  mojo::Remote<media::mojom::FairPlayRendererClientExtension> client_;
  content::AudibilityBypassTracker::ScopedGrant grant_;
};

class HlsPlayerLifetime final
    : public media::mojom::FairPlayHlsPlayerLifetime {
 public:
  explicit HlsPlayerLifetime(
      content::AudibilityBypassTracker::ScopedGrant grant)
      : grant_(std::move(grant)) {}

 private:
  content::AudibilityBypassTracker::ScopedGrant grant_;
};

}

FairPlayDocumentHost::FairPlayDocumentHost(content::RenderFrameHost* frame)
    : DocumentUserData(frame),
      WebContentsObserver(content::WebContents::FromRenderFrameHost(frame)) {}

FairPlayDocumentHost::~FairPlayDocumentHost() = default;

void FairPlayDocumentHost::BindMediaHost(
    content::RenderFrameHost* frame,
    mojo::PendingReceiver<media::mojom::FairPlayMediaHost> receiver) {
  FairPlayDocumentHost* host = GetOrCreateForCurrentDocument(frame);
  host->media_host_receivers_.Add(host, std::move(receiver));
}

bool FairPlayDocumentHost::CreateCdm(
    content::RenderFrameHost& frame,
    const media::CdmConfig& cdm_config,
    media::mojom::FairPlayFrameMedia::CreateCdmCallback& callback) {
  if (cdm_config.key_system != fairplay::kFairPlayKeySystem &&
      !media::IsSubKeySystemOf(cdm_config.key_system,
                               fairplay::kFairPlayKeySystem)) {
    return false;
  }
  if (!fairplay::IsFairPlayKeySystem(cdm_config.key_system) ||
      !content::CdmRegistryImpl::GetInstance()->GetCdmInfo(
          cdm_config.key_system,
          content::CdmInfo::Robustness::kSoftwareSecure)) {
    std::move(callback).Run(mojo::NullRemote(), nullptr,
                            media::CreateCdmStatus::kUnsupportedKeySystem);
    return true;
  }
  FairPlayDocumentHost* host = GetOrCreateForCurrentDocument(&frame);
  host->fairplay_playback_context_ = true;
  host->FrameMedia().CreateCdm(
      cdm_config, mojo::WrapCallbackWithDefaultInvokeIfNotRun(
                      std::move(callback), mojo::NullRemote(), nullptr,
                      media::CreateCdmStatus::kDisconnectionError));
  return true;
}

void FairPlayDocumentHost::CreateRenderer(
    int32_t player_id,
    mojo::PendingReceiver<media::mojom::Renderer> receiver,
    mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
        client_extension) {
  if (!fairplay_playback_context_ &&
      !fairplay::FramePresentsSafariIdentity(&render_frame_host())) {
    return;
  }
  mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
      gpu_client_extension;
  mojo::MakeSelfOwnedReceiver(
      std::make_unique<RendererClientExtensionProxy>(
          std::move(client_extension),
          content::ParcAddPlayerGrant(&render_frame_host(), player_id)),
      gpu_client_extension.InitWithNewPipeAndPassReceiver());
  FrameMedia().CreateRenderer(std::move(receiver),
                              std::move(gpu_client_extension));
}

void FairPlayDocumentHost::CreateHlsPlayer(
    int32_t player_id,
    mojo::PendingReceiver<media::mojom::FairPlayHlsPlayer> player,
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client) {
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayerLifetime> lifetime;
  mojo::MakeSelfOwnedReceiver(
      std::make_unique<HlsPlayerLifetime>(
          content::ParcAddPlayerGrant(&render_frame_host(), player_id)),
      lifetime.InitWithNewPipeAndPassReceiver());
  FrameMedia().CreateHlsPlayer(std::move(player), std::move(client),
                               std::move(lifetime));
}

void FairPlayDocumentHost::CreateMuteStateHandoff(
    CreateMuteStateHandoffCallback callback) {
  FrameMedia().CreateMuteStateHandoff(
      mojo::WrapCallbackWithDefaultInvokeIfNotRun(std::move(callback),
                                                  std::nullopt));
}

void FairPlayDocumentHost::GetStorageDirectory(
    GetStorageDirectoryCallback callback) {
  content::BrowserContext* browser_context =
      render_frame_host().GetBrowserContext();
  const url::Origin& top_origin =
      render_frame_host().GetOutermostMainFrame()->GetLastCommittedOrigin();
  const url::Origin& origin = render_frame_host().GetLastCommittedOrigin();
  if (browser_context->IsOffTheRecord() || browser_context->GetPath().empty() ||
      top_origin.opaque() || origin.opaque()) {
    std::move(callback).Run(base::FilePath());
    return;
  }
  const base::FilePath directory =
      browser_context->GetPath()
          .Append(FILE_PATH_LITERAL("Parc FairPlay"))
          .Append(FILE_PATH_LITERAL("MediaKeys"))
          .AppendASCII(
              base::HexEncode(crypto::hash::Sha256(top_origin.Serialize())))
          .AppendASCII(
              base::HexEncode(crypto::hash::Sha256(origin.Serialize())));
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_BLOCKING},
      base::BindOnce(
          [](const base::FilePath& directory) {
            return base::CreateDirectory(directory) ? directory
                                                    : base::FilePath();
          },
          directory),
      std::move(callback));
}

void FairPlayDocumentHost::GetDeviceIdSalt(GetDeviceIdSaltCallback callback) {
  if (render_frame_host().IsInLifecycleState(
          content::RenderFrameHost::LifecycleState::kPrerendering)) {
    std::move(callback).Run(std::string());
    return;
  }
  content::GetMediaDeviceSaltAndOrigin(
      render_frame_host().GetGlobalId(),
      base::BindOnce(
          [](GetDeviceIdSaltCallback callback,
             const content::MediaDeviceSaltAndOrigin& salt_and_origin) {
            std::move(callback).Run(salt_and_origin.device_id_salt());
          },
          std::move(callback)));
}

void FairPlayDocumentHost::IsEphemeralSession(
    IsEphemeralSessionCallback callback) {
  std::move(callback).Run(
      render_frame_host().GetBrowserContext()->IsOffTheRecord());
}

void FairPlayDocumentHost::GetAudioOutputDeviceUid(
    const std::string& hashed_device_id,
    GetAudioOutputDeviceUidCallback callback) {
  content::GetRawDeviceIdFromHMAC(
      render_frame_host().GetGlobalId(), hashed_device_id,
      blink::mojom::MediaDeviceType::kMediaAudioOutput, std::move(callback));
}

void FairPlayDocumentHost::RegisterMuteStateObserver(
    mojo::PendingRemote<media::mojom::FairPlayMuteStateObserver> observer) {
  auto id = mute_state_observers_.Add(std::move(observer));
  mute_state_observers_.Get(id)->OnMuteStateChange(
      web_contents()->IsAudioMuted());
}

void FairPlayDocumentHost::DidUpdateAudioMutingState(bool muted) {
  for (const auto& observer : mute_state_observers_) {
    observer->OnMuteStateChange(muted);
  }
}

media::mojom::FairPlayFrameMedia& FairPlayDocumentHost::FrameMedia() {
  if (!frame_media_) {
    mojo::PendingRemote<media::mojom::FairPlayFrameHost> frame_host;
    frame_host_receivers_.Add(this,
                              frame_host.InitWithNewPipeAndPassReceiver());
    FairPlayMediaService().CreateFrameMedia(
        render_frame_host().GetProcess()->GetDeprecatedID(),
        std::move(frame_host), frame_media_.BindNewPipeAndPassReceiver());
    frame_media_.reset_on_disconnect();
  }
  return *frame_media_.get();
}

DOCUMENT_USER_DATA_KEY_IMPL(FairPlayDocumentHost);

}

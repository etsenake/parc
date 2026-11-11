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

// The GPU process's FairPlay media service, reconnected after it restarts.
// Sequence-local on the UI thread, as content::GetMediaService() keeps its
// own.
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

// Forwards the FairPlay Renderer's client extension from the GPU process to
// the render process, and holds the document's audibility-bypass grant while
// that Renderer lives. Its audio plays through AVSampleBufferAudioRenderer, not
// the audio service, so this is how AudioStreamMonitor may count it audible.
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

// The browser's end of a native HLS player's lifetime handle. It holds the
// document's audibility-bypass grant until the GPU player closes the pipe:
// AVPlayer's audio goes straight to CoreAudio, not through the audio service,
// so this is how AudioStreamMonitor may count the player audible.
class HlsPlayerLifetime final
    : public media::mojom::FairPlayHlsPlayerLifetime {
 public:
  explicit HlsPlayerLifetime(
      content::AudibilityBypassTracker::ScopedGrant grant)
      : grant_(std::move(grant)) {}

 private:
  content::AudibilityBypassTracker::ScopedGrant grant_;
};

}  // namespace

FairPlayDocumentHost::FairPlayDocumentHost(content::RenderFrameHost* frame)
    : DocumentUserData(frame),
      WebContentsObserver(content::WebContents::FromRenderFrameHost(frame)) {}

FairPlayDocumentHost::~FairPlayDocumentHost() = default;

// static
void FairPlayDocumentHost::BindMediaHost(
    content::RenderFrameHost* frame,
    mojo::PendingReceiver<media::mojom::FairPlayMediaHost> receiver) {
  FairPlayDocumentHost* host = GetOrCreateForCurrentDocument(frame);
  host->media_host_receivers_.Add(host, std::move(receiver));
}

// static
bool FairPlayDocumentHost::CreateCdm(
    content::RenderFrameHost& frame,
    const media::CdmConfig& cdm_config,
    media::mojom::FairPlayFrameMedia::CreateCdmCallback& callback) {
  // Everything the FairPlay CdmInfo matches (CdmRegistryImpl::MatchKeySystem
  // takes any sub key system) stays here: Chromium's library CDM path would
  // hit its empty-CDM-path NOTREACHED for a name like "com.apple.fps.".
  if (cdm_config.key_system != fairplay::kFairPlayKeySystem &&
      !media::IsSubKeySystemOf(cdm_config.key_system,
                               fairplay::kFairPlayKeySystem)) {
    return false;
  }
  // Like every other CDM, only once registered (CdmRegistryImpl::Init), so a
  // renderer can't create one that Blink never offered.
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
  // The GPU process may drop the callback, when it crashes for one; the
  // trusted browser answers then, as MediaInterfaceProxy does.
  host->FrameMedia().CreateCdm(
      cdm_config, mojo::WrapCallbackWithDefaultInvokeIfNotRun(
                      std::move(callback), mojo::NullRemote(), nullptr,
                      media::CreateCdmStatus::kDisconnectionError));
  return true;
}

void FairPlayDocumentHost::CreateRenderer(
    mojo::PendingReceiver<media::mojom::Renderer> receiver,
    mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
        client_extension) {
  // Only for documents that created a FairPlay CDM, the only CDM it plays
  // with, or that present Safari's identity, where Dolby Vision plays through
  // it with or without keys (as Safari plays it); so a renderer can't reach
  // its parsers or claim audibility otherwise.
  if (!fairplay_playback_context_ &&
      !fairplay::FramePresentsSafariIdentity(&render_frame_host())) {
    return;
  }
  mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
      gpu_client_extension;
  mojo::MakeSelfOwnedReceiver(
      std::make_unique<RendererClientExtensionProxy>(
          std::move(client_extension),
          content::AudibilityBypassTracker::AddGrant(&render_frame_host())),
      gpu_client_extension.InitWithNewPipeAndPassReceiver());
  FrameMedia().CreateRenderer(std::move(receiver),
                              std::move(gpu_client_extension));
}

void FairPlayDocumentHost::CreateHlsPlayer(
    mojo::PendingReceiver<media::mojom::FairPlayHlsPlayer> player,
    mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client) {
  mojo::PendingRemote<media::mojom::FairPlayHlsPlayerLifetime> lifetime;
  mojo::MakeSelfOwnedReceiver(
      std::make_unique<HlsPlayerLifetime>(
          content::AudibilityBypassTracker::AddGrant(&render_frame_host())),
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

// WebKit's per-origin MediaKeys directory (Document::mediaKeysStorageDirectory:
// the website data store's directory for the top origin and the document's
// origin), where AVFoundation keeps expired-session reports. It is inside the
// Profile's engine folder, so it goes with the Profile: "Parc
// FairPlay/MediaKeys/" then the SHA-256 of the top-level origin and of the
// frame's origin. None off the record or for an opaque origin, as Safari keeps
// none for an ephemeral session or a document without storage access.
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
  // Created here, where the GPU process's sandbox needn't allow creating the
  // folders above it.
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

// WebKit's MediaKeys hash salt, DeviceIdHashSaltStorage's salt for the
// document origin and top-level origin, which seeds the randomized device
// identifier in the FairPlay CDM's SPCs. Chromium's media device ID salt is
// the same kind: per storage key (top-level site and origin), replaced when
// the user clears site data, in memory off the record. None while
// prerendering, when no CDM is made.
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

// WebKit's ephemeral session for the native HLS player's asset.
void FairPlayDocumentHost::IsEphemeralSession(
    IsEphemeralSessionCallback callback) {
  std::move(callback).Run(
      render_frame_host().GetBrowserContext()->IsOffTheRecord());
}

// As MediaWebContentsObserver translates a player's audio output sink.
void FairPlayDocumentHost::GetAudioOutputDeviceUid(
    const std::string& hashed_device_id,
    GetAudioOutputDeviceUidCallback callback) {
  content::GetRawDeviceIdFromHMAC(
      render_frame_host().GetGlobalId(), hashed_device_id,
      blink::mojom::MediaDeviceType::kMediaAudioOutput, std::move(callback));
}

// The FairPlay Renderer's and native HLS player's audio bypasses the audio
// service, so they take the tab's mute from here, as MediaFoundation's
// renderer does on Windows: the current state at once, then every change.
void FairPlayDocumentHost::RegisterMuteStateObserver(
    mojo::PendingRemote<media::mojom::MuteStateObserver> observer) {
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

}  // namespace parc

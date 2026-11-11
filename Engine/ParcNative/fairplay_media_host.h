// Copyright 2026 Parc contributors.
// The browser's end of Parc's FairPlay media service, one per document. It
// serves the document's render process (media.mojom.FairPlayMediaHost) and its
// FairPlay media in the GPU process (media.mojom.FairPlayFrameHost), and keeps
// what the browser decides for them: which documents may create FairPlay
// Renderers, the tab mute, the CDM storage and device ID salt, the audio
// output, and the audibility grants that put a FairPlay player in the tab's
// speaker indicator.
#ifndef PARC_NATIVE_FAIRPLAY_MEDIA_HOST_H_
#define PARC_NATIVE_FAIRPLAY_MEDIA_HOST_H_

#include <string>

#include "content/public/browser/document_user_data.h"
#include "content/public/browser/web_contents_observer.h"
#include "media/base/cdm_config.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/bindings/remote_set.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"

namespace parc {

class FairPlayDocumentHost final
    : public content::DocumentUserData<FairPlayDocumentHost>,
      public content::WebContentsObserver,
      public media::mojom::FairPlayMediaHost,
      public media::mojom::FairPlayFrameHost {
 public:
  FairPlayDocumentHost(const FairPlayDocumentHost&) = delete;
  FairPlayDocumentHost& operator=(const FairPlayDocumentHost&) = delete;
  ~FairPlayDocumentHost() override;

  // The frame's binder (RegisterBrowserInterfaceBindersForFrame).
  static void BindMediaHost(
      content::RenderFrameHost* frame,
      mojo::PendingReceiver<media::mojom::FairPlayMediaHost> receiver);

  // parc_hooks::SetFairPlayCdmCreator's creator: a FairPlay Streaming key
  // system's CDM comes from the document's FairPlay media. False for any
  // other key system.
  static bool CreateCdm(
      content::RenderFrameHost& frame,
      const media::CdmConfig& cdm_config,
      media::mojom::FairPlayFrameMedia::CreateCdmCallback& callback);

  // media::mojom::FairPlayMediaHost:
  void CreateRenderer(
      mojo::PendingReceiver<media::mojom::Renderer> receiver,
      mojo::PendingRemote<media::mojom::FairPlayRendererClientExtension>
          client_extension) override;
  void CreateHlsPlayer(
      mojo::PendingReceiver<media::mojom::FairPlayHlsPlayer> player,
      mojo::PendingRemote<media::mojom::FairPlayHlsPlayerClient> client)
      override;
  void CreateMuteStateHandoff(CreateMuteStateHandoffCallback callback) override;

  // media::mojom::FairPlayFrameHost:
  void GetStorageDirectory(GetStorageDirectoryCallback callback) override;
  void GetDeviceIdSalt(GetDeviceIdSaltCallback callback) override;
  void IsEphemeralSession(IsEphemeralSessionCallback callback) override;
  void GetAudioOutputDeviceUid(
      const std::string& hashed_device_id,
      GetAudioOutputDeviceUidCallback callback) override;
  void RegisterMuteStateObserver(
      mojo::PendingRemote<media::mojom::FairPlayMuteStateObserver> observer)
      override;

  // content::WebContentsObserver:
  void DidUpdateAudioMutingState(bool muted) override;

 private:
  friend content::DocumentUserData<FairPlayDocumentHost>;
  explicit FairPlayDocumentHost(content::RenderFrameHost* frame);
  DOCUMENT_USER_DATA_KEY_DECL();

  // The document's FairPlay media in the GPU process, connected on first use
  // and again after the GPU process restarts.
  media::mojom::FairPlayFrameMedia& FrameMedia();

  // Set once the document asked for a registered FairPlay CDM. Only then, or
  // on a Safari-identity document, are FairPlay Renderers created.
  bool fairplay_playback_context_ = false;
  mojo::ReceiverSet<media::mojom::FairPlayMediaHost> media_host_receivers_;
  mojo::ReceiverSet<media::mojom::FairPlayFrameHost> frame_host_receivers_;
  mojo::RemoteSet<media::mojom::FairPlayMuteStateObserver>
      mute_state_observers_;
  mojo::Remote<media::mojom::FairPlayFrameMedia> frame_media_;
};

}  // namespace parc

#endif  // PARC_NATIVE_FAIRPLAY_MEDIA_HOST_H_

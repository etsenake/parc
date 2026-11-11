// Installed by the reviewed overlay at
// //third_party/parc_fairplay/chromium/fairplay_media_service.h.
//
// Parc's FairPlay media service in the GPU process
// (media.mojom.FairPlayMediaService): each document's FairPlay CDMs, FairPlay
// Renderers and native HLS players, hosted with upstream's MojoCdmService and
// MojoRendererService on a single-thread task runner configured like the GPU
// media service's runner. Every document of one render process shares one
// MojoCdmServiceContext, so a player a Safari-identity page moved to another
// frame still finds its CDM, and no other process can name it.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_MEDIA_SERVICE_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_MEDIA_SERVICE_H_

#include <map>
#include <memory>
#include <set>
#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/unguessable_token.h"
#include "media/base/cdm_config.h"
#include "media/base/cdm_factory.h"
#include "media/mojo/services/deferred_destroy_unique_receiver_set.h"
#include "media/mojo/services/mojo_cdm_service.h"
#include "media/mojo/services/mojo_cdm_service_context.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/bindings/unique_receiver_set.h"
#include "third_party/parc_fairplay/chromium/fairplay_cdm_factory.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"

namespace media {

class FairPlayFrameMedia;

// The FairPlay media of one render process's documents, alive while any of
// them is.
class FairPlayProcessMedia final
    : public base::RefCounted<FairPlayProcessMedia> {
 public:
  // The process's, made when its first document connects.
  static scoped_refptr<FairPlayProcessMedia> Get(int render_process_id);

  FairPlayProcessMedia(const FairPlayProcessMedia&) = delete;
  FairPlayProcessMedia& operator=(const FairPlayProcessMedia&) = delete;

  MojoCdmServiceContext& cdm_service_context() { return cdm_service_context_; }

  void AddFrame(FairPlayFrameMedia* frame);
  void RemoveFrame(FairPlayFrameMedia* frame);

  // The tab mute observer one of the process's documents made for |handoff|
  // (FairPlayFrameMedia.CreateMuteStateHandoff), once, or an invalid one.
  mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> TakeMuteStateHandoff(
      const base::UnguessableToken& handoff);

 private:
  friend class base::RefCounted<FairPlayProcessMedia>;

  explicit FairPlayProcessMedia(int render_process_id);
  ~FairPlayProcessMedia();

  const int render_process_id_;
  MojoCdmServiceContext cdm_service_context_;
  std::set<raw_ptr<FairPlayFrameMedia, SetExperimental>> frames_;
};

// One document's FairPlay media, the FairPlay part of what InterfaceFactoryImpl
// is for a frame. It outlives its pipe while its CDMs, renderers or players
// do, as a CDM outlives its frame while its MediaKeys live.
class FairPlayFrameMedia final
    : public DeferredDestroy<mojom::FairPlayFrameMedia> {
 public:
  FairPlayFrameMedia(scoped_refptr<FairPlayProcessMedia> process,
                     mojo::PendingRemote<mojom::FairPlayFrameHost> frame_host);
  FairPlayFrameMedia(const FairPlayFrameMedia&) = delete;
  FairPlayFrameMedia& operator=(const FairPlayFrameMedia&) = delete;
  ~FairPlayFrameMedia() override;

  // mojom::FairPlayFrameMedia:
  void CreateCdm(const CdmConfig& cdm_config,
                 CreateCdmCallback callback) override;
  void CreateRenderer(
      mojo::PendingReceiver<mojom::Renderer> receiver,
      mojo::PendingRemote<mojom::FairPlayRendererClientExtension>
          client_extension) override;
  void CreateHlsPlayer(
      mojo::PendingReceiver<mojom::FairPlayHlsPlayer> player,
      mojo::PendingRemote<mojom::FairPlayHlsPlayerClient> client,
      mojo::PendingRemote<mojom::FairPlayHlsPlayerLifetime> lifetime) override;
  void CreateMuteStateHandoff(CreateMuteStateHandoffCallback callback) override;

  // DeferredDestroy<mojom::FairPlayFrameMedia>:
  void OnDestroyPending(base::OnceClosure destroy_cb) override;

  // The observer CreateMuteStateHandoff() made here for |handoff|, or an
  // invalid one.
  mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> TakeMuteStateHandoff(
      const base::UnguessableToken& handoff);

 private:
  void OnCdmServiceInitialized(MojoCdmService* raw_mojo_cdm_service,
                               CreateCdmCallback callback,
                               mojom::CdmContextPtr cdm_context,
                               CreateCdmStatus status);
  bool IsEmpty() const;
  void OnReceiverDisconnect();

  // Declared first, so it goes last: the CDMs, renderers and players below
  // use its MojoCdmServiceContext.
  const scoped_refptr<FairPlayProcessMedia> process_;
  // Before the CDM factory and renderers, which keep pointers to it.
  mojo::Remote<mojom::FairPlayFrameHost> frame_host_;
  FairPlayCdmFactory cdm_factory_;
  mojo::UniqueReceiverSet<mojom::Renderer> renderer_receivers_;
  mojo::UniqueReceiverSet<mojom::ContentDecryptionModule> cdm_receivers_;
  std::map<MojoCdmService*, std::unique_ptr<MojoCdmService>>
      pending_mojo_cdm_services_;
  // Tab mute observers the browser holds the other ends of, until a player
  // follows them; the oldest go past a few.
  std::vector<
      std::pair<base::UnguessableToken,
                mojo::PendingReceiver<mojom::FairPlayMuteStateObserver>>>
      mute_state_handoffs_;
  // After the CDMs, so they go first: they hold CdmContextRefs.
  mojo::UniqueReceiverSet<mojom::FairPlayHlsPlayer> hls_player_receivers_;
  base::OnceClosure destroy_cb_;
  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayFrameMedia> weak_factory_{this};
};

class FairPlayMediaService final : public mojom::FairPlayMediaService {
 public:
  FairPlayMediaService();
  FairPlayMediaService(const FairPlayMediaService&) = delete;
  FairPlayMediaService& operator=(const FairPlayMediaService&) = delete;
  ~FairPlayMediaService() override;

  void Bind(mojo::PendingReceiver<mojom::FairPlayMediaService> receiver);

  // mojom::FairPlayMediaService:
  void CreateFrameMedia(
      int32_t render_process_id,
      mojo::PendingRemote<mojom::FairPlayFrameHost> frame_host,
      mojo::PendingReceiver<mojom::FairPlayFrameMedia> frame_media) override;

 private:
  mojo::ReceiverSet<mojom::FairPlayMediaService> receivers_;
  DeferredDestroyUniqueReceiverSet<mojom::FairPlayFrameMedia>
      frame_media_receivers_;
};

// The thread the GPU process's service runs on, chosen as the GPU media
// service chooses its own (GpuServiceFactory::RunMediaService). Called once,
// on the GPU main thread.
scoped_refptr<base::SequencedTaskRunner> CreateFairPlayMediaServiceTaskRunner();

// Binds |receiver| to the GPU process's service, on that thread.
void BindFairPlayMediaService(
    mojo::PendingReceiver<mojom::FairPlayMediaService> receiver);

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_MEDIA_SERVICE_H_

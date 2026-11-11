#include "third_party/parc_fairplay/chromium/fairplay_media_service.h"

#include <algorithm>
#include <optional>
#include <string>

#include "base/check.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/task/thread_pool.h"
#include "media/audio/audio_device_description.h"
#include "media/base/media_switches.h"
#include "media/mojo/services/mojo_demuxer_stream_adapter.h"
#include "media/mojo/services/mojo_renderer_service.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "third_party/parc_fairplay/chromium/fairplay_hls_player_service.h"
#include "third_party/parc_fairplay/chromium/fairplay_renderer_adapter.h"

namespace media {

namespace {

// Each process's FairPlayProcessMedia, on the service's thread.
std::map<int, raw_ptr<FairPlayProcessMedia>>& Processes() {
  static base::NoDestructor<std::map<int, raw_ptr<FairPlayProcessMedia>>>
      processes;
  return *processes;
}

// HTMLMediaElement.setSinkId for a player whose audio bypasses the audio
// service. Runs |set_unique_id| with the Core Audio device each sink ID names
// (empty for the system default), as the browser resolves the page's hashed
// ID; an answer a later ID overtook is dropped, and a device the browser
// doesn't find leaves the output as it is.
base::RepeatingCallback<void(const std::string&)>
FairPlayAudioOutputDeviceSetter(
    mojom::FairPlayFrameHost* frame_host,
    base::RepeatingCallback<void(const std::string&)> set_unique_id) {
  using Setter = base::RepeatingCallback<void(const std::string&)>;
  using Requests = base::RefCountedData<uint64_t>;
  return base::BindRepeating(
      [](mojom::FairPlayFrameHost* frame_host, const Setter& set,
         const scoped_refptr<Requests>& requests, const std::string& sink_id) {
        const uint64_t request = ++requests->data;
        if (AudioDeviceDescription::IsDefaultDevice(sink_id)) {
          set.Run(std::string());
          return;
        }
        frame_host->GetAudioOutputDeviceUid(
            sink_id,
            base::BindOnce(
                [](Setter set, scoped_refptr<Requests> requests,
                   uint64_t request,
                   const std::optional<std::string>& unique_id) {
                  if (unique_id && request == requests->data) {
                    set.Run(*unique_id);
                  }
                },
                set, requests, request));
      },
      frame_host, std::move(set_unique_id),
      base::MakeRefCounted<Requests>(0));
}

// Streams the render process adds to a playing FairPlay Renderer reach it
// once their config arrived. Owned by the renderer, with the streams.
class FairPlayRendererStreams final : public mojom::FairPlayRendererExtension {
 public:
  FairPlayRendererStreams(
      FairPlayRendererAdapter* renderer,
      mojo::PendingReceiver<mojom::FairPlayRendererExtension> receiver,
      FairPlayHlsPlayerService::MuteStateHandoffTaker take_mute_state_handoff,
      mojom::FairPlayFrameHost* frame_host)
      : renderer_(renderer),
        receiver_(this, std::move(receiver)),
        take_mute_state_handoff_(std::move(take_mute_state_handoff)),
        set_audio_output_device_(FairPlayAudioOutputDeviceSetter(
            frame_host,
            renderer->GetAudioOutputDeviceCallback())) {}
  ~FairPlayRendererStreams() final = default;

  void AddStream(uint32_t id,
                 mojo::PendingRemote<mojom::DemuxerStream> stream,
                 AddStreamCallback callback) final {
    if (streams_.contains(id)) {
      std::move(callback).Run();
      return;
    }
    // Answered even if the stream is dropped before it is ready: the render
    // process's track change waits for it.
    streams_[id] = std::make_unique<MojoDemuxerStreamAdapter>(
        std::move(stream),
        base::BindOnce(&FairPlayRendererStreams::OnStreamReady,
                       weak_factory_.GetWeakPtr(), id,
                       mojo::WrapCallbackWithDefaultInvokeIfNotRun(
                           std::move(callback))));
  }

  void RemoveStream(uint32_t id) final {
    // A stream the renderer keeps (video) stays alive with it.
    if (renderer_->RemoveStream(id)) {
      streams_.erase(id);
    }
  }

  void FollowMuteStateHandoff(const base::UnguessableToken& handoff) final {
    mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> observer =
        take_mute_state_handoff_.Run(handoff);
    if (observer) {
      renderer_->ReplaceMuteStateObserverCloser(BindFairPlayMuteStateObserver(
          std::move(observer), renderer_->GetMuteStateCallback()));
    }
  }

  void SetAudioOutputDevice(const std::string& sink_id) final {
    set_audio_output_device_.Run(sink_id);
  }

  void SetPlaybackRateAt(double rate,
                         base::TimeDelta time,
                         base::TimeTicks host_time) final {
    renderer_->SetPlaybackRateAt(rate, time, host_time);
  }

 private:
  void OnStreamReady(uint32_t id, AddStreamCallback callback) {
    renderer_->AddStream(id, streams_[id].get());
    std::move(callback).Run();
  }

  const raw_ptr<FairPlayRendererAdapter> renderer_;
  mojo::Receiver<mojom::FairPlayRendererExtension> receiver_;
  const FairPlayHlsPlayerService::MuteStateHandoffTaker
      take_mute_state_handoff_;
  const base::RepeatingCallback<void(const std::string&)>
      set_audio_output_device_;
  std::map<uint32_t, std::unique_ptr<MojoDemuxerStreamAdapter>> streams_;
  base::WeakPtrFactory<FairPlayRendererStreams> weak_factory_{this};
};

}  // namespace

// static
scoped_refptr<FairPlayProcessMedia> FairPlayProcessMedia::Get(
    int render_process_id) {
  auto found = Processes().find(render_process_id);
  if (found != Processes().end()) {
    return base::WrapRefCounted(found->second.get());
  }
  return base::WrapRefCounted(new FairPlayProcessMedia(render_process_id));
}

FairPlayProcessMedia::FairPlayProcessMedia(int render_process_id)
    : render_process_id_(render_process_id) {
  Processes()[render_process_id_] = this;
}

FairPlayProcessMedia::~FairPlayProcessMedia() {
  DCHECK(frames_.empty());
  Processes().erase(render_process_id_);
}

void FairPlayProcessMedia::AddFrame(FairPlayFrameMedia* frame) {
  frames_.insert(frame);
}

void FairPlayProcessMedia::RemoveFrame(FairPlayFrameMedia* frame) {
  frames_.erase(frame);
}

mojo::PendingReceiver<mojom::FairPlayMuteStateObserver>
FairPlayProcessMedia::TakeMuteStateHandoff(
    const base::UnguessableToken& handoff) {
  for (FairPlayFrameMedia* frame : frames_) {
    if (mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> observer =
            frame->TakeMuteStateHandoff(handoff)) {
      return observer;
    }
  }
  return {};
}

FairPlayFrameMedia::FairPlayFrameMedia(
    scoped_refptr<FairPlayProcessMedia> process,
    mojo::PendingRemote<mojom::FairPlayFrameHost> frame_host)
    : process_(std::move(process)),
      frame_host_(std::move(frame_host)),
      cdm_factory_(frame_host_.get()) {
  process_->AddFrame(this);
  // Unretained: the receivers belong to |this|, so their disconnect handlers
  // never run once it is gone.
  auto disconnect_cb = base::BindRepeating(
      &FairPlayFrameMedia::OnReceiverDisconnect, base::Unretained(this));
  renderer_receivers_.set_disconnect_handler(disconnect_cb);
  cdm_receivers_.set_disconnect_handler(disconnect_cb);
  hls_player_receivers_.set_disconnect_handler(disconnect_cb);
}

FairPlayFrameMedia::~FairPlayFrameMedia() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  process_->RemoveFrame(this);
}

void FairPlayFrameMedia::CreateCdm(const CdmConfig& cdm_config,
                                   CreateCdmCallback callback) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto mojo_cdm_service =
      std::make_unique<MojoCdmService>(&process_->cdm_service_context());
  MojoCdmService* raw_mojo_cdm_service = mojo_cdm_service.get();
  pending_mojo_cdm_services_[raw_mojo_cdm_service] =
      std::move(mojo_cdm_service);
  raw_mojo_cdm_service->Initialize(
      &cdm_factory_, cdm_config,
      base::BindOnce(&FairPlayFrameMedia::OnCdmServiceInitialized,
                     weak_factory_.GetWeakPtr(), raw_mojo_cdm_service,
                     std::move(callback)));
}

void FairPlayFrameMedia::OnCdmServiceInitialized(
    MojoCdmService* raw_mojo_cdm_service,
    CreateCdmCallback callback,
    mojom::CdmContextPtr cdm_context,
    CreateCdmStatus status) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto pending = pending_mojo_cdm_services_.find(raw_mojo_cdm_service);
  CHECK(pending != pending_mojo_cdm_services_.end());
  std::unique_ptr<MojoCdmService> mojo_cdm_service = std::move(pending->second);
  pending_mojo_cdm_services_.erase(pending);

  if (!cdm_context) {
    std::move(callback).Run(mojo::NullRemote(), nullptr, status);
    return;
  }

  mojo::PendingRemote<mojom::ContentDecryptionModule> remote;
  cdm_receivers_.Add(std::move(mojo_cdm_service),
                     remote.InitWithNewPipeAndPassReceiver());
  std::move(callback).Run(std::move(remote), std::move(cdm_context),
                          CreateCdmStatus::kSuccess);
}

void FairPlayFrameMedia::CreateRenderer(
    mojo::PendingReceiver<mojom::Renderer> receiver,
    mojo::PendingRemote<mojom::FairPlayRendererClientExtension>
        client_extension) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // The adapter keeps the client extension's pipe open for its lifetime: the
  // browser ties the document's audibility bypass to it.
  auto client =
      std::make_unique<mojo::Remote<mojom::FairPlayRendererClientExtension>>(
          std::move(client_extension));
  mojo::Remote<mojom::FairPlayRendererClientExtension>* client_remote =
      client.get();
  auto renderer = std::make_unique<FairPlayRendererAdapter>(
      base::SequencedTaskRunner::GetCurrentDefault(),
      base::BindRepeating(
          [](mojo::Remote<mojom::FairPlayRendererClientExtension>* remote,
             const base::UnguessableToken& layer_token,
             const gfx::Size& natural_size) {
            (*remote)->OnLayerRegistered(layer_token, natural_size);
          },
          base::Owned(std::move(client))));
  mojo::PendingRemote<mojom::FairPlayRendererExtension> extension;
  renderer->SetExtension(std::make_unique<FairPlayRendererStreams>(
      renderer.get(), extension.InitWithNewPipeAndPassReceiver(),
      base::BindRepeating(&FairPlayProcessMedia::TakeMuteStateHandoff,
                          process_),
      frame_host_.get()));
  (*client_remote)->OnRendererExtension(std::move(extension));
  // The document's tab mute, the way MediaFoundationRendererWrapper gets it:
  // the browser answers with the current state at once. The observer closes
  // with the renderer.
  mojo::PendingRemote<mojom::FairPlayMuteStateObserver> observer;
  renderer->SetMuteStateObserverCloser(BindFairPlayMuteStateObserver(
      observer.InitWithNewPipeAndPassReceiver(),
      renderer->GetMuteStateCallback()));
  frame_host_->RegisterMuteStateObserver(std::move(observer));
  // Served with the process's CDM context, so the Renderer's SetCdm() finds a
  // FairPlay CDM of this document or, for an element a Safari-identity page
  // moved here, of another document of its render process.
  renderer_receivers_.Add(
      std::make_unique<MojoRendererService>(&process_->cdm_service_context(),
                                            std::move(renderer)),
      std::move(receiver));
}

void FairPlayFrameMedia::CreateHlsPlayer(
    mojo::PendingReceiver<mojom::FairPlayHlsPlayer> player,
    mojo::PendingRemote<mojom::FairPlayHlsPlayerClient> client,
    mojo::PendingRemote<mojom::FairPlayHlsPlayerLifetime> lifetime) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  // Resolves SetCdm()'s ID as the FairPlay Renderer's does. Unretained: the
  // player belongs to |hls_player_receivers_|, which goes before |process_|.
  auto service = std::make_unique<FairPlayHlsPlayerService>(
      base::SequencedTaskRunner::GetCurrentDefault(),
      base::BindRepeating(
          &MojoCdmServiceContext::GetCdmContextRef,
          base::Unretained(&process_->cdm_service_context())),
      std::move(client), std::move(lifetime));
  service->SetMuteStateHandoffTaker(base::BindRepeating(
      &FairPlayProcessMedia::TakeMuteStateHandoff, process_));
  service->SetAudioOutputDeviceSetter(FairPlayAudioOutputDeviceSetter(
      frame_host_.get(), service->GetAudioOutputDeviceCallback()));
  // Its audio bypasses the audio service too, so it gets the tab's mute the
  // same way; the observer closes with the player.
  mojo::PendingRemote<mojom::FairPlayMuteStateObserver> observer;
  service->SetMuteStateObserverCloser(BindFairPlayMuteStateObserver(
      observer.InitWithNewPipeAndPassReceiver(),
      service->GetMuteStateCallback()));
  frame_host_->RegisterMuteStateObserver(std::move(observer));
  // WebKit's ephemeral session sets the asset's cache and URL logging;
  // Initialize waits for the answer (none is a persistent session).
  frame_host_->IsEphemeralSession(mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      service->GetEphemeralSessionCallback(), false));
  hls_player_receivers_.Add(std::move(service), std::move(player));
}

void FairPlayFrameMedia::CreateMuteStateHandoff(
    CreateMuteStateHandoffCallback callback) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!frame_host_.is_connected()) {
    std::move(callback).Run(std::nullopt);
    return;
  }
  // Few players move into one document at once; this bounds what a render
  // process can leave unfollowed.
  constexpr size_t kMaxMuteStateHandoffs = 8;
  if (mute_state_handoffs_.size() == kMaxMuteStateHandoffs) {
    mute_state_handoffs_.erase(mute_state_handoffs_.begin());
  }
  // The browser answers the observer with the tab's mute at once and on every
  // change; it queues until a player follows the handoff.
  mojo::PendingRemote<mojom::FairPlayMuteStateObserver> observer;
  const base::UnguessableToken handoff = base::UnguessableToken::Create();
  mute_state_handoffs_.emplace_back(handoff,
                                    observer.InitWithNewPipeAndPassReceiver());
  frame_host_->RegisterMuteStateObserver(std::move(observer));
  std::move(callback).Run(handoff);
}

mojo::PendingReceiver<mojom::FairPlayMuteStateObserver>
FairPlayFrameMedia::TakeMuteStateHandoff(
    const base::UnguessableToken& handoff) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  auto found = std::ranges::find(
      mute_state_handoffs_, handoff,
      &std::ranges::range_value_t<decltype(mute_state_handoffs_)>::first);
  if (found == mute_state_handoffs_.end()) {
    return {};
  }
  mojo::PendingReceiver<mojom::FairPlayMuteStateObserver> observer =
      std::move(found->second);
  mute_state_handoffs_.erase(found);
  return observer;
}

void FairPlayFrameMedia::OnDestroyPending(base::OnceClosure destroy_cb) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  destroy_cb_ = std::move(destroy_cb);
  if (IsEmpty()) {
    std::move(destroy_cb_).Run();
  }
}

bool FairPlayFrameMedia::IsEmpty() const {
  return renderer_receivers_.empty() && cdm_receivers_.empty() &&
         hls_player_receivers_.empty();
}

void FairPlayFrameMedia::OnReceiverDisconnect() {
  if (destroy_cb_ && IsEmpty()) {
    std::move(destroy_cb_).Run();
  }
}

FairPlayMediaService::FairPlayMediaService() = default;

FairPlayMediaService::~FairPlayMediaService() = default;

void FairPlayMediaService::Bind(
    mojo::PendingReceiver<mojom::FairPlayMediaService> receiver) {
  receivers_.Add(this, std::move(receiver));
}

void FairPlayMediaService::CreateFrameMedia(
    int32_t render_process_id,
    mojo::PendingRemote<mojom::FairPlayFrameHost> frame_host,
    mojo::PendingReceiver<mojom::FairPlayFrameMedia> frame_media) {
  frame_media_receivers_.Add(
      std::make_unique<FairPlayFrameMedia>(
          FairPlayProcessMedia::Get(render_process_id), std::move(frame_host)),
      std::move(frame_media));
}

scoped_refptr<base::SequencedTaskRunner>
CreateFairPlayMediaServiceTaskRunner() {
  // Match IsDedicatedMediaServiceThreadEnabled()'s task-runner policy on
  // macOS. The single-thread runner keeps one sequence but may share its
  // worker thread. Decoding and key work must not wait behind lower-priority
  // tasks, hence user blocking.
  if (!base::FeatureList::IsEnabled(kDedicatedMediaServiceThread)) {
    return base::SingleThreadTaskRunner::GetCurrentDefault();
  }
  if (base::FeatureList::IsEnabled(kUseSequencedTaskRunnerForMediaService)) {
    return base::ThreadPool::CreateSequencedTaskRunner(
        {base::TaskPriority::USER_BLOCKING});
  }
  return base::ThreadPool::CreateSingleThreadTaskRunner(
      {base::TaskPriority::USER_BLOCKING});
}

void BindFairPlayMediaService(
    mojo::PendingReceiver<mojom::FairPlayMediaService> receiver) {
  static base::NoDestructor<FairPlayMediaService> service;
  service->Bind(std::move(receiver));
}

}  // namespace media

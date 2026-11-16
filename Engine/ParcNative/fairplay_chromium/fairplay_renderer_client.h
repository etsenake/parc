#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/base/parc_renderer_extensions.h"
#include "media/base/renderer.h"
#include "media/base/renderer_client.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"
#include "ui/gfx/geometry/size.h"

namespace media {

class AudioRendererSink;
class MediaResource;
class MojoDemuxerStreamImpl;
class MojoRenderer;
class OutputDeviceInfo;
class VideoRendererSink;

class FairPlayRendererClient final
    : public Renderer,
      public ParcRendererExtension,
      public RendererClient,
      public mojom::FairPlayRendererClientExtension {
 public:
  FairPlayRendererClient(
      scoped_refptr<base::SequencedTaskRunner> media_task_runner,
      std::unique_ptr<MojoRenderer> mojo_renderer,
      mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
          client_extension_receiver,
      VideoRendererSink* sink,
      AudioRendererSink* audio_sink);
  FairPlayRendererClient(const FairPlayRendererClient&) = delete;
  FairPlayRendererClient& operator=(const FairPlayRendererClient&) = delete;
  ~FairPlayRendererClient() override;

  void Initialize(MediaResource* media_resource,
                  RendererClient* client,
                  PipelineStatusCallback init_cb) override;
  void SetCdm(CdmContext* cdm_context, CdmAttachedCB cdm_attached_cb) override;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) override;
  void Flush(base::OnceClosure flush_cb) override;
  void StartPlayingFrom(base::TimeDelta time) override;
  void SetPlaybackRate(double playback_rate) override;
  void SetVolume(float volume) override;
  void SetPreservesPitch(bool preserves_pitch) override;
  base::TimeDelta GetMediaTime() override;
  void OnTracksChanged(DemuxerStream::Type track_type,
                       DemuxerStream* stream,
                       base::OnceClosure change_completed_cb) override;
  RendererType GetRendererType() override;
  ParcRendererExtension* GetParcExtension() override;

  void ParcOnAudioOutputDeviceChanged() override;
  void ParcSetHidden(bool hidden) override;
  void ParcSetPlaybackRateAt(double playback_rate,
                             base::TimeDelta time,
                             base::TimeTicks host_time) override;

  void OnError(PipelineStatus status) override;
  void OnFallback(PipelineStatus status) override;
  void OnEnded() override;
  void OnStatisticsUpdate(const PipelineStatistics& stats) override;
  void OnBufferingStateChange(BufferingState state,
                              BufferingStateChangeReason reason) override;
  void OnWaiting(WaitingReason reason) override;
  void OnAudioConfigChange(const AudioDecoderConfig& config) override;
  void OnVideoConfigChange(const VideoDecoderConfig& config) override;
  void OnVideoNaturalSizeChange(const gfx::Size& size) override;
  void OnVideoOpacityChange(bool opaque) override;
  void OnVideoFrameRateChange(std::optional<int> fps) override;

  void OnLayerRegistered(const base::UnguessableToken& layer_token,
                         const gfx::Size& natural_size) override;
  void OnRendererExtension(
      mojo::PendingRemote<mojom::FairPlayRendererExtension> extension) override;

  void FollowMuteStateHandoff(
      const std::optional<base::UnguessableToken>& handoff,
      uint64_t order);

  base::WeakPtr<FairPlayRendererClient> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 private:
  class PlayedStreams;
  struct Played {
    Played();
    Played(Played&&);
    Played& operator=(Played&&);
    ~Played();
    raw_ptr<DemuxerStream> stream;
    std::unique_ptr<MojoDemuxerStreamImpl> proxy;
  };

  void PaintHoleFrame();
  void OnAudioOutputDeviceInfo(uint64_t query, OutputDeviceInfo info);

  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  std::unique_ptr<PlayedStreams> initial_streams_;
  std::unique_ptr<MojoRenderer> mojo_renderer_;
  mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
      pending_client_extension_receiver_;
  mojo::Receiver<mojom::FairPlayRendererClientExtension>
      client_extension_receiver_{this};
  const raw_ptr<VideoRendererSink> sink_;
  const scoped_refptr<AudioRendererSink> audio_sink_;

  raw_ptr<RendererClient> client_ = nullptr;
  raw_ptr<MediaResource> media_resource_ = nullptr;
  std::map<uint32_t, Played> played_;
  std::vector<std::unique_ptr<MojoDemuxerStreamImpl>> retired_proxies_;
  bool video_turned_off_ = false;
  uint32_t next_stream_id_ = 0;
  mojo::Remote<mojom::FairPlayRendererExtension> renderer_extension_;
  base::OnceClosure pending_track_change_;
  std::optional<base::UnguessableToken> layer_token_;
  gfx::Size natural_size_;
  bool hidden_ = false;
  std::optional<base::UnguessableToken> pending_mute_state_handoff_;
  uint64_t mute_state_handoff_order_ = 0;
  uint64_t audio_output_device_queries_ = 0;
  std::optional<std::string> pending_audio_output_device_;
  bool preserves_pitch_ = true;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayRendererClient> weak_factory_{this};
};

}

#endif

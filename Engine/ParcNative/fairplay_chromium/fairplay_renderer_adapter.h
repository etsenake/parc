// media::Renderer over the FairPlay core's FairPlayRenderer
// (AVSampleBufferDisplayLayer + AVSampleBufferAudioRenderer under an
// AVSampleBufferRenderSynchronizer), served by the GPU process's media service
// through MojoRendererService. It pulls DecoderBuffers from the page's
// DemuxerStreams (still encrypted), hands them to the core with their
// DecryptConfig, and joins the FairPlay CDM of the same media service as a
// content key recipient. The display layer is registered in
// ui::ProtectedLayerRegistry; the compositor places it where the render
// process's video hole frame is.
#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_

#include <stdint.h>

#include <memory>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/demuxer_stream.h"
#include "media/base/pipeline_status.h"
#include "media/base/renderer.h"
#include "media/base/video_decoder_config.h"
#include "third_party/parc_fairplay/core/fairplay_renderer.h"
#include "ui/gfx/geometry/size.h"

namespace media {

class CdmContext;
class MediaResource;
class RendererClient;

class FairPlayRendererAdapter final
    : public Renderer,
      public parc::fairplay::FairPlayRendererClient {
 public:
  // Run once, when the display layer is registered under |layer_token|, so
  // the render process's client can paint a video hole frame naming it. Kept
  // for the adapter's lifetime: whatever it binds (the client extension's
  // pipe) lives exactly as long as this renderer.
  using LayerRegisteredCB =
      base::RepeatingCallback<void(const base::UnguessableToken& layer_token,
                                   const gfx::Size& natural_size)>;

  FairPlayRendererAdapter(scoped_refptr<base::SequencedTaskRunner> task_runner,
                          LayerRegisteredCB layer_registered_cb);
  FairPlayRendererAdapter(const FairPlayRendererAdapter&) = delete;
  FairPlayRendererAdapter& operator=(const FairPlayRendererAdapter&) = delete;
  ~FairPlayRendererAdapter() override;

  // Renderer implementation.
  void Initialize(MediaResource* media_resource,
                  RendererClient* client,
                  PipelineStatusCallback init_cb) override;
  void SetCdm(CdmContext* cdm_context, CdmAttachedCB cdm_attached_cb) override;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) override;
  void Flush(base::OnceClosure flush_cb) override;
  void StartPlayingFrom(base::TimeDelta time) override;
  void SetPlaybackRate(double playback_rate) override;
  void SetVolume(float volume) override;
  base::TimeDelta GetMediaTime() override;
  RendererType GetRendererType() override;

  // The frame's mute state (tab mute). The audio bypasses Chromium's audio
  // service, so the browser's MuteStateObserver feeds this; it is bound to a
  // weak pointer and may outlive the adapter.
  base::RepeatingCallback<void(bool)> GetMuteStateCallback();
  // Called once the browser was asked for the mute state. Audio stays muted
  // until its first answer, so a muted tab never plays a moment of sound
  // while the answer is on its way. |closer| closes the observer when the
  // adapter is destroyed.
  void SetMuteStateObserverCloser(base::ScopedClosureRunner closer);

  // parc::fairplay::FairPlayRendererClient implementation.
  void OnNeedData(parc::fairplay::StreamType stream) override;
  void OnWaitingForKey() override;
  void OnEnded() override;
  void OnError(parc::fairplay::RendererError error,
               const std::string& description) override;
  void OnVideoNaturalSizeChange(int32_t width, int32_t height) override;
  void OnBufferingStateChange(bool have_enough) override;

 private:
  struct Stream {
    raw_ptr<DemuxerStream> demuxer_stream = nullptr;
    bool read_pending = false;
    bool end_of_stream = false;
  };

  Stream& StreamFor(parc::fairplay::StreamType type);
  void ReadFromStream(parc::fairplay::StreamType type);
  void OnBuffersRead(parc::fairplay::StreamType type,
                     uint64_t generation,
                     DemuxerStream::Status status,
                     DemuxerStream::DecoderBufferVector buffers);
  void HandleConfigChange(parc::fairplay::StreamType type);
  void EnqueueToCore(parc::fairplay::StreamType type,
                     const DecoderBuffer& buffer);
  void MaybeFinishFlush();
  void ReportError(PipelineStatus status);
  void SetMuted(bool muted);

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  const LayerRegisteredCB layer_registered_cb_;

  raw_ptr<RendererClient> client_ = nullptr;
  Stream video_;
  Stream audio_;
  VideoDecoderConfig video_config_;
  AudioDecoderConfig audio_config_;

  std::unique_ptr<parc::fairplay::FairPlayRenderer> core_;
  bool core_initialized_ = false;
  bool cdm_attached_ = false;
  bool playing_ = false;
  bool errored_ = false;
  bool natural_size_reported_ = false;
  base::TimeDelta start_time_;
  float volume_ = 1;
  bool muted_ = false;
  bool awaiting_mute_state_ = false;

  // Bumped by Flush; reads issued before it are dropped when they return.
  uint64_t generation_ = 0;
  base::OnceClosure flush_cb_;
  bool core_flush_pending_ = false;

  base::UnguessableToken layer_token_;
  gfx::Size natural_size_;
  base::ScopedClosureRunner mute_state_observer_closer_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayRendererAdapter> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_

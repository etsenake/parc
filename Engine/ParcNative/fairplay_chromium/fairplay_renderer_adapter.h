#ifndef THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_
#define THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_

#include <stdint.h>

#include <map>
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
#include "base/timer/timer.h"
#include "base/unguessable_token.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/demuxer_stream.h"
#include "media/base/pipeline_status.h"
#include "media/base/renderer.h"
#include "media/base/video_decoder_config.h"
#include "third_party/parc_fairplay/chromium/fairplay_media.mojom.h"
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
  using LayerRegisteredCB =
      base::RepeatingCallback<void(const base::UnguessableToken& layer_token,
                                   const gfx::Size& natural_size)>;

  FairPlayRendererAdapter(scoped_refptr<base::SequencedTaskRunner> task_runner,
                          LayerRegisteredCB layer_registered_cb);
  FairPlayRendererAdapter(const FairPlayRendererAdapter&) = delete;
  FairPlayRendererAdapter& operator=(const FairPlayRendererAdapter&) = delete;
  ~FairPlayRendererAdapter() override;

  void Initialize(MediaResource* media_resource,
                  RendererClient* client,
                  PipelineStatusCallback init_cb) override;
  void SetCdm(CdmContext* cdm_context, CdmAttachedCB cdm_attached_cb) override;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) override;
  void Flush(base::OnceClosure flush_cb) override;
  void StartPlayingFrom(base::TimeDelta time) override;
  void SetPlaybackRate(double playback_rate) override;
  void SetPlaybackRateAt(double playback_rate,
                         base::TimeDelta time,
                         base::TimeTicks host_time);
  void SetPreservesPitch(bool preserves_pitch) override;
  void SetVolume(float volume) override;
  base::TimeDelta GetMediaTime() override;
  RendererType GetRendererType() override;

  base::RepeatingCallback<void(bool)> GetMuteStateCallback();
  base::RepeatingCallback<void(const std::string&)>
  GetAudioOutputDeviceCallback();
  void SetExtension(std::unique_ptr<mojom::FairPlayRendererExtension> extension);
  void AddStream(uint32_t id, DemuxerStream* stream);
  bool RemoveStream(uint32_t id);

  void SetMuteStateObserverCloser(base::ScopedClosureRunner closer);
  void ReplaceMuteStateObserverCloser(base::ScopedClosureRunner closer);

  void OnNeedData(parc::fairplay::StreamId stream) override;
  void OnWaitingForKey() override;
  void OnEnded() override;
  void OnError(parc::fairplay::RendererError error,
               const std::string& description) override;
  void OnVideoNaturalSizeChange(int32_t width, int32_t height) override;
  void OnBufferingStateChange(bool have_enough) override;

 private:
  struct Stream {
    raw_ptr<DemuxerStream> demuxer_stream = nullptr;
    parc::fairplay::StreamId core{parc::fairplay::StreamType::kVideo};
    bool read_pending = false;
    bool end_of_stream = false;
  };

  bool RegisterLayer();
  void ReadFromStream(uint32_t id);
  void OnBuffersRead(uint32_t id,
                     uint64_t generation,
                     DemuxerStream::Status status,
                     DemuxerStream::DecoderBufferVector buffers);
  void HandleConfigChange(Stream& stream);
  void EnqueueToCore(parc::fairplay::StreamId stream,
                     const DecoderBuffer& buffer);
  void MaybeFinishFlush();
  void ReportError(PipelineStatus status);
  void SetMuted(bool muted);
  void SetAudioOutputDevice(const std::string& unique_id);
  void UpdateStatisticsTimer();
  void PollStatistics();
  void RequestVideoMetrics();
  void OnVideoMetrics(const parc::fairplay::VideoMetrics& metrics);
  void ReportStatistics(int64_t frames_decoded, int64_t frames_dropped);

  const scoped_refptr<base::SequencedTaskRunner> task_runner_;
  const LayerRegisteredCB layer_registered_cb_;

  raw_ptr<RendererClient> client_ = nullptr;
  std::unique_ptr<mojom::FairPlayRendererExtension> extension_;
  std::map<uint32_t, Stream> streams_;

  std::unique_ptr<parc::fairplay::FairPlayRenderer> core_;
  bool core_initialized_ = false;
  bool core_has_video_ = false;
  raw_ptr<parc::fairplay::FairPlayCdm> attached_cdm_ = nullptr;
  bool playing_ = false;
  double playback_rate_ = 0;
  bool errored_ = false;
  bool natural_size_reported_ = false;
  base::TimeDelta start_time_;
  float volume_ = 1;
  bool muted_ = false;
  bool awaiting_mute_state_ = false;

  uint64_t generation_ = 0;
  base::OnceClosure flush_cb_;
  bool core_flush_pending_ = false;

  base::UnguessableToken layer_token_;
  gfx::Size natural_size_;
  base::ScopedClosureRunner mute_state_observer_closer_;

  base::RepeatingTimer statistics_timer_;
  base::TimeTicks video_metrics_requested_;
  int64_t reported_frames_decoded_ = 0;
  int64_t reported_frames_dropped_ = 0;
  uint64_t unreported_video_bytes_ = 0;
  uint64_t unreported_audio_bytes_ = 0;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayRendererAdapter> weak_factory_{this};
};

}

#endif

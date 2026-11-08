// media::Renderer over the FairPlay core's FairPlayRenderer
// (AVSampleBufferDisplayLayer + an AVSampleBufferAudioRenderer per audio stream
// under an AVSampleBufferRenderSynchronizer), served by the GPU process's media
// service through MojoRendererService. It plays every stream it is given (the
// first video, every audio stream, mixed) and pulls DecoderBuffers from the
// page's DemuxerStreams (still encrypted), hands them to the core with their
// DecryptConfig, and joins the FairPlay CDM of the same media service as a
// content key recipient. The display layer is registered in
// ui::ProtectedLayerRegistry; the compositor places it where the render
// process's video hole frame is. While the clock runs it reports the frames
// AVFoundation decoded and dropped (getVideoPlaybackQuality) and the bytes it
// was given, as the deltas RendererClient::OnStatisticsUpdate takes.
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
#include "media/mojo/mojom/renderer_extensions.mojom.h"
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
  // FairPlayRendererExtension.SetPlaybackRateAt
  // (FairPlayRenderer::SetPlaybackRateAt).
  void SetPlaybackRateAt(double playback_rate,
                         base::TimeDelta time,
                         base::TimeTicks host_time);
  void SetVolume(float volume) override;
  base::TimeDelta GetMediaTime() override;
  RendererType GetRendererType() override;

  // The frame's mute state (tab mute). The audio bypasses Chromium's audio
  // service, so the browser's MuteStateObserver feeds this; it is bound to a
  // weak pointer and may outlive the adapter.
  base::RepeatingCallback<void(bool)> GetMuteStateCallback();
  // HTMLMediaElement.setSinkId's Core Audio device UID (empty for the system
  // default), as the browser resolved it; bound to a weak pointer.
  base::RepeatingCallback<void(const std::string&)>
  GetAudioOutputDeviceCallback();
  // The render process's FairPlayRendererExtension, kept for the adapter's
  // lifetime; it owns the streams it adds.
  void SetExtension(std::unique_ptr<mojom::FairPlayRendererExtension> extension);
  // A stream the render process adds during playback (a SourceBuffer added
  // after the others), which joins the playing renderers without replacing
  // them (FairPlayRenderer::AddVideo, AddAudio). A video stream when there is
  // one already is a video track switch, or the track turned back on: it
  // replaces that one (FairPlayRenderer::ReplaceVideo). Streams given to
  // Initialize are named by their index there; |id| names this one, for
  // RemoveStream.
  void AddStream(uint32_t id, DemuxerStream* stream);
  // A stream the page turned off or replaced, read no more: an audio stream's
  // renderer leaves. False for video, whose stream then stays (the display
  // layer does; AddStream's next video stream replaces it).
  bool RemoveStream(uint32_t id);

  // Called once the browser was asked for the mute state. Audio stays muted
  // until its first answer, so a muted tab never plays a moment of sound
  // while the answer is on its way. |closer| closes the observer when the
  // adapter is destroyed.
  void SetMuteStateObserverCloser(base::ScopedClosureRunner closer);
  // For the frame a Safari-identity page moved the element to: the current
  // mute holds until that frame answers, so a move within a tab never cuts
  // the sound. |closer| replaces the old frame's.
  void ReplaceMuteStateObserverCloser(base::ScopedClosureRunner closer);

  // parc::fairplay::FairPlayRendererClient implementation.
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
  // Owns the streams it added, so it outlives |streams_|, which points at
  // them.
  std::unique_ptr<mojom::FairPlayRendererExtension> extension_;
  std::map<uint32_t, Stream> streams_;

  std::unique_ptr<parc::fairplay::FairPlayRenderer> core_;
  bool core_initialized_ = false;
  bool core_has_video_ = false;  // Its display layer exists.
  // The CDM accepted last, which MojoRendererService keeps alive for this
  // renderer; only compared, when the page sets the same MediaKeys again.
  raw_ptr<parc::fairplay::FairPlayCdm> attached_cdm_ = nullptr;
  bool playing_ = false;
  double playback_rate_ = 0;
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

  // Statistics. Frame totals already reported (cumulative, like the
  // sources); bytes enqueued since the last report.
  base::RepeatingTimer statistics_timer_;
  base::TimeTicks video_metrics_requested_;  // Null when none is outstanding.
  int64_t reported_frames_decoded_ = 0;
  int64_t reported_frames_dropped_ = 0;
  uint64_t unreported_video_bytes_ = 0;
  uint64_t unreported_audio_bytes_ = 0;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayRendererAdapter> weak_factory_{this};
};

}  // namespace media

#endif  // THIRD_PARTY_PARC_FAIRPLAY_CHROMIUM_FAIRPLAY_RENDERER_ADAPTER_H_

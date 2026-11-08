// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// The media::Renderer of Safari's native HLS route (NATIVE_HLS.md beside this
// file's source in the Parc repository): a render-process facade that drives
// the GPU AVPlayer owned by NativeHlsDemuxer. It decodes nothing. It maps the
// pipeline's play, pause, rate, seek and volume onto the player, passes
// AVFoundation's buffering, ended, waiting, error and frame-count reports to
// the pipeline as Safari's AVFoundation player reports them, answers the media
// time from the player's clock, and paints the video as a hole frame naming
// the player's AVPlayerLayer, exactly as FairPlayRendererClient does for the
// MSE route. Suspend and resume destroy and recreate only this facade.
#ifndef CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_H_
#define CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_H_

#include <stdint.h>

#include <atomic>
#include <optional>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/unguessable_token.h"
#include "content/renderer/media/fairplay/native_hls_demuxer.h"
#include "media/base/buffering_state.h"
#include "media/base/renderer.h"
#include "ui/gfx/geometry/size.h"

namespace media {
class AudioRendererSink;
class OutputDeviceInfo;
class RendererClient;
class VideoRendererSink;
}  // namespace media

namespace parc::fairplay {

class NativeHlsRenderer final : public media::Renderer,
                                public NativeHlsSource::Client {
 public:
  // Made on the main thread; every other call is on `media_task_runner`,
  // except GetMediaTime().
  NativeHlsRenderer(scoped_refptr<base::SequencedTaskRunner> media_task_runner,
                    media::VideoRendererSink* sink,
                    media::AudioRendererSink* audio_sink);
  NativeHlsRenderer(const NativeHlsRenderer&) = delete;
  NativeHlsRenderer& operator=(const NativeHlsRenderer&) = delete;
  ~NativeHlsRenderer() override;

  // media::Renderer.
  void Initialize(media::MediaResource* media_resource,
                  media::RendererClient* client,
                  media::PipelineStatusCallback init_cb) override;
  void SetCdm(media::CdmContext* cdm_context,
              CdmAttachedCB cdm_attached_cb) override;
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint) override;
  void SetPreservesPitch(bool preserves_pitch) override;
  void Flush(base::OnceClosure flush_cb) override;
  void StartPlayingFrom(base::TimeDelta time) override;
  void SetPlaybackRate(double playback_rate) override;
  void SetVolume(float volume) override;
  base::TimeDelta GetMediaTime() override;
  media::RendererType GetRendererType() override;
  // The player plays to the device the pipeline's audio sink names, from
  // Initialize() on.
  void ParcOnAudioOutputDeviceChanged() override;

  // NativeHlsSource::Client.
  void OnSourceBufferingStateChange(media::BufferingState state) override;
  void OnSourceEnded() override;
  void OnSourceError(media::PipelineStatus status) override;
  void OnSourceStatisticsUpdate(
      const media::PipelineStatistics& delta) override;
  void OnSourceWaiting(media::WaitingReason reason) override;
  void OnSourceNaturalSizeChange(const gfx::Size& size) override;
  void OnSourceLayerRegistered(const base::UnguessableToken& layer_token,
                               const gfx::Size& natural_size) override;

 private:
  // Reports `state` to the pipeline unless it already holds it. Before the
  // pipeline starts playback (and after a flush) nothing is reported:
  // RendererImpl's contract, which seeks and readyState follow.
  void ReportBufferingState(media::BufferingState state);
  // The player's buffering state after the StartPlayingFrom() numbered
  // `start`, reported in the task after it.
  void ReportStartState(uint64_t start);
  void PaintHoleFrame();
  void OnAudioOutputDeviceInfo(uint64_t query, media::OutputDeviceInfo info);

  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;
  const raw_ptr<media::VideoRendererSink> sink_;
  // HTMLMediaElement.setSinkId's sink, which names the device (hashed for
  // the frame's origin) but never plays.
  const scoped_refptr<media::AudioRendererSink> audio_sink_;
  // Answers to all but the last device query are dropped.
  uint64_t audio_output_device_queries_ = 0;

  raw_ptr<media::RendererClient> client_ = nullptr;
  base::WeakPtr<NativeHlsSource> source_;
  // Set in Initialize(). GetMediaTime() may run on any thread, from the
  // moment the pipeline holds this facade; the source outlives it (the
  // pipeline destroys its renderer before stopping the demuxer).
  std::atomic<NativeHlsSource*> time_source_{nullptr};

  // Between StartPlayingFrom() and Flush().
  bool playing_ = false;
  // StartPlayingFrom() calls so far.
  uint64_t starts_ = 0;
  media::BufferingState reported_buffering_state_ =
      media::BUFFERING_HAVE_NOTHING;
  bool ended_ = false;

  std::optional<base::UnguessableToken> layer_token_;
  gfx::Size natural_size_;

  // PipelineImpl sets the CDM, volume and pitch preservation before
  // Initialize(); they reach the source then, and again for every facade
  // made after a suspension.
  raw_ptr<media::CdmContext> pending_cdm_context_ = nullptr;
  CdmAttachedCB pending_cdm_attached_cb_;
  std::optional<float> volume_;
  std::optional<bool> preserves_pitch_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<NativeHlsRenderer> weak_factory_{this};
};

}  // namespace parc::fairplay

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_NATIVE_HLS_RENDERER_H_

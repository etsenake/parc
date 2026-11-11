// Installed by the reviewed overlay at //content/renderer/media/fairplay/.
// Render-process media::Renderer for FairPlay Streaming playback. It wraps the
// MojoRenderer connected to FairPlayRendererAdapter in the GPU process and
// paints the video as a hole frame naming the adapter's display layer: no
// VideoFrame ever carries the decrypted pixels, the compositor places the
// layer itself. The GPU process plays the enabled streams, every enabled audio
// stream mixed, as WebKit's AudioVideoRendererAVFObjC does; streams enabled
// later join it, and audio streams turned off leave.
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
#include "media/mojo/mojom/renderer_extensions.mojom.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
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
  // Constructed on the main thread; every other call is on
  // |media_task_runner|.
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
  // On Safari's Media Source (MediaResource::ParcMayAddStreams()) the
  // pipeline enabled |stream| (a SourceBuffer's track added during playback,
  // or one the page turned on): it joins the GPU process's renderers, with
  // every other enabled audio stream they don't play. Audio streams now
  // disabled leave; another video stream, or the video track turned back
  // on, replaces the one they play.
  void OnTracksChanged(DemuxerStream::Type track_type,
                       DemuxerStream* stream,
                       base::OnceClosure change_completed_cb) override;
  RendererType GetRendererType() override;
  ParcRendererExtension* GetParcExtension() override;

  // ParcRendererExtension implementation.
  // The GPU process's audio renderers play to the device the pipeline's
  // audio sink names, from Initialize on.
  void ParcOnAudioOutputDeviceChanged() override;
  // Taking over from Chromium's renderer (Pipeline::ParcHandOffToFairPlay()),
  // the video hole frame is painted only once shown.
  void ParcSetHidden(bool hidden) override;
  // Through FairPlayRendererExtension.SetPlaybackRateAt; dropped before the
  // GPU process sent the extension (the pipeline then starts it at the swap).
  void ParcSetPlaybackRateAt(double playback_rate,
                             base::TimeDelta time,
                             base::TimeTicks host_time) override;

  // RendererClient implementation, forwarded to the pipeline's client.
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

  // mojom::FairPlayRendererClientExtension implementation.
  void OnLayerRegistered(const base::UnguessableToken& layer_token,
                         const gfx::Size& natural_size) override;
  void OnRendererExtension(
      mojo::PendingRemote<mojom::FairPlayRendererExtension> extension) override;

  // The GPU process's renderer follows the tab mute of |handoff|'s frame
  // (FairPlayRendererExtension.FollowMuteStateHandoff), unless one asked for
  // later (a higher |order|) came first: the frames answer on their own pipes.
  // None (a frame without tab mute) still supersedes earlier ones.
  void FollowMuteStateHandoff(
      const std::optional<base::UnguessableToken>& handoff,
      uint64_t order);

  base::WeakPtr<FairPlayRendererClient> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

 private:
  class PlayedStreams;
  // A stream the GPU process plays, with the proxy that gave it there after
  // Initialize.
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
  // Outlives |mojo_renderer_|, which points at it.
  std::unique_ptr<PlayedStreams> initial_streams_;
  std::unique_ptr<MojoRenderer> mojo_renderer_;
  // Bound on |media_task_runner_| in Initialize().
  mojo::PendingReceiver<mojom::FairPlayRendererClientExtension>
      pending_client_extension_receiver_;
  mojo::Receiver<mojom::FairPlayRendererClientExtension>
      client_extension_receiver_{this};
  const raw_ptr<VideoRendererSink> sink_;
  // HTMLMediaElement.setSinkId's sink, which names the device (hashed for
  // the frame's origin) but never plays.
  const scoped_refptr<AudioRendererSink> audio_sink_;

  raw_ptr<RendererClient> client_ = nullptr;
  raw_ptr<MediaResource> media_resource_ = nullptr;
  // By the ID the GPU process names them with: their index among Initialize's
  // streams, then FairPlayRendererExtension::AddStream's.
  std::map<uint32_t, Played> played_;
  // The proxies of video streams a track switch replaced.
  std::vector<std::unique_ptr<MojoDemuxerStreamImpl>> retired_proxies_;
  // The page turned its video track off (a video track change with no
  // stream).
  bool video_turned_off_ = false;
  uint32_t next_stream_id_ = 0;
  mojo::Remote<mojom::FairPlayRendererExtension> renderer_extension_;
  // A track change from before |renderer_extension_| came (the pipeline
  // waits for one at a time).
  base::OnceClosure pending_track_change_;
  std::optional<base::UnguessableToken> layer_token_;
  gfx::Size natural_size_;
  bool hidden_ = false;
  // One from before |renderer_extension_| came.
  std::optional<base::UnguessableToken> pending_mute_state_handoff_;
  uint64_t mute_state_handoff_order_ = 0;
  // Answers to all but the last device query are dropped.
  uint64_t audio_output_device_queries_ = 0;
  // One from before |renderer_extension_| came.
  std::optional<std::string> pending_audio_output_device_;

  SEQUENCE_CHECKER(sequence_checker_);
  base::WeakPtrFactory<FairPlayRendererClient> weak_factory_{this};
};

}  // namespace media

#endif  // CONTENT_RENDERER_MEDIA_FAIRPLAY_FAIRPLAY_RENDERER_CLIENT_H_

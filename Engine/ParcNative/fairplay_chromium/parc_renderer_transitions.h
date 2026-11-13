#ifndef MEDIA_BASE_PARC_RENDERER_TRANSITIONS_H_
#define MEDIA_BASE_PARC_RENDERER_TRANSITIONS_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/sequence_checker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "media/base/buffering_state.h"
#include "media/base/pipeline_status.h"
#include "media/base/renderer.h"

namespace media {
class CdmContext;
class Demuxer;
class Renderer;
class RendererClient;
class SerialRunner;

class ParcRendererTransitions {
 public:
  class Host {
   public:
    virtual bool ParcIsPlaying() = 0;
    virtual double ParcPlaybackRate() = 0;
    virtual Demuxer* ParcDemuxer() = 0;
    virtual Renderer* ParcRenderer() = 0;
    virtual base::TimeDelta ParcCurrentTimestamp() = 0;
    virtual void ParcCreateFairPlayRenderer(
        base::OnceCallback<void(std::unique_ptr<Renderer>)> created) = 0;
    virtual void ParcConfigureRenderer(Renderer& renderer) = 0;
    virtual std::unique_ptr<Renderer> ParcReplaceRenderer(
        std::unique_ptr<Renderer> renderer) = 0;
    virtual void ParcOnPipelineError(PipelineStatus status) = 0;
    virtual CdmContext* ParcCdmContext() = 0;
    virtual void ParcSetCdmContext(CdmContext* cdm_context) = 0;
    virtual void ParcOnCdmAttached(
        base::OnceCallback<void(bool)> cdm_attached_cb,
        CdmContext* cdm_context,
        bool success) = 0;

   protected:
    virtual ~Host() = default;
  };

  ParcRendererTransitions(
      Host* host,
      RendererClient* client,
      scoped_refptr<base::SequencedTaskRunner> media_task_runner);
  ParcRendererTransitions(const ParcRendererTransitions&) = delete;
  ParcRendererTransitions& operator=(const ParcRendererTransitions&) = delete;
  ~ParcRendererTransitions();

  void HandOff(base::OnceCallback<void(bool)> done);
  Renderer* incoming() const { return incoming_.get(); }
  bool TakeOverAtSplit();
  void Settle();
  void Abort(bool restart);
  void DestroyRenderer(std::unique_ptr<Renderer> renderer);

  double RendererRate();
  void TurnIfNeeded();
  bool turning() const { return !!turn_; }
  void DeferUntilTurned(base::OnceClosure op);

  bool DefersTrackChanges() const;
  void DeferTrackChange(base::OnceClosure change);
  base::OnceClosure CountTrackChange(base::OnceClosure change_completed_cb);
  void RunDeferredTrackChanges();

  bool OnBufferingStateChange(BufferingState state);
  void FollowPlayingClock();

  void OnStart();
  bool SetCdm(CdmContext* cdm_context,
              base::OnceCallback<void(bool)>& cdm_attached_cb);
  bool cdm_detached() const { return cdm_detached_; }
  void set_cdm_detached(bool detached) { cdm_detached_ = detached; }

  void SetVolume(float volume);
  void SetLatencyHint(std::optional<base::TimeDelta> latency_hint);
  void SetPreservesPitch(bool preserves_pitch);
  void SetRenderMutedAudio(bool render_muted_audio);
  void OnAudioOutputDeviceChanged();

  base::TimeDelta FastSeekLanding(base::TimeDelta seek_time);

  void OnSeeking();
  void OnSuspending();
  void OnResuming();
  void Stop();

 private:
  class IncomingClient;

  void OnIncomingCreated(std::unique_ptr<Renderer> renderer);
  void OnIncomingInitialized(PipelineStatus status);
  void OnSplit(base::TimeDelta time);
  void Swap();
  void CompleteTurn(base::TimeDelta time, PipelineStatus status);
  void SeekDemuxer(base::TimeDelta time, base::OnceClosure done);
  void OnDemuxerSeeked(base::OnceClosure done, PipelineStatus status);
  void OnTrackChangeDone(base::OnceClosure change_completed_cb);

  const raw_ptr<Host> host_;
  const raw_ptr<RendererClient> client_;
  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;

  bool backward_ = false;
  std::unique_ptr<SerialRunner> turn_;
  base::OnceClosure deferred_op_;
  std::vector<base::OnceClosure> deferred_track_changes_;
  int track_changes_ = 0;
  bool demuxer_seek_pending_ = false;
  BufferingState buffering_state_ = BUFFERING_HAVE_NOTHING;
  bool turned_ = false;

  std::unique_ptr<Renderer> incoming_;
  std::unique_ptr<IncomingClient> incoming_client_;
  base::OnceCallback<void(bool)> handoff_done_;
  bool split_ = false;
  bool handed_off_ = false;

  bool cdm_detached_ = false;

  SEQUENCE_CHECKER(sequence_checker_);

  base::WeakPtrFactory<ParcRendererTransitions> handoff_weak_factory_{this};
  base::WeakPtrFactory<ParcRendererTransitions> weak_factory_{this};
  base::WeakPtrFactory<ParcRendererTransitions> cdm_weak_factory_{this};
};

std::optional<RendererType> ParcRendererTypeFor(CdmContext* cdm_context,
                                                Demuxer* demuxer);

}

#endif

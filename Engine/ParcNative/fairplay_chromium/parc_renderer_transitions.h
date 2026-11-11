// Copyright 2026 Parc contributors.
// Installed at //media/base/parc_renderer_transitions.h.

#ifndef MEDIA_BASE_PARC_RENDERER_TRANSITIONS_H_
#define MEDIA_BASE_PARC_RENDERER_TRANSITIONS_H_

#include <memory>
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

namespace media {

class Demuxer;
class Renderer;
class RendererClient;
class SerialRunner;

// Parc's two renderer transitions inside PipelineImpl. Its RendererWrapper
// owns this and calls each method on the media sequence at the point of its
// own state machine named beside the method.
// - A hand-off from Chromium's renderer to the FairPlay Renderer while it
//   plays (ParcPipelineExtension::ParcHandOffToFairPlay()). The FairPlay
//   Renderer reads the demuxer's hand-off streams and prerolls paused where
//   the demuxer splits them, at least 500 ms ahead (Demuxer::
//   ParcSplitForHandOff()). Prerolled, it runs on the playing renderer's
//   clock, and takes over, shown and played, when that renderer reaches the
//   end of its part, so the picture, the sound and the clock carry on.
// - A turn between directions for a file renderer, which plays backward in
//   its own mode (Renderer::ParcStartPlayingBackwardFrom()): a flush the page
//   doesn't see as a seek.
class ParcRendererTransitions {
 public:
  // The RendererWrapper, as the transitions read and change it.
  class Host {
   public:
    // Whether the pipeline plays (State::kPlaying), and its rate.
    virtual bool ParcIsPlaying() = 0;
    virtual double ParcPlaybackRate() = 0;
    virtual Demuxer* ParcDemuxer() = 0;
    // The pipeline's renderer, or null.
    virtual Renderer* ParcRenderer() = 0;
    virtual base::TimeDelta ParcCurrentTimestamp() = 0;
    // A FairPlay Renderer from the pipeline's client, or null, for
    // |created|.
    virtual void ParcCreateFairPlayRenderer(
        base::OnceCallback<void(std::unique_ptr<Renderer>)> created) = 0;
    // Gives |renderer| the pipeline's CDM and playback settings.
    virtual void ParcConfigureRenderer(Renderer& renderer) = 0;
    // Makes |renderer| the pipeline's and returns the one it replaces.
    virtual std::unique_ptr<Renderer> ParcReplaceRenderer(
        std::unique_ptr<Renderer> renderer) = 0;
    virtual void ParcOnPipelineError(PipelineStatus status) = 0;

   protected:
    virtual ~Host() = default;
  };

  // |client| hears the FairPlay Renderer from when it takes over.
  ParcRendererTransitions(
      Host* host,
      RendererClient* client,
      scoped_refptr<base::SequencedTaskRunner> media_task_runner);
  ParcRendererTransitions(const ParcRendererTransitions&) = delete;
  ParcRendererTransitions& operator=(const ParcRendererTransitions&) = delete;
  ~ParcRendererTransitions();

  // The hand-off; |done| answers as ParcHandOffToFairPlay()'s does.
  void HandOff(base::OnceCallback<void(bool)> done);
  // The renderer handed to, until it takes over; it gets every setting the
  // pipeline's renderer gets.
  Renderer* incoming() const { return incoming_.get(); }
  // OnEnded(): once the streams are split, the playing renderer reached the
  // split and the incoming one takes over. False before.
  bool TakeOverAtSplit();
  // Seek(): a split hand-off completes at once, as the playing renderer
  // can't go on past the split; an earlier one ends and the caller restarts.
  void Settle();
  // A turn of direction or a CDM change ends a hand-off on its way and the
  // caller restarts (|restart|); a suspend ends it and the resume makes the
  // renderer.
  void Abort(bool restart);
  // DestroyRenderer(): destroys the pipeline's |renderer|, then ends a
  // hand-off it took over in.
  void DestroyRenderer(std::unique_ptr<Renderer> renderer);

  // The rate the pipeline's renderer plays: backward only for a renderer
  // that does (a native HLS player rewinds itself), else 0, so time stops
  // where the other direction starts.
  double RendererRate();
  // After a rate change, a seek, a track change or a turn: turns the
  // renderer when its direction isn't the rate's.
  void TurnIfNeeded();
  bool turning() const { return !!turn_; }
  // Seek() or Suspend() during a turn: |op| runs when it completes.
  void DeferUntilTurned(base::OnceClosure op);

  // Backward, audio is silent and the video renderer has its own stream
  // position, so track changes wait for forward playback; during a hand-off
  // they wait for the renderer that plays after it.
  bool DefersTrackChanges() const;
  void DeferTrackChange(base::OnceClosure change);
  // A track change going ahead: no turn starts before
  // |change_completed_cb|.
  base::OnceClosure CountTrackChange(base::OnceClosure change_completed_cb);
  void RunDeferredTrackChanges();

  // Each buffering state the pipeline's renderer reports. True for the
  // renderer's first after a turn that repeats what the pipeline last heard,
  // which the page doesn't hear again.
  bool OnBufferingStateChange(BufferingState state);
  // The incoming renderer, prerolled, runs on the playing renderer's clock:
  // at its rate from where it is now, or stopped there while it doesn't play.
  void FollowPlayingClock();

  // The wrapper's Seek(), Suspend(), Resume() and Stop().
  void OnSeeking();
  void OnSuspending();
  void OnResuming();
  void Stop();

 private:
  class IncomingClient;

  void OnIncomingCreated(std::unique_ptr<Renderer> renderer);
  void OnIncomingInitialized(PipelineStatus status);
  void OnSplit(base::TimeDelta time);
  // The playing renderer ended its part, or a seek can't wait for it.
  void Swap();
  void CompleteTurn(base::TimeDelta time, PipelineStatus status);
  void SeekDemuxer(base::TimeDelta time, base::OnceClosure done);
  void OnDemuxerSeeked(base::OnceClosure done, PipelineStatus status);
  void OnTrackChangeDone(base::OnceClosure change_completed_cb);

  const raw_ptr<Host> host_;
  const raw_ptr<RendererClient> client_;
  const scoped_refptr<base::SequencedTaskRunner> media_task_runner_;

  // The renderer plays backward, or |turn_| is turning it.
  bool backward_ = false;
  std::unique_ptr<SerialRunner> turn_;
  base::OnceClosure deferred_op_;
  std::vector<base::OnceClosure> deferred_track_changes_;
  int track_changes_ = 0;
  bool demuxer_seek_pending_ = false;
  // The buffering state the pipeline last heard; the renderer's first after
  // a turn repeats it.
  BufferingState buffering_state_ = BUFFERING_HAVE_NOTHING;
  bool turned_ = false;

  // The incoming renderer, until it takes over; whether the streams are
  // split; and whether the pipeline's renderer reads the demuxer's hand-off
  // streams.
  std::unique_ptr<Renderer> incoming_;
  std::unique_ptr<IncomingClient> incoming_client_;
  base::OnceCallback<void(bool)> handoff_done_;
  bool split_ = false;
  bool handed_off_ = false;

  // The media sequence, which the wrapper binds on its first call.
  SEQUENCE_CHECKER(sequence_checker_);

  // For one hand-off's steps.
  base::WeakPtrFactory<ParcRendererTransitions> handoff_weak_factory_{this};
  // For the turn's and the track changes' steps, which Stop() drops.
  base::WeakPtrFactory<ParcRendererTransitions> weak_factory_{this};
};

}  // namespace media

#endif  // MEDIA_BASE_PARC_RENDERER_TRANSITIONS_H_

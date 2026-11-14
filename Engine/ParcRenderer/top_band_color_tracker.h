// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_TOP_BAND_COLOR_TRACKER_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_TOP_BAND_COLOR_TRACKER_H_

#include <optional>

#include "base/memory/scoped_refptr.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "third_party/blink/public/common/parc/top_band_color_sampling.h"
#include "third_party/blink/public/mojom/parc/top_band_color.mojom-blink.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/core/dom/dom_node_ids.h"
#include "third_party/blink/renderer/platform/graphics/color.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_associated_receiver.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_associated_remote.h"
#include "third_party/blink/renderer/platform/supplementable.h"
#include "third_party/blink/renderer/platform/timer.h"

namespace viz {
class FrameTimingDetails;
}

namespace blink {

class ComputedStyle;
class Element;
class LocalFrame;
class LocalFrameView;

class CORE_EXPORT TopBandColorTracker final
    : public GarbageCollected<TopBandColorTracker>,
      public Supplement<LocalFrame>,
      public parc::mojom::blink::TopBandColorAgent {
 public:
  static const char kSupplementName[];
  static void Install(LocalFrame&);
  static TopBandColorTracker* From(LocalFrame&);

  explicit TopBandColorTracker(LocalFrame&);

  // LocalFrameView::RunPostLifecycleSteps (0x46849d0).
  void FireDetection();
  // Document::FinishedParsing (0x18f4550).
  void DidFinishParsing();
  // Document::OnLargestContentfulPaintUpdated (0x46876a0).
  void DidUpdateLargestContentfulPaint();
  // DocumentLoader::CommitNavigation (0x1fefbd0).
  void DidCommitNavigation();

  void Trace(Visitor*) const override;

 private:
  struct ChosenState {
    Color color;
    bool has_color = false;
    bool sample_frame = false;
    int64_t frame_sample_id = 0;
    bool fallback = false;
    bool reuse_frame_sample = false;
    bool operator==(const ChosenState&) const;
  };
  enum class State { kInitial, kEmitted, kUnavailable };

  void BindAgent(
      mojo::PendingAssociatedReceiver<parc::mojom::blink::TopBandColorAgent>);
  // parc::mojom::blink::TopBandColorAgent:
  void SetObserver(
      mojo::PendingAssociatedRemote<parc::mojom::blink::TopBandColorObserver>)
      override;
  void ObserverDisconnected();

  void TimerFired(TimerBase*);
  void ScheduleDetection();
  void Detect(LocalFrameView&);
  void EmitChosenState(LocalFrameView&, const ChosenState&);
  void SendState(const ChosenState&);
  void DidPresent(uint32_t generation, const viz::FrameTimingDetails&);
  bool SameElementAsLastSample(const Element&) const;
  void RememberSampledElement(const Element&);
  void CancelPendingFallback();

  // The frame's kInternalDefault runner, kept past its detach.
  scoped_refptr<base::SingleThreadTaskRunner> task_runner_;
  HeapTaskRunnerTimer<TopBandColorTracker> timer_;
  HeapMojoAssociatedReceiver<parc::mojom::blink::TopBandColorAgent,
                             TopBandColorTracker>
      agent_{this, nullptr};
  HeapMojoAssociatedRemote<parc::mojom::blink::TopBandColorObserver>
      observer_{nullptr};

  State state_ = State::kInitial;
  bool has_sent_ = false;
  // An LCP update arrived for this document: translucent and colour-unknown
  // elements may be reported, and reports after the first one crossfade.
  bool seen_contentful_paint_ = false;
  bool crossfade_armed_ = false;
  bool detection_pending_ = false;
  bool finished_parsing_ = false;
  ChosenState last_sent_;
  // A frame-sample or fallback state waiting for the next presentation.
  bool awaiting_presentation_ = false;
  std::optional<ChosenState> pending_;
  uint32_t generation_ = 0;

  // The last element whose colour came from its pixels or the frame.
  DOMNodeId sampled_node_ = kInvalidDOMNodeId;
  Member<const ComputedStyle> sampled_style_;
  base::TimeTicks sampled_at_;
  std::optional<Color> sampled_color_;
  int64_t frame_sample_id_ = 0;
  // Pixel reads this pass and recent failures, so no element is decoded or
  // drawn again for each point or detection.
  parc::top_band::PixelSampleMemory pixel_memory_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_TOP_BAND_COLOR_TRACKER_H_

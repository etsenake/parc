// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_demuxer_extension.h.
// Parc's operations on media::Demuxer, reached through
// Demuxer::GetParcExtension(), which is null for a demuxer without them.
// Kept out of demuxer.h so that changing them rebuilds only what uses them.
#ifndef MEDIA_BASE_PARC_DEMUXER_EXTENSION_H_
#define MEDIA_BASE_PARC_DEMUXER_EXTENSION_H_

#include <optional>
#include <utility>

#include "base/functional/callback.h"
#include "base/time/time.h"
#include "media/base/demuxer.h"

namespace media {

class ParcDemuxerExtension {
 public:
  // Whether the pipeline picks the FairPlay Renderer without a FairPlay CDM:
  // a SourceBuffer took clear Dolby Vision that it plays, including the H.264,
  // HEVC or AV1 before a later switch into Dolby Vision. Any thread.
  virtual bool ParcPrefersFairPlayRenderer() { return false; }

  // HTMLMediaElement.fastSeek may land within `tolerance_before` before its
  // target, never after it. Zero asks for an exact seek, and a demuxer that
  // cannot land early seeks exactly. Set on the main thread; the landing is
  // returned once on the media thread after the seek completes.
  virtual void ParcSetFastSeek(base::TimeDelta target,
                               base::TimeDelta tolerance_before) {}
  virtual std::optional<base::TimeDelta> ParcTakeFastSeekLanding() {
    return std::nullopt;
  }

  // The playing renderer's streams handed to another renderer without a
  // restart. Beginning returns null where that is unsupported. The split falls
  // at or after `not_before`, on a video keyframe: the playing renderer reaches
  // end of stream there, the incoming one starts there and the callback receives
  // that split time. End the hand-off once the incoming renderer is gone or will
  // not be used. Called on the pipeline's media sequence; an implementation
  // keeps its existing lock.
  virtual MediaResource* ParcBeginHandOff() { return nullptr; }
  virtual void ParcSplitForHandOff(
      base::TimeDelta not_before,
      base::OnceCallback<void(base::TimeDelta)> split_cb) {}
  virtual void ParcEndHandOff() {}

 protected:
  virtual ~ParcDemuxerExtension() = default;
};

inline bool ParcDemuxerPrefersFairPlayRenderer(Demuxer* demuxer) {
  ParcDemuxerExtension* parc = demuxer->GetParcExtension();
  return parc && parc->ParcPrefersFairPlayRenderer();
}

inline void ParcSetDemuxerFastSeek(Demuxer* demuxer,
                                   base::TimeDelta target,
                                   base::TimeDelta tolerance_before) {
  if (ParcDemuxerExtension* parc = demuxer->GetParcExtension()) {
    parc->ParcSetFastSeek(target, tolerance_before);
  }
}

inline std::optional<base::TimeDelta> ParcTakeDemuxerFastSeekLanding(
    Demuxer* demuxer) {
  ParcDemuxerExtension* parc = demuxer->GetParcExtension();
  return parc ? parc->ParcTakeFastSeekLanding() : std::nullopt;
}

inline MediaResource* ParcBeginDemuxerHandOff(Demuxer* demuxer) {
  ParcDemuxerExtension* parc = demuxer->GetParcExtension();
  return parc ? parc->ParcBeginHandOff() : nullptr;
}

inline void ParcSplitDemuxerForHandOff(
    Demuxer* demuxer,
    base::TimeDelta not_before,
    base::OnceCallback<void(base::TimeDelta)> split_cb) {
  if (ParcDemuxerExtension* parc = demuxer->GetParcExtension()) {
    parc->ParcSplitForHandOff(not_before, std::move(split_cb));
  }
}

inline void ParcEndDemuxerHandOff(Demuxer* demuxer) {
  if (ParcDemuxerExtension* parc = demuxer->GetParcExtension()) {
    parc->ParcEndHandOff();
  }
}

}  // namespace media

#endif  // MEDIA_BASE_PARC_DEMUXER_EXTENSION_H_

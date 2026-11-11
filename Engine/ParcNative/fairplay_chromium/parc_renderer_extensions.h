// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_renderer_extensions.h.
// Parc's operations on media::Renderer, AudioRenderer and VideoRenderer, each
// reached through that interface's GetParcExtension(), which is null for an
// implementation without them. Kept out of Chromium's renderer headers so
// that changing them rebuilds only what uses them.
#ifndef MEDIA_BASE_PARC_RENDERER_EXTENSIONS_H_
#define MEDIA_BASE_PARC_RENDERER_EXTENSIONS_H_

#include <memory>

#include "base/functional/callback.h"
#include "base/time/time.h"

namespace media {

class AudioRenderer;

// Moves the demuxer to a time for a renderer playing backward, then runs the
// closure.
using ParcSeekDemuxerCB =
    base::RepeatingCallback<void(base::TimeDelta, base::OnceClosure)>;

class ParcRendererExtension {
 public:
  // After Flush(), plays backward from `time` at `playback_rate` < 0, as
  // Safari's AVPlayer rewinds a file (MediaPlayerPrivateAVFoundationObjC::
  // setRateDouble). Only RendererImpl does; audio stays silent.
  virtual void ParcStartPlayingBackwardFrom(base::TimeDelta time,
                                            double playback_rate,
                                            ParcSeekDemuxerCB seek_demuxer_cb) {
  }

  // The pipeline's audio sink switched to another output device
  // (HTMLMediaElement.setSinkId). Renderers whose audio bypasses the sink
  // (FairPlay, native HLS) move theirs to the device the sink now names.
  virtual void ParcOnAudioOutputDeviceChanged() {}

  // A renderer taking over from another
  // (ParcPipelineExtension::ParcHandOffToFairPlay()) shows nothing until it
  // does: the FairPlay Renderer paints its video hole frame only when shown.
  virtual void ParcSetHidden(bool hidden) {}

  // While hidden, runs at `playback_rate` on the playing renderer's clock,
  // which reads `time` at `host_time`, so it takes over at the split without
  // a gap. Only the FairPlay Renderer does.
  virtual void ParcSetPlaybackRateAt(double playback_rate,
                                     base::TimeDelta time,
                                     base::TimeTicks host_time) {}

 protected:
  virtual ~ParcRendererExtension() = default;
};

class ParcAudioRendererExtension {
 public:
  // A renderer for another audio stream whose output this one adds into its
  // own on its timeline, as WebKit's player plays every enabled audio track
  // on one synchronizer (AudioVideoRendererAVFObjC::addTrack). It plays
  // through this one's sink at this one's volume. Null if this one can't mix
  // (not initialized, or bitstream output). Call after Initialize()
  // completed.
  virtual std::unique_ptr<AudioRenderer> ParcCreateMixedRenderer() = 0;
  // Silences this renderer's own stream (its track was disabled) while its
  // clock and the renderers mixed into it go on.
  virtual void ParcSetOwnAudioMuted(bool muted) = 0;

 protected:
  virtual ~ParcAudioRendererExtension() = default;
};

class ParcVideoRendererExtension {
 public:
  // Like StartPlayingFrom(), but shows frames at and before `timestamp`
  // going backward (ParcRendererExtension::ParcStartPlayingBackwardFrom()).
  virtual void ParcStartPlayingBackwardFrom(
      base::TimeDelta timestamp,
      ParcSeekDemuxerCB seek_demuxer_cb) = 0;

 protected:
  virtual ~ParcVideoRendererExtension() = default;
};

}  // namespace media

#endif  // MEDIA_BASE_PARC_RENDERER_EXTENSIONS_H_

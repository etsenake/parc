// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_pipeline_extension.h.
// Parc's operations on media::Pipeline, reached through
// Pipeline::GetParcExtension() (or PipelineController's), which is null for
// a pipeline without them. Kept out of pipeline.h so that changing them
// rebuilds only what uses them.
#ifndef MEDIA_BASE_PARC_PIPELINE_EXTENSION_H_
#define MEDIA_BASE_PARC_PIPELINE_EXTENSION_H_

#include "base/functional/callback.h"

namespace media {

class ParcPipelineExtension {
 public:
  // GetMediaTime() may go back once, to a time the player really went back
  // to outside a seek (Safari's native HLS route).
  virtual void ParcResetMediaTimeClamp() = 0;

  // See ParcRendererExtension::ParcOnAudioOutputDeviceChanged().
  virtual void ParcOnAudioOutputDeviceChanged() = 0;

  // Chromium's renderer hands over to the FairPlay Renderer while it plays,
  // with no restart, as Safari's one Media Source renderer takes keys and
  // Dolby Vision at any time (PipelineImpl). |done| runs with false when the
  // caller must restart into the FairPlay Renderer instead: the hand-off
  // couldn't be done here, or ended before it completed. A pipeline without
  // this extension can't hand off.
  virtual void ParcHandOffToFairPlay(base::OnceCallback<void(bool)> done) = 0;

 protected:
  virtual ~ParcPipelineExtension() = default;
};

}  // namespace media

#endif  // MEDIA_BASE_PARC_PIPELINE_EXTENSION_H_

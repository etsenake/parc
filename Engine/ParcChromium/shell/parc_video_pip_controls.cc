// Copyright 2018 The Chromium Authors

#include <utility>

#include "content/browser/picture_in_picture/video_picture_in_picture_window_controller_impl.h"
#include "content/browser/picture_in_picture/picture_in_picture_session.h"
#include "content/browser/media/parc_fairplay_hooks.h"
#include "content/public/browser/render_frame_host.h"
#include "services/media_session/public/mojom/media_session.mojom.h"

namespace content {

bool VideoPictureInPictureWindowControllerImpl::ParcPresentsSafariIdentity() const {
  return active_session_ && active_session_->player_id() &&
         parc::fairplay::FramePresentsSafariIdentity(RenderFrameHost::FromID(
             active_session_->player_id()->frame_routing_id));
}

void VideoPictureInPictureWindowControllerImpl::SetScrubbing(bool scrubbing) {
  if (!active_session_ || scrubbing == parc_scrubbing_ ||
      (scrubbing && !ParcPresentsSafariIdentity()))
    return;
  parc_scrubbing_ = scrubbing;
  active_session_->GetMediaPlayerRemote()->RequestHandlePlaybackControlsAction(
      scrubbing ? media_session::mojom::PlaybackControlsAction::kBeginScrubbing
                : media_session::mojom::PlaybackControlsAction::kEndScrubbing,
      base::TimeDelta());
}

}

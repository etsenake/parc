// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_remote_playback_extension.h.
// Parc's AirPlay calls on an element's Remote Playback, reached through
// RemotePlaybackController::GetParcExtension(). Kept out of
// remote_playback_controller.h so that changing them rebuilds only what uses
// them.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_REMOTE_PLAYBACK_EXTENSION_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_REMOTE_PLAYBACK_EXTENSION_H_

namespace blink {

class ParcRemotePlaybackExtension {
 public:
  // An element whose player plays to AirPlay targets on a Safari-identity
  // page (ParcMediaElementAirPlay::PlaysToPlaybackTargets()) runs its Remote
  // Playback as AirPlay, as WebKit's RemotePlayback does. Whether it can offer
  // AirPlay may have changed: devices nearby
  // (wirelessRoutesAvailableDidChange), disabled, or a new player.
  virtual void ParcAirPlayAvailabilityChanged() = 0;
  // The element was given the route's target, or taken off it
  // (shouldPlayToRemoteTargetChanged).
  virtual void ParcShouldPlayToRemoteTargetChanged(bool should_play) = 0;
  // Its player plays to the device now, or stopped
  // (isPlayingToRemoteTargetChanged).
  virtual void ParcPlayingToRemoteTargetChanged(bool playing) = 0;
  // The route list closed without a choice
  // (playbackTargetPickerWasDismissed).
  virtual void ParcPlaybackTargetPickerDismissed() = 0;

 protected:
  virtual ~ParcRemotePlaybackExtension() = default;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_REMOTE_PLAYBACK_EXTENSION_H_

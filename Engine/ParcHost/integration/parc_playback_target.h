// Copyright 2026 Parc contributors.
// AirPlay for the media elements of Safari-identity pages
// (Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md "AirPlay"), WebKit's
// MediaPlaybackTargetClient and WebMediaSessionManager split the Chromium
// way: each element reports its AirPlay state through its
// media.mojom.MediaPlayerObserver, content hands it to the embedder's handler
// (Parc's route picker, parc::NativeAirPlay), and the handler answers each
// player through the functions below, which reach its media.mojom.MediaPlayer.
// Installed at content/public/browser/parc_playback_target.h.
#ifndef CONTENT_PUBLIC_BROWSER_PARC_PLAYBACK_TARGET_H_
#define CONTENT_PUBLIC_BROWSER_PARC_PLAYBACK_TARGET_H_

#include <cstdint>
#include <string>

#include "content/common/content_export.h"
#include "content/public/browser/media_player_id.h"
#include "ui/gfx/geometry/point.h"

namespace content {

class WebContents;

struct ParcPlaybackTargetState {
  // The element needs AirPlay devices watched: it has availability listeners
  // or a player that can play to a device.
  bool requires_monitoring = false;
  // Its player can play to an AirPlay device (Safari's native HLS player).
  bool supports_target = false;
  // It holds the handler's target with should-play on.
  bool plays_to_target = false;
  // Its player plays to the device now (AVPlayer's externalPlaybackActive).
  bool wireless = false;

  bool operator==(const ParcPlaybackTargetState&) const = default;
};

// Called on the UI thread.
class ParcPlaybackTargetHandler {
 public:
  virtual void OnPlaybackTargetStateChanged(
      WebContents* web_contents,
      const MediaPlayerId& player,
      const ParcPlaybackTargetState& state) = 0;
  // webkitShowPlaybackTargetPicker(), at `position` in DIPs of the
  // WebContents' view (the last mouse position in the page).
  virtual void OnShowPlaybackTargetPicker(WebContents* web_contents,
                                          const MediaPlayerId& player,
                                          const gfx::Point& position) = 0;
  // The player's registration ended (a new load, the element or its frame
  // went away).
  virtual void OnPlaybackTargetPlayerGone(WebContents* web_contents,
                                          const MediaPlayerId& player) = 0;

 protected:
  virtual ~ParcPlaybackTargetHandler() = default;
};

// Installs the embedder's handler; nullptr removes it. Main thread, before
// the browser starts.
CONTENT_EXPORT void SetParcPlaybackTargetHandler(
    ParcPlaybackTargetHandler* handler);

// Whether AirPlay devices are nearby, to the player's element
// (webkitplaybacktargetavailabilitychanged). Does nothing for a player that
// is gone.
CONTENT_EXPORT void SetParcPlaybackTargetAvailability(
    WebContents* web_contents,
    const MediaPlayerId& player,
    bool available);
// The route picker's AVOutputContext by its UUID (empty for none), the name
// of the device it routes to, whether the player plays to it, and the
// window's Space tint for AirPlay on dark and on light surfaces as ARGB (0
// for none).
CONTENT_EXPORT void SetParcPlaybackTarget(WebContents* web_contents,
                                          const MediaPlayerId& player,
                                          const std::string& output_context_id,
                                          const std::string& device_name,
                                          bool should_play,
                                          uint32_t tint_argb,
                                          uint32_t tint_on_light_argb);
// The route list the player's element opened closed without a choice.
CONTENT_EXPORT void SetParcPlaybackTargetPickerDismissed(
    WebContents* web_contents,
    const MediaPlayerId& player);

}  // namespace content

#endif  // CONTENT_PUBLIC_BROWSER_PARC_PLAYBACK_TARGET_H_

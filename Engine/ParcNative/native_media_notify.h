// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_MEDIA_NOTIFY_H_
#define PARC_NATIVE_NATIVE_MEDIA_NOTIFY_H_

#include <cstdint>
#include <string>

namespace parc {

// MediaState::Publish fans into the same NotifyNativePageChanged path as tab
// chrome. Playback/position-adjacent observer noise can fire Changed() when the
// Mini Player / tab-audio / admission inputs the shell actually rereads are
// unchanged. Capture that published media-relevant snapshot here so Publish can
// skip a true no-op without dropping play/pause, mute, title, artwork,
// eligibility, or action/capability flips.
struct NativeMediaNotifyState {
  bool eligible = false;
  bool active = false;
  bool dismissed = false;
  std::string identity;
  uint64_t admission_sequence = 0;
  // PCNativeMediaSessionStatus raw value (Active=0 … Inactive=3).
  uint8_t session_status = 0;
  bool session_controllable = false;
  bool session_state_active = false;
  bool can_admit = false;
  bool playing = false;
  bool can_play_pause = false;
  bool has_previous_track = false;
  bool has_next_track = false;
  bool muted = false;
  bool audible = false;
  // Advanced in DidUpdateAudioMutingState before Changed(); tab-audio toggles
  // validate against this, so a mute round-trip that ends at the same muted bit
  // must still publish when the revision moved.
  uint64_t mute_revision = 0;
  int volume_hundredths = 100;
  bool can_set_volume = false;
  bool can_toggle_microphone = false;
  bool can_toggle_camera = false;
  bool microphone_on = false;
  bool camera_on = false;
  bool can_enter_picture_in_picture = false;
  // PCNativeAirPlayState raw value and the device's name (native_airplay.h).
  int airplay_state = 0;
  std::string airplay_device_name;
  // PCNativeCastState raw value and the receiver's name
  // (native_gmc_presentation.h).
  int cast_state = 0;
  std::string cast_device_name;
  bool off_the_record = false;
  std::u16string title;
  std::string source_url;
  bool artwork_present = false;
  std::string artwork_url;
  bool published = false;
};

inline bool MediaNotifyPayloadChanged(const NativeMediaNotifyState& last,
                                      const NativeMediaNotifyState& current) {
  return last.eligible != current.eligible || last.active != current.active ||
         last.dismissed != current.dismissed ||
         last.identity != current.identity ||
         last.admission_sequence != current.admission_sequence ||
         last.session_status != current.session_status ||
         last.session_controllable != current.session_controllable ||
         last.session_state_active != current.session_state_active ||
         last.can_admit != current.can_admit ||
         last.playing != current.playing ||
         last.can_play_pause != current.can_play_pause ||
         last.has_previous_track != current.has_previous_track ||
         last.has_next_track != current.has_next_track ||
         last.muted != current.muted || last.audible != current.audible ||
         last.mute_revision != current.mute_revision ||
         last.volume_hundredths != current.volume_hundredths ||
         last.can_set_volume != current.can_set_volume ||
         last.can_toggle_microphone != current.can_toggle_microphone ||
         last.can_toggle_camera != current.can_toggle_camera ||
         last.microphone_on != current.microphone_on ||
         last.camera_on != current.camera_on ||
         last.can_enter_picture_in_picture !=
             current.can_enter_picture_in_picture ||
         last.airplay_state != current.airplay_state ||
         last.airplay_device_name != current.airplay_device_name ||
         last.cast_state != current.cast_state ||
         last.cast_device_name != current.cast_device_name ||
         last.off_the_record != current.off_the_record ||
         last.title != current.title || last.source_url != current.source_url ||
         last.artwork_present != current.artwork_present ||
         last.artwork_url != current.artwork_url;
}

// Skip only an identical published media snapshot. First publish and any real
// play/pause/mute/title/artwork/eligibility/capability change still notify.
inline bool ShouldNotifyMediaPayloadChange(
    const NativeMediaNotifyState& last,
    const NativeMediaNotifyState& current) {
  if (!last.published) {
    return true;
  }
  return MediaNotifyPayloadChanged(last, current);
}

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_MEDIA_NOTIFY_H_

#include "native_media_notify.h"

#include <cassert>
#include <iostream>

int main() {
  using parc::MediaNotifyPayloadChanged;
  using parc::NativeMediaNotifyState;
  using parc::ShouldNotifyMediaPayloadChange;

  NativeMediaNotifyState unpublished;
  NativeMediaNotifyState published;
  published.eligible = true;
  published.active = true;
  published.identity = "episode-1";
  published.admission_sequence = 3;
  published.session_status = 0;  // Active
  published.session_controllable = true;
  published.session_state_active = true;
  published.can_admit = true;
  published.playing = true;
  published.can_play_pause = true;
  published.muted = false;
  published.audible = true;
  published.volume_hundredths = 100;
  published.can_set_volume = true;
  published.title = u"Track";
  published.source_url = "https://music.example/";
  published.artwork_present = true;
  published.artwork_url = "https://music.example/art.png";
  published.published = true;

  NativeMediaNotifyState same = published;
  same.published = false;

  // First publish always notifies.
  assert(ShouldNotifyMediaPayloadChange(unpublished, published));
  assert(ShouldNotifyMediaPayloadChange(unpublished, same));

  // Identical published media snapshot must not notify (Images/Metadata churn).
  assert(!ShouldNotifyMediaPayloadChange(published, same));
  assert(!MediaNotifyPayloadChanged(published, same));

  // Real play/pause must still notify.
  NativeMediaNotifyState paused = same;
  paused.playing = false;
  assert(ShouldNotifyMediaPayloadChange(published, paused));
  assert(MediaNotifyPayloadChanged(published, paused));

  // Mute / audible flips must still notify (tab audio + CanAdmit).
  NativeMediaNotifyState muted = same;
  muted.muted = true;
  muted.can_admit = false;
  muted.mute_revision = 1;
  assert(ShouldNotifyMediaPayloadChange(published, muted));
  NativeMediaNotifyState silent = same;
  silent.audible = false;
  assert(ShouldNotifyMediaPayloadChange(published, silent));
  // Mute round-trip that returns to the same muted bit still notifies when
  // mute_revision advanced (tab-audio toggle validation).
  NativeMediaNotifyState mute_rev = same;
  mute_rev.mute_revision = 2;
  assert(ShouldNotifyMediaPayloadChange(published, mute_rev));
  assert(MediaNotifyPayloadChanged(published, mute_rev));

  // Title / artwork / source identity must still notify.
  NativeMediaNotifyState retitled = same;
  retitled.title = u"Other";
  assert(ShouldNotifyMediaPayloadChange(published, retitled));
  NativeMediaNotifyState art = same;
  art.artwork_url = "https://music.example/other.png";
  assert(ShouldNotifyMediaPayloadChange(published, art));
  NativeMediaNotifyState missing_art = same;
  missing_art.artwork_present = false;
  assert(ShouldNotifyMediaPayloadChange(published, missing_art));

  // Eligibility / admission / session status must still notify.
  NativeMediaNotifyState ineligible = same;
  ineligible.eligible = false;
  ineligible.active = false;
  ineligible.can_admit = false;
  assert(ShouldNotifyMediaPayloadChange(published, ineligible));
  NativeMediaNotifyState status = same;
  status.session_status = 3;  // Inactive
  status.session_state_active = false;
  status.can_admit = false;
  assert(ShouldNotifyMediaPayloadChange(published, status));
  NativeMediaNotifyState admit = same;
  admit.can_admit = false;
  assert(ShouldNotifyMediaPayloadChange(published, admit));
  NativeMediaNotifyState actions = same;
  actions.has_next_track = true;
  assert(ShouldNotifyMediaPayloadChange(published, actions));
  NativeMediaNotifyState volume = same;
  volume.volume_hundredths = 50;
  assert(ShouldNotifyMediaPayloadChange(published, volume));

  // Capability / mic-cam presentation flips must still notify.
  NativeMediaNotifyState mic = same;
  mic.can_toggle_microphone = true;
  mic.microphone_on = true;
  assert(ShouldNotifyMediaPayloadChange(published, mic));

  // A video track arriving or leaving shows or hides Open Picture in Picture.
  NativeMediaNotifyState pip = same;
  pip.can_enter_picture_in_picture = true;
  assert(ShouldNotifyMediaPayloadChange(published, pip));

  // After publishing a changed snapshot, an identical follow-up tick skips.
  NativeMediaNotifyState published_paused = paused;
  published_paused.published = true;
  NativeMediaNotifyState same_paused = paused;
  same_paused.published = false;
  assert(!ShouldNotifyMediaPayloadChange(published_paused, same_paused));

  std::cout << "Passed native media notify payload filters; no browser "
               "execution.\n";
}

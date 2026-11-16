#include "native_media_notify.h"

#include "../Support/TestFailure.h"
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
  published.session_status = 0;
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

  PARC_EXPECT(ShouldNotifyMediaPayloadChange(unpublished, published));
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(unpublished, same));

  PARC_EXPECT(!ShouldNotifyMediaPayloadChange(published, same));
  PARC_EXPECT(!MediaNotifyPayloadChanged(published, same));

  NativeMediaNotifyState paused = same;
  paused.playing = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, paused));
  PARC_EXPECT(MediaNotifyPayloadChanged(published, paused));

  NativeMediaNotifyState muted = same;
  muted.muted = true;
  muted.can_admit = false;
  muted.mute_revision = 1;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, muted));
  NativeMediaNotifyState silent = same;
  silent.audible = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, silent));
  NativeMediaNotifyState mute_rev = same;
  mute_rev.mute_revision = 2;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, mute_rev));
  PARC_EXPECT(MediaNotifyPayloadChanged(published, mute_rev));

  NativeMediaNotifyState retitled = same;
  retitled.title = u"Other";
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, retitled));
  NativeMediaNotifyState art = same;
  art.artwork_url = "https://music.example/other.png";
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, art));
  NativeMediaNotifyState missing_art = same;
  missing_art.artwork_present = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, missing_art));

  NativeMediaNotifyState ineligible = same;
  ineligible.eligible = false;
  ineligible.active = false;
  ineligible.can_admit = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, ineligible));
  NativeMediaNotifyState status = same;
  status.session_status = 3;
  status.session_state_active = false;
  status.can_admit = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, status));
  NativeMediaNotifyState admit = same;
  admit.can_admit = false;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, admit));
  NativeMediaNotifyState actions = same;
  actions.has_next_track = true;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, actions));
  NativeMediaNotifyState volume = same;
  volume.volume_hundredths = 50;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, volume));

  NativeMediaNotifyState mic = same;
  mic.can_toggle_microphone = true;
  mic.microphone_on = true;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, mic));

  NativeMediaNotifyState pip = same;
  pip.can_enter_picture_in_picture = true;
  PARC_EXPECT(ShouldNotifyMediaPayloadChange(published, pip));

  NativeMediaNotifyState published_paused = paused;
  published_paused.published = true;
  NativeMediaNotifyState same_paused = paused;
  same_paused.published = false;
  PARC_EXPECT(!ShouldNotifyMediaPayloadChange(published_paused, same_paused));

  std::cout << "Passed native media notify payload filters; no browser "
               "execution.\n";
}

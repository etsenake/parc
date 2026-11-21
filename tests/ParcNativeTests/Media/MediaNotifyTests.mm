#include "native_media_notify.h"

#import "ParcNativeTest.h"
#include <iostream>

@interface MediaNotifyTests : ParcNativeTestCase
@end

@implementation MediaNotifyTests

- (void)testFiltersMediaNotifyPayloads {
  @autoreleasepool {
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

  PARC_CHECK(ShouldNotifyMediaPayloadChange(unpublished, published));
  PARC_CHECK(ShouldNotifyMediaPayloadChange(unpublished, same));

  PARC_CHECK(!ShouldNotifyMediaPayloadChange(published, same));
  PARC_CHECK(!MediaNotifyPayloadChanged(published, same));

  NativeMediaNotifyState paused = same;
  paused.playing = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, paused));
  PARC_CHECK(MediaNotifyPayloadChanged(published, paused));

  NativeMediaNotifyState muted = same;
  muted.muted = true;
  muted.can_admit = false;
  muted.mute_revision = 1;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, muted));
  NativeMediaNotifyState silent = same;
  silent.audible = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, silent));
  NativeMediaNotifyState mute_rev = same;
  mute_rev.mute_revision = 2;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, mute_rev));
  PARC_CHECK(MediaNotifyPayloadChanged(published, mute_rev));

  NativeMediaNotifyState retitled = same;
  retitled.title = u"Other";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, retitled));
  NativeMediaNotifyState art = same;
  art.artwork_url = "https://music.example/other.png";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, art));
  NativeMediaNotifyState missing_art = same;
  missing_art.artwork_present = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, missing_art));

  NativeMediaNotifyState ineligible = same;
  ineligible.eligible = false;
  ineligible.active = false;
  ineligible.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, ineligible));
  NativeMediaNotifyState status = same;
  status.session_status = 3;
  status.session_state_active = false;
  status.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, status));
  NativeMediaNotifyState admit = same;
  admit.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, admit));
  NativeMediaNotifyState actions = same;
  actions.has_next_track = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, actions));
  NativeMediaNotifyState volume = same;
  volume.volume_hundredths = 50;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, volume));

  NativeMediaNotifyState mic = same;
  mic.can_toggle_microphone = true;
  mic.microphone_on = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, mic));

  NativeMediaNotifyState pip = same;
  pip.can_enter_picture_in_picture = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(published, pip));

  NativeMediaNotifyState published_paused = paused;
  published_paused.published = true;
  NativeMediaNotifyState same_paused = paused;
  same_paused.published = false;
  PARC_CHECK(!ShouldNotifyMediaPayloadChange(published_paused, same_paused));

  }
}

@end

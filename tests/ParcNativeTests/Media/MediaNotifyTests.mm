#include "native_media_notify.h"

#import "ParcNativeTest.h"

using parc::MediaNotifyPayloadChanged;
using parc::NativeMediaNotifyState;
using parc::ShouldNotifyMediaPayloadChange;

static NativeMediaNotifyState Published() {
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
  return published;
}

static NativeMediaNotifyState Same() {
  NativeMediaNotifyState same = Published();
  same.published = false;
  return same;
}

@interface MediaNotifyTests : ParcNativeTestCase
@end

@implementation MediaNotifyTests

- (void)testTheFirstPayloadIsAlwaysNotified {
  PARC_CHECK(ShouldNotifyMediaPayloadChange(NativeMediaNotifyState(), Published()));
  PARC_CHECK(ShouldNotifyMediaPayloadChange(NativeMediaNotifyState(), Same()));
}

- (void)testAnUnchangedPayloadIsNotNotified {
  PARC_CHECK(!ShouldNotifyMediaPayloadChange(Published(), Same()));
  PARC_CHECK(!MediaNotifyPayloadChanged(Published(), Same()));
}

- (void)testPausingIsNotified {
  NativeMediaNotifyState paused = Same();
  paused.playing = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), paused));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), paused));
}

- (void)testMutingAndSilenceAreNotified {
  NativeMediaNotifyState muted = Same();
  muted.muted = true;
  muted.can_admit = false;
  muted.mute_revision = 1;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), muted));
  NativeMediaNotifyState silent = Same();
  silent.audible = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), silent));
  NativeMediaNotifyState revision = Same();
  revision.mute_revision = 2;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), revision));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), revision));
}

- (void)testTitleAndArtworkChangesAreNotified {
  NativeMediaNotifyState retitled = Same();
  retitled.title = u"Other";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), retitled));
  NativeMediaNotifyState art = Same();
  art.artwork_url = "https://music.example/other.png";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), art));
  NativeMediaNotifyState missing = Same();
  missing.artwork_present = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), missing));
}

- (void)testEligibilitySessionAndAdmissionChangesAreNotified {
  NativeMediaNotifyState ineligible = Same();
  ineligible.eligible = false;
  ineligible.active = false;
  ineligible.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), ineligible));
  NativeMediaNotifyState status = Same();
  status.session_status = 3;
  status.session_state_active = false;
  status.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), status));
  NativeMediaNotifyState admit = Same();
  admit.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), admit));
}

- (void)testActionsVolumeMicrophoneAndPictureInPictureAreNotified {
  NativeMediaNotifyState actions = Same();
  actions.has_next_track = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), actions));
  NativeMediaNotifyState volume = Same();
  volume.volume_hundredths = 50;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), volume));
  NativeMediaNotifyState mic = Same();
  mic.can_toggle_microphone = true;
  mic.microphone_on = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), mic));
  NativeMediaNotifyState pip = Same();
  pip.can_enter_picture_in_picture = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), pip));
}

- (void)testAnUnchangedPausedPayloadIsNotNotified {
  NativeMediaNotifyState paused = Same();
  paused.playing = false;
  NativeMediaNotifyState published = paused;
  published.published = true;
  PARC_CHECK(!ShouldNotifyMediaPayloadChange(published, paused));
}

@end

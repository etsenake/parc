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

@interface ParcNativeTests_MediaNotifyTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_MediaNotifyTests

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


- (void)testMutingChangesNotifyTheShell {
  auto state = Same();
  state.muted = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testSilenceChangesNotifyTheShell {
  auto state = Same();
  state.audible = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testMuteRevisionChangesNotifyTheShell {
  auto state = Same();
  state.mute_revision = 2;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testTitleChangesNotifyTheShell {
  auto state = Same();
  state.title = u"Other";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testArtworkURLChangesNotifyTheShell {
  auto state = Same();
  state.artwork_url = "https://music.example/other.png";
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testMissingArtworkChangesNotifyTheShell {
  auto state = Same();
  state.artwork_present = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testEligibilityChangesNotifyTheShell {
  auto state = Same();
  state.eligible = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testActivationChangesNotifyTheShell {
  auto state = Same();
  state.active = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testAdmissionChangesNotifyTheShell {
  auto state = Same();
  state.can_admit = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testSessionStatusChangesNotifyTheShell {
  auto state = Same();
  state.session_status = 3;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testSessionActivityChangesNotifyTheShell {
  auto state = Same();
  state.session_state_active = false;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testNextTrackChangesNotifyTheShell {
  auto state = Same();
  state.has_next_track = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testVolumeChangesNotifyTheShell {
  auto state = Same();
  state.volume_hundredths = 50;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testMicrophoneControlChangesNotifyTheShell {
  auto state = Same();
  state.can_toggle_microphone = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testMicrophoneStateChangesNotifyTheShell {
  auto state = Same();
  state.microphone_on = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testPictureInPictureAvailabilityChangesNotifyTheShell {
  auto state = Same();
  state.can_enter_picture_in_picture = true;
  PARC_CHECK(ShouldNotifyMediaPayloadChange(Published(), state));
  PARC_CHECK(MediaNotifyPayloadChanged(Published(), state));
}

- (void)testAnUnchangedPausedPayloadIsNotNotified {
  NativeMediaNotifyState paused = Same();
  paused.playing = false;
  NativeMediaNotifyState published = paused;
  published.published = true;
  PARC_CHECK(!ShouldNotifyMediaPayloadChange(published, paused));
}

@end

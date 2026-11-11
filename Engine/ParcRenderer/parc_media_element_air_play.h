// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_media_element_air_play.h.
// AirPlay on a Safari-identity page's media element, as WebKit's
// WIRELESS_PLAYBACK_TARGET on macOS (HTMLMediaElement.cpp,
// MediaElementSession.cpp). The browser watches for AirPlay devices, shows the
// system's route list and hands the element its route picker's
// AVOutputContext; only the native HLS player plays to it, through AVPlayer,
// as only Safari's AVFoundation player does (NATIVE_HLS.md "AirPlay"). The
// element makes it when it is made and calls it where WebKit's element runs
// these steps; its static members are the partial interfaces in
// parc_media_element_air_play.idl and parc_video_element_air_play.idl.
// Main thread.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_AIR_PLAY_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_AIR_PLAY_H_

#include <stdint.h>

#include <memory>
#include <optional>

#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/supplementable.h"
#include "third_party/blink/renderer/platform/timer.h"
#include "third_party/blink/renderer/platform/wtf/text/atomic_string.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "v8/include/v8-forward.h"

namespace blink {

class HTMLVideoElement;
class ScriptState;
class WebMediaSource;

class CORE_EXPORT ParcMediaElementAirPlay final
    : public GarbageCollected<ParcMediaElementAirPlay>,
      public Supplement<HTMLMediaElement> {
 public:
  static const char kSupplementName[];

  // HTMLMediaElement's constructor.
  static void ProvideTo(HTMLMediaElement& element);
  static ParcMediaElementAirPlay& From(const HTMLMediaElement& element);

  explicit ParcMediaElementAirPlay(HTMLMediaElement& element);
  ~ParcMediaElementAirPlay();

  // WebKit's AirPlay members ([ContextEnabled=ParcSafariIdentity]).
  static void webkitShowPlaybackTargetPicker(HTMLMediaElement& element);
  static bool webkitCurrentPlaybackTargetIsWireless(HTMLMediaElement& element);
  // MediaElementSession::wirelessVideoPlaybackDisabled on macOS, and its
  // [ReflectSetter].
  static bool webkitWirelessVideoPlaybackDisabled(HTMLVideoElement& video);
  static void setWebkitWirelessVideoPlaybackDisabled(HTMLVideoElement& video,
                                                     bool disabled);

  // Keeps kParcWebKitPlaybackTargetScript's completion value, the
  // availability event's hook, for the main world of `script_state`
  // (parc_webkit_playback_target.h).
  static void SetPlaybackTargetEventHook(ScriptState* script_state,
                                         v8::Local<v8::Value> hook);

  // The element's player plays to AirPlay targets (the native HLS player), on
  // a Safari-identity page; its Remote Playback is AirPlay.
  bool PlaysToPlaybackTargets() const;
  // AirPlay devices are nearby and the element doesn't disable AirPlay.
  bool PlaybackTargetsAvailable() const {
    return !wireless_playback_target_disabled_ && has_playback_targets_;
  }
  // x-webkit-airplay="deny", webkitwirelessvideoplaybackdisabled or
  // disableremoteplayback (isWirelessPlaybackTargetDisabled).
  bool WirelessPlaybackTargetDisabled() const;
  // The target's device name (MediaPlaybackTarget::deviceName).
  const String& PlaybackTargetDeviceName() const {
    return playback_target_device_name_;
  }
  // The AirPlay glyph in the window's Space tint, as a CSS image, for the
  // connecting and connected button and the placard (dark surfaces), or for a
  // light surface (the overflow menu on a light page); null without a tint.
  String AirPlayTintedGlyph(bool on_light_surface = false) const;

  // The player plays to the AirPlay device now, or no longer (WebKit's
  // mediaPlayerCurrentPlaybackTargetIsWirelessChanged).
  void PlaybackTargetIsWirelessChanged(bool wireless);

  // webkitCurrentPlaybackTargetIsWireless or the target's device name
  // changed: PlacardSupport's AirPlay placard on a video.
  void PlayingToWirelessTargetChanged();

  void Trace(Visitor* visitor) const override;

 private:
  friend class HTMLMediaElement;
  friend class ParcMediaElementTest;

  HTMLMediaElement& Media() const { return *GetSupplementable(); }

  // The element moved to another document: the timer follows its task runner.
  void MoveTimerToNewTaskRunner();

  // The element's own steps, at the points where WebKit's run them: a player
  // was made (mediaEngineUpdated), the player reached HAVE_METADATA, the
  // player was cleared (clearMediaPlayer), and a <source> child came or went.
  void PlayerCreated();
  void MetadataLoaded();
  void PlayerCleared();
  void SourceWasAdded();
  void SourceWasRemoved();
  // webkitplaybacktargetavailabilitychanged listeners (WebKit's
  // HTMLMediaElement::addEventListener and removeEventListener).
  void EventListenerAdded(const AtomicString& event_type);
  void EventListenerRemoved(const AtomicString& event_type);

  // media::mojom::blink::MediaPlayer's AirPlay messages.
  void SetPlaybackTargetAvailability(bool available);
  void SetPlaybackTarget(const String& output_context_id,
                         const String& device_name,
                         bool should_play,
                         uint32_t tint_argb,
                         uint32_t tint_on_light_argb);
  void PlaybackTargetPickerDismissed();

  // isWirelessPlaybackTargetDisabledChanged.
  void WirelessPlaybackTargetDisabledChanged();
  // enqueuePlaybackTargetAvailabilityChangedEvent; `only_when_changed` skips
  // an event that would repeat the last one's availability.
  void EnqueuePlaybackTargetAvailabilityEvent(bool only_when_changed);
  // The element's AirPlay state, to the browser and the player.
  void ReportPlaybackTargetState();
  void ApplyPlaybackTargetToPlayer();
  // setIsPlayingToWirelessTarget: in a media element task, then
  // webkitcurrentplaybacktargetiswirelesschanged.
  void UpdatePlayingToWirelessTarget();
  void DidChangePlayingToWirelessTarget();
  bool HasPlaybackTargetAvailabilityListeners() const;
  // RemotePlayback's AirPlay availability may have changed.
  void RemoteAvailabilityChanged();
  // checkPlaybackTargetCompatibility, half a second after the element starts
  // or stops playing to the target.
  void CheckPlaybackTargetCompatibility(TimerBase*);
  // hasWirelessPlaybackTargetAlternative.
  bool HasWirelessPlaybackTargetAlternative() const;
  // The player plays to a target, or the element switches to one that can.
  bool SupportsPlaybackTarget() const;
  // deferredMediaSourceOpenCanProgress and openIfDeferredOpen: a
  // ManagedMediaSource opens once the element disables AirPlay or has an
  // AirPlay alternative.
  bool DeferredMediaSourceOpenCanProgress() const;
  void OpenIfDeferredOpen();

  bool has_playback_targets_ = false;
  bool last_availability_event_ = false;
  bool playing_to_wireless_target_ = false;
  // What the current player last reported (isCurrentPlaybackTargetWireless).
  bool player_wireless_ = false;
  bool wireless_playback_target_disabled_ = false;
  String playback_target_id_;
  String playback_target_device_name_;
  uint32_t playback_target_tint_ = 0;
  uint32_t playback_target_tint_on_light_ = 0;
  bool should_play_to_playback_target_ = false;
  // m_remotePlaybackConfiguration while the element switches to a <source>
  // alternative: its time, applied once that has future data. Rate and paused
  // stay with the element.
  std::optional<double> remote_playback_time_;
  // What the Media Source player was last told (its m_shouldPlayToTarget), and
  // that the check turned the target down (m_failedToPlayToWirelessTarget).
  bool player_should_play_ = false;
  bool failed_to_play_to_wireless_target_ = false;
  std::unique_ptr<WebMediaSource> deferred_web_media_source_;
  // See CheckPlaybackTargetCompatibility().
  HeapTaskRunnerTimer<ParcMediaElementAirPlay>
      check_playback_target_compatibility_timer_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_AIR_PLAY_H_

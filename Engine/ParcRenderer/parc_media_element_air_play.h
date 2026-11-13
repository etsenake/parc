// Copyright 2026 Parc contributors.
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

  static void ProvideTo(HTMLMediaElement& element);
  static ParcMediaElementAirPlay& From(const HTMLMediaElement& element);

  explicit ParcMediaElementAirPlay(HTMLMediaElement& element);
  ~ParcMediaElementAirPlay();

  static void webkitShowPlaybackTargetPicker(HTMLMediaElement& element);
  static bool webkitCurrentPlaybackTargetIsWireless(HTMLMediaElement& element);
  static bool webkitWirelessVideoPlaybackDisabled(HTMLVideoElement& video);
  static void setWebkitWirelessVideoPlaybackDisabled(HTMLVideoElement& video,
                                                     bool disabled);

  static void SetPlaybackTargetEventHook(ScriptState* script_state,
                                         v8::Local<v8::Value> hook);

  bool PlaysToPlaybackTargets() const;
  bool PlaybackTargetsAvailable() const {
    return !wireless_playback_target_disabled_ && has_playback_targets_;
  }
  bool WirelessPlaybackTargetDisabled() const;
  const String& PlaybackTargetDeviceName() const {
    return playback_target_device_name_;
  }
  String AirPlayTintedGlyph(bool on_light_surface = false) const;

  void PlaybackTargetIsWirelessChanged(bool wireless);

  void PlayingToWirelessTargetChanged();

  void Trace(Visitor* visitor) const override;

 private:
  friend class HTMLMediaElement;
  friend class ParcMediaElement;
  friend class ParcMediaElementTest;

  HTMLMediaElement& Media() const { return *GetSupplementable(); }

  void MoveTimerToNewTaskRunner();

  void PlayerCreated();
  void MetadataLoaded();
  void PlayerCleared();
  void RestoreRemotePlaybackTime(bool tracks_are_ready,
                                 HTMLMediaElement::ReadyState old_state);
  bool DefersMediaSourceOpen(
      std::unique_ptr<WebMediaSource>& web_media_source);
  void SourceWasAdded();
  void SourceWasRemoved();
  void EventListenerAdded(const AtomicString& event_type);
  void EventListenerRemoved(const AtomicString& event_type);

  void SetPlaybackTargetAvailability(bool available);
  void SetPlaybackTarget(const String& output_context_id,
                         const String& device_name,
                         bool should_play,
                         uint32_t tint_argb,
                         uint32_t tint_on_light_argb);
  void PlaybackTargetPickerDismissed();

  void WirelessPlaybackTargetDisabledChanged();
  void EnqueuePlaybackTargetAvailabilityEvent(bool only_when_changed);
  void ReportPlaybackTargetState();
  void ApplyPlaybackTargetToPlayer();
  void UpdatePlayingToWirelessTarget();
  void DidChangePlayingToWirelessTarget();
  bool HasPlaybackTargetAvailabilityListeners() const;
  void RemoteAvailabilityChanged();
  void CheckPlaybackTargetCompatibility(TimerBase*);
  bool HasWirelessPlaybackTargetAlternative() const;
  bool SupportsPlaybackTarget() const;
  bool DeferredMediaSourceOpenCanProgress() const;
  void OpenIfDeferredOpen();

  bool has_playback_targets_ = false;
  bool last_availability_event_ = false;
  bool playing_to_wireless_target_ = false;
  bool player_wireless_ = false;
  bool wireless_playback_target_disabled_ = false;
  String playback_target_id_;
  String playback_target_device_name_;
  uint32_t playback_target_tint_ = 0;
  uint32_t playback_target_tint_on_light_ = 0;
  bool should_play_to_playback_target_ = false;
  std::optional<double> remote_playback_time_;
  bool player_should_play_ = false;
  bool failed_to_play_to_wireless_target_ = false;
  std::unique_ptr<WebMediaSource> deferred_web_media_source_;
  HeapTaskRunnerTimer<ParcMediaElementAirPlay>
      check_playback_target_compatibility_timer_;
};

}

#endif

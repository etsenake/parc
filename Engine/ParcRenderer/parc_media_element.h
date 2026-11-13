// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_H_

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/containers/span.h"
#include "base/time/time.h"
#include "media/base/parc_inband_tracks.h"
#include "services/media_session/public/mojom/media_session.mojom-blink-forward.h"
#include "third_party/blink/public/mojom/frame/lifecycle.mojom-blink-forward.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/parc_page_media_state.h"
#include "third_party/blink/renderer/core/html/track/track_base.h"
#include "third_party/blink/renderer/core/page/page_visibility_observer.h"
#include "third_party/blink/renderer/platform/bindings/exception_code.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_hash_map.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/media/parc_media_player_client.h"
#include "third_party/blink/renderer/platform/network/mime/mime_type_registry.h"
#include "third_party/blink/renderer/platform/scheduler/public/post_cancellable_task.h"
#include "third_party/blink/renderer/platform/supplementable.h"
#include "third_party/blink/renderer/platform/timer.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

class SkBitmap;

namespace gfx {
class RectF;
class SizeF;
}

namespace blink {

class AudioTrack;
class Document;
class Event;
class ExceptionState;
class KURL;
class ParcInbandTextTrack;
class ScriptObject;
class ScriptState;
class V8TextTrackKind;

class CORE_EXPORT ParcMediaElement final
    : public GarbageCollected<ParcMediaElement>,
      public Supplement<HTMLMediaElement>,
      public ParcMediaPlayerClient {
 public:
  static const char kSupplementName[];

  static void ProvideTo(HTMLMediaElement& element);
  static ParcMediaElement& From(const HTMLMediaElement& element);

  explicit ParcMediaElement(HTMLMediaElement& element);

  static MIMETypeRegistry::SupportsType SupportsType(
      const Document& document,
      const String& type,
      bool fairplay_dolby_vision);

  static String WebKitPlayErrorMessage(DOMExceptionCode code);

  static bool DocumentIsPlayingAudio(const Document& document);

  static bool ProcessingUserGestureForMedia(const Document& document);
  static void NoteUserActivatedMediaEnded(const Document& document);

  void PlaybackStopped();
  void LoadWillStart();
  bool PlaybackPermitted(bool created_during_media_gesture,
                         bool audio_reported,
                         bool for_autoplay) const;

  bool HadMediaUserGesture() const { return had_media_user_gesture_; }

  bool WaitForKey();
  bool StopWaitingForKey();

  double PlayerPlaybackRate() const;
  void ScheduleCueTimeupdate();

  void MediaSourceEnded();
  void MediaSourceEndedWithError(bool network_error);
  bool CancelsLoadWhenMediaSourceDetaches() const;
  void MediaSourceWasDetached();

  void PictureInPictureEnded();
  void OpenerContextDestroyed();

  SkBitmap PaintTextTracksForPictureInPicture(const gfx::SizeF& window_size,
                                              float device_scale_factor,
                                              gfx::RectF& bounds);

  bool PresentsParcSafariIdentity() const override;
  void ParcVideoLayerSize(gfx::SizeF* size, float* scale) const override;
  bool ParcPreparesToPlay() const override;
  void ParcPlayerTimeChanged() override;
  void ParcPlaybackTargetIsWirelessChanged(bool wireless) override;
  void ParcReportMediaMetadata(
      bool has_audio,
      bool has_video,
      media::MediaContentType media_content_type) override;
  void ParcWebKitMediaSourceKeyNeeded(base::span<const uint8_t> sinf) override;
  void ParcWebKitKeyRequest(std::string_view key_uri) override;
  void ParcSetInbandTextTracks(
      const std::vector<media::ParcInbandTextTrack>& tracks,
      media::ParcInbandTextTrackModeCB set_mode) override;
  void ParcAddInbandTextCues(
      const std::string& key,
      const std::vector<media::ParcInbandTextCue>& cues) override;
  void ParcAddInbandDataCues(
      const std::string& key,
      const std::vector<media::ParcInbandDataCue>& cues) override;
  void ParcSetInbandAudioTracks(
      const std::vector<media::ParcInbandAudioTrack>& tracks,
      media::ParcInbandAudioTrackEnabledCB set_enabled) override;

  void Trace(Visitor* visitor) const override;

 private:
  friend class HTMLMediaElement;
  friend class ParcMediaElementTest;

  class PageObserver final : public GarbageCollected<PageObserver>,
                             public PageVisibilityObserver,
                             public ParcPageMediaState::InWindowObserver {
   public:
    explicit PageObserver(ParcMediaElement* parc);

    void Observe(Page* page);

    void Trace(Visitor* visitor) const final;

   private:
    void PageVisibilityChanged() final;
    void PageInWindowChanged(Page& page) final;

    Member<ParcMediaElement> parc_;
  };

  struct DocumentMove {
    bool keeps_player;
    Document* old_context;
    Document* new_context;
    bool moves_player_to_frame;
  };

  HTMLMediaElement& Media() const { return *GetSupplementable(); }

  DocumentMove BeginDocumentMove(Document& old_document);
  bool FinishesMoveWithoutOpener(const DocumentMove& move,
                                 Document& old_document);
  void FinishDocumentMove(const DocumentMove& move, Document& old_document);
  void AutoplayAttributeChanged();
  std::optional<bool> FrameHiddenOnInsertion(std::optional<bool> is_hidden);
  void PrepareToPlayAfterSelectionIfNeeded();
  void ExplicitLoadInvoked();
  void LoadAlgorithmStarted();
  void LoadInterruptedPlayback(bool explicit_load);
  void ResetPlaybackRateForLoad(bool default_rate_valid);
  void ExitPictureInPictureWithoutSource();
  void PrepareToPlayBeforeLoad();
  bool MayDeferLoad(const KURL& url) const;
  void PlayerWillLoad();
  bool IgnoresPlayerReadyState();
  bool SeekMayFinishOnReadyState(HTMLMediaElement::ReadyState old_state) const;
  void PrepareToPlayForFragment(double start_time);
  void PauseIfNotPermittedAtFutureData(HTMLMediaElement::ReadyState old_state);
  bool StopsProgressEvents();
  void SeekPlayer(double time);
  void SeekFinished(bool was_playing_before_seeking);
  double PlayingCurrentTime() const;
  void WillSetPaused(bool paused);
  bool ReportsEndOnRateChange(double rate) const;
  void PostEndCheckAfterRateChange();
  static void CheckEndAfterRateChange(HTMLMediaElement* element);
  bool PostsDeferredMediaLoad();
  bool PreloadsAuto() const;
  void LoadDeferredMediaBeforePlay();
  bool VolumeChangeHandledAsWebKit();
  bool MuteChangeHandledAsWebKit();
  void AutoplayAfterMuteChange();
  bool InbandAudioTrackChanged(AudioTrack* track,
                               TrackBase::ChangeSource source);
  bool SendEnabledAudioTracks();
  bool AllowsTextTrackKind(const V8TextTrackKind& kind,
                           ExceptionState& exception_state) const;
  void NotePlayerFinishedSeek();
  bool EndedForTimeChanged() const;
  void WillLoop();
  bool FiresEndedEvent();
  void NotAtEnd();
  void PrepareToPlayBeforePlayStateUpdate();
  bool HoldsPlayback() const;
  void PlayerCleared();
  bool KeepsPlayingAfterRemoval() const;
  bool InContextPictureInPicture() const;

  bool WithinBackgroundGrace() const;

  void MoveTimersToNewTaskRunner();

  void PauseIfPlaybackNotPermitted(bool reject_as_not_allowed,
                                   bool audio_reported = false);
  void BeginAutoplay();
  void LatchMutedAttribute();
  void NoteMediaUserGesture();

  void PrepareToPlay();
  void PrepareToPlayIfCouldPlay();
  bool HasFutureDataAsWebKit(HTMLMediaElement::ReadyState state) const;
  void NoteFutureDataAsWebKit();
  void NoteReadyState(HTMLMediaElement::ReadyState state);
  void ResetReadyStateMaximum();
  bool PotentiallyPlayingForEvents() const;
  void PrepareForLoad();

  void MediaSourceLoaded();

  void Seek(double time);
  void PostSeekTask();
  void SeekTask();
  void ClearSeeking();
  void ResetSeekState();
  bool SeekAwaitsTask() const;
  void CancelPendingSeek();
  void ScheduleNotifyPlayingAfterSeek();
  void SetCurrentTimeForBindings(double time, ExceptionState& exception_state);
  void FastSeek(double time);
  ScriptObject GetStartDate(ScriptState* script_state) const;

  void ScheduleTimeupdateEvent(bool periodic_event);
  void ScheduleUnconditionalTimeupdateEvent();
  void CancelPeriodicTimeupdate();
  void ResumeRepeatingProgressTimer();

  void HandleSeekToPlaybackPosition(double position);
  void RemoteScrubEndTimerFired(TimerBase*);
  void HandlePlaybackControlsAction(
      media_session::mojom::blink::PlaybackControlsAction action,
      base::TimeDelta seek_time);
  void StopScrubbing();

  bool ContextLifecycleStateChanged(mojom::blink::FrameLifecycleState state);
  void ResumeAfterBackForwardCacheIfAllowed();
  void UpdatePlayerPageVisibility();

  static Document* ContextDocument(Document& document);
  static bool KeepsPlayerAcrossDocuments(Document& old_document,
                                         Document& new_document);
  bool IsPictureInPictureElementOf(Document* document) const;
  bool MovePlayerToFrame();

  ParcInbandTextTrack* FindInbandTextTrack(const std::string& key);
  void RemoveInbandTextTrack(ParcInbandTextTrack* track);
  const String* InbandAudioTrackKey(AudioTrack* track) const;
  void ForgetResourceSpecificTracks();

  HTMLMediaElement::ReadyState ready_state_maximum_ =
      HTMLMediaElement::kHaveNothing;
  base::TimeTicks last_timeupdate_clock_;
  Member<Event> periodic_timeupdate_;
  bool progress_timer_resumes_repeating_ = false;
  bool finishing_seek_ = false;
  bool cue_timeupdate_after_seek_ = false;
  bool completely_loaded_ = false;
  bool had_media_user_gesture_ = false;
  bool playback_blocked_waiting_for_key_ = false;
  HTMLMediaElement::ReadyState player_ready_state_ =
      HTMLMediaElement::kHaveNothing;
  std::optional<double> fast_seek_tolerance_;
  bool has_ever_prepared_to_play_ = false;
  bool had_future_data_as_webkit_ = false;
  bool prepare_to_play_after_selection_ = false;
  bool media_source_failed_ = false;
  struct PendingSeek {
    double now;
    double time;
    double tolerance_before;
  };
  bool seek_from_page_ = false;
  std::optional<PendingSeek> pending_seek_;
  TaskHandle seek_task_;
  TaskHandle media_source_ended_task_;
  TaskHandle lazy_load_resume_task_;
  bool seek_with_player_ = false;
  bool fast_seek_with_player_ = false;
  bool sent_end_event_ = false;
  bool pending_notify_playing_ = false;
  bool player_finished_seek_ = false;
  bool scrubbing_playback_controls_ = false;
  bool scrubbing_remotely_ = false;
  bool was_playing_before_seeking_ = false;
  HeapTaskRunnerTimer<ParcMediaElement> remote_scrub_end_timer_;
  bool paused_for_back_forward_cache_ = false;
  bool paused_for_invisible_autoplay_ = false;
  HeapHashMap<String, Member<AudioTrack>> inband_audio_tracks_;
  media::ParcInbandAudioTrackEnabledCB set_inband_audio_track_enabled_;
  bool reports_inband_audio_tracks_ = false;
  bool player_waits_for_picture_in_picture_end_ = false;
  Member<PageObserver> page_observer_;
  std::optional<base::TimeTicks> playback_stopped_;
  bool hidden_autoplay_granted_ = false;
};

}

#endif

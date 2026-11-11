// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_media_element.h.
// The Parc side of an HTMLMediaElement: WebKit's media element behaviour on a
// Safari-identity page. Its state and steps live here; the element's own
// algorithm (html_media_element.cc) calls them at the points where WebKit's
// run, so their order is the element's. The element makes it when it is made,
// so it lasts exactly as long as the element. It is also what the element's
// player reaches through MediaPlayerClient::ParcClient(). Main thread.
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
}  // namespace gfx

namespace blink {

class AudioTrack;
class Document;
class Event;
class ExceptionState;
class ParcInbandTextTrack;
class ScriptObject;
class ScriptState;

class CORE_EXPORT ParcMediaElement final
    : public GarbageCollected<ParcMediaElement>,
      public Supplement<HTMLMediaElement>,
      public ParcMediaPlayerClient {
 public:
  static const char kSupplementName[];

  // HTMLMediaElement's constructor.
  static void ProvideTo(HTMLMediaElement& element);
  static ParcMediaElement& From(const HTMLMediaElement& element);

  explicit ParcMediaElement(HTMLMediaElement& element);

  // What a document is told about a type under its identity
  // (parc_safari_identity.h). AC-3 and E-AC-3 answer yes only under Safari's
  // identity. With `fairplay_dolby_vision`, under it, Dolby Vision profile 5,
  // which FairPlay plays encrypted (its CDM capability in
  // fairplay-media.patch), answers yes as in Safari: the rest of the type is
  // checked without it, as Chromium's Media Source and EME already do for
  // encrypted Dolby Vision. Clear Dolby Vision still can't play, so choosing a
  // <source> leaves it out. A document without a window of its own answers for
  // the window that created it.
  static MIMETypeRegistry::SupportsType SupportsType(
      const Document& document,
      const String& type,
      bool fairplay_dolby_vision);

  // WebKit rejects play promises with DOMExceptions made without a message,
  // which take their code's description (DOMException::create); play()'s own
  // NotSupportedError gives that same text.
  static String WebKitPlayErrorMessage(DOMExceptionCode code);

  // Whether a playing element of `document` is audible. Defined in
  // html_media_element.cc, beside the document's set of media elements.
  static bool DocumentIsPlayingAudio(const Document& document);

  // Whether a user gesture reached a load, play, volume, muted, audio track or
  // autoplay change of this element. WebKit lifts its fullscreen and
  // picture-in-picture gesture rule for the element from then on
  // (HTMLMediaElement::removeBehaviorRestrictionsAfterFirstUserGesture);
  // Safari's presentation script reads it (parc_webkit_presentation.h).
  bool HadMediaUserGesture() const { return had_media_user_gesture_; }

  // WebKit's Wait for Key, once while playback is blocked, and its end
  // (HTMLMediaElement::mediaPlayerWaitingForKeyChanged) on a Safari-identity
  // page. False elsewhere, where the encrypted media supplement runs Blink's.
  bool WaitForKey();
  bool StopWaitingForKey();

  // The rate the player is given: playbackRate() within what it can play.
  double PlayerPlaybackRate() const;
  // The cue timeline ran while playing, with the time reached without a seek
  // since it last ran (WebKit's updateActiveTextTrackCues, step 5).
  void ScheduleCueTimeupdate();

  // The attached MediaSource ended its stream without an error, or with a
  // network or decode error.
  void MediaSourceEnded();
  void MediaSourceEndedWithError(bool network_error);
  // The worker that owns the attached MediaSource went away. Under Safari's
  // identity this runs WebKit's mediaSourceWasDetached(); the cross-thread
  // attachment asks first, on attaching.
  bool CancelsLoadWhenMediaSourceDetaches() const;
  void MediaSourceWasDetached();

  // The video left picture in picture. A player a Safari-identity page left
  // with its old frame for it follows the element's frame now.
  void PictureInPictureEnded();
  // The element's opener context went (its OpenerContextObserver).
  void OpenerContextDestroyed();

  // TextTrackContainer::PaintForPictureInPicture.
  SkBitmap PaintTextTracksForPictureInPicture(const gfx::SizeF& window_size,
                                              float device_scale_factor,
                                              gfx::RectF& bounds);

  // ParcMediaPlayerClient implementation.
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
  // Safari's native HLS route's in-band text tracks and cues
  // (media::ParcInbandTrackSink).
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
  friend class HTMLMediaElementTest;

  // Tells the element when its page's visibility changes, while playback is
  // held for the back/forward cache or its player belongs to another page's
  // frame.
  class PageObserver final : public GarbageCollected<PageObserver>,
                             public PageVisibilityObserver {
   public:
    explicit PageObserver(ParcMediaElement* parc);

    void Trace(Visitor* visitor) const final;

   private:
    void PageVisibilityChanged() final;
    void ParcPageInWindowChanged() final;

    Member<ParcMediaElement> parc_;
  };

  HTMLMediaElement& Media() const { return *GetSupplementable(); }

  // The element moved to another document (HTMLMediaElement's
  // DidMoveToNewDocument): the timers follow its task runner.
  void MoveTimersToNewTaskRunner();

  // Under Safari's identity, pauses media playing against Safari's autoplay
  // rule (AutoplayPolicy::ParcPlaybackPermitted), refusing its play()
  // promises as not allowed or as aborted.
  void PauseIfPlaybackNotPermitted(bool reject_as_not_allowed,
                                   bool audio_reported = false);
  // The autoplay steps of reaching HAVE_ENOUGH_DATA.
  void BeginAutoplay();
  // Under Safari's identity, fixes muted from the muted attribute at the first
  // connection or resource load unless script set muted first.
  void LatchMutedAttribute();
  // See HadMediaUserGesture().
  void NoteMediaUserGesture();

  // WebKit's prepareToPlay under Safari's identity. Having prepared to play on
  // any load (m_hasEverPreparedToPlay, never reset) keeps the element's
  // preload auto (EffectivePreloadType).
  void PrepareToPlay();
  // As WebKit's updatePlayState, an element that could play but isn't
  // potentially playing prepares to play.
  void PrepareToPlayIfCouldPlay();
  // Whether `state` is HAVE_FUTURE_DATA or more as WebKit's player would
  // report it.
  bool HasFutureDataAsWebKit(HTMLMediaElement::ReadyState state) const;
  // Records in had_future_data_as_webkit_ whether WebKit's player has reached
  // HAVE_FUTURE_DATA on this load.
  void NoteFutureDataAsWebKit();
  // WebKit's m_readyStateMaximum: readyState reached `state`.
  void NoteReadyState(HTMLMediaElement::ReadyState state);
  // A load or the context's end resets readyState to HAVE_NOTHING.
  void ResetReadyStateMaximum();
  // Whether the element was potentially playing for `waiting`: as
  // PotentiallyPlaying(), or WebKit's rule under Safari's identity.
  bool PotentiallyPlayingForEvents() const;
  // As WebKit's prepareForLoad.
  void PrepareForLoad();

  // The Media Source player's Loaded report after endOfStream().
  void MediaSourceLoaded();

  // WebKit's HTMLMediaElement::seekWithTolerance, HTMLMediaElement::Seek() on
  // a Safari-identity page.
  void Seek(double time);
  void PostSeekTask();
  void SeekTask();
  void ClearSeeking();
  // The seek state a finished or cleared seek leaves.
  void ResetSeekState();
  bool SeekAwaitsTask() const;
  // Drops the queued seek with the element's other pending tasks.
  void CancelPendingSeek();
  // WebKit's scheduleNotifyAboutPlaying: a `playing` that readyState brings
  // while seeking fires after `seeked` (maybeFirePendingPlaying).
  void ScheduleNotifyPlayingAfterSeek();
  // The currentTime attribute's setter, WebKit's fastSeek() and
  // getStartDate() ([ContextEnabled=ParcSafariIdentity]).
  void SetCurrentTimeForBindings(double time, ExceptionState& exception_state);
  void FastSeek(double time);
  ScriptObject GetStartDate(ScriptState* script_state) const;

  // WebKit's scheduleTimeupdateEvent on a Safari-identity page: a timeupdate
  // only when the current time differs from the last one's, and a periodic
  // one only 250ms after the last. HTMLMediaElement's ScheduleTimeupdateEvent
  // has told the player first.
  void ScheduleTimeupdateEvent(bool periodic_event);
  // HTMLMediaElement::ScheduleTimeupdateEvent(false), except that under
  // Safari's identity the timeupdate is one WebKit queues directly, outside
  // its dedupe and throttling (seek finished, load reset).
  void ScheduleUnconditionalTimeupdateEvent();
  // A starting seek drops a queued periodic timeupdate, as WebKit's
  // seekWithTolerance cancels it (only Safari's identity queues one).
  void CancelPeriodicTimeupdate();
  // The progress timer, deferred by the throttling, repeats again.
  void ResumeRepeatingProgressTimer();

  // WebKit's remote scrubbing on macOS. A scrub from the system's media
  // controls lasts until 500 ms after its last seek (m_isScrubbingRemotely);
  // playback its first seek paused resumes when a seek finishes, unless a
  // pause or a seek that needs no player clears it first
  // (m_wasPlayingBeforeSeeking).
  void HandleSeekToPlaybackPosition(double position);
  void RemoteScrubEndTimerFired(TimerBase*);
  // The media session's playback controls action (WebKit's
  // PlaybackSessionModelMediaElement).
  void HandlePlaybackControlsAction(
      media_session::mojom::blink::PlaybackControlsAction action,
      base::TimeDelta seek_time);
  // The context's end stops any scrub.
  void StopScrubbing();

  // WebKit's suspend() and resume() for the back/forward cache. Returns true
  // when it handled `state`, so Chromium's frozen-frame pause doesn't run.
  bool ContextLifecycleStateChanged(mojom::blink::FrameLifecycleState state);
  // Ends paused_for_back_forward_cache_ once the document runs and its page is
  // visible.
  void ResumeAfterBackForwardCacheIfAllowed();
  // Under Safari's identity, tells a player made by a frame on another page
  // than the element's the visibility of the element's page.
  void UpdatePlayerPageVisibility();

  // As WebKit's Document::contextDocument (DOMImplementation::
  // createHTMLDocument, a template's content): a document without a frame runs
  // in the window that made it, and an element there keeps its player in that
  // window's frame.
  static Document* ContextDocument(Document& document);
  // WebKit's HTMLMediaElement::didMoveToNewDocument keeps the element's
  // player, position, paused state and tracks on every move. A player here
  // belongs to the frame that created it, so under Safari's identity a move
  // between same-origin documents that have a frame or a context document
  // keeps the player bound to that frame, as a move into Document
  // Picture-in-Picture does.
  static bool KeepsPlayerAcrossDocuments(Document& old_document,
                                         Document& new_document);
  // Whether this element is `document`'s picture-in-picture element.
  bool IsPictureInPictureElementOf(Document* document) const;
  // Under Safari's identity, makes the player a document move kept belong to
  // the element's new frame, if it can move.
  bool MovePlayerToFrame();

  // The in-band tracks of Safari's native HLS route.
  ParcInbandTextTrack* FindInbandTextTrack(const std::string& key);
  void RemoveInbandTextTrack(ParcInbandTextTrack* track);
  // The key of a native HLS audio track, or null for any other track.
  const String* InbandAudioTrackKey(AudioTrack* track) const;
  // As WebKit's forgetResourceSpecificTracks.
  void ForgetResourceSpecificTracks();

  // The highest readyState since the load began; unlike the element's
  // ready_state_maximum_, not above what pending text tracks allowed.
  HTMLMediaElement::ReadyState ready_state_maximum_ =
      HTMLMediaElement::kHaveNothing;
  // When the last deduplicated timeupdate was queued, the periodic one still
  // queued (a starting seek drops it), and whether the progress timer,
  // deferred by the throttling, repeats again when it next fires.
  base::TimeTicks last_timeupdate_clock_;
  Member<Event> periodic_timeupdate_;
  bool progress_timer_resumes_repeating_ = false;
  // While FinishSeek() runs the cue timeline, and whether that asked for a
  // periodic timeupdate, which WebKit queues after seeked.
  bool finishing_seek_ = false;
  bool cue_timeupdate_after_seek_ = false;
  // WebKit's m_completelyLoaded, set once the player reports Loaded.
  bool completely_loaded_ = false;
  bool had_media_user_gesture_ = false;
  // WebKit's playback blocked waiting for key value, and the player's
  // readyState as last heard while it is set.
  bool playback_blocked_waiting_for_key_ = false;
  HTMLMediaElement::ReadyState player_ready_state_ =
      HTMLMediaElement::kHaveNothing;
  // While FastSeek() runs Seek(), how far before its target the seek may land.
  std::optional<double> fast_seek_tolerance_;
  bool has_ever_prepared_to_play_ = false;
  bool had_future_data_as_webkit_ = false;
  // load() was called; the load timer prepares to play after resource
  // selection.
  bool prepare_to_play_after_selection_ = false;
  // See MediaSourceEndedWithError().
  bool media_source_failed_ = false;
  // WebKit's seek state on a Safari-identity page. While a page's seek runs
  // Seek(), it continues in a queued task (m_pendingSeek, with the position it
  // started from); a seek, or a fast one, is with the player (m_seekRequest,
  // m_pendingSeekType); `ended` fired since playback last left the end
  // (m_sentEndEvent); a `playing` waits for the seek to finish
  // (m_pendingNotifyAboutPlaying).
  struct PendingSeek {
    double now;
    double time;
    double tolerance_before;
  };
  bool seek_from_page_ = false;
  std::optional<PendingSeek> pending_seek_;
  TaskHandle seek_task_;
  // The Media Source player's Loaded report after endOfStream() and a resumed
  // lazy load's resource selection, each in its own task as WebKit's.
  TaskHandle media_source_ended_task_;
  TaskHandle lazy_load_resume_task_;
  bool seek_with_player_ = false;
  bool fast_seek_with_player_ = false;
  bool sent_end_event_ = false;
  bool pending_notify_playing_ = false;
  // The player finished a Safari Media Source seek (TimeChanged) while
  // readyState was below HAVE_CURRENT_DATA, so its rise finishes the seek.
  bool player_finished_seek_ = false;
  // See HandleSeekToPlaybackPosition().
  bool scrubbing_playback_controls_ = false;
  bool scrubbing_remotely_ = false;
  bool was_playing_before_seeking_ = false;
  HeapTaskRunnerTimer<ParcMediaElement> remote_scrub_end_timer_;
  // Under Safari's identity, WebKit's paused-internal state while the
  // document is in the back/forward cache; paused() is unchanged.
  bool paused_for_back_forward_cache_ = false;
  // Whether the last pause was the autoplay policy's for an invisible muted
  // autoplay, still in effect.
  bool paused_for_invisible_autoplay_ = false;
  // Safari's native HLS route's audio tracks by key, the way back to its
  // player, and whether it reports this resource's audio tracks (no
  // placeholder track then: WebKit has none).
  HeapHashMap<String, Member<AudioTrack>> inband_audio_tracks_;
  media::ParcInbandAudioTrackEnabledCB set_inband_audio_track_enabled_;
  bool reports_inband_audio_tracks_ = false;
  // The player stayed with its frame on a Safari-identity move only because
  // the video was in picture in picture; it moves once that ends.
  bool player_waits_for_picture_in_picture_end_ = false;
  Member<PageObserver> page_observer_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_H_

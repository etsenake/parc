// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_media_element.cc.
#include "third_party/blink/renderer/core/html/media/parc_media_element.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#include "base/auto_reset.h"
#include "base/feature_list.h"
#include "media/base/media_switches.h"
#include "media/base/video_codec_string_parsers.h"
#include "media/media_buildflags.h"
#include "services/media_session/public/mojom/media_session.mojom-blink.h"
#include "third_party/blink/public/mojom/frame/lifecycle.mojom-blink.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_need_key.h"
#include "third_party/blink/renderer/bindings/core/v8/script_value.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/core/css/style_engine.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/dom/events/event_queue.h"
#include "third_party/blink/renderer/core/event_type_names.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/frame/picture_in_picture_controller.h"
#include "third_party/blink/renderer/core/html/media/autoplay_policy.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/media_controls.h"
#include "third_party/blink/renderer/core/html/media/media_error.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"
#include "third_party/blink/renderer/core/html/media/parc_inband_text_track.h"
#include "third_party/blink/renderer/core/html/media/parc_media_player_move.h"
#include "third_party/blink/renderer/core/html/time_ranges.h"
#include "third_party/blink/renderer/core/html/track/audio_track.h"
#include "third_party/blink/renderer/core/html/track/audio_track_list.h"
#include "third_party/blink/renderer/core/html/track/cue_timeline.h"
#include "third_party/blink/renderer/core/html/track/text_track_container.h"
#include "third_party/blink/renderer/core/html/track/text_track_list.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/core/layout/layout_box.h"
#include "third_party/blink/renderer/core/page/chrome_client.h"
#include "third_party/blink/renderer/core/page/page.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/media/remote_playback_client.h"
#include "third_party/blink/renderer/platform/network/mime/content_type.h"
#include "third_party/blink/renderer/platform/runtime_enabled_features.h"
#include "third_party/blink/renderer/platform/weborigin/security_origin.h"
#include "third_party/blink/renderer/platform/wtf/casting.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/display/screen_info.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size_f.h"

namespace blink {

namespace {

// WebKit's maxTimeupdateEventFrequency. The element's progress timer repeats
// at Chromium's, which is also 250ms.
constexpr base::TimeDelta kWebKitMaxTimeupdateEventFrequency =
    base::Milliseconds(250);

// The Parc operations of `player`, or null without a player or without them.
ParcWebMediaPlayerExtension* ParcExtension(WebMediaPlayer* player) {
  return player ? player->GetParcExtension() : nullptr;
}

parc_hooks::MoveWebMediaPlayer g_parc_move_web_media_player = nullptr;

}  // namespace

namespace parc_hooks {
MoveWebMediaPlayer SetMoveWebMediaPlayer(MoveWebMediaPlayer hook) {
  return std::exchange(g_parc_move_web_media_player, hook);
}
}  // namespace parc_hooks

const char ParcMediaElement::kSupplementName[] = "ParcMediaElement";

void ParcMediaElement::ProvideTo(HTMLMediaElement& element) {
  Supplement<HTMLMediaElement>::ProvideTo(
      element, MakeGarbageCollected<ParcMediaElement>(element));
}

ParcMediaElement& ParcMediaElement::From(const HTMLMediaElement& element) {
  return *Supplement<HTMLMediaElement>::From<ParcMediaElement>(element);
}

ParcMediaElement::ParcMediaElement(HTMLMediaElement& element)
    : Supplement<HTMLMediaElement>(element),
      remote_scrub_end_timer_(
          element.GetDocument().GetTaskRunner(TaskType::kInternalMedia),
          this,
          &ParcMediaElement::RemoteScrubEndTimerFired) {}

void ParcMediaElement::Trace(Visitor* visitor) const {
  visitor->Trace(periodic_timeupdate_);
  visitor->Trace(remote_scrub_end_timer_);
  visitor->Trace(inband_audio_tracks_);
  visitor->Trace(page_observer_);
  Supplement<HTMLMediaElement>::Trace(visitor);
}

void ParcMediaElement::MoveTimersToNewTaskRunner() {
  remote_scrub_end_timer_.MoveToNewTaskRunner(
      Media().GetDocument().GetTaskRunner(TaskType::kInternalMedia));
}

MIMETypeRegistry::SupportsType ParcMediaElement::SupportsType(
    const Document& document,
    const String& type,
    bool fairplay_dolby_vision) {
  const ContentType content_type(type);
  const String codecs = content_type.Parameter("codecs");
  ExecutionContext* context = document.GetExecutionContext();
  const bool safari =
      context && IsParcSafariIdentityUserAgent(context->UserAgent());
  if (safari && ParcSafariAV1Unavailable(codecs)) {
    return MIMETypeRegistry::kNotSupported;
  }
  if (!safari && IsParcSafariOnlyAudioCodecs(codecs)) {
    return MIMETypeRegistry::kNotSupported;
  }
#if BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION)
  if (safari && fairplay_dolby_vision &&
      base::FeatureList::IsEnabled(media::kPlatformEncryptedDolbyVision) &&
      EqualIgnoringAsciiCase(content_type.GetType(), "video/mp4") &&
      !codecs.empty()) {
    StringBuilder others;
    wtf_size_t other_count = 0;
    bool dolby_vision = false;
    bool empty_entry = false;
    for (const String& codec : codecs.Split(',')) {
      const String id = codec.StripWhiteSpace();
      if (id.ContainsOnlyAsciiOrEmpty()) {
        const std::optional<media::VideoType> parsed =
            media::ParseDolbyVisionCodecId(id.Ascii());
        if (parsed && parsed->profile == media::DOLBYVISION_PROFILE5) {
          dolby_vision = true;
          continue;
        }
      }
      empty_entry = empty_entry || id.empty();
      if (other_count++) {
        others.Append(',');
      }
      others.Append(id);
    }
    // A malformed list (an empty entry) answers as before.
    if (dolby_vision && !empty_entry) {
      if (!other_count) {
        return MIMETypeRegistry::kSupported;
      }
      StringBuilder without_dolby_vision;
      without_dolby_vision.Append(content_type.GetType());
      without_dolby_vision.Append("; codecs=\"");
      without_dolby_vision.Append(others);
      without_dolby_vision.Append('"');
      return HTMLMediaElement::GetSupportsType(
          ContentType(without_dolby_vision.ToString()));
    }
  }
#endif  // BUILDFLAG(ENABLE_PLATFORM_ENCRYPTED_DOLBY_VISION)
  return HTMLMediaElement::GetSupportsType(content_type);
}

String ParcMediaElement::WebKitPlayErrorMessage(DOMExceptionCode code) {
  switch (code) {
    case DOMExceptionCode::kAbortError:
      return "The operation was aborted.";
    case DOMExceptionCode::kNotSupportedError:
      return "The operation is not supported.";
    case DOMExceptionCode::kNotAllowedError:
      return "The request is not allowed by the user agent or the platform in "
             "the current context, possibly because the user denied "
             "permission.";
    default:
      NOTREACHED();
  }
}

void ParcMediaElement::NoteMediaUserGesture() {
  if (AutoplayPolicy::ParcProcessingUserGestureForMedia(
          Media().GetDocument())) {
    had_media_user_gesture_ = true;
  }
}

void ParcMediaElement::PauseIfPlaybackNotPermitted(bool reject_as_not_allowed,
                                                   bool audio_reported) {
  HTMLMediaElement& element = Media();
  if (element.paused_ || !PresentsParcSafariIdentity() ||
      element.autoplay_policy_->ParcPlaybackPermitted(audio_reported)) {
    return;
  }
  if (reject_as_not_allowed) {
    element.ScheduleRejectPlayPromises(
        HTMLMediaElement::PlayPromiseError::kParcNotAllowed);
  }
  element.PauseInternal(WebMediaPlayer::PauseReason::kPauseCalled);
}

void ParcMediaElement::BeginAutoplay() {
  HTMLMediaElement& element = Media();
  element.SetPaused(false);
  element.SetShowPosterFlag(false);
  element.GetCueTimeline().InvokeTimeMarchesOn();
  element.ScheduleNamedEvent(event_type_names::kPlay);
  ScheduleNotifyPlayingAfterSeek();
  element.can_autoplay_ = false;
}

// WebKit (HTMLMediaElement::postConnectionSteps and loadResource): the first
// of these sets m_explicitlyMuted and m_muted from the attribute, without a
// volumechange; from then on the attribute no longer changes muted. Use the
// current document here, not the creation document: adoption before either
// boundary must still let a Safari document latch the attribute. Without
// MediaElementMutedDefaultState, Chrome reads muted_ even before this latch.
void ParcMediaElement::LatchMutedAttribute() {
  HTMLMediaElement& element = Media();
  if (!element.muted_is_default_) {
    return;
  }
  if (PresentsParcSafariIdentity()) {
    element.muted_is_default_ = false;
    element.muted_ = element.FastHasAttribute(html_names::kMutedAttr);
  } else if (!RuntimeEnabledFeatures::MediaElementMutedDefaultStateEnabled()) {
    element.muted_is_default_ = false;
  }
}

bool ParcMediaElement::PresentsParcSafariIdentity() const {
  return Media().PresentsParcSafariIdentity();
}

bool ParcMediaElement::ParcPreparesToPlay() const {
  // Only the native HLS route asks, under Safari's identity, where the
  // effective preload follows WebKit's rules.
  return Media().EffectivePreloadType() == WebMediaPlayer::kPreloadAuto;
}

void ParcMediaElement::PrepareToPlay() {
  if (has_ever_prepared_to_play_ || !Media().GetDocument().GetFrame()) {
    return;
  }
  has_ever_prepared_to_play_ = true;
  // WebKit's player->prepareToPlay(): the player's preload becomes auto, and
  // a load deferred at preload none starts.
  Media().SetPlayerPreload();
}

void ParcMediaElement::PrepareToPlayIfCouldPlay() {
  // WebKit's potentiallyPlaying holds once readyState has reached
  // HAVE_FUTURE_DATA on this load, a stall since included.
  NoteFutureDataAsWebKit();
  if (Media().CouldPlayIfEnoughData() && !had_future_data_as_webkit_) {
    PrepareToPlay();
  }
}

void ParcMediaElement::NoteFutureDataAsWebKit() {
  // Sampled as readyState and the preload change, since WebKit's player
  // keeps the data it has when its preload is lowered.
  if (!had_future_data_as_webkit_ &&
      ready_state_maximum_ >= HTMLMediaElement::kHaveFutureData &&
      PresentsParcSafariIdentity()) {
    had_future_data_as_webkit_ = HasFutureDataAsWebKit(ready_state_maximum_);
  }
}

bool ParcMediaElement::HasFutureDataAsWebKit(
    HTMLMediaElement::ReadyState state) const {
  // WebKit's AVFoundation player has data past metadata only once its
  // preload is auto (it has no item before), or for a Media Source, a media
  // stream or a live stream; Chromium's may at a lower preload.
  if (state < HTMLMediaElement::kHaveFutureData) {
    return false;
  }
  HTMLMediaElement& element = Media();
  return element.EffectivePreloadType() == WebMediaPlayer::kPreloadAuto ||
         element.GetLoadType() != WebMediaPlayer::kLoadTypeURL ||
         element.duration() == std::numeric_limits<double>::infinity();
}

void ParcMediaElement::NoteReadyState(HTMLMediaElement::ReadyState state) {
  ready_state_maximum_ = std::max(ready_state_maximum_, state);
  NoteFutureDataAsWebKit();
}

void ParcMediaElement::ResetReadyStateMaximum() {
  ready_state_maximum_ = HTMLMediaElement::kHaveNothing;
  had_future_data_as_webkit_ = false;
}

bool ParcMediaElement::PotentiallyPlayingForEvents() const {
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity()) {
    return element.PotentiallyPlaying();
  }
  // WebKit's potentiallyPlaying, which decides `waiting`: from
  // HAVE_FUTURE_DATA, or below it once the element has had that much.
  // PotentiallyPlaying() still starts the player from HAVE_METADATA, which
  // buffers it there as WebKit's prepareToPlay (updatePlayState) does.
  return (element.ready_state_ >= HTMLMediaElement::kHaveFutureData ||
          ready_state_maximum_ >= HTMLMediaElement::kHaveFutureData) &&
         element.CouldPlayIfEnoughData();
}

void ParcMediaElement::PrepareForLoad() {
  sent_end_event_ = false;
  pending_notify_playing_ = false;
  seek_with_player_ = false;
  fast_seek_with_player_ = false;
  player_finished_seek_ = false;
}

void ParcMediaElement::ParcVideoLayerSize(gfx::SizeF* size,
                                          float* scale) const {
  // WebKit's initial video layer size is the element's content box
  // (mediaPlayerContentBoxRect). Layout here is in physical pixels (zoom for
  // device scale), so the display's scale divides it back to points.
  HTMLMediaElement& element = Media();
  if (!element.IsHTMLVideoElement()) {
    return;
  }
  LocalFrame* frame = element.GetDocument().GetFrame();
  auto* box = DynamicTo<LayoutBox>(element.GetLayoutObject());
  if (!frame || !frame->GetPage() || !box) {
    return;
  }
  const float device_scale = frame->GetPage()
                                 ->GetChromeClient()
                                 .GetScreenInfo(*frame)
                                 .device_scale_factor;
  const PhysicalSize content = box->PhysicalContentBoxRect().size;
  if (!(device_scale > 0) || content.IsEmpty()) {
    return;
  }
  *size = gfx::SizeF(content.width.ToFloat() / device_scale,
                     content.height.ToFloat() / device_scale);
  *scale = device_scale;
}

// Under Safari's identity, a MediaSource that ends with an error runs the
// failure steps in the same task, as WebKit's
// MediaSource::streamEndedWithError does (mediaLoadingFailed before metadata,
// mediaLoadingFailedFatally after), so they close it before the page's
// handlers run. The player's own report of that error is ignored
// (SetNetworkState()), and one it has already made stands.
void ParcMediaElement::MediaSourceEndedWithError(bool network_error) {
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity() || media_source_failed_ || element.error_ ||
      (element.web_media_player_ &&
       element.web_media_player_->GetNetworkState() >=
           WebMediaPlayer::kNetworkStateFormatError)) {
    return;
  }
  media_source_failed_ = true;
  WebMediaPlayer::NetworkState state =
      WebMediaPlayer::kNetworkStateNetworkError;
  if (!network_error) {
    state = element.ready_state_ >= HTMLMediaElement::kHaveMetadata
                ? WebMediaPlayer::kNetworkStateDecodeError
                : WebMediaPlayer::kNetworkStateFormatError;
  }
  element.MediaLoadingFailed(
      state, element.web_media_player_
                 ? String(element.web_media_player_->GetErrorMessage())
                 : String());
}

void ParcMediaElement::MediaSourceEnded() {
  // WebKit: Safari's Media Source player reports Loaded, its only network
  // state but an error, once the stream ends without one
  // (MediaPlayerPrivateMediaSourceAVFObjC::mediaSourceHasRetrievedAllData).
  // That report reaches the element later, from the GPU process
  // (HTMLMediaElement::mediaPlayerNetworkStateChanged), never within
  // endOfStream().
  if (PresentsParcSafariIdentity()) {
    media_source_ended_task_ = PostCancellableTask(
        *Media().GetDocument().GetTaskRunner(TaskType::kMediaElementEvent),
        FROM_HERE,
        BindOnce(&ParcMediaElement::MediaSourceLoaded,
                 WrapWeakPersistent(this)));
  }
}

void ParcMediaElement::MediaSourceLoaded() {
  Media().SetNetworkState(WebMediaPlayer::kNetworkStateLoaded);
}

bool ParcMediaElement::CancelsLoadWhenMediaSourceDetaches() const {
  return PresentsParcSafariIdentity();
}

// WebKit's mediaSourceWasDetached(), which runs userCancelledLoad(). A
// pending MediaSourceLoaded() counts as loaded: it arrives on another task
// queue than this notification.
void ParcMediaElement::MediaSourceWasDetached() {
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity() ||
      element.network_state_ == HTMLMediaElement::kNetworkEmpty ||
      completely_loaded_ || media_source_ended_task_.IsActive()) {
    return;
  }

  // 1 - The user agent should cancel the fetching process. WebKit's
  // clearMediaPlayer() also drops a queued seek (cancelPendingTasks), leaving
  // seeking set.
  if (element.playing_) {
    element.autoplay_policy_->ParcPlaybackStopped();
  }
  element.ClearMediaPlayer();
  CancelPendingSeek();

  // WebKit resets readyState without events since the player is gone, and
  // without a player or MediaSource reports no duration and time 0, seeking
  // or not (durationMediaTime, currentMediaTime). The controls reset before
  // the error is set: with an error they pause, which could select a
  // resource again.
  const bool had_nothing =
      element.ready_state_ == HTMLMediaElement::kHaveNothing;
  element.ready_state_ = HTMLMediaElement::kHaveNothing;
  element.duration_ = std::numeric_limits<double>::quiet_NaN();
  element.last_seek_time_ = 0;
  element.SetOfficialPlaybackPosition(0);
  element.GetCueTimeline().OnReadyStateReset();
  if (element.GetMediaControls() && element.isConnected()) {
    element.GetMediaControls()->Reset();
  }

  // 2 - Set the error attribute to a new MediaError object whose code
  // attribute is set to MEDIA_ERR_ABORTED.
  element.SetError(MakeGarbageCollected<MediaError>(
      MediaError::kMediaErrAborted, "Load was aborted"));

  // 3 - Queue a task to fire a simple event named abort at the media element.
  element.ScheduleNamedEvent(event_type_names::kAbort);

  // 4 - If readyState is HAVE_NOTHING, set networkState to NETWORK_EMPTY, set
  // the show poster flag to true and fire emptied; otherwise set networkState
  // to NETWORK_IDLE.
  if (had_nothing) {
    element.SetNetworkState(HTMLMediaElement::kNetworkEmpty);
    element.SetShowPosterFlag(true);
    element.ScheduleNamedEvent(event_type_names::kEmptied);
  } else {
    element.SetNetworkState(HTMLMediaElement::kNetworkIdle);
  }

  // 5 - Set the element's delaying-the-load-event flag to false.
  element.SetShouldDelayLoadEvent(false);

  // 6 - Abort the overall resource selection algorithm.
  element.current_source_node_ = nullptr;

  element.UpdatePlayState();
  element.UpdateLayoutObject();
}

bool ParcMediaElement::WaitForKey() {
  if (!PresentsParcSafariIdentity()) {
    return false;
  }
  if (playback_blocked_waiting_for_key_) {
    return true;
  }
  HTMLMediaElement& element = Media();
  playback_blocked_waiting_for_key_ = true;
  player_ready_state_ = element.web_media_player_
                            ? static_cast<HTMLMediaElement::ReadyState>(
                                  element.web_media_player_->GetReadyState())
                            : element.ready_state_;
  const HTMLMediaElement::ReadyState next_state =
      element.buffered()->Contain(element.currentTime())
          ? HTMLMediaElement::kHaveCurrentData
          : HTMLMediaElement::kHaveMetadata;
  if (next_state < element.ready_state_) {
    element.SetReadyState(next_state);
  }
  element.ScheduleNamedEvent(event_type_names::kWaitingforkey);
  return true;
}

bool ParcMediaElement::StopWaitingForKey() {
  if (!PresentsParcSafariIdentity()) {
    return false;
  }
  if (!playback_blocked_waiting_for_key_) {
    return true;
  }
  playback_blocked_waiting_for_key_ = false;
  HTMLMediaElement& element = Media();
  if (element.web_media_player_) {
    element.SetReadyState(static_cast<HTMLMediaElement::ReadyState>(
        element.web_media_player_->GetReadyState()));
  }
  return true;
}

// WebKit's HTMLMediaElement::seekWithTolerance: seeking and the target
// (clamped to the duration) show at once; a page's seek continues in a queued
// task, which a further seek before it runs replaces, keeping the position
// the first started from. Seeks of the element's own run it at once
// (seekInternal).
void ParcMediaElement::Seek(double time) {
  HTMLMediaElement& element = Media();
  // If the player has been told to postpone loading data, let it go ahead:
  // a seek before there is future data, at a preload attribute below auto,
  // prepares to play.
  if (element.PreloadType() != WebMediaPlayer::kPreloadAuto &&
      !HasFutureDataAsWebKit(element.ready_state_)) {
    PrepareToPlay();
  }

  double now = element.currentTime();
  if (seek_task_.IsActive()) {
    seek_task_.Cancel();
    now = pending_seek_->now;
    fast_seek_with_player_ = false;
  }

  element.SetSeeking(true);
  if (element.playing_ && element.last_seek_time_ < now) {
    element.AddPlayedRange(element.last_seek_time_, now);
  }
  element.last_seek_time_ = std::min(time, element.duration());

  pending_seek_ = PendingSeek{now, time, fast_seek_tolerance_.value_or(0)};
  if (seek_from_page_) {
    PostSeekTask();
  } else {
    SeekTask();
  }
}

void ParcMediaElement::PostSeekTask() {
  seek_task_ = PostCancellableTask(
      *Media().GetDocument().GetTaskRunner(TaskType::kMediaElementEvent),
      FROM_HERE,
      BindOnce(&ParcMediaElement::SeekTask, WrapWeakPersistent(this)));
}

// WebKit's HTMLMediaElement::seekTask.
void ParcMediaElement::SeekTask() {
  HTMLMediaElement& element = Media();
  const PendingSeek seek = *pending_seek_;
  pending_seek_.reset();
  if (!element.web_media_player_ ||
      element.ready_state_ == HTMLMediaElement::kHaveNothing) {
    ClearSeeking();
    return;
  }

  // The player's start time is zero in WebKit on macOS.
  double time = std::max(std::min(seek.time, element.duration()), 0.0);
  time = element.web_media_player_->MediaTimeForTimeValue(time);

  // A precise seek to the current position needs no seek of the player,
  // unless a fast seek is still with it or an open Media Source must flush.
  WebTimeRanges seekable_ranges = element.SeekableInternal();
  const bool precise = !seek.tolerance_before;
  bool no_seek_required =
      seekable_ranges.empty() ||
      (time == seek.now && precise && !fast_seek_with_player_ &&
       !element.show_poster_flag_);
  if (element.media_source_attachment_ && !seekable_ranges.empty()) {
    no_seek_required = false;
  }
  if (no_seek_required) {
    // WebKit returns before touching m_sentEndEvent, even at rate zero.
    if (time == seek.now) {
      element.ScheduleNamedEvent(event_type_names::kSeeking);
      element.ScheduleTimeupdateEvent(false);
      element.ScheduleNamedEvent(event_type_names::kSeeked);
    }
    ClearSeeking();
    return;
  }
  // PlatformTimeRanges::nearest: a tie goes to the earliest range.
  time =
      seekable_ranges.Nearest(time, -std::numeric_limits<double>::infinity());

  element.last_seek_time_ = time;
  // A seek landing on the end leaves playback ended (endedPlayback, either
  // direction), so `ended` doesn't fire again.
  const bool lands_ended = element.playbackRate() > 0
                               ? element.duration() > 0 &&
                                     time >= element.duration() &&
                                     !element.Loop()
                               : element.playbackRate() < 0 && time <= 0;
  if (!lands_ended) {
    sent_end_event_ = false;
  }
  seek_with_player_ = true;
  fast_seek_with_player_ = !precise;
  player_finished_seek_ = false;
  element.SetSeeking(true);
  element.ScheduleNamedEvent(event_type_names::kSeeking);

  ParcWebMediaPlayerExtension* parc =
      element.web_media_player_->GetParcExtension();
  if (precise || !parc) {
    element.web_media_player_->Seek(time);
  } else {
    parc->ParcFastSeek(time, seek.tolerance_before);
  }
  element.web_media_player_->OnTimeUpdate();
}

void ParcMediaElement::ClearSeeking() {
  Media().SetSeeking(false);
  ResetSeekState();
}

void ParcMediaElement::ResetSeekState() {
  seek_with_player_ = false;
  fast_seek_with_player_ = false;
  was_playing_before_seeking_ = false;
  player_finished_seek_ = false;
}

// Only the player finishes a seek; one still in its task hasn't reached it.
// An earlier seek with the player still finishes, as WebKit's seek promise.
bool ParcMediaElement::SeekAwaitsTask() const {
  return seek_task_.IsActive() && !seek_with_player_;
}

void ParcMediaElement::CancelPendingSeek() {
  seek_task_.Cancel();
  pending_seek_.reset();
}

void ParcMediaElement::ScheduleNotifyPlayingAfterSeek() {
  if (Media().seeking_ && PresentsParcSafariIdentity()) {
    pending_notify_playing_ = true;
    return;
  }
  Media().ScheduleNotifyPlaying();
}

void ParcMediaElement::SetCurrentTimeForBindings(
    double time,
    ExceptionState& exception_state) {
  if (PresentsParcSafariIdentity()) {
    // WebKit's setCurrentTimeForBindings clamps to [0, DBL_MAX]: +Infinity
    // (`currentTime = duration` on a live stream) seeks to the end of the
    // seekable range, the live edge, and -Infinity to 0. A NaN seek lands
    // on time 0 in WebKit (its nearest seekable point of an invalid time).
    time = std::isnan(time)
               ? 0
               : std::clamp(time, 0.0, std::numeric_limits<double>::max());
    base::AutoReset<bool> from_page(&seek_from_page_, true);
    Media().setCurrentTime(time);
    return;
  } else if (!std::isfinite(time)) {
    // What the bindings say for a restricted double.
    exception_state.ThrowTypeError("The provided double value is non-finite.");
    return;
  }
  Media().setCurrentTime(time);
}

// WebKit's HTMLMediaElement::fastSeek: a seek that may land early, at a
// keyframe the player can start from promptly. Forward it lands no earlier
// than the current position, backward anywhere before the target, never
// after the target (seekWithTolerance with a negative threshold of the
// distance, or infinite going back, and no positive one). Before metadata it
// does nothing. Non-finite times are taken as currentTime takes them here.
void ParcMediaElement::FastSeek(double time) {
  time = std::isnan(time)
             ? 0
             : std::clamp(time, 0.0, std::numeric_limits<double>::max());
  const double delta = time - Media().currentTime();
  fast_seek_tolerance_ =
      delta < 0 ? std::numeric_limits<double>::infinity() : delta;
  base::AutoReset<bool> from_page(&seek_from_page_, true);
  Media().Seek(time);
  fast_seek_tolerance_.reset();
}

ScriptObject ParcMediaElement::GetStartDate(ScriptState* script_state) const {
  // WebKit: NaN without a player, otherwise the player's start date; a Date
  // either way (an Invalid Date for NaN).
  ParcWebMediaPlayerExtension* parc =
      ParcExtension(Media().web_media_player_.get());
  double date =
      parc ? parc->ParcStartDate() : std::numeric_limits<double>::quiet_NaN();
  return ScriptObject(
      script_state->GetIsolate(),
      v8::Date::New(script_state->GetContext(), date).ToLocalChecked());
}

double ParcMediaElement::PlayerPlaybackRate() const {
  // WebKit passes the exact rate to the player (setPlaybackRate). Negative
  // Media Source rates stop its sample-buffer renderer; URL players decide
  // whether their backend supports reverse playback.
  HTMLMediaElement& element = Media();
  if (PresentsParcSafariIdentity()) {
    return element.GetLoadType() == WebMediaPlayer::kLoadTypeMediaSource
               ? std::max(0.0, element.playbackRate())
               : element.playbackRate();
  }
  return element.playbackRate();
}

void ParcMediaElement::ScheduleTimeupdateEvent(bool periodic_event) {
  HTMLMediaElement& element = Media();
  const base::TimeTicks now = base::TimeTicks::Now();
  const base::TimeDelta since_last = now - last_timeupdate_clock_;
  if (periodic_event && since_last < kWebKitMaxTimeupdateEventFrequency) {
    // Fire when the interval is up, then repeat from there.
    element.playback_progress_timer_.Stop();
    element.playback_progress_timer_.StartOneShot(
        kWebKitMaxTimeupdateEventFrequency - since_last);
    progress_timer_resumes_repeating_ = true;
    return;
  }

  const double media_time = element.CurrentPlaybackPosition();
  if (media_time == element.last_time_update_event_media_time_) {
    return;
  }
  Event* event = Event::CreateCancelable(event_type_names::kTimeupdate);
  event->SetTarget(&element);
  element.ScheduleEvent(event);
  if (periodic_event) {
    periodic_timeupdate_ = event;
  }
  last_timeupdate_clock_ = now;
  element.last_time_update_event_media_time_ = media_time;
}

void ParcMediaElement::ScheduleUnconditionalTimeupdateEvent() {
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity()) {
    element.ScheduleTimeupdateEvent(false);
    return;
  }
  if (element.web_media_player_) {
    element.web_media_player_->OnTimeUpdate();
  }
  element.ScheduleNamedEvent(event_type_names::kTimeupdate);
}

void ParcMediaElement::CancelPeriodicTimeupdate() {
  if (periodic_timeupdate_) {
    Media().async_event_queue_->CancelEvent(*periodic_timeupdate_);
    periodic_timeupdate_ = nullptr;
  }
}

void ParcMediaElement::ResumeRepeatingProgressTimer() {
  if (progress_timer_resumes_repeating_) {
    progress_timer_resumes_repeating_ = false;
    Media().playback_progress_timer_.Stop();
    Media().playback_progress_timer_.StartRepeating(
        kWebKitMaxTimeupdateEventFrequency);
  }
}

void ParcMediaElement::ScheduleCueTimeupdate() {
  if (!PresentsParcSafariIdentity() || Media().seeking_) {
    return;
  }
  // WebKit's finishSeek runs the cue update in a task after its timeupdate
  // and seeked.
  if (finishing_seek_) {
    cue_timeupdate_after_seek_ = true;
    return;
  }
  Media().ScheduleTimeupdateEvent(true);
}

// WebKit's mediaPlayerTimeChanged for a time the player reports outside a
// seek; the end comes through TimeChanged().
void ParcMediaElement::ParcPlayerTimeChanged() {
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity() || !element.web_media_player_ ||
      element.seeking_) {
    return;
  }
  if (!element.IsShowPosterFlagSet()) {
    element.GetCueTimeline().InvokeTimeMarchesOn();
  }
  element.SetOfficialPlaybackPosition(element.CurrentPlaybackPosition());
  element.ScheduleTimeupdateEvent(false);
}

void ParcMediaElement::ParcPlaybackTargetIsWirelessChanged(bool wireless) {
  ParcMediaElementAirPlay::From(Media()).PlaybackTargetIsWirelessChanged(
      wireless);
}

void ParcMediaElement::ParcReportMediaMetadata(
    bool has_audio,
    bool has_video,
    media::MediaContentType media_content_type) {
  for (auto& observer : Media().media_player_observer_remote_set_->Value()) {
    observer->OnMediaMetadataChanged(has_audio, has_video, media_content_type);
  }
}

void ParcMediaElement::ParcWebKitMediaSourceKeyNeeded(
    base::span<const uint8_t> sinf) {
  ScheduleParcWebKitNeedKey(Media(), sinf, "media-source");
}

void ParcMediaElement::ParcWebKitKeyRequest(std::string_view key_uri) {
  ScheduleParcWebKitKeyRequest(Media(), key_uri);
}

void ParcMediaElement::ParcSetInbandTextTracks(
    const std::vector<media::ParcInbandTextTrack>& tracks,
    media::ParcInbandTextTrackModeCB set_mode) {
  // Only Safari's native HLS route reports in-band text tracks, and it plays
  // only under Safari's identity.
  if (!PresentsParcSafariIdentity()) {
    return;
  }
  HTMLMediaElement& element = Media();
  TextTrackList* list = element.textTracks();
  HeapVector<Member<TextTrack>> current(list->InbandTracks());
  for (const auto& track : current) {
    auto* inband = To<ParcInbandTextTrack>(track.Get());
    bool listed = false;
    for (const media::ParcInbandTextTrack& info : tracks) {
      listed = listed || info.key == inband->Key();
    }
    if (!listed) {
      RemoveInbandTextTrack(inband);
    }
  }
  bool added = false;
  for (const media::ParcInbandTextTrack& info : tracks) {
    if (ParcInbandTextTrack* existing = FindInbandTextTrack(info.key)) {
      existing->Update(info);
      existing->SetModeCallback(set_mode);
      continue;
    }
    // As WebKit's HTMLMediaElement::addTextTrack for an in-band track: listed
    // disabled, then automatic selection decides its mode.
    list->Append(
        MakeGarbageCollected<ParcInbandTextTrack>(info, element, set_mode));
    added = true;
  }
  if (added) {
    element.ScheduleAutomaticTextTrackSelection();
  }
}

void ParcMediaElement::ParcSetInbandAudioTracks(
    const std::vector<media::ParcInbandAudioTrack>& tracks,
    media::ParcInbandAudioTrackEnabledCB set_enabled) {
  // Only Safari's native HLS route reports these, under Safari's identity.
  if (!PresentsParcSafariIdentity()) {
    return;
  }
  HTMLMediaElement& element = Media();
  set_inband_audio_track_enabled_ = std::move(set_enabled);
  if (!reports_inband_audio_tracks_) {
    // A placeholder made before the player's first list goes.
    reports_inband_audio_tracks_ = true;
    HeapVector<Member<AudioTrack>> others;
    for (unsigned i = 0; i < element.audioTracks().length(); ++i) {
      AudioTrack* track = element.audioTracks().AnonymousIndexedGetter(i);
      if (!InbandAudioTrackKey(track)) {
        others.push_back(track);
      }
    }
    for (const auto& track : others) {
      element.audioTracks().RemoveTrack(track.Get());
    }
  }
  Vector<String> gone;
  for (const auto& entry : inband_audio_tracks_) {
    bool listed = false;
    for (const media::ParcInbandAudioTrack& info : tracks) {
      listed = listed || String::FromUtf8(info.key) == entry.key;
    }
    if (!listed) {
      gone.push_back(entry.key);
    }
  }
  for (const String& key : gone) {
    element.audioTracks().RemoveTrack(inband_audio_tracks_.Take(key).Get());
  }
  for (const media::ParcInbandAudioTrack& info : tracks) {
    const String key = String::FromUtf8(info.key);
    auto it = inband_audio_tracks_.find(key);
    if (it != inband_audio_tracks_.end()) {
      // WebKit's AudioTrack follows its private track's enabled state.
      it->value->setEnabled(info.enabled, TrackBase::ChangeSource::kDemuxer);
      continue;
    }
    // Not exclusive: as in WebKit, enabling one leaves the others enabled
    // until the player reports its selection.
    auto* track = MakeGarbageCollected<AudioTrack>(
        String::FromUtf8(info.id), AtomicString(String::FromUtf8(info.kind)),
        AtomicString(String::FromUtf8(info.label)),
        AtomicString(String::FromUtf8(info.language)), info.enabled,
        /*exclusive=*/false, /*webkit_kinds=*/true);
    inband_audio_tracks_.Set(key, track);
    element.audioTracks().Add(track);
  }
}

const String* ParcMediaElement::InbandAudioTrackKey(AudioTrack* track) const {
  for (const auto& entry : inband_audio_tracks_) {
    if (entry.value == track) {
      return &entry.key;
    }
  }
  return nullptr;
}

void ParcMediaElement::ParcAddInbandTextCues(
    const std::string& key,
    const std::vector<media::ParcInbandTextCue>& cues) {
  if (ParcInbandTextTrack* track = FindInbandTextTrack(key)) {
    track->AddCues(cues);
  }
}

void ParcMediaElement::ParcAddInbandDataCues(
    const std::string& key,
    const std::vector<media::ParcInbandDataCue>& cues) {
  if (ParcInbandTextTrack* track = FindInbandTextTrack(key)) {
    track->AddDataCues(cues);
  }
}

ParcInbandTextTrack* ParcMediaElement::FindInbandTextTrack(
    const std::string& key) {
  HTMLMediaElement& element = Media();
  if (!element.text_tracks_) {
    return nullptr;
  }
  for (const auto& track : element.text_tracks_->InbandTracks()) {
    auto* inband = To<ParcInbandTextTrack>(track.Get());
    if (inband->Key() == key) {
      return inband;
    }
  }
  return nullptr;
}

void ParcMediaElement::RemoveInbandTextTrack(ParcInbandTextTrack* track) {
  // As DidRemoveTrackElement; the track's cues leave the timeline with it.
  HTMLMediaElement& element = Media();
  element.GetDocument().GetStyleEngine().RemoveTextTrack(track);
  element.text_tracks_->Remove(track);
  wtf_size_t index =
      element.text_tracks_when_resource_selection_began_.Find(track);
  if (index != kNotFound) {
    element.text_tracks_when_resource_selection_began_.EraseAt(index);
  }
}

void ParcMediaElement::ForgetResourceSpecificTracks() {
  inband_audio_tracks_.clear();
  set_inband_audio_track_enabled_.Reset();
  reports_inband_audio_tracks_ = false;
  // And the native HLS route's in-band text tracks, as WebKit's
  // forgetResourceSpecificTracks.
  HTMLMediaElement& element = Media();
  if (element.text_tracks_) {
    HeapVector<Member<TextTrack>> inband(element.text_tracks_->InbandTracks());
    for (const auto& track : inband) {
      RemoveInbandTextTrack(To<ParcInbandTextTrack>(track.Get()));
    }
  }
}

// WebKit's HTMLMediaElement::handleSeekToPlaybackPosition on macOS: a seek
// from the system's media controls runs as a page's, and the first of a scrub
// pauses playing media until a seek finishes (finishSeek).
void ParcMediaElement::HandleSeekToPlaybackPosition(double position) {
  HTMLMediaElement& element = Media();
  {
    base::AutoReset<bool> from_page(&seek_from_page_, true);
    element.Seek(position);
  }
  element.ReportCurrentTimeToMediaSource();
  remote_scrub_end_timer_.StartOneShot(base::Milliseconds(500), FROM_HERE);

  if (!scrubbing_remotely_) {
    scrubbing_remotely_ = true;
    was_playing_before_seeking_ = !element.paused_;
    if (was_playing_before_seeking_) {
      element.PauseInternal(WebMediaPlayer::PauseReason::kPauseRequestedByUser);
    }
  }
}

// WebKit's seekToPlaybackPositionEndedTimerFired.
void ParcMediaElement::RemoteScrubEndTimerFired(TimerBase*) {
  scrubbing_remotely_ = false;
}

// WebKit PlaybackSessionModelMediaElement forwards playback controls to
// beginScrubbing/endScrubbing and setCurrentTimeWithTolerance, not remote
// seeks.
void ParcMediaElement::HandlePlaybackControlsAction(
    media_session::mojom::blink::PlaybackControlsAction action,
    base::TimeDelta seek_time) {
  using Action = media_session::mojom::blink::PlaybackControlsAction;
  HTMLMediaElement& element = Media();
  if (!PresentsParcSafariIdentity()) {
    switch (action) {
      case Action::kSeekTo:
        element.RequestSeekTo(seek_time);
        break;
      case Action::kPauseForDragging:
        element.RequestPause(true);
        break;
      case Action::kResumeForDragging:
        element.RequestPlay(true);
        break;
      case Action::kBeginScrubbing:
      case Action::kEndScrubbing:
        break;
    }
    return;
  }
  switch (action) {
    case Action::kSeekTo:
      element.setCurrentTime(seek_time.InSecondsF());
      break;
    case Action::kBeginScrubbing:
    case Action::kPauseForDragging:
      if (scrubbing_playback_controls_) {
        return;
      }
      if (!element.paused_) {
        if (element.EndedPlayback()) {
          element.pause();
        } else {
          scrubbing_playback_controls_ = true;
        }
      }
      element.UpdatePlayState(
          WebMediaPlayer::PauseReason::kPauseRequestedInternally);
      break;
    case Action::kEndScrubbing:
    case Action::kResumeForDragging:
      scrubbing_playback_controls_ = false;
      element.UpdatePlayState();
      break;
  }
}

void ParcMediaElement::StopScrubbing() {
  scrubbing_playback_controls_ = false;
  remote_scrub_end_timer_.Stop();
  scrubbing_remotely_ = false;
  was_playing_before_seeking_ = false;
}

// WebKit's suspend() stops playback only for the back/forward cache, without
// events and keeping its player and position
// (stopWithoutDestroyingMediaPlayer), and resume() plays on
// (setPausedInternal(false)); it leaves media alone for other suspensions.
bool ParcMediaElement::ContextLifecycleStateChanged(
    mojom::blink::FrameLifecycleState state) {
  HTMLMediaElement& element = Media();
  if (paused_for_back_forward_cache_) {
    if (state == mojom::blink::FrameLifecycleState::kRunning) {
      if (!page_observer_) {
        page_observer_ = MakeGarbageCollected<PageObserver>(this);
      }
      page_observer_->Observe(element.GetDocument().GetPage());
      ResumeAfterBackForwardCacheIfAllowed();
    }
    return true;
  }
  if (state == mojom::blink::FrameLifecycleState::kFrozen &&
      PresentsParcSafariIdentity()) {
    ExecutionContext* context = element.GetExecutionContext();
    if (context && context->is_in_back_forward_cache()) {
      paused_for_back_forward_cache_ = true;
      element.UpdatePlayState(WebMediaPlayer::PauseReason::kFrameFrozen);
      if (auto* parc = ParcExtension(element.web_media_player_.get())) {
        parc->ParcOnFrozenInBackForwardCache();
      }
    }
    return true;
  }
  return false;
}

void ParcMediaElement::ResumeAfterBackForwardCacheIfAllowed() {
  // WebKit's resume() plays on only once its page can start media
  // (MediaElementSession::pageAllowsPlaybackAfterResuming), which WebKit
  // allows while the page's view is in a window (WebPage::updateIsInWindow);
  // otherwise it waits for that (mediaCanStart). Visibility cannot distinguish
  // a background tab from a minimised or covered active tab.
  HTMLMediaElement& element = Media();
  ExecutionContext* context = element.GetExecutionContext();
  if (!paused_for_back_forward_cache_ || !context ||
      context->ContextPauseState() !=
          mojom::blink::FrameLifecycleState::kRunning ||
      !element.GetDocument().GetPage() ||
      !ParcPageMediaState::From(*element.GetDocument().GetPage()).InWindow()) {
    return;
  }
  paused_for_back_forward_cache_ = false;
  element.UpdatePlayState();
}

void ParcMediaElement::UpdatePlayerPageVisibility() {
  // WebKit's element tells its player its own document's visibility
  // (visibilityStateChanged) wherever it moved. A player kept across documents
  // (DidMoveToNewDocument) belongs to the frame that made it, whose page can be
  // another one. Hidden but painting counts as visible, as for that frame's
  // page (RendererWebMediaPlayerDelegate::IsPageHidden).
  HTMLMediaElement& element = Media();
  if (!element.web_media_player_ || !PresentsParcSafariIdentity()) {
    return;
  }
  Page* page = element.GetDocument().GetPage();
  LocalFrame* player_frame = element.LocalFrameForPlayer();
  std::optional<bool> is_page_hidden;
  if (page && player_frame && player_frame->GetPage() != page) {
    is_page_hidden = page->GetVisibilityState() ==
                     mojom::blink::PageVisibilityState::kHidden;
  }
  if (is_page_hidden.has_value() || page_observer_) {
    if (!page_observer_) {
      page_observer_ = MakeGarbageCollected<PageObserver>(this);
    }
    page_observer_->Observe(page);
  }
  if (auto* parc = element.web_media_player_->GetParcExtension()) {
    parc->ParcSetPageHidden(is_page_hidden);
  }
}

Document* ParcMediaElement::ContextDocument(Document& document) {
  if (document.GetFrame()) {
    return &document;
  }
  auto* window = DynamicTo<LocalDOMWindow>(document.GetExecutionContext());
  return window && window->GetFrame() ? window->document() : nullptr;
}

bool ParcMediaElement::KeepsPlayerAcrossDocuments(Document& old_document,
                                                  Document& new_document) {
  Document* old_context = ContextDocument(old_document);
  Document* new_context = ContextDocument(new_document);
  if (!old_context || !new_context) {
    return false;
  }
  LocalDOMWindow* old_window = old_context->domWindow();
  LocalDOMWindow* new_window = new_context->domWindow();
  return IsParcSafariIdentityUserAgent(old_window->UserAgent()) &&
         IsParcSafariIdentityUserAgent(new_window->UserAgent()) &&
         old_window->GetSecurityOrigin()->IsSameOriginWith(
             new_window->GetSecurityOrigin());
}

bool ParcMediaElement::IsPictureInPictureElementOf(Document* document) const {
  PictureInPictureController* controller =
      document
          ? Supplement<Document>::From<PictureInPictureController>(*document)
          : nullptr;
  return controller && controller->PictureInPictureElement() == &Media();
}

// As WebKit's player, which follows the element on the move: the picture in
// picture that held this one back is over, or went with the old document.
void ParcMediaElement::PictureInPictureEnded() {
  if (player_waits_for_picture_in_picture_end_ && Media().web_media_player_) {
    MovePlayerToFrame();
  }
}

void ParcMediaElement::OpenerContextDestroyed() {
  HTMLMediaElement& element = Media();
  // A notifier that went can't be asked to stop (AttachToNewFrame()).
  element.opener_context_observer_ = nullptr;
  if (player_waits_for_picture_in_picture_end_ && element.web_media_player_) {
    // Picture in picture ended with the document it was entered from, which
    // can't say so (PictureInPictureControllerImpl's document is gone). A
    // video also hides the interstitial picture in picture left behind, then
    // ends it as its own exit does.
    if (auto* video = DynamicTo<HTMLVideoElement>(element)) {
      video->OnExitedPictureInPicture();
    } else {
      PictureInPictureEnded();
    }
    // Moved (MovePlayerToFrame()).
    if (!element.opener_document_) {
      return;
    }
  }
  element.AttachToNewFrame();
}

// As WebKit's player belongs to its element wherever it is, which registers
// with its new document (HTMLMediaElement::didMoveToNewDocument and
// registerWithDocument): the player keeps playing when the frame that made it
// goes, the new frame's browser side shows and mutes its sound in that frame's
// tab, and Now Playing, the media keys and picture in picture reach it there.
// Closing the mojo endpoints of the old frame ends the player there.
bool ParcMediaElement::MovePlayerToFrame() {
  HTMLMediaElement& element = Media();
  player_waits_for_picture_in_picture_end_ = false;
  if (!element.GetDocument().GetFrame() || !g_parc_move_web_media_player ||
      !g_parc_move_web_media_player(element)) {
    return false;
  }
  element.ResetMojoState();
  element.RegisterWithMediaPlayerHost();
  if (auto* parc = element.web_media_player_->GetParcExtension()) {
    parc->ParcReportStateToClient();
  }
  element.OnRemotePlaybackMetadataChange();
  // What the video tells its new frame's browser side itself.
  if (auto* video = DynamicTo<HTMLVideoElement>(element)) {
    video->UpdatePictureInPictureAvailability();
    video->last_reported_video_frame_availability_ = false;
    video->UpdateVideoFrameAvailability();
  }
  if (element.remote_playback_client_) {
    element.remote_playback_client_->ParcDidMoveToDocument();
  }

  if (element.opener_context_observer_) {
    element.opener_context_observer_->SetContextLifecycleNotifier(nullptr);
  }
  element.opener_context_observer_ = nullptr;
  element.opener_document_ = nullptr;
  return true;
}

SkBitmap ParcMediaElement::PaintTextTracksForPictureInPicture(
    const gfx::SizeF& window_size,
    float device_scale_factor,
    gfx::RectF& bounds) {
  HTMLMediaElement& element = Media();
  if (!element.IsHTMLVideoElement() || !element.TextTracksVisible()) {
    return SkBitmap();
  }
  return element.EnsureTextTrackContainer().PaintForPictureInPicture(
      window_size, device_scale_factor, bounds);
}

ParcMediaElement::PageObserver::PageObserver(ParcMediaElement* parc)
    : PageVisibilityObserver(nullptr), parc_(parc) {}

void ParcMediaElement::PageObserver::Observe(Page* page) {
  if (page == GetPage()) {
    return;
  }
  if (GetPage()) {
    ParcPageMediaState::From(*GetPage()).RemoveInWindowObserver(this);
  }
  SetPage(page);
  if (page) {
    ParcPageMediaState::From(*page).AddInWindowObserver(this);
  }
}

void ParcMediaElement::PageObserver::Trace(Visitor* visitor) const {
  PageVisibilityObserver::Trace(visitor);
  visitor->Trace(parc_);
}

void ParcMediaElement::PageObserver::PageInWindowChanged(Page& page) {
  // A destroyed page ends observation without leaving `page`'s list; only the
  // page still observed counts, as with Page's own observer list.
  if (GetPage() != &page) {
    return;
  }
  parc_->ResumeAfterBackForwardCacheIfAllowed();
}

void ParcMediaElement::PageObserver::PageVisibilityChanged() {
  // Page::SetVisibilityState iterates its observers, so this must not change
  // which page is observed.
  if (GetPage() == parc_->Media().GetDocument().GetPage()) {
    parc_->UpdatePlayerPageVisibility();
  }
  parc_->ResumeAfterBackForwardCacheIfAllowed();
}

}  // namespace blink

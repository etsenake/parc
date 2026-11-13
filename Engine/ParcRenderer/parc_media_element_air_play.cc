// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"

#include <iterator>
#include <tuple>
#include <utility>

#include "base/time/time.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/public/platform/web_media_source.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_event.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_script_runner.h"
#include "third_party/blink/renderer/core/dom/element_traversal.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/visual_viewport.h"
#include "third_party/blink/renderer/core/html/html_source_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/media_controls.h"
#include "third_party/blink/renderer/core/html/media/media_remoting_interstitial.h"
#include "third_party/blink/renderer/core/html/media/media_source_attachment.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_names.h"
#include "third_party/blink/renderer/core/html/media/parc_remote_playback_extension.h"
#include "third_party/blink/renderer/core/html/media/picture_in_picture_interstitial.h"
#include "third_party/blink/renderer/core/html/media/remote_playback_controller.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/core/input/event_handler.h"
#include "third_party/blink/renderer/core/page/page.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/widget/frame_widget.h"
#include "third_party/blink/renderer/platform/wtf/casting.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/text/strcat.h"
#include "ui/gfx/geometry/point_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size_f.h"

namespace blink {

namespace {

ParcWebMediaPlayerExtension* ParcExtension(WebMediaPlayer* player) {
  return player ? player->GetParcExtension() : nullptr;
}

bool ParcPlayerSupportsPlaybackTarget(WebMediaPlayer* player) {
  ParcWebMediaPlayerExtension* parc = ParcExtension(player);
  return parc && parc->ParcSupportsPlaybackTarget();
}

v8::Local<v8::Private> ParcPlaybackTargetEventHookKey(v8::Isolate* isolate) {
  return v8::Private::ForApi(
      isolate, V8AtomicString(isolate, "Parc::WebKitPlaybackTargetEvent"));
}

Event* CreateParcPlaybackTargetAvailabilityEvent(LocalDOMWindow& window,
                                                 bool available) {
  if (window.IsContextDestroyed() || !window.GetFrame()) {
    return nullptr;
  }
  ScriptState* script_state = ToScriptStateForMainWorld(window.GetFrame());
  if (!script_state || !script_state->ContextIsValid()) {
    return nullptr;
  }
  ScriptState::Scope scope(script_state);
  v8::Isolate* isolate = script_state->GetIsolate();
  v8::Local<v8::Context> context = script_state->GetContext();
  v8::Local<v8::Value> hook;
  if (!context->Global()
           ->GetPrivate(context, ParcPlaybackTargetEventHookKey(isolate))
           .ToLocal(&hook) ||
      !hook->IsFunction()) {
    return nullptr;
  }
  v8::TryCatch try_catch(isolate);
  v8::Local<v8::Value> argv[] = {v8::Boolean::New(isolate, available)};
  v8::Local<v8::Value> event;
  if (!V8ScriptRunner::CallFunction(hook.As<v8::Function>(), &window,
                                    v8::Undefined(isolate), std::size(argv),
                                    argv, isolate)
           .ToLocal(&event)) {
    return nullptr;
  }
  Event* result = V8Event::ToWrappable(isolate, event);
  return result && result->type() ==
                       parc_media_element_names::
                           Webkitplaybacktargetavailabilitychanged()
             ? result
             : nullptr;
}

}

const char ParcMediaElementAirPlay::kSupplementName[] =
    "ParcMediaElementAirPlay";

void ParcMediaElementAirPlay::ProvideTo(HTMLMediaElement& element) {
  Supplement<HTMLMediaElement>::ProvideTo(
      element, MakeGarbageCollected<ParcMediaElementAirPlay>(element));
}

ParcMediaElementAirPlay& ParcMediaElementAirPlay::From(
    const HTMLMediaElement& element) {
  return *Supplement<HTMLMediaElement>::From<ParcMediaElementAirPlay>(element);
}

ParcMediaElementAirPlay::ParcMediaElementAirPlay(HTMLMediaElement& element)
    : Supplement<HTMLMediaElement>(element),
      check_playback_target_compatibility_timer_(
          element.GetDocument().GetTaskRunner(TaskType::kInternalMedia),
          this,
          &ParcMediaElementAirPlay::CheckPlaybackTargetCompatibility) {}

ParcMediaElementAirPlay::~ParcMediaElementAirPlay() = default;

void ParcMediaElementAirPlay::Trace(Visitor* visitor) const {
  visitor->Trace(check_playback_target_compatibility_timer_);
  Supplement<HTMLMediaElement>::Trace(visitor);
}

void ParcMediaElementAirPlay::MoveTimerToNewTaskRunner() {
  check_playback_target_compatibility_timer_.MoveToNewTaskRunner(
      Media().GetDocument().GetTaskRunner(TaskType::kInternalMedia));
}

bool ParcMediaElementAirPlay::WirelessPlaybackTargetDisabled() const {
  HTMLMediaElement& element = Media();
  return EqualIgnoringAsciiCase(
             element.FastGetAttribute(
                 parc_media_element_names::XWebkitAirplayAttr()),
             "deny") ||
         element.FastHasAttribute(
             parc_media_element_names::
                 WebkitwirelessvideoplaybackdisabledAttr()) ||
         element.FastHasAttribute(html_names::kDisableremoteplaybackAttr);
}

void ParcMediaElementAirPlay::SetPlaybackTargetEventHook(
    ScriptState* script_state,
    v8::Local<v8::Value> hook) {
  if (hook.IsEmpty() || !hook->IsFunction()) {
    return;
  }
  v8::Local<v8::Context> context = script_state->GetContext();
  std::ignore = context->Global()->SetPrivate(
      context, ParcPlaybackTargetEventHookKey(script_state->GetIsolate()),
      hook);
}

bool ParcMediaElementAirPlay::HasPlaybackTargetAvailabilityListeners() const {
  return Media().HasEventListeners(
      parc_media_element_names::Webkitplaybacktargetavailabilitychanged());
}

void ParcMediaElementAirPlay::WirelessPlaybackTargetDisabledChanged() {
  HTMLMediaElement& element = Media();
  if (!element.PresentsParcSafariIdentity()) {
    return;
  }
  OpenIfDeferredOpen();
  const bool disabled = WirelessPlaybackTargetDisabled();
  if (disabled == wireless_playback_target_disabled_) {
    return;
  }
  wireless_playback_target_disabled_ = disabled;
  if (HasPlaybackTargetAvailabilityListeners() &&
      (!disabled || last_availability_event_)) {
    EnqueuePlaybackTargetAvailabilityEvent(false);
  }
  if (auto* parc = ParcExtension(element.web_media_player_.get())) {
    parc->ParcSetWirelessVideoPlaybackDisabled(disabled);
  }
  ReportPlaybackTargetState();
  RemoteAvailabilityChanged();
}

void ParcMediaElementAirPlay::EnqueuePlaybackTargetAvailabilityEvent(
    bool only_when_changed) {
  const bool has_targets =
      !wireless_playback_target_disabled_ && has_playback_targets_;
  if (only_when_changed && has_targets == last_availability_event_) {
    return;
  }
  last_availability_event_ = has_targets;
  HTMLMediaElement& element = Media();
  auto* window = DynamicTo<LocalDOMWindow>(element.GetExecutionContext());
  if (Event* event = window ? CreateParcPlaybackTargetAvailabilityEvent(
                                  *window, has_targets)
                            : nullptr) {
    event->SetTarget(&element);
    element.ScheduleEvent(event);
  }
}

void ParcMediaElementAirPlay::EventListenerAdded(
    const AtomicString& event_type) {
  if (event_type !=
          parc_media_element_names::Webkitplaybacktargetavailabilitychanged() ||
      !Media().PresentsParcSafariIdentity() ||
      wireless_playback_target_disabled_) {
    return;
  }
  ReportPlaybackTargetState();
  EnqueuePlaybackTargetAvailabilityEvent(false);
}

void ParcMediaElementAirPlay::EventListenerRemoved(
    const AtomicString& event_type) {
  if (event_type ==
          parc_media_element_names::Webkitplaybacktargetavailabilitychanged() &&
      Media().PresentsParcSafariIdentity() &&
      !HasPlaybackTargetAvailabilityListeners()) {
    ReportPlaybackTargetState();
  }
}

void ParcMediaElementAirPlay::webkitShowPlaybackTargetPicker(
    HTMLMediaElement& element) {
  LocalFrame* frame = element.GetDocument().GetFrame();
  if (!frame || element.ready_state_ < HTMLMediaElement::kHaveMetadata) {
    return;
  }
  gfx::PointF position =
      frame->GetEventHandler().LastKnownMousePositionInRootFrame();
  if (frame->LocalFrameRoot().IsOutermostMainFrame()) {
    position =
        frame->GetPage()->GetVisualViewport().RootFrameToViewport(position);
  }
  if (FrameWidget* widget = frame->GetWidgetForLocalRoot()) {
    position =
        widget->BlinkSpaceToDIPs(gfx::RectF(position, gfx::SizeF())).origin();
  }
  const gfx::Point dips = gfx::ToFlooredPoint(position);
  for (auto& observer : element.media_player_observer_remote_set_->Value()) {
    observer->OnParcShowPlaybackTargetPicker(dips);
  }
}

bool ParcMediaElementAirPlay::webkitCurrentPlaybackTargetIsWireless(
    HTMLMediaElement& element) {
  return From(element).playing_to_wireless_target_;
}

bool ParcMediaElementAirPlay::webkitWirelessVideoPlaybackDisabled(
    HTMLVideoElement& video) {
  return video.FastHasAttribute(
             parc_media_element_names::
                 WebkitwirelessvideoplaybackdisabledAttr()) ||
         video.FastHasAttribute(html_names::kDisableremoteplaybackAttr) ||
         !video.GetWebMediaPlayer();
}

void ParcMediaElementAirPlay::setWebkitWirelessVideoPlaybackDisabled(
    HTMLVideoElement& video,
    bool disabled) {
  video.SetBooleanAttribute(
      parc_media_element_names::WebkitwirelessvideoplaybackdisabledAttr(),
      disabled);
}

void ParcMediaElementAirPlay::PlayerCreated() {
  player_wireless_ = false;
  player_should_play_ = false;
  failed_to_play_to_wireless_target_ = false;
  if (playing_to_wireless_target_) {
    UpdatePlayingToWirelessTarget();
  }
  ApplyPlaybackTargetToPlayer();
  ReportPlaybackTargetState();
  if (HasPlaybackTargetAvailabilityListeners() &&
      !wireless_playback_target_disabled_) {
    EnqueuePlaybackTargetAvailabilityEvent(false);
  }
  RemoteAvailabilityChanged();
}

void ParcMediaElementAirPlay::MetadataLoaded() {
  if (HasPlaybackTargetAvailabilityListeners() &&
      !wireless_playback_target_disabled_) {
    EnqueuePlaybackTargetAvailabilityEvent(true);
  }
  ReportPlaybackTargetState();
}

void ParcMediaElementAirPlay::PlayerCleared() {
  if (HasPlaybackTargetAvailabilityListeners() &&
      !wireless_playback_target_disabled_) {
    EnqueuePlaybackTargetAvailabilityEvent(false);
  }
  if (playing_to_wireless_target_) {
    UpdatePlayingToWirelessTarget();
  }
  RemoteAvailabilityChanged();
}

void ParcMediaElementAirPlay::RestoreRemotePlaybackTime(
    bool tracks_are_ready,
    HTMLMediaElement::ReadyState old_state) {
  HTMLMediaElement& element = Media();
  if (remote_playback_time_ && tracks_are_ready &&
      element.ready_state_ >= HTMLMediaElement::kHaveFutureData &&
      old_state < HTMLMediaElement::kHaveFutureData) {
    if (const double time =
            *std::exchange(remote_playback_time_, std::nullopt)) {
      element.setCurrentTime(time);
    }
  }
}

bool ParcMediaElementAirPlay::DefersMediaSourceOpen(
    std::unique_ptr<WebMediaSource>& web_media_source) {
  HTMLMediaElement& element = Media();
  if (!element.media_source_attachment_->ParcManaged() ||
      !element.PresentsParcSafariIdentity() ||
      DeferredMediaSourceOpenCanProgress()) {
    return false;
  }
  deferred_web_media_source_ = std::move(web_media_source);
  return true;
}

void ParcMediaElementAirPlay::SourceWasAdded() {
  OpenIfDeferredOpen();
  ReportPlaybackTargetState();
}

void ParcMediaElementAirPlay::SourceWasRemoved() {
  ReportPlaybackTargetState();
}

void ParcMediaElementAirPlay::SetPlaybackTargetAvailability(bool available) {
  if (!Media().PresentsParcSafariIdentity() ||
      available == has_playback_targets_) {
    return;
  }
  has_playback_targets_ = available;
  if (!wireless_playback_target_disabled_) {
    EnqueuePlaybackTargetAvailabilityEvent(true);
  }
  RemoteAvailabilityChanged();
}

void ParcMediaElementAirPlay::SetPlaybackTarget(const String& output_context_id,
                                                const String& device_name,
                                                bool should_play,
                                                uint32_t tint_argb,
                                                uint32_t tint_on_light_argb) {
  HTMLMediaElement& element = Media();
  if (!element.PresentsParcSafariIdentity()) {
    return;
  }
  const bool tint_changed =
      tint_argb != playback_target_tint_ ||
      tint_on_light_argb != playback_target_tint_on_light_;
  const bool placard_changed =
      tint_changed || device_name != playback_target_device_name_;
  const bool target_changed = output_context_id != playback_target_id_ ||
                              (should_play && !output_context_id.empty()) !=
                                  should_play_to_playback_target_;
  playback_target_id_ = output_context_id;
  playback_target_device_name_ = device_name;
  playback_target_tint_ = tint_argb;
  playback_target_tint_on_light_ = tint_on_light_argb;
  should_play_to_playback_target_ = should_play && !output_context_id.empty();
  if (target_changed || !tint_changed) {
    ApplyPlaybackTargetToPlayer();
  }
  if (!should_play_to_playback_target_ && playing_to_wireless_target_) {
    UpdatePlayingToWirelessTarget();
  }
  ReportPlaybackTargetState();
  if (placard_changed && playing_to_wireless_target_ &&
      should_play_to_playback_target_) {
    PlayingToWirelessTargetChanged();
  }
  if (tint_changed && element.media_controls_) {
    element.media_controls_->ParcAirPlayTintChanged();
  }
  if (auto* remote = RemotePlaybackController::From(element)) {
    remote->GetParcExtension().ParcShouldPlayToRemoteTargetChanged(
        should_play_to_playback_target_);
  }
}

void ParcMediaElementAirPlay::PlaybackTargetPickerDismissed() {
  HTMLMediaElement& element = Media();
  if (!element.PresentsParcSafariIdentity()) {
    return;
  }
  if (auto* remote = RemotePlaybackController::From(element)) {
    remote->GetParcExtension().ParcPlaybackTargetPickerDismissed();
  }
}

String ParcMediaElementAirPlay::AirPlayTintedGlyph(
    bool on_light_surface) const {
  static constexpr char kGlyphPath[] =
      "M11.1001033,9.39348478 L11.9211522,10.324939 L14.5705804,10.324939 "
      "C15.4675804,10.324939 15.9642652,9.83506087 15.9642652,8.93120761 "
      "L15.9642652,1.39681739 C15.9642652,0.492978261 15.4675804,0.01 "
      "14.5705804,0.01 L1.43372717,0.01 C0.585067391,0.01 "
      "0.04,0.492978261 0.04,1.39681739 L0.04,8.93120761 C0.04,9.83506087 "
      "0.536769565,10.324939 1.43372717,10.324939 L4.09007935,10.324939 "
      "L4.90423261,9.39348478 L1.60621739,9.39348478 "
      "C1.22673043,9.39348478 1.02664348,9.18650217 1.02664348,8.80701522 "
      "L1.02664348,1.52100978 C1.02664348,1.1346413 "
      "1.22673043,0.934554348 1.60621739,0.934554348 "
      "L14.3980478,0.934554348 C14.7775913,0.934554348 "
      "14.9776783,1.1346413 14.9776783,1.52100978 L14.9776783,8.80701522 "
      "C14.9776783,9.18650217 14.7775913,9.39348478 14.3980478,9.39348478 "
      "L11.1001033,9.39348478 Z M12.2178348,12.9881967 "
      "C12.5421565,12.9881967 12.666363,12.6501134 12.4593522,12.4155255 "
      "L8.29884348,7.703075 C8.1401587,7.52368913 7.86417717,7.52368913 "
      "7.70547826,7.703075 L3.54501196,12.4155255 C3.33801522,12.6501134 "
      "3.46220761,12.9881967 3.78648696,12.9881967 L12.2178348,12.9881967 "
      "Z";
  const uint32_t tint =
      on_light_surface ? playback_target_tint_on_light_ : playback_target_tint_;
  if (!tint) {
    return String();
  }
  return StrCat(
      {"url(\"data:image/svg+xml,<svg "
       "xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 13' "
       "fill='rgba(",
       String::Number((tint >> 16) & 0xff), ",",
       String::Number((tint >> 8) & 0xff), ",", String::Number(tint & 0xff),
       ",", String::Number(((tint >> 24) & 0xff) / 255.0), ")'><path d='",
       kGlyphPath, "'/></svg>\")"});
}

bool ParcMediaElementAirPlay::PlaysToPlaybackTargets() const {
  return Media().PresentsParcSafariIdentity() && SupportsPlaybackTarget();
}

bool ParcMediaElementAirPlay::SupportsPlaybackTarget() const {
  HTMLMediaElement& element = Media();
  return element.web_media_player_ &&
         (ParcPlayerSupportsPlaybackTarget(element.web_media_player_.get()) ||
          (element.GetLoadType() == WebMediaPlayer::kLoadTypeMediaSource &&
           !failed_to_play_to_wireless_target_ &&
           HasWirelessPlaybackTargetAlternative()));
}

bool ParcMediaElementAirPlay::HasWirelessPlaybackTargetAlternative() const {
  HTMLMediaElement& element = Media();
  if (element.load_state_ != HTMLMediaElement::kLoadingFromSourceElement) {
    return false;
  }
  for (HTMLSourceElement& source :
       Traversal<HTMLSourceElement>::ChildrenOf(element)) {
    const KURL url = source.GetNonEmptyURLAttribute(html_names::kSrcAttr);
    if (url.IsValid() && !url.ProtocolIs("blob")) {
      return true;
    }
  }
  return false;
}

bool ParcMediaElementAirPlay::DeferredMediaSourceOpenCanProgress() const {
  return WirelessPlaybackTargetDisabled() ||
         HasWirelessPlaybackTargetAlternative();
}

void ParcMediaElementAirPlay::OpenIfDeferredOpen() {
  HTMLMediaElement& element = Media();
  if (deferred_web_media_source_ && element.media_source_attachment_ &&
      DeferredMediaSourceOpenCanProgress()) {
    element.media_source_attachment_->CompleteAttachingToMediaElement(
        element.media_source_tracer_, std::move(deferred_web_media_source_));
  }
}

void ParcMediaElementAirPlay::CheckPlaybackTargetCompatibility(TimerBase*) {
  HTMLMediaElement& element = Media();
  if (!playing_to_wireless_target_ || !element.web_media_player_ ||
      ParcPlayerSupportsPlaybackTarget(element.web_media_player_.get())) {
    return;
  }
  if (!remote_playback_time_ &&
      element.load_state_ == HTMLMediaElement::kLoadingFromSourceElement &&
      element.HavePotentialSourceChild()) {
    remote_playback_time_ = element.currentTime();
    element.ScheduleNextSourceChild();
    return;
  }
  remote_playback_time_.reset();
  failed_to_play_to_wireless_target_ = true;
  PlaybackTargetIsWirelessChanged(false);
}

void ParcMediaElementAirPlay::RemoteAvailabilityChanged() {
  if (auto* remote = RemotePlaybackController::From(Media())) {
    remote->GetParcExtension().ParcAirPlayAvailabilityChanged();
  }
}

void ParcMediaElementAirPlay::ApplyPlaybackTargetToPlayer() {
  HTMLMediaElement& element = Media();
  if (!element.web_media_player_) {
    return;
  }
  if (auto* parc = element.web_media_player_->GetParcExtension()) {
    parc->ParcSetWirelessVideoPlaybackDisabled(
        wireless_playback_target_disabled_);
    parc->ParcSetPlaybackTarget(playback_target_id_.Utf8(),
                                should_play_to_playback_target_);
  }
  if (element.GetLoadType() == WebMediaPlayer::kLoadTypeMediaSource &&
      should_play_to_playback_target_ != player_should_play_) {
    player_should_play_ = should_play_to_playback_target_;
    PlaybackTargetIsWirelessChanged(player_should_play_);
  }
}

void ParcMediaElementAirPlay::ReportPlaybackTargetState() {
  HTMLMediaElement& element = Media();
  if (!element.media_player_observer_remote_set_) {
    return;
  }
  const bool supports_target =
      !wireless_playback_target_disabled_ && SupportsPlaybackTarget();
  const bool requires_monitoring =
      !wireless_playback_target_disabled_ &&
      (HasPlaybackTargetAvailabilityListeners() || supports_target);
  for (auto& observer : element.media_player_observer_remote_set_->Value()) {
    observer->OnParcPlaybackTargetStateChanged(
        requires_monitoring, supports_target, should_play_to_playback_target_,
        playing_to_wireless_target_ &&
            ParcPlayerSupportsPlaybackTarget(element.web_media_player_.get()));
  }
}

void ParcMediaElementAirPlay::PlaybackTargetIsWirelessChanged(bool wireless) {
  player_wireless_ = wireless;
  if (!wireless) {
    ReportPlaybackTargetState();
    RemoteAvailabilityChanged();
  }
  UpdatePlayingToWirelessTarget();
}

void ParcMediaElementAirPlay::UpdatePlayingToWirelessTarget() {
  Media()
      .GetDocument()
      .GetTaskRunner(TaskType::kMediaElementEvent)
      ->PostTask(
          FROM_HERE,
          BindOnce(&ParcMediaElementAirPlay::DidChangePlayingToWirelessTarget,
                   WrapWeakPersistent(this)));
}

void ParcMediaElementAirPlay::DidChangePlayingToWirelessTarget() {
  HTMLMediaElement& element = Media();
  const bool wireless = player_wireless_ && should_play_to_playback_target_ &&
                        element.web_media_player_;
  if (!element.GetExecutionContext() ||
      element.GetExecutionContext()->IsContextDestroyed() ||
      wireless == playing_to_wireless_target_) {
    return;
  }
  playing_to_wireless_target_ = wireless;
  if (auto* remote = RemotePlaybackController::From(element)) {
    remote->GetParcExtension().ParcPlayingToRemoteTargetChanged(wireless);
  }
  ReportPlaybackTargetState();
  PlayingToWirelessTargetChanged();
  check_playback_target_compatibility_timer_.StartOneShot(
      base::Milliseconds(500), FROM_HERE);
  element.DispatchEvent(*Event::CreateCancelable(
      parc_media_element_names::
          Webkitcurrentplaybacktargetiswirelesschanged()));
}

void ParcMediaElementAirPlay::PlayingToWirelessTargetChanged() {
  auto* video = DynamicTo<HTMLVideoElement>(Media());
  if (!video) {
    return;
  }
  const bool in_picture_in_picture =
      video->picture_in_picture_interstitial_ &&
      video->picture_in_picture_interstitial_->IsVisible();
  if (playing_to_wireless_target_ && !in_picture_in_picture) {
    if (video->picture_in_picture_interstitial_) {
      video->picture_in_picture_interstitial_->remove();
    }
    video->EnsureRemotingInterstitial().ParcShowAirPlay(
        playback_target_device_name_, AirPlayTintedGlyph());
  } else if (video->remoting_interstitial_ &&
             video->remoting_interstitial_->ParcShowsAirPlay()) {
    video->remoting_interstitial_->remove();
    video->remoting_interstitial_->Hide(
        MediaPlayerClient::kMediaRemotingStopNoText);
  }
}

}

// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/modules/remoteplayback/parc_remote_playback_air_play.h"

#include <utility>

#include "build/build_config.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise_resolver.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_throw_dom_exception.h"
#include "third_party/blink/renderer/core/dom/dom_exception.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/event_type_names.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"
#include "third_party/blink/renderer/core/html/media/remote_playback_observer.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/modules/remoteplayback/availability_callback_wrapper.h"
#include "third_party/blink/renderer/modules/remoteplayback/remote_playback.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"

namespace blink {

ParcRemotePlaybackAirPlay::ParcRemotePlaybackAirPlay(RemotePlayback& remote)
    : remote_(&remote) {}

bool ParcRemotePlaybackAirPlay::UsesAirPlay() const {
  return remote_->media_element_ &&
         ParcMediaElementAirPlay::From(*remote_->media_element_)
             .PlaysToPlaybackTargets();
}

bool ParcRemotePlaybackAirPlay::RemotePlaybackDisabled() const {
  return remote_->media_element_->FastHasAttribute(
             html_names::kDisableremoteplaybackAttr) ||
         (UsesAirPlay() && ParcMediaElementAirPlay::From(*remote_->media_element_)
                               .WirelessPlaybackTargetDisabled());
}

bool ParcRemotePlaybackAirPlay::TargetsAvailable() const {
  return ParcMediaElementAirPlay::From(*remote_->media_element_)
      .PlaybackTargetsAvailable();
}

ScriptPromise<IDLUndefined> ParcRemotePlaybackAirPlay::Prompt(
    ScriptState* script_state,
    ExceptionState& exception_state) {
  CheckPrompt(exception_state);
  if (exception_state.HadException()) {
    return EmptyPromise();
  }
  auto* resolver = MakeGarbageCollected<ScriptPromiseResolver<IDLUndefined>>(
      script_state, exception_state.GetContext());
  prompt_resolvers_.push_back(resolver);
  ParcMediaElementAirPlay::webkitShowPlaybackTargetPicker(
      *remote_->media_element_);
  return resolver->Promise();
}

bool ParcRemotePlaybackAirPlay::ShowsPickerForPrompt() {
  if (!UsesAirPlay()) {
    return false;
  }
  ParcMediaElementAirPlay::webkitShowPlaybackTargetPicker(
      *remote_->media_element_);
  return true;
}

void ParcRemotePlaybackAirPlay::CastPromptStarted() {
#if !BUILDFLAG(IS_ANDROID)
  if (WebMediaPlayer* player = remote_->media_element_->GetWebMediaPlayer()) {
    if (auto* parc = player->GetParcExtension()) {
      parc->ParcSetCastPrompted(true);
    }
  }
#endif
}

void ParcRemotePlaybackAirPlay::CastPromptEnded() {
#if !BUILDFLAG(IS_ANDROID)
  if (WebMediaPlayer* player = remote_->media_element_->GetWebMediaPlayer()) {
    if (auto* parc = player->GetParcExtension()) {
      parc->ParcSetCastPrompted(false);
    }
  }
#endif
}

bool ParcRemotePlaybackAirPlay::DefersPresentationResponse(
    mojom::blink::PresentationConnectionResultPtr& result,
    mojom::blink::PresentationErrorPtr& error) {
  ExecutionContext* context = remote_->GetExecutionContext();
  if (!context || !context->IsContextFrozenOrPaused()) {
    return false;
  }
#if !BUILDFLAG(IS_ANDROID)
  if (WebMediaPlayer* player = remote_->media_element_->GetWebMediaPlayer()) {
    if (result) {
      player->RequestMediaRemoting();
      remoting_requested_while_frozen_ = true;
    }
    if (auto* parc = player->GetParcExtension()) {
      parc->ParcSetCastPrompted(false);
    }
  }
#endif
  context->GetTaskRunner(TaskType::kPresentation)
      ->PostTask(FROM_HERE,
                 BindOnce(&RemotePlayback::HandlePresentationResponse,
                          WrapPersistent(remote_.Get()), std::move(result),
                          std::move(error)));
  return true;
}

bool ParcRemotePlaybackAirPlay::TakeRemotingRequestedWhileFrozen() {
  return std::exchange(remoting_requested_while_frozen_, false);
}

void ParcRemotePlaybackAirPlay::ContextDestroyed() {
  ExecutionContext* element_context =
      remote_->media_element_->GetExecutionContext();
  if (!follows_element_ || !element_context ||
      element_context == remote_->GetExecutionContext() ||
      element_context->IsContextDestroyed()) {
    return;
  }
  element_context->GetTaskRunner(TaskType::kMediaElementEvent)
      ->PostTask(FROM_HERE,
                 BindOnce(&ParcRemotePlaybackAirPlay::EndSessionOfGoneFrame,
                          WrapWeakPersistent(this)));
}

void ParcRemotePlaybackAirPlay::DidMoveToDocument() {
  follows_element_ = true;
  MaybeMoveToElementContext();
}

void ParcRemotePlaybackAirPlay::MaybeMoveToElementContext() {
  if (remote_->prompt_promise_resolver_ ||
      remote_->state_ ==
          mojom::blink::PresentationConnectionState::CONNECTING ||
      remote_->state_ == mojom::blink::PresentationConnectionState::CONNECTED) {
    return;
  }
  MoveToElementContext();
}

void ParcRemotePlaybackAirPlay::MoveToElementContext() {
  RemotePlayback& remote = *remote_;
  ExecutionContext* context = remote.media_element_->GetExecutionContext();
  if (!follows_element_ || !context || context->IsContextDestroyed() ||
      context == remote.GetExecutionContext()) {
    return;
  }
  if (remote.GetExecutionContext() &&
      remote.GetExecutionContext()->IsContextDestroyed()) {
    return;
  }
  remote.StopListeningForAvailability();
  remote.is_listening_ = false;
  remote.availability_ = mojom::ScreenAvailability::UNKNOWN;
  remote.SetExecutionContext(context);
  remote.MaybeStartListeningForAvailability();
}

void ParcRemotePlaybackAirPlay::EndSessionOfGoneFrame() {
  MoveToElementContext();
  if (airplay_connection_) {
    return;
  }
  remote_->StateChanged(mojom::blink::PresentationConnectionState::CLOSED);
}

void ParcRemotePlaybackAirPlay::CheckPrompt(ExceptionState& exception_state) {
  if (RemotePlaybackDisabled()) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidStateError,
        "disableRemotePlayback attribute is present.");
    return;
  }
  LocalDOMWindow* window = remote_->media_element_->DomWindow();
  if (!window) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidAccessError,
        "RemotePlayback::prompt() does not work in a detached window.");
    return;
  }
  if (remote_->media_element_->getReadyState() <
      HTMLMediaElement::kHaveMetadata) {
    exception_state.ThrowDOMException(DOMExceptionCode::kNotSupportedError,
                                      "The media element has no metadata.");
    return;
  }
  if (!LocalFrame::HasTransientUserActivation(window->GetFrame())) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidAccessError,
        "RemotePlayback::prompt() requires user gesture.");
    return;
  }
  if (remote_->state_ == mojom::blink::PresentationConnectionState::CLOSED &&
      !remote_->RemotePlaybackAvailable()) {
    exception_state.ThrowDOMException(DOMExceptionCode::kNotSupportedError,
                                      "No remote playback devices found.");
  }
}

void ParcRemotePlaybackAirPlay::SettlePrompts(bool resolve) {
  HeapVector<Member<ScriptPromiseResolver<IDLUndefined>>> resolvers;
  resolvers.swap(prompt_resolvers_);
  for (auto& resolver : resolvers) {
    if (!IsInParallelAlgorithmRunnable(resolver->GetExecutionContext(),
                                       resolver->GetScriptState())) {
      continue;
    }
    ScriptState::Scope script_state_scope(resolver->GetScriptState());
    if (resolve) {
      resolver->Resolve();
    } else {
      resolver->Reject(V8ThrowDOMException::CreateOrDie(
          resolver->GetScriptState()->GetIsolate(),
          DOMExceptionCode::kNotAllowedError, "The prompt was dismissed."));
    }
  }
}

void ParcRemotePlaybackAirPlay::SetAirPlayState(
    mojom::blink::PresentationConnectionState state) {
  RemotePlayback& remote = *remote_;
  if (remote.state_ == state) {
    return;
  }
  remote.state_ = state;
  airplay_connection_ =
      state != mojom::blink::PresentationConnectionState::CLOSED;
  const AtomicString& type =
      state == mojom::blink::PresentationConnectionState::CONNECTING
          ? event_type_names::kConnecting
      : state == mojom::blink::PresentationConnectionState::CONNECTED
          ? event_type_names::kConnect
          : event_type_names::kDisconnect;
  remote.EnqueueEvent(*Event::Create(type), TaskType::kMediaElementEvent);
  for (auto observer : remote.observers_) {
    observer->OnRemotePlaybackStateChanged(remote.state_);
  }
  MaybeMoveToElementContext();
}

void ParcRemotePlaybackAirPlay::ParcAirPlayAvailabilityChanged() {
  if (!UsesAirPlay()) {
    SettlePrompts(false);
  }
  const bool available = remote_->RemotePlaybackAvailable();
  if (available == reported_availability_) {
    return;
  }
  reported_availability_ = available;
  HeapVector<Member<AvailabilityCallbackWrapper>> callbacks(
      remote_->availability_callbacks_.Values());
  for (auto& callback : callbacks) {
    callback->Run(remote_.Get(), available);
  }
}

void ParcRemotePlaybackAirPlay::ParcShouldPlayToRemoteTargetChanged(
    bool should_play) {
  if (!UsesAirPlay() && !airplay_connection_) {
    return;
  }
  SettlePrompts(true);
  if (should_play) {
    if (remote_->state_ == mojom::blink::PresentationConnectionState::CLOSED) {
      SetAirPlayState(mojom::blink::PresentationConnectionState::CONNECTING);
    }
  } else if (airplay_connection_) {
    SetAirPlayState(mojom::blink::PresentationConnectionState::CLOSED);
  }
}

void ParcRemotePlaybackAirPlay::ParcPlayingToRemoteTargetChanged(bool playing) {
  if (!UsesAirPlay() && !airplay_connection_) {
    return;
  }
  SetAirPlayState(playing
                      ? mojom::blink::PresentationConnectionState::CONNECTED
                      : mojom::blink::PresentationConnectionState::CLOSED);
}

void ParcRemotePlaybackAirPlay::ParcPlaybackTargetPickerDismissed() {
  SettlePrompts(false);
}

void ParcRemotePlaybackAirPlay::Trace(Visitor* visitor) const {
  visitor->Trace(remote_);
  visitor->Trace(prompt_resolvers_);
}

}

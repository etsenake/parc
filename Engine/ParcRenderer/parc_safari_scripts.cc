// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/bindings/core/v8/parc_safari_scripts.cc.
#include "third_party/blink/renderer/bindings/core/v8/parc_safari_scripts.h"

#include <iterator>
#include <tuple>

#include "third_party/blink/renderer/bindings/core/v8/parc_managed_media_source.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_safari_media_keys.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_media_keys.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_need_key.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_playback_target.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_presentation.h"
#include "third_party/blink/renderer/bindings/core/v8/script_evaluation_result.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_event_target.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_html_media_element.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_html_video_element.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_navigator.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_script_runner.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_worker_navigator.h"
#include "third_party/blink/renderer/core/context_features/context_feature_settings.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/frame/picture_in_picture_controller.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/script/classic_script.h"
#include "third_party/blink/renderer/core/workers/worker_or_worklet_global_scope.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/bindings/v8_per_context_data.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "v8/include/v8.h"

namespace blink {

namespace {

// Parc: what Safari's presentation script (parc_webkit_presentation.h)
// receives as its argument and the page never sees. fire(target, type)
// dispatches a trusted, cancelable, non-bubbling event, as WebKit's
// HTMLMediaElement::scheduleEvent does.
void ParcPresentationFire(const v8::FunctionCallbackInfo<v8::Value>& info) {
  v8::Isolate* isolate = info.GetIsolate();
  if (info.Length() < 2 || !info[1]->IsString()) {
    return;
  }
  EventTarget* target = V8EventTarget::ToWrappable(isolate, info[0]);
  if (!target) {
    return;
  }
  target->DispatchEvent(*Event::CreateCancelable(
      AtomicString(ToCoreString(isolate, info[1].As<v8::String>()))));
}

// mediaGesture(element): whether WebKit has lifted the element's fullscreen
// and picture-in-picture gesture rule (HTMLMediaElement::
// ParcHadMediaUserGesture).
void ParcPresentationMediaGesture(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  HTMLMediaElement* element =
      info.Length() ? V8HTMLMediaElement::ToWrappable(info.GetIsolate(), info[0])
                    : nullptr;
  info.GetReturnValue().Set(element && element->ParcHadMediaUserGesture());
}

// allowPictureInPicture(video): lets the next picture-in-picture request go
// without transient activation once WebKit's rule is lifted for the video,
// through Chromium's picture-in-picture request token. Only for a video
// Chromium would let in, so the request that follows at once spends the
// token and none is left for the page.
void ParcPresentationAllowPictureInPicture(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  HTMLVideoElement* video =
      info.Length() ? V8HTMLVideoElement::ToWrappable(info.GetIsolate(), info[0])
                    : nullptr;
  if (!video || !video->ParcHadMediaUserGesture()) {
    return;
  }
  PictureInPictureController& controller =
      PictureInPictureController::From(video->GetDocument());
  if (!controller.PictureInPictureElement() &&
      controller.IsElementAllowed(*video, /*report_failure=*/false) ==
          PictureInPictureController::Status::kEnabled) {
    controller.ActivatePictureInPictureRequestToken();
  }
}

// The presentation script evaluates to a function; it is called with an
// object holding the helpers above. Errors are reported like the page's.
void CallParcPresentationScript(ScriptState* script_state,
                                v8::Local<v8::Function> install) {
  v8::Isolate* isolate = script_state->GetIsolate();
  v8::Local<v8::Context> context = script_state->GetContext();
  v8::Local<v8::Object> helpers = v8::Object::New(isolate);
  const struct {
    const char* name;
    v8::FunctionCallback callback;
  } kHelpers[] = {
      {"fire", ParcPresentationFire},
      {"mediaGesture", ParcPresentationMediaGesture},
      {"allowPictureInPicture", ParcPresentationAllowPictureInPicture},
  };
  for (const auto& helper : kHelpers) {
    v8::Local<v8::Function> function;
    if (!v8::Function::New(context, helper.callback, v8::Local<v8::Value>(), 0,
                           v8::ConstructorBehavior::kThrow)
             .ToLocal(&function) ||
        helpers
            ->CreateDataProperty(context, V8AtomicString(isolate, helper.name),
                                 function)
            .IsNothing()) {
      return;
    }
  }
  v8::TryCatch try_catch(isolate);
  try_catch.SetVerbose(true);
  v8::Local<v8::Value> argv[] = {helpers};
  std::ignore = V8ScriptRunner::CallFunction(
      install, ExecutionContext::From(script_state), v8::Undefined(isolate),
      std::size(argv), argv, isolate);
}

}  // namespace

bool PresentsParcSafariIdentity(LocalDOMWindow* window) {
  return IsParcSafariIdentityUserAgent(window->UserAgent());
}

// Parc: Safari's members of Blink interfaces
// ([ContextEnabled=ParcSafariIdentity], such as HTMLMediaElement's
// getStartDate) are installed with each interface object made after the
// window has these settings; they check the document's user agent then.
// ContextEnabled=ParcAudioVideoTracks needs them with Chromium's
// AudioVideoTracks flag too, which [RuntimeEnabled] alone gave.
void EnableParcSafariBindings(LocalDOMWindow* window) {
  ContextFeatureSettings::From(
      window, ContextFeatureSettings::CreationMode::kCreateIfNotExists);
}

// Parc: Safari has no navigator.userAgentData, so a document presenting
// Safari's identity has none either, in every world. The [SecureContext]
// attribute is installed when the prototype is created, which
// PrototypeForType does, so it is removed after that. Runs no script.
void RemoveParcUserAgentData(ScriptState* script_state) {
  v8::Local<v8::Object> prototype =
      script_state->PerContextData()->PrototypeForType(
          V8Navigator::GetWrapperTypeInfo());
  if (!prototype.IsEmpty()) {
    std::ignore = prototype->Delete(
        script_state->GetContext(),
        V8AtomicString(script_state->GetIsolate(), "userAgentData"));
  }
}

// Parc: the main world of a new context also gets Safari's
// ManagedMediaSource, which Chromium lacks (parc_managed_media_source.h),
// its legacy prefixed EME (parc_webkit_media_keys.h), its MediaKeys
// without getStatusForPolicy (parc_safari_media_keys.h) and its video
// presentation API (parc_webkit_presentation.h) and its AirPlay availability
// event (parc_webkit_playback_target.h), before any script of the
// page runs, unless the document can't run scripts. Errors from them are
// reported unmuted, like the page's. The legacy EME script's value is its
// webkitneedkey hook, which only Blink reaches (parc_webkit_need_key.h).
void InstallParcSafariScripts(ScriptState* script_state,
                              LocalDOMWindow* window) {
  if (window->CanExecuteScripts(kNotAboutToExecuteScript)) {
    for (const char* source :
         {kParcManagedMediaSourceScript, kParcWebKitMediaKeysScript,
          kParcSafariMediaKeysScript, kParcWebKitPresentationScript,
          kParcWebKitPlaybackTargetScript}) {
      String script(source);
      v8::HandleScope handle_scope(script_state->GetIsolate());
      ScriptEvaluationResult result =
          ClassicScript::CreateUnspecifiedScript(
              script, ScriptSourceLocationType::kInternal,
              SanitizeScriptErrors::kDoNotSanitize)
              ->RunScriptOnScriptStateAndReturnValue(script_state);
      if (source == kParcWebKitMediaKeysScript) {
        SetParcWebKitNeedKeyHook(script_state,
                                 result.GetSuccessValueOrEmpty());
      }
      if (source == kParcWebKitPlaybackTargetScript) {
        HTMLMediaElement::SetParcPlaybackTargetEventHook(
            script_state, result.GetSuccessValueOrEmpty());
      }
      if (source == kParcWebKitPresentationScript) {
        v8::Local<v8::Value> install = result.GetSuccessValueOrEmpty();
        if (!install.IsEmpty() && install->IsFunction()) {
          CallParcPresentationScript(script_state, install.As<v8::Function>());
        }
      }
    }
  }
}

// A document that took over its window's context gets them in a microtask:
// after the commit that installed it has finished, and before any of its own
// scripts run.
void InstallParcSafariScriptsAfterCommit(ScriptState* script_state,
                                         LocalDOMWindow* window) {
  if (!script_state || !window || !script_state->ContextIsValid() ||
      !window->GetFrame() || !PresentsParcSafariIdentity(window)) {
    return;
  }
  ScriptState::Scope scope(script_state);
  InstallParcSafariScripts(script_state, window);
}

void InstallParcSafariWorkerScripts(WorkerOrWorkletGlobalScope& global_scope,
                                    ScriptState* script_state,
                                    V8PerContextData* per_context_data,
                                    v8::Isolate* isolate) {
  // Parc: a worker of a document presenting Safari's identity carries
  // Safari's user agent and, like Safari, has no navigator.userAgentData
  // (third_party/blink/renderer/core/frame/parc_safari_identity.h). Removed
  // before the worker's script is evaluated. A dedicated worker also gets
  // Safari's ManagedMediaSource (parc_managed_media_source.h).
  if (global_scope.IsWorkerGlobalScope() &&
      IsParcSafariIdentityUserAgent(global_scope.UserAgent())) {
    ScriptState::Scope scope(script_state);
    v8::Local<v8::Object> prototype = per_context_data->PrototypeForType(
        V8WorkerNavigator::GetWrapperTypeInfo());
    if (!prototype.IsEmpty()) {
      std::ignore = prototype->Delete(
          script_state->GetContext(),
          V8AtomicString(isolate, "userAgentData"));
    }
    if (global_scope.IsDedicatedWorkerGlobalScope()) {
      ClassicScript::CreateUnspecifiedScript(
          String(kParcManagedMediaSourceScript),
          ScriptSourceLocationType::kInternal,
          SanitizeScriptErrors::kDoNotSanitize)
          ->RunScriptOnScriptState(script_state);
    }
  }
}

}  // namespace blink

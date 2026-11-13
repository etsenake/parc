// Copyright 2026 Parc contributors.
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
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/element.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/dom/qualified_name.h"
#include "third_party/blink/renderer/core/event_type_names.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/frame/picture_in_picture_controller.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element.h"
#include "third_party/blink/renderer/core/html/media/parc_media_element_air_play.h"
#include "third_party/blink/renderer/core/script/classic_script.h"
#include "third_party/blink/renderer/core/workers/worker_or_worklet_global_scope.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/bindings/v8_per_context_data.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/scheduler/public/event_loop.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/std_lib_extras.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "v8/include/v8.h"

namespace blink {

namespace {

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

void ParcPresentationMediaGesture(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  HTMLMediaElement* element =
      info.Length() ? V8HTMLMediaElement::ToWrappable(info.GetIsolate(), info[0])
                    : nullptr;
  info.GetReturnValue().Set(
      element && ParcMediaElement::From(*element).HadMediaUserGesture());
}

void ParcPresentationAllowPictureInPicture(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  HTMLVideoElement* video =
      info.Length() ? V8HTMLVideoElement::ToWrappable(info.GetIsolate(), info[0])
                    : nullptr;
  if (!video || !ParcMediaElement::From(*video).HadMediaUserGesture()) {
    return;
  }
  PictureInPictureController& controller =
      PictureInPictureController::From(video->GetDocument());
  if (!controller.PictureInPictureElement() &&
      controller.IsElementAllowed(*video, false) ==
          PictureInPictureController::Status::kEnabled) {
    controller.ActivatePictureInPictureRequestToken();
  }
}

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

}

bool PresentsParcSafariIdentity(LocalDOMWindow* window) {
  return IsParcSafariIdentityUserAgent(window->UserAgent());
}

void EnableParcSafariBindings(LocalDOMWindow* window) {
  ContextFeatureSettings::From(
      window, ContextFeatureSettings::CreationMode::kCreateIfNotExists);
}

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
        ParcMediaElementAirPlay::SetPlaybackTargetEventHook(
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

void InstallParcSafariScriptsAfterCommit(ScriptState* script_state,
                                         LocalDOMWindow* window) {
  if (!script_state || !window || !script_state->ContextIsValid() ||
      !window->GetFrame() || !PresentsParcSafariIdentity(window)) {
    return;
  }
  ScriptState::Scope scope(script_state);
  InstallParcSafariScripts(script_state, window);
}

void ParcSafariWindowContextCreated(ScriptState* script_state,
                                    LocalDOMWindow* window,
                                    bool main_world) {
  if (!PresentsParcSafariIdentity(window)) {
    return;
  }
  RemoveParcUserAgentData(script_state);
  if (main_world) {
    InstallParcSafariScripts(script_state, window);
  }
}

void ParcSafariDocumentTookOverWindow(ScriptState* script_state,
                                      LocalDOMWindow* window,
                                      bool main_world) {
  if (!PresentsParcSafariIdentity(window)) {
    return;
  }
  ScriptState::Scope scope(script_state);
  RemoveParcUserAgentData(script_state);
  if (main_world) {
    window->GetAgent()->event_loop()->EnqueueMicrotask(
        BindOnce(&InstallParcSafariScriptsAfterCommit,
                 WrapWeakPersistent(script_state), WrapWeakPersistent(window)));
  }
}

namespace {

void FireParcSafariFullscreenEvents(const AtomicString& type,
                                    Element* element,
                                    Document* document) {
  if (!document || !element) {
    return;
  }
  EventTarget* target =
      element->isConnected() && &element->GetDocument() == document
          ? static_cast<EventTarget*>(element)
          : static_cast<EventTarget*>(document);
  const auto fire = [target](const AtomicString& event_type) {
    Event* event = Event::CreateBubble(event_type);
    event->SetComposed(true);
    target->DispatchEvent(*event);
  };
  fire(type);
  if (type == event_type_names::kFullscreenerror) {
    fire(event_type_names::kWebkitfullscreenerror);
    return;
  }
  const auto handles_both = [](const EventTarget& listening) {
    return listening.HasJSBasedEventListeners(
               event_type_names::kWebkitfullscreenchange) &&
           listening.HasJSBasedEventListeners(
               event_type_names::kFullscreenchange);
  };
  if (handles_both(*target) || handles_both(target->ToNode()->GetDocument())) {
    return;
  }
  fire(event_type_names::kWebkitfullscreenchange);
}

}

bool EnqueueParcSafariFullscreenEvent(const AtomicString& type,
                                      Element& element,
                                      Document& document) {
  const ExecutionContext* context = document.GetExecutionContext();
  if (!context || !IsParcSafariIdentityUserAgent(context->UserAgent())) {
    return false;
  }
  document.EnqueueAnimationFrameTask(
      BindOnce(FireParcSafariFullscreenEvents, type,
               WrapWeakPersistent(&element), WrapWeakPersistent(&document)));
  return true;
}

const AtomicString& ParcLegacyEmeEventName(const QualifiedName& attr_name) {
  struct Handler {
    QualifiedName attribute;
    AtomicString event;
  };
  DEFINE_STATIC_LOCAL(const Vector<Handler>, handlers,
                      ({{QualifiedName(AtomicString("onwebkitkeyadded")),
                         AtomicString("webkitkeyadded")},
                        {QualifiedName(AtomicString("onwebkitkeyerror")),
                         AtomicString("webkitkeyerror")},
                        {QualifiedName(AtomicString("onwebkitkeymessage")),
                         AtomicString("webkitkeymessage")},
                        {QualifiedName(AtomicString("onwebkitneedkey")),
                         AtomicString("webkitneedkey")}}));
  for (const Handler& handler : handlers) {
    if (attr_name == handler.attribute) {
      return handler.event;
    }
  }
  return g_null_atom;
}

bool ParcLegacyEmeHandlersEnabled(const Document& document) {
  auto* window = DynamicTo<LocalDOMWindow>(document.GetExecutionContext());
  return window && IsParcSafariIdentityUserAgent(window->UserAgent());
}

void InstallParcSafariWorkerScripts(WorkerOrWorkletGlobalScope& global_scope,
                                    ScriptState* script_state,
                                    V8PerContextData* per_context_data,
                                    v8::Isolate* isolate) {
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

}

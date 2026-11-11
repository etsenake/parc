// Copyright 2026 Parc contributors.
// Safari's `webkitneedkey` for documents presenting Safari's identity
// (docs/fairplay-identity.md, docs/fairplay-safari-surface.md), raised the way
// WebKit raises it: HTMLMediaElement::mediaPlayerKeyNeeded queues a trusted
// WebKitMediaKeyNeededEvent at the media element as its own task, whether or
// not anything listens, before the `encrypted` event of the same init data.
// WebKit calls it for each protected track a Media Source parses
// (SourceBufferPrivateAVFObjC::
// didProvideContentKeyRequestInitializationDataForTrackID) and for every key
// request of its AVFoundation player (MediaPlayerPrivateAVFoundationObjC::
// shouldWaitForLoadingOfResource, `skd://` and `clearkey://`).
//
// Parc's media pipeline reports the same two sources through
// ParcMediaPlayerClient: ParcWebKitMediaSourceKeyNeeded() from
// WebMediaPlayerImpl::OnEncryptedMediaInitData for a Safari-identity Media
// Source's sinf, before it decides on `encrypted`, and ParcWebKitKeyRequest()
// from the native HLS route for every key request.
//
// WebKitMediaKeyNeededEvent is a class of kParcWebKitMediaKeysScript
// (parc_webkit_media_keys.h), which the main world runs before the page's
// scripts. Its completion value is the script's key-needed hook, a function
// (element, initData, kind) that records the init data for the element's
// legacy keys and returns the event. LocalWindowProxy keeps the hook in a
// private property of the main world's global object, which no page script
// can see, and the media element queues the event the hook returns, so it is
// trusted.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_need_key.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_NEED_KEY_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_NEED_KEY_H_

#include <iterator>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

#include "base/containers/span.h"
#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom-blink.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/parc_web_media_player_extension.h"
#include "third_party/blink/public/platform/web_media_player.h"
#include "third_party/blink/renderer/bindings/core/v8/parc_webkit_skd_init_data.h"
#include "third_party/blink/renderer/bindings/core/v8/to_v8_traits.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_binding_for_core.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_event.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_html_media_element.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_script_runner.h"
#include "third_party/blink/renderer/core/dom/events/event.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/parc_safari_identity.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/typed_arrays/dom_typed_array.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/bindings/v8_binding.h"
#include "third_party/blink/renderer/platform/wtf/hash_map.h"
#include "third_party/blink/renderer/platform/wtf/std_lib_extras.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "v8/include/v8.h"

namespace blink {

// A V8 private symbol, the same one for every caller in the isolate. Set on
// the global proxy, V8 keeps it on the context's own global object, so a
// navigation's new context starts without the previous document's hook.
inline v8::Local<v8::Private> ParcWebKitNeedKeyHookKey(v8::Isolate* isolate) {
  return v8::Private::ForApi(isolate,
                             V8AtomicString(isolate, "Parc::WebKitNeedKey"));
}

// canPlayAVFoundationType(type), which Blink gives the script's hook: the
// browser's answer to WebKit's AVAssetMIMETypeCache::canDecodeType
// (media.mojom.ParcVideoToolboxDecoding.CanPlayAVFoundationType), which
// WebKit's AVFoundation player key systems ask
// (MediaPlayerPrivateAVFoundationObjC::supportsKeySystem). Synchronous, as
// the script's isTypeSupported is; each answer is kept for the render
// process, as WebKit's MIMETypeCache keeps its results.
inline void ParcCanPlayAVFoundationType(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  v8::Isolate* isolate = info.GetIsolate();
  if (!info.Length() || !info[0]->IsString()) {
    info.GetReturnValue().Set(false);
    return;
  }
  const String type = ToCoreString(isolate, info[0].As<v8::String>());
  using TypeSupportAnswers = HashMap<String, bool>;
  DEFINE_STATIC_LOCAL(TypeSupportAnswers, answers, ());
  auto it = answers.find(type);
  if (it != answers.end()) {
    info.GetReturnValue().Set(it->value);
    return;
  }
  ExecutionContext* execution_context = CurrentExecutionContext(isolate);
  if (!execution_context || execution_context->IsContextDestroyed()) {
    info.GetReturnValue().Set(false);
    return;
  }
  mojo::Remote<media::mojom::blink::ParcVideoToolboxDecoding> remote;
  execution_context->GetBrowserInterfaceBroker().GetInterface(
      remote.BindNewPipeAndPassReceiver());
  bool supported = false;
  if (!remote->CanPlayAVFoundationType(type, &supported)) {
    info.GetReturnValue().Set(false);
    return;
  }
  answers.Set(type, supported);
  info.GetReturnValue().Set(supported);
}

// Keeps kParcWebKitMediaKeysScript's completion value when it is the hook,
// and gives the hook its helpers as own properties no page script can reach.
// The script returns nothing when the context already has WebKitMediaKeys (a
// document taking over its window's context keeps the first hook).
inline void SetParcWebKitNeedKeyHook(ScriptState* script_state,
                                     v8::Local<v8::Value> hook) {
  if (hook.IsEmpty() || !hook->IsFunction()) {
    return;
  }
  v8::Isolate* isolate = script_state->GetIsolate();
  v8::Local<v8::Context> context = script_state->GetContext();
  v8::Local<v8::Function> can_play;
  if (v8::Function::New(context, ParcCanPlayAVFoundationType,
                        v8::Local<v8::Value>(), 1,
                        v8::ConstructorBehavior::kThrow)
          .ToLocal(&can_play)) {
    std::ignore = hook.As<v8::Object>()->CreateDataProperty(
        context, V8AtomicString(isolate, "canPlayAVFoundationType"), can_play);
  }
  std::ignore = context->Global()->SetPrivate(
      context, ParcWebKitNeedKeyHookKey(isolate), hook);
}

// The provideKey(keyId, key) the hook gets with a clearkey:// request, bound
// to the element and the player that made the request: the script calls it
// with a key its WebKitMediaKeys hold for the request
// (MediaPlayerPrivateAVFoundationObjC::keyAdded, fulfillRequestWithKeyData),
// and that player takes it. A request lives as long as its player (WebKit's
// m_keyURIToRequestMap), so a key for an element that has loaded another
// player since goes nowhere. The player is only compared, never used.
inline void ParcProvideClearKey(
    const v8::FunctionCallbackInfo<v8::Value>& info) {
  v8::Isolate* isolate = info.GetIsolate();
  v8::Local<v8::Context> context = isolate->GetCurrentContext();
  v8::Local<v8::Value> wrapper;
  v8::Local<v8::Value> requester;
  if (!info.Data()->IsArray() ||
      !info.Data().As<v8::Array>()->Get(context, 0).ToLocal(&wrapper) ||
      !info.Data().As<v8::Array>()->Get(context, 1).ToLocal(&requester) ||
      !requester->IsExternal() || info.Length() < 2 || !info[0]->IsString() ||
      !info[1]->IsUint8Array()) {
    return;
  }
  HTMLMediaElement* element = V8HTMLMediaElement::ToWrappable(isolate, wrapper);
  WebMediaPlayer* player = element ? element->GetWebMediaPlayer() : nullptr;
  if (!player ||
      player != requester.As<v8::External>()->Value(
                    v8::kExternalPointerTypeTagDefault)) {
    return;
  }
  const std::string key_id =
      ToCoreString(isolate, info[0].As<v8::String>()).Utf8();
  v8::Local<v8::Uint8Array> array = info[1].As<v8::Uint8Array>();
  std::vector<uint8_t> key(array->ByteLength());
  array->CopyContents(key.data(), key.size());
  if (ParcWebMediaPlayerExtension* parc = player->GetParcExtension()) {
    parc->ParcProvideClearKey(key_id, key);
  }
}

// HTMLMediaElement::mediaPlayerKeyNeeded: queues webkitneedkey at |element|
// with |init_data| when its document presents Safari's identity. Callers
// queue it before the `encrypted` event of the same init data, as WebKit
// does; the media element's event queue keeps that order, one task per event.
// |kind| tells the hook where the init data comes from: "media-source",
// "skd" or "clearkey". A clearkey:// request also hands the hook
// ParcProvideClearKey bound to the element; the hook may answer it from keys
// the page already gave and raise nothing, as WebKit does.
inline void ScheduleParcWebKitNeedKey(HTMLMediaElement& element,
                                      base::span<const uint8_t> init_data,
                                      const char* kind) {
  auto* window = DynamicTo<LocalDOMWindow>(element.GetExecutionContext());
  if (!window || window->IsContextDestroyed() || !window->GetFrame() ||
      !IsParcSafariIdentityUserAgent(window->UserAgent())) {
    return;
  }
  ScriptState* script_state = ToScriptStateForMainWorld(window->GetFrame());
  if (!script_state || !script_state->ContextIsValid()) {
    return;
  }
  ScriptState::Scope scope(script_state);
  v8::Isolate* isolate = script_state->GetIsolate();
  v8::Local<v8::Context> context = script_state->GetContext();
  v8::Local<v8::Value> hook;
  if (!context->Global()
           ->GetPrivate(context, ParcWebKitNeedKeyHookKey(isolate))
           .ToLocal(&hook) ||
      !hook->IsFunction()) {
    return;
  }
  v8::Local<v8::Value> element_wrapper =
      ToV8Traits<HTMLMediaElement>::ToV8(script_state, &element);
  v8::Local<v8::Value> provide_key = v8::Undefined(isolate);
  if (std::string_view(kind) == "clearkey" && element.GetWebMediaPlayer()) {
    v8::Local<v8::Value> data[] = {
        element_wrapper,
        v8::External::New(isolate, element.GetWebMediaPlayer(),
                          v8::kExternalPointerTypeTagDefault),
    };
    v8::Local<v8::Function> function;
    if (v8::Function::New(context, &ParcProvideClearKey,
                          v8::Array::New(isolate, data, std::size(data)), 2,
                          v8::ConstructorBehavior::kThrow)
            .ToLocal(&function)) {
      provide_key = function;
    }
  }
  v8::Local<v8::Value> argv[] = {
      element_wrapper,
      ToV8Traits<DOMUint8Array>::ToV8(script_state,
                                      DOMUint8Array::Create(init_data)),
      V8AtomicString(isolate, kind),
      provide_key,
  };
  // The hook is Parc's own script; nothing it could throw reaches the page.
  v8::TryCatch try_catch(isolate);
  v8::Local<v8::Value> result;
  if (!V8ScriptRunner::CallFunction(hook.As<v8::Function>(), window,
                                    v8::Undefined(isolate),
                                    static_cast<int>(std::size(argv)), argv,
                                    isolate)
           .ToLocal(&result)) {
    return;
  }
  Event* event = V8Event::ToWrappable(isolate, result);
  if (!event) {
    return;
  }
  event->SetTarget(&element);
  element.ScheduleEvent(event);
}

// A new load of |element| (HTMLMediaElement::StartPlayerLoad): the hook,
// called with kind "load", forgets the init data and key requests the
// previous player gave the element and its renderer session, as WebKit's new
// player starts without them. It raises nothing.
inline void ParcWebKitMediaKeysNewLoad(HTMLMediaElement& element) {
  ScheduleParcWebKitNeedKey(element, base::span<const uint8_t>(), "load");
}

// A key request of WebKit's AVFoundation player
// (MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource), by the
// scheme of |key_uri|, the request URL's absolute string as UTF-8: skd:// is
// ParcWebKitSkdInitData(the URI), clearkey:// the key ID (the URL after
// "clearkey:") as UTF-8. Schemes are compared as WebKit does, case-sensitively;
// other requests raise nothing.
inline void ScheduleParcWebKitKeyRequest(HTMLMediaElement& element,
                                         std::string_view key_uri) {
  if (key_uri.starts_with("skd:")) {
    const String uri = String::FromUtf8(key_uri);
    std::u16string units;
    units.reserve(uri.length());
    for (wtf_size_t i = 0; i < uri.length(); ++i) {
      units.push_back(uri[i]);
    }
    const std::vector<uint8_t> init_data = ParcWebKitSkdInitData(units);
    ScheduleParcWebKitNeedKey(element, init_data, "skd");
  } else if (key_uri.starts_with("clearkey:")) {
    ScheduleParcWebKitNeedKey(element, base::as_byte_span(key_uri.substr(9)),
                              "clearkey");
  }
}

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_NEED_KEY_H_

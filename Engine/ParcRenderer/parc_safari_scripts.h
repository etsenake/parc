// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/bindings/core/v8/parc_safari_scripts.h.
// What a context of a document presenting Safari's identity gets before the
// page's scripts run: Safari-only bindings, no navigator.userAgentData, and
// Safari's script APIs. LocalWindowProxy and WorkerOrWorkletScriptController
// call these at the points where they install a context's features.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_SCRIPTS_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_SCRIPTS_H_

namespace v8 {
class Isolate;
}  // namespace v8

namespace blink {

class LocalDOMWindow;
class ScriptState;
class V8PerContextData;
class WorkerOrWorkletGlobalScope;

bool PresentsParcSafariIdentity(LocalDOMWindow* window);

// Safari's members of Blink interfaces, installed with each interface object
// made after this.
void EnableParcSafariBindings(LocalDOMWindow* window);

// Removes navigator.userAgentData from the context's Navigator prototype.
// Runs no script.
void RemoveParcUserAgentData(ScriptState* script_state);

// Runs Safari's scripts in the window's main world, unless the document
// can't run scripts.
void InstallParcSafariScripts(ScriptState* script_state,
                              LocalDOMWindow* window);

// InstallParcSafariScripts() from a microtask, for a document that took over
// its window's context.
void InstallParcSafariScriptsAfterCommit(ScriptState* script_state,
                                         LocalDOMWindow* window);

// A worker's: no navigator.userAgentData, and ManagedMediaSource in a
// dedicated worker, for a Safari-identity global scope.
void InstallParcSafariWorkerScripts(WorkerOrWorkletGlobalScope& global_scope,
                                    ScriptState* script_state,
                                    V8PerContextData* per_context_data,
                                    v8::Isolate* isolate);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_SCRIPTS_H_

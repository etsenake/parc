// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_SCRIPTS_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_SCRIPTS_H_

namespace v8 {
class Isolate;
}

namespace blink {

class AtomicString;
class Document;
class Element;
class LocalDOMWindow;
class QualifiedName;
class ScriptState;
class V8PerContextData;
class WorkerOrWorkletGlobalScope;

bool PresentsParcSafariIdentity(LocalDOMWindow* window);

void EnableParcSafariBindings(LocalDOMWindow* window);

void RemoveParcUserAgentData(ScriptState* script_state);

void InstallParcSafariScripts(ScriptState* script_state,
                              LocalDOMWindow* window);

void InstallParcSafariScriptsAfterCommit(ScriptState* script_state,
                                         LocalDOMWindow* window);

void ParcSafariWindowContextCreated(ScriptState* script_state,
                                    LocalDOMWindow* window,
                                    bool main_world);

void ParcSafariDocumentTookOverWindow(ScriptState* script_state,
                                      LocalDOMWindow* window,
                                      bool main_world);

bool EnqueueParcSafariFullscreenEvent(const AtomicString& type,
                                      Element& element,
                                      Document& document);

const AtomicString& ParcLegacyEmeEventName(const QualifiedName& attr_name);

bool ParcLegacyEmeHandlersEnabled(const Document& document);

void InstallParcSafariWorkerScripts(WorkerOrWorkletGlobalScope& global_scope,
                                    ScriptState* script_state,
                                    V8PerContextData* per_context_data,
                                    v8::Isolate* isolate);

}

#endif

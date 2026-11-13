// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_REMOTEPLAYBACK_PARC_REMOTE_PLAYBACK_AIR_PLAY_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_REMOTEPLAYBACK_PARC_REMOTE_PLAYBACK_AIR_PLAY_H_

#include "third_party/blink/public/mojom/presentation/presentation.mojom-blink.h"
#include "third_party/blink/renderer/bindings/core/v8/idl_types.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise.h"
#include "third_party/blink/renderer/core/html/media/parc_remote_playback_extension.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_vector.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"

namespace blink {

class ExceptionState;
class RemotePlayback;
template <typename IDLResolvedType>
class ScriptPromiseResolver;
class ScriptState;

class ParcRemotePlaybackAirPlay final
    : public GarbageCollected<ParcRemotePlaybackAirPlay>,
      public ParcRemotePlaybackExtension {
 public:
  explicit ParcRemotePlaybackAirPlay(RemotePlayback& remote);

  bool UsesAirPlay() const;
  bool RemotePlaybackDisabled() const;
  bool TargetsAvailable() const;
  bool KeepsConnection() const { return airplay_connection_; }
  bool HasPendingActivity() const { return !prompt_resolvers_.empty(); }

  ScriptPromise<IDLUndefined> Prompt(ScriptState* script_state,
                                     ExceptionState& exception_state);
  bool ShowsPickerForPrompt();
  void CastPromptStarted();
  void CastPromptEnded();
  bool DefersPresentationResponse(
      mojom::blink::PresentationConnectionResultPtr& result,
      mojom::blink::PresentationErrorPtr& error);
  bool TakeRemotingRequestedWhileFrozen();
  void AvailabilityReported(bool available) {
    reported_availability_ = available;
  }

  void ContextDestroyed();
  void DidMoveToDocument();
  void MaybeMoveToElementContext();

  void ParcAirPlayAvailabilityChanged() override;
  void ParcShouldPlayToRemoteTargetChanged(bool should_play) override;
  void ParcPlayingToRemoteTargetChanged(bool playing) override;
  void ParcPlaybackTargetPickerDismissed() override;

  void Trace(Visitor* visitor) const;

 private:
  void MoveToElementContext();
  void EndSessionOfGoneFrame();
  void CheckPrompt(ExceptionState& exception_state);
  void SettlePrompts(bool resolve);
  void SetAirPlayState(mojom::blink::PresentationConnectionState state);

  Member<RemotePlayback> remote_;
  bool remoting_requested_while_frozen_ = false;
  bool follows_element_ = false;
  bool reported_availability_ = false;
  bool airplay_connection_ = false;
  HeapVector<Member<ScriptPromiseResolver<IDLUndefined>>> prompt_resolvers_;
};

}

#endif

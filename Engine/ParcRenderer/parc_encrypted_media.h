// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_

#include <vector>

#include "base/functional/callback.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_vector.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/wtf/hash_map.h"
#include "third_party/blink/renderer/platform/wtf/text/string_hash.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "third_party/blink/renderer/platform/wtf/wtf_size_t.h"

namespace blink {

class ExceptionState;
class ExecutionContext;
class MediaKeySystemConfiguration;
class MediaKeys;
class ScriptState;
template <typename IDLResolvedType>
class ScriptPromiseResolver;
class Visitor;
struct WebMediaKeySystemConfiguration;

void ParcApplyInitDataTypeRules(const MediaKeySystemConfiguration& config,
                                bool safari_identity,
                                bool refuse_empty_init_data_types,
                                WebMediaKeySystemConfiguration& web_config);

void ParcApplySafariOnlyAudioCodecs(bool safari_identity,
                                    WebMediaKeySystemConfiguration& web_config);

void ParcApplyFairPlayCapabilityRules(
    const String& key_system,
    bool safari_fairplay,
    bool is_from_media_capabilities,
    WebMediaKeySystemConfiguration& web_config);

void ParcApplySafariOnlySessionTypes(
    const MediaKeySystemConfiguration& config,
    bool safari_identity,
    WebMediaKeySystemConfiguration& web_config);

bool ParcCheckSafariEnumValues(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations,
    ExceptionState& exception_state);

struct ParcAVFoundationCheck {
  wtf_size_t configuration;
  bool video;
  wtf_size_t index;
  String content_type;
  bool hls;
};

Vector<ParcAVFoundationCheck> ParcAVFoundationChecks(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations);

void ParcApplyAVFoundationAnswers(
    const Vector<ParcAVFoundationCheck>& checks,
    const HashMap<String, bool>& answers,
    std::vector<WebMediaKeySystemConfiguration>& configurations);

class ParcAVFoundationQuery : public GarbageCollected<ParcAVFoundationQuery> {
 public:
  using DoneCallback =
      base::OnceCallback<void(const Vector<ParcAVFoundationCheck>& checks,
                              const HashMap<String, bool>& answers)>;

  static ParcAVFoundationQuery* CreateIfNeeded(
      ExecutionContext* context,
      const String& key_system,
      const HeapVector<Member<MediaKeySystemConfiguration>>&
          supported_configurations);

  virtual ~ParcAVFoundationQuery() = default;

  virtual bool Ask(ExecutionContext& context, DoneCallback done) = 0;

  virtual void Trace(Visitor* visitor) const {}
};

bool ParcRejectFairPlayPersistentLicense(
    ScriptState* script_state,
    const String& key_system,
    const WebMediaKeySystemConfiguration& configuration,
    ScriptPromiseResolver<MediaKeys>* resolver);

}

#endif

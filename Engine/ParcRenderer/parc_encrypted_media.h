// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/encryptedmedia/parc_encrypted_media.h.
// The rules requestMediaKeySystemAccess and decodingInfo apply to a
// configuration for Safari's identity and FairPlay, beside the Blink code
// that calls them at each step (MediaKeySystemAccessInitializerBase and
// navigator_request_media_key_system_access.cc).
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_

#include <vector>

#include "third_party/blink/renderer/platform/heap/collection_support/heap_vector.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/wtf/hash_map.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"
#include "third_party/blink/renderer/platform/wtf/wtf_size_t.h"

namespace blink {

class ExceptionState;
class MediaKeySystemConfiguration;
struct WebMediaKeySystemConfiguration;

// After the init data types convert: FairPlay's types only under Safari's
// identity, and with `refuse_empty_init_data_types` an empty list refused.
void ParcApplyInitDataTypeRules(const MediaKeySystemConfiguration& config,
                                bool safari_identity,
                                bool refuse_empty_init_data_types,
                                WebMediaKeySystemConfiguration& web_config);

// After the audio capabilities convert: AC-3 and E-AC-3 only under Safari's
// identity.
void ParcApplySafariOnlyAudioCodecs(bool safari_identity,
                                    WebMediaKeySystemConfiguration& web_config);

// After both capability lists convert: Safari's FairPlay content types, MP4
// only for FairPlay, and Safari's FairPlay encryption schemes.
void ParcApplyFairPlayCapabilityRules(
    const String& key_system,
    bool safari_fairplay,
    bool is_from_media_capabilities,
    WebMediaKeySystemConfiguration& web_config);

// After the session types convert: "persistent-usage-record" only under
// Safari's identity.
void ParcApplySafariOnlySessionTypes(
    const MediaKeySystemConfiguration& config,
    bool safari_identity,
    WebMediaKeySystemConfiguration& web_config);

// Under Safari's identity, MediaKeyEncryptionScheme and MediaKeySessionType
// values WebKit's IDL enums would reject throw a TypeError. Returns false
// after throwing.
bool ParcCheckSafariEnumValues(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations,
    ExceptionState& exception_state);

// One FairPlay capability AVFoundation judges under Safari's identity.
struct ParcAVFoundationCheck {
  wtf_size_t configuration;
  bool video;
  wtf_size_t index;
  String content_type;
  bool hls;  // An HLS type, else MP4 for Media Source.
};

// The HLS and MP4 capabilities of `supported_configurations` AVFoundation
// must judge, in order.
Vector<ParcAVFoundationCheck> ParcAVFoundationChecks(
    const HeapVector<Member<MediaKeySystemConfiguration>>&
        supported_configurations);

// Rewrites each checked capability of `configurations` by AVFoundation's
// answer for its content type: skipped without a yes, judged as a FairPlay
// codec of its kind for an HLS type.
void ParcApplyAVFoundationAnswers(
    const Vector<ParcAVFoundationCheck>& checks,
    const HashMap<String, bool>& answers,
    std::vector<WebMediaKeySystemConfiguration>& configurations);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_

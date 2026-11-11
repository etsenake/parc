// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/modules/encryptedmedia/parc_encrypted_media.h.
// The rules requestMediaKeySystemAccess and decodingInfo apply to a
// configuration for Safari's identity and FairPlay, beside the Blink code
// that calls them at each step (MediaKeySystemAccessInitializerBase).
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_

namespace blink {

class MediaKeySystemConfiguration;
class String;
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

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_MODULES_ENCRYPTEDMEDIA_PARC_ENCRYPTED_MEDIA_H_

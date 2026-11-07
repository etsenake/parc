// Copyright 2026 Parc contributors.
// MediaKeys as Safari has it, for documents presenting Safari's identity
// (docs/fairplay-identity.md). WebKit's MediaKeys has no getStatusForPolicy
// (Source/WebCore/Modules/encryptedmedia/MediaKeys.idl), so a page that tests
// for it there finds nothing. Chromium has it (rejecting NotSupportedError for
// FairPlay, the ContentDecryptionModule default), so this script, run in the
// main world before the page's own scripts, removes it from
// MediaKeys.prototype. Every other MediaKeys member stays. In a context that
// isn't secure there's no MediaKeys and nothing to do.
// tests/FairPlayIdentity/safari_media_keys.mjs runs this exact script.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_safari_media_keys.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_MEDIA_KEYS_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_MEDIA_KEYS_H_

namespace blink {

inline constexpr char kParcSafariMediaKeysScript[] = R"PARC_SMK_JS(
(() => {
  // Sloppy mode: a delete that can't happen fails quietly instead of
  // throwing.
  const MediaKeysInterface = globalThis.MediaKeys;
  if (typeof MediaKeysInterface !== 'function' ||
      !MediaKeysInterface.prototype) {
    return;
  }
  delete MediaKeysInterface.prototype.getStatusForPolicy;
})();
)PARC_SMK_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_SAFARI_MEDIA_KEYS_H_

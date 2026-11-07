// Copyright 2026 Parc contributors.
// WebKitMediaKeys for documents presenting Safari's identity
// (docs/fairplay-identity.md). Netflix decides that Safari can play DRM video
// with exactly `WebKitMediaKeys.isTypeSupported("com.apple.fps.2_0")`, so
// without the object it refuses before asking for a manifest. This script,
// run in the main world before the page's own scripts, adds Safari's legacy
// prefixed interface as a capability probe only:
// - `WebKitMediaKeys.isTypeSupported(keySystem, type)` answers as WebKit's
//   legacy Media Source CDM does for its key systems, `com.apple.fps.2_N` and
//   `com.apple.fps.3_N` (LegacyCDMPrivateAVFObjC), and with a type, whether
//   Parc's FairPlay path plays it: an MP4 container whose codecs are all ones
//   FairPlay's CDM lists in fairplay-media.patch (H.264, HEVC, Dolby Vision
//   profile 5, AAC, AC-3, E-AC-3) and that Media Source accepts.
//   `com.apple.fps` and `com.apple.fps.1_0` answer false: WebKit gives them to
//   its AVFoundation player (HLS with skd key requests), which Parc doesn't
//   have. Apple TV+'s MusicKit probes only `com.apple.fps.1_0`, so it stays
//   on standard EME.
// - `new WebKitMediaKeys(keySystem)` always throws, as WebKit does for a key
//   system it can't serve (InvalidAccessError for an empty one,
//   NotSupportedError otherwise): Parc has no legacy key sessions,
//   `webkitSetMediaKeys` or `webkitneedkey`. Netflix never constructs it;
//   Disney+'s native client constructs it inside a try and treats the failure
//   as before.
// tests/FairPlayIdentity/webkit_media_keys.mjs runs this exact script.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_media_keys.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_

namespace blink {

inline constexpr char kParcWebKitMediaKeysScript[] = R"PARC_WKMK_JS(
(() => {
  'use strict';
  const g = globalThis;
  if ('WebKitMediaKeys' in g) {
    return;
  }
  // Taken now: players polyfill MediaSource.isTypeSupported, and the answer
  // must stay Chromium's.
  const NativeMediaSource = g.MediaSource;
  const mediaSourceSupports = typeof NativeMediaSource === 'function' &&
      typeof NativeMediaSource.isTypeSupported === 'function' ?
      NativeMediaSource.isTypeSupported : null;

  // LegacyCDMPrivateAVFObjC::parseKeySystem.
  const MEDIA_SOURCE_KEY_SYSTEM = /^com\.apple\.fps\.[23]_\d+(?:,\d+)*$/i;
  const CONTAINER = /^\s*(?:video|audio)\/mp4\s*(?:;|$)/i;
  const CODECS_PARAMETER = /;\s*codecs\s*=\s*(?:"([^"]*)"|([^;]*))/i;
  // The codecs of FairPlay's CdmCapability (GetFairPlayCdmInfo in
  // fairplay-media.patch); Media Source then checks each one's details.
  const FAIRPLAY_CODECS = [
    /^avc[13](?:\.|$)/i,                 // H.264
    /^(?:hvc1|hev1)(?:\.|$)/i,           // HEVC
    /^(?:dvh1|dvhe)\.05(?:\.|$)/i,       // Dolby Vision profile 5
    /^mp4a\.(?:40(?:\.\d+)?|6[678])$/i,  // AAC
    /^(?:ac-3|ec-3|mp4a\.a[56])$/i,      // AC-3, E-AC-3
  ];

  // WebIDL's DOMString conversion (a Symbol throws TypeError).
  const toDOMString = (value) => `${value}`;

  function fairPlayPlays(type) {
    if (!CONTAINER.test(type)) {
      return false;
    }
    const parameter = CODECS_PARAMETER.exec(type);
    if (parameter) {
      const list = parameter[1] !== undefined ? parameter[1] : parameter[2];
      for (const codec of list.split(',')) {
        const id = codec.trim();
        if (!FAIRPLAY_CODECS.some((pattern) => pattern.test(id))) {
          return false;
        }
      }
    }
    return !!mediaSourceSupports &&
        Reflect.apply(mediaSourceSupports, NativeMediaSource, [type]) === true;
  }

  class WebKitMediaKeys {
    constructor(keySystem) {
      if (arguments.length < 1) {
        throw new TypeError("Failed to construct 'WebKitMediaKeys': " +
            '1 argument required, but only 0 present.');
      }
      if (toDOMString(keySystem) === '') {
        throw new DOMException('The keySystem is empty.', 'InvalidAccessError');
      }
      throw new DOMException('The key system is not supported.', 'NotSupportedError');
    }

    // The default makes its length 1, as for a WebIDL operation with one
    // required argument.
    static isTypeSupported(keySystem, type = undefined) {
      if (arguments.length < 1) {
        throw new TypeError("Failed to execute 'isTypeSupported' on " +
            "'WebKitMediaKeys': 1 argument required, but only 0 present.");
      }
      const system = toDOMString(keySystem);
      const contentType = type === undefined ? '' : toDOMString(type);
      if (!MEDIA_SOURCE_KEY_SYSTEM.test(system)) {
        return false;
      }
      return contentType === '' || fairPlayPlays(contentType);
    }
  }

  Object.defineProperty(g, 'WebKitMediaKeys', {
    value: WebKitMediaKeys, writable: true, enumerable: false, configurable: true,
  });
})();
)PARC_WKMK_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_

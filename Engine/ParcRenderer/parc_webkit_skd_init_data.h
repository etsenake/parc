// Copyright 2026 Parc contributors.
// WebKit's legacy init data for an HLS skd:// key request, which Safari's
// `webkitneedkey` carries (MediaPlayerPrivateAVFoundationObjC::
// shouldWaitForLoadingOfResource): the key URI's length in bytes as UTF-16 (4
// bytes, little-endian), then its UTF-16 code units, little-endian. The URI is
// the request URL's absolute string. parc_webkit_need_key.h builds it for
// every skd request the native HLS route reports.
// tests/FairPlayIdentity/webkit_need_key_main.cc checks it.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_skd_init_data.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_SKD_INIT_DATA_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_SKD_INIT_DATA_H_

#include <cstdint>
#include <string_view>
#include <vector>

namespace blink {

inline std::vector<uint8_t> ParcWebKitSkdInitData(std::u16string_view uri) {
  const uint32_t length = static_cast<uint32_t>(uri.size() * 2);
  std::vector<uint8_t> init_data;
  init_data.reserve(4 + uri.size() * 2);
  for (int shift = 0; shift < 32; shift += 8) {
    init_data.push_back(static_cast<uint8_t>(length >> shift));
  }
  for (char16_t unit : uri) {
    init_data.push_back(static_cast<uint8_t>(unit));
    init_data.push_back(static_cast<uint8_t>(unit >> 8));
  }
  return init_data;
}

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_SKD_INIT_DATA_H_

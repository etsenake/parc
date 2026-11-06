// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_KEYCHAIN_NAMESPACE_H_
#define PARC_NATIVE_KEYCHAIN_NAMESPACE_H_

#include <string_view>
#include <vector>

namespace parc {
enum class StorageNamespace { kUnset, kParc, kLegacyChromium, kInvalid };
enum class StorageKeyStatus { kFound, kMissing, kDuplicate, kError };
struct StorageKey {
  StorageKeyStatus status;
  std::vector<unsigned char> bytes;
};
inline constexpr char kParcStorageService[] = "Parc Safe Storage";
inline constexpr char kParcStorageAccount[] = "Parc";
// Separate from any previous Parc key: never overwrite an existing item's key.
inline constexpr char kParcLegacyStorageAccount[] = "Parc (Chromium compatibility)";
inline constexpr char kLegacyStorageService[] = "Chromium Safe Storage";
inline constexpr char kLegacyStorageAccount[] = "Chromium";

inline const char* StorageAccount(StorageNamespace selected) {
  return selected == StorageNamespace::kLegacyChromium
             ? kParcLegacyStorageAccount
             : kParcStorageAccount;
}
inline std::string_view StorageMarker(StorageNamespace selected) {
  return selected == StorageNamespace::kLegacyChromium ? "parc-chromium-v1\n"
                                                      : "parc-v1\n";
}
inline StorageNamespace ParseStorageMarker(std::string_view value) {
  if (value == "parc-v1\n") return StorageNamespace::kParc;
  if (value == "parc-chromium-v1\n") return StorageNamespace::kLegacyChromium;
  return StorageNamespace::kInvalid;
}

// The adapters use normal macOS Keychain authorization. Add MUST create only,
// never update an item. No key bytes are written to the profile's marker file.
// Existing ciphertext keeps exactly the same key; the legacy item stays intact.
template <typename Read, typename Add, typename Save>
StorageNamespace PrepareStorageNamespace(StorageNamespace recorded,
                                         bool existing_profile,
                                         Read read, Add add, Save save) {
  if (recorded == StorageNamespace::kLegacyChromium) {
    auto current = read(kParcStorageService, kParcLegacyStorageAccount);
    if (current.status == StorageKeyStatus::kFound && !current.bytes.empty())
      return recorded;
    if (current.status != StorageKeyStatus::kMissing)
      return StorageNamespace::kInvalid;
    // Recover a missing migrated item from the intact legacy item rather than
    // allowing Chromium to silently generate a different encryption key.
    existing_profile = true;
    recorded = StorageNamespace::kUnset;
  }
  if (recorded != StorageNamespace::kUnset) return recorded;
  auto selected = existing_profile ? StorageNamespace::kLegacyChromium
                                   : StorageNamespace::kParc;
  if (existing_profile) {
    auto legacy = read(kLegacyStorageService, kLegacyStorageAccount);
    if (legacy.status != StorageKeyStatus::kFound || legacy.bytes.empty())
      return StorageNamespace::kInvalid;
    auto current = read(kParcStorageService, StorageAccount(selected));
    if (current.status == StorageKeyStatus::kMissing) {
      auto added = add(kParcStorageService, StorageAccount(selected), legacy.bytes);
      if (added != StorageKeyStatus::kFound && added != StorageKeyStatus::kDuplicate)
        return StorageNamespace::kInvalid;
      // Re-read after creation, including a concurrent creator. Never assume
      // an existing destination item contains the legacy encryption key.
      current = read(kParcStorageService, StorageAccount(selected));
    }
    if (current.status != StorageKeyStatus::kFound || current.bytes != legacy.bytes)
      return StorageNamespace::kInvalid;
  }
  return save(StorageMarker(selected)) ? selected : StorageNamespace::kInvalid;
}
}  // namespace parc
#endif  // PARC_NATIVE_KEYCHAIN_NAMESPACE_H_

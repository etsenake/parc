#include "native_keychain_namespace.h"

#include <cassert>
#include <iostream>
#include <map>
#include <string>

using parc::StorageKey;
using parc::StorageKeyStatus;
using parc::StorageNamespace;
using Bytes = std::vector<unsigned char>;
using Item = std::pair<std::string, std::string>;
struct Fixture {
  std::map<Item, Bytes> keys;
  std::vector<Item> reads;
  std::vector<Item> adds;
  std::string marker;
  bool denied = false, add_denied = false, save_denied = false;
  bool race = false, different_race = false;
  StorageNamespace Run(bool existing = true,
                       StorageNamespace recorded = StorageNamespace::kUnset) {
    return parc::PrepareStorageNamespace(recorded, existing,
      [&](const char* service, const char* account) -> StorageKey {
        reads.emplace_back(service, account);
        if (denied) return {StorageKeyStatus::kError, {}};
        auto it = keys.find({service, account});
        return it == keys.end() ? StorageKey{StorageKeyStatus::kMissing, {}}
                               : StorageKey{StorageKeyStatus::kFound, it->second};
      },
      [&](const char* service, const char* account, const Bytes& bytes) {
        adds.emplace_back(service, account);
        if (add_denied) return StorageKeyStatus::kError;
        if (race) {
          keys.emplace(Item{service, account}, different_race ? Bytes{99} : bytes);
          return StorageKeyStatus::kDuplicate;
        }
        return keys.emplace(Item{service, account}, bytes).second
                   ? StorageKeyStatus::kFound : StorageKeyStatus::kDuplicate;
      },
      [&](std::string_view value) {
        if (save_denied) return false;
        marker = value;
        return true;
      });
  }
};
int main() {
  const Item legacy{parc::kLegacyStorageService, parc::kLegacyStorageAccount};
  const Item target{parc::kParcStorageService, parc::kParcLegacyStorageAccount};
  const Item previous_parc{parc::kParcStorageService, parc::kParcStorageAccount};
  const Bytes original{0, 1, 65, 255, 0, 42};
  {
    Fixture f;
    assert(f.Run(false) == StorageNamespace::kParc);
    assert(f.reads.empty() && f.adds.empty());
    assert(f.marker == "parc-v1\n");
  }
  {
    Fixture f; f.keys[legacy] = original; f.keys[previous_parc] = {42};
    assert(f.Run() == StorageNamespace::kLegacyChromium);
    assert(f.keys[legacy] == original && f.keys[target] == original);
    assert(f.keys[previous_parc] == Bytes{42});
    assert(f.adds.size() == 1 && f.adds.front() == target);
    assert(f.marker == "parc-chromium-v1\n");
    assert(f.marker.find(std::string(original.begin(), original.end())) == std::string::npos);
  }
  for (auto selected : {StorageNamespace::kParc, StorageNamespace::kInvalid}) {
    Fixture f; f.denied = true;
    assert(f.Run(true, selected) == selected);
    assert(f.reads.empty() && f.adds.empty() && f.marker.empty());
  }
  {
    Fixture f; f.keys[target] = original;
    assert(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kLegacyChromium);
    assert(f.reads == std::vector<Item>{target} && f.adds.empty() && f.marker.empty());
  }
  {
    Fixture f; f.keys[legacy] = original;
    assert(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kLegacyChromium);
    assert(f.keys[target] == original && f.keys[legacy] == original);
  }
  {
    Fixture f; f.denied = true;
    assert(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kInvalid);
    assert(f.adds.empty() && f.marker.empty());
  }
  {
    Fixture f; f.keys[legacy] = original; f.keys[target] = {99};
    auto before = f.keys;
    assert(f.Run() == StorageNamespace::kInvalid);
    assert(f.keys == before && f.adds.empty() && f.marker.empty());
  }
  {
    Fixture f;
    assert(f.Run() == StorageNamespace::kInvalid);
    assert(f.keys.empty() && f.adds.empty() && f.marker.empty());
  }
  {
    Fixture f; f.keys[legacy] = original; f.denied = true;
    assert(f.Run() == StorageNamespace::kInvalid);
    assert(f.adds.empty() && f.marker.empty() && f.keys[legacy] == original);
  }
  {
    Fixture f; f.keys[legacy] = original; f.add_denied = true;
    assert(f.Run() == StorageNamespace::kInvalid);
    assert(!f.keys.contains(target) && f.marker.empty());
  }
  for (bool conflict : {false, true}) {
    Fixture f; f.keys[legacy] = original; f.race = true; f.different_race = conflict;
    assert(f.Run() == (conflict ? StorageNamespace::kInvalid : StorageNamespace::kLegacyChromium));
    assert(f.keys[legacy] == original);
    assert(f.marker.empty() == conflict);
  }
  {
    Fixture f; f.keys[legacy] = original; f.save_denied = true;
    assert(f.Run() == StorageNamespace::kInvalid);
    assert(f.keys[target] == original && f.marker.empty());
    f.save_denied = false; f.adds.clear();
    assert(f.Run() == StorageNamespace::kLegacyChromium);
    assert(f.adds.empty() && f.keys[legacy] == original && f.keys[target] == original);
  }
  {
    Fixture f; f.save_denied = true;
    assert(f.Run(false) == StorageNamespace::kInvalid);
    assert(f.keys.empty() && f.marker.empty());
  }
  assert(parc::ParseStorageMarker("parc-v1\n") == StorageNamespace::kParc);
  assert(parc::ParseStorageMarker("parc-chromium-v1\n") == StorageNamespace::kLegacyChromium);
  assert(parc::ParseStorageMarker("corrupt") == StorageNamespace::kInvalid);
  assert(std::string(parc::StorageAccount(StorageNamespace::kParc)) == "Parc");
  std::cout << "Keychain namespace: fresh, legacy-byte-preserving migration, prior-Parc preservation, "
               "retry, duplicate race, denied/missing/conflicting key and marker failure checks passed\n";
}

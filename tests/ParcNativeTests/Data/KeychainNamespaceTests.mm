#import "ParcNativeTest.h"
#include "native_keychain_namespace.h"

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
static const Item legacy{parc::kLegacyStorageService, parc::kLegacyStorageAccount};
static const Item target{parc::kParcStorageService, parc::kParcLegacyStorageAccount};
static const Item previous_parc{parc::kParcStorageService, parc::kParcStorageAccount};
static const Bytes original{0, 1, 65, 255, 0, 42};

@interface KeychainNamespaceTests : ParcNativeTestCase
@end

@implementation KeychainNamespaceTests

- (void)testAFreshRootUsesTheParcNamespace {
    Fixture f;
    PARC_CHECK(f.Run(false) == StorageNamespace::kParc);
    PARC_CHECK(f.reads.empty() && f.adds.empty());
    PARC_CHECK(f.marker == "parc-v1\n");
}

- (void)testALegacyRootCopiesTheChromiumKeyWithoutTouchingOthers {
    Fixture f; f.keys[legacy] = original; f.keys[previous_parc] = {42};
    PARC_CHECK(f.Run() == StorageNamespace::kLegacyChromium);
    PARC_CHECK(f.keys[legacy] == original && f.keys[target] == original);
    PARC_CHECK(f.keys[previous_parc] == Bytes{42});
    PARC_CHECK(f.adds.size() == 1 && f.adds.front() == target);
    PARC_CHECK(f.marker == "parc-chromium-v1\n");
    PARC_CHECK(f.marker.find(std::string(original.begin(), original.end())) == std::string::npos);
}

- (void)testDeniedAccessKeepsAMarkedNamespaceWithoutReading {
  for (auto selected : {StorageNamespace::kParc, StorageNamespace::kInvalid}) {
    Fixture f; f.denied = true;
    PARC_CHECK(f.Run(true, selected) == selected);
    PARC_CHECK(f.reads.empty() && f.adds.empty() && f.marker.empty());
  }
}

- (void)testAMigratedRootReadsOnlyItsCopiedKey {
    Fixture f; f.keys[target] = original;
    PARC_CHECK(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kLegacyChromium);
    PARC_CHECK(f.reads == std::vector<Item>{target} && f.adds.empty() && f.marker.empty());
}

- (void)testAMarkedLegacyRootRepairsAMissingCopy {
    Fixture f; f.keys[legacy] = original;
    PARC_CHECK(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kLegacyChromium);
    PARC_CHECK(f.keys[target] == original && f.keys[legacy] == original);
}

- (void)testDeniedAccessFailsALegacyRoot {
    Fixture f; f.denied = true;
    PARC_CHECK(f.Run(true, StorageNamespace::kLegacyChromium) == StorageNamespace::kInvalid);
    PARC_CHECK(f.adds.empty() && f.marker.empty());
}

- (void)testAConflictingCopyIsNeverOverwritten {
    Fixture f; f.keys[legacy] = original; f.keys[target] = {99};
    auto before = f.keys;
    PARC_CHECK(f.Run() == StorageNamespace::kInvalid);
    PARC_CHECK(f.keys == before && f.adds.empty() && f.marker.empty());
}

- (void)testAMissingLegacyKeyFails {
    Fixture f;
    PARC_CHECK(f.Run() == StorageNamespace::kInvalid);
    PARC_CHECK(f.keys.empty() && f.adds.empty() && f.marker.empty());
}

- (void)testDeniedLegacyReadsChangeNothing {
    Fixture f; f.keys[legacy] = original; f.denied = true;
    PARC_CHECK(f.Run() == StorageNamespace::kInvalid);
    PARC_CHECK(f.adds.empty() && f.marker.empty() && f.keys[legacy] == original);
}

- (void)testARefusedAddWritesNoMarker {
    Fixture f; f.keys[legacy] = original; f.add_denied = true;
    PARC_CHECK(f.Run() == StorageNamespace::kInvalid);
    PARC_CHECK(!f.keys.contains(target) && f.marker.empty());
}

- (void)testADuplicateAddRaceKeepsOnlyAnIdenticalKey {
  for (bool conflict : {false, true}) {
    Fixture f; f.keys[legacy] = original; f.race = true; f.different_race = conflict;
    PARC_CHECK(f.Run() == (conflict ? StorageNamespace::kInvalid : StorageNamespace::kLegacyChromium));
    PARC_CHECK(f.keys[legacy] == original);
    PARC_CHECK(f.marker.empty() == conflict);
  }
}

- (void)testAFailedMarkerSaveRetriesWithoutAddingAgain {
    Fixture f; f.keys[legacy] = original; f.save_denied = true;
    PARC_CHECK(f.Run() == StorageNamespace::kInvalid);
    PARC_CHECK(f.keys[target] == original && f.marker.empty());
    f.save_denied = false; f.adds.clear();
    PARC_CHECK(f.Run() == StorageNamespace::kLegacyChromium);
    PARC_CHECK(f.adds.empty() && f.keys[legacy] == original && f.keys[target] == original);
}

- (void)testAFreshRootThatCannotSaveItsMarkerFails {
    Fixture f; f.save_denied = true;
    PARC_CHECK(f.Run(false) == StorageNamespace::kInvalid);
    PARC_CHECK(f.keys.empty() && f.marker.empty());
}

- (void)testMarkersAndAccountsParse {
  PARC_CHECK(parc::ParseStorageMarker("parc-v1\n") == StorageNamespace::kParc);
  PARC_CHECK(parc::ParseStorageMarker("parc-chromium-v1\n") == StorageNamespace::kLegacyChromium);
  PARC_CHECK(parc::ParseStorageMarker("corrupt") == StorageNamespace::kInvalid);
  PARC_CHECK(std::string(parc::StorageAccount(StorageNamespace::kParc)) == "Parc");
}

@end

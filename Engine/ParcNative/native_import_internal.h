// Copyright 2026 Parc contributors.
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include "base/files/file_path.h"
#import "native_appkit_bridge.h"
NS_ASSUME_NONNULL_BEGIN
namespace parc::importer {
struct SourceKey {
  SourceKey() = default;
  SourceKey(const SourceKey&) {}
  SourceKey& operator=(const SourceKey&) { return *this; }
  ~SourceKey() {
    volatile uint8_t* data = bytes.data();
    for (size_t i = 0; i < bytes.size(); ++i)
      data[i] = 0;
  }
  std::vector<uint8_t> bytes;
  bool refused = false;
};
struct Installation {
  int family;
  std::string bundle_id, name, root_relative, key_service, key_account;
  base::FilePath app_path;
  mutable SourceKey key;
  std::vector<std::pair<std::string, std::string>> key_fallbacks;
};
struct ProfileData {
  std::shared_ptr<const Installation> source;
  base::FilePath path;
  std::string identifier, name;
  NSUInteger categories = 0;
  bool restricted = false;
  uint64_t device = 0, inode = 0;
  std::vector<std::string> constraints;
  std::vector<std::pair<std::string, std::string>> extensions;
};
NSError* ImportError(NSString* message);
bool ReserveImportDestination(NSString* path, const void* owner);
void ReleaseImportDestination(NSString* path, const void* owner);
bool SourceReady(const ProfileData& source, std::string& error);
}
@interface PCNativeImportSource (Private)
- (instancetype)initWithInstallation:
    (std::shared_ptr<const parc::importer::Installation>)source;
- (std::shared_ptr<const parc::importer::Installation>)installation;
@end
@interface PCNativeImportProfile (Private)
- (instancetype)initWithData:
                    (std::shared_ptr<const parc::importer::ProfileData>)data
                      source:(PCNativeImportSource*)source;
- (std::shared_ptr<const parc::importer::ProfileData>)profileData;
@end
@interface PCNativeImportProfileResult (Private)
- (instancetype)initWithProfiles:(NSArray<PCNativeImportProfile*>*)profiles
                      restricted:(BOOL)restricted
                     constraints:(NSArray<NSString*>*)constraints
                           error:(nullable NSError*)error;
@end
@interface PCNativeImportedBookmark (Private)
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                               URL:(nullable NSURL*)url
                          children:
                              (NSArray<PCNativeImportedBookmark*>*)children;
@end
@interface PCNativeImportEvent (Private)
- (instancetype)initWithCategory:(NSUInteger)category
                           phase:(PCNativeImportPhase)phase
                           count:(NSUInteger)count
                         message:(nullable NSString*)message;
@end
@interface PCNativeImportSession (Private)
- (instancetype)initWithCancel:(void (^)(void))cancel;
@end
@interface PCNativeImportResult (Private)
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      completed:(NSUInteger)completed
                         failed:(NSUInteger)failed
                      bookmarks:(NSArray<PCNativeImportedBookmark*>*)bookmarks
             historyVisitCounts:(NSDictionary<NSString*, NSNumber*>*)historyVisitCounts
                       warnings:(NSArray<NSString*>*)warnings
                          error:(nullable NSError*)error;
@end

NS_ASSUME_NONNULL_END

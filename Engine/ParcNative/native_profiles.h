// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PROFILES_H_
#define PARC_NATIVE_NATIVE_PROFILES_H_
#import <Foundation/Foundation.h>
#include <memory>
#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
class Profile;
class ScopedProfileKeepAlive;
namespace parc {
// UI-thread operation ownership. Private operations also block parent removal;
// the window coordinator delays primary OTR retirement until they drain.
class NativeProfileLease final : public base::RefCounted<NativeProfileLease> {
 public:
  Profile* profile() const;
 private:
  friend class base::RefCounted<NativeProfileLease>;
  friend scoped_refptr<NativeProfileLease> NativeLeaseForProfile(Profile&);
  NativeProfileLease(Profile&, std::unique_ptr<ScopedProfileKeepAlive>);
  ~NativeProfileLease();
  Profile* const identity_;
  base::WeakPtr<Profile> profile_;
  const base::FilePath parent_path_;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive_;
};
using NativeProfileLeasePtr = scoped_refptr<NativeProfileLease>;
using NativeProfileCallback = base::OnceCallback<void(Profile*, NativeProfileLeasePtr, NSError*)>;
void ConfigureNativeProfiles(base::FilePath root,
    base::RepeatingCallback<void(Profile&)> initialize, base::RepeatingClosure changed);
const base::FilePath& NativeProfileRoot();
void SetNativeProfilesReady();
void SetNativeProfilesClosing(bool closing);
void ShutdownNativeProfiles();
void WithNativeProfile(NSString* path, NativeProfileCallback callback);
NativeProfileLeasePtr NativeLeaseForProfile(Profile& profile);
Profile* NativePrimaryOTRProfile(Profile& parent);
bool NativeProfilesLoading();
bool NativeProfilesHaveOperations();
bool NativeProfileHasOperations(Profile& profile);
// expected must be ProfileManager::GetProfileByPath(path), also used at release.
NSError* CheckNativeProfileRegistryRemoval(const base::FilePath&, Profile* expected);
void ReleaseNativeProfileRegistry(const base::FilePath&);
}  // namespace parc
#endif

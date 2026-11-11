// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PROFILE_POLICY_H_
#define PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

#include "base/functional/callback.h"

class PrefRegistrySimple;
class PrefService;
class Profile;
class ProfileManager;
namespace base {
class FilePath;
}
namespace parc {
void RegisterNativeProfilePrefs(PrefRegistrySimple* registry);
bool RestoreNativeSessionState();
bool NativeGaiaAccountsAllowed(PrefService* preferences);

// ProfileManager's native removal hooks. The manager reports whether a path
// still has a Profile object and whether its destruction is pending.
void OnProfileManagerCreated(
    ProfileManager& manager,
    base::RepeatingCallback<bool(const base::FilePath&)> has_profile,
    base::RepeatingCallback<bool(const base::FilePath&)> destruction_pending);
void OnProfileManagerDestroyed(ProfileManager& manager);
// A durable removal tombstone refuses the path, except for the scoped load
// that lets its own deletion run sign-out and extension cleanup.
bool NativeProfileCreationRefused(const ProfileManager& manager,
                                  const base::FilePath& path);
bool OwnsNativeProfileDiskCleanup(const ProfileManager& manager,
                                  const base::FilePath& path);
// Posts the registered cleanup once no Profile object or pending destruction
// remains. True when a native removal owns the path's cleanup.
bool RunNativeProfileDiskCleanup(ProfileManager& manager,
                                 const base::FilePath& path);
void LoadNativeProfileForDeletion(
    ProfileManager& manager,
    const base::FilePath& path,
    base::OnceCallback<void(Profile*)> callback);
}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

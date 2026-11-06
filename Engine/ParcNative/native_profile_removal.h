// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PROFILE_REMOVAL_H_
#define PARC_NATIVE_NATIVE_PROFILE_REMOVAL_H_
#import "native_appkit_bridge.h"
#include "base/files/file_path.h"
#include "base/memory/weak_ptr.h"
class Profile;
namespace parc {
// Both prepared leases and durable committed tombstones exclude new owners.
bool IsNativeProfileRemovalBlocked(const base::FilePath& path);
// Registry inspection never creates a Profile or takes a new CEF reference.
NSError* CheckNativeProfileRemovalOwners(const base::FilePath& path,
                                        base::WeakPtr<Profile>* identity);
void ReleaseNativeProfileForRemoval(const base::FilePath& path);
bool NativeProfileRemovalApplicationReady();
}
#endif

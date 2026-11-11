// Copyright 2026 Parc contributors.
// Profile creation handoff follows Chromium Embedded Framework's
// chrome_browser_context.cc, Copyright 2020 The Chromium Embedded Framework
// Authors. All rights reserved. BSD-style license: see LICENSE.
#include "native_profiles.h"
#include "native_profile_policy.h"
#include <map>
#include <utility>
#include <vector>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/values.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/prefs/session_startup_pref.h"
#include "chrome/common/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "components/signin/public/base/signin_pref_names.h"
#include "components/translate/core/browser/translate_pref_names.h"
#include "native_profile_removal.h"
#include "native_search.h"

namespace parc {
namespace {
struct Record {
  base::WeakPtr<Profile> profile;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  bool loading = true;
  NSError* failure = nil;
  std::vector<NativeProfileCallback> waiters;
};
struct Registry {
  base::FilePath root;
  std::map<base::FilePath, Record> records;
  std::map<Profile*, size_t> operations;
  std::map<base::FilePath, size_t> parent_operations;
  std::vector<base::OnceClosure> pending;
  base::RepeatingCallback<void(Profile&)> initialize;
  base::RepeatingClosure changed;
  bool ready = false;
  bool closing = false;
  bool notification_pending = false;
};
Registry& State() {
  CHECK(NSThread.isMainThread);
  static base::NoDestructor<Registry> state;
  return *state;
}
NSError* Error(NSString* message) {
  return [NSError errorWithDomain:@"org.parc.profile" code:1
      userInfo:@{NSLocalizedDescriptionKey: message}];
}
void Changed() {
  auto& state = State();
  if (!state.changed || state.notification_pending) return;
  state.notification_pending = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([] {
        auto& state = State();
        state.notification_pending = false;
        if (state.changed) state.changed.Run();
      }));
}
void Created(const base::FilePath& path, Profile* profile) {
  auto& record = State().records.at(path);
  if (!profile || profile->IsOffTheRecord() || profile->GetPath() != path ||
      record.keep_alive) return;
  record.keep_alive = ScopedProfileKeepAlive::TryAcquire(
      profile, ProfileKeepAliveOrigin::kProfileCreationFlow);
  if (record.keep_alive) record.profile = profile->GetWeakPtr();
}
void Initialized(const base::FilePath& path, Profile* profile) {
  Created(path, profile);
  auto& state = State();
  auto& record = state.records.at(path);
  if (!profile || record.profile.get() != profile || !record.keep_alive ||
      profile->ShutdownStarted()) {
    record.failure = Error(@"The browser engine could not load the requested persistent Profile.");
    record.profile.reset();
    record.keep_alive.reset();
  } else {
    // Matches the old request-context default: session cookies are not restored.
    profile->GetPrefs()->SetInteger(prefs::kRestoreOnStartup,
                                    SessionStartupPref::kPrefValueNewTab);
    InitializeNativeSearch(*profile);
    if (state.initialize) state.initialize.Run(*profile);
  }
  record.loading = false;
  auto waiters = std::move(record.waiters);
  // Acquire all deliveries before external callbacks can reenter removal.
  std::vector<NativeProfileLeasePtr> leases;
  for (size_t i = 0; i < waiters.size(); ++i)
    leases.push_back(record.failure ? nullptr : NativeLeaseForProfile(*profile));
  NSError* failure = record.failure;
  for (size_t i = 0; i < waiters.size(); ++i) {
    auto lease = std::move(leases[i]);
    Profile* live = lease ? lease->profile() : nullptr;
    std::move(waiters[i]).Run(live, std::move(lease),
        failure ?: (live ? nil : Error(@"The requested Profile is closing.")));
  }
  Changed();
}
}  // namespace

NativeProfileLease::NativeProfileLease(Profile& profile,
    std::unique_ptr<ScopedProfileKeepAlive> keep_alive)
    : identity_(&profile), profile_(profile.GetWeakPtr()),
      parent_path_(profile.GetOriginalProfile()->GetPath()),
      keep_alive_(std::move(keep_alive)) {
  ++State().operations[&profile];
  ++State().parent_operations[parent_path_];
}
NativeProfileLease::~NativeProfileLease() {
  auto& state = State();
  auto found = state.operations.find(identity_);
  if (found != state.operations.end() && !--found->second)
    state.operations.erase(found);
  auto parent = state.parent_operations.find(parent_path_);
  CHECK(parent != state.parent_operations.end());
  if (!--parent->second) state.parent_operations.erase(parent);
  keep_alive_.reset();
  Changed();
}
Profile* NativeProfileLease::profile() const {
  CHECK(NSThread.isMainThread);
  return profile_ && !State().closing && !profile_->ShutdownStarted() &&
      !IsNativeProfileRemovalBlocked(parent_path_) ? profile_.get() : nullptr;
}
void ConfigureNativeProfiles(base::FilePath root,
    base::RepeatingCallback<void(Profile&)> initialize, base::RepeatingClosure changed) {
  auto& state = State();
  CHECK(state.root.empty());
  CHECK(root.IsAbsolute());
  state.root = std::move(root);
  state.initialize = std::move(initialize);
  state.changed = std::move(changed);
}
const base::FilePath& NativeProfileRoot() { return State().root; }
void SetNativeProfilesReady() {
  auto& state = State();
  CHECK(g_browser_process && g_browser_process->profile_manager());
  CHECK_EQ(state.root, g_browser_process->profile_manager()->user_data_dir());
  state.ready = true;
  auto pending = std::move(state.pending);
  for (auto& run : pending) std::move(run).Run();
  Changed();
}
void SetNativeProfilesClosing(bool closing) {
  auto& state = State();
  state.closing = closing;
  if (closing) {
    auto pending = std::move(state.pending);
    state.pending.clear();
    for (auto& run : pending) std::move(run).Run();
    Changed();
  }
}
void WithNativeProfile(NSString* path, NativeProfileCallback callback) {
  auto& state = State();
  if (state.closing) {
    std::move(callback).Run(nullptr, nullptr, Error(@"Parc is closing this operation."));
    return;
  }
  if (!state.ready) {
    state.pending.push_back(base::BindOnce(&WithNativeProfile, [path copy], std::move(callback)));
    return;
  }
  const base::FilePath requested(base::SysNSStringToUTF8(path));
  if (!path.isAbsolutePath || ![path isEqual:path.stringByStandardizingPath] ||
      requested.DirName() != state.root || IsNativeProfileRemovalBlocked(requested)) {
    std::move(callback).Run(nullptr, nullptr, Error(@"The requested Profile is unavailable."));
    return;
  }
  auto [found, inserted] = state.records.try_emplace(requested);
  auto& record = found->second;
  if (record.failure) {
    std::move(callback).Run(nullptr, nullptr, record.failure);
  } else if (!record.loading) {
    auto lease = record.profile ? NativeLeaseForProfile(*record.profile) : nullptr;
    Profile* profile = lease ? lease->profile() : nullptr;
    std::move(callback).Run(profile, std::move(lease),
        profile ? nil : Error(@"The requested Profile is closing."));
  } else {
    record.waiters.push_back(std::move(callback));
    if (inserted) g_browser_process->profile_manager()->CreateProfileAsync(requested,
        base::BindOnce(&Initialized, requested), base::BindOnce(&Created, requested));
  }
}
NativeProfileLeasePtr NativeLeaseForProfile(Profile& profile) {
  auto& state = State();
  Profile* parent = profile.GetOriginalProfile();
  auto found = state.records.find(parent->GetPath());
  if (!state.ready || state.closing || profile.ShutdownStarted() ||
      parent->ShutdownStarted() || IsNativeProfileRemovalBlocked(parent->GetPath()) ||
      found == state.records.end() || found->second.profile.get() != parent ||
      found->second.loading || found->second.failure) return nullptr;
  auto keep_alive = ScopedProfileKeepAlive::TryAcquire(
      parent, ProfileKeepAliveOrigin::kProfileCreationFlow);
  if (!keep_alive) return nullptr;
  return base::WrapRefCounted(new NativeProfileLease(profile, std::move(keep_alive)));
}
Profile* NativePrimaryOTRProfile(Profile& parent) {
  CHECK(!parent.IsOffTheRecord());
  return NativeLeaseForProfile(parent) ? parent.GetPrimaryOTRProfile(true) : nullptr;
}
bool NativeProfilesLoading() {
  auto& state = State();
  if (!state.pending.empty()) return true;
  for (const auto& [path, record] : state.records) if (record.loading) return true;
  return false;
}
bool NativeProfilesHaveOperations() { return !State().parent_operations.empty(); }
bool NativeProfileHasOperations(Profile& profile) {
  return State().operations.contains(&profile);
}
NSError* CheckNativeProfileRegistryRemoval(const base::FilePath& path, Profile* expected) {
  auto& state = State();
  auto found = state.records.find(path);
  if (state.parent_operations.contains(path))
    return Error(@"This Profile still has a native operation in progress.");
  if (found == state.records.end())
    return expected ? Error(@"Another native owner loaded this Profile.") : nil;
  if (found->second.loading || !found->second.waiters.empty())
    return Error(@"This Profile is still being initialized.");
  if (found->second.profile.get() != expected)
    return Error(@"The native Profile identity changed.");
  return nil;
}
void ReleaseNativeProfileRegistry(const base::FilePath& path) {
  CHECK(!CheckNativeProfileRegistryRemoval(path,
      g_browser_process->profile_manager()->GetProfileByPath(path)));
  State().records.erase(path);
}
void ShutdownNativeProfiles() {
  auto& state = State();
  CHECK(!NativeProfilesLoading());
  CHECK(!NativeProfilesHaveOperations());
  state.closing = true;
  state.ready = false;
  state.records.clear();
  state.initialize.Reset();
  state.changed.Reset();
}
void RegisterNativeProfilePrefs(PrefRegistrySimple* registry) {
  RegisterNativeSearchPreferences(*registry);
  registry->SetDefaultPrefValue(prefs::kSigninAllowedOnNextStartup, base::Value(false));
  registry->SetDefaultPrefValue(prefs::kSigninAllowed, base::Value(false));
  registry->SetDefaultPrefValue(translate::prefs::kOfferTranslateEnabled, base::Value(false));
}
}  // namespace parc

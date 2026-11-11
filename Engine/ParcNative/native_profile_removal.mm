// Copyright 2026 Parc contributors.
//
// publishes model removal only after the native operation succeeds. Current
// Chromium adaptation: real DeleteProfileHelper, profile retirement, and an
// operation-bound durable receipt; no live-directory deletion or URL replay.
#import "native_profile_removal.h"

#include "native_profile_policy.h"

#include <cerrno>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <map>
#include <memory>
#include <string>
#include <utility>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/containers/span.h"
#include "base/memory/raw_ptr.h"
#include "base/feature_list.h"
#include "base/files/file.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "base/uuid.h"
#include "native_profiles.h"
#include "chrome/browser/browser_features.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/nuke_profile_directory_utils.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_attributes_storage_observer.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_manager_observer.h"
#include "chrome/browser/profiles/profiles_state.h"
#include "chrome/common/chrome_paths_internal.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"

namespace parc {
namespace {
constexpr NSInteger kUnavailable = 1;
constexpr NSInteger kProtected = 2;
constexpr NSInteger kInUse = 3;
constexpr NSInteger kCancelled = 4;
constexpr NSInteger kStorage = 5;
constexpr NSInteger kCommitted = 6;
using Completion = void (^)(PCNativeProfileRemovalState, NSError*);
NSError* RemovalError(NSInteger code, NSString* message) {
  return [NSError errorWithDomain:@"ParcProfileRemoval" code:code
                        userInfo:@{NSLocalizedDescriptionKey: message}];
}
NSString* String(const base::FilePath& path) {
  return base::SysUTF8ToNSString(path.value());
}
base::FilePath Root() {
  return NativeProfileRoot();
}
base::FilePath Journal(const base::FilePath& path) {
  return path.DirName().AppendASCII(".parc-profile-removals")
      .Append(path.BaseName().AddExtensionASCII("plist"));
}
// PathExists also returns false on access/I/O errors. Only ENOENT proves
// absence; an unreadable journal or directory never authorizes false success.
bool Absent(const base::FilePath& path) {
  struct stat info;
  return lstat(path.value().c_str(), &info) < 0 && errno == ENOENT;
}
// A fixed, native-derived location outside every profile survives cleanup.
// Completed records remain tombstones: UUID paths are never silently reused.
NSDictionary* ReadJournal(const base::FilePath& path) {
  NSData* bytes = [NSData dataWithContentsOfFile:String(Journal(path))];
  if (!bytes)
    return nil;
  id value = [NSPropertyListSerialization propertyListWithData:bytes
      options:NSPropertyListImmutable format:nil error:nil];
  return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
struct WriteResult { bool durable = false; bool published = false; };
WriteResult WriteJournal(const base::FilePath& path, std::string operation,
                         std::string protected_path, bool removed) {
  @autoreleasepool {
    const auto file = Journal(path);
    if (!base::CreateDirectory(file.DirName()) || base::IsLink(file.DirName()) ||
        base::IsLink(file))
      return {};
    NSDictionary* record = @{@"version": @1, @"operationID": base::SysUTF8ToNSString(operation),
      @"profilePath": String(path), @"protectedProfilePath": base::SysUTF8ToNSString(protected_path),
      @"state": removed ? @"removed" : @"committed"};
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:record
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data)
      return {};
    base::FilePath temporary;
    if (!base::CreateTemporaryFileInDir(file.DirName(), &temporary))
      return {};
    base::File output(temporary, base::File::FLAG_OPEN | base::File::FLAG_WRITE);
    const std::string bytes(static_cast<const char*>(data.bytes), data.length);
    const bool wrote = output.WriteAtCurrentPosAndCheck(base::as_byte_span(bytes)) && output.Flush();
    output.Close();
    if (!wrote || !base::ReplaceFile(temporary, file, nullptr)) {
      base::DeleteFile(temporary);
      return {};
    }
    // Rename is the irreversible boundary. A failed directory flush is
    // Pending, never Failed, because a committed record may survive a crash.
    const int descriptor = open(file.DirName().value().c_str(), O_RDONLY | O_DIRECTORY);
    const bool flushed = descriptor >= 0 && fsync(descriptor) == 0;
    if (descriptor >= 0)
      close(descriptor);
    const int parent = open(path.DirName().value().c_str(), O_RDONLY | O_DIRECTORY);
    const bool parent_flushed = parent >= 0 && fsync(parent) == 0;
    if (parent >= 0)
      close(parent);
    return {flushed && parent_flushed, true};
  }
}
bool ValidRecord(NSDictionary* record, const base::FilePath& path,
                 NSString* protected_path, NSString* operation) {
  return [record[@"version"] isEqual:@1] &&
      [record[@"profilePath"] isEqual:String(path)] &&
      [record[@"protectedProfilePath"] isEqual:protected_path] &&
      [record[@"operationID"] isEqual:operation] &&
      ([record[@"state"] isEqual:@"committed"] ||
       [record[@"state"] isEqual:@"removed"]);
}
NSError* Validate(NSString* path, NSString* protected_path, NSString* operation) {
  if (!NativeProfileRemovalApplicationReady())
    return RemovalError(kUnavailable, @"The browser is not ready to remove a Profile.");
  const base::FilePath root = Root();
  const base::FilePath requested(base::SysNSStringToUTF8(path));
  const base::FilePath protected_native(base::SysNSStringToUTF8(protected_path));
  const auto uuid = base::Uuid::ParseCaseInsensitive(requested.BaseName().value());
  if (!path.isAbsolutePath || ![path isEqual:path.stringByStandardizingPath] ||
      !protected_path.isAbsolutePath ||
      ![protected_path isEqual:protected_path.stringByStandardizingPath] ||
      requested.DirName() != root || protected_native.DirName() != root ||
      !uuid.is_valid() ||
      !base::Uuid::ParseCaseInsensitive(protected_native.BaseName().value()).is_valid() ||
      uuid == base::Uuid::ParseCaseInsensitive(protected_native.BaseName().value()) ||
      !base::Uuid::ParseCaseInsensitive(base::SysNSStringToUTF8(operation)).is_valid() ||
      base::IsLink(requested) || base::IsLink(root) ||
      base::IsLink(Journal(requested).DirName()) || base::IsLink(Journal(requested)))
    return RemovalError(kProtected, @"Default and unrecognized Profile paths cannot be removed.");
  base::FilePath cache;
  chrome::GetUserCacheDirectory(requested, &cache);
  if (cache == root || cache == protected_native || base::IsLink(cache))
    return RemovalError(kProtected, @"The Profile cache path is not safe to remove.");
  return nil;
}
// What ProfileManager kept for native removal: cleanups waiting for their
// Profile's destruction, and the one path a scoped cleanup load may create.
struct ManagerState {
  base::RepeatingCallback<bool(const base::FilePath&)> has_profile;
  base::RepeatingCallback<bool(const base::FilePath&)> destruction_pending;
  std::map<base::FilePath, base::OnceClosure> disk_cleanup;
  base::FilePath cleanup_load;
};
std::map<const ProfileManager*, ManagerState>& ManagerStates() {
  static base::NoDestructor<std::map<const ProfileManager*, ManagerState>>
      value;
  return *value;
}
ManagerState& StateOf(const ProfileManager& manager) {
  auto found = ManagerStates().find(&manager);
  CHECK(found != ManagerStates().end());
  return found->second;
}
void DeferNativeProfileDiskCleanup(ProfileManager& manager,
                                   const base::FilePath& path,
                                   base::OnceClosure cleanup) {
  auto& state = StateOf(manager);
  CHECK(!state.disk_cleanup.contains(path));
  state.disk_cleanup.emplace(path, std::move(cleanup));
}
class Removal;
std::map<base::FilePath, std::shared_ptr<Removal>>& Operations() {
  static base::NoDestructor<std::map<base::FilePath, std::shared_ptr<Removal>>> value;
  return *value;
}
class Removal final : public std::enable_shared_from_this<Removal>,
                      public ProfileAttributesStorageObserver,
                      public ProfileManagerObserver {
 public:
  Removal(base::FilePath path, NSString* protected_path, NSString* operation,
          base::WeakPtr<Profile> identity)
      : path_(std::move(path)), protected_path_([protected_path copy]),
        operation_([operation copy]), identity_(identity),
        had_profile_(!!identity) {}
  ~Removal() override { StopObserving(); }
  NSString* operation() const { return operation_; }
  const base::FilePath& path() const { return path_; }
  void Cancel() {
    CHECK(NSThread.isMainThread);
    if (committed_ || writing_)
      return;
    cancelled_ = true;
    EraseReservation();
  }
  void Commit(BOOL (^revalidate)(void), Completion completion) {
    CHECK(NSThread.isMainThread);
    if (committed_ || writing_) {
      completion(PCNativeProfileRemovalStatePending,
                 RemovalError(kCommitted, @"Profile removal has already started."));
      return;
    }
    if (cancelled_ || !CurrentReservation()) {
      completion(PCNativeProfileRemovalStateFailed,
                 RemovalError(kCancelled, @"Profile removal was cancelled."));
      return;
    }
    if (NSError* error = Validate(String(path_), protected_path_, operation_)) {
      Fail(completion, error);
      return;
    }
    base::WeakPtr<Profile> current;
    NSError* owners = CheckNativeProfileRemovalOwners(path_, &current);
    if (owners || current.get() != identity_.get() || (had_profile_ && !current)) {
      Fail(completion, RemovalError(kInUse, owners ? owners.localizedDescription :
                                   @"The Profile changed before removal."));
      return;
    }
    // The app durably staged metadata first. The gate checks current immutable
    // Default/Space/name/model identities, not the text field alone.
    if (!revalidate || !revalidate() || !CurrentReservation() || cancelled_) {
      Fail(completion, RemovalError(kCancelled, @"The Profile is no longer eligible for removal."));
      return;
    }
    // A synchronous gate can reenter native code. Inspect ownership once more.
    owners = CheckNativeProfileRemovalOwners(path_, &current);
    if (owners || current.get() != identity_.get()) {
      Fail(completion, RemovalError(kInUse, @"The Profile acquired a new native owner."));
      return;
    }
    completion_ = [completion copy];
    WriteCommit();
  }
  void Recover(Completion completion, bool authenticated_journal = false) {
    CHECK(NSThread.isMainThread);
    if (completion_ || writing_ || running_) {
      completion(PCNativeProfileRemovalStatePending,
                 RemovalError(kCommitted, @"Profile removal is still in progress."));
      return;
    }
    if (!committed_ && !authenticated_journal) {
      completion(PCNativeProfileRemovalStatePending,
                 RemovalError(kCommitted, @"A prepared removal still owns this Profile. Finish or cancel that confirmation first."));
      return;
    }
    committed_ = true;
    completion_ = [completion copy];
    // Reflush the authenticated record before continuing an earlier uncertain
    // directory flush. No new app consent is inferred from elapsed time.
    WriteCommit();
  }
  void OnProfileWasRemoved(const base::FilePath& path,
                           const std::u16string&) override {
    if (path != path_)
      return;
    auto self = shared_from_this();
    content::GetUIThreadTaskRunner({})->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Removal> self) {
          ReleaseNativeProfileForRemoval(self->path_);
          if (self->manager_)
            RunNativeProfileDiskCleanup(*self->manager_, self->path_);
        }, self));
  }
  void OnProfileManagerDestroying() override {
    StopObserving();
    Finish(PCNativeProfileRemovalStatePending,
           RemovalError(kCommitted, @"Removal will resume when Parc next opens."));
  }
 private:
  bool CurrentReservation() const {
    auto found = Operations().find(path_);
    return found != Operations().end() && found->second.get() == this;
  }
  void EraseReservation() {
    if (CurrentReservation())
      Operations().erase(path_);
  }
  void Fail(Completion completion, NSError* error) {
    Cancel();
    completion(PCNativeProfileRemovalStateFailed, error);
  }
  void Finish(PCNativeProfileRemovalState state, NSError* error) {
    Completion completion = completion_;
    completion_ = nil;
    if (completion)
      completion(state, error);
  }
  void StopObserving() {
    if (!manager_)
      return;
    manager_->GetProfileAttributesStorage().RemoveObserver(this);
    manager_->RemoveObserver(this);
    manager_ = nullptr;
    fallback_keep_alive_.reset();
  }
  void WriteCommit() {
    ++attempt_;
    writing_ = true;
    auto self = shared_from_this();
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
         base::TaskShutdownBehavior::CONTINUE_ON_SHUTDOWN},
        base::BindOnce(&WriteJournal, path_, base::SysNSStringToUTF8(operation_),
                       base::SysNSStringToUTF8(protected_path_), false),
        base::BindOnce([](std::shared_ptr<Removal> self, WriteResult result) {
          self->writing_ = false;
          self->committed_ = self->committed_ || result.published;
          if (!result.durable) {
            if (!self->committed_) {
              self->cancelled_ = true;
              self->EraseReservation();
            }
            self->Finish(self->committed_ ? PCNativeProfileRemovalStatePending :
                                          PCNativeProfileRemovalStateFailed,
                         RemovalError(kStorage, @"The removal record could not be saved safely."));
            return;
          }
          self->StartDeletion();
        }, self));
  }
  void StartDeletion() {
    if (!NativeProfileRemovalApplicationReady()) {
      Finish(PCNativeProfileRemovalStatePending,
             RemovalError(kCommitted, @"Removal will resume when the browser is ready."));
      return;
    }
    base::WeakPtr<Profile> current;
    if (NSError* owners = CheckNativeProfileRemovalOwners(path_, &current)) {
      Finish(PCNativeProfileRemovalStatePending, RemovalError(kCommitted, owners.localizedDescription));
      return;
    }
    auto* manager = g_browser_process->profile_manager();
    Profile* fallback = nullptr;
    for (Profile* profile : manager->GetLoadedProfiles()) {
      if (profile->GetPath() != path_ && !profile->IsOffTheRecord() &&
          !profile->IsGuestSession() && !profile->IsSystemProfile() &&
          !IsProfileDirectoryMarkedForDeletion(profile->GetPath()) &&
          !IsNativeProfileRemovalBlocked(profile->GetPath())) {
        fallback = profile;
        if ([String(profile->GetPath()) isEqual:protected_path_])
          break;
      }
    }
    if (!fallback) {
      Finish(PCNativeProfileRemovalStatePending,
             RemovalError(kCommitted, @"Open another Profile to finish this removal."));
      return;
    }
    // Force upstream's first loaded-other-profile branch. An app Default may
    // be unmaterialized; never let that cause an invented Chrome replacement.
    fallback_keep_alive_ = std::make_unique<ScopedProfileKeepAlive>(
        fallback, ProfileKeepAliveOrigin::kProfileDeletionProcess);
    profiles::SetLastUsedProfile(fallback->GetPath().BaseName());
    manager_ = manager;
    auto& storage = manager_->GetProfileAttributesStorage();
    manager_->AddObserver(this);
    storage.AddObserver(this);
    running_ = true;
    auto self = shared_from_this();
    DeferNativeProfileDiskCleanup(*manager_, path_, base::BindOnce(
        [](std::shared_ptr<Removal> self) { self->CleanDisk(); }, self));
    if (!storage.GetProfileAttributesWithPath(path_)) {
      // Never materialized, or a previous commit already removed attributes.
      // No Profile may still be loaded before direct physical cleanup.
      ReleaseNativeProfileForRemoval(path_);
      RunNativeProfileDiskCleanup(*manager_, path_);
    } else if (IsProfileDirectoryMarkedForDeletion(path_)) {
      // Upstream startup may already own polite cleanup of its durable mark.
      // Do not schedule the same deletion twice or recreate a removed Profile.
      ReleaseNativeProfileForRemoval(path_);
      RunNativeProfileDiskCleanup(*manager_, path_);
    } else {
      manager_->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(
          path_, base::BindOnce([](Profile*) {}),
          ProfileMetrics::DELETE_PROFILE_SETTINGS);
    }
    // A slow upstream keepalive or I/O failure is a recoverable committed state,
    // not permission to destroy an owner or hold app termination indefinitely.
    const uint64_t attempt = attempt_;
    content::GetUIThreadTaskRunner({})->PostDelayedTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Removal> self, uint64_t attempt) {
          if (self->attempt_ != attempt)
            return;
          self->Finish(PCNativeProfileRemovalStatePending,
              RemovalError(kCommitted, @"Removal is committed; native cleanup is still finishing."));
        }, self, attempt), base::Seconds(15));
  }
  void CleanDisk() {
    if (!manager_ || manager_->GetProfileByPath(path_) ||
        IsNativeProfileLifecyclePending(*manager_, path_)) {
      Finish(PCNativeProfileRemovalStatePending,
             RemovalError(kCommitted, @"The original Profile is still finishing retirement."));
      return;
    }
    StopObserving();
    auto self = shared_from_this();
    base::ThreadPool::PostTask(FROM_HERE,
        {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
         base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
        base::BindOnce(&NukeProfileFromDisk, path_,
            base::BindOnce([](std::shared_ptr<Removal> self) {
              self->VerifyCleanup();
            }, self)));
  }
  void VerifyCleanup() {
    auto self = shared_from_this();
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
         base::TaskShutdownBehavior::CONTINUE_ON_SHUTDOWN},
        base::BindOnce([](base::FilePath path, std::string operation,
                          std::string protected_path) {
          base::FilePath cache;
          chrome::GetUserCacheDirectory(path, &cache);
          if (!Absent(path) || !Absent(cache))
            return false;
          return WriteJournal(path, std::move(operation), std::move(protected_path), true).durable;
        }, path_, base::SysNSStringToUTF8(operation_), base::SysNSStringToUTF8(protected_path_)),
        base::BindOnce([](std::shared_ptr<Removal> self, bool removed) {
          self->running_ = false;
          self->Finish(removed ? PCNativeProfileRemovalStateRemoved : PCNativeProfileRemovalStatePending,
              removed ? nil : RemovalError(kStorage, @"Some Profile data could not be removed. Retry cleanup."));
        }, self));
  }
  const base::FilePath path_;
  NSString* __strong protected_path_;
  NSString* __strong operation_;
  base::WeakPtr<Profile> identity_;
  const bool had_profile_;
  bool cancelled_ = false;
  bool committed_ = false;
  bool writing_ = false;
  bool running_ = false;
  uint64_t attempt_ = 0;
  std::unique_ptr<ScopedProfileKeepAlive> fallback_keep_alive_;
  raw_ptr<ProfileManager> manager_ = nullptr;
  Completion __strong completion_ = nil;
};
}  // namespace
bool IsNativeProfileRemovalBlocked(const base::FilePath& path) {
  CHECK(NSThread.isMainThread);
  return Operations().contains(path) || !Absent(Journal(path));
}
bool IsNativeProfileLifecyclePending(const ProfileManager& manager,
                                     const base::FilePath& path) {
  const auto& state = StateOf(manager);
  return state.destruction_pending.Run(path) ||
         (state.has_profile.Run(path) && !manager.GetProfileByPath(path));
}
void OnProfileManagerCreated(
    ProfileManager& manager,
    base::RepeatingCallback<bool(const base::FilePath&)> has_profile,
    base::RepeatingCallback<bool(const base::FilePath&)> destruction_pending) {
  auto [it, inserted] = ManagerStates().try_emplace(&manager);
  CHECK(inserted);
  it->second.has_profile = std::move(has_profile);
  it->second.destruction_pending = std::move(destruction_pending);
}
void OnProfileManagerDestroyed(ProfileManager& manager) {
  // Out of the registry before its cleanups are destroyed.
  auto node = ManagerStates().extract(&manager);
}
bool NativeProfileCreationRefused(const ProfileManager& manager,
                                  const base::FilePath& path) {
  // Unlike Journal(path), always the manager's own root.
  return path != StateOf(manager).cleanup_load &&
         !Absent(manager.user_data_dir()
                     .AppendASCII(".parc-profile-removals")
                     .Append(path.BaseName().AddExtensionASCII("plist")));
}
bool OwnsNativeProfileDiskCleanup(const ProfileManager& manager,
                                  const base::FilePath& path) {
  return StateOf(manager).disk_cleanup.contains(path);
}
bool RunNativeProfileDiskCleanup(ProfileManager& manager,
                                 const base::FilePath& path) {
  auto& state = StateOf(manager);
  auto it = state.disk_cleanup.find(path);
  if (it == state.disk_cleanup.end())
    return false;
  if (state.has_profile.Run(path) || state.destruction_pending.Run(path))
    return true;
  auto cleanup = std::move(it->second);
  state.disk_cleanup.erase(it);
  // The observer is a SupportsUserData destructor. Finish that destruction
  // stack before the native owner starts any filesystem work.
  content::GetUIThreadTaskRunner({})->PostTask(FROM_HERE, std::move(cleanup));
  return true;
}
void LoadNativeProfileForDeletion(
    ProfileManager& manager,
    const base::FilePath& path,
    base::OnceCallback<void(Profile*)> callback) {
  auto& state = StateOf(manager);
  base::AutoReset<base::FilePath> allow_cleanup_load(
      &state.cleanup_load,
      state.disk_cleanup.contains(path) ? path : base::FilePath());
  manager.LoadProfileByPath(path, false, std::move(callback));
}
}  // namespace parc

@interface PCNativeProfileRemoval () {
  std::shared_ptr<parc::Removal> _removal;
}
- (instancetype)initWithRemoval:(std::shared_ptr<parc::Removal>)removal;
@end
@implementation PCNativeProfileRemoval
- (instancetype)initWithRemoval:(std::shared_ptr<parc::Removal>)removal {
  self = [super init];
  if (self)
    _removal = std::move(removal);
  return self;
}
- (NSString*)operationID { return _removal->operation(); }
- (NSString*)profilePath { return parc::String(_removal->path()); }
- (void)cancel { _removal->Cancel(); }
- (void)commitWithRevalidate:(BOOL (^)(void))revalidate
                completion:(void (^)(PCNativeProfileRemovalState, NSError*))completion {
  _removal->Commit(revalidate, completion);
}
@end
@implementation PCNativeBrowserApplication (ProfileRemoval)
+ (void)prepareProfileRemoval:(NSString*)path
         protectedProfilePath:(NSString*)protectedPath
                  operationID:(NSString*)operationID
                   completion:(void (^)(PCNativeProfileRemoval*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  if (NSError* error = parc::Validate(path, protectedPath, operationID)) {
    completion(nil, error);
    return;
  }
  const base::FilePath native(base::SysNSStringToUTF8(path));
  if (parc::IsNativeProfileRemovalBlocked(native)) {
    completion(nil, parc::RemovalError(parc::kCommitted,
        @"This Profile already has a removal record. Recover that operation first."));
    return;
  }
  if (!base::FeatureList::IsEnabled(features::kDestroyProfileOnBrowserClose)) {
    completion(nil, parc::RemovalError(parc::kUnavailable,
        @"Profile retirement is disabled by the current engine configuration."));
    return;
  }
  base::WeakPtr<Profile> identity;
  if (NSError* error = parc::CheckNativeProfileRemovalOwners(native, &identity)) {
    completion(nil, parc::RemovalError(parc::kInUse, error.localizedDescription));
    return;
  }
  auto removal = std::make_shared<parc::Removal>(native, protectedPath, operationID, identity);
  parc::Operations().emplace(native, removal);
  completion([[PCNativeProfileRemoval alloc] initWithRemoval:removal], nil);
}
+ (void)recoverProfileRemoval:(NSString*)path
         protectedProfilePath:(NSString*)protectedPath
                  operationID:(NSString*)operationID
                   completion:(void (^)(PCNativeProfileRemovalState, NSError*))completion {
  CHECK(NSThread.isMainThread);
  if (NSError* error = parc::Validate(path, protectedPath, operationID)) {
    // A validation error cannot prove the durable operation was uncommitted.
    completion(PCNativeProfileRemovalStatePending, error);
    return;
  }
  const base::FilePath native(base::SysNSStringToUTF8(path));
  // Consult process ownership before disk: an asynchronous commit may not yet
  // have renamed its journal. Returning Failed here would unlock the app while
  // that exact authorized write was still able to proceed.
  auto found = parc::Operations().find(native);
  if (found != parc::Operations().end()) {
    if (![found->second->operation() isEqual:operationID]) {
      completion(PCNativeProfileRemovalStatePending,
          parc::RemovalError(parc::kCommitted, @"A different operation owns this Profile."));
      return;
    }
    found->second->Recover(completion);
    return;
  }
  NSDictionary* record = parc::ReadJournal(native);
  if (!record && parc::Absent(parc::Journal(native))) {
    completion(PCNativeProfileRemovalStateFailed,
        parc::RemovalError(parc::kCancelled, @"No native removal was committed."));
    return;
  }
  if (!parc::ValidRecord(record, native, protectedPath, operationID)) {
    completion(PCNativeProfileRemovalStatePending,
        parc::RemovalError(parc::kCommitted, @"The native removal record is unreadable or does not match this operation."));
    return;
  }
  base::FilePath cache;
  chrome::GetUserCacheDirectory(native, &cache);
  auto* manager = g_browser_process->profile_manager();
  if ([record[@"state"] isEqual:@"removed"] &&
      parc::Absent(native) && parc::Absent(cache) &&
      !manager->GetProfileByPath(native) &&
      !parc::IsNativeProfileLifecyclePending(*manager, native)) {
    completion(PCNativeProfileRemovalStateRemoved, nil);
    return;
  }
  auto removal = std::make_shared<parc::Removal>(native, protectedPath, operationID,
                                                base::WeakPtr<Profile>());
  parc::Operations().emplace(native, removal);
  removal->Recover(completion, true);
}
@end

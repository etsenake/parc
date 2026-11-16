// Copyright 2026 Parc contributors.
#include <algorithm>
#include <map>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/extensions/extension_management.h"
#include "chrome/browser/extensions/webstore_install_with_prompt.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "parc/importer/parc_import.mojom.h"
#include "content/public/browser/service_process_host.h"
#include "mojo/public/cpp/bindings/remote.h"
#import "native_appkit_host.h"
#include "native_profiles.h"
#import "native_import_internal.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/management_policy.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/extension_urls.h"
#include "extensions/common/manifest.h"

@interface PCNativeImportExtensionRequest ()
@property(nonatomic, readonly) PCNativeImportProfile* source;
@property(nonatomic, readonly, copy) NSString* profilePath;
@property(nonatomic, readonly, copy) NSSet<NSString*>* extensionIDs;
@end
@implementation PCNativeImportExtensionRequest
@synthesize source = _source, profilePath = _profilePath,
            extensionIDs = _extensionIDs;
- (instancetype)initWithSource:(PCNativeImportProfile*)source
                   profilePath:(NSString*)profilePath
                  extensionIDs:(NSSet<NSString*>*)extensionIDs {
  if ((self = [super init])) {
    _source = source;
    _profilePath = [profilePath copy];
    _extensionIDs = [extensionIDs copy];
  }
  return self;
}
@end
@interface PCNativeImportExtensionFailure ()
- (instancetype)initWithIdentifier:(NSString*)identifier
                              name:(NSString*)name
                       profilePath:(NSString*)profilePath
                       restriction:(PCNativeExtensionRestriction)restriction;
@end
@implementation PCNativeImportExtensionFailure
@synthesize identifier = _identifier, name = _name, profilePath = _profilePath,
            restriction = _restriction;
- (instancetype)initWithIdentifier:(NSString*)identifier
                              name:(NSString*)name
                       profilePath:(NSString*)profilePath
                       restriction:(PCNativeExtensionRestriction)restriction {
  if ((self = [super init])) {
    _identifier = [identifier copy];
    _name = [name copy];
    _profilePath = [profilePath copy];
    _restriction = restriction;
  }
  return self;
}
@end
@interface PCNativeImportExtensionResult ()
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      installed:(NSSet<NSString*>*)installed
                     installing:(NSSet<NSString*>*)installing
                       failures:(NSArray<PCNativeImportExtensionFailure*>*)failures;
@end
@implementation PCNativeImportExtensionResult
@synthesize outcome = _outcome, installedIdentifiers = _installedIdentifiers,
            installingIdentifiers = _installingIdentifiers,
            failures = _failures;
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      installed:(NSSet<NSString*>*)installed
                     installing:(NSSet<NSString*>*)installing
                       failures:(NSArray<PCNativeImportExtensionFailure*>*)failures {
  if ((self = [super init])) {
    _outcome = outcome;
    _installedIdentifiers = [installed copy];
    _installingIdentifiers = [installing copy];
    _failures = [failures copy];
  }
  return self;
}
@end

namespace parc::importer {
namespace {
constexpr uint32_t kExtensionCategory = PCNativeImportCategoryExtensions;
NSString* const kRestrictionKey = @"PCNativeExtensionRestriction";
NSError* RestrictedError(NSString* message,
                         PCNativeExtensionRestriction restriction) {
  NSError* error = ImportError(message);
  if (restriction == PCNativeExtensionRestrictionNone)
    return error;
  NSMutableDictionary* info = [error.userInfo mutableCopy];
  info[kRestrictionKey] = @(restriction);
  return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}
PCNativeExtensionRestriction InstallRestriction(
    Profile* profile,
    const std::string& id,
    extensions::webstore_install::Result result) {
  if (result == extensions::webstore_install::BLOCKLISTED)
    return PCNativeExtensionRestrictionBlocklisted;
  if (!profile || profile->ShutdownStarted())
    return PCNativeExtensionRestrictionNone;
  if (profile->IsChild())
    return PCNativeExtensionRestrictionParentalApproval;
  auto* management =
      extensions::ExtensionManagementFactory::GetForBrowserContext(profile);
  if (!management)
    return PCNativeExtensionRestrictionNone;
  const auto mode = management->GetInstallationMode(
      id, extension_urls::GetWebstoreUpdateUrl().spec());
  return mode == extensions::ManagedInstallationMode::kBlocked ||
                 mode == extensions::ManagedInstallationMode::kRemoved
             ? PCNativeExtensionRestrictionAdministrator
             : PCNativeExtensionRestrictionNone;
}
class Batch;
std::vector<std::weak_ptr<Batch>>& LiveBatches() {
  static base::NoDestructor<std::vector<std::weak_ptr<Batch>>> batches;
  return *batches;
}
class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(std::weak_ptr<Batch> batch,
            size_t item,
            const std::string& id,
            Profile& profile,
            Callback callback)
      : WebstoreInstallWithPrompt(id,
                                  &profile,
                                  gfx::NativeWindow(),
                                  std::move(callback)),
        batch_(std::move(batch)),
        item_(item),
        profile_(profile.GetWeakPtr()) {
    set_show_post_install_ui(false);
  }
  bool CancelBeforeInstall() {
    if (installing_)
      return false;
    AbortInstall();
    return true;
  }

 protected:
  ~Installer() override = default;
  bool CheckRequestorAlive() const override;
  std::unique_ptr<extensions::InstallPromptData> CreateInstallPrompt()
      const override {
    return nullptr;
  }
  void OnManifestParsed() override;

 private:
  std::weak_ptr<Batch> batch_;
  size_t item_;
  base::WeakPtr<Profile> profile_;
  bool installing_ = false;
};
class Batch final : public ProfileObserver,
                    public std::enable_shared_from_this<Batch> {
 public:
  using Completion = void (^)(PCNativeImportExtensionResult*);
  using Failures = void (^)(NSArray<PCNativeImportExtensionFailure*>*);
  struct Group {
    std::shared_ptr<const ProfileData> source;
    NSString* __strong path;
    std::vector<std::string> ids;
    base::WeakPtr<Profile> profile;
    parc::NativeProfileLeasePtr context;
    mojo::Remote<mojom::Reader> reader;
    bool loaded = false, observing = false;
  };
  Batch(std::vector<Group> groups, Completion completion, Failures background)
      : groups_(std::move(groups)),
        completion_([completion copy]),
        background_([background copy]),
        loading_(groups_.size()) {}
  ~Batch() override { Stop(); }
  bool Reserve() {
    for (auto& group : groups_) {
      if ([reserved_ containsObject:group.path])
        continue;
      if (!ReserveImportDestination(group.path, this)) {
        Stop();
        return false;
      }
      [reserved_ addObject:group.path];
    }
    lifetime_ = shared_from_this();
    return true;
  }
  void Start() {
    if (finished_)
      return;
    auto& live = LiveBatches();
    std::erase_if(live, [](const std::weak_ptr<Batch>& batch) { return batch.expired(); });
    live.push_back(weak_from_this());
    started_ = base::TimeTicks::Now();
    ticker_.Start(FROM_HERE, base::Seconds(1),
                  base::BindRepeating(&Batch::Tick, base::Unretained(this)));
    for (size_t i = 0; i < groups_.size(); ++i)
      Load(i);
    MaybeFinish();
  }
  bool Stopped() const { return cancelled_ || finished_; }
  bool MayInstall(NSString* path, const std::string& id) const {
    if (finished_)
      return false;
    for (const auto& group : groups_)
      if (!group.loaded && [group.path isEqualToString:path] &&
          std::find(group.ids.begin(), group.ids.end(), id) != group.ids.end())
        return true;
    return std::any_of(items_.begin(), items_.end(), [&](const Item& item) {
      return item.id == id && Pending(item) &&
             [groups_[item.group].path isEqualToString:path];
    });
  }
  bool Proceed(size_t index) {
    if (Stopped() || items_[index].state != Item::kPreparing)
      return false;
    items_[index].state = Item::kInstalling;
    --preparing_;
    StartQueuedLater();
    return true;
  }
  void Cancel() {
    if (finished_ || reported_)
      return;
    cancelled_ = true;
    ticker_.Stop();
    for (size_t i = 0; i < groups_.size(); ++i)
      Loaded(i, {});
    for (auto& item : items_) {
      if (item.state == Item::kPreparing && !Abort(item))
        continue;
      if (item.state == Item::kQueued || item.state == Item::kInstalling)
        --pending_;
      if (Pending(item)) {
        item.state = Item::kDeclined;
        item.installer = nullptr;
      }
    }
    MaybeFinish();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    for (auto& item : items_) {
      if (groups_[item.group].profile.get() != profile || !Pending(item))
        continue;
      if (item.state == Item::kPreparing)
        --preparing_;
      item.state = reported_ ? Item::kDeclined : Item::kFailed;
      --pending_;
      item.installer = nullptr;
    }
    for (auto& group : groups_)
      if (group.profile.get() == profile) {
        group.profile.reset();
        group.observing = false;
      }
    StartQueued();
    MaybeFinish();
  }

 private:
  struct Item {
    enum State {
      kQueued,
      kPreparing,
      kInstalling,
      kDeclined,
      kInstalled,
      kFailed
    };
    size_t group;
    std::string id, name;
    State state = kQueued;
    PCNativeExtensionRestriction restriction = PCNativeExtensionRestrictionNone;
    scoped_refptr<Installer> installer;
    base::TimeTicks started;
    bool background = false, elsewhere = false;
  };
  static bool Pending(const Item& item) {
    return item.state == Item::kQueued || item.state == Item::kPreparing ||
           item.state == Item::kInstalling;
  }
  bool Abort(Item& item) {
    if (!item.installer || !item.installer->CancelBeforeInstall())
      return false;
    item.installer = nullptr;
    --pending_;
    --preparing_;
    return true;
  }
  void Load(size_t index) {
    WithNativeProfile(
        groups_[index].path,
        base::BindOnce(
            [](std::weak_ptr<Batch> weak, size_t index, Profile* profile,
               parc::NativeProfileLeasePtr context, NSError* error) {
              auto self = weak.lock();
              if (!self || self->finished_ || self->groups_[index].loaded)
                return;
              auto& group = self->groups_[index];
              if (self->cancelled_ || error || !profile || !context ||
                  profile->IsOffTheRecord() || profile->ShutdownStarted()) {
                self->Loaded(index, {});
                return;
              }
              group.profile = profile->GetWeakPtr();
              group.context = context;
              group.observing = true;
              if (std::none_of(self->groups_.begin(), self->groups_.end(),
                               [&](const Group& other) {
                                 return &other != &group && other.observing &&
                                        other.profile.get() == profile;
                               }))
                profile->AddObserver(self.get());
              self->Read(index);
            },
            weak_from_this(), index));
  }
  void Read(size_t index) {
    auto& group = groups_[index];
    std::string error;
    if (!SourceReady(*group.source, error)) {
      Loaded(index, {});
      return;
    }
    content::ServiceProcessHost::Launch(
        group.reader.BindNewPipeAndPassReceiver(),
        content::ServiceProcessHost::Options()
            .WithDisplayName("Browser data import")
            .Pass());
    group.reader.set_disconnect_handler(base::BindOnce(
        [](std::weak_ptr<Batch> weak, size_t index) {
          if (auto self = weak.lock())
            self->Loaded(index, {});
        },
        weak_from_this(), index));
    auto source = mojom::Source::New();
    source->family = static_cast<mojom::Family>(group.source->source->family);
    source->profile_path = group.source->path.value();
    source->app_path = group.source->source->app_path.value();
    source->extension_ids = group.ids;
    group.reader->ReadCategory(
        std::move(source), kExtensionCategory,
        base::BindOnce(
            [](std::weak_ptr<Batch> weak, size_t index, mojom::BatchPtr batch) {
              auto self = weak.lock();
              if (!self)
                return;
              std::vector<mojom::ExtensionPtr> extensions;
              if (batch && batch->success &&
                  batch->category == kExtensionCategory)
                extensions = std::move(batch->extensions);
              self->Loaded(index, std::move(extensions));
            },
            weak_from_this(), index));
  }
  void Loaded(size_t index, std::vector<mojom::ExtensionPtr> extensions) {
    auto& group = groups_[index];
    if (finished_ || group.loaded)
      return;
    group.loaded = true;
    group.reader.reset();
    std::set<std::string> confirmed;
    for (const auto& extension : extensions)
      confirmed.insert(extension->id);
    for (const auto& id : group.ids) {
      std::string name = id;
      for (const auto& pair : group.source->extensions)
        if (pair.first == id)
          name = pair.second;
      items_.push_back({index, id, name});
      auto& item = items_.back();
      if (cancelled_) {
        item.state = Item::kDeclined;
      } else if (!confirmed.contains(id) || !group.profile ||
                 group.profile->ShutdownStarted() || group.profile->IsChild()) {
        item.state = Item::kFailed;
        item.restriction = InstallRestriction(
            group.profile.get(), id, extensions::webstore_install::OTHER_ERROR);
      } else if (extensions::ExtensionRegistry::Get(group.profile.get())
                     ->enabled_extensions()
                     .Contains(id)) {
        item.state = Item::kInstalled;
      } else {
        ++pending_;
      }
    }
    --loading_;
    StartQueued();
    MaybeFinish();
  }
  void StartQueued() {
    for (size_t index = 0; index < items_.size() && preparing_ < 4; ++index) {
      auto& item = items_[index];
      if (Stopped() || item.state != Item::kQueued)
        continue;
      auto& profile = groups_[item.group].profile;
      if (profile && !profile->ShutdownStarted()) {
        Install(index);
      } else {
        item.state = Item::kFailed;
        --pending_;
      }
    }
  }
  void StartQueuedLater() {
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::weak_ptr<Batch> weak) {
                         if (auto self = weak.lock()) {
                           self->StartQueued();
                           self->MaybeFinish();
                         }
                       },
                       weak_from_this()));
  }
  void Install(size_t index) {
    auto& item = items_[index];
    item.state = Item::kPreparing;
    item.started = base::TimeTicks::Now();
    ++preparing_;
    item.installer = base::MakeRefCounted<Installer>(
        weak_from_this(), index, item.id, *groups_[item.group].profile,
        base::BindOnce(
            [](std::weak_ptr<Batch> weak, size_t index, bool success,
               const std::string&, extensions::webstore_install::Result result) {
              if (auto self = weak.lock())
                self->Installed(index, success, result);
            },
            weak_from_this(), index));
    item.installer->BeginInstall();
  }
  void Installed(size_t index,
                 bool success,
                 extensions::webstore_install::Result result) {
    auto& item = items_[index];
    if (Pending(item)) {
      if (item.state == Item::kPreparing) {
        --preparing_;
        StartQueuedLater();
      }
      item.elsewhere = result == extensions::webstore_install::INSTALL_IN_PROGRESS;
      item.state = success          ? Item::kInstalled
                   : item.elsewhere ? Item::kDeclined
                                    : Item::kFailed;
      if (item.state == Item::kFailed)
        item.restriction = InstallRestriction(
            groups_[item.group].profile.get(), item.id, result);
      --pending_;
    }
    item.installer = nullptr;
    MaybeFinish();
  }
  void Tick() {
    const auto now = base::TimeTicks::Now();
    if (now - started_ > base::Seconds(30))
      for (size_t i = 0; i < groups_.size(); ++i)
        Loaded(i, {});
    for (auto& item : items_)
      if (item.state == Item::kPreparing && now - item.started > base::Seconds(30) &&
          Abort(item))
        item.state = Item::kFailed;
    StartQueued();
    MaybeFinish();
  }
  void MaybeFinish() {
    if (finished_ || loading_)
      return;
    if (!reported_ &&
        std::none_of(items_.begin(), items_.end(), [](const Item& item) {
          return item.state == Item::kQueued || item.state == Item::kPreparing;
        }))
      Report();
    if (!pending_)
      Finish();
  }
  void Report() {
    reported_ = true;
    ticker_.Stop();
    ReleaseDestinations();
    NSMutableSet<NSString*>* installed = [NSMutableSet set];
    NSMutableSet<NSString*>* installing = [NSMutableSet set];
    NSMutableArray<PCNativeImportExtensionFailure*>* failed = [NSMutableArray array];
    for (auto& item : items_) {
      if (item.state == Item::kInstalled)
        [installed addObject:base::SysUTF8ToNSString(item.id)];
      else if (item.state == Item::kInstalling || item.elsewhere)
        [installing addObject:base::SysUTF8ToNSString(item.id)];
      else if (item.state == Item::kFailed)
        [failed addObject:Failure(item)];
      item.background = item.state == Item::kInstalling;
    }
    if (cancelled_)
      [failed removeAllObjects];
    const PCNativeImportOutcome outcome =
        cancelled_        ? PCNativeImportOutcomeCancelled
        : !failed.count   ? PCNativeImportOutcomeCompleted
        : installed.count || installing.count ? PCNativeImportOutcomePartial
                                              : PCNativeImportOutcomeFailed;
    auto result =
        [[PCNativeImportExtensionResult alloc] initWithOutcome:outcome
                                                     installed:installed
                                                    installing:installing
                                                      failures:failed];
    auto completion = completion_;
    completion_ = nil;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](PCNativeImportExtensionResult* result,
                          Completion completion) {
                         if (completion)
                           completion(result);
                       },
                       result, completion));
  }
  void Finish() {
    auto keep = shared_from_this();
    finished_ = true;
    NSMutableArray<PCNativeImportExtensionFailure*>* failed = [NSMutableArray array];
    for (const auto& item : items_)
      if (item.background && item.state == Item::kFailed)
        [failed addObject:Failure(item)];
    Failures background = nil;
    if (failed.count)
      background = background_;
    background_ = nil;
    Stop();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::shared_ptr<Batch> self,
                          NSArray<PCNativeImportExtensionFailure*>* failed,
                          Failures background) {
                         self->lifetime_.reset();
                         if (background)
                           background(failed);
                       },
                       keep, failed, background));
  }
  PCNativeImportExtensionFailure* Failure(const Item& item) const {
    return [[PCNativeImportExtensionFailure alloc]
        initWithIdentifier:base::SysUTF8ToNSString(item.id)
                      name:base::SysUTF8ToNSString(item.name)
               profilePath:groups_[item.group].path
               restriction:item.restriction];
  }
  void ReleaseDestinations() {
    for (NSString* path in reserved_)
      ReleaseImportDestination(path, this);
    [reserved_ removeAllObjects];
  }
  void Stop() {
    ticker_.Stop();
    for (auto& group : groups_) {
      group.reader.reset();
      if (group.profile && group.observing)
        group.profile->RemoveObserver(this);
      group.observing = false;
      group.profile.reset();
      group.context = nullptr;
    }
    ReleaseDestinations();
  }
  std::vector<Group> groups_;
  std::vector<Item> items_;
  NSMutableArray<NSString*>* __strong reserved_ = [NSMutableArray array];
  Completion __strong completion_;
  Failures __strong background_;
  std::shared_ptr<Batch> lifetime_;
  base::RepeatingTimer ticker_;
  base::TimeTicks started_;
  size_t loading_, pending_ = 0, preparing_ = 0;
  bool cancelled_ = false, reported_ = false, finished_ = false;
};
bool Installer::CheckRequestorAlive() const {
  auto batch = batch_.lock();
  return batch && (installing_ || !batch->Stopped()) && profile_ &&
         !profile_->ShutdownStarted();
}
void Installer::OnManifestParsed() {
  auto batch = batch_.lock();
  if (!batch || !batch->Proceed(item_)) {
    CompleteInstall(extensions::webstore_install::ABORTED, std::string());
    return;
  }
  installing_ = true;
  ProceedWithInstallPrompt();
}
bool ImportMayInstall(NSString* path, const std::string& id) {
  return std::any_of(LiveBatches().begin(), LiveBatches().end(),
                     [&](const std::weak_ptr<Batch>& weak) {
                       auto batch = weak.lock();
                       return batch && batch->MayInstall(path, id);
                     });
}
}
}

@implementation PCNativeBrowserApplication (ImportedExtensions)
+ (PCNativeImportSession*)installImportedExtensions:
                              (NSArray<PCNativeImportExtensionRequest*>*)requests
                                         completion:
                                             (void (^)(PCNativeImportExtensionResult*))
                                                 completion
                                 backgroundFailures:
                                     (void (^)(NSArray<PCNativeImportExtensionFailure*>*))
                                         backgroundFailures {
  CHECK(NSThread.isMainThread);
  if (!requests.count || !completion || !backgroundFailures)
    return nil;
  std::vector<parc::importer::Batch::Group> groups;
  std::map<std::string, std::set<std::string>> requested;
  for (PCNativeImportExtensionRequest* request in requests) {
    auto data = [request.source profileData];
    NSString* path = request.profilePath;
    if (!data || !path.isAbsolutePath ||
        ![path isEqual:path.stringByStandardizingPath] ||
        !request.extensionIDs.count)
      return nil;
    std::set<std::string> eligible;
    for (const auto& pair : data->extensions)
      eligible.insert(pair.first);
    parc::importer::Batch::Group group;
    group.source = data;
    group.path = path;
    auto& destination = requested[base::SysNSStringToUTF8(path)];
    for (NSString* id in request.extensionIDs) {
      const auto value = base::SysNSStringToUTF8(id);
      if (!eligible.contains(value))
        return nil;
      if (destination.insert(value).second)
        group.ids.push_back(value);
    }
    std::sort(group.ids.begin(), group.ids.end());
    if (!group.ids.empty())
      groups.push_back(std::move(group));
  }
  auto batch =
      std::make_shared<parc::importer::Batch>(std::move(groups), completion,
                                              backgroundFailures);
  if (!batch->Reserve())
    return nil;
  auto lease = [[PCNativeImportSession alloc] initWithCancel:^{
    batch->Cancel();
  }];
  dispatch_async(dispatch_get_main_queue(), ^{
    batch->Start();
  });
  return lease;
}
@end

namespace parc::setup_extension {
namespace {
constexpr char kICloudPasswordsID[] = "pejdijmoenmkgeppbflobdenhhabjlaj";
constexpr char kUBlockOriginID[] = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
constexpr char kUBlockOriginLiteID[] = "ddkjiahejlhfcafbddmgiahcphecmpfh";
constexpr const char* kAdBlockerIDs[] = {
    "cfhdojbkjhnklbpkdaibdccddilifddb", "aemffjkmgcepimloclpkecifcnipnodh",
    "mlomiejdfkolichcflejclcbmpeaniij", "pkehgijcmpdhfbdbbnkijodmdjhbjlgp",
    "cjpalhdlnbpafiamejdnhcphjbkeiagm", "ddkjiahejlhfcafbddmgiahcphecmpfh",
    "bgnkhhnnamicmpeenaelnjfhikgbkllg", "gighmmpiobklfepjocnamgkkbiglidom",
    "ohahllgiabjaoigichmmfljhkcfikeof", "lgblnfidahcdcjddiepkckcfdhpknnjh",
    "bkkbcggnhapdmkeljlodobbkopceiche", "pmekfefnodgilnnjcfkkdjlebokonhpm",
    "gekdekpbfehejjiecgonmgmepbdnaggp", "ggdpplfehdighdpleoegjefnpefgpgfh",
    "onomjaelhagjjojbkcafidnepbfkpnee", "ojjjflcdgjegkdcojbahlbgeiinpbfgf",
    "jhkhlgaomejplkanglolfpcmfknnomle", "gekoepiplklhniacchbbgbhilidiojmb",
    "amgmhmoikcefmalfmbpkpnnpebhmhfnd"};
constexpr base::TimeDelta kRemovalWait = base::Minutes(10);

class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(const std::string& id, Profile& profile, Callback callback)
      : WebstoreInstallWithPrompt(id, &profile, gfx::NativeWindow(),
                                  std::move(callback)),
        profile_(profile.GetWeakPtr()) {
    set_show_post_install_ui(false);
  }
 protected:
  ~Installer() override = default;
  bool CheckRequestorAlive() const override {
    return profile_ && !profile_->ShutdownStarted();
  }
  std::unique_ptr<extensions::InstallPromptData> CreateInstallPrompt() const override {
    return nullptr;
  }

 private:
  base::WeakPtr<Profile> profile_;
};

class Session final : public std::enable_shared_from_this<Session> {
 public:
  Session(NSString* path, std::vector<std::string> candidates, NSString* failure,
          void (^completion)(NSError*))
      : path_([path copy]), candidates_(std::move(candidates)),
        failure_([failure copy]), completion_([completion copy]) {}

  void Start() {
    lifetime_ = shared_from_this();
    auto weak = weak_from_this();
    WithNativeProfile(path_, base::BindOnce(
        [](std::weak_ptr<Session> weak, Profile* profile,
           parc::NativeProfileLeasePtr context, NSError* error) {
          auto self = weak.lock();
          if (!self || self->finished_) return;
          if (error || !profile || !context || profile->IsOffTheRecord() ||
              profile->ShutdownStarted()) {
            self->Finish(error ?: importer::ImportError(@"The selected Profile is unavailable."));
            return;
          }
          if (profile->IsChild()) {
            self->Finish(importer::RestrictedError(
                @"This Profile requires parental approval to install extensions.",
                PCNativeExtensionRestrictionParentalApproval));
            return;
          }
          self->context_ = context;
          self->profile_ = profile->GetWeakPtr();
          self->Next();
        }, weak));
  }

 private:
  void Next() {
    if (finished_) return;
    if (!profile_ || profile_->ShutdownStarted()) {
      Finish(importer::ImportError(@"The selected Profile is unavailable."));
      return;
    }
    auto* registry = extensions::ExtensionRegistry::Get(profile_.get());
    if (std::any_of(candidates_.begin(), candidates_.end(), [&](const std::string& id) {
          return registry->enabled_extensions().Contains(id);
        })) {
      std::u16string ignored;
      for (const auto& id : disabled_)
        if (registry->disabled_extensions().Contains(id))
          extensions::ExtensionRegistrar::Get(profile_.get())->UninstallExtension(
              id, extensions::UNINSTALL_REASON_INTERNAL_MANAGEMENT, &ignored);
      Finish(nil);
      return;
    }
    if (next_ == candidates_.size()) {
      Finish(importer::RestrictedError(error_.localizedDescription ?: failure_, restriction_));
      return;
    }
    error_ = nil;
    const auto id = candidates_[next_++];
    const bool existed = registry->GetInstalledExtension(id) != nullptr;
    installer_ = base::MakeRefCounted<Installer>(id, *profile_,
        base::BindOnce([](std::weak_ptr<Session> weak, std::string id, bool existed, bool success,
                          const std::string& message, extensions::webstore_install::Result result) {
          auto self = weak.lock();
          if (!self) return;
          if (success && !existed && self->profile_ &&
              !extensions::ExtensionRegistry::Get(self->profile_.get())->enabled_extensions().Contains(id))
            self->disabled_.push_back(id);
          if (!success && !message.empty())
            self->error_ = importer::ImportError(base::SysUTF8ToNSString(message));
          if (!success) {
            const auto restriction = importer::InstallRestriction(self->profile_.get(), id, result);
            self->restriction_ = self->failures_++ == 0 || self->restriction_ == restriction
                                     ? restriction
                                     : PCNativeExtensionRestrictionNone;
          }
          base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
              base::BindOnce([](std::shared_ptr<Session> self) {
                self->installer_ = nullptr;
                self->Next();
              }, self));
        }, weak_from_this(), id, existed));
    installer_->BeginInstall();
  }
  void Finish(NSError* error) {
    if (finished_) return;
    finished_ = true;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Session> self, NSError* error) {
          self->installer_ = nullptr; self->context_ = nullptr;
          auto completion = self->completion_; self->completion_ = nil;
          self->lifetime_.reset();
          completion(error);
        }, shared_from_this(), error));
  }
  NSString* __strong path_;
  std::vector<std::string> candidates_, disabled_;
  size_t next_ = 0;
  NSString* __strong failure_;
  NSError* __strong error_;
  PCNativeExtensionRestriction restriction_ = PCNativeExtensionRestrictionNone;
  size_t failures_ = 0;
  void (^completion_)(NSError*);
  parc::NativeProfileLeasePtr context_;
  base::WeakPtr<Profile> profile_;
  scoped_refptr<Installer> installer_;
  std::shared_ptr<Session> lifetime_;
  bool finished_ = false;
};

void StartSession(NSString* path, std::vector<std::string> candidates,
                  NSString* failure, void (^completion)(NSError*)) {
  auto session = std::make_shared<Session>(path, std::move(candidates), failure, completion);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&Session::Start, std::move(session)));
}

class Removal final : public extensions::ExtensionRegistryObserver,
                      public ProfileObserver,
                      public std::enable_shared_from_this<Removal> {
 public:
  Removal(NSString* path, std::set<std::string> ids, void (^completion)(NSError*))
      : path_([path copy]), waiting_(std::move(ids)), completion_([completion copy]) {}
  ~Removal() override { Stop(); }

  void Start() {
    lifetime_ = shared_from_this();
    WithNativeProfile(path_, base::BindOnce(
        [](std::weak_ptr<Removal> weak, Profile* profile,
           parc::NativeProfileLeasePtr context, NSError* error) {
          auto self = weak.lock();
          if (!self || self->finished_) return;
          if (error || !profile || !context || profile->IsOffTheRecord() ||
              profile->ShutdownStarted()) {
            self->Finish(error ?: importer::ImportError(@"The selected Profile is unavailable."));
            return;
          }
          self->context_ = context;
          self->profile_ = profile->GetWeakPtr();
          profile->AddObserver(self.get());
          self->registry_.Observe(extensions::ExtensionRegistry::Get(profile));
          for (const auto& id : self->waiting_) self->Remove(id);
          self->Poll();
          if (self->finished_) return;
          self->poll_.Start(FROM_HERE, base::Seconds(5),
              base::BindRepeating(&Removal::Poll, base::Unretained(self.get())));
          self->timer_.Start(FROM_HERE, kRemovalWait,
              base::BindOnce(&Removal::Expire, base::Unretained(self.get())));
        }, weak_from_this()));
  }
  void OnExtensionInstalled(content::BrowserContext*,
                            const extensions::Extension* extension,
                            bool) override {
    if (finished_ || !waiting_.erase(extension->id())) return;
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::weak_ptr<Removal> weak, std::string id) {
          auto self = weak.lock();
          if (!self || self->finished_) return;
          self->Remove(id);
          self->Poll();
        }, weak_from_this(), extension->id()));
  }
  void OnProfileWillBeDestroyed(Profile*) override {
    Stop();
    Finish(importer::ImportError(@"The selected Profile is unavailable."));
  }

 private:
  void Poll() {
    if (finished_) return;
    std::erase_if(waiting_, [&](const std::string& id) {
      return !importer::ImportMayInstall(path_, id);
    });
    if (waiting_.empty()) Finish(error_);
  }
  void Remove(const std::string& id) {
    if (!profile_ || profile_->ShutdownStarted()) {
      error_ = importer::ImportError(@"The selected Profile is unavailable.");
      return;
    }
    const extensions::Extension* extension =
        extensions::ExtensionRegistry::Get(profile_.get())->GetInstalledExtension(id);
    if (!extension) return;
    if (extensions::Manifest::IsPolicyLocation(extension->location())) {
      error_ = importer::RestrictedError(@"Your administrator keeps this ad blocker installed.",
                                         PCNativeExtensionRestrictionAdministrator);
      return;
    }
    if (extensions::Manifest::IsExternalLocation(extension->location())) {
      error_ = importer::RestrictedError(@"An ad blocker installed by another app can't be removed here.",
                                         PCNativeExtensionRestrictionOtherApp);
      return;
    }
    auto* policy = extensions::ExtensionSystem::Get(profile_.get())->management_policy();
    std::u16string message;
    NSString* fallback = @"An imported ad blocker could not be removed.";
    if (!policy->UserMayModifySettings(extension, &message) ||
        policy->MustRemainInstalled(extension, &message)) {
      error_ = importer::RestrictedError(
          message.empty() ? fallback : base::SysUTF16ToNSString(message),
          PCNativeExtensionRestrictionAdministrator);
    } else if (!extensions::ExtensionRegistrar::Get(profile_.get())->UninstallExtension(
                   id, extensions::UNINSTALL_REASON_INTERNAL_MANAGEMENT, &message)) {
      error_ = importer::ImportError(message.empty() ? fallback : base::SysUTF16ToNSString(message));
    }
  }
  void Expire() {
    Finish(error_ ?: importer::ImportError(
        @"An imported ad blocker was still being added and could not be removed."));
  }
  void Stop() {
    timer_.Stop();
    poll_.Stop();
    registry_.Reset();
    if (profile_) profile_->RemoveObserver(this);
    profile_.reset();
  }
  void Finish(NSError* error) {
    if (finished_) return;
    finished_ = true;
    Stop();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Removal> self, NSError* error) {
          self->context_ = nullptr;
          auto completion = self->completion_; self->completion_ = nil;
          self->lifetime_.reset();
          completion(error);
        }, shared_from_this(), error));
  }
  NSString* __strong path_;
  std::set<std::string> waiting_;
  void (^completion_)(NSError*);
  NSError* __strong error_;
  parc::NativeProfileLeasePtr context_;
  base::WeakPtr<Profile> profile_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_{this};
  base::OneShotTimer timer_;
  base::RepeatingTimer poll_;
  std::shared_ptr<Removal> lifetime_;
  bool finished_ = false;
};
}
}

@implementation PCNativeBrowserApplication (SetupPasswordExtension)
+ (void)installICloudPasswordsExtensionToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError*))completion {
  parc::setup_extension::StartSession(profilePath,
      {parc::setup_extension::kICloudPasswordsID},
      @"The selected iCloud Passwords extension could not be installed.", completion);
}
+ (void)installSetupAdBlockerToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError*))completion {
  parc::setup_extension::StartSession(profilePath,
      {parc::setup_extension::kUBlockOriginID, parc::setup_extension::kUBlockOriginLiteID},
      @"uBlock Origin could not be installed.", completion);
}
+ (void)removeSetupAdBlockers:(NSSet<NSString*>*)extensionIDs
    fromProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError*))completion {
  std::set<std::string> ids;
  for (NSString* id in extensionIDs)
    ids.insert(base::SysNSStringToUTF8(id));
  if (!profilePath.isAbsolutePath || ![profilePath isEqual:profilePath.stringByStandardizingPath] ||
      !std::all_of(ids.begin(), ids.end(), [](const std::string& value) {
        return std::any_of(std::begin(parc::setup_extension::kAdBlockerIDs),
                           std::end(parc::setup_extension::kAdBlockerIDs),
                           [&](const char* known) { return value == known; });
      })) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(parc::importer::ImportError(@"Only known ad blockers can be removed."));
    });
    return;
  }
  auto removal = std::make_shared<parc::setup_extension::Removal>(profilePath, std::move(ids), completion);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::setup_extension::Removal::Start, std::move(removal)));
}
+ (PCNativeExtensionRestriction)extensionRestrictionForError:(NSError*)error {
  id raw = error.userInfo[parc::importer::kRestrictionKey];
  NSNumber* value = [raw isKindOfClass:[NSNumber class]] ? raw : nil;
  if (!value || value.integerValue <= PCNativeExtensionRestrictionNone ||
      value.integerValue > PCNativeExtensionRestrictionBlocklisted)
    return PCNativeExtensionRestrictionNone;
  return static_cast<PCNativeExtensionRestriction>(value.integerValue);
}
@end

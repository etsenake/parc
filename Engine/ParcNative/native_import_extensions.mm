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
@interface PCNativeImportExtensionResult ()
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      installed:(NSSet<NSString*>*)installed
                     installing:(NSSet<NSString*>*)installing
                         failed:(NSArray<NSString*>*)failed;
@end
@implementation PCNativeImportExtensionResult
@synthesize outcome = _outcome, installedIdentifiers = _installedIdentifiers,
            installingIdentifiers = _installingIdentifiers,
            failedNames = _failedNames;
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      installed:(NSSet<NSString*>*)installed
                     installing:(NSSet<NSString*>*)installing
                         failed:(NSArray<NSString*>*)failed {
  if ((self = [super init])) {
    _outcome = outcome;
    _installedIdentifiers = [installed copy];
    _installingIdentifiers = [installing copy];
    _failedNames = [failed copy];
  }
  return self;
}
@end

namespace parc::importer {
namespace {
constexpr uint32_t kExtensionCategory = PCNativeImportCategoryExtensions;
class Batch;
// Imports that may still be installing extensions; main thread only.
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
  // False once Chromium is installing; its real result follows.
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
// Every request's extensions are read back from their source, then installed
// side by side; one failure never stops the others.
class Batch final : public ProfileObserver,
                    public std::enable_shared_from_this<Batch> {
 public:
  using Completion = void (^)(PCNativeImportExtensionResult*);
  using Failures = void (^)(NSArray<NSString*>*);
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
  // Whether this import may still install `id` into the Profile at `path`.
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
  // The Web Store answered; past this point Chromium owns the install.
  bool Proceed(size_t index) {
    if (Stopped() || items_[index].state != Item::kPreparing)
      return false;
    items_[index].state = Item::kInstalling;
    --preparing_;
    StartQueuedLater();
    return true;
  }
  // Stop reaches only lookups; downloads Chromium already owns carry on.
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
  // The installer observes its Profile and aborts itself; only that Profile's
  // extensions fail. Our reference goes first so the installer can't outlive
  // the Profile.
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    for (auto& item : items_) {
      if (groups_[item.group].profile.get() != profile || !Pending(item))
        continue;
      if (item.state == Item::kPreparing)
        --preparing_;
      // A Profile removed after the results has nothing left to report.
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
    scoped_refptr<Installer> installer;
    base::TimeTicks started;
    bool background = false, elsewhere = false;
  };
  static bool Pending(const Item& item) {
    return item.state == Item::kQueued || item.state == Item::kPreparing ||
           item.state == Item::kInstalling;
  }
  // Released with its abort so that no late callback can reach it.
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
  // The reader confirms each selection is still the source's own Web Store
  // extension, as it did when extensions imported with the profile.
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
      // A supervised Profile's parent approval can't come from an import.
      if (cancelled_) {
        item.state = Item::kDeclined;
      } else if (!confirmed.contains(id) || !group.profile ||
                 group.profile->ShutdownStarted() || group.profile->IsChild()) {
        item.state = Item::kFailed;
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
  // A few Web Store requests at a time, each with its own time limit.
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
  // Runs inside Chromium's completion, which still holds its own reference.
  void Installed(size_t index,
                 bool success,
                 extensions::webstore_install::Result result) {
    auto& item = items_[index];
    if (Pending(item)) {
      if (item.state == Item::kPreparing) {
        --preparing_;
        StartQueuedLater();
      }
      // An earlier import is still downloading it; that one reports it.
      item.elsewhere = result == extensions::webstore_install::INSTALL_IN_PROGRESS;
      item.state = success          ? Item::kInstalled
                   : item.elsewhere ? Item::kDeclined
                                    : Item::kFailed;
      --pending_;
    }
    item.installer = nullptr;
    MaybeFinish();
  }
  // One stalled Web Store answer can't hold up the rest.
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
    NSMutableArray<NSString*>* failed = [NSMutableArray array];
    for (auto& item : items_) {
      NSString* name = base::SysUTF8ToNSString(item.name);
      if (item.state == Item::kInstalled)
        [installed addObject:base::SysUTF8ToNSString(item.id)];
      else if (item.state == Item::kInstalling || item.elsewhere)
        [installing addObject:base::SysUTF8ToNSString(item.id)];
      else if (item.state == Item::kFailed && ![failed containsObject:name])
        [failed addObject:name];
      item.background = item.state == Item::kInstalling;
    }
    // Stopping is the user's choice; nothing to report as failed.
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
                                                        failed:failed];
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
  // Downloads still running at Report end here, once, with any failures.
  void Finish() {
    auto keep = shared_from_this();
    finished_ = true;
    NSMutableArray<NSString*>* failed = [NSMutableArray array];
    for (const auto& item : items_) {
      NSString* name = base::SysUTF8ToNSString(item.name);
      if (item.background && item.state == Item::kFailed &&
          ![failed containsObject:name])
        [failed addObject:name];
    }
    Failures background = nil;
    if (failed.count)
      background = background_;
    background_ = nil;
    Stop();
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::shared_ptr<Batch> self, NSArray<NSString*>* failed,
                          Failures background) {
                         self->lifetime_.reset();
                         if (background)
                           background(failed);
                       },
                       keep, failed, background));
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
}  // namespace
}  // namespace parc::importer

@implementation PCNativeBrowserApplication (ImportedExtensions)
+ (PCNativeImportSession*)installImportedExtensions:
                              (NSArray<PCNativeImportExtensionRequest*>*)requests
                                         completion:
                                             (void (^)(PCNativeImportExtensionResult*))
                                                 completion
                                 backgroundFailures:
                                     (void (^)(NSArray<NSString*>*))backgroundFailures {
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
// An import may still be downloading a blocker the user chose to remove.
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
    // The setup owner has already accepted this particular extension. Keep
    // Chromium's metadata, signature, policy and CRX installation checks.
    return nullptr;
  }

 private:
  base::WeakPtr<Profile> profile_;
};

// Installs the first candidate that ends up enabled; one already enabled is
// the result.
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
          // This setup continuation cannot provide parental reauthentication.
          // Never replace a required parent decision with the setup selection.
          if (profile->IsChild()) {
            self->Finish(importer::ImportError(@"This Profile requires parental approval to install extensions."));
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
      // An earlier candidate this setup installed but the engine keeps off.
      std::u16string ignored;
      for (const auto& id : disabled_)
        if (registry->disabled_extensions().Contains(id))
          extensions::ExtensionRegistrar::Get(profile_.get())->UninstallExtension(
              id, extensions::UNINSTALL_REASON_INTERNAL_MANAGEMENT, &ignored);
      Finish(nil);
      return;
    }
    if (next_ == candidates_.size()) {
      Finish(error_ ?: importer::ImportError(failure_));
      return;
    }
    error_ = nil;
    // A Manifest V2 candidate is refused, or installed disabled, by an engine
    // that no longer runs Manifest V2; the next candidate follows.
    const auto id = candidates_[next_++];
    // Chromium reports an existing install as success; that copy is the user's.
    const bool existed = registry->GetInstalledExtension(id) != nullptr;
    installer_ = base::MakeRefCounted<Installer>(id, *profile_,
        base::BindOnce([](std::weak_ptr<Session> weak, std::string id, bool existed, bool success,
                          const std::string& message, extensions::webstore_install::Result) {
          auto self = weak.lock();
          if (!self) return;
          if (success && !existed && self->profile_ &&
              !extensions::ExtensionRegistry::Get(self->profile_.get())->enabled_extensions().Contains(id))
            self->disabled_.push_back(id);
          if (!success && !message.empty())
            self->error_ = importer::ImportError(base::SysUTF8ToNSString(message));
          // Leave Chromium's completion stack before releasing its installer.
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
    // Do not release the installer/context inside Chromium's own completion
    // stack. Retain this owner through the single main-thread delivery.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](std::shared_ptr<Session> self, NSError* error) {
          // WebstoreStandaloneInstaller itself observes Profile destruction
          // and supplies its terminal failure before aborting installation.
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
  // Always asynchronous, including profile admission failure.
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
    // Not from inside the registry's own notification.
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
  // Only a blocker an import may still install is waited for, so one the
  // user installs again later stays.
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
    // External installs return after an internal uninstall.
    if (extensions::Manifest::IsExternalLocation(extension->location())) {
      error_ = importer::ImportError(@"An ad blocker installed by another app can't be removed here.");
      return;
    }
    // The internal reason opens no uninstall page and skips Chromium's policy
    // check, so the user's own permission is checked here.
    auto* policy = extensions::ExtensionSystem::Get(profile_.get())->management_policy();
    std::u16string message;
    if (!policy->UserMayModifySettings(extension, &message) ||
        policy->MustRemainInstalled(extension, &message) ||
        !extensions::ExtensionRegistrar::Get(profile_.get())->UninstallExtension(
            id, extensions::UNINSTALL_REASON_INTERNAL_MANAGEMENT, &message)) {
      error_ = importer::ImportError(message.empty()
          ? @"An imported ad blocker could not be removed."
          : base::SysUTF16ToNSString(message));
    }
  }
  void Expire() { Finish(error_); }
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
}  // namespace
}  // namespace parc::setup_extension

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
  // Paths match the import's own, which are standardized absolute paths.
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
@end

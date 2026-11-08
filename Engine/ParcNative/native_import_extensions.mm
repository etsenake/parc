// Copyright 2026 Parc contributors.
#include <algorithm>
#include <map>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/extensions/webstore_install_with_prompt.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/common/importer/parc_import.mojom.h"
#include "content/public/browser/service_process_host.h"
#include "mojo/public/cpp/bindings/remote.h"
#import "native_appkit_host.h"
#import "native_import_internal.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"

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
//
// metadata, policy, blocklist and CRX checks still run.
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
    CefRefPtr<CefRequestContext> context;
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
    started_ = base::TimeTicks::Now();
    ticker_.Start(FROM_HERE, base::Seconds(1),
                  base::BindRepeating(&Batch::Tick, base::Unretained(this)));
    for (size_t i = 0; i < groups_.size(); ++i)
      Load(i);
    MaybeFinish();
  }
  bool Stopped() const { return cancelled_ || finished_; }
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
               CefRefPtr<CefRequestContext> context, NSError* error) {
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
  // The import's results never wait on downloads; Chromium finishes those in
  //
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

namespace parc::setup_password_extension {
namespace {
//
// general unattended-extension API and cannot accept an ID from page content.
constexpr char kICloudPasswordsID[] = "pejdijmoenmkgeppbflobdenhhabjlaj";

class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(Profile& profile, Callback callback)
      : WebstoreInstallWithPrompt(kICloudPasswordsID, &profile,
                                  gfx::NativeWindow(), std::move(callback)),
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

class Session final : public std::enable_shared_from_this<Session> {
 public:
  Session(NSString* path, void (^completion)(NSError*))
      : path_([path copy]), completion_([completion copy]) {}

  void Start() {
    lifetime_ = shared_from_this();
    auto weak = weak_from_this();
    WithNativeProfile(path_, base::BindOnce(
        [](std::weak_ptr<Session> weak, Profile* profile,
           CefRefPtr<CefRequestContext> context, NSError* error) {
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
          self->installer_ = base::MakeRefCounted<Installer>(*profile,
              base::BindOnce([](std::weak_ptr<Session> weak, bool success,
                                const std::string& message, extensions::webstore_install::Result) {
                if (auto self = weak.lock()) {
                  NSError* failure = success ? nil : importer::ImportError(message.empty()
                      ? @"The selected iCloud Passwords extension could not be installed."
                      : base::SysUTF8ToNSString(message));
                  self->Finish(failure);
                }
              }, weak));
          self->installer_->BeginInstall();
        }, weak));
  }

 private:
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
  void (^completion_)(NSError*);
  CefRefPtr<CefRequestContext> context_;
  scoped_refptr<Installer> installer_;
  std::shared_ptr<Session> lifetime_;
  bool finished_ = false;
};
}  // namespace
}  // namespace parc::setup_password_extension

@implementation PCNativeBrowserApplication (SetupPasswordExtension)
+ (void)installICloudPasswordsExtensionToProfilePath:(NSString*)profilePath
    completion:(void (^)(NSError*))completion {
  auto session = std::make_shared<parc::setup_password_extension::Session>(profilePath, completion);
  // Always asynchronous, including profile admission failure.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::setup_password_extension::Session::Start, std::move(session)));
}
@end

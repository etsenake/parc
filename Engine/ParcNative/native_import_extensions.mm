// Copyright 2026 Parc contributors.
#include <algorithm>
#include <map>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "chrome/browser/extensions/extension_install_native_host.h"
#include "chrome/browser/extensions/webstore_install_with_prompt.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/common/importer/parc_import.mojom.h"
#include "content/public/browser/service_process_host.h"
#include "mojo/public/cpp/bindings/remote.h"
#import "native_appkit_host.h"
#import "native_import_internal.h"
#import "extension_install_presenter.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#import "window_security_reservation.h"

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
                         failed:(NSArray<NSString*>*)failed;
@end
@implementation PCNativeImportExtensionResult
@synthesize outcome = _outcome, installedIdentifiers = _installedIdentifiers,
            failedNames = _failedNames;
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      installed:(NSSet<NSString*>*)installed
                         failed:(NSArray<NSString*>*)failed {
  if ((self = [super init])) {
    _outcome = outcome;
    _installedIdentifiers = [installed copy];
    _failedNames = [failed copy];
  }
  return self;
}
@end

namespace parc::importer {
namespace {
using Result = extensions::ExtensionInstallPromptClient::Result;
using Payload = extensions::ExtensionInstallPromptClient::DoneCallbackPayload;
using Done = extensions::ExtensionInstallPromptClient::DoneCallback;
constexpr uint32_t kExtensionCategory = PCNativeImportCategoryExtensions;
class Batch;
// Holds one prepared Web Store install at its prompt until the batch decides.
class Consent final : public extensions::ExtensionInstallNativeBinding,
                      public std::enable_shared_from_this<Consent> {
 public:
  Consent(std::weak_ptr<Batch> batch, Profile& profile, size_t item)
      : batch_(std::move(batch)), profile_(profile.GetWeakPtr()), item_(item) {}
  ~Consent() override { Cancel(); }
  bool Begin(const extensions::Extension* extension, Done done) override {
    if (done_) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(std::move(done), Payload(Result::ABORTED)));
      return false;
    }
    extension_ = extension;
    done_ = std::move(done);
    if (!CanContinue()) {
      Complete(Result::ABORTED);
      return false;
    }
    return true;
  }
  bool CanContinue() const override;
  void Show(std::unique_ptr<extensions::InstallPromptData> prompt) override;
  bool authorized() const { return authorized_; }
  void Opened() {
    if (prompt_ && !opened_)
      prompt_->OnDialogOpened();
    opened_ = true;
  }
  void Decide(Result result) { Complete(result); }
  void Cancel() override {
    cancelled_ = true;
    Complete(Result::ABORTED);
  }
  void ShowParentApproval(const extensions::Extension*,
                          const gfx::ImageSkia&,
                          Done done) override {
    // A parent reauthentication cannot be replaced by import consent.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), Payload(Result::ABORTED)));
  }
  void InstallationFinished(const extensions::Extension*,
                            bool,
                            const std::u16string&,
                            const SkBitmap*,
                            bool) override {}

 private:
  void Complete(Result result);
  std::weak_ptr<Batch> batch_;
  base::WeakPtr<Profile> profile_;
  size_t item_;
  bool cancelled_ = false;
  bool authorized_ = false;
  bool opened_ = false;
  Done done_;
  scoped_refptr<const extensions::Extension> extension_;
  std::unique_ptr<extensions::InstallPromptData> prompt_;
};
class Installer final : public extensions::WebstoreInstallWithPrompt {
 public:
  Installer(const std::string& id,
            Profile& profile,
            NSWindow* window,
            std::shared_ptr<Consent> consent,
            Callback callback)
      : WebstoreInstallWithPrompt(id,
                                  &profile,
                                  gfx::NativeWindow(window),
                                  std::move(callback)),
        window_(window),
        consent_(std::move(consent)) {
    set_show_post_install_ui(false);
  }
  // False means installation has already been authorized; keep its genuine
  // completion callback and wait rather than claiming to undo that operation.
  bool CancelBeforeInstall() {
    if (consent_->authorized())
      return false;
    consent_->Cancel();
    AbortInstall();
    return true;
  }

 protected:
  ~Installer() override = default;
  std::unique_ptr<ExtensionInstallPrompt> CreateInstallUI(
      std::unique_ptr<extensions::InstallPromptData> prompt) override {
    return std::make_unique<ExtensionInstallPrompt>(
        profile(), gfx::NativeWindow(window_), std::move(prompt), consent_);
  }

 private:
  NSWindow* __weak window_;
  std::shared_ptr<Consent> consent_;
};
// Every request's extensions are prepared up to their prompts, then one sheet
// decides for all of them.
class Batch final : public ProfileObserver,
                    public std::enable_shared_from_this<Batch> {
 public:
  using Completion = void (^)(PCNativeImportExtensionResult*);
  struct Group {
    std::shared_ptr<const ProfileData> source;
    NSString* __strong path;
    std::vector<std::string> ids;
    base::WeakPtr<Profile> profile;
    CefRefPtr<CefRequestContext> context;
    mojo::Remote<mojom::Reader> reader;
    bool loaded = false, observing = false;
  };
  Batch(std::vector<Group> groups, NSWindow* window, Completion completion)
      : groups_(std::move(groups)),
        window_(window),
        completion_([completion copy]),
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
    if (!window_) {
      Cancel();
      return;
    }
    std::weak_ptr<Batch> weak = shared_from_this();
    close_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window_
                     queue:nil
                usingBlock:^(NSNotification*) {
                  if (auto self = weak.lock())
                    self->Cancel();
                }];
    deadline_.Start(FROM_HERE, base::Seconds(30),
                    base::BindOnce(&Batch::PreparationTimedOut,
                                   base::Unretained(this)));
    for (size_t i = 0; i < groups_.size(); ++i)
      Load(i);
    MaybePresent();
  }
  bool CanContinue() const {
    NSWindow* window = window_;
    return !finished_ && !cancelled_ && window && window.visible &&
           !window.miniaturized &&
           (!window.attachedSheet || window.attachedSheet == presenter_.sheet) &&
           (reservation_ ? reservation_.isOnlyReservation
                         : !PCNativeWindowHasSecurityReservation(window));
  }
  // Preparing needs no usable window; the decision waits for one.
  bool CanPrepare() const { return !finished_ && !cancelled_ && window_; }
  bool CanDeliver() const {
    return CanContinue() && !PCNativeWindowHasSecurityReservation(window_);
  }
  void Ready(size_t index,
             const std::string& name,
             NSImage* icon,
             NSArray<NSString*>* permissions,
             NSArray<NSString*>* details) {
    auto& item = items_[index];
    if (item.state != Item::kPreparing)
      return;
    item.state = Item::kReady;
    if (!name.empty())
      item.name = name;
    item.icon = icon;
    item.permissions = permissions;
    item.details = details;
    --preparing_;
    MaybePresent();
  }
  void Cancel() {
    if (finished_)
      return;
    cancelled_ = true;
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    for (auto& group : groups_)
      group.reader.reset();
    deadline_.Stop();
    for (auto& item : items_) {
      if (Pending(item) && Abort(item)) {
        if (item.state == Item::kAccepted)
          --installing_;
        item.state = Item::kDeclined;
      }
    }
    if (!installing_)
      Finish();
  }
  // The installer observes its Profile and aborts itself; only that Profile's
  // extensions fail.
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    for (auto& item : items_) {
      if (groups_[item.group].profile.get() != profile || !Pending(item))
        continue;
      if (item.state == Item::kPreparing)
        --preparing_;
      if (item.state == Item::kAccepted)
        --installing_;
      item.state = Item::kFailed;
      item.consent->Cancel();
      item.installer = nullptr;
    }
    for (auto& group : groups_)
      if (group.profile.get() == profile) {
        group.profile.reset();
        group.observing = false;
      }
    MaybeFinish();
    MaybePresent();
  }

 private:
  struct Item {
    enum State { kPreparing, kReady, kAccepted, kDeclined, kInstalled, kFailed };
    size_t group;
    std::string id, name;
    State state = kPreparing;
    std::shared_ptr<Consent> consent;
    scoped_refptr<Installer> installer;
    NSImage* __strong icon;
    NSArray<NSString*>* __strong permissions;
    NSArray<NSString*>* __strong details;
  };
  static bool Pending(const Item& item) {
    return item.installer && (item.state == Item::kPreparing ||
                              item.state == Item::kReady ||
                              item.state == Item::kAccepted);
  }
  // False once Chromium holds an authorized install; its real result follows.
  // Otherwise the installer is released with its abort so that no late
  // callback can reach it.
  static bool Abort(Item& item) {
    if (!item.installer->CancelBeforeInstall())
      return false;
    item.installer = nullptr;
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
      if (cancelled_) {
        item.state = Item::kDeclined;
      } else if (!confirmed.contains(id) || !group.profile ||
                 group.profile->ShutdownStarted()) {
        item.state = Item::kFailed;
      } else if (extensions::ExtensionRegistry::Get(group.profile.get())
                     ->GetInstalledExtension(id)) {
        item.state = Item::kInstalled;
      } else {
        Prepare(items_.size() - 1);
      }
    }
    --loading_;
    if (!loading_ && preparing_)
      deadline_.Start(FROM_HERE, base::Seconds(30),
                      base::BindOnce(&Batch::PreparationTimedOut,
                                     base::Unretained(this)));
    MaybePresent();
  }
  void PreparationTimedOut() {
    for (size_t i = 0; i < groups_.size(); ++i)
      Loaded(i, {});
    for (auto& item : items_)
      if (item.state == Item::kPreparing && Pending(item) && Abort(item)) {
        item.state = Item::kFailed;
        --preparing_;
      }
    deadline_.Stop();
    MaybePresent();
  }
  void Prepare(size_t index) {
    auto& item = items_[index];
    Profile& profile = *groups_[item.group].profile;
    ++preparing_;
    item.consent =
        std::make_shared<Consent>(weak_from_this(), profile, index);
    item.installer = base::MakeRefCounted<Installer>(
        item.id, profile, window_, item.consent,
        base::BindOnce(
            [](std::weak_ptr<Batch> weak, size_t index, bool success,
               const std::string&, extensions::webstore_install::Result) {
              if (auto self = weak.lock())
                self->Installed(index, success);
            },
            weak_from_this(), index));
    item.installer->BeginInstall();
  }
  void Installed(size_t index, bool success) {
    auto& item = items_[index];
    switch (item.state) {
      case Item::kPreparing:
        item.state = Item::kFailed;
        --preparing_;
        MaybePresent();
        break;
      case Item::kReady:
        item.state = Item::kFailed;
        break;
      case Item::kAccepted:
        item.state = success ? Item::kInstalled : Item::kFailed;
        --installing_;
        MaybeFinish();
        break;
      default:
        break;
    }
  }
  void MaybePresent() {
    if (finished_ || cancelled_ || decided_ || presenter_ || loading_ ||
        preparing_)
      return;
    if (!window_) {
      Cancel();
      return;
    }
    presented_ = true;
    NSMutableArray<PCExtensionInstallItem*>* list = [NSMutableArray array];
    std::set<std::string> listed;
    for (const auto& item : items_) {
      if (item.state != Item::kReady || !listed.insert(item.id).second)
        continue;
      [list addObject:[[PCExtensionInstallItem alloc]
                          initWithName:base::SysUTF8ToNSString(item.name)
                                                              icon:item.icon
                                                       permissions:item.permissions
                                                           details:item.details]];
    }
    if (!list.count) {
      MaybeFinish();
      return;
    }
    if (CanContinue())
      reservation_ = [PCNativeWindowSecurityReservation acquireForWindow:window_];
    if (!reservation_.active || !CanContinue()) {
      [reservation_ invalidate];
      reservation_ = nil;
      PresentLater();
      return;
    }
    for (auto& item : items_)
      if (item.state == Item::kReady)
        item.consent->Opened();
    std::weak_ptr<Batch> weak = shared_from_this();
    presenter_ = [[PCExtensionInstallPresenter alloc] initWithWindow:window_
        title:@"Extensions"
        icon:nil
        heading:@""
        permissions:@[]
        details:@[]
        acceptLabel:@"Add All"
        cancelLabel:@"Skip"
        checkboxLabel:nil
        validate:^BOOL {
          auto self = weak.lock();
          return self && self->CanContinue();
        }
        inputAllowed:^BOOL(NSWindow* sheet) {
          // As for any extension prompt: never under a picture in picture.
          auto bounds = PictureInPictureWindowManager::GetInstance()
                            ->GetPictureInPictureWindowBoundsInScreen();
          return sheet && (!bounds || !bounds->Intersects(
                                          gfx::ScreenRectFromNSRect(sheet.frame)));
        }
        result:^(PCExtensionInstallChoice choice, BOOL) {
          auto self = weak.lock();
          if (self && !self->cancelled_ && !self->finished_)
            self->Decide(choice);
        }];
    [presenter_ configureImportedExtensions:list];
    [presenter_ start];
  }
  // A minimized, hidden or busy window keeps the prepared installs waiting.
  void PresentLater() {
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE,
        base::BindOnce(
            [](std::weak_ptr<Batch> weak) {
              if (auto self = weak.lock())
                self->MaybePresent();
            },
            weak_from_this()),
        base::Milliseconds(500));
  }
  void Decide(PCExtensionInstallChoice choice) {
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    if (choice == PCExtensionInstallInterrupted) {
      PresentLater();
      return;
    }
    decided_ = true;
    skipped_ = choice == PCExtensionInstallCancel;
    const Result result =
        skipped_ ? Result::USER_CANCELED : Result::ACCEPTED;
    std::vector<std::shared_ptr<Consent>> decided;
    for (auto& item : items_) {
      if (item.state != Item::kReady)
        continue;
      if (result == Result::ACCEPTED) {
        item.state = Item::kAccepted;
        ++installing_;
      } else {
        item.state = Item::kDeclined;
      }
      decided.push_back(item.consent);
    }
    for (auto& consent : decided)
      consent->Decide(result);
    MaybeFinish();
  }
  void MaybeFinish() {
    if (!presented_ || installing_ ||
        (!decided_ && std::any_of(items_.begin(), items_.end(), [](const Item& item) {
          return item.state == Item::kReady;
        })))
      return;
    Finish();
  }
  void Finish() {
    if (finished_)
      return;
    auto keep = shared_from_this();
    finished_ = true;
    NSMutableSet<NSString*>* installed = [NSMutableSet set];
    NSMutableArray<NSString*>* failed = [NSMutableArray array];
    for (const auto& item : items_) {
      NSString* name = base::SysUTF8ToNSString(item.name);
      if (item.state == Item::kInstalled)
        [installed addObject:base::SysUTF8ToNSString(item.id)];
      else if (item.state == Item::kFailed && ![failed containsObject:name])
        [failed addObject:name];
    }
    // Stopping is the user's choice. Skipped ones are declined, not failed.
    if (cancelled_)
      [failed removeAllObjects];
    const PCNativeImportOutcome outcome =
        cancelled_ || skipped_ ? PCNativeImportOutcomeCancelled
        : !failed.count        ? PCNativeImportOutcomeCompleted
        : installed.count      ? PCNativeImportOutcomePartial
                               : PCNativeImportOutcomeFailed;
    auto result =
        [[PCNativeImportExtensionResult alloc] initWithOutcome:outcome
                                                     installed:installed
                                                        failed:failed];
    auto completion = completion_;
    completion_ = nil;
    Stop();
    // Installers are released outside Chromium's own completion stack.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::shared_ptr<Batch> self,
                          PCNativeImportExtensionResult* result,
                          Completion completion) {
                         self->items_.clear();
                         self->lifetime_.reset();
                         if (completion)
                           completion(result);
                       },
                       keep, result, completion));
  }
  void Stop() {
    [presenter_ invalidate];
    presenter_ = nil;
    [reservation_ invalidate];
    reservation_ = nil;
    if (close_observer_) {
      [NSNotificationCenter.defaultCenter removeObserver:close_observer_];
      close_observer_ = nil;
    }
    deadline_.Stop();
    for (auto& group : groups_) {
      group.reader.reset();
      if (group.profile && group.observing)
        group.profile->RemoveObserver(this);
      group.observing = false;
      group.profile.reset();
      group.context = nullptr;
    }
    for (NSString* path in reserved_)
      ReleaseImportDestination(path, this);
    [reserved_ removeAllObjects];
  }
  std::vector<Group> groups_;
  std::vector<Item> items_;
  NSMutableArray<NSString*>* __strong reserved_ = [NSMutableArray array];
  NSWindow* __weak window_;
  Completion __strong completion_;
  id __strong close_observer_;
  PCExtensionInstallPresenter* __strong presenter_;
  PCNativeWindowSecurityReservation* __strong reservation_;
  std::shared_ptr<Batch> lifetime_;
  base::OneShotTimer deadline_;
  size_t loading_, preparing_ = 0, installing_ = 0;
  bool presented_ = false, decided_ = false, skipped_ = false,
       cancelled_ = false, finished_ = false;
};
bool Consent::CanContinue() const {
  auto batch = batch_.lock();
  return !cancelled_ && batch && batch->CanPrepare() && profile_ &&
         !profile_->ShutdownStarted();
}
void Consent::Show(std::unique_ptr<extensions::InstallPromptData> prompt) {
  auto keep = shared_from_this();
  if (!CanContinue() || !done_ ||
      prompt->type() != extensions::InstallPromptData::INSTALL_PROMPT ||
      prompt->extension() != extension_.get()) {
    Complete(Result::ABORTED);
    return;
  }
  auto permissions = prompt->GetPermissions();
  if (permissions.permissions.size() != permissions.details.size()) {
    Complete(Result::ABORTED);
    return;
  }
  NSMutableArray* messages = [NSMutableArray array];
  NSMutableArray* details = [NSMutableArray array];
  for (size_t i = 0; i < permissions.permissions.size(); ++i) {
    [messages addObject:base::SysUTF16ToNSString(permissions.permissions[i])];
    [details addObject:base::SysUTF16ToNSString(permissions.details[i])];
  }
  NSImage* icon = prompt->icon().IsEmpty() ? nil : prompt->icon().ToNSImage();
  const std::string name = prompt->extension()->name();
  prompt_ = std::move(prompt);
  batch_.lock()->Ready(item_, name, icon, messages, details);
}
void Consent::Complete(Result result) {
  if (!done_)
    return;
  std::weak_ptr<Consent> weak = weak_from_this();
  auto done = std::move(done_);
  auto prompt = std::move(prompt_);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](std::weak_ptr<Consent> weak,
             std::unique_ptr<extensions::InstallPromptData> prompt, Done done,
             Result result) {
            auto self = weak.lock();
            auto valid = [&] {
              auto batch = self ? self->batch_.lock() : nullptr;
              return self && !self->cancelled_ && batch && batch->CanDeliver() &&
                     self->profile_ && !self->profile_->ShutdownStarted();
            };
            if (result == Result::ACCEPTED && !valid())
              result = Result::ABORTED;
            if (prompt) {
              if (result == Result::ACCEPTED)
                prompt->OnDialogAccepted();
              else
                prompt->OnDialogCanceled();
            }
            if (result == Result::ACCEPTED && !valid())
              result = Result::ABORTED;
            if (result == Result::ACCEPTED)
              self->authorized_ = true;
            std::move(done).Run(Payload(result));
          },
          weak, std::move(prompt), std::move(done), result));
}
}  // namespace
}  // namespace parc::importer

@implementation PCNativeBrowserApplication (ImportedExtensions)
+ (PCNativeImportSession*)installImportedExtensions:
                              (NSArray<PCNativeImportExtensionRequest*>*)requests
                                           inWindow:(NSWindow*)window
                                         completion:
                                             (void (^)(PCNativeImportExtensionResult*))
                                                 completion {
  CHECK(NSThread.isMainThread);
  if (!requests.count || !window || !window.visible || !completion)
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
  auto batch = std::make_shared<parc::importer::Batch>(std::move(groups),
                                                       window, completion);
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

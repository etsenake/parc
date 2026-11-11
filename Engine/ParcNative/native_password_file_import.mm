// Copyright 2026 Parc contributors.
#include <map>
#include <set>
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/timer/timer.h"
#include "chrome/browser/password_manager/factories/profile_password_store_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/password_manager/core/browser/password_store/password_store_consumer.h"
#include "components/password_manager/core/browser/password_store/password_store_interface.h"
#include "components/password_manager/core/common/password_manager_constants.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/password_manager/services/csv_password/csv_password_parser_service.h"
#include "components/prefs/pref_service.h"
#import "native_appkit_host.h"
#include "native_profiles.h"
#import "native_import_internal.h"
#include "native_password_file.h"

@interface PCNativePasswordFileImportResult ()
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome imported:(NSUInteger)imported
    existing:(NSUInteger)existing invalid:(NSUInteger)invalid removable:(BOOL)removable error:(NSError*)error;
@end
@implementation PCNativePasswordFileImportResult
@synthesize outcome = _outcome, importedCount = _importedCount, existingCount = _existingCount,
    invalidCount = _invalidCount, canRemoveSourceFile = _canRemoveSourceFile, error = _error;
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome imported:(NSUInteger)imported
    existing:(NSUInteger)existing invalid:(NSUInteger)invalid removable:(BOOL)removable error:(NSError*)error {
  if ((self = [super init])) {
    _outcome = outcome; _importedCount = imported; _existingCount = existing;
    _invalidCount = invalid; _canRemoveSourceFile = removable; _error = error;
  }
  return self;
}
@end

namespace parc::password_file {
namespace {
using Completion = void (^)(PCNativePasswordFileImportResult*);
using Credential = password_manager::StoredCredential;
using Key = std::pair<std::string, std::u16string>;
struct Expected { password_manager::PasswordString password; std::u16string note; };
class Session final : public ProfileObserver, public password_manager::PasswordStoreConsumer,
                      public std::enable_shared_from_this<Session> {
 public:
  Session(NSURL* file, NSString* path, NSWindow* window, Completion completion)
      : file_([file copy]), path_([path copy]), window_(window), completion_([completion copy]) {}
  ~Session() override { Release(); }
  bool Reserve() {
    if (!importer::ReserveImportDestination(path_, this)) return false;
    reserved_ = true; lifetime_ = shared_from_this(); return true;
  }
  void Start() {
    if (finished_) return;
    auto weak = weak_from_this();
    close_observer_ = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
        object:window_ queue:nil usingBlock:^(NSNotification*) { if (auto self = weak.lock()) self->Cancel(); }];
    WithNativeProfile(path_, base::BindOnce([](std::weak_ptr<Session> weak, Profile* profile,
        parc::NativeProfileLeasePtr context, NSError* error) {
      auto self = weak.lock(); if (!self || self->finished_) return;
      if (error || !profile || !context || profile->IsOffTheRecord()) {
        self->Finish(PCNativeImportOutcomeFailed, error ?: importer::ImportError(@"The destination Profile is unavailable.")); return;
      }
      self->profile_ = profile->GetWeakPtr(); self->context_ = context;
      profile->AddObserver(self.get()); self->observing_ = true;
      self->ReadFile();
    }, weak));
  }
  void Cancel() {
    cancelled_ = true; removable_ = false;
    if (!finished_ && !writing_) Finish(PCNativeImportOutcomeCancelled, nil);
    else if (finished_) Release();
    // Accepted writes must drain and be verified. Cancellation is not rollback.
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this); observing_ = false; profile_.reset();
    cancelled_ = true; removable_ = false;
    if (!finished_) Finish(PCNativeImportOutcomeCancelled,
        importer::ImportError(@"The destination Profile closed. Pending password writes could not be confirmed."));
    else Release();
  }
  void Remove(void (^completion)(NSError*)) {
    if (!finished_ || !removable_ || removing_ || !ValidOwner() || !identity_) {
      completion(importer::ImportError(@"The original imported file is no longer eligible for removal.")); return;
    }
    removing_ = true;
    auto weak = weak_from_this(); auto expected = *identity_;
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&Read, base::SysNSStringToUTF8(file_.path)),
        base::BindOnce([](std::weak_ptr<Session> weak, Identity expected, void (^completion)(NSError*), ReadResult read) {
          std::fill(read.bytes.begin(), read.bytes.end(), 0);
          auto self = weak.lock();
          if (!self) { completion(importer::ImportError(@"The import was closed.")); return; }
          self->removing_ = false;
          if (!self->ValidOwner() || !self->removable_ || !read.identity || *read.identity != expected) {
            self->removable_ = false;
            completion(importer::ImportError(@"The original file changed or its import closed. It was not removed.")); return;
          }
          NSError* error = nil;
          if (![NSFileManager.defaultManager trashItemAtURL:self->file_ resultingItemURL:nil error:&error]) {
            completion(error ?: importer::ImportError(@"The file could not be moved to Trash.")); return;
          }
          self->removable_ = false; completion(nil);
        }, weak, expected, [completion copy]));
  }
  void OnGetPasswordStoreResultsOrErrorFrom(password_manager::PasswordStoreInterface* store,
      base::expected<std::vector<Credential>, password_manager::PasswordStoreBackendError> result) override {
    if (finished_) return;
    if (store != store_.get() || !result.has_value()) {
      Finish(cancelled_ ? PCNativeImportOutcomeCancelled : PCNativeImportOutcomeFailed,
          importer::ImportError(writing_ ? @"Password writes could not be confirmed. The exported file has been kept." : @"The destination password store could not be read.")); return;
    }
    if (writing_) { Verify(result.value()); return; }
    if (!ValidOwner() || cancelled_ || !PasswordSavingEnabled()) { Finish(PCNativeImportOutcomeCancelled, nil); return; }
    std::map<Key, const Credential*> existing;
    std::set<std::string> blocked;
    for (const auto& credential : result.value()) {
      if (credential.blocked_by_user) blocked.insert(credential.signon_realm);
      else existing.try_emplace(Key(credential.signon_realm, credential.username_value), &credential);
    }
    std::vector<Credential> additions;
    for (auto& credential : incoming_) {
      Key key(credential.signon_realm, credential.username_value);
      auto found = existing.find(key);
      if (blocked.contains(credential.signon_realm) || found != existing.end()) {
        ++existing_count_;
        if (blocked.contains(credential.signon_realm) || found->second->password_value != credential.password_value ||
            found->second->GetPasswordNote() != credential.GetPasswordNote()) ++conflicts_;
        continue;
      }
      auto [it, inserted] = expected_.try_emplace(key, Expected{credential.password_value, credential.GetPasswordNote()});
      if (!inserted) {
        ++existing_count_;
        if (it->second.password != credential.password_value || it->second.note != credential.GetPasswordNote()) ++conflicts_;
        continue;
      }
      additions.push_back(std::move(credential));
    }
    incoming_.clear();
    if (additions.empty()) { Complete(); return; }
    writing_ = true; deadline_.Stop();
    store_->AddLogins(std::move(additions), base::BindOnce([](std::shared_ptr<Session> self) {
      if (self->finished_) return;
      if (!self->profile_ || self->profile_->ShutdownStarted()) {
        self->Finish(PCNativeImportOutcomeCancelled, importer::ImportError(@"The destination closed before password writes could be confirmed.")); return;
      }
      self->store_->GetAllLogins(self->weak_factory_.GetWeakPtr());
    }, shared_from_this()));
  }
 private:
  bool ValidOwner() const {
    return !cancelled_ && window_ && window_.visible && profile_ && !profile_->IsOffTheRecord() &&
        !profile_->ShutdownStarted() && context_ && context_->profile() == profile_.get();
  }
  bool PasswordSavingEnabled() const {
    return profile_ && profile_->GetPrefs()->GetBoolean(password_manager::prefs::kCredentialsEnableService);
  }
  void ReadFile() {
    if (!ValidOwner()) { Finish(PCNativeImportOutcomeCancelled, nil); return; }
    if (!PasswordSavingEnabled()) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Password saving is disabled for this Profile.")); return; }
    deadline_.Start(FROM_HERE, base::Seconds(30), base::BindOnce([](std::weak_ptr<Session> weak) {
      if (auto self = weak.lock()) self->Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Reading the exported password file timed out."));
    }, weak_from_this()));
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&Read, base::SysNSStringToUTF8(file_.path)),
        base::BindOnce([](std::weak_ptr<Session> weak, ReadResult read) {
          auto self = weak.lock();
          if (!self || self->finished_ || !self->ValidOwner()) {
            std::fill(read.bytes.begin(), read.bytes.end(), 0);
            if (self && !self->finished_) self->Finish(PCNativeImportOutcomeCancelled, nil);
            return;
          }
          if (!read.identity) { self->Finish(PCNativeImportOutcomeFailed, importer::ImportError(base::SysUTF8ToNSString(read.error))); return; }
          self->identity_ = read.identity;
          self->parser_ = password_manager::LaunchCSVPasswordParser();
          self->parser_.set_disconnect_handler(base::BindOnce([](std::weak_ptr<Session> weak) {
            if (auto self = weak.lock()) self->Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"The CSV password reader stopped. No passwords were imported."));
          }, weak));
          self->parser_->ParseCSV(read.bytes, base::BindOnce(&Session::Parsed, self->weak_factory_.GetWeakPtr()));
          std::fill(read.bytes.begin(), read.bytes.end(), 0);
        }, weak_from_this()));
  }
  void Parsed(password_manager::mojom::CSVPasswordSequencePtr sequence) {
    parser_.reset();
    if (finished_) return;
    if (!ValidOwner()) { Finish(PCNativeImportOutcomeCancelled, nil); return; }
    if (!sequence || sequence->csv_passwords.empty() || sequence->csv_passwords.size() > 3000) {
      Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Choose an exported password CSV with URL, username and password columns, and no more than 3000 rows.")); return;
    }
    for (const auto& row : sequence->csv_passwords) {
      using namespace password_manager;
      if (row.GetParseStatus() != CSVPassword::Status::kOK || !row.GetURL().has_value() ||
          !row.GetURL()->SchemeIsHTTPOrHTTPS() || row.GetURL()->has_username() || row.GetURL()->has_password() ||
          row.GetURL()->spec().size() > constants::kMaxUrlLengthForImport || row.GetPassword().empty() ||
          row.GetPassword().size() > constants::kMaxPasswordLengthForImport ||
          row.GetUsername().size() > constants::kMaxUsernameLengthForImport || row.GetNote().size() > constants::kMaxPasswordNoteLength) {
        ++invalid_count_; continue;
      }
      Credential credential;
      credential.url = row.GetURL().value(); credential.signon_realm = credential.url.DeprecatedGetOriginAsURL().spec();
      credential.username_value = base::UTF8ToUTF16(row.GetUsername());
      credential.password_value = PasswordString(base::UTF8ToUTF16(row.GetPassword()));
      credential.SetPasswordNote(base::UTF8ToUTF16(row.GetNote()));
      credential.type = PasswordForm::Type::kImported; credential.in_store = PasswordForm::Store::kProfileStore;
      credential.date_created = base::Time::Now();
      incoming_.push_back(std::move(credential));
    }
    if (incoming_.empty()) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"No supported website passwords were found. The file has been kept.")); return; }
    store_ = ProfilePasswordStoreFactory::GetForProfile(profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!store_) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Password storage is unavailable.")); return; }
    store_->GetAllLogins(weak_factory_.GetWeakPtr());
  }
  void Verify(const std::vector<Credential>& stored) {
    for (const auto& credential : stored) {
      if (credential.blocked_by_user) continue;
      auto found = expected_.find(Key(credential.signon_realm, credential.username_value));
      if (found != expected_.end() && found->second.password == credential.password_value && found->second.note == credential.GetPasswordNote()) {
        ++imported_count_; expected_.erase(found);
      }
    }
    if (!expected_.empty()) {
      Finish(cancelled_ ? PCNativeImportOutcomeCancelled : PCNativeImportOutcomeFailed,
          importer::ImportError(@"Some password writes could not be confirmed. Confirmed passwords remain saved; the exported file has been kept.")); return;
    }
    Complete();
  }
  void Complete() {
    removable_ = !cancelled_ && invalid_count_ == 0 && conflicts_ == 0 && (imported_count_ || existing_count_);
    Finish(cancelled_ ? PCNativeImportOutcomeCancelled :
        (conflicts_ || invalid_count_ ? PCNativeImportOutcomePartial : PCNativeImportOutcomeCompleted),
        conflicts_ ? importer::ImportError(@"Existing or duplicate entries were kept. Some rows differed; keep the exported file to review them.") : nil);
  }
  void Finish(PCNativeImportOutcome outcome, NSError* error) {
    if (finished_) return;
    auto keep_alive = shared_from_this(); finished_ = true;
    deadline_.Stop(); parser_.reset(); incoming_.clear(); expected_.clear(); store_.reset();
    if (reserved_) { importer::ReleaseImportDestination(path_, this); reserved_ = false; }
    if (outcome != PCNativeImportOutcomeCompleted) removable_ = false;
    auto result = [[PCNativePasswordFileImportResult alloc] initWithOutcome:outcome imported:imported_count_
        existing:existing_count_ invalid:invalid_count_ removable:removable_ error:error];
    auto completion = completion_; completion_ = nil;
    if (!removable_) Release();
    lifetime_.reset();
    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
  }
  void Release() {
    deadline_.Stop(); parser_.reset(); weak_factory_.InvalidateWeakPtrs();
    if (close_observer_) { [NSNotificationCenter.defaultCenter removeObserver:close_observer_]; close_observer_ = nil; }
    if (observing_ && profile_) profile_->RemoveObserver(this);
    observing_ = false; profile_.reset(); context_ = nullptr;
    if (reserved_) { importer::ReleaseImportDestination(path_, this); reserved_ = false; }
  }
  NSURL* __strong file_;
  NSString* __strong path_;
  NSWindow* __weak window_;
  Completion __strong completion_;
  id __strong close_observer_;
  std::shared_ptr<Session> lifetime_;
  base::WeakPtr<Profile> profile_;
  parc::NativeProfileLeasePtr context_;
  scoped_refptr<password_manager::PasswordStoreInterface> store_;
  mojo::Remote<password_manager::mojom::CSVPasswordParser> parser_;
  std::vector<Credential> incoming_;
  std::map<Key, Expected> expected_;
  std::optional<Identity> identity_;
  size_t imported_count_ = 0, existing_count_ = 0, invalid_count_ = 0, conflicts_ = 0;
  bool reserved_ = false, observing_ = false, cancelled_ = false, finished_ = false, writing_ = false;
  bool removable_ = false, removing_ = false;
  base::OneShotTimer deadline_;
  base::WeakPtrFactory<Session> weak_factory_{this};
};
}  // namespace
}  // namespace parc::password_file

@interface PCNativePasswordFileImportSession ()
- (instancetype)initWithSession:(std::shared_ptr<parc::password_file::Session>)session;
@end
@implementation PCNativePasswordFileImportSession {
  std::shared_ptr<parc::password_file::Session> _session;
}
- (instancetype)initWithSession:(std::shared_ptr<parc::password_file::Session>)session {
  if ((self = [super init])) _session = std::move(session); return self;
}
- (void)cancel { if (_session) _session->Cancel(); }
- (void)removeSourceFileWithCompletion:(void (^)(NSError*))completion {
  CHECK(NSThread.isMainThread); _session->Remove(completion);
}
- (void)dealloc { [self cancel]; }
@end
@implementation PCNativeBrowserApplication (PasswordFileImport)
+ (PCNativePasswordFileImportSession*)importPasswordFile:(NSURL*)fileURL toProfilePath:(NSString*)path
    inWindow:(NSWindow*)window completion:(void (^)(PCNativePasswordFileImportResult*))completion {
  CHECK(NSThread.isMainThread);
  if (!fileURL.isFileURL || ![fileURL.pathExtension.lowercaseString isEqual:@"csv"] || !window.visible ||
      !path.isAbsolutePath || ![path isEqual:path.stringByStandardizingPath]) return nil;
  auto session = std::make_shared<parc::password_file::Session>(fileURL, path, window, completion);
  if (!session->Reserve()) return nil;
  auto lease = [[PCNativePasswordFileImportSession alloc] initWithSession:session];
  dispatch_async(dispatch_get_main_queue(), ^{ session->Start(); });
  return lease;
}
@end

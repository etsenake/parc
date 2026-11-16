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
struct Loaded { ReadResult read; Chunks chunks; };
Loaded Load(const std::string& path) {
  Loaded loaded{Read(path), {}};
  if (loaded.read.identity) loaded.chunks = Split(loaded.read.bytes);
  return loaded;
}
NSString* Unreadable() {
  return @"Choose an exported password CSV with URL, username and password columns.";
}
void Wipe(std::string& bytes) {
  std::fill(bytes.begin(), bytes.end(), 0); bytes.clear(); bytes.shrink_to_fit();
}
class Session final : public ProfileObserver, public password_manager::PasswordStoreConsumer,
                      public std::enable_shared_from_this<Session> {
 public:
  Session(NSURL* file, NSString* path, NSWindow* window, Completion completion)
      : file_([file copy]), path_([path copy]), window_(window), completion_([completion copy]) {}
  ~Session() override { Wipe(bytes_); Release(); }
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
    if (finished_) { Release(); return; }
    if (writing_ || verifying_) return;
    if (wrote_) { Stop(nil); return; }
    Finish(PCNativeImportOutcomeCancelled, nil);
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
          importer::ImportError(verifying_ ? @"Password writes could not be confirmed. The exported file has been kept." : @"The destination password store could not be read.")); return;
    }
    if (verifying_) { Verify(result.value()); return; }
    if (!Alive()) { Finish(PCNativeImportOutcomeCancelled, nil); return; }
    if (!PasswordSavingEnabled()) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Password saving is disabled for this Profile.")); return; }
    for (const auto& credential : result.value()) {
      if (credential.blocked_by_user) blocked_.insert(credential.signon_realm);
      else existing_.try_emplace(Key(credential.signon_realm, credential.username_value),
                                 Expected{credential.password_value, credential.GetPasswordNote()});
    }
    snapshot_ = true;
    Apply();
  }
 private:
  bool Alive() const {
    return !cancelled_ && window_ && profile_ && !profile_->IsOffTheRecord() &&
        !profile_->ShutdownStarted() && context_ && context_->profile() == profile_.get();
  }
  bool ValidOwner() const { return Alive() && window_.visible; }
  bool PasswordSavingEnabled() const {
    return profile_ && profile_->GetPrefs()->GetBoolean(password_manager::prefs::kCredentialsEnableService);
  }
  void ReadFile() {
    if (!ValidOwner()) { Finish(PCNativeImportOutcomeCancelled, nil); return; }
    if (!PasswordSavingEnabled()) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Password saving is disabled for this Profile.")); return; }
    StartDeadline();
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&Load, base::SysNSStringToUTF8(file_.path)),
        base::BindOnce([](std::weak_ptr<Session> weak, Loaded loaded) {
          auto self = weak.lock();
          if (!self || self->finished_ || !self->Alive()) {
            Wipe(loaded.read.bytes);
            if (self && !self->finished_) self->Finish(PCNativeImportOutcomeCancelled, nil);
            return;
          }
          if (!loaded.read.identity) { self->Finish(PCNativeImportOutcomeFailed, importer::ImportError(base::SysUTF8ToNSString(loaded.read.error))); return; }
          self->identity_ = loaded.read.identity;
          self->bytes_ = std::move(loaded.read.bytes);
          self->chunks_ = std::move(loaded.chunks);
          if (self->chunks_.ranges.empty()) { self->Finish(PCNativeImportOutcomeFailed, importer::ImportError(Unreadable())); return; }
          self->ParseNext();
        }, weak_from_this()));
  }
  void StartDeadline() {
    deadline_.Start(FROM_HERE, base::Seconds(30), base::BindOnce([](std::weak_ptr<Session> weak) {
      if (auto self = weak.lock()) self->Fail(importer::ImportError(@"Reading the exported password file timed out."));
    }, weak_from_this()));
  }
  void Fail(NSError* error) {
    if (finished_ || writing_ || verifying_) return;
    if (wrote_) Stop(error); else Finish(PCNativeImportOutcomeFailed, error);
  }
  void ParseNext() {
    if (finished_) return;
    if (!Alive()) { Cancel(); return; }
    if (next_ == chunks_.ranges.size()) { Parsed(); return; }
    if (!parser_.is_bound() || !parser_.is_connected()) {
      parser_.reset();
      parser_ = password_manager::LaunchCSVPasswordParser();
      parser_.set_disconnect_handler(base::BindOnce([](std::weak_ptr<Session> weak) {
        if (auto self = weak.lock()) {
          self->parser_.reset();
          if (self->parsing_) {
            self->parsing_ = false;
            self->Fail(importer::ImportError(self->wrote_ ? @"The CSV password reader stopped. Passwords saved before it stopped remain saved; the exported file has been kept." : @"The CSV password reader stopped. No passwords were imported."));
          }
        }
      }, weak_from_this()));
    }
    const auto [begin, end] = chunks_.ranges[next_++];
    std::string chunk;
    chunk.reserve(chunks_.header + end - begin);
    chunk.append(bytes_, 0, chunks_.header).append(bytes_, begin, end - begin);
    StartDeadline();
    parsing_ = true;
    parser_->ParseCSV(chunk, base::BindOnce(&Session::ChunkParsed, weak_factory_.GetWeakPtr()));
    Wipe(chunk);
  }
  void ChunkParsed(password_manager::mojom::CSVPasswordSequencePtr sequence) {
    parsing_ = false;
    if (finished_) return;
    if (!Alive()) { Cancel(); return; }
    if (!sequence) { Fail(importer::ImportError(Unreadable())); return; }
    rows_ += sequence->csv_passwords.size();
    for (const auto& row : sequence->csv_passwords) Admit(row);
    sequence.reset();
    if (incoming_.empty()) { ParseNext(); return; }
    if (snapshot_) { Apply(); return; }
    store_ = ProfilePasswordStoreFactory::GetForProfile(profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!store_) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"Password storage is unavailable.")); return; }
    store_->GetAllLogins(weak_factory_.GetWeakPtr());
  }
  void Admit(const password_manager::CSVPassword& row) {
    using namespace password_manager;
    if (row.GetParseStatus() == CSVPassword::Status::kOK && row.GetURL().has_value() &&
        row.GetURL()->SchemeIs("chrome")) return;
    if (row.GetParseStatus() != CSVPassword::Status::kOK || !row.GetURL().has_value() ||
        !row.GetURL()->SchemeIsHTTPOrHTTPS() || row.GetURL()->has_username() || row.GetURL()->has_password() ||
        row.GetURL()->spec().size() > constants::kMaxUrlLengthForImport || row.GetPassword().empty() ||
        row.GetPassword().size() > constants::kMaxPasswordLengthForImport ||
        row.GetUsername().size() > constants::kMaxUsernameLengthForImport || row.GetNote().size() > constants::kMaxPasswordNoteLength) {
      ++invalid_count_; return;
    }
    Credential credential;
    credential.url = row.GetURL().value(); credential.signon_realm = credential.url.DeprecatedGetOriginAsURL().spec();
    credential.username_value = base::UTF8ToUTF16(row.GetUsername());
    credential.password_value = PasswordString(base::UTF8ToUTF16(row.GetPassword()));
    credential.SetPasswordNote(base::UTF8ToUTF16(row.GetNote()));
    credential.type = PasswordForm::Type::kImported; credential.in_store = PasswordForm::Store::kProfileStore;
    credential.date_created = base::Time::Now();
    ++admitted_;
    incoming_.push_back(std::move(credential));
  }
  void Apply() {
    std::vector<Credential> additions;
    for (auto& credential : incoming_) {
      Key key(credential.signon_realm, credential.username_value);
      const bool blocked = blocked_.contains(credential.signon_realm);
      auto found = existing_.find(key);
      if (blocked || found != existing_.end()) {
        ++existing_count_;
        if (blocked || found->second.password != credential.password_value ||
            found->second.note != credential.GetPasswordNote()) ++conflicts_;
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
    if (additions.empty()) { ParseNext(); return; }
    if (!PasswordSavingEnabled()) {
      Fail(importer::ImportError(@"Password saving was turned off during the import. Passwords saved before then remain saved; the exported file has been kept.")); return;
    }
    writing_ = true; deadline_.Stop();
    store_->AddLogins(std::move(additions), base::BindOnce([](std::shared_ptr<Session> self) {
      self->writing_ = false; self->wrote_ = true;
      if (self->finished_) return;
      if (!self->profile_ || self->profile_->ShutdownStarted()) {
        self->Finish(PCNativeImportOutcomeCancelled, importer::ImportError(@"The destination closed before password writes could be confirmed.")); return;
      }
      if (!self->Alive()) { self->Cancel(); return; }
      self->ParseNext();
    }, shared_from_this()));
  }
  void Parsed() {
    parsed_all_ = true;
    deadline_.Stop(); Wipe(bytes_); parser_.reset();
    if (!rows_) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(Unreadable())); return; }
    if (!admitted_) { Finish(PCNativeImportOutcomeFailed, importer::ImportError(@"No supported website passwords were found. The file has been kept.")); return; }
    if (!wrote_) { Complete(); return; }
    verifying_ = true;
    store_->GetAllLogins(weak_factory_.GetWeakPtr());
  }
  void Stop(NSError* error) {
    deadline_.Stop(); Wipe(bytes_); parser_.reset(); parsing_ = false; incoming_.clear();
    failure_ = error;
    if (!wrote_ || !store_) {
      Finish(error ? PCNativeImportOutcomeFailed : PCNativeImportOutcomeCancelled, error); return;
    }
    verifying_ = true;
    store_->GetAllLogins(weak_factory_.GetWeakPtr());
  }
  void Verify(const std::vector<Credential>& stored) {
    verifying_ = false;
    for (const auto& credential : stored) {
      if (credential.blocked_by_user) continue;
      auto found = expected_.find(Key(credential.signon_realm, credential.username_value));
      if (found != expected_.end() && found->second.password == credential.password_value && found->second.note == credential.GetPasswordNote()) {
        ++imported_count_; expected_.erase(found);
      }
    }
    if (!expected_.empty()) {
      Finish(cancelled_ ? PCNativeImportOutcomeCancelled : (imported_count_ ? PCNativeImportOutcomePartial : PCNativeImportOutcomeFailed),
          importer::ImportError(@"Some password writes could not be confirmed. Confirmed passwords remain saved; the exported file has been kept.")); return;
    }
    Complete();
  }
  void Complete() {
    removable_ = parsed_all_ && !cancelled_ && !failure_ && invalid_count_ == 0 && conflicts_ == 0 && (imported_count_ || existing_count_);
    Finish(cancelled_ ? PCNativeImportOutcomeCancelled :
        (!parsed_all_ || failure_ || conflicts_ || invalid_count_ ? PCNativeImportOutcomePartial : PCNativeImportOutcomeCompleted),
        failure_ ?: (conflicts_ ? importer::ImportError(@"Existing or duplicate entries were kept. Some rows differed; keep the exported file to review them.") : nil));
  }
  void Finish(PCNativeImportOutcome outcome, NSError* error) {
    if (finished_) return;
    auto keep_alive = shared_from_this(); finished_ = true;
    deadline_.Stop(); parser_.reset(); Wipe(bytes_); incoming_.clear(); expected_.clear(); existing_.clear(); blocked_.clear(); store_.reset();
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
  NSError* __strong failure_;
  std::shared_ptr<Session> lifetime_;
  base::WeakPtr<Profile> profile_;
  parc::NativeProfileLeasePtr context_;
  scoped_refptr<password_manager::PasswordStoreInterface> store_;
  mojo::Remote<password_manager::mojom::CSVPasswordParser> parser_;
  std::string bytes_;
  Chunks chunks_;
  size_t next_ = 0, rows_ = 0, admitted_ = 0;
  std::vector<Credential> incoming_;
  std::map<Key, Expected> existing_, expected_;
  std::set<std::string> blocked_;
  std::optional<Identity> identity_;
  size_t imported_count_ = 0, existing_count_ = 0, invalid_count_ = 0, conflicts_ = 0;
  bool reserved_ = false, observing_ = false, cancelled_ = false, finished_ = false;
  bool snapshot_ = false, parsing_ = false, writing_ = false, verifying_ = false, wrote_ = false, parsed_all_ = false;
  bool removable_ = false, removing_ = false;
  base::OneShotTimer deadline_;
  base::WeakPtrFactory<Session> weak_factory_{this};
};
}
}

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

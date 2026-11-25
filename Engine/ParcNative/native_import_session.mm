// Copyright 2026 Parc contributors.
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#import <Security/Security.h>
#include <map>
#include <set>
#include "base/check.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/synchronization/lock.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/timer/timer.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "content/public/browser/service_process_host.h"
#include "mojo/public/cpp/bindings/remote.h"
#import "native_appkit_host.h"
#include "native_profiles.h"
#import "native_import_internal.h"
#include "parc/importer/import_reader.h"
#import "native_import_writer.h"
#include "url/gurl.h"

@implementation PCNativeImportedBookmark
@synthesize identifier = _identifier, title = _title, url = _url,
            children = _children;
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                               URL:(NSURL*)url
                          children:
                              (NSArray<PCNativeImportedBookmark*>*)children {
  if ((self = [super init])) {
    _identifier = [identifier copy];
    _title = [title copy];
    _url = [url copy];
    _children = [children copy];
  }
  return self;
}
@end
@implementation PCNativeImportEvent
@synthesize category = _category, phase = _phase, itemCount = _itemCount,
            message = _message;
- (instancetype)initWithCategory:(NSUInteger)category
                           phase:(PCNativeImportPhase)phase
                           count:(NSUInteger)count
                         message:(NSString*)message {
  if ((self = [super init])) {
    _category = static_cast<PCNativeImportCategories>(category);
    _phase = phase;
    _itemCount = count;
    _message = [message copy];
  }
  return self;
}
@end
@implementation PCNativeImportResult
@synthesize outcome = _outcome, completedCategories = _completedCategories,
            failedCategories = _failedCategories, bookmarks = _bookmarks,
            historyVisitCounts = _historyVisitCounts,
            warnings = _warnings, error = _error;
- (instancetype)initWithOutcome:(PCNativeImportOutcome)outcome
                      completed:(NSUInteger)completed
                         failed:(NSUInteger)failed
                      bookmarks:(NSArray<PCNativeImportedBookmark*>*)bookmarks
             historyVisitCounts:(NSDictionary<NSString*, NSNumber*>*)historyVisitCounts
                       warnings:(NSArray<NSString*>*)warnings
                          error:(NSError*)error {
  if ((self = [super init])) {
    _outcome = outcome;
    _completedCategories = static_cast<PCNativeImportCategories>(completed);
    _failedCategories = static_cast<PCNativeImportCategories>(failed);
    _bookmarks = [bookmarks copy];
    _historyVisitCounts = [historyVisitCounts copy];
    _warnings = [warnings copy];
    _error = error;
  }
  return self;
}
@end
namespace parc::importer {
namespace {
std::map<std::string, const void*>& DestinationOwners() {
  static base::NoDestructor<std::map<std::string, const void*>> owners;
  return *owners;
}
}
bool ReserveImportDestination(NSString* path, const void* owner) {
  CHECK(NSThread.isMainThread);
  return DestinationOwners().emplace(base::SysNSStringToUTF8(path), owner).second;
}
void ReleaseImportDestination(NSString* path, const void* owner) {
  CHECK(NSThread.isMainThread);
  auto it = DestinationOwners().find(base::SysNSStringToUTF8(path));
  if (it != DestinationOwners().end() && it->second == owner) DestinationOwners().erase(it);
}
namespace {
using Progress = void (^)(PCNativeImportEvent*);
using Completion = void (^)(PCNativeImportResult*);
constexpr char kKeychainRefused[] = "macOS Keychain access was not authorized.";
struct KeyResult {
  std::vector<uint8_t> bytes;
  std::string error;
  bool refused = false;
  bool missing = false;
};
KeyResult ReadKeyItem(const std::string& service, const std::string& account) {
  @autoreleasepool {
    NSDictionary* query = @{
      (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrService : base::SysUTF8ToNSString(service),
      (__bridge id)kSecAttrAccount : base::SysUTF8ToNSString(account),
      (__bridge id)kSecReturnData : @YES,
      (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef value = nullptr;
    OSStatus status =
        SecItemCopyMatching((__bridge CFDictionaryRef)query, &value);
    const bool refused =
        status == errSecUserCanceled || status == errSecAuthFailed;
    if (status != errSecSuccess || !value)
      return {{},
              refused ? kKeychainRefused
                      : "The source browser's encryption key is unavailable.",
              refused, status == errSecItemNotFound};
    if (CFGetTypeID(value) != CFDataGetTypeID()) {
      CFRelease(value);
      return {{}, "The source encryption key has an unsupported format."};
    }
    CFDataRef data = static_cast<CFDataRef>(value);
    std::vector<uint8_t> key(16);
    const char salt[] = "saltysalt";
    int derived = CCKeyDerivationPBKDF(
        kCCPBKDF2, reinterpret_cast<const char*>(CFDataGetBytePtr(data)),
        CFDataGetLength(data), reinterpret_cast<const uint8_t*>(salt),
        sizeof(salt) - 1, kCCPRFHmacAlgSHA1, 1003, key.data(), key.size());
    CFRelease(value);
    if (derived != kCCSuccess) {
      std::fill(key.begin(), key.end(), 0);
      return {{}, "The source encryption key could not be prepared."};
    }
    return {std::move(key), {}};
  }
}
KeyResult ReadKey(const Installation& source) {
  if (source.key_service.empty())
    return {{}, "The source browser keeps its encryption key where other apps cannot read it."};
  KeyResult result = ReadKeyItem(source.key_service, source.key_account);
  for (const auto& [service, account] : source.key_fallbacks) {
    if (!result.missing)
      break;
    result = ReadKeyItem(service, account);
  }
  return result;
}
NSArray<PCNativeImportedBookmark*>* Tree(
    const std::vector<mojom::BookmarkPtr>& rows,
    bool* valid) {
  std::map<std::string, const mojom::Bookmark*> ids;
  std::map<std::string, std::vector<const mojom::Bookmark*>> children;
  *valid = false;
  for (const auto& row : rows) {
    if (row->id.empty() || ids.contains(row->id) ||
        (!row->folder && !GURL(row->url).is_valid()))
      return @[];
    ids[row->id] = row.get();
    children[row->parent].push_back(row.get());
  }
  for (const auto& row : rows)
    if (!row->parent.empty() &&
        (!ids.contains(row->parent) || !ids[row->parent]->folder))
      return @[];
  std::set<std::string> visited;
  bool okay = true;
  std::function<NSArray<PCNativeImportedBookmark*>*(const std::string&, int)>
      build;
  build = [&](const std::string& parent,
              int depth) -> NSArray<PCNativeImportedBookmark*>* {
    if (depth > 128) {
      okay = false;
      return @[];
    }
    NSMutableArray* result = [NSMutableArray array];
    for (const auto* row : children[parent]) {
      if (!visited.insert(row->id).second) {
        okay = false;
        break;
      }
      auto nested = build(row->id, depth + 1);
      NSURL* url =
          row->folder ? nil
                      : [NSURL URLWithString:base::SysUTF8ToNSString(row->url)];
      [result
          addObject:[[PCNativeImportedBookmark alloc]
                        initWithIdentifier:base::SysUTF8ToNSString(row->id)
                                     title:base::SysUTF8ToNSString(row->title)
                                       URL:url
                                  children:nested]];
    }
    return result;
  };
  auto result = build("", 0);
  *valid = okay && visited.size() == rows.size();
  return *valid ? result : @[];
}
class Session;
std::map<std::string, std::weak_ptr<Session>>& Active() {
  static base::NoDestructor<std::map<std::string, std::weak_ptr<Session>>>
      sessions;
  return *sessions;
}
using KeyCallback = base::OnceCallback<void(const std::vector<uint8_t>&,
                                            const std::string&)>;
std::map<const Installation*, std::vector<KeyCallback>>& KeyRequests() {
  static base::NoDestructor<
      std::map<const Installation*, std::vector<KeyCallback>>>
      requests;
  return *requests;
}
void KeyRead(std::shared_ptr<const Installation> source, KeyResult key) {
  std::vector<KeyCallback> waiting;
  if (auto it = KeyRequests().find(source.get()); it != KeyRequests().end()) {
    waiting = std::move(it->second);
    KeyRequests().erase(it);
  }
  if (key.refused)
    source->key.refused = true;
  if (!key.bytes.empty())
    source->key.bytes = key.bytes;
  for (auto& callback : waiting)
    std::move(callback).Run(key.bytes, key.error);
  std::fill(key.bytes.begin(), key.bytes.end(), 0);
}
void RequestSourceKey(std::shared_ptr<const Installation> source,
                      KeyCallback callback) {
  CHECK(NSThread.isMainThread);
  const auto& cached = source->key;
  if (!cached.bytes.empty() || cached.refused) {
    std::move(callback).Run(cached.bytes,
                            cached.refused ? kKeychainRefused : "");
    return;
  }
  auto& waiting = KeyRequests()[source.get()];
  waiting.push_back(std::move(callback));
  if (waiting.size() > 1)
    return;
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&ReadKey, *source), base::BindOnce(&KeyRead, source));
}
class Session final : public ProfileObserver,
                      public std::enable_shared_from_this<Session> {
 public:
  Session(std::shared_ptr<const ProfileData> source,
          NSString* path,
          NSUInteger categories,
          bool skip,
          Progress progress,
          Completion completion)
      : source_(std::move(source)),
        path_([path copy]),
        requested_(categories),
        remaining_(categories),
        skip_(skip),
        progress_([progress copy]),
        completion_([completion copy]) {}
  ~Session() override { Stop(); }
  bool Reserve() {
    const auto key = base::SysNSStringToUTF8(path_);
    auto& active = Active();
    if (auto existing = active[key].lock())
      return false;
    if (!ReserveImportDestination(path_, this)) return false;
    active[key] = shared_from_this();
    lifetime_ = shared_from_this();
    return true;
  }
  void Start() {
    if (finished_ || cancelled_)
      return;
    std::weak_ptr<Session> weak = shared_from_this();
    WithNativeProfile(
        path_,
        base::BindOnce(
            [](std::weak_ptr<Session> weak, Profile* profile,
               parc::NativeProfileLeasePtr context, NSError* error) {
              if (auto self = weak.lock()) {
                if (self->finished_)
                  return;
                if (error || !profile || !context ||
                    profile->IsOffTheRecord()) {
                  self->Finish(
                      PCNativeImportOutcomeFailed,
                      error
                          ?: ImportError(
                                 @"The destination Profile is unavailable."));
                  return;
                }
                self->profile_ = profile->GetWeakPtr();
                self->context_ = context;
                profile->AddObserver(self.get());
                self->observing_ = true;
                self->Prepare();
              }
            },
            weak));
  }
  void Cancel() {
    if (finished_)
      return;
    cancelled_ = true;
    deadline_.Stop();
    if (reader_) {
      reader_->Cancel();
      reader_.reset();
    }
    if (writer_) {
      writer_->Cancel();
      return;
    }
    Finish(PCNativeImportOutcomeCancelled, nil);
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    observing_ = false;
    profile_.reset();
    cancelled_ = true;
    failure_ = ImportError(@"The destination Profile closed during import. "
                           @"Pending writes could not be confirmed.");
    deadline_.Stop();
    if (reader_) {
      reader_->Cancel();
      reader_.reset();
    }
    if (writer_) {
      writer_->OnProfileDestroyed();
      return;
    }
    Finish(PCNativeImportOutcomeCancelled, failure_);
  }

 private:
  bool Valid() const {
    return !finished_ && !cancelled_ && profile_ && !profile_->IsOffTheRecord() &&
           !profile_->ShutdownStarted() &&
           context_ && context_->profile() == profile_.get();
  }
  void Prepare() {
    if (!Valid()) {
      Finish(PCNativeImportOutcomeCancelled, nil);
      return;
    }
    std::string source_error;
    if (!SourceReady(*source_, source_error)) {
      Finish(PCNativeImportOutcomeFailed,
             ImportError(base::SysUTF8ToNSString(source_error)));
      return;
    }
    if (source_->path.value() == base::SysNSStringToUTF8(path_)) {
      Finish(PCNativeImportOutcomeFailed,
             ImportError(@"A Profile cannot be imported into itself."));
      return;
    }
    encrypted_ = (requested_ & (PCNativeImportCategoryCookies |
                                PCNativeImportCategoryPasswords |
                                PCNativeImportCategoryAutofill)) != 0;
    const bool bookmarks = (requested_ & PCNativeImportCategoryBookmarks) != 0;
    const auto& cached = source_->source->key;
    if (source_->source->family != 0 || !(encrypted_ || bookmarks)) {
      Launch();
    } else if (encrypted_ || !cached.bytes.empty() || cached.refused) {
      RequestKey();
    } else {
      base::ThreadPool::PostTaskAndReplyWithResult(
          FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
          base::BindOnce(&ChromiumBookmarksNeedKey, source_->path),
          base::BindOnce(
              [](std::weak_ptr<Session> weak, bool needed) {
                if (auto self = weak.lock(); self && !self->finished_) {
                  if (needed)
                    self->RequestKey();
                  else
                    self->Launch();
                }
              },
              weak_from_this()));
    }
  }
  void RequestKey() {
    RequestSourceKey(
        source_->source,
        base::BindOnce(
            [](std::weak_ptr<Session> weak, const std::vector<uint8_t>& bytes,
               const std::string& error) {
              if (auto self = weak.lock(); self && !self->finished_)
                self->UseKey(bytes, error);
            },
            weak_from_this()));
  }
  void UseKey(const std::vector<uint8_t>& bytes, const std::string& error) {
    key_ = bytes;
    if (encrypted_ && !error.empty())
      [warnings_ addObject:base::SysUTF8ToNSString(error)];
    Launch();
  }
  void Launch() {
    if (!remaining_) {
      Finish(PCNativeImportOutcomeCompleted, nil);
      return;
    }
    if (!Valid()) {
      Finish(PCNativeImportOutcomeCancelled, nil);
      return;
    }
    content::ServiceProcessHost::Launch(
        reader_.BindNewPipeAndPassReceiver(),
        content::ServiceProcessHost::Options()
            .WithDisplayName("Browser data import")
            .Pass());
    reader_.set_disconnect_handler(base::BindOnce(
        [](std::weak_ptr<Session> weak) {
          if (auto self = weak.lock())
            self->FailAfterDrain(
                ImportError(@"The import reader stopped unexpectedly."));
        },
        weak_from_this()));
    Next();
  }
  void Event(NSUInteger category,
             PCNativeImportPhase phase,
             NSUInteger count,
             NSString* message) {
    if (!progress_ || finished_)
      return;
    auto event = [[PCNativeImportEvent alloc] initWithCategory:category
                                                         phase:phase
                                                         count:count
                                                       message:message];
    auto callback = progress_;
    std::weak_ptr<Session> weak = shared_from_this();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (auto self = weak.lock(); self && !self->cancelled_)
        callback(event);
    });
  }
  void Next() {
    writer_.reset();
    deadline_.Stop();
    if (cancelled_ || !Valid()) {
      Finish(PCNativeImportOutcomeCancelled, failure_);
      return;
    }
    if (!remaining_) {
      Finish(failure_ || failed_
                 ? ((completed_ || written_any_) ? PCNativeImportOutcomePartial
                                                 : PCNativeImportOutcomeFailed)
                 : PCNativeImportOutcomeCompleted,
             failure_);
      return;
    }
    std::string source_error;
    if (!SourceReady(*source_, source_error)) {
      failed_ |= remaining_;
      remaining_ = 0;
      Finish((completed_ || written_any_) ? PCNativeImportOutcomePartial
                                          : PCNativeImportOutcomeFailed,
             ImportError(base::SysUTF8ToNSString(source_error)));
      return;
    }
    active_ = remaining_ & (~remaining_ + 1);
    remaining_ &= ~active_;
    Event(active_, PCNativeImportPhaseReading, 0, nil);
    auto source = mojom::Source::New();
    source->family = static_cast<mojom::Family>(source_->source->family);
    source->profile_path = source_->path.value();
    source->app_path = source_->source->app_path.value();
    source->source_name = source_->source->name;
    source->source_key = key_;
    deadline_.Start(FROM_HERE, base::Minutes(5),
                    base::BindOnce(
                        [](std::weak_ptr<Session> weak) {
                          if (auto self = weak.lock()) {
                            self->FailAfterDrain(ImportError(
                                @"The import did not finish. Already saved "
                                @"data remains available."));
                          }
                        },
                        weak_from_this()));
    reader_->ReadCategory(
        std::move(source), active_,
        base::BindOnce(
            [](std::weak_ptr<Session> weak, mojom::BatchPtr batch) {
              if (auto self = weak.lock())
                self->ReadFinished(std::move(batch));
            },
            weak_from_this()));
  }
  void FailAfterDrain(NSError* error) {
    if (finished_)
      return;
    failure_ = error;
    failed_ |= remaining_;
    remaining_ = 0;
    deadline_.Stop();
    if (reader_) {
      reader_->Cancel();
      reader_.reset();
    }
    if (writer_) {
      writer_->Cancel();
      return;
    }
    failed_ |= active_;
    Next();
  }
  void ReadFinished(mojom::BatchPtr batch) {
    if (finished_ || failure_)
      return;
    if (!Valid()) {
      Finish(PCNativeImportOutcomeCancelled, nil);
      return;
    }
    if (!batch || batch->category != active_) {
      FailAfterDrain(
          ImportError(@"The import reader returned an invalid category."));
      return;
    }
    for (const auto& warning : batch->warnings)
      [warnings_ addObject:base::SysUTF8ToNSString(warning)];
    if (!batch->success) {
      failed_ |= active_;
      [warnings_ addObject:base::SysUTF8ToNSString(batch->error)];
      Event(active_, PCNativeImportPhaseFinished, 0,
            base::SysUTF8ToNSString(batch->error));
      Next();
      return;
    }
    std::string source_error;
    if (!SourceReady(*source_, source_error)) {
      failed_ |= active_;
      [warnings_ addObject:base::SysUTF8ToNSString(source_error)];
      Next();
      return;
    }
    if (active_ == 2) {
      bool valid = false;
      auto tree = Tree(batch->bookmarks, &valid);
      if (valid) {
        bookmarks_ = tree;
        completed_ |= active_;
        Event(active_, PCNativeImportPhaseFinished, batch->bookmarks.size(),
              nil);
      } else {
        failed_ |= active_;
        [warnings_ addObject:@"The source bookmark tree is inconsistent and "
                             @"was not imported."];
      }
      Next();
      return;
    }
    if (active_ == PCNativeImportCategoryHistory &&
        (requested_ & PCNativeImportCategoryBookmarks)) {
      for (const auto& row : batch->history) {
        if (!GURL(row->url).is_valid() || row->visits < 0 ||
            row->last_visit <= 0 || row->typed < 0)
          continue;
        NSString* key = base::SysUTF8ToNSString(row->url);
        if (!key)
          continue;
        NSNumber* existing = history_visit_counts_[key];
        if (!existing || existing.intValue < row->visits)
          history_visit_counts_[key] = @(row->visits);
      }
    }
    Event(active_, PCNativeImportPhaseWriting, 0, nil);
    writer_ = WriteImportBatch(
        *profile_, source_->source->family, std::move(batch), skip_,
        base::BindOnce(
            [](std::weak_ptr<Session> weak, WriteResult result) {
              if (auto self = weak.lock()) {
                if (self->finished_)
                  return;
                if (result.count)
                  self->written_any_ = true;
                if (!result.warning.empty())
                  [self->warnings_
                      addObject:base::SysUTF8ToNSString(result.warning)];
                if (result.success)
                  self->completed_ |= self->active_;
                else {
                  self->failed_ |= self->active_;
                  [self->warnings_
                      addObject:base::SysUTF8ToNSString(result.error)];
                }
                self->Event(self->active_, PCNativeImportPhaseFinished,
                            result.count,
                            result.error.empty()
                                ? nil
                                : base::SysUTF8ToNSString(result.error));
                self->Next();
              }
            },
            weak_from_this()));
  }
  void Finish(PCNativeImportOutcome outcome, NSError* error) {
    if (finished_)
      return;
    auto keep = shared_from_this();
    finished_ = true;
    auto completion = completion_;
    completion_ = nil;
    progress_ = nil;
    auto result = [[PCNativeImportResult alloc] initWithOutcome:outcome
                                                      completed:completed_
                                                         failed:failed_
                                                      bookmarks:bookmarks_
                                             historyVisitCounts:history_visit_counts_
                                                       warnings:warnings_
                                                          error:error];
    Stop();
    lifetime_.reset();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (completion)
        completion(result);
    });
  }
  void Stop() {
    deadline_.Stop();
    if (reader_) {
      reader_->Cancel();
      reader_.reset();
    }
    if (writer_)
      writer_->Cancel();
    writer_.reset();
    std::fill(key_.begin(), key_.end(), 0);
    key_.clear();
    if (observing_ && profile_)
      profile_->RemoveObserver(this);
    observing_ = false;
    profile_.reset();
    context_ = nullptr;
    ReleaseImportDestination(path_, this);
    auto key = base::SysNSStringToUTF8(path_);
    auto it = Active().find(key);
    if (it != Active().end()) {
      auto current = it->second.lock();
      if (!current || current.get() == this)
        Active().erase(it);
    }
  }
  std::shared_ptr<Session> lifetime_;
  std::shared_ptr<const ProfileData> source_;
  NSString* __strong path_;
  NSUInteger requested_, remaining_, active_ = 0, completed_ = 0, failed_ = 0;
  bool written_any_ = false;
  bool skip_, cancelled_ = false, finished_ = false, observing_ = false,
       encrypted_ = false;
  NSError* __strong failure_;
  Progress __strong progress_;
  Completion __strong completion_;
  NSArray<PCNativeImportedBookmark*>* __strong bookmarks_ = @[];
  NSMutableDictionary<NSString*, NSNumber*>* __strong history_visit_counts_ =
      [NSMutableDictionary dictionary];
  NSMutableArray<NSString*>* __strong warnings_ = [NSMutableArray array];
  base::WeakPtr<Profile> profile_;
  parc::NativeProfileLeasePtr context_;
  std::vector<uint8_t> key_;
  mojo::Remote<mojom::Reader> reader_;
  std::shared_ptr<ImportWriter> writer_;
  base::OneShotTimer deadline_;
};
constexpr int64_t kSidebarKeyWait = 5 * 60;
constexpr int64_t kSidebarReadWait = 60;
constexpr char kSidebarUnreadable[] =
    "The encrypted browser file could not be read.";
class SidebarDecryption {
 public:
  SidebarDecryption() : signal_(dispatch_semaphore_create(0)) {}
  ~SidebarDecryption() { std::fill(data_.begin(), data_.end(), 0); }
  SidebarDecryption(const SidebarDecryption&) = delete;
  SidebarDecryption& operator=(const SidebarDecryption&) = delete;
  bool Done() {
    base::AutoLock hold(lock_);
    return done_;
  }
  void Launched() {
    {
      base::AutoLock hold(lock_);
      launched_ = true;
    }
    dispatch_semaphore_signal(signal_);
  }
  void Finish(std::vector<uint8_t> data, std::string error) {
    {
      base::AutoLock hold(lock_);
      if (done_) {
        std::fill(data.begin(), data.end(), 0);
        return;
      }
      done_ = true;
      data_ = std::move(data);
      error_ = std::move(error);
    }
    dispatch_semaphore_signal(signal_);
  }
  NSData* Wait(std::string& error) {
    bool reading = false;
    dispatch_time_t deadline =
        dispatch_time(DISPATCH_TIME_NOW, kSidebarKeyWait * NSEC_PER_SEC);
    for (;;) {
      if (dispatch_semaphore_wait(signal_, deadline) != 0) {
        Finish({}, "Reading the encrypted browser file took too long.");
        break;
      }
      base::AutoLock hold(lock_);
      if (done_)
        break;
      if (launched_ && !reading) {
        reading = true;
        deadline =
            dispatch_time(DISPATCH_TIME_NOW, kSidebarReadWait * NSEC_PER_SEC);
      }
    }
    base::AutoLock hold(lock_);
    if (!error_.empty() || data_.empty()) {
      error = error_.empty() ? kSidebarUnreadable : error_;
      return nil;
    }
    NSData* result = [NSData dataWithBytes:data_.data() length:data_.size()];
    std::fill(data_.begin(), data_.end(), 0);
    data_.clear();
    return result;
  }

 private:
  dispatch_semaphore_t __strong signal_;
  base::Lock lock_;
  bool done_ = false, launched_ = false;
  std::vector<uint8_t> data_;
  std::string error_;
};
std::map<const SidebarDecryption*, mojo::Remote<mojom::Reader>>&
SidebarReaders() {
  static base::NoDestructor<
      std::map<const SidebarDecryption*, mojo::Remote<mojom::Reader>>>
      readers;
  return *readers;
}
void SidebarFinished(std::shared_ptr<SidebarDecryption> request,
                     mojom::DecryptedFilePtr file) {
  SidebarReaders().erase(request.get());
  if (!file)
    request->Finish({}, "The import reader stopped unexpectedly.");
  else if (!file->success)
    request->Finish({}, file->error.empty() ? kSidebarUnreadable : file->error);
  else
    request->Finish(std::move(file->data), {});
}
void SidebarKeyReady(std::shared_ptr<SidebarDecryption> request,
                     std::shared_ptr<const ProfileData> profile,
                     base::FilePath file,
                     base::FilePath directory,
                     mojom::SidebarFormat format,
                     const std::vector<uint8_t>& key,
                     const std::string& error) {
  if (request->Done())
    return;
  if (key.empty()) {
    request->Finish(
        {}, error.empty() ? "The source browser's encryption key is "
                            "unavailable."
                          : error);
    return;
  }
  request->Launched();
  auto& reader = SidebarReaders()[request.get()];
  content::ServiceProcessHost::Launch(
      reader.BindNewPipeAndPassReceiver(),
      content::ServiceProcessHost::Options()
          .WithDisplayName("Browser data import")
          .Pass());
  reader.set_disconnect_handler(base::BindOnce(
      [](std::shared_ptr<SidebarDecryption> request) {
        base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(&SidebarFinished, request,
                                      mojom::DecryptedFilePtr()));
      },
      request));
  auto source = mojom::Source::New();
  source->family = mojom::Family::kChromium;
  source->profile_path = directory.value();
  source->app_path = profile->source->app_path.value();
  source->source_name = profile->source->name;
  source->source_key = key;
  reader->DecryptSidebarFile(std::move(source), file.value(), format,
                             base::BindOnce(&SidebarFinished, request));
}
NSData* DecryptProfileFile(std::shared_ptr<const ProfileData> data,
                           NSURL* file,
                           PCNativeImportSidebarFormat format,
                           std::string& error) {
  constexpr char kOutside[] =
      "The requested file is not part of the source browser.";
  if (NSThread.isMainThread) {
    error = "Encrypted browser files are read off the main thread.";
    return nil;
  }
  if (format != PCNativeImportSidebarFormatChromiumSession &&
      format != PCNativeImportSidebarFormatDiaTabs) {
    error = "This encrypted browser file format is unsupported.";
    return nil;
  }
  if (!data || data->source->family != 0 ||
      data->source->key_service.empty() || data->root.empty()) {
    error = "This browser's encrypted files cannot be read.";
    return nil;
  }
  if (!file.isFileURL || !file.path.isAbsolutePath) {
    error = kOutside;
    return nil;
  }
  if (!SourceReady(*data, error))
    return nil;
  const bool dia = format == PCNativeImportSidebarFormatDiaTabs;
  const base::FilePath requested(base::SysNSStringToUTF8(file.path));
  const base::FilePath parent =
      requested.ReferencesParent()
          ? base::FilePath()
          : base::MakeAbsoluteFilePath(requested.DirName());
  const base::FilePath directory = dia ? parent : parent.DirName();
  const std::string name = requested.BaseName().value();
  if (parent.empty() ||
      (dia ? name != kDiaTabs
           : parent.BaseName().value() != kChromiumEncryptedSessions) ||
      !(directory == data->root || data->root.IsParent(directory)) ||
      !base::PathExists(directory.AppendASCII("Preferences"))) {
    error = kOutside;
    return nil;
  }
  auto request = std::make_shared<SidebarDecryption>();
  const base::FilePath target = parent.Append(name);
  const auto kind = dia ? mojom::SidebarFormat::kDiaTabs
                        : mojom::SidebarFormat::kChromiumSession;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!request->Done())
      RequestSourceKey(data->source,
                       base::BindOnce(&SidebarKeyReady, request, data, target,
                                      directory, kind));
  });
  NSData* plain = request->Wait(error);
  if (!plain)
    dispatch_async(dispatch_get_main_queue(), ^{
      SidebarReaders().erase(request.get());
    });
  return plain;
}
}
}
@implementation PCNativeImportProfile (SidebarFiles)
- (BOOL)canDecryptSidebarFiles {
  auto data = [self profileData];
  return data && data->source->family == 0 &&
         !data->source->key_service.empty();
}
- (NSData*)decryptSidebarFile:(NSURL*)file
                       format:(PCNativeImportSidebarFormat)format
                        error:(NSError**)error {
  std::string failure;
  NSData* plain = parc::importer::DecryptProfileFile(
      [self profileData], file, format, failure);
  if (!plain && error)
    *error = parc::importer::ImportError(base::SysUTF8ToNSString(failure));
  return plain;
}
@end
@implementation PCNativeImportSession {
  void (^_cancel)(void);
}
- (instancetype)initWithCancel:(void (^)(void))cancel {
  if ((self = [super init]))
    _cancel = [cancel copy];
  return self;
}
- (void)cancel {
  if (_cancel)
    _cancel();
}
- (void)dealloc {
  [self cancel];
}
@end
@implementation PCNativeBrowserApplication (DirectBrowserImportExecution)
+ (PCNativeImportSession*)
    importBrowserDataFromProfile:(PCNativeImportProfile*)source
                   toProfilePath:(NSString*)profilePath
                        inWindow:(NSWindow*)window
                      categories:(PCNativeImportCategories)categories
             skipExistingCookies:(BOOL)skip
                        progress:(void (^)(PCNativeImportEvent*))progress
                      completion:(void (^)(PCNativeImportResult*))completion {
  CHECK(NSThread.isMainThread);
  auto data = [source profileData];
  if (!data || !window || !window.visible || !profilePath.isAbsolutePath ||
      ![profilePath isEqual:profilePath.stringByStandardizingPath] ||
      !categories || (categories & ~data->categories) ||
      (categories & PCNativeImportCategoryExtensions))
    return nil;
  auto session = std::make_shared<parc::importer::Session>(
      data, profilePath, categories, skip, progress, completion);
  if (!session->Reserve())
    return nil;
  auto lease = [[PCNativeImportSession alloc] initWithCancel:^{
    session->Cancel();
  }];
  dispatch_async(dispatch_get_main_queue(), ^{
    session->Start();
  });
  return lease;
}
@end

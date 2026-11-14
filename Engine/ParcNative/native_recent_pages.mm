// Copyright 2026 Parc contributors.
#import "native_appkit_bridge.h"
#include "native_appkit_host.h"
#include "native_profiles.h"
#include "native_internal_urls.h"

#include <memory>
#include <optional>
#include <string_view>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_split.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "url/gurl.h"

@interface PCNativeRecentPage ()
- (instancetype)initWithURL:(NSURL*)url title:(NSString*)title date:(NSDate*)date;
@end
@implementation PCNativeRecentPage
@synthesize url = _url;
@synthesize title = _title;
@synthesize visitedAt = _visitedAt;
- (instancetype)initWithURL:(NSURL*)url title:(NSString*)title date:(NSDate*)date {
  if ((self = [super init])) {
    _url = [url copy];
    _title = [title copy];
    _visitedAt = [date copy];
  }
  return self;
}
@end

namespace parc {
namespace {
enum class RecentDomain { kNotion, kFigma, kLinear, kConfluence, kAll };
std::optional<RecentDomain> Domain(NSString* value) {
  if ([value isEqualToString:@"notion"]) return RecentDomain::kNotion;
  if ([value isEqualToString:@"figma"]) return RecentDomain::kFigma;
  if ([value isEqualToString:@"linear"]) return RecentDomain::kLinear;
  if ([value isEqualToString:@"confluence"]) return RecentDomain::kConfluence;
  if ([value isEqualToString:@"all"]) return RecentDomain::kAll;
  return std::nullopt;
}
std::u16string SearchText(RecentDomain domain) {
  switch (domain) {
    case RecentDomain::kNotion: return u"notion.";
    case RecentDomain::kFigma: return u"figma.com/";
    case RecentDomain::kLinear: return u"linear.app/";
    case RecentDomain::kConfluence: return u"atlassian.net/wiki/";
    case RecentDomain::kAll: return std::u16string();
  }
}
bool Matches(RecentDomain domain, const GURL& url) {
  if (!url.is_valid() || !url.SchemeIsHTTPOrHTTPS()) return false;
  switch (domain) {
    case RecentDomain::kNotion:
      return url.DomainIs("notion.so") || url.DomainIs("notion.site");
    case RecentDomain::kFigma: return url.DomainIs("figma.com");
    case RecentDomain::kLinear: return url.DomainIs("linear.app");
    case RecentDomain::kConfluence:
      if (!url.DomainIs("atlassian.net")) return false;
      for (const auto part : base::SplitStringPiece(
               url.path(), "/", base::KEEP_WHITESPACE,
               base::SPLIT_WANT_NONEMPTY)) {
        if (part == "wiki") return true;
      }
      return false;
    case RecentDomain::kAll: return true;
  }
}

// The hover owner retains the lease. Cancellation never recreates a page or
// delivers stale history into a subsequent hover/profile generation.
class RecentPagesQuery final : public ProfileObserver {
 public:
  using Reply = void (^)(NSArray<PCNativeRecentPage*>*);
  RecentPagesQuery(RecentDomain domain, Reply reply)
      : domain_(domain), reply_([reply copy]) {}
  ~RecentPagesQuery() override { Cancel(); }

  void Start(NSString* path) {
    deadline_.Start(FROM_HERE, base::Milliseconds(500),
                    base::BindOnce(&RecentPagesQuery::FinishEmpty,
                                   weak_factory_.GetWeakPtr()));
    WithNativeProfile(path, base::BindOnce(
        [](base::WeakPtr<RecentPagesQuery> query, Profile* profile,
           parc::NativeProfileLeasePtr context, NSError* error) {
          if (!query || query->finished_) return;
          if (!profile || !context || error) {
            query->FinishEmpty();
            return;
          }
          query->lease_ = std::move(context);
          query->Begin(*profile);
        }, weak_factory_.GetWeakPtr()));
  }
  void Cancel() {
    CHECK(NSThread.isMainThread);
    reply_ = nil;
    finished_ = true;
    deadline_.Stop();
    tasks_.TryCancelAll();
    weak_factory_.InvalidateWeakPtrs();
    DetachProfile();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    profile_.reset();
    FinishEmpty();
  }

 private:
  void Begin(Profile& profile) {
    CHECK(NSThread.isMainThread);
    if (profile.IsOffTheRecord() || (!lease_ || lease_->profile() != &profile)) {
      FinishEmpty();
      return;
    }
    auto* service = HistoryServiceFactory::GetForProfile(
        &profile, ServiceAccessType::EXPLICIT_ACCESS);
    if (!service) { FinishEmpty(); return; }
    profile_ = profile.GetWeakPtr();
    profile.AddObserver(this);
    history::QueryOptions options;
    options.end_time = base::Time::Now();
    if (domain_ == RecentDomain::kAll) {
      // The command bar's empty list: the newest pages in all of the
      // profile's history, imported visits included. It shows at most eight
      // once open tabs and the current page are left out.
      options.max_count = 50;
    } else {
      options.begin_time = options.end_time - base::Days(30);
    }
    options.duplicate_policy = history::QueryOptions::REMOVE_ALL_DUPLICATES;
    options.policy_for_404_visits = history::VisitQuery404sPolicy::kInclude404s;
    const auto task = service->QueryHistory(SearchText(domain_), options,
        base::BindOnce(&RecentPagesQuery::Completed, weak_factory_.GetWeakPtr()),
        &tasks_);
    if (task == base::CancelableTaskTracker::kBadTaskId) FinishEmpty();
  }
  void Completed(history::QueryResults results) {
    if (finished_) return;
    NSMutableArray<PCNativeRecentPage*>* pages = [[NSMutableArray alloc] init];
    if (profile_ && lease_ && lease_->profile() == profile_.get()) {
      for (const auto& result : results) {
        if (!Matches(domain_, result.url())) continue;
        NSURL* url = [NSURL URLWithString:base::SysUTF8ToNSString(parc::PublicInternalURL(result.url()).spec())];
        if (!url) continue;
        [pages addObject:[[PCNativeRecentPage alloc]
            initWithURL:url title:base::SysUTF16ToNSString(result.title())
            date:[NSDate dateWithTimeIntervalSince1970:
                result.visit_time().InSecondsFSinceUnixEpoch()]]];
      }
    }
    Finish([pages copy]);
  }
  void FinishEmpty() { Finish(@[]); }
  void Finish(NSArray<PCNativeRecentPage*>* pages) {
    if (finished_) return;
    finished_ = true;
    deadline_.Stop();
    tasks_.TryCancelAll();
    // Never call the shell from the service callback, profile observer or
    // factory stack. Destroying the lease from its reply is safe.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce(&RecentPagesQuery::Deliver, weak_factory_.GetWeakPtr(), pages));
  }
  void Deliver(NSArray<PCNativeRecentPage*>* pages) {
    if (!reply_) return;
    if (!profile_ || !lease_ || lease_->profile() != profile_.get()) pages = @[];
    auto reply = reply_;
    reply_ = nil;
    DetachProfile();
    weak_factory_.InvalidateWeakPtrs();
    reply(pages);
  }
  void DetachProfile() {
    if (profile_) profile_->RemoveObserver(this);
    profile_.reset();
    lease_.reset();
  }
  parc::NativeProfileLeasePtr lease_;
  RecentDomain domain_;
  Reply reply_;
  bool finished_ = false;
  base::WeakPtr<Profile> profile_;
  base::CancelableTaskTracker tasks_;
  base::OneShotTimer deadline_;
  base::WeakPtrFactory<RecentPagesQuery> weak_factory_{this};
};
}  // namespace
}  // namespace parc

@interface PCNativeHistoryQuery () {
 @public
  std::unique_ptr<parc::RecentPagesQuery> state;
}
@end
@implementation PCNativeHistoryQuery
- (void)invalidate { state.reset(); }
@end

@implementation PCNativeBrowserApplication (RecentPages)
+ (PCNativeHistoryQuery*)recentPagesForDomain:(NSString*)domain
                                profilePath:(NSString*)path
                                 completion:(void (^)(NSArray<PCNativeRecentPage*>*))completion {
  CHECK(NSThread.isMainThread);
  const auto selected = parc::Domain(domain);
  if (!selected || !path.length || !completion) return nil;
  PCNativeHistoryQuery* query = [[PCNativeHistoryQuery alloc] init];
  query->state = std::make_unique<parc::RecentPagesQuery>(*selected, completion);
  query->state->Start(path);
  return query;
}
@end

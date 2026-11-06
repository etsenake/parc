// Copyright 2026 Parc contributors.
#import "native_appkit_bridge.h"
#include "native_appkit_host.h"

#include <map>
#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/favicon/core/favicon_service.h"
#include "components/favicon_base/favicon_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace parc {
namespace {
using IconReply = void (^)(NSImage*);
const char kFaviconRequestsKey = 0;

// Always deliver outside the service/profile observer stack. The caller owns
// its view-generation checks; no view or page is retained by this service.
void Deliver(IconReply reply, NSImage* image,
             base::WeakPtr<Profile> profile = {}) {
  dispatch_async(dispatch_get_main_queue(), ^{
    reply(image && profile && NativeContextForProfile(*profile) ? image : nil);
  });
}

class FaviconRequests final : public base::SupportsUserData::Data,
                             public ProfileObserver {
 public:
  explicit FaviconRequests(Profile& profile) : profile_(profile.GetWeakPtr()) {
    profile.AddObserver(this);
  }
  ~FaviconRequests() override {
    if (profile_)
      profile_->RemoveObserver(this);
    CancelAll();
  }

  static FaviconRequests& Get(Profile& profile) {
    auto* requests = static_cast<FaviconRequests*>(
        profile.GetUserData(&kFaviconRequestsKey));
    if (!requests) {
      auto owned = std::make_unique<FaviconRequests>(profile);
      requests = owned.get();
      profile.SetUserData(&kFaviconRequestsKey, std::move(owned));
    }
    return *requests;
  }

  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    profile_.reset();
    CancelAll();
  }

  void Request(const GURL& url, IconReply reply) {
    CHECK(NSThread.isMainThread);
    // Archive belongs to its saved persistent profile. An OTR profile must
    // not silently redirect this history lookup to another profile's store.
    if (!profile_ || profile_->IsOffTheRecord() ||
        !NativeContextForProfile(*profile_)) {
      Deliver(reply, nil);
      return;
    }
    auto* service = FaviconServiceFactory::GetForProfile(
        profile_.get(), ServiceAccessType::EXPLICIT_ACCESS);
    if (!service) {
      Deliver(reply, nil);
      return;
    }
    const uint64_t identifier = ++next_identifier_;
    replies_.emplace(identifier, [reply copy]);
    // This reads the actual history favicon database. It neither downloads a
    // guessed /favicon.ico nor falls back to a different URL on the host.
    const auto task = service->GetFaviconImageForPageURL(
        url,
        base::BindOnce(&FaviconRequests::Completed,
                       weak_factory_.GetWeakPtr(), identifier),
        &tasks_);
    if (task == base::CancelableTaskTracker::kBadTaskId)
      Finish(identifier, nil);
  }

 private:
  void Completed(uint64_t identifier,
                 const favicon_base::FaviconImageResult& result) {
    CHECK(NSThread.isMainThread);
    NSImage* image = profile_ && NativeContextForProfile(*profile_) &&
                            !result.image.IsEmpty()
                        ? [result.image.AsNSImage() copy]
                        : nil;
    Finish(identifier, image);
  }
  void Finish(uint64_t identifier, NSImage* image) {
    auto found = replies_.find(identifier);
    if (found == replies_.end())
      return;
    IconReply reply = found->second;
    replies_.erase(found);
    Deliver(reply, image, profile_);
  }
  void CancelAll() {
    weak_factory_.InvalidateWeakPtrs();
    tasks_.TryCancelAll();
    auto replies = std::move(replies_);
    replies_.clear();
    for (const auto& [identifier, reply] : replies)
      Deliver(reply, nil);
  }
  base::WeakPtr<Profile> profile_;
  base::CancelableTaskTracker tasks_;
  std::map<uint64_t, IconReply> replies_;
  uint64_t next_identifier_ = 0;
  base::WeakPtrFactory<FaviconRequests> weak_factory_{this};
};
}  // namespace
}  // namespace parc

@implementation PCNativeBrowserApplication (Favicons)
+ (void)faviconForURL:(NSURL*)url
         profilePath:(NSString*)path
          completion:(void (^)(NSImage*))completion {
  CHECK(NSThread.isMainThread);
  const GURL page_url(base::SysNSStringToUTF8(url.absoluteString ?: @""));
  if (!page_url.is_valid()) {
    parc::Deliver(completion, nil);
    return;
  }
  parc::WithNativeProfile(
      path, base::BindOnce(
                [](GURL url, parc::IconReply reply, Profile* profile,
                   CefRefPtr<CefRequestContext> context, NSError* error) {
                  if (!profile || !context || error) {
                    parc::Deliver(reply, nil);
                    return;
                  }
                  parc::FaviconRequests::Get(*profile).Request(url, reply);
                },
                page_url, [completion copy]));
}
@end

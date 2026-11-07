#include "fairplay_hls_keys.h"

#include <algorithm>
#include <deque>
#include <map>
#include <utility>
#include <vector>

#include "fairplay_key_session_internal.h"

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

namespace parc::fairplay {

namespace {

NSError* CancelledError() {
  return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
}

}  // namespace

class FairPlayHlsKeyLoader::Impl : public AssetKeyClient,
                                   public std::enable_shared_from_this<FairPlayHlsKeyLoader::Impl> {
 public:
  Impl(AVURLAsset* asset, FairPlayHlsKeyLoaderClient* client, PostTask post_task)
      : asset_(asset),
        client_(client),
        poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  void Start(FairPlayCdm* cdm) {
    std::shared_ptr<FairPlayCdm::Impl> core = cdm ? cdm->weak_impl().lock() : nullptr;
    if (core && AttachAsset(core.get(), this, asset_).ok()) {
      cdm_ = core;
    }
  }

  // The asset is going away: requests the CDM took and hasn't answered stay
  // as the detach leaves them, and the ones still held here fail.
  void Shutdown() {
    if (auto core = cdm_.lock()) {
      DetachAsset(core.get(), this);
    }
    cdm_.reset();
    for (auto& [uri, queue] : held_) {
      for (const Held& held : queue) {
        [held.request finishLoadingWithError:CancelledError()];
      }
    }
    held_.clear();
  }

  void HandleLoadingRequest(AVAssetResourceLoadingRequest* request) {
    NSString* url = request.request.URL.absoluteString;
    if (!url.length) {
      [request finishLoadingWithError:CancelledError()];
      return;
    }
    std::string uri = url.UTF8String;
    ReportLoadingRequest(uri);  // Posted ahead of anything else it raises.
    // The CDM may answer it at once: a session waiting for the URI, the
    // session whose earlier request AVFoundation cancelled, or one made
    // before the CDM was attached.
    if (auto core = cdm_.lock(); core && OfferLoadingRequest(core.get(), this, uri, request)) {
      return;
    }
    std::deque<Held>& queue = held_[uri];
    queue.push_back({request});
    if (queue.size() == 1) {
      ReportNeed(uri, request);
    }
  }

  void HandleCancelledLoadingRequest(AVAssetResourceLoadingRequest* request) {
    for (auto it = held_.begin(); it != held_.end(); ++it) {
      auto found = std::find_if(it->second.begin(), it->second.end(),
                                [request](const Held& held) { return held.request == request; });
      if (found != it->second.end()) {
        bool was_front = found == it->second.begin();
        it->second.erase(found);
        if (it->second.empty()) {
          held_.erase(it);
        } else if (was_front) {
          ReportNeed(it->first, it->second.front().request);
        }
        return;
      }
    }
    if (auto core = cdm_.lock()) {
      CancelLoadingRequest(core.get(), this, request);
    }
  }

  Result SetCdm(FairPlayCdm* cdm) {
    std::shared_ptr<FairPlayCdm::Impl> next = cdm ? cdm->weak_impl().lock() : nullptr;
    std::shared_ptr<FairPlayCdm::Impl> current = cdm_.lock();
    if (next == current) {
      return Result::Ok();
    }
    // The new CDM first: if it can't take the asset, the old one stays
    // attached, as EME keeps the old MediaKeys when setMediaKeys rejects.
    if (next) {
      Result result = AttachAsset(next.get(), this, asset_);
      if (!result.ok()) {
        return result;
      }
    }
    if (current) {
      DetachAsset(current.get(), this);  // Its unanswered requests stay pending.
    }
    cdm_ = next;
    if (!next) {
      return Result::Ok();
    }
    if (output_obscured_) {
      SetAssetOutputObscured(next.get(), this, true);
    }
    // A session on that CDM may already want one of the held URIs (the page
    // generated the request before attaching its MediaKeys).
    std::vector<std::string> uris;
    for (const auto& [uri, queue] : held_) {
      uris.push_back(uri);
    }
    for (const std::string& uri : uris) {
      auto it = held_.find(uri);
      if (it == held_.end() || it->second.empty()) {
        continue;
      }
      AVAssetResourceLoadingRequest* request = it->second.front().request;
      if (OfferLoadingRequest(next.get(), this, uri, request)) {
        it = held_.find(uri);
        if (it != held_.end() && !it->second.empty() && it->second.front().request == request) {
          it->second.pop_front();
          if (it->second.empty()) {
            held_.erase(it);
          } else {
            ReportNeed(uri, it->second.front().request);  // It needs its own session.
          }
        }
      }
    }
    return Result::Ok();
  }

  void SetOutputObscured(bool obscured) {
    output_obscured_ = obscured;
    if (auto core = cdm_.lock()) {
      SetAssetOutputObscured(core.get(), this, obscured);
    }
  }

  // AssetKeyClient.

  AVAssetResourceLoadingRequest* TakeLoadingRequest(const std::string& uri) override {
    auto it = held_.find(uri);
    if (it == held_.end() || it->second.empty()) {
      return nil;
    }
    AVAssetResourceLoadingRequest* request = it->second.front().request;
    it->second.pop_front();
    if (it->second.empty()) {
      held_.erase(it);
    } else {
      // Each request needs its own SPC and CKC: the next one is a new need.
      ReportNeed(uri, it->second.front().request);
    }
    return request;
  }

 private:
  struct Held {
    AVAssetResourceLoadingRequest* request = nil;
    bool reported = false;  // Its OnKeyNeeded has been delivered.
  };

  void ReportLoadingRequest(const std::string& url) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, url] {
      if (auto impl = weak.lock()) {
        impl->client_->OnKeyLoadingRequest(url);
      }
    });
  }

  // Reports |request|'s need once, if it is still held and first in line for
  // its URI when the report is delivered (a session may have taken it).
  void ReportNeed(const std::string& uri, AVAssetResourceLoadingRequest* request) {
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, uri, request] {
      auto impl = weak.lock();
      if (!impl) {
        return;
      }
      auto it = impl->held_.find(uri);
      if (it == impl->held_.end() || it->second.empty() || it->second.front().request != request ||
          it->second.front().reported) {
        return;
      }
      it->second.front().reported = true;
      impl->client_->OnKeyNeeded(uri);
    });
  }

  AVURLAsset* const asset_;
  FairPlayHlsKeyLoaderClient* const client_;
  const std::shared_ptr<const PostTask> poster_;
  std::weak_ptr<FairPlayCdm::Impl> cdm_;
  bool output_obscured_ = false;
  // skd loading requests not yet answered, oldest first, by URI. Only the
  // first of a URI is reported; the next is when a session takes it.
  std::map<std::string, std::deque<Held>> held_;
};

FairPlayHlsKeyLoader::FairPlayHlsKeyLoader(AVURLAsset* asset,
                                           FairPlayCdm* cdm,
                                           FairPlayHlsKeyLoaderClient* client,
                                           PostTask post_task)
    : impl_(std::make_shared<Impl>(asset, client, std::move(post_task))) {
  impl_->Start(cdm);
}

FairPlayHlsKeyLoader::~FairPlayHlsKeyLoader() {
  impl_->Shutdown();
}

void FairPlayHlsKeyLoader::HandleLoadingRequest(AVAssetResourceLoadingRequest* request) {
  impl_->HandleLoadingRequest(request);
}

void FairPlayHlsKeyLoader::HandleCancelledLoadingRequest(AVAssetResourceLoadingRequest* request) {
  impl_->HandleCancelledLoadingRequest(request);
}

Result FairPlayHlsKeyLoader::SetCdm(FairPlayCdm* cdm) {
  return impl_->SetCdm(cdm);
}

void FairPlayHlsKeyLoader::SetOutputObscured(bool obscured) {
  impl_->SetOutputObscured(obscured);
}

}  // namespace parc::fairplay

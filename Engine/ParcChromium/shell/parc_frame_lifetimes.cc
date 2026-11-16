// Copyright 2013 The Chromium Authors

#include <utility>

#include "content/browser/renderer_host/render_frame_host_impl.h"
#include "content/browser/media/media_web_contents_observer.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "third_party/blink/public/common/renderer_preferences/renderer_preferences.h"
#include "base/functional/bind.h"

namespace content {

void RenderFrameHostImpl::OnBackForwardCacheEvictionTimeout(
    base::TimeDelta waited) {
  constexpr base::TimeDelta kCastingLifetime = base::Hours(1);
  if (waited < kCastingLifetime && !LoadedWithCacheControlNoStoreHeader() &&
      MediaWebContentsObserver::IsRemotePlaybackStartedInPage(this)) {
    back_forward_cache_eviction_timer_.Start(
        FROM_HERE, kCastingLifetime - waited,
        base::BindOnce(&RenderFrameHostImpl::OnBackForwardCacheEvictionTimeout,
                       weak_ptr_factory_.GetWeakPtr(), kCastingLifetime));
    return;
  }
  EvictFromBackForwardCacheWithReason(
      BackForwardCacheMetrics::NotRestoredReason::kTimeout);
}

void RenderFrameHostImpl::PrepareNativeMainFrameLink(
    const GURL& url, const blink::DocumentToken& document,
    WindowOpenDisposition disposition, std::optional<uint32_t> input_modifiers,
    PrepareNativeMainFrameLinkCallback callback) {
  auto* contents = WebContents::FromRenderFrameHost(this);
  const bool option = disposition == WindowOpenDisposition::SAVE_TO_DISK;
  if ((disposition != WindowOpenDisposition::CURRENT_TAB &&
       disposition != WindowOpenDisposition::NEW_FOREGROUND_TAB &&
       disposition != WindowOpenDisposition::NEW_BACKGROUND_TAB && !option) ||
      !contents || !(option ? GetPage().IsPrimary() : IsInPrimaryMainFrame()) ||
      !IsActive() ||
      IsNestedWithinFencedFrame() ||
      document != GetDocumentToken() || !url.SchemeIsHTTPOrHTTPS() ||
      !contents->GetMutableRendererPrefs()->native_main_frame_link_policy ||
      !contents->GetDelegate()) {
    std::move(callback).Run(std::nullopt);
    return;
  }
  const auto lease = GetWeakDocumentPtr();
  auto token = contents->GetDelegate()->PrepareNativeMainFrameLink(this, url, disposition, input_modifiers);
  if (!lease.AsRenderFrameHostIfValid()) token.reset();
  std::move(callback).Run(token);
}

}

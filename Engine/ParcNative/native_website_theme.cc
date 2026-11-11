// Copyright 2026 Parc contributors.
#include "parc/native/native_website_theme.h"

#include <utility>

#include "content/browser/renderer_host/render_frame_host_impl.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace parc {
NativeWebsiteTheme::NativeWebsiteTheme(
    content::WebContents& contents, base::RepeatingCallback<bool()> valid_owner)
    : content::WebContentsObserver(&contents),
      valid_owner_(std::move(valid_owner)) {}
NativeWebsiteTheme::~NativeWebsiteTheme() { Revoke(); }

void NativeWebsiteTheme::SetStylesheet(const std::string& stylesheet) {
  stylesheet_ = stylesheet;
  Publish();
}
void NativeWebsiteTheme::Publish() {
  if (!web_contents() || !valid_owner_.Run()) return;
  auto* frame = web_contents()->GetPrimaryMainFrame();
  if (!frame || !frame->IsRenderFrameLive() || !frame->IsActive()) return;
  const auto token =
      static_cast<content::RenderFrameHostImpl*>(frame)->GetDocumentToken();
  if (document_.AsRenderFrameHostIfValid() != frame ||
      document_token_ != token || !remote_.is_bound() ||
      !remote_.is_connected()) {
    // Never wake an inactive cached page. The primary-page notification
    // publishes the current window value on restoration; stale tokens fail.
    remote_.reset();
    document_ = frame->GetWeakDocumentPtr();
    document_token_ = token;
    published_stylesheet_.reset();
    frame->GetRemoteAssociatedInterfaces()->GetInterface(&remote_);
  } else if (published_stylesheet_ && *published_stylesheet_ == stylesheet_) {
    // Same live primary document, same lease owner, same CSS already applied.
    // Same-document SPA navigations and identical SetStylesheet fan-out must
    // not Remove/Insert the stylesheet again.
    return;
  }
  remote_->SetTheme(token, owner_, stylesheet_);
  published_stylesheet_ = stylesheet_;
}
void NativeWebsiteTheme::Revoke() {
  // Only remove this lease's exact document/style. A late old-window removal
  // cannot clear a replacement owner's stylesheet in the same document.
  if (auto* frame = document_.AsRenderFrameHostIfValid();
      frame && frame->IsRenderFrameLive() && frame->IsActive() &&
      document_token_ && remote_.is_bound() && remote_.is_connected()) {
    remote_->RemoveTheme(*document_token_, owner_);
  }
  remote_.reset();
  document_ = {};
  document_token_.reset();
  published_stylesheet_.reset();
}
void NativeWebsiteTheme::PrimaryPageChanged(content::Page&) { Publish(); }
void NativeWebsiteTheme::PrimaryPageWillBeDeactivated(content::Page&) {
  // Revoke on the still-active outgoing document before it can enter BFCache.
  // The associated channel preserves ordering with frame lifecycle messages.
  Revoke();
}
void NativeWebsiteTheme::RenderFrameCreated(content::RenderFrameHost* frame) {
  if (web_contents() && frame == web_contents()->GetPrimaryMainFrame()) Publish();
}
void NativeWebsiteTheme::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (navigation->HasCommitted() && navigation->IsInPrimaryMainFrame() &&
      navigation->IsSameDocument()) Publish();
}
void NativeWebsiteTheme::WebContentsDestroyed() {
  remote_.reset();
  document_ = {};
  document_token_.reset();
  published_stylesheet_.reset();
  Observe(nullptr);
}
}  // namespace parc

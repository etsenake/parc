// Copyright 2026 Parc contributors.
#include "native_reader.h"

#include <string_view>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/dom_distiller/dom_distiller_service_factory.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/back_forward_cache/back_forward_cache_disable.h"
#include "components/dom_distiller/content/browser/distiller_javascript_utils.h"
#include "components/dom_distiller/content/browser/distiller_page_web_contents.h"
#include "components/dom_distiller/content/browser/dom_distiller_viewer_source.h"
#include "components/dom_distiller/core/dom_distiller_service.h"
#include "components/dom_distiller/core/proto/distilled_article.pb.h"
#include "components/dom_distiller/core/url_constants.h"
#include "components/dom_distiller/core/url_utils.h"
#include "content/public/browser/back_forward_cache.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/url_data_source.h"
#include "content/public/browser/web_contents.h"
#include "native_page_tool_appearance.h"
#include "ui/base/page_transition_types.h"

namespace parc {
namespace {
const char kNativeReaderViewerRegistered = 0;
class ViewerRegistered final : public base::SupportsUserData::Data {};
}  // namespace

NativeReader::NativeReader(content::WebContents& contents,
                           base::RepeatingClosure changed)
    : WebContentsObserver(&contents), changed_(std::move(changed)) {
  // Session/history restoration can reach a reader URL without a new action.
  // Registration is local to the actual BrowserContext, including incognito.
  if (dom_distiller::url_utils::IsDistilledPage(contents.GetVisibleURL())) {
    RegisterViewer();
  }
}

NativeReader::~NativeReader() {
  // The service's checked observer must be removed before its delegate dies.
  viewer_handle_.reset();
}

void NativeReader::RegisterViewer() {
  auto* context = web_contents()->GetBrowserContext();
  if (context->GetUserData(&kNativeReaderViewerRegistered)) {
    return;
  }
  if (!dom_distiller::DistillerJavaScriptWorldIdIsSet()) {
    dom_distiller::SetDistillerJavaScriptWorldId(
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  auto* service =
      dom_distiller::DomDistillerServiceFactory::GetForBrowserContext(context);
  CHECK(service);
  content::URLDataSource::Add(
      context,
      std::make_unique<dom_distiller::DomDistillerViewerSource>(service));
  context->SetUserData(&kNativeReaderViewerRegistered,
                       std::make_unique<ViewerRegistered>());
}

NativeReader::Mode NativeReader::mode() const {
  if (distilling_) {
    return Mode::kDistilling;
  }
  if (web_contents() && dom_distiller::url_utils::IsDistilledPage(
                            web_contents()->GetLastCommittedURL())) {
    const auto* entry = web_contents()->GetController().GetLastCommittedEntry();
    return entry && entry->GetPageType() == content::PAGE_TYPE_ERROR
               ? Mode::kFailedViewer
               : Mode::kViewing;
  }
  return message_.empty() ? Mode::kInactive : Mode::kUnavailable;
}

GURL NativeReader::DisplayURL() const {
  return web_contents()
             ? dom_distiller::url_utils::GetOriginalUrlFromDistillerUrl(
                   web_contents()->GetVisibleURL())
             : GURL();
}

bool NativeReader::CanToggle() const {
  auto* contents = web_contents();
  if (!contents || contents->IsBeingDestroyed() || contents->IsCrashed() ||
      !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive()) {
    return false;
  }
  if (distilling_ || mode() == Mode::kViewing ||
      mode() == Mode::kFailedViewer) {
    return true;
  }
  // This is URL eligibility, not an invented readability score. The real
  // extractor determines whether an article exists and reports an empty result.
  return !contents->GetController().GetPendingEntry() &&
         contents->GetContentsMimeType() != "application/pdf" &&
         dom_distiller::url_utils::IsUrlDistillable(
             contents->GetLastCommittedURL());
}

bool NativeReader::Toggle(
    base::RepeatingCallback<bool()> original_owner_valid) {
  if (!CanToggle() || !original_owner_valid.Run()) {
    return false;
  }
  if (distilling_) {
    const bool loading_viewer = !viewer_navigation_.is_empty();
    Cancel();
    if (loading_viewer) {
      web_contents()->Stop();
    }
    return true;
  }
  if (mode() == Mode::kViewing || mode() == Mode::kFailedViewer) {
    auto& controller = web_contents()->GetController();
    const GURL source =
        dom_distiller::url_utils::GetOriginalUrlFromDistillerUrl(
            web_contents()->GetLastCommittedURL());
    // Return to the actual source history entry when it still exists. This
    // preserves its original POST/history state; do not blindly go Back into a
    // different page after history traversal or session restoration.
    for (int i = controller.GetLastCommittedEntryIndex() - 1; i >= 0; --i) {
      const auto* entry = controller.GetEntryAtIndex(i);
      if (entry && entry->GetUniqueID() == source_entry_id_ &&
          entry->GetURL() == source) {
        controller.GoToIndex(i);
        return true;
      }
    }
    content::NavigationController::LoadURLParams params(source);
    params.transition_type = ui::PAGE_TRANSITION_AUTO_BOOKMARK;
    controller.LoadURLWithParams(params);
    return true;
  }

  RegisterViewer();
  Cancel();
  auto* contents = web_contents();
  original_owner_valid_ = std::move(original_owner_valid);
  source_document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
  source_url_ = contents->GetLastCommittedURL();
  auto* entry = contents->GetController().GetLastCommittedEntry();
  source_entry_id_ = entry ? entry->GetUniqueID() : 0;
  distilling_ = true;
  content::BackForwardCache::DisableForRenderFrameHost(
      contents->GetPrimaryMainFrame(),
      back_forward_cache::DisabledReason(
          back_forward_cache::DisabledReasonId::
              kDomDistiller_SelfDeletingRequestDelegate));
  auto* service =
      dom_distiller::DomDistillerServiceFactory::GetForBrowserContext(
          contents->GetBrowserContext());
  auto page = service->CreateDefaultDistillerPageWithHandle(
      std::make_unique<dom_distiller::SourcePageHandleWebContents>(contents,
                                                                   false));
  // Retain Chromium's article cache and viewer handoff. Both now belong to this
  // exact profile rather than an off-record profile's regular parent.
  viewer_handle_ = service->ViewUrl(this, std::move(page), source_url_);
  if (!viewer_handle_) {
    Unavailable("Reader could not extract this page. You can try again.");
  } else {
    changed_.Run();
  }
  return true;
}

bool NativeReader::SourceStillCurrent() const {
  return web_contents() && !web_contents()->IsBeingDestroyed() &&
         source_document_.AsRenderFrameHostIfValid() ==
             web_contents()->GetPrimaryMainFrame() &&
         web_contents()->GetLastCommittedURL() == source_url_ &&
         original_owner_valid_ && original_owner_valid_.Run();
}

void NativeReader::OnArticleReady(
    const dom_distiller::DistilledArticleProto* article) {
  // DistilledArticle.pages[0].html is the recovered article payload. Viewing
  // chrome stays Chromium's chrome-distiller viewer.
  QueueResult(article && article->pages_size() > 0 &&
              article->pages(0).has_html() &&
              !article->pages(0).html().empty());
}

void NativeReader::OnArticleUpdated(dom_distiller::ArticleDistillationUpdate) {}

void NativeReader::OnDistillationFailed(
    dom_distiller::DistillationParseResult) {
  QueueResult(false);
}

void NativeReader::QueueResult(bool has_content) {
  if (!distilling_ || result_queued_) {
    return;
  }
  result_queued_ = true;
  // Never navigate or remove the checked observer inside the extractor's
  // delivery stack. Cancellation invalidates this exact queued request.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(&NativeReader::CompleteRequest,
                                weak_factory_.GetWeakPtr(), has_content));
}

void NativeReader::CompleteRequest(bool has_content) {
  if (!SourceStillCurrent()) {
    Cancel();
    return;
  }
  if (!has_content) {
    Unavailable("No readable article was found on this page.");
    return;
  }
  CHECK(std::string_view(kPCPageToolReaderScheme) ==
        std::string_view(dom_distiller::kDomDistillerScheme));
  viewer_navigation_ = dom_distiller::url_utils::GetDistillerViewUrlFromUrl(
      kPCPageToolReaderScheme, source_url_,
      base::UTF16ToUTF8(web_contents()->GetTitle()),
      (base::TimeTicks::Now() - base::TimeTicks()).InMilliseconds());
  content::NavigationController::LoadURLParams params(viewer_navigation_);
  params.transition_type = ui::PAGE_TRANSITION_AUTO_BOOKMARK;
  // Loading remains true until the real viewer navigation commits. A denied,
  // cancelled or failed navigation is never reported as a visible reader.
  web_contents()->GetController().LoadURLWithParams(params);
}

void NativeReader::Cancel() {
  ++revision_;
  weak_factory_.InvalidateWeakPtrs();
  viewer_handle_.reset();
  original_owner_valid_.Reset();
  source_document_ = content::WeakDocumentPtr();
  viewer_navigation_ = GURL();
  viewer_navigation_id_ = 0;
  distilling_ = false;
  result_queued_ = false;
  message_.clear();
  changed_.Run();
}

void NativeReader::Unavailable(const std::string& message) {
  Cancel();
  message_ = message;
  changed_.Run();
}

void NativeReader::DidStartNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) {
    return;
  }
  if (distilling_ && !viewer_navigation_.is_empty() &&
      navigation->GetURL() == viewer_navigation_ && !viewer_navigation_id_ &&
      SourceStillCurrent()) {
    viewer_navigation_id_ = navigation->GetNavigationId();
    return;
  }
  Cancel();
  // Register before restoring/following a genuine distilled URL as well.
  if (dom_distiller::url_utils::IsDistilledPage(navigation->GetURL())) {
    RegisterViewer();
  }
}

void NativeReader::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) {
    return;
  }
  if (viewer_navigation_id_ == navigation->GetNavigationId()) {
    const bool committed = navigation->HasCommitted() &&
                           !navigation->IsErrorPage() &&
                           navigation->GetURL() == viewer_navigation_;
    Cancel();
    if (!committed) {
      message_ = "Reader could not open this page. You can try again.";
    }
  }
  changed_.Run();
}

void NativeReader::OnVisibilityChanged(content::Visibility visibility) {
  if (distilling_ && visibility == content::Visibility::HIDDEN) {
    const bool loading_viewer = !viewer_navigation_.is_empty();
    Cancel();
    if (loading_viewer) {
      web_contents()->Stop();
    }
  }
}

void NativeReader::PrimaryMainFrameRenderProcessGone(base::TerminationStatus) {
  Cancel();
}

void NativeReader::WebContentsDestroyed() {
  Cancel();
  Observe(nullptr);
}
}  // namespace parc

// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_READER_H_
#define PARC_NATIVE_READER_H_

#include <cstdint>
#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/dom_distiller/core/task_tracker.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "url/gurl.h"

namespace parc {

class NativeReader final : public content::WebContentsObserver,
                           public dom_distiller::ViewRequestDelegate {
 public:
  enum class Mode {
    kInactive,
    kDistilling,
    kViewing,
    kUnavailable,
    kFailedViewer
  };

  NativeReader(content::WebContents& contents, base::RepeatingClosure changed);
  ~NativeReader() override;
  Mode mode() const;
  uint64_t revision() const { return revision_; }
  const std::string& message() const { return message_; }
  bool CanToggle() const;
  bool Toggle(base::RepeatingCallback<bool()> original_owner_valid);
  void Cancel();
  GURL DisplayURL() const;

 private:
  void OnArticleReady(
      const dom_distiller::DistilledArticleProto* article) override;
  void OnArticleUpdated(dom_distiller::ArticleDistillationUpdate) override;
  void OnDistillationFailed(
      dom_distiller::DistillationParseResult reason) override;
  void QueueResult(bool has_content);
  void CompleteRequest(bool has_content);
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void OnVisibilityChanged(content::Visibility visibility) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override;
  void WebContentsDestroyed() override;
  void Unavailable(const std::string& message);
  bool SourceStillCurrent() const;
  void RegisterViewer();

  base::RepeatingClosure changed_;
  base::RepeatingCallback<bool()> original_owner_valid_;
  content::WeakDocumentPtr source_document_;
  GURL source_url_;
  GURL viewer_navigation_;
  int source_entry_id_ = 0;
  int64_t viewer_navigation_id_ = 0;
  uint64_t revision_ = 0;
  bool distilling_ = false;
  bool result_queued_ = false;
  std::string message_;
  std::unique_ptr<dom_distiller::ViewerHandle> viewer_handle_;
  base::WeakPtrFactory<NativeReader> weak_factory_{this};
};

}  // namespace parc
#endif  // PARC_NATIVE_READER_H_

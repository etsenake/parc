// Copyright 2026 Parc contributors.
#pragma once
#include "base/functional/callback.h"
#include <vector>
class BrowserWindowInterface;
namespace content {
class WebContents;
}
namespace parc {
enum class TabTransferResult {
  kTransferred,
  kRefused,
  kRestoredToSource,
  // An independent owner destroyed/replaced the page while delivering its
  // synchronous model callbacks. No replacement page is constructed.
  kExternallyInterrupted,
};
// UI thread, distinct normal/popup Browsers, pointer-equal Profiles.
// DevTools, document-PiP and app-owned Browser types use separate lifecycles.
// Move the actual TabModel, preserving its TabInterface, WebContents and
// renderer. Presentation receives its actual owner after insertion and after
// any rollback. It must attach that existing page; it must not run nested
// loops, close a Browser, mutate tab membership or navigate. Ordinary native
// lifecycle reentry is validated after delivery. Only an empty destination
// activates the moved tab. When supplied, deferred_empty_owner_close receives
// an optional weak-source close operation that the caller must run only after
// its result/ownership callback returns. Without it, the operation is posted.
// A preexisting destination is never retired, including after rollback.
TabTransferResult TransferLiveTab(
    content::WebContents& contents,
    BrowserWindowInterface& destination,
    base::RepeatingCallback<bool(BrowserWindowInterface&,
                                 content::WebContents&)> present,
    base::OnceClosure* deferred_empty_owner_close = nullptr);
// Same-source collection transaction. Exact native attachment precedes the
// synchronous durable shell commit. Refusal or commit failure restores surviving
// originals; independent destruction is Interrupted. No navigation is issued.
// Caller keeps all shell claims reserved and runs deferred source cleanup only
// after its posted completion has reconciled the collection.
TabTransferResult TransferLiveTabs(
    const std::vector<content::WebContents*>& contents,
    BrowserWindowInterface& destination,
    base::RepeatingCallback<bool(BrowserWindowInterface&, content::WebContents&)> present,
    base::OnceCallback<bool()> commit,
    std::vector<base::OnceClosure>* deferred_empty_owner_close);
bool HasLiveTabTransfer();
bool IsLiveTabTransferTarget(content::WebContents* contents);
}  // namespace parc

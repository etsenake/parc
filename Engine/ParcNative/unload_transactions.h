// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_UNLOAD_TRANSACTIONS_H_
#define PARC_NATIVE_UNLOAD_TRANSACTIONS_H_

#include <cstdint>
#include <optional>
#include <vector>

#include "base/functional/callback.h"

class BrowserWindowInterface;
class UnloadController;
namespace content {
class WebContents;
}

namespace parc {
// Exact-page transaction used by native batch retirement. All targets must
// belong to the controller's Browser. The posted preflight reports true for
// PREPARED (no page closed). A later false can synchronously invalidate that
// state on external document/owner changes, including after arming posted
// unload. The caller must hold all Browser owners, validate every participating
// token, then commit each on the same UI stack without an intervening callback.
using TabCloseToken = uint64_t;
// A same-profile native tab transfer must keep an empty source Browser alive
// until insertion/rollback has completed. This reservation refuses close
// attempts but never fires beforeunload or destroys a page. UI thread only.
std::optional<TabCloseToken> ReserveTabTransfer(UnloadController& controller);
// Releases the hold without closing synchronously or posting work. Returns
// an optional weak-owner close operation only if this hold observed the tab
// strip become empty and it remains empty. The caller decides whether that
// owner should retire and runs it after committing native/shell ownership.
base::OnceClosure ReleaseTabTransfer(UnloadController& controller,
                                     TabCloseToken token);
std::optional<TabCloseToken> ReserveTabClosePreflight(
    UnloadController& controller,
    const std::vector<content::WebContents*>& contents,
    base::RepeatingCallback<void(bool)> prepared);
// Start one reserved group after the previous Browser's sheet has completed.
// Dispatch is posted; reservation itself never opens UI or invokes callbacks.
bool RunTabClosePreflight(UnloadController& controller, TabCloseToken token);
bool IsTabClosePreflightReady(const UnloadController& controller,
                              TabCloseToken token);
// Marks committed and POSTS actual ClosePage. No callback or unload runs
// inside this function, allowing all participating controllers to arm first.
bool CommitTabClosePreflight(UnloadController& controller,
                             TabCloseToken token);
// Cancellation is non-destructive before commit. After commit this only
// releases completed bookkeeping; it cannot roll back an actual unload.
void ReleaseTabClosePreflight(UnloadController& controller,
                              TabCloseToken token);
bool HasTabClosePreflight(const UnloadController& controller);

// UnloadController's hooks, installed before any Browser exists. The
// controller hands over its private unclosable-app policy and its
// beforeunload runner, which takes the custom-confirmation completion to use.
using UnloadEventsRunner = base::RepeatingCallback<
    bool(content::WebContents*, base::OnceCallback<void(bool)>)>;
void OnUnloadControllerCreated(UnloadController& controller,
                               BrowserWindowInterface& browser,
                               base::RepeatingCallback<bool()> unclosable_app,
                               UnloadEventsRunner run_unload_events);
void OnUnloadControllerDestroyed(UnloadController& controller);
void OnUnloadControllerTabAttached(UnloadController& controller,
                                   content::WebContents* contents);
void OnUnloadControllerTabDetached(UnloadController& controller,
                                   content::WebContents* contents);
void OnUnloadControllerRenderProcessGone(UnloadController& controller,
                                         content::WebContents* contents);
// True when a transfer hold absorbs the tab strip becoming empty.
bool AbsorbsTabStripEmpty(UnloadController& controller);
// HandleBeforeClose refuses the window close.
bool BlocksWindowClose(const UnloadController& controller);
// GetBrowserClosingStatus reports unload handlers needing time.
bool HoldsClosingStatus(const UnloadController& controller);
// RunBeforeUnloadForShutdown refuses, reporting false asynchronously.
bool BlocksShutdownBeforeUnload(const UnloadController& controller);
// Ordinary close paths may neither unload nor close `contents`.
bool HoldsContents(const UnloadController& controller,
                   content::WebContents* contents);
// RunUnloadEventsHelper's result for a held or committed page; nullopt runs
// Chromium's beforeunload.
std::optional<bool> UnloadEventsResult(const UnloadController& controller,
                                       content::WebContents* contents);
// A beforeunload reply owed to a close transaction, wherever the page moved.
bool HasTabCloseReply(content::WebContents* contents);
// True when the transaction consumed this beforeunload reply, so Chromium's
// ordinary close path must not proceed.
bool ConsumesBeforeUnloadReply(UnloadController& controller,
                               content::WebContents* contents,
                               bool proceed);
}  // namespace parc

#endif  // PARC_NATIVE_UNLOAD_TRANSACTIONS_H_

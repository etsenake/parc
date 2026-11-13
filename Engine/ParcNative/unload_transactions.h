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
using TabCloseToken = uint64_t;
std::optional<TabCloseToken> ReserveTabTransfer(UnloadController& controller);
base::OnceClosure ReleaseTabTransfer(UnloadController& controller,
                                     TabCloseToken token);
std::optional<TabCloseToken> ReserveTabClosePreflight(
    UnloadController& controller,
    const std::vector<content::WebContents*>& contents,
    base::RepeatingCallback<void(bool)> prepared);
bool RunTabClosePreflight(UnloadController& controller, TabCloseToken token);
bool IsTabClosePreflightReady(const UnloadController& controller,
                              TabCloseToken token);
bool CommitTabClosePreflight(UnloadController& controller,
                             TabCloseToken token);
void ReleaseTabClosePreflight(UnloadController& controller,
                              TabCloseToken token);
bool HasTabClosePreflight(const UnloadController& controller);

using UnloadEventsRunner = base::RepeatingCallback<
    bool(content::WebContents*, base::OnceCallback<void(bool)>)>;
void OnUnloadControllerCreated(UnloadController& controller,
                               BrowserWindowInterface& browser,
                               base::RepeatingCallback<bool()> unclosable_app,
                               UnloadEventsRunner run_unload_events);
void OnUnloadControllerDestroyed(UnloadController& controller);
bool AbsorbsTabStripEmpty(UnloadController& controller);
bool BlocksWindowClose(const UnloadController& controller);
bool HoldsClosingStatus(const UnloadController& controller);
bool BlocksShutdownBeforeUnload(const UnloadController& controller);
bool HoldsContents(const UnloadController& controller,
                   content::WebContents* contents);
std::optional<bool> UnloadEventsResult(const UnloadController& controller,
                                       content::WebContents* contents);
bool HasTabCloseReply(content::WebContents* contents);
bool ConsumesBeforeUnloadReply(UnloadController& controller,
                               content::WebContents* contents,
                               bool proceed);
}

#endif

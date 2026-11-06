// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_TAB_RETIREMENT_H_
#define PARC_NATIVE_TAB_RETIREMENT_H_
#include <vector>

#include "base/functional/callback.h"
namespace content {
class WebContents;
}
namespace parc {
// UI thread only. A single real transaction holds exact Browser/Tab/document
// leases. context_is_valid is a non-mutating native association query;
// should_commit is the one callback permitted to mutate/reenter, after all
// confirmations. All leases are checked again before committing unload.
void RequestTabRetirement(std::vector<content::WebContents*> pages,
                          base::RepeatingCallback<bool()> context_is_valid,
                          base::OnceCallback<bool()> should_commit,
                          base::OnceCallback<void(bool)> completion);
bool HasTabRetirementWork();
bool IsTabRetiring(content::WebContents*);
}  // namespace parc
#endif

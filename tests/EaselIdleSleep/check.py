#!/usr/bin/env python3
import re
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")


def body(signature):
    match = re.search(r"^    (?:private )?func " + re.escape(signature) + r".*?^    }\n", controller, re.S | re.M)
    assert match, f"{signature} is missing"
    return match.group(0)


sweep = body("discardIdleBackgroundPages()")
assert sweep.count("tab.lastAccessed < cutoff") == 2, "tabs and Easels share the same four-hour cutoff"
easels = sweep[sweep.index("for (id, pane) in easelEditors"):]
for use in ("where !shown.contains(id) && !closingTabIDs.contains(id) && !transferringTabIDs.contains(id)",
            "store.state.tab(id, where: { $0.archivedAt == nil })", "easelPagesCanSleep(pane)",
            "releaseIdleEaselPages(id, cached: pane)"):
    assert use in easels, f"the idle sweep no longer limits Easel sleep to unseen, settled Easels: {use}"

eligible = body("easelPagesCanSleep(")
for use in ("pane.editor.canPrepareForProfileRelocation", "!objects.hasPendingCreation", "!objects.pages.isEmpty",
            "objects.ownedViews.values.allSatisfy { $0.automaticArchiveProtectionState == .eligible }"):
    assert use in eligible, f"an Easel in use could sleep: {use}"

release = body("releaseIdleEaselPages(")
commit = release[release.index("shouldCommit:"):release.index("completion:")]
for use in ("let shown = self.renderedPaneIDs.contains(id) || self.selectedTabIDs.contains(id) || self.pendingNativeSelection?.tabID == id",
            "!shown", "!self.transferringTabIDs.contains(id)", "self.store.state.tab(id) == expected",
            "self.easelPagesCanSleep(current)"):
    assert use in commit, f"closing no longer rechecks that the Easel is still unseen and idle: {use}"
done = release[release.index("completion:"):]
assert release.index("cached.editor.prepareForPreviewClose()") < release.index("requestClosePages"), \
    "the editor settles before its pages close"
assert done.index("guard let self else { return }") < done.index("self.closingTabIDs.remove(id)") < done.index("if allowed, let objects"), \
    "every finished or refused close releases the closing hold, even when the editor changed meanwhile"
assert done.index("cached.editor.retirePageOwner()") < done.index("self.easelEditors.removeValue(forKey: id)")
assert done.rstrip().count("self.render(self.store.state); self.requestNativeSelection()") == 1 \
    and "guard !self.isClosing else { return }" in done, \
    "every finished or refused close redraws, so a shown, archived or deleted Easel never keeps stale pages"
print("PASS: Easel idle sleep source assertions")

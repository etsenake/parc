#!/usr/bin/env python3
"""Source assertions for the split cell's Close gate (SP30).

The window controller is not compiled here. These assertions keep the split
cell's Close and keyboard Close of selected roots on ordinary row Close's
window and per-tab conditions (without its key-window check), the close
action read at press time and no split accessibility close action (Parc's
SplitViewCellView has none). No browser, window or input.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
checks = 0

def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")

def expect(condition, message):
    global checks
    assert condition, message
    checks += 1

window = body(controller, "private var sidebarTabActionWindowAvailable: Bool")
for guard in ("!isPopupWindow", "presentation.isReady", "!isClosing", "!wholeWindowClose", "!windowClosePending",
              "!windowCloseApproved", "nativeFullscreenTabID == nil", "window?.attachedSheet == nil",
              "!store.isProfileRemovalPending(activeProfileID)"):
    expect(guard in window, f"window condition missing: {guard}")
expect("isKeyWindow" not in window, "the shared window conditions carry no key-window check")
tab = body(controller, "private func sidebarTabActionAvailable(_ id: UUID) -> Bool")
for guard in ("!closingTabIDs.contains(id)", "!transferringTabIDs.contains(id)", "!resolvingTransfers.contains(id)",
              "transferRecoveries[id] == nil", "!store.retiringTabIDs.contains(id)", "ownership.canUse(id, owner: presentationID)"):
    expect(guard in tab, f"per-tab condition missing: {guard}")
row = body(controller, "private func canPerformSidebarTabAction(")
expect("sidebarTabActionWindowAvailable" in row and "sidebarTabActionAvailable(expected.id)" in row
       and "window?.isKeyWindow == true" in row, "ordinary row actions use the shared conditions plus the key window")
roots = body(controller, "private func sidebarRootsCloseAvailable(_ ids: Set<UUID>) -> Bool")
for guard in ("sidebarTabActionWindowAvailable", "commandBar == nil", "!ids.isEmpty", "visibleTabs.contains",
              "sidebarTabActionAvailable(id)", "switcherCanUse(id)", "retirementUnavailableReason?(ids) == nil"):
    expect(guard in roots, f"roots close condition missing: {guard}")
close = body(controller, "private func prepareSidebarRootsClose(")
expect("self.sidebarRootsCloseAvailable(ids)" in close and "guard valid() else { return nil }" in close
       and "guard !consumed, let self, valid()," in close, "roots close validates the shared conditions when prepared and pressed")
expect("prepareSidebarMoves" not in close.split("if !isPrivateBrowsing, archive {")[1].split("}")[1],
       "the closing path does not depend on the window-move lease")
expect("sidebarRootsCloseAvailable(Set(group.tabIDs))" in body(controller, "private func splitCellCloseAvailable("),
       "the split Close enables with the same conditions")
split = body(controller, "sidebar.prepareSplitClose = { [weak self] id in")
expect("self.splitCellCloseAction(id)" in split, "the split's close action is read when pressed")
expect("closeAX" not in sidebar and "Archive Split View" not in sidebar and "Close Split View\"" not in sidebar,
       "the split cell has no Close/Archive accessibility action; its visible Close button is the only route")
print(f"PASS: {checks} split close gate source assertions (no browser)")

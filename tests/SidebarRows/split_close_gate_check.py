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

def body(source, signature, opener="{"):
    start = source.index(signature)
    depth, i = 0, source.index(opener, start) + len(opener) - 1
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
              "transferRecoveries[id] == nil", "!store.retiringTabIDs.contains(id)"):
    expect(guard in tab, f"per-tab condition missing: {guard}")
expect("ownership" not in tab, "the shared per-tab conditions leave which window holds the page to each action")
row = body(controller, "private func canPerformSidebarTabAction(")
expect("sidebarTabActionWindowAvailable" in row and "sidebarTabActionAvailable(expected.id)" in row
       and "window?.isKeyWindow == true" in row, "ordinary row actions use the shared conditions plus the key window")
# The per-tab conditions hold wherever the page is; each action checks which
# window holds it. A row's Close takes this window's page or moves it here.
expect("usableHere: closing ? ownership.canUse(expected.id, owner: presentationID) : switcherCanUse(expected.id)" in row
       and "heldElsewhere: canMovePageHere(expected.id)" in row, "a row action checks which window holds its page")
expect("PageReparenting.rowAction(closing: closing, busy: !sidebarTabActionAvailable(expected.id)" in row,
       "row Close acts on a page here or one another window holds that can move here")
roots = body(controller, "private func sidebarRootsCloseAvailable(_ ids: Set<UUID>, movingHere: Bool = true) -> Bool")
for guard in ("sidebarTabActionWindowAvailable", "commandBar == nil", "!ids.isEmpty", "visibleTabs.contains",
              "PageReparenting.rowAction(closing: true, busy: !sidebarTabActionAvailable(id)",
              "usableHere: switcherCanUse(id)", "heldElsewhere: movingHere && canMovePageHere(id)) != nil",
              "retirementUnavailableReason?(ids) == nil"):
    expect(guard in roots, f"roots close condition missing: {guard}")
expect("ids.allSatisfy" in roots and "PageReparenting.rowAction" in roots.split("ids.allSatisfy")[1],
       "every root's page, here or elsewhere, must pass row Close's rule, so a page that can't move refuses the set")
expect("ownership.canUse(id, owner: presentationID)" in body(controller, "private func switcherCanUse(_ id: UUID) -> Bool"),
       "a page counts as usable here only while this window owns it")
close = body(controller, "private func prepareSidebarRootsClose(", ") -> (() -> Bool)? {")
moving, rest = close.split("if !isPrivateBrowsing, archive {")
expect("let elsewhere = target.items.tabs.map(\\.id).filter { !switcherCanUse($0) }" in moving
       and "if !elsewhere.isEmpty {" in moving,
       "pages another window holds are found before the archive and close branches, for split and keyboard Close alike")
expect("self.sidebarRootsCloseAvailable(ids)" in moving and "guard valid() else { return nil }" in moving
       and "guard !consumed, let self, valid() else { return false }" in moving,
       "moving held pages here validates row Close's conditions when prepared and pressed")
expect("self.moveRootsHere(elsewhere[...], moved: [])" in moving and "ids.allSatisfy(self.switcherCanUse)" in moving
       and "self.prepareSidebarRootsClose(items, archive: archive, requiresConfirmation: requiresConfirmation," in moving
       and "isSelectionCommand: isSelectionCommand, selectionIsCurrent: current, declined: giveBack)," in moving,
       "held pages move here, then the whole set (here and moved) closes or archives here only once all are here")
# A later move in the set can still be refused after earlier pages arrived
# (the transfer rechecks both windows and the page), so nothing may stay
# half-moved: every way the press ends without closing sends moved pages back.
expect("let giveBack = { [weak self] in self?.returnMovedRoots(moved); declined() }" in moving
       and "close() else { giveBack(); return false }" in moving,
       "moved pages go back when the close can't be prepared or doesn't start")
chain = body(controller, "private func moveRootsHere(")
expect("let arrival = PendingArrival { [weak self] in self?.returnMovedRoots(moved) }" in chain,
       "a move that ends without the page arriving (dropped unrun) sends earlier pages back")
expect("if !started { arrival.ran = true; returnMovedRoots(moved) }" in chain,
       "a move refused at once sends earlier pages back")
step = chain.split("let started = request(id, self) {")[1].split("if !started")[0]
expect(step.index("arrival.ran = true") < step.index("moveRootsHere(ids.dropFirst(), moved: moved + [id], then: close)")
       < step.index("return true\n"),
       "an arrival continues the chain and is never selected here instead of being closed or returned")
expect("for id in ids { returnIfUnshown(id) }" in body(controller, "private func returnMovedRoots("),
       "moved pages go back through the ordinary deferred return")
unshown = body(controller, "private func returnIfUnshown(_ id: UUID)")
returnable = body(controller, "private var returnableIDs: Set<UUID>")
expect("heldContentIDs.contains(id) || holdsEmptyClaim(id)" in unshown
       and "shownSinceArrival.filter(holdsEmptyClaim)" in returnable,
       "a handed-over claim with nothing behind it, which has no pane here, goes back as moved content does")
pending = body(controller, "private final class PendingArrival {")
expect("guard !ran else { return }" in pending and "DispatchQueue.main.async(execute: abandoned)" in pending,
       "a dropped step reports itself on the main thread when released")
expect("guard let self, allowed else { declined(); return }" in rest,
       "a close declined at its leave-page prompt sends moved pages back")
expect("prepareSidebarDeletion(" in rest.split("}")[0] and "declined: declined)" in rest.split("}")[0],
       "the archive branch passes the give-back on")
deletion = body(controller, "private func prepareSidebarDeletion(", ") -> (() -> Bool)? {")
expect(deletion.count("declined()") == 3 and "case .success(false): self.updateNavigation(); declined()" in deletion
       and "case .failure(let error): self.updateNavigation(); declined();" in deletion
       and "self.updateNavigation(); declined()\n" in deletion,
       "an archive cancelled at confirmation, refused or failed sends moved pages back")
expect("self.sidebarRootsCloseAvailable(ids, movingHere: false)" in rest and "self.sidebarRootsCloseAvailable(ids)" not in rest
       and "guard valid() else { return nil }" in rest and "guard !consumed, let self, valid()," in rest,
       "closing pages here validates the shared conditions when prepared and pressed, with every page here")
expect("prepareSidebarMoves" not in rest.split("}", 1)[1],
       "the closing path does not depend on the window-move lease")
keyboard = body(controller, "sidebar.prepareSidebarClose = { [weak self] items in")
expect("self.prepareSidebarRootsClose(items, archive: target.archivesItems," in keyboard
       and "isSelectionCommand: true, selectionIsCurrent: current)" in keyboard,
       "keyboard Close of selected rows takes the same roots close, moving held pages here")
expect("sidebarRootsCloseAvailable(Set(group.tabIDs))" in body(controller, "private func splitCellCloseAvailable("),
       "the split Close enables with the same conditions")
split = body(controller, "sidebar.prepareSplitClose = { [weak self] id in")
expect("self.splitCellCloseAction(id)" in split, "the split's close action is read when pressed")
expect("closeAX" not in sidebar and "Archive Split View" not in sidebar and "Close Split View\"" not in sidebar,
       "the split cell has no Close/Archive accessibility action; its visible Close button is the only route")
expect("canMovePageHere(" in roots or "canCloseOrMoveHere(" in roots,
       "closing roots must take a page another window holds as row Close does (move it here, then close); "
       "roots Close still requires this window to hold every page (switcherCanUse)")
print(f"PASS: {checks} split close gate source assertions (no browser)")

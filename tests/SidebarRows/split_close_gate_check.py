#!/usr/bin/env python3
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
       and "shownSinceArrival.union(heldReturns).filter(holdsEmptyClaim)" in returnable,
       "a handed-over claim with nothing behind it, which has no pane here, goes back as moved content does, "
       "including while its return is held")
returns = body(controller, "private func scheduleUntargetedReturns()")
expect("self.shownSinceArrival.remove(id)" in returns
       and "let outcome = self.onUntargetedReturn?(id, self, .deselected)" in returns
       and "if outcome == .started { return }" in returns
       and "if outcome == .blocked, self.failedDuringReturn != id { self.heldReturns.insert(id) }" in returns,
       "a refused return is held for retry; one that no longer applies is dropped")
transfer = body(controller, "func transferTab(_ id: UUID, to destination: BrowserWindowController")
expect(transfer.index("if untargeted { failedDuringReturn = nil }") < transfer.index("holdsEmptyClaim(id)"),
       "each untargeted attempt starts with no failure marked, so an old failure can't hide a refusal")
expect("func returnFailed(_ id: UUID) -> Bool { failedDuringReturn == id }" in controller,
       "a move that started and failed before reporting it is held only by its own failure, keeping the one-retry limit")
retry = body(controller, "func retryHeldReturns()")
gate = body(controller, "private func noteReturnGate()")
for name, text in (("scheduleUntargetedReturns", returns), ("retryHeldReturns", retry), ("noteReturnGate", gate),
                   ("holdFailedReturn", body(controller, "private func holdFailedReturn(_ id: UUID)"))):
    expect("asyncAfter" not in text and "Timer" not in text, f"{name} never retries on a timer")
expect("guard !heldReturns.isEmpty, !isClosing else { return }" in retry
       and "shownSinceArrival.formUnion(heldReturns)" in retry and "heldReturns.removeAll()" in retry
       and "scheduleUntargetedReturns()" in retry,
       "a retry with nothing held does nothing; otherwise each held page is tried once more")
for name, change in (("transferringTabIDs", "if transferringTabIDs.isEmpty, !oldValue.isEmpty { onReturnUnblocked?() }"),
                     ("collectionTransfer", "if collectionTransfer == nil, oldValue != nil { onReturnUnblocked?() }"),
                     ("nativeFullscreenTabID", "if nativeFullscreenTabID == nil, oldValue != nil { onReturnUnblocked?() }"),
                     ("wholeWindowClose", "if !wholeWindowClose, oldValue { onReturnUnblocked?() }")):
    expect(change in controller.split(f"private var {name}", 1)[1].split("\n    }\n", 1)[0],
           f"the end of {name} (a move or its recovery, full screen, a cancelled close) retries held returns")
expect(body(controller, "func selectSpace(_ id: UUID)").rstrip("}").rstrip().endswith("noteReturnGate()"),
       "showing another Space retries held returns, after the new Space is in place")
expect("if open, !returnGateWasOpen || space != returnGateSpaceID { onReturnUnblocked?() }" in gate
       and "defer { returnGateWasOpen = open; returnGateSpaceID = space }" in gate,
       "the window's own refusals retry held returns only as they end or its Space changes, never on every pass")
gate_terms = body(controller, "private var returnGateOpen: Bool")
for term in ("presentation.isReady", "activePeek == nil", "!promotingPeek", "commandBar == nil", "tabSwitcher == nil",
             "themePopover == nil", "!siteControlCenterDefers", "closingTabIDs.isEmpty", "modelRetirementIDs.isEmpty",
             "peekRetirementParents.isEmpty", "!$0.closePending", "!store.isProfileRemovalPending(activeProfileID)",
             "nativeBinding?.canParticipateInPageTransfer == true"):
    expect(term in gate_terms, f"a refusal that ends without a move, full screen or close is in the gate: {term}")
expect("self.tabSwitcher = nil\n            self.noteReturnGate()" in controller, "closing the tab switcher checks the gate")
for name in ("themePopover", "siteControlCenter", "peeks", "promotingPeek"):
    declaration = controller.split(f"private var {name}", 1)[1].split("\n", 1)[0]
    expect("noteReturnGate()" in declaration, f"closing {name} checks the gate")
expect("noteReturnGate()" in body(controller, "private var commandBar: CommandBar?"), "closing the command bar checks the gate")
navigation = body(controller, "private func updateNavigation()")
expect(navigation.rstrip("}").rstrip().endswith("noteReturnGate()"), "every navigation refresh checks the gate")
expect("noteReturnGate()\n        refreshStartPage()\n        refreshPendingPaneSidebar()\n        scheduleUntargetedReturns()\n    }" in controller,
       "every render checks the gate, so a Space change any path made is seen")
expect("heldReturns.formIntersection(returnableIDs); heldReturns.subtract(displayedIDs)" in controller
       and "failedReturns.formIntersection(returnableIDs); failedReturns.subtract(displayedIDs)" in controller,
       "a held return stops when its page closes, leaves or is shown here again")
failed = body(controller, "private func holdFailedReturn(_ id: UUID)")
expect("!presentation.displayedTabIDs.contains(id)" in failed and failed.index("failedDuringReturn = id") < failed.index("guard")
       and "if failedReturns.insert(id).inserted { heldReturns.insert(id) } else {\n"
           "            failedReturns.remove(id); heldReturns.remove(id); shownSinceArrival.remove(id)" in failed,
       "a started return that leaves the page here is tried on one more change, then waits for a reselection")
document_end = controller[controller.index("source.collectionTransfer = nil; destination.collectionTransfer = nil"):]
expect(document_end.index("source.collectionTransfer = nil") < document_end.index("finished?(committed)"),
       "a Note or Easel move's end wakes the others before its failure is held, so it can't retry itself")
expect("} else if untargeted {\n                holdFailedReturn(id)" in body(controller, "private func resolveTabTransfer(")
       and "if untargeted, !page.isClosed { holdFailedReturn(id) }" in body(controller, "private func resolvePeekTransfer(")
       and "guard committed else { if untargeted { self.holdFailedReturn(id) }; return }"
           in body(controller, "private func transferDocument("),
       "every untargeted move that ends with the page still here holds its return")
for move in ("private func resolveTabTransfer(", "private func resolvePeekTransfer("):
    step = body(controller, move)
    expect(step.rindex("finish()") < step.index("holdFailedReturn(id)"),
           "a failed return is held after its own move's end has woken the others, so it can't retry itself")
expect("== .started { closeAfterEjecting = true; return true }" in body(controller, "private func ejectPageBeforeClose()"),
       "a closing window's ejection waits only for a started move")
delegate = (root / "Sources/ParcApp/AppDelegate.swift").read_text()
untargeted = body(delegate, "controller.onUntargetedReturn = {")
expect("if trigger == .deselected, owner.returnFailed(id) { return .blocked }" in untargeted,
       "a move that started and failed stops the pass, so a second placeholder window can't retry it in a loop")
expect("return .started" in untargeted and "return PageReparenting.unstartedReturn(candidates)" in untargeted,
       "a return no placeholder window could take reports whether one still keeps its placeholder")
unblocked = body(delegate, "controller.onReturnUnblocked = {")
expect("for other in self.windows where other.store === controller.store { other.retryHeldReturns() }" in unblocked,
       "an unblocking change in one window retries held returns in every window")
closed = body(delegate, "controller.onClose = {")
expect(closed.index("self?.windows.removeAll { $0 === controller }")
       < closed.index("for other in self?.windows ?? [] where other.store === controller.store { other.retryHeldReturns() }"),
       "a closed window lets the others retry, after it is gone, so none waits for it")
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

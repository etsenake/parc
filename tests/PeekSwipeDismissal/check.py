#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]


def body(path, start, end="\n    }\n"):
    text = (root / path).read_text()
    assert text.count(start) == 1, f"{path}: expected one {start!r}"
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


def require(text, where, present=(), absent=()):
    for token in present:
        assert token in text, f"{where} no longer has {token!r}"
    for token in absent:
        assert token not in text, f"{where} has {token!r} again"


peek = "Sources/ParcApp/PeekController.swift"
require(body(peek, "    private func closeConfirmed("), "the confirmed close",
        present=("closeTransition.close(", "observeSheets()"), absent=("browser.requestClose",))
request = body(peek, "    private func requestPageClose() {")
require(request, "the page close request",
        present=("browser.requestClose", "self.refuseClose()", "stopObservingSheets()", "onReturn()"))
assert request.count("closeTransition.holdForParent()") == 2 \
    and request.index("closeTransition.holdForParent()") < request.index("browser.requestClose"), \
    "a Peek whose tab is closing must wait instead of asking or springing back"
require(body(peek, "    func refuseClose() {"), "a refused close or return",
        present=("closeTransition.refused(", "stopObservingSheets()", "restoreFocusAfterRefusal(", "onCloseRefused?()"))
require(body(peek, "    func parentClosingChanged("), "the tab-close notice",
        present=("closeTransition.parentClosingChanged(", "DispatchQueue.main.async", "!self.finished"))
apply = body(peek, "    private func apply(", "\n    }\n\n")
require(apply, "the close effects", present=("case .cancelClose:", "refuseClose()", "onLeavingChange?()", "!finished"))
require(body(peek, "    private func observeSheets() {"), "the Leave site? watch",
        present=("NSWindow.willBeginSheetNotification", "closeTransition.sheetBegan("))
require(body(peek, "    func commitSwipeDismissal() -> Bool {"), "the swipe commit",
        present=("requestDismiss(.swipe)", "closeTransition.springBack()"))
require(body(peek, "    func setVisible("), "hiding a Peek", present=("closeTransition.hide()", "DispatchQueue.main.async"))
require(body(peek, "    func lendFocus("), "the keyboard handover", present=("closeFocusReturn?.lend(",))
focus = "Sources/ParcApp/PeekFocusReturn.swift"
require(body(focus, "    func lend("), "lending the keyboard to the parent",
        present=("original.firstResponder === responder", "makeFirstResponder(nil)", "borrower = current", "lending = true"))
require(body(focus, "    func perform("), "the focus return", present=("current === borrower",))
window = "Sources/ParcApp/BrowserWindowController+Peek.swift"
require(body(window, "    func wirePeek("), "the Peek's window wiring",
        present=("promotePeek(peek, split: false, orphaned: true)",), absent=("onLeavingChange",))
require(body(window, "    func wirePeekPresentation("), "the wiring every Peek, Open in Peek included, shares",
        present=("peek.onLeavingChange", "self.requestNativeSelection()", "self.handPeekFocusToParent(peek)"))
tab = "Sources/ParcApp/BrowserWindowController+TabPeek.swift"
require(body(tab, "    private func wireTabPeek("), "Open in Peek's wiring", present=("controller.onReturn",))
returned = body(tab, "        controller.onReturn = {", "\n        }\n")
assert returned.index("controller.refuseClose()") < returned.index("controller.takeFocusReturn()"), \
    "a failed hand-back must leave the keyboard return with the card so it comes back too"
require((root / tab).read_text(), "Open in Peek", present=("wirePeekPresentation(controller)",))
promote = body(window, "    func promotePeek(")
require(promote, "orphan promotion", present=("!peek.closePending || (orphaned && peek.waitsForParent)",))
notice = body(peek, "    func parentClosingChanged(")
assert notice.index("DispatchQueue.main.async") < notice.index("closeTransition.parentClosingChanged(false)") \
    and "self.parentNotice == notice" in notice, \
    "the all-clear must wait a turn so orphan promotion takes a waiting Peek first, and a newer tab close cancels it"
mutations = {}
for source in sorted((root / "Sources").rglob("*.swift")):
    for number, line in enumerate(source.read_text().splitlines(), 1):
        if "peekRetirementParents" in line and any(f"peekRetirementParents{op}" in line for op in
                                                   (".insert(", ".remove(", ".removeAll(", ".formUnion(", ".subtract(", " = ")):
            mutations.setdefault(source.name, []).append(line.strip())
assert mutations.get("BrowserWindowController.swift") == [
    "var peekRetirementParents = Set<UUID>() { didSet { noteRetiringPeekParents(from: oldValue) } }"], mutations
retiring = {name: lines for name, lines in mutations.items() if name != "BrowserWindowController.swift"}
assert all(any(".remove(" in line for line in lines) for lines in retiring.values()) \
    and {"BrowserWindowController+Closing.swift", "BrowserWindowController+Peek.swift"} <= retiring.keys(), \
    f"both tab-close routes must clear the parent mark that tells waiting Peeks to carry on: {retiring}"
closing = "Sources/ParcApp/BrowserWindowController+Closing.swift"
finished = body(closing, "    func finishPageRetirement(")
require(finished, "the app-wide tab close", present=("peekRetirementParents.remove(id)", "promotePeek(peek, split: false, orphaned: true)"))
group = body(window, "    func closePageAndPeeks(", "\n    }\n\n")
assert group.index("self.peekRetirementParents.remove(id)") < group.index("orphaned: true"), \
    "the window's own tab close must clear the parent mark and still promote orphans"
require(body(window, "    private func handPeekFocusToParent("), "the keyboard handover to the parent",
        present=("peek.lendFocus(", "selectedNativePage() === peek.parentPage", "parentCanTakeFocus(",
                 "binding.requestFocus(for: peek.parentPage)"))
require(body(window, "    func removePeek("), "the focus return after a close",
        present=("self.activePeek == nil && self.parentCanTakeFocus(", "binding.requestFocus(for: peek.parentPage)"))
require(body(window, "    func noteRetiringPeekParents("), "the tab-close notice to Peeks",
        present=("symmetricDifference", "parentClosingChanged(peekRetirementParents.contains("))
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
require(controller, "the window controller",
        present=("var peekRetirementParents = Set<UUID>() { didSet { noteRetiringPeekParents(from: oldValue) } }",))
selected = body("Sources/ParcApp/BrowserWindowController.swift", "    func selectedNativePage() -> PCNativePage? {")
assert selected.index("peek.isLeaving { return peek.parentPage }") < selected.index("currentBrowser"), \
    "a leaving Peek must hand the selected page to its parent so the parent can take the keyboard"
finish = body(peek, "    func finish() {")
require(finish, "retiring a Peek", present=("closeTransition.finish()", "exitTimer?.invalidate()", "stopObservingSheets()"))
assert finish.index("closeTransition.finish()") < finish.index("view.removeFromSuperview()"), \
    "a retiring Peek must go invisible before its view is removed"
require(body(peek, "    private func installSwipeMonitor() {"), "the three-finger swipe", present=("requestDismiss(.swipe)",))
require(body(peek, "    func settleMotion() {"), "settling Peek motion", present=("swipe.complete()",))
require((root / "Sources/ParcApp/HistorySwipeForwarder.swift").read_text(), "the swipe forwarder",
        present=("activePeek(showing:", "canSwipeDismiss", "commitSwipeDismissal()", "followSwipeDismissal(",
                 "beginSwipeDismissal()"))
require(body("Sources/ParcApp/BrowserWindowController+Peek.swift",
             "    func activePeek(showing page: PCNativePage) -> PeekController? {"),
        "the swiped Peek lookup", present=("activePeek", "peek.page === page"))

sources = [root / "tests/Support/TestFailure.swift",
           root / "Sources/ParcCore/HistorySwipeInterface.swift",
           root / "Sources/ParcCore/HistorySwipeRecognizer.swift",
           root / "Sources/ParcApp/PeekDismissalConfirmation.swift",
           root / "Sources/ParcApp/PeekCloseTransition.swift",
           root / "Sources/ParcApp/PeekDismissalMotion.swift",
           Path(__file__).with_name("main.swift")]
with tempfile.TemporaryDirectory(prefix="parc-peek-swipe-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

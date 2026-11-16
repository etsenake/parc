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
require(body(peek, "    private func requestPageClose() {"), "the page close request",
        present=("browser.requestClose", "closeTransition.refused(", "stopObservingSheets()"))
require(body(peek, "    private func observeSheets() {"), "the Leave site? watch",
        present=("NSWindow.willBeginSheetNotification", "closeTransition.sheetBegan("))
require(body(peek, "    func commitSwipeDismissal() -> Bool {"), "the swipe commit",
        present=("requestDismiss(.swipe)", "closeTransition.springBack()"))
require(body(peek, "    func setVisible("), "hiding a Peek", present=("closeTransition.hide()", "DispatchQueue.main.async"))
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

#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
window = browser_window_controller_source(root / "Sources/ParcApp")
peek = (root / "Sources/ParcApp/PeekController.swift").read_text()


def body(text, start, end="\n    }\n"):
    assert text.count(start) == 1, f"expected one {start!r}"
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


assert "let parentPage: PCNativePage?" in peek, "a Peek over a Note, Easel or start page has no parent page"
active = body(window, "    var activePeek: PeekController? {")
assert "peekHostID" in active and "currentTabID" not in active, \
    "the shown Peek is found by the window's host, so a start-page preview shows with no tab selected"
assert "PeekBackdrop.hostID(currentTabID: currentTabID, showsStartPage: showsStartPage, activeSpaceID: activeSpaceID)" in window

preview = body(window, "    func previewArchivedItem(_ id: UUID, profileID: UUID) -> Bool {", "\n    }\n\n")
assert "peekBackdrop.archivePreviewRoute" in preview, "the preview route comes from what the window shows"
assert "parent.openPeek(url: url)" in preview, "a web page behind still opens the preview from that page"
assert "openHostedArchivePreview(url, lease: lease, host: host, token: token, binding: binding)" in preview, \
    "a Note, Easel, start page or empty window gets a window-hosted preview"
assert "selectedNativePage() === parent" not in preview.split("if let parent {")[0], \
    "a missing web page no longer refuses the preview before the route is chosen"
assert "archivePreviews.values.contains(lease)" in preview, \
    "a preview that failed straight away lets a double-click put the item back"

backdrop = body(window, "    var peekBackdrop: PeekBackdrop {")
for token in ("InternalPage.isInternal($0.url)", "showsStartPage: showsStartPage", "hasLivePage:"):
    assert token in backdrop, f"the backdrop lost {token!r}"

opening = body(window, "    private func openHostedArchivePreview(")
assert "binding.open(url, profilePath: path, container: parkedPages)" in opening, \
    "the hosted page is created hidden in this window, with no parent page"
adopt = body(window, "    private func adoptHostedArchivePreview(")
for token in ("request.token == token", "PeekController(page: page, parent: nil, parentTabID: host",
              "archivePreviews[peek.identity] = lease", "wirePeek(peek, binding: binding)",
              "store.releaseArchivePreview(lease); page?.requestClose", "binding.pageWillDetach(page)",
              "presentAdoptedPeek(peek, shown: true, entryFocus: entryFocus)"):
    assert token in adopt, f"hosted adoption lost {token!r}"
present = body(window, "    private func presentAdoptedPeek(")
assert "peekLayer.addSubview(peek.view" in present and "placePeek(peek)" in present, \
    "a hosted preview lands in the window's Peek layer like any other Peek"
assert "presentAdoptedPeek(peek, shown: shown, entryFocus: entryFocus)" in window, \
    "both adoptions share the Peek layer placement, entry motion and focus"

promote = body(window, "    func promotePeek(_ peek: PeekController, split: Bool, orphaned: Bool = false) {")
assert "} else if peek.parentPage == nil {" in promote and "archivePreviews[peek.identity] != nil" in promote, \
    "Expand puts a window-hosted preview back without a parent page"
removal = body(window, "    func removePeek(_ peek: PeekController) {")
assert "self.focusPeekBackdrop()" in removal, "closing a hosted preview returns focus to the Note, Easel or start page behind it"
assert "peekHostID == peek.parentTabID" in body(window, "    private func parentCanTakeFocus("), \
    "focus goes back only while the preview's own Note, Easel or start page is still what the window shows"
assert "preserveHostlessPeeks()" in body(window, "    func render(_ sharedState: BrowserState) {", "\n    }\n\n"), \
    "a hosted preview whose Note, Easel or Space is gone closes instead of holding its archive item"
assert "if peek.parentPage.map({ $0.isClosed }) ?? !self.peekHostLives(peek) { self.promotePeek(peek, split: false, orphaned: true) }" in window, \
    "a hosted preview that refuses to close after its host went keeps its page as a tab"
lost = body(window, "    private func hostlessPreviewLost(_ peek: PeekController) -> Bool {")
for token in ("archivePreviews[peek.identity] != nil", "!peekHostLives(peek)", "!peek.closePending"):
    assert token in lost, f"the automatic close lost {token!r}: after one refusal it must not ask again"
assert "where peek.view.isHidden && self.hostlessPreviewLost(peek)" in window, "only a hidden preview closes by itself"
assert "requestDismiss" not in body(window, "    func preserveHostlessPeeks() {"), \
    "an automatic close never repeats a dismissal that could confirm Hang up"
assert "openPeek(url:))), peek.parentPage != nil," in window, "a hosted preview never leaves a closed-Peek record it can't reopen"
assert "hosted.flatMap(peekProfileID)" in window, "Add Image to Easel works from a preview over a Note or the start page"
lives = body(window, "    private func peekHostLives(_ peek: PeekController) -> Bool {")
assert "activeSpaceID != id || currentTabID == nil" in lives, \
    "a start-page preview closes once a tab takes the start page's place, so it can't hide forever holding its item"
assert "ownership.canUse(id, owner: presentationID)" in lives, "a Note or Easel moved to another window no longer hosts here"
for line in ("peeks.values.filter { $0.parentTabID == id && $0.parentPage != nil && !$0.page.isClosed }.map(\\.page)",
             "peeks.values.contains(where: { $0.parentTabID == id && $0.parentPage != nil }) { peekRetirementParents.insert(id) }"):
    assert line in window, "closing, archiving, moving or splitting a Note or Easel ignores a hidden preview over it"
media = (root / "Sources/ParcApp/BrowserWindowController+MediaAndCapture.swift").read_text()
assert media.count("peekProfileID(peek)") == 3 and "self.revealPeekHost(peek), valid()" in media, \
    "sound in a hidden hosted preview still gets a Mini Player that brings it back"
assert "$0.parentTabID == id && $0.parentPage != nil && !$0.page.isClosed" in window, \
    "moving a Note or Easel to another window isn't blocked by a hidden preview over it"

sources = [root / "Sources/ParcCore/PeekBackdrop.swift", root / "tests/Support/TestFailure.swift",
           root / "tests/PeekBackdropTests.swift"]
with tempfile.TemporaryDirectory(prefix="parc-archive-preview-host-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    "-module-cache-path", str(Path(directory) / "modules"), *map(str, sources), "-o", str(executable)],
                   check=True)
    subprocess.run([str(executable)], check=True)
print("archive preview host checks passed")

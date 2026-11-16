#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
core = root / "Sources/ParcCore"
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources

sidebar = (app / "SidebarView.swift").read_text()
controller = "".join(path.read_text() for path in sorted(app.glob("BrowserWindowController*.swift")))
delegate = (app / "AppDelegate.swift").read_text()
settings = (app / "SettingsWindow.swift").read_text()


def requires(text, uses, reason):
    for use in uses:
        assert use in text, f"{reason}: {use}"


requires(sidebar, ("let pinnedFilter = pinned.folded ? Array(pinned.peek.prefix(1)) : nil",
                   ".container(nil, .pinned, 0, pinnedFilter)",
                   "if pinned.folded, let index = pinned.peek.firstIndex(of: item) {",
                   "isPrivate: isPrivateBrowsing, sectionHeader: pinned.header) {",
                   "case .pinnedSectionHeader:",
                   "page.list.animateDisclosure(from: previousFrames, fadesAppearing: pinnedChanged)"),
         "SidebarView no longer folds Pinned through the checked model")
requires(sidebar, ("guard PinnedSectionCollapse.hasItems(state: state, spaceID: spaceID) else { return .init() }",
                   "let folded = state.spaces.contains { $0.id == spaceID && $0.pinnedCollapsed }",
                   "pinned: pinnedPresentation(state, focused: focused))"),
         "Library Space cards, private windows or the page key lost the Pinned rule")
requires(sidebar, ("return PinnedSectionCollapse.isEmpty(state: state, spaceID: spaceID) ? .init(header: true, placeholder: true) : .init()",
                   "if pinned.placeholder { outline.append(.init(key: SidebarListRow.pinnedHeader, content: header, row: slot.row)); continue }",
                   "let peeks = folder.isExpanded || pinned.folded && pinned.peek.contains(item) ? [] : folderPeeks[folder.id] ?? []",
                   "guard InternalPage(urlString: tab.url) == nil else { header.setFavicon(nil, for: tab.id, url: tab.url); return }"),
         "empty Library cards, folded folder peeks or internal-page icons lost their checked handling")
requires(sidebar, ("if let admitted = pinnedHeaderDrop(session, at: point, copying: copying, state: state, spaceID: spaceID) {",
                   "PinnedSectionCollapse.headerDrop(state: state, spaceID: spaceID, moving: session.items)",
                   "guard admitDrop(session, to: destination, before: first, copying: copying) else { return false }",
                   "if pinnedFolded(spaceID) { springPinnedCandidate = spaceID }",
                   "updatePinnedSpringLoading(operation.isEmpty ? nil : springPinnedCandidate)",
                   "self.onSetPinnedSection?(spaceID, false)",
                   "updatePinnedSpringLoading(nil); sprungFolders = []; sprungPinned = nil"),
         "dropping onto a folded Pinned header no longer follows the checked path")
assert sidebar.count("collapseSprungFolders(); collapseSprungPinned()") == 2, \
    "a cancelled drag no longer folds a spring-opened Pinned back up"
assert "PinnedSectionPreferences" not in sidebar, "the sidebar reads the icon preference only through its window"
requires(controller, ("pinnedPeek: pinnedKeyboardPeek, available: { self.switcherCanUse($0) })",
                      "do { try store.setPinnedSectionCollapsed(collapsed, spaceID: spaceID) }",
                      "pinnedSectionSubscription = wirePinnedSection()",
                      "clearEmptyPinnedFolds(sharedState)",
                      "self.store.clearEmptyPinnedFolds()",
                      "sidebar.onSetCollapsedPinnedIcons = PinnedSectionPreferences.shared.loadError ? nil : { shows in",
                      "sidebar.showsCollapsedPinnedIcons = PinnedSectionPreferences.shared.state.showsCollapsedIcons",
                      "return PinnedSectionPreferences.shared.$state.dropFirst().sink"),
         "the window no longer folds Pinned through the Space or refreshes its header")
assert "collapsedPinnedSpaces" not in controller and "collapsedPinnedSpaces" not in sidebar, \
    "fold state is the Space's, shared by every window, never a window's own copy"
requires(delegate, ("(SidebarPinnedHeaderLayout.actionTitle(collapsed: false), #selector(togglePinnedSection), \"Collapse or Expand Pinned\", false)",
                    "let entry = NSMenuItem(title: title, action: selector, keyEquivalent: \"\")",
                    "KeyboardShortcuts.shared.register(entry, group: view.title, title: setting)",
                    "return spaceCommandWindow?.pinnedSectionCommandAvailable ?? false",
                    "@objc private func togglePinnedSection(_ sender: Any?) { spaceCommandWindow?.togglePinnedSection() }"),
         "the View menu commands lost their checked wiring")
view_menu = delegate[delegate.index('let view = menu("View")'):delegate.index('item("Adjust Window Frame…"')]
assert "togglePinnedSection" in view_menu and "toggleCollapsedPinnedIcons" in view_menu, "the Pinned commands left the View menu"
requires(settings, ('title: "Show icons when Pinned is collapsed", control: collapsedPinnedIcons',
                    "try PinnedSectionPreferences.shared.setShowsCollapsedIcons(collapsedPinnedIcons.state == .on)"),
         "the Settings switch lost its checked wiring")

store = (core / "BrowserStore.swift").read_text()
core_sources = re.search(r"^core_sources=\((.*?)^\)", (root / "scripts/test.sh").read_text(), re.S | re.M)
assert core_sources, "scripts/test.sh no longer lists core_sources"
store_sources = [core / name for name in re.findall(r"Sources/ParcCore/(\w+\.swift)", core_sources.group(1))]
reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
assert reference, "SidebarItemReference not found in BrowserStore.swift"

with tempfile.TemporaryDirectory(prefix="parc-pinned-section-") as directory:
    scratch = Path(directory)
    (scratch / "SidebarItemReference.swift").write_text("import Foundation\n" + reference.group(0))
    (scratch / "ActionButton.swift").write_text(
        "import AppKit\nenum SplitOrientation: Equatable { case horizontal, vertical }\n"
        + sidebar[:sidebar.index("final class MenuAction")])
    suites = {
        "model": [*sorted(core.glob("*.swift")), here / "ModelTests.swift"],
        "header": [*store_sources, app / "SidebarChromeLayout.swift", app / "SidebarRowAppearance.swift",
                   app / "SidebarPinnedHeader.swift", app / "PinnedSectionPreferences.swift",
                   *tooltip_sources(root, scratch, store_sources), here / "HeaderTests.swift"],
        "outline": [core / "SidebarOutlineConfigureSkip.swift", app / "SidebarOutline.swift", app / "SidebarChromeLayout.swift",
                    scratch / "SidebarItemReference.swift", scratch / "ActionButton.swift",
                    app / "TranslucentButtonFace.swift", app / "PointerCover.swift", app / "ReloadControl.swift",
                    app / "PointingHand.swift", here / "OutlineHeaderTests.swift"],
    }
    for name, sources in suites.items():
        executable = scratch / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
print("Pinned section checks passed")

#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
sidebar = (app / "SidebarView.swift").read_text()
for use in ("private let favoritesEmptyState = FavoritesEmptyStateView()",
            "favoritesEmptyState.update(favorites: favorites.count, profileID: space?.profileID, settings: state.settings,",
            "privateWindow: isPrivateBrowsing) { [weak self] in self?.dismissFavoritesEmptyState?($0) }",
            "favoritesEmptyState.trayHeight(gridHeight: grid.height, width: width)",
            "let listY = Chrome.tablistTop(trayHeight: favoritesHeight, spaceHeader: showsSpaceHeader, hasFavorites: !favorites.isEmpty)",
            "dropFeedback.targetRect = favoritesEmptyState.showsDrop(true) ? nil : feedback",
            "favoritesEmptyState.showsDrop(false)"):
    assert use in sidebar, f"SidebarView no longer drives the empty state by the checked paths: {use}"
controller = browser_window_controller_source(app)
assert "sidebar.dismissFavoritesEmptyState = { [weak self] profileID in self?.store.dismissFavoritesEmptyState(profileID: profileID) }" in controller, \
    "BrowserWindowController no longer records a dismissal in the store"
store = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-empty-state-") as directory:
    for name, sources in [("view", [*store, app / "SidebarChromeLayout.swift", app / "SidebarFavoritesEmptyState.swift", app / "PointerCover.swift", app / "PointingHand.swift",
                                    app / "SidebarAccessibility.swift", here / "EmptyStateViewTests.swift"]),
                          ("dismissal", [*store, here / "EmptyStateDismissalTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

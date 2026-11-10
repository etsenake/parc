#!/usr/bin/env python3
"""the first-run App Tray empty state: the production view in off-screen
windows that are never made key (strings, fonts, wrapping, geometry against
the checked model, the dragging style, accessibility, Dismiss and Hide, and the
tray height, list position and keyboard focus it gives two windows of a real
store's profile), and its per-profile dismissal through the real session
store; no browser or input. SidebarChrome's layout suite checks the model's
constants."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
# SidebarView and BrowserWindowController are not compiled here; they only
# hand the view its state, layout and drops through the checked entry points.
sidebar = (app / "SidebarView.swift").read_text()
for use in ("private let favoritesEmptyState = FavoritesEmptyStateView()",
            "favoritesEmptyState.update(favorites: favorites.count, profileID: space?.profileID, settings: state.settings,",
            "privateWindow: isPrivateBrowsing) { [weak self] in self?.dismissFavoritesEmptyState?($0) }",
            "favoritesEmptyState.trayHeight(gridHeight: grid.height, width: width)",
            "let listY = Chrome.tablistTop(trayHeight: favoritesHeight, spaceHeader: showsSpaceHeader, hasFavorites: !favorites.isEmpty)",
            "dropFeedback.targetRect = favoritesEmptyState.showsDrop(true) ? nil : feedback",
            "favoritesEmptyState.showsDrop(false)"):
    assert use in sidebar, f"SidebarView no longer drives the empty state by the checked paths: {use}"
controller = (app / "BrowserWindowController.swift").read_text()
assert "sidebar.dismissFavoritesEmptyState = { [weak self] profileID in self?.store.dismissFavoritesEmptyState(profileID: profileID) }" in controller, \
    "BrowserWindowController no longer records a dismissal in the store"
store = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-empty-state-") as directory:
    for name, sources in [("view", [*store, app / "SidebarChromeLayout.swift", app / "SidebarFavoritesEmptyState.swift", app / "PointerCover.swift", app / "PointingHand.swift",
                                    app / "SidebarAccessibility.swift", here / "EmptyStateViewTests.swift"]),
                          ("dismissal", [*store, here / "EmptyStateDismissalTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

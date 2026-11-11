#!/usr/bin/env python3
"""Actual manager/sidebar responder and AX checks in an undisplayed window.
No engine linkage, browser, OS event dispatch, application activation or real profile.
Only unrelated native media/shortcut host types are inert stand-ins.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
# The window controller is not compiled here: its card Clear must reach the
# shared page-retirement archive for the card's own Space, as the window's does.
controller = (app / "BrowserWindowController.swift").read_text()
configure = controller[controller.index("private func configureSpaceManager("):controller.index("func clearArchive()")]
for use in ("return SpaceClearToday.ids(in: self.store.state, spaceID: id, profileID: space.profileID)",
            ".filter { self.ownership.canUse($0, owner: self.presentationID) }",
            # Nothing it may clear disables a card's Clear; a stale press beeps.
            "sidebar.canClearToday = { targetValid() && !clearable().isEmpty }",
            "sidebar.onClearToday = { [weak self] in",
            "guard let self, targetValid(), let space = self.managementSpace(id) else { return }",
            "let ids = clearable()\n                guard !ids.isEmpty else { NSSound.beep(); return }\n"
            "                self.archiveTabs(ids, reason: .clearButton, in: space)",
            "manager.windowSpaceID = { [weak self] in self?.activeSpaceID }"):
    assert use in configure, f"Library cards no longer use their own window and Space: {use}"
for use in ("archiveTabs(SpaceClearToday.ids(in: store.state, spaceID: activeSpaceID, profileID: activeProfileID), reason: .clearButton)",
            "let spaceID = space?.id ?? originSpace, profileID = space?.profileID ?? originProfile",
            "self.activeSpaceID == originSpace, self.activeProfileID == originProfile else { return false }",
            "&& $0.spaceID == spaceID && $0.profileID == profileID"):
    assert use in controller, f"Clear's shared archive path changed: {use}"
# The window sidebar's New Tab is current while a new-tab bar shows its
# suggestions in the centre: Command-T, the New Tab row and Add Split, not the
# sidebar's keyboard search. Closing the bar ends it.
for use in ("commandBarCreatesNewTab = newTab; commandBarShowsNewTabPlaceholder = newTab && !inSidebar\n        commandBar = panel; panel.present()",
            "commandBarCreatesNewTab = true; commandBarShowsNewTabPlaceholder = true\n        commandBar = panel; panel.present()",
            "if commandBar == nil { commandBarCreatesNewTab = false; commandBarShowsNewTabPlaceholder = false }\n"
            "            refreshSplitPaneHighlights()\n            refreshNewTabPlaceholder()",
            "let active = commandBar != nil && commandBarShowsNewTabPlaceholder\n"
            "        guard sidebar.newTabPlaceholderActive != active else { return }\n"
            "        sidebar.newTabPlaceholderActive = active\n"
            "        if presentation.isReady, !rendering, !isClosing { updateNavigation() }"):
    assert use in controller, f"the New Tab placeholder wiring changed: {use}"
assert controller.count("commandBarShowsNewTabPlaceholder = ") == 4, "an unexpected New Tab placeholder write"
assert controller.count("newTabPlaceholderActive") == 2, "only the window's own sidebar takes the New Tab placeholder"
names = """PArcDialog.swift
PArcMenuColors.swift
SidebarBannerHost.swift
AutoArchiveEducationView.swift
BoxOfThingsIcon.swift
CaptureIndicatorPresentation.swift
CaptureLibraryStore.swift
CommandBarSiteColor.swift
DownloadActivityBadge.swift
DownloadFileDrag.swift
DownloadLibraryPreview.swift
DownloadLibrarySelection.swift
ExtensionControls.swift
FavoriteTile.swift
FavoriteTileLayout.swift
FavoriteTileOverlays.swift
InterfaceFeedback.swift
KeyboardShortcuts.swift
LibraryArtwork.swift
LibraryFlyout.swift
MiniPlayerMotion.swift
MiniPlayerView.swift
NavigationControlPress.swift
PageCardShadow.swift
ParcSplitView.swift
PointerCover.swift
PointingHand.swift
ReloadControl.swift
SadTabContent.swift
SavedFocus.swift
SidebarAccessibility.swift
SidebarAddressPill.swift
SidebarChromeLayout.swift
SidebarDockStrip.swift
SidebarFaviconView.swift
SidebarFavoritesEmptyState.swift
SidebarFolderIcon.swift
SidebarIconCatalog.swift
SidebarItemDrag.swift
SidebarLibraryEntry.swift
SidebarMotionController.swift
SidebarMoveAttentionView.swift
SidebarOutline.swift
SidebarPreviewPreferences.swift
SidebarPlusButtonFace.swift
SidebarPlusMenu.swift
SidebarRowActionButton.swift
SidebarRowAppearance.swift
SidebarSpaceHeader.swift
SidebarSpaceMenu.swift
SidebarSpaceCreationFeedback.swift
SidebarSpacePaging.swift
SidebarSpeakerIcon.swift
SidebarSplitCellLayout.swift
SidebarSplitCellMenu.swift
SidebarSplitTitleView.swift
SidebarTablist.swift
SidebarTablistBackground.swift
SidebarTitleField.swift
SidebarView.swift
SpaceCreationView.swift
SpaceManagerView.swift
SplitDragView.swift
SplitDropGeometry.swift
SplitDropPlaceholderCard.swift
SplitDropView.swift
SplitMarginHandle.swift
ThemeRenderer.swift
Tooltip.swift
TooltipController.swift
TooltipView.swift
TranslucentButtonFace.swift
UpdateCompleteCard.swift
UpdateReadyCard.swift
WindowStandardButtons.swift""".splitlines()
with tempfile.TemporaryDirectory(prefix="parc-space-manager-") as directory:
    scratch = Path(directory)
    excerpts = [
        ("SidebarPreviewController.swift", None, "struct SidebarPreviewRow: Equatable {", ""),
        ("NavigationControls.swift", None, "enum NavigationHistoryMenuMetrics", ""),
        ("SiteControlCenter.swift", None, "enum SiteControlCenterMetrics", ""),
        ("DownloadLibraryView.swift", "@MainActor enum DownloadRowSubtitle", "@MainActor enum DownloadRowArtwork {", "import AppKit\nimport UniformTypeIdentifiers\n"),
        #
        ("OnboardingProgressionButton.swift", "struct PArcButtonSpinner", "extension NSColor", "import SwiftUI\n"),
    ]
    extracted = []
    for name, start, end, prefix in excerpts:
        text = (app / name).read_text()
        path = scratch / name
        path.write_text(prefix + text[text.index(start) if start else 0:text.index(end)])
        extracted.append(path)
    text = (app / "DownloadLibraryView.swift").read_text()
    path = scratch / "DownloadFileActivation.swift"
    path.write_text("import AppKit\nimport UniformTypeIdentifiers\n" + text[text.index("enum DownloadFileActivation"):])
    extracted.append(path)
    sources = list((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + extracted
    sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift",
                Path(__file__).with_name("NativeHostStub.swift"), Path(__file__).with_name("SpaceManagerTests.swift")]
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
names = """ParcDialog.swift
ParcMenuColors.swift
SidebarBannerHost.swift
AutoArchiveEducationView.swift
BlockedContentSign.swift
BlockedPageContent.swift
BoxOfThingsIcon.swift
CaptureIndicatorPresentation.swift
CaptureLibraryStore.swift
CommandBarSiteColor.swift
DocumentDefaultIcon.swift
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
MenuItemImage.swift
MiniPlayerMotion.swift
MiniPlayerView.swift
NavigationControlPress.swift
NoteTabIconArt.swift
PageCardShadow.swift
ParcSplitView.swift
PointerCover.swift
PointingHand.swift
ReloadControl.swift
SadTabContent.swift
SavedFocus.swift
SidebarAccessibility.swift
SidebarAddressPill.swift
SidebarAddressText.swift
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
SidebarNotePlacement.swift
SidebarOutline.swift
SidebarPinnedHeader.swift
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
        ("OnboardingProgressionButton.swift", "struct ParcButtonSpinner", "extension NSColor", "import SwiftUI\n"),
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
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

#!/usr/bin/env python3
"""the home width, read only on a page change
, over the actual LibraryView, SpaceManagementLayout and
SidebarChromeFrames. The Library is never put in a
window and the process cannot activate; no browser, engine, input or real
profile. The window controller's group, settle and close are asserted in
tests/SidebarMotion."""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-library-width-") as directory:
    temporary = pathlib.Path(directory)
    # As tests/DownloadLibrary/check-view.py: the shared controls at the start
    # of SidebarView.swift, the documents catalog's lazy store owner, and only
    # the card sidebar's members SpaceManagerView reaches.
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    controls = temporary / "NativeControls.swift"
    controls.write_text(sidebar[:sidebar.index("final class FlippedStackView:")])
    easel = (root / "Sources/ParcApp/EaselEditorViewController.swift").read_text()
    store_owner = temporary / "EaselStoreOwner.swift"
    store_owner.write_text(easel[:easel.index("    private let session:")] + "}\n")
    sidebar_stub = temporary / "SpaceCardSidebar.swift"
    sidebar_stub.write_text("""import AppKit
@MainActor final class SidebarView: NSView {
    var keyViewExit: NSView?
    var isSpaceManagement = false
    var palette: ThemeChromePalette?
    func cancelSpaceNameEditing() {}
    func spaceAppearanceAnchor(_ id: UUID) -> NSView? { nil }
    func render(state: BrowserState, focusedTabID: UUID?, loading: Set<UUID>, canBack: Bool, canForward: Bool) {}
}
""")
    app = ["LibraryView", "CaptureLibraryStore", "CaptureLibraryView", "DocumentsLibraryView", "DownloadLibrarySelection", "DownloadLibraryTable", "DownloadLibraryView",
           "DownloadLibraryPreview", "DownloadActivityBadge", "DownloadThumbnailProvider", "DownloadFileDrag", "ThemeRenderer", "LibraryArtwork",
           "ExternalMediaLibrary", "CaptureLibrarySharing", "MediaLibraryContext", "SpaceManagerView", "SidebarIconCatalog", "SidebarRowAppearance",
           "CaptureMotion", "DownloadArrivalMotion", "LibraryRailTile", "LibraryRailIcon", "WindowStandardButtons", "TranslucentButtonFace", "ReloadControl",
           "SidebarMotionController", "PArcToast", "TopBarColorClient", "PArcDialog"]
    sources = sorted((root / "Sources/ParcCore").glob("*.swift"))
    sources += [root / "Sources/ParcApp" / f"{name}.swift" for name in app]
    sources += [controls, store_owner, sidebar_stub, pathlib.Path(__file__).with_name("LibraryWidthTests.swift")]
    sources += tooltip_sources(root, temporary, sources)
    shutil.copytree(root / "Resources/Library", temporary / "Library")
    executable = temporary / "library-width"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)

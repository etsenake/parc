#!/usr/bin/env python3
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
           "SidebarMotionController", "ParcToast", "TopBarColorClient", "ParcDialog"]
    sources = sorted((root / "Sources/ParcCore").glob("*.swift"))
    sources += [root / "Sources/ParcApp" / f"{name}.swift" for name in app]
    spinner = temporary / "ParcButtonSpinner.swift"
    subprocess.run([sys.executable, "-B", str(root / "tests/Support/declarations.py"), str(spinner), "ParcButtonSpinner"],
                   check=True, stdout=subprocess.DEVNULL)
    sources += [controls, store_owner, sidebar_stub, spinner, root / "tests/Support/AppKitObservation.swift",
                pathlib.Path(__file__).with_name("LibraryWidthTests.swift")]
    sources += tooltip_sources(root, temporary, sources)
    shutil.copytree(root / "Resources/Library", temporary / "Library")
    executable = temporary / "library-width"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)

#!/usr/bin/env python3
import pathlib
import subprocess
import tempfile
import os
import plistlib
import shutil
import re

root = pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
with tempfile.TemporaryDirectory(prefix="parc-download-library-view-") as directory:
    temporary = pathlib.Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    controls = temporary / "NativeControls.swift"
    controls.write_text(sidebar[:sidebar.index("final class FlippedStackView:")])
    easel = (root / "Sources/ParcApp/EaselEditorViewController.swift").read_text()
    store_owner = temporary / "EaselStoreOwner.swift"
    store_owner.write_text(easel[:re.search(r"^    (?:private )?let session:", easel, re.M).start()] + "}\n")
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
    app = ["LibraryView", "CaptureLibraryStore", "CaptureLibraryView", "DocumentsLibraryView", "DocumentDefaultIcon", "DocumentsLibraryCatalog", "NoteAnimation", "DownloadLibrarySelection", "DownloadLibraryTable", "DownloadLibraryView",
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
                root / "tests/DownloadLibrary/ViewTests.swift"]
    sources += tooltip_sources(root, temporary, sources)
    shutil.copytree(root / "Resources/Library", temporary / "Library")
    executable = temporary / "download-library-view"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library", *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)
    if destination := os.environ.get("PARC_COMPONENT_APP"):
        app = pathlib.Path(destination)
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(executable, contents / "MacOS" / "DownloadLibraryComponent")
        shutil.copytree(root / "Resources/Library", contents / "Resources" / "Library", dirs_exist_ok=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.parc.DownloadLibraryComponent",
            "CFBundleExecutable": "DownloadLibraryComponent", "CFBundleName": "DownloadLibraryComponent",
            "CFBundlePackageType": "APPL", "ParcComponentPreview": True,
        }))

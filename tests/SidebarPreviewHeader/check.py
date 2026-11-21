#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-preview-header-") as directory:
    scratch = Path(directory)
    slices = {
        "ActionButton.swift": ("SidebarView.swift", "class LayoutView"),
        "ThemePalette.swift": ("ThemeRenderer.swift", "@MainActor\nenum NativeInputDiagnostics"),
        "SidebarPreviewModel.swift": ("SidebarPreviewController.swift", "@MainActor\nfinal class SidebarPreviewController"),
    }
    for target, (source, marker) in slices.items():
        text = (root / "Sources/ParcApp" / source).read_text()
        (scratch / target).write_text(text[:text.index(marker)])
    action = scratch / "ActionButton.swift"
    action.write_text("enum SplitOrientation: Equatable { case horizontal, vertical }\n" + action.read_text())
    shutil.copytree(root / "Resources/SidebarPreview", scratch / "SidebarPreview")
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
        str(root / "Sources/ParcCore/SpaceTheme.swift"),
        str(root / "Sources/ParcCore/SidebarPreviewTitles.swift"),
        str(root / "Sources/ParcCore/SidebarPreviewActivation.swift"),
        str(root / "Sources/ParcCore/NoteFileKind.swift"), str(root / "Sources/ParcCore/SidebarDocumentPreview.swift"),
        *[str(scratch / name) for name in slices],
        str(root / "Sources/ParcApp/PopoverBackgroundView.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewPresentation.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewCard.swift"),
        str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
        str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
        str(root / "tests/Support/AppKitObservation.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
card = (root / "Sources/ParcApp/SidebarPreviewCard.swift").read_text()
assert 'peek.image = SidebarPreviewArtwork.openInPeek' in card, "the header's Open in Peek button must use the bundled artwork"
assert 'appendingPathComponent("SidebarPreview", isDirectory: true)' in card, "the artwork loads from Resources/SidebarPreview"
for name in ("open-in-peek.pdf", "open-in-peek.png", "open-in-peek@2x.png"):
    assert (root / "Resources/SidebarPreview" / name).is_file(), f"missing artwork {name}"
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
        *[str(scratch / name) for name in slices],
        str(root / "Sources/ParcApp/PopoverBackgroundView.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewPresentation.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewCard.swift"),
        str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
        str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
        str(root / "tests/Support/AppKitObservation.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

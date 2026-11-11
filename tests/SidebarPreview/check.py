#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/SidebarPreviewController.swift").read_text()
assert "let visible = view.visibleRect.intersection(view.bounds)" in controller \
    and "return host.convert(visible, from: view)" in controller, "the preview anchor is no longer its row's own visible part"
assert "SidebarPreviewMotion.keepsSessionTarget" in controller, "row stay must skip sidebar hit-testing"
assert "!(hit is NSButton)" in controller, "row stay must keep previewTarget's NSButton exclusion"
assert "if event.type == .mouseMoved, let host" in controller \
    and "if !overCard, sessionNeedsReconcile()" in controller, \
    "mouseMoved over the open card must skip session reconcile without dropping host-nil reconcile"
with tempfile.TemporaryDirectory(prefix="parc-sidebar-preview-") as directory:
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
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
        str(root / "Sources/ParcCore/SpaceTheme.swift"),
        str(root / "Sources/ParcCore/SidebarPreviewTitles.swift"),
        str(root / "Sources/ParcCore/SidebarPreviewActivation.swift"),
        *[str(scratch / name) for name in slices],
        str(root / "Sources/ParcApp/PopoverBackgroundView.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewPresentation.swift"),
        str(root / "Sources/ParcApp/SidebarPreviewCard.swift"),
        str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
        str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

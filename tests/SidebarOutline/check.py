#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-outline-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    for removed in ("list.addArrangedSubview", "list.arrangedSubviews", ".selectedChildrenChanged", "SidebarOutlineEntry("):
        assert removed not in sidebar, f"SidebarView bypasses the outline: {removed}"
    hand_built = [key for key in re.findall(r"outline\.append\(\.init\(key: ([\w.]+)", sidebar) if not key.startswith("SidebarListRow.")]
    assert not hand_built, f"items reach the outline only through its checked entry helpers: {hand_built}"
    assert "outline.append(.pinnedHeader(SidebarListRow.pinnedHeader))" in sidebar, "SidebarView builds its pinned header row without the checked entry"
    assert "button?.activate?()" not in sidebar, "a folder row's AXDisclosing runs the folder click"
    store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
    reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
    assert reference, "SidebarItemReference not found in BrowserStore.swift"
    (scratch / "SidebarItemReference.swift").write_text("import Foundation\n" + reference.group(0))
    (scratch / "ActionButton.swift").write_text(
        "import AppKit\nenum SplitOrientation: Equatable { case horizontal, vertical }\n"
        + sidebar[:sidebar.index("final class MenuAction")])
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SidebarOutlineConfigureSkip.swift"),
                    str(root / "Sources/ParcApp/SidebarOutline.swift"),
                    str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
                    str(scratch / "SidebarItemReference.swift"),
                    str(scratch / "ActionButton.swift"),
                    str(root / "Sources/ParcApp/TranslucentButtonFace.swift"), str(root / "Sources/ParcApp/PointerCover.swift"),
                    str(root / "Sources/ParcApp/ReloadControl.swift"), str(root / "Sources/ParcApp/PointingHand.swift"),
                    str(Path(__file__).with_name("SidebarOutlineTests.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

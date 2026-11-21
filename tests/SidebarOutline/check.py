#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-sidebar-outline-") as directory:
    scratch = Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    store = (root / "Sources/ParcCore/BrowserStore.swift").read_text()
    reference = re.search(r"^enum SidebarItemReference\b.*?^\}\n", store, re.S | re.M)
    selection = re.search(r"^struct SidebarItemSelection\b.*?^\}\n", store, re.S | re.M)
    (scratch / "SidebarItemReference.swift").write_text("import Foundation\n" + reference.group(0) + selection.group(0))
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

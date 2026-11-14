#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
app = root / "Sources/ParcApp"
core = root / "Sources/ParcCore"
controller = (app / "BrowserWindowController.swift").read_text()
for use in ("frameThickness: frameThickness\n",
            "sidePanel: extensionSidePanelVisible, thickness: frameThickness)",
            "isPopupWindow ? SidebarChromeFrames.pageInset : WindowFramePreferences.shared.thickness",
            "guard WindowFrameThickness.showsSplitGrip(inset)",
            "setContentResizeReason(.frameAdjust, active: preferences.isAdjusting)",
            "windowFrameSubscription = WindowFramePreferences.shared.objectWillChange.sink",
            "|| frameCrank != nil",
            "func windowWillClose(_ notification: Notification) { abandonFrameCrank();",
            "frameCrank?.finishNow(commit: true)"):
    assert use in controller, f"BrowserWindowController no longer wires the window frame by the checked path: {use}"
assert controller.count("splitView.dividerThickness = frameThickness") == 2, "both chrome passes size the split gutters"
assert controller.count("layoutFrameCrank(") >= 3, "both chrome passes keep the crank in place"
with tempfile.TemporaryDirectory(prefix="parc-window-frame-") as directory:
    for name, sources in [("geometry", [app / "SidebarMotionController.swift", app / "SidebarChromeLayout.swift",
                                        app / "WindowStandardButtons.swift", here / "GeometryTests.swift"]),
                          ("preferences", [core / "WindowFrame.swift", app / "WindowFramePreferences.swift",
                                           here / "PreferenceTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

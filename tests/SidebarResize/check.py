#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
model = root / "Sources/ParcCore/SidebarResize.swift"
placement = root / "Sources/ParcCore/SavedWindowFrame.swift"
hold = root / "Sources/ParcCore/PageContentResize.swift"
core = sorted((root / "Sources/ParcCore").glob("*.swift"))
with tempfile.TemporaryDirectory(prefix="parc-sidebar-resize-") as directory:
    for name, sources in [("gesture", [model, here / "SidebarResizeGestureTests.swift"]),
                          ("width", [model, here / "SidebarWindowWidthTests.swift"]),
                          ("placement", [placement, here / "SavedWindowFrameTests.swift"]),
                          ("session", [*core, here / "SidebarWindowSessionTests.swift"]),
                          ("region", [model, root / "Sources/ParcApp/SidebarResizeRegion.swift", root / "Sources/ParcApp/PointerCover.swift",
                                      here / "SidebarResizeRegionTests.swift"]),
                          ("hold", [hold, here / "PageContentResizeTests.swift"]),
                          ("resizer", [hold, root / "Sources/ParcApp/PageContentResizer.swift",
                                       here / "PageContentResizerTests.swift"]),
                          ("frames", [hold, root / "Sources/ParcApp/PageContentResizer.swift",
                                      root / "Sources/ParcApp/PageRenderFrames.swift",
                                      here / "EngineStub.swift", here / "PageRenderFramesTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

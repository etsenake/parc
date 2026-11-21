#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
hold = root / "Sources/ParcCore/PageContentResize.swift"
with tempfile.TemporaryDirectory(prefix="parc-sidebar-resize-") as directory:
    for name, sources in [("frames", [hold, root / "Sources/ParcApp/PageContentResizer.swift",
                                      root / "Sources/ParcApp/PageRenderFrames.swift",
                                      here / "EngineStub.swift", here / "PageRenderFramesTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

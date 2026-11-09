#!/usr/bin/env python3
"""A Space swipe's main-thread work on the production SidebarView with 5, 50
and 200 folders and items per Space, in an off-screen window that is never
shown and, like the browser window, lays its content out with constraints.
Phased scroll events are built in memory and handed to the sidebar; no
browser, engine, posted events or preferences. Prints each size's frame times,
release, spring frames, a jump to the farthest Space, the rows each swipe
builds, the longest idle turn, the frames of a scroll through the list, a
drag auto-scrolling it, a folder springing open under the drag and folders
expanding and collapsing, and the footprint. Without arguments it is the
regression check at 5 and 50 folders, four Spaces, first visits and returns:
no swipe builds a row, swipe frames stay within a frame, spring frames, idle
turns and list frames stay under 8 ms, releases and far jumps under 50 ms.
"""
from pathlib import Path
import ast
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
# The sources the Space Manager's real-sidebar checks compile.
manager = ast.parse((root / "tests/SpaceManager/check.py").read_text())
names = excerpts = None
for node in ast.walk(manager):
    if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
        if node.targets[0].id == "names":
            names = node.value.func.value.value.splitlines()
        elif node.targets[0].id == "excerpts":
            excerpts = ast.literal_eval(node.value)
assert names and excerpts, "tests/SpaceManager/check.py no longer lists the sidebar's sources"

with tempfile.TemporaryDirectory(prefix="parc-space-swipe-") as directory:
    scratch = Path(directory)
    extracted = []
    for name, start, end, prefix in excerpts:
        text = (app / name).read_text()
        path = scratch / name
        path.write_text(prefix + text[text.index(start) if start else 0:text.index(end)])
        extracted.append(path)
    text = (app / "DownloadLibraryView.swift").read_text()
    path = scratch / "DownloadFileActivation.swift"
    path.write_text("import AppKit\nimport UniformTypeIdentifiers\n" + text[text.index("enum DownloadFileActivation"):])
    extracted.append(path)
    sources = list((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + extracted
    sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift",
                root / "tests/SpaceManager/NativeHostStub.swift", Path(__file__).with_name("main.swift")]
    executable = Path(os.environ.get("SWIPE_BINARY", scratch / "swipe"))
    subprocess.run(["xcrun", "swiftc", "-O", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    # Without sizes: the regression check at 5 and 50 folders and items, four Spaces.
    environment = dict(os.environ) if len(sys.argv) > 1 else {**os.environ, "SWIPE_ASSERT": "1", "SWIPE_SPACES": "4"}
    run = lambda: subprocess.run([str(executable), *(sys.argv[1:] or ["5", "50"])], env=environment).returncode
    # Frame timings are wall clock: a busy Mac gets one more try before a failure counts.
    if run() != 0 and (len(sys.argv) > 1 or run() != 0):
        sys.exit("SidebarSpaceSwipe failed")

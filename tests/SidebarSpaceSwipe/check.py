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
it fails if a swipe or jump builds a row or a page doesn't settle, and reports
the three-run medians against the frame limits (swipe frames within a frame,
spring frames, idle turns and list frames under 8 ms, folder expansion under
16 ms, releases and far jumps under 50 ms).
"""
from pathlib import Path
import ast
import os
import re
import statistics
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
    if len(sys.argv) > 1:
        sys.exit(subprocess.run([str(executable), *sys.argv[1:]]).returncode)
    # The regression check at 5 and 50 folders and items, four Spaces. The
    # binary fails on what is exact: no swipe or jump builds rows, pages
    # settle, list motion produces frames. Frame times are wall clock: the same
    # build measured 10 ms and 25 ms runs apart, so their medians over three
    # runs are reported against the limits rather than failing the suite.
    environment = {**os.environ, "SWIPE_ASSERT": "1", "SWIPE_SPACES": "4"}
    limits = {"swipe first frame": 16, "other frames max": 16, "settle frame max": 8, "release": 50,
              "far jump": 50, "longest idle turn": 8, "scroll frame max": 8, "drag auto-scroll frame max": 8,
              "spring-open frame max": 16, "expand/collapse frame max": 16}
    samples = {}
    for _ in range(3):
        result = subprocess.run([str(executable), "5", "50"], env=environment, capture_output=True, text=True)
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            sys.exit(result.stderr + "SidebarSpaceSwipe failed")
        for line in result.stdout.splitlines():
            size = re.match(r"(\d+) folders\+", line)
            for name in limits if size else ():
                value = re.search(re.escape(name) + r" ([0-9.]+) ms", line)
                assert value, f"the report no longer gives the {name}"
                samples.setdefault((int(size.group(1)), name), []).append(float(value.group(1)))
    assert {size for size, _ in samples} == {5, 50}, "the report no longer covers 5 and 50 folders"
    slow = [f"{size} folders: {name} median {statistics.median(values):.1f} ms (limit {limits[name]})"
            for (size, name), values in sorted(samples.items()) if statistics.median(values) >= limits[name]]
    for line in slow:
        print("SidebarSpaceSwipe timing over its limit on this machine: " + line)
    print("SidebarSpaceSwipe: no swipe or jump built rows and every page settled over three runs")

#!/usr/bin/env python3
"""Library rail tile playback and Downloads badge, offscreen: no activation, events or browser."""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-library-rail-") as directory:
    temporary = pathlib.Path(directory)
    sources = sorted((root / "Sources/ParcCore").glob("*.swift"))
    sources += [root / "Sources/ParcApp" / f"{name}.swift" for name in
                ("LibraryRailTile", "LibraryRailIcon", "DownloadActivityBadge", "DownloadLibrarySelection", "WindowStandardButtons")]
    sources += [root / "tests/Support/AppKitObservation.swift", pathlib.Path(__file__).with_name("main.swift")]
    sources += tooltip_sources(root, temporary, sources)
    # An unbundled executable's Bundle.main.resourceURL is its own directory,
    # so the rail compositions sit beside the binary as they do in the app.
    shutil.copytree(root / "Resources/Library", temporary / "Library")
    executable = temporary / "library-rail"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)

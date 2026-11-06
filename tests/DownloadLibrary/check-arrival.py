#!/usr/bin/env python3
"""Exercise the actual DownloadToLibrary arrival sources without Chromium.

Synthetic arrivals only: a disposable borderless parent window far outside every
display, a manual clock and explicitly ticked frames. No browser, download or
personal file is touched. Set PARC_ARRIVAL_ACCEPTANCE=<dir> to also render the
real arrival layer tree at sampled times into PNGs there.
"""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-download-arrival-") as directory:
    executable = pathlib.Path(directory) / "download-arrival"
    sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [
        root / "Sources/ParcApp/ThemeRenderer.swift",
        root / "Sources/ParcApp/DownloadArrivalMotion.swift",
        root / "Sources/ParcApp/DownloadArrival.swift",
        # The bin's item is the Library entry's BoxOfThingsIcon item.
        root / "Sources/ParcApp/LibraryArtwork.swift",
        root / "Sources/ParcApp/BoxOfThingsIcon.swift",
        root / "Sources/ParcApp/TranslucentButtonFace.swift",
        root / "Sources/ParcApp/ReloadControl.swift",
        root / "tests/DownloadLibrary/ArrivalTests.swift",
    ]
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    # An unbundled executable's Bundle.main.resourceURL is its own directory.
    shutil.copytree(root / "Resources/Library", pathlib.Path(directory) / "Library")
    subprocess.run([str(executable)], check=True, timeout=120)

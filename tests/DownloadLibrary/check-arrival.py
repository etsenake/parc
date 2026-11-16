#!/usr/bin/env python3
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
        root / "Sources/ParcApp/LibraryArtwork.swift",
        root / "Sources/ParcApp/BoxOfThingsIcon.swift",
        root / "Sources/ParcApp/TranslucentButtonFace.swift",
        root / "Sources/ParcApp/ReloadControl.swift",
        root / "tests/Support/AppKitObservation.swift",
        root / "tests/DownloadLibrary/ArrivalTests.swift",
    ]
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    shutil.copytree(root / "Resources/Library", pathlib.Path(directory) / "Library")
    subprocess.run([str(executable)], check=True, timeout=120)

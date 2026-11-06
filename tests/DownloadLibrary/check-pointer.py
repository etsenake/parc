#!/usr/bin/env python3
"""Visible inert AppKit mouse tracking; synthetic rows, no browser/file actions.

Coordinate the foreground before running. The component requires its genuine
key/active window and closes it after the bounded native input assertions.
"""
import pathlib
import plistlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-download-pointer-") as directory:
    contents = pathlib.Path(directory) / "DownloadPointer.app" / "Contents"
    executable = contents / "MacOS" / "DownloadPointer"
    executable.parent.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.parc.DownloadPointerComponent",
        "CFBundleExecutable": executable.name,
        "CFBundleName": "Downloads pointer component",
        "CFBundlePackageType": "APPL",
    }))
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library",
                    str(root / "Sources/ParcApp/DownloadLibraryTable.swift"),
                    str(root / "tests/DownloadLibrary/PointerTests.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)

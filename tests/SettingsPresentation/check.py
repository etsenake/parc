#!/usr/bin/env python3
"""Inert native presentation checks; never creates a browser or touches preferences."""
import pathlib
import subprocess
import sys
import tempfile
root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-settings-presentation-") as folder:
    folder = pathlib.Path(folder)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    (folder / "NativeControls.swift").write_text(sidebar[:sidebar.index("final class FlippedStackView:")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    executable = folder / "presentation"
    sources = [folder / "NativeControls.swift", root / "Sources/ParcApp/TranslucentButtonFace.swift",
               root / "Sources/ParcApp/ReloadControl.swift", root / "Sources/ParcApp/SettingsHoverButton.swift",
               root / "Sources/ParcApp/SettingsPresentation.swift", root / "tests/SettingsPresentation/PresentationTests.swift"]
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    # The light/dark component renders go to the given directory, else build/.
    renders = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build/tests/settings-presentation"
    subprocess.run([str(executable), str(root), str(renders)], check=True)
    print(f"Settings presentation renders: {renders}")

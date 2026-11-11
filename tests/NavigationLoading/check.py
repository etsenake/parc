#!/usr/bin/env python3
from pathlib import Path
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
source = (app / "PageLoadingIndicator.swift").read_text()
assert "enum PageLoadingPresentationSkip" in source, "presentation skip helper missing"
assert "static func shouldSkip(previous: PageLoadingPresentation?, next: PageLoadingPresentation)" in source, \
    "shouldSkip predicate missing"
assert "previous == next" in source, "shouldSkip must be a true identical-fingerprint no-op"
assert "PageLoadingPresentationSkip.shouldSkip(previous: lastPresentation, next: next)" in source, \
    "presentPulse must gate on PageLoadingPresentationSkip.shouldSkip"
body_start = source.index("private func presentPulse(stroke:")
body = source[body_start:source.index("\n    override func viewDidChangeEffectiveAppearance", body_start)]
assert body.index("PageLoadingPresentationSkip.shouldSkip(") < body.index("CATransaction.begin()"), \
    "shouldSkip must run before the layer transaction"
assert "presentPulse(stroke: stroke)" in source, "tick must present through the skip gate"
assert "updateSweep(" not in source, "sweep writes belong in the gated present path"
with tempfile.TemporaryDirectory(prefix="parc-navigation-loading-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(app / "PageLoadingIndicator.swift"), str(app / "ReloadControl.swift"),
                    str(app / "SidebarChromeLayout.swift"), str(root / "tests/Support/AppKitObservation.swift"),
                    str(Path(__file__).with_name("main.swift")),
                    "-o", str(executable)], check=True)
    shutil.copytree(root / "Resources/NavigationControls", Path(directory) / "NavigationControls")
    subprocess.run([str(executable)], check=True)
print("NavigationLoading presentation-skip check passed")

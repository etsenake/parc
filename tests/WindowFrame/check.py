#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
here = Path(__file__).parent
model = root / "Sources/ParcCore/WindowFrame.swift"
preferences = root / "Sources/ParcApp/InterfaceFeedback.swift"
feedback = root / "Sources/ParcApp/WindowFrameCrankFeedback.swift"
scene = root / "Sources/ParcApp/WindowFrameCrankModel.swift"
view = root / "Sources/ParcApp/WindowFrameCrankView.swift"
saved = root / "Sources/ParcApp/SavedFocus.swift"
with tempfile.TemporaryDirectory(prefix="parc-window-frame-") as directory:
    for name, sources in [("model", [model, here / "ModelTests.swift"]),
                          ("feedback", [model, preferences, feedback, here / "FeedbackTests.swift"]),
                          ("view", [model, preferences, feedback, scene, saved, view, here / "ViewTests.swift"])]:
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                        *map(str, sources), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

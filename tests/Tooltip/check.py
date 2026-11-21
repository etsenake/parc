#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from support import tooltip_sources

root = Path(__file__).resolve().parents[2]


with tempfile.TemporaryDirectory(prefix="parc-tooltip-") as directory:
    scratch = Path(directory)
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *[str(path) for path in tooltip_sources(root, scratch, [])],
                    str(root / "tests/Support/AppKitObservation.swift"),
                    str(Path(__file__).with_name("TooltipTests.swift")), "-o", str(executable)], check=True)
    run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=120)
    print(run.stdout, end="")
    assert run.returncode == 0, run.stderr
    assert "Invalid message sent to event" not in run.stdout + run.stderr, run.stderr

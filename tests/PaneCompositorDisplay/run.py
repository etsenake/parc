#!/usr/bin/env python3
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path,
                    default=ROOT / "Engine/ParcNative/pane_compositor.mm")
parser.add_argument("--case", choices=["all", "reuse", "suspended", "callbacks"],
                    default="all")
args = parser.parse_args()
source = args.source.read_text()
methods = ["ClearDisplay", "AcceleratedWidgetCALayerParamsUpdated",
           "SuspendDrawing", "ResumeDrawing", "Hide", "NotifyPresented",
           "RequestPresentation", "DropPresentation"]
out = ROOT / "build/tests/pane-compositor-display"
out.mkdir(parents=True, exist_ok=True)
bodies = []
for method in methods:
    start = source.index(f"void NativePaneCompositor::{method}(")
    end = source.index("\n}", start) + 2
    bodies.append(source[start:end])
(out / "handoff.inc").write_text("\n\n".join(bodies) + "\n")
subprocess.run([
    "xcrun", "clang++", "-arch", "arm64", "-std=c++20",
    "-mmacosx-version-min=13.0", "-fobjc-arc", "-fblocks",
    "-Wall", "-Wextra", "-Werror", "-I", str(out),
    "-I", str(ROOT / "Engine/ParcNative"),
    str(ROOT / "Engine/ParcNative/pane_compositor_view.mm"),
    str(ROOT / "tests/PaneCompositorDisplay/Tests.mm"),
    "-framework", "Cocoa", "-framework", "QuartzCore",
    "-o", str(out / "check"),
], check=True)
raise SystemExit(subprocess.run([str(out / "check"), args.case]).returncode)

#!/usr/bin/env python3
"""Whether a built engine carries the renderer frame report the sidebar-width
page hold needs (PCNativePage (RenderFrameViewport)), read with nm only; no
engine is loaded or launched.

Usage: engine_report.py <engine-artifacts.json | framework binary>...

A sealed manifest names its framework under engine_dir, whose SHA-256 must
match; a binary (for example a packaged app's framework copy) is read as is.
PCBrowserView takes the report through responds(to:) on these selectors
(PageRenderFrames in the app); without them a throttled page runs
as intrinsic and resizes on every pointer event.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
REQUIRED = ["-[PCNativePage(RenderFrameViewport) observeRenderFrameViewportSize:]",
            "-[PCNativePage(RenderFrameViewport) renderFrameViewportSize]",
            "-[PCNativeRenderFrameObservation invalidate]",
            "_OBJC_CLASS_$_PCNativeRenderFrameObservation"]

if len(sys.argv) < 2:
    sys.exit(__doc__)
failed = False
for argument in sys.argv[1:]:
    path = Path(argument)
    if path.suffix == ".json":
        manifest = json.loads(path.read_text())
        binary = Path(manifest["engine_dir"]) / "Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"
        expected = manifest["framework"]["Versions/A/Chromium Embedded Framework"]["sha256"]
        digest = hashlib.sha256(binary.read_bytes()).hexdigest()
        if digest != expected:
            print(f"FAIL {path}: {binary} is {digest}, the manifest lists {expected}"); failed = True; continue
    else:
        binary = path
    symbols = subprocess.run(["xcrun", "nm", "-m", str(binary)], check=True, capture_output=True, text=True).stdout
    missing = [name for name in REQUIRED if name not in symbols]
    if missing:
        print(f"FAIL {argument}: missing {', '.join(missing)}"); failed = True
    else:
        print(f"ok {argument}: {len(REQUIRED)} renderer frame report symbols")
sys.exit(1 if failed else 0)

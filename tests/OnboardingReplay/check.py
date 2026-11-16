#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

ROOT = Path(__file__).resolve().parents[2]


def method(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end].replace("private func", "func")


app = (ROOT / "Sources/ParcApp/AppDelegate.swift").read_text()
browser = browser_window_controller_source(ROOT / "Sources/ParcApp")
template = (Path(__file__).parent / "Harness.swift").read_text()
browser_methods = "\n".join(method(browser, signature) for signature in (
    "func prepareAuxiliaryWindowForOnboarding(", "func closeForOnboarding(",
    "func windowShouldClose(", "func finishScriptingWindowClose("))
app_methods = "\n".join(method(app, signature) for signature in (
    "private func startOnboardingReplay(", "private func restoreReplayWindow(",
    "private func finishOnboardingReplay("))
for signature in ("func requestApplicationTermination(", "private func continueApplicationTermination("):
    gate = method(app, signature).split("        guard started else", 1)[0]
    app_methods += "\n" + gate + "        globalQuitRequests += 1\n    }"
browser_end = "\n}\nfinal class AppDelegate {"
app_end = "\n}\nfunc drain()"
assert template.count(browser_end) == 1 and template.count(app_end) == 1, "Harness.swift class endings moved"
generated = (template.replace(browser_end, "\n    " + browser_methods + browser_end)
             .replace(app_end, "\n    " + app_methods + app_end))
with tempfile.TemporaryDirectory(prefix="parc-replay-check-") as directory:
    source = Path(directory) / "main.swift"
    binary = Path(directory) / "replay-check"
    source.write_text(generated)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

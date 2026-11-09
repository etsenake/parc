#!/usr/bin/env python3
"""Execute production replay coordination with inert window/native collaborators.

No AppKit application or browser is started. Extract the actual methods so a
regression in their ordering, reservation or recovery cannot pass a copied model.
"""
from pathlib import Path
import subprocess
import tempfile

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
browser = (ROOT / "Sources/ParcApp/BrowserWindowController.swift").read_text()
template = (Path(__file__).parent / "Harness.swift").read_text()
browser_methods = "\n".join(method(browser, signature) for signature in (
    "func prepareAuxiliaryWindowForOnboarding(", "func closeForOnboarding(",
    "func windowShouldClose(", "private func finishScriptingWindowClose("))
app_methods = "\n".join(method(app, signature) for signature in (
    "private func startOnboardingReplay(", "private func restoreReplayWindow(",
    "private func finishOnboardingReplay("))
# Exercise both real termination entry gates; the unrelated normal shutdown
# backend is replaced by a counter after its initial started guard.
for signature in ("func requestApplicationTermination(", "private func continueApplicationTermination("):
    gate = method(app, signature).split("        guard started else", 1)[0]
    app_methods += "\n" + gate + "        globalQuitRequests += 1\n    }"
generated = template.replace("// BROWSER_METHODS", browser_methods).replace("// APP_METHODS", app_methods)
with tempfile.TemporaryDirectory(prefix="parc-replay-check-") as directory:
    source = Path(directory) / "main.swift"
    binary = Path(directory) / "replay-check"
    source.write_text(generated)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

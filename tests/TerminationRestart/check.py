#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
APP_END = "\n}\nfunc drain()"


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
template = (Path(__file__).parent / "Harness.swift").read_text()
assert template.count(APP_END) == 1, "Harness.swift AppDelegate ending moved"
methods = "\n".join(method(app, signature) for signature in (
    "func requestApplicationTermination(", "private func continueApplicationTermination(",
    "private func abandonApplicationTermination("))
generated = template.replace(APP_END, "\n    " + methods + APP_END)
with tempfile.TemporaryDirectory(prefix="parc-termination-restart-") as directory:
    source = Path(directory) / "main.swift"
    binary = Path(directory) / "termination-restart"
    source.write_text(generated)
    subprocess.run(["xcrun", "swiftc", str(ROOT / "tests/Support/TestFailure.swift"), "-swift-version", "5",
                    "-warnings-as-errors", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

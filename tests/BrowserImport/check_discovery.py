#!/usr/bin/env python3
"""Syntax-check import discovery and its made-up fixture with the shipping flags.

Compiles the repository's discovery source and tests/BrowserImport/ImportDiscovery.mm
with the existing Parc browser target flags of a built Chromium output. Does not run
GN/Ninja, apply the overlay, link, execute, read real profiles or touch Keychain.
Logs and command records go to the repository's ignored build/ directory.
"""
import argparse
import json
from pathlib import Path
import runpy
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    if args.output_name is None:
        args.output_name = runpy.run_path(
            str(repo / "scripts/engine-source.py"))["SHIPPING_CONFIGURATION"]
    if Path(args.output_name).name != args.output_name or args.output_name in (".", ".."):
        parser.error("--output-name must name one existing output directory")
    build = (tree / "out" / args.output_name).resolve(strict=True)
    flags_from = runpy.run_path(
        str(repo / "tests/NativeLocationBar/check-chromium.py"))["flags_from"]
    logs = repo / "build/tests/browser-import-discovery"
    include = logs / "include/parc/importer"
    include.mkdir(parents=True, exist_ok=True)
    for name in ("import_reader.h", "import_snapshot.h"):
        shutil.copy2(repo / "Engine/ParcImport" / name, include / name)
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    flags = ["-I" + str(logs / "include")] + [
        f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
        else flag
        for flag in flags_from(build / "obj/parc/browser.ninja", "cflags_objcc", False)]
    results = []
    for name, source in (
        ("discovery", repo / "Engine/ParcNative/native_import_discovery.mm"),
        ("discovery-fixture", repo / "tests/BrowserImport/ImportDiscovery.mm"),
    ):
        command = [str(compiler), *flags, "-fsyntax-only", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "command": command, "cwd": str(build),
                        "exit_code": result.returncode})
        print(f"{name}: {'PASS' if not result.returncode else 'FAIL'}", flush=True)
        if result.returncode:
            print(result.stdout, flush=True)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compile the real window lookup and regression cases with generated flags.

Requires the reviewed Parc overlay and existing pinned Chromium outputs. Does
not run GN/Ninja, modify Chromium, link tests or execute them. Missing generated
headers are failures, never replaced with test stubs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    parser.add_argument("--tests-only", action="store_true",
                        help="Only compile the test source; do not check the implementation")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    lock_path = repo / "Engine/source-lock.json"
    lock = json.loads(lock_path.read_text())
    if lock.get("schema_version") != 2:
        parser.error("unsupported source lock schema")
    if args.output_name is None:
        args.output_name = lock["build"]["configuration"]
    manifest_path = repo / ('Engine/ParcHost/overlay.json')
    build = tree / "out" / args.output_name
    flags_from = runpy.run_path(str(repo / "tests/NativeLocationBar/check-chromium.py"))["flags_from"]
    logs = repo / "build/tests/native-window-lookup/chromium-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    results = []
    units = [("unit-tests", Path(__file__).with_name("native_window_lookup_unittest.cc"),
              "obj/chrome/test/unit_tests.ninja")]
    if not args.tests_only:
        manifest = json.loads(manifest_path.read_text())
        implementations = []
        for name, target, flags_file in (
            ("window-lookup", "chrome/browser/ui/views/frame/browser_view.cc",
             "obj/chrome/browser/ui/ui.ninja"),
            ("address-continuation", "chrome/browser/ui/autofill/address_bubbles_controller.cc",
             "obj/chrome/browser/ui/autofill/impl.ninja"),
        ):
            entries = [entry for patch in manifest["patches"] for entry in patch["files"]
                       if entry["target"] == target]
            if len(entries) != 1:
                parser.error(f"The overlay must identify {target} exactly once")
            if hashlib.sha256((tree / target).read_bytes()).hexdigest() != entries[0]["after_sha256"]:
                parser.error(f"{target} does not match the reviewed overlay; apply it first")
            implementations.append((name, tree / target, flags_file))
        units = implementations + units
    for name, source, flags_file in units:
        flags = flags_from(build / flags_file)
        flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
                 else flag for flag in flags]
        command = [str(compiler), *flags, "-fsyntax-only", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "flags_file": str(build / flags_file),
                        "command": command, "cwd": str(build),
                        "exit_code": result.returncode})
        print(f"{name}: {'PASS' if not result.returncode else 'FAIL'}", flush=True)
        if result.returncode:
            print(result.stdout, flush=True)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

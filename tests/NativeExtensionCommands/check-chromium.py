#!/usr/bin/env python3
"""Syntax only against existing pinned Chromium build outputs; no GN/Ninja."""
import argparse
import json
from pathlib import Path
import runpy
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    lock_path = repo / "Engine/source-lock.json"
    lock = json.loads(lock_path.read_text())
    if lock.get("schema_version") != 2:
        parser.error("unsupported source lock schema")
    output_name = (lock["build"]["configuration"] if args.output_name is None
                   else args.output_name)
    if Path(output_name).name != output_name or output_name in ("", ".", ".."):
        parser.error("output name must name one existing directory")
    build = tree / "out" / output_name
    # Reuse the existing strict Ninja-variable reader; it never runs a builder.
    flags_from = runpy.run_path(str(repo / "tests/NativeLocationBar/check-chromium.py"))["flags_from"]
    logs = repo / "build/tests/native-extension-commands/chromium-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    results = []
    for name, source, flags_file in (
        ("implementation", repo / "Engine/ParcNative/extension_keybinding_registry.cc",
         'obj/parc/browser.ninja'),
        ("browser-tests", Path(__file__).with_name("extension_keybinding_registry_browsertest.cc"),
         "obj/chrome/test/browser_tests.ninja"),
    ):
        flags = flags_from(build / flags_file)
        flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
                 else flag for flag in flags]
        command = [str(compiler), *flags, "-fsyntax-only",
                   f"-I{repo / 'Engine/ParcNative'}", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "flags_file": str(build / flags_file),
                        "command": command, "cwd": str(build),
                        "exit_code": result.returncode})
        print(f"{name}: {'PASS' if not result.returncode else 'FAIL'}")
        if result.returncode:
            print(result.stdout)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Syntax-check the real modal implementation against existing Chromium output.

Reads generated compile flags only; never invokes GN/Ninja or writes checkout
files. This is not a linked test run or a substitute for native integration.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    source_tree = args.source_tree.resolve(strict=True)
    lock = json.loads((repo / "Engine/source-lock.json").read_text())
    if lock.get("schema_version") != 2:
        parser.error("unsupported source lock schema")
    output_name = lock["build"]["configuration"] if args.output_name is None else args.output_name
    if Path(output_name).name != output_name or output_name in ("", ".", ".."):
        parser.error("output name must name one existing directory")
    build = source_tree / "out" / output_name
    compiler = source_tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    results_dir = repo / "build/tests/native-window/chromium-syntax"
    results_dir.mkdir(parents=True, exist_ok=True)
    inputs = [
        ("implementation", "obj/ui/gfx/gfx.ninja",
         repo / "Engine/ParcNative/browser_window.mm"),
        ("modal-tests", "obj/components/web_modal/unit_tests.ninja",
         repo / "tests/EngineConformance/native-window/ModalHostTests.mm"),
    ]
    results = []
    for name, flags_file, source in inputs:
        variables = {}
        for line in (build / flags_file).read_text().splitlines():
            if " =" in line and not line.startswith(" "):
                key, value = line.split(" =", 1)
                variables[key] = value.lstrip()
        flags = []
        for key in ("defines", "include_dirs", "framework_dirs", "cflags", "cflags_objcc"):
            if key not in variables:
                raise RuntimeError(f"Missing {key} in {flags_file}")
            flags.extend(shlex.split(variables[key]))
        if any("$" in flag for flag in flags):
            raise RuntimeError("Unexpanded generated variable; require explicit flags")
        # A compiler crash must not create diagnostics in the external checkout.
        flags = [f"-fcrash-diagnostics-dir={results_dir}"
                 if flag.startswith("-fcrash-diagnostics-dir=") else flag
                 for flag in flags]
        command = [str(compiler), *flags, "-fsyntax-only",
                   f"-I{repo / 'Engine/ParcNative'}", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (results_dir / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "flags_file": str(build / flags_file),
                        "command": command, "cwd": str(build),
                        "exit_code": result.returncode})
        print(f"{name}: {'PASS' if result.returncode == 0 else 'FAIL'}")
        if result.returncode:
            print(result.stdout)
    (results_dir / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(item["exit_code"] for item in results))


if __name__ == "__main__":
    raise SystemExit(main())

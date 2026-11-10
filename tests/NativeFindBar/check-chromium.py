#!/usr/bin/env python3
"""Read-only pinned Chromium syntax checks, without GN, Ninja or fake headers."""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    parser.add_argument("--lock-file", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    lock_path = args.lock_file or repo / "Engine/source-lock.json"
    lock = json.loads(lock_path.read_text())
    if lock.get("schema_version") not in (1, 2):
        parser.error("unsupported source lock schema")
    direct = lock["schema_version"] == 2
    output_name = (lock["build"]["configuration"] if args.output_name is None
                   else args.output_name)
    if Path(output_name).name != output_name or output_name in ("", ".", ".."):
        parser.error("output name must name one existing directory")
    build = tree / "out" / output_name
    flags_file = build / ("obj/parc/browser.ninja" if direct else "obj/cef/libcef_static.ninja")
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    logs = repo / "build/tests/native-find-bar/chromium-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    variables = {}
    for line in flags_file.read_text().splitlines():
        if not line:
            break
        key, value = line.split(" =", 1)
        value = re.sub(r"\$([$: ])", r"\1", value.lstrip())
        if re.search(r"\$[A-Za-z_{]", value):
            raise RuntimeError(f"Unexpanded generated variable: {key}")
        variables[key] = value
    flags = []
    for key in ("defines", "include_dirs", "framework_dirs", "cflags", "cflags_objcc"):
        flags.extend(shlex.split(variables[key]))
    flags = [f"-fcrash-diagnostics-dir={logs}" if x.startswith("-fcrash-diagnostics-dir=") else x for x in flags]
    results = []
    for name in ("find_bar_view", "find_bar"):
        actual_flags_file = (build / "obj/parc/native/native_components.ninja"
                             if direct and name == "find_bar_view" else flags_file)
        if actual_flags_file != flags_file:
            variables = {}
            for line in actual_flags_file.read_text().splitlines():
                if not line:
                    break
                key, value = line.split(" =", 1)
                value = re.sub(r"\$([$: ])", r"", value.lstrip())
                if re.search(r"\$[A-Za-z_{]", value):
                    raise RuntimeError(f"Unexpanded generated variable: {key}")
                variables[key] = value
            flags = []
            for key in ("defines", "include_dirs", "framework_dirs", "cflags", "cflags_objcc"):
                flags.extend(shlex.split(variables[key]))
            flags = [f"-fcrash-diagnostics-dir={logs}" if x.startswith("-fcrash-diagnostics-dir=") else x for x in flags]
        command = [str(compiler), *flags, "-fsyntax-only",
                   f"-I{repo / 'Engine/ParcNative'}", str(repo / f"Engine/ParcNative/{name}.mm")]
        result = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "flags_file": str(actual_flags_file), "command": command,
                        "cwd": str(build), "exit_code": result.returncode})
        print(f"{name}: {'PASS' if not result.returncode else 'FAIL'}")
        if result.returncode:
            print(result.stdout)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(x["exit_code"] for x in results))


if __name__ == "__main__":
    raise SystemExit(main())

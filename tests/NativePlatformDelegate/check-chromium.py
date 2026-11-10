#!/usr/bin/env python3
"""Check the native page binding (legacy platform delegate) with real generated Chromium ObjC++ flags.

No GN/Ninja invocation or writes to the external checkout. This compiles syntax
only; linking, a real shell host, factory wiring and runtime checks remain
separate requirements.
"""
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
    logs = repo / "build/tests/native-platform-delegate/chromium-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    variables = {}
    for line in flags_file.read_text().splitlines():
        if not line:
            break
        key, value = line.split(" =", 1)
        value = re.sub(r"\$([$: ])", r"\1", value.lstrip())
        if re.search(r"\$[A-Za-z_{]", value):
            raise RuntimeError(f"Unexpanded Ninja variable: {key}")
        variables[key] = value
    flags = []
    # ObjC++ uses its own language flags. The C++ module flags describe a
    # different compiler mode and must not be copied into this command.
    for key in ("defines", "include_dirs", "framework_dirs", "cflags",
                "cflags_objcc"):
        flags.extend(shlex.split(variables[key]))
    flags = [f"-fcrash-diagnostics-dir={logs}"
             if flag.startswith("-fcrash-diagnostics-dir=") else flag
             for flag in flags]
    command = [str(tree / "third_party/llvm-build/Release+Asserts/bin/clang++"),
               *flags, "-fsyntax-only", f"-I{repo / 'Engine/ParcNative'}",
               str(repo / ("Engine/ParcNative/native_page_binding.mm" if direct
                           else "Engine/ParcNative/native_chrome_platform_delegate.mm"))]
    result = subprocess.run(command, cwd=build, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (logs / "implementation.log").write_text(result.stdout)
    (logs / "results.json").write_text(json.dumps({
        "command": command, "cwd": str(build), "flags_file": str(flags_file),
        "exit_code": result.returncode,
    }, indent=2) + "\n")
    print(f"native-platform-delegate: {'PASS' if result.returncode == 0 else 'FAIL'}")
    if result.returncode:
        print(result.stdout)
    return int(result.returncode != 0)


if __name__ == "__main__":
    raise SystemExit(main())

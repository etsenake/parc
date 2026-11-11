#!/usr/bin/env python3
"""Check both dialog implementations with their real generated ObjC++ flags.

No GN/Ninja, generation, downloads, linking or application execution. The source
checkout is read-only; command records, diagnostics and caches stay in build/tests.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default="Release_GN_arm64")
    args = parser.parse_args()
    if Path(args.output_name).name != args.output_name or args.output_name in (".", "..", ""):
        parser.error("--output-name must be one existing output directory name")

    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    build = tree / "out" / args.output_name
    targets = {"presenter": "native_components", "manager": "native_javascript_dialogs"}
    flags_files = {name: build / f"obj/parc/native/{target}.ninja"
                   for name, target in targets.items()}
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    if not compiler.is_file() or not all(path.is_file() for path in flags_files.values()):
        parser.error("existing pinned compiler and generated parc/native target ninja files are required")

    sys.dont_write_bytecode = True
    helper_path = repo / "tests/NativeLocationBar/check-chromium.py"
    spec = importlib.util.spec_from_file_location("parc_chromium_flags", helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    toolchain_file = build / "toolchain.ninja"
    rule = re.search(r"^rule objcxx\n  command = (.+)$", toolchain_file.read_text(), re.MULTILINE)
    if not rule or "${cflags_objcc}" not in rule[1]:
        raise RuntimeError("Missing actual ObjC++ compiler rule")

    logs = repo / "build/tests/native-javascript-dialogs/chromium-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for name, flags_file in flags_files.items():
        flags = helper.flags_from(flags_file, language_flags="cflags_objcc",
                                  include_module_deps="${module_deps}" in rule[1])
        if "-fobjc-arc" not in flags or "-Werror" not in flags:
            raise RuntimeError("Expected real ObjC++ ARC and warnings-as-errors settings")
        flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
                 else f"-fmodules-cache-path={logs / 'module-cache'}"
                 if flag.startswith("-fmodules-cache-path=") else flag for flag in flags]
        source = repo / f"Engine/ParcNative/javascript_dialog_{name}.mm"
        command = [str(compiler), *flags, "-fsyntax-only",
                   f"-I{repo / 'Engine/ParcNative'}", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "flags_file": str(flags_file),
                        "flags_sha256": hashlib.sha256(flags_file.read_bytes()).hexdigest(),
                        "toolchain_file": str(toolchain_file), "objcxx_rule": rule[1],
                        "toolchain_sha256": hashlib.sha256(toolchain_file.read_bytes()).hexdigest(),
                        "language_flags": "cflags_objcc", "command": command,
                        "cwd": str(build), "source": str(source),
                        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "exit_code": result.returncode})
        print(f"{name}: {'PASS' if not result.returncode else 'FAIL'}")
        if result.returncode:
            print(result.stdout)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

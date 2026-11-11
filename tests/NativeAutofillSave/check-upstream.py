#!/usr/bin/env python3
"""Compile changed Autofill sources with their actual generated Chromium flags.

Requires the applied reviewed overlay and its generated targets. No generation,
checkout edits, linking or test execution. Missing headers remain failures.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default=None)
    args = parser.parse_args()
    if args.output_name is not None and (Path(args.output_name).name != args.output_name or
            args.output_name in (".", "..", "")):
        parser.error("--output-name must name one existing output directory")

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
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    if not compiler.is_file():
        parser.error("the existing pinned compiler is required")
    compiler_sha256 = digest(compiler.read_bytes())
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    sources = {}
    for patch in manifest["patches"]:
        for item in patch["files"]:
            target = item["target"]
            if (target.endswith(".cc") and target.startswith((
                    "chrome/browser/ui/autofill/",
                    "components/autofill/core/browser/"))):
                if target in sources:
                    parser.error(f"duplicate source target: {target}")
                source = tree / target
                if digest(source.read_bytes()) != item["after_sha256"]:
                    parser.error(f"apply the reviewed overlay first: {target}")
                sources[target] = item
    if not sources:
        parser.error("the manifest contains no Autofill translation units")

    owners = {target: [] for target in sources}
    flag_files = [path for folder in ("obj/chrome/browser/ui/autofill",
                                     "obj/components/autofill/core/browser")
                  for path in sorted((build / folder).rglob("*.ninja"))]
    chrome_tests = build / "obj/chrome/test/unit_tests.ninja"
    if chrome_tests.is_file():
        flag_files.append(chrome_tests)
    for flags_file in flag_files:
        text = flags_file.read_text()
        for match in re.finditer(r"^build [^\n]+: cxx ../../([^\s]+)",
                                 text, re.MULTILINE):
            target = match[1]
            if target in owners and flags_file not in owners[target]:
                owners[target].append(flags_file)
    unresolved = {target: [str(path) for path in choices]
                  for target, choices in owners.items() if len(choices) != 1}
    if unresolved:
        parser.error("expected one generated object owner per source:\n" +
                     json.dumps(unresolved, indent=2))

    sys.dont_write_bytecode = True
    flags_from = runpy.run_path(str(
        repo / "tests/NativeLocationBar/check-chromium.py"))["flags_from"]
    toolchain = build / "toolchain.ninja"
    rule = re.search(r"^rule cxx\n  command = (.+)$",
                     toolchain.read_text(), re.MULTILINE)
    if not rule:
        parser.error("missing generated CXX compiler rule")
    expected_rule = (
        '../../third_party/llvm-build/Release+Asserts/bin/clang++ '
        '-MMD -MF ${target_out_dir}/${label_name}/${source_name_part}.o.d '
        '${defines} ${include_dirs} ${cflags} ${cflags_cc} ${module_deps} '
        '-fmodule-name="${cc_module_name}_Private" -c ${in} '
        '-o ${target_out_dir}/${label_name}/${source_name_part}.o')
    if rule[1] != expected_rule:
        parser.error("the generated CXX rule changed; review it before checking")
    logs = repo / "build/tests/native-autofill-save/upstream-syntax"
    logs.mkdir(parents=True, exist_ok=True)
    print("Actual generated CXX targets; syntax only, no linking or execution",
          flush=True)
    results = []
    for target, item in sources.items():
        flags_file = owners[target][0]
        flags = flags_from(flags_file, language_flags="cflags_cc",
                           include_module_deps="${module_deps}" in rule[1])
        variables = {}
        for line in flags_file.read_text().splitlines():
            if not line:
                break
            key, value = line.split(" =", 1)
            value = re.sub(r"\$([$: ])", r"\1", value.lstrip())
            if re.search(r"\$[A-Za-z_{]", value):
                raise RuntimeError(f"unexpanded variable: {flags_file}: {key}")
            variables[key] = value
        if variables.get("framework_dirs"):
            raise RuntimeError("the CXX rule does not consume framework_dirs")
        module_name = variables.get("cc_module_name")
        if not module_name:
            raise RuntimeError(f"missing actual cc_module_name: {flags_file}")
        flags.append(f"-fmodule-name={module_name}_Private")
        if "-Werror" not in flags:
            raise RuntimeError("expected Chromium warnings-as-errors settings")
        flags = [f"-fcrash-diagnostics-dir={logs}"
                 if flag.startswith("-fcrash-diagnostics-dir=") else
                 f"-fmodules-cache-path={logs / 'module-cache'}"
                 if flag.startswith("-fmodules-cache-path=") else flag
                 for flag in flags]
        command = [str(compiler), *flags, "-fsyntax-only", str(tree / target)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        name = target.replace("/", "_")
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({
            "source": target, "source_sha256": item["after_sha256"],
            "overlay_sha256": digest(manifest_bytes),
            "flags_file": str(flags_file),
            "flags_sha256": digest(flags_file.read_bytes()),
            "toolchain_file": str(toolchain), "cxx_rule": rule[1],
            "toolchain_sha256": digest(toolchain.read_bytes()),
            "compiler_sha256": compiler_sha256,
            "command": command, "cwd": str(build),
            "exit_code": result.returncode,
        })
        print(f"{target}: {'PASS' if result.returncode == 0 else 'FAIL'}",
              flush=True)
        if result.returncode:
            print(result.stdout, flush=True)
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

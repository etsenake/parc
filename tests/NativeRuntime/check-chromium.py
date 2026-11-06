#!/usr/bin/env python3
"""Check the integrated driver with its actual generated source-set flags.

No generator, build, linking, app execution, compatibility fallback or checkout
writes. Requires the full reviewed overlay already applied. The separately
packaged AppKit executable is compiled by package.py using the public ABI only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_tree", type=Path)
    parser.add_argument("--output-name", default="Release_GN_arm64")
    args = parser.parse_args()
    if Path(args.output_name).name != args.output_name or args.output_name in (".", "..", ""):
        parser.error("output-name must be one existing output directory")
    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    build = (tree / "out" / args.output_name).resolve(strict=True)
    if not build.is_relative_to(tree / "out"):
        parser.error("build output left the source tree")
    sys.dont_write_bytecode = True
    shared = runpy.run_path(str(repo / "tests/NativeHTTPAuth/check-chromium.py"))
    contained = shared["contained"]
    manifest_path = repo / "Engine/ParcHost/overlay.json"
    manifest = json.loads(manifest_path.read_text())
    snapshots = {}
    outputs = {}
    sources = {}
    def check(path, expected):
        if sha(path) != expected:
            raise ValueError(f"reviewed source/hash mismatch: {path}")
        snapshots[path] = expected
    if manifest.get("source_root") != "repository":
        raise ValueError("expected repository-relative reviewed manifest")
    lock_path = repo / "Engine/source-lock.json"
    lock = json.loads(lock_path.read_text())
    if manifest["upstream"] != {name: lock[name]["commit"] for name in ("cef", "chromium")}:
        raise ValueError("overlay revisions differ from the source lock")
    for item in manifest["files"]:
        if item["target"] in outputs or item["source"] in sources:
            raise ValueError("duplicate manifest mapping")
        check(contained(repo, item["source"]), item["sha256"])
        check(contained(tree, item["target"]), item["sha256"])
        outputs[item["target"]] = item["sha256"]
        sources[item["source"]] = item["target"]
    for patch in manifest["patches"]:
        check(contained(repo, patch["source"]), patch["sha256"])
        for item in patch["files"]:
            if item["target"] in outputs:
                raise ValueError("duplicate patched output")
            check(contained(tree, item["target"]), item["after_sha256"])
            outputs[item["target"]] = item["after_sha256"]
    target = sources["tests/NativeRuntime/runtime_driver.mm"]
    flags_file = build / "obj/cef/tests/parc_native_runtime/driver.ninja"
    if not shared["contains_object"](flags_file, "objcxx", target):
        raise ValueError("actual source-set object is not generated")
    toolchain = build / "toolchain.ninja"
    import re
    rule = re.search(r"^rule objcxx\n  command = (.+)$", toolchain.read_text(), re.MULTILINE)
    if not rule or rule[1] != shared["RULES"]["objcxx"]:
        raise ValueError("generated ObjC++ command changed")
    flags_from = runpy.run_path(str(repo / "tests/NativeLocationBar/check-chromium.py"))["flags_from"]
    flags = flags_from(flags_file, "cflags_objcc", False)
    if "-Werror" not in flags or "-fobjc-arc" not in flags:
        raise ValueError("actual target lost ARC or warnings-as-errors")
    logs = repo / "build/tests/native-runtime/chromium-syntax"
    flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
             else f"-fmodules-cache-path={logs / 'modules'}" if flag.startswith("-fmodules-cache-path=")
             else flag for flag in flags]
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    for path in (manifest_path, lock_path, flags_file, toolchain, compiler, build / "args.gn"):
        snapshots[path] = sha(path)
    command = [str(compiler), *flags, "-fsyntax-only", str(tree / target)]
    logs.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (logs / "driver.log").write_text(result.stdout)
    for path, expected in snapshots.items():
        if sha(path) != expected:
            raise ValueError(f"input changed during check: {path}")
    record = {"mode": "integrated-actual-target", "target": target, "command": command,
              "cwd": str(build), "source_sha256": outputs[target], "exit_code": result.returncode,
              "input_sha256": {str(path): value for path, value in snapshots.items()}}
    (logs / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    print("PASS" if result.returncode == 0 else result.stdout)
    return int(result.returncode != 0)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, ValueError, RuntimeError) as error:
        raise SystemExit(f"Checker refused: {error}") from error

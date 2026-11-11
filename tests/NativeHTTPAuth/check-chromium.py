#!/usr/bin/env python3
"""Syntax-check the integrated native HTTP/proxy authentication route with actual target flags.

Uses the canonical engine lock and overlay.
Requires the reviewed overlay's complete applied file/hash cohort and generated
object membership. No compatibility mode, generation, linking, test execution or
checkout writes. Logs and compiler caches stay in the repository's ignored build.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys


NATIVE = (
    ("Engine/ParcNative/http_auth_presenter.mm",
     "obj/parc/native/native_components.ninja"),
    ("Engine/ParcNative/http_auth.mm",
     "obj/parc/native/native_http_auth.ninja"),
    ("Engine/ParcNative/native_page_binding.mm",
     "obj/parc/browser.ninja"),
    ("tests/NativeHTTPAuth/login_unittest.mm",
     "obj/parc/tests/parc_native_http_auth/unit_tests.ninja"),
)
UPSTREAM = (
    ("chrome/browser/ui/login/login_handler.cc",
     "obj/chrome/browser/ui/login/impl.ninja"),
)
RULE_PREFIX = (
    "../../third_party/llvm-build/Release+Asserts/bin/clang++ "
    "-MMD -MF ${target_out_dir}/${label_name}/${source_name_part}.o.d "
)
RULE_SUFFIX = "-c ${in} -o ${target_out_dir}/${label_name}/${source_name_part}.o"
RULES = {
    "objcxx": RULE_PREFIX + "${defines} ${include_dirs} ${framework_dirs} "
              "${cflags} ${cflags_objcc} " + RULE_SUFFIX,
    "cxx": RULE_PREFIX + "${defines} ${include_dirs} ${cflags} ${cflags_cc} "
           '${module_deps} -fmodule-name="${cc_module_name}_Private" ' + RULE_SUFFIX,
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contained(root, value):
    relative = Path(value)
    if relative.is_absolute() or not value or ".." in relative.parts:
        raise ValueError(f"invalid manifest path: {value}")
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root):
        raise ValueError(f"manifest path leaves its root: {value}")
    return path


def variables_from(path):
    variables = {}
    for line in path.read_text().splitlines():
        if not line:
            break
        key, value = line.split(" =", 1)
        value = re.sub(r"\$([$: ])", r"\1", value.lstrip())
        if re.search(r"\$[A-Za-z_{]", value):
            raise ValueError(f"unexpanded variable in {path}: {key}")
        variables[key] = value
    return variables


def contains_object(flags_file, rule, target):
    pattern = r"^build [^\n]+: " + rule + r" ../../" + re.escape(target) + r"(?=\s|$)"
    return len(re.findall(pattern, flags_file.read_text(), re.MULTILINE)) == 1


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
    build = (tree / "out" / args.output_name).resolve(strict=True)
    if not build.is_relative_to(tree / "out"):
        parser.error("the build output must remain inside source_tree/out")
    manifest_path = repo / ('Engine/ParcHost/overlay.json')
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("source_root") != "repository":
        parser.error("expected the reviewed repository-relative overlay")
    upstream = ['chromium']
    if manifest["upstream"] != {key: lock[key]["commit"] for key in upstream}:
        parser.error("overlay upstream identities do not match the source lock")

    snapshots = {}

    def require_hash(path, expected):
        actual = digest(path)
        if actual != expected:
            raise ValueError(f"reviewed overlay/hash mismatch: {path}")
        snapshots[path] = actual

    # Validate all mapped sources, headers, BUILD files and patch outputs before
    # any compiler starts. Native source is then compiled at its actual checkout
    # path; no repository include override can mask an unapplied dependency.
    sources = {}
    outputs = {}
    for item in manifest["files"]:
        source = item["source"]
        target = item["target"]
        if source in sources or target in outputs:
            raise ValueError(f"duplicate overlay mapping: {source}: {target}")
        require_hash(contained(repo, source), item["sha256"])
        require_hash(contained(tree, target), item["sha256"])
        sources[source] = target
        outputs[target] = item["sha256"]
    patch_outputs = {}
    output_names = {target.casefold(): target for target in outputs}
    for patch in manifest["patches"]:
        require_hash(contained(repo, patch["source"]), patch["sha256"])
        patch_targets = set()
        for item in patch["files"]:
            target = item["target"]
            folded = target.casefold()
            if folded in patch_targets:
                raise ValueError(f"duplicate patch target: {target}")
            patch_targets.add(folded)
            if folded in patch_outputs:
                if (output_names[folded] != target or
                        patch_outputs[folded] != item["before_sha256"]):
                    raise ValueError(f"broken overlay patch chain: {target}")
            elif folded in output_names:
                raise ValueError(f"duplicate overlay output: {target}")
            else:
                output_names[folded] = target
            patch_outputs[folded] = item["after_sha256"]
            outputs[target] = item["after_sha256"]
    for target, expected in outputs.items():
        require_hash(contained(tree, target), expected)
    for path in (manifest_path, lock_path, build / "args.gn"):
        snapshots[path] = digest(path)

    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    compiler_hash = digest(compiler)
    snapshots[compiler] = compiler_hash
    toolchain = build / "toolchain.ninja"
    snapshots[toolchain] = digest(toolchain)
    toolchain_text = toolchain.read_text()
    for language, expected in RULES.items():
        match = re.search(r"^rule " + language + r"\n  command = (.+)$",
                          toolchain_text, re.MULTILINE)
        if not match or match[1] != expected:
            raise ValueError(f"generated {language} rule changed; review it first")

    targets = []
    for source, owner in NATIVE:
        source = source
        if source not in sources:
            raise ValueError(f"reviewed overlay does not map {source}")
        flags_file = build / owner
        language = "cxx" if source.endswith(".cc") else "objcxx"
        if not flags_file.is_file() or not contains_object(flags_file, language, sources[source]):
            raise ValueError(f"missing actual object membership: {source}: {flags_file}")
        targets.append((sources[source], flags_file, language))

    # These original CXX sources keep their own generated owners. A test
    # source_set must use its own flags, never chrome/test's top-level flags.
    for target, owner in UPSTREAM:
        flags_file = build / owner
        if (target not in outputs or not flags_file.is_file() or
                not contains_object(flags_file, "cxx", target)):
            raise ValueError(f"expected reviewed output and actual CXX owner: {target}")
        targets.append((target, flags_file, "cxx"))

    sys.dont_write_bytecode = True
    helper_path = repo / "tests/NativeLocationBar/check-chromium.py"
    snapshots[helper_path] = digest(helper_path)
    flags_from = runpy.run_path(str(helper_path))["flags_from"]
    logs = repo / "build/tests/native-http-auth/chromium-syntax"
    commands = []
    for target, flags_file, language in targets:
        snapshots[flags_file] = digest(flags_file)
        variables = variables_from(flags_file)
        cxx = language == "cxx"
        flags = flags_from(flags_file, language_flags="cflags_cc" if cxx else "cflags_objcc",
                           include_module_deps=cxx)
        if cxx:
            if variables.get("framework_dirs") or not variables.get("cc_module_name"):
                raise ValueError(f"unsupported CXX variables: {flags_file}")
            flags.append(f'-fmodule-name={variables["cc_module_name"]}_Private')
        elif "-fobjc-arc" not in flags:
            raise ValueError(f"missing actual ARC setting: {flags_file}")
        if "-Werror" not in flags:
            raise ValueError(f"missing actual warnings-as-errors: {flags_file}")
        flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
                 else f"-fmodules-cache-path={logs / 'module-cache'}"
                 if flag.startswith("-fmodules-cache-path=") else flag for flag in flags]
        commands.append((target, flags_file, language,
                         [str(compiler), *flags, "-fsyntax-only", str(tree / target)]))

    def unchanged():
        for path, expected in snapshots.items():
            if digest(path) != expected:
                raise ValueError(f"input changed during checker run: {path}")

    unchanged()
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    print("Actual integrated targets; syntax only, no linking or test execution", flush=True)
    for target, flags_file, language, command in commands:
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / (target.replace("/", "_") + ".log")).write_text(result.stdout)
        results.append({"source": target, "source_sha256": outputs[target],
                        "mode": "integrated-actual-target", "direct": True, "rule": language,
                        "overlay_sha256": snapshots[manifest_path],
                        "source_lock_sha256": snapshots[lock_path],
                        "args_gn_sha256": snapshots[build / "args.gn"],
                        "compiler": str(compiler), "compiler_sha256": compiler_hash,
                        "flags_file": str(flags_file), "flags_sha256": snapshots[flags_file],
                        "toolchain_file": str(toolchain), "compiler_rule": RULES[language],
                        "toolchain_sha256": snapshots[toolchain],
                        "command": command, "cwd": str(build), "exit_code": result.returncode})
        print(f"{target}: {'PASS' if result.returncode == 0 else 'FAIL'}", flush=True)
        if result.returncode:
            print(result.stdout, flush=True)
    unchanged()
    (logs / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(result["exit_code"] for result in results))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, ValueError, RuntimeError) as error:
        raise SystemExit(f"Checker refused: {error}") from error

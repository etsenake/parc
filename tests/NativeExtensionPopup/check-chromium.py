#!/usr/bin/env python3
"""Check native extension popup sources with their generated target's ObjC++ flags.

No GN/Ninja, generation, downloads, linking or application execution. The source
checkout is read-only; command records, diagnostics and caches stay in build/tests.
The default requires the integrated production and test source_set targets.
--pre-integration explicitly checks compatibility with the older libcef_static
and browser_tests flags; that mode does not verify the new targets' configurations.
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
    parser.add_argument("--output-name", default=None)
    parser.add_argument(
        "--pre-integration", action="store_true",
        help="use existing libcef_static/browser_tests flags before the shared "
             "targets are generated; this is compatibility-only evidence")
    parser.add_argument("--lock-file", type=Path)
    args = parser.parse_args()
    if args.output_name is not None and (Path(args.output_name).name != args.output_name or args.output_name in (".", "..", "")):
        parser.error("--output-name must be one existing output directory name")

    repo = Path(__file__).resolve().parents[2]
    tree = args.source_tree.resolve(strict=True)
    lock_path = args.lock_file or repo / "Engine/source-lock.json"
    lock = json.loads(lock_path.read_text())
    if lock.get("schema_version") not in (1, 2):
        parser.error("unsupported source lock schema")
    direct = lock["schema_version"] == 2
    if args.output_name is None:
        args.output_name = lock["build"]["configuration"]
    build = tree / "out" / args.output_name
    compiler = tree / "third_party/llvm-build/Release+Asserts/bin/clang++"
    if not compiler.is_file():
        parser.error("the existing pinned compiler is required")

    production_flags = ("obj/cef/libcef_static.ninja" if args.pre_integration else
                        "obj/cef/libcef/browser/parc_native/native_extensions.ninja")
    production_target = ("//cef:libcef_static" if args.pre_integration else
                         "//cef/libcef/browser/parc_native:native_extensions")
    targets = tuple((name, f"Engine/ParcNative/{name}.mm", production_flags,
                     production_target) for name in
                    ("extension_popup_presenter", "extension_popup",
                     "extension_action_container")) + (
        ("popup-browser-tests", "tests/NativeExtensionPopup/extension_popup_browsertest.mm",
         "obj/chrome/test/browser_tests.ninja" if args.pre_integration else
         "obj/cef/tests/parc_native_extensions/popup_browser_tests.ninja",
         "//chrome/test:browser_tests" if args.pre_integration else
         "//cef/tests/parc_native_extensions:popup_browser_tests"),
    )
    if direct:
        if args.pre_integration:
            parser.error("--pre-integration requires the legacy CEF lock")
        targets = tuple((name, source,
                         flags.replace("obj/cef/libcef/browser/parc_native/", "obj/parc/native/")
                              .replace("obj/cef/tests/", "obj/parc/tests/"),
                         target.replace("//cef/libcef/browser/parc_native:", "//parc/native:")
                               .replace("//cef/tests/", "//parc/tests/"))
                        for name, source, flags, target in targets)
    missing = [str(build / target[2]) for target in targets
               if not (build / target[2]).is_file()]
    if missing:
        parser.error("missing generated target flags:\n" + "\n".join(missing) +
                     "\nNo compiler check ran. Generate the reviewed targets "
                     "through the source workflow, or explicitly use "
                     "--pre-integration for compatibility-only checks.")

    # Share the bounded Ninja literal reader. Import without writing __pycache__
    # into the repository's source directories.
    sys.dont_write_bytecode = True
    helper_path = repo / "tests/NativeLocationBar/check-chromium.py"
    spec = importlib.util.spec_from_file_location("parc_chromium_flags", helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    toolchain_file = build / "toolchain.ninja"
    rule = re.search(r"^rule objcxx\n  command = (.+)$", toolchain_file.read_text(), re.MULTILINE)
    if not rule or "${cflags_objcc}" not in rule[1]:
        raise RuntimeError("Missing actual ObjC++ compiler rule")
    # Unlike the cxx rule, pinned objcxx does not pass module_deps. Its system
    # PCM is C++-only, despite being an order dependency of the object target.
    mode = "pre-integration" if args.pre_integration else "integrated-targets"
    log_name = "chromium-syntax-pre-integration" if args.pre_integration else "chromium-syntax"
    logs = repo / "build/tests/native-extension-popup" / log_name
    logs.mkdir(parents=True, exist_ok=True)
    print(f"Mode: {mode}; syntax only, no linking or test execution")
    compiler_sha256 = hashlib.sha256(compiler.read_bytes()).hexdigest()
    results = []
    for name, source_path, target_flags, gn_target in targets:
        flags_file = build / target_flags
        flags = helper.flags_from(flags_file, language_flags="cflags_objcc",
                                  include_module_deps="${module_deps}" in rule[1])
        if "-fobjc-arc" not in flags or "-Werror" not in flags:
            raise RuntimeError("Expected real ObjC++ ARC and warnings-as-errors settings")
        flags = [f"-fcrash-diagnostics-dir={logs}" if flag.startswith("-fcrash-diagnostics-dir=")
                 else f"-fmodules-cache-path={logs / 'module-cache'}"
                 if flag.startswith("-fmodules-cache-path=") else flag for flag in flags]
        source = repo / source_path
        command = [str(compiler), *flags, "-fsyntax-only",
                   f"-I{repo / 'Engine/ParcNative'}", str(source)]
        result = subprocess.run(command, cwd=build, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (logs / f"{name}.log").write_text(result.stdout)
        results.append({"name": name, "mode": mode, "gn_target": gn_target,
                        "compiler": str(compiler), "compiler_sha256": compiler_sha256,
                        "flags_file": str(flags_file),
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

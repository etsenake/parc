#!/usr/bin/env python3
"""Check Parc's Swift package build without packaging or launching it.

Builds the Parc target through Swift Package Manager, which keeps warnings as errors, the Swift 5 language
mode and the macOS 13 deployment target, and fails on any warning the build still reports. The build
weak-links the committed engine stub, so no engine build is needed. This tool never selects a built package.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
compiler_spec = importlib.util.spec_from_file_location("parc_compiler", Path(__file__).with_name("compiler.py"))
compiler = importlib.util.module_from_spec(compiler_spec)
compiler_spec.loader.exec_module(compiler)
MODES = ("typecheck", "sil", "release")


class Refusal(Exception):
    pass


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def capture(command: list[str], repo: Path) -> str:
    return subprocess.check_output(command, cwd=repo, text=True, stderr=subprocess.PIPE).strip()


def git_state(repo: Path) -> dict:
    actual = Path(capture(["git", "rev-parse", "--show-toplevel"], repo)).resolve()
    if actual != repo:
        raise Refusal(f"--repo must name the Parc checkout root, not a subdirectory: {actual}")
    return {
        "head": capture(["git", "rev-parse", "HEAD"], repo),
        "status": capture(["git", "status", "--porcelain=v1", "--untracked-files=all"], repo),
    }


def swift_sources(repo: Path) -> list[Path]:
    sources = []
    for directory in compiler.APP_SWIFT_DIRECTORIES:
        group = sorted((repo / directory).glob("*.swift"))
        if not group:
            raise Refusal(f"Missing Swift sources: {repo / directory}")
        sources.extend(group)
    return sources


def snapshot(repo: Path, bridge_headers: Path) -> tuple[list[Path], dict[str, str]]:
    sources = swift_sources(repo)
    files = set(sources)
    for directory in (repo / "Sources/ParcEngine", repo / "Engine/ParcNative"):
        files.update(directory.rglob("*.h"))
        files.update(directory.rglob("*.modulemap"))
    files.update((repo / "Sources/ParcEngine").glob("*.m"))
    files.update(path for path in bridge_headers.rglob("*") if path.is_file())
    files.update(path for path in (repo / "Package.swift", repo / "Package.resolved") if path.is_file())
    files.update((repo / "Stubs").rglob("*.tbd"))
    files.add(repo / "Engine/source-lock.json")
    files.add(Path(__file__).resolve())
    files.add(Path(compiler.__file__).resolve())
    return sources, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(files)}


def compiler_command(repo: Path, mode: str, scratch: Path | None) -> list[str]:
    if mode == "typecheck":
        return compiler.swift_build(repo, "debug", target=compiler.APP_PRODUCT)
    if mode == "sil":
        return compiler.swift_build(repo, "debug", scratch=scratch, target=compiler.APP_PRODUCT,
                                    extra=("-Xswiftc", "-whole-module-optimization"))
    return compiler.swift_build(repo, "release", scratch=scratch, target=compiler.APP_PRODUCT)


def write_json(path: Path, value: dict) -> None:
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo", type=Path, default=REPO,
                        help="Parc checkout root (default: this script's checkout)")
    result.add_argument("--mode", choices=MODES, default="typecheck",
                        help="Incremental debug build, whole-module debug build, or the release's optimized "
                             "build without the engine (for publishing Swift changes)")
    result.add_argument("--output-dir", type=Path,
                        help="Receipt parent (default: <repo>/build/swift-checks)")
    result.add_argument("--label", help="Fresh receipt subdirectory name (default: unique timestamp and PID)")
    result.add_argument("--plan", action="store_true",
                        help="Print validated paths, compiler argv and input hashes; no compiler or file writes")
    result.add_argument("--source-archive", action="store_true",
                        help="--repo is an extracted release source archive, not a Git checkout; skip the Git "
                             "HEAD checks and rely on the input hashes")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        repo = args.repo.expanduser().resolve()
        state = None if args.source_archive else git_state(repo)
        bridge_headers = repo / "Engine/ParcNative"
        protocol_header = bridge_headers / "native_application_protocols.h"
        for required in (repo / "Package.swift", repo / "Package.resolved", repo / "Sources/ParcEngine/ParcEngine.h",
                         repo / "Engine/ParcNative/native_appkit_bridge.h",
                         protocol_header):
            if not required.is_file():
                raise Refusal(f"Required compiler input is missing: {required}")
        label = args.label or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + f"-{os.getpid()}"
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", label):
            raise Refusal("--label must begin with a letter/digit and contain only letters, digits, '.', '_' or '-'")
        parent = (args.output_dir or repo / "build/swift-checks").expanduser().resolve()
        output = parent / label
        if output.exists() or output.is_symlink():
            raise Refusal(f"Receipt directory already exists; use a fresh --label: {output}")
        sources, before = snapshot(repo, bridge_headers)
        scratch = None if args.mode == "typecheck" else output / "swiftpm"
        command = compiler_command(repo, args.mode, scratch)
        record = {
            "schema_version": 1, "mode": args.mode, "repo": str(repo), "git_before": state,
            "bridge_headers": str(bridge_headers), "command": command, "inputs": before,
            "source_count": len(sources), "output": str(output),
            "scope": "Swift package build only; no engine ABI, packaged app or runtime verification",
        }
        if args.plan:
            print(json.dumps({**record, "executed": False}, indent=2))
            return 0
        record["toolchain"] = {
            "swiftc": capture(["xcrun", "--sdk", "macosx", "--find", "swiftc"], repo),
            "swift_version": capture(["xcrun", "--sdk", "macosx", "swiftc", "--version"], repo),
            "sdk": capture(["xcrun", "--sdk", "macosx", "--show-sdk-path"], repo),
            "xcode_version": capture(["xcodebuild", "-version"], repo),
            "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR"),
            "SDKROOT": os.environ.get("SDKROOT"),
        }
        parent.mkdir(parents=True, exist_ok=True)
        output.mkdir()
        record.update(started=utc(), executed=True)
        write_json(output / "start.json", record)
        started = time.monotonic()
        print(f"{args.mode}: {record['source_count']} Swift sources; log: {output / 'compiler.log'}", flush=True)
        error = None
        compiler_exit = None
        with (output / "compiler.log").open("x") as log:
            try:
                compiler_exit = subprocess.run(command, cwd=repo, stdout=log,
                                               stderr=subprocess.STDOUT).returncode
            except OSError as exc:
                error = str(exc)
            finally:
                if scratch is not None:
                    shutil.rmtree(scratch, ignore_errors=True)
        warnings = compiler.warnings((output / "compiler.log").read_text(errors="replace"))
        unchanged = False
        head_unchanged = False
        after_state = None
        try:
            after_sources, after = snapshot(repo, bridge_headers)
            unchanged = after == before and after_sources == sources
            after_state = None if args.source_archive else git_state(repo)
            head_unchanged = args.source_archive or after_state["head"] == state["head"]
        except (Refusal, OSError, subprocess.CalledProcessError) as exc:
            error = str(exc)
        passed = compiler_exit == 0 and not warnings and unchanged and head_unchanged and error is None
        if passed:
            status = 0
        elif compiler_exit and compiler_exit > 0:
            status = compiler_exit
        else:
            status = 1 if warnings and unchanged and head_unchanged and error is None else 2
        record.update(finished=utc(), seconds=round(time.monotonic() - started, 3),
                      compiler_exit=compiler_exit, warnings=warnings, status=status, passed=passed,
                      inputs_unchanged=unchanged, head_unchanged=head_unchanged,
                      git_after=after_state, error=error)
        write_json(output / "result.json", record)
        if warnings:
            print(f"{len(warnings)} compiler warning(s); Parc treats every warning as an error:",
                  *warnings, sep="\n", file=sys.stderr)
        print(f"{'PASS' if passed else 'FAIL'}: {output / 'result.json'}", flush=True)
        if not unchanged or not head_unchanged:
            print("Compiler inputs or Git HEAD changed; this check cannot validate the finished tree", file=sys.stderr)
        return status
    except (Refusal, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"check-swift: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Check Parc's complete Swift module without linking, packaging or launching it.

Portable replacement for the retained claude-split-checks/typecheck.sh. Uses
the same warnings-as-errors, whole-module, ARM64 macOS 13 compiler contract.
Direct bridge declarations are self-contained; legacy CEF checkouts select their
headers explicitly. This tool never selects a built package.
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
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
sparkle_spec = importlib.util.spec_from_file_location("parc_sparkle", Path(__file__).with_name("sparkle.py"))
sparkle = importlib.util.module_from_spec(sparkle_spec)
sparkle_spec.loader.exec_module(sparkle)


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
    # Keep the source selection identical to scripts/build.py.
    for directory in ("Sources/ParcCore", "Sources/ParcApp"):
        group = sorted((repo / directory).glob("*.swift"))
        if not group:
            raise Refusal(f"Missing Swift sources: {repo / directory}")
        sources.extend(group)
    return sources


def snapshot(repo: Path, cef_include: Path, sparkle_release: Path) -> tuple[list[Path], dict[str, str]]:
    sources = swift_sources(repo)
    files = set(sources)
    sparkle_code = sparkle_release / "Sparkle.framework/Versions/B"
    for directory in (repo / "Sources/ParcEngine", repo / "Engine/ParcNative", sparkle_code / "Headers",
                      sparkle_code / "PrivateHeaders", sparkle_code / "Modules"):
        files.update(directory.rglob("*.h"))
        files.update(directory.rglob("*.modulemap"))
    files.update(path for path in cef_include.rglob("*") if path.is_file())
    files.add(repo / "Engine/source-lock.json")
    files.add(Path(__file__).resolve())
    return sources, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(files)}


def compiler_command(repo: Path, cef_include: Path, sparkle_release: Path, mode: str,
                     sources: list[Path]) -> list[str]:
    flags = ["-emit-sil", "-Onone", "-o", "/dev/null"] if mode == "sil" else ["-typecheck"]
    return [
        "xcrun", "--sdk", "macosx", "swiftc", "-warnings-as-errors",
        "-whole-module-optimization", *flags, "-target", "arm64-apple-macos13.0",
        "-I", str(repo / "Engine/ParcNative"), "-Xcc", "-DOS_MAC=1",
        *(["-I", str(cef_include)] if cef_include != repo / "Engine/ParcNative" else []),
        "-F", str(sparkle_release),
        "-import-objc-header", str(repo / "Sources/ParcEngine/ParcEngine.h"),
        *map(str, sources),
    ]


def write_json(path: Path, value: dict) -> None:
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo", type=Path, default=REPO,
                        help="Parc checkout root (default: this script's checkout)")
    headers = result.add_mutually_exclusive_group()
    headers.add_argument("--chromium-source", type=Path,
                         help="Selected engine workspace's chromium/src directory; also PARC_CHROMIUM_SOURCE")
    headers.add_argument("--cef-include", type=Path,
                         help="Explicit CEF include directory containing cef_application_mac.h")
    result.add_argument("--mode", choices=("typecheck", "sil"), default="typecheck",
                        help="Fast iteration check, or whole-module SIL for a finished row")
    result.add_argument("--output-dir", type=Path,
                        help="Receipt parent (default: <repo>/build/swift-checks)")
    result.add_argument("--label", help="Fresh receipt subdirectory name (default: unique timestamp and PID)")
    result.add_argument("--plan", action="store_true",
                        help="Print validated paths, compiler argv and input hashes; no compiler or file writes")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        repo = args.repo.expanduser().resolve()
        state = git_state(repo)
        chromium = args.chromium_source
        if chromium is None and args.cef_include is None:
            configured = os.environ.get("PARC_CHROMIUM_SOURCE")
            if configured:
                chromium = Path(configured)
        facade = repo / "Sources/ParcEngine/ParcEngine.h"
        if not facade.is_file():
            raise Refusal(f"Required compiler input is missing: {facade}")
        direct = bool(re.search(r'^\s*#import\s+"native_application_protocols.h"', facade.read_text(), re.M))
        if direct and (args.cef_include is not None or args.chromium_source is not None):
            raise Refusal("The direct facade uses Engine/ParcNative headers; omit legacy CEF header options")
        if direct:
            cef_include = repo / "Engine/ParcNative"
            protocol_header = cef_include / "native_application_protocols.h"
        elif args.cef_include is not None:
            cef_include = args.cef_include.expanduser().resolve()
        elif chromium is not None:
            cef_include = chromium.expanduser().resolve() / "cef/include"
        else:
            raise Refusal("Select --chromium-source, --cef-include or PARC_CHROMIUM_SOURCE; no engine is guessed")
        if not direct:
            protocol_header = cef_include / "cef_application_mac.h"
        for required in (repo / "Sources/ParcEngine/ParcEngine.h",
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
        # Fetch the build's pinned Sparkle into the same ignored cache; a plan writes nothing.
        cache = repo / "build/sparkle"
        sparkle_release = sparkle.directory(cache) if args.plan else sparkle.fetch(cache)
        sources, before = snapshot(repo, cef_include, sparkle_release)
        command = compiler_command(repo, cef_include, sparkle_release, args.mode, sources)
        record = {
            "schema_version": 1, "mode": args.mode, "repo": str(repo), "git_before": state,
            ("bridge_headers" if direct else "cef_include"): str(cef_include), "sparkle_release": str(sparkle_release),
            "sparkle_cached": sparkle_release.is_dir(), "command": command, "inputs": before,
            "source_count": len(sources), "output": str(output),
            "scope": "Swift compiler check only; no engine ABI, linked app, package or runtime verification",
        }
        if args.plan:
            print(json.dumps({**record, "executed": False}, indent=2))
            return 0
        # Query the selected toolchain without overriding xcode-select or the
        # caller's DEVELOPER_DIR/SDKROOT. Record it instead of assuming Xcode.app.
        record["toolchain"] = {
            "swiftc": capture(["xcrun", "--sdk", "macosx", "--find", "swiftc"], repo),
            "swift_version": capture(["xcrun", "--sdk", "macosx", "swiftc", "--version"], repo),
            "sdk": capture(["xcrun", "--sdk", "macosx", "--show-sdk-path"], repo),
            "xcode_version": capture(["xcodebuild", "-version"], repo),
            "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR"),
            "SDKROOT": os.environ.get("SDKROOT"),
        }
        parent.mkdir(parents=True, exist_ok=True)
        output.mkdir()  # Atomic claim; concurrent invocations cannot overwrite receipts.
        record.update(started=utc(), executed=True)
        write_json(output / "start.json", record)
        started = time.monotonic()
        print(f"{args.mode}: {record['source_count']} Swift sources; log: {output / 'compiler.log'}", flush=True)
        error = None
        compiler_exit = None
        with (output / "compiler.log").open("x") as log:
            try:
                compiler_exit = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT).returncode
            except OSError as exc:
                error = str(exc)
        unchanged = False
        head_unchanged = False
        after_state = None
        try:
            after_sources, after = snapshot(repo, cef_include, sparkle_release)
            unchanged = after == before and after_sources == sources
            after_state = git_state(repo)
            head_unchanged = after_state["head"] == state["head"]
        except (Refusal, OSError, subprocess.CalledProcessError) as exc:
            error = str(exc)
        passed = compiler_exit == 0 and unchanged and head_unchanged and error is None
        status = 0 if passed else (compiler_exit if compiler_exit and compiler_exit > 0 else 2)
        record.update(finished=utc(), seconds=round(time.monotonic() - started, 3),
                      compiler_exit=compiler_exit, status=status, passed=passed,
                      inputs_unchanged=unchanged, head_unchanged=head_unchanged,
                      git_after=after_state, error=error)
        write_json(output / "result.json", record)
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

#!/usr/bin/env python3
"""Pinned macOS ARM64 upstream bootstrap. Never installs or launches a browser.

check/plan are read-only. sync claims a NEW directory or resumes an unchanged
owned dependency-sync failure. overlay-check/apply validate reviewed source
manifests; build accepts only the recorded baseline and applied overlay.
reconfigure adopts a source lock that changes only build.gn_defines; the next
build regenerates. retarget changes pinned revisions in an idle owned workspace.
No clean, stash, binary patches, installation or
application launch.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
LOCK_FILE = REPO / "Engine/source-lock.json"
MARKER = ".parc-engine-source.json"
SHIPPING_MARKER = ".parc-shipping-build.json"
SHIPPING_CONFIGURATION = "ParcDistribution_GN_arm64"
OVERLAY_RECORD_LIMIT = 64 * 1024 * 1024
# Chromium defaults dcheck_always_on (and EXPENSIVE_DCHECKs, V8 DEBUG/debug
# code, cppgc heap verification) and the bundled field-trial testing config to
# non-official builds; both engines turn them off, as CEF's official policy does.
# Both play H.264/HEVC/AAC through macOS's decoders and encoders: FFmpeg keeps its
# Chromium branding (no H.264/AAC decoders) and OpenH264 stays out.
#
# because the profile is a separate gclient download the lock doesn't pin.
SHIPPING_DEFINES = ('is_component_build=false is_official_build=true chrome_pgo_phase=0 '
                    'dcheck_always_on=false '
                    'disable_fieldtrial_testing_config=true '
                    'proprietary_codecs=true ffmpeg_branding="Chromium" enable_ffmpeg_video_decoders=false '
                    'media_use_openh264=false enable_hangout_services_extension=true '
                    'enable_platform_dolby_vision=true enable_platform_encrypted_dolby_vision=true '
                    'enable_platform_ac3_eac3_audio=true '
                    'target_cpu="arm64" enable_dsyms=false use_remoteexec=false')
GIT = ["/usr/bin/git", "-c", "core.hooksPath=/dev/null", "-c", "init.templateDir="]
ORIGINS = {
    "cef": "https://github.com/chromiumembedded/cef.git",
    "chromium": "https://chromium.googlesource.com/chromium/src.git",
    "depot_tools": "https://chromium.googlesource.com/chromium/tools/depot_tools.git",
}


class Refusal(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def direct_mode(lock: dict) -> bool:
    return lock.get("schema_version") == 2


def repository_names(lock: dict) -> tuple[str, ...]:
    return ("depot_tools", "chromium") if direct_mode(lock) else ("depot_tools", "chromium", "cef")


def gn_arguments(defines: str) -> bytes:
    # The reviewed recipe uses scalar GN literals, never imports or expressions.
    pairs = re.findall(r'([a-z][a-z0-9_]*)=("[^"\n]*"|true|false|[0-9]+)(?:\s+|$)', defines)
    if " ".join(k + "=" + v for k, v in pairs) != defines or len(dict(pairs)) != len(pairs):
        raise Refusal("Expected unique scalar GN arguments")
    return ("\n".join(k + "=" + v for k, v in sorted(pairs)) + "\n").encode()


def load_lock(path: Path = LOCK_FILE) -> tuple[dict, str]:
    raw = path.read_bytes()
    lock = json.loads(raw)
    if lock.get("schema_version") not in {1, 2} or lock.get("target") != "mac-arm64":
        raise Refusal("Unsupported source lock")
    if direct_mode(lock) and "cef" in lock:
        raise Refusal("Direct source locks cannot contain CEF")
    for name in repository_names(lock):
        origin = ORIGINS[name]
        item = lock[name]
        if item["url"] != origin or not re.fullmatch(r"[0-9a-f]{40}", item["commit"]):
            raise Refusal(f"Invalid pinned origin/revision: {name}")
        for filename, sha in item.get("files", {}).items():
            if Path(filename).is_absolute() or ".." in Path(filename).parts or not re.fullmatch(r"[0-9a-f]{64}", sha):
                raise Refusal(f"Invalid pinned file: {name}/{filename}")
    if lock["build"]["configuration"] != "Release_GN_arm64" or (not direct_mode(lock) and lock["build"]["target"] != "cef"):
        raise Refusal("Only the reviewed ARM64 upstream build is supported")
    if direct_mode(lock):
        if lock["build"].get("targets") != ["//parc:parc_framework", "//parc/helper:parc_helper"]:
            raise Refusal("Unsupported direct build targets")
        gn_arguments(lock["build"]["gn_defines"] + " symbol_level=0")
    return lock, digest(raw)


def safe_path(value: str, repo: Path = REPO) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute() or ".." in path.parts:
        raise Refusal("Workspace must be an absolute path without '..'")
    # Chromium's generated commands are not all safe with whitespace/shell chars.
    if not re.fullmatch(r"/[A-Za-z0-9_./-]+", str(path)):
        raise Refusal("Workspace path must contain only ASCII letters, digits, /, ., _, -")
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise Refusal(f"Symlinked workspace/ancestor refused: {part}")
    path = path.resolve()
    repo = repo.resolve()
    work_root = (repo / "work").resolve()
    under_work = path == work_root or work_root in path.parents
    under_repo = path == repo or repo in path.parents
    # Prefer ignored checkout-local work/; outside paths remain valid for older setups.
    if (path == Path.home().resolve() or len(path.parts) < 3 or path in repo.parents
            or path == repo or path == work_root or (under_repo and not under_work)):
        raise Refusal("Use a dedicated workspace under this checkout's ignored work/ "
                      "(for example work/engine), or an owned path outside the repository")
    parent = path if path.exists() else path.parent
    if not parent.is_dir():
        raise Refusal("Workspace parent must already exist")
    if parent.stat().st_uid != os.getuid():
        raise Refusal("Workspace/parent must be owned by the current user")
    return path


def internal_path(path: Path, workspace: Path) -> Path:
    if ".." in path.parts or workspace not in path.parents:
        raise Refusal(f"Path is outside owned workspace: {path}")
    part = path
    while part != workspace:
        if part.is_symlink():
            raise Refusal(f"Symlinked internal path refused: {part}")
        part = part.parent
    return path


def run(argv: list[str], cwd: Path, env: dict, capture: bool = False) -> bytes:
    result = subprocess.run(argv, cwd=cwd, env=env, check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout or b""


def environment(workspace: Path, lock: dict, symbol_level: int) -> dict:
    # Do not inherit GN, GIT, Python injection or remote-execution configuration.
    return {
        "HOME": os.environ.get("HOME", str(Path.home())),
        "PATH": f"{workspace / 'depot_tools'}:/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(workspace / "tmp") + "/",
        "LANG": "en_US.UTF-8",
        "DEPOT_TOOLS_UPDATE": "0",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_TERMINAL_PROMPT": "0",
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
        # vpython's uv otherwise trusts only its bundled roots, and on networks
        # that re-sign TLS it stalls each depot_tools bootstrap for five minutes.
        "UV_NATIVE_TLS": "1",
        "GN_OUT_CONFIGS": lock["build"]["configuration"],
        "GN_DEFINES": lock["build"]["gn_defines"] + f" symbol_level={symbol_level}",
    }


def locations(workspace: Path, lock: dict | None = None) -> dict[str, Path]:
    paths = {"depot_tools": workspace / "depot_tools",
            "chromium": workspace / "chromium/src",
            "cef": workspace / "chromium/src/cef"}
    return {k: v for k, v in paths.items() if lock is None or k in repository_names(lock)}


def gclient_text(lock: dict) -> str:
    solution = {"name": "src", "url": lock["chromium"]["url"], "managed": False,
                "custom_deps": {}, "custom_vars": {"checkout_pgo_profiles": False},
                "deps_file": "DEPS", "safesync_url": ""}
    return "solutions = " + repr([solution]) + "\n"


def command_plan(workspace: Path, lock: dict, jobs: int) -> dict:
    paths = locations(workspace, lock)
    sync = []
    for name in repository_names(lock):
        path = paths[name]
        # Googlesource shallow-fetch of a raw Chromium commit SHA stalls with no
        # progress. Fetch the pinned tag when present, then detach at the commit.
        fetch = GIT + ["-c", "http.version=HTTP/1.1", "fetch", "--progress"]
        if name != "cef":
            fetch.append("--depth=1")
        fetch.append("origin")
        if name == "chromium" and lock[name].get("tag"):
            fetch.extend(["tag", lock[name]["tag"]])
        else:
            fetch.append(lock[name]["commit"])
        sync.extend([
            {"cwd": str(workspace), "argv": GIT + ["init", str(path)]},
            {"cwd": str(path), "argv": GIT + ["remote", "add", "origin", lock[name]["url"]]},
            {"cwd": str(path), "argv": fetch},
            {"cwd": str(path), "argv": GIT + ["checkout", "--detach", lock[name]["commit"]]},
        ])
    gclient = str(paths["depot_tools"] / "gclient")
    sync.extend([
        {"cwd": str(workspace / "chromium"), "argv": [gclient, "sync", "--nohooks", "--no-history", "--revision", "src@" + lock["chromium"]["commit"], "--output-json", str(workspace / "dependency-sync.json")]},
        {"cwd": str(paths["chromium"]), "argv": [sys.executable, str(locations(workspace)["cef"] / "tools/patcher.py"), "--patch-file", str(locations(workspace)["cef"] / "patch/patches/runhooks"), "--patch-dir", str(paths["chromium"])]},
        {"cwd": str(workspace / "chromium"), "argv": [gclient, "runhooks"]},
    ])
    if direct_mode(lock):
        sync = [c for c in sync if "--patch-file" not in c["argv"]]
        return {"sync": sync, "build": [
            {"cwd": str(paths["depot_tools"]), "argv": [str(paths["depot_tools"] / "ensure_bootstrap")]},
            {"cwd": str(paths["chromium"]), "argv": [str(paths["depot_tools"] / "gn"), "gen", "out/" + lock["build"]["configuration"]]},
            {"cwd": str(paths["chromium"]), "argv": [str(paths["depot_tools"] / "autoninja"), "-C", "out/" + lock["build"]["configuration"], "-j", str(jobs), *[t.removeprefix("//") for t in lock["build"]["targets"]]]},
        ]}
    return {"sync": sync, "build": [
        {"cwd": str(paths["depot_tools"]), "argv": [str(paths["depot_tools"] / "ensure_bootstrap")]},
        {"cwd": str(paths["cef"]), "argv": ["/bin/bash", "cef_create_projects.sh"]},
        {"cwd": str(paths["chromium"]), "argv": [str(paths["depot_tools"] / "autoninja"), "-C", "out/" + lock["build"]["configuration"], "-j", str(jobs), "cef_framework"]},
    ]}


def host_report(workspace: Path, lock: dict, operation: str) -> dict:
    parent = workspace if workspace.exists() else workspace.parent
    free = shutil.disk_usage(parent).free
    required = lock["storage"][operation + "_minimum_free_bytes"]
    blockers = []
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        blockers.append("A native Apple Silicon Mac is required")
    filesystem = "unknown"
    if platform.system() == "Darwin":
        # diskutil does not accept an arbitrary directory; resolve its device.
        device = subprocess.check_output(["/bin/df", "-P", str(parent)], text=True).splitlines()[-1].split()[0]
        info = plistlib.loads(subprocess.check_output(["/usr/sbin/diskutil", "info", "-plist", device]))
        filesystem = info.get("FilesystemType", "unknown")
        if filesystem != "apfs" or info.get("ReadOnlyVolume", False):
            blockers.append("A writable APFS volume is required")
        try:
            subprocess.run(["/usr/bin/xcodebuild", "-version"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError:
            blockers.append("Xcode must be installed and usable; this tool does not accept licenses")
    if free < required:
        blockers.append(f"Insufficient space: {free} free bytes; policy requires {required}")
    return {"operation": operation, "workspace": str(workspace), "filesystem": filesystem,
            "free_bytes": free, "minimum_free_bytes": required,
            "storage_basis": lock["storage"]["basis"], "blockers": blockers}


def read_marker(workspace: Path, lock_sha: str) -> dict:
    marker = internal_path(workspace / MARKER, workspace)
    if marker.is_symlink() or not marker.is_file():
        raise Refusal("Not a workspace created by this tool")
    state = json.loads(marker.read_text())
    if state.get("schema_version") != 1 or state.get("workspace") != str(workspace):
        raise Refusal("Workspace ownership/path/source lock does not match")
    if state.get("lock_sha256") != lock_sha:
        raise Refusal("Workspace ownership/path/source lock does not match; if only build.gn_defines "
                      "changed, run reconfigure with the previous source lock")
    return state


def write_marker(workspace: Path, state: dict, name: str = MARKER) -> None:
    if name not in {MARKER, SHIPPING_MARKER}:
        raise Refusal("Unknown build receipt")
    temp = internal_path(workspace / (name + ".tmp"), workspace)
    internal_path(workspace / name, workspace)
    # Every writer holds the operation lock (or has just claimed a new
    # workspace), so an existing temp is the remnant of a killed write.
    if temp.is_file():
        temp.unlink()
    with temp.open("x") as stream:
        json.dump(state, stream, indent=2)
        stream.write("\n")
    os.replace(temp, workspace / name)


def settle_dead_operation(workspace: Path, receipt: dict, name: str = MARKER) -> dict:
    """Record a dead generation or build as that step's returned failure.

    Callers hold the operation lock, and flock is released when its process
    dies, so a step still recorded in progress belongs to no live process.
    Resuming re-verifies the source fingerprint. A dead sync stays refused:
    a partial checkout is never adopted.
    """
    phase = receipt.get("phase")
    if phase not in {"generation-in-progress", "build-in-progress"}:
        return receipt
    error = "generation_error" if name == MARKER else "error"
    receipt = dict(receipt, phase=phase.removesuffix("-in-progress") + "-failed",
                   **{error: "interrupted: its process died"})
    write_marker(workspace, receipt, name)
    return receipt


def shipping_environment(workspace: Path, lock: dict, symbol_level: int) -> dict:
    env = environment(workspace, lock, symbol_level)
    defines = SHIPPING_DEFINES
    if direct_mode(lock):
        values = dict(line.split("=", 1) for line in gn_arguments(lock["build"]["gn_defines"]).decode().splitlines())
        values.update(line.split("=", 1) for line in gn_arguments(SHIPPING_DEFINES).decode().splitlines())
        defines = " ".join(k + "=" + v for k, v in values.items())
    env["GN_DEFINES"] = defines + f" symbol_level={symbol_level}"
    return env


def shipping_command_plan(workspace: Path, jobs: int, lock: dict | None = None) -> list[dict]:
    paths = locations(workspace)
    output = "out/" + SHIPPING_CONFIGURATION
    return [
        {"cwd": str(paths["chromium"]), "argv": [str(paths["depot_tools"] / "gn"), "gen", output]},
        {"cwd": str(paths["chromium"]), "argv": [str(paths["depot_tools"] / "autoninja"), "-C", output,
                                                "-j", str(jobs), *([t.removeprefix("//") for t in lock["build"]["targets"]] if lock and direct_mode(lock) else ["cef_framework"])]},
    ]


def shipping_arguments(workspace: Path, env: dict, lock: dict | None = None) -> bytes:
    if lock and direct_mode(lock):
        return gn_arguments(env["GN_DEFINES"])
    # Use the pinned CEF configuration generator, as gclient_hook.py does.
    # The separate GN output preserves all existing development objects.
    program = ("import gn_args; "
               "args=gn_args.GetAllPlatformConfigs({}, quiet=True)['Release_GN_arm64']; "
               "assert args['is_component_build'] is False and args['is_debug'] is False; "
               "assert args['dcheck_always_on'] is False; "
               "assert args['disable_fieldtrial_testing_config'] is True; "
               "assert args['proprietary_codecs'] is True and args['ffmpeg_branding'] == 'Chromium'; "
               "assert args['enable_ffmpeg_video_decoders'] is False and args['media_use_openh264'] is False; "
               "assert args['enable_hangout_services_extension'] is True; "
               "print(gn_args.GetConfigFileContents(args))")
    return run([sys.executable, "-c", program], locations(workspace)["cef"] / "tools", env, True)


def read_shipping_marker(workspace: Path, lock_sha: str, state: dict) -> dict:
    path = internal_path(workspace / SHIPPING_MARKER, workspace)
    receipt = json.loads(path.read_text())
    if (receipt.get("schema_version") != 1 or receipt.get("workspace") != str(workspace)
            or receipt.get("lock_sha256") != lock_sha
            or receipt.get("configuration") != SHIPPING_CONFIGURATION
            or receipt.get("gn_defines") != SHIPPING_DEFINES
            or receipt.get("symbol_level") != state["symbol_level"]):
        raise Refusal("Shipping build ownership/configuration mismatch")
    return receipt


def verify_shipping_build(workspace: Path, lock_sha: str, state: dict) -> dict:
    receipt = read_shipping_marker(workspace, lock_sha, state)
    args_path = internal_path(locations(workspace)["chromium"] / "out" / SHIPPING_CONFIGURATION / "args.gn", workspace)
    if (receipt.get("phase") != "built"
            or receipt.get("source_fingerprint") != state["source_fingerprint"]
            or receipt.get("overlay") != state.get("overlay")
            or receipt.get("args_sha256") != digest(args_path.read_bytes())):
        raise Refusal("A completed shipping build for the current source and GN arguments is required")
    return receipt


RESUMABLE_SHIPPING_PHASES = {"generated", "built", "generation-failed", "build-failed", "reconfigured"}


def shipping_build(workspace: Path, lock: dict, lock_sha: str, symbol_level: int, jobs: int,
                   *, generate_only: bool = False) -> None:
    report = host_report(workspace, lock, "build")
    if report["blockers"]:
        raise Refusal("; ".join(report["blockers"]))
    guard_path = internal_path(workspace / ".parc-operation.lock", workspace)
    with guard_path.open("r") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        state = settle_dead_operation(workspace, read_marker(workspace, lock_sha))
        if state.get("phase") not in {"generated", "built"} or state["symbol_level"] != symbol_level:
            raise Refusal("Complete normal engine source generation before building the shipping configuration")
        env = shipping_environment(workspace, lock, symbol_level)
        verify_workspace(workspace, lock, state, env)
        applied = recorded_overlay(workspace, state)
        if not applied:
            raise Refusal("Shipping requires the reviewed native source overlay")
        output = internal_path(locations(workspace)["chromium"] / "out" / SHIPPING_CONFIGURATION, workspace)
        receipt_path = internal_path(workspace / SHIPPING_MARKER, workspace)
        arguments = shipping_arguments(workspace, env, lock)
        if receipt_path.exists():
            previous = settle_dead_operation(workspace, read_shipping_marker(workspace, lock_sha, state),
                                             SHIPPING_MARKER)
            if previous.get("phase") not in RESUMABLE_SHIPPING_PHASES:
                raise Refusal("Interrupted shipping operation preserved; receipt is not resumable")
            args_path = internal_path(output / "args.gn", workspace)
            if args_path.read_bytes() != arguments or previous.get("args_sha256") != digest(arguments):
                raise Refusal("Shipping GN arguments changed; existing output is preserved")
        elif output.exists():
            raise Refusal("Shipping output exists without its ownership receipt")
        else:
            output.mkdir()
            (output / "args.gn").write_bytes(arguments)
        receipt = {"schema_version": 1, "workspace": str(workspace), "lock_sha256": lock_sha,
                   "configuration": SHIPPING_CONFIGURATION, "gn_defines": SHIPPING_DEFINES,
                   "symbol_level": symbol_level, "args_sha256": digest(arguments),
                   "source_fingerprint": state["source_fingerprint"], "overlay": state["overlay"]}
        if direct_mode(lock):
            receipt.update(engine_mode="direct", build_targets=lock["build"]["targets"], effective_gn_defines=env["GN_DEFINES"])
        commands = shipping_command_plan(workspace, jobs, lock)
        if generate_only:
            commands = commands[:1]
        for phase, command in zip(("generation", "build"), commands):
            receipt["phase"] = phase + "-in-progress"
            write_marker(workspace, receipt, SHIPPING_MARKER)
            try:
                run(command["argv"], Path(command["cwd"]), env)
            except (OSError, subprocess.CalledProcessError) as error:
                receipt.update(phase=phase + "-failed", error=str(error))
                write_marker(workspace, receipt, SHIPPING_MARKER)
                raise
            receipt["phase"] = "generated" if phase == "generation" else "built"
            write_marker(workspace, receipt, SHIPPING_MARKER)


def reconfigure_shipping(workspace: Path, lock: dict, previous_sha: str, lock_sha: str,
                         state: dict) -> dict:
    receipt = json.loads(internal_path(workspace / SHIPPING_MARKER, workspace).read_text())
    if (receipt.get("schema_version") != 1 or receipt.get("workspace") != str(workspace)
            or receipt.get("configuration") != SHIPPING_CONFIGURATION
            or receipt.get("symbol_level") != state["symbol_level"]
            or receipt.get("lock_sha256") not in {previous_sha, lock_sha}):
        raise Refusal("Shipping build ownership/configuration mismatch")
    receipt = settle_dead_operation(workspace, receipt, SHIPPING_MARKER)
    if receipt.get("phase") not in RESUMABLE_SHIPPING_PHASES:
        raise Refusal("Interrupted shipping operation preserved; receipt is not resumable")
    args_path = internal_path(locations(workspace)["chromium"] / "out" / SHIPPING_CONFIGURATION / "args.gn", workspace)
    if args_path.is_symlink() or not args_path.is_file():
        raise Refusal("Shipping output exists without its generated arguments")
    arguments = shipping_arguments(workspace, shipping_environment(workspace, lock, state["symbol_level"]), lock)
    current = args_path.read_bytes()
    # A killed reconfigure may already have replaced args.gn before its receipt.
    if digest(current) not in {receipt.get("args_sha256"), digest(arguments)}:
        raise Refusal("Shipping arguments differ from their receipt; existing output is preserved")
    changed = receipt.get("args_sha256") != digest(arguments)
    if current != arguments:
        write_source(args_path, arguments, args_path.stat().st_mode & 0o777)
    receipt.update(lock_sha256=lock_sha, gn_defines=SHIPPING_DEFINES, args_sha256=digest(arguments))
    if changed:
        # gn gen and compilation must run again before this output can be sealed.
        receipt.pop("error", None)
        receipt["phase"] = "reconfigured"
    write_marker(workspace, receipt, SHIPPING_MARKER)
    return {"phase": receipt["phase"], "arguments_changed": changed}


def reconfigure(workspace: Path, lock: dict, lock_sha: str, previous_path: Path) -> dict:
    """Adopt a source lock whose only changes are build.gn_defines and the host disk floors.

    Sources, overlay records and compiled objects are untouched. The receipt
    returns to synced, so the next build regenerates GN files with the new
    arguments; that build recompiles whatever those arguments invalidate.
    """
    if (not previous_path.is_absolute() or ".." in previous_path.parts
            or any(p.is_symlink() for p in [previous_path, *previous_path.parents])):
        raise Refusal("Previous source lock must be an absolute non-symlink path")
    previous, previous_sha = load_lock(previous_path)
    if previous_sha == lock_sha:
        raise Refusal("Previous source lock is the current source lock")

    def without_defines(item: dict) -> dict:
        # storage holds this host's free-space preflight floors, not a build input.
        return {**{k: v for k, v in item.items() if k != "storage"},
                "build": {k: v for k, v in item["build"].items() if k != "gn_defines"}}
    if without_defines(previous) != without_defines(lock):
        raise Refusal("reconfigure only accepts a source lock that changes build.gn_defines or storage")
    guard_path = internal_path(workspace / ".parc-operation.lock", workspace)
    with guard_path.open("r") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        try:
            read_marker(workspace, lock_sha)
            already = True
        except Refusal:
            already = False
        if already:
            raise Refusal("Workspace already records the current source lock; reconfigure is complete, "
                          "continue with overlay-apply or build")
        state = settle_dead_operation(workspace, read_marker(workspace, previous_sha))
        if state.get("phase") not in {"synced", "generation-failed", "generated", "built"}:
            raise Refusal("Partial operation preserved; only a completed source state can be reconfigured")
        verify_workspace(workspace, previous, state, environment(workspace, previous, state["symbol_level"]))
        report = {"workspace": str(workspace), "previous_lock_sha256": previous_sha,
                  "lock_sha256": lock_sha, "previous_phase": state["phase"],
                  "gn_defines": lock["build"]["gn_defines"], "shipping": None}
        if (workspace / SHIPPING_MARKER).exists():
            report["shipping"] = reconfigure_shipping(workspace, lock, previous_sha, lock_sha, state)
        active = dict(state)
        active.pop("generation_error", None)
        active.update(lock_sha256=lock_sha, phase="synced")
        write_marker(workspace, active)
        report["phase"] = "synced"
        return report


def retarget_reserve(workspace: Path, previous: dict, lock: dict, env: dict) -> str:
    """Use the incremental reserve only with matching lock tags and CEF ancestry."""
    values = [item["chromium"].get("tag") for item in (previous, lock)]
    tags = [re.fullmatch(r"([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)", value)
            if isinstance(value, str) else None for value in values]
    if not all(tags) or tags[0].groups()[:3] != tags[1].groups()[:3]:
        return "sync"
    cef = locations(workspace)["cef"]
    branch = "refs/heads/" + tags[0].group(3)
    try:
        # Refresh this one CEF branch, never Chromium or its dependencies, before
        # deciding whether a locked source upgrade qualifies as incremental.
        run(GIT + ["fetch", "--no-tags", "origin", branch], cef, env)
        head = run(GIT + ["rev-parse", "--verify", "FETCH_HEAD^{commit}"], cef, env, True).decode().strip()
        if not re.fullmatch(r"[0-9a-f]{40}", head):
            return "sync"
        for item in (previous, lock):
            run(GIT + ["merge-base", "--is-ancestor", item["cef"]["commit"], head], cef, env, True)
    except (OSError, subprocess.CalledProcessError, UnicodeError):
        return "sync"
    return "build"


def retarget(workspace: Path, lock: dict, lock_sha: str, previous_path: Path) -> dict:
    """Change only dependency pins, preserving outputs and untracked files."""
    if (not previous_path.is_absolute() or ".." in previous_path.parts
            or any(p.is_symlink() for p in [previous_path, *previous_path.parents])):
        raise Refusal("Previous source lock must be an absolute non-symlink path")
    previous, previous_sha = load_lock(previous_path)
    if direct_mode(lock) or direct_mode(previous):
        raise Refusal("Direct retarget transition is not enabled yet")
    def fixed(item):
        return {k: v for k, v in item.items() if k not in
                {"chromium", "cef", "depot_tools", "references"}}
    if previous_sha == lock_sha or fixed(previous) != fixed(lock):
        raise Refusal("retarget requires changed pins with unchanged build settings and storage")
    for name in locations(workspace):
        if previous[name]["url"] != lock[name]["url"]:
            raise Refusal("retarget cannot change repository origins")
    report = host_report(workspace, lock, "build")
    if report["blockers"]:
        raise Refusal("; ".join(report["blockers"]))
    guard_path = internal_path(workspace / ".parc-operation.lock", workspace)
    with guard_path.open("r") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        state = read_marker(workspace, previous_sha)
        if state.get("phase") not in {"synced", "generated", "built"}:
            raise Refusal("retarget requires a recorded good source phase")
        env = environment(workspace, previous, state["symbol_level"])
        verify_workspace(workspace, previous, state, env)
        reserve = retarget_reserve(workspace, previous, lock, env)
        report = host_report(workspace, lock, reserve)
        if report["blockers"]:
            raise Refusal("; ".join(report["blockers"]))
        record = recorded_overlay(workspace, state)
        # Validate every restoration path before starting a non-resumable stage.
        restores = [(target_path(workspace, target, previous),
                     item["original"].encode() if item["original"] is not None else None,
                     item["mode"]) for target, item in (record or {}).get("targets", {}).items()]
        shipping_path = internal_path(workspace / SHIPPING_MARKER, workspace)
        shipping = None
        if shipping_path.exists():
            shipping = read_shipping_marker(workspace, previous_sha, state)
        active = dict(state, phase="retarget-in-progress", retarget_lock_sha256=lock_sha)
        write_marker(workspace, active)
        if shipping is not None:
            shipping.update(phase="retarget-in-progress")
            write_marker(workspace, shipping, SHIPPING_MARKER)
        for path, original, mode in restores:
            write_source(path, original, mode)
        # Undo only tracked changes in the verified receipt (CEF's patches).
        # No reset --hard or clean: untracked files and out/ must survive.
        for relative in state["repositories"]:
            path = internal_path(workspace / relative, workspace)
            run(GIT + ["restore", "--source=HEAD", "--staged", "--worktree", "."], path, env)
        plan = command_plan(workspace, lock, 4)
        env = environment(workspace, lock, state["symbol_level"])
        for index, command in enumerate(plan["sync"]):
            if index < 12 and index % 4 not in {2, 3}:
                continue
            if index >= 12:
                for name, path in locations(workspace, lock).items():
                    verify_repository(path, lock[name], env, require_clean=name == "depot_tools")
            run(command["argv"], Path(command["cwd"]), env)
        # CEF's full patch set is normally applied by project generation. Apply
        # it explicitly here without generating or touching compiled outputs.
        run([sys.executable, str(locations(workspace)["cef"] / "tools/patcher.py")],
            locations(workspace)["cef"], env)
        repositories = synced_repositories(workspace, lock)
        for name, path in locations(workspace, lock).items():
            verify_repository(path, lock[name], env, require_clean=name == "depot_tools")
        active = {k: v for k, v in state.items() if k not in {"overlay", "generation_error"}}
        active.update(lock_sha256=lock_sha, phase="synced", repositories=repositories,
                      source_fingerprint=tree_fingerprint(workspace, env, repositories))
        if shipping is not None:
            shipping.update(lock_sha256=lock_sha, phase="reconfigured",
                            source_fingerprint=active["source_fingerprint"], overlay=None)
            write_marker(workspace, shipping, SHIPPING_MARKER)
        write_marker(workspace, active)
        return {"workspace": str(workspace), "phase": "synced", "lock_sha256": lock_sha,
                "reserve": reserve, "minimum_free_bytes": report.get("minimum_free_bytes")}


def verify_repository(path: Path, item: dict, env: dict, require_clean: bool = True) -> None:
    if path.is_symlink() or not (path / ".git").is_dir() or (path / ".git").is_symlink():
        raise Refusal(f"Expected owned ordinary Git checkout: {path}")
    if run(GIT + ["rev-parse", "HEAD"], path, env, True).decode().strip() != item["commit"]:
        raise Refusal(f"Revision mismatch: {path}")
    if run(GIT + ["remote", "get-url", "origin"], path, env, True).decode().strip() != item["url"]:
        raise Refusal(f"Origin mismatch: {path}")
    if require_clean and run(GIT + ["status", "--porcelain", "--untracked-files=all"], path, env, True):
        raise Refusal(f"Modified checkout refused: {path}")
    for filename, sha in item.get("files", {}).items():
        file = path / filename
        if file.is_symlink() or digest(file.read_bytes()) != sha:
            raise Refusal(f"Pinned script/content digest mismatch: {file}")


def discover_repositories(workspace: Path) -> list[str]:
    """Used only for interrupted sync recovery, never for ordinary builds."""
    roots = []
    for base, dirs, files in os.walk(workspace / "chromium/src", followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in {"out", ".git"} and not (Path(base) / d).is_symlink())
        if (Path(base) / ".git").exists():
            roots.append(str(Path(base).relative_to(workspace)))
    return sorted(roots)


def synced_repositories(workspace: Path, lock: dict | None = None) -> list[str]:
    entries = json.loads((workspace / "dependency-sync.json").read_text())["solutions"]
    roots = {"chromium/src"}
    if lock is None or not direct_mode(lock):
        roots.add("chromium/src/cef")
    for name, value in entries.items():
        if value.get("scm") == "git":
            relative = Path("chromium") / name
            internal_path(workspace / relative, workspace)
            roots.add(str(relative))
    return sorted(roots)


def tree_fingerprint(workspace: Path, env: dict, repositories: list[str]) -> str:
    """Bind recorded Git dependencies' HEADs, diffs and untracked file contents.

    No source-tree traversal during build. Ignored build outputs are excluded.
    The repository inventory is bound by the owned workspace marker. This is an
    upstream-baseline check; future reviewed Parc source overlays are separate.
    """
    result = hashlib.sha256()
    if not repositories or "chromium/src" not in repositories:
        raise Refusal("Source repository inventory is missing")
    for relative in sorted(repositories):
        root = internal_path(workspace / relative, workspace)
        git = internal_path(root / ".git", workspace)
        if not git.is_dir():
            raise Refusal(f"Expected ordinary Git metadata: {git}")
        result.update(relative.encode() + b"\0")
        # A failed dependency fetch may have initialized an unborn repository.
        try:
            head = run(GIT + ["rev-parse", "--verify", "HEAD"], root, env, True)
        except subprocess.CalledProcessError:
            head = b"UNBORN"
        result.update(head + b"\0")
        if head != b"UNBORN":
            result.update(run(GIT + ["diff", "--binary", "HEAD"], root, env, True) + b"\0")
        result.update(run(GIT + ["status", "--porcelain=v1", "-z", "--untracked-files=all"], root, env, True) + b"\0")
        others = run(GIT + ["ls-files", "--others", "--exclude-standard", "-z"], root, env, True)
        for name in sorted(others.split(b"\0")):
            if not name:
                continue
            file = root / os.fsdecode(name)
            result.update(name + b"\0")
            if file.is_symlink():
                result.update(os.readlink(file).encode())
            else:
                with file.open("rb") as stream:
                    file_hash = hashlib.sha256()
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        file_hash.update(chunk)
                    result.update(file_hash.digest())
    return result.hexdigest()


def verify_workspace(workspace: Path, lock: dict, state: dict, env: dict) -> None:
    config = internal_path(workspace / "chromium/.gclient", workspace)
    if config.is_symlink() or config.read_text() != gclient_text(lock):
        raise Refusal("gclient configuration changed")
    for name, path in locations(workspace, lock).items():
        internal_path(path, workspace)
        for filename in lock[name].get("files", {}):
            internal_path(path / filename, workspace)
        # The CEF project generator applies reviewed upstream source patches.
        verify_repository(path, lock[name], env, require_clean=name == "depot_tools")
    if tree_fingerprint(workspace, env, state.get("repositories", [])) != state.get("source_fingerprint"):
        raise Refusal("Source/dependency changes detected; preserved without regeneration")
    if direct_mode(lock) and state.get("phase") in {"generated", "built"}:
        args = internal_path(locations(workspace)["chromium"] / "out" / lock["build"]["configuration"] / "args.gn", workspace)
        if (not args.is_file() or state.get("engine_mode") != "direct" or state.get("build_targets") != lock["build"]["targets"]
                or state.get("args_sha256") != digest(args.read_bytes())
                or args.read_bytes() != gn_arguments(environment(workspace, lock, state["symbol_level"])["GN_DEFINES"])):
            raise Refusal("Direct generated arguments differ from their receipt")
    recorded_overlay(workspace, state)


def relative_source(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_./-]*", value):
        raise Refusal(f"Unsupported relative source path: {value}")
    if any(part in {"", ".", ".."} for part in value.split("/")):
        raise Refusal(f"Invalid relative source path: {value}")
    return value


def text_bytes(path: Path, *, maximum_bytes: int = 8 * 1024 * 1024) -> bytes:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_bytes:
        raise Refusal(f"Expected a regular text file of at most {maximum_bytes} bytes: {path}")
    data = path.read_bytes()
    data.decode("utf-8")
    if b"\0" in data:
        raise Refusal(f"Binary source overlay refused: {path}")
    return data


def target_path(workspace: Path, target: str, lock: dict | None = None) -> Path:
    relative_source(target)
    # Overlay build logic is reviewable source, but bootstrap trust inputs,
    # repository metadata, dependency selection and generated outputs are not.
    parts = target.split("/")
    if any(p.startswith(".") or p in {"out", "DEPS"} for p in parts):
        raise Refusal(f"Overlay cannot change bootstrap/generated inputs: {target}")
    if lock and direct_mode(lock) and parts[0] == "cef":
        raise Refusal("Direct overlays cannot target CEF")
    if lock and target in {"cef/" + name for name in lock.get("cef", {}).get("files", {})}:
        raise Refusal(f"Overlay cannot change a pinned bootstrap file: {target}")
    file = internal_path(workspace / "chromium/src" / target, workspace)
    for parent in file.parents:
        if parent == workspace:
            break
        if parent.exists() and not parent.is_dir():
            raise Refusal(f"Source parent is not a directory: {parent}")
    return file


def apply_context_patch(patch: str, originals: dict[str, bytes]) -> dict[str, bytes]:
    """Apply ordinary unified text hunks exactly, without fuzzy offsets or Git.

    New files use manifest files[], so rename/mode/binary/add/delete sections
    are deliberately unsupported. Both git diff and plain unified headers work.
    """
    lines = patch.splitlines(keepends=True)
    outputs = {}
    index = 0
    while index < len(lines):
        declared_target = None
        if lines[index].startswith("diff --git "):
            header = lines[index].rstrip("\n").split(" ")
            if len(header) != 4 or not header[2].startswith("a/") or not header[3].startswith("b/") or header[2][2:] != header[3][2:]:
                raise Refusal("Renamed/quoted patch paths are unsupported")
            declared_target = header[2][2:]
            index += 1
            if index < len(lines) and re.fullmatch(r"index [0-9a-f]+\.\.[0-9a-f]+(?: [0-7]{6})?\n?", lines[index]):
                index += 1
        if index + 1 >= len(lines) or not lines[index].startswith("--- a/") or not lines[index + 1].startswith("+++ b/"):
            raise Refusal("Expected same-file unified source patch headers")
        target = relative_source(lines[index][6:].rstrip("\n"))
        if declared_target is not None and declared_target != target:
            raise Refusal("Git and unified patch paths disagree")
        if lines[index + 1][6:].rstrip("\n") != target or target in outputs or target not in originals:
            raise Refusal(f"Unexpected/duplicate patch target: {target}")
        source = originals[target].decode("utf-8").splitlines(keepends=True)
        result = []
        cursor = 0
        index += 2
        hunks = 0
        while index < len(lines) and lines[index].startswith("@@ "):
            match = re.fullmatch(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n?", lines[index])
            if not match:
                raise Refusal("Malformed source patch hunk")
            old_start, old_count, new_start, new_count = (int(v) if v is not None else 1 for v in match.groups())
            position = old_start - 1 if old_count else old_start
            if position < cursor or position > len(source):
                raise Refusal("Overlapping/out-of-bounds source patch hunk")
            result.extend(source[cursor:position])
            if (new_start - 1 if new_count else new_start) != len(result):
                raise Refusal("Source patch new-line position does not match")
            index += 1
            body = []
            while index < len(lines) and lines[index][:1] in {" ", "+", "-", "\\"} and not lines[index].startswith("--- a/"):
                line = lines[index]
                if line.startswith("\\"):
                    if line.rstrip("\n") != "\\ No newline at end of file" or not body or not body[-1][1].endswith("\n"):
                        raise Refusal("Invalid missing-newline patch marker")
                    body[-1] = (body[-1][0], body[-1][1][:-1])
                else:
                    body.append((line[0], line[1:]))
                index += 1
            before = [line for tag, line in body if tag in {" ", "-"}]
            after = [line for tag, line in body if tag in {" ", "+"}]
            if not any(tag == " " for tag, _ in body) or len(before) != old_count or len(after) != new_count:
                raise Refusal("Source patch requires matching counts and context")
            if source[position:position + old_count] != before:
                raise Refusal(f"Source patch context mismatch: {target}")
            result.extend(after)
            cursor = position + old_count
            hunks += 1
        if not hunks:
            raise Refusal("Source patch has no contextual hunks")
        result.extend(source[cursor:])
        outputs[target] = "".join(result).encode("utf-8")
    if set(outputs) != set(originals):
        raise Refusal("Source patch targets do not match manifest inventory")
    return outputs


def overlay_record_bytes(record: dict) -> bytes:
    # The aggregate contains original text from hundreds of source files. Its
    # bound is separate from each source's limit and checked before any writes.
    raw = (json.dumps(record, indent=2) + "\n").encode("utf-8")
    if len(raw) > OVERLAY_RECORD_LIMIT:
        raise Refusal("Aggregate overlay record exceeds its size limit")
    return raw


def load_overlay_record(workspace: Path, state: dict) -> dict | None:
    """Load the saved overlay record without checking live tree bytes."""
    reference = state.get("overlay")
    if reference is None:
        return None
    identity = reference["identity"]
    if not re.fullmatch(r"[0-9a-f]{64}", identity):
        raise Refusal("Invalid recorded overlay identity")
    file = internal_path(workspace / ".parc-overlays" / (identity + ".json"), workspace)
    raw = text_bytes(file, maximum_bytes=OVERLAY_RECORD_LIMIT)
    if digest(raw) != reference["record_sha256"]:
        raise Refusal("Overlay record changed")
    record = json.loads(raw)
    if record["identity"] != identity:
        raise Refusal("Overlay record identity mismatch")
    return record


def recorded_overlay(workspace: Path, state: dict) -> dict | None:
    record = load_overlay_record(workspace, state)
    if record is None:
        return None
    for target, item in record["targets"].items():
        file = target_path(workspace, target)
        if digest(text_bytes(file)) != item["output_sha256"] or file.stat().st_mode & 0o777 != item["mode"]:
            raise Refusal(f"Applied overlay source changed: {target}")
    return record


def prepare_overlay(workspace: Path, lock: dict, state: dict, manifest: Path,
                    *, verify_live_outputs: bool = True) -> tuple[dict, dict]:
    """Validate every input and compute the complete update before any writes."""
    if not manifest.is_absolute() or ".." in manifest.parts or any(p.is_symlink() for p in [manifest, *manifest.parents]):
        raise Refusal("Manifest must be an absolute non-symlink path")
    raw = text_bytes(manifest)
    spec = json.loads(raw)
    if spec.get("schema_version") != 1 or not re.fullmatch(r"[a-z][a-z0-9-]*", spec.get("id", "")) or type(spec.get("version")) is not int or spec["version"] < 1:
        raise Refusal("Unsupported source overlay identity/version")
    if spec.get("upstream") != {name: lock[name]["commit"] for name in (("chromium",) if direct_mode(lock) else ("cef", "chromium"))}:
        raise Refusal("Overlay upstream commits do not match the source lock")
    source_root = spec.get("source_root", "manifest")
    if source_root not in {"manifest", "repository"}:
        raise Refusal("Overlay source_root must be manifest or repository")
    input_root = REPO if source_root == "repository" else manifest.parent
    internal_path(manifest, input_root)
    build_targets = spec.get("build_targets", [])
    if not isinstance(build_targets, list) or len(set(build_targets)) != len(build_targets) or any(not isinstance(t, str) or not re.fullmatch(r"//parc(?:/[a-z][a-z0-9_]*)*:[a-z][a-z0-9_]*" if direct_mode(lock) else r"[a-z][a-z0-9_]*", t) or t == "cef" for t in build_targets):
        raise Refusal("Invalid overlay build targets")
    # Resume after a killed apply must not require live outputs to still match the
    # previous overlay; those files may already be partially updated.
    previous = (recorded_overlay(workspace, state) if verify_live_outputs
                else load_overlay_record(workspace, state))

    identity = digest(raw)
    if previous and (spec["id"] != previous["id"] or (identity != previous["identity"] and spec["version"] <= previous["version"])):
        raise Refusal("An overlay update must keep its ID and increment its version")
    old = previous["targets"] if previous else {}
    targets = {}
    used = set()

    def input_bytes(item):
        file = internal_path(input_root / relative_source(item["source"]), input_root)
        data = text_bytes(file)
        if digest(data) != item["sha256"]:
            raise Refusal(f"Overlay input digest mismatch: {file}")
        return data

    def original(target, adding=False):
        file = target_path(workspace, target, lock)
        folded = target.casefold()
        if folded in used:
            raise Refusal(f"Duplicate overlay target: {target}")
        used.add(folded)
        if target in old:
            item = old[target]
            data = item["original"]
            data = data.encode("utf-8") if data is not None else None
            mode = item["mode"]
        else:
            data = text_bytes(file) if file.exists() else None
            mode = file.stat().st_mode & 0o777 if data is not None else 0o644
        if (data is None) != adding:
            raise Refusal(f"Expected {'new' if adding else 'existing'} source target: {target}")
        targets[target] = {"original": data.decode("utf-8") if data is not None else None, "mode": mode}
        return data

    writes = {}
    for item in spec.get("files", []):
        target = item["target"]
        original(target, adding=True)
        writes[target] = input_bytes(item)
    for patch in spec.get("patches", []):
        originals = {}
        expected = {}
        for item in patch["files"]:
            target = item["target"]
            data = original(target)
            if digest(data) != item["before_sha256"]:
                raise Refusal(f"Overlay base digest mismatch: {target}")
            originals[target] = data
            expected[target] = item["after_sha256"]
        outputs = apply_context_patch(input_bytes(patch).decode("utf-8"), originals)
        for target, data in outputs.items():
            if digest(data) != expected[target]:
                raise Refusal(f"Overlay result digest mismatch: {target}")
        writes.update(outputs)
    if not targets:
        raise Refusal("Empty source overlay")
    for target, data in writes.items():
        targets[target]["output_sha256"] = digest(data)
    # An update can retire earlier owned additions or restore patched originals,
    # but only after the old record and all live outputs have been verified.
    for target, item in old.items():
        if target not in targets:
            writes[target] = item["original"].encode("utf-8") if item["original"] is not None else None
    record = {"schema_version": 1, "identity": identity, "id": spec["id"], "version": spec["version"],
              "upstream": spec["upstream"], "build_targets": build_targets, "targets": targets}
    overlay_record_bytes(record)
    return record, writes


def write_source(path: Path, data: bytes | None, mode: int) -> None:
    if data is None:
        path.unlink()  # Only a verified, previously overlay-owned addition.
        return
    # Siso's local incremental checks use input mtimes. Replacing identical
    # reviewed headers would needlessly invalidate their compiled dependents.
    if path.is_file() and path.stat().st_mode & 0o777 == mode and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".parc-source-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _finish_overlay_writes(workspace: Path, lock: dict, state: dict, env: dict,
                           record: dict, writes: dict, raw: bytes) -> None:
    """Write every overlay target then mark the workspace synced."""
    for target, data in writes.items():
        path = target_path(workspace, target, lock)
        mode = record["targets"].get(target, {}).get("mode", path.stat().st_mode & 0o777 if path.exists() else 0o644)
        write_source(path, data, mode)
    active = dict(state)
    active.pop("pending_overlay", None)
    active.update(phase="synced", overlay={"identity": record["identity"], "record_sha256": digest(raw)},
                  source_fingerprint=tree_fingerprint(workspace, env, state["repositories"]))
    recorded_overlay(workspace, active)
    write_marker(workspace, active)


def overlay(workspace: Path, lock: dict, lock_sha: str, manifest: Path, apply: bool) -> dict:
    state = read_marker(workspace, lock_sha)
    guard_path = internal_path(workspace / ".parc-operation.lock", workspace)
    # The bootstrap creates this lock. Checking an overlay creates no files.
    with guard_path.open("rb") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        state = settle_dead_operation(workspace, read_marker(workspace, lock_sha))
        env = environment(workspace, lock, state["symbol_level"])
        # A killed apply leaves phase overlay-applying with pending_overlay set.
        # Re-running overlay-apply with the same manifest finishes those writes.
        if state.get("phase") == "overlay-applying":
            pending = state.get("pending_overlay")
            if not apply:
                raise Refusal("Interrupted overlay apply in progress; re-run overlay-apply to finish")
            if not isinstance(pending, str) or not re.fullmatch(r"[0-9a-f]{64}", pending):
                raise Refusal("Interrupted overlay apply is missing pending_overlay")
            record, writes = prepare_overlay(workspace, lock, state, manifest, verify_live_outputs=False)
            if record["identity"] != pending:
                raise Refusal("Interrupted overlay apply pending a different manifest; "
                              "re-run overlay-apply with that same reviewed overlay")
            raw = overlay_record_bytes(record)
            record_path = internal_path(workspace / ".parc-overlays" / (record["identity"] + ".json"), workspace)
            if not record_path.is_file() or record_path.read_bytes() != raw:
                raise Refusal("Interrupted overlay apply is missing its saved overlay record")
            report = {"overlay": record["id"], "version": record["version"], "identity": record["identity"],
                      "targets": sorted(writes), "build_targets": record["build_targets"], "applied": True}
            _finish_overlay_writes(workspace, lock, state, env, record, writes, raw)
            return report
        if state.get("phase") not in {"synced", "generation-failed", "generated", "built"}:
            raise Refusal("Overlay requires a complete, unchanged source workspace")
        verify_workspace(workspace, lock, state, env)
        record, writes = prepare_overlay(workspace, lock, state, manifest)
        report = {"overlay": record["id"], "version": record["version"], "identity": record["identity"],
                  "targets": sorted(writes), "build_targets": record["build_targets"], "applied": False}
        if not apply or state.get("overlay", {}).get("identity") == record["identity"]:
            report["applied"] = state.get("overlay", {}).get("identity") == record["identity"]
            return report
        before = {}
        for target in writes:
            path = target_path(workspace, target, lock)
            before[target] = (text_bytes(path), path.stat().st_mode & 0o777) if path.exists() else (None, 0o644)
        raw = overlay_record_bytes(record)
        record_path = internal_path(workspace / ".parc-overlays" / (record["identity"] + ".json"), workspace)
        record_path.parent.mkdir(exist_ok=True)
        if record_path.exists():
            if record_path.read_bytes() != raw:
                raise Refusal("Conflicting saved overlay record")
        else:
            with record_path.open("xb") as stream:
                stream.write(raw)
        # Marker flips before writes so a kill can resume via overlay-apply.
        active = dict(state, phase="overlay-applying", pending_overlay=record["identity"])
        write_marker(workspace, active)
        changed = []
        try:
            for target, data in writes.items():
                path = target_path(workspace, target, lock)
                mode = record["targets"].get(target, {}).get("mode", before[target][1])
                write_source(path, data, mode)
                changed.append(target)
            active.pop("pending_overlay")
            active.update(phase="synced", overlay={"identity": record["identity"], "record_sha256": digest(raw)},
                          source_fingerprint=tree_fingerprint(workspace, env, state["repositories"]))
            recorded_overlay(workspace, active)
            write_marker(workspace, active)
        except Exception:
            # Ordinary errors roll back exact prior bytes. KeyboardInterrupt and
            # other BaseException kills stay in overlay-applying; re-run apply.
            for target in reversed(changed):
                write_source(target_path(workspace, target, lock), *before[target])
            write_marker(workspace, state)
            raise
        report["applied"] = True
        return report


def execute(workspace: Path, lock: dict, lock_sha: str, operation: str, symbol_level: int, jobs: int) -> None:
    # generate uses the same disk floor as build; only sync has a separate reserve.
    report = host_report(workspace, lock, "build" if operation == "generate" else operation)
    if report["blockers"]:
        raise Refusal("; ".join(report["blockers"]))
    plan = command_plan(workspace, lock, jobs)
    env = environment(workspace, lock, symbol_level)
    is_new = not workspace.exists()

    def admitted_state() -> dict:
        state = settle_dead_operation(workspace, read_marker(workspace, lock_sha))
        allowed = {"dependency-sync-failed"} if operation == "sync" else {"synced", "generation-failed", "generated", "built"}
        if state.get("phase") not in allowed:
            raise Refusal("Partial operation preserved; only recorded, unchanged failures can resume")
        if state["symbol_level"] != symbol_level:
            raise Refusal("Build configuration differs from owned workspace")
        return state
    claimed = operation == "sync" and is_new
    if claimed:
        workspace.mkdir(mode=0o700)  # Atomic claim, never adopt an arbitrary tree.
        state = {"schema_version": 1, "workspace": str(workspace), "lock_sha256": lock_sha,
                 "phase": "sync-in-progress", "symbol_level": symbol_level}
        write_marker(workspace, state)
    else:
        # Ownership before touching the lock; the phase is judged under it.
        state = read_marker(workspace, lock_sha)
    for name in ("tmp", ".parc-operation.lock"):
        internal_path(workspace / name, workspace)
    with (workspace / ".parc-operation.lock").open("a") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        if not claimed:
            state = admitted_state()
        if operation == "sync":
            if is_new:
                for directory in ("tmp", "chromium"):
                    (workspace / directory).mkdir()
                (workspace / "chromium/.gclient").write_text(gclient_text(lock))
                start = 0
            else:
                verify_workspace(workspace, lock, state, env)
                start = 4 * len(repository_names(lock))  # Only repeat gclient sync, never checkout/reset sources.
                state["phase"] = "sync-in-progress"
                write_marker(workspace, state)
            for index, command in enumerate(plan["sync"]):
                if index < start:
                    continue
                if index == 8 and not direct_mode(lock):
                    exclude = locations(workspace)["chromium"] / ".git/info/exclude"
                    exclude.parent.mkdir(exist_ok=True)
                    with exclude.open("a") as stream:
                        stream.write("\n/cef/\n")
                if index >= 4 * len(repository_names(lock)):
                    for name, path in locations(workspace, lock).items():
                        verify_repository(path, lock[name], env, require_clean=name != "chromium" or index == 4 * len(repository_names(lock)))
                try:
                    run(command["argv"], Path(command["cwd"]), env)
                except (OSError, subprocess.CalledProcessError):
                    if index == 4 * len(repository_names(lock)):
                        # Snapshot only this owned failed sync; any later edit blocks
                        # resumption. gclient is rerun without force/reset/delete.
                        repositories = discover_repositories(workspace)
                        state.update(phase="dependency-sync-failed", repositories=repositories,
                                     source_fingerprint=tree_fingerprint(workspace, env, repositories))
                        write_marker(workspace, state)
                    raise
            repositories = synced_repositories(workspace, lock)
            state.update(phase="synced", repositories=repositories,
                         source_fingerprint=tree_fingerprint(workspace, env, repositories))
            write_marker(workspace, state)
        else:
            verify_workspace(workspace, lock, state, env)
            applied = recorded_overlay(workspace, state)
            if applied:
                plan["build"][-1]["argv"].extend(t.removeprefix("//") if direct_mode(lock) else t for t in applied["build_targets"])
            if direct_mode(lock) and not applied:
                raise Refusal("Direct generation requires the reviewed Parc overlay")
            if state["phase"] in {"synced", "generation-failed"}:
                # gclient intentionally skips update_depot_tools under the
                # pinned DEPOT_TOOLS_UPDATE=0 policy. Its vpython entry point
                # can work even while GN's hermetic Python is missing.
                command = plan["build"][0]
                run(command["argv"], Path(command["cwd"]), env)
                state["phase"] = "generation-in-progress"
                write_marker(workspace, state)
                command = plan["build"][1]
                if direct_mode(lock):
                    output = internal_path(locations(workspace)["chromium"] / "out" / lock["build"]["configuration"], workspace)
                    output.mkdir(parents=True, exist_ok=True)
                    arguments = gn_arguments(env["GN_DEFINES"])
                    write_source(internal_path(output / "args.gn", workspace), arguments, 0o644)
                    state.update(engine_mode="direct", build_targets=lock["build"]["targets"], args_sha256=digest(arguments))
                    write_marker(workspace, state)
                try:
                    run(command["argv"], Path(command["cwd"]), env)
                except (OSError, subprocess.CalledProcessError) as error:
                    # Only a returned failure is resumable. A killed process
                    # remains in-progress. Preserve upstream-applied patches
                    # and reject later edits before any retry or overlay.
                    recorded_overlay(workspace, state)
                    state.update(phase="generation-failed", generation_error=str(error),
                                 source_fingerprint=tree_fingerprint(workspace, env, state["repositories"]))
                    write_marker(workspace, state)
                    raise
                # Upstream CEF generation can apply its own source patches;
                # refuse to compile if those changed a reviewed Parc target.
                recorded_overlay(workspace, state)
                state.pop("generation_error", None)
                state.update(phase="generated", source_fingerprint=tree_fingerprint(workspace, env, state["repositories"]))
                write_marker(workspace, state)
            if operation == "generate":
                return
            command = plan["build"][-1]
            run(command["argv"], Path(command["cwd"]), env)
            state["phase"] = "built"
            write_marker(workspace, state)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "plan", "sync", "build", "generate", "shipping-plan", "shipping-generate", "shipping-build", "overlay-check", "overlay-apply", "reconfigure", "retarget", "adopt-clone"))
    parser.add_argument("--lock-file", type=Path, default=LOCK_FILE, help="Explicit reviewed source lock; defaults to the stopgap lock")
    parser.add_argument("--workspace", required=True,
                        help="Dedicated absolute path under this checkout's ignored work/ "
                             "(preferred) or outside the repo; sync claims a new directory or "
                             "resumes an owned dependency-sync failure")
    parser.add_argument("--for", dest="operation", choices=("sync", "build"), default="sync", help="Operation to inspect with check/plan")
    parser.add_argument("--symbol-level", type=int, choices=(0, 1), default=0)
    parser.add_argument("--jobs", type=int, choices=range(1, 33), default=4)
    parser.add_argument("--manifest", type=Path, help="Absolute reviewed source overlay manifest for overlay-check/apply")
    parser.add_argument("--previous-lock", type=Path,
                        help="Absolute copy of the source lock the workspace was built with, for reconfigure, retarget or adopt-clone")
    parser.add_argument("--source-workspace", type=Path, help="Idle owned source of an APFS clone")
    args = parser.parse_args(argv)
    try:
        lock, sha = load_lock(args.lock_file)
        workspace = safe_path(args.workspace)
        if args.previous_lock is not None and args.command not in {"reconfigure", "retarget", "adopt-clone"}:
            raise Refusal("--previous-lock is only accepted by reconfigure, retarget or adopt-clone")
        if args.command == "adopt-clone":
            if args.source_workspace is None or args.manifest is not None:
                raise Refusal("adopt-clone requires --source-workspace, without a manifest override")
            import engine_workspace
            try:
                print(json.dumps(engine_workspace.adopt_local_clone(args.source_workspace, workspace, REPO, args.previous_lock or args.lock_file), indent=2))
            except engine_workspace.Refusal as error:
                raise Refusal(str(error)) from error
            return 0
        if args.source_workspace is not None:
            raise Refusal("--source-workspace is only accepted by adopt-clone")
        if args.command.startswith("overlay-"):
            if args.manifest is None:
                raise Refusal("Source overlay requires --manifest")
            print(json.dumps(overlay(workspace, lock, sha, args.manifest, args.command == "overlay-apply"), indent=2))
            return 0
        if args.manifest is not None:
            raise Refusal("--manifest is only accepted by overlay-check/apply")
        if args.command in {"reconfigure", "retarget"}:
            if args.previous_lock is None:
                raise Refusal(args.command + " requires --previous-lock")
            print(json.dumps((retarget if args.command == "retarget" else reconfigure)(workspace, lock, sha, args.previous_lock), indent=2))
            return 0
        if args.command.startswith("shipping-"):
            report = host_report(workspace, lock, "build")
            state = read_marker(workspace, sha)
            if state.get("phase") not in {"generated", "built"} or state.get("symbol_level") != args.symbol_level:
                report["blockers"].append("Complete normal engine generation with the same symbol level first")
            report.update(configuration=SHIPPING_CONFIGURATION, ready=not report["blockers"],
                          source_lock_sha256=sha, commands=shipping_command_plan(workspace, args.jobs, lock),
                          environment=shipping_environment(workspace, lock, args.symbol_level),
                          scope="Non-component release in a separate output; preserves development objects; no installation or launch")
            print(json.dumps(report, indent=2))
            if args.command == "shipping-plan":
                return 0
            if report["blockers"]:
                return 2
            shipping_build(workspace, lock, sha, args.symbol_level, args.jobs,
                           generate_only=args.command == "shipping-generate")
            return 0
        operation = args.command if args.command in {"sync", "build", "generate"} else args.operation
        report = host_report(workspace, lock, "build" if operation == "generate" else operation)
        if operation == "sync" and workspace.exists():
            try:
                state = read_marker(workspace, sha)
                if state.get("phase") != "dependency-sync-failed" or state.get("symbol_level") != args.symbol_level:
                    report["blockers"].append("Only an unchanged owned dependency-sync failure can resume")
            except (Refusal, OSError, ValueError) as error:
                report["blockers"].append(str(error))
        if operation in {"build", "generate"}:
            try:
                state = read_marker(workspace, sha)
                if state.get("phase") not in {"synced", "generation-failed", "generated", "built"} or state.get("symbol_level") != args.symbol_level:
                    report["blockers"].append("Workspace is incomplete or uses a different symbol level")
            except (Refusal, OSError, ValueError) as error:
                report["blockers"].append(str(error))
        report["ready"] = not report["blockers"]
        report["source_lock_sha256"] = sha
        report["validation_scope"] = "Host/path/ownership preflight; execution also verifies pinned files and complete source fingerprint"
        if args.command == "plan":
            report["commands"] = command_plan(workspace, lock, args.jobs)[operation]
            if operation == "build" and not report["blockers"]:
                applied = recorded_overlay(workspace, state)
                if applied:
                    report["commands"][-1]["argv"].extend(applied["build_targets"])
                    report["overlay_identity"] = applied["identity"]
            report["environment"] = environment(workspace, lock, args.symbol_level)
            report["gclient_config"] = gclient_text(lock)
            report["scope"] = "Pinned upstream plus explicitly applied source overlay; no installation or launch"
        print(json.dumps(report, indent=2))
        if args.command == "plan":
            return 0
        if report["blockers"]:
            return 2
        if args.command in {"sync", "build", "generate"}:
            execute(workspace, lock, sha, operation, args.symbol_level, args.jobs)
        return 0
    except (Refusal, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"engine-source: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

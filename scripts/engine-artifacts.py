#!/usr/bin/env python3
"""Create, fetch and restore existing engine workspaces and development packages."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location("parc_" + name, Path(__file__).with_name(name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def load_pin(lock_path, kind):
    lock = json.loads(lock_path.read_text())
    if lock.get("schema_version") != 1 or lock.get("target") != "mac-arm64":
        raise ValueError("Unsupported engine artifact lock")
    pin = lock["artifacts"][kind]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", lock["repository"]):
        raise ValueError("Invalid GitHub repository")
    for key in ("manifest_sha256", "metadata_sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", pin[key]):
            raise ValueError("Invalid pinned digest")
    asset_name(pin["manifest"])
    return lock, pin


def asset_name(name):
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", name):
        raise ValueError("Invalid release asset name")
    return name


def fetch_asset(repository, asset, destination, expected):
    if destination.is_symlink():
        raise ValueError("Symlinked cached asset refused")
    if destination.exists():
        if digest(destination) != expected:
            raise ValueError("Cached asset differs from its pin: " + destination.name)
        return
    partial = destination.with_name(destination.name + ".partial")
    if partial.is_symlink():
        raise ValueError("Symlinked partial download refused")
    if partial.is_file() and partial.stat().st_size == asset["size"] and digest(partial) == expected:
        os.link(partial, destination)
        partial.unlink()
        return
    token = subprocess.check_output(["gh", "auth", "token"], text=True).strip()
    if not re.fullmatch(r"[A-Za-z0-9_]+", token):
        raise ValueError("Unexpected GitHub token format")
    url = f"https://api.github.com/repos/{repository}/releases/assets/{int(asset['id'])}"
    config = f'header = "Authorization: Bearer {token}"\nheader = "Accept: application/octet-stream"\n'
    subprocess.run(["curl", "--config", "-", "--fail", "--location", "--silent", "--show-error",
                    "--proto", "=https", "--proto-redir", "=https",
                    "--retry", "3", "--continue-at", "-", "--output", str(partial), url],
                   input=config, text=True, check=True)
    if digest(partial) != expected or partial.stat().st_size != asset["size"]:
        raise ValueError("Downloaded asset digest/size mismatch: " + destination.name)
    os.link(partial, destination)
    partial.unlink()


def fetch(lock_path, kind, cache):
    lock, pin = load_pin(lock_path, kind)
    pkg = module("build")
    cache = pkg.explicit_path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    guard = cache / ".fetch.lock"
    if guard.is_symlink():
        raise ValueError("Symlinked cache lock refused")
    with guard.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        from urllib.parse import quote
        endpoint = f"repos/{lock['repository']}/releases/tags/{quote(lock['release'], safe='')}"
        release = json.loads(subprocess.check_output(["gh", "api", endpoint], text=True))
        assets = {item["name"]: item for item in release["assets"]}
        def download(name, sha):
            name = asset_name(name)
            fetch_asset(lock["repository"], assets[name], cache / name, sha)
        download(pin["manifest"], pin["manifest_sha256"])
        manifest_path = cache / pin["manifest"]
        manifest = json.loads(manifest_path.read_text())
        for item in [manifest["inventory"], *manifest["parts"]]:
            download(item["name"], item["sha256"])
        module("artifact_archive").verify_archive(manifest_path)
    return manifest_path


def trusted_manifest(lock_path, kind, cache):
    _, pin = load_pin(lock_path, kind)
    path = cache / pin["manifest"]
    if path.is_symlink() or digest(path) != pin["manifest_sha256"]:
        raise ValueError("Archive manifest differs from trusted artifact lock")
    return path, pin


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("create-package", "create-workspace"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--output", type=Path, required=True, help="Existing output directory; asset names must be new")
        cmd.add_argument("--name", default=name.removeprefix("create-"))
        cmd.add_argument("--part-size", type=int, default=2_000_000_000)
        if name == "create-package":
            cmd.add_argument("--package-dir", type=Path, required=True)
        else:
            cmd.add_argument("--workspace", type=Path, required=True)
    for name in ("fetch", "verify", "restore"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--lock", type=Path, default=ROOT / "Engine/engine-artifacts.json")
        cmd.add_argument("--kind", choices=("package", "workspace"), required=True)
        cmd.add_argument("--cache", type=Path, required=True)
        if name == "restore":
            cmd.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        archive = module("artifact_archive")
        pkg = module("build")
        if args.command == "create-package":
            package = pkg.explicit_path(args.package_dir)
            report = package / "package-report.json"
            if not (package / "Parc.app").is_dir() or not report.is_file():
                raise ValueError("Expected a complete development package with Parc.app and package-report.json")
            metadata = {"schema_version": 1, "kind": "parc-development-package", "original_path": str(package),
                        "package_report_sha256": digest(report),
                        "scope": "Existing package snapshot; no new build, signing or runtime acceptance"}
            result = archive.create_archive(package, args.output, args.name,
                extra_files={".parc-package-snapshot.json": encoded(metadata)},
                replace_extra_files=True, part_size=args.part_size)
            if digest(report) != metadata["package_report_sha256"]:
                raise ValueError("Package report changed during capture")
            print(json.dumps({"archive": result, "metadata_sha256": hashlib.sha256(encoded(metadata)).hexdigest()}, indent=2))
        elif args.command == "create-workspace":
            workspace_module = module("engine_workspace")
            workspace = pkg.explicit_path(args.workspace)
            with workspace_module.workspace_guard(workspace):
                metadata = workspace_module.snapshot_metadata(workspace, ROOT)
                result = archive.create_archive(workspace, args.output, args.name,
                    extra_files={".parc-workspace-snapshot.json": workspace_module.canonical_json(metadata)},
                    excludes=metadata["archive_excludes"], symlink_rewrites=metadata["symlink_rewrites"],
                    replace_extra_files=True,
                    part_size=args.part_size)
                if workspace_module.snapshot_metadata(workspace, ROOT) != metadata:
                    raise ValueError("Workspace changed while creating snapshot")
            print(json.dumps({"archive": result, "metadata_sha256": hashlib.sha256(workspace_module.canonical_json(metadata)).hexdigest()}, indent=2))
        else:
            if args.command == "fetch":
                print(fetch(args.lock, args.kind, args.cache))
                return 0
            manifest_path, pin = trusted_manifest(args.lock, args.kind, args.cache)
            if args.command == "verify":
                archive.verify_archive(manifest_path)
                print("Verified pinned " + args.kind + " archive")
                return 0
            destination = pkg.explicit_path(args.destination)
            def finish_restore(stage, final):
                if args.kind == "package":
                    metadata_path = stage / ".parc-package-snapshot.json"
                    if digest(metadata_path) != pin["metadata_sha256"]:
                        raise ValueError("Package metadata differs from trusted artifact lock")
                    metadata = json.loads(metadata_path.read_text())
                    if (metadata.get("kind") != "parc-development-package" or
                            metadata.get("schema_version") != 1 or
                            digest(stage / "package-report.json") != metadata["package_report_sha256"] or
                            not (stage / "Parc.app").is_dir()):
                        raise ValueError("Package contents differ from their captured report")
                else:
                    metadata_path = stage / ".parc-workspace-snapshot.json"
                    if digest(metadata_path) != pin["metadata_sha256"]:
                        raise ValueError("Workspace metadata differs from trusted artifact lock")
                    metadata = json.loads(metadata_path.read_text())
                    report = module("engine_workspace").adopt_workspace(stage, metadata,
                        verified_archive_sha256=digest(manifest_path), expected_archive_sha256=pin["manifest_sha256"],
                        expected_metadata_sha256=pin["metadata_sha256"], destination=final, repo=ROOT)
                    print(json.dumps(report, indent=2))
            archive.extract_archive(manifest_path, destination, post_extract=finish_restore)
            print(destination)
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print("Engine artifact operation refused: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

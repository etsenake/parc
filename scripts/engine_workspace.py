"""Authenticated workspace snapshot metadata and conservative relocation.

This module never builds an engine or adopts an arbitrary existing directory.
The artifact CLI authenticates and extracts an archive into private staging, then
calls adopt_workspace before publishing it. Local clone adoption instead proves
the copy against an idle owned source. Only receipts and proven generated links
are rewritten;
GN regeneration is mandatory, and cached source/object mtimes remain intact.
"""
from __future__ import annotations

from contextlib import contextmanager, nullcontext
import copy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess

REPO = Path(__file__).resolve().parents[1]
SNAPSHOT_FILE = ".parc-workspace-snapshot.json"
SCHEMA_VERSION = 1
COMPLETE_PHASES = {"synced", "generation-failed", "generated", "built"}
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


class Refusal(RuntimeError):
    pass


def canonical_json(value: dict) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _file_sha(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(data)
    return result.hexdigest()


def _engine(repo: Path):
    # Load trusted code beside this module, even when validating a fixture repo.
    spec = importlib.util.spec_from_file_location("parc_snapshot_engine_source", Path(__file__).with_name("engine-source.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.REPO = repo.resolve()
    module.GIT += ["-c", "core.fsmonitor=false"]
    return module


def _read(path: Path) -> tuple[dict, str]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise Refusal(f"Expected ordinary bounded JSON file: {path}")
    raw = path.read_bytes()
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise Refusal(f"Invalid JSON: {path}") from error
    if not isinstance(value, dict):
        raise Refusal(f"Expected JSON object: {path}")
    return value, _sha(raw)


def _relative(value: str) -> Path:
    if not isinstance(value, str):
        raise Refusal(f"Invalid workspace-relative path: {value!r}")
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts or str(path) != value:
        raise Refusal(f"Invalid workspace-relative path: {value!r}")
    return path


@contextmanager
def workspace_guard(workspace: Path):
    """Hold this across metadata creation AND archive capture, without waiting."""
    engine = _engine(REPO)
    path = engine.internal_path(Path(workspace) / ".parc-operation.lock", Path(workspace))
    with path.open("rb") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Another operation is using this workspace") from error
        yield


def _receipt(engine, workspace: Path, lock: dict, lock_sha: str) -> tuple[dict, str]:
    state, receipt_sha = _read(workspace / engine.MARKER)
    if (state.get("schema_version") != 1 or state.get("lock_sha256") != lock_sha
            or state.get("phase") not in COMPLETE_PHASES
            or type(state.get("symbol_level")) is not int
            or state["symbol_level"] not in lock["build"]["symbol_levels"]
            or not SHA256.fullmatch(str(state.get("source_fingerprint", "")))):
        raise Refusal("Snapshot requires a complete source receipt with matching lock and fingerprint")
    roots = state.get("repositories")
    if (not isinstance(roots, list) or not roots or len(roots) != len(set(roots))
            or "chromium/src" not in roots):
        raise Refusal("Invalid source repository inventory")
    for value in roots:
        _relative(value)
    return state, receipt_sha


def _validate_baseline(engine, workspace: Path, repo: Path, lock: dict, state: dict, *, verify_overlay_inputs: bool = True) -> None:
    env = engine.environment(workspace, lock, state["symbol_level"])
    env["GIT_OPTIONAL_LOCKS"] = "0"  # Do not refresh indexes during verification.
    # Refuse Git metadata that would make an apparently complete snapshot rely
    # on an external object store or worktree. No Git commands run before this.
    for relative in ["depot_tools", *state["repositories"]]:
        git = engine.internal_path(workspace / relative / ".git", workspace)
        if not git.is_dir():
            raise Refusal(f"Expected complete ordinary Git checkout: {relative}")
        for name in ("commondir", "objects/info/alternates", "objects/info/http-alternates"):
            path = engine.internal_path(git / name, workspace)
            if path.exists() and path.read_bytes().strip():
                raise Refusal(f"External Git storage is not portable: {relative}/.git/{name}")
        # A transplanted core.worktree could make Git verify the old checkout
        # while we adopt different source bytes. Includes can hide that setting.
        config = engine.run(engine.GIT + ["config", "--local", "--no-includes", "--null", "--list"], git.parent, env, True)
        for entry in config.split(b"\0"):
            key, _, value = entry.partition(b"\n")
            key = key.lower()
            if (key in {b"core.worktree", b"extensions.worktreeconfig", b"include.path"}
                    or key.startswith(b"includeif.") or key == b"core.bare" and value.lower() != b"false"):
                raise Refusal(f"External Git configuration is not portable: {relative}: {key.decode(errors='replace')}")
    engine.verify_workspace(workspace, lock, state, env)
    if not verify_overlay_inputs:
        return
    manifest = repo / "Engine/ParcHost/overlay.json"
    expected = _sha(manifest.read_bytes())
    if state.get("overlay", {}).get("identity") != expected:
        raise Refusal("Snapshot overlay is stale for this repository")
    record, _ = engine.prepare_overlay(workspace, lock, state, manifest)
    if record != engine.recorded_overlay(workspace, state):
        raise Refusal("Snapshot overlay proof differs from repository inputs")


def _ignored_source_link(engine, workspace: Path, state: dict, path: Path, lock: dict) -> bool:
    roots = [workspace / "depot_tools", *(workspace / item for item in state["repositories"])]
    owners = [root for root in roots if root in path.parents]
    if not owners:
        return True  # Workspace metadata, never included in the Git fingerprint.
    owner = max(owners, key=lambda root: len(root.parts))
    relative = str(path.relative_to(owner))
    if ".git" in Path(relative).parts:
        return False
    env = engine.environment(workspace, lock, state["symbol_level"])
    tracked = engine.run(engine.GIT + ["ls-files", "--", relative], owner, env, True)
    if tracked:
        return False
    result = subprocess.run(engine.GIT + ["check-ignore", "-q", "--", relative], cwd=owner, env=env)
    if result.returncode not in (0, 1):
        raise Refusal(f"Cannot check source ownership for link: {path}")
    return result.returncode == 0


def _generated_external(relative: Path) -> bool:
    parts = relative.parts
    if len(parts) < 5 or parts[:3] != ("chromium", "src", "out"):
        return False
    rest = parts[4:]
    return (len(rest) == 1 and re.fullmatch(r"siso(?:\.[0-9]+)?\.(INFO|WARNING|ERROR|FATAL)", rest[0]) is not None
            or len(rest) == 3 and rest[:2] == ("sdk", "xcode_links")
            and (rest[2] in {"MacOSX.platform", "XcodeDefault.xctoolchain"}
                 or re.fullmatch(r"MacOSX[0-9.]*\.sdk", rest[2]) is not None))


def _links(engine, workspace: Path, state: dict, lock: dict, *, restored: bool = False) -> dict:
    rewrites, excluded = {}, []
    for base, dirs, files in os.walk(workspace, followlinks=False):
        for name in sorted([*dirs, *files]):
            path = Path(base) / name
            if not path.is_symlink():
                continue
            target = os.readlink(path)
            relative = path.relative_to(workspace)
            # Resolve the entire chain, not only its first hop; dangling
            # internal links are allowed but cycles and escaping chains are not.
            try:
                resolved = path.resolve()
            except (RuntimeError, OSError) as error:
                raise Refusal(f"Unresolvable symlink: {relative}") from error
            internal = resolved == workspace or workspace in resolved.parents
            if restored:
                if os.path.isabs(target) or not internal:
                    raise Refusal(f"Restored snapshot has a nonportable symlink: {relative}")
                continue
            if not internal:
                if not _generated_external(relative) or not _ignored_source_link(engine, workspace, state, path, lock):
                    raise Refusal(f"Unrepresented external symlink: {relative} -> {target}")
                excluded.append({"path": str(relative), "target": target, "reason": "regenerated SDK link or transient build diagnostic"})
            elif os.path.isabs(target):
                if not _ignored_source_link(engine, workspace, state, path, lock):
                    raise Refusal(f"Absolute source symlink changes the baseline fingerprint: {relative}")
                rewrites[str(relative)] = os.path.relpath(resolved, path.parent)
    return {"symlink_rewrites": rewrites, "external_dependencies": excluded,
            "archive_excludes": [item["path"] for item in excluded]}


def _toolchain(workspace: Path, engine) -> dict:
    # These hashes identify the bundled compiler and generated graph inputs.
    # They are provenance, not evidence that old objects are reusable on a new host.
    names = ["chromium/src/third_party/llvm-build/Release+Asserts/bin/clang",
             "chromium/src/third_party/llvm-build/Release+Asserts/cr_build_revision",
             "chromium/src/third_party/rust-toolchain/bin/rustc",
             "chromium/src/third_party/siso/cipd/siso"]
    out = workspace / "chromium/src/out"
    if out.is_dir() and not out.is_symlink():
        for config in sorted(out.iterdir()):
            if config.is_dir() and not config.is_symlink():
                names.extend(str((config / name).relative_to(workspace)) for name in ("args.gn", "build.ninja", "toolchain.ninja"))
    files = {}
    for name in names:
        path = engine.internal_path(workspace / name, workspace)
        if path.is_file():
            files[name] = _file_sha(path)
    external = {}
    if platform.system() == "Darwin":
        selection = subprocess.run(["/usr/bin/xcode-select", "-p"], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, check=False)
        if selection.returncode == 0:
            developer = Path(selection.stdout.strip())
            external["developer_dir"] = str(developer)
            version = developer.parent / "version.plist"
            if version.is_file():
                external["version_plist_sha256"] = _file_sha(version)
                external["version"] = plistlib.loads(version.read_bytes())
            settings = developer / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.json"
            if settings.is_file():
                external["sdk_settings_sha256"] = _file_sha(settings)
    return {"system": platform.system(), "machine": platform.machine(),
            "macos_version": platform.mac_ver()[0], "files": files,
            "external_xcode": external}


def snapshot_metadata(workspace: Path, repo: Path = REPO, *, lock_path: Path | None = None,
                      verify_overlay_inputs: bool = True) -> dict:
    """Read and validate a frozen owned workspace; caller holds workspace_guard."""
    engine = _engine(repo)
    try:
        workspace = engine.safe_path(str(workspace), repo)
        lock, lock_sha = engine.load_lock(lock_path or repo / "Engine/source-lock.json")
        state, receipt_sha = _receipt(engine, workspace, lock, lock_sha)
        if state.get("workspace") != str(workspace):
            raise Refusal("Snapshot receipt names a different original workspace")
        _validate_baseline(engine, workspace, repo, lock, state, verify_overlay_inputs=verify_overlay_inputs)
        metadata = {"schema_version": SCHEMA_VERSION, "kind": "parc-engine-workspace",
                    "original_workspace": str(workspace), "source_receipt": state,
                    "source_receipt_sha256": receipt_sha, "source_lock_sha256": lock_sha,
                    "requires_regeneration": True, "toolchain": _toolchain(workspace, engine)}
        metadata.update(_links(engine, workspace, state, lock))
        shipping = workspace / engine.SHIPPING_MARKER
        if shipping.exists() or shipping.is_symlink():
            receipt, receipt_sha = _read(shipping)
            if receipt.get("workspace") != str(workspace) or receipt.get("schema_version") != 1 or receipt.get("lock_sha256") != lock_sha:
                raise Refusal("Shipping receipt ownership differs from snapshot")
            metadata["shipping_receipt"] = receipt
            metadata["shipping_receipt_sha256"] = receipt_sha
        return metadata
    except engine.Refusal as error:
        raise Refusal(str(error)) from error


def adopt_workspace(extracted_root: Path, metadata: dict, *, verified_archive_sha256: str,
                    expected_archive_sha256: str, expected_metadata_sha256: str,
                    destination: Path | None = None, repo: Path = REPO) -> dict:
    """Adopt authenticated private staging before archive publication.

    The caller must authenticate the archive manifest against its trusted lock,
    verify all archive parts/inventory, and pass the snapshot entry's digest from
    that authenticated inventory. Passing equal unauthenticated strings does not
    authenticate an archive. This is deliberately not exposed as an adoption CLI.
    """
    if (not isinstance(verified_archive_sha256, str) or not SHA256.fullmatch(verified_archive_sha256)
            or verified_archive_sha256 != expected_archive_sha256
            or not isinstance(expected_metadata_sha256, str) or not SHA256.fullmatch(expected_metadata_sha256)):
        raise Refusal("Authenticated archive and metadata digests are required for adoption")
    return _adopt_workspace(extracted_root, metadata,
                            expected_metadata_sha256=expected_metadata_sha256,
                            provenance={"archive_sha256": verified_archive_sha256},
                            destination=destination, repo=repo)


def _adopt_workspace(extracted_root: Path, metadata: dict, *, expected_metadata_sha256: str,
                     provenance: dict, destination: Path | None = None, repo: Path = REPO,
                     source_lock: tuple | None = None, already_guarded: bool = False,
                     local_source: Path | None = None) -> dict:
    engine = _engine(repo)
    try:
        root = engine.safe_path(str(extracted_root), repo)
        final = engine.safe_path(str(destination or root), repo)
        if final != root and final.exists():
            raise Refusal("Adoption destination must not already exist")
        actual_metadata, metadata_sha = (_read(root / SNAPSHOT_FILE) if local_source is None
                                         else (metadata, _sha(canonical_json(metadata))))
        if actual_metadata != metadata or metadata_sha != expected_metadata_sha256:
            raise Refusal("Snapshot metadata is not bound to the authenticated archive inventory")
        if (metadata.get("schema_version") != SCHEMA_VERSION or metadata.get("kind") != "parc-engine-workspace"
                or metadata.get("requires_regeneration") is not True):
            raise Refusal("Unsupported workspace snapshot metadata")
        lock, lock_sha = source_lock or engine.load_lock(repo / "Engine/source-lock.json")
        with (nullcontext() if already_guarded else workspace_guard(root)):
            state, receipt_sha = _receipt(engine, root, lock, lock_sha)
            original = metadata.get("original_workspace")
            if (not isinstance(original, str) or not Path(original).is_absolute()
                    or ".." in Path(original).parts or state.get("workspace") != original
                    or state != metadata.get("source_receipt")
                    or receipt_sha != metadata.get("source_receipt_sha256")
                    or lock_sha != metadata.get("source_lock_sha256")):
                raise Refusal("Original workspace ownership/source receipt proof does not match")
            if local_source is None:
                _links(engine, root, state, lock, restored=True)
                for value in metadata.get("archive_excludes", []):
                    path = root / _relative(value)
                    if not _generated_external(Path(value)) or path.exists() or path.is_symlink():
                        raise Refusal("Excluded generated dependency was unexpectedly restored")
                for value, target in metadata.get("symlink_rewrites", {}).items():
                    path = root / _relative(value)
                    if not path.is_symlink() or os.readlink(path) != target:
                        raise Refusal("Normalized symlink differs from snapshot metadata")
            for value, expected in metadata.get("toolchain", {}).get("files", {}).items():
                path = engine.internal_path(root / _relative(value), root)
                if not isinstance(expected, str) or not SHA256.fullmatch(expected) or _file_sha(path) != expected:
                    raise Refusal(f"Toolchain/graph fingerprint changed: {value}")
            _validate_baseline(engine, root, repo, lock, state, verify_overlay_inputs=source_lock is None)
            shipping_path = root / engine.SHIPPING_MARKER
            shipping = None
            if metadata.get("shipping_receipt") is not None:
                shipping, shipping_sha = _read(shipping_path)
                if shipping != metadata["shipping_receipt"] or shipping_sha != metadata.get("shipping_receipt_sha256") or shipping.get("workspace") != original:
                    raise Refusal("Shipping receipt proof does not match")
            elif shipping_path.exists() or shipping_path.is_symlink():
                raise Refusal("Unrepresented shipping receipt in snapshot")
            if local_source is not None:
                for value, target in metadata["symlink_rewrites"].items():
                    path = root / value
                    path.unlink()
                    path.symlink_to(target)
                for value in metadata["archive_excludes"]:
                    (root / value).unlink()
                _links(engine, root, state, lock, restored=True)
            # All proofs pass before ownership changes. Invalidate shipping first:
            # interruption cannot leave a built shipping receipt at the new path.
            provenance = {**provenance, "original_workspace": original,
                          "snapshot_sha256": metadata_sha, "requires_regeneration": True}
            if shipping is not None:
                shipping = copy.deepcopy(shipping)
                shipping["relocation"] = dict(provenance, original_phase=shipping.get("phase"))
                shipping.update(workspace=str(final), phase="generation-failed",
                                error="Restored snapshot requires GN regeneration on this host")
                engine.write_marker(root, shipping, engine.SHIPPING_MARKER)
            adopted = copy.deepcopy(state)
            adopted["relocation"] = dict(provenance, original_phase=state["phase"])
            adopted.update(workspace=str(final), phase="synced")
            adopted.pop("generation_error", None)
            engine.write_marker(root, adopted)
            return {"workspace": str(final), "original_workspace": original,
                    "original_phase": state["phase"], "phase": "synced", "requires_regeneration": True,
                    "source_fingerprint": state["source_fingerprint"],
                    "external_dependencies": metadata.get("external_dependencies", []),
                    "next_step": "Regenerate the build graph explicitly before resuming compilation; no build was started"}
    except engine.Refusal as error:
        raise Refusal(str(error)) from error


def adopt_local_clone(source: Path, clone: Path, repo: Path = REPO,
                      previous_lock: Path | None = None) -> dict:
    """Adopt only a verified local copy of an idle owned workspace."""
    engine = _engine(repo)
    try:
        source = engine.safe_path(str(source), repo)
        clone = engine.safe_path(str(clone), repo)
        if (source == clone or source in clone.parents or clone in source.parents
                or len(source.parts) != len(clone.parts)
                or source.stat().st_dev != clone.stat().st_dev):
            raise Refusal("Clone must be a separate path at the same depth on the same volume")
        if previous_lock is not None and (not previous_lock.is_absolute()
                or ".." in previous_lock.parts
                or any(p.is_symlink() for p in [previous_lock, *previous_lock.parents])):
            raise Refusal("Previous source lock must be an absolute non-symlink path")
        lock_path = previous_lock or repo / "Engine/source-lock.json"
        lock, lock_sha = engine.load_lock(lock_path)
        with workspace_guard(source), workspace_guard(clone):
            metadata = snapshot_metadata(source, repo, lock_path=lock_path, verify_overlay_inputs=False)
            state, receipt_sha = _receipt(engine, clone, lock, lock_sha)
            if state != metadata["source_receipt"] or receipt_sha != metadata["source_receipt_sha256"]:
                raise Refusal("Clone receipt does not match the idle source")
            _validate_baseline(engine, clone, repo, lock, state, verify_overlay_inputs=False)
            def link_inventory(root):
                return {str((Path(base) / name).relative_to(root)): os.readlink(Path(base) / name)
                        for base, dirs, files in os.walk(root, followlinks=False)
                        for name in [*dirs, *files] if (Path(base) / name).is_symlink()}
            if link_inventory(source) != link_inventory(clone):
                raise Refusal("Clone symlink inventory differs from source")
            snapshot = engine.internal_path(clone / SNAPSHOT_FILE, clone)
            original_snapshot = engine.internal_path(source / SNAPSHOT_FILE, source)
            if snapshot.exists() or original_snapshot.exists():
                if not snapshot.is_file() or not original_snapshot.is_file() or snapshot.read_bytes() != original_snapshot.read_bytes():
                    raise Refusal("Inherited clone snapshot metadata differs from source")
            return _adopt_workspace(clone, metadata,
                                    expected_metadata_sha256=_sha(canonical_json(metadata)),
                                    provenance={"kind": "local-clone", "source_receipt_sha256": receipt_sha},
                                    source_lock=(lock, lock_sha), already_guarded=True, local_source=source, repo=repo)
    except engine.Refusal as error:
        raise Refusal(str(error)) from error

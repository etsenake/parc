#!/usr/bin/env python3
"""Export committed Chromium changes and prove overlay equivalence, offline.

Only Git object reads and temporary fixture writes are used. This is not an
engine workspace operation and is deliberately separate from release tooling.
"""
from __future__ import annotations

import argparse
import difflib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

_spec = importlib.util.spec_from_file_location("engine_source", Path(__file__).with_name("engine-source.py"))
engine = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(engine)
Refusal = engine.Refusal


def git(repository: Path, *args: str) -> bytes:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0")
    return subprocess.run(["git", "--no-replace-objects", "-C", str(repository), *args],
                          check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          env=env).stdout


class Branch:
    def __init__(self, repository: Path, base: str, branch: str):
        self.repository = repository.resolve()
        top = git(self.repository, "rev-parse", "--show-toplevel").decode().strip()
        if Path(top).resolve() != self.repository:
            raise Refusal(f"Expected repository root: {repository}")
        self.base = self.resolve(base)
        self.branch = self.resolve(branch)
        git(self.repository, "merge-base", "--is-ancestor", self.base, self.branch)
        self.before = self.inventory(self.base)
        self.after = self.inventory(self.branch)

    def resolve(self, ref: str) -> str:
        return git(self.repository, "rev-parse", "--verify", "--end-of-options",
                   ref + "^{commit}").decode().strip()

    def inventory(self, commit: str) -> dict:
        result = {}
        for entry in git(self.repository, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
            if entry:
                header, path = entry.split(b"\t", 1)
                mode, kind, oid = header.decode().split()
                result[path.decode("utf-8")] = (mode, kind, oid)
        return result

    def read(self, path: str, after: bool = False) -> tuple[bytes, int] | None:
        entry = (self.after if after else self.before).get(path)
        if entry is None:
            return None
        mode, kind, oid = entry
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise Refusal(f"Unsupported Git object/mode: {path}")
        size = int(git(self.repository, "cat-file", "-s", oid))
        if size > 8 * 1024 * 1024:
            raise Refusal(f"Source exceeds overlay size limit: {path}")
        data = git(self.repository, "cat-file", "blob", oid)
        data.decode("utf-8")
        if b"\0" in data:
            raise Refusal(f"Binary source refused: {path}")
        return data, int(mode[-3:], 8)


def targets(spec: dict) -> set[str]:
    return {f["target"] for f in spec.get("files", [])} | {
        f["target"] for p in spec.get("patches", []) for f in p["files"]}


def contextual_diff(target: str, before: bytes, after: bytes) -> bytes:
    lines = difflib.unified_diff(before.decode().splitlines(True), after.decode().splitlines(True),
                                 fromfile="a/" + target, tofile="b/" + target,
                                 n=3)
    parts = []
    for line in lines:
        parts.append(line if line.endswith("\n") else line + "\n\\ No newline at end of file\n")
    data = "".join(parts).encode()
    if engine.apply_context_patch(data.decode(), {target: before}) != {target: after}:
        raise Refusal(f"Patch did not reproduce branch bytes: {target}")
    return data


def export(manifest: Path, lock: dict, branches: dict[str, Branch], output: Path) -> dict:
    if "" not in branches or branches[""].base != lock["chromium"]["commit"]:
        raise Refusal("Chromium branch base must equal the pinned source-lock commit")
    for prefix in branches:
        if prefix:
            engine.relative_source(prefix)
    for prefix, branch in branches.items():
        if not prefix:
            continue
        for parent_prefix, parent in branches.items():
            name = prefix[len(parent_prefix) + 1:] if parent_prefix else prefix
            if parent_prefix and not prefix.startswith(parent_prefix + "/"):
                continue
            entry = parent.before.get(name)
            if entry and entry[0] == "160000" and entry[2] != branch.base:
                raise Refusal(f"Dependency base differs from pinned gitlink: {prefix}")
    prefixes = sorted(branches, key=len, reverse=True)

    def locate(target):
        for prefix in prefixes:
            if not prefix or target.startswith(prefix + "/"):
                return branches[prefix], target[len(prefix) + 1:] if prefix else target
        raise Refusal(f"No branch for target: {target}")

    manifest_bytes = engine.text_bytes(manifest)
    spec = json.loads(manifest_bytes)
    changed = set()
    for prefix, branch in branches.items():
        for name in set(branch.before) | set(branch.after):
            target = prefix + "/" + name if prefix else name
            if locate(target)[0] is not branch:
                raise Refusal(f"Overlapping branch trees: {target}")
            if branch.before.get(name) != branch.after.get(name):
                changed.add(target)
    relevant = changed | targets(spec)
    before = {}
    after = {}
    with tempfile.TemporaryDirectory(prefix="parc-export-") as temporary:
        work = Path(temporary).resolve()
        for target in sorted(relevant):
            path = engine.target_path(work, target, lock)
            branch, name = locate(target)
            before[target] = branch.read(name)
            after[target] = branch.read(name, True)
            if before[target] is not None:
                data, mode = before[target]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                path.chmod(mode)
        current_record, current_writes = engine.prepare_overlay(work, lock, {}, manifest)
        if current_record["identity"] != engine.digest(manifest_bytes):
            raise Refusal("Manifest changed during export")
        for target in sorted(relevant):
            expected = ((current_writes[target], current_record["targets"][target]["mode"])
                        if target in current_writes else before[target])
            if after[target] != expected:
                raise Refusal(f"Branch differs from current overlay bytes/mode: {target}")
        candidate = {key: spec[key] for key in ("schema_version", "id", "version", "upstream")}
        candidate.update(source_root="manifest", files=[], patches=[])
        if "build_targets" in spec:
            candidate["build_targets"] = spec["build_targets"]
        inputs = {}
        for target in sorted(changed):
            original, result = before[target], after[target]
            if result is None:
                raise Refusal(f"Overlay cannot delete source: {target}")
            data, mode = result
            if original is None:
                if mode != 0o644:
                    raise Refusal(f"Owned additions require mode 0644: {target}")
                source = "owned/" + target
                inputs[source] = data
                candidate["files"].append(dict(source=source, target=target, sha256=engine.digest(data)))
            else:
                if mode != original[1]:
                    raise Refusal(f"Overlay cannot change source mode: {target}")
                source = "patches/" + target + ".patch"
                inputs[source] = contextual_diff(target, original[0], data)
                candidate["patches"].append(dict(source=source, sha256=engine.digest(inputs[source]), files=[
                    dict(target=target, before_sha256=engine.digest(original[0]), after_sha256=engine.digest(data))]))
        candidate_root = work / "candidate"
        candidate_root.mkdir()
        for source, data in inputs.items():
            path = candidate_root / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        raw = (json.dumps(candidate, indent=2) + "\n").encode()
        candidate_manifest = candidate_root / "overlay.json"
        candidate_manifest.write_bytes(raw)
        record, writes = engine.prepare_overlay(work, lock, {}, candidate_manifest)
        for target in sorted(relevant):
            result = ((writes[target], record["targets"][target]["mode"])
                      if target in writes else before[target])
            if result != after[target]:
                raise Refusal(f"Export differs from branch bytes/mode: {target}")
        if not output.is_absolute() or ".." in output.parts or any(p.is_symlink() for p in [output, *output.parents]):
            raise Refusal("Output must be an absolute non-symlink path")
        for branch in branches.values():
            root = branch.repository.resolve()
            if root.exists() and any(parent.exists() and parent.samefile(root) for parent in output.parents):
                raise Refusal("Output must be separate from branch repositories")
            folded_output, folded_root = str(output).casefold(), str(root).casefold()
            if (folded_output == folded_root or folded_output.startswith(folded_root + "/")
                    or folded_root.startswith(folded_output + "/")):
                raise Refusal("Output must be separate from branch repositories")
        with tempfile.TemporaryDirectory(prefix=".parc-export-", dir=output.parent) as staging:
            stage = Path(staging)
            for source, data in {**inputs, "overlay.json": raw}.items():
                path = stage / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                path.chmod(0o644)
            output.mkdir()
            try:
                os.replace(stage, output)
            except OSError:
                output.rmdir()
                raise
    return dict(equivalent=True, targets=len(relevant), changed=len(changed),
                manifest=str(output / "overlay.json"))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=engine.LOCK_FILE)
    parser.add_argument("--dependency", action="append", default=[], metavar="PREFIX=BASE..BRANCH",
                        help="Explicit committed dependency trees beneath --repository")
    args = parser.parse_args(argv)
    try:
        lock, _ = engine.load_lock(args.lock)
        branches = {"": Branch(args.repository, lock["chromium"]["commit"], args.branch)}
        for value in args.dependency:
            prefix, refs = value.split("=", 1)
            engine.relative_source(prefix)
            base, branch = refs.split("..", 1)
            if prefix in branches:
                raise Refusal(f"Duplicate dependency: {prefix}")
            branches[prefix] = Branch(args.repository / prefix, base, branch)
        print(json.dumps(export(args.manifest, lock, branches, args.output), indent=2))
        return 0
    except (Refusal, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Export refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

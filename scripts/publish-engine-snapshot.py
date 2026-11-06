#!/usr/bin/env python3
"""Finish an engine snapshot without an agent. Re-run the same config to resume."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import artifact_archive


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def run(args, **kwargs):
    return subprocess.check_output([str(x) for x in args], **kwargs).decode().strip()


def write(path, value):
    path = Path(path)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(value, indent=2) + "\n")
    os.replace(temp, path)


def github_preflight(cfg):
    """Validate the inherited login; recover only invalid token overrides."""
    command = ["gh", "api", f"repos/{cfg['repository']}/releases/tags/{cfg['release']}"]
    def probe(env):
        return subprocess.run(command, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True)
    result = probe(os.environ.copy())
    if result.returncode == 0:
        return
    overridden = [name for name in ("GH_TOKEN", "GITHUB_TOKEN") if os.environ.get(name)]
    if overridden and "HTTP 401" in result.stderr:
        stored_login = os.environ.copy()
        for name in ("GH_TOKEN", "GITHUB_TOKEN"):
            stored_login.pop(name, None)
        fallback = probe(stored_login)
        if fallback.returncode == 0:
            for name in ("GH_TOKEN", "GITHUB_TOKEN"):
                os.environ.pop(name, None)
            print("Ignoring invalid token environment override; using the saved GitHub login.", flush=True)
            return
        result = fallback
    detail = result.stderr.strip() or f"GitHub CLI exited {result.returncode}"
    raise RuntimeError("GitHub preflight failed: " + detail +
                       "\nNo background job was started. Check `gh auth status`; "
                       "if login is required, run `gh auth login --hostname github.com --web`.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--background", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--check", action="store_true", help="Check GitHub access without starting capture or upload")
    args = parser.parse_args()
    config_path = args.config.resolve(strict=True)
    cfg = json.loads(config_path.read_text())
    state_path = config_path.with_name("publisher-state.json")
    log_path = config_path.with_name("publisher.log")
    if args.status:
        print(state_path.read_text() if state_path.exists() else "Not started")
        print("Log:", log_path)
        return
    github_preflight(cfg)
    if args.check:
        print("GitHub release access verified. No capture or upload started.")
        return
    if args.background:
        with log_path.open("a") as log:
            child = subprocess.Popen([sys.executable, "-u", __file__, "--config", str(config_path)],
                                     stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     start_new_session=True)
        # Catch an immediate launch failure instead of reporting it as running.
        try:
            code = child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        else:
            if code:
                raise RuntimeError(f"Publisher exited during startup; read {log_path}")
            print(f"Publisher exited normally; check status and {log_path}")
            return
        print(f"Started PID {child.pid}; log: {log_path}")
        return
    guard = config_path.with_name("publisher.lock").open("a")
    try:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("Already running; use --status")
        return
    assets = Path(cfg["assets"]).resolve()
    assets.mkdir(parents=True, exist_ok=True)
    repository, tag = cfg["repository"], cfg["release"]
    state = {"pid": os.getpid(), "release": tag, "started": time.time(), "uploaded": []}

    def report(message, **extra):
        state.update(stage=message, updated=time.time(), **extra)
        write(state_path, state)
        print(time.strftime("%H:%M:%S"), message, flush=True)

    def upload_command(path):
        started = time.monotonic()
        command = ["gh", "release", "upload", tag, str(path), "--repo", repository]
        process = subprocess.Popen(command)
        while True:
            try:
                code = process.wait(timeout=15)
                if code:
                    raise subprocess.CalledProcessError(code, command)
                return
            except subprocess.TimeoutExpired:
                report(f"Uploading {path.name}: {time.monotonic() - started:.0f}s elapsed")

    def remote():
        return json.loads(run(["gh", "api", f"repos/{repository}/releases/tags/{tag}"]))

    def upload(path):
        if not path.exists() and (assets / path.name).exists():
            path = assets / path.name
        digest = "sha256:" + sha(path)
        release = remote()
        found = next((x for x in release["assets"] if x["name"] == path.name), None)
        if found:
            if found.get("digest") == digest and found["size"] == path.stat().st_size:
                report("Already uploaded: " + path.name)
                return
            # Only an unfinished workspace upload may be replaced. Completed
            # snapshots and the original application package are immutable.
            finalized = any(x["name"] == "engine-workspace.manifest.json" for x in release["assets"])
            if finalized or not path.name.startswith("engine-workspace.part"):
                raise RuntimeError("Remote asset differs; refusing replacement: " + path.name)
            report("Replacing incomplete snapshot chunk: " + path.name)
            run(["gh", "api", "--method", "DELETE", f"repos/{repository}/releases/assets/{found['id']}"])
        report("Uploading: " + path.name)
        for attempt in range(3):
            try:
                upload_command(path)
                break
            except subprocess.CalledProcessError:
                current = next((x for x in remote()["assets"] if x["name"] == path.name), None)
                if current and current.get("digest") == digest:
                    break
                if attempt == 2 or current:
                    raise
                time.sleep(15)
        found = next(x for x in remote()["assets"] if x["name"] == path.name)
        if found.get("digest") != digest or found["size"] != path.stat().st_size:
            raise RuntimeError("Uploaded digest differs: " + path.name)
        state["uploaded"].append(path.name)
        report("Verified upload: " + path.name)

    def closed_parts():
        # The next part is created only after the previous part is closed.
        for stage in assets.glob(".engine-workspace-*"):
            for part in sorted(stage.glob("engine-workspace.part*.tar.gz"))[:-1]:
                yield part

    try:
        remote()  # Authentication/release check before expensive work.
        done = set()
        manifest_path = assets / "engine-workspace.manifest.json"
        attempts = 0
        while not manifest_path.exists():
            workspace = Path(cfg["workspace"])
            with (workspace / ".parc-operation.lock").open("r") as source_lock:
                try:
                    fcntl.flock(source_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    busy = False
                except BlockingIOError:
                    busy = True
            process = None
            if not busy:
                attempts += 1
                if attempts > 3:
                    raise RuntimeError("Capture failed three times; inspect capture.log, then re-run this command")
                report("Capturing existing workspace (no engine build)", capture_attempt=attempts)
                with config_path.with_name("capture.log").open("a") as log:
                    process = subprocess.Popen([sys.executable, str(ROOT / "scripts/engine-artifacts.py"),
                        "create-workspace", "--workspace", str(workspace), "--output", str(assets),
                        "--name", "engine-workspace"], stdout=log, stderr=log, start_new_session=True)
                done.clear()
            else:
                report("Waiting for existing capture; preserving its progress")
            while True:
                parts = [p for stage in assets.glob(".engine-workspace-*")
                         for p in stage.glob("engine-workspace.part*.tar.gz")]
                sizes = []
                for part in parts:
                    try:
                        sizes.append(part.stat().st_size)
                    except FileNotFoundError:
                        pass
                if sizes:
                    report(f"Compressing workspace: {sum(sizes) / 1e9:.2f} GB written, "
                           f"{len(sizes)} chunks created")
                else:
                    report("Preparing workspace snapshot; compression has not started yet")
                for part in closed_parts():
                    key = (str(part), part.stat().st_size)
                    if key not in done:
                        upload(part)
                        done.add(key)
                if manifest_path.exists() or process and process.poll() is not None:
                    break
                if process is None:
                    break
                time.sleep(10)
            if process is not None and process.wait() != 0 and manifest_path.exists():
                raise RuntimeError("Capture verification failed after archive creation; inspect capture.log before using it")
            if not manifest_path.exists():
                time.sleep(10)
        pins = {}
        for kind, name, metadata in (("package", "engine-package", ".parc-package-snapshot.json"),
                                      ("workspace", "engine-workspace", ".parc-workspace-snapshot.json")):
            path = assets / (name + ".manifest.json")
            if not path.exists():
                report("Capturing completed application package")
                run([sys.executable, ROOT / "scripts/engine-artifacts.py", "create-package",
                     "--package-dir", cfg["package"], "--output", assets, "--name", name])
            report("Verifying complete " + kind + " archive")
            artifact_archive.verify_archive(path)
            manifest = json.loads(path.read_text())
            for item in [*manifest["parts"], manifest["inventory"]]:
                upload(assets / item["name"])
            upload(path)  # A manifest is published only after all payloads pass.
            with (assets / manifest["inventory"]["name"]).open() as stream:
                entry = next(json.loads(line) for line in stream if json.loads(line)["path"] == metadata)
            pins[kind] = {"manifest": path.name, "manifest_sha256": sha(path),
                          "metadata_sha256": entry["sha256"]}
        pin = {"schema_version": 1, "target": "mac-arm64", "repository": repository,
               "release": tag, "source_revision": cfg["source_revision"], "artifacts": pins}
        write(config_path.with_name("engine-artifacts.json"), pin)
        if cfg.get("publish_git", False):
            report("Publishing verified artifact pin to Git")
            if run(["git", "status", "--porcelain"], cwd=ROOT):
                raise RuntimeError("Publication checkout has changes; preserve/commit them, then re-run")
            run(["git", "fetch", "origin"], cwd=ROOT)
            run(["git", "merge", "--ff-only", "origin/main"], cwd=ROOT)
            write(ROOT / "Engine/engine-artifacts.json", pin)
            if subprocess.call(["git", "diff", "--quiet", "--", "Engine/engine-artifacts.json"], cwd=ROOT) or run(["git", "ls-files", "--others", "--exclude-standard", "Engine/engine-artifacts.json"], cwd=ROOT):
                run(["git", "add", "Engine/engine-artifacts.json"], cwd=ROOT)
                run(["git", "commit", "-m", "Pin existing engine workspace and development package"], cwd=ROOT)
            run(["git", "push", "origin", "HEAD:main"], cwd=ROOT)
            head = run(["git", "rev-parse", "HEAD"], cwd=ROOT)
            if run(["git", "ls-remote", "origin", "refs/heads/main"], cwd=ROOT).split()[0] != head:
                raise RuntimeError("Remote HEAD differs after publication; inspect Git state")
            state["commit"] = head
        report("COMPLETE", complete=True, pin=str(config_path.with_name("engine-artifacts.json")))
    except Exception as error:
        report("STOPPED: " + str(error), complete=False)
        raise


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

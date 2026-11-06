#!/usr/bin/env python3
"""Run or resume one complete production release: release.sh --type minor."""
import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import signal
import shutil
import subprocess
import sys
import time
import uuid

import release_inputs
import release_lease
import app_version

ROOT = Path(__file__).resolve().parents[1]
TEAM = "94HKA7L2DR"
REPOSITORY = "etsenake/parc"
TERMINAL = {"complete", "abandoned"}


class Failure(RuntimeError):
    pass


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def next_version(version, kind):
    parts = [int(piece) for piece in version.split(".")]
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    parts[index] += 1
    for tail in range(index + 1, 3):
        parts[tail] = 0
    return ".".join(map(str, parts))


def module(source, name):
    spec = importlib.util.spec_from_file_location("parc_release_" + name.replace("-", "_"), Path(source) / "scripts" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class Release:
    def __init__(self, root=ROOT, kind="patch"):
        self.root = Path(root).resolve()
        self.kind = kind
        self.base = self.root / "build/releases"
        self.base.mkdir(parents=True, exist_ok=True)
        self.current = self.base / "current.json"
        self.state = {}
        self.env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_INSTALL_CLEANUP="1", GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1")
        self.secrets = []
        self.locks = []

    def emit(self, message, **fields):
        value = {"time": now(), "stage": self.state.get("stage", "preflight"), "message": message, **fields}
        line = json.dumps(value, sort_keys=True)
        for secret in self.secrets:
            line = line.replace(secret, "[REDACTED]")
        print(f"[{value['time']}] {value['stage']}: {json.loads(line)['message']}", flush=True)
        if self.state.get("run"):
            with (Path(self.state["run"]) / "events.jsonl").open("a") as stream:
                stream.write(line + "\n")

    def checkpoint(self, **values):
        self.state.update(values, updated_utc=now(), pid=os.getpid())
        save(self.current, self.state)
        if self.state.get("run"):
            save(Path(self.state["run"]) / "state.json", self.state)

    def lock(self):
        for path in [self.root / "build/recurring-prod-refresh/refresh.lock", self.base / "release.lock"]:
            path.parent.mkdir(parents=True, exist_ok=True)
            handle = path.open("a+")
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                handle.close()
                raise Failure("A release/build/install is already active; no overlapping work was started") from error
            self.locks.append(handle)

    def command(self, args, *, cwd=None, capture=False, retries=0, name=None):
        args = [str(arg) for arg in args]
        log = Path(self.state["run"]) / ((name or self.state.get("stage", "command")) + ".log") if self.state.get("run") else None
        for attempt in range(retries + 1):
            self.emit("Running " + (name or args[0]), attempt=attempt + 1, command=args)
            with subprocess.Popen(args, cwd=cwd or self.root, env=self.env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True, bufsize=1,
                                  start_new_session=True, pass_fds=tuple(item.fileno() for item in self.locks)) as child:
                self.checkpoint(command_pid=child.pid, command=args, command_started_utc=now())
                output = []
                try:
                    with log.open("a") if log else open(os.devnull, "w") as stream:
                        for line in child.stdout:
                            for secret in self.secrets:
                                line = line.replace(secret, "[REDACTED]")
                            stream.write(line); stream.flush()
                            if capture:
                                output.append(line)
                            elif line.strip():
                                print(line.rstrip(), flush=True)
                    code = child.wait()
                except BaseException:
                    try:
                        os.killpg(child.pid, signal.SIGTERM)
                        child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
                    except ProcessLookupError:
                        pass
                    raise
            self.checkpoint(command_pid=None, last_command_exit=code)
            if code == 0:
                return "".join(output).strip() if capture else ""
            if attempt < retries:
                self.emit("Transient operation failed; retrying unchanged inputs", exit_code=code)
                time.sleep(min(10 * (attempt + 1), 30))
        raise Failure(f"Command failed ({code}); see {log}")

    def git(self, *args, **kwargs):
        return self.command(["git", *args], capture=True, **kwargs)

    def github(self, *args):
        return self.command(["gh", *args], capture=True, retries=2, name="github")

    def start(self):
        self.lock()
        if self.current.exists():
            prior = json.loads(self.current.read_text())
            if prior.get("status") not in TERMINAL:
                if prior["release_type"] != self.kind:
                    raise Failure("An unfinished " + prior["release_type"] + " release must resume before another bump")
                self.state = prior
                self.emit("Resuming the existing release; version and inputs remain frozen")
        if not self.state:
            run = self.base / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
            run.mkdir(mode=0o700)
            self.state = {"schema_version": 1, "id": run.name, "run": str(run), "release_type": self.kind,
                          "started_utc": now(), "status": "running", "stage": "preflight", "completed": []}
        self.checkpoint(status="running", error=None)

    def auth(self):
        clean = {key: value for key, value in self.env.items() if key not in ("GH_TOKEN", "GITHUB_TOKEN")}
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, env=clean)
        if result.returncode or not result.stdout.strip():
            raise Failure("GitHub authentication missing; run gh auth login once")
        token = result.stdout.strip(); self.secrets.append(token)
        self.env.update(GH_TOKEN=token, GITHUB_TOKEN="")
        if json.loads(self.github("api", "repos/" + REPOSITORY))["private"] is not True:
            raise Failure("The app repository must remain private")
        # Git uses the same saved GitHub identity without putting a token in argv.
        self.env.update(GIT_CONFIG_COUNT="2", GIT_CONFIG_KEY_0="credential.helper", GIT_CONFIG_VALUE_0="",
                        GIT_CONFIG_KEY_1="credential.helper", GIT_CONFIG_VALUE_1="!gh auth git-credential")

    def preflight(self):
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            raise Failure("Release builds require an Apple Silicon Mac with full Xcode")
        self.auth()
        if not shutil.which('brew'):
            raise Failure('Install Homebrew once before running a production release')
        self.command(["xcrun", "--find", "swiftc"], capture=True)
        self.command(["xcrun", "--find", "notarytool"], capture=True)
        self.command(["xcodebuild", "-checkFirstLaunchStatus"], capture=True)
        identity_path = Path.home() / ".config/parc/signing-identity"
        identities = self.command(["security", "find-identity", "-v", "-p", "codesigning"], capture=True)
        if not re.search(r'"Developer ID Application: [^"\n]+ \(' + TEAM + r'\)"', identities) and shutil.which('op'):
            self.command([sys.executable, self.root / 'scripts/signing-backup.py', 'restore'], name='restore-signing-identity')
            identities = self.command(['security','find-identity','-v','-p','codesigning'], capture=True)
        if not identity_path.is_file():
            candidates = re.findall(r'"(Developer ID Application: [^"\n]+ \(' + TEAM + r'\))"', identities)
            if len(candidates) != 1:
                raise Failure('Import this Team Developer ID certificate AND private key on this Mac, then run scripts/setup-signing.sh; never ad-hoc fallback')
            identity_path.parent.mkdir(parents=True, exist_ok=True)
            identity_path.write_text(candidates[0] + '\n')
        identity = identity_path.read_text().strip()
        if not identity.startswith("Developer ID Application:") or TEAM not in identity:
            raise Failure("The configured Developer ID must belong to production Team " + TEAM)
        if '"' + identity + '"' not in identities:
            raise Failure("Configured signing identity/private key is unavailable or expired on this Mac")
        self.env["PARC_SIGN_IDENTITY"] = identity
        self.env["PARC_NOTARY_PROFILE"] = os.environ.get("PARC_NOTARY_PROFILE", "parc-notary")
        self.command(["xcrun", "notarytool", "history", "--keychain-profile", self.env["PARC_NOTARY_PROFILE"], "--output-format", "json"], capture=True, retries=2)
        self.checkpoint(identity=identity, notary_profile=self.env["PARC_NOTARY_PROFILE"])

    def published(self, commit):
        return subprocess.run(["git", "merge-base", "--is-ancestor", commit, "origin/main"],
                              cwd=self.root, env=self.env, capture_output=True).returncode == 0

    def prepare(self):
        if self.git("branch", "--show-current") != "main":
            raise Failure("Use main; all local changes are preserved")
        if self.state.get("source_frozen"):
            release_inputs.verify(self.root, self.state["source"], self.state["commit"])
            return
        if not self.state.get("version"):
            if self.git("status", "--porcelain"):
                raise Failure("Start on clean main; never reset/stash/clean local changes")
            self.checkpoint(quiet_seconds=None, quiet_head=None, quiet_since=None)
            self.git("fetch", "origin", "main", retries=2)
            self.git("merge", "--ff-only", "origin/main")
            previous = app_version.read(self.root)
            if previous['build'] >= 9999:
                raise Failure("Apple bundle build number exhausted")
            version = {"version": next_version(previous["version"], self.kind), "build": previous["build"] + 1}
            self.checkpoint(previous_version=previous, version=version, base_commit=self.git('rev-parse', 'HEAD'),
                            tag='v' + version['version'], source=str(Path(self.state['run']) / 'source'))
        path = self.root / 'app-version.json'
        wanted = self.state['version']
        if not self.state.get('commit'):
            head = self.git('rev-parse', 'HEAD')
            # Recover a kill between commit creation and checkpoint, without a second bump.
            if head != self.state['base_commit']:
                parent = self.git('rev-parse', 'HEAD^')
                changed = self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD')
                if parent != self.state['base_commit'] or changed != 'app-version.json' or app_version.read(self.root) != wanted:
                    raise Failure('Source changed during version transaction; preserved for reconciliation')
            else:
                dirty = self.git('status', '--porcelain')
                if dirty and (dirty.strip() not in ('M app-version.json', 'M  app-version.json') or app_version.read(self.root) != wanted):
                    raise Failure('Unexpected local edits during version transaction; preserved')
                path.write_text(json.dumps(wanted, indent=2) + '\n')
                self.git('add', 'app-version.json')
                self.git('commit', '--only', 'app-version.json', '-m', 'Release Parc ' + wanted['version'])
            self.checkpoint(commit=self.git('rev-parse', 'HEAD'))
        for attempt in range(4):
            self.git('fetch', 'origin', 'main', retries=2)
            commit = self.state['commit']
            if self.published(commit):
                break
            if self.git('status', '--porcelain') or self.git('rev-parse', 'HEAD') != commit:
                raise Failure('Unpublished version commit has local edits; preserved without overwriting')
            remote_version = json.loads(self.git('show', 'origin/main:app-version.json'))
            if remote_version != self.state['previous_version']:
                raise Failure('Another release changed the remote version; no retagging or automatic version replacement')
            if not subprocess.run(['git', 'merge-base', '--is-ancestor', 'origin/main', commit], cwd=self.root,
                                  env=self.env, capture_output=True).returncode == 0:
                self.git('merge', '--no-edit', 'origin/main')
                self.checkpoint(commit=self.git('rev-parse', 'HEAD'))
            try:
                self.git('push', 'origin', self.state['commit'] + ':refs/heads/main')
            except Failure:
                if attempt == 3:
                    raise
        self.git('fetch', 'origin', 'main', retries=2)
        if not self.published(self.state['commit']):
            raise Failure('Could not verify the version commit on origin/main')
        release_inputs.create(self.root, self.state['source'], self.state['commit'])
        self.checkpoint(source_frozen=True)

    def engine(self):
        source = Path(self.state["source"])
        workspace = Path(os.environ.get("PARC_ENGINE_WORKSPACE", "")) if os.environ.get("PARC_ENGINE_WORKSPACE") else None
        if workspace is None:
            options = [self.root / "work/engine", Path.home() / "ParcBuild/engine"]
            workspace = next((p for p in options if (p / ".parc-engine-source.json").is_file()), options[0])
        workspace = workspace.resolve()
        script = source / "scripts/engine-source.py"
        lock = source / "Engine/source-lock.json"
        overlay = source / "Engine/ParcHost/overlay.json"
        self.checkpoint(workspace=str(workspace), overlay=json.loads(overlay.read_text())["version"])
        if not (workspace / ".parc-engine-source.json").exists() and (not workspace.exists() or not any(workspace.iterdir())):
            workspace.parent.mkdir(parents=True, exist_ok=True)
            self.command([sys.executable, script, "sync", "--workspace", workspace], name="engine-sync")
        elif not (workspace / ".parc-engine-source.json").is_file():
            raise Failure("Existing workspace is unowned; preserved without adoption or deletion")
        old = json.loads((workspace / ".parc-engine-source.json").read_text())
        if old["lock_sha256"] != sha(lock):
            previous = None
            for revision in self.git('rev-list', self.state['commit'], '--', 'Engine/source-lock.json').splitlines():
                data = self.git('show', revision + ':Engine/source-lock.json') + '\n'
                if hashlib.sha256(data.encode()).hexdigest() == old['lock_sha256']:
                    previous = Path(self.state['run']) / 'previous-source-lock.json'
                    previous.write_text(data)
                    break
            if previous is None:
                raise Failure('Previous source lock is absent from Git history; workspace and objects preserved')
            before = json.loads(previous.read_text()); after = json.loads(lock.read_text())
            def sources(value):
                return {**{k:v for k,v in value.items() if k != 'storage'},
                        'build': {k:v for k,v in value['build'].items() if k != 'gn_defines'}}
            if sources(before) == sources(after):
                self.command([sys.executable, script, 'reconfigure', '--workspace', workspace,
                              '--previous-lock', previous], name='engine-reconfigure')
            else:
                # Upstream revisions need their own workspace; never reset an existing cache.
                workspace = workspace.with_name(workspace.name + '-' + sha(lock)[:12])
                self.checkpoint(workspace=str(workspace))
                self.command([sys.executable, script, 'sync', '--workspace', workspace], name='engine-sync')
        self.git("fetch", "origin", "main", retries=2)
        self.command([sys.executable, script, "overlay-check", "--workspace", workspace, "--manifest", overlay], name="overlay-check")
        current = json.loads((workspace / ".parc-engine-source.json").read_text())
        if current.get("overlay", {}).get("identity") != sha(overlay):
            self.command([sys.executable, script, "overlay-apply", "--workspace", workspace, "--manifest", overlay], name="overlay-apply")
        output = workspace / "chromium/src/out/ParcDistribution_GN_arm64"
        manifest = Path(self.state.get('engine_seal_path', str(Path(self.state['run']) / 'engine-artifacts.json')))
        self.checkpoint(engine_seal_path=str(manifest))
        if manifest.exists():
            self.command([sys.executable, source / 'scripts/release_engine.py', source, manifest, output], name='verify-resumed-engine')
            self.checkpoint(manifest=str(manifest), manifest_sha256=sha(manifest))
            return
        # Sealing first reuses a compatible completed shipping build. A refusal
        # proceeds through generation/incremental compilation, preserving output.
        try:
            self.command([sys.executable, source / "scripts/build.py", "seal-engine", "--engine-dir", output, "--manifest", manifest, "--purpose", "distribution"], name="engine-reuse")
        except Failure:
            jobs = str(min(7, os.cpu_count() or 4))
            self.command([sys.executable, script, "generate", "--workspace", workspace, "--jobs", jobs], name="engine-generate")
            self.git("fetch", "origin", "main", retries=2)
            self.command([sys.executable, script, "shipping-build", "--workspace", workspace, "--jobs", jobs], name="engine-build")
            self.command([sys.executable, source / "scripts/build.py", "seal-engine", "--engine-dir", output, "--manifest", manifest, "--purpose", "distribution"], name="engine-seal")
        self.checkpoint(manifest=str(manifest), manifest_sha256=sha(manifest))

    def package(self):
        source = Path(self.state["source"]); package_run = Path(self.state["run"]) / "package"
        self.env.update(PARC_RELEASE_REPOSITORY=str(self.root), PARC_RELEASE_COMMIT=self.state["commit"],
                        PARC_PACKAGE_RUN=str(package_run), PARC_ENGINE_WORKSPACE=self.state["workspace"])
        self.command(["bash", source / "scripts/package-app.sh", "--stable", self.state["manifest"]], name="package-publish")
        self.checkpoint(package=str(package_run / "development"))

    def install(self):
        source = Path(self.state["source"])
        self.command([sys.executable, source / "scripts/release_install.py", "--package", self.state["package"],
                      "--tag", self.state["tag"], "--commit", self.state["commit"], "--receipts", Path(self.state["run"]) / "install"], name="install-open-verify")
        self.checkpoint(acceptance=str(Path(self.state["run"]) / "install/acceptance.json"))

    def tap(self):
        source = Path(self.state["source"]); tap = Path.home() / "homebrew-tap"
        if not tap.exists():
            self.command(["git", "clone", "https://github.com/etsenake/homebrew-tap.git", tap], name="tap-clone", retries=2)
        self.command([sys.executable, source / "scripts/publish-homebrew.py", self.state["tag"], "--tap", tap,
                      "--acceptance", self.state["acceptance"], "--resume"], name="tap-update")
        self.git("diff", "--check", cwd=tap)
        self.command(["brew", "ruby", "--", "-c", tap / "Casks/parc.rb"], name="tap-syntax")
        if self.git("status", "--porcelain", cwd=tap):
            self.git("commit", "--only", "Casks/parc.rb", "-m", "Release Parc " + self.state["version"]["version"], cwd=tap)
            head = self.git("rev-parse", "HEAD", cwd=tap)
            self.git("push", "origin", head + ":refs/heads/main", cwd=tap, retries=2)
        self.git('fetch', 'origin', 'main', cwd=tap, retries=2)
        head = self.git('rev-parse', 'HEAD', cwd=tap)
        remote = self.git('ls-remote', 'origin', 'refs/heads/main', cwd=tap).split()[0]
        if head != remote:
            # A resumed local cask commit may simply await its first push.
            self.git('push', 'origin', head + ':refs/heads/main', cwd=tap, retries=2)
            if self.git('ls-remote', 'origin', 'refs/heads/main', cwd=tap).split()[0] != head:
                raise Failure('Tap commit publication was not verified')
        self.command(["brew", "tap", "etsenake/tap"], name="tap-register")
        installed_tap = Path(self.command(["brew", "--repo", "etsenake/tap"], capture=True))
        if self.git("status", "--porcelain", cwd=installed_tap):
            raise Failure("Installed Homebrew tap has local edits; preserved without overwriting")
        self.git("fetch", "origin", "main", cwd=installed_tap, retries=2)
        self.git("merge", "--ff-only", "origin/main", cwd=installed_tap)
        self.command(["brew", "audit", "--cask", "etsenake/tap/parc"], name="tap-audit")
        self.command([sys.executable, source / 'scripts/release_brew.py', self.state['package'],
                      Path(self.state['run']) / 'homebrew'], name='homebrew-upgrade')
        self.checkpoint(tap=str(tap), tap_commit=self.git("rev-parse", "HEAD", cwd=tap))

    def finish(self):
        self.checkpoint(stage='cleanup')
        app = Path('/Applications/Parc.app')
        source = Path(self.state['source'])
        check = module(source, 'record-release-acceptance')
        report = json.loads((Path(self.state['package']) / 'package-report.json').read_text())
        check.verify_installed(app, report, strict=False)
        lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
        state_path = self.root / 'build/recurring-prod-refresh/state.json'
        if state_path.exists() and not (Path(self.state['run']) / 'previous-refresh-state.json').exists():
            save(Path(self.state['run']) / 'previous-refresh-state.json', json.loads(state_path.read_text()))
        acceptance_path = Path(self.state['run']) / 'homebrew/acceptance.json'
        if not acceptance_path.exists():
            acceptance_path = Path(self.state['acceptance'])
        acceptance = json.loads(acceptance_path.read_text())
        report_path = Path(self.state['package']) / 'package-report.json'
        check.publisher.verify_acceptance(acceptance, self.state['tag'], self.state['commit'],
                                          report['app_version'], sha(report_path))
        removed = []
        # Only exact rollback bundles owned by this run are eligible. The newest
        # pristine package, reports, profiles, seals and compiled output remain.
        for relative in ('install/previous-Parc.app', 'homebrew/before-Parc.app', 'homebrew/manual-Parc.app'):
            old = Path(self.state['run']) / relative
            if old.is_dir() and not old.is_symlink():
                self.command([lsregister, '-u', old], name='unregister-old-app')
                shutil.rmtree(old)
                removed.append(str(old))
        self.command([lsregister, '-f', app], name='register-installed-app')
        previous = {'schema_version': 2, 'status': 'installed_master_release_verified',
                    'automation_id': 'refresh-parc-production-app', 'automation_status': 'deleted_by_user',
                    'installed_app': str(app), 'installed_source_commit': self.state['commit'],
                    'engine_overlay': self.state['overlay'], 'overlay_identity': report['overlay']['identity'],
                    'source_lock_sha256': report['source_lock_sha256'], 'engine_manifest': self.state['manifest'],
                    'engine_manifest_file_sha256': self.state['manifest_sha256'], 'package': self.state['package'],
                    'package_report': str(report_path), 'package_report_sha256': sha(report_path),
                    'release_tag': self.state['tag'], 'release_url': 'https://github.com/' + REPOSITORY + '/releases/tag/' + self.state['tag'],
                    'app_version': self.state['version'], 'signing_team': report['signing_team'],
                    'signing_identity': report['signing_identity'], 'notarization': report['notarization'],
                    'launch_observation': str(acceptance_path), 'launch_result': acceptance['launch_observation'],
                    'designated_requirement': acceptance['designated_requirement'], 'code_image_count': len(report['signed_images']),
                    'strict_signature_before_launch_verified': acceptance['prelaunch_strict_verified'],
                    'signature_after_launch_verified': acceptance['installed_code_hashes_verified'],
                    'application_window_verified': False, 'browser_functionality_acceptance_claimed': False,
                    'homebrew': {'version': self.state['version']['version'], 'tap_commit': self.state['tap_commit']},
                    'completed_utc': now(), 'master_release_run': self.state['run']}
        save(state_path, previous)
        self.checkpoint(removed_rollback_apps=removed, lease_release_started=True)
        release_lease.release(self.state['lease'])
        self.checkpoint(lease=None, status='complete', stage='complete', completed_utc=now())

    def run(self):
        def interrupted(signum, frame):
            raise KeyboardInterrupt('Release interrupted by signal ' + str(signum))
        prior_signal = signal.signal(signal.SIGTERM, interrupted)
        try:
            self.start()
            self.preflight()
            if self.state.get('lease_release_started'):
                self.finish()
                return 0
            # Use the saved gh identity for the atomic cross-Mac lease too.
            os.environ['GH_TOKEN'] = self.env['GH_TOKEN']
            os.environ.pop('GITHUB_TOKEN', None)
            if not self.state.get('source_frozen'):
                self.git('fetch', 'origin', 'main', retries=2)
            lease = release_lease.acquire(self.state['id'], self.state.get('commit') or self.git('rev-parse', 'origin/main'), self.state.get('lease'))
            self.checkpoint(lease=lease)
            for name, action in [("source", self.prepare), ("engine", self.engine), ("package", self.package),
                                 ("install", self.install), ("homebrew", self.tap)]:
                if name in self.state["completed"]:
                    if name == 'source':
                        release_inputs.verify(self.root, self.state['source'], self.state['commit'])
                    if name == 'engine' and sha(self.state['manifest']) != self.state['manifest_sha256']:
                        raise Failure('Completed engine seal changed; preserved without retargeting')
                    self.emit("Reusing completed " + name + " stage")
                    continue
                self.checkpoint(stage=name)
                action()
                self.state["completed"].append(name)
                self.checkpoint()
            self.finish()
            self.emit("Released " + self.state["tag"] + "; installed app and Homebrew cask verified")
            return 0
        except (Failure, RuntimeError, OSError, ValueError, subprocess.SubprocessError, KeyboardInterrupt) as error:
            self.emit(str(error))
            if self.state:
                self.checkpoint(status="stopped", error=str(error))
            return 1
        finally:
            signal.signal(signal.SIGTERM, prior_signal)
            for handle in self.locks:
                handle.close()
            self.locks.clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", required=True, choices=("major", "minor", "patch"))
    args = parser.parse_args()
    return Release(kind=args.type).run()


if __name__ == "__main__":
    raise SystemExit(main())

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
    def __init__(self, root=ROOT, kind="patch", refresh_source=False, source_commit=None):
        self.root = Path(root).resolve()
        self.kind = kind
        self.refresh_source = refresh_source
        self.source_commit = source_commit
        self.base = self.root / "build/releases"
        self.base.mkdir(parents=True, exist_ok=True)
        self.log = self.root / "build/master-release-development/nightly-release.log"
        self.log.parent.mkdir(parents=True, exist_ok=True)
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
        message = f"[{value['time']}] {value['stage']}: {json.loads(line)['message']}"
        with self.log.open("a") as stream:
            stream.write(message + "\n")
        print(message, flush=True)
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
                    with self.log.open("a") as combined, (log.open("a") if log else open(os.devnull, "w")) as stream:
                        for line in child.stdout:
                            for secret in self.secrets:
                                line = line.replace(secret, "[REDACTED]")
                            stream.write(line); stream.flush()
                            combined.write(line); combined.flush()
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
        raise Failure(f"Command failed ({code}); see {self.log}")

    def git(self, *args, **kwargs):
        return self.command(["git", *args], capture=True, **kwargs)

    def github(self, *args):
        return self.command(["gh", *args], capture=True, retries=2, name="github")

    def start(self):
        self.lock()
        if self.current.exists():
            prior = json.loads(self.current.read_text())
            if prior.get("status") not in TERMINAL and prior["release_type"] != self.kind:
                self.supersede(prior)
                prior = json.loads(self.current.read_text())
            if prior.get("status") not in TERMINAL:
                if self.refresh_source and (prior.get('status') != 'stopped'
                        or prior.get('stage') != 'engine'
                        or prior.get('completed') != ['source']
                        or prior.get('command_pid') is not None):
                    raise Failure('Source refresh requires a stopped engine stage with no active command or packaged artifacts')
                self.refresh_previous = dict(prior)
                self.state = prior
                if (prior.get('status') == 'stopped' and prior.get('command_pid')
                        and 'shipping-build' in prior.get('command', [])):
                    self.state['interrupted_process_group'] = prior['command_pid']
                self.emit("Resuming the existing release; version and inputs remain frozen")
        if not self.state:
            if self.refresh_source:
                raise Failure('Source refresh requires an existing stopped release')
            run = self.base / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
            run.mkdir(mode=0o700)
            self.state = {"schema_version": 1, "id": run.name, "run": str(run), "release_type": self.kind,
                          "started_utc": now(), "status": "running", "stage": "preflight", "completed": []}
        self.checkpoint(status="running", error=None)

    def supersede(self, prior):
        """Retire a stopped, never-published release of another type so a new bump can start.

        Its run directory, frozen source and compiled engine objects stay in place.
        """
        unfinished = "An unfinished " + prior["release_type"] + " release must resume before another bump"
        if prior.get("status") != "stopped" or prior.get("lease_release_started"):
            raise Failure(unfinished)
        for key in ("pid", "command_pid"):
            pid = prior.get(key)
            if pid and pid != os.getpid():
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    continue
                except PermissionError:
                    pass
                raise Failure(unfinished + "; its process " + str(pid) + " is still alive")
        if prior.get("tag"):
            # No self.git here: its checkpoint would overwrite current.json before the state is known.
            remote = subprocess.run(["git", "ls-remote", "origin", "refs/tags/" + prior["tag"]], cwd=self.root,
                                    env=self.env, capture_output=True, text=True)
            if remote.returncode:
                raise Failure(unfinished + "; could not check whether " + prior["tag"] + " is published")
            if remote.stdout.strip():
                raise Failure(unfinished + "; " + prior["tag"] + " is already published")
        if prior.get("lease"):
            release_lease.release(prior["lease"])
        retired = dict(prior, status="abandoned", lease=None, superseded_by=self.kind,
                       abandoned_utc=now(), updated_utc=now())
        if prior.get("run"):
            save(Path(prior["run"]) / "state.json", retired)
        save(self.current, retired)
        self.emit("Abandoned the stopped, unpublished " + prior["release_type"] + " release " + prior.get("tag", prior["id"])
                  + " so a " + self.kind + " release can start; its run, source archive and engine objects were kept")

    def refresh_inputs(self):
        """Explicitly replace failed, unpublished build inputs; retain the old archive."""
        if self.git('status', '--porcelain'):
            raise Failure('Source refresh requires clean main; local edits were preserved')
        if self.git('branch', '--show-current') != 'main':
            raise Failure('Source refresh requires main')
        self.git('fetch', 'origin', 'main', retries=2)
        self.git('merge', '--ff-only', 'origin/main')
        commit = self.source_commit or self.git('rev-parse', 'HEAD')
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise Failure('Refreshed source requires a full Git commit SHA')
        if json.loads(self.git('show', commit + ':app-version.json')) != self.state['version']:
            raise Failure('Source refresh cannot change the saved release version')
        if self.git('ls-remote', 'origin', 'refs/tags/' + self.state['tag']):
            raise Failure('A published release tag is immutable; source refresh refused')
        if (Path(self.state['run']) / 'package').exists() or Path(self.state['engine_seal_path']).exists():
            raise Failure('Source refresh refused after sealing or packaging; existing artifacts were preserved')
        if not self.published(commit):
            raise Failure('Refreshed source must be published on origin/main')
        self.git('merge-base', '--is-ancestor', self.state['commit'], commit)
        release_inputs.verify(self.root, self.state['source'], self.state['commit'])
        source = Path(self.state['run']) / ('source-' + commit)
        release_inputs.create(self.root, source, commit)
        history = list(self.state.get('source_history', []))
        history.append({'commit': self.state['commit'], 'source': self.state['source'],
                        'overlay': self.state.get('overlay'), 'error': self.refresh_previous.get('error'),
                        'refreshed_utc': now()})
        self.checkpoint(commit=commit, source=str(source), source_history=history)
        self.emit('Refreshed unpublished release inputs to ' + commit + '; previous archive and compiled objects preserved')

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
        if self.state.get('interrupted_process_group'):
            self.command([sys.executable, self.root / 'scripts/release_recover.py', source, workspace,
                          str(self.state['interrupted_process_group']), Path(self.state['run']) / 'cancelled-shipping-receipt.json'],
                         name='recover-cancelled-engine')
            self.checkpoint(interrupted_process_group=None)
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
            generated = json.loads((workspace / '.parc-engine-source.json').read_text())
            if generated.get('phase') not in ('generated', 'built'):
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

    def tap(self):
        source = Path(self.state["source"]); tap = Path.home() / "homebrew-tap"
        if not tap.exists():
            self.command(["git", "clone", "https://github.com/etsenake/homebrew-tap.git", tap], name="tap-clone", retries=2)
        self.command([sys.executable, self.root / "scripts/publish-homebrew.py", self.state["tag"], "--tap", tap,
                      "--artifact-only", "--resume"], name="tap-update")
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
        self.checkpoint(tap=str(tap), tap_commit=self.git("rev-parse", "HEAD", cwd=tap))

    def finish(self):
        self.checkpoint(stage='verify-release')
        package = Path(self.state['package'])
        check = module(self.root, 'record-release-acceptance')
        report_path = package / 'package-report.json'
        report = json.loads(report_path.read_text())
        check.publisher.dmg_tool.require_report(report, TEAM)
        check.verify_installed(package / 'Parc.app', report, strict=True)
        check.publisher.verify_tag(self.state['tag'], self.state['commit'])
        published = json.loads(self.github('api', 'repos/' + REPOSITORY + '/releases/tags/' + self.state['tag']))
        if published['draft'] or published['prerelease'] or published['target_commitish'] != self.state['commit']:
            raise Failure('Final GitHub release/source promotion was not verified')
        delivery = {'schema_version': 1, 'status': 'published', 'source_commit': self.state['commit'],
                    'engine_overlay': self.state['overlay'], 'overlay_identity': report['overlay']['identity'],
                    'engine_manifest': self.state['manifest'], 'engine_manifest_sha256': self.state['manifest_sha256'],
                    'package': str(package), 'package_report_sha256': sha(report_path),
                    'release_tag': self.state['tag'], 'release_url': published['html_url'],
                    'app_version': self.state['version'], 'signing_team': report['signing_team'],
                    'notarization': report['notarization'], 'tap_commit': self.state['tap_commit'],
                    'installed_or_launched_by_release_script': False, 'runtime_acceptance_claimed': False,
                    'homebrew_upgrade': 'manual', 'completed_utc': now(), 'run': self.state['run']}
        save(Path(self.state['run']) / 'delivery.json', delivery)
        save(self.base / 'latest.json', delivery)
        self.checkpoint(lease_release_started=True)
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
            if self.refresh_source:
                self.refresh_inputs()
            for name, action in [("source", self.prepare), ("engine", self.engine), ("package", self.package),
                                 ("homebrew", self.tap)]:
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
            self.emit("Released " + self.state["tag"] + "; notarized assets and published Homebrew cask verified")
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
    parser.add_argument("--refresh-source", action="store_true",
                        help="Use published fixes for a stopped, unsealed engine build without bumping again")
    parser.add_argument("--source-commit", help="Full published commit SHA to freeze for an explicit source refresh")
    args = parser.parse_args()
    if args.source_commit and not args.refresh_source:
        parser.error('--source-commit requires --refresh-source')
    return Release(kind=args.type, refresh_source=args.refresh_source, source_commit=args.source_commit).run()


if __name__ == "__main__":
    raise SystemExit(main())

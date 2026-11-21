#!/usr/bin/env python3
"""Run or resume one complete production release: release.sh [--type major|minor|patch]."""
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
import shlex
import signal
import shutil
import subprocess
import sys
import time
import traceback
import uuid

import developer_id
import notary_service
import release_inputs
import release_lease
import release_notes
import app_version
import sparkle

ROOT = Path(__file__).resolve().parents[1]
TEAM = "94HKA7L2DR"
REPOSITORY = "etsenake/parc"
PUBLIC_REPOSITORY = "etsenake/parc-releases"
TERMINAL = {"complete", "abandoned", "nothing-to-release", "handed-off"}
RELEASE_FILES = ("app-version.json", "release-notes.json", "CHANGELOG.md")
INERT_FOLDERS = ("site/", "docs/", "tests/", ".github/")
MARKDOWN = (".md", ".markdown", ".mdc")
CHANGE_KEYS = ("type", "scope", "summary", "breaking")
OVERLAY = "Engine/ParcHost/overlay.json"
LOCK = "Engine/source-lock.json"
SWIFT_INPUTS = ("Package.swift", "Package.resolved", "Sources", "Stubs", "Engine/ParcNative", LOCK, "scripts")
CHECK_ROUNDS = 5


class Failure(RuntimeError):
    def __init__(self, message, code=None, output=""):
        super().__init__(message)
        self.code, self.output = code, output


def release_file(path):
    return path.casefold() in {name.casefold() for name in RELEASE_FILES}


def inert(path):
    return not release_file(path) and (path.startswith(INERT_FOLDERS) or path.casefold().endswith(MARKDOWN))


def blocking(changes, own=()):
    return sorted(path for path, (code, _, _) in changes.items() if path not in own
                  and (release_file(path) or code == "UU" or (code != "??" and not inert(path))))


def overlaps(path, other):
    path, other = path.rstrip("/"), other.rstrip("/")
    return path == other or other.startswith(path + "/") or path.startswith(other + "/")


def listing(paths):
    return ", ".join(paths[:10]) + (" and " + str(len(paths) - 10) + " more" if len(paths) > 10 else "")


def retargetable(before, after):
    return (all(before.get(key) == after.get(key) for key in ('schema_version', 'target'))
            and all(before.get(name, {}).get('url') == after.get(name, {}).get('url') for name in ('chromium', 'depot_tools')))


def engine_jobs(cores=None, memory=None):
    cores = cores or os.cpu_count() or 4
    if memory is None:
        try:
            memory = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
        except (ValueError, OSError):
            memory = 0
    by_memory = memory // (2 * 2**30) if memory else cores
    return max(1, min(cores - 1, by_memory))


def metal_toolchain_ready(env=None):
    try:
        return subprocess.run(["xcrun", "metal", "--version"], env=env, capture_output=True, timeout=120).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def interpreter_path(root, path):
    folder = Path(root) / "build/release-tools/bin"
    folder.mkdir(parents=True, exist_ok=True)
    shim = folder / "python3"
    text = "#!/bin/sh\nexec " + shlex.quote(sys.executable) + ' "$@"\n'
    if not shim.is_file() or shim.read_text() != text:
        temporary = folder / ("python3." + uuid.uuid4().hex[:8])
        temporary.write_text(text)
        temporary.chmod(0o755)
        os.replace(temporary, shim)
    return str(folder) + os.pathsep + (path or os.defpath)


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
    def __init__(self, root=ROOT, kind=None, refresh_source=False, source_commit=None):
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
        self.env = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_INSTALL_CLEANUP="1", GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1",
                        PATH=interpreter_path(self.root, os.environ.get("PATH")))
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
        raise Failure(f"Command failed ({code}); see {self.log}", code, "".join(output))

    def git(self, *args, **kwargs):
        return self.command(["git", *args], capture=True, **kwargs)

    def github(self, *args):
        return self.command(["gh", *args], capture=True, retries=2, name="github")

    def start(self):
        self.lock()
        if self.current.exists():
            prior = {key: value for key, value in json.loads(self.current.read_text()).items()
                     if not key.startswith("storage_")}
            if prior.get("status") == "running":
                prior.update(status="stopped",
                             error=prior.get("error") or "The previous release process exited without stopping cleanly")
                save(self.current, prior)
                if prior.get("run"):
                    save(Path(prior["run"]) / "state.json", prior)
            if (prior.get("status") not in TERMINAL and self.kind and prior["release_type"]
                    and prior["release_type"] != self.kind):
                self.supersede(prior)
                prior = json.loads(self.current.read_text())
            if prior.get("status") not in TERMINAL:
                if self.refresh_source:
                    self.recover_dead_command(prior)
                if self.refresh_source and (prior.get('status') != 'stopped'
                        or prior.get('stage') != 'engine'
                        or prior.get('completed') != ['source']
                        or prior.get('command_pid') is not None):
                    raise Failure('Source refresh requires a stopped engine stage with no active command or packaged artifacts')
                if self.refresh_source and prior.get('interrupted_process_group'):
                    prior['interrupted_inputs_refreshed'] = True
                self.refresh_previous = dict(prior)
                self.state = prior
                if self.kind:
                    self.state["type_override"] = self.kind
                self.kind = self.kind or prior["release_type"]
                self.state["release_type"] = self.kind
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

    def recover_dead_command(self, prior):
        command = prior.get('command', [])
        pid = prior.get('command_pid')
        source = prior.get('source')
        overlay_check = bool(source) and command[1:3] == [str(Path(source) / 'scripts/engine-source.py'), 'overlay-check']
        tool = command[:1] in (['git'], ['gh'], ['xcrun'], ['xcodebuild'], ['security']) or command[:2] == ['brew', 'install']
        restore = command[1:3] == [str(self.root / 'scripts/signing-backup.py'), 'restore']
        shipping = bool(source) and command[1:3] == [str(Path(source) / 'scripts/engine-source.py'), 'shipping-build']
        if (prior.get('status') != 'stopped' or prior.get('stage') != 'engine' or not pid
                or not (overlay_check or tool or restore or shipping)):
            return
        for probe in (os.kill, os.killpg):
            try:
                probe(pid, 0)
            except ProcessLookupError:
                continue
            raise Failure('Previous command ' + str(pid) + ' or its process group is still alive')
        if shipping:
            prior.update(interrupted_process_group=pid)
        else:
            prior['interrupted_command'] = {
                'command': command, 'pid': pid,
                'started_utc': prior.get('command_started_utc'), 'recovered_utc': now()}
        prior.update(command_pid=None, last_command_exit=None)
        save(self.current, prior)
        save(Path(prior['run']) / 'state.json', prior)

    def supersede(self, prior):
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

    def superseded_shipping_build(self):
        found = []
        for path in self.base.glob('*/state.json'):
            try:
                state = json.loads(path.read_text())
            except (OSError, ValueError):
                continue
            if (state.get('status') == 'abandoned' and state.get('superseded_by') == self.kind
                    and not state.get('cancelled_build_recovered') and state.get('command_pid')
                    and 'shipping-build' in state.get('command', [])):
                found.append(state)
        return max(found, key=lambda state: state.get('abandoned_utc', '')) if found else None

    def local_changes(self):
        raw = subprocess.run(['git', '--no-optional-locks', 'status', '--porcelain=v2', '-z', '--no-renames',
                              '--untracked-files=all'], cwd=self.root, env=self.env, capture_output=True,
                             check=True).stdout.split(b'\0')
        changes = {}
        records = iter(raw)
        for record in records:
            kind, _, rest = record.partition(b' ')
            if kind == b'?':
                changes.setdefault(os.fsdecode(rest), ('??', None, None))
            elif kind in (b'1', b'2', b'u'):
                fields = rest.split(b' ', {b'1': 7, b'2': 8, b'u': 9}[kind])
                if kind == b'u':
                    changes[os.fsdecode(fields[-1])] = ('UU', None, None)
                    continue
                changes[os.fsdecode(fields[-1])] = (fields[0].decode(), fields[5].decode(), fields[6].decode())
                if kind == b'2':
                    changes[os.fsdecode(next(records))] = ('D.', None, None)
        return changes

    def require_clean(self, message):
        blocked = blocking(self.local_changes())
        if blocked:
            raise Failure(message + ': ' + listing(blocked))

    def text(self, name):
        try:
            return (self.root / name).read_text()
        except FileNotFoundError:
            return None

    def fast_forward(self):
        head, tip = self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'origin/main')
        if self.ancestor(tip, head):
            return
        if not self.ancestor(head, tip):
            raise Failure('Local main has unpushed commits; preserved without releasing them')
        raw = subprocess.run(['git', 'diff-tree', '-r', '-z', '--no-renames', '--name-status', head, tip],
                             cwd=self.root, env=self.env, capture_output=True, check=True).stdout.split(b'\0')
        changed = dict(zip(map(os.fsdecode, raw[1::2]), map(bytes.decode, raw[0::2])))
        local = self.local_changes()
        clashes = sorted({path for path in local for name in changed if overlaps(path, name)}
                         | {name for name, status in changed.items()
                            if status == 'A' and os.path.lexists(self.root / name)})
        if clashes:
            raise Failure('Main moved under local edits to ' + listing(clashes)
                          + '; nothing was fast-forwarded or overwritten. Commit or move those edits, then rerun')
        try:
            self.git('merge', '--ff-only', '--no-autostash', '--no-overwrite-ignore', tip, retries=2)
        except Failure:
            raise Failure('Git refused to fast-forward main; local edits were preserved (see ' + str(self.log) + ')') from None

    def refresh_inputs(self):
        self.require_clean('Source refresh requires clean main; local edits were preserved')
        if self.git('branch', '--show-current') != 'main':
            raise Failure('Source refresh requires main')
        self.git('fetch', 'origin', 'main', retries=2)
        self.fast_forward()
        commit = self.source_commit or self.state.get('refresh_commit') or self.git('rev-parse', 'HEAD')
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise Failure('Refreshed source requires a full Git commit SHA')
        if json.loads(self.git('show', commit + ':app-version.json')) != self.state['version']:
            raise Failure('Source refresh cannot change the saved release version')
        if self.git('ls-remote', 'origin', 'refs/tags/' + self.state['tag']):
            raise Failure('A published release tag is immutable; source refresh refused')
        seal = Path(self.state.get('engine_seal_path') or Path(self.state['run']) / 'engine-artifacts.json')
        if (Path(self.state['run']) / 'package').exists() or seal.exists():
            raise Failure('Source refresh refused after sealing or packaging; existing artifacts were preserved')
        if not self.published(commit):
            raise Failure('Refreshed source must be published on origin/main')
        self.git('merge-base', '--is-ancestor', self.state['commit'], commit)
        release_inputs.verify(self.root, self.state['source'], self.state['commit'])
        since, found = self.changes(commit)
        version = self.state['version']
        kind = release_notes.bump(found) or self.kind
        raised = next_version(self.state['previous_version']['version'], kind)
        outgrown = release_notes.number(raised) > release_notes.number(version['version'])
        if outgrown and not self.state.get('type_override'):
            raise Failure('Refreshed source would ship a ' + kind + ' change in ' + version['version']
                          + '; pin --source-commit before it, or release ' + raised + ' with --type ' + kind)
        self.check_source(commit, since, 'The stopped release was not changed.')
        notes = release_notes.entry(version['version'], version['build'], self.state['notes']['date'], found)
        files = release_notes.files(json.loads(self.git('show', commit + ':release-notes.json')), notes, since[1:])
        if any(self.git('show', commit + ':' + name) != text.strip() for name, text in files.items()):
            self.checkpoint(refresh_commit=commit)
            commit = self.publish_notes(commit, files)
        source = Path(self.state['run']) / ('source-' + commit)
        release_inputs.create(self.root, source, commit)
        history = list(self.state.get('source_history', []))
        history.append({'commit': self.state['commit'], 'source': self.state['source'],
                        'overlay': self.state.get('overlay'), 'error': self.refresh_previous.get('error'),
                        'refreshed_utc': now()})
        self.checkpoint(commit=commit, notes=notes, since=since, source=str(source), source_history=history,
                        refresh_commit=None)
        self.emit('Refreshed unpublished release inputs to ' + commit + '; previous archive and compiled objects preserved')

    def plumbing(self, args, text):
        return subprocess.run(['git', *args], cwd=self.root, env=self.env, input=text, capture_output=True,
                              text=True, check=True).stdout.strip()

    def blob(self, text):
        return self.plumbing(['hash-object', '-w', '--stdin'], text)

    def tree(self, commit, files):
        entries = [line for line in self.git('ls-tree', commit).splitlines() if line.split('\t', 1)[1] not in files]
        entries += ['100644 blob ' + self.blob(text) + '\t' + name for name, text in files.items()]
        return self.plumbing(['mktree'], '\n'.join(entries) + '\n')

    def publish_notes(self, source, files):
        message = 'chore(release): ' + self.state['version']['version'] + ' notes'
        tree = self.tree(source, files)
        self.git('fetch', 'origin', 'main', retries=2)
        log = self.git('log', '--format=%H %T %P', source + '..origin/main').splitlines()
        published = [line.split()[0] for line in log if line.split()[1:] == [tree, source]]
        notes = published[0] if published else self.git('commit-tree', tree, '-p', source, '-m', message)
        for attempt in range(4):
            if self.published(notes):
                break
            tip, head = self.git('rev-parse', 'origin/main'), notes
            if tip != source:
                if any(self.git('show', tip + ':' + name) != self.git('show', source + ':' + name) for name in files):
                    raise Failure('Main changed the release notes after ' + source + '; preserved for reconciliation')
                head = self.git('commit-tree', self.tree(tip, files), '-p', tip, '-p', notes, '-m', 'Merge ' + message)
            try:
                self.git('push', 'origin', head + ':refs/heads/main')
            except Failure:
                if attempt == 3:
                    raise
            self.git('fetch', 'origin', 'main', retries=2)
        if not self.published(notes):
            raise Failure('Could not verify the release notes commit on origin/main')
        self.fast_forward()
        return notes

    def auth(self):
        clean = {key: value for key, value in self.env.items() if key not in ("GH_TOKEN", "GITHUB_TOKEN")}
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, env=clean)
        if result.returncode or not result.stdout.strip():
            raise Failure("GitHub authentication missing; run gh auth login once")
        token = result.stdout.strip(); self.secrets.append(token)
        self.env.update(GH_TOKEN=token, GITHUB_TOKEN="")
        self.env.update(GIT_CONFIG_COUNT="2", GIT_CONFIG_KEY_0="credential.helper", GIT_CONFIG_VALUE_0="",
                        GIT_CONFIG_KEY_1="credential.helper", GIT_CONFIG_VALUE_1="!gh auth git-credential")

    def provision(self, tool, *package):
        if shutil.which(tool):
            return True
        self.emit("Installing " + package[-1] + " with Homebrew; the release needs " + tool)
        try:
            self.command(["brew", "install", *package], name="install-" + package[-1])
        except Failure:
            return False
        return shutil.which(tool) is not None

    def restore_credentials(self, name):
        if not self.provision("op", "--cask", "1password-cli"):
            return False
        try:
            self.command([sys.executable, self.root / "scripts/signing-backup.py", "restore"], name=name)
        except Failure:
            return False
        return True

    def identities(self, valid=True):
        return self.command(["security", "find-identity", *(["-v"] if valid else []), "-p", "codesigning"], capture=True)

    def preflight(self):
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            raise Failure("Release builds require an Apple Silicon Mac with full Xcode")
        if not shutil.which("brew"):
            raise Failure("Install Homebrew once before running a production release")
        if not self.provision("gh", "gh"):
            raise Failure("The GitHub CLI is missing and Homebrew could not install it; see " + str(self.log))
        self.auth()
        self.command(["xcrun", "--find", "swiftc"], capture=True)
        self.command(["xcrun", "--find", "notarytool"], capture=True)
        try:
            self.command(["xcodebuild", "-checkFirstLaunchStatus"], capture=True)
        except Failure:
            raise Failure("Xcode is not ready: select full Xcode with sudo xcode-select -s /Applications/Xcode.app, "
                          "then run sudo xcodebuild -runFirstLaunch once") from None
        if not metal_toolchain_ready(self.env):
            self.emit("Downloading Apple's Metal toolchain, which the engine build needs")
            try:
                self.command(["xcodebuild", "-downloadComponent", "MetalToolchain"], name="install-metal-toolchain", retries=1)
            except Failure:
                pass
            if not metal_toolchain_ready(self.env):
                raise Failure("Apple's Metal toolchain is missing and could not be downloaded; the engine build needs it. "
                              "Install it with: xcodebuild -downloadComponent MetalToolchain")
        identity_path = Path.home() / ".config/parc/signing-identity"
        identities = self.identities()
        if not developer_id.IDENTITY.search(identities):
            listed = developer_id.names(self.identities(valid=False))
            if listed:
                try:
                    if developer_id.install_intermediates(listed, log=self.emit):
                        identities = self.identities()
                except (ValueError, OSError, subprocess.SubprocessError) as error:
                    self.emit("Could not install Apple's Developer ID intermediate certificate: " + str(error))
        if not developer_id.IDENTITY.search(identities) or not sparkle.has_key():
            self.restore_credentials("restore-signing-keys")
            identities = self.identities()
        if not sparkle.has_key():
            raise Failure("Sparkle's update signing key (login Keychain, account parc) is missing and was not restored; "
                          "unlock 1Password and rerun the release")
        if not identity_path.is_file():
            candidates = developer_id.IDENTITY.findall(identities)
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
        profile = self.env["PARC_NOTARY_PROFILE"] = os.environ.get("PARC_NOTARY_PROFILE", "parc-notary")
        missing = ("The notarytool profile " + profile + " is missing or failing and was not restored; "
                   "unlock 1Password and rerun the release")
        found = self.notary_profile(profile)
        if found == notary_service.CREDENTIALS:
            if not self.restore_credentials("restore-notary-profile"):
                raise Failure(missing)
            found = self.notary_profile(profile)
            if found == notary_service.CREDENTIALS:
                raise Failure(missing)
        if found != notary_service.OK:
            raise Failure("notarytool history failed with the " + profile + " profile, and the error is neither an "
                          "Apple outage nor a credential problem; see " + str(self.log))
        self.checkpoint(identity=identity, notary_profile=self.env["PARC_NOTARY_PROFILE"])

    def notary_profile(self, profile):
        history = notary_service.history(profile)

        def attempt():
            try:
                return subprocess.CompletedProcess(history, 0, self.command(history, capture=True), "")
            except Failure as error:
                return subprocess.CompletedProcess(history, error.code, error.output, "")
        try:
            return notary_service.wait(attempt, self.emit)[0]
        except notary_service.Refusal as error:
            raise Failure(str(error)) from None

    def ancestor(self, older, newer):
        return subprocess.run(["git", "merge-base", "--is-ancestor", older, newer],
                              cwd=self.root, env=self.env, capture_output=True).returncode == 0

    def published(self, commit):
        return self.ancestor(commit, "origin/main")

    def changes(self, revision):
        self.git('fetch', '--no-tags', 'origin', 'refs/tags/v*:refs/tags/v*', retries=2)
        tag = release_notes.last_release(self.root, revision)
        return tag, release_notes.changes(self.root, tag, revision)

    def contents(self, revision, path):
        result = subprocess.run(['git', 'cat-file', 'blob', revision + ':' + path], cwd=self.root, env=self.env,
                                capture_output=True)
        return result.stdout if result.returncode == 0 else None

    def swift_inputs(self, revision):
        try:
            compiler = subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '--version'], env=self.env,
                                      capture_output=True, text=True).stdout.strip()
        except OSError:
            compiler = ''
        return self.git('ls-tree', revision, '--', *SWIFT_INPUTS) + '\n' + compiler

    def check_source(self, commit, tag, untouched):
        self.check_overlay(commit, tag, untouched)
        self.check_swift(commit, untouched)

    def check_overlay(self, commit, tag, untouched):
        raw, published = self.contents(commit, OVERLAY), self.contents(tag, OVERLAY)
        if raw is None or published is None:
            return
        spec, before = json.loads(raw), json.loads(published)
        lock = json.loads(self.contents(commit, LOCK) or b'{}')

        def inputs(manifest):
            prefix = '' if manifest.get('source_root', 'manifest') == 'repository' else OVERLAY.rpartition('/')[0] + '/'
            return {prefix + item['source']: item['sha256'] for item in [*manifest.get('files', []), *manifest.get('patches', [])]}
        current, earlier = inputs(spec), inputs(before)
        diff = subprocess.run(['git', 'diff', '--name-only', '--no-renames', '-z', tag, commit], cwd=self.root,
                              env=self.env, capture_output=True, check=True).stdout.split(b'\0')
        changed = (set(current) | set(earlier)) & {os.fsdecode(name) for name in diff if name}
        stale = sorted(path for path in changed if path in current
                       and hashlib.sha256(self.contents(commit, path) or b'').hexdigest() != current[path])
        needed = before['version'] + 1
        unraised = spec['version'] < needed
        if spec['id'] != before['id']:
            raise Failure(OVERLAY + ' changed its ID since ' + tag + ', and an overlay update must keep its ID. ' + untouched)
        if lock and spec.get('upstream') != {'chromium': lock.get('chromium', {}).get('commit')}:
            raise Failure(OVERLAY + "'s upstream Chromium commit doesn't match " + LOCK + '; update the overlay for '
                          'that lock on main and rerun the release. ' + untouched)
        if stale:
            raise Failure(listing(stale) + ' changed since ' + tag + ' without a matching checksum in ' + OVERLAY
                          + '; refresh the overlay manifest' + (', raising its version to ' + str(needed) if unraised else '')
                          + ', on main and rerun the release. ' + untouched)
        if (raw != published or changed) and unraised:
            raise Failure('Engine inputs changed since ' + tag + ' but ' + OVERLAY + ' is still version '
                          + str(spec['version']) + '; raise it to ' + str(needed) + ' on main and rerun the release. '
                          + untouched)

    def check_swift(self, commit, untouched):
        key = self.swift_inputs(commit)
        if self.state.get('swift_checked') == key:
            self.emit('Reusing the release-mode Swift compile that passed for these sources')
            return
        folder = Path(self.state['run']) / 'swift-check' / commit
        source = folder / 'source'
        release_inputs.create(self.root, source, commit)
        label = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
        self.emit('Compiling ' + commit + ' in release mode before the version commit')
        try:
            self.command([sys.executable, source / 'scripts/check-swift.py', '--repo', source, '--source-archive',
                          '--mode', 'release', '--output-dir', folder, '--label', label], name='swift-check')
        except Failure:
            log = folder / label / 'compiler.log'
            raise Failure('The release-mode Swift compile of ' + commit + ' failed; see '
                          + str(log if log.exists() else Path(self.state['run']) / 'swift-check.log') + '. ' + untouched) from None
        shutil.rmtree(source)
        self.checkpoint(swift_checked=key)

    def version_files(self, base):
        notes = json.loads(self.git('show', base + ':release-notes.json'))
        version, entry = self.state['version'], self.state['notes']
        changes = [{**{key: change[key] for key in CHANGE_KEYS if key in change}, **change} for change in entry['changes']]
        entry = release_notes.entry(entry['version'], entry['build'], entry['date'], changes)
        return {'app-version.json': json.dumps({'version': version['version'], 'build': version['build']}, indent=2) + '\n',
                **release_notes.files(notes, entry, self.state['since'][1:])}

    def prepare(self):
        if self.git("branch", "--show-current") != "main":
            raise Failure("Use main; all local changes are preserved")
        if self.state.get("source_frozen"):
            release_inputs.verify(self.root, self.state["source"], self.state["commit"])
            return
        if not self.state.get("version"):
            for _ in range(CHECK_ROUNDS):
                self.require_clean("Start on clean main; never reset/stash/clean local changes")
                self.checkpoint(quiet_seconds=None, quiet_head=None, quiet_since=None)
                self.git("fetch", "origin", "main", retries=2)
                self.fast_forward()
                head = self.git('rev-parse', 'HEAD')
                if head != self.git('rev-parse', 'origin/main'):
                    raise Failure('Local main has unpushed commits; preserved without releasing them')
                previous = app_version.read(self.root)
                if previous['build'] >= 9999:
                    raise Failure("Apple bundle build number exhausted")
                tag, found = self.changes(head)
                kind = self.kind or release_notes.bump(found)
                if not kind:
                    raise Failure('Nothing to release since ' + tag + '; main changed after the release check')
                self.check_source(head, tag, 'Nothing was committed or pushed.')
                self.git("fetch", "origin", "main", retries=2)
                if (self.git('rev-parse', 'HEAD') == head == self.git('rev-parse', 'origin/main')
                        and not blocking(self.local_changes())):
                    break
                self.emit('Main changed during the release checks; checking its newest commit')
            else:
                raise Failure('Main kept changing release inputs during ' + str(CHECK_ROUNDS) + ' rounds of release '
                              'checks; nothing was committed or pushed, so rerun the release')
            version = {"version": next_version(previous["version"], kind), "build": previous["build"] + 1}
            date = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
            self.checkpoint(release_type=kind, type_override=self.kind, previous_version=previous, version=version,
                            since=tag, notes=release_notes.entry(version['version'], version['build'], date, found),
                            base_commit=head, tag='v' + version['version'],
                            source=str(Path(self.state['run']) / 'source'))
            self.kind = kind
        wanted = self.state['version']
        if not self.state.get('commit'):
            files = self.version_files(self.state['base_commit'])
            head = self.git('rev-parse', 'HEAD')
            if head != self.state['base_commit']:
                parent = self.git('rev-parse', 'HEAD^')
                changed = self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()
                if (parent != self.state['base_commit'] or sorted(changed) != sorted(files)
                        or any(self.git('show', 'HEAD:' + name) != text.strip() for name, text in files.items())):
                    raise Failure('Source changed during version transaction; preserved for reconciliation')
            else:
                unexpected = Failure('Unexpected local edits during version transaction; preserved')
                blobs = {name: self.blob(text) for name, text in files.items()}
                changes = self.local_changes()
                if blocking(changes, files) or any(
                        code == 'UU' or self.text(name) != files[name]
                        or (code != '??' and index not in (committed, blobs[name]))
                        for name, (code, committed, index) in changes.items() if name in files):
                    raise unexpected
                message = 'chore(release): ' + wanted['version']
                commit = self.git('commit-tree', self.tree(head, files), '-p', head, '-m', message)
                for name, text in files.items():
                    if self.text(name) != text:
                        (self.root / name).write_text(text)
                self.git('add', '--', *files, retries=2)
                staged = {fields[3]: fields[1] for fields in
                          map(str.split, self.git('ls-files', '-s', '--', *files).splitlines())}
                if staged != blobs:
                    raise unexpected
                try:
                    self.git('update-ref', '-m', 'commit: ' + message, 'refs/heads/main', commit, head)
                except Failure:
                    raise Failure('Source changed during version transaction; preserved for reconciliation') from None
                head = commit
            self.checkpoint(commit=head)
        for attempt in range(4):
            self.git('fetch', 'origin', 'main', retries=2)
            commit = self.state['commit']
            if self.published(commit):
                break
            remote_version = json.loads(self.git('show', 'origin/main:app-version.json'))
            if remote_version != self.state['previous_version']:
                raise Failure('Another release changed the remote version; no retagging or automatic version replacement')
            if not self.ancestor('origin/main', commit):
                tip = self.git('rev-parse', 'origin/main')
                ours = self.git('diff-tree', '-r', '--name-only', self.git('merge-base', commit, tip), commit).splitlines()
                if not set(ours) <= set(self.version_files(tip)):
                    raise Failure('The version commit carries changes main lacks; preserved for reconciliation')
                since, found = self.changes(tip)
                self.check_source(tip, since, 'The version commit was not pushed.')
                kind = self.state.get('type_override') or release_notes.bump(found) or self.kind
                raised = next_version(self.state['previous_version']['version'], kind)
                if release_notes.number(raised) > release_notes.number(wanted['version']):
                    self.emit('Commits that landed before the push raise ' + wanted['version'] + ' to ' + raised)
                    self.kind, wanted = kind, {'version': raised, 'build': wanted['build']}
                notes = release_notes.entry(wanted['version'], wanted['build'], self.state['notes']['date'], found)
                self.checkpoint(release_type=self.kind, version=wanted, tag='v' + wanted['version'],
                                notes=notes, since=since)
                self.checkpoint(commit=self.git('commit-tree', self.tree(tip, self.version_files(tip)), '-p', commit,
                                                '-p', tip, '-m', 'chore(release): ' + wanted['version']))
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
        engine_tool = module(source, "engine-source")
        selected_lock, _ = engine_tool.load_lock(lock)
        overlay = source / "Engine/ParcHost/overlay.json"
        self.checkpoint(workspace=str(workspace), overlay=json.loads(overlay.read_text())["version"])
        if not (workspace / ".parc-engine-source.json").exists() and (not workspace.exists() or not any(workspace.iterdir())):
            workspace.parent.mkdir(parents=True, exist_ok=True)
            self.command([sys.executable, script, "sync", "--workspace", workspace], name="engine-sync")
        elif not (workspace / ".parc-engine-source.json").is_file():
            raise Failure("Existing workspace is unowned; preserved without adoption or deletion")
        workspace = self.move_engine_to_lock(script, workspace, lock)
        if not self.state.get('interrupted_process_group'):
            superseded = self.superseded_shipping_build()
            if superseded:
                self.checkpoint(interrupted_process_group=superseded['command_pid'],
                                interrupted_inputs_replaced=superseded['id'])
        if self.state.get('interrupted_process_group'):
            self.command([sys.executable, self.root / 'scripts/release_recover.py', source, workspace,
                          str(self.state['interrupted_process_group']), Path(self.state['run']) / 'cancelled-shipping-receipt.json',
                          *(['--inputs-replaced'] if self.state.get('interrupted_inputs_replaced')
                            or self.state.get('interrupted_inputs_refreshed') else [])],
                         name='recover-cancelled-engine')
            if self.state.get('interrupted_inputs_replaced'):
                retired = self.base / self.state['interrupted_inputs_replaced'] / 'state.json'
                save(retired, dict(json.loads(retired.read_text()), cancelled_build_recovered=self.state['id']))
            self.checkpoint(interrupted_process_group=None, interrupted_inputs_replaced=None,
                            interrupted_inputs_refreshed=None)
        self.git("fetch", "origin", "main", retries=2)
        if hasattr(engine_tool, "reset_source"):
            self.command([sys.executable, script, "reset-source", "--workspace", workspace], name="engine-reset-source")
        self.command([sys.executable, script, "overlay-check", "--workspace", workspace, "--manifest", overlay], name="overlay-check")
        current = json.loads((workspace / ".parc-engine-source.json").read_text())
        if current.get("overlay", {}).get("identity") != sha(overlay):
            self.command([sys.executable, script, "overlay-apply", "--workspace", workspace, "--manifest", overlay], name="overlay-apply")
        output = workspace / "chromium/src/out" / engine_tool.SHIPPING_CONFIGURATION
        manifest = Path(self.state.get('engine_seal_path', str(Path(self.state['run']) / 'engine-artifacts.json')))
        self.checkpoint(engine_seal_path=str(manifest))
        if manifest.exists():
            self.command([sys.executable, source / 'scripts/release_engine.py', source, manifest, output], name='verify-resumed-engine')
            self.checkpoint(manifest=str(manifest), manifest_sha256=sha(manifest))
            return
        try:
            self.command([sys.executable, source / "scripts/build.py", "seal-engine", "--engine-dir", output, "--manifest", manifest, "--purpose", "distribution"], name="engine-reuse")
        except Failure:
            jobs = str(engine_jobs())
            generated = json.loads((workspace / '.parc-engine-source.json').read_text())
            if generated.get('phase') not in ('generated', 'built'):
                self.command([sys.executable, script, "generate", "--workspace", workspace, "--jobs", jobs], name="engine-generate")
            self.git("fetch", "origin", "main", retries=2)
            self.command([sys.executable, script, "shipping-build", "--workspace", workspace, "--jobs", jobs], name="engine-build")
            self.command([sys.executable, source / "scripts/build.py", "seal-engine", "--engine-dir", output, "--manifest", manifest, "--purpose", "distribution"], name="engine-seal")
        self.checkpoint(manifest=str(manifest), manifest_sha256=sha(manifest))

    def move_engine_to_lock(self, script, workspace, lock):
        old = json.loads((workspace / ".parc-engine-source.json").read_text())
        if old["lock_sha256"] == sha(lock):
            return workspace
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
            return {**value,
                    'build': {k: v for k, v in value['build'].items() if k != 'gn_defines'}}
        if sources(before) == sources(after):
            self.command([sys.executable, script, 'reconfigure', '--workspace', workspace,
                          '--previous-lock', previous], name='engine-reconfigure')
        elif retargetable(before, after):
            self.command([sys.executable, script, 'retarget', '--workspace', workspace,
                          '--previous-lock', previous], name='engine-retarget')
        else:
            workspace = workspace.with_name(workspace.name + '-' + sha(lock)[:12])
            self.checkpoint(workspace=str(workspace))
            self.command([sys.executable, script, 'sync', '--workspace', workspace], name='engine-sync')
        return workspace

    def package(self):
        source = Path(self.state["source"]); package_run = Path(self.state["run"]) / "package"
        self.env.update(PARC_RELEASE_REPOSITORY=str(self.root), PARC_RELEASE_COMMIT=self.state["commit"],
                        PARC_PACKAGE_RUN=str(package_run), PARC_ENGINE_WORKSPACE=self.state["workspace"])
        try:
            self.command(["bash", source / "scripts/package-app.sh", "--stable", self.state["manifest"]], name="package-publish")
        except Failure as error:
            if error.code == notary_service.EXIT_DOWN:
                raise Failure(notary_service.Unavailable().args[0]) from None
            if error.code == notary_service.EXIT_AGREEMENT:
                raise Failure(notary_service.ACCEPT_AGREEMENT) from None
            raise
        self.checkpoint(package=str(package_run / "development"))

    def appcast(self):
        source = Path(self.state["source"]); run = Path(self.state["run"]); version = self.state["version"]["version"]
        if not self.state.get("appcast_published"):
            self.checkpoint(appcast_published=now())
        output = run / "appcast.xml"
        self.command([sys.executable, source / "scripts/appcast.py", Path(self.state["package"]) / "Parc.app",
                      run / "package" / ("Parc-" + version + "-arm64.zip"), output,
                      "--published", self.state["appcast_published"]], name="appcast")
        self.checkpoint(appcast=str(output), appcast_sha256=sha(output))

    def tap(self):
        source = Path(self.state["source"]); tap = Path.home() / "homebrew-tap"
        if not tap.exists():
            self.command(["git", "clone", "https://github.com/etsenake/homebrew-tap.git", tap], name="tap-clone", retries=2)
        self.command([sys.executable, self.root / "scripts/publish-homebrew.py", self.state["tag"], "--tap", tap,
                      "--artifact-only", "--resume", "--appcast", self.state["appcast"]], name="tap-update")
        self.git("diff", "--check", cwd=tap)
        self.command(["brew", "ruby", "--", "-c", tap / "Casks/parc.rb"], name="tap-syntax")
        if self.git("status", "--porcelain", "--untracked-files=no", cwd=tap):
            self.git("commit", "--only", "Casks/parc.rb", "-m", "Release Parc " + self.state["version"]["version"], cwd=tap)
            head = self.git("rev-parse", "HEAD", cwd=tap)
            self.git("push", "origin", head + ":refs/heads/main", cwd=tap, retries=2)
        self.git('fetch', 'origin', 'main', cwd=tap, retries=2)
        head = self.git('rev-parse', 'HEAD', cwd=tap)
        remote = self.git('ls-remote', 'origin', 'refs/heads/main', cwd=tap).split()[0]
        if head != remote:
            self.git('push', 'origin', head + ':refs/heads/main', cwd=tap, retries=2)
            if self.git('ls-remote', 'origin', 'refs/heads/main', cwd=tap).split()[0] != head:
                raise Failure('Tap commit publication was not verified')
        self.command(["brew", "tap", "etsenake/tap"], name="tap-register")
        self.command(["brew", "trust", "--tap", "etsenake/tap"], name="tap-trust")
        installed_tap = Path(self.command(["brew", "--repo", "etsenake/tap"], capture=True))
        if self.git("status", "--porcelain", "--untracked-files=no", cwd=installed_tap):
            raise Failure("Installed Homebrew tap has local edits; preserved without overwriting")
        self.git("fetch", "origin", "main", cwd=installed_tap, retries=2)
        self.git("merge", "--ff-only", "origin/main", cwd=installed_tap)
        self.command(["brew", "audit", "--cask", "etsenake/tap/parc"], name="tap-audit")
        self.checkpoint(tap=str(tap), tap_commit=self.git("rev-parse", "HEAD", cwd=tap))

    def verify_feed(self):
        public = json.loads(self.github('api', 'repos/' + PUBLIC_REPOSITORY + '/releases/latest'))
        feed = {item['name']: item.get('digest') for item in public['assets']}.get('appcast.xml')
        if public['tag_name'] != self.state['tag'] or feed != 'sha256:' + self.state['appcast_sha256']:
            raise Failure("The public latest release does not serve this release's appcast")

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
        self.verify_feed()
        delivery = {'schema_version': 1, 'status': 'published', 'source_commit': self.state['commit'],
                    'engine_overlay': self.state['overlay'], 'overlay_identity': report['overlay']['identity'],
                    'engine_manifest': self.state['manifest'], 'engine_manifest_sha256': self.state['manifest_sha256'],
                    'package': str(package), 'package_report_sha256': sha(report_path),
                    'release_tag': self.state['tag'], 'release_url': published['html_url'],
                    'app_version': self.state['version'], 'signing_team': report['signing_team'],
                    'notarization': report['notarization'], 'tap_commit': self.state['tap_commit'],
                    'appcast': self.state['appcast'], 'appcast_sha256': self.state['appcast_sha256'],
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
            os.environ['GH_TOKEN'] = self.env['GH_TOKEN']
            os.environ.pop('GITHUB_TOKEN', None)
            if not self.state.get('source_frozen'):
                self.git('fetch', 'origin', 'main', retries=2)
            if not self.kind and not self.state.get('version'):
                tag, found = self.changes('origin/main')
                if not release_notes.bump(found):
                    if self.state.get('lease'):
                        release_lease.release(self.state['lease'])
                    self.checkpoint(status='nothing-to-release', lease=None)
                    self.emit('Nothing to release since ' + tag)
                    return 0
            lease = release_lease.acquire(self.state['id'], self.state.get('commit') or self.git('rev-parse', 'origin/main'), self.state.get('lease'))
            self.checkpoint(lease=lease)
            if self.refresh_source or self.state.get('refresh_commit'):
                self.refresh_inputs()
            for name, action in [("source", self.prepare), ("engine", self.engine), ("package", self.package),
                                 ("appcast", self.appcast), ("homebrew", self.tap)]:
                if name in self.state["completed"]:
                    if name == 'source':
                        release_inputs.verify(self.root, self.state['source'], self.state['commit'])
                    if name == 'engine' and sha(self.state['manifest']) != self.state['manifest_sha256']:
                        raise Failure('Completed engine seal changed; preserved without retargeting')
                    if name == 'appcast' and sha(self.state['appcast']) != self.state['appcast_sha256']:
                        raise Failure('Completed appcast changed; preserved without signing again')
                    self.emit("Reusing completed " + name + " stage")
                    continue
                self.checkpoint(stage=name)
                action()
                self.state["completed"].append(name)
                self.checkpoint()
            self.finish()
            self.emit("Released " + self.state["tag"] + "; notarized assets and published Homebrew cask verified")
            return 0
        except Exception as error:
            self.emit(str(error) if isinstance(error, (Failure, RuntimeError, OSError, ValueError, subprocess.SubprocessError))
                      else "".join(traceback.format_exception(error)).strip())
            if self.state:
                self.checkpoint(status="stopped", error=str(error) or type(error).__name__)
            return 1
        except KeyboardInterrupt as error:
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
    if sys.version_info < (3, 12):
        raise SystemExit("Production releases need Python 3.12 or later; start them with: bash scripts/release.sh")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", choices=("major", "minor", "patch"),
                        help="Override the bump Conventional Commits since the last release tag would choose")
    parser.add_argument("--refresh-source", action="store_true",
                        help="Use published fixes for a stopped, unsealed engine build without bumping again")
    parser.add_argument("--source-commit", help="Full published commit SHA to freeze for an explicit source refresh")
    args = parser.parse_args()
    if args.source_commit and not args.refresh_source:
        parser.error('--source-commit requires --refresh-source')
    return Release(kind=args.type, refresh_source=args.refresh_source, source_commit=args.source_commit).run()


if __name__ == "__main__":
    raise SystemExit(main())

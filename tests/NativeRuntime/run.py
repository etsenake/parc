#!/usr/bin/env python3
"""Run the sealed native controller harness with a new disposable profile.

Does not build, sign, change Keychain, reuse profiles or report network coverage.
Logs and the disposable profile remain at the printed path, including on failure.
"""
import argparse
from contextlib import contextmanager, nullcontext
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

MARKER = "parc-native-runtime-test.marker"
PAYLOAD = "Parc native runtime test v1\n"
REGISTRATION = "NATIVE_REGISTRATION_PASS manager=true global=true tab=true supplied_window=true"
ACCESSIBILITY = "NATIVE_ACCESSIBILITY_PASS requested_basic_mode=true live_tree=true native_web_area=true"
PAGE_EVENTS = "NATIVE_PAGE_EVENTS_PASS renderer_failure=true nested_deferred=true recovered=true metadata=true"
RENDERER_CRASH = ("NATIVE_RENDERER_CRASH_PASS snapshot_status=true persistent_detach=true "
                  "stale_action_rejected=true cleared_on_recovery=true")
ACCESSIBILITY_SHUTDOWN = "NATIVE_ACCESSIBILITY_SHUTDOWN_PASS query_after_shutdown=true"


def fresh_root(parent):
    parent = parent.resolve(strict=True)
    if not parent.is_dir():
        raise ValueError("artifacts must be an existing directory")
    root = Path(tempfile.mkdtemp(prefix="parc-runtime-", dir=parent))
    root.chmod(0o700)
    fd = os.open(str(root / MARKER), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(PAYLOAD)
    return root


def verdict(status, stdout, timed_out):
    if timed_out or status != 0:
        return False
    lines = stdout.splitlines()
    expected = [f"HTTP_AUTH_CONTROLLER_{i} PASS:" for i in range(3)]
    return (all(sum(line.startswith(prefix) for line in lines) == 1 for prefix in expected)
            and lines.count(REGISTRATION) == 1
            and lines.count(ACCESSIBILITY) == 1
            and lines.count(PAGE_EVENTS) == 1
            and lines.count(RENDERER_CRASH) == 1
            and lines.index(ACCESSIBILITY) < lines.index(PAGE_EVENTS)
            and lines.index(PAGE_EVENTS) < lines.index(RENDERER_CRASH)
            and lines.index(RENDERER_CRASH) < next(i for i, line in enumerate(lines)
                                                  if line.startswith(expected[0]))
            and lines.count(ACCESSIBILITY_SHUTDOWN) == 1
            and next(i for i, line in enumerate(lines) if line.startswith(expected[-1]))
                < lines.index(ACCESSIBILITY_SHUTDOWN)
            and lines.index(REGISTRATION) < lines.index(ACCESSIBILITY)
            and lines.index(ACCESSIBILITY) < next(i for i, line in enumerate(lines)
                                                  if line.startswith(expected[0]))
            and lines.index(REGISTRATION) < next(i for i, line in enumerate(lines)
                                                 if line.startswith(expected[0]))
            and sum(line == "NATIVE_RUNTIME_PASS cases=3 synthetic_http_auth=true clean_shutdown=true"
                    for line in lines) == 1
            and not any("FAIL" in line for line in lines))


ENGINE_SELECTION = ("NATIVE_ENGINE_SELECTION_PASS exact_page=true deferred=true geometry_preserved=true "
                    "latest_wins=true shell_override=true")
EXTENSION_SNAPSHOT = "NATIVE_EXTENSION_SNAPSHOT_PASS real_profile=true copied=true pin_model=true pin_order=true"
EXTENSION_SELECTION = ("NATIVE_EXTENSION_SELECTION_PASS unselected_empty=true "
                       "stale_execute_rejected=true stale_pin_rejected=true no_grant=true")
EXTENSION_GRANT = ("NATIVE_EXTENSION_GRANT_PASS real_action=true selected_tab=true "
                   "loopback_host=true other_tab_denied=true other_origin_denied=true")
EXTENSION_COMPLETE = "NATIVE_EXTENSION_RUNTIME_PASS clean_shutdown=true"


def extension_verdict(status, stdout, timed_out):
    if timed_out or status != 0:
        return False
    lines = stdout.splitlines()
    markers = [REGISTRATION, ENGINE_SELECTION, EXTENSION_SNAPSHOT, EXTENSION_SELECTION,
               EXTENSION_GRANT, ACCESSIBILITY_SHUTDOWN, EXTENSION_COMPLETE]
    return (all(lines.count(marker) == 1 for marker in markers)
            and [lines.index(marker) for marker in markers] == sorted(lines.index(marker) for marker in markers)
            and not any("FAIL" in line for line in lines))


PIP_CASES = ("close_pauses", "hide_keeps_playback", "native_close_destroys",
             "reentry_keeps_identity", "return_original_without_pause",
             "resize_notifies_session", "compositor_bounds")
PIP_COMPLETE = "NATIVE_PIP_RUNTIME_PASS cases=7 clean_shutdown=true"


def pip_verdict(status, stdout, timed_out):
    if timed_out or status != 0:
        return False
    lines = stdout.splitlines()
    markers = [REGISTRATION] + [f"NATIVE_PIP_CASE_{i} PASS: {name}"
                                for i, name in enumerate(PIP_CASES)] + [
        ACCESSIBILITY_SHUTDOWN, PIP_COMPLETE]
    return (all(lines.count(marker) == 1 for marker in markers)
            and [lines.index(marker) for marker in markers] == sorted(lines.index(marker) for marker in markers)
            and not any("FAIL" in line for line in lines)
            and sum(line.startswith("NATIVE_PIP_CASE_") for line in lines) == 7)


@contextmanager
def video_fixture_server(app):
    """Serve the package-bound real upstream media on one loopback origin."""
    report = json.loads((app.parent / "runtime-package-report.json").read_text())
    body = (app / "Contents/Resources/NativeVideoFixture/bear.webm").read_bytes()
    digest = hashlib.sha256(body).hexdigest()
    if not body or digest != report.get("video_fixture_sha256"):
        raise ValueError("Packaged media fixture differs from its bound report")
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/bear.webm":
                self.send_error(404)
                return
            first, last = 0, len(body) - 1
            partial = self.headers.get("Range")
            if partial:
                import re
                match = re.fullmatch(r"bytes=(\d+)-(\d*)", partial)
                if not match or int(match[1]) >= len(body):
                    self.send_error(416)
                    return
                first = int(match[1])
                if match[2]:
                    last = min(int(match[2]), last)
                if last < first:
                    self.send_error(416)
                    return
            self.send_response(206 if partial else 200)
            self.send_header("Content-Type", "video/webm")
            self.send_header("Content-Length", str(last - first + 1))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "no-store")
            if partial:
                self.send_header("Content-Range", f"bytes {first}-{last}/{len(body)}")
            self.end_headers()
            self.wfile.write(body[first:last + 1])
        def log_message(self, *_args):
            pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield {"url": f"http://127.0.0.1:{server.server_port}/bear.webm", "sha256": digest}
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@contextmanager
def extension_fixture_server():
    """One launcher-owned origin, existing fixture only; no external server."""
    body = (Path(__file__).parent / "fixtures/extension-actions.html").read_bytes()
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ("/extension-actions.html?tab=first", "/extension-actions.html?tab=second"):
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *_args):
            pass  # No URLs, headers or page text in the receipt.
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, name="parc-runtime-fixture", daemon=True)
    thread.start()
    try:
        yield {"url": f"http://127.0.0.1:{server.server_port}/extension-actions.html",
               "sha256": hashlib.sha256(body).hexdigest()}
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--deadline", type=int, default=120)
    parser.add_argument("--suite", choices=("controllers", "extension-actions", "video-pip"), default="controllers")
    args = parser.parse_args()
    if not 100 <= args.deadline <= 300:
        parser.error("deadline must be 100..300 seconds (above the internal 80-second deadline)")
    app = args.app.resolve(strict=True)
    if app.name != "parc_native_runtime_tests.app" or not app.is_dir():
        parser.error("expected the exact focused runtime test app bundle")
    executable = app / "Contents/MacOS/parc_native_runtime_tests"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error("test executable is absent")
    # The same closure/signing prerequisite as the production app. This does
    # not bless external component dylibs or claim Seatbelt execution passed.
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(app)], check=True)
    root = fresh_root(args.artifacts)
    log_dir = root.parent / (root.name + "-logs")
    log_dir.mkdir(mode=0o700)
    print(f"Disposable profile: {root}", flush=True)
    print(f"Logs: {log_dir}", flush=True)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("DYLD_") and key not in ("CEF_ROOT", "CHROME_LOG_FILE")}
    # Official Chromium switch: selects its FakeKeychainV2. Never supplied to a
    # normal user profile; the executable independently checks our fresh marker.
    env["MallocNanoZone"] = "0"
    command = [str(executable), str(root), "--use-mock-keychain"]
    started = time.monotonic()
    timed_out = False
    fixture = None
    fixture_context = (extension_fixture_server() if args.suite == "extension-actions" else
                       video_fixture_server(app) if args.suite == "video-pip" else nullcontext(None))
    with fixture_context as fixture:
        if fixture:
            command += ["--video-pip" if args.suite == "video-pip" else "--extension-actions", fixture["url"]]
        with (log_dir / "stdout.log").open("w") as out, (log_dir / "stderr.log").open("w") as err:
            process = subprocess.Popen(command, env=env, stdout=out, stderr=err, start_new_session=True)
            try:
                status = process.wait(timeout=args.deadline)
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    status = process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    status = process.wait()
    stdout = (log_dir / "stdout.log").read_text(errors="replace")
    check = (pip_verdict if args.suite == "video-pip" else
             extension_verdict if args.suite == "extension-actions" else verdict)
    passed = check(status, stdout, timed_out)
    record = {"command": command, "exit_code": status, "timed_out": timed_out,
              "duration_seconds": time.monotonic() - started, "passed": passed,
              "coverage": "real native Browser registration/page ownership and demand-triggered basic native accessibility WebArea; genuine disposable renderer failure/deferred notification/same-page recovery, actual crash snapshot status/detach persistence/reset/stale-action rejection; synthetic real LoginHandler accept/cancel/detach; not native Swift Retry interaction, tab transfer or HTTP 401/407",
              "profile": str(root), "forced_cleanup": timed_out}
    record["suite"] = args.suite
    if args.suite == "extension-actions":
        record["coverage"] = ("real native Profile and two actual tabs; engine-to-shell exact-page selection after "
                              "observer unwind, geometry-only synchronization, latest-selection and explicit-command override; "
                              "copied action snapshots and real pin model; "
                              "unselected/stale selection rejection; genuine action activeTab grant and per-tab "
                              "launcher-owned loopback host permission; not popup, side panel, menu or GUI gesture acceptance")
        record["fixture_sha256"] = fixture["sha256"]
    if args.suite == "video-pip":
        record["coverage"] = ("seven real native video PiP controller cases using the production factory/presenter, "
                              "exact original document and JS test activation/promise resolution; "
                              "not physical pointer, visual pixels, Return focus/input or whole media parity")
        record["fixture_sha256"] = fixture["sha256"]
    (log_dir / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    print(stdout, end="")
    print("PASS" if passed else "FAIL (see retained logs; no clean-shutdown claim on timeout)")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

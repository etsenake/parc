#!/usr/bin/env python3
"""Test profile/receipt guards only; never launches Chromium or fakes its result."""
import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
import urllib.request
import urllib.error

spec = importlib.util.spec_from_file_location("native_runtime_launcher", Path(__file__).with_name("run.py"))
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

class LauncherTest(unittest.TestCase):
    def test_fresh_marker_and_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            first = launcher.fresh_root(Path(directory))
            second = launcher.fresh_root(Path(directory))
            self.assertNotEqual(first, second)
            self.assertEqual(stat.S_IMODE(first.stat().st_mode), 0o700)
            marker = first / launcher.MARKER
            self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
            self.assertEqual(marker.read_text(), launcher.PAYLOAD)
            self.assertEqual(list(first.iterdir()), [marker])
    def test_complete_receipt(self):
        receipt = "\n".join([launcher.REGISTRATION, launcher.ACCESSIBILITY, launcher.PAGE_EVENTS, launcher.RENDERER_CRASH] +
            [f"HTTP_AUTH_CONTROLLER_{i} PASS: checked" for i in range(3)] +
            [launcher.ACCESSIBILITY_SHUTDOWN,
             "NATIVE_RUNTIME_PASS cases=3 synthetic_http_auth=true clean_shutdown=true"])
        self.assertTrue(launcher.verdict(0, receipt, False))
        self.assertFalse(launcher.verdict(1, receipt, False))
        self.assertFalse(launcher.verdict(0, receipt, True))
        self.assertFalse(launcher.verdict(0, receipt + "\nFAIL", False))
        self.assertFalse(launcher.verdict(0, receipt.replace("CONTROLLER_1", "CONTROLLER_0"), False))
        self.assertFalse(launcher.verdict(0, receipt.replace("clean_shutdown=true", "clean_shutdown=false"), False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.REGISTRATION + "\n", ""), False))
        self.assertFalse(launcher.verdict(0, launcher.REGISTRATION + "\n" + receipt, False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.REGISTRATION + "\n", "") +
                                         "\n" + launcher.REGISTRATION, False))

    def test_requires_native_accessibility_before_controller_cases(self):
        receipt = "\n".join([launcher.REGISTRATION, launcher.ACCESSIBILITY, launcher.PAGE_EVENTS, launcher.RENDERER_CRASH] +
            [f"HTTP_AUTH_CONTROLLER_{i} PASS: checked" for i in range(3)] +
            [launcher.ACCESSIBILITY_SHUTDOWN,
             "NATIVE_RUNTIME_PASS cases=3 synthetic_http_auth=true clean_shutdown=true"])
        self.assertTrue(launcher.verdict(0, receipt, False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.ACCESSIBILITY + "\n", ""), False))
        self.assertFalse(launcher.verdict(0, receipt + "\n" + launcher.ACCESSIBILITY, False))
        self.assertFalse(launcher.verdict(0, receipt.replace("native_web_area=true", "native_web_area=false"), False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.ACCESSIBILITY_SHUTDOWN + "\n", ""), False))
        self.assertFalse(launcher.verdict(0, receipt + "\n" + launcher.ACCESSIBILITY_SHUTDOWN, False))
        self.assertFalse(launcher.verdict(0, launcher.ACCESSIBILITY_SHUTDOWN + "\n" +
                                         receipt.replace(launcher.ACCESSIBILITY_SHUTDOWN + "\n", ""), False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.ACCESSIBILITY + "\n", "") +
                                         "\n" + launcher.ACCESSIBILITY, False))
        self.assertFalse(launcher.verdict(0, launcher.ACCESSIBILITY + "\n" +
                                         receipt.replace(launcher.ACCESSIBILITY + "\n", ""), False))

    def test_requires_page_event_probe_before_controller_cases(self):
        receipt = "\n".join([launcher.REGISTRATION, launcher.ACCESSIBILITY, launcher.PAGE_EVENTS, launcher.RENDERER_CRASH] +
            [f"HTTP_AUTH_CONTROLLER_{i} PASS: checked" for i in range(3)] +
            [launcher.ACCESSIBILITY_SHUTDOWN,
             "NATIVE_RUNTIME_PASS cases=3 synthetic_http_auth=true clean_shutdown=true"])
        self.assertTrue(launcher.verdict(0, receipt, False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.PAGE_EVENTS + "\n", ""), False))
        self.assertFalse(launcher.verdict(0, receipt + "\n" + launcher.PAGE_EVENTS, False))
        self.assertFalse(launcher.verdict(0, receipt.replace("nested_deferred=true", "nested_deferred=false"), False))
        self.assertFalse(launcher.verdict(0, receipt.replace(launcher.PAGE_EVENTS + "\n", "") +
                                         "\n" + launcher.PAGE_EVENTS, False))
        self.assertFalse(launcher.verdict(0, launcher.PAGE_EVENTS + "\n" +
                                         receipt.replace(launcher.PAGE_EVENTS + "\n", ""), False))

    def test_requires_actual_crash_snapshot_lifecycle_before_authentication(self):
        receipt = "\n".join([launcher.REGISTRATION, launcher.ACCESSIBILITY,
            launcher.PAGE_EVENTS, launcher.RENDERER_CRASH] +
            [f"HTTP_AUTH_CONTROLLER_{i} PASS: checked" for i in range(3)] +
            [launcher.ACCESSIBILITY_SHUTDOWN,
             "NATIVE_RUNTIME_PASS cases=3 synthetic_http_auth=true clean_shutdown=true"])
        self.assertTrue(launcher.verdict(0, receipt, False))
        # An earlier runner can pass page events without exercising the new
        # production crash state. Its old complete receipt is insufficient.
        old_receipt = receipt.replace(launcher.RENDERER_CRASH + "\n", "")
        self.assertFalse(launcher.verdict(0, old_receipt, False))
        self.assertFalse(launcher.verdict(0, receipt + "\n" + launcher.RENDERER_CRASH, False))
        for field in ("snapshot_status", "persistent_detach",
                      "stale_action_rejected", "cleared_on_recovery"):
            with self.subTest(field=field):
                self.assertFalse(launcher.verdict(0, receipt.replace(
                    field + "=true", field + "=false"), False))
        # It must follow the real crash/reload and precede authentication;
        # a premature or late marker cannot turn a partial run into success.
        early = old_receipt.replace(launcher.PAGE_EVENTS,
                                   launcher.RENDERER_CRASH + "\n" + launcher.PAGE_EVENTS)
        late = old_receipt.replace("HTTP_AUTH_CONTROLLER_0 PASS: checked",
                                  "HTTP_AUTH_CONTROLLER_0 PASS: checked\n" + launcher.RENDERER_CRASH)
        self.assertFalse(launcher.verdict(0, early, False))
        self.assertFalse(launcher.verdict(0, late, False))

    def test_extension_receipt_is_separate_and_complete(self):
        markers = [launcher.REGISTRATION, launcher.ENGINE_SELECTION, launcher.EXTENSION_SNAPSHOT,
                   launcher.EXTENSION_SELECTION, launcher.EXTENSION_GRANT,
                   launcher.ACCESSIBILITY_SHUTDOWN, launcher.EXTENSION_COMPLETE]
        receipt = "\n".join(markers)
        self.assertTrue(launcher.extension_verdict(0, receipt, False))
        self.assertFalse(launcher.verdict(0, receipt, False))
        self.assertFalse(launcher.extension_verdict(1, receipt, False))
        self.assertFalse(launcher.extension_verdict(0, receipt, True))
        self.assertFalse(launcher.extension_verdict(0, receipt + "\nFAIL", False))
        for marker in markers:
            with self.subTest(marker=marker):
                self.assertFalse(launcher.extension_verdict(0, receipt.replace(marker, ""), False))
                self.assertFalse(launcher.extension_verdict(0, receipt + "\n" + marker, False))
        self.assertFalse(launcher.extension_verdict(0, "\n".join(reversed(markers)), False))
        for field in ("copied", "pin_model", "pin_order", "unselected_empty", "stale_execute_rejected",
                      "stale_pin_rejected", "no_grant", "real_action", "selected_tab", "loopback_host",
                      "other_tab_denied", "other_origin_denied", "clean_shutdown", "exact_page",
                      "deferred", "geometry_preserved", "latest_wins", "shell_override"):
            with self.subTest(field=field):
                self.assertFalse(launcher.extension_verdict(0, receipt.replace(field + "=true", field + "=false"), False))

    def test_launcher_owns_real_loopback_fixture(self):
        # Exercises the actual server implementation and shutdown; no browser,
        # surrogate permission result or synthetic runtime PASS is produced.
        with launcher.extension_fixture_server() as fixture:
            for tab in ("first", "second"):
                with urllib.request.urlopen(fixture["url"] + "?tab=" + tab, timeout=2) as response:
                    data = response.read()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.headers["Cache-Control"], "no-store")
                    self.assertEqual(launcher.hashlib.sha256(data).hexdigest(), fixture["sha256"])
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(fixture["url"] + "?tab=other", timeout=2)
            self.assertEqual(error.exception.code, 404)
        with self.assertRaises(urllib.error.URLError):
            urllib.request.urlopen(fixture["url"] + "?tab=first", timeout=2)

    def test_pip_receipt_requires_each_real_case_and_cleanup(self):
        markers = [launcher.REGISTRATION] + [f"NATIVE_PIP_CASE_{i} PASS: {name}"
            for i, name in enumerate(launcher.PIP_CASES)] + [
                launcher.ACCESSIBILITY_SHUTDOWN, launcher.PIP_COMPLETE]
        receipt = "\n".join(markers)
        self.assertTrue(launcher.pip_verdict(0, receipt, False))
        self.assertFalse(launcher.verdict(0, receipt, False))
        self.assertFalse(launcher.extension_verdict(0, receipt, False))
        for status, timeout in ((1, False), (0, True)):
            self.assertFalse(launcher.pip_verdict(status, receipt, timeout))
        for marker in markers:
            with self.subTest(marker=marker):
                self.assertFalse(launcher.pip_verdict(0, receipt.replace(marker, ""), False))
                self.assertFalse(launcher.pip_verdict(0, receipt + "\n" + marker, False))
        self.assertFalse(launcher.pip_verdict(0, "\n".join(reversed(markers)), False))
        self.assertFalse(launcher.pip_verdict(0, receipt + "\nFAIL", False))
        self.assertFalse(launcher.pip_verdict(0, receipt.replace("cases=7", "cases=6"), False))
        self.assertFalse(launcher.pip_verdict(0, receipt.replace("clean_shutdown=true", "clean_shutdown=false"), False))
        self.assertFalse(launcher.pip_verdict(0, receipt + "\nNATIVE_PIP_CASE_7 PASS: unexpected", False))

    def test_video_transport_binds_package_hash_and_range(self):
        # Transport/provenance checks only. These bytes are not a media decode
        # or substitute for the real packaged bear.webm controller run.
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "parc_native_runtime_tests.app"
            media = app / "Contents/Resources/NativeVideoFixture/bear.webm"
            media.parent.mkdir(parents=True)
            body = bytes(range(32))
            media.write_bytes(body)
            report = app.parent / "runtime-package-report.json"
            report.write_text(launcher.json.dumps({"video_fixture_sha256": launcher.hashlib.sha256(body).hexdigest()}))
            with launcher.video_fixture_server(app) as fixture:
                url = fixture["url"]
                with urllib.request.urlopen(url, timeout=2) as response:
                    self.assertEqual(response.read(), body)
                    self.assertEqual(response.headers["Content-Type"], "video/webm")
                request = urllib.request.Request(url, headers={"Range": "bytes=4-9"})
                with urllib.request.urlopen(request, timeout=2) as response:
                    self.assertEqual(response.status, 206)
                    self.assertEqual(response.headers["Content-Range"], "bytes 4-9/32")
                    self.assertEqual(response.read(), body[4:10])
                for path, range_value, status in (("?stale=1", None, 404), ("", "bytes=32-", 416),
                                                  ("", "bytes=9-4", 416), ("", "bytes=0-2,4-5", 416)):
                    with self.subTest(path=path, range=range_value):
                        request = urllib.request.Request(url + path, headers={"Range": range_value} if range_value else {})
                        with self.assertRaises(urllib.error.HTTPError) as error:
                            urllib.request.urlopen(request, timeout=2)
                        self.assertEqual(error.exception.code, status)
            with self.assertRaises(urllib.error.URLError):
                urllib.request.urlopen(url, timeout=2)
            media.write_bytes(body + b"changed")
            with self.assertRaises(ValueError):
                with launcher.video_fixture_server(app):
                    self.fail("changed media must be refused before listening")

if __name__ == "__main__":
    unittest.main()

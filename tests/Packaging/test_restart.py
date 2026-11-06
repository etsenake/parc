"""Exercise the production restart waiter's real process/pipe lifecycle.

Only execl is replaced with a recorder; no browser or application is launched.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "kqueue process events require macOS")
class RestartHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="parc-restart-test-")
        cls.root = Path(cls.temporary.name)
        cls.helper = cls.root / "ParcRestart"
        wrapper = cls.root / "restart_fixture.c"
        wrapper.write_text(r'''
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int record_launch(const char *path, const char *arg, ...);
#define execl record_launch
#define main production_main
#include "main.c"
#undef main
#undef execl
static int record_launch(const char *path, const char *arg, ...) {
  FILE *file = fopen(getenv("PARC_RESTART_TEST_RECEIPT"), "w");
  if (!file) _exit(74);
  fprintf(file, "%s\n", path);
  va_list args; va_start(args, arg);
  while (arg) { fprintf(file, "%s\n", arg); arg = va_arg(args, const char *); }
  va_end(args); fclose(file); _exit(0);
}
int main(int argc, char **argv) { return production_main(argc, argv); }
''')
        subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        "-I", str(REPO / "Sources/ParcRestart"), str(wrapper),
                        "-o", str(cls.helper)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def launch(self, *extra):
        self.receipt = self.root / (self.id().split(".")[-1] + ".txt")
        environment = {**os.environ, "PARC_RESTART_TEST_RECEIPT": str(self.receipt)}
        return subprocess.Popen([str(self.helper), str(os.getpid()), "/Apps/Parc Dev.app", *extra],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=environment)

    def test_cancel_before_arming(self):
        child = self.launch()
        self.assertEqual(child.stdout.readline(), b"READY\n")
        self.assertEqual(child.communicate(b"CANCEL\n", timeout=3), (b"", b""))
        self.assertEqual(child.returncode, 0)
        self.assertFalse(self.receipt.exists())

    def test_cancel_after_arming(self):
        child = self.launch()
        self.assertEqual(child.stdout.readline(), b"READY\n")
        child.stdin.write(b"RESTART\n"); child.stdin.flush()
        self.assertIsNone(child.poll())
        child.communicate(b"CANCEL\n", timeout=3)
        self.assertEqual(child.returncode, 0)
        self.assertFalse(self.receipt.exists())

    def test_pipe_closure_without_permission(self):
        child = self.launch()
        self.assertEqual(child.stdout.readline(), b"READY\n")
        child.communicate(timeout=3)
        self.assertEqual(child.returncode, 0)
        self.assertFalse(self.receipt.exists())

    def test_reject_malformed_command(self):
        child = self.launch()
        child.communicate(b"RESTART /tmp/other\n", timeout=3)
        self.assertEqual(child.returncode, 64)
        self.assertFalse(self.receipt.exists())

    def test_reject_nonparent_pid(self):
        result = subprocess.run([str(self.helper), "1", "/Apps/Parc.app"], capture_output=True)
        self.assertEqual(result.returncode, 64)
        self.assertEqual(result.stdout, b"")

    def test_reject_unowned_arguments(self):
        child = self.launch("--url", "https://example.invalid")
        child.communicate(timeout=3)
        self.assertEqual(child.returncode, 64)

    def test_exact_parent_exit_and_argument_boundaries(self):
        receipt = self.root / "after-exit.txt"
        program = r'''
import os, subprocess, sys
child = subprocess.Popen([sys.argv[1], str(os.getpid()), "/Apps/Parc Dev.app",
                          "--parc-profile", "/tmp/profile with spaces;$literal"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
assert child.stdout.readline() == b"READY\n"
child.stdin.write(b"RESTART\n"); child.stdin.flush()
assert not os.path.exists(sys.argv[2])
assert child.poll() is None
print("armed", flush=True)
sys.stdin.buffer.read(1)
'''
        parent = subprocess.Popen([sys.executable, "-c", program, str(self.helper), str(receipt)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  env={**os.environ, "PARC_RESTART_TEST_RECEIPT": str(receipt)})
        self.assertEqual(parent.stdout.readline(), b"armed\n")
        self.assertFalse(receipt.exists())
        parent.communicate(b"x", timeout=3)
        self.assertEqual(parent.returncode, 0)
        deadline = time.monotonic() + 3
        while not receipt.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertEqual(receipt.read_text().splitlines(),
                         ["/usr/bin/open", "open", "-n", "-a", "/Apps/Parc Dev.app", "--args",
                          "--parc-profile", "/tmp/profile with spaces;$literal"])


if __name__ == "__main__":
    unittest.main()

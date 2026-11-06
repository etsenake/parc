"""Execute the actual helper against controlled test dylibs, never Chromium.

This verifies loader sequencing/cleanup/failure propagation, NOT Seatbelt policy.
The independent Chromium sandbox and helper process types still need live tests.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("parc_packager_helper", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


@unittest.skipUnless(sys.platform == "darwin", "real Mach-O helper test requires macOS")
class HelperLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name).resolve()
        cls.framework = cls.root / "Parc.app/Contents/Frameworks/Chromium Embedded Framework.framework"
        (cls.framework / "Libraries").mkdir(parents=True)
        helper = cls.root / "Parc Helper"
        subprocess.run(["xcrun", "clang++", "-arch", "arm64", "-std=c++20", "-mmacosx-version-min=13.0", "-Wall", "-Wextra", "-Werror", str(REPO / "Sources/ParcHelper/main.cc"), "-o", str(helper)], check=True, capture_output=True)
        cls.helper_binary = helper
        cls.sandbox_source = cls.root / "sandbox.c"
        cls.sandbox_source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
static void log_event(const char* text) { FILE* f=fopen(getenv("PARC_HELPER_TEST_LOG"),"a"); if(f){fprintf(f,"%s\n",text); fclose(f);} }
__attribute__((constructor)) static void loaded(void){log_event("sandbox-load");}
__attribute__((destructor)) static void unloaded(void){log_event("sandbox-unload");}
void* cef_sandbox_initialize(int argc, char** argv) { log_event("sandbox-init"); return getenv("PARC_HELPER_TEST_FAIL") ? NULL : (void*)1; }
void cef_sandbox_destroy(void* value) { if(value == (void*)1) log_event("sandbox-destroy"); }
''')
        cls.engine_source = cls.root / "engine.c"
        cls.engine_source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
static void log_event(const char* text) { FILE* f=fopen(getenv("PARC_HELPER_TEST_LOG"),"a"); if(f){fprintf(f,"%s\n",text); fclose(f);} }
__attribute__((constructor)) static void loaded(void){log_event("engine-load");}
__attribute__((destructor)) static void unloaded(void){log_event("engine-unload");}
int parc_engine_execute_process(int argc, char** argv) { log_event("engine-execute"); return getenv("PARC_HELPER_TEST_BROWSER") ? -1 : 37; }
''')
        for source, target in ((cls.sandbox_source, cls.framework / "Libraries/libcef_sandbox.dylib"), (cls.engine_source, cls.framework / "Chromium Embedded Framework")):
            subprocess.run(["xcrun", "clang", "-arch", "arm64", "-dynamiclib", str(source), "-o", str(target)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def execute(self, suffix="", **extra):
        name = "Parc Helper" + suffix
        target = self.root / "Parc.app/Contents/Frameworks" / (name + ".app") / "Contents/MacOS" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        # A fresh inode avoids macOS caching an earlier executable signature.
        target.unlink(missing_ok=True)
        target.write_bytes(self.helper_binary.read_bytes())
        target.chmod(0o755)
        log = self.root / (self.id().split(".")[-1] + suffix + ".log")
        log.unlink(missing_ok=True)
        result = subprocess.run([str(target), "--type=renderer"], capture_output=True,
                                env={**os.environ, "PARC_HELPER_TEST_LOG": str(log), **extra})
        return result, log.read_text().splitlines() if log.exists() else []

    def test_no_non_system_startup_dependency(self):
        info = pkg.inspect_macho(self.helper_binary)
        self.assertTrue(info["loads"])
        self.assertTrue(all(pkg.system_library(v) for v in info["loads"]))
        directory = self.root / "inspection"
        directory.mkdir()
        for suffix, _, _ in pkg.HELPERS:
            with self.subTest(helper=suffix):
                target = directory / ("Parc Helper" + suffix)
                target.write_bytes(self.helper_binary.read_bytes())
                self.assertEqual(pkg.inspect_macho(target), info)

    def test_sandbox_precedes_engine_static_initializer_all_variants(self):
        for suffix, _, _ in pkg.HELPERS:
            with self.subTest(helper=suffix):
                result, events = self.execute(suffix)
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assertEqual(events, ["sandbox-load", "sandbox-init", "engine-load", "engine-execute", "engine-unload", "sandbox-destroy", "sandbox-unload"])

    def test_failed_sandbox_never_loads_framework(self):
        result, events = self.execute(PARC_HELPER_TEST_FAIL="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(events, ["sandbox-load", "sandbox-init", "sandbox-unload"])

    def test_browser_process_return_refused_after_orderly_cleanup(self):
        result, events = self.execute(PARC_HELPER_TEST_BROWSER="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(events[-3:], ["engine-unload", "sandbox-destroy", "sandbox-unload"])


if __name__ == "__main__":
    unittest.main()

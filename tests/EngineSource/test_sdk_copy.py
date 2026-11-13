import copy
import os
import re
import subprocess
import unittest
from unittest.mock import patch
import test_engine_source as fixture
engine = fixture.engine
ENSURE_SDK = engine.ensure_sdk


class SdkCopyTests(unittest.TestCase):
    def setUp(self):
        fixture.EngineSourceTests.setUp(self)
        self.lock = copy.deepcopy(self.lock)
        defines = re.sub(r'\s*mac_sdk_path="[^"]*"', "", self.lock["build"]["gn_defines"])
        self.without = defines
        self.lock["build"]["gn_defines"] = defines + ' mac_sdk_path="//build/mac_files/parc_sdk/MacOSX.sdk"'
        (self.workspace / "chromium/src").mkdir(parents=True)
        self.installed = self.base / "Xcode.app/MacOSX27.2.sdk"
        (self.installed / "usr/include").mkdir(parents=True)
        (self.installed / "SDKSettings.json").write_text('{"Version": "27.2"}')
        self.header = self.installed / "usr/include/stdio.h"
        self.header.write_text("int printf();")
        os.utime(self.header, ns=(1_700_000_000_000_000_000, 1_700_000_000_000_000_000))
        self.calls = []
        self.addCleanup(subprocess.run, ["/bin/chmod", "-R", "u+w", str(self.base)])

    def run_with_sdk(self, sdk=None):
        real = subprocess.run
        found = str(self.installed if sdk is None else sdk)

        def run(argv, *args, **kwargs):
            self.calls.append(argv)
            if argv[0] == "/usr/bin/xcrun":
                return subprocess.CompletedProcess(argv, 0, found + "\n", "")
            return real(argv, *args, **kwargs)

        with patch.object(engine.subprocess, "run", side_effect=run):
            return ENSURE_SDK(self.workspace, self.lock)

    def test_the_installed_sdk_is_copied_into_the_engine_with_its_dates(self):
        copied = self.run_with_sdk()
        self.assertEqual(copied, self.workspace / "chromium/src" / engine.SDK_COPY)
        self.assertEqual((copied / "usr/include/stdio.h").read_text(), "int printf();")
        self.assertEqual((copied / "usr/include/stdio.h").stat().st_mtime_ns, 1_700_000_000_000_000_000)
        self.assertFalse(copied.with_name(copied.name + ".copying").exists())

    def test_an_existing_copy_is_never_touched_again(self):
        copied = self.run_with_sdk()
        os.utime(self.header, ns=(1_800_000_000_000_000_000, 1_800_000_000_000_000_000))
        self.calls.clear()
        self.assertEqual(self.run_with_sdk(), copied)
        self.assertEqual(self.calls, [])
        self.assertEqual((copied / "usr/include/stdio.h").stat().st_mtime_ns, 1_700_000_000_000_000_000)

    def test_an_engine_without_the_setting_keeps_using_the_installed_xcode(self):
        self.lock["build"]["gn_defines"] = self.without
        self.assertIsNone(self.run_with_sdk())
        self.assertFalse((self.workspace / "chromium/src/build/mac_files").exists())

    def test_a_missing_installed_sdk_says_what_to_install(self):
        with self.assertRaisesRegex(engine.Refusal, "install Xcode"):
            self.run_with_sdk(self.base / "nowhere")

    def test_a_new_copy_is_read_only_so_no_build_step_can_delete_from_it(self):
        copied = self.run_with_sdk()
        self.assertFalse(os.access(copied, os.W_OK))
        self.assertFalse(os.access(copied / "usr/include", os.W_OK))
        self.assertEqual((copied / "usr/include/stdio.h").stat().st_mtime_ns, 1_700_000_000_000_000_000)

    def test_each_build_folder_compiles_against_its_own_link_to_the_copy(self):
        development = engine.engine_arguments(self.lock, self.lock["build"]["gn_defines"] + " symbol_level=0")
        self.assertIn(b'mac_sdk_path="//out/Release_GN_arm64/parc_sdk/MacOSX.sdk"', development)
        shipping = engine.shipping_arguments(self.workspace, engine.shipping_environment(self.workspace, self.lock, 0),
                                             self.lock)
        self.assertIn(b'mac_sdk_path="//out/ParcDistribution_GN_arm64/parc_sdk/MacOSX.sdk"', shipping)
        self.assertNotIn(b"build/mac_files", development + shipping)

    def test_the_link_reaches_the_copy_by_a_relative_path(self):
        copied = self.run_with_sdk()
        output = self.workspace / "chromium/src/out/Release_GN_arm64"
        output.mkdir(parents=True)
        engine.link_sdk(self.workspace, self.lock, output)
        link = output / "parc_sdk/MacOSX.sdk"
        self.assertTrue(link.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(link)))
        self.assertEqual(link.resolve(), copied.resolve())
        self.assertEqual((link / "usr/include/stdio.h").read_text(), "int printf();")

    def test_a_stale_link_is_pointed_back_at_the_copy(self):
        copied = self.run_with_sdk()
        output = self.workspace / "chromium/src/out/ParcDistribution_GN_arm64"
        (output / "parc_sdk").mkdir(parents=True)
        (output / "parc_sdk/MacOSX.sdk").symlink_to(self.installed)
        engine.link_sdk(self.workspace, self.lock, output)
        self.assertEqual((output / "parc_sdk/MacOSX.sdk").resolve(), copied.resolve())

    def test_an_engine_without_the_setting_gets_no_link_and_unchanged_arguments(self):
        self.lock["build"]["gn_defines"] = self.without
        output = self.workspace / "chromium/src/out/Release_GN_arm64"
        output.mkdir(parents=True)
        engine.link_sdk(self.workspace, self.lock, output)
        self.assertFalse((output / "parc_sdk").exists())
        self.assertNotIn(b"mac_sdk_path", engine.engine_arguments(self.lock, self.without + " symbol_level=0"))

    def test_the_copy_sits_where_chromium_ignores_it_so_cleanup_keeps_it(self):
        self.assertTrue(engine.SDK_COPY.startswith("build/mac_files/"))


if __name__ == "__main__":
    unittest.main()

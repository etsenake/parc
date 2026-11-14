from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("widevine_packager", REPO / "scripts/build.py")
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)
vmp = pkg.widevine_vmp

OPENSSL = shutil.which("openssl")
XCRUN = shutil.which("xcrun")


def compile_image(path: Path, *, executable=False, archs=("arm64",)) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    source = "int main(void) { return 0; }\n" if executable else "int parc_vmp_fixture(void) { return 7; }\n"
    arch_args = [value for arch in archs for value in ("-arch", arch)]
    kind = [] if executable else ["-dynamiclib"]
    subprocess.run(["xcrun", "clang", *arch_args, *kind, "-x", "c", "-", "-o", str(path)],
                   input=source, text=True, check=True, capture_output=True)
    return path


def make_identity(directory: Path, name="parc-vmp-test", passphrase=None) -> tuple[Path, Path]:
    key, certificate = directory / (name + ".key.pem"), directory / (name + ".cert.pem")
    command = [OPENSSL, "req", "-x509", "-newkey", "rsa:2048", "-keyout", str(key), "-out", str(certificate),
               "-days", "30", "-subj", f"/O=Parc test/CN={name}"]
    command += ["-passout", "pass:" + passphrase] if passphrase else ["-nodes"]
    subprocess.run(command, check=True, capture_output=True)
    return certificate, key


def ad_hoc_sign(path: Path) -> None:
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(path)], check=True, capture_output=True)


class SignatureFormatTests(unittest.TestCase):
    def test_round_trip_and_strict_decoding(self):
        certificate, signature = bytes(range(256)) * 2, b"\x5a" * 256
        data = vmp.encode(certificate, signature, 1)
        self.assertEqual(data[:4], b"\x00\x01\x80\x04")
        self.assertEqual(vmp.decode(data), {"certificate": certificate, "signature": signature, "flags": 1})
        flags = b"\x03\x01\x01"
        for broken in (b"\x01" + data[1:], data + flags, data[:-1], data[:-3],
                       data[:-3] + b"\x04\x01\x01", data[:-3] + b"\x03\x02\x01\x01", b""):
            with self.subTest(broken=broken[-4:]), self.assertRaises(vmp.VmpError):
                vmp.decode(broken)

    def test_certificate_validity_window_is_enforced(self):
        certificate = vmp.Certificate(b"", "", "", datetime(2026, 1, 1, tzinfo=timezone.utc),
                                      datetime(2026, 2, 1, tzinfo=timezone.utc), 3, 3)
        vmp.check_validity(certificate, datetime(2026, 1, 15, tzinfo=timezone.utc))
        for moment in (datetime(2025, 12, 31, tzinfo=timezone.utc), datetime(2026, 2, 2, tzinfo=timezone.utc)):
            with self.assertRaisesRegex(vmp.VmpError, "not valid now"):
                vmp.check_validity(certificate, moment)

    def test_non_macho_and_text_less_images_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "image"
            for content in (b"\x00\x01", b"#!/bin/sh\nexit 0\n",
                            struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 6, 0, 0, 0, 0)):
                path.write_bytes(content)
                with self.subTest(content=content[:4]), self.assertRaises(vmp.VmpError):
                    vmp.macho_digest(path)


@unittest.skipUnless(XCRUN, "Xcode command-line tools are required")
class MachOBodyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def test_body_ignores_apple_signature_but_not_code(self):
        image = compile_image(self.root / "libfixture.dylib")
        [(start, end)] = vmp.macho_body_ranges(image)
        commands = subprocess.run(["/usr/bin/otool", "-l", str(image)], check=True, capture_output=True,
                                  text=True).stdout
        symbols = re.search(r"cmd LC_SYMTAB.*?stroff (\d+)\s+strsize (\d+)", commands, re.S)
        sections = re.findall(r"segname __TEXT\s+addr \S+\s+size \S+\s+offset (\d+)", commands)
        self.assertEqual(start, min(map(int, sections)))
        self.assertEqual(end, int(symbols[1]) + int(symbols[2]))
        self.assertGreater(start, 32)
        digest, before = vmp.macho_digest(image), image.read_bytes()
        ad_hoc_sign(image)
        self.assertNotEqual(image.read_bytes(), before)
        self.assertEqual(vmp.macho_digest(image), digest)
        data = bytearray(image.read_bytes())
        data[start] ^= 0xFF
        image.write_bytes(bytes(data))
        self.assertNotEqual(vmp.macho_digest(image), digest)

    def test_universal_binary_hashes_each_slice_in_header_order(self):
        image = compile_image(self.root / "libuniversal.dylib", archs=("x86_64", "arm64"))
        with image.open("rb") as stream:
            stream.seek(8)
            order = [struct.unpack(">5I", stream.read(20))[0] for _ in range(2)]
        names = {0x01000007: "x86_64", 0x0100000C: "arm64"}
        expected = hashlib.sha512()
        for cpu in order:
            thin = self.root / names[cpu]
            subprocess.run(["/usr/bin/lipo", str(image), "-thin", names[cpu], "-output", str(thin)], check=True)
            [(start, end)] = vmp.macho_body_ranges(thin)
            expected.update(thin.read_bytes()[start:end])
        self.assertEqual(len(vmp.macho_body_ranges(image)), 2)
        self.assertEqual(vmp.macho_digest(image), expected.digest())


@unittest.skipUnless(XCRUN and OPENSSL, "Xcode command-line tools and openssl are required")
class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.certificate, self.key = make_identity(self.root)

    def signer(self, certificate=None, key=None):
        return vmp.KeySigner(certificate or self.certificate, key or self.key, OPENSSL, None)

    def test_key_signer_output_verifies_and_rejects_tampering(self):
        image = compile_image(self.root / "libfixture.dylib")
        signature = self.root / "libfixture.dylib.sig"
        self.signer().write(image, signature, vmp.BLESSED)
        info = vmp.verify(image, signature.read_bytes(), vmp.BLESSED)
        self.assertEqual(info["certificate"]["subject"], "O=Parc test, CN=parc-vmp-test")
        self.assertEqual(info["body_sha512"], vmp.macho_digest(image).hex())
        with self.assertRaisesRegex(vmp.VmpError, "flags"):
            vmp.verify(image, signature.read_bytes(), 0)
        with self.assertRaisesRegex(vmp.VmpError, "not valid now"):
            vmp.verify(image, signature.read_bytes(), vmp.BLESSED, datetime.now(timezone.utc) + timedelta(days=60))
        other_certificate, _ = make_identity(self.root, "other")
        fields = vmp.decode(signature.read_bytes())
        mismatched = vmp.encode(vmp.load_certificate(other_certificate).der, fields["signature"], vmp.BLESSED)
        with self.assertRaisesRegex(vmp.VmpError, "does not match"):
            vmp.verify(image, mismatched, vmp.BLESSED)
        [(start, _)] = vmp.macho_body_ranges(image)
        data = bytearray(image.read_bytes())
        data[start + 1] ^= 0xFF
        image.write_bytes(bytes(data))
        with self.assertRaisesRegex(vmp.VmpError, "does not match"):
            vmp.verify(image, signature.read_bytes(), vmp.BLESSED)

    def test_encrypted_key_uses_only_the_given_passphrase(self):
        certificate, key = make_identity(self.root, "encrypted", passphrase="vmp-test-passphrase")
        image = compile_image(self.root / "libfixture.dylib")
        with patch.dict(os.environ, {vmp.PASSPHRASE_VARIABLE: "vmp-test-passphrase"}):
            with self.assertRaisesRegex(vmp.VmpError, "could not sign with the VMP key: "):
                vmp.KeySigner(certificate, key, OPENSSL, "wrong").write(image, self.root / "wrong.sig", 0)
        vmp.KeySigner(certificate, key, OPENSSL, "vmp-test-passphrase").write(image, self.root / "right.sig", 0)
        vmp.verify(image, (self.root / "right.sig").read_bytes(), 0)

    def test_encrypted_key_without_passphrase_fails_without_prompting(self):
        certificate, key = make_identity(self.root, "encrypted", passphrase="vmp-test-passphrase")
        image = compile_image(self.root / "libfixture.dylib")
        signer = vmp.KeySigner(certificate, key, OPENSSL, None)
        pid, terminal = pty.fork()
        if pid == 0:
            try:
                signer.write(image, self.root / "unset.sig", 0)
                os._exit(1)
            except vmp.VmpError as error:
                os.write(1, str(error).encode())
                os._exit(0 if vmp.PASSPHRASE_VARIABLE in str(error) else 2)
            except BaseException:
                os._exit(3)
        transcript, status, deadline = b"", None, time.monotonic() + 20
        while status is None:
            if time.monotonic() > deadline:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                os.close(terminal)
                self.fail("openssl waited for a passphrase: " + transcript.decode(errors="replace"))
            if select.select([terminal], [], [], 0.2)[0]:
                try:
                    transcript += os.read(terminal, 4096)
                except OSError:
                    pass
            done, code = os.waitpid(pid, os.WNOHANG)
            status = code if done else None
        os.close(terminal)
        self.assertNotIn(b"Enter pass phrase", transcript)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0, transcript.decode(errors="replace"))

    def test_configured_key_outside_checkouts_becomes_a_key_signer(self):
        signer = pkg.widevine_signer(self.certificate, self.key, None, passphrase="vmp-test-passphrase")
        self.assertIsInstance(signer, vmp.KeySigner)
        self.assertEqual(signer.certificate, vmp.load_certificate(self.certificate))
        self.assertEqual((signer.private_key, signer.passphrase), (self.key, "vmp-test-passphrase"))

    def test_der_certificate_is_accepted_and_malformed_ones_refused(self):
        der = self.root / "certificate.der"
        subprocess.run([OPENSSL, "x509", "-in", str(self.certificate), "-outform", "der", "-out", str(der)],
                       check=True)
        self.assertEqual(vmp.load_certificate(der), vmp.load_certificate(self.certificate))
        data = der.read_bytes()
        for broken in (data[:40], data[:4] + b"\x00" * (len(data) - 4), data + b"\x00", b"\x30\x00"):
            with self.subTest(size=len(broken)), self.assertRaises(vmp.VmpError):
                vmp.parse_certificate(broken)


class PackagingConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def test_signer_needs_explicit_complete_configuration(self):
        certificate, key = self.root / "cert.pem", self.root / "key.pem"
        self.assertIsNone(pkg.widevine_signer(None, None, None))
        with self.assertRaisesRegex(pkg.Refusal, "together"):
            pkg.widevine_signer(certificate, None, None)
        with self.assertRaisesRegex(pkg.Refusal, "not both"):
            pkg.widevine_signer(certificate, key, self.root / "sign")
        with self.assertRaisesRegex(pkg.Refusal, "absolute"):
            pkg.widevine_signer(Path("cert.pem"), Path("key.pem"), None)
        with self.assertRaisesRegex(pkg.Refusal, "existing files"):
            pkg.widevine_signer(certificate, key, None)
        script = self.root / "sign"
        script.write_text("#!/bin/sh\n")
        with self.assertRaisesRegex(pkg.Refusal, "executable"):
            pkg.widevine_signer(None, None, script)

    def test_private_key_must_stay_outside_git_checkouts(self):
        checkout = self.root / "checkout"
        (checkout / "keys").mkdir(parents=True)
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        (checkout / ".git/keys").mkdir()
        linked = self.root / "linked"
        (linked / "keys").mkdir(parents=True)
        (linked / ".git").write_text("gitdir: /nonexistent/.git/worktrees/linked\n")
        for directory, repo in ((checkout / "keys", REPO), (checkout / ".git/keys", REPO),
                                (linked / "keys", REPO), (self.root, self.root)):
            certificate, key = directory / "cert.pem", directory / "key.pem"
            certificate.write_text("not used")
            key.write_text("not used")
            with self.subTest(directory=directory), self.assertRaisesRegex(pkg.Refusal, "outside"):
                pkg.widevine_signer(certificate, key, None, repo)

    def test_component_engines_cannot_claim_signed_hosts(self):
        shipping = {"build_classification": "release-noncomponent", "components": {}}
        pkg.require_widevine_signing({"build_classification": "development-component"}, None)
        pkg.require_widevine_signing(shipping, object())
        for manifest in ({"build_classification": "development-component", "components": {}},
                         {**shipping, "components": {"libmedia.dylib": {}}}):
            with self.subTest(manifest=manifest), self.assertRaisesRegex(pkg.Refusal, "non-component"):
                pkg.require_widevine_signing(manifest, object())

    def test_unsigned_report_is_truthful(self):
        development = pkg.widevine_host_signatures(self.root / "Parc.app", None, None)
        self.assertEqual(development["host_signatures"], "unsigned")
        self.assertIn("no VMP certificate", development["unsigned_reason"])
        self.assertEqual(development["cdm_helper"], "Parc Helper (CDM)")
        self.assertEqual(development["helper_library_validation"], "disabled on every helper without a Team ID")
        certificate = pkg.widevine_host_signatures(self.root / "Parc.app", None, "FIXTURETEAM")
        self.assertEqual(certificate["helper_library_validation"], "disabled only on the CDM helper")
        self.assertNotIn("signatures", certificate)



    def test_cli_keeps_widevine_options_on_build(self):
        for argv, message in ((["seal-engine", "--widevine-sign-command", "/bin/true"], "not seal-engine"),
                              (["build", "--widevine-certificate", "/missing.pem"], "together")):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = pkg.main([*argv, "--engine-dir", "/missing", "--manifest", "/missing.json"])
            self.assertEqual(code, 1)
            self.assertIn(message, stderr.getvalue())

    def test_cli_takes_the_passphrase_out_of_the_environment(self):
        argv = ["build", "--engine-dir", "/missing", "--manifest", "/missing.json",
                "--widevine-certificate", "/cert.pem", "--widevine-private-key", "/key.pem"]
        with patch.dict(os.environ, {pkg.WIDEVINE_KEY_PASSPHRASE: "vmp-test-passphrase"}), \
                patch.object(pkg, "widevine_signer", return_value=None) as signer, redirect_stderr(io.StringIO()):
            pkg.main(argv)
            self.assertNotIn(pkg.WIDEVINE_KEY_PASSPHRASE, os.environ)
        signer.assert_called_once_with(Path("/cert.pem"), Path("/key.pem"), None, passphrase="vmp-test-passphrase")


@unittest.skipUnless(XCRUN and OPENSSL, "Xcode command-line tools and openssl are required")
class PackagedHostTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.certificate, self.key = make_identity(self.root)
        self.app = self.root / "Parc.app"
        framework = self.app / "Contents/Frameworks" / pkg.FRAMEWORK
        compile_image(framework / "Versions/A" / pkg.ENGINE_NAME)
        (framework / "Versions/A/Resources").mkdir()
        (framework / "Versions/Current").symlink_to("A")
        (framework / "Resources").symlink_to("Versions/Current/Resources")
        (framework / pkg.ENGINE_NAME).symlink_to("Versions/Current/" + pkg.ENGINE_NAME)
        self.helper = compile_image(
            self.app / "Contents/Frameworks/Parc Helper (CDM).app/Contents/MacOS/Parc Helper (CDM)", executable=True)
        (self.app / "Contents/Resources").mkdir()
        self.framework = framework

    def command(self, body: str) -> Path:
        script = self.root / f"vmp-sign-{len(list(self.root.glob('vmp-sign-*')))}"
        script.write_text(f"#!{sys.executable}\n" + body)
        script.chmod(0o755)
        return script

    def test_signatures_land_where_chromium_reads_them_and_survive_apple_signing(self):
        signer = vmp.KeySigner(self.certificate, self.key, OPENSSL, None)
        report = pkg.widevine_host_signatures(self.app, signer, "FIXTURETEAM")
        self.assertEqual(report["host_signatures"], "signed")
        self.assertEqual(report["signer"], "certificate-key")
        self.assertIs(report["certificate_chain_verified"], False)
        framework_sig = f"Contents/Frameworks/{pkg.FRAMEWORK}/Versions/A/Resources/{pkg.ENGINE_NAME}.sig"
        self.assertEqual({name: item["flags"] for name, item in report["signatures"].items()},
                         {framework_sig: 1, "Contents/Resources/Parc Helper (CDM).sig": 0})
        self.assertTrue((self.framework / "Resources" / (pkg.ENGINE_NAME + ".sig")).is_file())
        for item in report["signatures"].values():
            ad_hoc_sign(self.app / item["binary"])
        pkg.verify_widevine_signatures(self.app, report)
        data = bytearray(self.helper.read_bytes())
        data[vmp.macho_body_ranges(self.helper)[0][0]] ^= 0xFF
        self.helper.write_bytes(bytes(data))
        with self.assertRaisesRegex(pkg.Refusal, "invalidated"):
            pkg.verify_widevine_signatures(self.app, report)

    def test_existing_signature_is_never_overwritten(self):
        (self.app / "Contents/Resources/Parc Helper (CDM).sig").write_bytes(b"old")
        signer = vmp.KeySigner(self.certificate, self.key, OPENSSL, None)
        with self.assertRaisesRegex(pkg.Refusal, "already exists"):
            pkg.widevine_host_signatures(self.app, signer, None)

    def signing_service(self, after: str = "") -> Path:
        library = REPO / "scripts/widevine_vmp.py"
        return self.command(
            "import importlib.util, sys\nfrom pathlib import Path\n"
            f"spec = importlib.util.spec_from_file_location('v', {str(library)!r})\n"
            "v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)\n"
            f"open({str(self.root / 'calls')!r}, 'a').write(' | '.join(sys.argv[1:]) + '\\n')\n"
            f"v.KeySigner(Path({str(self.certificate)!r}), Path({str(self.key)!r}), {OPENSSL!r}, None)"
            ".write(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]))\n" + after)

    def test_signing_service_command_protocol_and_output_checks(self):
        report = pkg.widevine_host_signatures(self.app, pkg.widevine_signer(None, None, self.signing_service()), None)
        self.assertEqual(report["signer"], "command")
        calls = (self.root / "calls").read_text().splitlines()
        self.assertEqual([call.rsplit(" | ", 1)[1] for call in calls], ["1", "0"])
        self.assertTrue(calls[1].startswith(str(self.helper) + " | " + str(self.app / "Contents/Resources")))
        appends = "open(sys.argv[1], 'ab').write(b'outside the signed body')\n"
        cases = ((self.command("import sys\nopen(sys.argv[2], 'wb').write(b'\\x00garbage')\n"), "Unknown"),
                 (self.command("import sys\nsys.exit(3)\n"), "command failed"),
                 (self.command(f"import os, sys\nopen({str(self.root / 'elsewhere.sig')!r}, 'wb').write(b'x')\n"
                               f"os.symlink({str(self.root / 'elsewhere.sig')!r}, sys.argv[2])\n"), "symlink"),
                 (self.signing_service(appends), "changed the binary"))
        for script, message in cases:
            for signature in self.app.rglob("*.sig"):
                signature.unlink()
            with self.subTest(message=message), self.assertRaisesRegex(pkg.Refusal, message):
                pkg.widevine_host_signatures(self.app, pkg.widevine_signer(None, None, script), None)


if __name__ == "__main__":
    unittest.main()

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

REPO = Path(__file__).resolve().parents[2]
IDENTITY = "Developer ID Application: Fixture (FIXTURE)"
TEAM = "TEAM123456"


@unittest.skipUnless(Path("/usr/bin/openssl").exists(), "requires OpenSSL")
class PublishedSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "Engine/ParcHost").mkdir(parents=True)
        (self.repo / "Resources").mkdir()
        shutil.copy2(REPO / "scripts/package-app.sh", self.repo / "scripts/package-app.sh")
        shutil.copy2(REPO / "scripts/app_version.py", self.repo / "scripts/app_version.py")
        shutil.copy2(REPO / "scripts/release_notes.py", self.repo / "scripts/release_notes.py")
        (self.repo / "release-notes.json").write_text(json.dumps({"releases": [{
            "version": "1.0.0", "build": 1, "date": "2026-11-10", "changes": [
                {"type": "feat", "scope": "updates", "summary": "Show What’s New", "breaking": False}]}]}))
        (self.repo / "app-version.json").write_text(json.dumps({"version": "1.0.0", "build": 1}) + "\n")
        (self.repo / "Engine/ParcHost/overlay.json").write_text('{"version": 316}')
        self.manifest = self.root / "engine.json"
        self.manifest.write_text(json.dumps({"engine_dir": str(self.root / "engine")}))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.cert = self.root / "certificate.pem"
        self.certificate(TEAM)
        self.env = {**os.environ, "HOME": str(self.home), "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "PARC_SIGN_IDENTITY": IDENTITY, "FIXTURE_IDENTITY": IDENTITY,
                    "FIXTURE_CERT": str(self.cert), "FIXTURE_ROOT": str(self.root), "FIXTURE_TEAM": TEAM}
        workspace = self.root / 'workspace'
        self.env['PARC_ENGINE_WORKSPACE'] = str(workspace)
        for key in ("GH_TOKEN", "GITHUB_TOKEN", "FIXTURE_INVALID", "FIXTURE_ADHOC_REPORT"):
            self.env.pop(key, None)
        self.tool("git", """
            import sys
            if sys.argv[1] == 'rev-parse': print('a' * 40)
            elif sys.argv[1] == 'show': print({'v1.1.0': '{"version": 317}'}.get(sys.argv[2].split(':')[0], '{"version": 316}'))
        """)
        self.tool("security", """
            import os, pathlib, sys
            if sys.argv[1] == 'find-identity':
                if not os.environ.get('FIXTURE_INVALID'):
                    print('  1) ' + 'A' * 40 + ' "' + os.environ['FIXTURE_IDENTITY'] + '"')
            elif sys.argv[1] == 'find-certificate':
                print(pathlib.Path(os.environ['FIXTURE_CERT']).read_text())
        """)
        self.tool("gh", """
            import hashlib, json, os, pathlib, subprocess, sys
            if sys.argv[1:3] == ['auth', 'token']: print('fixture-token')
            elif sys.argv[1:3] == ['release', 'list']:
                if os.environ.get('FIXTURE_LIST_FAIL'): sys.exit('HTTP 502')
                releases = [{'tagName': 'v1.0.0', 'name': '1.0.0',
                             'createdAt': '2026-11-06T00:00:00Z', 'isDraft': False, 'isPrerelease': False},
                            {'tagName': 'v1.1.0', 'name': '1.1.0',
                             'createdAt': '2026-11-07T00:00:00Z', 'isDraft': False, 'isPrerelease': False},
                            {'tagName': 'v9.0.0', 'name': '9.0.0',
                             'createdAt': '2026-11-08T00:00:00Z', 'isDraft': False, 'isPrerelease': True}]
                query = sys.argv[sys.argv.index('--jq') + 1]
                print(subprocess.check_output(['jq', '-r', query], input=json.dumps(releases), text=True).strip())
            elif sys.argv[1:3] == ['release', 'view']:
                print(json.dumps({'targetCommitish': 'b' * 40, 'assets': [
                    {'name': 'Parc-1.0.0-arm64.zip', 'digest': 'sha256:' + hashlib.sha256(b'fixture archive').hexdigest()},
                    {'name': 'Parc-arm64.dmg', 'digest': 'sha256:' + 'd' * 64}]}))
            elif sys.argv[1:3] == ['release', 'download']:
                pathlib.Path(sys.argv[sys.argv.index('-D') + 1], sys.argv[sys.argv.index('-p') + 1]).write_bytes(b'fixture archive')
            elif sys.argv[1:3] == ['release', 'create']:
                pathlib.Path(os.environ['FIXTURE_ROOT'], 'published').write_text('\\n'.join(sys.argv[2:]))
                print('https://example.invalid/release')
        """)
        self.tool("ditto", """
            import pathlib, sys
            pathlib.Path(sys.argv[-1]).write_bytes(b'fixture archive')
        """)
        self.tool("xcrun", """
            import os, sys
            if os.environ.get('FIXTURE_MISSING_NOTARY'): sys.exit(1)
        """)
        (self.repo / "scripts/notarize-app.py").write_text(textwrap.dedent("""
            import json, os, pathlib, sys
            root = pathlib.Path(os.environ['FIXTURE_ROOT'])
            if os.environ.get('FIXTURE_NOTARY_FAIL'): sys.exit(1)
            path = pathlib.Path(sys.argv[1]) / 'package-report.json'
            report = json.loads(path.read_text())
            report['notarized'] = not bool(os.environ.get('FIXTURE_MISSING_TICKET'))
            report['notarization'] = {'status': 'Accepted', 'team': os.environ['FIXTURE_TEAM'],
                                      'stapled': True, 'gatekeeper_verified': True}
            path.write_text(json.dumps(report))
            (root / 'notarized').touch()
        """))
        (self.repo / "scripts/build.py").write_text(textwrap.dedent("""
            import json, os, pathlib, sys
            root = pathlib.Path(os.environ['FIXTURE_ROOT'])
            (root / 'built').touch()
            (root / 'build-arguments.json').write_text(json.dumps(sys.argv[1:]))
            output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
            output.mkdir(parents=True)
            (output / 'Parc.app').mkdir()
            report = {'signing_team': os.environ['FIXTURE_TEAM'],
                      'signing_identity': '-' if os.environ.get('FIXTURE_ADHOC_REPORT') else 'A' * 40}
            (output / 'package-report.json').write_text(json.dumps(report))
        """))
        (self.repo / "scripts/package-dmg.py").write_text(textwrap.dedent("""
            import os, pathlib, sys
            if os.environ.get('FIXTURE_DMG_FAIL'): sys.exit(1)
            pathlib.Path(sys.argv[sys.argv.index('--output') + 1]).write_bytes(b'fixture notarized dmg')
            pathlib.Path(os.environ['FIXTURE_ROOT'], 'dmg-notarized').touch()
        """))

    def tool(self, name, source):
        path = self.bin / name
        path.write_text('#!/usr/bin/env python3\n' + textwrap.dedent(source))
        path.chmod(0o755)

    def certificate(self, team):
        subject = '/CN=Apple Development Fixture' + ('/OU=' + team if team else '')
        subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(self.root / 'fixture.key'), '-out', str(self.cert),
                        '-subj', subject, '-days', '1'], check=True, capture_output=True)

    def run_package(self, *options):
        arguments = list(options) if '--from-release' in options else [*options, str(self.manifest)]
        return subprocess.run(['bash', str(self.repo / 'scripts/package-app.sh'), *arguments],
                              env=self.env, capture_output=True, text=True, timeout=30)

    def rejected(self, message, built=False):
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)
        self.assertEqual((self.root / 'built').exists(), built)
        self.assertFalse((self.root / 'published').exists())

    def test_missing_identity_never_builds_or_publishes(self):
        self.env['PARC_SIGN_IDENTITY'] = ''
        self.rejected('require a Developer ID Application identity')

    def test_generic_local_identity_cannot_publish(self):
        self.env['PARC_SIGN_IDENTITY'] = self.env['FIXTURE_IDENTITY'] = 'Local Signing'
        self.rejected('require a Developer ID Application identity')

    def test_development_identity_cannot_publish_production(self):
        self.env['PARC_SIGN_IDENTITY'] = self.env['FIXTURE_IDENTITY'] = 'Apple Development: Fixture'
        self.rejected('require a Developer ID Application identity')

    def test_missing_notarization_credentials_never_builds(self):
        self.env['FIXTURE_MISSING_NOTARY'] = '1'
        self.rejected('store this Mac\'s credentials')

    def test_failed_notarization_never_publishes(self):
        self.env['FIXTURE_NOTARY_FAIL'] = '1'
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / 'built').exists())
        self.assertFalse((self.root / 'published').exists())

    def test_missing_verified_notarization_report_never_publishes(self):
        self.env['FIXTURE_MISSING_TICKET'] = '1'
        self.rejected('missing verified Apple notarization', built=True)

    def test_invalid_configured_identity_never_builds(self):
        self.env['FIXTURE_INVALID'] = '1'
        self.rejected("isn't a valid code-signing identity")

    def test_certificate_without_team_never_builds(self):
        self.certificate(None)
        self.rejected('require an Apple Team ID')

    def test_different_package_team_never_publishes(self):
        self.env['FIXTURE_TEAM'] = 'OTHER12345'
        self.rejected('refusing publication', built=True)

    def test_ad_hoc_package_report_never_publishes(self):
        self.env['FIXTURE_ADHOC_REPORT'] = '1'
        self.rejected('refusing publication', built=True)

    def test_matching_apple_team_publishes(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'built').exists())
        self.assertTrue((self.root / 'notarized').exists())
        arguments = (self.root / 'published').read_text().split('\n--')
        self.assertIn('title\nParc app ', arguments[-2])
        self.assertIn(', engine overlay 316)', arguments[-2])
        self.assertRegex(arguments[-1], r'^notes\nPackage built from a{40} on engine overlay 316; signed '
                         r'Developer ID Application: Fixture \(FIXTURE\)\. Notarized by Apple with a stapled ticket\. '
                         r'Install: tests/Packaging/README.md, "Publishing app builds"\.$')

    def test_stable_release_uses_retained_versioned_tag_and_archive(self):
        result = self.run_package('--stable')
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.root / 'published').read_text().splitlines()
        self.assertIn('v1.0.0', arguments)
        self.assertTrue(any(item.endswith('/Parc-1.0.0-arm64.zip') for item in arguments))
        self.assertTrue(any(item.endswith('/Parc-arm64.dmg') for item in arguments))
        self.assertFalse(any(item.endswith('-1.0.0-arm64.dmg') for item in arguments))
        self.assertIn('--latest=false', arguments)
        self.assertIn('--prerelease', arguments)
        self.assertTrue((self.root / 'published').read_text().endswith(
            '\n--title\n1.0.0\n--notes\n### New\n\n- **updates:** Show What’s New'))
        self.assertTrue((self.root / 'notarized').exists())
        self.assertTrue((self.root / 'dmg-notarized').exists())

    def test_failed_dmg_notarization_never_publishes_stable_release(self):
        self.env['FIXTURE_DMG_FAIL'] = '1'
        result = self.run_package('--stable')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / 'notarized').exists())
        self.assertFalse((self.root / 'published').exists())

    def test_stable_release_refuses_existing_tag_before_build(self):
        self.tool('git', """
            import sys
            if sys.argv[1] == 'rev-parse': print('a' * 40)
            elif sys.argv[1] == 'ls-remote': print('b' * 40 + '\\trefs/tags/v1.0.0')
        """)
        result = self.run_package('--stable')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('already exists', result.stderr)
        self.assertFalse((self.root / 'built').exists())

    def test_explicit_stable_engine_reuse_selects_zip_alongside_dmg(self):
        result = self.run_package('--from-release', 'v1.0.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads((self.root / 'build-arguments.json').read_text())
        self.assertEqual(arguments[0], 'release-build')
        self.assertEqual(arguments[arguments.index('--release-tag') + 1], 'v1.0.0')
        self.assertTrue((self.repo / 'build/release-cache/v1.0.0/Parc-1.0.0-arm64.zip').exists())

    def test_auto_engine_selection_takes_the_newest_stable_release_with_this_overlay(self):
        result = self.run_package('--from-release')
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = json.loads((self.root / 'build-arguments.json').read_text())
        self.assertEqual(arguments[arguments.index('--release-tag') + 1], 'v1.0.0')

    def test_auto_engine_selection_refuses_without_a_release_on_this_overlay(self):
        (self.repo / "Engine/ParcHost/overlay.json").write_text('{"version": 318}')
        result = self.run_package('--from-release')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no published app package has engine overlay 318', result.stderr)
        self.assertFalse((self.root / 'built').exists())

    def test_auto_engine_selection_stops_on_a_failed_release_list(self):
        self.env['FIXTURE_LIST_FAIL'] = '1'
        result = self.run_package('--from-release')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HTTP 502', result.stderr)
        self.assertNotIn('build the engine instead', result.stderr)
        self.assertFalse((self.root / 'built').exists())


if __name__ == '__main__':
    unittest.main()

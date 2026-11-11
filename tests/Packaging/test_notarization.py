import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('notarize', Path(__file__).resolve().parents[2] /
                                            'scripts/notarize-app.py')
notarize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notarize)
TEAM = 'TEAM123456'
SUBMISSION = 'b6743aa6-df42-48cb-bd8e-cbbebee591fd'


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name) / 'run/package'
        self.image = self.package / 'Parc.app/Contents/MacOS/Parc'
        self.image.parent.mkdir(parents=True)
        self.image.write_bytes(b'signed fixture code')
        self.report_path = self.package / 'package-report.json'
        self.report = {'configuration': 'release', 'purpose': 'distribution',
                       'layout': 'standalone-app', 'distribution_eligible': True,
                       'signing_team': TEAM, 'notarized': False,
                       'signed_images': {'Parc.app/Contents/MacOS/Parc':
                                         hashlib.sha256(self.image.read_bytes()).hexdigest()}}
        self.report_path.write_text(json.dumps(self.report))
        self.calls = []
        self.status = 'Accepted'
        self.fail = None
        self.no_submission_id = False
        self.wrong_approval_hash = False
        self.actual_team = TEAM
        self.authority = 'Developer ID Application: Fixture'

    def run_tool(self, args, **kwargs):
        args = [str(arg) for arg in args]
        self.calls.append(args)
        out = ''
        err = ''
        code = int(self.fail is not None and args[:len(self.fail)] == self.fail)
        if args[:2] == ['codesign', '-dv']:
            err = f'Authority={self.authority}\nTeamIdentifier={self.actual_team}\nTimestamp=Today\n'
        elif args[0] == 'ditto':
            Path(args[-1]).write_bytes(b'fixture upload')
        elif args[:3] == ['xcrun', 'notarytool', 'submit']:
            out = json.dumps({} if self.no_submission_id else {'id': SUBMISSION})
        elif args[:3] == ['xcrun', 'notarytool', 'info']:
            out = json.dumps({'id': SUBMISSION, 'status': self.status})
        elif args[:3] == ['xcrun', 'notarytool', 'log']:
            Path(args[-1]).write_text(json.dumps({'status': self.status, 'issues': None,
                'jobId': SUBMISSION, 'sha256': 'wrong' if self.wrong_approval_hash else
                hashlib.sha256(b'fixture upload').hexdigest()}))
        result = subprocess.CompletedProcess(args, code, out, err)
        if kwargs.get('check') and code:
            raise subprocess.CalledProcessError(code, args, out, err)
        return result

    def execute(self):
        with patch.object(notarize.subprocess, 'run', side_effect=self.run_tool), \
                contextlib.redirect_stdout(io.StringIO()):
            return notarize.notarize(self.package, 'fixture-profile', TEAM, poll_seconds=0)

    def assert_unpublished(self):
        self.assertFalse(json.loads(self.report_path.read_text())['notarized'])

    def test_acceptance_stapling_validation_and_gatekeeper_are_required(self):
        receipt = self.execute()
        report = json.loads(self.report_path.read_text())
        self.assertTrue(report['notarized'])
        self.assertEqual(receipt['submission_id'], SUBMISSION)
        self.assertTrue(receipt['stapled'])
        self.assertTrue(any(call[:3] == ['xcrun', 'stapler', 'validate'] for call in self.calls))
        self.assertTrue(any(call[0] == 'spctl' for call in self.calls))

    def test_rejection_keeps_report_unnotarized(self):
        self.status = 'Invalid'
        with self.assertRaisesRegex(notarize.Refusal, 'Apple rejected'):
            self.execute()
        self.assert_unpublished()
        self.assertFalse(any(call[:2] == ['xcrun', 'stapler'] for call in self.calls))

    def test_stapling_failure_keeps_report_unnotarized(self):
        self.fail = ['xcrun', 'stapler', 'staple']
        with self.assertRaises(notarize.Refusal):
            self.execute()
        self.assert_unpublished()

    def test_approval_must_match_the_uploaded_archive(self):
        self.wrong_approval_hash = True
        with self.assertRaisesRegex(notarize.Refusal, 'does not match'):
            self.execute()
        self.assert_unpublished()

    def test_ticket_validation_failure_keeps_report_unnotarized(self):
        self.fail = ['xcrun', 'stapler', 'validate']
        with self.assertRaises(notarize.Refusal):
            self.execute()
        self.assert_unpublished()

    def test_gatekeeper_failure_keeps_report_unnotarized(self):
        self.fail = ['spctl']
        with self.assertRaises(notarize.Refusal):
            self.execute()
        self.assert_unpublished()

    def test_resume_uses_existing_submission_instead_of_duplicate_upload(self):
        self.fail = ['xcrun', 'notarytool', 'info']
        with self.assertRaises(notarize.Refusal):
            self.execute()
        self.fail = None
        self.execute()
        self.assertEqual(sum(call[:3] == ['xcrun', 'notarytool', 'submit'] for call in self.calls), 1)

    def test_ambiguous_upload_requires_reconciliation_not_duplicate_submit(self):
        self.no_submission_id = True
        with self.assertRaisesRegex(notarize.Refusal, 'confirmed ID'):
            self.execute()
        with self.assertRaisesRegex(notarize.Refusal, 'earlier upload'):
            self.execute()
        self.assertEqual(sum(call[:3] == ['xcrun', 'notarytool', 'submit'] for call in self.calls), 1)

    def test_changed_report_cannot_resume_a_submission(self):
        self.fail = ['xcrun', 'notarytool', 'info']
        with self.assertRaises(notarize.Refusal):
            self.execute()
        self.report['new_field'] = 'changed'
        self.report_path.write_text(json.dumps(self.report))
        with self.assertRaisesRegex(notarize.Refusal, 'Package changed'):
            self.execute()

    def test_changed_code_is_rejected_before_upload(self):
        self.image.write_bytes(b'changed')
        with self.assertRaisesRegex(notarize.Refusal, 'differs from its report'):
            self.execute()
        self.assertFalse(any(call[:3] == ['xcrun', 'notarytool', 'submit'] for call in self.calls))

    def test_wrong_actual_team_or_development_authority_is_rejected(self):
        for team, authority in [('OTHER12345', self.authority),
                                (TEAM, 'Apple Development: Fixture')]:
            with self.subTest(team=team, authority=authority):
                self.actual_team = team
                self.authority = authority
                with self.assertRaisesRegex(notarize.Refusal, 'Developer ID signing'):
                    self.execute()


class DirectNotarizationTests(NotarizationTests):
    def setUp(self):
        super().setUp()
        helper = self.package / 'Parc.app/Contents/Frameworks/Parc Helper.app/Contents/MacOS/Parc Helper'
        helper.parent.mkdir(parents=True)
        helper.write_bytes(b'signed direct Chromium helper')
        self.report['engine_runtime'] = 'chromium-direct'
        self.report['signed_images'][helper.relative_to(self.package).as_posix()] = hashlib.sha256(helper.read_bytes()).hexdigest()
        self.report_path.write_text(json.dumps(self.report))

    def test_changed_direct_helper_is_rejected_before_upload(self):
        helper = self.package / 'Parc.app/Contents/Frameworks/Parc Helper.app/Contents/MacOS/Parc Helper'
        helper.write_bytes(b'changed helper')
        with self.assertRaisesRegex(notarize.Refusal, 'differs from its report'):
            self.execute()
        self.assertFalse(any(call[:3] == ['xcrun', 'notarytool', 'submit'] for call in self.calls))


if __name__ == '__main__':
    unittest.main()

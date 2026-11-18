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
OUTAGE = 'Error: invalidJSONResponse(statusCode: Optional(503), data: "<title>503 Service Unavailable</title>")\n'
AGREEMENT = ('Error: HTTP status code: 403. A required agreement is missing or has expired. This request requires an '
             'in-effect agreement that has not been signed or has expired. Ensure your team has signed the necessary '
             'legal agreements and that they are not expired.\n')


class Clock:
    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


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
        self.outages = {}
        self.unsigned = set()
        self.history = []
        self.clock = Clock()

    def run_tool(self, args, **kwargs):
        args = [str(arg) for arg in args]
        self.calls.append(args)
        out = ''
        err = ''
        code = int(self.fail is not None and args[:len(self.fail)] == self.fail)
        if args[:2] == ['xcrun', 'notarytool'] and self.outages.get(args[2]):
            self.outages[args[2]] -= 1
            return subprocess.CompletedProcess(args, 1, '', OUTAGE)
        if args[:2] == ['xcrun', 'notarytool'] and args[2] in self.unsigned:
            return subprocess.CompletedProcess(args, 69, '', AGREEMENT)
        if args[:2] == ['codesign', '-dv']:
            err = f'Authority={self.authority}\nTeamIdentifier={self.actual_team}\nTimestamp=Today\n'
        elif args[0] == 'ditto':
            Path(args[-1]).write_bytes(b'fixture upload')
        elif args[:3] == ['xcrun', 'notarytool', 'submit']:
            out = json.dumps({} if self.no_submission_id else {'id': SUBMISSION})
        elif args[:3] == ['xcrun', 'notarytool', 'info']:
            out = json.dumps({'id': SUBMISSION, 'status': self.status})
        elif args[:3] == ['xcrun', 'notarytool', 'history']:
            out = json.dumps({'history': self.history})
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
                patch.object(notarize.service, 'time', self.clock), contextlib.redirect_stdout(io.StringIO()):
            return notarize.notarize(self.package, 'fixture-profile', TEAM, poll_seconds=0)

    def count(self, operation):
        return sum(call[:3] == ['xcrun', 'notarytool', operation] for call in self.calls)

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

    def test_apple_outage_while_waiting_keeps_polling_the_same_submission(self):
        self.outages = {'info': 2, 'log': 1}
        self.assertEqual(self.execute()['phase'], 'complete')
        self.assertEqual((self.count('submit'), self.count('info'), self.count('log')), (1, 3, 2))
        self.assertEqual(self.clock.sleeps, [120] * 3)

    def test_apple_outage_during_upload_submits_again_only_when_apple_never_registered_it(self):
        self.outages = {'submit': 1}
        self.assertEqual(self.execute()['submission_id'], SUBMISSION)
        self.assertEqual((self.count('submit'), self.count('history')), (2, 1))

    def test_apple_outage_during_an_upload_apple_registered_never_uploads_twice(self):
        self.outages = {'submit': 1}
        self.history = [{'name': 'Parc-' + self.package.parent.name + '.zip', 'id': 'registered',
                         'createdDate': notarize.service.utc().isoformat().replace('+00:00', 'Z')}]
        for _ in range(2):
            with self.assertRaisesRegex(notarize.Refusal, 'lists registered'):
                self.execute()
        self.assertEqual((self.count('submit'), self.count('history')), (1, 2))
        self.assert_unpublished()

    def test_apple_outage_lasting_two_hours_stops_with_a_resumable_exit(self):
        self.outages = {'info': 61}
        with self.assertRaises(notarize.service.Unavailable):
            self.execute()
        self.clock.now = 0
        self.assertEqual(self.execute()['phase'], 'complete')
        self.assertEqual(self.count('submit'), 1)
        with patch.object(notarize, 'notarize', side_effect=notarize.service.Unavailable('HTTP 503')), \
                patch.object(notarize.sys, 'argv', ['notarize-app.py', str(self.package), '--profile', 'p', '--team', TEAM]), \
                contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(notarize.main(), 75)
        self.assertIn("Apple's notary service is down (HTTP 503)", errors.getvalue())

    def stop_for_agreement_then_resume(self, operation):
        self.unsigned = {operation}
        with self.assertRaisesRegex(notarize.service.Agreement, '^Apple needs you to accept'):
            self.execute()
        self.assertEqual((self.count('submit'), self.count(operation), self.clock.sleeps), (1, 1, []))
        self.unsigned = set()
        self.assertEqual(self.execute()['phase'], 'complete')
        self.assertEqual(self.count('submit'), 1)

    def test_unaccepted_apple_agreement_while_polling_stops_and_resumes_the_same_submission(self):
        self.stop_for_agreement_then_resume('info')

    def test_unaccepted_apple_agreement_while_fetching_the_log_stops_and_resumes_the_same_submission(self):
        self.stop_for_agreement_then_resume('log')

    def test_unaccepted_apple_agreement_during_upload_stops_and_the_rerun_checks_history_first(self):
        self.unsigned = {'submit'}
        with self.assertRaises(notarize.service.Agreement):
            self.execute()
        self.assertEqual((self.count('submit'), self.count('history'), self.clock.sleeps), (1, 0, []))
        self.assert_unpublished()
        self.unsigned = set()
        self.calls.clear()
        self.assertEqual(self.execute()['phase'], 'complete')
        operations = [call[2] for call in self.calls if call[:2] == ['xcrun', 'notarytool']]
        self.assertEqual(operations[:2], ['history', 'submit'])

    def test_unaccepted_apple_agreement_exits_with_its_own_status(self):
        with patch.object(notarize, 'notarize', side_effect=notarize.service.Agreement()), \
                patch.object(notarize.sys, 'argv', ['notarize-app.py', str(self.package), '--profile', 'p', '--team', TEAM]), \
                contextlib.redirect_stderr(io.StringIO()) as errors:
            self.assertEqual(notarize.main(), 77)
        self.assertEqual(errors.getvalue(), 'Notarization refused: ' + notarize.service.ACCEPT_AGREEMENT + '\n')

    def test_receipt_from_an_older_unconfirmed_upload_refuses_without_calling_apple(self):
        folder = self.package.parent / 'notarization'
        folder.mkdir()
        invariant = {key: value for key, value in self.report.items() if key not in ('notarized', 'notarization')}
        fingerprint = notarize.hashlib.sha256(json.dumps(invariant, sort_keys=True).encode()).hexdigest()
        (folder / 'submission.json').write_text(json.dumps({'team': TEAM, 'package_fingerprint': fingerprint,
                                                            'phase': 'submitting', 'archive': 'Parc-run.zip',
                                                            'archive_sha256': 'a' * 64}))
        with self.assertRaisesRegex(notarize.Refusal, 'earlier upload has no confirmed ID'):
            self.execute()
        self.assertFalse([call for call in self.calls if call[:2] == ['xcrun', 'notarytool']])

    def test_upload_outage_lasting_two_hours_reruns_through_history_once(self):
        self.outages = {'submit': 61}
        with self.assertRaises(notarize.service.Unavailable):
            self.execute()
        self.clock.now = 0
        self.calls.clear()
        self.assertEqual(self.execute()['phase'], 'complete')
        operations = [call[2] for call in self.calls if call[:2] == ['xcrun', 'notarytool']]
        self.assertEqual(operations[:2], ['history', 'submit'])
        self.assertEqual(self.count('submit'), 1)

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

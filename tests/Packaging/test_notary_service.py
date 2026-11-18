import contextlib
import datetime
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('parc_notary_service_test', Path(__file__).resolve().parents[2] /
                                              'scripts/notary_service.py')
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)
OUTAGE = ('Error: invalidJSONResponse(statusCode: Optional(503), data: "<html>\\n<head>\\n<title>503 Service '
          'Unavailable</title>\\n</head>\\n<body>\\n<div id=\\"desc\\">It appears no upstream tasks are announcing '
          'via service discovery.</div>\\n<span class=\\"value\\">1e2b0fba-51fc-479f-a1f3-a4b78cec220c</span>'
          '\\n</body>\\n</html>\\n")\n')


class Clock:
    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


def result(code, output='', args=('xcrun', 'notarytool', 'history')):
    return subprocess.CompletedProcess(list(args), code, output, '')


class Classifier(unittest.TestCase):
    def test_outages_are_never_credential_problems(self):
        cases = {
            OUTAGE: 'HTTP 503',
            'Error: invalidJSONResponse(statusCode: Optional(502), data: "<html>Bad Gateway</html>")': 'HTTP 502',
            'Error: HTTP status code: 500. Internal Server Error': 'HTTP 500',
            '<html><head><title>504 Gateway Time-out</title></head></html>': 'HTTP 504',
            'Error: The request timed out.': 'timed out',
            'notarytool timed out after 300 seconds': 'timed out',
            'Error Domain=NSURLErrorDomain Code=-1009 "The Internet connection appears to be offline."': 'network error',
            'Error: A server with the specified hostname could not be found.': 'network error',
        }
        for output, reason in cases.items():
            with self.subTest(output=output[:60]):
                self.assertEqual(service.classify(1, output), (service.UNAVAILABLE, reason))

    def test_only_authentication_and_profile_errors_are_credential_problems(self):
        for output in ('Error: HTTP status code: 401. Invalid credentials. Username or password is incorrect.',
                       'Error: HTTP status code: 403. A required agreement is missing or has expired.',
                       'Error: No Keychain password item found for profile: parc-notary',
                       'Error: errSecItemNotFound: The specified item could not be found in the keychain.'):
            with self.subTest(output=output[:60]):
                self.assertEqual(service.classify(69, output)[0], service.CREDENTIALS)

    def test_success_and_unrecognised_failures(self):
        self.assertEqual(service.classify(0, '{"history": []}'), (service.OK, None))
        self.assertEqual(service.classify(0, OUTAGE), (service.OK, None))
        self.assertEqual(service.classify(1, 'Error: Unexpected argument'), (service.FAILED, None))
        self.assertEqual(service.classify(1, 'Error: HTTP status code: 404. Not Found'), (service.FAILED, 'HTTP 404'))
        for local in ('Error Domain=NSURLErrorDomain Code=-1202 "The certificate for this server is invalid."',
                      'Error Domain=NSURLErrorDomain Code=-999 "cancelled"'):
            self.assertEqual(service.classify(1, local), (service.FAILED, None))


class Waiting(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.lines = []
        patcher = patch.object(service, 'time', self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_outage_waits_two_minutes_between_attempts_until_apple_is_back(self):
        replies = [result(1, OUTAGE)] * 3 + [result(0, '{"history": []}')]
        kind, final = service.wait(lambda: replies.pop(0), self.lines.append)
        self.assertEqual((kind, final.stdout), (service.OK, '{"history": []}'))
        self.assertEqual(self.clock.sleeps, [120] * 3)
        self.assertEqual(self.lines, ["Apple's notary service is unavailable (HTTP 503); waiting and retrying"] * 3)

    def test_outage_gives_up_after_two_hours_with_a_plain_message(self):
        attempts = []
        with self.assertRaises(service.Unavailable) as raised:
            service.wait(lambda: attempts.append(self.clock.now) or result(1, OUTAGE), self.lines.append)
        self.assertEqual(len(attempts), 61)
        self.assertEqual(attempts[-1], 7200)
        self.assertEqual(sum(self.clock.sleeps), 7200)
        message = str(raised.exception)
        self.assertIn("Apple's notary service is down (HTTP 503)", message)
        self.assertIn('Rerun the same command', message)
        self.assertNotIn('1Password', message)

    def test_credential_and_unknown_failures_return_without_waiting(self):
        for output, kind in (('Error: No Keychain password item found for profile: parc-notary', service.CREDENTIALS),
                             ('Error: HTTP status code: 401. Invalid credentials.', service.CREDENTIALS),
                             ('Error: Unexpected argument', service.FAILED)):
            with self.subTest(kind=kind):
                self.assertEqual(service.wait(lambda: result(69, output), self.lines.append)[0], kind)
        self.assertEqual((self.clock.sleeps, self.lines), ([], []))

    def test_check_command_exit_codes(self):
        for replies, code in (([result(0, '{}')], 0), ([result(69, 'Error: HTTP status code: 401.')], 3),
                              ([result(1, 'Error: Unexpected argument')], 2), ([result(1, OUTAGE)] * 61, 75)):
            with self.subTest(code=code), \
                    patch.object(service.subprocess, 'run', side_effect=lambda *args, **kwargs: replies.pop(0)), \
                    patch.object(service.sys, 'argv', ['notary_service.py', 'check', '--profile', 'parc-notary']), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(service.main(), code)
                if code == 75:
                    self.assertIn("Apple's notary service is down", errors.getvalue())

    def test_hung_notarytool_counts_as_a_timeout(self):
        with patch.object(service.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['xcrun'], 300)):
            hung = service.run(['xcrun', 'notarytool', 'info', 'id'])
        self.assertEqual(service.classify(hung.returncode, hung.stdout + hung.stderr), (service.UNAVAILABLE, 'timed out'))


class Submitting(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / 'Parc-package.zip'
        self.archive.write_bytes(b'archive')
        self.clock = Clock()
        patcher = patch.object(service, 'time', self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.receipt = {'phase': 'archived'}
        self.saved = []
        self.calls = []
        self.submits = []
        self.listed = []

    def tool(self, args, **kwargs):
        self.calls.append(args)
        if args[2] == 'submit':
            reply = self.submits.pop(0)
            if reply == 'outage':
                return result(1, OUTAGE, args)
            if reply == 'locked':
                return result(1, 'Error: No Keychain password item found for profile: parc-notary', args)
            return result(0, json.dumps({'id': reply}), args)
        entries = self.listed.pop(0) if self.listed else []
        return result(0, entries if isinstance(entries, str) else json.dumps({'history': entries}), args)

    def submit(self):
        with patch.object(service.subprocess, 'run', side_effect=self.tool):
            return service.submit(self.archive, 'parc-notary', Path(self.temp.name) / 'submit.log', self.receipt,
                                  lambda value: self.saved.append(dict(value)), 'unconfirmed', report=lambda line: None)

    def count(self, operation):
        return sum(call[2] == operation for call in self.calls)

    def test_outage_before_apple_registers_the_upload_submits_again(self):
        self.submits = ['outage', 'b6743aa6-df42-48cb-bd8e-cbbebee591fd']
        self.assertEqual(self.submit(), 'b6743aa6-df42-48cb-bd8e-cbbebee591fd')
        self.assertEqual((self.count('submit'), self.count('history')), (2, 1))
        self.assertEqual(self.clock.sleeps, [120])
        self.assertEqual(self.receipt['phase'], 'submitted')
        self.assertNotIn('submit_failure', self.receipt)
        self.assertNotIn('unconfirmed_since', self.receipt)
        self.assertIn('submit_failure', self.saved[1])

    def test_outage_after_apple_registered_the_upload_never_uploads_again(self):
        self.submits = ['outage']
        recent = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        self.listed = [[{'name': 'Parc-arm64.dmg', 'createdDate': recent, 'id': 'other'},
                        {'name': 'Parc-package.zip', 'createdDate': '2026-11-01T10:00:00.000Z', 'id': 'old'},
                        {'name': 'Parc-package.zip', 'createdDate': recent, 'id': 'registered'}]]
        with self.assertRaisesRegex(service.Refusal, 'lists registered; nothing was uploaded again'):
            self.submit()
        self.assertEqual(self.count('submit'), 1)
        self.assertNotIn('submission_id', self.receipt)

    def test_long_outage_stops_and_the_rerun_reconciles_before_submitting(self):
        self.submits = ['outage'] * 61
        with self.assertRaises(service.Unavailable):
            self.submit()
        self.assertEqual(self.receipt['submit_failure'], 'HTTP 503')
        uploads = self.count('submit')
        self.calls.clear()
        self.clock.now = 0
        self.submits = ['c0ffee00-0000-4000-8000-000000000000']
        self.assertEqual(self.submit(), 'c0ffee00-0000-4000-8000-000000000000')
        self.assertEqual([call[2] for call in self.calls], ['history', 'submit'])
        self.assertGreater(uploads, 1)

    def test_credential_failure_during_upload_reruns_through_history_instead_of_stalling(self):
        self.submits = ['locked']
        with self.assertRaisesRegex(service.Refusal, 'checks notarytool history before uploading again'):
            self.submit()
        self.assertEqual((self.count('submit'), self.receipt['submit_failure']), (1, 'credentials'))
        self.submits, self.listed = ['d00d0000-0000-4000-8000-000000000000'], [[
            {'name': 'Parc-package.zip', 'createdDate': None, 'id': 'undated'}]]
        self.assertEqual(self.submit(), 'd00d0000-0000-4000-8000-000000000000')
        self.assertEqual(self.count('submit'), 2)

    def test_history_check_looks_back_to_the_first_unconfirmed_attempt(self):
        first = service.utc() - datetime.timedelta(hours=2)
        self.receipt.update(phase='submitting', submit_failure='timed out', unconfirmed_since=first.isoformat(),
                            submit_started_utc=(first + datetime.timedelta(hours=1)).isoformat())
        self.listed = [[{'name': 'Parc-package.zip', 'id': 'first-attempt',
                         'createdDate': (first + datetime.timedelta(minutes=1)).isoformat().replace('+00:00', 'Z')}]]
        with self.assertRaisesRegex(service.Refusal, 'lists first-attempt'):
            self.submit()
        self.assertEqual(self.count('submit'), 0)

    def test_unreadable_history_refuses_instead_of_uploading(self):
        self.submits, self.listed = ['outage'], ['[]']
        with self.assertRaisesRegex(service.Refusal, "can't read"):
            self.submit()
        self.assertEqual(self.count('submit'), 1)

    def test_unconfirmed_upload_that_is_not_an_outage_stops_for_reconciliation(self):
        self.submits = ['']
        with self.assertRaisesRegex(service.Refusal, '^unconfirmed$'):
            self.submit()
        self.assertEqual((self.count('submit'), self.receipt['phase']), (1, 'submitting'))


if __name__ == '__main__':
    unittest.main()

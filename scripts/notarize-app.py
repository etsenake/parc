#!/usr/bin/env python3
"""Notarize a pristine distribution package; retain the submission for retries."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


class Refusal(RuntimeError):
    pass


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def save(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def command(args, log):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise Refusal(f'{args[0]} failed; see {log}')
    return result.stdout


def notarize(package, profile, team, poll_seconds=20):
    package = package.resolve()
    app = package / 'Parc.app'
    report_path = package / 'package-report.json'
    report = json.loads(report_path.read_text())
    if (report.get('configuration') != 'release'
            or report.get('purpose') != 'distribution'
            or report.get('layout') != 'standalone-app'
            or report.get('distribution_eligible') is not True
            or report.get('signing_team') != team):
        raise Refusal('Notarization requires a matching-Team standalone release distribution package')
    folder = package.parent / 'notarization'
    folder.mkdir(exist_ok=True)
    lock = (folder / 'operation.lock').open('a+')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        raise Refusal('This package already has an active notarization operation') from error
    with lock:
        invariant = {key: value for key, value in report.items()
                     if key not in ('notarized', 'notarization')}
        fingerprint = hashlib.sha256(json.dumps(invariant, sort_keys=True).encode()).hexdigest()
        receipt_path = folder / 'submission.json'
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        if receipt and (receipt['package_fingerprint'] != fingerprint or receipt['team'] != team):
            raise Refusal('Package changed since submission; preserve the original notarization inputs')

        def verify_images():
            images = report.get('signed_images', {})
            if not images:
                raise Refusal('Package has no signed-image inventory')
            for relative, expected in images.items():
                image = package / relative
                if not image.resolve().is_relative_to(app.resolve()) or digest(image) != expected:
                    raise Refusal('Signed package image differs from its report: ' + relative)
                result = subprocess.run(['codesign', '-dv', '--verbose=4', str(image)],
                                        capture_output=True, text=True, check=True)
                details = result.stdout + result.stderr
                if (f'TeamIdentifier={team}\n' not in details
                        or 'Authority=Developer ID Application: ' not in details
                        or not re.search(r'^Timestamp=.+', details, re.M)):
                    raise Refusal('Every image needs timestamped Developer ID signing: ' + relative)
            command(['codesign', '--verify', '--deep', '--strict', app], folder / 'codesign.log')

        verify_images()
        if receipt is None:
            archive = folder / ('Parc-' + package.parent.name + '.zip')
            command(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive],
                    folder / 'archive.log')
            receipt = {'team': team, 'package_fingerprint': fingerprint, 'phase': 'submitting',
                       'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       'archive': archive.name, 'archive_sha256': digest(archive)}
            save(receipt_path, receipt)
            result = subprocess.run(['xcrun', 'notarytool', 'submit', str(archive),
                                     '--keychain-profile', profile, '--output-format', 'json'],
                                    capture_output=True, text=True)
            (folder / 'submit.log').write_text(result.stdout + result.stderr)
            try:
                submitted = json.loads(result.stdout)
            except ValueError:
                submitted = {}
            if submitted.get('id'):
                receipt.update(submission_id=submitted['id'], phase='submitted')
                save(receipt_path, receipt)
            if result.returncode or not receipt.get('submission_id'):
                raise Refusal('Submission did not return a confirmed ID; inspect submit.log and notarytool '
                              'history before retrying. Do not submit another copy automatically.')
        if not receipt.get('submission_id'):
            raise Refusal('An earlier upload has no confirmed ID; reconcile it with notarytool history '
                          'and record its submission_id before resuming')
        submission_id = receipt['submission_id']
        while True:
            info = json.loads(command(['xcrun', 'notarytool', 'info', submission_id,
                                      '--keychain-profile', profile, '--output-format', 'json'],
                                     folder / 'status.json'))
            status = info.get('status')
            receipt.update(status=status, phase='processing')
            save(receipt_path, receipt)
            if status in ('Accepted', 'Invalid', 'Rejected'):
                break
            if status != 'In Progress':
                raise Refusal('Unrecognized notarization status: ' + repr(status))
            print('Apple notarization pending: ' + submission_id, flush=True)
            time.sleep(poll_seconds)
        command(['xcrun', 'notarytool', 'log', submission_id, '--keychain-profile', profile,
                 str(folder / 'apple-log.json')], folder / 'download-log.log')
        apple_log = json.loads((folder / 'apple-log.json').read_text())
        if status != 'Accepted' or apple_log.get('status') != 'Accepted':
            receipt.update(phase='rejected')
            save(receipt_path, receipt)
            raise Refusal('Apple rejected notarization; inspect ' + str(folder / 'apple-log.json'))
        if (apple_log.get('jobId') != submission_id
                or apple_log.get('sha256', '').lower() != receipt['archive_sha256']):
            raise Refusal('Apple approval log does not match this submission and archive')
        command(['xcrun', 'stapler', 'staple', app], folder / 'staple.log')
        command(['xcrun', 'stapler', 'validate', app], folder / 'staple-validation.log')
        verify_images()
        command(['spctl', '--assess', '--type', 'execute', '--verbose=4', app],
                folder / 'gatekeeper.log')
        receipt.update(phase='complete', completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       stapled=True, gatekeeper_verified=True,
                       apple_log_sha256=digest(folder / 'apple-log.json'))
        save(receipt_path, receipt)
        report['notarized'] = True
        report['notarization'] = {key: receipt[key] for key in
                                  ('submission_id', 'status', 'team', 'stapled',
                                   'gatekeeper_verified', 'completed_utc', 'apple_log_sha256')}
        report['notarization']['apple_log_issues'] = apple_log.get('issues') or []
        save(report_path, report)
        print('Apple notarization accepted, stapled and Gatekeeper verified: ' + submission_id, flush=True)
        return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--profile', required=True, help='notarytool Keychain profile; never a password')
    parser.add_argument('--team', required=True)
    args = parser.parse_args()
    try:
        notarize(args.package, args.profile, args.team)
        return 0
    except (Refusal, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print('Notarization refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

"""Exercise the published cask without deleting any browser data."""
import json
import os
from pathlib import Path
import subprocess
import sys

import release_install as install


def upgrade(package, receipts):
    receipts.mkdir(parents=True, exist_ok=True, mode=0o700)
    report = json.loads((package / 'package-report.json').read_text())
    version = report['app_version']['version']
    app = Path('/Applications/Parc.app')
    check = install.checker()
    check.verify_installed(app, report, strict=False)
    info = json.loads(subprocess.check_output(['brew', 'info', '--json=v2', '--cask', 'etsenake/tap/parc'], text=True))['casks'][0]
    if info['version'] != version:
        raise ValueError('The installed tap does not resolve the released version')
    acceptance = receipts / 'acceptance.json'
    if acceptance.exists():
        check.publisher.verify_acceptance(json.loads(acceptance.read_text()), 'v' + version,
            json.loads((receipts.parent / 'state.json').read_text())['commit'], report['app_version'], install.digest(package / 'package-report.json'))
        return
    if info.get('installed') == version:
        # The initial install stage already supplied normal startup acceptance.
        install.atomic(receipts / 'homebrew.json', {'version': version, 'installed': version, 'already_registered': True})
        return
    install.stop_app(app)
    profile, before, backup = install.backup_profile(receipts)
    old = receipts / 'before-Parc.app'
    if not old.exists():
        subprocess.run(['ditto', str(app), str(old)], check=True)
    if info.get('installed'):
        args = ['brew', 'upgrade', '--cask', 'etsenake/tap/parc']
    else:
        # Fresh machines may have a manually installed copy. Move it, never
        # uninstall/zap the profile or merge bundles, then install through brew.
        os.rename(app, receipts / 'manual-Parc.app')
        args = ['brew', 'install', '--cask', 'etsenake/tap/parc']
    subprocess.run(args, check=True)
    if install.profile_inventory(profile) != before:
        raise ValueError('Profile changed during Homebrew installation; backup retained')
    check.verify_installed(app, report, strict=True)
    commit = json.loads((receipts.parent / 'state.json').read_text())['commit']
    result = check.record(package, app, 'v' + version, commit, acceptance, seconds=90)
    if result['status'] != 'passed':
        raise ValueError('Homebrew startup check failed; raw evidence and profile preserved')
    install.atomic(receipts / 'homebrew.json', {'version': version, 'profile_unchanged_before_launch': True,
                                               'profile_backup': str(backup), 'installed': version})


if __name__ == '__main__':
    upgrade(Path(sys.argv[1]), Path(sys.argv[2]))

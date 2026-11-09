#!/usr/bin/env python3
"""Store/restore Parc's signing credentials in an unlocked 1Password vault: the selected
encrypted Developer ID identity and Sparkle's EdDSA update key.

No private key/password in argv, logs, plaintext files or GitHub; Sparkle's own
generate_keys only reads or writes its key through a removed 0600 temporary file.
Normal Keychain approval is never bypassed. Notarization profiles use Apple's
separate --sync.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TITLE = 'Parc Developer ID 94HKA7L2DR'
SPARKLE_TITLE = 'Parc Sparkle EdDSA key'
spec = importlib.util.spec_from_file_location('parc_signing_sparkle', Path(__file__).with_name('sparkle.py'))
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


def run(args, *, data=None, umask=-1):
    result = subprocess.run(args, input=data, text=True, capture_output=True, timeout=60, umask=umask)
    if result.returncode:
        # Tool diagnostics can echo secret-bearing input. Emit only the operation.
        raise ValueError('Credential operation failed: ' + Path(args[0]).name + ' ' + args[1])
    return result.stdout.strip()


def fields(item):
    return {field['id']: field.get('value', '') for field in item['fields']}


def existing(title):
    result = subprocess.run(['op','item','get',title,'--format=json'], capture_output=True, text=True, timeout=15)
    return fields(json.loads(result.stdout)) if result.returncode == 0 else None


def create(template):
    """Save a vault item and return its fields from a fresh read."""
    args = ['op','item','create','--format=json']
    if os.environ.get('PARC_SIGNING_VAULT'):
        args += ['--vault',os.environ['PARC_SIGNING_VAULT']]
    created = json.loads(run(args,data=json.dumps(template)))
    return fields(json.loads(run(['op','item','get',created['id'],'--format=json'])))


def helper():
    source = ROOT / 'scripts/signing-keychain.swift'
    cache = ROOT / 'build/signing-tools'; cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    output = cache / ('keychain-' + hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not output.exists():
        run(['xcrun','swiftc',str(source),'-o',str(output),'-framework','Security'])
    return str(output)


def backup():
    # Do not prompt/unlock 1Password behind an unattended release.
    env = dict(os.environ, OP_BIOMETRIC_UNLOCK_ENABLED='false')
    result = subprocess.run(['op','whoami','--format=json'], capture_output=True, env=env, timeout=10)
    if result.returncode:
        raise ValueError('Unlock/sign in to 1Password CLI once with op signin; secure backup is pending')
    backup_identity()
    backup_sparkle()


def backup_identity():
    identity = (Path.home() / '.config/parc/signing-identity').read_text().strip()
    if not identity.startswith('Developer ID Application: ') or not identity.endswith('(94HKA7L2DR)'):
        raise ValueError('Only the selected Team 94HKA7L2DR Developer ID may be backed up')
    saved = existing(TITLE)
    if saved is not None:
        if saved.get('identity') != identity or not saved.get('pkcs12') or not saved.get('password'):
            raise ValueError('Existing signing vault entry differs or is incomplete; it was preserved')
        print('Existing encrypted production identity backup verified in 1Password')
        return
    password = secrets.token_urlsafe(48)
    encoded = run([helper(),'export'], data=json.dumps({'identity':identity,'password':password}))
    base64.b64decode(encoded, validate=True)
    saved = create({'title':TITLE,'category':'SECURE_NOTE','tags':['Parc','production-signing'], 'fields':[
        {'id':'identity','type':'STRING','label':'Identity','value':identity},
        {'id':'pkcs12','type':'CONCEALED','label':'Encrypted PKCS12','value':encoded},
        {'id':'password','type':'CONCEALED','label':'PKCS12 password','value':password}]})
    # Verify the saved secret bytes through a fresh read without exposing them.
    if saved.get('pkcs12') != encoded or saved.get('password') != password:
        raise ValueError('Vault round-trip verification failed; no successful backup claimed')
    print('Selected production identity encrypted and backed up to 1Password')


def generate_keys():
    return [str(sparkle.fetch(ROOT / 'build/sparkle') / 'bin/generate_keys'), '--account', sparkle.ACCOUNT]


def backup_sparkle():
    if not sparkle.has_key():
        raise ValueError("No Sparkle signing key (account parc) in this Mac's login Keychain to back up")
    tool = generate_keys()
    if run([*tool, '-p']) != sparkle.PUBLIC_ED_KEY:
        raise ValueError("The Keychain's Sparkle key is not the one Parc trusts; nothing was backed up")
    saved = existing(SPARKLE_TITLE)
    if saved is not None:
        if (saved.get('account') != sparkle.ACCOUNT or saved.get('public_key') != sparkle.PUBLIC_ED_KEY
                or not saved.get('private_key')):
            raise ValueError('Existing Sparkle key vault entry differs or is incomplete; it was preserved')
        print('Existing Sparkle signing key backup verified in 1Password')
        return
    with tempfile.TemporaryDirectory(prefix='parc-sparkle-') as folder:
        exported = Path(folder) / 'key'
        run([*tool, '-x', str(exported)], umask=0o077)
        key = exported.read_text().strip()
    if len(base64.b64decode(key, validate=True)) not in (32, 96):
        raise ValueError('Sparkle exported a key in an unexpected format; nothing was backed up')
    saved = create({'title':SPARKLE_TITLE,'category':'SECURE_NOTE','tags':['Parc','production-signing'], 'fields':[
        {'id':'account','type':'STRING','label':'Keychain account','value':sparkle.ACCOUNT},
        {'id':'public_key','type':'STRING','label':'SUPublicEDKey','value':sparkle.PUBLIC_ED_KEY},
        {'id':'private_key','type':'CONCEALED','label':'Private EdDSA key','value':key}]})
    if saved.get('private_key') != key:
        raise ValueError('Vault round-trip verification failed; no successful backup claimed')
    print('Sparkle signing key backed up to 1Password')


def restore():
    """Restore whichever credential this Mac's Keychain lacks."""
    restore_identity()
    restore_sparkle()


def restore_identity():
    identities = run(['security','find-identity','-v','-p','codesigning'])
    if re.search(r'"Developer ID Application: [^"\n]+ \(94HKA7L2DR\)"', identities):
        print('Production identity already in the normal Keychain')
        return
    saved = fields(json.loads(run(['op','item','get',TITLE,'--format=json'])))
    identity = saved['identity']
    if not identity.startswith('Developer ID Application: ') or not identity.endswith('(94HKA7L2DR)'):
        raise ValueError('Vault entry is not the expected production identity')
    run([helper(),'import'],data=json.dumps({'pkcs12':saved['pkcs12'],'password':saved['password']}))
    identities = run(['security','find-identity','-v','-p','codesigning'])
    if '"' + identity + '"' not in identities:
        raise ValueError('Imported identity does not validate for code signing')
    config = Path.home() / '.config/parc/signing-identity'; config.parent.mkdir(parents=True,exist_ok=True)
    if config.exists() and config.read_text().strip() != identity:
        raise ValueError('Existing signing configuration differs; preserved')
    config.write_text(identity + '\n')
    print('Production identity restored and validated in the normal Keychain')


def restore_sparkle():
    if sparkle.has_key():
        print('Sparkle signing key already in the login Keychain')
        return
    saved = fields(json.loads(run(['op','item','get',SPARKLE_TITLE,'--format=json'])))
    if saved.get('account') != sparkle.ACCOUNT or saved.get('public_key') != sparkle.PUBLIC_ED_KEY:
        raise ValueError('Vault entry is not the Sparkle key Parc trusts')
    tool = generate_keys()
    with tempfile.TemporaryDirectory(prefix='parc-sparkle-') as folder:
        imported = Path(folder) / 'key'
        with os.fdopen(os.open(imported, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
            stream.write(saved['private_key'])
        run([*tool, '-f', str(imported)])
    if run([*tool, '-p']) != sparkle.PUBLIC_ED_KEY:
        raise ValueError("The restored Sparkle key is not the one Parc trusts")
    print('Sparkle signing key restored and verified in the login Keychain')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('operation',choices=('backup','restore'))
    args=parser.parse_args()
    try:
        backup() if args.operation == 'backup' else restore()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1,str(error)+'\n')

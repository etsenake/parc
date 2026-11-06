#!/usr/bin/env python3
"""Store/restore Parc's selected encrypted signing identity in an unlocked 1Password vault.

No private key/password in argv, logs, plaintext files or GitHub. Normal Keychain
approval is never bypassed. Notarization profiles use Apple's separate --sync.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TITLE = 'Parc Developer ID 94HKA7L2DR'


def run(args, *, data=None):
    result = subprocess.run(args, input=data, text=True, capture_output=True, timeout=60)
    if result.returncode:
        # Tool diagnostics can echo secret-bearing input. Emit only the operation.
        raise ValueError('Credential operation failed: ' + args[0] + ' ' + args[1])
    return result.stdout.strip()


def helper():
    source = ROOT / 'scripts/signing-keychain.swift'
    cache = ROOT / 'build/signing-tools'; cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    output = cache / ('keychain-' + hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not output.exists():
        run(['xcrun','swiftc',str(source),'-o',str(output),'-framework','Security'])
    return str(output)


def backup():
    identity = (Path.home() / '.config/parc/signing-identity').read_text().strip()
    if not identity.startswith('Developer ID Application: ') or not identity.endswith('(94HKA7L2DR)'):
        raise ValueError('Only the selected Team 94HKA7L2DR Developer ID may be backed up')
    # Do not prompt/unlock 1Password behind an unattended release.
    env = dict(os.environ, OP_BIOMETRIC_UNLOCK_ENABLED='false')
    result = subprocess.run(['op','whoami','--format=json'], capture_output=True, env=env, timeout=10)
    if result.returncode:
        raise ValueError('Unlock/sign in to 1Password CLI once with op signin; secure backup is pending')
    existing = subprocess.run(['op','item','get',TITLE,'--format=json'], capture_output=True, text=True, timeout=15)
    if existing.returncode == 0:
        value = json.loads(existing.stdout)
        fields = {item['id']:item.get('value','') for item in value['fields']}
        if fields.get('identity') != identity or not fields.get('pkcs12') or not fields.get('password'):
            raise ValueError('Existing signing vault entry differs or is incomplete; it was preserved')
        print('Existing encrypted production identity backup verified in 1Password')
        return
    password = secrets.token_urlsafe(48)
    encoded = run([helper(),'export'], data=json.dumps({'identity':identity,'password':password}))
    base64.b64decode(encoded, validate=True)
    template = {'title':TITLE,'category':'SECURE_NOTE','tags':['Parc','production-signing'], 'fields':[
        {'id':'identity','type':'STRING','label':'Identity','value':identity},
        {'id':'pkcs12','type':'CONCEALED','label':'Encrypted PKCS12','value':encoded},
        {'id':'password','type':'CONCEALED','label':'PKCS12 password','value':password}]}
    args = ['op','item','create','--format=json']
    if os.environ.get('PARC_SIGNING_VAULT'):
        args += ['--vault',os.environ['PARC_SIGNING_VAULT']]
    created = json.loads(run(args,data=json.dumps(template)))
    # Verify the saved secret bytes through a fresh read without exposing them.
    saved = json.loads(run(['op','item','get',created['id'],'--format=json']))
    fields = {item['id']:item.get('value','') for item in saved['fields']}
    if fields.get('pkcs12') != encoded or fields.get('password') != password:
        raise ValueError('Vault round-trip verification failed; no successful backup claimed')
    print('Selected production identity encrypted and backed up to 1Password')


def restore():
    saved = json.loads(run(['op','item','get',TITLE,'--format=json']))
    fields = {item['id']:item.get('value','') for item in saved['fields']}
    identity = fields['identity']
    if not identity.startswith('Developer ID Application: ') or not identity.endswith('(94HKA7L2DR)'):
        raise ValueError('Vault entry is not the expected production identity')
    run([helper(),'import'],data=json.dumps({'pkcs12':fields['pkcs12'],'password':fields['password']}))
    identities = run(['security','find-identity','-v','-p','codesigning'])
    if '"' + identity + '"' not in identities:
        raise ValueError('Imported identity does not validate for code signing')
    config = Path.home() / '.config/parc/signing-identity'; config.parent.mkdir(parents=True,exist_ok=True)
    if config.exists() and config.read_text().strip() != identity:
        raise ValueError('Existing signing configuration differs; preserved')
    config.write_text(identity + '\n')
    print('Production identity restored and validated in the normal Keychain')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('operation',choices=('backup','restore'))
    args=parser.parse_args()
    try:
        backup() if args.operation == 'backup' else restore()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1,str(error)+'\n')

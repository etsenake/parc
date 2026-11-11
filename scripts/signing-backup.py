#!/usr/bin/env python3
"""Store/restore Parc's signing credentials in an unlocked 1Password vault: the selected
encrypted Developer ID identity, Sparkle's EdDSA update key and the notarytool profile.

No private key/password in argv, logs, plaintext files or GitHub; Sparkle's own
generate_keys only reads or writes its key through a removed 0600 temporary file,
and notarytool reads its password on standard input. Normal Keychain approval is
never bypassed.
"""
import argparse
import base64
import getpass
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
NOTARY_TITLE = 'Parc notary profile'
PROFILE = os.environ.get('PARC_NOTARY_PROFILE', 'parc-notary')
os.environ.setdefault('OP_ACCOUNT', 'my.1password.ca')
spec = importlib.util.spec_from_file_location('parc_signing_sparkle', Path(__file__).with_name('sparkle.py'))
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


def run(args, *, data=None, umask=-1, start_new_session=False):
    result = subprocess.run(args, input=data, text=True, capture_output=True, timeout=60, umask=umask,
                            start_new_session=start_new_session)
    if result.returncode:
        raise ValueError('Credential operation failed: ' + ' '.join([Path(args[0]).name, *args[1:]]))
    return result.stdout.strip()


def fields(item):
    return {field['id']: field.get('value', '') for field in item['fields']}


def vault():
    return ['--vault', os.environ['PARC_SIGNING_VAULT']] if os.environ.get('PARC_SIGNING_VAULT') else []


def existing(title):
    found = [item['id'] for item in json.loads(run(['op','item','list','--format=json',*vault()])) if item['title'] == title]
    if len(found) > 1:
        raise ValueError('More than one 1Password item is titled ' + title + '; preserved for manual cleanup')
    return fields(json.loads(run(['op','item','get',found[0],'--format=json']))) if found else None


def create(template):
    created = json.loads(run(['op','item','create','--format=json',*vault()],data=json.dumps(template)))
    return fields(json.loads(run(['op','item','get',created['id'],'--format=json'])))


def helper():
    source = ROOT / 'scripts/signing-keychain.swift'
    cache = ROOT / 'build/signing-tools'; cache.mkdir(parents=True, exist_ok=True, mode=0o700)
    output = cache / ('keychain-' + hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not output.exists():
        run(['xcrun','swiftc',str(source),'-o',str(output),'-framework','Security'])
    return str(output)


def backup():
    result = subprocess.run(['op','whoami','--format=json'], capture_output=True, timeout=120)
    if result.returncode:
        raise ValueError('Sign in to 1Password CLI with op signin --account ' + os.environ['OP_ACCOUNT']
                         + '; secure backup is pending')
    backup_identity()
    backup_sparkle()
    backup_notary()


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


def notarytool(*args, password):
    run(['xcrun','notarytool',*args,'--team-id','94HKA7L2DR'], data=password + '\n', start_new_session=True)


def notary_works():
    try:
        run(['xcrun','notarytool','history','--keychain-profile',PROFILE,'--output-format','json'])
    except (ValueError, subprocess.TimeoutExpired):
        return False
    return True


def backup_notary():
    saved = existing(NOTARY_TITLE)
    if saved is not None:
        if saved.get('team_id') != '94HKA7L2DR' or not saved.get('apple_id') or not saved.get('password'):
            raise ValueError('Existing notary profile vault entry differs or is incomplete; it was preserved')
        try:
            notarytool('history','--apple-id',saved['apple_id'],'--output-format','json', password=saved['password'])
        except (ValueError, subprocess.TimeoutExpired):
            raise ValueError('Apple did not accept the existing notary profile backup; it was preserved') from None
        print('Existing notary profile backup verified with Apple and in 1Password')
        return
    if not sys.stdin.isatty():
        raise ValueError('Run backup in a terminal to enter the notary profile\'s app-specific password')
    apple_id = input('Apple ID of the ' + PROFILE + ' notary profile: ').strip()
    password = getpass.getpass('Its app-specific password (not shown): ')
    try:
        notarytool('history','--apple-id',apple_id,'--output-format','json', password=password)
    except (ValueError, subprocess.TimeoutExpired):
        raise ValueError('Apple did not accept that Apple ID and app-specific password; nothing was backed up') from None
    saved = create({'title':NOTARY_TITLE,'category':'SECURE_NOTE','tags':['Parc','production-signing'], 'fields':[
        {'id':'apple_id','type':'STRING','label':'Apple ID','value':apple_id},
        {'id':'team_id','type':'STRING','label':'Team ID','value':'94HKA7L2DR'},
        {'id':'password','type':'CONCEALED','label':'App-specific password','value':password}]})
    if saved.get('apple_id') != apple_id or saved.get('password') != password:
        raise ValueError('Vault round-trip verification failed; no successful backup claimed')
    print('Notary profile credentials verified with Apple and backed up to 1Password')


def restore():
    restore_identity()
    restore_sparkle()
    restore_notary()


def restore_identity():
    identities = run(['security','find-identity','-v','-p','codesigning'])
    if re.search(r'"Developer ID Application: [^"\n]+ \(94HKA7L2DR\)"', identities):
        print('Production identity already in the normal Keychain')
        return
    saved = existing(TITLE)
    if saved is None:
        raise ValueError('1Password has no production identity backup to restore')
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
    saved = existing(SPARKLE_TITLE)
    if saved is None:
        raise ValueError('1Password has no Sparkle signing key backup to restore')
    if saved.get('account') != sparkle.ACCOUNT or saved.get('public_key') != sparkle.PUBLIC_ED_KEY:
        raise ValueError('Vault entry is not the Sparkle key Parc trusts')
    tool = generate_keys()
    with tempfile.TemporaryDirectory(prefix='parc-sparkle-') as folder:
        imported = Path(folder) / 'key'
        with os.fdopen(os.open(imported, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
            stream.write(saved['private_key'])
        run([*tool, '-f', str(imported)])
    if run([*tool, '-p']) != sparkle.PUBLIC_ED_KEY:
        run(['security','delete-generic-password','-s',sparkle.SERVICE,'-a',sparkle.ACCOUNT])
        raise ValueError('The restored Sparkle key is not the one Parc trusts; it was removed again')
    print('Sparkle signing key restored and verified in the login Keychain')



def restore_notary():
    if notary_works():
        print('Notary profile ' + PROFILE + ' already works')
        return
    saved = existing(NOTARY_TITLE)
    if saved is None:
        raise ValueError('1Password has no notary profile backup to restore')
    if saved.get('team_id') != '94HKA7L2DR' or not saved.get('apple_id') or not saved.get('password'):
        raise ValueError('Vault entry is not the expected notary profile')
    notarytool('store-credentials',PROFILE,'--apple-id',saved['apple_id'], password=saved['password'])
    if not notary_works():
        raise ValueError('The restored notary profile ' + PROFILE + ' still fails notarytool history')
    print('Notary profile ' + PROFILE + ' restored and verified')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('operation',choices=('backup','restore'))
    args=parser.parse_args()
    try:
        backup() if args.operation == 'backup' else restore()
    except (OSError, EOFError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1,str(error)+'\n')

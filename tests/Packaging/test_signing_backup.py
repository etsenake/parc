import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('parc_signing_backup',Path(__file__).resolve().parents[2]/'scripts/signing-backup.py')
backup=importlib.util.module_from_spec(spec);spec.loader.exec_module(backup)
REAL_RUN = subprocess.run

def setUpModule():
    guard = patch.object(backup.subprocess, 'run', side_effect=AssertionError('unfaked credential command'))
    guard.start(); unittest.addModuleCleanup(guard.stop)

class Backup(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.home=Path(self.tmp.name);config=self.home/'.config/parc';config.mkdir(parents=True)
        (config/'signing-identity').write_text('Developer ID Application: Fixture (94HKA7L2DR)\n')

    def test_unavailable_vault_never_exports_key(self):
        from subprocess import CompletedProcess
        with patch.object(Path,'home',return_value=self.home),patch.object(backup.subprocess,'run',return_value=CompletedProcess([],1)),patch.object(backup,'helper') as helper:
            with self.assertRaisesRegex(ValueError,'op signin'):backup.backup()
            helper.assert_not_called()

    def test_native_export_passphrase_uses_standard_input(self):
        from subprocess import CompletedProcess
        calls=[]
        def run(args,data=None):
            calls.append((args,data))
            if args[-1]=='export':return 'ZW5jcnlwdGVk'
            if args[:3]==['op','item','list']:return '[]'
            template=json.loads(data) if data else None
            if template:
                fields=template['fields'];self.saved={'id':'vault-id','fields':fields};return json.dumps(self.saved)
            return json.dumps(self.saved)
        with patch.object(Path,'home',return_value=self.home),patch.object(backup.subprocess,'run',side_effect=[CompletedProcess([],0),CompletedProcess([],1)]),patch.object(backup,'helper',return_value='native-helper'),patch.object(backup,'run',side_effect=run),patch.object(backup,'backup_sparkle'),patch.object(backup,'backup_notary'),contextlib.redirect_stdout(io.StringIO()) as output:
            backup.backup()
        native=next(call for call in calls if call[0][-1]=='export')
        password=json.loads(native[1])['password']
        self.assertGreaterEqual(len(password),32)
        self.assertNotIn(password,repr([item[0] for item in calls]))
        self.assertNotIn(password,output.getvalue())
        self.assertTrue(all(item['type']=='CONCEALED' for item in self.saved['fields'] if item['id'] in ('password','pkcs12')))


class SparkleKey(unittest.TestCase):
    KEY = base64.b64encode(bytes(range(32))).decode()

    def setUp(self):
        self.keychain, self.public, self.vault, self.calls, self.files, self.modes = None, backup.sparkle.PUBLIC_ED_KEY, {}, [], [], []
        def run(args, *, data=None, umask=-1):
            self.calls.append(list(args))
            if args[0] == 'generate_keys' and args[3] == '-p':
                return self.public
            if args[0] == 'generate_keys':
                path = Path(args[4]); self.files.append(path)
                if args[3] == '-x':
                    self.assertEqual(umask, 0o077); self.modes.append(path.parent.stat().st_mode & 0o777)
                    path.write_text(self.KEY + '\n')
                else:
                    self.modes.append(path.stat().st_mode & 0o777); self.keychain = path.read_text()
                return ''
            if args[:3] == ['op', 'item', 'create']:
                self.vault['created'] = json.loads(data)['fields']; return json.dumps({'id': 'created'})
            if args[:3] == ['op', 'item', 'get']:
                return json.dumps({'fields': self.vault[args[3]]})
            if args[:2] == ['security', 'delete-generic-password']:
                self.keychain = None; return ''
            raise AssertionError(args)
        for target, value in (('run', {'side_effect': run}), ('generate_keys', {'return_value': ['generate_keys', '--account', 'parc']}),
                              ('existing', {'side_effect': lambda title: backup.fields({'fields': self.vault[title]}) if title in self.vault else None})):
            patcher = patch.object(backup, target, **value); patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(backup.sparkle, 'has_key', side_effect=lambda: self.keychain is not None)
        patcher.start(); self.addCleanup(patcher.stop)

    def entry(self, public=None):
        return [{'id': 'account', 'type': 'STRING', 'value': 'parc'},
                {'id': 'public_key', 'type': 'STRING', 'value': public or backup.sparkle.PUBLIC_ED_KEY},
                {'id': 'private_key', 'type': 'CONCEALED', 'value': self.KEY}]

    def test_backup_exports_through_a_removed_private_file_and_verifies_the_vault(self):
        self.keychain = self.KEY
        with contextlib.redirect_stdout(io.StringIO()) as output:
            backup.backup_sparkle()
        self.assertEqual({field['id']: (field['type'], field['value']) for field in self.vault['created']}['private_key'],
                         ('CONCEALED', self.KEY))
        self.assertEqual(self.modes, [0o700])
        self.assertFalse(self.files[0].exists())
        self.assertNotIn(self.KEY, repr(self.calls) + output.getvalue())
        self.assertEqual(self.calls[-1], ['op', 'item', 'get', 'created', '--format=json'])

    def test_backup_refuses_a_missing_or_untrusted_keychain_key(self):
        with self.assertRaisesRegex(ValueError, 'No Sparkle signing key'):
            backup.backup_sparkle()
        self.keychain, self.public = self.KEY, 'another-key'
        with self.assertRaisesRegex(ValueError, 'not the one Parc trusts'):
            backup.backup_sparkle()
        self.assertEqual(self.files, []); self.assertNotIn('created', self.vault)

    def test_existing_backup_is_verified_or_preserved(self):
        self.keychain = self.KEY; self.vault[backup.SPARKLE_TITLE] = self.entry()
        with contextlib.redirect_stdout(io.StringIO()):
            backup.backup_sparkle()
        self.vault[backup.SPARKLE_TITLE] = self.entry('another-key')
        with self.assertRaisesRegex(ValueError, 'preserved'):
            backup.backup_sparkle()
        self.assertEqual(self.files, []); self.assertNotIn('created', self.vault)

    def test_restore_imports_through_a_removed_0600_file_and_verifies(self):
        self.vault[backup.SPARKLE_TITLE] = self.entry()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            backup.restore_sparkle()
        self.assertEqual(self.keychain, self.KEY)
        self.assertEqual(self.modes, [0o600])
        self.assertFalse(self.files[0].exists())
        self.assertEqual([call[3] for call in self.calls if call[0] == 'generate_keys'], ['-f', '-p'])
        self.assertNotIn(self.KEY, repr(self.calls) + output.getvalue())

    def test_restore_keeps_a_present_key_and_refuses_a_foreign_or_untrusted_one(self):
        self.keychain = self.KEY
        with contextlib.redirect_stdout(io.StringIO()):
            backup.restore_sparkle()
        self.assertEqual(self.calls, [])
        self.keychain = None; self.vault[backup.SPARKLE_TITLE] = self.entry('another-key')
        with self.assertRaisesRegex(ValueError, 'not the Sparkle key Parc trusts'):
            backup.restore_sparkle()
        self.assertEqual(self.files, [])
        self.vault[backup.SPARKLE_TITLE] = self.entry(); self.public = 'another-key'
        with self.assertRaisesRegex(ValueError, 'restored Sparkle key is not'):
            backup.restore_sparkle()
        self.assertIsNone(self.keychain)
        self.assertEqual(self.calls[-1], ['security', 'delete-generic-password', '-s', 'https://sparkle-project.org', '-a', 'parc'])
        self.vault.clear()
        with self.assertRaisesRegex(ValueError, 'no Sparkle signing key backup'):
            backup.restore_sparkle()

    def test_present_identity_is_not_restored_again(self):
        with patch.object(backup, 'run', return_value='1) ABC "Developer ID Application: Fixture (94HKA7L2DR)"') as run, \
                contextlib.redirect_stdout(io.StringIO()):
            backup.restore_identity()
        run.assert_called_once_with(['security', 'find-identity', '-v', '-p', 'codesigning'])


class Identity(unittest.TestCase):
    IDENTITY = 'Developer ID Application: Fixture (94HKA7L2DR)'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name); (self.home / '.config/parc').mkdir(parents=True)
        (self.home / '.config/parc/signing-identity').write_text(self.IDENTITY + '\n')

    def keychain(self, state):
        def run(args, *, data=None, umask=-1):
            self.calls.append(list(args))
            if args[:2] == ['security', 'find-identity']:
                if '-v' in args:
                    return '1) ABC "' + self.IDENTITY + '"' if state['valid'] else '0 valid identities found'
                return '1) ABC "' + self.IDENTITY + '" (CSSMERR_TP_NOT_TRUSTED)' if state['listed'] else ''
            if args == ['native-helper', 'import']:
                state['listed'] = True; return 'Imported selected production identity'
            raise AssertionError(args)
        return run

    def chain(self, state, installable):
        def install(identities):
            self.installs.append(list(identities))
            state['valid'] = installable
            return ['DeveloperIDG2CA.cer'] if installable else []
        return install

    def test_listed_identity_validates_once_its_intermediate_is_installed_without_the_vault(self):
        self.calls, self.installs, state = [], [], {'valid': False, 'listed': True}
        with patch.object(Path, 'home', return_value=self.home), patch.object(backup, 'run', side_effect=self.keychain(state)), \
                patch.object(backup.developer_id, 'install_intermediates', side_effect=self.chain(state, True)), \
                patch.object(backup, 'existing', side_effect=AssertionError('vault read')), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            backup.restore_identity()
        self.assertEqual(self.installs, [[self.IDENTITY]])
        self.assertIn("intermediate certificate was installed", output.getvalue())

    def test_imported_identity_gets_its_intermediate_or_fails_clearly(self):
        saved = {'identity': self.IDENTITY, 'pkcs12': 'ZW5jcnlwdGVk', 'password': 'p' * 48}
        (self.home / '.config/parc/signing-identity').unlink()
        for installable in (True, False):
            self.calls, self.installs, state = [], [], {'valid': False, 'listed': False}
            with self.subTest(installable=installable), patch.object(Path, 'home', return_value=self.home), \
                    patch.object(backup, 'run', side_effect=self.keychain(state)), \
                    patch.object(backup, 'helper', return_value='native-helper'), \
                    patch.object(backup, 'existing', return_value=saved), \
                    patch.object(backup.developer_id, 'install_intermediates', side_effect=self.chain(state, installable)), \
                    contextlib.redirect_stdout(io.StringIO()):
                if installable:
                    backup.restore_identity()
                    self.assertEqual((self.home / '.config/parc/signing-identity').read_text(), self.IDENTITY + '\n')
                else:
                    with self.assertRaisesRegex(ValueError, 'Imported identity does not validate for code signing'):
                        backup.restore_identity()
                self.assertEqual(self.installs, [[self.IDENTITY]])
                self.assertIn(['native-helper', 'import'], self.calls)


class DeveloperIDChain(unittest.TestCase):
    IDENTITY = 'Developer ID Application: Fixture (94HKA7L2DR)'
    G2 = '/C=US/O=Apple Inc./OU=G2/CN=Developer ID Certification Authority'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name)
        (self.folder / 'openssl.cnf').write_text(
            '[req]\ndistinguished_name = dn\n[dn]\n[ca]\nbasicConstraints = critical,CA:TRUE\n'
            'keyUsage = critical,keyCertSign,cRLSign\n[leaf]\nbasicConstraints = critical,CA:FALSE\n'
            'keyUsage = critical,digitalSignature\nextendedKeyUsage = codeSigning\n')
        root = '/CN=Apple Root CA/OU=Apple Certification Authority/O=Apple Inc./C=US'
        self.authority('root', root); self.authority('impostor', root)
        self.authority('g2', self.G2, 'root'); self.authority('forged', self.G2, 'impostor')
        self.authority('leaf', '/CN=' + self.IDENTITY + '/OU=94HKA7L2DR/O=Fixture/C=US', 'g2', 'leaf')
        self.authority('stranger', '/CN=' + self.IDENTITY + '/OU=94HKA7L2DR/O=Fixture/C=US')
        self.present, self.served, self.issuer, self.roots = [], 'g2', 'leaf', ['root']
        self.downloads, self.imports = [], []
        patcher = patch.object(backup.developer_id.subprocess, 'run', side_effect=self.fake)
        patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(Path, 'home', return_value=self.folder)
        patcher.start(); self.addCleanup(patcher.stop)

    def openssl(self, *args):
        REAL_RUN(['/usr/bin/openssl', *args], cwd=self.folder, capture_output=True, check=True)

    def authority(self, name, subject, issuer=None, extensions='ca'):
        common = ['-config', 'openssl.cnf', '-newkey', 'rsa:2048', '-nodes', '-keyout', name + '.key', '-subj', subject]
        if issuer is None:
            self.openssl('req', '-x509', *common, '-extensions', extensions, '-days', '30', '-out', name + '.pem')
        else:
            self.openssl('req', '-new', *common, '-out', name + '.csr')
            self.openssl('x509', '-req', '-in', name + '.csr', '-CA', issuer + '.pem', '-CAkey', issuer + '.key',
                         '-set_serial', '7', '-extfile', 'openssl.cnf', '-extensions', extensions, '-days', '30',
                         '-out', name + '.pem')
        self.openssl('x509', '-in', name + '.pem', '-outform', 'DER', '-out', name + '.cer')

    def pem(self, *names):
        return ''.join((self.folder / (name + '.pem')).read_text() for name in names)

    def fake(self, args, **kwargs):
        if args[0] == '/usr/bin/openssl':
            return REAL_RUN(args, **kwargs)
        if args[:5] == ['security', 'find-certificate', '-a', '-c', backup.developer_id.INTERMEDIATE]:
            output = self.pem(*self.present)
        elif args[:5] == ['security', 'find-certificate', '-a', '-c', self.IDENTITY]:
            output = self.pem(self.issuer)
        elif args[:5] == ['security', 'find-certificate', '-a', '-c', 'Apple Root CA']:
            self.assertEqual(args[6:], [backup.developer_id.SYSTEM_ROOTS])
            output = self.pem(*self.roots)
        elif args[0] == '/usr/bin/curl':
            self.assertEqual(args[args.index('--proto') + 1], '=https')
            self.downloads.append(args[-1])
            Path(args[args.index('--output') + 1]).write_bytes((self.folder / (self.served + '.cer')).read_bytes())
            output = ''
        elif args[:2] == ['security', 'import']:
            self.assertEqual(args[3:], ['-k', str(self.folder / 'Library/Keychains/login.keychain-db'), '-t', 'cert'])
            self.imports.append(Path(args[2]).read_bytes()); self.present.append(self.served)
            output = ''
        else:
            raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0 if output or args[1] != 'find-certificate' else 44, output, '')

    def test_missing_issuer_is_downloaded_checked_against_apple_root_and_imported_once(self):
        logged = []
        self.assertEqual(backup.developer_id.install_intermediates([self.IDENTITY], log=logged.append), ['DeveloperIDG2CA.cer'])
        self.assertEqual(self.downloads, ['https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer'])
        self.assertEqual(self.imports, [(self.folder / 'g2.cer').read_bytes()])
        self.assertIn('issued by Apple Root CA', logged[0])
        self.assertEqual(backup.developer_id.install_intermediates([self.IDENTITY], log=logged.append), [])
        self.assertEqual((len(self.downloads), len(self.imports)), (1, 1))

    def test_a_certificate_apple_root_did_not_issue_is_never_imported(self):
        for served, roots, expected in (('forged', ['root'], 'not issued by Apple Root CA'),
                                        ('root', ['root'], 'different certificate'),
                                        ('g2', ['impostor'], 'not issued by Apple Root CA'),
                                        ('g2', [], 'no Apple Root CA')):
            with self.subTest(served=served, roots=roots):
                self.served, self.roots = served, roots
                with self.assertRaisesRegex(ValueError, expected):
                    backup.developer_id.install_intermediates([self.IDENTITY], log=lambda message: None)
        self.assertEqual(self.imports, [])

    def test_an_identity_from_another_authority_is_left_alone(self):
        self.issuer = 'stranger'
        with self.assertRaisesRegex(ValueError, 'not an Apple Developer ID intermediate'):
            backup.developer_id.install_intermediates([self.IDENTITY], log=lambda message: None)
        self.assertEqual((self.downloads, self.imports), ([], []))

    def test_identity_names_come_from_find_identity_output(self):
        output = ('  1) ABC "Developer ID Application: Fixture (94HKA7L2DR)" (CSSMERR_TP_NOT_TRUSTED)\n'
                  '  2) DEF "Developer ID Application: Other (0000000000)"\n'
                  '  3) ABC "Developer ID Application: Fixture (94HKA7L2DR)"\n')
        self.assertEqual(backup.developer_id.names(output), [self.IDENTITY])


class NotaryProfile(unittest.TestCase):
    PASSWORD = 'fake-fake-fake-fake'

    def setUp(self):
        self.profile, self.accepted, self.vault, self.calls = None, self.PASSWORD, {}, []
        def run(args, *, data=None, umask=-1, start_new_session=False):
            self.calls.append(list(args))
            if args[:2] == ['xcrun', 'notarytool']:
                self.assertNotIn(self.PASSWORD, args)
                if '--keychain-profile' in args:
                    if self.profile is None: raise ValueError('Credential operation failed')
                    return '{"history": []}'
                self.assertTrue(start_new_session); self.assertEqual(args[-2:], ['--team-id', '94HKA7L2DR'])
                if data != self.accepted + '\n': raise ValueError('Credential operation failed')
                if args[2] == 'store-credentials':
                    self.assertEqual(args[3:6], ['parc-notary', '--apple-id', 'release@example.com']); self.profile = data
                return ''
            if args[:3] == ['op', 'item', 'create']:
                self.vault['created'] = json.loads(data)['fields']; return json.dumps({'id': 'created'})
            if args[:3] == ['op', 'item', 'get']:
                return json.dumps({'fields': self.vault[args[3]]})
            raise AssertionError(args)
        for target, value in (('run', {'side_effect': run}),
                              ('existing', {'side_effect': lambda title: backup.fields({'fields': self.vault[title]}) if title in self.vault else None})):
            patcher = patch.object(backup, target, **value); patcher.start(); self.addCleanup(patcher.stop)

    def entry(self, team='94HKA7L2DR'):
        return [{'id': 'apple_id', 'type': 'STRING', 'value': 'release@example.com'},
                {'id': 'team_id', 'type': 'STRING', 'value': team},
                {'id': 'password', 'type': 'CONCEALED', 'value': self.PASSWORD}]

    def prompted(self, terminal=True):
        prompts = patch.object(backup, 'input', create=True, return_value='release@example.com ')
        hidden = patch.object(backup.getpass, 'getpass', return_value=self.PASSWORD)
        tty = patch.object(backup.sys.stdin, 'isatty', return_value=terminal)
        return prompts, hidden, tty

    def test_backup_verifies_the_typed_password_with_apple_then_the_vault(self):
        prompts, hidden, tty = self.prompted()
        with prompts, hidden, tty, contextlib.redirect_stdout(io.StringIO()) as output:
            backup.backup_notary()
        self.assertEqual({field['id']: (field['type'], field['value']) for field in self.vault['created']},
                         {'apple_id': ('STRING', 'release@example.com'), 'team_id': ('STRING', '94HKA7L2DR'),
                          'password': ('CONCEALED', self.PASSWORD)})
        self.assertEqual(self.calls[0][2:6], ['history', '--apple-id', 'release@example.com', '--output-format'])
        self.assertEqual(self.calls[-1], ['op', 'item', 'get', 'created', '--format=json'])
        self.assertNotIn(self.PASSWORD, repr(self.calls) + output.getvalue())

    def test_backup_saves_nothing_apple_rejects_or_without_a_terminal(self):
        self.accepted = 'another-password'
        prompts, hidden, tty = self.prompted()
        with prompts, hidden, tty, self.assertRaisesRegex(ValueError, 'nothing was backed up'):
            backup.backup_notary()
        prompts, hidden, tty = self.prompted(terminal=False)
        with prompts as asked, hidden, tty, self.assertRaisesRegex(ValueError, 'in a terminal'):
            backup.backup_notary()
        asked.assert_not_called(); self.assertNotIn('created', self.vault)

    def test_existing_backup_is_verified_or_preserved(self):
        self.vault[backup.NOTARY_TITLE] = self.entry()
        with contextlib.redirect_stdout(io.StringIO()):
            backup.backup_notary()
        self.assertEqual([call[2] for call in self.calls], ['history'])
        self.accepted = 'rotated-password'
        with self.assertRaisesRegex(ValueError, 'Apple did not accept the existing'):
            backup.backup_notary()
        self.vault[backup.NOTARY_TITLE] = self.entry('0000000000')
        with self.assertRaisesRegex(ValueError, 'preserved'):
            backup.backup_notary()
        self.assertEqual(len(self.calls), 2); self.assertEqual(set(self.vault), {backup.NOTARY_TITLE})

    def test_restore_recreates_the_profile_through_the_prompt_and_rechecks_it(self):
        self.vault[backup.NOTARY_TITLE] = self.entry()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            backup.restore_notary()
        self.assertEqual(self.profile, self.PASSWORD + '\n')
        self.assertEqual([call[2] for call in self.calls], ['history', 'store-credentials', 'history'])
        self.assertNotIn(self.PASSWORD, repr(self.calls) + output.getvalue())

    def test_restore_keeps_a_working_profile_and_refuses_a_missing_or_rejected_backup(self):
        self.profile = 'present'
        with contextlib.redirect_stdout(io.StringIO()):
            backup.restore_notary()
        self.assertEqual(len(self.calls), 1)
        self.profile = None
        with self.assertRaisesRegex(ValueError, 'no notary profile backup'):
            backup.restore_notary()
        self.vault[backup.NOTARY_TITLE] = self.entry('0000000000')
        with self.assertRaisesRegex(ValueError, 'not the expected notary profile'):
            backup.restore_notary()
        self.vault[backup.NOTARY_TITLE] = self.entry(); self.accepted = 'another-password'
        with self.assertRaisesRegex(ValueError, 'Credential operation failed'):
            backup.restore_notary()
        self.assertIsNone(self.profile)


class Vault(unittest.TestCase):
    def test_lookup_uses_one_titled_item_and_refuses_duplicates_or_failures(self):
        items = [{'id': 'a', 'title': 'Parc Sparkle EdDSA key'}, {'id': 'b', 'title': 'Other'}]
        def run(args, data=None):
            if args[:3] == ['op', 'item', 'list']:
                self.assertEqual(args[4:], ['--vault', 'Release'])
                return json.dumps(items)
            self.assertEqual(args[:4], ['op', 'item', 'get', 'a'])
            return json.dumps({'fields': [{'id': 'account', 'value': 'parc'}]})
        with patch.dict(backup.os.environ, {'PARC_SIGNING_VAULT': 'Release'}), patch.object(backup, 'run', side_effect=run):
            self.assertEqual(backup.existing('Parc Sparkle EdDSA key'), {'account': 'parc'})
            self.assertIsNone(backup.existing('Missing'))
            items.append({'id': 'c', 'title': 'Parc Sparkle EdDSA key'})
            with self.assertRaisesRegex(ValueError, 'More than one'):
                backup.existing('Parc Sparkle EdDSA key')
        with patch.object(backup, 'run', side_effect=ValueError('Credential operation failed: op item list')):
            with self.assertRaises(ValueError):
                backup.existing('Parc Sparkle EdDSA key')

    def test_keychain_lookup_separates_missing_from_unsearchable(self):
        from subprocess import CompletedProcess
        for code, expected in ((0, True), (44, False), (36, RuntimeError)):
            with self.subTest(code=code), patch.object(backup.sparkle.subprocess, 'run', return_value=CompletedProcess([], code)) as run:
                if expected is RuntimeError:
                    with self.assertRaisesRegex(RuntimeError, 'unlock it'):
                        backup.sparkle.has_key()
                else:
                    self.assertIs(backup.sparkle.has_key(), expected)
                self.assertNotIn('-w', run.call_args[0][0]); self.assertNotIn('-g', run.call_args[0][0])

    def test_backup_covers_the_identity_the_sparkle_key_then_the_notary_profile(self):
        from subprocess import CompletedProcess
        order = []
        with patch.object(backup.subprocess, 'run', return_value=CompletedProcess([], 0)), \
                patch.object(backup, 'backup_identity', side_effect=lambda: order.append('identity')), \
                patch.object(backup, 'backup_sparkle', side_effect=lambda: order.append('sparkle')), \
                patch.object(backup, 'backup_notary', side_effect=lambda: order.append('notary')):
            backup.backup()
        self.assertEqual(order, ['identity', 'sparkle', 'notary'])

    def test_restore_covers_the_identity_the_sparkle_key_then_the_notary_profile(self):
        order = []
        with patch.object(backup, 'restore_identity', side_effect=lambda: order.append('identity')), \
                patch.object(backup, 'restore_sparkle', side_effect=lambda: order.append('sparkle')), \
                patch.object(backup, 'restore_notary', side_effect=lambda: order.append('notary')):
            backup.restore()
        self.assertEqual(order, ['identity', 'sparkle', 'notary'])

if __name__=='__main__':unittest.main()

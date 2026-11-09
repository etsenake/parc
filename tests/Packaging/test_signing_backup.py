"""Credential backup refuses unavailable vaults and keeps secrets off argv/logs."""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('parc_signing_backup',Path(__file__).resolve().parents[2]/'scripts/signing-backup.py')
backup=importlib.util.module_from_spec(spec);spec.loader.exec_module(backup)

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
            template=json.loads(data) if data else None
            if template:
                fields=template['fields'];self.saved={'id':'vault-id','fields':fields};return json.dumps(self.saved)
            return json.dumps(self.saved)
        with patch.object(Path,'home',return_value=self.home),patch.object(backup.subprocess,'run',side_effect=[CompletedProcess([],0),CompletedProcess([],1)]),patch.object(backup,'helper',return_value='native-helper'),patch.object(backup,'run',side_effect=run),patch.object(backup,'backup_sparkle'),contextlib.redirect_stdout(io.StringIO()) as output:
            backup.backup()
        native=next(call for call in calls if call[0][-1]=='export')
        password=json.loads(native[1])['password']
        self.assertGreaterEqual(len(password),32)
        self.assertNotIn(password,repr([item[0] for item in calls]))
        self.assertNotIn(password,output.getvalue())
        self.assertTrue(all(item['type']=='CONCEALED' for item in self.saved['fields'] if item['id'] in ('password','pkcs12')))


class SparkleKey(unittest.TestCase):
    """Fake Keychain, generate_keys and vault; the real Keychain item and 1Password are never touched."""
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

    def test_present_identity_is_not_restored_again(self):
        with patch.object(backup, 'run', return_value='1) ABC "Developer ID Application: Fixture (94HKA7L2DR)"') as run, \
                contextlib.redirect_stdout(io.StringIO()):
            backup.restore_identity()
        run.assert_called_once_with(['security', 'find-identity', '-v', '-p', 'codesigning'])

if __name__=='__main__':unittest.main()

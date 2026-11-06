"""Credential backup refuses unavailable vaults and keeps secrets off argv/logs."""
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
        with patch.object(Path,'home',return_value=self.home),patch.object(backup.subprocess,'run',side_effect=[CompletedProcess([],0),CompletedProcess([],1)]),patch.object(backup,'helper',return_value='native-helper'),patch.object(backup,'run',side_effect=run),contextlib.redirect_stdout(io.StringIO()) as output:
            backup.backup()
        native=next(call for call in calls if call[0][-1]=='export')
        password=json.loads(native[1])['password']
        self.assertGreaterEqual(len(password),32)
        self.assertNotIn(password,repr([item[0] for item in calls]))
        self.assertNotIn(password,output.getvalue())
        self.assertTrue(all(item['type']=='CONCEALED' for item in self.saved['fields'] if item['id'] in ('password','pkcs12')))

if __name__=='__main__':unittest.main()

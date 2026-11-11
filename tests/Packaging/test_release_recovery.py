import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
import release_recover

class Recovery(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);(self.root/'.parc-operation.lock').touch()
        self.output=self.root/'chromium/src/out/Shipping';self.output.mkdir(parents=True)
        (self.output/'args.gn').write_bytes(b'unchanged args')
        (self.output/'compiled.o').write_bytes(b'valuable compiled output')
        self.marker=self.root/'shipping.json'
        self.state={'symbol_level':0,'source_fingerprint':'same','overlay':{'identity':'reviewed'}}
        self.receipt={'phase':'build-in-progress','source_fingerprint':'same','overlay':self.state['overlay'],
                      'args_sha256':hashlib.sha256(b'unchanged args').hexdigest()}
        self.marker.write_text(json.dumps(self.receipt))
        self.before=self.marker.read_bytes()
        self.engine=SimpleNamespace(SHIPPING_CONFIGURATION='Shipping',SHIPPING_MARKER='shipping.json',
            load_lock=lambda:({'schema_version':2},'lock'),read_marker=lambda *args:self.state,
            read_shipping_marker=lambda *args:json.loads(self.marker.read_text()),
            shipping_environment=lambda *args:{},verify_workspace=Mock(),recorded_overlay=Mock(),
            shipping_arguments=Mock(return_value=b'unchanged args'),digest=lambda b:hashlib.sha256(b).hexdigest(),
            write_marker=lambda workspace,value,name:self.marker.write_text(json.dumps(value)))
        self.addCleanup(patch.stopall)
        patch.object(release_recover.importlib.util,'spec_from_file_location').start()
        patch.object(release_recover.importlib.util,'module_from_spec',return_value=self.engine).start()

    def recover(self):
        release_recover.recover(self.root,self.root,12345,self.root/'evidence.json')

    def test_dead_group_with_unchanged_inputs_becomes_resumable_failure(self):
        with patch.object(release_recover.os,'killpg',side_effect=ProcessLookupError):self.recover()
        self.assertEqual(json.loads(self.marker.read_text())['phase'],'build-failed')
        self.assertEqual((self.root/'evidence.json').read_bytes(),self.before)
        self.assertEqual((self.output/'compiled.o').read_bytes(),b'valuable compiled output')
        self.engine.verify_workspace.assert_called_once()
        self.engine.shipping_arguments.assert_called_once_with(self.root, {}, {'schema_version': 2})

    def test_live_group_is_never_relabelled_or_killed(self):
        with patch.object(release_recover.os,'killpg') as signal:
            with self.assertRaisesRegex(ValueError,'still alive'):self.recover()
            signal.assert_called_once_with(12345,0)
        self.assertEqual(self.marker.read_bytes(),self.before)

    def test_changed_arguments_refuse_without_touching_receipt_or_objects(self):
        (self.output/'args.gn').write_bytes(b'changed recipe')
        with patch.object(release_recover.os,'killpg',side_effect=ProcessLookupError):
            with self.assertRaisesRegex(ValueError,'inputs changed'):self.recover()
        self.assertEqual(self.marker.read_bytes(),self.before)
        self.assertFalse((self.root/'evidence.json').exists())

    def test_replaced_inputs_resume_only_when_superseded(self):
        self.state['source_fingerprint']='new source'
        with patch.object(release_recover.os,'killpg',side_effect=ProcessLookupError):
            with self.assertRaisesRegex(ValueError,'inputs changed'):self.recover()
            self.assertEqual(self.marker.read_bytes(),self.before)
            release_recover.recover(self.root,self.root,12345,self.root/'evidence.json',inputs_replaced=True)
        receipt=json.loads(self.marker.read_text())
        self.assertEqual(receipt['phase'],'build-failed'); self.assertIn('superseding',receipt['error'])
        self.assertEqual((self.output/'compiled.o').read_bytes(),b'valuable compiled output')

    def test_replaced_inputs_still_require_unchanged_arguments(self):
        (self.output/'args.gn').write_bytes(b'changed recipe')
        with patch.object(release_recover.os,'killpg',side_effect=ProcessLookupError):
            with self.assertRaisesRegex(ValueError,'GN arguments'):
                release_recover.recover(self.root,self.root,12345,self.root/'evidence.json',inputs_replaced=True)
        self.assertEqual(self.marker.read_bytes(),self.before)

    def test_built_receipt_needs_no_cancellation_recovery(self):
        self.receipt['phase']='built';self.marker.write_text(json.dumps(self.receipt))
        with patch.object(release_recover.os,'killpg') as signal:self.recover();signal.assert_not_called()
        self.assertEqual(json.loads(self.marker.read_text())['phase'],'built')

if __name__=='__main__':unittest.main()

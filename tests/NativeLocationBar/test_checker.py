"""Check production owner selection without invoking a compiler."""
import json
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


class LocationBarOwnerTest(unittest.TestCase):
    def test_actual_owner_for_each_lock(self):
        source = Path(__file__).with_name('check-chromium.py').read_text()
        for schema, expected in ((2, 'obj/parc/browser.ninja'),):
            with self.subTest(schema=schema), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                script = root / 'repo/tests/NativeLocationBar/check-chromium.py'
                script.parent.mkdir(parents=True)
                script.write_text(source)
                lock = root / 'repo/Engine/source-lock.json'
                lock.parent.mkdir(parents=True)
                lock.write_text(json.dumps({'schema_version': schema,
                    'build': {'configuration': 'SelectedOutput'}}))
                tree = root / 'chromium'
                tree.mkdir()
                main = runpy.run_path(str(script))['main']
                owners = []
                def flags_from(path):
                    owners.append(path.relative_to(tree / 'out/SelectedOutput').as_posix())
                    return ['-Werror']
                with patch.dict(main.__globals__, {'flags_from': flags_from}), \
                        patch.object(sys, 'argv', [str(script), str(tree)]), \
                        patch('subprocess.run') as compiler:
                    compiler.return_value.returncode = 0
                    compiler.return_value.stdout = ''
                    self.assertEqual(main(), 0)
                self.assertEqual(owners, [expected, 'obj/chrome/test/browser_tests.ninja'])
                self.assertEqual(compiler.call_count, 2)
                for call in compiler.call_args_list:
                    self.assertIn('-fsyntax-only', call.args[0])
                    self.assertIn('-Werror', call.args[0])


if __name__ == '__main__':
    unittest.main()

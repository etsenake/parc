import hashlib
import json
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


CHECKERS = ('NativeCertificateViewer', 'NativeClientCertificates',
            'NativeExternalProtocol', 'NativeHTTPAuth', 'NativeWebAuthn')
REPO = Path(__file__).resolve().parents[2]


class CheckerSelectionTests(unittest.TestCase):
    def exercise(self, name, corrupt=False, refusal=None):
        original = REPO / 'tests' / name / 'check-chromium.py'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            repo, tree = root / 'repo', root / 'src'
            script = repo / 'tests' / name / 'check-chromium.py'
            script.parent.mkdir(parents=True)
            script.write_text(original.read_text())
            namespace = runpy.run_path(str(script))
            build = tree / 'out' / 'ChosenOutput'
            build.mkdir(parents=True)

            def write(path, data='fixture\n'):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(data)
                return hashlib.sha256(path.read_bytes()).hexdigest()

            lock = {'schema_version': 2,
                    'chromium': {'commit': 'chromium-pin'},
                    'build': {'configuration': 'ChosenOutput'}}
            lock_path = repo / 'Engine/source-lock.json'
            write(lock_path, json.dumps(lock))
            write(lock_path, json.dumps(lock))
            manifest = {'source_root': 'repository', 'upstream': {
                key: lock[key]['commit'] for key in ('chromium',) if key in lock},
                'files': [], 'patches': []}
            expected = []
            for source, owner in namespace['NATIVE']:
                source = source.replace('native_chrome_platform_delegate.mm', 'native_page_binding.mm')
                owner = owner
                owner = owner
                owner = owner
                target = 'mapped/' + source
                digest = write(repo / source)
                write(tree / target)
                manifest['files'].append({'source': source, 'target': target, 'sha256': digest})
                flags = build / owner
                previous = flags.read_text() if flags.exists() else '\n'
                write(flags, previous + f'build object: objcxx ../../{target}\n')
                expected.append(str(tree / target))
            for target, owner in namespace['UPSTREAM']:
                digest = write(tree / target)
                source = 'patches/' + target
                patch_digest = write(repo / source)
                manifest['patches'].append({'source': source, 'sha256': patch_digest,
                    'files': [{'target': target, 'after_sha256': digest}]})
                flags = build / owner
                previous = flags.read_text() if flags.exists() else 'cc_module_name = fixture\n\n'
                write(flags, previous + f'build object: cxx ../../{target}\n')
                expected.append(str(tree / target))
            write(repo / ('Engine/ParcHost/overlay.json'), json.dumps(manifest))
            write(build / 'args.gn')
            write(build / 'toolchain.ninja', '\n'.join(
                f'rule {language}\n  command = {rule}' for language, rule in namespace['RULES'].items()))
            write(tree / 'third_party/llvm-build/Release+Asserts/bin/clang++')
            write(repo / 'tests/NativeLocationBar/check-chromium.py',
                  'def flags_from(*args, **kwargs): return ["-Werror", "-fobjc-arc"]\n')
            if refusal == 'schema':
                lock['schema_version'] = 3
                write(lock_path, json.dumps(lock))
            elif refusal == 'identity':
                lock['chromium']['commit'] = 'wrong-pin'
                write(lock_path, json.dumps(lock))
            if corrupt:
                (tree / manifest['files'][0]['target']).write_text('corrupted')
            with patch.object(sys, 'argv', [str(script), str(tree)]), patch('subprocess.run') as compiler:
                compiler.return_value.returncode = 0
                compiler.return_value.stdout = ''
                if refusal:
                    with self.assertRaises(SystemExit) as error:
                        namespace['main']()
                    self.assertEqual(error.exception.code, 2)
                    compiler.assert_not_called()
                elif corrupt:
                    with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                        namespace['main']()
                    compiler.assert_not_called()
                else:
                    self.assertEqual(namespace['main'](), 0)
                    self.assertEqual([call.args[0][-1] for call in compiler.call_args_list], expected)

    def test_direct_targets_and_hash_refusal(self):
        for name in CHECKERS:
            for corrupt in (False, True):
                with self.subTest(checker=name, direct=True, corrupt=corrupt):
                    self.exercise(name, corrupt)

    def test_bad_lock_refused_before_compiler(self):
        for name in CHECKERS:
            for refusal in ('schema', 'identity'):
                with self.subTest(checker=name, direct=True, refusal=refusal):
                    self.exercise(name, refusal=refusal)


if __name__ == '__main__':
    unittest.main()

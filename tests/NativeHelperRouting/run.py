#!/usr/bin/env python3
"""Link a routing regression to actual completed CEF/Chromium code, then run it.

Never invokes GN/Ninja or changes the source tree. Requires an explicit external
result directory. This tests path selection, not sandbox/JIT/browser execution.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import plistlib
import tempfile
import subprocess


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_tree', type=Path)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--lock-file', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    lock = json.loads((args.lock_file or repo / 'Engine/source-lock.json').read_text())
    if lock.get('schema_version') not in (1, 2):
        parser.error('unsupported source lock schema')
    direct = lock['schema_version'] == 2
    tree = args.source_tree.resolve(strict=True)
    build = tree / 'out' / lock['build']['configuration']
    results = args.results.resolve()
    if results.is_relative_to(tree):
        parser.error('results must be outside the source checkout')
    results.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name('helper_routing_test.mm')
    native = Path(__file__).resolve().parents[2] / 'Engine/ParcNative'
    policy = native / 'native_startup_policy.h'
    flags_file = build / ('obj/parc/browser.ninja' if direct else 'obj/cef/libcef_static.ninja')
    variables = {}
    for line in flags_file.read_text().splitlines():
        if ' =' in line and not line.startswith(' '):
            key, value = line.split(' =', 1)
            variables[key] = value.strip()
    flags = ['-I' + str(native)]
    for key in ('defines', 'include_dirs', 'framework_dirs', 'cflags', 'cflags_objcc'):
        flags += shlex.split(variables[key].replace('$:', ':'))
    if any('$' in f for f in flags) or '-Werror' not in flags or '-fobjc-arc' not in flags:
        raise RuntimeError('Generated target flags are incomplete/unresolved')
    flags = [f'-fcrash-diagnostics-dir={results}' if f.startswith('-fcrash-diagnostics-dir=') else f for f in flags]
    compiler = tree / 'third_party/llvm-build/Release+Asserts/bin/clang++'
    objects = [build / 'obj/cef/libcef_static' / name for name in ('util_mac.o', 'cef_switches.o', 'command_line_impl.o',
                                                                   'value_base.o', 'string_types_impl.o')]
    flags.append('-DPARC_DIRECT_ENGINE=' + ('1' if direct else '0'))
    if direct:
        objects = [build / 'obj/parc/browser/parc_bundle_mac.o',
                   build / 'obj/chrome/common/constants/chrome_paths_mac.o',
                   build / 'obj/chrome/common/constants/chrome_constants.o']
    libraries = [build / name for name in ('libcontent.dylib', 'libbase.dylib', 'libbase_i18n.dylib', 'libc++_chrome.dylib')]
    inputs = [source, policy, flags_file, compiler, *objects, *libraries]
    receipt = {'scope': 'actual selected-engine bundle objects, native startup policy and Chromium routing; no browser initialization',
               'inputs': [{'path': str(p), 'sha256': sha(p)} for p in inputs], 'commands': []}
    obj = results / 'helper_routing_test.o'
    binary = results / 'helper_routing_test'
    if direct:
        # dladdr must see the production layout. Each executable name gets an
        # independent process so NSBundle's cached identity cannot cross cases.
        binaries = []
        fixture_root = Path(tempfile.mkdtemp(prefix='bundle-fixture-', dir=results))
        for name in ('Parc', 'parc_native_runtime_tests'):
            bundle = fixture_root / (name + '.app')
            macos = bundle / 'Contents/MacOS'
            macos.mkdir(parents=True, exist_ok=True)
            (macos / name).touch()
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'org.parc.helper-routing-fixture',
                'CFBundleExecutable': name, 'CFBundlePackageType': 'APPL'}))
            framework = bundle / 'Contents/Frameworks/Chromium Embedded Framework.framework'
            version = framework / 'Versions/A'
            (version / 'Resources').mkdir(parents=True, exist_ok=True)
            (version / 'Resources/Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'org.parc.framework-fixture',
                'CFBundleExecutable': 'Chromium Embedded Framework', 'CFBundlePackageType': 'FMWK'}))
            (framework / 'Versions/Current').symlink_to('A')
            (framework / 'Resources').symlink_to('Versions/Current/Resources')
            (framework / 'Chromium Embedded Framework').symlink_to('Versions/Current/Chromium Embedded Framework')
            binaries.append((version / 'Chromium Embedded Framework', name))
        commands = [[str(compiler), *flags, '-c', str(source), '-o', str(obj)]]
        for executable, name in binaries:
            commands += [[str(compiler), '-nostdlib++', str(obj), *map(str, objects), *map(str, libraries),
                          '-framework', 'Foundation', '-Wl,-rpath,' + str(build), '-o', str(executable)],
                         [str(executable), name]]
    else:
        commands = [[str(compiler), *flags, '-c', str(source), '-o', str(obj)],
                [str(compiler), '-nostdlib++', str(obj), *map(str, objects), *map(str, libraries),
                 '-framework', 'Foundation', '-Wl,-rpath,' + str(build), '-o', str(binary)],
                [str(binary)]]
    code = 0
    for i, command in enumerate(commands):
        process = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = results / f'{i}.log'
        log.write_text(process.stdout)
        receipt['commands'].append({'command': command, 'cwd': str(build), 'exit_code': process.returncode,
                                    'log': str(log), 'log_sha256': sha(log)})
        print(process.stdout, end='')
        if process.returncode:
            code = process.returncode
            break
    for item in receipt['inputs']:
        if sha(Path(item['path'])) != item['sha256']:
            raise RuntimeError('Input changed during focused check: ' + item['path'])
    receipt['exit_code'] = code
    (results / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())

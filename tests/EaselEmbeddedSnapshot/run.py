#!/usr/bin/env python3
"""Compile the Easel embedded-page snapshot's engine translation units with
their real build flags (docs/easels.md, Export as Image).

Reads each object's exact clang command from `siso query commands -C
out/Release_GN_arm64`, swaps the source for this checkout's overlay copy,
puts every Engine/ParcNative overlay file first on the include path, and
rewrites -o, -MF and crash diagnostics into the results directory. Never
invokes GN/Ninja/siso builds or writes the engine workspace. This proves the
code compiles against Chromium 156's real headers, not that it links or runs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]
UNITS = {
    'obj/cef/libcef_static/native_page_capture.o': 'cef/libcef/browser/parc_native/native_page_capture.mm',
    'obj/cef/libcef_static/native_appkit_page.o': 'cef/libcef/browser/parc_native/native_appkit_page.mm',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def real_command(tree, build, objects, unit, sources, results):
    query = subprocess.run([str(tree / 'third_party/siso/cipd/siso'), 'query', 'commands', '-C', str(build), objects],
                           cwd=tree, capture_output=True, check=True)
    # Other commands in the graph carry non-UTF-8 bytes; keep them undecoded.
    lines = [line for line in query.stdout.decode('utf-8', 'surrogateescape').splitlines()
             if f' -c ../../{unit} -o {objects}' in line]
    if len(lines) != 1:
        raise RuntimeError(f'Expected one compile command for {unit}, found {len(lines)}')
    command = shlex.split(lines[0])
    output = results / (Path(unit).stem + '.o')
    rewritten, skip = [], False
    for index, arg in enumerate(command):
        if skip:
            skip = False
            continue
        if arg in ('-o', '-MF'):
            rewritten += [arg, str(output) + ('.d' if arg == '-MF' else '')]
            skip = True
        elif arg.startswith('-fcrash-diagnostics-dir='):
            rewritten.append(f'-fcrash-diagnostics-dir={results}')
        elif arg == '../../' + unit:
            rewritten.append(str(sources / unit))
        else:
            rewritten.append(arg)
    if '-Werror' not in rewritten or str(sources / unit) not in rewritten:
        raise RuntimeError('Unexpected compile command shape for ' + unit)
    return [rewritten[0], '-I' + str(sources), *rewritten[1:]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_tree', type=Path)
    parser.add_argument('--results', type=Path, required=True)
    args = parser.parse_args()
    tree = args.source_tree.resolve(strict=True)
    build = tree / 'out/Release_GN_arm64'
    results = args.results.resolve()
    if results.is_relative_to(tree):
        parser.error('results must be outside the source checkout')
    results.mkdir(parents=True, exist_ok=True)
    sources = results / 'src'
    shutil.rmtree(sources, ignore_errors=True)
    manifest = json.loads((REPO / 'Engine/ParcHost/overlay.json').read_text())
    inputs = []
    for item in manifest['files']:
        if item['source'].startswith('Engine/ParcNative/'):
            path = sources / item['target']
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / item['source'], path)
            if sha(path) != item['sha256']:
                raise RuntimeError('Overlay file differs from its manifest digest: ' + item['source'])
            inputs.append({'path': item['source'], 'sha256': item['sha256']})
    receipt = {'overlay_version': manifest['version'], 'inputs': inputs, 'commands': []}
    code = 0
    for objects, unit in UNITS.items():
        command = real_command(tree, build, objects, unit, sources, results)
        process = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = results / (Path(unit).stem + '.log')
        log.write_text(process.stdout)
        receipt['commands'].append({'unit': unit, 'exit_code': process.returncode, 'log': str(log)})
        print(f"{'ok' if not process.returncode else 'FAILED'}: {unit}")
        if process.returncode:
            print(process.stdout[-6000:], end='')
            code = process.returncode
            break
    receipt['exit_code'] = code
    (results / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())

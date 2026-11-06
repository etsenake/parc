#!/usr/bin/env python3
"""Compile real import readers against a built Chromium; run disposable fixtures.

No GN generation, browser launch, profile discovery, destination writes, or source
SQLite opens occur. Existing component libraries must correspond to the supplied
Chromium checkout. --output must be a disposable/private build directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parc-root', type=Path, required=True)
    parser.add_argument('--chromium-source', type=Path, required=True)
    parser.add_argument('--engine-output', type=Path, required=True)
    parser.add_argument('--ninja', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    parc, chromium, engine, output = [p.resolve() for p in
        (args.parc_root, args.chromium_source, args.engine_output, args.output)]
    if output == parc or output == chromium or output == engine or chromium in output.parents:
        parser.error('--output must be outside source/build inputs')
    output.mkdir(parents=True, exist_ok=True)
    include = output / 'include/chrome/utility/importer/parc'
    include.mkdir(parents=True, exist_ok=True)
    source = parc / 'Engine/ParcImport'
    files = [source / name for name in
             ('safari_reader.mm', 'firefox_reader.cc', 'import_snapshot.cc',
              'import_snapshot.h', 'import_reader.h')]
    fixture = parc / 'tests/BrowserImport/SafariFirefoxReaders.mm'
    files.append(fixture)
    for name in ('import_reader.h', 'import_snapshot.h'):
        shutil.copy2(source / name, include / name)
    libraries = [engine / ('lib' + name + '.dylib') for name in
                 ('base', 'url', 'sql', 'third_party_sqlite_chromium_sqlite3', 'c++_chrome')]
    for path in files + libraries:
        if not path.is_file():
            parser.error('required actual input missing: ' + str(path))
    receipt = {'inputs': {str(path): digest(path) for path in files + libraries},
               'commands': [], 'exit': None}

    def run(command, name):
        started = time.monotonic()
        result = subprocess.run(command, cwd=engine, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'name': name, 'command': command,
            'exit': result.returncode, 'seconds': time.monotonic() - started})
        if result.returncode:
            print(result.stdout + result.stderr)
            raise RuntimeError(name + ' failed')
        return result.stdout

    def flags(stem):
        target = 'obj/chrome/utility/utility/' + stem + '.o'
        commands = run([str(args.ninja.resolve()), '-C', str(engine), '-t', 'commands', '-s', target],
                       stem + '-command')
        command = next(shlex.split(line) for line in commands.splitlines()
                       if 'clang++' in line and stem in line)
        retained = []
        i = 0
        while i < len(command):
            if command[i] in ('-o', '-c', '-MF'):
                i += 2
            elif command[i] == '-MMD':
                i += 1
            else:
                retained.append(command[i])
                i += 1
        return retained

    try:
        cxx, objcxx = flags('firefox_importer'), flags('safari_importer')
        objects = []
        for path in (source / 'safari_reader.mm', source / 'firefox_reader.cc',
                     source / 'import_snapshot.cc', fixture):
            obj = output / (path.stem + '.o')
            run((objcxx if path.suffix == '.mm' else cxx) +
                ['-I' + str(output / 'include'), '-c', str(path), '-o', str(obj)], path.stem)
            objects.append(str(obj))
        link = [objcxx[0], '-nostdlib++', '-L' + str(engine), '-Wl,-rpath,' + str(engine),
                '-o', str(output / 'readers-fixtures')] + objects + [
                '-lbase', '-lurl', '-lsql', '-lthird_party_sqlite_chromium_sqlite3',
                '-lc++_chrome', '-framework', 'Foundation']
        if '-isysroot' in objcxx:
            link += ['-isysroot', objcxx[objcxx.index('-isysroot') + 1]]
        run(link, 'link')
        print(run([str(output / 'readers-fixtures')], 'fixtures'), end='')
        receipt['exit'] = 0
    except (RuntimeError, StopIteration) as error:
        receipt['exit'] = 1
        print(error)
    finally:
        receipt['inputs_unchanged'] = all(digest(Path(path)) == sha
                                        for path, sha in receipt['inputs'].items())
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return 0 if receipt['exit'] == 0 and receipt['inputs_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

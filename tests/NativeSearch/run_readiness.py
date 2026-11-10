#!/usr/bin/env python3
"""Run native search-readiness components against the pinned built Chromium.

Uses the production queue, actual Chromium ObserverList and task executor. The
negative control deliberately reproduces the synchronous ObserverList abort in
an isolated child process. No browser, Profile or user data is opened.
"""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import shlex
import signal
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
    parser.add_argument('--lock-file', type=Path)
    args = parser.parse_args()
    parc, chromium, engine, output = [p.resolve() for p in
        (args.parc_root, args.chromium_source, args.engine_output, args.output)]
    lock = json.loads((args.lock_file or parc / 'Engine/source-lock.json').read_text())
    if lock.get('schema_version') not in (1, 2):
        parser.error('unsupported source lock schema')
    direct = lock['schema_version'] == 2
    if output in (parc, chromium, engine) or chromium in output.parents:
        parser.error('--output must be outside source/build inputs')
    output.mkdir(parents=True, exist_ok=True)
    files = [parc / 'Engine/ParcNative/native_search_readiness.h',
             parc / 'tests/NativeSearch/ReadinessTests.cc',
             chromium / 'base/observer_list.h',
             chromium / 'components/search_engines/template_url_service_observer.h',
             engine / 'libbase.dylib', engine / 'libc++_chrome.dylib']
    receipt = {'inputs': {str(p): digest(p) for p in files}, 'commands': []}

    def run(command, name, expected=0):
        started = time.monotonic()
        result = subprocess.run(command, cwd=engine, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'name': name, 'command': command,
            'exit': result.returncode, 'expected': expected,
            'seconds': time.monotonic() - started})
        if result.returncode != expected:
            raise RuntimeError(name + ': ' + result.stdout + result.stderr)
        return result.stdout + result.stderr

    try:
        commands = run([str(args.ninja.resolve()), '-C', str(engine), '-t',
            'commands', '-s', ('obj/parc/browser/native_search.o' if direct
                               else 'obj/cef/libcef_static/native_search.o')], 'flags')
        command = next(shlex.split(line) for line in commands.splitlines()
                       if 'clang++' in line and 'native_search.mm' in line)
        flags, i = [], 0
        while i < len(command):
            if command[i] in ('-o', '-c', '-MF'):
                i += 2
            elif command[i] == '-MMD' or command[i].startswith(('-fobjc-', '-fno-objc-')):
                i += 1
            else:
                flags.append(command[i]); i += 1
        obj = output / 'readiness.o'
        run(flags + ['-c', str(files[1]), '-o', str(obj)], 'compile')
        executable = output / 'readiness'
        link = [flags[0], '-fuse-ld=lld', '-nostdlib++', '-L' + str(engine), '-Wl,-rpath,' + str(engine),
            '-o', str(executable), str(obj), '-lbase', '-lc++_chrome']
        if '-isysroot' in flags:
            link += ['-isysroot', flags[flags.index('-isysroot') + 1]]
        run(link, 'link')
        print(run([str(executable)], 'components'), end='')
        # Never produce a core dump for this deliberate child-process CHECK.
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        negative = run([str(executable), '--synchronous-negative-control'],
                       'negative-control', -signal.SIGABRT)
        if 'check_reentrancy' not in negative or 'IsOnlyRemainingNode' not in negative:
            raise RuntimeError('negative control did not hit the expected Chromium check')
        print('PASS: synchronous negative control reached Chromium ObserverList CHECK')
        receipt['exit'] = 0
    except (RuntimeError, StopIteration) as error:
        receipt['exit'] = 1
        print(error)
    finally:
        receipt['inputs_unchanged'] = all(digest(Path(p)) == sha
                                        for p, sha in receipt['inputs'].items())
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return 0 if receipt['exit'] == 0 and receipt['inputs_unchanged'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

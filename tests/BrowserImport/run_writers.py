#!/usr/bin/env python3
"""Check actual history/WebDatabase import transactions in disposable databases.

Uses the supplied built Chromium's pinned commands/libraries without building it
or opening any browser/Profile. --upstream-source may name private patched files;
otherwise the integrated Chromium files are used. All outputs stay in --output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import time

LIBRARIES = ['obj/components/history/core/browser/libbrowser.a', 'obj/components/favicon/core/libdatabase.a', 'obj/components/sync/protocol/libprotocol.a', 'obj/components/sync/model/libmodel.a', 'obj/components/sync/base/libbase.a', 'libnet.dylib', 'libgoogle_apis.dylib', 'libui_base.dylib', 'libicuuc_hidden_visibility.dylib', 'libnetwork_cpp_base.dylib', 'libskia.dylib', 'libchrome_zlib.dylib', 'libthird_party_perfetto_perfetto_test_support.dylib', 'libui_gfx_geometry.dylib', 'libthird_party_perfetto_libperfetto.dylib', 'libthird_party_abseil-cpp_absl.dylib', 'libsql.dylib', 'liburl.dylib', 'libthird_party_icu_icui18n.dylib', 'libcomponents_history_core_browser_features.dylib', 'libui_gfx.dylib', 'libbase.dylib', 'libui_base_ui_data_pack.dylib', 'libui_gfx_codec.dylib', 'libnetwork_cpp.dylib', 'libthird_party_protobuf_protobuf_full_and_lite_library.dylib', 'libbase_i18n.dylib', 'libbase_allocator_partition_allocator_src_partition_alloc_allocator_base.dylib', 'libc++_chrome.dylib', 'libwebdata_common.dylib', 'libui_gfx_color_utils.dylib', 'obj/components/google/core/common/libcommon.a', 'obj/components/favicon_base/libfavicon_base.a', 'obj/components/sync_device_info/libsync_device_info.a', 'obj/components/url_formatter/liburl_formatter.a', 'obj/components/url_formatter/libskeleton_generator.a', 'obj/components/database_utils/libdatabase_utils.a', 'obj/components/sync/protocol/libutil.a', 'obj/components/sync/engine/libengine.a', 'obj/third_party/crashpad/crashpad/client/libcommon.a']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('parc-root', 'chromium-source', 'engine-output', 'ninja', 'output'):
        parser.add_argument('--' + arg, type=Path, required=True)
    parser.add_argument('--upstream-source', type=Path)
    args = parser.parse_args()
    parc, chromium, engine, output = [p.resolve() for p in
        (args.parc_root, args.chromium_source, args.engine_output, args.output)]
    upstream = (args.upstream_source or chromium).resolve()
    if output in (parc, chromium, engine, upstream) or chromium in output.parents:
        parser.error('--output must be outside source/build inputs')
    output.mkdir(parents=True, exist_ok=True)
    paths = ['components/history/core/browser/history_backend',
             'components/webdata/common/web_database']
    sources = [upstream / (p + '.cc') for p in paths]
    headers = [upstream / (p + '.h') for p in paths]
    fixture = parc / 'tests/BrowserImport/HistoryWriter.cc'
    libraries = [engine / p for p in LIBRARIES]
    feature_object = engine / 'obj/components/sync/base/features/features.o'
    required = sources + headers + libraries + [fixture, feature_object, Path(__file__).resolve()]
    for p in required:
        if not p.is_file():
            parser.error('Missing actual input: ' + str(p))
    vfs = output / 'headers.vfs.json'
    vfs.write_text(json.dumps({'version': 0, 'roots': [
        {'type': 'file', 'name': str(chromium / (p + '.h')),
         'external-contents': str(upstream / (p + '.h'))} for p in paths]}, indent=2))
    receipt = {'inputs': {str(p): sha(p) for p in required}, 'commands': [], 'exit': None}

    def run(command, name):
        start = time.monotonic()
        result = subprocess.run(command, cwd=engine, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'name': name, 'command': command,
            'exit': result.returncode, 'seconds': time.monotonic() - start})
        if result.returncode:
            raise RuntimeError(name + ': ' + result.stdout + result.stderr)
        return result.stdout

    def flags(target):
        commands = run([str(args.ninja.resolve()), '-C', str(engine), '-t',
                        'commands', '-s', target], Path(target).stem + '-command')
        command = next(shlex.split(line) for line in commands.splitlines()
                       if 'clang++' in line and ' -c ' in line)
        retained = []
        i = 0
        while i < len(command):
            if command[i] in ('-c', '-o', '-MF'):
                i += 2
            elif command[i] == '-MMD':
                i += 1
            else:
                retained.append(command[i])
                i += 1
        return retained

    try:
        history = flags('obj/components/history/core/browser/browser/history_backend.o')
        webdata = flags('obj/components/webdata/common/common/web_database.o')
        objects = []
        for source, command in zip(sources + [fixture], [history, webdata, history]):
            obj = output / (source.stem + '.o')
            dep = output / (source.stem + '.d')
            run(command + ['-ivfsoverlay', str(vfs), '-MMD', '-MF', str(dep),
                           '-c', str(source), '-o', str(obj)], source.stem)
            objects.append(obj)
            for value in shlex.split(dep.read_text().replace(chr(92) + chr(10), ' ').split(':', 1)[1]):
                p = Path(value)
                if not p.is_absolute():
                    p = engine / p
                p = p.resolve()
                if p.is_file():
                    receipt['inputs'][str(p)] = sha(p)
        llvm = chromium / 'third_party/llvm-build/Release+Asserts/bin'
        for lib in libraries:
            if lib.suffix != '.a':
                continue
            for member in run([str(llvm / 'llvm-ar'), 't', str(lib)],
                              'archive-' + str(lib.relative_to(engine)).replace('/', '_')).splitlines():
                p = Path(member)
                if not p.is_absolute():
                    p = engine / p
                if p.is_file():
                    receipt['inputs'][str(p.resolve())] = sha(p)
        exe = output / 'import-writer-fixture'
        # Private patched definitions precede existing archives; no production
        # object or library is replaced. ld64.lld reads LLVM thin archives.
        run([history[0], '-fuse-ld=lld', '-nostdlib++', '-Wl,-dead_strip',
             '-Wl,-dead_strip_dylibs', '-Wl,-rpath,' + str(engine), '-o', str(exe)] +
            [str(p) for p in objects + [feature_object] + libraries], 'link')
        for name, switches in [('legacy', []), ('scoped', ['--scoped'])]:
            print(run([str(exe)] + switches, name), end='')
        receipt['binarySHA256'] = sha(exe)
        receipt['inputsUnchanged'] = all(sha(Path(p)) == digest for p, digest in receipt['inputs'].items())
        if not receipt['inputsUnchanged']:
            raise RuntimeError('An actual checked input changed during the run')
        receipt['exit'] = 0
    finally:
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()

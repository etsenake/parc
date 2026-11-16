#!/usr/bin/env python3
"""Syntax-check the top-band colour sources (docs/top-band-color.md) with their
targets' actual flags, one translation unit at a time.

Generates top_band_color.mojom's C++ bindings into the results directory with
the checkout's mojom tools, applies top-band-color.patch in memory to the
pristine Blink files, and runs `clang++ -fsyntax-only` on the renderer tracker,
the four patched Blink files and the browser's native_appkit_page.mm. Never
invokes GN/Ninja or writes the source tree. This checks that the code compiles
against the pinned Chromium's real headers, not that it links or runs.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]
PATCH = 'Engine/ParcHost/integration/top-band-color.patch'
MOJOM = 'third_party/blink/public/mojom/parc/top_band_color.mojom'
CORE = 'obj/third_party/blink/renderer/core/core.ninja'
MANIFEST_PATH = REPO / 'Engine/ParcHost/overlay.json'
CEF = 'obj/parc/browser.ninja'
RENDERER_UNITS = [
    'third_party/blink/renderer/core/frame/parc_top_band_color_tracker.cc',
    'third_party/blink/renderer/core/frame/local_frame.cc',
    'third_party/blink/renderer/core/frame/local_frame_view.cc',
    'third_party/blink/renderer/core/dom/document.cc',
    'third_party/blink/renderer/core/loader/document_loader.cc',
]
BROWSER_UNIT = 'parc/native/native_appkit_page.mm'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest():
    return json.loads(MANIFEST_PATH.read_text())


def patched_sources(tree):
    spec = importlib.util.spec_from_file_location('engine_source', REPO / 'scripts/engine-source.py')
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    entry = next(p for p in manifest()['patches'] if p['source'] == PATCH)
    if sha(REPO / PATCH) != entry['sha256']:
        raise RuntimeError('Patch differs from its manifest digest')
    pristine = {}
    for item in entry['files']:
        path = tree / item['target']
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item['before_sha256']:
            data = subprocess.run(['git', '-C', str(path.parent), 'show', 'HEAD:./' + path.name],
                                  capture_output=True, check=True).stdout
        if hashlib.sha256(data).hexdigest() != item['before_sha256']:
            raise RuntimeError('No pristine source matches the manifest: ' + item['target'])
        pristine[item['target']] = data
    outputs = engine.apply_context_patch((REPO / PATCH).read_text(), pristine)
    for item in entry['files']:
        if hashlib.sha256(outputs[item['target']]).hexdigest() != item['after_sha256']:
            raise RuntimeError('Patched output differs from the manifest: ' + item['target'])
    return outputs


def target_flags(ninja, keys, results, module=True):
    variables = {}
    for line in ninja.read_text().splitlines():
        if ' =' in line and not line.startswith(' '):
            key, value = line.split(' =', 1)
            variables[key] = value.strip().replace('$:', ':')
    flags = []
    for key in keys:
        flags += shlex.split(variables[key])
    if module:
        flags.append('-fmodule-name=%s_Private' % variables['cc_module_name'])
    if any('$' in f for f in flags) or '-Werror' not in flags:
        raise RuntimeError('Generated target flags are incomplete/unresolved: ' + str(ninja))
    return [f'-fcrash-diagnostics-dir={results}' if f.startswith('-fcrash-diagnostics-dir=') else f
            for f in flags]


def generate_bindings(tree, build, results):
    root = results / 'mojom'
    shutil.rmtree(root, ignore_errors=True)
    (root / MOJOM).parent.mkdir(parents=True)
    shutil.copyfile(REPO / 'Engine/ParcRenderer/top_band_color.mojom', root / MOJOM)
    python = str(tree / 'third_party/cpython3/host/bin/python3')
    gen = results / 'gen'
    subprocess.run([python, str(tree / 'mojo/public/tools/mojom/mojom_parser.py'), '--input-root', str(root),
                    '--output-root', str(gen), '--mojoms', str(root / MOJOM), '--enable-feature', 'is_posix',
                    '--enable-feature', 'is_mac', '--enable-feature', 'is_apple'], check=True)
    generator = [python, str(tree / 'mojo/public/tools/bindings/mojom_bindings_generator.py'), '--use_bundled_pylibs',
                 '-o', str(gen), 'generate', '-d', str(root) + '/', '-I', str(root) + '/',
                 '--bytecode_path', str(build / 'gen/mojo/public/tools/bindings')]
    for extra in (['--generate_non_variant_code', '--generate_message_ids'],
                  ['--generate_non_variant_code', '--export_attribute',
                   'COMPONENT_EXPORT(MOJOM_SHARED_BLINK_COMMON_EXPORT)', '--export_header', 'base/component_export.h'],
                  ['--export_attribute', 'BLINK_COMMON_EXPORT', '--export_header',
                   'third_party/blink/public/common/common_export.h'],
                  ['--export_attribute', 'CORE_EXPORT', '--export_header',
                   'third_party/blink/renderer/core/core_export.h', '--variant', 'blink', '--for_blink']):
        subprocess.run([*generator, *extra, '-g', 'c++', str(root / MOJOM)], check=True)
    return gen


def main():
    global MANIFEST_PATH
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_tree', type=Path)
    parser.add_argument('--results', type=Path, required=True)
    args = parser.parse_args()
    lock = json.loads((REPO / "Engine/source-lock.json").read_text())
    if lock.get('schema_version') != 2:
        parser.error('unsupported source lock schema')
    MANIFEST_PATH = REPO / ('Engine/ParcHost/overlay.json')
    tree = args.source_tree.resolve(strict=True)
    build = tree / 'out' / lock['build']['configuration']
    results = args.results.resolve()
    if results.is_relative_to(tree):
        parser.error('results must be outside the source checkout')
    results.mkdir(parents=True, exist_ok=True)
    sources = results / 'src'
    shutil.rmtree(sources, ignore_errors=True)
    for item in manifest()['files']:
        if item['source'].startswith(('Engine/ParcRenderer/', 'Engine/ParcNative/')):
            path = sources / item['target']
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / item['source'], path)
    for target, data in patched_sources(tree).items():
        path = sources / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    gen = generate_bindings(tree, build, results)

    clang = str(tree / 'third_party/llvm-build/Release+Asserts/bin/clang++')
    local = ['-I' + str(sources), '-I' + str(gen)]
    core = target_flags(build / CORE, ('defines', 'include_dirs', 'cflags', 'cflags_cc', 'module_deps'), results)
    browser_flags = target_flags(build / ('obj/parc/browser.ninja'), ('defines', 'include_dirs', 'framework_dirs', 'cflags', 'cflags_objcc'), results,
                       module=False)
    commands = [[clang, *local, *core, '-fsyntax-only', str(sources / unit)] for unit in RENDERER_UNITS]
    commands.append([clang, *local, *browser_flags, '-fsyntax-only', str(sources / (BROWSER_UNIT))])
    receipt = {'inputs': [{'path': str(p), 'sha256': sha(p)} for p in
                          [REPO / PATCH, *(REPO / i['source'] for i in manifest()['files']
                                           if 'ParcRenderer' in i['source'])]],
               'commands': []}
    code = 0
    for i, command in enumerate(commands):
        process = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = results / f'{i}.log'
        log.write_text(process.stdout)
        receipt['commands'].append({'unit': command[-1], 'exit_code': process.returncode, 'log': str(log)})
        print(f"{'ok' if not process.returncode else 'FAILED'}: {command[-1]}")
        if process.returncode:
            print(process.stdout[-6000:], end='')
            code = process.returncode
            break
    receipt['exit_code'] = code
    (results / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())

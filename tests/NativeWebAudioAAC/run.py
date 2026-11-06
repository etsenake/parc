#!/usr/bin/env python3
"""Compile WebAudio's AAC route with the engine's actual target flags and run
it without a browser: blink::PlatformAudioFileDecoder (the renderer half of
decodeAudioData() for AAC), the patched media::AudioFileReader and the patched
AudioToolboxAudioDecoder, directly and behind a real MojoAudioDecoder and
MojoAudioDecoderService pair, compared with macOS's ExtAudioFile.

Never invokes GN/Ninja or changes the source tree; patched sources, objects,
fixtures and the receipt go to the external result directory. --compile-only
stops before linking, which needs a finished engine build. The Blink half that
turns the result into an AudioBuffer (base_audio_context.cc) is compiled, not
run: it needs a renderer.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import wave

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]
PATCHES = ['Engine/ParcHost/integration/platform-codecs.patch',
           'Engine/ParcHost/integration/webaudio-aac.patch']
WEBAUDIO = 'third_party/blink/renderer/modules/webaudio'
# (source, target ninja, linked)
UNITS = [
    ('media/filters/mac/audio_toolbox_audio_decoder.cc', 'obj/media/filters/filters.ninja', True),
    ('media/filters/audio_file_reader.cc', 'obj/media/filters/filters.ninja', True),
    ('media/ffmpeg/ffmpeg_common.cc', 'obj/media/ffmpeg/ffmpeg.ninja', True),
    ('media/mojo/clients/mojo_audio_decoder.cc', 'obj/media/mojo/clients/clients.ninja', True),
    ('media/mojo/services/mojo_audio_decoder_service.cc', 'obj/media/mojo/services/services.ninja', True),
    (WEBAUDIO + '/platform_audio_file_decoder.cc', f'obj/{WEBAUDIO}/webaudio.ninja', True),
    (WEBAUDIO + '/base_audio_context.cc', f'obj/{WEBAUDIO}/webaudio.ninja', False),
]
TEST_NINJA = 'obj/media/mojo/services/services.ninja'
SERVICES_LINK = 'build ./libmedia_mojo_services.dylib'
CLIENT_OBJECTS = ['obj/media/mojo/clients/clients/mojo_media_log_service.o']
# Built objects whose patched sources the check compiles instead.
REPLACED = {'obj/media/mojo/services/services/mojo_audio_decoder_service.o'}
FIXTURES = {  # name: (afconvert container, data format, source)
    'lc.m4a': ('m4af', 'aac ', 'stereo.wav'),
    'lc_mono.m4a': ('m4af', 'aac ', 'mono.wav'),
    'he.m4a': ('m4af', 'aach', 'stereo.wav'),
    'hev2.m4a': ('m4af', 'aacp', 'stereo.wav'),
    'lc.aac': ('adts', 'aac ', 'stereo.wav'),
    'he.aac': ('adts', 'aach', 'stereo.wav'),
    'lc_long.m4a': ('m4af', 'aac ', 'long.wav'),
    'lc_10min.m4a': ('m4af', 'aac ', '10min.wav'),
}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CODECS = load('platform_codecs_check', REPO / 'tests/NativePlatformCodecs/run.py')
ENGINE = load('engine_source', REPO / 'scripts/engine-source.py')
sha = CODECS.sha


def patched_sources(tree):
    """Every target of both patches and the new files, from the reviewed overlay. A live target
    may be patched, pristine or an earlier overlay's version; for the last, the pristine bytes
    come read-only from the Git checkout that holds the file."""
    manifest = json.loads((REPO / 'Engine/ParcHost/overlay.json').read_text())
    outputs = {}
    for name in PATCHES:
        entry = next(p for p in manifest['patches'] if p['source'] == name)
        if sha(REPO / name) != entry['sha256']:
            raise RuntimeError('Patch differs from its manifest digest: ' + name)
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
        result = ENGINE.apply_context_patch((REPO / name).read_text(), pristine)
        for item in entry['files']:
            if hashlib.sha256(result[item['target']]).hexdigest() != item['after_sha256']:
                raise RuntimeError('Patched output differs from the manifest: ' + item['target'])
        outputs.update(result)
    for item in manifest['files']:
        if item['target'].startswith(WEBAUDIO + '/'):
            if sha(REPO / item['source']) != item['sha256']:
                raise RuntimeError('New file differs from its manifest digest: ' + item['source'])
            outputs[item['target']] = (REPO / item['source']).read_bytes()
    return outputs


def ninja_build(ninja, prefix):
    """The explicit inputs and indented variables of the build statement starting with `prefix`."""
    lines = ninja.read_text().splitlines()
    index = next(i for i, line in enumerate(lines) if line.startswith(prefix))
    inputs = lines[index].split(': solink ', 1)[1].split(' | ', 1)[0].split(' || ', 1)[0].split()
    variables = {}
    for line in lines[index + 1:]:
        if not line.startswith('  '):
            break
        key, value = line.strip().split(' = ', 1) if ' = ' in line else (line.strip().rstrip(' ='), '')
        variables[key] = value
    if any('$' in item for item in inputs + variables.get('solibs', '').split()):
        raise RuntimeError('Escaped ninja paths are unsupported: ' + str(ninja))
    return inputs, variables


def write_wav(path, channels, seconds):
    # Whole-hertz tones repeat every second, so longer files repeat that second.
    rate = 44100
    tones = [(1000, 14000), (500, 16000)][:channels]
    second = bytearray()
    for index in range(rate):
        t = index / rate
        for low, high in tones:
            value = 0.3 * math.sin(2 * math.pi * low * t) + 0.3 * math.sin(2 * math.pi * high * t)
            second += struct.pack('<h', int(value * 32767))
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(bytes(second) * seconds)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_tree', type=Path)
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--compile-only', action='store_true',
                        help='compile the patched units and stop before linking against built objects')
    args = parser.parse_args()
    tree = args.source_tree.resolve(strict=True)
    build = tree / 'out/Release_GN_arm64'
    results = args.results.resolve()
    if results.is_relative_to(tree):
        parser.error('results must be outside the source checkout')
    results.mkdir(parents=True, exist_ok=True)
    sources = results / 'src'
    for target, data in patched_sources(tree).items():
        if target.endswith(('.cc', '.h')):
            path = sources / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    config_dir = tree / CODECS.FFMPEG_CONFIG
    cxx_keys = ('defines', 'include_dirs', 'cflags', 'cflags_cc', 'module_deps')
    llvm = tree / 'third_party/llvm-build/Release+Asserts/bin'
    objects = results / 'objects'
    objects.mkdir(exist_ok=True)
    test = Path(__file__).with_name('webaudio_aac_test.cc')
    inputs = [*(REPO / p for p in PATCHES), REPO / 'Engine/ParcHost/overlay.json', test, llvm / 'clang++']
    commands, linked = [], []
    for source, ninja, link in [*UNITS, (str(test), TEST_NINJA, True)]:
        flags = ['-I' + str(sources), *CODECS.target_flags(build / ninja, cxx_keys, config_dir, results)]
        path = Path(source) if source == str(test) else sources / source
        output = objects / (Path(source).stem + '.o')
        commands.append([str(llvm / 'clang++'), *flags, '-c', str(path), '-o', str(output)])
        inputs.append(build / ninja)
        if link:
            linked.append(output)
    compiled = len(commands)

    binary = results / 'webaudio_aac_test'
    fixtures = results / 'fixtures'
    if not args.compile_only:
        services, variables = ninja_build(build / TEST_NINJA, SERVICES_LINK)
        solibs = [build / item for item in variables['solibs'].split()]
        if build / 'libffmpeg.dylib' not in solibs:
            solibs.append(build / 'libffmpeg.dylib')
        if not REPLACED <= set(services):
            raise RuntimeError('libmedia_mojo_services.dylib no longer links ' + ', '.join(REPLACED))
        archives = [build / item for item in services
                    if item.endswith(('.o', '.a')) and item not in REPLACED]
        clients = [build / item for item in CLIENT_OBJECTS]
        runtime = [build / item for item in variables.get('libs', '').split()]
        sysroot = flags[flags.index('-isysroot') + 1]
        inputs += [build / TEST_NINJA, *archives, *clients, *solibs, *runtime]
        # Chromium's static libraries are thin archives, which only its own lld reads.
        commands.append([str(llvm / 'clang++'), '--target=arm64-apple-macos', '-isysroot', sysroot,
                         '-mmacos-version-min=13.0', '-nostdlib++', '-fuse-ld=lld',
                         '--ld-path=' + str(llvm / 'ld64.lld'), *map(str, linked), *map(str, archives),
                         *map(str, clients), *map(str, solibs), *map(str, runtime),
                         '-framework', 'AudioToolbox', '-framework', 'CoreFoundation',
                         '-Wl,-rpath,' + str(build), '-o', str(binary)])
        fixtures.mkdir(exist_ok=True)
        write_wav(fixtures / 'stereo.wav', 2, 2)
        write_wav(fixtures / 'mono.wav', 1, 2)
        write_wav(fixtures / 'long.wav', 2, 60)
        write_wav(fixtures / '10min.wav', 2, 600)
        for name, (container, data_format, source) in FIXTURES.items():
            commands.append(['/usr/bin/afconvert', '-f', container, '-d', data_format,
                             str(fixtures / source), str(fixtures / name)])
        prepare = len(commands)
        commands.append([str(binary), str(fixtures)])

    receipt = {'scope': 'patched PlatformAudioFileDecoder, AudioFileReader, AudioToolboxAudioDecoder, '
                        'MojoAudioDecoder, MojoAudioDecoderService and ffmpeg_common.cc with actual target flags; base_audio_context.cc compiled only' +
                        ('' if args.compile_only else '; linked to completed media/mojo objects and run in-process '
                         'and over a real MojoAudioDecoder/MojoAudioDecoderService pair against macOS ExtAudioFile') +
                        '; no GN/Ninja, browser, renderer or GPU process', 'commands': []}
    code = 0
    for i, command in enumerate(commands):
        if not args.compile_only and i == prepare:
            lc = (fixtures / 'lc.aac').read_bytes()
            (fixtures / 'lc_truncated.aac').write_bytes(lc[:len(lc) // 2])
            block, garbage = b'parc', bytearray()
            while len(garbage) < 65536:
                block = hashlib.sha256(block).digest()
                garbage += block
            (fixtures / 'garbage.bin').write_bytes(bytes(garbage))
        process = subprocess.run(command, cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = results / f'{i}.log'
        log.write_text(process.stdout)
        receipt['commands'].append({'command': command, 'cwd': str(build), 'exit_code': process.returncode,
                                    'log': str(log), 'log_sha256': sha(log)})
        print(process.stdout, end='')
        if i < compiled and not process.returncode:
            print('compiled ' + command[-3])
        if process.returncode:
            code = process.returncode
            break
    receipt['inputs'] = [{'path': str(p), 'sha256': sha(p)} for p in inputs]
    if fixtures.is_dir():
        receipt['fixtures'] = {p.name: sha(p) for p in sorted(fixtures.iterdir())}
    receipt['exit_code'] = code
    (results / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())

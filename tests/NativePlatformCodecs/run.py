#!/usr/bin/env python3
"""Compile the overlay's AudioToolboxAudioDecoder, its FFmpeg ADTS demuxer and
ffmpeg_common.cc with their actual target flags, link them to completed
FFmpeg/media/base objects and decode macOS-encoded AAC. Then repeat under the
pinned GPU seatbelt profile and confirm the renderer profile refuses
AudioToolbox.

Never invokes GN/Ninja or changes the source tree; the patched sources, objects,
combined profiles and fixtures are written to the external result directory.
This checks the decoder, the demuxing half of src= playback and the sandbox,
not renderer decoder selection, the GPU process's IPC or playback.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shlex
import shutil
import struct
import subprocess
import sys
import wave

sys.dont_write_bytecode = True

REPO = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO / 'Engine/ParcHost/overlay.json'
PATCH = 'Engine/ParcHost/integration/platform-codecs.patch'
DECODER = 'media/filters/mac/audio_toolbox_audio_decoder'
FFMPEG_COMMON = 'media/ffmpeg/ffmpeg_common.cc'
FFMPEG_CONFIG = 'third_party/ffmpeg/chromium/config/Chromium/mac/arm64'
FFMPEG_DEMUXER = 'third_party/ffmpeg/libavformat/aacdec.c'
# FFmpeg units the patch adds or alters: allformats.c and parsers.c include
# the demuxer and parser lists, adts_parser.c reads CONFIG_ADTS_HEADER, and the
# rest are the ADTS demuxer (patched, so compiled from the results) and its
# AAC parser and tag dependencies.
FFMPEG_UNITS = ['libavformat/allformats.c', 'libavcodec/parsers.c', 'libavcodec/adts_parser.c',
                'libavcodec/aac_ac3_parser.c', 'libavcodec/aac_parser.c', 'libavcodec/adts_header.c',
                'libavformat/apetag.c', 'libavformat/img2.c']
FIXTURES = {  # name: (afconvert container, data format, source)
    'lc.m4a': ('m4af', 'aac ', 'stereo.wav'),
    'he.m4a': ('m4af', 'aach', 'stereo.wav'),
    'hev2.m4a': ('m4af', 'aacp', 'stereo.wav'),
    'lc.aac': ('adts', 'aac ', 'stereo.wav'),
    'he.aac': ('adts', 'aach', 'stereo.wav'),
    'hev2.aac': ('adts', 'aacp', 'stereo.wav'),
    'he_mono.aac': ('adts', 'aach', 'mono.wav'),
    'he51.aac': ('adts', 'aach', 'six.wav'),
    'lc_mono.aac': ('adts', 'aac ', 'mono.wav'),
    'lc22.aac': ('adts', 'aac ', 'stereo22.wav'),
    'lc22_mono.aac': ('adts', 'aac ', 'mono22.wav'),
}
# afconvert's MP4s signal SBR explicitly; these copies keep only the AAC-LC core.
IMPLICIT_MP4 = {'he_implicit.m4a': 'he.m4a', 'hev2_implicit.m4a': 'hev2.m4a'}
# macOS's own decoding of these, with its priming, remainder and decoder tail,
# made by afconvert so that nothing touches AudioToolbox in the test process
# before a seatbelt applies.
REFERENCES = ['he.aac', 'hev2.aac', 'he.m4a', 'hev2.m4a', 'lc.m4a']


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def patched_sources(tree):
    """Return every target of the overlay patch as the manifest's after-digest bytes. Each live
    target may already be patched, be pristine, or carry an earlier overlay's version; for the
    last, the pristine bytes come read-only from the Git checkout that holds the file."""
    spec = importlib.util.spec_from_file_location('engine_source', REPO / 'scripts/engine-source.py')
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    manifest = json.loads(MANIFEST_PATH.read_text())
    entry = next(p for p in manifest['patches'] if p['source'] == PATCH)
    if sha(REPO / PATCH) != entry['sha256']:
        raise RuntimeError('Patch differs from its manifest digest')
    pristine = {}
    for item in entry['files']:
        target = item['target']
        data = (tree / target).read_bytes()
        if hashlib.sha256(data).hexdigest() != item['before_sha256']:
            path = tree / target
            data = subprocess.run(['git', '-C', str(path.parent), 'show', 'HEAD:./' + path.name],
                                  capture_output=True, check=True).stdout
        if hashlib.sha256(data).hexdigest() != item['before_sha256']:
            raise RuntimeError('No pristine source matches the manifest: ' + target)
        pristine[target] = data
    outputs = engine.apply_context_patch((REPO / PATCH).read_text(), pristine)
    for item in entry['files']:
        if hashlib.sha256(outputs[item['target']]).hexdigest() != item['after_sha256']:
            raise RuntimeError('Patched output differs from the manifest: ' + item['target'])
    return outputs


def target_flags(ninja, keys, config_dir, results):
    variables = {}
    for line in ninja.read_text().splitlines():
        if ' =' in line and not line.startswith(' '):
            key, value = line.split(' =', 1)
            variables[key] = value.strip().replace('$:', ':')
    flags = []
    for key in keys:
        flags += shlex.split(variables[key])
    flags.append('-fmodule-name=%s_Private' % variables['cc_module_name'])
    if any('$' in f for f in flags) or '-Werror' not in flags:
        raise RuntimeError('Generated target flags are incomplete/unresolved: ' + str(ninja))
    original_config = '-I../../' + FFMPEG_CONFIG
    return [('-I' + str(config_dir) if f == original_config else
             f'-fcrash-diagnostics-dir={results}' if f.startswith('-fcrash-diagnostics-dir=') else f)
            for f in flags]


def boxes(data, start=0, end=None):
    end = len(data) if end is None else end
    while start + 8 <= end:
        size, kind = struct.unpack('>I4s', data[start:start + 8])
        header = 8
        if size == 1:
            size, header = struct.unpack('>Q', data[start + 8:start + 16])[0], 16
        yield kind.decode('latin1'), start + header, start + size
        start += size


def child(data, start, end, *path):
    for name in path:
        start, end = next((s, e) for kind, s, e in boxes(data, start, end) if kind == name)
    return start, end


def extract_mp4(source, target):
    """Write the AudioSpecificConfig and access units of an afconvert .m4a without AudioToolbox,
    so nothing initializes AudioToolbox before the test applies a seatbelt profile."""
    data = source.read_bytes()
    stbl = child(data, 0, len(data), 'moov', 'trak', 'mdia', 'minf', 'stbl')
    stsd = child(data, *stbl, 'stsd')
    esds = child(data, stsd[0] + 8 + 8 + 28, stsd[1], 'esds')
    offset = esds[0] + 4
    config = b''
    while offset < esds[1]:
        tag = data[offset]
        offset += 1
        length = 0
        while True:
            byte = data[offset]
            offset += 1
            length = (length << 7) | (byte & 0x7f)
            if not byte & 0x80:
                break
        if tag == 5:
            config = data[offset:offset + length]
            break
        offset += {3: 3, 4: 13}.get(tag, length)
    stsz = child(data, *stbl, 'stsz')
    uniform, count = struct.unpack('>II', data[stsz[0] + 4:stsz[0] + 12])
    sizes = [uniform] * count if uniform else list(struct.unpack(f'>{count}I', data[stsz[0] + 12:stsz[0] + 12 + 4 * count]))
    stsc = child(data, *stbl, 'stsc')
    runs = [struct.unpack('>III', data[stsc[0] + 8 + 12 * i:stsc[0] + 20 + 12 * i])
            for i in range(struct.unpack('>I', data[stsc[0] + 4:stsc[0] + 8])[0])]
    stco = child(data, *stbl, 'stco')
    chunks = struct.unpack('>%dI' % struct.unpack('>I', data[stco[0] + 4:stco[0] + 8])[0],
                           data[stco[0] + 8:stco[1]])
    packets, sample = [], 0
    for index, chunk_offset in enumerate(chunks, 1):
        per_chunk = next(n for first, n, _ in reversed(runs) if first <= index)
        for _ in range(per_chunk):
            packets.append(data[chunk_offset:chunk_offset + sizes[sample]])
            chunk_offset += sizes[sample]
            sample += 1
    output = struct.pack('<I', len(config)) + config + struct.pack('<I', len(packets))
    output += b''.join(struct.pack('<I', len(p)) + p for p in packets)
    target.write_bytes(output)


def implicit_mp4(source, target):
    """Rewrite an afconvert HE-AAC .m4a so its esds AudioSpecificConfig is the bare two-byte
    AAC-LC core, as an implicitly signalled HE-AAC MP4 carries. The `free` box between moov and
    mdat absorbs the size change, so the chunk offsets stay valid."""
    data = bytearray(source.read_bytes())
    ancestors, start, end = [], 0, len(data)
    for name in ('moov', 'trak', 'mdia', 'minf', 'stbl', 'stsd'):
        start, end = child(data, start, end, name)
        ancestors.append(start - 8)
    ancestors.append(start + 8)  # the sample entry, after stsd's version, flags and count
    esds = child(data, start + 8 + 8 + 28, end, 'esds')
    ancestors.append(esds[0] - 8)
    lengths, offset = [], esds[0] + 4
    while True:
        tag = data[offset]
        if data[offset + 1:offset + 4] != b'\x80\x80\x80':
            raise RuntimeError('Unexpected esds descriptor length encoding in ' + source.name)
        lengths.append(offset + 4)
        offset += 5
        if tag == 5:
            break
        offset += {3: 3, 4: 13}[tag]
    config = bytes(data[offset:offset + data[offset - 1]])
    if config[0] >> 3 != 2 or len(config) <= 2:
        raise RuntimeError('Expected a backward-compatible HE-AAC config in ' + source.name)
    shrink = len(config) - 2
    moov_end = ancestors[0] + struct.unpack('>I', data[ancestors[0]:ancestors[0] + 4])[0]
    if data[moov_end + 4:moov_end + 8] != b'free':
        raise RuntimeError('Expected a free box after moov in ' + source.name)
    free_size = struct.unpack('>I', data[moov_end:moov_end + 4])[0]
    data[moov_end:moov_end + 4] = struct.pack('>I', free_size + shrink)
    data[moov_end + free_size:moov_end + free_size] = bytes(shrink)
    for box in ancestors:
        data[box:box + 4] = struct.pack('>I', struct.unpack('>I', data[box:box + 4])[0] - shrink)
    for length in lengths:
        data[length] -= shrink
    del data[offset + 2:offset + len(config)]
    target.write_bytes(bytes(data))


def reference_pcm(source, target):
    """Write afconvert's 32-bit float WAV as <u32 channels><u32 frames> and planar floats."""
    data = source.read_bytes()
    if data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise RuntimeError('Not a WAVE file: ' + source.name)
    offset, channels, samples = 12, None, None
    while offset + 8 <= len(data):
        kind, size = data[offset:offset + 4], struct.unpack('<I', data[offset + 4:offset + 8])[0]
        body = data[offset + 8:offset + 8 + size]
        if kind == b'fmt ':
            tag, channels, _, _, _, bits = struct.unpack('<HHIIHH', body[:16])
            if tag not in (3, 0xfffe) or bits != 32:
                raise RuntimeError('Expected 32-bit float samples in ' + source.name)
        elif kind == b'data':
            samples = struct.unpack('<%df' % (size // 4), body)
        offset += 8 + size + (size & 1)
    if not channels or samples is None:
        raise RuntimeError('Incomplete WAVE file: ' + source.name)
    frames = len(samples) // channels
    planar = [samples[channel::channels] for channel in range(channels)]
    target.write_bytes(struct.pack('<II', channels, frames) +
                       b''.join(struct.pack('<%df' % frames, *plane) for plane in planar))


def write_wav(path, channels, rate=44100):
    # Every 5.1 channel gets the first pair, so the decoded left channel has it
    # however afconvert maps the WAV's channels.
    tones = [(1000, 14000), (500, 16000)][:channels] if channels <= 2 else [(1000, 14000)] * channels
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        frames = bytearray()
        for index in range(rate * 2):
            t = index / rate
            for low, high in tones:
                value = 0.3 * math.sin(2 * math.pi * low * t)
                if high < rate / 2:
                    value += 0.3 * math.sin(2 * math.pi * high * t)
                frames += struct.pack('<h', int(value * 32767))
        output.writeframes(bytes(frames))


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
    config_dir = sources / FFMPEG_CONFIG
    if config_dir.exists():
        shutil.rmtree(config_dir)
    shutil.copytree(tree / FFMPEG_CONFIG, config_dir)
    for target, data in patched_sources(tree).items():
        if target.startswith((DECODER, FFMPEG_COMMON, FFMPEG_CONFIG, FFMPEG_DEMUXER)):
            path = sources / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    fixtures = results / 'fixtures'
    fixtures.mkdir(exist_ok=True)
    write_wav(fixtures / 'stereo.wav', 2)
    write_wav(fixtures / 'mono.wav', 1)
    write_wav(fixtures / 'six.wav', 6)
    write_wav(fixtures / 'stereo22.wav', 2, 22050)
    write_wav(fixtures / 'mono22.wav', 1, 22050)

    filters_ninja = build / 'obj/media/filters/filters.ninja'
    media_ffmpeg_ninja = build / 'obj/media/ffmpeg/ffmpeg.ninja'
    ffmpeg_ninja = build / 'obj/third_party/ffmpeg/ffmpeg_internal.ninja'
    cxx_keys = ('defines', 'include_dirs', 'cflags', 'cflags_cc', 'module_deps')
    decoder_flags = ['-I' + str(sources), *target_flags(filters_ninja, cxx_keys, config_dir, results)]
    media_flags = ['-I' + str(sources), *target_flags(media_ffmpeg_ninja, cxx_keys, config_dir, results)]
    ffmpeg_flags = target_flags(ffmpeg_ninja, ('defines', 'include_dirs', 'cflags', 'cflags_c'), config_dir, results)
    if not any(f == '-I' + str(config_dir) for f in ffmpeg_flags):
        raise RuntimeError('FFmpeg flags do not name the platform configuration directory')
    sysroot = decoder_flags[decoder_flags.index('-isysroot') + 1]
    link_flags = ['--target=arm64-apple-macos', '-isysroot', sysroot, '-mmacos-version-min=13.0']
    llvm = tree / 'third_party/llvm-build/Release+Asserts/bin'
    test = Path(__file__).with_name('aac_decoder_test.cc')
    libraries = [build / name for name in (
        'libmedia.dylib', 'libbase.dylib', 'libc++_chrome.dylib', 'libui_gfx_color_space.dylib',
        'libbase_allocator_partition_allocator_src_partition_alloc_allocator_core.dylib')]
    # The rest of FFmpeg exactly as the engine links libffmpeg.dylib, so this
    # executable's demuxing uses one FFmpeg with the patched lists.
    link_line = next(line for line in (build / 'obj/third_party/ffmpeg/ffmpeg.ninja').read_text().splitlines()
                     if line.startswith('build ./libffmpeg.dylib'))
    replaced = {Path(unit).stem + '.o' for unit in FFMPEG_UNITS} | {'autorename_libavformat_aacdec.o'}
    ffmpeg_objects = [build / item for item in link_line.split()
                      if item.startswith('obj/third_party/ffmpeg/ffmpeg_internal/') and item.endswith('.o')
                      and Path(item).name not in replaced]
    # libopus.a is a thin archive, which the system linker doesn't read.
    opus = subprocess.run([str(tree / 'third_party/llvm-build/Release+Asserts/bin/llvm-ar'), 't',
                           str(build / 'obj/third_party/opus/libopus.a')], capture_output=True, text=True,
                          check=True).stdout.split()
    ffmpeg_objects += [build / member for member in opus]
    inputs = [REPO / PATCH, MANIFEST_PATH, test, filters_ninja, media_ffmpeg_ninja,
              ffmpeg_ninja, llvm / 'clang++', *libraries, *ffmpeg_objects]
    receipt = {'scope': 'patched AudioToolboxAudioDecoder, ffmpeg_common.cc and FFmpeg ADTS demuxer/parser with '
                        'actual target flags, linked to completed FFmpeg/media/base objects, decoding afconvert '
                        'AAC; no GN/Ninja, browser, renderer or GPU process', 'commands': []}
    objects = results / 'objects'
    objects.mkdir(exist_ok=True)
    binary = results / 'aac_decoder_test'
    commands = [[str(llvm / 'clang++'), *decoder_flags, '-c', str(sources / (DECODER + '.cc')),
                 '-o', str(objects / 'audio_toolbox_audio_decoder.o')],
                [str(llvm / 'clang++'), *media_flags, '-c', str(sources / FFMPEG_COMMON),
                 '-o', str(objects / 'ffmpeg_common.o')],
                [str(llvm / 'clang++'), *media_flags, '-c', str(test), '-o', str(objects / 'aac_decoder_test.o')]]
    for unit in FFMPEG_UNITS:
        commands.append([str(llvm / 'clang'), *ffmpeg_flags, '-c', str(tree / 'third_party/ffmpeg' / unit),
                         '-o', str(objects / (Path(unit).stem + '.o'))])
    # FFmpeg's build includes aacdec.c through an autorename wrapper; its own
    # quoted includes resolve beside the original.
    commands.append([str(llvm / 'clang'), *ffmpeg_flags, '-I' + str(tree / FFMPEG_DEMUXER).rsplit('/', 1)[0],
                     '-c', str(sources / FFMPEG_DEMUXER), '-o', str(objects / 'autorename_libavformat_aacdec.o')])
    compiled = [command[-1] for command in commands]
    commands.append([str(llvm / 'clang++'), *link_flags, '-nostdlib++', *compiled, *map(str, ffmpeg_objects),
                     *map(str, libraries), '-framework', 'AudioToolbox', '-framework', 'CoreFoundation',
                     '-Wl,-rpath,' + str(build), '-o', str(binary)])
    for name, (container, data_format, source) in FIXTURES.items():
        commands.append(['/usr/bin/afconvert', '-f', container, '-d', data_format,
                         str(fixtures / source), str(fixtures / name)])
    for name in REFERENCES:
        commands.append(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEF32', str(fixtures / name),
                         str(fixtures / (name + '.wav'))])
    extract = len(commands)
    commands.append([str(binary), str(fixtures)])
    # Chromium's own parameters for a helper (content/browser/sandbox_parameters_mac.mm).
    darwin = {name: subprocess.run(['/usr/bin/getconf', name], capture_output=True, text=True,
                                   check=True).stdout.strip() for name in
              ('DARWIN_USER_CACHE_DIR', 'DARWIN_USER_DIR', 'DARWIN_USER_TEMP_DIR')}
    version = subprocess.run(['/usr/bin/sw_vers', '-productVersion'], capture_output=True, text=True,
                             check=True).stdout.strip().split('.')
    parameters = {'BROWSER_PID': '1', 'BUNDLE_ID': 'org.parc.codec-check',
                  'HELPER_BUNDLE_ID': 'org.parc.codec-check.helper', 'BUNDLE_PATH': str(results),
                  'EXECUTABLE_PATH': str(binary), 'USER_HOMEDIR_AS_LITERAL': str(Path.home().resolve()),
                  'LOG_FILE_PATH': '/dev/null', 'OS_VERSION': str(int(version[0]) * 100 + int(version[1])),
                  'DISABLE_SANDBOX_DENIAL_LOGGING': 'TRUE', 'ENABLE_LOGGING': 'FALSE',
                  'DISABLE_METAL_SHADER_CACHE': 'FALSE', 'RESTRICT_GPU_DARWIN_USER_DIRS': 'FALSE', **darwin}
    policies = tree / 'sandbox/policy/mac'
    for process, expectation in (('gpu', []), ('renderer', ['--expect-blocked'])):
        profile = results / f'{process}.sb'
        profile.write_bytes((policies / 'common.sb').read_bytes() + (policies / f'{process}.sb').read_bytes())
        inputs += [policies / 'common.sb', policies / f'{process}.sb']
        commands.append([str(binary), str(fixtures), '--seatbelt', str(profile), *expectation,
                         *[item for pair in parameters.items() for item in pair]])
    receipt['inputs'] = [{'path': str(p), 'sha256': sha(p)} for p in inputs]
    code = 0
    for i, command in enumerate(commands):
        if i == extract:
            for name, source in IMPLICIT_MP4.items():
                implicit_mp4(fixtures / source, fixtures / name)
            for name in [*FIXTURES, *IMPLICIT_MP4]:
                if name.endswith('.m4a'):
                    extract_mp4(fixtures / name, fixtures / (name[:-4] + '.mp4packets'))
            for name in REFERENCES:
                reference_pcm(fixtures / (name + '.wav'), fixtures / (name + '.pcm'))
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
    receipt['fixtures'] = {p.name: sha(p) for p in sorted(fixtures.iterdir())}
    receipt['exit_code'] = code
    (results / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return code


if __name__ == '__main__':
    raise SystemExit(main())

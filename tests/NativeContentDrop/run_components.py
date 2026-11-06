#!/usr/bin/env python3
"""Disposable native router/session fixtures; no browser or personal pasteboard."""
from pathlib import Path
import argparse, hashlib, json, subprocess, tempfile, time
parser = argparse.ArgumentParser()
parser.add_argument('kind', choices=['router', 'session'])
parser.add_argument('--receipt', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
hash_file = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
header = root / 'Engine/ParcNative/content_drop_router.h'
with tempfile.TemporaryDirectory(prefix='parc-native-drop-') as scratch:
    output = Path(scratch)
    if args.kind == 'router':
        files = [header, root / 'Engine/ParcNative/content_drop_router.mm', root / 'tests/NativeContentDrop/RouterTests.mm']
        vfs = output / 'headers.json'
        vfs.write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': str(output / 'ui/base/cocoa/content_drop_router.h'), 'external-contents': str(header)}]}))
        command = ['xcrun', 'clang++', '-std=c++20', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-ivfsoverlay', str(vfs), '-I' + str(output), '-I' + str(header.parent)] + [str(p) for p in files[1:]] + ['-framework', 'AppKit', '-o', str(output / 'check')]
    else:
        files = sorted((root / 'Sources/ParcCore').glob('*.swift')) + [root / 'Sources/ParcApp/LocalContentDrop.swift', root / 'Sources/ParcApp/ExternalSplitDropView.swift', root / 'Sources/ParcApp/SplitDropPlaceholderCard.swift', root / 'Sources/ParcApp/SadTabContent.swift', root / 'Sources/ParcApp/SidebarIconCatalog.swift', root / 'Sources/ParcApp/SplitDropGeometry.swift', root / 'Sources/ParcApp/SplitPaneHighlight.swift', root / 'Sources/ParcApp/ParcSplitView.swift', root / 'Sources/ParcApp/PageCardShadow.swift', root / 'Sources/ParcApp/SplitMarginHandle.swift', root / 'tests/NativeContentDrop/SessionTests.swift', header]
        native = root / 'Engine/ParcNative/content_drop_router.mm'
        bridge = root / 'Engine/ParcNative/content_drop_bridge.mm'
        bridge_header = root / 'Engine/ParcNative/content_drop_bridge.h'
        imports = output / 'imports.h'
        imports.write_text('#import \"' + str(header) + '\"\n#import \"' + str(bridge_header) + '\"\n')
        vfs = output / 'headers.json'
        vfs.write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': str(output / 'ui/base/cocoa/content_drop_router.h'), 'external-contents': str(header)}]}))
        native_command = ['xcrun', 'clang++', '-std=c++20', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-ivfsoverlay', str(vfs), '-I' + str(output), '-c', str(native), '-o', str(output / 'router.o')]
        native_result = subprocess.run(native_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if native_result.returncode:
            print(native_result.stdout.decode()); raise SystemExit(native_result.returncode)
        bridge_command = native_command.copy()
        bridge_command[bridge_command.index(str(native))] = str(bridge)
        bridge_command[-1] = str(output / 'bridge.o')
        bridge_result = subprocess.run(bridge_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if bridge_result.returncode:
            print(bridge_result.stdout.decode()); raise SystemExit(bridge_result.returncode)
        command = ['xcrun', 'swiftc', '-warnings-as-errors', '-whole-module-optimization', '-parse-as-library', '-import-objc-header', str(imports)] + [str(p) for p in files[:-1]] + [str(output / 'router.o'), str(output / 'bridge.o'), '-lc++', '-o', str(output / 'check')]
        files.extend([native, bridge, bridge_header])
    inputs = {str(p.relative_to(root)): hash_file(p) for p in files}
    start = time.monotonic()
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = result.stdout
    if result.returncode == 0:
        result = subprocess.run([str(output / 'check')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log += result.stdout
    unchanged = all(hash_file(root / path) == digest for path, digest in inputs.items())
    receipt = {'returncode': result.returncode, 'seconds': time.monotonic() - start, 'inputs': inputs, 'allInputsUnchanged': unchanged, 'command': command, 'output': log.decode()}
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
    print(log.decode(), end='')
    if not unchanged:
        raise SystemExit('Source changed during component check')
    raise SystemExit(result.returncode)

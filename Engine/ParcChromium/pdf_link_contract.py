#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

PDF_RESOURCES = 'chrome/browser/resources/pdf'
NAVIGATOR = f'{PDF_RESOURCES}/navigator.ts'
NEW_WINDOW_CASE = re.compile(
    r'case\s+WindowOpenDisposition\.NEW_WINDOW\s*:\s*'
    r'this\.navigatorDelegate_\.navigateInNewWindow\(\s*url\.href\s*\)\s*;')
NEW_WINDOW_METHOD = re.compile(
    r'navigateInNewWindow\(\s*url\s*:\s*string\s*\)\s*\{[^}]*?'
    r'chrome\.windows\.create\(\s*\{\s*url\s*:\s*url\s*\}\s*\)\s*;')
WINDOWS_CREATE = re.compile(r'chrome\.windows\.create\s*\(')


def check(chromium: Path):
    read_paths = []
    problems = []
    navigator = chromium / NAVIGATOR
    read_paths.append(navigator)
    if not navigator.is_file():
        problems.append(f'{NAVIGATOR} is missing')
    else:
        text = navigator.read_text(encoding='utf-8')
        if not NEW_WINDOW_CASE.search(text):
            problems.append(f'{NAVIGATOR} no longer sends a Shift-clicked link to '
                            'navigateInNewWindow')
        if not NEW_WINDOW_METHOD.search(text):
            problems.append(f'{NAVIGATOR} no longer opens a Shift-clicked link with '
                            'chrome.windows.create({url: url})')
    root = chromium / PDF_RESOURCES
    calls = 0
    if root.is_dir():
        read_paths.append(root)
        read_paths.extend(path for path in sorted(root.rglob('*')) if path.is_dir())
        for path in sorted(root.rglob('*.ts')):
            read_paths.append(path)
            calls += len(WINDOWS_CREATE.findall(path.read_text(encoding='utf-8')))
    if calls != 1:
        problems.append(f'{PDF_RESOURCES} calls chrome.windows.create {calls} times; Parc '
                        'treats every PDF viewer window request as a Shift-clicked link')
    return read_paths, problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--chromium', type=Path, required=True)
    parser.add_argument('--stamp', type=Path)
    parser.add_argument('--depfile', type=Path)
    args = parser.parse_args()
    try:
        read_paths, problems = check(args.chromium)
    except (OSError, UnicodeDecodeError) as error:
        print(f'Parc PDF link contract failed: {error}', file=sys.stderr)
        return 1
    if problems:
        print('Parc PDF link contract failed. Chromium changed how the PDF viewer opens a '
              'Shift-clicked link, which Parc turns into a Peek:', file=sys.stderr)
        for problem in problems:
            print(f'  - {problem}', file=sys.stderr)
        return 1
    if args.stamp:
        args.stamp.write_text('ok\n', encoding='utf-8')
    if args.depfile and args.stamp:
        inputs = ' '.join(str(path).replace(' ', '\\ ') for path in read_paths)
        args.depfile.write_text(f'{args.stamp}: {inputs}\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())

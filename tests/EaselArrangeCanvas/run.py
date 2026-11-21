#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/tests/easel-arrange-canvas'
out.mkdir(parents=True, exist_ok=True)
text = (root / 'scripts/test-easels.sh').read_text()
blocks = re.split(r'\n(?=xcrun swiftc )', text)
block = next(b for b in blocks if b.startswith('xcrun swiftc') and 'tests/EaselCanvasTests.swift' in b)
command = block.split('-o "')[0].replace('tests/EaselCanvasTests.swift', 'tests/EaselArrangeCanvas/Tests.swift')
spinner = subprocess.check_output(['python3', '-B', str(root / 'tests/Support/declarations.py'),
                                   str(out / 'ParcButtonSpinner.swift'), 'ParcButtonSpinner'], text=True).strip()
binary = out / 'arrange-canvas'
script = 'set -euo pipefail\nrepo_root="%s"\nspinner="%s"\n%s -warnings-as-errors -o "%s"\n' % (
    root, spinner, command.rstrip().rstrip('\\').rstrip(), binary)
compiled = subprocess.run(['bash', '-c', script])
if compiled.returncode != 0:
    sys.exit(compiled.returncode)
sys.exit(subprocess.run([str(binary)]).returncode)

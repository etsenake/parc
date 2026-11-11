#!/usr/bin/env python3
"""Embed the component manifest without startup disk I/O."""
import base64
import hashlib
import json
from pathlib import Path
import sys

manifest = Path(sys.argv[1]).read_text(encoding="utf-8")
key = json.loads(manifest)["key"]
digest = hashlib.sha256(base64.b64decode(key, validate=True)).hexdigest()[:32]
extension_id = "".join(chr(ord("a") + int(n, 16)) for n in digest)
if extension_id != "nncglbbjcndfbjaofnljgecleghcjohe":
    raise ValueError("Internal extension key changed; update exact-ID admission deliberately")
if ')ParcExtension"' in manifest:
    raise ValueError("Manifest contains the C++ literal delimiter")
output = Path(sys.argv[2])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(
    '// Generated from the internal component manifest.\n'
    '#ifndef PARC_INTERNAL_EXTENSION_MANIFEST_H_\n'
    '#define PARC_INTERNAL_EXTENSION_MANIFEST_H_\n'
    'namespace parc {\n'
    'inline constexpr char kInternalExtensionManifest[] = R"ParcExtension('
    + manifest + ')ParcExtension";\n}\n#endif\n', encoding="utf-8")

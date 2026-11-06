"""Verify an interrupted sealing stage without rewriting its engine or receipt."""
import json
from pathlib import Path
import sys
import build

if __name__ == '__main__':
    source, manifest, engine = map(Path, sys.argv[1:])
    with build.engine_lock(engine):
        value = json.loads(manifest.read_text())
        build.verify_manifest(value, engine, source)
        build.require_package_purpose('distribution', value, identity='selected-certificate', configuration='release')

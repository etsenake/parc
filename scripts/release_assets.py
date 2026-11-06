"""Reconcile an interrupted GitHub asset upload without replacing released bytes."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def reconcile(tag, commit, paths):
    release = json.loads(subprocess.check_output(["gh", "api", "repos/etsenake/parc/releases/tags/" + tag], text=True))
    if release["target_commitish"] != commit:
        raise ValueError("Release source commit differs from the frozen package")
    assets = {item["name"]: item for item in release["assets"]}
    for path in map(Path, paths):
        with path.open("rb") as stream:
            digest = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
        if path.name in assets:
            if assets[path.name].get("digest") != digest:
                raise ValueError("Existing released asset differs; immutable asset preserved: " + path.name)
        else:
            subprocess.run(["gh", "release", "upload", tag, str(path), "--repo", "etsenake/parc"], check=True)


if __name__ == "__main__":
    reconcile(sys.argv[1], sys.argv[2], sys.argv[3:])

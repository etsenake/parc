#!/usr/bin/env python3
"""Read-only validation of real overlay sources and pinned patch preimages."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib

REPO = Path(__file__).resolve().parents[3]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path,
                        help="Pristine pinned Chromium src directory; never modified")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    spec = importlib.util.spec_from_file_location("engine_source", REPO / "scripts/engine-source.py")
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    manifest = json.loads((REPO / "Engine/ParcHost/overlay.json").read_text())
    lock = json.loads((REPO / "Engine/source-lock.json").read_text())
    assert manifest["upstream"] == {key: lock[key]["commit"] for key in ["cef", "chromium"]}
    targets = set()
    for entry in manifest["files"]:
        assert entry["target"] not in targets
        targets.add(entry["target"])
        data = (REPO / entry["source"]).read_bytes()
        assert sha(data) == entry["sha256"], entry["source"]
        data.decode("utf-8")
        if entry["source"].endswith(".plist.in"):
            plistlib.loads(data)
        assert not (source / entry["target"]).exists(), entry["target"]
    for patch in manifest["patches"]:
        data = (REPO / patch["source"]).read_bytes()
        assert sha(data) == patch["sha256"]
        originals = {}
        for item in patch["files"]:
            assert item["target"] not in targets
            targets.add(item["target"])
            raw = (source / item["target"]).read_bytes()
            assert sha(raw) == item["before_sha256"], item["target"]
            originals[item["target"]] = raw
        outputs = engine.apply_context_patch(data.decode("utf-8"), originals)
        for item in patch["files"]:
            assert sha(outputs[item["target"]]) == item["after_sha256"], item["target"]
    print(f"PASS: {len(manifest['files'])} owned files, {len(targets) - len(manifest['files'])} exact source patches; no external writes")


if __name__ == "__main__":
    main()

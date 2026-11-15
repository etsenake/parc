# Adapted from Ardia's scripts/lib/app-copy.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

INJECTION_ENTITLEMENTS = ("com.apple.security.cs.allow-dyld-environment-variables",
                          "com.apple.security.cs.disable-library-validation")
COPY_NAME = "Parc.app"
ENTITLEMENTS_NAME = "entitlements.plist"


def installed(path: str) -> bool:
    return path.startswith("/Applications/")


def source_of(app) -> Path:
    refusal = f"{app} is installed in /Applications: pass a build or a copy"
    if installed(os.path.abspath(app)):
        raise ValueError(refusal)
    source = os.path.realpath(app, strict=True)
    if installed(source):
        raise ValueError(refusal)
    return Path(source)


def refuse_overlap(source: Path, directory) -> None:
    target = Path(os.path.realpath(directory))
    if target == source or target in source.parents or source in target.parents:
        raise ValueError(f"{directory} and {source} overlap: pick a folder outside the app for its copy")


def authority(details: str) -> str:
    match = re.search(r"^Authority=(.+)$", details, re.MULTILINE)
    return match.group(1) if match else "-"


def granted_entitlements(xml: bytes) -> dict:
    return plistlib.loads(xml) if xml.strip() else {}


def missing_entitlements(granted: dict, wanted) -> list[str]:
    return [key for key in wanted if key not in granted]


def merged_entitlements(granted: dict, missing) -> bytes:
    return plistlib.dumps({**granted, **{key: True for key in missing}}, fmt=plistlib.FMT_XML)


def signing_plan(xml: bytes, wanted) -> bytes | None:
    granted = granted_entitlements(xml)
    missing = missing_entitlements(granted, wanted)
    return merged_entitlements(granted, missing) if missing else None


def clone_command(source: Path, copy: Path) -> list[str]:
    return ["cp", "-cR", str(source), str(copy)]


def entitlements_command(app: Path) -> list[str]:
    return ["codesign", "-d", "--entitlements", "-", "--xml", str(app)]


def details_command(app: Path) -> list[str]:
    return ["codesign", "-dvv", str(app)]


def sign_command(identity: str, plist: Path, copy: Path) -> list[str]:
    return ["codesign", "--force", "--sign", identity, "--timestamp=none", "--options", "runtime",
            "--entitlements", str(plist), str(copy)]


def signing_identity(app) -> str:
    return authority(subprocess.run(details_command(Path(app)), capture_output=True, text=True).stderr)


def clear(directory: Path) -> None:
    if directory.is_symlink() or directory.is_file():
        directory.unlink()
    elif directory.is_dir():
        shutil.rmtree(directory)


def prepare_app(app, directory, entitlements=()) -> Path:
    source = source_of(app)
    directory = Path(directory)
    refuse_overlap(source, directory)
    copy = directory / COPY_NAME
    clear(directory)
    directory.mkdir(parents=True)
    subprocess.run(clone_command(source, copy), check=True)
    granted = subprocess.run(entitlements_command(source), check=True, capture_output=True).stdout
    plan = signing_plan(granted, entitlements)
    if plan is None:
        return copy
    plist = directory / ENTITLEMENTS_NAME
    plist.write_bytes(plan)
    subprocess.run(sign_command(signing_identity(source), plist, copy), check=True)
    return copy

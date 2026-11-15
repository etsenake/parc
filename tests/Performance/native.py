# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs and native-bench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
NATIVE = HERE / "native"
TOOLS = ROOT / "build" / "perf-tools"

SWIFT = (".swift",)
DYLIB = (".m", ".c")
SOURCE = "{source}"
OUTPUT = "{output}"


def output_name(name: str, source: Path) -> str:
    if source.suffix in SWIFT:
        return name
    if source.suffix in DYLIB:
        return f"{name}.dylib"
    raise ValueError(f"{source}: no native build for {source.suffix or 'a file without a suffix'}")


def command_templates(source: Path) -> list[list[str]]:
    if source.suffix in SWIFT:
        return [["swiftc", "-O", SOURCE, "-o", OUTPUT]]
    if source.suffix == ".m":
        link = ["clang", "-dynamiclib", "-fobjc-arc", "-framework", "AppKit", "-framework", "QuartzCore",
                "-arch", "arm64", SOURCE, "-o", OUTPUT]
    elif source.suffix == ".c":
        link = ["clang", "-dynamiclib", "-arch", "arm64", SOURCE, "-o", OUTPUT]
    else:
        raise ValueError(f"{source}: no native build for {source.suffix or 'a file without a suffix'}")
    return [link, ["codesign", "--force", "--sign", "-", OUTPUT]]


def build_commands(source: Path, output: Path) -> list[list[str]]:
    fill = {SOURCE: str(source), OUTPUT: str(output)}
    return [[fill.get(part, part) for part in command] for command in command_templates(source)]


def cache_key(source_text: bytes, templates: list[list[str]]) -> str:
    digest = hashlib.sha256(source_text)
    for command in templates:
        digest.update(b"\0" + "\x1f".join(command).encode())
    return digest.hexdigest()


def stamp_path(binary: Path) -> Path:
    return binary.with_name(binary.name + ".sha256")


def is_current(binary: Path, key: str) -> bool:
    stamp = stamp_path(binary)
    return binary.is_file() and stamp.is_file() and stamp.read_text().strip() == key


def compiled(name: str, source: Path) -> Path:
    source = Path(source).resolve()
    tools = Path(TOOLS)
    binary = tools / output_name(name, source)
    templates = command_templates(source)
    key = cache_key(source.read_bytes(), templates)
    if is_current(binary, key):
        return binary
    tools.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix=f".{name}-", dir=tools))
    try:
        built = scratch / binary.name
        for command in build_commands(source, built):
            subprocess.run(command, check=True)
        os.replace(built, binary)
        stamp_path(binary).write_text(key + "\n")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return binary


def dylib(name: str, source: Path) -> Path:
    if Path(source).suffix not in DYLIB:
        raise ValueError(f"{source}: an injected library is built from .m or .c")
    return compiled(name, source)

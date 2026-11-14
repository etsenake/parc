#!/usr/bin/env python3
"""Seal an owned engine, then compile/package Parc. Never launches it."""
from __future__ import annotations

import argparse
import contextlib
import ctypes
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
version_spec = importlib.util.spec_from_file_location("parc_app_version", Path(__file__).with_name("app_version.py"))
app_version = importlib.util.module_from_spec(version_spec)
version_spec.loader.exec_module(app_version)
icon_spec = importlib.util.spec_from_file_location("parc_app_icons", Path(__file__).with_name("app_icons.py"))
app_icons = importlib.util.module_from_spec(icon_spec)
icon_spec.loader.exec_module(app_icons)
whats_new_spec = importlib.util.spec_from_file_location("parc_whats_new", Path(__file__).with_name("whats_new.py"))
whats_new = importlib.util.module_from_spec(whats_new_spec)
whats_new_spec.loader.exec_module(whats_new)
vmp_spec = importlib.util.spec_from_file_location("parc_widevine_vmp", Path(__file__).with_name("widevine_vmp.py"))
widevine_vmp = importlib.util.module_from_spec(vmp_spec)
vmp_spec.loader.exec_module(widevine_vmp)
sparkle_spec = importlib.util.spec_from_file_location("parc_sparkle", Path(__file__).with_name("sparkle.py"))
sparkle = importlib.util.module_from_spec(sparkle_spec)
sparkle_spec.loader.exec_module(sparkle)
WIDEVINE_KEY_PASSPHRASE = widevine_vmp.PASSPHRASE_VARIABLE
FRAMEWORK = "Chromium Embedded Framework.framework"
ENGINE_NAME = "Chromium Embedded Framework"
PUBLIC_SYMBOLS = {
    "_PCCreateNativeContentDropRouter",
    "_parc_engine_execute_process", "_parc_engine_initialize",
    "_parc_engine_run_message_loop", "_parc_engine_request_quit_when_idle",
    "_parc_engine_quit_message_loop_if_idle", "_parc_engine_shutdown_if_idle",
    "_OBJC_CLASS_$_PCNativePage", "_OBJC_CLASS_$_PCNativeBrowserWindow",
    "_OBJC_CLASS_$_PCNativePageHost", "_OBJC_CLASS_$_PCNativeApplication",
    "_OBJC_CLASS_$_PCNativeBrowserApplication", "_OBJC_CLASS_$_PCNativeRendererCrash",
}
CDM_HELPER = " (CDM)"
HELPERS = (("", "", False), (" (Renderer)", ".renderer", True),
           (" (GPU)", "", True), (" (Alerts)", ".alerts", False), (CDM_HELPER, ".cdm", False),
           (" (Aperitif)", "", False), (" (Aperitif Renderer)", ".renderer", True),
           (" (Aperitif GPU)", "", True))
PROOF_FILES = (
    "content/public/app/mac_helpers.gni",
    "chrome/app/helper-renderer-entitlements.plist",
    "chrome/app/helper-gpu-entitlements.plist", "chrome/app/app-entitlements.plist",
    "ui/gl/features.gni", "ui/gl/BUILD.gn",
)
CHROMIUM_USAGE_DESCRIPTIONS = "chrome/tools/build/mac/infoplist_strings_util.cc"
PINNED_INPUTS = (("chromium", "LICENSE"),
                 ("chromium", "chrome/app/app-entitlements.plist"),
                 ("chromium", CHROMIUM_USAGE_DESCRIPTIONS))
RELEASE_FRAMEWORK = "Parc.app/Contents/Frameworks/" + FRAMEWORK
SPARKLE = "Sparkle.framework"
LOAD_COMMANDS = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
                 "LC_LOAD_UPWARD_DYLIB", "LC_LAZY_LOAD_DYLIB"}
MACH_MAGIC = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe",
              b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


class Refusal(RuntimeError):
    pass


def run(*args: object, capture: bool = True) -> str:
    cmd = [str(a) for a in args]
    if capture:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.PIPE)
    subprocess.check_call(cmd)
    return ""


def progress(message: str) -> None:
    print(message, flush=True)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative(value: str) -> Path:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or any(p in {".", ".."} for p in value.split("/")):
        raise Refusal(f"Invalid relative path: {value}")
    return Path(*path.parts)


def explicit_path(value: str | Path) -> Path:
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts:
        raise Refusal(f"Use an absolute path without '..': {path}")
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise Refusal(f"Symlinked path/ancestor is not allowed: {path}")
    return path


def inside(path: Path, root: Path) -> Path:
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(root.resolve(strict=True)):
        raise Refusal(f"Path escapes its source root: {path}")
    return resolved


def is_macho(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(4) in MACH_MAGIC


def parse_macho(output: str) -> dict:
    result = {"loads": [], "rpaths": [], "id": None}
    command = None
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            command = line[4:]
        elif command in LOAD_COMMANDS | {"LC_ID_DYLIB"} and line.startswith("name "):
            value = line[5:].rsplit(" (offset ", 1)[0]
            if command == "LC_ID_DYLIB":
                result["id"] = value
            else:
                result["loads"].append(value)
        elif command == "LC_RPATH" and line.startswith("path "):
            result["rpaths"].append(line[5:].rsplit(" (offset ", 1)[0])
    return result


def macho_layout(path: Path) -> dict:
    file_size = path.stat().st_size
    with path.open("rb") as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise Refusal(f"Truncated Mach-O header: {path}")
        magic, cpu, _, file_type, count, size, _, _ = struct.unpack("<8I", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C:
            raise Refusal(f"Expected a thin little-endian ARM64 Mach-O: {path}")
        if size > file_size - 32 or count > size // 8:
            raise Refusal(f"Mach-O load commands exceed file bounds: {path}")
        table = stream.read(size)
    commands, segments = [], []
    offset = 0
    for _ in range(count):
        if offset + 8 > size:
            raise Refusal(f"Truncated Mach-O load command: {path}")
        command, command_size = struct.unpack_from("<II", table, offset)
        if command_size < 8 or command_size % 8 or command_size > size - offset:
            raise Refusal(f"Invalid Mach-O load command size: {path}")
        raw = table[offset:offset + command_size]
        commands.append((command, raw))
        if command == 0x19:
            if command_size < 72:
                raise Refusal(f"Truncated Mach-O segment: {path}")
            (_, _, name, vmaddr, vmsize, fileoff, filesize, _, _, sections, _) = struct.unpack_from("<II16sQQQQiiII", raw)
            name = name.rstrip(b"\0")
            if command_size != 72 + sections * 80:
                raise Refusal(f"Invalid Mach-O section table: {path}")
            if fileoff > file_size or filesize > file_size - fileoff or filesize > vmsize:
                raise Refusal(f"Mach-O segment exceeds file/VM bounds: {path}")
            for index in range(sections):
                section = struct.unpack_from("<16s16sQQ8I", raw, 72 + index * 80)
                address, length, start, flags = section[2], section[3], section[4], section[8]
                if address < vmaddr or length > vmsize or address - vmaddr > vmsize - length:
                    raise Refusal(f"Mach-O section exceeds VM bounds: {path}")
                if flags & 0xFF not in {1, 0xC, 0x12}:
                    if start < fileoff or length > filesize or start - fileoff > filesize - length:
                        raise Refusal(f"Mach-O section exceeds segment bounds: {path}")
                    if length and start < 32 + size:
                        raise Refusal(f"Mach-O section overlaps load commands: {path}")
            segments.append({"name": name, "fileoff": fileoff, "filesize": filesize,
                             "vmsize": vmsize, "sections": sections})
        offset += command_size
    if offset != size:
        raise Refusal(f"Mach-O command count/size mismatch: {path}")
    text = [segment for segment in segments if segment["name"] == b"__TEXT"]
    if len(text) != 1 or text[0]["fileoff"] != 0 or text[0]["filesize"] < 32 + size:
        raise Refusal(f"Mach-O header/load commands do not fit __TEXT: {path}")
    ranges = sorted((s["fileoff"], s["fileoff"] + s["filesize"]) for s in segments if s["filesize"])
    if any(a[1] > b[0] for a, b in zip(ranges, ranges[1:])):
        raise Refusal(f"Overlapping Mach-O file-backed segments: {path}")
    return {"header": header, "table": table, "commands": commands, "file_type": file_type,
            "sectionless_dylib": file_type == 6 and text[0]["sections"] == 0}


def inspect_macho(path: Path) -> dict:
    macho_layout(path)
    if run("/usr/bin/lipo", "-archs", path).strip() != "arm64":
        raise Refusal(f"Expected an ARM64-only image: {path}")
    return parse_macho(run("/usr/bin/otool", "-m", "-l", path))


def system_library(value: str) -> bool:
    return value.startswith(("/System/Library/", "/usr/lib/"))


def exported_symbols(path: Path) -> set[str]:
    return set(run("/usr/bin/nm", "-gUj", path).splitlines())


def require_exports(symbols: set[str]) -> None:
    missing = PUBLIC_SYMBOLS - symbols
    if missing:
        raise Refusal("Engine lacks the actual native bridge exports: " + ", ".join(sorted(missing)))


def resolve_dependency(value: str, image: Path, info: dict, root: Path, *, output_fallback=True) -> Path | None:
    if system_library(value):
        return None
    candidates: list[Path] = []
    if value.startswith("@loader_path/"):
        candidates = [image.parent / value[len("@loader_path/"):]]
    elif value.startswith("@rpath/"):
        tail = value[len("@rpath/"):]
        for rpath in info["rpaths"]:
            if rpath == "@loader_path" or rpath.startswith("@loader_path/"):
                candidates.append(image.parent / rpath.replace("@loader_path", ".", 1) / tail)
            elif rpath.startswith("/"):
                candidates.append(Path(rpath) / tail)
        if output_fallback:
            candidates.append(root / tail)
    elif value.startswith("/"):
        candidates = [Path(value)]
    valid = set()
    for candidate in candidates:
        if candidate.exists():
            resolved = candidate.resolve()
            if not resolved.is_relative_to(root.resolve()):
                raise Refusal(f"Non-system dependency escapes engine output: {value}")
            valid.add(resolved)
    if len(valid) != 1:
        raise Refusal(f"Unresolved/ambiguous dependency {value!r} from {image}")
    return valid.pop()


def dependency_closure(root: Path, seeds: list[Path], inspect=inspect_macho) -> dict:
    pending = list(seeds)
    images = {}
    while pending:
        image = inside(pending.pop(), root)
        key = image.relative_to(root).as_posix()
        if key in images:
            continue
        if not is_macho(image):
            raise Refusal(f"Dependency is not Mach-O: {image}")
        info = inspect(image)
        loads = {}
        for value in info["loads"]:
            target = resolve_dependency(value, image, info, root)
            if target is not None:
                loads[value] = target.relative_to(root).as_posix()
                pending.append(target)
        images[key] = {**info, "resolved": loads}
    return dict(sorted(images.items()))


def inventory_tree(root: Path) -> dict:
    records = {}
    for path in sorted(root.rglob("*")):
        name = path.relative_to(root).as_posix()
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            target = os.readlink(path)
            if os.path.isabs(target):
                raise Refusal(f"Absolute symlink in source bundle: {path}")
            inside(path, root)
            records[name] = {"symlink": target}
        elif path.is_file():
            records[name] = {"sha256": sha(path), "mode": mode}
        elif not path.is_dir():
            raise Refusal(f"Unsupported filesystem entry: {path}")
    return records


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def overlay_path(repo: Path) -> Path:
    return repo / "Engine/ParcHost/overlay.json"


def check_helper_contract(source: Path) -> None:
    content = (source / "content/public/app/mac_helpers.gni").read_text()
    block = content.split("content_mac_helpers = [", 1)[1].split("\n]", 1)[0]
    actual = re.findall(r'\[\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,?\s*\]', block)
    if actual != [("default", "", ""), ("renderer", ".renderer", " (Renderer)"), ("gpu", "", " (GPU)")]:
        raise Refusal("Pinned content helper variants changed; review packaging")
    block = content.split("content_mac_aperitif_helpers = [", 1)[1].split("\n]", 1)[0]
    actual = re.findall(r'\[\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,?\s*\]', block)
    if actual != [("aperitif", "", " (Aperitif)"), ("aperitif_renderer", ".renderer", " (Aperitif Renderer)"),
                  ("aperitif_gpu", "", " (Aperitif GPU)")]:
        raise Refusal("Pinned Aperitif helper variants changed; review packaging")
    helper = (source / "parc/helper/BUILD.gn").read_text()
    if 'executable("parc_helper")' not in helper or '"//content/public/app:aperitif"' not in helper:
        raise Refusal("Direct engine helper target or its Aperitif sandbox library is missing")
    client = (source / "parc/parc_content_clients.mm").read_text()
    bundle = (source / "parc/parc_bundle_mac.mm").read_text()
    constants = (source / "chrome/common/chrome_constants.cc").read_text()
    if (f'kMacHelperSuffixCdm[] = "{CDM_HELPER}";' not in client or
            "SetCdmServiceChildFlags(" not in client or
            "HelperExecutablePath(chrome::kMacHelperSuffixAlerts)" not in client or
            '" Helper"' not in bundle or
            'kMacHelperSuffixAlerts[] = " (Alerts)";' not in constants):
        raise Refusal("Direct engine CDM or Alerts helper routing is missing")


def source_verifier(repo: Path):
    spec = importlib.util.spec_from_file_location("parc_source_verifier", repo / "scripts/engine-source.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_source_baseline(repo: Path, workspace: Path, lock: dict, state: dict) -> None:
    module = source_verifier(repo)
    try:
        module.verify_workspace(workspace, lock, state,
                                module.environment(workspace, lock, state["symbol_level"]) | module.READ_ONLY_GIT)
    except module.Refusal as error:
        raise Refusal(str(error)) from error


def verify_workspace(engine: Path, repo: Path) -> tuple[Path, dict]:
    engine = explicit_path(engine)
    source = engine.parent.parent
    workspace = source.parent.parent
    lock_path = repo / "Engine/source-lock.json"
    lock = read_json(lock_path)
    module = source_verifier(repo)
    shipping = engine.name == module.SHIPPING_CONFIGURATION
    configuration = module.SHIPPING_CONFIGURATION if shipping else lock["build"]["configuration"]
    if engine != workspace / "chromium/src/out" / configuration:
        raise Refusal("Engine directory is not the locked configuration of an owned source workspace")
    state = read_json(workspace / ".parc-engine-source.json")
    if (state.get("schema_version") != 1 or state.get("workspace") != str(workspace)
            or state.get("phase") not in ({"generated", "built"} if shipping else {"built"})
            or state.get("lock_sha256") != sha(lock_path)):
        raise Refusal("A successful engine-source.py build with the current source lock is required")
    shipping_proof = None
    if shipping:
        try:
            module.verify_shipping_build(workspace, sha(lock_path), state)
        except module.Refusal as error:
            raise Refusal(str(error)) from error
        shipping_proof = sha(workspace / module.SHIPPING_MARKER)
    reference = state.get("overlay", {})
    identity = sha(overlay_path(repo))
    if reference.get("identity") != identity:
        raise Refusal("Built engine does not match the repository's reviewed overlay")
    record_path = workspace / ".parc-overlays" / (identity + ".json")
    explicit_path(record_path)
    if sha(record_path) != reference.get("record_sha256"):
        raise Refusal("Recorded overlay digest changed")
    record = read_json(record_path)
    if record.get("identity") != identity:
        raise Refusal("Overlay identity mismatch")
    for target, item in record["targets"].items():
        path = source / relative(target)
        explicit_path(path)
        if sha(path) != item["output_sha256"] or stat.S_IMODE(path.stat().st_mode) != item["mode"]:
            raise Refusal(f"Applied source no longer matches completed build: {target}")
    header_names = ["native_engine_entry.h", "native_appkit_bridge.h", "native_application_protocols.h"]
    for name in header_names:
        target = "parc/native/" + name
        if target not in record["targets"] or sha(repo / "Engine/ParcNative" / name) != record["targets"][target]["output_sha256"]:
            raise Refusal(f"Public native ABI header is not in the completed overlay: {name}")
    verify_source_baseline(repo, workspace, lock, state)
    check_helper_contract(source)
    args_path = engine / "args.gn"
    generated_args = dict(re.findall(r'^([A-Za-z0-9_]+)\s*=\s*([^\n]+)$', args_path.read_text(), re.M))
    expected_args = {"target_cpu": '"arm64"', "is_component_build": "false" if shipping else "true",
                     "is_official_build": "true" if shipping else "false", "dcheck_always_on": "false",
                     "disable_fieldtrial_testing_config": "true", "proprietary_codecs": "true",
                     "ffmpeg_branding": '"Chromium"', "enable_ffmpeg_video_decoders": "false",
                     "media_use_openh264": "false", "enable_hangout_services_extension": "true",
                     "is_debug": "false", "enable_dsyms": "false", "symbol_level": str(state["symbol_level"])}
    if any(generated_args.get(k, "").strip() != v for k, v in expected_args.items()):
        raise Refusal("Generated engine configuration differs from the reviewed Release ARM64 build")
    proof_names = PROOF_FILES + (
        "parc/BUILD.gn", "parc/helper/BUILD.gn", "parc/helper/main.cc",
        "parc/parc_content_clients.mm", "parc/parc_bundle_mac.mm", "chrome/common/chrome_constants.cc")
    proof = {name: sha(source / name) for name in proof_names}
    proof["out/" + engine.name + "/args.gn"] = sha(args_path)
    gl_flags = engine / "gen/ui/gl/buildflags.h"
    static_angle = re.search(
        r"^#define BUILDFLAG_INTERNAL_USE_STATIC_ANGLE\(\) \(([01])\)$",
        gl_flags.read_text(), re.M)
    if not static_angle:
        raise Refusal("Generated ANGLE linkage mode is missing or invalid")
    proof["out/" + engine.name + "/gen/ui/gl/buildflags.h"] = sha(gl_flags)
    trial_flags = engine / "gen/components/variations/service/buildflags.h"
    if not re.search(r"^#define BUILDFLAG_INTERNAL_FIELDTRIAL_TESTING_ENABLED\(\) \(0\)$",
                     trial_flags.read_text(), re.M):
        raise Refusal("Generated engine still includes Chromium's field-trial testing config")
    proof["out/" + engine.name + "/gen/components/variations/service/buildflags.h"] = sha(trial_flags)
    return source, {"source_lock_sha256": sha(lock_path), "overlay": reference,
                    "source_fingerprint": state["source_fingerprint"],
                    "engine_build_flags": {name: json.loads(generated_args[name].strip())
                                           for name in expected_args},
                    "build_classification": "release-noncomponent" if shipping else "development-component",
                    "distribution_eligible": shipping,
                    **({"shipping_build_receipt_sha256": shipping_proof} if shipping else {}),
                    "use_static_angle": static_angle.group(1) == "1",
                    "upstream": {name: lock[name]["commit"] for name in ("chromium", "depot_tools") if name in lock},
                    "proof_files": proof}


@contextlib.contextmanager
def engine_lock(engine: Path):
    path = engine.parent.parent.parent.parent / ".parc-operation.lock"
    explicit_path(path)
    with path.open("r") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise Refusal("Source workspace is busy; do not package a running build") from error
        yield


def make_manifest(engine: Path, repo: Path) -> dict:
    _, provenance = verify_workspace(engine, repo)
    return seal_framework(engine, provenance)


APERITIF = "libaperitif.dylib"
APERITIF_LOAD = "@loader_path/../../../" + FRAMEWORK + "/Libraries/" + APERITIF


def check_bootstrap_graph(images: dict, helper_name: str = "parc_helper") -> None:
    aperitif = FRAMEWORK + "/Versions/A/Libraries/" + APERITIF
    for name, info in images.items():
        if name not in {helper_name, aperitif, "libseatbelt.dylib"}:
            raise Refusal("Forbidden pre-sandbox dependency: " + name)
        for load in info["loads"]:
            if not system_library(load) and load not in {"@rpath/libseatbelt.dylib", APERITIF_LOAD}:
                raise Refusal("Forbidden pre-sandbox load: " + load)


def engine_helper(engine: Path) -> Path:
    helper = engine / "Parc Helper.app/Contents/MacOS/Parc Helper"
    if not helper.is_file():
        raise Refusal("GN helper is missing from the engine output")
    return inside(helper, engine)


def seal_framework(engine: Path, provenance: dict) -> dict:
    framework = engine / FRAMEWORK
    if os.path.lexists(framework / "Libraries/libcef_sandbox.dylib"):
        raise Refusal("Retired sandbox library remains in the engine output")
    files = inventory_tree(framework)
    main = inside(framework / ENGINE_NAME, framework)
    require_exports(exported_symbols(main))
    if main != (framework / "Versions/A" / ENGINE_NAME).resolve() or not (framework / "Versions/Current").is_symlink() or (framework / "Versions/Current").readlink() != Path("A"):
        raise Refusal("Direct framework must preserve the Versions/A layout")
    info = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "org.cef.framework" or info.get("CFBundleExecutable") != ENGINE_NAME:
        raise Refusal("Direct framework bundle identity changed")
    for required in ("resources.pak", "chrome_100_percent.pak", "chrome_200_percent.pak", "icudtl.dat"):
        if not (framework / "Resources" / required).is_file():
            raise Refusal(f"Incomplete framework resource: {required}")
    if not list((framework / "Resources").glob("*.lproj/locale.pak")):
        raise Refusal("Framework locale bundles are missing")
    if not (list((framework / "Resources").glob("v8_context_snapshot*.bin")) or
            (framework / "Resources/snapshot_blob.bin").is_file()):
        raise Refusal("Framework V8 startup snapshot is missing")
    runtime_libraries = [APERITIF, "libvk_swiftshader.dylib",
                         "libvulkan.dylib", "vk_swiftshader_icd.json"]
    if not provenance["use_static_angle"]:
        runtime_libraries += ["libEGL.dylib", "libGLESv2.dylib"]
    for name in runtime_libraries:
        if not (framework / "Libraries" / name).is_file():
            raise Refusal("Incomplete runtime graphics/sandbox library: " + name)
    seeds = [framework / name for name, item in files.items()
             if "sha256" in item and is_macho(framework / name)]
    bootstrap = {}
    helper = engine_helper(engine)
    helper_name = helper.relative_to(engine).as_posix()
    if not helper.stat().st_mode & 0o111:
        raise Refusal("GN helper is not executable")
    bootstrap = dependency_closure(engine, [helper])
    check_bootstrap_graph(bootstrap, helper_name)
    seeds.append(helper)
    images = dependency_closure(engine, seeds)
    extra = {}
    for name in images:
        if name == helper_name:
            continue
        if not name.startswith(FRAMEWORK + "/"):
            if any(part.endswith(".framework") for part in Path(name).parts):
                raise Refusal("Additional runtime framework requires an explicit resource-bundle mapping: " + name)
            path = engine / name
            extra[name] = {"sha256": sha(path), "mode": stat.S_IMODE(path.stat().st_mode)}
    if provenance["distribution_eligible"] and extra:
        raise Refusal("Non-component shipping framework has dependencies outside its bundle")
    return {"schema_version": 1, "engine_dir": str(engine), **provenance,
            "framework": files, "components": extra, "images": images,
            "engine_runtime": "chromium-direct", "helper": {"sha256": sha(helper), "image": helper_name,
                                                       "mode": stat.S_IMODE(helper.stat().st_mode)},
            "required_exports": sorted(PUBLIC_SYMBOLS)}


def verify_manifest(manifest: dict, engine: Path, repo: Path) -> None:
    if manifest.get("schema_version") != 1 or manifest.get("engine_dir") != str(engine):
        raise Refusal("Engine artifact manifest/output directory mismatch")
    if manifest != make_manifest(engine, repo):
        raise Refusal("Engine artifacts/source provenance changed after sealing")


def release_report(repo: Path, package: Path, *, local_test: bool = False) -> dict:
    report = read_json(package / "package-report.json")
    if (report.get("schema_version") != 1 or report.get("layout") != "standalone-app"
            or report.get("build_classification") != "release-noncomponent"
            or report.get("distribution_eligible") is not True
            or report.get("engine_build_flags", {}).get("is_component_build") is not False):
        raise Refusal("A release engine must come from a standalone non-component package")
    if report.get("widevine", {}).get("host_signatures") != "unsigned":
        raise Refusal("A release engine must not carry an earlier package's Widevine host signatures")
    if "local_test" in report.get("engine_release", {}):
        raise Refusal("A local test build is not a release engine")
    if report.get("source_lock_sha256") != sha(repo / "Engine/source-lock.json"):
        raise Refusal("The release engine was built from a different source lock than this checkout")
    if local_test:
        return report
    recorded = report["engine_build_flags"]
    for define in source_verifier(repo).SHIPPING_DEFINES.split():
        name, value = define.split("=", 1)
        if name in recorded and recorded[name] != json.loads(value):
            raise Refusal(f"The release engine was built with {name}={json.dumps(recorded[name])}, "
                          f"not the current shipping {value}")
    manifest_path = overlay_path(repo)
    if report.get("overlay", {}).get("identity") != sha(manifest_path):
        raise Refusal("The release engine was built from a different engine overlay than this checkout")
    overlay = read_json(manifest_path)
    for item in overlay["files"] + overlay.get("patches", []):
        if sha(repo / relative(item["source"])) != item["sha256"]:
            raise Refusal("Engine source changed without a new overlay: " + item["source"])
    return report


def verify_release_framework(package: Path, report: dict) -> None:
    framework = package / RELEASE_FRAMEWORK
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", framework)
    published = {name: digest for name, digest in report.get("signed_images", {}).items()
                 if name.startswith(RELEASE_FRAMEWORK + "/")}
    present = {path.relative_to(package).as_posix() for path in framework.rglob("*")
               if not path.is_symlink() and path.is_file() and is_macho(path)}
    if not published or set(published) != present:
        raise Refusal("Release framework code differs from its package report")
    for name, digest in published.items():
        if sha(package / name) != digest:
            raise Refusal("Release framework code differs from its package report: " + name)


def verify_release_helper(package: Path, report: dict) -> None:
    engine = package / "Parc.app/Contents/Frameworks"
    helper = engine_helper(engine)
    name = helper.relative_to(package).as_posix()
    if report.get("signed_images", {}).get(name) != sha(helper):
        raise Refusal("Release helper differs from its package report")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", helper.parent.parent.parent)


def pinned_source(repo: Path, workspace: Path, destination: Path) -> Path:
    lock = read_json(repo / "Engine/source-lock.json")
    overlay = read_json(overlay_path(repo))
    patched = {item["target"] for item in overlay["files"]}
    patched |= {item["target"] for patch in overlay.get("patches", []) for item in patch["files"]}
    chromium = explicit_path(workspace) / "chromium/src"
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    for repository, name in PINNED_INPUTS:
        if name in patched:
            raise Refusal("The overlay changes a pinned packaging input; build the engine instead: " + name)
        checkout, path = chromium, name
        result = subprocess.run(["git", "-C", str(checkout), "show", f"{lock[repository]['commit']}:{path}"],
                                capture_output=True, env=environment)
        if result.returncode:
            raise Refusal(f"{checkout} lacks {path} at the pinned {repository} commit: "
                          + result.stderr.decode(errors="replace").strip())
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(result.stdout)
    return destination


def app_engine_headers(repo: Path, source: Path) -> list[str]:
    output = run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=13.0", "-fobjc-arc", "-fblocks",
                 "-I", repo / "Engine/ParcNative", "-I", repo / "Sources/ParcEngine", "-DOS_MAC=1",
                 "-M", repo / "Sources/ParcEngine/ParcEngine.m")
    root = (repo / "Engine/ParcNative").resolve()
    application_protocols = root / "native_application_protocols.h"
    headers = {Path(token).resolve().relative_to(repo.resolve()).as_posix()
               for token in output.replace("\\\n", " ").split()
               if token.endswith(".h") and Path(token).resolve().is_relative_to(root)
               and Path(token).resolve() != application_protocols}
    if not headers:
        raise Refusal("Could not find the engine headers the app compiles against")
    return sorted(headers)


def changed_since(repo: Path, commit: str, names: list[str]) -> list[str]:
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    changed = []
    for name in names:
        result = subprocess.run(["git", "-C", str(repo), "show", f"{commit}:{name}"], capture_output=True,
                                env=environment)
        if result.returncode or result.stdout != (repo / name).read_bytes():
            changed.append(name)
    return changed


def release_manifest(engine: Path, report: dict, release: dict) -> dict:
    provenance = {name: report[name] for name in ("source_lock_sha256", "overlay", "engine_build_flags",
                                                  "build_classification", "distribution_eligible")}
    provenance["use_static_angle"] = not (engine / FRAMEWORK / "Libraries/libEGL.dylib").exists()
    return seal_framework(engine, {**provenance, "engine_release": release})


def release_engine(repo: Path, package: Path, workspace: Path, stage: Path, tag: str, commit: str,
                   *, local_test: bool = False, allow_changed_headers: bool = False):
    package = explicit_path(package)
    report = release_report(repo, package, local_test=local_test)
    verify_release_framework(package, report)
    verify_release_helper(package, report)
    licenses = [("Chromium-LICENSE.txt", "LICENSE")]
    for name, _ in licenses:
        if not (package / "Parc.app/Contents/Resources/EngineLicenses" / name).is_file():
            raise Refusal("Release package lacks its engine license: " + name)
    source = pinned_source(repo, workspace, stage)
    for name, original in licenses:
        if sha(package / "Parc.app/Contents/Resources/EngineLicenses" / name) != sha(source / original):
            raise Refusal("Release engine license differs from the pinned source: " + name)
    previous = report.get("engine_release", {})
    release = {"tag": tag, "commit": commit, "package_report_sha256": sha(package / "package-report.json"),
               "engine_origin": previous.get("engine_origin", {"tag": tag, "commit": commit})}
    if local_test:
        headers = app_engine_headers(repo, source)
        changed = changed_since(repo, commit, headers)
        if changed and not allow_changed_headers:
            raise Refusal(f"The app compiles against engine headers changed since {commit[:8]} "
                          f"({', '.join(changed)}); it needs a newer engine unless every new call is "
                          "guarded with respondsToSelector:, which --allow-changed-headers asserts")
        release["local_test"] = {"checkout_overlay": sha(overlay_path(repo)),
                                 "engine_api_headers": headers, "changed_headers_allowed": changed}
    engine = package / "Parc.app/Contents/Frameworks"
    manifest = release_manifest(engine, report, release)
    if manifest["components"]:
        raise Refusal("Release framework depends on code outside its bundle")

    def verify(sealed: dict, directory: Path, _repo: Path) -> None:
        if directory != engine or sealed != release_manifest(engine, report, release):
            raise Refusal("Release engine changed while packaging")
        verify_release_framework(package, report)
        verify_release_helper(package, report)
    return engine, source, manifest, verify


def development_engine_path(app: Path, name: str) -> Path:
    relative_path = relative(name)
    if relative_path.parts[0] == FRAMEWORK:
        return app / "Contents/Frameworks" / relative_path
    return app.parent / relative_path


def copy_engine(engine: Path, app: Path, manifest: dict) -> dict:
    framework = app / "Contents/Frameworks" / FRAMEWORK
    shutil.copytree(engine / FRAMEWORK, framework, symlinks=True)
    if inventory_tree(framework) != manifest["framework"]:
        raise Refusal("Copied framework differs from sealed engine")
    for name, expected in manifest["components"].items():
        target = development_engine_path(app, name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(engine / name, target)
        if sha(target) != expected["sha256"] or stat.S_IMODE(target.stat().st_mode) != expected["mode"]:
            raise Refusal("Copied component differs from sealed engine: " + name)
    return {development_engine_path(app, name).relative_to(app.parent).as_posix():
            sha(development_engine_path(app, name)) for name in manifest["images"] if name != manifest.get("helper", {}).get("image")}


def expand_loader_path(value: str, image: Path, executable: Path) -> Path:
    for prefix, parent in (("@loader_path", image.parent), ("@executable_path", executable.parent)):
        if value == prefix or value.startswith(prefix + "/"):
            return parent / value[len(prefix):].lstrip("/")
    if value.startswith("/"):
        return Path(value)
    raise Refusal(f"Unsupported loader path: {image}: {value}")


def resolve_development_dependency(value: str, image: Path, executable: Path,
                                   rpaths: list[Path], root: Path) -> Path | None:
    if system_library(value):
        return None
    if value.startswith("@rpath/"):
        tail = relative(value[len("@rpath/"):])
        candidates = [path / tail for path in rpaths]
    else:
        candidates = [expand_loader_path(value, image, executable)]
    for candidate in candidates:
        if system_library(str(candidate)):
            return None
        if candidate.exists():
            target = candidate.resolve(strict=True)
            if not target.is_relative_to(root):
                raise Refusal(f"Dependency escapes development directory: {image}: {value}: {target}")
            return target
    raise Refusal(f"Unresolved development dependency: {image}: {value}")


def verify_development_layout(app: Path, manifest: dict) -> dict:
    root = app.parent.resolve(strict=True)
    dependency_root = app.resolve(strict=True) if manifest.get("distribution_eligible") else root
    if manifest.get("distribution_eligible") and manifest["components"]:
        raise Refusal("A shipping application cannot depend on sibling components")
    images = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or not path.is_file() or not is_macho(path):
            continue
        if path.name == "libParcKeychain.dylib":
            raise Refusal("Superseded engine code is not a packaging input")
        images[inside(path, root)] = inspect_macho(path)
    expected = {}
    for name, sealed in manifest["images"].items():
        if name == manifest.get("helper", {}).get("image"):
            continue
        path = inside(development_engine_path(app, name), root)
        if images.get(path) != {key: sealed[key] for key in ("id", "loads", "rpaths")}:
            raise Refusal("Engine load commands changed during packaging: " + name)
        expected[path] = {load: inside(development_engine_path(app, target), root)
                          for load, target in sealed["resolved"].items()}
    main = app / "Contents/MacOS" / app.stem
    executables = [path for path in images if path.parent.name == "MacOS"
                   and macho_layout(path)["file_type"] == 2]
    if main not in executables:
        raise Refusal("Development application executable is missing")
    framework = inside(app / "Contents/Frameworks" / FRAMEWORK / ENGINE_NAME, root)
    sparkle_framework = (app / "Contents/Frameworks" / SPARKLE).resolve()
    for executable in executables:
        direct_helper = (executable.parent.parent.parent.name in {prefix + " Helper" + suffix + ".app"
                         for prefix in {"Parc", app.stem} for suffix, _, _ in HELPERS})
        if executable != main and not direct_helper and any(not system_library(v) for v in images[executable]["loads"]):
            raise Refusal("Helper directly links non-system code before sandbox initialization")
        visited = set()

        def visit(image: Path, inherited: tuple[Path, ...]) -> None:
            if image not in images:
                raise Refusal("Dependency is not an audited Mach-O: " + str(image))
            info = images[image]
            rpaths = tuple(dict.fromkeys(
                [expand_loader_path(v, image, executable).resolve() for v in info["rpaths"]] + list(inherited)))
            key = (image, rpaths)
            if key in visited:
                return
            visited.add(key)
            for value in info["loads"]:
                target = resolve_development_dependency(value, image, executable, rpaths, dependency_root)
                if ((image in expected and target != expected[image].get(value)) or
                        (direct_helper and image == executable and target != helper_expected.get(value))):
                    raise Refusal(f"Engine dependency changed during packaging: {image}: {value}")
                if target is not None:
                    visit(target, rpaths)

        if direct_helper:
            info = images[executable]
            check_bootstrap_graph({"parc_helper": info})
            helper_expected = {
                load: inside(development_engine_path(app, target), root)
                for load, target in manifest["images"][manifest["helper"]["image"]]["resolved"].items()}
            if info != {key: manifest["images"][manifest["helper"]["image"]][key] for key in ("id", "loads", "rpaths")}:
                raise Refusal("GN helper load commands changed during packaging")
        visit(executable, ())
        if (executable == (app / "Contents/MacOS/ParcRestart").resolve()
                or sparkle_framework in executable.parents):
            continue
        inherited = tuple(expand_loader_path(v, executable, executable).resolve()
                          for v in images[executable]["rpaths"])
        visit(framework, inherited)
        framework_paths = tuple(dict.fromkeys(
            [expand_loader_path(v, framework, executable).resolve() for v in images[framework]["rpaths"]]
            + list(inherited)))
        for image in expected:
            visit(image, framework_paths)
        if executable == main:
            for image in images:
                if image not in expected and image not in executables:
                    visit(image, inherited)
    return {path.relative_to(root).as_posix(): sha(path) for path in images}


def validate_output(output: Path, repo: Path, engine: Path) -> None:
    explicit_path(output)
    if output.suffix == ".app":
        raise Refusal("--output must name a fresh development directory, not an .app; "
                      "use --output /existing/parent/parc-dev to create the app and sibling libraries there")
    if output.exists():
        raise Refusal("Output already exists; choose a fresh development directory (no automatic deletion)")
    for protected in (engine, repo / "Sources", repo / "Engine", repo / "Resources"):
        if output.is_relative_to(protected) or protected.is_relative_to(output):
            raise Refusal("Output overlaps source/engine inputs")
    if not output.parent.is_dir():
        raise Refusal("Output parent must already exist")


def publish_development_directory(stage: Path, output: Path) -> None:
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(os.fsencode(stage), os.fsencode(output), 0x00000004) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(output))


def embed_sparkle(release: Path, frameworks: Path) -> Path:
    framework = frameworks / SPARKLE
    shutil.copytree(release / SPARKLE, framework, symlinks=True)
    if os.readlink(framework / "Versions/Current") != "B":
        raise Refusal("Unexpected Sparkle framework version layout")
    code = framework / "Versions/B"
    for name in ("Headers", "PrivateHeaders", "Modules", "XPCServices"):
        (framework / name).unlink()
        shutil.rmtree(code / name)
    for binary in (code / "Sparkle", code / "Autoupdate", code / "Updater.app/Contents/MacOS/Updater"):
        thin = binary.with_name(binary.name + ".arm64")
        run("/usr/bin/lipo", binary, "-thin", "arm64", "-output", thin)
        os.replace(thin, binary)
    return framework


def plist(path: Path, data: dict) -> None:
    path.write_bytes(plistlib.dumps(data))


def info_plist(name: str, bundle_id: str, version: dict) -> dict:
    return {"CFBundleDevelopmentRegion": "en", "CFBundleExecutable": name,
            "CFBundleIdentifier": bundle_id, "CFBundleName": name,
            "CFBundleDisplayName": name, "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version["version"], "CFBundleVersion": str(version["build"]),
            "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": True,
            "NSSupportsAutomaticGraphicsSwitching": True}


def require_package_purpose(purpose: str, manifest: dict | None = None,
                            identity: str = "-", configuration: str = "release") -> None:
    if purpose not in ("development", "distribution"):
        raise Refusal("Unsupported packaging purpose: " + purpose)
    if purpose == "distribution":
        if (manifest is None or manifest.get("build_classification") != "release-noncomponent"
                or manifest.get("distribution_eligible") is not True
                or manifest.get("engine_build_flags", {}).get("is_component_build") is not False
                or manifest.get("components")):
            raise Refusal("Distribution requires a sealed non-component shipping engine")
        if identity == "-" or not identity.strip() or configuration != "release":
            raise Refusal("Distribution requires certificate-backed signing and release application optimization")


def inside_git_checkout(path: Path) -> bool:
    if any(os.path.lexists(parent / ".git") for parent in path.parents):
        return True
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    try:
        result = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--is-inside-work-tree",
                                 "--is-inside-git-dir"], capture_output=True, text=True, env=environment)
    except FileNotFoundError:
        return False
    return result.returncode == 0 and "true" in result.stdout.split()


def widevine_signer(certificate: Path | None, private_key: Path | None, command: Path | None,
                    repo: Path = ROOT, *, passphrase: str | None = None):
    if command is not None and (certificate is not None or private_key is not None):
        raise Refusal("Use either --widevine-sign-command or a VMP certificate and key, not both")
    try:
        if command is not None:
            return widevine_vmp.CommandSigner(explicit_path(command))
        if certificate is None and private_key is None:
            return None
        if certificate is None or private_key is None:
            raise Refusal("A VMP certificate and its private key must be supplied together")
        certificate, private_key = explicit_path(certificate), explicit_path(private_key)
        if not certificate.is_file() or not private_key.is_file():
            raise Refusal("The VMP certificate and private key must be existing files")
        if private_key.is_relative_to(repo.resolve()) or inside_git_checkout(private_key):
            raise Refusal("Keep the VMP private key outside the repository and any other Git checkout")
        openssl = shutil.which("openssl")
        if openssl is None:
            raise Refusal("Signing with a VMP key needs openssl on PATH")
        return widevine_vmp.KeySigner(certificate, private_key, openssl, passphrase)
    except widevine_vmp.VmpError as error:
        raise Refusal(str(error)) from error


def require_widevine_signing(manifest: dict, signer) -> None:
    if signer is not None and (manifest.get("build_classification") != "release-noncomponent"
                               or manifest.get("components")):
        raise Refusal("Widevine host signatures need the non-component engine: in a component build the "
                      "media code that loads and verifies the CDM lives outside the signed framework")


def widevine_host_files(app: Path) -> list[tuple[Path, Path, int]]:
    framework = app / "Contents/Frameworks" / FRAMEWORK
    current = framework / "Versions/Current"
    version = os.readlink(current) if current.is_symlink() else ""
    if not version or "/" in version or version in {".", ".."}:
        raise Refusal("Engine framework lacks its versioned bundle layout")
    versioned = framework / "Versions" / version
    name = "Parc Helper" + CDM_HELPER
    helper = app / "Contents/Frameworks" / (name + ".app") / "Contents/MacOS" / name
    return [(versioned / ENGINE_NAME, versioned / "Resources" / (ENGINE_NAME + ".sig"), widevine_vmp.BLESSED),
            (helper, app / "Contents/Resources" / (name + ".sig"), 0)]


def widevine_host_signatures(app: Path, signer, team: str | None) -> dict:
    report = {"cdm": "downloaded by the component updater, not bundled",
              "cdm_helper": "Parc Helper" + CDM_HELPER,
              "helper_library_validation": ("disabled on every helper without a Team ID" if team is None else
                                            "disabled only on the CDM helper")}
    if signer is None:
        return {**report, "host_signatures": "unsigned",
                "unsigned_reason": "no VMP certificate or signing service was configured"}
    signatures = {}
    for binary, signature, flags in widevine_host_files(app):
        if signature.exists():
            raise Refusal("Widevine signature already exists: " + signature.name)
        before = sha(binary)
        try:
            signer.write(binary, signature, flags)
            info = widevine_vmp.verify(binary, signature.read_bytes(), flags)
        except widevine_vmp.VmpError as error:
            raise Refusal(f"Widevine host signature for {binary.name}: {error}") from error
        if sha(binary) != before:
            raise Refusal("The VMP signer changed the binary it signed: " + binary.name)
        signatures[signature.relative_to(app).as_posix()] = {"binary": binary.relative_to(app).as_posix(), **info}
    return {**report, "host_signatures": "signed", "signer": signer.kind,
            "certificate_chain_verified": False, "signatures": signatures}


def verify_widevine_signatures(app: Path, report: dict) -> None:
    for signature, item in report.get("signatures", {}).items():
        try:
            widevine_vmp.verify(app / item["binary"], (app / signature).read_bytes(), item["flags"])
        except widevine_vmp.VmpError as error:
            raise Refusal(f"Apple signing invalidated the Widevine signature {signature}: {error}") from error


def signing_team(identity: str, probe: Path) -> str | None:
    if identity == "-":
        return None
    run("/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none", probe)
    details = subprocess.run(["/usr/bin/codesign", "-dv", str(probe)], capture_output=True, text=True, check=True).stderr
    team = re.search(r"^TeamIdentifier=(.+)$", details, re.M)
    return None if team is None or team.group(1) == "not set" else team.group(1)


def build_app(repo: Path, engine: Path, manifest: dict, output: Path, identity: str,
              configuration: str = "release", *, purpose: str = "development", widevine=None,
              source: Path | None = None, verify=None, bundle_note: str | None = None) -> dict:
    verify = verify or verify_manifest
    source = engine.parent.parent if source is None else source
    require_package_purpose(purpose, manifest, identity, configuration)
    require_widevine_signing(manifest, widevine)
    if configuration not in ("debug", "release"):
        raise Refusal("Unsupported application configuration: " + configuration)
    validate_output(output, repo, engine)
    progress("packaging: verifying sealed engine")
    verify(manifest, engine, repo)
    try:
        version = app_version.read(repo)
    except ValueError as error:
        raise Refusal(str(error)) from error
    optimization = (["-g", "-Onone"] if configuration == "debug" else
                    ["-O", "-whole-module-optimization", "-num-threads", str(os.cpu_count() or 4)])
    for name in ("native_engine_entry.h", "native_appkit_bridge.h"):
        if not (repo / "Engine/ParcNative" / name).is_file():
            raise Refusal("Independent native engine source is not integrated")
    facade = repo / "Sources/ParcEngine/ParcEngine.m"
    if '"native_engine_entry.h"' not in facade.read_text():
        raise Refusal("Refusing to compile the superseded engine facade")
    protocols = repo / "Engine/ParcNative/native_application_protocols.h"
    if not protocols.is_file():
        raise Refusal("Required application protocol header is missing: " + str(protocols))
    progress(f"packaging: fetching Sparkle {sparkle.VERSION}")
    sparkle_release = sparkle.fetch(repo / "build/sparkle")
    with tempfile.TemporaryDirectory(prefix=".parc-package-", dir=output.parent) as temporary:
        stage = Path(temporary)
        development = stage / "development"
        app = development / "Parc.app"
        contents = app / "Contents"
        frameworks = contents / "Frameworks"
        (contents / "MacOS").mkdir(parents=True)
        frameworks.mkdir()
        resources = contents / "Resources"
        inventory_tree(repo / "Resources")
        progress("packaging: copying resources and engine framework")
        shutil.copytree(repo / "Resources", resources, symlinks=True)
        whats_new.write(repo, resources / "WhatsNew.html")
        icon_file = app_icons.package_app_icons(resources)
        copied_engine = copy_engine(engine, app, manifest)
        notices = resources / "EngineLicenses"
        notices.mkdir()
        shutil.copy2(source / "LICENSE", notices / "Chromium-LICENSE.txt")
        headers = repo / "Engine/ParcNative"
        common = ["-arch", "arm64", "-mmacosx-version-min=13.0", "-Wall", "-Wextra", "-Werror", "-O2"]
        progress("packaging: compiling native facade and helpers")
        run("xcrun", "clang", *common, "-Wno-unused-parameter", "-fobjc-arc", "-fblocks",
            "-I", headers, "-I", repo / "Sources/ParcEngine",
            "-DOS_MAC=1", "-c", facade, "-o", stage / "ParcEngine.o")
        run("xcrun", "clang", *common, "-Wno-unused-parameter", "-fobjc-arc", "-fblocks",
            "-I", headers, "-I", repo / "Sources/ParcEngine", "-c",
            repo / "Sources/ParcEngine/VideoPiPWindow.m", "-o", stage / "VideoPiPWindow.o")
        helper = engine / manifest["helper"]["image"]
        if {"sha256": sha(helper), "mode": stat.S_IMODE(helper.stat().st_mode), "image": manifest["helper"]["image"]} != manifest["helper"]:
            raise Refusal("GN helper differs from sealed engine")
        shutil.copy2(helper, stage / "Parc Helper")
        dock_plugin = contents / "PlugIns/ParcDockTile.plugin"
        (dock_plugin / "Contents/MacOS").mkdir(parents=True)
        run("xcrun", "clang", *common, "-fobjc-arc", "-fblocks", "-bundle",
            "-framework", "AppKit", repo / "Sources/ParcDockTile/ParcDockTile.m",
            "-o", dock_plugin / "Contents/MacOS/ParcDockTile")
        plugin_info = info_plist("ParcDockTile", "org.parc.Browser.DockTile", version)
        plugin_info.update(CFBundlePackageType="BNDL", NSPrincipalClass="ParcDockTile")
        plist(dock_plugin / "Contents/Info.plist", plugin_info)
        helper_apps = []
        for suffix, id_suffix, jit in HELPERS:
            name = "Parc Helper" + suffix
            helper = frameworks / (name + ".app")
            (helper / "Contents/MacOS").mkdir(parents=True)
            shutil.copy2(stage / "Parc Helper", helper / "Contents/MacOS" / name)
            info = info_plist(name, "org.parc.Browser.helper" + id_suffix, version)
            info.update(LSUIElement=True, LSFileQuarantineEnabled=True,
                        LSEnvironment={"MallocNanoZone": "0"})
            if id_suffix == ".alerts":
                info["NSUserNotificationAlertStyle"] = "alert"
                helper_resources = helper / "Contents/Resources"
                helper_resources.mkdir()
                shutil.copyfile(resources / icon_file, helper_resources / icon_file)
                info["CFBundleIconFile"] = icon_file
            plist(helper / "Contents/Info.plist", info)
            helper_apps.append((helper, jit, suffix == CDM_HELPER))
        run("xcrun", "clang", *common, repo / "Sources/ParcRestart/main.c",
            "-o", contents / "MacOS/ParcRestart")
        swift = sorted((repo / "Sources/ParcCore").glob("*.swift")) + sorted((repo / "Sources/ParcApp").glob("*.swift"))
        if not swift:
            raise Refusal("Native Swift application sources are missing")
        progress(f"packaging: compiling Swift app ({len(swift)} sources, swiftc -v)")
        run("xcrun", "swiftc", "-v", "-target", "arm64-apple-macos13.0", *optimization, "-I", headers,
            "-Xcc", "-DOS_MAC=1",
            "-import-objc-header", repo / "Sources/ParcEngine/ParcEngine.h", *swift,
            stage / "ParcEngine.o", stage / "VideoPiPWindow.o", "-F", frameworks, "-framework", ENGINE_NAME,
            "-F", sparkle_release, "-framework", "Sparkle", "-framework", "Cocoa", "-framework", "QuartzCore", "-framework", "AVFoundation", "-framework", "AVKit",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            "-o", contents / "MacOS/Parc", capture=False)
        sparkle_framework = embed_sparkle(sparkle_release, frameworks)
        progress("packaging: copying Swift runtime and signing")
        swift_runtime = stage / "swift-runtime"
        swift_runtime.mkdir()
        run("xcrun", "swift-stdlib-tool", "--copy", "--scan-executable", contents / "MacOS/Parc",
            "--platform", "macosx", "--destination", swift_runtime)
        for library in sorted(swift_runtime.iterdir()):
            if not library.is_file() or not library.name.startswith("libswift") or library.suffix != ".dylib":
                raise Refusal("Unexpected Swift runtime artifact: " + str(library))
            destination = frameworks / library.name
            if destination.exists():
                raise Refusal("Swift runtime collides with an engine dependency")
            architectures = run("/usr/bin/lipo", "-archs", library).split()
            if architectures == ["arm64"]:
                shutil.copy2(library, destination)
            elif "arm64" in architectures:
                run("/usr/bin/lipo", library, "-thin", "arm64", "-output", destination)
            else:
                raise Refusal("Swift runtime lacks ARM64: " + library.name)
        info = info_plist("Parc", "org.parc.Browser", version)
        info["ParcChromiumVersion"] = read_json(repo / "Engine/source-lock.json")["chromium"]["tag"]
        info.update(CFBundleIconFile=icon_file, NSDockTilePlugIn="ParcDockTile.plugin", NSPrincipalClass="ParcApplication", NSUserNotificationAlertStyle="banner",
                    NSAppleScriptEnabled=True, OSAScriptingDefinition="Parc.sdef", LSEnvironment={"MallocNanoZone": "0"},
                    CFBundleURLTypes=[{"CFBundleTypeRole": "Viewer", "CFBundleURLName": "Webpage URL",
                                       "CFBundleURLSchemes": ["http", "https"]}],
                    CFBundleDocumentTypes=[
                        {"CFBundleTypeName": "HTML document", "CFBundleTypeRole": "Viewer",
                         "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.html"],
                         "CFBundleTypeExtensions": ["html", "htm", "shtml"],
                         "CFBundleTypeMIMETypes": ["text/html"]},
                        {"CFBundleTypeName": "XHTML document", "CFBundleTypeRole": "Viewer",
                         "LSHandlerRank": "Alternate", "LSItemContentTypes": ["public.xhtml"],
                         "CFBundleTypeExtensions": ["xhtml", "xht"],
                         "CFBundleTypeMIMETypes": ["application/xhtml+xml"]}],
                    LSApplicationCategoryType="public.app-category.productivity",
                    NSUserActivityTypes=["NSUserActivityTypeBrowsingWeb"],
                    NSCameraUsageDescription="Allow camera access for websites you choose.",
                    NSMicrophoneUsageDescription="Allow microphone access for websites you choose.",
                    NSBluetoothAlwaysUsageDescription="Websites you allow can use Bluetooth, for example to sign in with a passkey on your phone.",
                    NSBluetoothPeripheralUsageDescription="Websites you allow can use Bluetooth, for example to sign in with a passkey on your phone.",
                    NSLocationUsageDescription="Allow location access for websites you choose.",
                    NSLocationWhenInUseUsageDescription="Allow location access for websites you choose.",
                    NSWebBrowserPublicKeyCredentialUsageDescription="Sign in to websites with passkeys saved in iCloud Keychain or your password manager.",
                    NSAudioCaptureUsageDescription="Websites you allow can share this Mac's audio, for example when casting a tab.",
                    NSLocalNetworkUsageDescription="Find Chromecast and other devices on your network to cast to.",
                    NSDesktopFolderUsageDescription="Show your recent files from Desktop in Library.",
                    NSDocumentsFolderUsageDescription="Show your recent files from Documents in Library.",
                    NSDownloadsFolderUsageDescription="Show images and videos from Downloads in your Media Library.")
        if purpose == "distribution":
            info.update(sparkle.INFO)
        if bundle_note:
            info["ParcLocalTestBuild"] = bundle_note
        chromium_usage = re.findall(r'"(NS\w+UsageDescription)"',
                                    (source / CHROMIUM_USAGE_DESCRIPTIONS).read_text())
        missing_usage = sorted(set(chromium_usage) - info.keys())
        if missing_usage:
            raise Refusal("Info.plist lacks usage descriptions Chromium declares: " + ", ".join(missing_usage))
        plist(contents / "Info.plist", info)
        entitlements = plistlib.loads((source / "chrome/app/app-entitlements.plist").read_bytes())
        probe = stage / "signing-probe"
        shutil.copy2(contents / "MacOS/ParcRestart", probe)
        team = signing_team(identity, probe)
        if purpose == "distribution" and team is None:
            raise Refusal("Distribution requires an Apple-issued signing identity with a Team ID")
        if team is None:
            entitlements["com.apple.security.cs.disable-library-validation"] = True
        ent_path = stage / "main-entitlements.plist"
        plist(ent_path, entitlements)
        progress("packaging: Widevine host signatures")
        widevine_report = widevine_host_signatures(app, widevine, team)
        run("/usr/bin/xattr", "-cr", development)
        images = verify_development_layout(app, manifest)
        progress(f"packaging: signing {len(images)} images")
        def sign(path: Path, ent: Path | None = None) -> None:
            args = ["/usr/bin/codesign", "--force", "--sign", identity, "--options", "runtime"]
            if identity != "-":
                args.append("--timestamp" if team else "--timestamp=none")
            if ent is not None:
                args += ["--entitlements", ent]
            run(*args, path)
        for name in sorted(images, key=lambda s: (-s.count("/"), s)):
            path = development / name
            if path.parent.name != "MacOS":
                sign(path)
        sign(frameworks / FRAMEWORK)
        sign(sparkle_framework / "Versions/B/Updater.app")
        sign(sparkle_framework)
        for helper, jit, hosts_cdm in helper_apps:
            helper_ent = {"com.apple.security.cs.allow-jit": True} if jit else {}
            if team is None or hosts_cdm:
                helper_ent["com.apple.security.cs.disable-library-validation"] = True
            helper_path = stage / (helper.stem + ".plist")
            plist(helper_path, helper_ent)
            sign(helper, helper_path)
        sign(dock_plugin)
        sign(contents / "MacOS/ParcRestart")
        sign(app, ent_path)
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
        verify_widevine_signatures(app, widevine_report)
        for name in manifest["components"]:
            run("/usr/bin/codesign", "--verify", "--strict", development / name)
        signed = verify_development_layout(app, manifest)
        require_exports(exported_symbols(frameworks / FRAMEWORK / ENGINE_NAME))
        report = {"schema_version": 1, "executed": False, "destination": str(output),
                  "app_version": version,
                  "app": str(output / "Parc.app"),
                  "layout": "standalone-app" if manifest["distribution_eligible"] else "chromium-direct-component-development",
                  "engine_manifest_sha256": hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
                  "source_lock_sha256": manifest["source_lock_sha256"],
                  "engine_runtime": manifest["engine_runtime"], "overlay": manifest["overlay"],
                  "configuration": configuration,
                  "purpose": purpose,
                  "engine_build_flags": manifest["engine_build_flags"],
                  "build_classification": manifest["build_classification"],
                  "distribution_eligible": manifest["distribution_eligible"],
                  "engine_copy_sha256_before_signing": copied_engine,
                  "application_icon": {"file": icon_file, "sha256": sha(resources / icon_file)},
                  "signing_identity": identity, "signing_team": team, "signed_images": signed,
                  "notarized": False, "widevine": widevine_report,
                  "sparkle": {"version": sparkle.VERSION, "sha256": sparkle.SHA256,
                              "update_feed": info.get("SUFeedURL")},
                  "signing_verification": "app deep/strict and sibling components strict verification passed",
                  "runtime_verified": False,
                  **({"engine_release": manifest["engine_release"]} if "engine_release" in manifest else {})}
        verify(manifest, engine, repo)
        with (development / "package-report.json").open("x") as stream:
            json.dump(report, stream, indent=2, sort_keys=True)
            stream.write("\n")
        progress(f"packaging: publishing {output}")
        publish_development_directory(development, output)
        progress("packaging: done")
        return report


class _Tee:
    def __init__(self, primary, log_file) -> None:
        self.primary = primary
        self.log_file = log_file

    def write(self, data) -> int:
        self.primary.write(data)
        self.log_file.write(data)
        return len(data)

    def flush(self) -> None:
        self.primary.flush()
        self.log_file.flush()

    def fileno(self):
        return self.primary.fileno()

    def isatty(self) -> bool:
        return self.primary.isatty()


def _attach_run_log(run_dir: Path, name: str):
    if not run_dir.is_dir():
        raise Refusal(f"Run directory does not exist: {run_dir}")
    handle = (run_dir / name).open("a", encoding="utf-8")
    sys.stdout = _Tee(sys.__stdout__, handle)
    sys.stderr = _Tee(sys.__stderr__, handle)
    return handle


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("seal-engine", "build", "release-build"))
    parser.add_argument("--engine-dir", type=Path, help="seal-engine/build: the sealed engine output")
    parser.add_argument("--manifest", type=Path, help="seal-engine/build: the engine seal")
    parser.add_argument("--release-package", type=Path,
                        help="release-build: an extracted standalone package directory whose engine is reused")
    parser.add_argument("--release-tag", help="release-build: the package's GitHub release tag")
    parser.add_argument("--release-commit", help="release-build: the commit the package was built from")
    parser.add_argument("--local-test", action="store_true",
                        help="release-build: allow a different overlay when the app's engine headers are unchanged; "
                             "labels the bundle as a local test build, never to publish")
    parser.add_argument("--allow-changed-headers", action="store_true",
                        help="release-build --local-test: accept changed engine headers whose new calls the app "
                             "guards with respondsToSelector:")
    parser.add_argument("--engine-workspace", type=Path,
                        help="release-build: an engine workspace whose Git objects hold the pinned Chromium commits")
    parser.add_argument("--output", type=Path, help="Fresh package directory containing Parc.app and a provenance report; development component engines also require sibling libraries")
    parser.add_argument("--sign-identity", default="-", help="codesign identity; '-' is development ad-hoc")
    parser.add_argument("--configuration", choices=("debug", "release"), default="release",
                        help="Swift optimization only; both use the shared Original icon and sealed Release engine")
    parser.add_argument("--purpose", choices=("development", "distribution"), default="development",
                        help="Distribution requires the sealed non-component engine, release app and certificate-backed signing")
    parser.add_argument("--widevine-certificate", type=Path,
                        help="Widevine VMP certificate (PEM or DER) for CDM host signatures; build only")
    parser.add_argument("--widevine-private-key", type=Path,
                        help=f"The certificate's RSA private key (PEM), kept outside any Git checkout; "
                             f"an optional passphrase is read from {WIDEVINE_KEY_PASSPHRASE}")
    parser.add_argument("--widevine-sign-command", type=Path,
                        help="External VMP signing service, run as COMMAND BINARY SIGNATURE FLAGS; build only")
    args = parser.parse_args(argv)
    log_handle = None
    try:
        passphrase = os.environ.pop(WIDEVINE_KEY_PASSPHRASE, None)
        widevine_options = (args.widevine_certificate, args.widevine_private_key, args.widevine_sign_command)
        if args.command == "seal-engine" and any(option is not None for option in widevine_options):
            raise Refusal("Widevine signing options apply to build, not seal-engine")
        release_options = (args.release_package, args.release_tag, args.release_commit, args.engine_workspace)
        if args.command == "release-build":
            if any(option is None for option in (*release_options, args.output)) or args.engine_dir or args.manifest:
                raise Refusal("release-build takes --release-package, --release-tag, --release-commit, "
                              "--engine-workspace and --output, not --engine-dir or --manifest")
            if any(option is not None for option in widevine_options):
                raise Refusal("release-build does not add Widevine host signing")
            if args.local_test and args.purpose == "distribution":
                raise Refusal("Local test packages cannot be distributions")
            if args.allow_changed_headers and not args.local_test:
                raise Refusal("--allow-changed-headers applies to --local-test only")
            if not re.fullmatch(r"[0-9a-f]{40}", args.release_commit):
                raise Refusal("--release-commit must be a full commit SHA")
            output = explicit_path(args.output)
            if not output.parent.is_dir():
                raise Refusal(f"Run directory does not exist: {output.parent}")
            log_handle = _attach_run_log(output.parent, "package.log")
            with tempfile.TemporaryDirectory(prefix=".parc-pinned-", dir=output.parent) as pinned:
                engine, source, manifest, verify = release_engine(
                    ROOT, args.release_package, args.engine_workspace, Path(pinned),
                    args.release_tag, args.release_commit, local_test=args.local_test,
                    allow_changed_headers=args.allow_changed_headers)
                note = (f"Local test build on the engine of {args.release_tag}; not for publishing"
                        if args.local_test else None)
                build_app(ROOT, engine, manifest, output, args.sign_identity, args.configuration,
                          source=source, verify=verify, bundle_note=note, purpose=args.purpose)
            print(output / "Parc.app")
            return 0
        if any(option is not None for option in release_options) or args.local_test or args.allow_changed_headers:
            raise Refusal("Release options apply to release-build only")
        if args.engine_dir is None or args.manifest is None:
            raise Refusal(f"{args.command} requires --engine-dir and --manifest")
        widevine = (widevine_signer(*widevine_options, passphrase=passphrase)
                    if args.command == "build" else None)
        engine = explicit_path(args.engine_dir)
        if args.purpose == "distribution" and engine.name != source_verifier(ROOT).SHIPPING_CONFIGURATION:
            raise Refusal("Distribution requires the reviewed non-component shipping output")
        manifest_path = explicit_path(args.manifest)
        with engine_lock(engine):
            if args.command == "seal-engine":
                if args.output or manifest_path.exists() or not manifest_path.parent.is_dir():
                    raise Refusal("Seal requires a new manifest in an existing directory, and no --output")
                log_handle = _attach_run_log(manifest_path.parent, "seal.log")
                manifest = make_manifest(engine, ROOT)
                with manifest_path.open("x") as stream:
                    json.dump(manifest, stream, indent=2, sort_keys=True)
                    stream.write("\n")
                print(manifest_path)
            else:
                if args.output is None:
                    raise Refusal("build requires --output /existing/parent/new-development-directory")
                if not manifest_path.parent.is_dir():
                    raise Refusal(f"Run directory does not exist: {manifest_path.parent}")
                log_handle = _attach_run_log(manifest_path.parent, "package.log")
                manifest = read_json(manifest_path)
                build_app(ROOT, engine, manifest, args.output, args.sign_identity,
                          args.configuration, purpose=args.purpose, widevine=widevine)
                print(args.output / "Parc.app")
        return 0
    except (Refusal, OSError, ValueError, KeyError, IndexError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Packaging refused: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1
    finally:
        sys.stdout = sys.__stdout__
        sys.stderr = sys.__stderr__
        if log_handle is not None:
            log_handle.close()


if __name__ == "__main__":
    sys.exit(main())

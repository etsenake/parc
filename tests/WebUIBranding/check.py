#!/usr/bin/env python3
"""Check Parc's WebUI branding rules, its vector mark and the Chromium text the rules replace."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / "build/tests/webui-branding"
CHECK = BUILD / "check"
MARK_SVG = ROOT / "Resources/AppIcons/Marks/Monochrome.svg"
DEFAULT_CHROMIUM = ROOT / "work/engine/chromium/src"
OUT_DIR = "out/ParcDistribution_GN_arm64"
SVG = "{http://www.w3.org/2000/svg}"

SOURCES = {
    "IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS": [
        "ui/webui/resources/cr_elements/icons.html.ts"],
    "IDR_SETTINGS_SHARED_ROLLUP_JS": [
        "ui/webui/resources/cr_elements/icons.html.ts",
        "chrome/browser/resources/settings/icons.html.ts",
        "chrome/browser/resources/settings/about_page/about_page.html.ts"],
    "IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS": [
        "components/metrics/debug/field_trials.html"],
    "IDR_VERSION_UI_ABOUT_VERSION_HTML": [
        "components/webui/version/resources/about_version.html"],
}

class Failures:
    def __init__(self):
        self.messages = []
        self.checks = 0

    def check(self, condition, message):
        self.checks += 1
        if not condition:
            self.messages.append(message)
        return condition


def run(*arguments):
    return subprocess.run([str(CHECK), *map(str, arguments)], capture_output=True, text=True)


def compile_check():
    BUILD.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror",
                    "-I", str(ROOT / "Engine/ParcChromium"), str(HERE / "Tests.cc"),
                    "-o", str(CHECK)], check=True)


def path_of(element):
    paths = list(element.iter(SVG + "path")) or list(element.iter("path"))
    return paths[0].get("d") if len(paths) == 1 else None


def check_artwork(failures):
    mark = run("mark").stdout
    svg = ET.parse(MARK_SVG).getroot()
    failures.check(svg.tag == SVG + "svg" and svg.get("viewBox") == "0 0 24 24",
                   f"{MARK_SVG.name} must be a 24-unit SVG")
    failures.check(path_of(svg) == mark,
                   f"{MARK_SVG.name} and the engine's mark path differ")
    dark = ET.fromstring(run("svg").stdout)
    failures.check(dark.get("viewBox") == "0 0 24 24" and path_of(dark) == mark,
                   "the dark logo SVG must draw the mark in a 24-unit box")
    failures.check(next(dark.iter(SVG + "path")).get("fill") == "#fff",
                   "the dark logo must be white")
    for mode, box in (("adaptive", "0 0 24 24"), ("padded", "-12 -12 48 48")):
        logo = ET.fromstring(run(mode).stdout)
        style = next(logo.iter(SVG + "style"), None)
        failures.check(logo.get("viewBox") == box and path_of(logo) == mark and
                       style is not None and "prefers-color-scheme: dark" in style.text,
                       f"the {mode} product logo must draw the mark in {box} and follow the colour scheme")
    icon = ET.fromstring(run("icon").stdout)
    failures.check(icon.tag == "g" and icon.get("id") == "chrome-product" and
                   icon.get("viewBox") == "0 0 24 24" and path_of(icon) == mark,
                   "the product icon must be one 24-unit path that takes the icon's colour")
    failures.check(next(icon.iter("path")).get("fill") is None,
                   "the product icon must not set its own fill")


def built_files(out):
    files = {}
    pattern = re.compile(r'<include name="(IDR_[A-Z0-9_]+)" file="([^"]+)"[^>]*resource_path="([^"]+)"')
    for grd in (out / "gen").rglob("*.grd*"):
        for name, file, resource_path in pattern.findall(grd.read_text(errors="replace")):
            path = file.replace("${root_gen_dir}", str(out / "gen")).replace(
                "${root_src_dir}", str(out.parents[1]))
            files[name] = (Path(path), resource_path)
    return files


def check_engine(chromium, failures, require_fresh):
    out = chromium / OUT_DIR
    files = built_files(out)
    names = run("names").stdout.split()
    failures.check(set(names) == set(SOURCES), "every branded resource needs its Chromium sources listed")
    dark = files.get("IDR_WEBUI_IMAGES_CHROME_LOGO_DARK_SVG")
    failures.check(dark and dark[1] == "images/chrome_logo_dark.svg",
                   "the toolbar's dark logo is no longer served at images/chrome_logo_dark.svg")
    with tempfile.TemporaryDirectory(prefix="webui-branding-") as temporary:
        scratch = Path(temporary)
        for name in names:
            sources = [chromium / relative for relative in SOURCES.get(name, [])]
            if name not in files:
                failures.messages.append(f"{name} is not in the engine's resource lists")
                continue
            built = files[name][0]
            if not failures.check(built.is_file(), f"{name}: built file {built} is missing"):
                continue
            stale = [path for path in sources if path.stat().st_mtime > built.stat().st_mtime]
            if stale:
                message = (f"{name}: {built.name} is older than {', '.join(p.name for p in stale)}; "
                           "build the engine to check the built page")
                if require_fresh:
                    failures.messages.append(message)
                else:
                    print(f"skipped: {message}")
                continue
            result = run("apply", name, built, scratch / "edited")
            failures.check(result.returncode == 0 and "failed" not in result.stdout,
                           f"{name}: " + "; ".join((result.stdout or result.stderr).split("\n")).strip("; "))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chromium", type=Path, help="Engine workspace chromium/src with a built ParcDistribution output")
    parser.add_argument("--require-engine", action="store_true",
                        help="Fail when no engine workspace is available or its built pages are older than their sources")
    arguments = parser.parse_args()
    compile_check()
    unit = run("unit")
    print(unit.stdout.strip() or unit.stderr.strip())
    if unit.returncode:
        return 1
    failures = Failures()
    check_artwork(failures)
    chromium = arguments.chromium or DEFAULT_CHROMIUM
    if (chromium / OUT_DIR / "gen").is_dir():
        check_engine(chromium.resolve(), failures, arguments.require_engine)
        engine = f"{failures.checks} checks against {chromium}"
    elif arguments.require_engine:
        failures.messages.append(f"no built engine workspace at {chromium}")
        engine = "missing"
    else:
        engine = "skipped: no engine workspace"
    for message in failures.messages:
        print(f"FAIL: {message}")
    print(f"webui branding: {'failed' if failures.messages else 'ok'} ({engine})")
    return 1 if failures.messages else 0


if __name__ == "__main__":
    sys.exit(main())

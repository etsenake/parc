#!/usr/bin/env python3
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    "IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS": ["ui/webui/resources/cr_elements/icons.html.ts"],
    "IDR_SETTINGS_SHARED_ROLLUP_JS": [
        "ui/webui/resources/cr_elements/icons.html.ts",
        "chrome/browser/resources/settings/icons.html.ts",
        "chrome/browser/resources/settings/about_page/about_page.html.ts",
    ],
    "IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS": ["components/metrics/debug/field_trials.html"],
    "IDR_VERSION_UI_ABOUT_VERSION_HTML": ["components/webui/version/resources/about_version.html"],
}


def resources(chromium, generated):
    result = {}
    for manifest in generated.rglob("*.grd*"):
        if not manifest.is_file():
            continue
        for entry in re.findall(r"<include\b[^>]+>", manifest.read_text(errors="replace")):
            attributes = dict(re.findall(r'(\w+)="([^"]*)"', entry))
            if {"name", "file", "resource_path"} <= attributes.keys():
                name = attributes["name"]
                if name in SOURCES or name == "IDR_WEBUI_IMAGES_CHROME_LOGO_DARK_SVG":
                    path = attributes["file"].replace("${root_gen_dir}", str(generated))
                    path = path.replace("${root_src_dir}", str(chromium))
                    result[name] = (manifest.parent / path, attributes["resource_path"])
    return result


def main():
    parser = argparse.ArgumentParser(description="Apply Parc’s branding rules to a built Chromium resource set.")
    parser.add_argument("--chromium", type=Path, default=ROOT / "work/engine/chromium/src")
    parser.add_argument("--require-engine", action="store_true")
    args = parser.parse_args()
    chromium = args.chromium.resolve()
    generated = chromium / "out/ParcDistribution_GN_arm64/gen"
    if not generated.is_dir():
        if args.require_engine:
            parser.exit(1, f"Missing generated resources in {generated}\n")
        print(f"Skipped engine branding checks. No generated resources in {generated}")
        return
    files = resources(chromium, generated)
    dark = files.get("IDR_WEBUI_IMAGES_CHROME_LOGO_DARK_SVG")
    if not dark or dark[1] != "images/chrome_logo_dark.svg":
        parser.exit(1, "The toolbar dark logo has no resource at images/chrome_logo_dark.svg\n")
    with tempfile.TemporaryDirectory(prefix="parc-branding-") as scratch:
        tool = Path(scratch) / "apply-webui-branding"
        subprocess.run(["xcrun", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror",
                        "-I", ROOT / "Engine/ParcChromium", ROOT / "scripts/apply-webui-branding.cc",
                        "-o", tool], check=True, timeout=60)
        names = subprocess.check_output([tool, "--list"], text=True, timeout=10).splitlines()
        if set(names) != SOURCES.keys():
            parser.exit(1, "Update the generated resource inputs for the current branding rules\n")
        for name in names:
            if name not in files:
                parser.exit(1, f"Missing generated resource {name}\n")
            asset = files[name][0]
            if any((chromium / source).stat().st_mtime > asset.stat().st_mtime for source in SOURCES[name]):
                if args.require_engine:
                    parser.exit(1, f"Rebuild stale generated resource {asset}\n")
                print(f"Skipped stale generated resource {asset}")
                continue
            subprocess.run([tool, name, asset], stdout=subprocess.DEVNULL, check=True, timeout=30)
            print(f"Applied branding to {name}")
        covered = {files[name][0].resolve() for name in names}
        for bundle in generated.rglob("minified/*.js"):
            if bundle.resolve() in covered:
                continue
            content = bundle.read_text(errors="replace")
            if '<g id="chrome-product"' in content and re.search(r"""[\w-]+:chrome-product['"]""", content):
                parser.exit(1, f"Unbranded generated product icon in {bundle}\n")


if __name__ == "__main__":
    main()

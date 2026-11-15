import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ICON_FILE = "Parc.icns"


def package_app_icons(resources: Path) -> str:
    icons = resources / "AppIcons"
    catalog = json.loads((icons / "catalog.json").read_text())
    default = catalog["default"]
    variants = catalog["variants"]
    if (default not in variants or len(variants) != len(set(variants))
            or any(not name or Path(name).name != name or name in (".", "..")
                   for name in variants)):
        raise ValueError("Invalid application icon catalog")
    for name in variants:
        if not (icons / (name + ".png")).is_file():
            raise FileNotFoundError(icons / (name + ".png"))
    with tempfile.TemporaryDirectory(prefix="parc-app-icons-") as temporary:
        renderer = Path(temporary) / "render-app-icon"
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-O",
                        str(Path(__file__).with_name("render_app_icon.swift")),
                        "-o", str(renderer)], check=True)
        for name in variants:
            _package_icon(icons / (name + ".png"), icons / (name + ".icns"),
                          renderer, mascot=name == "Terminal")
    shutil.copyfile(icons / (default + ".icns"), resources / ICON_FILE)
    return ICON_FILE


def _package_icon(source: Path, destination: Path, renderer: Path, *, mascot: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="parc-app-icon-") as temporary:
        iconset = Path(temporary) / "Parc.iconset"
        iconset.mkdir()
        subprocess.run([str(renderer), str(source), str(iconset),
                        "mascot" if mascot else "tile"], check=True)
        subprocess.run(["/usr/bin/iconutil", "--convert", "icns", "--output",
                        str(destination), str(iconset)], check=True)

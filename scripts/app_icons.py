"""Package Parc's app-icon family and shared default from versioned artwork."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ICON_FILE = "Parc.icns"


def package_app_icons(resources: Path) -> str:
    """Export every variant's native sizes and the shared Dock/Finder default."""
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
                          renderer, mascot=name == "Dev")
    shutil.copyfile(icons / (default + ".icns"), resources / ICON_FILE)
    return ICON_FILE


def _package_icon(source: Path, destination: Path, renderer: Path, *, mascot: bool) -> None:
    # macOS consumes the 1x/2x representations from one standard ICNS file.
    # Optical framing uses the opaque silhouette, ignoring faint edge/shadow
    # pixels. Each size comes directly from the unchanged approved artwork.
    with tempfile.TemporaryDirectory(prefix="parc-app-icon-") as temporary:
        iconset = Path(temporary) / "Parc.iconset"
        iconset.mkdir()
        subprocess.run([str(renderer), str(source), str(iconset),
                        "mascot" if mascot else "tile"], check=True)
        subprocess.run(["/usr/bin/iconutil", "--convert", "icns", "--output",
                        str(destination), str(iconset)], check=True)

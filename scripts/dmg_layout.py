import hashlib
import importlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

VOLUME = "Parc"
ROOT = Path(__file__).resolve().parents[1]
ART_FOLDER = "Sources/DiskImage"
ART = ROOT / ART_FOLDER
ARTWORK = ("background.png", "background@2x.png")
BACKGROUND = ".background.tiff"
VOLUME_ICON = ".VolumeIcon.icns"
WINDOW = (640, 400)
WINDOW_ORIGIN = (200, 120)
BACKGROUND_SIZES = [WINDOW, (WINDOW[0] * 2, WINDOW[1] * 2)]
ICON_SIZE = 128
TEXT_SIZE = 13
POSITIONS = {"Parc.app": (160, 190), "Applications": (480, 190)}
CACHE = ROOT / "build/dmgbuild"
PYPI = "https://files.pythonhosted.org/packages/"
WHEELS = (("dmgbuild", "1.6.7",
           PYPI + "6c/4a/8812638bba991a55a4b670806ab9cf60207077401893bb308eb1b04f288c/dmgbuild-1.6.7-py3-none-any.whl",
           "37ee5771c377beb3203d9164aae8046ffed8531c06edf9227f5788b3c599b1bf"),
          ("ds_store", "1.3.1",
           PYPI + "47/bf/b1c10362a0d670ee8ae086d92c3ab795fca2a927e4ff25e7cd15224d3863/ds_store-1.3.1-py3-none-any.whl",
           "fbacbb0bd5193ab3e66e5a47fff63619f15e374ffbec8ae29744251a6c8f05b5"),
          ("mac_alias", "2.2.2",
           PYPI + "39/a1/4136777ed6a56df83e7c748ad28892f0672cbbcdc3b3d15a57df6ba72443/mac_alias-2.2.2-py3-none-any.whl",
           "504ab8ac546f35bbd75ad014d6ad977c426660aa721f2cd3acf3dc2f664141bd"))


class LayoutError(ValueError):
    pass


def directory(cache=CACHE):
    pins = hashlib.sha256(" ".join(f"{name}={version}:{digest}" for name, version, _, digest in WHEELS).encode())
    return cache / f"dmgbuild-{WHEELS[0][1]}-{pins.hexdigest()[:12]}"


def fetch(cache=CACHE):
    target = directory(cache)
    if target.is_dir():
        return target
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".dmgbuild-", dir=cache) as temporary:
        site = Path(temporary) / "site"
        site.mkdir()
        for name, version, url, digest in WHEELS:
            wheel = Path(temporary) / f"{name}.whl"
            subprocess.run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
                            "--connect-timeout", "30", "--max-time", "300", "--output", str(wheel), url], check=True)
            with wheel.open("rb") as stream:
                if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                    raise LayoutError(f"Downloaded {name} {version} does not match its pinned SHA-256")
            with zipfile.ZipFile(wheel) as archive:
                archive.extractall(site, [member for member in archive.namelist() if member.split("/")[0] == name])
            if not (site / name / "__init__.py").is_file():
                raise LayoutError(f"{name} {version} lacks its package")
        try:
            site.rename(target)
        except OSError:
            if not target.is_dir():
                raise
    return target


def load(cache=CACHE):
    site = fetch(cache).resolve()
    if str(site) not in sys.path:
        sys.path.insert(0, str(site))
    modules = [importlib.import_module(name) for name, *_ in WHEELS]
    for module in modules:
        if not getattr(module, "__file__", None) or Path(module.__file__).resolve().parents[1] != site:
            raise LayoutError(f"{module.__name__} was loaded from outside its pinned copy")
    return modules


def settings(app):
    return {"files": [str(app)], "symlinks": {"Applications": "/Applications"},
            "icon": str(app / "Contents/Resources/Parc.icns"), "background": str(ART / ARTWORK[0]),
            "format": "UDZO", "window_rect": (WINDOW_ORIGIN, WINDOW), "default_view": "icon-view",
            "show_status_bar": False, "show_tab_view": False, "show_toolbar": False, "show_pathbar": False,
            "show_sidebar": False, "icon_size": ICON_SIZE, "text_size": TEXT_SIZE, "icon_locations": dict(POSITIONS)}


def build(app, image, log, cache=CACHE):
    dmgbuild = load(cache)[0]
    with log.open("a") as stream:
        dmgbuild.build_dmg(str(image), VOLUME, settings=settings(app),
                           callback=lambda info: stream.write(json.dumps(info, default=str) + "\n"))


def window_options():
    return {"ShowStatusBar": False, "WindowBounds": "{{%d, %d}, {%d, %d}}" % (*WINDOW_ORIGIN, *WINDOW),
            "ContainerShowSidebar": False, "PreviewPaneVisibility": False, "SidebarWidth": 180,
            "ShowTabView": False, "ShowToolbar": False, "ShowPathbar": False, "ShowSidebar": False}


def icon_view_options(alias):
    return {"viewOptionsVersion": 1, "backgroundType": 2, "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0,
            "backgroundColorBlue": 1.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
            "arrangeBy": "none", "showIconPreview": False, "showItemInfo": False, "labelOnBottom": True,
            "textSize": float(TEXT_SIZE), "iconSize": float(ICON_SIZE), "scrollPositionX": 0.0,
            "scrollPositionY": 0.0, "backgroundImageAlias": alias}


def written_store(alias, cache=CACHE):
    ds_store = load(cache)[1]
    with tempfile.TemporaryDirectory(prefix="parc-ds-store-") as temporary:
        path = Path(temporary) / "DS_Store"
        with ds_store.DSStore.open(str(path), "w+") as records:
            records["."]["vSrn"] = ("long", 1)
            records["."]["bwsp"] = window_options()
            records["."]["icvp"] = icon_view_options(alias)
            records["."]["icvl"] = (b"type", b"icnv")
            for name, point in POSITIONS.items():
                records[name]["Iloc"] = point
        return path.read_bytes()


def records(data, cache=CACHE):
    ds_store = load(cache)[1]
    with tempfile.TemporaryDirectory(prefix="parc-ds-store-") as temporary:
        path = Path(temporary) / "DS_Store"
        path.write_bytes(data)
        with ds_store.DSStore.open(str(path), "r") as store:
            return {(entry.filename, entry.code.decode()): entry.value for entry in store}


def alias_identity(alias):
    volume, target = alias.volume, alias.target
    return (os.fsdecode(volume.name), volume.creation_date, volume.fs_type, target.kind, os.fsdecode(target.filename),
            target.folder_cnid, target.cnid, target.creation_date, os.fsdecode(target.carbon_path),
            os.fsdecode(target.posix_path))


def tiff_sizes(data):
    order = {b"II": "<", b"MM": ">"}.get(data[:2])
    if order is None or struct.unpack_from(order + "H", data, 2)[0] != 42:
        raise LayoutError("background is not a TIFF image")
    sizes, offset = [], struct.unpack_from(order + "I", data, 4)[0]
    while offset:
        if len(sizes) == 8:
            raise LayoutError("background has too many images")
        count = struct.unpack_from(order + "H", data, offset)[0]
        fields = {}
        for index in range(count):
            field = offset + 2 + 12 * index
            tag, kind = struct.unpack_from(order + "HH", data, field)
            fields[tag] = struct.unpack_from(order + ("H" if kind == 3 else "I"), data, field + 8)[0]
        if 256 not in fields or 257 not in fields:
            raise LayoutError("background image lacks its size")
        sizes.append((fields[256], fields[257]))
        offset = struct.unpack_from(order + "I", data, offset + 2 + 12 * count)[0]
    return sizes


def verify(volume, finder_info, app_icon, cache=CACHE):
    try:
        mac_alias = load(cache)[2]
    except (OSError, ImportError, subprocess.CalledProcessError) as error:
        raise LayoutError("the pinned dmgbuild libraries could not be loaded: " + str(error)) from error
    try:
        data = (volume / ".DS_Store").read_bytes()
        found = records(data, cache)
        alias = found[(".", "icvp")]["backgroundImageAlias"]
        expected = written_store(alias, cache)
    except Exception as error:
        raise LayoutError("the Finder layout is missing or unreadable") from error
    if data != expected:
        planned = records(expected, cache)
        differing = sorted(set(found) ^ set(planned)) or sorted(key for key in planned if found[key] != planned[key])
        raise LayoutError("the Finder layout differs from what dmgbuild writes for this window: "
                          + (", ".join(f"{name} {code}" for name, code in differing) or "its record tree"))
    background = volume / BACKGROUND
    try:
        stored, actual = mac_alias.Alias.from_bytes(alias), mac_alias.Alias.for_file(str(background))
        identity = alias_identity(stored)
        points_here = identity == alias_identity(actual) and identity[0] == VOLUME
    except Exception:
        points_here = False
    if not points_here:
        raise LayoutError("the background reference does not point at this volume's picture")
    try:
        sizes = tiff_sizes(background.read_bytes())
        icon = (volume / VOLUME_ICON).read_bytes()
    except (OSError, struct.error) as error:
        raise LayoutError("the background picture or volume icon is missing") from error
    if sorted(sizes) != BACKGROUND_SIZES:
        raise LayoutError("the background picture lacks its 1x and 2x images")
    if icon != app_icon or len(finder_info) < 10 or not finder_info[8] & 0x04:
        raise LayoutError("the volume does not carry Parc's icon")

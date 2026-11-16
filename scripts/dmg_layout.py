import os
from pathlib import Path
import plistlib
import stat
import struct

VOLUME = "Parc"
ART_FOLDER = "Sources/DiskImage"
ART = Path(__file__).resolve().parents[1] / ART_FOLDER
ARTWORK = ("background.png", "background@2x.png")
BACKGROUND = Path(".background/background.tiff")
VOLUME_ICON = ".VolumeIcon.icns"
WINDOW = (640, 400)
WINDOW_ORIGIN = (200, 120)
BACKGROUND_SIZES = [WINDOW, (WINDOW[0] * 2, WINDOW[1] * 2)]
ICON_SIZE = 128
TEXT_SIZE = 13
POSITIONS = {"Parc.app": (160, 204), "Applications": (480, 204)}
CUSTOM_ICON = bytes(8) + b"\x04\x00" + bytes(22)
MAC_EPOCH_OFFSET = 2082844800
PAGE = 4096
INFO_ADDRESS = 2048
SUPERBLOCK_ADDRESS = 32
NODE_ADDRESS = PAGE
HEADER_TAIL = bytes.fromhex("0000100c000000870000200b00000000")
ALIAS_FIXED = ">h28pI2shI64pII4s4shhI2s10s"


class LayoutError(ValueError):
    pass


def mac_time(posix_seconds):
    return posix_seconds + MAC_EPOCH_OFFSET


def pad(data):
    return data + b"\0" * (len(data) & 1)


def alias_record(volume, volume_created, folder, folder_id, name, file_id, file_created):
    carbon_volume = volume.encode().replace(b":", b"/")
    carbon_name = name.encode().replace(b":", b"/")
    record = struct.pack(">4shh", b"\0" * 4, 0, 2)
    record += struct.pack(ALIAS_FIXED, 0, carbon_volume, int(volume_created), b"H+", 0, folder_id, carbon_name,
                          file_id, int(file_created), b"\0" * 4, b"\0" * 4, -1, -1, 0, b"\0\0", b"\0" * 10)
    tags = [(0, folder.encode()),
            (16, struct.pack(">Q", int(volume_created * 65536))),
            (17, struct.pack(">Q", int(file_created * 65536))),
            (1, struct.pack(">I", folder_id)),
            (2, f"{volume}:{folder}:\0{name}".encode()),
            (14, struct.pack(">h", len(name)) + name.encode("utf-16-be")),
            (15, struct.pack(">h", len(volume)) + volume.encode("utf-16-be")),
            (18, f"/{folder}/{name}".encode()),
            (19, f"/Volumes/{volume}".encode())]
    for tag, value in tags:
        record += struct.pack(">hh", tag, len(value)) + pad(value)
    record += struct.pack(">hh", -1, 0)
    return record[:4] + struct.pack(">h", len(record)) + record[6:]


def read_alias(data):
    if len(data) < 8 + struct.calcsize(ALIAS_FIXED):
        raise LayoutError("background reference is truncated")
    _, size, version = struct.unpack_from(">4shh", data)
    if version != 2 or size != len(data):
        raise LayoutError("background reference is not a version 2 alias record")
    (kind, volume, volume_created, filesystem, _, folder_id, name, file_id, file_created,
     *_) = struct.unpack_from(ALIAS_FIXED, data, 8)
    offset = 8 + struct.calcsize(ALIAS_FIXED)
    tags = {}
    while True:
        tag, length = struct.unpack_from(">hh", data, offset)
        offset += 4
        if tag == -1:
            break
        if length < 0 or offset + length > len(data):
            raise LayoutError("background reference has a malformed field")
        tags[tag] = data[offset:offset + length]
        offset += length + (length & 1)
    return {"kind": kind, "volume": volume.decode(), "volume_created": volume_created,
            "filesystem": filesystem, "folder_id": folder_id, "name": name.decode(), "file_id": file_id,
            "file_created": file_created, "path": tags.get(18, b"").decode(),
            "folder": tags.get(0, b"").decode(), "carbon_path": tags.get(2, b"").decode()}


def encode_entry(name, code, kind, value):
    text = name.encode("utf-16-be")
    head = struct.pack(">I", len(text) // 2) + text + code.encode("ascii") + kind.encode("ascii")
    if kind == "blob":
        return head + struct.pack(">I", len(value)) + value
    if kind in ("long", "shor"):
        return head + struct.pack(">I", value)
    if kind == "bool":
        return head + bytes([int(value)])
    if kind == "type":
        return head + value
    raise LayoutError("unsupported record type " + kind)


def store(entries):
    ordered = sorted(entries, key=lambda entry: (entry[0].lower(), entry[1]))
    node = struct.pack(">II", 0, len(ordered)) + b"".join(encode_entry(*entry) for entry in ordered)
    if len(node) > PAGE:
        raise LayoutError("layout records exceed one page")
    offsets = [SUPERBLOCK_ADDRESS | 5, NODE_ADDRESS | 12]
    free = [[1 << level] if 6 <= level <= 30 and level not in (11, 12) else [] for level in range(32)]
    info = struct.pack(">II", len(offsets), 0) + struct.pack(">256I", *offsets, *[0] * (256 - len(offsets)))
    info += struct.pack(">I", 1) + bytes([4]) + b"DSDB" + struct.pack(">I", 0)
    info += b"".join(struct.pack(f">I{len(addresses)}I", len(addresses), *addresses) for addresses in free)
    space = bytearray(NODE_ADDRESS + PAGE)
    space[0:32] = b"Bud1" + struct.pack(">III", INFO_ADDRESS, INFO_ADDRESS, INFO_ADDRESS) + HEADER_TAIL
    space[SUPERBLOCK_ADDRESS:SUPERBLOCK_ADDRESS + 20] = struct.pack(">IIIII", 1, 0, len(ordered), 1, PAGE)
    space[INFO_ADDRESS:INFO_ADDRESS + len(info)] = info
    space[NODE_ADDRESS:NODE_ADDRESS + len(node)] = node
    return struct.pack(">I", 1) + bytes(space)


def read_entry(data, offset):
    length = struct.unpack_from(">I", data, offset)[0]
    offset += 4
    name = data[offset:offset + length * 2].decode("utf-16-be")
    offset += length * 2
    code, kind = data[offset:offset + 4].decode("ascii"), data[offset + 4:offset + 8].decode("ascii")
    offset += 8
    if kind == "blob":
        size = struct.unpack_from(">I", data, offset)[0]
        value, offset = data[offset + 4:offset + 4 + size], offset + 4 + size
    elif kind in ("long", "shor"):
        value, offset = struct.unpack_from(">I", data, offset)[0], offset + 4
    elif kind == "bool":
        value, offset = bool(data[offset]), offset + 1
    elif kind == "type":
        value, offset = data[offset:offset + 4], offset + 4
    elif kind == "ustr":
        size = struct.unpack_from(">I", data, offset)[0]
        value, offset = data[offset + 4:offset + 4 + size * 2].decode("utf-16-be"), offset + 4 + size * 2
    elif kind in ("comp", "dutc"):
        value, offset = struct.unpack_from(">Q", data, offset)[0], offset + 8
    else:
        raise LayoutError("unknown record type " + repr(kind))
    return (name, code), (kind, value), offset


def read_store(data):
    if data[:8] != b"\0\0\0\1Bud1":
        raise LayoutError(".DS_Store is not a Finder layout file")
    info, _, info_again = struct.unpack_from(">III", data, 8)
    if info != info_again:
        raise LayoutError(".DS_Store root addresses differ")
    position = info + 4
    count = struct.unpack_from(">I", data, position)[0]
    offsets = struct.unpack_from(f">{count}I", data, position + 8)
    position += 8 + 4 * ((count + 255) // 256 * 256)
    directory = {}
    for _ in range(struct.unpack_from(">I", data, position)[0]):
        length = data[position + 4]
        name = data[position + 5:position + 5 + length]
        directory[name] = struct.unpack_from(">I", data, position + 5 + length)[0]
        position += 1 + length + 4

    def address(block):
        return (offsets[block] & ~31) + 4

    if b"DSDB" not in directory:
        raise LayoutError(".DS_Store has no record tree")
    root, _, total, _, _ = struct.unpack_from(">IIIII", data, address(directory[b"DSDB"]))
    entries = {}
    visited = set()

    def walk(block, depth):
        if depth > 16 or block in visited:
            raise LayoutError(".DS_Store record tree is malformed")
        visited.add(block)
        offset = address(block)
        rightmost, count = struct.unpack_from(">II", data, offset)
        offset += 8
        for _ in range(count):
            if rightmost:
                walk(struct.unpack_from(">I", data, offset)[0], depth + 1)
                offset += 4
            key, value, offset = read_entry(data, offset)
            entries[key] = value
        if rightmost:
            walk(rightmost, depth + 1)

    walk(root, 0)
    if len(entries) != total:
        raise LayoutError(".DS_Store record count disagrees with its tree")
    return entries


def window_options():
    return {"ContainerShowSidebar": False, "PreviewPaneVisibility": False, "ShowPathbar": False,
            "ShowSidebar": False, "ShowStatusBar": False, "ShowTabView": False, "ShowToolbar": False,
            "SidebarWidth": 0, "WindowBounds": "{{%d, %d}, {%d, %d}}" % (*WINDOW_ORIGIN, *WINDOW)}


def icon_view_options():
    return {"arrangeBy": "none", "backgroundColorBlue": 1.0, "backgroundColorGreen": 1.0,
            "backgroundColorRed": 1.0, "backgroundType": 2, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
            "gridSpacing": 100.0, "iconSize": float(ICON_SIZE), "labelOnBottom": True, "scrollPositionX": 0.0,
            "scrollPositionY": 0.0, "showIconPreview": False, "showItemInfo": False,
            "textSize": float(TEXT_SIZE), "viewOptionsVersion": 1}


def icon_location(x, y):
    return struct.pack(">IIII", x, y, 0xFFFFFFFF, 0xFFFF0000)


def layout_entries(alias):
    view = icon_view_options() | {"backgroundImageAlias": alias}
    entries = [(".", "bwsp", "blob", plistlib.dumps(window_options(), fmt=plistlib.FMT_BINARY)),
               (".", "icvp", "blob", plistlib.dumps(view, fmt=plistlib.FMT_BINARY)),
               (".", "vSrn", "long", 1), (".", "vstl", "type", b"icnv")]
    return entries + [(name, "Iloc", "blob", icon_location(*point)) for name, point in POSITIONS.items()]


def background_alias(volume):
    background = volume / BACKGROUND
    root, folder, image = volume.stat(), background.parent.stat(), background.stat()
    return alias_record(VOLUME, mac_time(root.st_birthtime), background.parent.name, folder.st_ino,
                        background.name, image.st_ino, mac_time(image.st_birthtime))


def write(volume):
    (volume / ".DS_Store").write_bytes(store(layout_entries(background_alias(volume))))


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


def property_list(entries, code):
    kind, value = entries.pop((".", code))
    if kind != "blob":
        raise LayoutError(f"the {code} record is not a property list")
    result = plistlib.loads(value)
    if not isinstance(result, dict):
        raise LayoutError(f"the {code} record is not a dictionary")
    return result


def encoded(options):
    return plistlib.dumps(options, fmt=plistlib.FMT_BINARY)


def verify(volume, finder_info, app_icon):
    try:
        entries = read_store((volume / ".DS_Store").read_bytes())
        view, window = property_list(entries, "icvp"), property_list(entries, "bwsp")
        alias = view.pop("backgroundImageAlias")
        if not isinstance(alias, bytes):
            raise LayoutError("the background reference is not an alias record")
        planned_options = encoded(window) == encoded(window_options()) and encoded(view) == encoded(icon_view_options())
    except LayoutError:
        raise
    except Exception as error:
        raise LayoutError("the Finder layout is missing or unreadable") from error
    expected = {(name, code): (kind, value) for name, code, kind, value in layout_entries(b"")
                if code not in ("bwsp", "icvp")}
    if not planned_options or entries != expected:
        raise LayoutError("the Finder window, icon view or icon positions differ from the planned layout")
    background = volume / BACKGROUND
    try:
        root, folder, image = volume.stat(), background.parent.stat(), background.stat()
        sizes = tiff_sizes(background.read_bytes())
        icon = (volume / VOLUME_ICON).read_bytes()
    except (OSError, struct.error) as error:
        raise LayoutError("the background picture or volume icon is missing") from error
    if alias != alias_record(VOLUME, mac_time(root.st_birthtime), BACKGROUND.parent.name, folder.st_ino,
                             BACKGROUND.name, image.st_ino, mac_time(image.st_birthtime)):
        raise LayoutError("the background reference does not point at this volume's picture")
    if sorted(sizes) != BACKGROUND_SIZES:
        raise LayoutError("the background picture lacks its 1x and 2x images")
    if not folder.st_flags & stat.UF_HIDDEN:
        raise LayoutError("the background folder is visible")
    if icon != app_icon or len(finder_info) < 10 or not finder_info[8] & 0x04:
        raise LayoutError("the volume does not carry Parc's icon")


def stage_extras(stage, icon):
    background = stage / BACKGROUND
    background.parent.mkdir()
    (stage / VOLUME_ICON).write_bytes(icon.read_bytes())
    return background


def hide(path):
    os.chflags(path, os.stat(path).st_flags | stat.UF_HIDDEN)

"""Stream portable trees to split gzip tar assets, and restore them without clobbering.

The JSON manifest binds a JSONL inventory and every compressed part by SHA-256.
Inventory records are in component-wise path order, so even very large trees can
be checked without retaining all file names. Symlink resolution uses a temporary
SQLite index. Ownership, ACLs, xattrs and hardlink identity are deliberately not
transported; hardlinked regular files are archived as independent contents.

The manifest must come from a trusted source: hashes establish integrity, not
publisher authenticity. No archive member is ever extracted with tar.extract().
"""
from __future__ import annotations

import ctypes
import errno
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import sys
import tarfile
import tempfile

FORMAT = "parc-artifact-archive-v1"
DEFAULT_PART_SIZE = 2_000_000_000
CHUNK = 1024 * 1024


class ArchiveError(ValueError):
    """The archive is invalid, unsafe or changed while it was being read."""


def _path(value):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ArchiveError("invalid relative path")
    parts = value.split("/")
    if any(p in ("", ".", "..") for p in parts):
        raise ArchiveError(f"unsafe relative path: {value!r}")
    return tuple(parts)


def _asset(value):
    if len(_path(value)) != 1:
        raise ArchiveError("asset names must be basenames")
    return value


def _integer(value, label, minimum=None, maximum=None):
    if type(value) is not int or (minimum is not None and value < minimum) or (
            maximum is not None and value > maximum):
        raise ArchiveError(f"invalid {label}")
    return value


def _metadata(record):
    if not isinstance(record, dict):
        raise ArchiveError("invalid metadata record")
    _integer(record.get("mode"), "mode", 0, 0o7777)
    _integer(record.get("mtime_ns"), "mtime_ns")


def _json(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def _open_regular(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ArchiveError(f"not a regular file: {path}")
        return os.fdopen(fd, "rb")
    except BaseException:
        os.close(fd)
        raise


def _fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def _digest(path):
    digest = hashlib.sha256()
    with _open_regular(path) as source:
        before = os.fstat(source.fileno())
        while data := source.read(CHUNK):
            digest.update(data)
        if _fingerprint(before) != _fingerprint(os.fstat(source.fileno())):
            raise ArchiveError(f"file changed while hashing: {path}")
    return {"name": path.name, "size": before.st_size, "sha256": digest.hexdigest()}


class _PartWriter:
    def __init__(self, directory, name, limit):
        self.directory, self.name, self.limit = directory, name, limit
        self.parts, self.file, self.size = [], None, 0

    def write(self, data):
        original = len(data)
        data = memoryview(data)
        while data:
            if self.file is None:
                self.path = self.directory / f"{self.name}.part{len(self.parts) + 1:06d}.tar.gz"
                self.file = self.path.open("xb")
                self.digest, self.size = hashlib.sha256(), 0
            portion = data[:self.limit - self.size]
            self.file.write(portion)
            self.digest.update(portion)
            self.size += len(portion)
            data = data[len(portion):]
            if self.size == self.limit:
                self.close()
        return original

    def flush(self):
        if self.file:
            self.file.flush()

    def close(self):
        if self.file:
            self.file.close()
            self.parts.append({"name": self.path.name, "size": self.size,
                               "sha256": self.digest.hexdigest()})
            self.file = None


class _HashReader:
    def __init__(self, file):
        self.file, self.digest = file, hashlib.sha256()

    def read(self, size):
        data = self.file.read(size)
        self.digest.update(data)
        return data


def _selection(includes, extras):
    root = {"children": {}, "selected": includes is None}
    for name in includes or ():
        if name == ".":
            root["selected"] = True
            continue
        node = root
        for part in _path(name):
            node = node["children"].setdefault(part, {"children": {}})
        node["selected"] = True
    for name, contents in extras.items():
        if not isinstance(contents, bytes):
            raise ArchiveError("extra_files values must be bytes")
        node = root
        for part in _path(name):
            node = node["children"].setdefault(part, {"children": {}})
        node["extra"] = contents
    return root


def _walk(root, selection, excluded, extras, rewrites, replace_extra_files=False):
    used_rewrites = set()

    def visit(parts, node, inherited=False):
        name = "/".join(parts)
        if any(parts[:len(prefix)] == prefix for prefix in excluded):
            if name in extras:
                raise ArchiveError(f"extra file is excluded: {name}")
            return
        source = root.joinpath(*parts)
        try:
            info = source.lstat()
        except FileNotFoundError:
            info = None
        if "extra" in node:
            if node["children"] or (info is not None and
                    (not replace_extra_files or not stat.S_ISREG(info.st_mode))):
                raise ArchiveError(f"extra file collides with a source path: {name}")
            yield name, {"type": "file", "mode": 0o644, "mtime_ns": 0}, io.BytesIO(node["extra"])
            return
        if info is None and (node.get("selected") or not node["children"]):
            raise ArchiveError(f"missing source: {name}")
        is_dir = info is None or stat.S_ISDIR(info.st_mode)
        record = {"mode": stat.S_IMODE(info.st_mode) if info else 0o755,
                  "mtime_ns": info.st_mtime_ns if info else 0}
        if is_dir:
            record["type"] = "directory"
            if parts:
                yield name, record, None
            whole = inherited or node.get("selected", False)
            names = set(node["children"])
            if whole and info:
                with os.scandir(source) as entries:
                    names.update(entry.name for entry in entries)
            for child in sorted(names):
                yield from visit(parts + (child,), node["children"].get(child, {"children": {}}), whole)
            if info and _fingerprint(info) != _fingerprint(source.lstat()):
                raise ArchiveError(f"directory changed during export: {source}")
        elif node["children"]:
            raise ArchiveError(f"non-directory source ancestor: {name}")
        elif stat.S_ISLNK(info.st_mode):
            record["type"] = "symlink"
            record["target"] = rewrites.get(name, os.readlink(source))
            if name in rewrites:
                used_rewrites.add(name)
            if _fingerprint(info) != _fingerprint(source.lstat()):
                raise ArchiveError(f"symlink changed during export: {name}")
            yield name, record, None
        elif stat.S_ISREG(info.st_mode):
            record["type"] = "file"
            with _open_regular(source) as file:
                if _fingerprint(info) != _fingerprint(os.fstat(file.fileno())):
                    raise ArchiveError(f"file changed before export: {name}")
                yield name, record, file
                if _fingerprint(info) != _fingerprint(os.fstat(file.fileno())):
                    raise ArchiveError(f"file changed during export: {name}")
        else:
            raise ArchiveError(f"special files cannot be archived: {name}")

    yield from visit((), selection)
    if set(rewrites) != used_rewrites:
        raise ArchiveError("symlink rewrite does not name an included symlink")


def create_archive(root, output_directory, name, *, includes=None, extra_files=None,
                   excludes=(), part_size=DEFAULT_PART_SIZE, symlink_rewrites=None,
                   replace_extra_files=False):
    """Write split assets and publish the manifest last; return its JSON object.

    Paths in includes/excludes/extra_files are relative to root, without a wrapper
    directory. Missing ancestors of extra_files are generated as 0755 directories.
    symlink_rewrites explicitly replaces included links with internal relative
    targets. replace_extra_files permits virtual metadata to supersede existing
    regular files in the archive only; it never changes the source tree.
    Sources must remain quiescent throughout this operation.
    """
    root, output = Path(root).resolve(), Path(output_directory).resolve()
    _asset(name)
    _integer(part_size, "part size", 1, DEFAULT_PART_SIZE)
    if output == root or root in output.parents:
        raise ArchiveError("output directory must be outside the source tree")
    if not root.is_dir():
        raise ArchiveError("source root must be a directory")
    extras, rewrites = dict(extra_files or {}), dict(symlink_rewrites or {})
    excluded = [_path(value) for value in excludes]
    for key in rewrites:
        _path(key)
    for key in extras:
        parts = _path(key)
        if any(parts[:len(prefix)] == prefix for prefix in excluded):
            raise ArchiveError(f"extra file is excluded: {key}")
    selection = _selection(includes, extras)
    output.mkdir(parents=True, exist_ok=True)
    root_info = root.stat()
    published = []
    with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=output) as temporary:
        stage = Path(temporary)
        writer = _PartWriter(stage, name, part_size)
        inventory_path = stage / f"{name}.inventory.jsonl"
        count = 0
        try:
            with inventory_path.open("xb") as inventory, gzip.GzipFile(
                    filename="", mode="wb", fileobj=writer, mtime=0, compresslevel=1) as compressed:
                with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as archive:
                    for path, record, source in _walk(root, selection, excluded, extras, rewrites, replace_extra_files):
                        record = {"path": path, **record}
                        header = tarfile.TarInfo(path)
                        header.mode = record["mode"]
                        header.mtime = record["mtime_ns"] // 1_000_000_000
                        header.pax_headers = {"PARC.mtime_ns": str(record["mtime_ns"])}
                        if record["type"] == "file":
                            header.size = (len(source.getbuffer()) if isinstance(source, io.BytesIO)
                                           else os.fstat(source.fileno()).st_size)
                            hashed = _HashReader(source)
                            archive.addfile(header, hashed)
                            record.update(size=header.size, sha256=hashed.digest.hexdigest())
                        else:
                            header.type = tarfile.DIRTYPE if record["type"] == "directory" else tarfile.SYMTYPE
                            if record["type"] == "symlink":
                                header.linkname = record["target"]
                            archive.addfile(header)
                        archive.members.clear()  # Do not retain one TarInfo per source file.
                        inventory.write(_json(record))
                        count += 1
            writer.close()  # gzip's trailer is written after the tar stream closes.
            if _fingerprint(root_info) != _fingerprint(root.stat()):
                raise ArchiveError("source root changed during export")
            manifest = {"format": FORMAT, "compression": "gzip", "archive": "tar",
                        "parts": writer.parts,
                        "inventory": {**_digest(inventory_path), "entries": count},
                        "root": {"mode": stat.S_IMODE(root_info.st_mode), "mtime_ns": root_info.st_mtime_ns}}
            # Validate paths and complete symlink chains before publishing anything.
            with _Inventory(inventory_path, manifest["inventory"]):
                pass
            manifest_path = stage / f"{name}.manifest.json"
            manifest_path.write_bytes(_json(manifest))
            for asset in [*writer.parts, manifest["inventory"], {"name": manifest_path.name}]:
                target = output / asset["name"]
                os.link(stage / asset["name"], target)  # exclusive; never overwrite.
                published.append(target)
            return manifest
        except BaseException:
            for target in reversed(published):
                target.unlink()
            raise
        finally:
            writer.close()


def _descriptor(record):
    if not isinstance(record, dict):
        raise ArchiveError("invalid asset descriptor")
    _asset(record.get("name"))
    _integer(record.get("size"), "asset size", 0)
    if not isinstance(record.get("sha256"), str) or not re.fullmatch("[0-9a-f]{64}", record["sha256"]):
        raise ArchiveError("invalid SHA-256")


def _load(manifest_path):
    path = Path(manifest_path)
    with _open_regular(path) as source:
        if os.fstat(source.fileno()).st_size > 16 * CHUNK:
            raise ArchiveError("manifest is too large")
        manifest = json.load(source)
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT or (
            manifest.get("compression"), manifest.get("archive")) != ("gzip", "tar"):
        raise ArchiveError("unsupported archive format")
    _metadata(manifest.get("root", {}))
    parts = manifest.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ArchiveError("archive has no parts")
    names = {path.name}
    for asset in [manifest.get("inventory"), *parts]:
        _descriptor(asset)
        if asset["name"] in names:
            raise ArchiveError("duplicate asset name")
        names.add(asset["name"])
    _integer(manifest["inventory"].get("entries"), "entry count", 0)
    return path.parent, manifest


class _Inventory:
    def __init__(self, path, descriptor):
        self.path, self.descriptor = path, descriptor

    def __enter__(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="parc-inventory-")
        self.database = sqlite3.connect(Path(self.temporary.name) / "links.sqlite")
        self.file = None
        try:
            self.database.execute("CREATE TABLE links (path TEXT PRIMARY KEY, target TEXT)")
            # Keep a private verified inventory snapshot across validation passes.
            # A caller changing the downloaded file cannot alter paths after checks.
            local = Path(self.temporary.name) / "inventory.jsonl"
            digest, size = hashlib.sha256(), 0
            with _open_regular(self.path) as source, local.open("xb") as copy:
                for chunk in iter(lambda: source.read(CHUNK), b""):
                    digest.update(chunk)
                    size += len(chunk)
                    copy.write(chunk)
            self.file = local.open("rb")
            if (size, digest.hexdigest()) != (self.descriptor["size"], self.descriptor["sha256"]):
                raise ArchiveError("inventory hash or size mismatch")
            count = 0
            for record in self.records():
                count += 1
                if record["type"] == "symlink":
                    target = record.get("target")
                    if not isinstance(target, str) or not target or target.startswith("/") or "\x00" in target:
                        raise ArchiveError("symlink target must be relative and internal")
                    self.database.execute("INSERT INTO links VALUES (?, ?)", (record["path"], target))
            if count != self.descriptor["entries"]:
                raise ArchiveError("inventory entry count mismatch")
            for name, target in self.database.execute("SELECT path, target FROM links"):
                _check_link(name, target, lambda path: self.database.execute(
                    "SELECT target FROM links WHERE path = ?", (path,)).fetchone())
            return self
        except BaseException:
            self.__exit__(*sys.exc_info())
            raise

    def records(self):
        self.file.seek(0)
        previous, directories = (), set()
        for line in self.file:
            record = json.loads(line)
            if not isinstance(record, dict):
                raise ArchiveError("invalid inventory record")
            parts = _path(record.get("path"))
            if parts <= previous:
                raise ArchiveError("inventory is unordered or has duplicate paths")
            directories = {item for item in directories if parts[:len(item)] == item}
            if len(parts) > 1 and parts[:-1] not in directories:
                raise ArchiveError("inventory path has a missing or non-directory ancestor")
            _metadata(record)
            kind = record.get("type")
            if kind == "directory":
                directories.add(parts)
            elif kind == "file":
                _descriptor({"name": "file", "size": record.get("size"), "sha256": record.get("sha256")})
            elif kind != "symlink":
                raise ArchiveError("unsupported inventory entry type")
            previous = parts
            yield record

    def __exit__(self, *args):
        if self.file:
            self.file.close()
        self.database.close()
        self.temporary.cleanup()


def _check_link(name, target, lookup):
    """Resolve each component, checking containment before following any link."""
    base, pending, hops = name.split("/")[:-1], target.split("/"), 0
    while pending:
        component = pending.pop(0)
        if component in ("", "."):
            continue
        if component == "..":
            if not base:
                raise ArchiveError(f"symlink escapes archive: {name}")
            base.pop()
        else:
            base.append(component)
            link = lookup("/".join(base))
            if link:
                hops += 1
                if hops > 40:
                    raise ArchiveError(f"symlink cycle or excessive chain: {name}")
                if link[0].startswith("/"):
                    raise ArchiveError(f"absolute symlink target: {name}")
                base.pop()
                pending = link[0].split("/") + pending


def _check_staged_links(stage, inventory):
    # Case and Unicode aliases are determined by the destination filesystem, not
    # Python or SQLite string equality. All directories are still traversable.
    def lookup(path):
        candidate = stage / path
        try:
            if stat.S_ISLNK(candidate.lstat().st_mode):
                return (os.readlink(candidate),)
        except (FileNotFoundError, NotADirectoryError):
            pass
        return None

    for record in inventory.records():
        if record["type"] == "symlink":
            _check_link(record["path"], record["target"], lookup)


class _PartReader(io.RawIOBase):
    def __init__(self, directory, descriptors):
        self.directory, self.descriptors = directory, iter(descriptors)
        self.file, self.expected, self.size = None, None, 0

    def readable(self):
        return True

    def read(self, size=-1):
        if size < 0:
            raise ArchiveError("unbounded archive read")
        result = bytearray()
        while len(result) < size:
            if self.file is None:
                self.expected = next(self.descriptors, None)
                if self.expected is None:
                    break
                self.file = _open_regular(self.directory / self.expected["name"])
                self.before = os.fstat(self.file.fileno())
                if self.before.st_size != self.expected["size"]:
                    raise ArchiveError("part size mismatch")
                self.digest, self.size = hashlib.sha256(), 0
            chunk = self.file.read(min(size - len(result), CHUNK))
            if chunk:
                self.size += len(chunk)
                self.digest.update(chunk)
                result.extend(chunk)
            else:
                unchanged = _fingerprint(self.before) == _fingerprint(os.fstat(self.file.fileno()))
                self.file.close()
                self.file = None
                if not unchanged or (self.size, self.digest.hexdigest()) != (self.expected["size"], self.expected["sha256"]):
                    raise ArchiveError("part hash mismatch or source changed")
        return bytes(result)

    def close(self):
        if self.file:
            self.file.close()
            self.file = None
        super().close()


def _apply_metadata(path, record):
    if record.get("type") != "symlink":
        os.chmod(path, record["mode"])
    elif stat.S_IMODE(path.lstat().st_mode) != record["mode"]:
        os.chmod(path, record["mode"], follow_symlinks=False)
    os.utime(path, ns=(record["mtime_ns"], record["mtime_ns"]), follow_symlinks=False)


def _consume(directory, manifest, inventory, stage=None):
    with _PartReader(directory, manifest["parts"]) as raw, gzip.GzipFile(fileobj=raw, mode="rb") as compressed:
        with tarfile.open(fileobj=compressed, mode="r|") as archive:
            for record in inventory.records():
                header = archive.next()
                if header is None:
                    raise ArchiveError("archive is missing inventory entries")
                archive.members.clear()  # tarfile otherwise retains millions of headers.
                kind = ("file" if header.isreg() else "directory" if header.isdir()
                        else "symlink" if header.issym() else "unsupported")
                if (header.name != record["path"] or kind != record["type"] or header.sparse is not None
                        or header.mode != record["mode"] or header.pax_headers.get("PARC.mtime_ns") != str(record["mtime_ns"])
                        or header.size != record.get("size", 0)
                        or (kind == "symlink" and header.linkname != record["target"])):
                    raise ArchiveError("tar header does not match inventory")
                target = stage / record["path"] if stage else None
                if kind == "file":
                    digest, size = hashlib.sha256(), 0
                    destination = target.open("xb") if target else None
                    try:
                        source = archive.extractfile(header)
                        while chunk := source.read(CHUNK):
                            size += len(chunk)
                            digest.update(chunk)
                            if destination:
                                destination.write(chunk)
                    finally:
                        if destination:
                            destination.close()
                    if (size, digest.hexdigest()) != (record["size"], record["sha256"]):
                        raise ArchiveError("file contents do not match inventory")
                elif target and kind == "directory":
                    target.mkdir(mode=0o700)
                elif target:
                    target.symlink_to(record["target"])
                if target and kind != "directory":
                    _apply_metadata(target, record)
            extra = archive.next() if manifest["inventory"]["entries"] else archive.firstmember
            if extra is not None:
                raise ArchiveError("archive contains unlisted entries")
            while chunk := archive.fileobj.read(CHUNK):
                if chunk.strip(b"\0"):
                    raise ArchiveError("archive contains trailing data")
        # Exhaust the compressed stream and force every part's digest check.
        while chunk := compressed.read(CHUNK):
            if chunk.strip(b"\0"):
                raise ArchiveError("archive contains trailing data")
        if raw.read(1):
            raise ArchiveError("archive contains unread compressed data")
    if stage:
        _check_staged_links(stage, inventory)
        # Restore directory times only after their children have been created.
        pending = []
        for record in inventory.records():
            parts = _path(record["path"])
            while pending and parts[:len(pending[-1][0])] != pending[-1][0]:
                _, finished = pending.pop()
                _apply_metadata(stage / finished["path"], finished)
            if record["type"] == "directory":
                pending.append((parts, record))
        for _, record in reversed(pending):
            _apply_metadata(stage / record["path"], record)
        _apply_metadata(stage, manifest["root"])


def verify_archive(manifest_path):
    """Verify part hashes, inventory, tar headers and every regular file's bytes."""
    directory, manifest = _load(manifest_path)
    with _Inventory(directory / manifest["inventory"]["name"], manifest["inventory"]) as inventory:
        _consume(directory, manifest, inventory)
    return manifest


def _publish(stage, destination):
    """Atomic directory rename which refuses any existing destination, even empty."""
    library = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        function = library.renamex_np
        function.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        result = function(os.fsencode(stage), os.fsencode(destination), 4)  # RENAME_EXCL
    elif sys.platform.startswith("linux") and hasattr(library, "renameat2"):
        function = library.renameat2
        function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        result = function(-100, os.fsencode(stage), -100, os.fsencode(destination), 1)  # RENAME_NOREPLACE
    else:
        raise ArchiveError("atomic exclusive directory publication is unsupported on this platform")
    if result:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


def _cleanup(stage):
    if stage.exists():
        os.chmod(stage, 0o700)
        for directory, names, _ in os.walk(stage):
            for name in names:
                path = Path(directory) / name
                if not path.is_symlink():
                    os.chmod(path, 0o700)
        shutil.rmtree(stage)


def extract_archive(manifest_path, destination, *, post_extract=None):
    """Verify and stage a tree, invoke optional trusted callback(stage, final), publish.

    The callback runs after archive metadata restoration and before publication;
    it may perform application-specific adoption. Failure leaves no destination.
    The destination parent must already exist. Existing paths are never replaced.
    """
    destination = Path(destination).absolute()
    destination = destination.parent.resolve(strict=True) / destination.name
    if os.path.lexists(destination):
        raise FileExistsError(errno.EEXIST, "destination already exists", str(destination))
    directory, manifest = _load(manifest_path)
    stage = Path(tempfile.mkdtemp(prefix=f".{destination.name}-", dir=destination.parent))
    try:
        with _Inventory(directory / manifest["inventory"]["name"], manifest["inventory"]) as inventory:
            _consume(directory, manifest, inventory, stage)
        if post_extract:
            post_extract(stage, destination)
        _publish(stage, destination)
        return destination
    finally:
        _cleanup(stage)

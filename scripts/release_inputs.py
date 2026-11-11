import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import sys
import os
import uuid


def inventory(repo, commit):
    raw = subprocess.check_output(["git", "ls-tree", "-rz", commit], cwd=repo)
    result = {}
    for record in raw.split(b"\0"):
        if not record:
            continue
        header, name = record.split(b"\t", 1)
        mode, kind, identity = header.decode().split()
        if kind != "blob":
            raise ValueError("Release snapshots do not accept submodules")
        result[name.decode()] = {"mode": mode, "blob": identity}
    return result


def verify(repo, source, commit):
    expected = inventory(repo, commit)
    for name, entry in expected.items():
        path = Path(source) / name
        data = path.readlink().as_posix().encode() if entry["mode"] == "120000" else path.read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != entry["blob"]:
            raise ValueError("Frozen release input changed: " + name)
    for directory in ('Sources', 'Resources', 'Engine', 'scripts'):
        for parent, dirs, files in os.walk(Path(source) / directory):
            dirs[:] = [d for d in dirs if d != '__pycache__']
            for filename in files:
                relative = (Path(parent) / filename).relative_to(source).as_posix()
                if relative not in expected:
                    raise ValueError('Untracked frozen release input: ' + relative)
    return expected


def create(repo, source, commit):
    source = Path(source)
    if source.exists():
        verify(repo, source, commit)
        return
    stage = source.with_name(source.name + '.extract-' + uuid.uuid4().hex[:8])
    stage.mkdir(parents=True)
    archive = stage.parent / (stage.name + '.tar')
    with archive.open("wb") as stream:
        subprocess.run(["git", "archive", "--format=tar", commit], cwd=repo, stdout=stream, check=True)
    with tarfile.open(archive) as stream:
        stream.extractall(stage, filter="data")
    verify(repo, stage, commit)
    os.rename(stage, source)
    archive.unlink()
    (source.parent / "source-receipt.json").write_text(json.dumps({
        "commit": commit, "repository": str(Path(repo).resolve()),
        "source": str(source.resolve()), "kind": "immutable-git-archive"}, indent=2) + "\n")


if __name__ == "__main__":
    verify(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])

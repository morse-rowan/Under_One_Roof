"""Checksummed, append-only experiment storage with OS-released writer locks."""
import contextlib
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from .config import ROOT
from .engine import lune_executable


def canonical(value):
    def normalize(item):
        if isinstance(item, float) and item.is_integer():
            return int(item)
        if isinstance(item, dict):
            return {key: normalize(v) for key, v in item.items()}
        if isinstance(item, list):
            return [normalize(v) for v in item]
        return item
    return json.dumps(normalize(value), sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".pending-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical(value))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


@contextlib.contextmanager
def lock(directory, blocking=False):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".writer.lock").open("a+b") as stream:
        stream.seek(0, 2)
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK if blocking else msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except OSError as exc:
            raise RuntimeError(f"Another writer owns {directory}") from exc
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def append(path, value):
    with Path(path).open("ab") as stream:
        stream.write(canonical(value) + b"\n")
        stream.flush()
        os.fsync(stream.fileno())


def journal(directory, repair=False):
    path = Path(directory) / "journal.jsonl"
    if not path.exists():
        return []
    raw = path.read_bytes()
    records, offset = [], 0
    previous = ""
    for line in raw.splitlines(keepends=True):
        if not line.endswith(b"\n"):
            if repair:
                # Preserve torn bytes as evidence before discarding the uncommitted tail.
                (Path(directory) / f"torn-{uuid.uuid4().hex}.bin").write_bytes(line)
                with path.open("r+b") as stream:
                    stream.truncate(offset)
            break
        row = json.loads(line)
        payload = row["payload"]
        if row["previous"] != previous or row["hash"] != digest({"previous": previous, "payload": payload}):
            raise ValueError("Journal checksum/chain mismatch")
        records.append(payload)
        previous = row["hash"]
        offset += len(line)
    return records


def record(directory, payload):
    path = Path(directory) / "journal.jsonl"
    previous = ""
    if path.exists():
        lines = path.read_bytes().splitlines()
        if lines:
            previous = json.loads(lines[-1])["hash"]
    append(path, {"payload": payload, "previous": previous,
                  "hash": digest({"previous": previous, "payload": payload})})


def checkpoint(directory, number, payload, operation):
    checksum = digest(payload)
    filename = f"checkpoints/{number:06d}.json"
    atomic(Path(directory) / filename, {"hash": checksum, "payload": payload})
    record(directory, {"kind": "commit", "number": number, "file": filename,
                       "hash": checksum, "operation": operation})


def load_checkpoint(directory, number=None):
    commits = [r for r in journal(directory) if r["kind"] == "commit"]
    if not commits:
        raise ValueError("No committed checkpoint")
    row = commits[-1] if number is None else next((r for r in commits if r["number"] == number), None)
    if row is None:
        raise ValueError("Checkpoint does not exist")
    content = read(Path(directory) / row["file"])
    if content["hash"] != row["hash"] or digest(content["payload"]) != row["hash"]:
        raise ValueError("Checkpoint checksum mismatch")
    return row["number"], content["payload"]


def source_files(source=ROOT):
    source = Path(source)
    files = list((source / "src/shared").glob("Lab*.luau"))
    files += [p for p in (source / "tools/simlab").rglob("*") if p.suffix in {".py", ".luau"} and "__pycache__" not in p.parts]
    files += list((source / "experiments").rglob("*.json"))
    files += [source / "tools/simulate.py", source / "rokit.toml"]
    files += [source / "src/server/LabSession.luau", source / "tools/simulate-live.ps1"]
    return sorted(files)


def source_manifest(source=ROOT):
    return {p.relative_to(source).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files(source) if p.exists()}


def snapshot(destination, source=ROOT):
    hashes = source_manifest(source)
    for name in hashes:
        target = Path(destination) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(source) / name, target)
    return hashes


def verify_source(directory):
    manifest = read(Path(directory) / "manifest.json")
    source = Path(directory) / "source"
    for name, expected in manifest["source_files"].items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != expected:
            raise ValueError(f"Archived source changed: {name}")
    version = subprocess.check_output([lune_executable(), "--version"], text=True).strip()
    if version != manifest["lune_version"]:
        raise ValueError("Lune version differs from run; install its pinned toolchain")
    return source


def create(root, config, parent=None, source=ROOT, run_id=None):
    run_id = run_id or time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:10]
    directory = Path(root).resolve() / "runs" / run_id
    directory.mkdir(parents=True, exist_ok=False)
    hashes = snapshot(directory / "source", source)
    try:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        revision = "unavailable"
    manifest = {"schema": 1, "run_id": run_id, "created": time.time(), "parent": parent,
                "source_files": hashes, "source_hash": digest(hashes), "git_revision": revision,
                "lune_version": subprocess.check_output([lune_executable(), "--version"], text=True).strip(),
                "config_hash": digest(config)}
    atomic(directory / "manifest.json", manifest)
    atomic(directory / "config.json", config)
    atomic(directory / "tags.json", [])
    return directory


def free_space(directory, config):
    if shutil.disk_usage(directory).free < config["limits"]["min_free_mb"] * 1024 * 1024:
        raise RuntimeError("disk_pressure")

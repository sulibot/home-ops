#!/usr/bin/env python3
"""Repair an explicitly audited list of dangling CephFS clone references.

Dry-run by default. The caller must first verify that each VolumeSnapshotContent
is already deleting and its original VolumeSnapshot UID no longer exists.
Apply requires the Ceph volumes module to be disabled and the clone index empty.
See the 2026-11-13 incident report for the maintenance/recovery procedure.
"""

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile


UUID = r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}"


def parse(data):
    result = configparser.ConfigParser(interpolation=None)
    result.read_string(data.decode())
    return result


def repaired_bytes(original, snapshot, index):
    before = parse(original)
    if before.get("GLOBAL", "state") != "complete":
        raise ValueError("Source subvolume is not complete")
    tracks = [key for key, value in before.items("clone snaps") if value == snapshot]
    if not tracks:
        raise ValueError("No matching clone references")
    for track in tracks:
        if not re.fullmatch(UUID, track):
            raise ValueError("Invalid clone tracking ID")
        # lexists also rejects a dangling symlink: it is still a live index entry.
        if os.path.lexists(index / track):
            raise ValueError("Clone index entry still exists: " + track)
    section = None
    lines = []
    removed = []
    for line in original.decode().splitlines(keepends=True):
        if line.strip().startswith("["):
            section = line.strip()[1:-1]
        if section == "clone snaps" and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() in tracks and value.strip() == snapshot:
                removed.append(key.strip())
                continue
        lines.append(line)
    if sorted(removed) != sorted(tracks):
        raise ValueError("Unexpected metadata formatting; refusing partial edit")
    updated = "".join(lines).encode()
    after = parse(updated)
    for track in tracks:
        before.remove_option("clone snaps", track)
    if {s: dict(before[s]) for s in before} != {s: dict(after[s]) for s in after}:
        raise ValueError("Edit changed unrelated metadata")
    return updated, tracks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--filesystem-root", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    root = args.filesystem_root.resolve(strict=True)
    index = root / "volumes/_index/clone"
    plan = json.loads(args.plan.read_text())
    if not plan:
        raise ValueError("Empty plan")
    prepared = []
    seen = set()
    for entry in plan:
        source, snapshot = entry["source"], entry["snapshot"]
        if not re.fullmatch("sol-config-csi-vol-" + UUID, source):
            raise ValueError("Unexpected source name")
        if not re.fullmatch("csi-snap-" + UUID, snapshot):
            raise ValueError("Unexpected snapshot name")
        if source in seen:
            raise ValueError("Multiple edits for one source require a combined plan")
        seen.add(source)
        path = root / "volumes/csi" / source / ".meta"
        if path.is_symlink() or path.resolve().parent != path.parent:
            raise ValueError("Unexpected metadata symlink")
        original = path.read_bytes()
        metadata = parse(original)
        section = "SNAP_METADATA_" + snapshot
        if metadata.get(section, "csi.storage.k8s.io/volumesnapshotcontent/name") != entry["content"]:
            raise ValueError("Snapshot metadata does not match the planned content")
        updated, tracks = repaired_bytes(original, snapshot, index)
        prepared.append((entry, path, original, updated, tracks))
        print(json.dumps({"content": entry["content"], "source": source,
                          "orphan_references": len(tracks)}), flush=True)
    if not args.apply:
        return
    if args.backup_dir is None:
        raise ValueError("--backup-dir is required for apply")
    backup = args.backup_dir.resolve()
    if backup == root or root in backup.parents:
        raise ValueError("Backups must be outside the repaired filesystem")
    modules = json.loads(subprocess.check_output(["ceph", "mgr", "module", "ls", "-f", "json"]))
    if "volumes" not in modules["force_disabled_modules"]:
        raise ValueError("Ceph volumes module must be disabled before apply")
    if list(index.iterdir()):
        raise ValueError("Clone index is not empty")
    backup.mkdir(mode=0o700, parents=True, exist_ok=False)
    (backup / "plan.json").write_text(json.dumps(plan, indent=2))
    # Back up and validate the full batch before modifying any source.
    for entry, path, original, updated, tracks in prepared:
        if path.read_bytes() != original:
            raise ValueError("Metadata changed after preflight")
        target = backup / (entry["source"] + ".meta")
        with target.open("xb") as stream:
            os.chmod(target, 0o600)
            stream.write(original)
            stream.flush()
            os.fsync(stream.fileno())
    applied = []
    for entry, path, original, updated, tracks in prepared:
        if path.read_bytes() != original or list(index.iterdir()):
            raise ValueError("Concurrent metadata/clone change detected")
        info = path.stat()
        fd, temporary = tempfile.mkstemp(prefix=".meta.orphan-repair-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                os.fchmod(stream.fileno(), stat.S_IMODE(info.st_mode))
                os.fchown(stream.fileno(), info.st_uid, info.st_gid)
                stream.write(updated)
                stream.flush()
                os.fsync(stream.fileno())
            if path.read_bytes() != original:
                raise ValueError("Concurrent metadata change before rename")
            os.replace(temporary, path)
            if path.read_bytes() != updated:
                raise ValueError("Readback mismatch")
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        applied.append({"source": entry["source"], "removed": tracks,
                        "before_sha256": hashlib.sha256(original).hexdigest(),
                        "after_sha256": hashlib.sha256(updated).hexdigest()})
        (backup / "applied.json").write_text(json.dumps(applied, indent=2))
    print(json.dumps({"repaired_sources": len(applied), "backup_dir": str(backup)}))


if __name__ == "__main__":
    main()

# CephFS orphan snapshot cleanup, 2026-11-13

## Result

Removed 81 dangling clone tracking references from 18 CephFS subvolume metadata
files. CSI then completed all 18 snapshot deletions that had been stuck since
May–July. Verified:

- All 18 old snapshots are absent from Ceph.
- All 18 source subvolumes remain in `complete` state.
- Kubernetes has zero `VolumeSnapshotContent` objects awaiting deletion.
- No recurring `pending clones` snapshot-deletion errors after reconciliation.
- All active cluster-101 pods were Ready after the repair, and all four CephFS
  filesystems had active MDS ranks.
- The existing four-OSD BlueStore warning remained unchanged. This cleanup does
  not resolve or suppress that separate latency-history warning.

Kubernetes finalizers were not stripped. Application data, backup repositories,
and current snapshots were not manually removed. New scheduled VolSync snapshot
clones continued after recovery; `clone ... pending/in progress` during creation
is normal asynchronous provisioning, unlike the months-old deletion failures.

## Cause and evidence

Ceph 19.2.4's `subvolume_v1.py` checks the source `.meta` file's `[clone snaps]`
section before deleting a snapshot. Its snapshot information command separately
resolves tracking IDs through `/volumes/_index/clone`. These 81 tracking IDs had
no index entries, so snapshot information returned `has_pending_clones: no` with
an `orphan_clones_count`, but snapshot deletion still failed with EAGAIN.

Every affected Kubernetes content object already had `deletionPolicy: Delete`
and a deletion timestamp. Every original VolumeSnapshot UID was absent. Some
current snapshots reused the old names, so identity was checked by UID, not name.
Each source was complete; none of the 81 tracking IDs was present in the index,
including as a dangling symlink. The config filesystem's entire clone index was
empty immediately before the repair.

## Repair and recovery safeguards

The script `scripts/repair-ceph-orphan-clone-metadata.py` is dry-run by default.
Its plan records `content`, `content_uid`, `ref`, `source`, `snapshot`, and
`deleted` for each audited content object. Before using it again:

1. Rebuild the plan from live Kubernetes resources. Require already-deleting
   contents, absent original snapshot UIDs, and matching Ceph source/snapshot
   handles. Do not reuse this incident's plan for a new operation.
2. Confirm each snapshot reports no pending clones and a positive orphan count.
   Confirm no active clone index entries. Defer if a backup clone is running.
3. Dry-run the script against the mounted filesystem root. Inspect the proposed
   changes; it removes only exact matching lines in `[clone snaps]` and verifies
   that the rest of the parsed metadata is unchanged.
4. Arm an independent recovery timer on the Ceph host before pausing the volumes
   module. This incident used `systemd-run --on-active=90s` to run
   `/usr/bin/ceph mgr module enable volumes` if the maintenance session failed.
5. Briefly disable volume management with
   `ceph mgr module force disable volumes --yes-i-really-mean-it`. This pauses
   volume-management/provisioning operations; existing filesystem client I/O
   does not depend on this module. Allow module shutdown to settle and verify
   `force_disabled_modules` contains `volumes`. A volume API request can hang
   while the module is disabled; do not use a successful API response as the
   quiescence check.
6. Apply with an external backup directory. The script checks the disabled module,
   empty clone index, complete sources, snapshot-content metadata identity,
   unchanged file bytes, and absent individual index entries. It backs up the
   entire batch before editing, preserves ownership/mode, fsyncs temporary files,
   atomically replaces each `.meta`, and verifies readback. It records removed
   IDs and before/after hashes.
7. Always re-enable `volumes` in a `finally`/trap handler. Retry a bounded volume
   API check until it works; only then disarm the independent recovery timer.
8. Let CSI perform the existing deletions. If necessary, enqueue reconciliation
   by annotating the exact content objects with JSON Patch tests for their UID
   and deletion timestamp. Do not strip finalizers or directly remove snapshots.
9. Verify both backend snapshot absence and Kubernetes content removal, source
   volume health, active workload readiness, and storage logs.

The successful metadata-edit window held the module disabled for 7.69 seconds.
An earlier preflight attempt timed out probing the disabled API, restored the
module, and made no metadata changes. Both independent recovery timers were
disarmed after successful recovery. No MDS or OSD restart was required.

Backups and the applied-record manifest are retained on `pve01` at
`/root/ceph-orphan-metadata-backup-20261113/` (root-only directory). Do not blindly
restore these files after CSI has deleted the snapshots: that would reintroduce
references to snapshots that no longer exist. They are forensic/recovery input,
not an automatic rollback after deletion completes.

Six regression tests cover exact-line edits, preserving other snapshot entries,
refusing existing index entries and dangling links, incomplete sources, missing
snapshot matches, and invalid tracking paths:

```sh
python3 -m unittest discover -s scripts/tests -p test_ceph_orphan_metadata.py -v
```

References:
- [CephFS snapshot and clone management](https://docs.ceph.com/en/squid/cephfs/fs-volumes/)
- Installed Ceph source: `/usr/share/ceph/mgr/volumes/fs/operations/versions/subvolume_v1.py`

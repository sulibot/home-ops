# Cluster-104 Home Assistant Config Backup

This component backs up the live cluster-104 Home Assistant `/config` local PVC
to the shared Kopia S3 repository defined by the `volsync-template` 1Password
item.

Cluster-104 currently uses local PVs and does not have VolSync or snapshot CRDs,
so this is intentionally a direct Kopia CronJob rather than a ReplicationSource.
It is GitOps-owned and can be replaced by VolSync later if cluster-104 gains the
same storage primitives as the main cluster.

Restore is intentionally suspended. To restore, stop Home Assistant first, copy
`home-assistant-config-restore-template` to a one-off Job, set
`RESTORE_SNAPSHOT_ID`, and run it against the `home-assistant-config` PVC.

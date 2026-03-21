# RWX Migration Plan

## Goal

Use `ReadWriteMany` only where shared access is a real requirement:

- shared backup repositories
- shared content libraries
- shared config volumes that may be mounted by jobs, restores, or replacement pods on different nodes

Keep `ReadWriteOnce` for single-writer stateful services and local app data where concurrent mounts are not useful.

## Current State

The repo already uses `RWX` in the places where it most clearly makes sense:

- VolSync component defaults to `ReadWriteMany` for replication PVCs in [kubernetes/components/volsync/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/components/volsync/pvc.yaml) and related source/destination templates in [kubernetes/components/volsync/replicationsource.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/components/volsync/replicationsource.yaml) and [kubernetes/components/volsync/replicationdestination.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/components/volsync/replicationdestination.yaml)
- Kopia repository storage is already `RWX` in [kubernetes/components/volsync/kopia-repository-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/components/volsync/kopia-repository-pvc.yaml), [kubernetes/apps/tier-2-applications/kopia/app/kopia-repository-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/kopia/app/kopia-repository-pvc.yaml), and [kubernetes/apps/tier-2-applications/volsync-repository-pvc/app/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/volsync-repository-pvc/app/pvc.yaml)
- Shared media/content storage is already `RWX` in [kubernetes/apps/tier-0-foundation/ceph-csi/shared-storage/app/csi-cephfs-content-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-0-foundation/ceph-csi/shared-storage/app/csi-cephfs-content-pvc.yaml)
- Observability shared content and cross-namespace Kopia access are already `RWX` in [kubernetes/apps/tier-1-infrastructure/observability-namespace/_namespace/csi-cephfs-content-pvc-observability.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-1-infrastructure/observability-namespace/_namespace/csi-cephfs-content-pvc-observability.yaml) and [kubernetes/apps/tier-1-infrastructure/observability-namespace/_namespace/kopia-repository-pv-observability.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-1-infrastructure/observability-namespace/_namespace/kopia-repository-pv-observability.yaml)

The new Victoria Logs PVC is intentionally `RWO` and should stay that way in [kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml).

## Recommendation

There is no blanket RWX migration to do right now. The main repository-level work is an audit and normalization pass:

1. Keep backup repository and shared library PVCs on `RWX`.
2. Keep single-writer StatefulSets and databases on `RWO`.
3. Normalize app config PVCs only where there is a concrete operational reason.

## Classes

### Keep RWX

These are good `RWX` fits and should remain that way:

- Kopia repository PVCs
- VolSync source/destination mover PVCs
- shared media/content PVCs
- shared restore/maintenance mounts
- app config PVCs only when the app regularly depends on restore jobs, sidecars, or cross-node replacement using the same volume

### Keep RWO

These should stay `RWO` unless the deployment model changes:

- Victoria Logs
- databases and queue stores
- single-writer StatefulSets
- node-local caches or scratch data
- PVCs backed by `openebs-hostpath` or other node-local storage intended for one pod on one node

Examples already matching this rule:

- [kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml)
- [kubernetes/apps/tier-2-applications/actions-runner-controller/runners/home-ops/helmrelease.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/actions-runner-controller/runners/home-ops/helmrelease.yaml)

### Review Case By Case

These are often `RWX` today, but should be reviewed instead of changed blindly:

- per-app config PVCs under `manual-pvc-*-config.yaml`
- Home Assistant cache/config PVCs
- Grafana config PVC
- app-scaffolded config PVCs on `csi-cephfs-config-sc`

Most of these are already `RWX` in the repo. The question is not "should they be migrated?" but "should any of them be tightened back to RWO?"

## Migration Priorities

### Phase 1

Confirm and leave alone:

- VolSync/Kopia repository PVCs
- shared content PVCs
- Victoria Logs `RWO`

This phase is effectively complete from a manifest-design perspective.

### Phase 2

Audit app config PVCs and classify each one:

- `RWX justified`
- `could be RWO`
- `must stay RWO`

Start with:

- Home Assistant
- Grafana
- Paperless
- Immich
- Plex and the *arr stack

### Phase 3

For any app config PVC that should move from `RWX` to `RWO` or from `RWO` to `RWX`, use a cutover migration:

1. create the new PVC with the desired access mode
2. stop or scale down the workload
3. copy data with a one-shot job
4. update the HelmRelease or manifest to point at the new claim
5. bring the workload back
6. remove the old PVC after validation

Do not try to change access mode in place on a bound PVC.

## Safe Candidates To Leave As-Is

These already align with the intended model and are not worth churn right now:

- [kubernetes/components/volsync/kopia-repository-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/components/volsync/kopia-repository-pvc.yaml)
- [kubernetes/apps/tier-2-applications/kopia/app/kopia-repository-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/kopia/app/kopia-repository-pvc.yaml)
- [kubernetes/apps/tier-2-applications/volsync-repository-pvc/app/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/volsync-repository-pvc/app/pvc.yaml)
- [kubernetes/apps/tier-0-foundation/ceph-csi/shared-storage/app/csi-cephfs-content-pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-0-foundation/ceph-csi/shared-storage/app/csi-cephfs-content-pvc.yaml)
- [kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml](/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-1-infrastructure/victoria-logs/app/pvc.yaml)

## Follow-Up Work

If you want to continue this, the next useful task is not a bulk migration. It is a classification audit of app config PVCs so the repo has a documented reason for each access mode choice.

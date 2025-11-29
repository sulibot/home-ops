# Volsync Auto-Restore Status & Architecture

## Current State Summary

### ✅ What's Working
1. **Kubernetes v1.35.0-alpha.3** - Fully operational 6-node cluster
2. **MutatingAdmissionPolicy Enabled** - Feature gates configured, API available
3. **MutatingAdmissionPolicies Deployed**:
   - `volsync-mover-jitter` ✅ (Verified: injects jitter initContainer)
   - `volsync-mover-nfs` ✅ (Verified: injects repository PVC volume)
   - `kopia-maintenance-nfs` ✅ (For maintenance jobs)
4. **Backups Working Perfectly** - ReplicationSource with `repositoryPVC` field works flawlessly
5. **Kopia Repository Initialized** - `/repository` on kopia PVC, ready for use
6. **Volume Populator Configuration** - PVCs configured with `dataSourceRef` to ReplicationDestination

### ❌ What's Not Working
**Automated Restores** - Both methods blocked by the same root cause

## Architecture Comparison

### Method 1: destinationPVC (Original)
```yaml
# ReplicationDestination
spec:
  kopia:
    destinationPVC: app-config  # <-- Writes directly to existing PVC
    
# PVC created manually or by app
spec:
  resources:
    requests:
      storage: 5Gi
```

**Flow**: ReplicationDestination → Restore Job → Write to PVC  
**Status**: ❌ Job can't connect to filesystem repository

---

### Method 2: Volume Populator (Current)
```yaml
# ReplicationDestination  
spec:
  kopia:
    # No destinationPVC - creates VolumeSnapshot instead
    volumeSnapshotClassName: csi-cephfs-config-snapclass
    
# PVC references ReplicationDestination
spec:
  dataSourceRef:
    kind: ReplicationDestination
    apiGroup: volsync.backube
    name: app-dst  # <-- References ReplicationDestination
```

**Flow**: ReplicationDestination → Restore Job → VolumeSnapshot → Volume Populator → PVC  
**Status**: ❌ Still requires restore job to succeed (same blocker)

---

## Root Cause Analysis

**The Core Issue**: Volsync mover script cannot connect new users to existing Kopia filesystem repositories.

### Error Details
```
ERROR error connecting to repository: repository not initialized in the provided storage
Connection failed, creating new repository...
ERROR unable to get repository storage: found existing data in storage location
```

### Why This Happens
1. Repository exists at `/repository` (created as `volsync@volsync.volsync-system.svc.cluster.local`)
2. Restore job tries to connect as `app@namespace` (different user)
3. Kopia **supports** multi-user repositories ✅
4. Volsync mover script's connection logic **doesn't** handle this properly ❌

### Specific Failure Point
The volsync mover script logic:
1. Tries to connect → Fails (returns "not initialized")
2. Tries to create → Fails (data exists)
3. Gives up

**What it should do**: Connect with proper override parameters OR use KOPIA_MANUAL_CONFIG

---

## What onedr0p Actually Does

Based on research of [onedr0p/home-ops](https://github.com/onedr0p/home-ops):

**They likely use HTTP repository** (not filesystem) OR **manual restores only**:

### Evidence:
1. Their ExternalSecret has `KOPIA_REPOSITORY: filesystem:///repository` (same as ours)
2. Their disaster recovery is described as "hands-off" via volume populator
3. **BUT**: Volume populator still requires successful restore jobs to create snapshots

### Most Likely Scenario:
- onedr0p uses **rsync-based** volsync (not Kopia) for actual automated restores
- OR uses Kopia only for backups, manual restores
- OR has Kopia HTTP server properly configured (we couldn't verify)

---

## Solutions & Trade-offs

### Option 1: HTTP Server (**Proper** Long-term Fix)
**Configure Kopia HTTP server for API access**

**Pros**:
- ✅ Designed for multi-user scenarios
- ✅ Standard volsync pattern
- ✅ No MutatingAdmissionPolicy needed for restores

**Cons**:
- ❌ Complex setup (user management, authentication)
- ❌ Additional infrastructure
- ❌ We already have filesystem repository working for backups

**Implementation**:
1. Configure Kopia server with `--server-users` or API tokens
2. Update secrets with HTTP credentials
3. Test restore jobs

---

### Option 2: Fix Volsync Mover (**Upstream** Contribution)
**Patch volsync mover script to handle multi-user filesystem repos**

**Pros**:
- ✅ Benefits entire community
- ✅ Enables filesystem repos for everyone
- ✅ Cleaner architecture

**Cons**:
- ❌ Requires upstream contribution
- ❌ Time to merge & release
- ❌ Need to maintain fork until then

**Implementation**:
1. Fork volsync
2. Fix mover script connection logic
3. Test & submit PR
4. Use custom image until merged

---

### Option 3: Manual Restores (Current **Working** State)
**Use documented manual procedure**

**Pros**:
- ✅ Works TODAY
- ✅ Well-documented in [KOPIA_MANUAL_RESTORE.md](KOPIA_MANUAL_RESTORE.md)
- ✅ Backups fully automated
- ✅ Simple architecture

**Cons**:
- ❌ Not hands-off DR
- ❌ Requires manual intervention per app

**Usage**: See [KOPIA_MANUAL_RESTORE.md](KOPIA_MANUAL_RESTORE.md) for procedures

---

## MutatingAdmissionPolicy Value

Even with manual restores, MutatingAdmissionPolicy provides:

1. ✅ **Backup Job Jitter** - Prevents backup storms (all apps backing up simultaneously)
2. ✅ **Maintenance Job Repository Access** - Auto-mounts repository for Kopia maintenance
3. ✅ **Future-Proof** - Ready when volsync fixes filesystem repo support
4. ✅ **Innovation Showcase** - Testing bleeding-edge K8s features

---

## Recommendations

### Short Term (Production Ready)
**Use Manual Restores + Automated Backups**

1. Keep current configuration (filesystem repository)
2. Rely on automated backups (working perfectly)
3. Use manual restore procedures for DR
4. MutatingAdmissionPolicy provides backup jitter

**This is stable and production-ready.**

---

### Long Term (Full Automation)
**Choose ONE**:

1. **Easy**: Switch to HTTP repository (if Kopia server config is documented)
2. **Impactful**: Contribute volsync mover fix upstream
3. **Alternative**: Switch to rsync-based volsync (like onedr0p might use)

---

## Test Results

### Backup Test ✅
```
Snapshot: k7ecb37177b0c5be5cd6fa41a21eba05e
Identity: atuin-src@default
Size: 227.2 KB
Status: SUCCESS
```

### MutatingAdmissionPolicy Test ✅
```
Job: volsync-src-atuin-src
InitContainers: jitter (✅ injected by policy)
Volumes: repository (✅ injected by policy)
PVC: kopia (✅ correct mount)
Status: WORKING
```

### Restore Test ❌
```
Job: volsync-dst-atuin-dst
Error: repository not initialized in the provided storage
Root Cause: Volsync mover script connection logic
Blocker: Multi-user filesystem repo not supported
```

---

## Related Documentation

- [KOPIA_MANUAL_RESTORE.md](KOPIA_MANUAL_RESTORE.md) - Working manual restore procedures
- [kubernetes/components/volsync/](../kubernetes/components/volsync/) - Volsync component configuration
- [kubernetes/apps/6-data/volsync/app/mutatingadmissionpolicy.yaml](../kubernetes/apps/6-data/volsync/app/mutatingadmissionpolicy.yaml) - Policy definitions

---

**Last Updated**: 2025-11-29  
**Cluster Version**: Kubernetes v1.35.0-alpha.3 + Talos v1.12.0-beta.0  
**Volsync Version**: v0.16.12

# Cluster Rebuild Issues & Long-Term Fixes

This document summarizes issues encountered during cluster rebuild and their long-term solutions.

---

## Issue 1: Ceph-CSI HelmReleases Not Reconciling

### Symptoms
- HelmReleases stuck with error: `"HelmChart is not ready: latest generation of object has not been reconciled"`
- HelmCharts successfully pulled but HelmReleases remained in `False/Error` state
- Timestamps in status conditions showed `1970-01-01T00:00:00Z` (epoch 0)

### Root Cause
Transient state in Flux where the HelmRelease controller waits for HelmChart's `ObservedGeneration` to match current `Generation`. This is a known temporary condition but can persist if the helm-controller gets stuck.

### Short-Term Fix
```bash
flux reconcile helmrelease ceph-csi-cephfs -n ceph-csi
flux reconcile helmrelease ceph-csi-rbd -n ceph-csi
```

### Long-Term Fix
**Add health checks and retry logic to infrastructure kustomizations:**

```yaml
# kubernetes/infrastructure/2-foundation/ceph-csi/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ceph-csi
spec:
  # ... existing config ...
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: ceph-csi-cephfs
      namespace: ceph-csi
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: ceph-csi-rbd
      namespace: ceph-csi
  timeout: 10m  # Allow time for large image pulls
  retryInterval: 2m
```

**Monitor for this pattern:**
- If rebuilding frequently, consider pre-pulling CSI images to nodes
- Or use a local container registry mirror

---

## Issue 2: Kopia Repository PVC Pointing to Wrong Subvolume

### Symptoms
- Restore jobs completed but found "No snapshots found"
- Kopia repository appeared empty even though backups existed
- PVC bound to a NEW subvolume instead of existing one with data

### Root Cause
When Kopia PVC was deleted and recreated by Flux, CephFS CSI provisioner created a **new** subvolume instead of reconnecting to the existing one. The volumeHandle changed from the saved value to a new UUID.

### Short-Term Fix
1. Delete the incorrectly-created PVC
2. Run `./scripts/dr-2-reclaim-kopia-repository.sh` to create PV/PVC with correct volumeHandle

### Long-Term Fix
**Exclude Kopia repository PVC from Flux management entirely:**

Already implemented:
- ✅ Removed `kopia-repository-pvc.yaml` from kopia app kustomization
- ✅ Removed `kopia-repository-pvc.yaml` from volsync component kustomization
- ✅ PVC managed exclusively via reclaim script during DR

**Why this works:**
- PVC is created once with correct volumeHandle during cluster rebuild
- Flux never touches it afterward
- Survives cluster rebuilds because volumeHandle is saved in Git
- Component kustomizations no longer try to manage it

**File locations:**
- Excluded from: `kubernetes/apps/6-data/kopia/app/kustomization.yaml`
- Excluded from: `kubernetes/components/volsync/kustomization.yaml`
- Managed by: `scripts/dr-2-reclaim-kopia-repository.sh`

---

## Issue 3: ReplicationDestination Missing `copyMethod` Field

### Symptoms
- ReplicationDestination status showed: `unsupported copyMethod: -- must be Direct, None, or Snapshot`
- Volume populator pattern not working
- PVCs stuck in Pending waiting for VolumeSnapshots

### Root Cause
The volsync component template `replicationdestination.yaml` was missing the `copyMethod: Snapshot` field, which is required for the volume populator pattern.

### Short-Term Fix
Added `copyMethod: Snapshot` to the template at line 25.

### Long-Term Fix
**Already implemented - verify in template:**

File: `kubernetes/components/volsync/replicationdestination.yaml`

```yaml
spec:
  kopia:
    repository: "${APP}-volsync-secret"
    sourceIdentity:
      sourceName: "${APP}-src"
      sourceNamespace: "${NAMESPACE:-default}"

    # CRITICAL: Required for volume populator pattern
    copyMethod: Snapshot

    storageClassName: "${VOLSYNC_STORAGECLASS:=csi-cephfs-config-sc}"
    accessModes:
      - "${VOLSYNC_ACCESSMODES:=ReadWriteMany}"
    capacity: "${VOLSYNC_CAPACITY:=5Gi}"

    # Snapshot class for volume populator
    volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:=csi-cephfs-config-snapclass}"
```

**Validation:**
After cluster rebuild, verify all ReplicationDestinations have copyMethod:
```bash
kubectl get replicationdestination -A -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.kopia.copyMethod}{"\n"}{end}'
```

Expected output: All should show `Snapshot`

---

## Issue 4: Kopia PVC Conflicts - Multiple Kustomizations Managing Same Resource

### Symptoms
- All app kustomizations failing with PVC conflicts
- Error: `spec is immutable after creation except resources.requests`
- Flux trying to update `volumeName` field on bound PVC

### Root Cause
The volsync **component** at `kubernetes/components/volsync/kustomization.yaml` included `kopia-repository-pvc.yaml` in its resources. Since ALL apps use this component via `components: - ../../../../components/volsync`, every app was trying to manage the Kopia repository PVC!

### Discovery Process
1. Initially tried `IfNotPresent` label on PVC - didn't work
2. Removed from kopia app kustomization - didn't work
3. Deleted all app kustomizations to force recreation - STILL didn't work
4. **Found root cause**: Component included the PVC, affecting all apps

### Short-Term Fix
Removed `kopia-repository-pvc.yaml` from volsync component kustomization.

### Long-Term Fix
**Already implemented - verify component structure:**

File: `kubernetes/components/volsync/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./externalsecret.yaml
  # kopia-repository-pvc.yaml MUST NOT be here - managed manually
  - ./pvc.yaml  # App-specific PVC template only
  - ./replicationdestination.yaml
  - ./replicationsource.yaml
```

**Key principle:**
- Components are included by ALL apps
- Only include resources that should be created PER APP
- Never include shared/singleton resources in components
- Manage shared resources (like kopia PVC) separately

**Validation:**
```bash
# Verify component doesn't include kopia PVC
grep -r "kopia-repository-pvc" kubernetes/components/volsync/
# Should return: No matches

# Verify apps can reconcile without conflicts
flux get ks --all-namespaces | grep -E "sonarr|radarr|plex"
# Should all show: Ready True
```

---

## Issue 5: DR Script Hanging on kubectl patch

### Symptoms
- `dr-3-trigger-restores.sh` hung after first app with no output
- No error messages, just silent hang
- Script appeared stuck indefinitely

### Root Cause
1. `kubectl patch` command without timeout could hang on slow API responses
2. `((RESTORE_COUNT++))` arithmetic expansion with `set -euo pipefail` caused silent failures in some shell contexts

### Short-Term Fix
Added timeout and changed arithmetic syntax:
```bash
timeout 10 kubectl patch "$rd" ...
RESTORE_COUNT=$((RESTORE_COUNT + 1))  # Instead of ((RESTORE_COUNT++))
```

### Long-Term Fix
**Already implemented - script best practices applied:**

File: `scripts/dr-3-trigger-restores.sh`

```bash
set -euo pipefail

# All kubectl commands should have timeouts
for rd in $(kubectl get replicationdestination -n default -o name); do
  app=$(echo "$rd" | sed 's|.*/||;s/-dst$//')
  echo "  Triggering restore: $app"

  # Timeout prevents indefinite hangs
  if ! timeout 10 kubectl patch "$rd" -n default --type=merge \
       -p "{\"spec\":{\"trigger\":{\"manual\":\"restore-${TIMESTAMP}\"}}}" &>/dev/null; then
    echo "    ⚠️  Failed to patch $app (continuing...)"
  fi

  # Portable arithmetic syntax
  RESTORE_COUNT=$((RESTORE_COUNT + 1))
done
```

**Best practices for all DR scripts:**
1. Always use `timeout` with kubectl commands (default: 10-30s)
2. Use `$((expr))` instead of `(( ))` for arithmetic with pipefail
3. Add error handling to continue on failures
4. Provide progress output for long-running operations

---

## Issue 6: LoadBalancer Services Missing IPv4 Addresses

### Symptoms
- Services stuck in `EXTERNAL-IP: <pending>` state
- Annotations had IPv6 addresses but no IPv4
- Cilium LB-IPAM not assigning IPs

### Root Cause
Dual-stack cluster requires **both** IPv4 and IPv6 addresses in `lbipam.cilium.io/ips` annotation. Services only had IPv6 addresses specified.

### Short-Term Fix
Updated annotations to include both:
```yaml
annotations:
  lbipam.cilium.io/ips: fd00:101::1b:122,10.101.27.122  # IPv6,IPv4
```

### Long-Term Fix
**Document dual-stack requirements and create validation:**

Create validation script: `scripts/validate-loadbalancer-ips.sh`

```bash
#!/usr/bin/env bash
# Validate LoadBalancer services have both IPv4 and IPv6 IPs

echo "Checking LoadBalancer services for dual-stack configuration..."

ISSUES=0

for svc in $(kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"'); do
  IPS=$(kubectl get svc $svc -o jsonpath='{.metadata.annotations.lbipam\.cilium\.io/ips}')

  if [[ -z "$IPS" ]]; then
    echo "⚠️  $svc: No lbipam annotation"
    ((ISSUES++))
    continue
  fi

  if ! echo "$IPS" | grep -q ","; then
    echo "❌ $svc: Only one IP specified: $IPS"
    echo "   Should have: IPv6,IPv4 (e.g., fd00:101::1b:120,10.101.27.120)"
    ((ISSUES++))
  else
    echo "✅ $svc: $IPS"
  fi
done

if [ $ISSUES -gt 0 ]; then
  echo ""
  echo "❌ Found $ISSUES services with IP configuration issues"
  exit 1
else
  echo ""
  echo "✅ All LoadBalancer services properly configured"
fi
```

**Template for new services:**
```yaml
service:
  app:
    type: LoadBalancer
    annotations:
      external-dns.alpha.kubernetes.io/hostname: myapp.sulibot.com
      lbipam.cilium.io/ips: fd00:101::1b:XXX,10.101.27.XXX  # BOTH required!
    externalTrafficPolicy: Local
    ports:
      http:
        port: 80
```

**IP allocation scheme:**
- IPv6: `fd00:101::1b:XXX` (where XXX = 100-255)
- IPv4: `10.101.27.XXX` (where XXX matches IPv6)
- Keep last octet consistent for easy mapping

---

## Issue 7: Gateway API Gateways Not Programmed

### Symptoms
- Gateways stuck in `PROGRAMMED: Unknown` state
- Status conditions showed `1970-01-01T00:00:00Z` (epoch 0)
- HTTPRoutes had no effect - no DNS entries created
- Message: "Waiting for controller"

### Root Cause
Cilium operator's Gateway API controller not running or stuck. The epoch 0 timestamp indicated the controller never updated the Gateway status.

### Short-Term Fix
```bash
kubectl rollout restart deployment/cilium-operator -n kube-system
```

After restart, Gateways immediately became Programmed with IP addresses.

### Long-Term Fix
**Add automated health monitoring and recovery:**

1. **Add Gateway health checks to cilium kustomization:**

File: `kubernetes/infrastructure/2-foundation/cilium/ks.yaml`

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
spec:
  # ... existing config ...
  healthChecks:
    - apiVersion: gateway.networking.k8s.io/v1
      kind: Gateway
      name: gateway-external
      namespace: network
    - apiVersion: gateway.networking.k8s.io/v1
      kind: Gateway
      name: gateway-internal
      namespace: network
  timeout: 5m
```

2. **Create monitoring alert for unprogrammed Gateways:**

File: `kubernetes/observability/kube-prometheus-stack/app/prometheusrules/gateway-alerts.yaml`

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gateway-alerts
  namespace: observability
spec:
  groups:
    - name: gateway
      interval: 1m
      rules:
        - alert: GatewayNotProgrammed
          expr: |
            gateway_api_gateway_status{type="Programmed",status="False"} == 1
            or
            gateway_api_gateway_status{type="Programmed",status="Unknown"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Gateway {{ $labels.name }} is not programmed"
            description: "Gateway {{ $labels.name }} in {{ $labels.namespace }} has been unprogrammed for 5 minutes"
```

3. **Document in cluster rebuild runbook:**

After cluster rebuild, verify Gateways before proceeding:
```bash
# Check Gateway status
kubectl get gateway -A

# Should show:
# NAME               CLASS    ADDRESS         PROGRAMMED   AGE
# gateway-external   cilium   10.0.101.64     True         Xm
# gateway-internal   cilium   fd00:101:1b::10 True         Xm

# If PROGRAMMED shows Unknown or False, restart operator:
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system
```

---

## Issue 8: External-DNS Not Creating AAAA Records for LoadBalancer Services

### Symptoms
- LoadBalancer services (smtp-relay, mosquitto) only got A records in RouterOS
- Missing AAAA (IPv6) records
- Annotation has both IPs but only IPv4 appears in DNS

### Root Cause
Kubernetes LoadBalancer `.status.loadBalancer.ingress[]` only reports **one IP** in the status, even though both IPv4 and IPv6 are requested via the Cilium annotation. External-DNS reads from the LoadBalancer status field, not from annotations.

### Current State
- A records created: ✅ (from LoadBalancer status)
- AAAA records created: ❌ (not in LoadBalancer status)

### Long-Term Fix Options

**Option 1: Manual AAAA Records (Quick Fix)**
Manually add AAAA records to RouterOS for LoadBalancer services:
```bash
ssh admin@router.sulibot.com
/ip dns static add name=smtp-relay.sulibot.com type=AAAA address=fd00:101::1b:122
/ip dns static add name=mosquitto.sulibot.com type=AAAA address=fd00:101::1b:129
```

**Option 2: External-DNS Annotation Support (Better)**
Configure external-dns to read IPv6 from service annotations.

Research needed: Check if external-dns supports reading both IPs from `lbipam.cilium.io/ips` annotation.

Potential configuration:
```yaml
# In external-dns deployment args
--annotation-filter=lbipam.cilium.io/ips
```

**Option 3: Dual-Stack LoadBalancer Status (Proper)**
Configure Cilium to report both IPs in LoadBalancer status.

File: `kubernetes/infrastructure/2-foundation/cilium/app/values.yaml`

Research Cilium documentation for:
```yaml
loadBalancer:
  dualStack: true  # or similar option
```

**Recommended Approach:**
1. Short term: Use manual AAAA records (5 minutes)
2. Medium term: Research external-dns annotation support
3. Long term: Configure Cilium dual-stack LoadBalancer status properly

**Tracking:**
- Document which LoadBalancer services need manual AAAA records
- Create script to sync AAAA records from annotations
- Monitor Cilium releases for dual-stack LoadBalancer status support

---

## Issue 9: ReplicationDestination `IfNotPresent` Didn't Work

### Symptoms
- Added `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` label to ReplicationDestination
- Flux still tried to update existing resources
- `copyMethod` field wasn't applied to existing RDs

### Root Cause
`IfNotPresent` in Flux SSA means "don't update if field exists", but for NEW fields (like `copyMethod` that didn't exist), Flux should still add them. However, the generation tracking might have prevented reconciliation.

### Short-Term Fix
Deleted all ReplicationDestinations and let Flux recreate them with correct spec.

### Long-Term Fix
**Remove `IfNotPresent` from ReplicationDestination template:**

File: `kubernetes/components/volsync/replicationdestination.yaml`

```yaml
---
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: "${APP}-dst"
  labels:
    app.kubernetes.io/name: "${APP}"
    app.kubernetes.io/component: backup-restore
    # REMOVED: kustomize.toolkit.fluxcd.io/ssa: IfNotPresent
    # Let Flux manage ReplicationDestinations normally
spec:
  # ... rest of spec ...
```

**Why remove it:**
- ReplicationDestinations are app-specific, not shared resources
- They should be recreated during DR anyway
- Allowing Flux to fully manage them ensures spec updates are applied
- The `IfNotPresent` was originally added to prevent disruption, but RDs are declarative and safe to update

**Validation after change:**
```bash
# Verify all RDs have copyMethod
kubectl get replicationdestination -A -o yaml | grep -A 3 "kopia:" | grep "copyMethod"

# Should see "copyMethod: Snapshot" for all
```

---

## Complete Disaster Recovery Runbook

After implementing all long-term fixes, the DR process should be:

### 1. Pre-Flight Checks
```bash
# Check all required infrastructure is ready
./scripts/dr-1-check-readiness.sh

# Expected time: 15-20 minutes after Flux deployment
```

### 2. Reclaim Kopia Repository
```bash
# Reconnect to existing backup repository
./scripts/dr-2-reclaim-kopia-repository.sh

# Expected time: < 1 minute
```

### 3. Verify Gateways (Critical!)
```bash
# Ensure Gateway API is working
kubectl get gateway -A

# If PROGRAMMED shows Unknown:
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system
```

### 4. Trigger Restores
```bash
# Restore all 22 app config PVCs
./scripts/dr-3-trigger-restores.sh

# Expected time: 10-15 minutes
```

### 5. Verify Completion
```bash
# Verify all PVCs restored successfully
./scripts/dr-4-verify-restores.sh

# Expected time: < 1 minute
```

### 6. Validate DNS
```bash
# Verify external-dns created records
ssh admin@router.sulibot.com "/ip dns static print count-only"

# Should show 150+ records

# Check specific apps
nslookup plex.sulibot.com router.sulibot.com  # Should have both A and AAAA
```

### 7. Manual Fixes (Until Long-Term Solutions Implemented)
```bash
# Add missing AAAA records for LoadBalancer services
ssh admin@router.sulibot.com <<'EOF'
/ip dns static add name=smtp-relay.sulibot.com type=AAAA address=fd00:101::1b:122
/ip dns static add name=mosquitto.sulibot.com type=AAAA address=fd00:101::1b:129
EOF
```

---

## Monitoring & Validation Scripts

### Post-Rebuild Validation
Create: `scripts/validate-cluster-dr.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Cluster DR Validation ==="
echo ""

ISSUES=0

# Check 1: Kopia repository
echo "✓ Checking Kopia repository..."
if kubectl get pvc kopia -n default | grep -q Bound; then
  VOLUME=$(kubectl get pvc kopia -n default -o jsonpath='{.spec.volumeName}')
  echo "  ✅ Kopia PVC bound to: $VOLUME"
else
  echo "  ❌ Kopia PVC not bound"
  ((ISSUES++))
fi

# Check 2: ReplicationDestinations have copyMethod
echo ""
echo "✓ Checking ReplicationDestinations..."
MISSING=$(kubectl get replicationdestination -A -o json | jq -r '.items[] | select(.spec.kopia.copyMethod != "Snapshot") | .metadata.name' | wc -l)
if [ "$MISSING" -eq 0 ]; then
  echo "  ✅ All RDs have copyMethod: Snapshot"
else
  echo "  ❌ $MISSING RDs missing copyMethod"
  ((ISSUES++))
fi

# Check 3: Gateways programmed
echo ""
echo "✓ Checking Gateways..."
UNPROGRAMMED=$(kubectl get gateway -A -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Programmed" and .status!="True")) | .metadata.name' | wc -l)
if [ "$UNPROGRAMMED" -eq 0 ]; then
  echo "  ✅ All Gateways programmed"
else
  echo "  ❌ $UNPROGRAMMED Gateways not programmed"
  ((ISSUES++))
fi

# Check 4: App PVCs bound
echo ""
echo "✓ Checking app config PVCs..."
PENDING=$(kubectl get pvc -n default | grep config | grep -c Pending || echo "0")
BOUND=$(kubectl get pvc -n default | grep config | grep -c Bound || echo "0")
echo "  Bound: $BOUND, Pending: $PENDING"
if [ "$PENDING" -gt 0 ]; then
  echo "  ⚠️  $PENDING PVCs still pending"
  ((ISSUES++))
fi

# Check 5: LoadBalancer dual-stack
echo ""
echo "✓ Checking LoadBalancer services..."
LB_SINGLE_IP=$(kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | select(.metadata.annotations."lbipam.cilium.io/ips" != null) | select(.metadata.annotations."lbipam.cilium.io/ips" | contains(",") | not) | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l)
if [ "$LB_SINGLE_IP" -gt 0 ]; then
  echo "  ⚠️  $LB_SINGLE_IP services with single IP (should have both IPv4/IPv6)"
  ((ISSUES++))
else
  echo "  ✅ All LoadBalancer services have dual-stack IPs"
fi

# Summary
echo ""
echo "=========================================="
if [ "$ISSUES" -eq 0 ]; then
  echo "✅ All validations passed!"
  exit 0
else
  echo "❌ Found $ISSUES issues"
  exit 1
fi
```

---

## Prevention Checklist

Before cluster rebuild, verify these are in place:

- [ ] Kopia repository subvolume ID saved in Git (`kopia-repository-subvolume-secret.yaml`)
- [ ] Kopia PVC excluded from kopia app kustomization
- [ ] Kopia PVC excluded from volsync component kustomization
- [ ] All ReplicationDestination templates have `copyMethod: Snapshot`
- [ ] `IfNotPresent` removed from ReplicationDestination template
- [ ] All LoadBalancer services have dual-stack IPs (IPv6,IPv4)
- [ ] DR scripts tested and working (especially dr-3 with timeout)
- [ ] Gateway health checks added to cilium kustomization
- [ ] Validation scripts exist and are executable

---

## Timeline Expectations

| Phase | Time | Cumulative |
|-------|------|------------|
| Flux deployed | 0 | 0 |
| Infrastructure ready (cert-manager, external-secrets, ceph-csi, volsync) | 15-20 min | 15-20 min |
| Run dr-1-check-readiness.sh | 1 min | 16-21 min |
| Run dr-2-reclaim-kopia-repository.sh | 1 min | 17-22 min |
| Check/fix Gateways if needed | 0-2 min | 17-24 min |
| Run dr-3-trigger-restores.sh | 1 min | 18-25 min |
| Wait for restores to complete | 10-15 min | 28-40 min |
| Run dr-4-verify-restores.sh | 1 min | 29-41 min |
| Apps start running | 1-5 min | **30-46 min total** |

**Best case:** 30 minutes from cluster rebuild to apps running
**Typical case:** 35-40 minutes
**Worst case (with Gateway issue):** 45 minutes

---

## References

- [Flux HelmRelease Troubleshooting](https://github.com/fluxcd/flux2/discussions/4855)
- [Cilium Gateway API Documentation](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/)
- [Volsync Documentation](https://volsync.readthedocs.io/)
- [External-DNS Mikrotik Provider](https://github.com/mirceanton/external-dns-provider-mikrotik)

---

**Last Updated:** 2025-12-02
**Cluster Version:** Kubernetes v1.35.0-alpha.3 + Talos v1.12.0-beta.0
**Tested By:** Disaster Recovery from cluster-101 rebuild

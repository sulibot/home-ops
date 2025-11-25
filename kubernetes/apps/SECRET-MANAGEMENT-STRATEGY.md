# Secret Management Strategy: SOPS vs External Secrets

## The Chicken-and-Egg Problem

**Problem:** If External Secrets depends on Ceph for storage, and Ceph depends on External Secrets for credentials, you have a circular dependency:

```
External Secrets
  ↓ (needs storage)
Ceph CSI
  ↓ (needs credentials)
External Secrets  ← CIRCULAR!
```

## Recommended Solution: Layered Secret Management

Use **different secret management approaches for different layers**:

### Layer 0-2: Infrastructure Secrets → **SOPS**
- Ceph credentials
- External Secrets bootstrap credentials (1Password token)
- Cert-Manager CA keys
- Database root passwords
- Talos secrets

### Layer 3+: Application Secrets → **External Secrets**
- App API keys
- OAuth credentials
- Service passwords
- TLS certificates

## Why This Works

### SOPS Benefits for Infrastructure:
1. **No runtime dependencies** - secrets are decrypted by Flux at apply time
2. **Git-native** - secrets stored encrypted in your repo
3. **No external service dependency** - works even if 1Password is down
4. **Faster bootstrap** - no waiting for External Secrets controller
5. **Disaster recovery** - can rebuild cluster from Git alone

### External Secrets Benefits for Applications:
1. **Centralized management** - update in 1Password, auto-syncs everywhere
2. **Rotation** - can rotate secrets without Git commits
3. **Audit trail** - 1Password logs all access
4. **Team sharing** - multiple people can manage secrets
5. **No Git commits** - sensitive data never in Git, even encrypted

## Implementation Pattern

### Step 1: SOPS for Ceph

```yaml
# kubernetes/apps/storage/ceph-csi/cephfs/app/secret.sops.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ceph-csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: admin
  userKey: ENC[AES256_GCM,data:base64encryptedkey...]  # ← SOPS encrypted
  adminID: admin
  adminKey: ENC[AES256_GCM,data:base64encryptedkey...]
```

```yaml
# kubernetes/apps/storage/ceph-csi/cephfs/app/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
  - secret.sops.yaml  # ← Flux decrypts with SOPS
```

### Step 2: SOPS for External Secrets Bootstrap

```yaml
# kubernetes/apps/security/external-secrets/onepassword/app/secret.sops.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-token
  namespace: external-secrets
stringData:
  token: ENC[AES256_GCM,data:1passwordtoken...]  # ← SOPS encrypted
```

This allows External Secrets to start **without depending on itself**.

### Step 3: External Secrets for Applications

```yaml
# kubernetes/apps/default/plex/app/externalsecret.yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: plex-secret
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: plex-secret
  data:
    - secretKey: PLEX_CLAIM
      remoteRef:
        key: plex
        property: claim-token
```

```yaml
# kubernetes/apps/default/plex/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: plex
spec:
  dependsOn:
    - name: external-secrets  # ← App depends on External Secrets
      namespace: flux-system
    - name: onepassword
      namespace: flux-system
    - name: ceph-csi-cephfs
      namespace: flux-system
  # But Ceph doesn't depend on External Secrets!
```

## Dependency Graph

### With Layered Approach (Good):
```
SOPS (built into Flux)
  ↓
Ceph CSI (uses SOPS secrets)
  ↓
External Secrets Operator (uses SOPS for bootstrap, stores state in Ceph)
  ↓
Applications (use External Secrets)
```

### Without Layering (Bad - Circular):
```
External Secrets
  ↓
Ceph CSI (stores External Secrets data)
  ↑
External Secrets (needs Ceph for credentials)  ← DEADLOCK!
```

## What Secrets Go Where?

### Use SOPS for:
- ✅ Ceph cluster credentials
- ✅ Ceph CSI driver secrets
- ✅ 1Password Connect token
- ✅ External Secrets operator credentials
- ✅ Cert-Manager CA private keys
- ✅ Database root/admin passwords
- ✅ CloudNative-PG bootstrap secrets
- ✅ Backup encryption keys
- ✅ Talos secrets
- ✅ Age/GPG keys for SOPS itself

### Use External Secrets for:
- ✅ Application API keys (Sonarr, Radarr, etc.)
- ✅ OAuth client secrets
- ✅ SMTP credentials
- ✅ GitHub tokens
- ✅ Cloudflare API keys
- ✅ Monitoring webhook URLs
- ✅ Application database passwords
- ✅ TLS certificates (non-CA)
- ✅ Service account keys

### Rule of Thumb:
**If it's needed before External Secrets is running → SOPS**
**If it changes frequently or is shared → External Secrets**

## Example: Current Directory Structure

Your existing setup already does some of this! Let's verify:

```bash
# Check what's using SOPS
find kubernetes/apps -name "*.sops.yaml" -o -name "*secret*.yaml"

# Check what's using External Secrets
find kubernetes/apps -name "*externalsecret.yaml"
```

## Migration Path

If you currently use External Secrets for Ceph:

### Step 1: Create SOPS secret for Ceph
```bash
# Create unencrypted secret file
cat <<EOF > /tmp/ceph-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ceph-csi-cephfs-secret
  namespace: ceph-csi
stringData:
  userID: admin
  userKey: "YOUR_CEPH_KEY"
  adminID: admin
  adminKey: "YOUR_ADMIN_KEY"
EOF

# Encrypt with SOPS
sops --encrypt --in-place /tmp/ceph-secret.yaml

# Move to correct location
mv /tmp/ceph-secret.yaml kubernetes/apps/storage/ceph-csi/cephfs/app/secret.sops.yaml
```

### Step 2: Update Kustomization
```yaml
# kubernetes/apps/storage/ceph-csi/cephfs/app/kustomization.yaml
resources:
  - helmrelease.yaml
  - secret.sops.yaml  # ← Add this
  # Remove externalsecret.yaml
```

### Step 3: Update Ceph CSI dependency
```yaml
# kubernetes/apps/storage/ceph-csi/ks.yaml
spec:
  dependsOn:
    - name: cilium
      namespace: flux-system
    - name: snapshot-controller
      namespace: flux-system
    # Remove external-secrets dependency!
```

### Step 4: Update External Secrets dependency
```yaml
# kubernetes/apps/security/external-secrets/ks.yaml
spec:
  dependsOn:
    - name: cilium
      namespace: flux-system
    - name: ceph-csi  # ← Now External Secrets can depend on Ceph!
      namespace: flux-system
```

## Disaster Recovery Benefits

### Scenario: 1Password is Down

**With SOPS for infrastructure:**
```bash
# Can still rebuild cluster from Git
flux bootstrap github ...
# All infrastructure secrets decrypt from Git
# Ceph, CNI, cert-manager all work
# Only apps using External Secrets are affected
```

**Without SOPS (all External Secrets):**
```bash
# Cannot rebuild cluster
flux bootstrap github ...
# Ceph won't start (no credentials)
# Storage unavailable
# External Secrets can't start (no storage)
# Everything is blocked ← TOTAL FAILURE
```

## Security Considerations

### SOPS Security:
- Secrets encrypted at rest in Git
- Decrypt key stored in Flux namespace (or age key in cluster)
- Need cluster access to decrypt
- Audit trail via Git commits

### External Secrets Security:
- Secrets never in Git
- Stored in 1Password (SOC 2, encryption at rest)
- Can revoke 1Password access independently
- Better for compliance (GDPR, SOC 2)

### Best of Both:
- Infrastructure bootstraps securely with SOPS
- Applications get compliance benefits of External Secrets
- No single point of failure

## Monitoring

### Alert on SOPS Decryption Failures:
```promql
gotk_kustomize_condition{
  type="Ready",
  status="False",
  reason=~".*sops.*|.*decrypt.*"
}
```

### Alert on External Secrets Sync Failures:
```promql
externalsecret_sync_calls_error{} > 0
```

## Summary

| Aspect | SOPS | External Secrets |
|--------|------|------------------|
| **Use for** | Infrastructure | Applications |
| **Dependencies** | None (Flux built-in) | Needs storage + network |
| **Rotation** | Git commit required | Automatic from 1Password |
| **Disaster Recovery** | Excellent | Depends on external service |
| **Team Sharing** | Via Git | Via 1Password |
| **Compliance** | Git audit trail | External audit trail |
| **Bootstrap** | Immediate | Needs controller running |

## Recommendation

1. ✅ **Use SOPS** for:
   - Ceph credentials
   - External Secrets bootstrap token
   - Database admin passwords
   - Any secret needed during cluster bootstrap

2. ✅ **Use External Secrets** for:
   - Application API keys
   - OAuth secrets
   - Frequently rotated credentials
   - Secrets shared across teams

3. ✅ **Never create circular dependencies**:
   - Storage should NOT depend on External Secrets
   - External Secrets CAN depend on storage
   - Applications depend on both

This gives you the **best of both worlds**: resilient infrastructure that can bootstrap independently, and convenient application secret management with rotation and central control.

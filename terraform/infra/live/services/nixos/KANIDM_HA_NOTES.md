# Kanidm HA Architecture Notes

## Current Limitation

Kanidm **only supports 2-node active-active** replication. Multi-master clustering beyond two nodes is not currently available.

Source: [Kanidm Replication Docs](https://kanidm.github.io/kanidm/stable/repl/index.html)

## Recommended Setup

### Option 1: Active-Active Pair (Recommended)

**Deploy only kanidm01 + kanidm02**:
- Both nodes are read-write (active-active)
- Eventually consistent replication
- Automatic failover

```bash
cd kanidm01 && terragrunt apply
cd kanidm02 && terragrunt apply
```

### Option 2: Active-Active + Backup

**kanidm01 + kanidm02**: Active-active pair
**kanidm03**: Backup/DR (separate standalone instance, manual sync)

### Option 3: Active-Active + Dev

**kanidm01 + kanidm02**: Production
**kanidm03**: Development/testing environment

## Current Config Status

All three configs exist, but **kanidm03 replication won't work as designed** since Kanidm doesn't support 3-node clusters.

### To Deploy 2-Node HA Only

```bash
cd terraform/infra/live/services/nixos
terragrunt apply --terragrunt-working-dir kanidm01
terragrunt apply --terragrunt-working-dir kanidm02
# Skip kanidm03 or repurpose it
```

### To Repurpose kanidm03

Edit `kanidm03/terragrunt.hcl` to remove replication settings and run as standalone:

```hcl
# Remove replication_peer - run as standalone instance
services.kanidm.serverSettings = {
  domain = "auth-dev.example.com";  # Different domain for dev
  origin = "https://auth-dev.example.com";
  db_path = "/var/lib/kanidm/kanidm.db";
  bindaddress = "0.0.0.0:8443";
  # No replication settings
};
```

## Disk Sizing

- **40GB per node** (reduced from 100GB)
- SQLite database grows slowly
- Adequate for 10k+ users

## Load Balancing

Use external load balancer (HAProxy/Traefik) to distribute traffic:

```
           ┌─────────────┐
           │ Load Balancer│
           │  (HAProxy)   │
           └──────┬───────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   ┌────▼────┐         ┌────▼────┐
   │kanidm01 │◄───────►│kanidm02 │
   │(active) │ Sync    │(active) │
   └─────────┘         └─────────┘

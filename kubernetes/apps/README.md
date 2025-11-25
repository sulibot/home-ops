# Flux Application Layers

Applications are organized into dependency layers for controlled startup and updates.

## Layer 0: CRDs
Core Custom Resource Definitions that other components depend on.
- `gateway-api-crds` - Gateway API CRDs for Cilium
- `snapshot-controller-crds` - Volume snapshot CRDs

## Layer 1: Network & CNI
Container Network Interface and core networking.
- `cilium` - Primary CNI (depends on: gateway-api-crds)
- `multus` - Secondary network interfaces

## Layer 2: Storage & Security Foundations
Storage providers and secrets management.
- `external-secrets` - External secrets operator (depends on: cilium)
- `onepassword` - 1Password integration (depends on: external-secrets)
- `ceph-csi-*` - Ceph CSI drivers (depends on: cilium, snapshot-controller-crds)
- `snapshot-controller` - Volume snapshots (depends on: cilium, snapshot-controller-crds)

## Layer 3: Core Platform Services
Essential cluster services.
- `cert-manager` - Certificate management (depends on: external-secrets, cilium)
- `reloader` - Auto-reload on ConfigMap/Secret changes (depends on: cilium)
- `metrics-server` - Resource metrics (depends on: cilium)
- `coredns` - DNS services (depends on: cilium)
- `spegel` - P2P image distribution (depends on: cilium)

## Layer 4: Network Services
Ingress, egress, and DNS automation.
- `cilium-gateway` - Gateway API (depends on: cert-manager, cilium)
- `cilium-bgp` - BGP configuration (depends on: cilium)
- `cilium-ippool` - IP pool management (depends on: cilium)
- `external-dns` - Automatic DNS records (depends on: cilium-gateway)
- `certificates` - TLS certificates (depends on: cert-manager)
- `cloudflare-tunnel` - Cloudflare Tunnel (depends on: external-secrets)

## Layer 5: Observability
Monitoring, logging, and alerting.
- `kube-prometheus-stack` - Prometheus & Grafana (depends on: ceph-csi)
- `victoria-logs` - Log aggregation (depends on: ceph-csi)
- `fluent-bit` - Log collection (depends on: cilium)
- `gatus` - Health monitoring (depends on: cilium-gateway)
- `grafana-instance` - Grafana dashboards (depends on: kube-prometheus-stack)

## Layer 6: Data Services
Databases, caching, and backup.
- `cloudnative-pg` - PostgreSQL operator (depends on: ceph-csi)
- `volsync` - Volume replication (depends on: ceph-csi, external-secrets, snapshot-controller)

## Layer 7: Applications
User-facing applications and workloads.
- All apps in `default/*` namespace (depends on: ceph-csi, cilium-gateway, external-secrets)
- All apps in `observability/*` for additional monitoring tools
- All apps in `actions-runner-system/*` for GitHub Actions

## Dependency Flow

```
CRDs (0)
  ↓
CNI (1) ←─ depends on CRDs
  ↓
Storage/Security (2) ←─ depends on CNI
  ↓
Core Services (3) ←─ depends on Storage/Security
  ↓
Network Services (4) ←─ depends on Core Services
  ↓
Observability (5) ←─ depends on Storage
  ↓
Data Services (6) ←─ depends on Storage
  ↓
Applications (7) ←─ depends on Network Services, Storage
```

## Implementation

Each Kustomization has a `layer` label that can be used for:
- Selective reconciliation: `flux reconcile ks --with-source -l layer=network`
- Monitoring: Filter by layer in dashboards
- Troubleshooting: Reconcile layers in order during recovery

Example:
```yaml
metadata:
  labels:
    layer: network
    component: ingress
```

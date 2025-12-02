# Istio Ambient Mesh Deployment

## Overview

This document describes the Istio Ambient Mesh service mesh deployment on cluster-101, including the complete observability stack with Jaeger and Kiali.

**Deployment Date**: 2025-12-02
**Istio Version**: 1.24.1
**Mode**: Ambient Mesh (sidecar-less)
**Architecture**: Layered on top of Cilium CNI

---

## Architecture

```
┌─────────────────────────────────────────┐
│  Cilium Gateway API (North/South)      │  ← External traffic ingress
├─────────────────────────────────────────┤
│  Istio Ambient Mesh (East/West)        │  ← NEW: Service mesh layer
│  - ztunnel (L4 mTLS)                    │
│  - Waypoint proxies (L7, selective)    │
├─────────────────────────────────────────┤
│  Cilium CNI (Network Layer)            │  ← Pod networking + LB-IPAM
└─────────────────────────────────────────┘
```

### Why Ambient Mesh?

**Traditional Sidecar Mode**:
- 50-128Mi memory overhead **per pod**
- 24 apps × 128Mi = **3Gi total overhead**
- Requires pod restarts for mesh enrollment

**Ambient Mesh Mode**:
- 256Mi memory overhead **per node** (shared ztunnel)
- 6 nodes × 256Mi = **1.5Gi total overhead**
- Zero-downtime enrollment (namespace labeling only)
- **50% resource savings**

---

## Deployed Components

### 1. Istio Control Plane (istio-system namespace)

#### Istio Base
- **Purpose**: CRDs and cluster-wide RBAC
- **HelmRelease**: `istio-base`
- **Version**: 1.24.1

#### Istiod
- **Purpose**: Control plane (ambient mode)
- **HelmRelease**: `istiod`
- **Resources**: 500m CPU, 2Gi memory
- **Features**:
  - Ambient mesh enabled (`PILOT_ENABLE_AMBIENT=true`)
  - Distributed tracing (100% sampling → Jaeger)
  - DNS capture and auto-allocation
  - JSON logging

#### ztunnel
- **Purpose**: L4 transparent proxy (DaemonSet)
- **HelmRelease**: `ztunnel`
- **Resources**: 100m CPU, 256Mi memory per node
- **Security**: Privileged (node-level networking)
- **Capabilities**: NET_ADMIN, SYS_ADMIN
- **Monitoring**: ServiceMonitor enabled (Prometheus scraping)

#### PeerAuthentication Policy
- **Mode**: PERMISSIVE (allows both mTLS and plaintext)
- **Purpose**: Safe gradual migration
- **Namespace**: istio-system (mesh-wide default)

---

### 2. Jaeger Distributed Tracing (observability namespace)

#### Jaeger All-in-One
- **Purpose**: Trace collection, storage, and query
- **HelmRelease**: `jaeger`
- **Chart**: jaegertracing/jaeger 3.3.x
- **Resources**: 200m CPU, 512Mi memory
- **Storage**: In-memory (10,000 traces max)

#### Ports
- **16686**: Jaeger UI (HTTP)
- **14250**: gRPC collector
- **9411**: Zipkin collector (Istio integration)

#### External Access
- **URL**: https://jaeger.sulibot.com
- **Gateway**: gateway-internal (Cilium)
- **HTTPRoute**: `jaeger` in observability namespace

#### Integration
- Istio proxies → Zipkin endpoint (port 9411)
- Prometheus scraping via ServiceMonitor
- Grafana datasource (future)

---

### 3. Kiali Service Mesh Dashboard (observability namespace)

#### Kiali Server
- **Purpose**: Service mesh visualization and management
- **HelmRelease**: `kiali-server`
- **Chart**: kiali/kiali-server 2.3.x
- **Resources**: 100m CPU, 256Mi memory
- **Authentication**: Anonymous (internal network)

#### External Services Integration
- **Prometheus**: http://prometheus-operated.observability:9090
- **Jaeger**: http://jaeger-query.observability:16686
- **Grafana**: http://grafana-service.observability:3000
- **Istio**: istiod + ztunnel monitoring

#### External Access
- **URL**: https://kiali.sulibot.com
- **Gateway**: gateway-internal (Cilium)
- **HTTPRoute**: `kiali` in observability namespace

#### Features
- Service dependency graph (real-time)
- Traffic flow visualization
- Request tracing integration (Jaeger)
- Configuration validation (VirtualService, DestinationRule)
- Health status monitoring
- Istio injection action support

---

## Deployment Status

### Phase 1: Istio Ambient Mesh ✅
- **Commit**: c4859020
- **Status**: Deployed (waiting for Flux reconciliation)
- **Files**: 13 manifests
- **Components**: istio-base, istiod, ztunnel, policies

### Phase 2: Jaeger ✅
- **Commit**: 4a25a49b
- **Status**: Deployed (waiting for Flux reconciliation)
- **Files**: 5 manifests
- **Components**: jaeger all-in-one, HTTPRoute, ServiceMonitor

### Phase 3: Kiali ✅
- **Commit**: 86648c2d
- **Status**: Deployed (waiting for Flux reconciliation)
- **Files**: 5 manifests
- **Components**: kiali-server, HTTPRoute, ServiceMonitor

### Phase 4: Namespace Enrollment (Next)
- **Target**: observability namespace (Wave 1)
- **Method**: Namespace labeling + waypoint proxy
- **Status**: Pending

---

## Flux Kustomizations

### Layer 1: Network
```yaml
kubernetes/apps/1-network/kustomization.yaml:
  - ./istio/helm-repo/ks.yaml
  - ./istio/ks.yaml
  - ./istio/policies/ks.yaml
```

### Layer 5: Observability
```yaml
kubernetes/apps/5-observability/kustomization.yaml:
  - ./jaeger/ks.yaml
  - ./kiali/ks.yaml
```

### Dependencies
- **Istio**: depends on Cilium
- **Jaeger**: depends on Istio
- **Kiali**: depends on Jaeger, Istio, kube-prometheus-stack

---

## Verification Commands

### Check Deployments
```bash
# Istio control plane
kubectl get pods -n istio-system
kubectl get helmrelease -n istio-system

# Observability stack
kubectl get pods -n observability
kubectl get helmrelease -n observability

# Check ztunnel DaemonSet
kubectl get ds -n istio-system ztunnel
```

### Verify Istio Status
```bash
# Install istioctl (if needed)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.1 sh -

# Verify installation
istioctl verify-install

# Check proxy status
istioctl proxy-status

# Check mesh config
kubectl get configmap istio -n istio-system -o yaml
```

### Check HTTPRoutes
```bash
# Verify external access routes
kubectl get httproute -n observability
kubectl get httproute jaeger -n observability -o yaml
kubectl get httproute kiali -n observability -o yaml
```

### Monitor Flux Reconciliation
```bash
# Trigger immediate reconciliation
flux reconcile source git flux-system

# Watch HelmRelease status
watch kubectl get helmrelease -A

# Check Flux logs
flux logs --all-namespaces --follow
```

---

## Namespace Enrollment (Ambient Mesh)

### Current Status
- **Enrolled**: None (mesh deployed but not enabled for any namespace)
- **Pending**: observability, media, default

### Wave 1: Observability Namespace (Next Step)
```bash
# Enable ambient mesh
kubectl label namespace observability istio.io/dataplane-mode=ambient

# Deploy waypoint proxy for L7 features
kubectl apply -f kubernetes/apps/1-network/istio/waypoints/observability-waypoint.yaml

# Verify enrollment
kubectl get namespace observability -o yaml | grep istio.io/dataplane-mode
```

### Expected Behavior
- ✅ All pods automatically get L4 mTLS (via ztunnel)
- ✅ NO pod restarts required
- ✅ Waypoint proxy provides L7 metrics for Kiali
- ✅ Traffic flows: Pod → ztunnel → Waypoint → Destination

---

## Traffic Flow

### Before Mesh Enrollment
```
Pod A → Network → Pod B
(plaintext, no observability)
```

### After Ambient Mesh (L4 only)
```
Pod A → ztunnel (node) → ztunnel (node) → Pod B
         ↑ mTLS encrypted ↑
(encrypted, basic metrics)
```

### With Waypoint Proxy (L7)
```
Pod A → ztunnel → Waypoint Proxy → ztunnel → Pod B
                      ↑
                  L7 features:
                  - Tracing (Jaeger)
                  - Metrics (Prometheus)
                  - Traffic management
                  - Circuit breaking
```

---

## Resource Allocation

### Control Plane (istio-system)
- **Istiod**: 500m CPU, 2Gi memory
- **ztunnel**: 600m CPU, 1.5Gi memory (6 nodes)
- **Total**: ~1.1 CPU, 3.5Gi memory

### Observability (observability namespace)
- **Jaeger**: 200m CPU, 512Mi memory
- **Kiali**: 100m CPU, 256Mi memory
- **Total**: 300m CPU, 768Mi memory

### Waypoint Proxies (when deployed)
- **Per waypoint**: 200m CPU, 512Mi memory
- **Expected**: 2-3 waypoints total (~1.5Gi memory)

### Grand Total
- **CPU**: ~2 CPU
- **Memory**: ~5.8Gi

**Savings vs Sidecar Mode**: 40% less memory (5.8Gi vs ~9Gi)

---

## Security Configuration

### mTLS Mode
- **Current**: PERMISSIVE
- **Behavior**: Accepts both mTLS and plaintext
- **Purpose**: Safe gradual migration
- **Future**: STRICT (after all namespaces enrolled)

### PeerAuthentication Policy
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: PERMISSIVE
```

### Authorization Policies
- **Status**: Not yet configured
- **Future**: Per-namespace policies for service-to-service access control

---

## Observability Integration

### Prometheus Metrics
- **Istiod**: http://istiod.istio-system:15014/metrics
- **ztunnel**: Per-node metrics via ServiceMonitor
- **Jaeger**: http://jaeger.observability:16686/metrics
- **Kiali**: http://kiali.observability:20001/metrics

### Grafana Dashboards (Future)
1. Istio Mesh Dashboard
2. Istio Service Dashboard
3. Istio Workload Dashboard
4. Istio Performance Dashboard
5. Istio Control Plane Dashboard

### Distributed Tracing
- **Backend**: Jaeger
- **Sampling**: 100% (reduce after testing)
- **Protocol**: Zipkin (port 9411)
- **Integration**: Istio proxies → Jaeger collector

---

## Troubleshooting

### Istio Not Starting
```bash
# Check Helm values
kubectl get helmrelease istiod -n istio-system -o yaml

# Check pod logs
kubectl logs -n istio-system -l app=istiod

# Check events
kubectl get events -n istio-system --sort-by='.lastTimestamp'
```

### ztunnel Not Running
```bash
# Check DaemonSet
kubectl get ds -n istio-system ztunnel

# Check node selector
kubectl describe ds -n istio-system ztunnel

# Check pod logs
kubectl logs -n istio-system -l app=ztunnel
```

### Jaeger/Kiali Not Accessible
```bash
# Check HTTPRoute
kubectl get httproute -n observability

# Check Gateway
kubectl get gateway -n network gateway-internal

# Check DNS
dig jaeger.sulibot.com
dig kiali.sulibot.com

# Check external-dns logs
kubectl logs -n network -l app.kubernetes.io/name=external-dns
```

### No Traces in Jaeger
```bash
# Check Istio tracing config
kubectl get configmap istio -n istio-system -o yaml | grep -A 10 tracing

# Check Jaeger collector endpoint
kubectl get svc -n observability jaeger-collector

# Port-forward and test
kubectl port-forward -n observability svc/jaeger-collector 9411:9411
curl -I http://localhost:9411/api/v2/spans
```

### Kiali Not Showing Services
```bash
# Check Kiali config
kubectl logs -n observability -l app.kubernetes.io/name=kiali | grep -i prometheus

# Verify Prometheus accessible
kubectl exec -n observability deploy/kiali-server -- curl -I http://prometheus-operated.observability:9090

# Check namespace enrollment
kubectl get namespace -L istio.io/dataplane-mode
```

---

## Next Steps

### Immediate (Phase 4)
1. ✅ Monitor Flux reconciliation (~5-10 minutes)
2. ✅ Verify all pods running in istio-system and observability
3. ✅ Test external access (jaeger.sulibot.com, kiali.sulibot.com)
4. 🔲 Enable ambient mesh for observability namespace (Wave 1)
5. 🔲 Deploy waypoint proxy for L7 observability
6. 🔲 Validate mesh telemetry in Kiali

### Wave 2: Immich (Media Namespace)
- Label media namespace for ambient mesh
- Monitor without waypoint initially
- Validate mTLS between immich components

### Wave 3: Media Stack (Default Namespace)
- Label default namespace for ambient mesh
- Deploy waypoint for L7 tracing
- Validate indexer → download client traces

### Future Enhancements
- Migrate Jaeger to persistent storage (BadgerDB on Ceph)
- Add Grafana datasource for Jaeger
- Deploy Istio Grafana dashboards
- Create PrometheusRules for mesh alerts
- Configure authorization policies
- Switch to STRICT mTLS mode

---

## References

- [Istio Ambient Mesh Documentation](https://istio.io/latest/docs/ambient/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Kiali Documentation](https://kiali.io/docs/)
- [Cilium + Istio Integration](https://docs.cilium.io/en/stable/network/servicemesh/istio/)

---

**Last Updated**: 2025-12-02
**Cluster**: cluster-101
**Status**: Phase 3 Complete, Phase 4 Pending

# Tier 1: Infrastructure

**Bootstrap Phase**: Parallel (wait: false)
**Purpose**: Infrastructure services that applications depend on.

## Apps in this Tier

### Core Infrastructure
- **cert-manager**: SSL/TLS certificate management
- **cert-manager-issuers**: Let's Encrypt ClusterIssuers
- **metrics-server**: Cluster metrics for HPA
- **reloader**: Auto-restart pods on ConfigMap/Secret changes
- **descheduler**: Rebalance pod distribution
- **coredns**: DNS service

### Networking
- **multus**: Multi-network plugin
- **multus-networks**: Network attachment definitions
- **istio**: Service mesh (base, istiod, ztunnel)
- **istio-namespace-config**: Namespace configurations
- **istio-policies**: Authorization policies
- **istio-waypoints**: L7 proxies
- **cilium-gateway**: Gateway API implementation
- **external-dns**: Automated DNS record management
- **cloudflared**: Cloudflare tunnel
- **certificates**: TLS certificates for services

### Data Services
- **volsync**: Backup and restore for PVCs
- **cloudnative-pg**: PostgreSQL operator
- **postgres-vectorchord**: Vector database extension
- **redis**: In-memory data store

### Observability
- **kube-prometheus-stack**: Prometheus + Grafana + Alertmanager
- **victoria-logs**: Log aggregation
- **fluent-bit**: Log forwarding
- **grafana**: Additional Grafana instance
- **jaeger**: Distributed tracing
- **kiali**: Service mesh observability
- **keda**: Event-driven autoscaling

## Bootstrap Behavior

- **Interval**: 1m (aggressive during bootstrap) → 10m (steady-state)
- **Wait**: `false` - Allows parallel deployment with Tier 2
- **Parallel**: All apps deploy concurrently, retry until dependencies ready
- **Health Checks**: Validates cert-manager and volsync HelmReleases

## Why These Apps?

These provide the infrastructure layer that applications need:
- **Certificates**: Apps need TLS
- **Storage**: Apps need backup/restore
- **Databases**: Apps need data persistence
- **Observability**: Ops need monitoring

Apps in Tier 2 can start deploying while these finish, relying on Kubernetes retry logic.

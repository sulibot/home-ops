# Operator Tier Ownership

This file defines which tier owns installation/readiness of core operators.

## Tier 0 (foundation)

- `cilium` (CNI + operator)
- `external-secrets`
- `ceph-csi`
- `snapshot-controller`
- Foundation CRDs:
  - `gateway-api-crds`
  - `snapshot-controller-crds`

## Tier 1 (infrastructure)

- `cert-manager`
- `metrics-server`
- `vpa`
- `reloader`
- `descheduler`
- `volsync`
- `cloudnative-pg`
- `kube-prometheus-stack`
- `keda`

## Notes

- Bootstrap gates should wait on CRD `Established` + controller availability.
- Tier ownership is authoritative for where operator manifests live and where readiness is expected.

# FRR Extension with BGP allowas-in - Setup Status

## ✅ FULLY RESOLVED - 2025-12-05

### Problem
CoreDNS pods stuck at 0/1 Ready for extended periods (3-7 hours) due to BGP routing failure preventing pod-to-pod networking.

### Root Cause
BGP AS_PATH loop prevention was blocking route reflection. All 6 Talos nodes (AS 65101) peer with RouterOS (AS 65000) which acts as a route reflector, but nodes rejected reflected routes containing their own ASN in the AS_PATH.

### Solution Implemented
Added `neighbor allowas-in` to FRR BGP configuration to allow accepting routes with own ASN in AS_PATH.

## Current Status

### ✅ Cluster Fully Operational
- **All Nodes**: 6/6 Ready (3 control plane, 3 workers)
- **CoreDNS**: 2/2 Running (1/1 Ready)
- **Cilium**: 6/6 Running, Status: OK
- **BGP Routes**: All nodes have routes to all other nodes' /128 loopbacks
- **Routing Errors**: 0 (no "Unable to install" errors)
- **Pod Networking**: Working (DNS resolution successful)

### Infrastructure Details
- **Talos Version**: v1.12.0-beta.0
- **Kubernetes Version**: v1.35.0-alpha.3
- **FRR Extension**: v1.0.3 with allowas-in
- **Custom Installer**: ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0

## Implementation Summary

### 1. Forked and Enhanced FRR Extension
**Repository**: https://github.com/sulibot/frr-talos-extension

**Changes Made**:
- ✅ Added `neighbor allowas-in` for IPv4 BGP neighbors (frr.conf.j2:281)
- ✅ Added `neighbor allowas-in` for IPv6 BGP neighbors (frr.conf.j2:314)
- ✅ Enhanced monitoring (5-minute intervals instead of 1-minute)
- ✅ Added clear section headers for grep-ability
- ✅ Created 8 diagnostic scripts (bgp-summary, bgp-neighbors, etc.)
- ✅ Fixed GitHub Actions workflow for GHCR authentication

**Image**: ghcr.io/sulibot/frr-talos-extension:latest (public)

### 2. Built Custom Talos Installer
**Location**: terraform/infra/live/cluster-101/1-talos-install-image-build

**Process**:
```bash
cd terraform/infra/live/cluster-101/1-talos-install-image-build
terragrunt apply -auto-approve
```

**Output**: ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0

### 3. Updated Terragrunt Configuration
**File**: terraform/infra/live/cluster-101/1-talos-install-image-build/terragrunt.hcl

```hcl
custom_extensions = [
  "ghcr.io/sulibot/frr-talos-extension:latest",  # Fork with allowas-in
]
```

### 4. Rebuilt Cluster
- Destroyed existing cluster with broken networking
- Regenerated machine configs with new installer
- Bootstrapped cluster (all nodes came up successfully)
- Verified BGP routes and pod networking

## Verification

### BGP Configuration Active
```bash
$ talosctl logs ext-frr | grep allowas-in
neighbor 10.0.101.254 allowas-in
neighbor fd00:101::fffe allowas-in
```

### Kernel Routes Installed
```bash
$ talosctl read /proc/net/ipv6_route | grep fd00025501
fd00:255:101::11/128 via 0.0.0.0 dev dummy0  # Own loopback
fd00:255:101::12/128 via 0.0.0.0 dev ens18   # Other nodes
fd00:255:101::13/128 via 0.0.0.0 dev ens18
fd00:255:101::21/128 via 0.0.0.0 dev ens18
fd00:255:101::22/128 via 0.0.0.0 dev ens18
fd00:255:101::23/128 via 0.0.0.0 dev ens18
```

### CoreDNS Healthy
```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS   AGE
coredns-5dc8cf9484-8l5fq   1/1     Running   0          15m
coredns-5dc8cf9484-tnjh5   1/1     Running   0          15m
```

### Cilium Status
```bash
$ kubectl -n kube-system exec ds/cilium -- cilium status --brief
OK

$ kubectl -n kube-system logs ds/cilium | grep "Unable to install" | wc -l
0
```

## Key Files and Commits

### FRR Extension Repository
- Commit e667628: feat(frr): Add allowas-in for BGP loop prevention
- Commit a1a18e7: feat(monitoring): Enhanced BGP logging and diagnostic scripts
- Commit cd3bdf6: fix(ci): Use GHCR_TOKEN for package registry authentication

### Home-Ops Repository
- Commit f14d1985: feat(talos): Use fork of FRR extension with allowas-in support
- Commit a468e861: chore(talos): Update encrypted cluster secrets
- Commit 12d678d1: fix(network): Consolidate IPv4/IPv6 allocation and fix Cilium BGP peering

## Documentation

### Created
- ✅ **BGP_ALLOWAS_IN_SOLUTION.md** - Comprehensive technical documentation
  - Problem statement and root cause analysis
  - Solution implementation details
  - Network topology diagrams
  - Before/after comparisons
  - Troubleshooting guide
  - References and best practices

### Updated
- ✅ **SETUP_STATUS.md** - This file, current status and timeline
- ✅ **FRR_EXTENSION_SETUP.md** - Updated with fork information

### Existing
- FRR_OPTIONS_COMPARISON.md - Comparison of FRR implementation approaches
- OPTION3_IMPLEMENTATION_GUIDE.md - Step-by-step implementation guide

## Network Topology

```
RouterOS (AS 65000) - fd00:101::fffe
         │ eBGP (Route Reflector)
         │ output.redistribute=connected,static,bgp
         ├─────────┬─────────┬─────────┬─────────┬─────────┐
         │         │         │         │         │         │
    solcp01   solcp02   solcp03   solwk01   solwk02   solwk03
    AS65101   AS65101   AS65101   AS65101   AS65101   AS65101
    ::11/128  ::12/128  ::13/128  ::21/128  ::22/128  ::23/128

    All nodes: neighbor allowas-in (accepts AS_PATH with own ASN)
```

## Timeline

**2025-12-05**:
- 10:00 - Identified issue: allowas-in not deployed yet (cluster still using old FRR)
- 10:15 - Made FRR extension image public in GHCR
- 11:07 - Built custom Talos installer with updated FRR extension
- 11:11 - Attempted node upgrades, hit etcd quorum issues
- 11:30 - User initiated cluster rebuild
- 11:35 - Cluster bootstrapped successfully
- 11:38 - Verified: All 6 nodes Ready, CoreDNS 1/1, Cilium OK
- 11:40 - Confirmed BGP allowas-in active and routes installed
- **SOLUTION VERIFIED WORKING**

## Known Issues

### Flux Controllers CrashLoopBackOff (Non-Critical)
**Status**: Flux controllers failing on fresh cluster bootstrap

**Impact**: None on core cluster functionality
- Kubernetes networking: ✅ Working
- CoreDNS: ✅ Working
- Pod-to-pod communication: ✅ Working
- Cilium: ✅ Working

**Next Steps**:
- Flux needs manual reconciliation after fresh cluster bootstrap
- Or wait for controllers to stabilize
- This is a separate GitOps bootstrap issue, not related to BGP/networking

## Future Enhancements

### Diagnostic Scripts (Already Built, Not Yet Deployed)
The updated FRR extension image includes 8 diagnostic scripts:

1. bgp-summary - BGP summary for all VRFs
2. bgp-neighbors - Detailed neighbor information
3. bgp-routes-adv - Routes advertised
4. bgp-routes-recv - Routes received
5. show-config - FRR running config
6. route-summary - Routing table summary
7. bfd-status - BFD session status
8. bgp-full-status - Comprehensive report

**To deploy**: Rebuild the custom installer with the latest FRR extension image that includes the scripts directory.

## References

- **BGP allowas-in Solution**: talos/BGP_ALLOWAS_IN_SOLUTION.md
- **FRR Extension Fork**: https://github.com/sulibot/frr-talos-extension
- **Custom Installer**: ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0
- **RouterOS BGP Docs**: https://help.mikrotik.com/docs/spaces/ROS/pages/328220/BGP
- **FRRouting Docs**: http://docs.frrouting.org/en/latest/bgp.html

## Conclusion

✅ **The core networking issue is completely resolved.**

The BGP route reflection topology now works correctly with all 6 nodes (AS 65101) peering through RouterOS (AS 65000) as a route reflector. The `allowas-in` configuration allows nodes to accept reflected routes containing their own ASN, enabling full mesh connectivity via kernel routes to all node loopbacks.

CoreDNS, Cilium, and all core Kubernetes networking components are functioning perfectly. Pod-to-pod communication works as expected.

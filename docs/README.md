# Documentation

Operational and architecture documentation for the home-ops repository.

## Operations

- [Runbooks](runbooks/README.md)
- [Observability Deployment Blueprint](observability-deployment-blueprint.md)
- [Observability, Monitoring, and Incident Reporting](observability-monitoring-and-incident-reporting.md)
- [Monitoring and Reporting Implementation](monitoring-and-reporting-implementation.md)
- [Backup system](backup-system.md)
- [Offsite backup monitoring and response](runbooks/offsite-backup-monitoring.md)
- [Cluster rebuild workflow](CLUSTER_REBUILD_WORKFLOW.md)
- [VolSync automatic restore](VOLSYNC_AUTOMATIC_RESTORE.md)

## Networking

- [FRR BGP architecture](frr-bgp-architecture.md)
- [FRR BGP design specification](frr-bgp-design-specification.md)
- [OpenBao HA cluster](openbao-ha-cluster.md)
- [Cloud resilience: KMS and offsite backup](cloud-resilience.md)
- [IP addressing layout](ip-addressing-layout.md)
- [Network ASN allocation](NETWORK_ASN_ALLOCATION.md)
- [ENG-322: EVPN/VRF NAT44/NAT66 fabric - operational history](tickets/eng-322-vrf-evpnz1-ipv4-snat.md)

## Platform

- [Auth architecture](auth-architecture.md)
- [CI/CD pipeline](CI_CD_PIPELINE.md)
- [Talos FRR boot configuration](talos-frr-boot-configuration.md)
- [RWX migration plan](rwx-migration-plan.md)

## Archive

`_archive/` holds superseded design docs and raw AI-debugging-session
transcripts (BGP/EVPN/xvrf/Cilium/DNS investigations from late 2025 and
earlier) that are no longer accurate against the current deployed state but
retain forensic value. Not maintained - don't treat as current.

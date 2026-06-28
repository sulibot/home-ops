# Incident Report: <short title>

## Summary

<One paragraph: what happened, when, and current status.>

## Impact

- User/application impact:
- Data safety impact:
- Affected namespaces/workloads:
- Affected VMs:
- Affected Proxmox hosts:
- Affected Ceph pools/PGs/OSDs:
- Start time:
- End time or current state:

## Timeline

| Time | Event | Evidence |
|---|---|---|
| YYYY-MM-DD HH:MM TZ | Alert fired | Alertmanager link |
| YYYY-MM-DD HH:MM TZ | Mitigation applied | Command/change link |

## Current State

- Ceph health:
- PG state:
- Recovery/backfill/scrub state:
- Kubernetes node/pod state:
- Proxmox host/VM state:
- Hardware state:

## Suspected Root Cause

<State the leading hypothesis and confidence level. Separate root cause from contributing factors.>

## Evidence

- Metrics:
- Logs:
- Events:
- Hardware signals:
- Configuration changes:
- Recent maintenance:

## Affected Layers

- Physical hardware:
- Proxmox:
- Ceph:
- Kubernetes:
- Application:

## Immediate Mitigations

- Pause/throttle:
- Migrate/drain:
- Ceph config changes:
- Hardware action:
- Application action:

## Rollback Plan

- What was changed:
- How to reverse:
- Validation after rollback:

## Follow-Up Actions

| Action | Owner | Priority | Due | Tracking |
|---|---|---:|---|---|

## Vendor/Hardware Questions

- Is this disk/NIC/BIOS firmware revision known to have issues?
- Are repeated errors tied to one physical slot, cable, controller, or host?
- Are PCIe AER/MCE/EDAC events present?
- Are replacement parts or firmware updates needed?

## Prevention and Monitoring Gaps

- Missing metrics:
- Missing labels/joins:
- Missing dashboards:
- Missing alerts:
- Missing runbooks:
- Automation to add:


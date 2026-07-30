# NFS gateway monitoring plan

## Purpose and service classification

The CephFS NFS gateway is an internal, stateful file-access service for VMs
and trusted LXCs. It is a Tier 2 home-lab service: users expect it to work at
all times, but it does not justify the cost or operational load of a commercial
24x7 storage SLA.

Monitoring runs entirely inside the home lab. It does not depend on a laptop,
VPN session, OpenCloud client, or a user being logged in.

Service owner: Home Ops SRE.

Supporting owners:

- Storage: CephFS, MDS, OSD, and CephX behavior.
- Compute: Proxmox nodes and LXC lifecycle.
- Network: tenant 200 routing, VRRP, and Kubernetes-to-tenant reachability.
- Identity: Kanidm numeric UID/GID allocation. Authentication availability is
  outside this service's NFS availability SLO.

## User journey and service boundaries

The measured user journey is:

1. Resolve the fixed endpoint from configuration.
2. Reach `10.200.0.209:2049`.
3. Mount both `10.200.0.209:/shared` and
   `10.200.0.209:/common` with NFSv4.1.
4. Write, read, verify, and remove a file in each export as service UID
   `1000`. The Common export inherits the canonical `storage_common_rw` GID.

This crosses the client tenant network, Keepalived VIP, NFS-Ganesha, CephFS
MDS, Ceph OSDs, and the canonical directory. It deliberately does not measure
web access or synchronization through OpenCloud; that is a separate user
journey with separate failure modes.

## Reliability objectives

The reporting window is a rolling 14 days because that is the current
Prometheus retention period.

| Objective | Target | Measurement | Consequence |
| --- | --- | --- | --- |
| Availability | 99.5% over 14 days | Successful synthetic NFS transactions / scheduled transactions | About 101 minutes of error budget |
| Recovery | Restore successful client IO within 60 seconds of a single gateway failure | Quarterly disruptive failover test | Failed test creates reliability work |
| Data correctness | 100% of successful probes preserve expected ownership and payload | Personal NFS files use canonical Kanidm owner UID `1888405477` and OpenCloud Space GID `1000`; Common files use supplemental GID `1965604563` | Any mismatch is an availability failure |
| Recovery point | Zero gateway-local data loss | Both gateways serve the same CephFS path | Gateway rebuild must not copy or restore user data |
| Monitoring coverage | All three exporter targets and the Kubernetes TCP probe healthy | Prometheus target and Blackbox metrics | Missing coverage is a warning, not a healthy sample |

The availability objective should be reviewed after four weeks of measurements.
Do not increase it solely because the first period was quiet. Increase it only
when users need a stronger commitment and the observed failure modes support
that commitment.

## Signals and collection

### User-facing SLI

`debfs-vm01` runs `nfs-client-probe.timer` every 30 seconds. A VM is used
because the current Proxmox/kernel combination rejects NFS client mounts from
the validation LXC without weakening its confinement. The probe uses a
monitoring-only soft mount so endpoint failure cannot indefinitely block the
collector. Production mounts remain hard mounts.

Metrics:

- `homeops_nfs_client_probe_success`
- `homeops_nfs_client_probe_duration_seconds`
- `homeops_nfs_client_probe_timestamp_seconds`
- `homeops_nfs_client_probe_last_success_timestamp_seconds`

The recording rule `homeops:nfs_shared:probe_success` converts missing probe
data into failure. Missing telemetry must not make the availability percentage
look better.

### Gateway state

Each gateway publishes state every 15 seconds through the node_exporter
textfile collector:

- Keepalived and Ganesha process state.
- IPv4 and IPv6 VIP ownership.
- Export 100 (`/shared`) and export 101 (`/common`) availability through
  Ganesha D-Bus.
- TCP/2049 listener state.
- Required Ceph messenger route.
- Health-inhibition state.
- Collector freshness.

The same scrape supplies CPU, memory, filesystem, network, and process host
metrics for incident diagnosis.

### Independent network path

Blackbox Exporter connects from Kubernetes to `10.200.0.209:2049` every 15
seconds. It does not replace the semantic client probe. Its purpose is to tell
the responder whether Kubernetes-to-tenant routing differs from the actual NFS
client path.

### Dependencies

Existing telemetry supplies:

- Ceph health, MDS state, OSD state, slow operations, and recovery.
- Proxmox node and LXC lifecycle.
- Host storage, network, and hardware health.
- Flux reconciliation and Prometheus target health.

Gateway journal logs remain local to each LXC. Metrics are sufficient for
detection and first-pass diagnosis; central LXC journal collection is a
separate platform-level logging decision and should not be implemented as a
one-off agent for this service.

## Alert policy

Critical alerts indicate user-visible failure or an unsafe active/active state.
They route through the existing Alertmanager policy to Linear, Pushover, and
email. Warning alerts always create or update a Linear issue and page through
Pushover only outside configured quiet hours.

| Alert | Severity | Why it exists | Expected response |
| --- | --- | --- | --- |
| `NFSSharedEndpointUnavailable` | Critical | End-to-end user IO has failed for two minutes | Acknowledge within 15 minutes; restore service |
| `NFSSharedAvailabilityFastBurn` | Critical | 14.4x budget burn remains present in both five-minute and one-hour windows | Treat as active impact |
| `NFSGatewayUnsafeHAState` | Critical | VIPs are absent, split, duplicated, or both exports are not ready on one owner | Prevent conflicting servers and restore one owner |
| `NFSSharedAvailabilitySlowBurn` | Warning | Chronic 6x error-budget burn | Investigate within one working day |
| `NFSGatewayFailoverCapacityLost` | Warning | Service is working without redundancy | Repair before planned maintenance |
| `NFSGatewayCephRouteMissing` | Warning | Standby promotion may fail | Restore the node-local Ceph route |
| `NFSGatewayHealthInhibited` | Warning | A repaired node cannot preempt until explicitly cleared | Validate, then clear the marker |
| `NFSGatewayMetricsTargetDown` | Warning | One of three exporter targets is unavailable | Restore observability or the guest |
| `NFSGatewayMetricsStale` | Warning | Gateway textfile collection stopped | Repair the systemd timer |
| `NFSClientProbeStale` | Warning | The semantic probe stopped updating | Repair the probe without assuming service health |
| `NFSClientProbeLatencyHigh` | Warning | Synthetic IO exceeds two seconds for five minutes | Correlate with Ceph and network pressure |
| `NFSGatewayClusterPathDown` | Warning | Kubernetes cannot reach TCP/2049 | Compare paths before changing the NFS service |

The fast and slow burn thresholds use multi-window burn-rate alerting. Direct
endpoint failure remains the fastest page because this is a low-traffic service
with synthetic transactions rather than a high-volume request stream.

Burn-rate alerts start only after the recording rules have enough samples to
represent their long window: 100 one-hour samples for fast burn and 600
six-hour samples for slow burn. The direct endpoint alert stays active during
this one-time cold-start period and pages on two minutes of continuous failed
end-to-end I/O. This avoids treating deployment bootstrap as an artificial
outage without hiding a real new-service outage.

## Error-budget policy

| Remaining budget | Management action |
| --- | --- |
| 50–100% | Normal delivery; perform scheduled resilience tests |
| 25–50% | Review failures weekly and prioritize repeat causes |
| 1–25% | Freeze nonessential NFS gateway changes; prioritize reliability work |
| 0% | No feature work until the owner reviews incidents and accepts or mitigates the risk |

Planned maintenance counts against measured availability unless the user
journey remains successful through failover. This encourages maintenance that
uses the redundancy already paid for.

## Dashboard and operating rhythm

Grafana dashboard: `SRE / NFS Gateway`, folder `storage`.

The landing row answers:

- Are users succeeding now?
- Are we meeting the 14-day objective?
- How much error budget remains?
- Can Kubernetes reach the VIP?
- Has the VIP moved recently?
- Is monitoring complete?

The diagnostic rows show VIP ownership, Ganesha/Keepalived/export state, probe
latency, and gateway memory.

Operating cadence:

- Daily: rely on actionable alerts; no manual green-dashboard ritual.
- Weekly for the first month: review alert noise, probe latency, failover
  count, and budget consumption.
- Monthly: review availability and recurring causes; create reliability work
  for patterns rather than isolated harmless events.
- Quarterly: run `validate-failover.sh` during a maintenance window and record
  recovery time and client IO result.
- After any incident: record detection, failover, restoration, and prevention
  actions in the Linear incident/task.

## Validation and change control

Repository validation:

```bash
kustomize build --load-restrictor LoadRestrictionsNone \
  kubernetes/apps/tier-1-infrastructure/proxmox-observability/app
kustomize build --load-restrictor LoadRestrictionsNone \
  kubernetes/apps/tier-1-infrastructure/blackbox-exporter/lan
kustomize build --load-restrictor LoadRestrictionsNone \
  kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/rules
kustomize build --load-restrictor LoadRestrictionsNone \
  kubernetes/apps/tier-1-infrastructure/grafana/dashboard
```

Live acceptance:

1. Prometheus reports three healthy `nfs-gateway-observability` targets.
2. `homeops_nfs_client_probe_success` is 1.
3. `probe_success{service="nfs-gateway-tcp"}` is 1.
4. Exactly one gateway owns both VIPs and exposes exports 100 and 101.
5. The dashboard is reconciled by Grafana Operator.
6. Prometheus accepts all recording and alert rules without evaluation errors.
7. A controlled failover preserves client IO and moves the ownership metrics.

Reconcile the external client collector from the NFS service directory:

```bash
./configure-client-monitoring.sh
```

The script owns only monitoring packages, units, and collectors inside
`debfs-vm01`; it deliberately does not import or manage the VM's historical
OpenTofu resources.

Threshold changes require evidence from at least one week of data or an
incident review. Do not silence a noisy alert without either fixing its cause,
changing its response class, or documenting why it is not actionable.

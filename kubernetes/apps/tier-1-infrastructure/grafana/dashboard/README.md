# SRE Dashboards

This directory contains repo-owned Grafana dashboards managed by the Grafana Operator.

## Maintenance Rules

- Keep dashboards few and purpose-built.
- Prefer one executive view and one drill-down view over many overlapping dashboards.
- A panel must answer an operational question, not merely show that a metric exists.
- Top-N tables should stay bounded to 10-15 rows.
- Do not add panels for debug/info logs.
- Do not duplicate imported dashboards unless the custom dashboard adds cross-layer correlation.
- If a panel is not used during incidents or weekly review, remove it.

## Current Custom Dashboards

| Dashboard | File | Purpose |
|---|---|---|
| SRE Executive Cluster Health | `sre-executive-dashboard-configmap.yaml` | Daily glance: safety, pressure, top IO, hardware red flags, active alerts, logs. |
| SRE Incident Drill-Down | `sre-incident-drilldown-configmap.yaml` | Active response: write IO versus recovery, Ceph safety, top pods/VMs/disks, alerts, logs. |
| SRE Home Control Health | `home-control-dashboard-configmap.yaml` | Home Assistant, Music Assistant, cluster-104 Hubble flows, and related logs/events. |

## Editing Workflow

1. Edit the dashboard in Grafana when layout work is easier visually.
2. Export the dashboard JSON.
3. Replace only the JSON block in the matching ConfigMap.
4. Keep panel titles short and operational.
5. Validate locally:

```bash
kustomize build --load-restrictor LoadRestrictionsNone kubernetes/apps/tier-1-infrastructure/grafana/dashboard
```

## Dashboard Anti-Patterns

- More than one screen of stat panels.
- Large unfiltered pod tables.
- Panels that require knowing obscure metric names to interpret.
- Alert panels without runbook links in the underlying alert rules.
- Log panels that show raw high-volume application logs by default.
- Adding another datastore or board without a specific workflow gap.

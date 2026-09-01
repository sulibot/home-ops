# GitHub Actions runner observability

## Purpose

Operate the shared GitHub Actions Runner Controller (ARC) capacity plane without
confusing infrastructure health with repository test success.

- GitHub Actions is authoritative for each run and protected check.
- Harness evidence and GitHub artifacts hold exact-SHA test detail.
- Grafana's `Engineering CI` dashboard shows aggregate runner health and trends.
- Plane tracks work; integration and staging sites show deployed candidates.

The dashboard is not a promotion gate and its failure ratio is not a paging
signal.

## Expected resources

```bash
kubectl -n actions-runner-system get pods,svc,podmonitor,servicemonitor,prometheusrule
kubectl -n actions-runner-system get ciliumnetworkpolicy
kubectl get ciliumclusterwidenetworkpolicy actions-runner-jobs-onward
```

Expected long-lived pods are one controller and one listener per scale set.
Runner pods remain ephemeral and scale from zero to each set's configured
maximum.

## Confirm scraping

```bash
prometheus_pod="$(kubectl -n observability get pod -l app.kubernetes.io/name=prometheus -o name | head -1)"
kubectl -n observability exec -c prometheus "${prometheus_pod}" -- \
  promtool query instant http://localhost:9090 'gha_max_runners'

kubectl -n observability exec -c prometheus "${prometheus_pod}" -- \
  promtool query instant http://localhost:9090 \
  'up{namespace="actions-runner-system"}'
```

Listener series should contain stable `name` or `repository` dimensions. They
must not contain commit SHA, run ID, or `job_workflow_ref` labels.

## Diagnose missing metrics

1. Confirm controller and listener pods are ready.
2. Confirm the listener pod exposes a named `metrics` port on `8080`.
3. Inspect the PodMonitor and ServiceMonitor targets in Prometheus.
4. Check that the Prometheus pod label still matches the metrics ingress policy.
5. Check controller reconciliation logs for listener replacement failures.

```bash
kubectl -n actions-runner-system get pods --show-labels
kubectl -n actions-runner-system get pod -l app.kubernetes.io/component=runner-scale-set-listener \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].ports}{"\n"}{end}'
kubectl -n actions-runner-system logs deploy/actions-runner-controller --since=30m
```

Enabling or changing metrics replaces listeners and resets their process-local
counters. This rollout replaces both the Onward listener and the trusted
`home-ops-runner` administrative listener, so a short dispatch discontinuity is
expected for each. Alerts wait 10 to 15 minutes before firing.

Confirm the rule and notification paths after applying the change:

```bash
kubectl -n observability get prometheus kube-prometheus-stack \
  -o jsonpath='{.spec.ruleSelector}{" "}{.spec.ruleNamespaceSelector}{"\n"}'
kubectl -n observability get alertmanagerconfig alertmanager
```

Both Prometheus selectors are expected to be `{}`. Confirm the five
`ActionsRunner*` rules appear in the Prometheus rules API. Warning alerts use
the existing severity route: they are recorded by the durable work receiver and
sent to the warning notification receiver outside its quiet-hours interval.

## Diagnose stalled provisioning

Compare desired, registered, running, and maximum capacity:

```promql
sum by (name) (gha_desired_runners)
sum by (name) (gha_registered_runners)
sum by (name) (gha_running_jobs)
sum by (name) (gha_max_runners)
```

If desired exceeds registered for more than 15 minutes:

1. inspect ephemeral runner pods and events;
2. check image pulls, scheduling, memory, CPU, and storage pressure;
3. inspect the listener and controller logs;
4. open the corresponding GitHub Actions job for its requested runner label.

Do not increase `maxRunners` until scheduling/resource pressure is understood.

## Diagnose failed ephemeral runners

```bash
kubectl -n actions-runner-system get ephemeralrunner,ephemeralrunnerset
kubectl -n actions-runner-system get events --sort-by=.lastTimestamp | tail -50
kubectl -n actions-runner-system logs deploy/actions-runner-controller --since=30m
```

Identify the failed runner's image, scheduling, storage, or startup error before
deleting it. After preserving the relevant event and log evidence, delete only
the exact failed `EphemeralRunner`; the controller will reconcile desired state.
Confirm `gha_controller_failed_ephemeral_runners` returns to zero and the alert
resolves.

## Diagnose stalled dispatch

If assigned jobs exceed running jobs while capacity remains below the maximum
and desired runners remain zero:

1. inspect the affected listener log and GitHub runner-scale-set status;
2. verify its GitHub App credential and network path;
3. confirm the workflow requested the exact scale-set name; and
4. check controller reconciliation errors before restarting the listener.

Do not page on ordinary test failure or simple saturation at `maxRunners`.

## Network boundary

During the canary, ARC-created `onward-runner` pods in
`actions-runner-system` accept no ingress and may egress only to cluster DNS
and public IPv4 destinations. IPv6 egress is denied during the canary because
the PVE management plane has both ULA and delegated GUA addresses. Cluster,
node, API-server, RFC1918, carrier-grade NAT, loopback, unique-local, and
link-local ranges are denied. This blocks Kubernetes, ARC secrets, the private
LAN/PVE management plane, Prometheus, Loki, Grafana, OpenTelemetry, and other
private services. Controller and listener metrics accept ingress only from
Prometheus and the Kubernetes host.

If a repository legitimately requires a private dependency, add the smallest
explicit endpoint/port allowance after reviewing its trust boundary. Do not
remove the runner policy wholesale.

## Canary rollout

Listener metrics and runner network containment roll out one verification scale
set at a time. `onward-runner` is the first canary. Before enabling the same
boundary for another project's untrusted verification runner, require:

1. its listener remains Ready with zero restarts for at least 10 minutes;
2. the controller and listener Prometheus targets are up;
3. real `gha_*` series contain only the intended bounded labels;
4. one complete burst job succeeds; and
5. its runner endpoint has ingress and egress policy enforcement enabled, can
   reach GitHub over IPv4, cannot reach a LAN/PVE address over IPv4 or IPv6,
   and has no general IPv6 egress allowance. Inspect `.status.podIPs` while the
   runner exists and test both families explicitly. The cluster currently gives
   runner pods IPv4 and IPv6 addresses; direct IPv6 egress must remain denied,
   while the complete harness run proves its clients fall back to allowed
   public IPv4 promptly.

For the Cilium endpoint, `policy-enabled` must be `both`, not only `egress`.
Cilium requires an ingress rule section to activate ingress default-deny;
`enableDefaultDeny.ingress: true` alone does not activate that direction.

`home-ops-runner` is a separate trusted administrative lane used by explicit
PVE, Talos, Terraform, and credential-gated workflows. It is not a general
project verification pool and must not receive this public-only egress policy.
Its listener still uses an explicit bounded metric label set because controller
metrics are enabled globally. Keep the PodMonitor scoped to `onward-runner`
until another scale set completes this canary; never replace it with a broad
listener-component selector.

## Rollback

The repository harness remains usable on the persistent devbox or laptop if ARC
observability fails. To roll back only this observability slice, revert:

- controller `metrics` values;
- scale-set `listenerMetrics` and runner labels;
- metrics discovery, policies, and Prometheus rules; and
- the `Engineering CI` Grafana resources.

Reverting observability does not change test selection, canonical coverage, or
GitHub check authority.

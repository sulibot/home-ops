# IaC-managed persistent agent control plane with elastic verification workers

**Status:** Partially deployed; convergence work remains  
**Last verified:** 2026-09-01  
**Proving project:** Onward.jobs  
**Owner repositories:** `home-ops` for infrastructure and `onward` for the verification contract

Status terms in this document are deliberate:

- **deployed** means observed live and represented in the current checkout;
- **live drift** means observed live but missing or inconsistent in the current checkout;
- **candidate** means implemented on an unmerged repository revision;
- **planned** means a target-state requirement with no current implementation; and
- **blocked** means it must not be used for untrusted work until the named control lands.

## Decision

Run Codex and Claude Code from a small persistent NixOS LXC and treat the
developer laptop or phone as a control surface. Keep test selection and quality
policy inside each repository's deterministic verification harness. Execute the
ordinary development loop on the persistent LXC and use ephemeral Kubernetes
workers only for selected independent or resource-heavy verification.

This is a provider-neutral development platform. Codex and Claude consume the
same repository contracts, commands, result schema, artifacts, and promotion
gates. Neither agent defines test coverage or substitutes model judgment for a
deterministic gate.

The architecture is intended to improve:

- deterministic execution latency;
- orchestration and context efficiency;
- safe parallelism;
- disconnect/reconnect behavior;
- repeatability across repositories; and
- evidence durability.

It does **not** reduce model reasoning latency. Infrastructure can remove local
resource contention and waiting, but it does not make an API model think faster.

## Architecture

```text
Mac / phone
  human control, review, approval
          |
          v
agent-devbox01.sulibot.com
NixOS LXC on PVE
  - Codex CLI
  - Claude Code
  - Git worktrees
  - tmux / lingering user services
  - lightweight orchestration
          |
          +--------------------+
          |                    |
          v                    v
repository harness       durable coordination
  affected / fast          Git commits and refs
  integration / security   Plane work state
  E2E / full               CI runs and artifacts
  compact result.json      repository documentation
          |
          +-----------------------------+
          |                             |
          v                             v
persistent LXC execution        Kubernetes burst execution
routine edit/build/test         ephemeral ARC runner pods
low coordination overhead      selected parallel profiles
local retained artifacts       centralized CI artifacts
```

### Responsibility boundaries

| Layer | Owns | Does not own |
| --- | --- | --- |
| Human control surface | priorities, consequential approvals, review, promotion | long-running process lifetime |
| Persistent agent LXC | sessions, worktrees, orchestration, lightweight commands, routine verification | canonical coverage policy |
| Repository harness | profile definitions, isolation preconditions, timeouts, result schema, cleanup | placement or autoscaling |
| GitHub/CI | dispatch, immutable revision identity, runner selection, artifact retention | agent reasoning or repository test selection |
| Kubernetes | ephemeral compute, pod isolation, bounded concurrency, disposable resources | durable source code or session state |
| Git/Plane/artifacts | durable work and evidence state | secret delivery |
| 1Password/OpenBao | human custody and scoped machine delivery of secrets | product or test policy |

The harness defines **what** must run. The execution layer decides **where and
when** it runs.

### Independent reasoning checkpoints

Meaningful new work uses Claude as an independent challenger at two points:

1. Codex writes a concrete, contract-grounded plan before implementation.
2. Claude reviews the plan for missing risks and alternatives.
3. Codex reconciles that advice against canonical contracts and repository or
   runtime evidence, then implements the accepted plan.
4. Claude independently reviews the completed diff before merge.
5. Codex remediates supported findings and reruns deterministic verification.

Both checkpoints are required for architecture/infrastructure,
authentication/authorization/privacy/secrets, database schemas or migrations,
billing, shared contracts or state machines, cross-cutting changes,
deployment/CI trust boundaries, and changes that could weaken verification.
Ordinary bounded features may use post-implementation review only. Trivial
copy, formatting, and mechanical changes with strong deterministic coverage may
skip Claude review.

Claude is an independent reviewer, not an automatic veto or a substitute for
evidence. Codex remains accountable for resolving conflicts between reviewer
advice, pinned dependency behavior, live observations, and canonical product
contracts. Record material accepted and rejected findings in the change or PR.

### CI visibility and evidence authority

The engineering CI view is deliberately layered rather than implemented as a
new Jenkins-like control service:

| Surface | Authority |
| --- | --- |
| GitHub Actions checks | Authoritative result for a commit, workflow, job, and protected promotion gate |
| Harness `result.json` and retained artifacts | Exact-SHA suite evidence, fingerprints, trust, reuse, logs, JUnit, traces, screenshots, and coverage |
| Grafana `Engineering CI` dashboard | Aggregate ARC demand, capacity, throughput, outcome ratio, and latency across repositories |
| Plane | Work ownership, acceptance state, and follow-up defects; never a test executor |
| Integration/staging site | Human inspection of the deployed candidate; never proof that its gates passed |

ARC listener metrics intentionally exclude Git refs, run IDs, and candidate
SHAs. Those values have unbounded cardinality and belong in GitHub and harness
evidence. Listener metrics aggregate on stable repository, workflow, event,
job, result, and scale-set labels. Duration histograms use a bounded bucket set.

Runner pools are separated by trust purpose. `onward-runner` is the first
public-egress-only verification lane for repository tests. `home-ops-runner`
executes explicit credential-gated PVE/Talos/Terraform administration and may
require private infrastructure access; it is not a shared verification pool.
Future projects receive their own constrained verification scale set rather
than borrowing the administrative lane.

The Grafana failure ratio is diagnostic and does not page. Ordinary test
failures are handled by GitHub checks. Alerts are limited to platform failures:
missing listener or controller metrics, stalled runner provisioning, failed
ephemeral runners, and assigned work that ARC is not dispatching despite spare
configured capacity.

Per-test history and harness reuse/trust trends remain a planned evidence
ingestion layer. Until a write-only, authenticated OTLP/Loki path and retention
contract exist, compact evidence stays in GitHub artifacts rather than giving
repository-controlled jobs access to observability query APIs or a Prometheus
Pushgateway.

## Persistent control plane

### Host identity

The current host is declared by:

- `nix/hosts/agent-devbox01/default.nix`;
- `nix/modules/profiles/agent-devbox.nix`; and
- the `agent-devbox01` output in `nix/flake.nix`.

Current network identity:

| Property | Value |
| --- | --- |
| DNS | `agent-devbox01.sulibot.com` |
| IPv4 | `10.200.0.210/24` |
| IPv6 | `fd00:200::210/64` |
| User | `agent` |
| Workspace root | `/srv/agent/workspaces` |

The LXC has a persistent `agent` user, SSH key access, `linger=yes`, Git, pnpm,
Node.js, Codex, Claude Code, GitHub CLI, OpenBao CLI, direnv, ripgrep, tmux, and
the repository toolchain. NixOS provides reproducible package and systemd
configuration; application repositories remain ordinary Git checkouts and
worktrees.

### Disconnect and recovery model

Long-running work must not depend on the laptop remaining awake. Work runs in a
tmux session, user service, or another server-owned process on the LXC. A client
may disconnect and later reconnect over SSH.

Conversation state is useful but is not the recovery authority. Durable state is:

1. candidate commits pushed to a recoverable remote agent ref;
2. exact candidate SHAs;
3. harness `result.json` and referenced artifacts;
4. Plane issue state and canonical Work IDs after its API integration is verified; and
5. repository architecture/status documentation.

An interrupted agent conversation must be able to reconstruct work from these
sources without replaying raw test transcripts.

An unpushed commit or merely inspectable worktree is **not** durable against LXC
storage loss. Before a run is accepted as promotion evidence, push its candidate
SHA to a namespaced remote ref such as `refs/heads/agents/<work-id>/<timestamp>`.
Until Plane integration is verified, Git plus machine-readable evidence is the
recovery authority and Plane is only a human coordination index.

## Resource model

An LXC does not use VM ballooning. Its equivalent is a dynamically adjustable
cgroup CPU, memory, and swap ceiling backed by the PVE host. Unused host memory
is inherently available to other workloads; a configured limit bounds the
container under contention.

Current live measurements on 2026-09-01:

| Property | Observed value |
| --- | --- |
| Visible CPUs | 4 |
| CPU quota (`cpu.max`) | unlimited; visibility is already restricted to 4 CPUs |
| Memory cgroup ceiling | unlimited |
| Swap ceiling | unlimited |
| Memory currently charged | approximately 2.4 GiB |

The current container therefore does **not** yet meet the intended bounded,
lowest-practical-resource policy. The PVE LXC resource definition must be moved
into IaC and measured under real Nix/pnpm/build workloads.

Recommended initial controlled envelope:

- 4 vCPU maximum;
- 6 GiB memory ceiling;
- 4 GiB swap ceiling;
- no guaranteed idle reservation beyond PVE's normal scheduling; and
- alerting on sustained memory pressure, OOM kills, swap churn, and load.

Reduce the ceiling only after representative Codex/Claude plus routine harness
runs prove sufficient headroom. Increase it before moving routine heavy browser
or database lanes back from Kubernetes. An OOM-retry loop costs more time and
tokens than a modest idle-memory ceiling.

## Identity and secret delivery

### Trust flow

```text
human-managed 1Password vault
          |
          | bootstrap / rotation
          v
OpenBao KV + agent-devbox AppRole policy
          |
          | root-only systemd refresh
          v
/run/agent-credentials/runtime.env (root:agent, 0640)
          |
          v
agent-job-shell -> Codex / Claude / Plane client
```

`agent-credentials.service` authenticates with a dedicated OpenBao AppRole,
reads only allowlisted paths, and writes an atomic runtime environment. Its
timer runs after boot and every 45 minutes with jitter. Codex API authentication
is refreshed through the supported `codex login --with-api-key` stdin flow; the
API key is not passed as a command argument.

The AppRole bootstrap is `/var/lib/agent-secrets/approle.env`, owned by root and
mode `0600` in the live container. The `agent` user cannot read it. The generated
runtime file is `root:agent` mode `0640`, however, so every process running as
`agent` can read every variable in that file. The current `agent-job-shell`
wrapper loads that complete file; it is a delivery helper, not a per-secret
sandbox. Per-lane credential files or helpers are planned before credentials
with repository write authority are enabled.

Codex currently persists API authentication in `/home/agent/.codex/auth.json`
at mode `0600`. This is outside the ephemeral `/run` boundary and must be moved
to ephemeral storage or explicitly excluded from backup and wiped on rotation.
No GitHub CLI configuration or login was present on the LXC when checked on
2026-09-01. Claude and future GitHub client caches require the same inventory.

Current credential state:

| Credential | State |
| --- | --- |
| OpenAI project service account | Deployed and verified with unattended Codex |
| Anthropic API key | Deployed and verified with unattended Claude Code |
| Plane API key | Delivered; workspace-scoped API verification remains |
| ARC GitHub App | Existing identity for runner administration only |
| Development-agent GitHub App | Required; not yet created |

Static OpenAI, Anthropic, and Plane keys cached in `runtime.env` remain usable
until the file and all holding processes are replaced; OpenBao unavailability
does not make those cached values expire. Rotation therefore requires rewriting
the runtime, clearing persistent client caches, and restarting credential-holding
jobs. Track revocation propagation time. A future short-lived GitHub token must
be read at use time through a credential helper rather than captured once in a
long-lived tmux or systemd process environment. Its refresh interval plus
maximum jitter must remain below its token lifetime.

### GitHub identity separation

Do not expose the Actions Runner Controller App token to development agents.
The ARC App requires repository Administration permission but does not need
source-code or pull-request access. Combining ARC and coding permissions would
produce an unnecessarily broad identity.

Create a dedicated development-agent GitHub App, install it only on approved
development repositories, and request only:

- Contents: read/write;
- Pull requests: read/write;
- Actions: read-only;
- Checks: read-only; and
- Workflows: no access by default; grant write only through a separately
  reviewed workflow-change path.

Mint short-lived installation tokens in the root-only refresh service. Deliver
tokens through a read-at-use credential helper; keep the App private key outside
the agent-readable runtime file. The existing ARC App material was staged in an
OpenBao `github-app` path during bootstrap but is not loaded into the LXC runtime
and no `GH_TOKEN` is present. Remove that path from the agent AppRole policy and
delete the staged copy before enabling GitHub access.

Repository write permission never confers promotion authority. The target gate
is a protected default branch with no agent direct-push permission, required
human PR approval, and required CI status checks produced outside the
development LXC. LXC-local results are advisory for promotion; CI-attested
checks bound to the exact candidate SHA are authoritative. The exact required
checks remain repository policy.

## Deterministic repository harness

Onward's executable contract is documented in
`docs/implementation/VERIFICATION_HARNESS.md` in the Onward repository.

Stable profiles:

| Profile | Use |
| --- | --- |
| `pnpm verify:affected -- --base <ref> --sha <sha>` | Normal edit loop; affected tests plus fast checks |
| `pnpm verify:fast -- --sha <sha>` | Canonical, formatting, lint, type, and architecture checks |
| `pnpm verify:integration -- --sha <sha>` | Isolated migration and database verification |
| `pnpm verify:security -- --sha <sha>` | Secret, workflow pin, and dependency security policy |
| `pnpm verify:e2e -- --sha <sha>` | One production build and relevant browser smoke coverage |
| `pnpm verify:full -- --sha <sha>` | Clean-tree milestone gate with all required local equivalents |

Every run is bound to an exact SHA and writes versioned
`onward.validation.v1` output. The normal agent response is one line:

```text
PASS · revision <sha> · profile <profile> · suites <count> · duration <time> · artifacts <path>
```

A failure returns the revision, failing suite, first actionable error, affected
paths, duration, and artifact location. Passing output, repeated errors, traces,
screenshots, and full logs stay outside the main model context.

Codex and Claude follow the same consumption policy:

1. invoke the smallest appropriate profile;
2. read the compact line;
3. inspect `result.json` only when suite structure is needed; and
4. open one referenced failing log only when the bounded error is insufficient.

This is the primary token-saving mechanism. Moving a verbose command to another
machine without changing its result contract does not itself reduce context use.

## Execution placement policy

### Persistent LXC is the default

Use the LXC for:

- repository inspection and editing;
- Git/worktree operations;
- affected and fast profiles;
- bounded unit tests;
- low-cost security/static checks;
- result interpretation; and
- orchestration of remote lanes.

Keeping the ordinary loop on the LXC minimizes queueing, checkout, image-pull,
dependency-install, and artifact-transfer overhead.

### Kubernetes is selected burst capacity

Use Kubernetes when at least one of these is true:

- two or more independent profiles have enough duration to amortize runner startup;
- a database, browser, or service lane needs disposable isolation;
- a build/test would materially contend with the interactive agent host;
- multiple architecture/browser/security matrices can run safely in parallel; or
- centralized artifacts are required for a promotion gate.

Do not use Kubernetes for every command. A five-second check should not wait for
a pod. Do not split gates whose setup or shared build cost exceeds the saved
execution time.

The selected Onward burst workflow is defined on an Onward proving branch and
dispatches `fast` and `security` as independent ARC jobs on the `onward-runner`
scale set. It uploads harness artifacts for seven days. The scale set is now
represented in `home-ops` IaC and configured with:

- `minRunners: 0`;
- `maxRunners: 3`;
- per-pod requests of 250m CPU and 512 MiB memory; and
- per-pod limits of 4 CPU and 4 GiB memory.

No idle runner pod is retained. Listener/controller overhead remains.

### Kubernetes workload boundary

The original Kubernetes-container mode gave runner pods a service account that
could read/list namespace Secrets, including the ARC GitHub App secret. This was
closed by `home-ops` PR #334 on 2026-09-01.

Both scale sets now run direct steps in ephemeral runner pods with:

- a chart-generated `*-gha-rs-no-permission` service account;
- `automountServiceAccountToken: false`;
- no Kubernetes container-hook variables;
- no Secret `get` or `list` authorization; and
- an explicit 25 GiB Ceph-backed generic ephemeral workspace.

The trusted ARC controller retains its separate manager Role. The obsolete
`*-gha-rs-kube-mode` Roles, RoleBindings, and service accounts were removed
after confirming no pod used them. Do not re-enable Kubernetes container mode
without a design that keeps ARC credentials outside the workload trust domain.
Do not grant the development App workflow write access as a workaround.

### Isolation rules

- Never run automated validation against the interactive Onward server,
  database, ports, browser profile, or working tree.
- Every DB-backed lane needs a unique project identity, ports, users, volumes,
  and cleanup.
- Build once per exact candidate when browser shards can reuse the artifact.
- Do not run two heavy builds concurrently on the persistent LXC.
- Set pod requests/limits, job timeouts, cancellation/concurrency groups, and
  cleanup TTLs.
- Redact and secret-scan logs, screenshots, traces, and environment-derived
  files before artifact upload.
- Reap orphaned databases, volumes, pods, and workspaces by unique run identity
  and age; trap-based cleanup alone does not cover OOM, eviction, or node loss.
- Full milestone and merge gates remain mandatory even when affected selection
  is used during development.

## End-to-end flow

### Routine development

1. Human selects/approves the Plane work item.
2. Agent creates or resumes an isolated worktree on the LXC.
3. Agent edits and freezes a candidate SHA.
4. Agent invokes `verify:affected` against a trusted base.
5. Independent `verify:fast` and `verify:security` may overlap.
6. Agent reads compact structured results and continues productive work while
   independent lanes run.
7. Failures open only their first relevant artifact/log.

### Burst verification

1. The orchestrator determines that remote startup is amortized.
2. CI dispatches the exact candidate SHA to the `onward-runner` scale set.
3. ARC creates ephemeral runner pods up to the configured ceiling.
4. Each pod checks out the immutable revision and runs a harness profile.
5. CI retains compact results and raw artifacts.
6. The orchestrator consumes summaries, not complete runner logs.
7. Pods and disposable test resources are removed after completion, and a
   periodic reaper handles abnormal terminations.

This flow is deployed for the selected `fast` and `security` profiles. Container
jobs and `services:` are intentionally unsupported on this scale set; a profile
that needs them requires a separately designed execution lane.

### Promotion

1. Freeze a clean candidate SHA.
2. Run affected, fast, security, integration, E2E, and full gates as required by
   the repository milestone.
3. Complete required independent review, including Claude review for high-risk
   infrastructure/security changes. A second model on the same host is an
   independent reasoning pass, not an independent security principal; a human
   or separate read-only trust domain supplies consequential approval.
4. Record exact evidence in Git/Plane.
5. Push the candidate ref, then merge or deploy only through the protected
   repository gate and authoritative CI checks.

## Observability and measurements

Measure the platform by revision and profile. Required fields:

- queue/startup latency;
- dependency/cache preparation time;
- execution duration;
- artifact upload duration;
- total wall-clock duration;
- peak CPU, memory, and swap;
- cache hit/miss;
- retry and cancellation reason;
- result size delivered to the agent;
- raw log size retained externally; and
- execution-surface identity: Nix flake revision or runner image digest,
  toolchain/browser versions, and effective resource envelope;
- estimated agent tokens used to interpret deterministic results.

Track four separate latency classes:

1. model reasoning latency;
2. deterministic execution latency;
3. orchestration/context overhead; and
4. local-resource contention.

Success must be demonstrated by measured changes, not inferred from adding
infrastructure. Compare LXC and Kubernetes executions for the same exact SHA.
Use Kubernetes only when median end-to-end wall time, interactive-host
stability, or required isolation improves enough to cover operational cost.

Keep ephemeral debugging artifacts for seven days. Retain promotion evidence —
the exact SHA, profile, result schema/version, environment identity, outcome,
timing, checksums, and durable artifact reference — for the repository's audit
period in storage outside transient CI artifacts.

### First accepted burst evidence

Onward Actions run
[`33482692124`](https://github.com/sulibot/onward/actions/runs/33482692124)
verified exact SHA `92b9a4786b76acf35aab7e3bce7ef357580f3663` after the boundary change:

- security harness: passed in 1m19s;
- fast harness: passed in 1m39s;
- both live pods used `onward-runner-gha-rs-no-permission` with token automount
  disabled;
- Secret `get` and `list` authorization returned `no`;
- both compact artifact bundles were retained for seven days; and
- job pods and generic ephemeral PVCs returned to zero after completion.

## Failure and recovery

| Failure | Expected behavior | Recovery authority |
| --- | --- | --- |
| Laptop disconnects | LXC process continues | tmux/user service and worktree |
| Agent conversation is lost | Reconstruct from durable state | Git, Plane, `result.json`, docs |
| LXC reboots | NixOS returns system services, but tmux and non-service jobs terminate until P1 session management lands | flake, pushed refs, retained results, OpenBao AppRole |
| LXC or storage is lost | Recreate from IaC and restore only non-secret state; unpushed work is lost | pushed agent refs, PVE backup after P0, external artifacts |
| OpenBao unavailable | Refresh stops; cached static keys remain usable and short-lived credentials expire | OpenBao HA/runbook, systemd status, credential revocation runbook |
| API key revoked | Agent call fails; rotate in 1Password/OpenBao | credential inventory and refresh service |
| Harness interrupted | cleanup runs and result exits `130` | versioned aborted result and artifacts |
| Plane unavailable | Continue from Git refs/results; defer ticket synchronization | Git and later Plane reconciliation |
| Kubernetes unavailable | routine LXC lane remains usable | local/LXC harness |
| Runner pod fails | CI preserves bounded evidence; retry only classified transient failures | workflow/job attempt and artifacts |
| Bad NixOS generation | boot or switch previous generation | NixOS generation rollback |
| Bad repository change | revert/cherry-pick from exact Git state | trusted base and candidate SHA |

PVE backup schedule, retention, and a tested restore are target state and must
land before LXC loss can be considered recoverable. Backups must exclude or
encrypt credential caches and OpenBao bootstrap material.

## IaC ownership map

| Concern | Canonical location |
| --- | --- |
| LXC NixOS host | `nix/hosts/agent-devbox01/default.nix` |
| Agent packages, user, services | `nix/modules/profiles/agent-devbox.nix` |
| Nix inputs/configuration | `nix/flake.nix`, `nix/flake.lock` |
| OpenBao agent policy | `terraform/infra/live/services/openbao/policies/agent-devbox.hcl` |
| AppRole bootstrap | `terraform/infra/live/services/openbao/configure-integrations.sh` |
| DNS declaration | `terraform/infra/live/routeros/terragrunt.hcl` |
| PVE LXC object, storage, resources, backup | **Planned; canonical provider/path not yet selected** |
| ARC controller and home-ops runner | `kubernetes/apps/tier-2-applications/actions-runner-controller/` |
| ARC discovery, isolation, and alerts | `kubernetes/apps/tier-2-applications/actions-runner-controller/app/` |
| Per-scale-set listener metrics | `kubernetes/apps/tier-2-applications/actions-runner-controller/runners/*/helmrelease.yaml` |
| Multi-project CI dashboard | `kubernetes/apps/tier-1-infrastructure/grafana/dashboard/{grafanadashboard-engineering-ci.yaml,engineering-ci-dashboard-configmap.yaml}` |
| Onward harness | Onward `scripts/validation/` and `docs/implementation/VERIFICATION_HARNESS.md` |
| Onward burst workflow | Onward `.github/workflows/burst-verification.yml` |

## Current implementation status

| Capability | State on 2026-09-01 |
| --- | --- |
| Persistent DNS-addressable NixOS LXC | Deployed |
| Persistent `agent` user and worktree root | Deployed |
| Codex CLI unattended API authentication | Deployed and tested |
| Claude Code unattended API authentication | Deployed and tested |
| Scoped OpenBao refresh timer | Deployed and tested |
| Plane credential | Delivered; workspace/API integration incomplete |
| Repository-neutral harness contract | Proven in Onward, not yet extracted as a standard |
| Onward compact structured results | Implemented |
| Live `onward-runner` ARC scale set | Ready, zero idle runners, maximum three |
| Onward burst workflow | Present on the proving branch; fast/security smoke passed |
| `onward-runner` manifest in `home-ops` | Deployed through Flux from merged PR #334 |
| LXC CPU/memory/swap ceilings in IaC | Missing; live container is currently unlimited |
| Dedicated development-agent GitHub App | Missing; ARC identity must not be reused |
| Automatic short-lived GitHub token refresh | Blocked on dedicated App |
| LXC GitHub credential | None present; GitHub operations are unavailable |
| Persistent Codex credential cache | Present; boundary/backup remediation required |
| ARC runner workload secret isolation | Deployed and verified: no token, no Secret authorization |
| Accepted end-to-end Onward burst run | Passed for SHA `92b9a47`; artifacts and cleanup verified |
| ARC Prometheus metrics, runner network policy, and CI dashboard | Candidate; Onward is the first untrusted-verification canary and live convergence is pending |
| Per-test/reuse evidence history in Grafana | Planned; GitHub artifacts remain authoritative meanwhile |
| Protected promotion gate and CI authority | Must be verified per proving repository before agent write access |
| Universal multi-repository harness package | Deferred until Onward evidence justifies extraction |

## Convergence plan

### P0 — close trust and drift gaps

1. Verify protected-branch, human-review, and authoritative required-check
   policy for Onward. Treat LXC results as advisory.
2. Remove the staged ARC App path from the agent AppRole. Inventory all client
   caches, move secrets to ephemeral/read-at-use delivery, and define rotation
   plus holder restart/wipe behavior.
3. Create the dedicated development-agent GitHub App with least privileges,
   install it only on approved repositories, and mint constrained short-lived
   tokens through a read-at-use helper.
4. Select and commit the PVE provider/path for the LXC object. Declare CPU,
   memory, swap, startup, storage quota/reserve, backup, and restore-test policy.
5. Re-review the remaining infrastructure and secret boundaries. The initial
   Claude document review on 2026-09-01 returned **APPROVE WITH CHANGES** and
   produced the remaining items above. Claude separately approved the exact ARC
   boundary diff before PR #334 was merged.

### P1 — complete unattended coordination

1. Add Plane base URL, workspace slug, project identifier, and a read/write
   smoke test that does not expose ticket content in logs.
2. Add a durable job/session convention for Codex and Claude using tmux or
   systemd user services, with worktree and task metadata.
3. Define artifact retention outside conversation context and cleanup policy.
4. Add monitoring for the credential timer, LXC pressure, ARC listener/runner
   health, queue latency, failed cleanup, stale artifacts, disk headroom, and
   PVE/NixOS/Flux drift.
5. Put jobs in a constrained systemd slice with CPU, memory, task, and storage
   controls; enforce a machine-readable heavy-build concurrency lock.
6. Record producing agent/session identity in results and commit metadata.

### P2 — prove and extract

1. Record comparable local-Mac, LXC, and Kubernetes timings for exact SHAs.
2. Prove affected selection during development and full coverage at promotion.
3. Quantify compact-result token savings and end-to-end wall-clock change.
4. Extract only the stable repository-neutral pieces: command naming, result
   schema, agent policy block, bootstrap procedure, and optional remote runner
   integration.

Do not generalize the Onward harness until the proving data shows that its
contracts apply cleanly to another repository.

The first Kubernetes proof must use a known SHA and retain dispatch, pod,
harness, artifact, and cleanup evidence. It is not complete merely because the
scale-set listener is Ready.

## Acceptance criteria

The platform is considered operational when:

- closing the laptop does not stop an active server-owned task;
- NixOS can reproduce the LXC from committed configuration;
- the LXC has explicit PVE resource ceilings and measured headroom;
- Codex and Claude complete unattended smoke calls after a credential refresh;
- GitHub uses a dedicated short-lived least-privilege agent identity;
- the agent cannot directly push the protected branch or satisfy its own
  authoritative promotion checks;
- runner workloads cannot read ARC/controller secrets and the first complete
  burst run has retained cleanup evidence;
- Plane can be read and updated through an audited scoped credential;
- the same exact SHA can run through LXC or Kubernetes using one harness contract;
- Kubernetes starts from zero runners, respects concurrency/resource limits,
  retains evidence, and cleans up;
- agents consume compact summaries rather than passing logs;
- full canonical coverage remains required at merge/milestone boundaries;
- infrastructure/security changes receive independent review; and
- credential refresh, LXC pressure/disk, ARC health, and drift monitoring are
  live; PVE backup restore has been tested;
- Git, Plane, machine-readable results, and repository docs are sufficient to
  recover after loss of a client or conversation.

## Rollback

- Run the harness locally or on the LXC without Kubernetes; no repository test
  semantics depend on ARC.
- Disable/remove the burst workflow without changing canonical verification
  commands.
- Roll back the NixOS generation if the agent profile fails.
- After the dedicated App exists, revoke its installation/key without affecting
  the ARC App; this rollback is not available today.
- Revoke the OpenBao AppRole/policy, wipe `/run/agent-credentials/` and persistent
  client caches, and restart credential-holding processes to stop machine
  secret delivery.
- Keep the Mac-local deterministic harness as the minimum viable fallback.

Rollback must preserve worktrees, Git history, Plane state, and retained
verification artifacts.

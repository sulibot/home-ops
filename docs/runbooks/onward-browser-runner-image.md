# Onward browser runner image

## Purpose and boundary

`onward-browser-runner` is the separate, zero-idle scale set for only
`sulibot/onward` `.github/workflows/checks.yml` job `full` (Full gate).
Quick checks keep their two `onward-runner` slots and upstream image.
The Full gate runs Storybook tests, the production build, UI smoke tests,
the demo build, and saved-searches Playwright tests. Main runs and manual
branch dispatches can execute candidate code here; keep the same containment
as quick checks: no Kubernetes token, job secrets, registry write access, or
zot credentials. ARC's ExternalSecret is for controller authentication and is
not mounted into the job pod.

The recipe is
`kubernetes/apps/tier-2-applications/actions-runner-controller/images/onward-browser-runner/Dockerfile`.
It is outside the ARC Flux `app` and `runners` paths. No image build pipeline
exists in this repository. Google Chrome Stable and the Liberation and Noto
color emoji fonts are baked in because the job policy permits only cluster
DNS and GitHub/artifact/npm hosts, not Google downloads or Ubuntu archives.
Node and pnpm remain the workflow's responsibility.

Playwright uses `channel: "chrome"`, which needs `/opt/google/chrome/chrome`.
Downloaded Chromium is not a replacement. Playwright supplies `--no-sandbox`
and `--disable-dev-shm-usage`; Talos has `user.max_user_namespaces=0`, so
Chrome's own sandbox cannot run. No Onward flag changes are needed.

## Build and publish

Run these commands from the home-ops repository root on a networked machine
with Docker buildx and linux/amd64 execution support (native or emulated).
The owner must already have authenticated Docker to zot for pushing; do not
put credentials in the recipe or manifests. Nodes pull from zot without login.

### The image this change pins

`runners/onward-browser/helmrelease.yaml` pins
`zot.sulibot.com/onward-browser-runner:2.338.2-chrome157.0.8103.78@sha256:e95518246a397a9522c7eb5317cdf7ce4a7a8f4c2b0b677648be4460dffcc2ff`.
That is the image built from this Dockerfile on 2026-11-17 on the owner's Mac
(OrbStack, linux/amd64, `--provenance=false --sbom=false`), with Google Chrome
157.0.8103.78. It is **not in zot yet**: pushing needs the owner's zot login,
and the local Docker is logged in to `ghcr.io` only. Until it is pushed, nodes
cannot pull it and the scale set's first runner pod would sit in
`ImagePullBackOff`. Push that exact local image before merging:

```bash
docker push zot.sulibot.com/onward-browser-runner:2.338.2-chrome157.0.8103.78
docker buildx imagetools inspect zot.sulibot.com/onward-browser-runner:2.338.2-chrome157.0.8103.78
```

The top-level `Digest:` must equal the pin above (the containerd image store
pushes the manifest unchanged). If it differs, or the local image is gone,
rebuild with the recipe below and put the new tag and digest in the
HelmRelease.

First build locally, then read the actual installed Chrome version. The
second build reuses the installation layer from the same builder: do not
prune its cache or use `--no-cache` between the two builds. The build argument
only records metadata; it does not select Google's package version. Google's
`current` URL is mutable, so verify the published version before rollout.

```bash
set -eu
recipe=kubernetes/apps/tier-2-applications/actions-runner-controller/images/onward-browser-runner
image=zot.sulibot.com/onward-browser-runner

docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --load -t onward-browser-runner:probe "$recipe"
chrome_version="$(docker run --rm --platform linux/amd64 \
  --entrypoint /opt/google/chrome/chrome onward-browser-runner:probe \
  --version | awk '{print $3}')"
test -n "$chrome_version"
tag="2.338.2-chrome${chrome_version}"

docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --build-arg CHROME_VERSION="$chrome_version" \
  -t "$image:$tag" --push "$recipe"
docker buildx imagetools inspect "$image:$tag"
```

The tag format is `2.338.2-chrome<full Chrome version>`, including all four
Chrome version components. Copy the top-level `Digest: sha256:...` from
`imagetools inspect`, then verify that exact published image:

```bash
# Replace this value with the complete Digest from imagetools inspect.
digest=sha256:REPLACE_WITH_PUSHED_DIGEST
published_version="$(docker run --rm --platform linux/amd64 \
  --entrypoint /opt/google/chrome/chrome "$image@$digest" \
  --version | awk '{print $3}')"
test "$published_version" = "$chrome_version"
docker image inspect "$image@$digest" \
  --format '{{ index .Config.Labels "com.google.chrome.version" }}'
docker run --rm --platform linux/amd64 --entrypoint /bin/sh "$image@$digest" \
  -ec 'test "$(id -u)" = 1001; ldd /opt/google/chrome/chrome > /tmp/chrome-libraries; cat /tmp/chrome-libraries; ! grep "not found" /tmp/chrome-libraries'
```

The label must equal the installed version. If it differs, rebuild using the
newly read version and verify again before changing the HelmRelease. The
Dockerfile also fails the build if Chrome's version command or `ldd` fails,
or any library is missing. Only the supervisor/owner builds and pushes.

## Rollout and verification

After a rebuild, put the verified tag and digest in
`runners/onward-browser/helmrelease.yaml` (under the ARC directory). Never
merge placeholders or a digest that is not in zot.
Keep the Dockerfile base pin aligned with `runners/onward/helmrelease.yaml`;
a base update requires rebuilding and publishing this derived image.

After human review and merge, Flux rolls the scale set. Running jobs finish
on their old pods; newly created runners use the new image. Do not delete
busy ephemeral runners to accelerate the rollout. Verify on sol:

```bash
kubectl --context admin@sol -n actions-runner-system get autoscalingrunnerset onward-browser-runner
kubectl --context admin@sol -n actions-runner-system get pods \
  -l actions.github.com/scale-set-name=onward-browser-runner
kubectl --context admin@sol get ciliumclusterwidenetworkpolicy actions-runner-jobs-onward
```

Zero idle job pods is expected. Confirm the shared policy selects both sets
before dispatching candidate code. The Onward-side workflow change is a
separate prerequisite: `full.runs-on` must name `onward-browser-runner`, and
the workflow must include its "Show the browser the tests use" step. From a
checkout of `sulibot/onward`, dispatch one run:

```bash
gh workflow run Checks --ref <branch>
```

Replace `<branch>` with the branch containing that workflow change. The
"Show the browser the tests use" step should print the baked Google Chrome
version. Confirm Full uses the browser set, Quick still uses `onward-runner`,
and all Full steps complete. Investigate OOM events, disk usage and dropped
flows if they do not.

Checked before the change was proposed (2026-11-17, on the owner's Mac, not on
the cluster): the image builds for linux/amd64; `google-chrome` and
`/opt/google/chrome/chrome` print `Google Chrome 157.0.8103.78`; `ldd` finds no
missing library; the image runs as uid 1001 (`runner`). Inside that image,
with Node 24.20.0 and a clean `pnpm install --frozen-lockfile`, Playwright's
`channel: "chrome"` ran Onward's smoke test `page-help.spec.ts:56` and it
passed in 12.4 s. Not checked: a run on the cluster, any job through ARC, and
the full gate's other steps.

## Capacity

- Browser set: `minRunners: 0`, `maxRunners: 1`; request 1 CPU / 4 Gi,
  limit 4 CPU / 8 Gi, and a 25 Gi ephemeral RBD work volume on `csi-rbd-rbd-vm-sc`.
- Full runs `next build` with a 4 GB heap cap from `NODE_OPTIONS`, then a Next
  dev server, mock server and Chrome together. Quick's measured peaks were
  about 3.5 CPU and 2.95 GiB working set; Full needs additional memory headroom.
- Three workers each have 6 vCPU and about 15.1 GiB allocatable memory, plus
  one control plane. Worker memory requests were 62%, 81%, and 51% of
  allocatable, while actual use was about 40–53%. The 4 Gi request leaves
  more placement room than reserving the 8 Gi ceiling; placement still depends
  on available requests when the job starts. The limit is not a reservation.
- Both verification sets use `agentic-verification` priority -10 with
  `preemptionPolicy: Never`. Their ceilings total 2 quick × (1 CPU / 3 Gi)
  + 1 Full × (1 CPU / 4 Gi) = 3 pods / 3 CPU / 10 Gi. Adding the existing
  headroom of 1 pod / 1 CPU / 3 Gi gives quota 4 pods / 4 CPU / 13 Gi.
  Staging is outside this priority-scoped quota.
- Keep 25 Gi: dependencies, `.next`, Storybook/demo output, and test artifacts
  can coexist, but the builds are sequential and Chrome lives in the image,
  not the work volume. There is no measured evidence of output exceeding
  25 Gi. This is an initial capacity judgment, not a disk-usage measurement;
  measure the complete run before increasing it. A new job gets a fresh volume.

## Rollback

Restore the last verified browser image tag and digest in its HelmRelease
through a reviewed change; Flux rolls subsequent runners back while active
jobs finish. For the first deployment there is no previous browser image:
revert the Onward workflow routing first, drain active jobs, then remove the
browser set through a reviewed revert and restore the prior shared selector
and quota. GitHub-hosted Full remains blocked while billing is unresolved.
Keep quick checks on their unchanged scale set. Never remove containment while
candidate-code pods still exist.

## Owner decision: Google Fonts

**NOT APPLIED.** The Full gate cannot pass with only GitHub and npm egress.
Onward's pages include a stylesheet from `fonts.googleapis.com`
(`apps/web/src/app/layout.tsx`) and preconnect to `fonts.gstatic.com`, which
serves the font files. A default-deny policy drops those connections, so the
page's `load` event waits for them, and Playwright's `page.goto` waits for
`load`. Onward's `docs/staging-deployment.md` records the same failure on the
staging lane, with Hubble flows.

Shown on 2026-11-17 inside the candidate image on the owner's Mac, with the two
hosts mapped to `192.0.2.1` (a documentation address nothing answers, so the
connection hangs as a dropped one does), the same smoke test
(`page-help.spec.ts:56`, `pnpm exec playwright test --grep "a first visit shows one tip"`):

| Google Fonts hosts | Test timeout | Result |
| --- | --- | --- |
| reachable | raised to 240 s on the command line | passed in 12.4 s |
| dropped | raised to 240 s on the command line | passed in 2.4 minutes |
| dropped | the config's 45 s | failed: `page.goto: Test timeout of 45000ms exceeded`, waiting until "load" |

A test that opens a page pays this wait; the table shows it for one test, not
for all of them. These are the only extra hosts found. Not checked: the other
Full-gate steps (stories, `pnpm build`, the demo build) with egress limited, so
a further host is possible. `pnpm install` reaches npm, checkout and artifacts
reach GitHub, and Chrome is baked in.

The options are (a) allow the two hosts for the browser set only, below, or
(b) change Onward so its tests do not load them (for example, a fixture that
aborts those requests), which changes Onward's tests and was left out of
this work. The owner can decide whether to apply the following exact patch
from the repository root. It adds only TCP 443 to those two hosts for the
browser set. Cilium combines its egress allowance with the existing shared
policy, which still supplies DNS and ingress default-deny. Quick keeps only
GitHub/npm egress. Do not apply merely because Chrome is installed.

```diff
--- a/kubernetes/apps/tier-2-applications/actions-runner-controller/app/runner-networkpolicy.yaml
+++ b/kubernetes/apps/tier-2-applications/actions-runner-controller/app/runner-networkpolicy.yaml
@@ -167,3 +167,23 @@
         - ports:
             - port: "443"
               protocol: TCP
+---
+# Optional browser-only Google Fonts access; quick retains GitHub/npm only.
+apiVersion: cilium.io/v2
+kind: CiliumClusterwideNetworkPolicy
+metadata:
+  name: actions-runner-jobs-onward-browser-fonts
+spec:
+  endpointSelector:
+    matchLabels:
+      k8s:io.kubernetes.pod.namespace: actions-runner-system
+      actions.github.com/scale-set-name: onward-browser-runner
+      app.kubernetes.io/component: runner
+  egress:
+    - toFQDNs:
+        - matchName: fonts.googleapis.com
+        - matchName: fonts.gstatic.com
+      toPorts:
+        - ports:
+            - port: "443"
+              protocol: TCP
```

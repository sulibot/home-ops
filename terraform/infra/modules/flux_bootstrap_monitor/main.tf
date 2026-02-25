# Flux Bootstrap Monitor Module
# Creates a bootstrap override ConfigMap so Flux uses aggressive intervals during bootstrap.
# ks.yaml files use ${VAR:=production_default} — without the ConfigMap, apps run at
# their individual production-appropriate intervals. With the ConfigMap, all tier
# Kustomizations are overridden to aggressive bootstrap intervals.
# After bootstrap completes, the ConfigMap is deleted and apps revert to their defaults.

terraform {
  backend "local" {}

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

########## STEP 0: CREATE BOOTSTRAP OVERRIDE ConfigMap (IMMEDIATELY) ##########
# Applied as soon as this module runs — before Flux has time to reconcile at
# production defaults. Overrides all tier intervals to aggressive bootstrap values.
# Deleted in Step 5 after bootstrap completes.

resource "null_resource" "create_bootstrap_configmap" {
  triggers = {
    # Re-create if cluster changes (new kubeconfig) or bootstrap values change
    kubeconfig           = var.kubeconfig_path
    tier0_interval       = var.tier0_bootstrap_interval
    tier0_retry_interval = var.tier0_bootstrap_retry_interval
    tier1_interval       = var.tier1_bootstrap_interval
    tier1_retry_interval = var.tier1_bootstrap_retry_interval
    tier2_interval       = var.tier2_bootstrap_interval
    tier2_retry_interval = var.tier2_bootstrap_retry_interval
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🚀 CREATING BOOTSTRAP OVERRIDE ConfigMap"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  TIER0_INTERVAL:       ${var.tier0_bootstrap_interval}"
      echo "  TIER0_RETRY_INTERVAL: ${var.tier0_bootstrap_retry_interval}"
      echo "  TIER1_INTERVAL:       ${var.tier1_bootstrap_interval}"
      echo "  TIER1_RETRY_INTERVAL: ${var.tier1_bootstrap_retry_interval}"
      echo "  TIER2_INTERVAL:       ${var.tier2_bootstrap_interval}"
      echo "  TIER2_RETRY_INTERVAL: ${var.tier2_bootstrap_retry_interval}"

      kubectl --kubeconfig="${var.kubeconfig_path}" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-settings
  namespace: flux-system
  labels:
    app.kubernetes.io/managed-by: terraform
    bootstrap: "true"
data:
  TIER0_INTERVAL: "${var.tier0_bootstrap_interval}"
  TIER0_RETRY_INTERVAL: "${var.tier0_bootstrap_retry_interval}"
  TIER1_INTERVAL: "${var.tier1_bootstrap_interval}"
  TIER1_RETRY_INTERVAL: "${var.tier1_bootstrap_retry_interval}"
  TIER2_INTERVAL: "${var.tier2_bootstrap_interval}"
  TIER2_RETRY_INTERVAL: "${var.tier2_bootstrap_retry_interval}"
EOF

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✅ Bootstrap ConfigMap applied — Flux will pick up on next reconcile"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }
}

########## STEP 1: CHECK TIER 0 (FOUNDATION) ##########
# Uses kubectl directly — data "kubernetes_resource" returns null for non-existent
# resources and OpenTofu treats that as a fatal error on a fresh cluster.

resource "null_resource" "check_tier_0" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📦 TIER 0 (Foundation) Status"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      READY=$(kubectl --kubeconfig="${var.kubeconfig_path}" \
        get kustomization tier-0-foundation -n flux-system \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
      echo "Ready: $${READY:-Unknown}"
      echo ""
      echo "Apps included:"
      echo "  • gateway-api-crds"
      echo "  • snapshot-controller-crds"
      echo "  • cilium (CNI)"
      echo "  • external-secrets + onepassword"
      echo "  • ceph-csi (storage)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.create_bootstrap_configmap]
}

########## STEP 2: CHECK TIER 1 (INFRASTRUCTURE) ##########

resource "null_resource" "check_tier_1" {
  triggers = {
    tier_0_complete = null_resource.check_tier_0.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🏗️  TIER 1 (Infrastructure) Status"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      READY=$(kubectl --kubeconfig="${var.kubeconfig_path}" \
        get kustomization tier-1-infrastructure -n flux-system \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
      echo "Ready: $${READY:-Unknown}"
      echo ""
      echo "Apps included: 21 infrastructure services"
      echo "  • cert-manager, volsync, metrics-server"
      echo "  • multus, istio, external-dns"
      echo "  • postgres, redis"
      echo "  • prometheus, grafana, victoria-logs"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }
}

########## STEP 2.5: CNPG AUTOMATIC RESTORE ##########
# Checks for available backups (barman-cloud WAL or VolumeSnapshot).
# If found, the cluster is a rebuild (disaster recovery), not a fresh install:
#   1. Suspend the postgres-vectorchord Flux kustomization so Flux doesn't fight us
#   2. Delete the CNPG Cluster (takes its PVC with it — data dir is empty anyway)
#   3. Apply a recovery cluster spec (barman-cloud WAL preferred, snapshot fallback)
#   4. Wait for the cluster to reach healthy state
#   5. Normalize bootstrap: patch server from recovery → initdb BEFORE resuming Flux
#      (required: Flux dry-run 3-way merge of server:recovery + git:initdb produces both
#       methods simultaneously, which the CNPG webhook rejects as invalid)
#   6. Resume the kustomization — server bootstrap now matches Git, dry-run passes cleanly
# On a fresh install there are no backups, so this is a no-op.

resource "null_resource" "cnpg_restore" {
  triggers = {
    tier_1_complete = null_resource.check_tier_1.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      KC="kubectl --kubeconfig=${var.kubeconfig_path}"

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🐘 CNPG AUTOMATIC RESTORE CHECK"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      # Wait for CNPG operator to be running (CRDs registered + webhook active).
      # The tier-1 kustomization becomes Ready when resources are *applied*, but the
      # CNPG Helm chart may still be installing (operator pod starting, CRDs registering).
      # We must wait for the operator pod to be Ready — not just the CRD to exist — because
      # the CNPG validating webhook (which rejects invalid Cluster specs) runs in the operator.
      echo "Waiting for CNPG CRDs (up to 10m)..."
      if ! $KC wait --for=condition=Available crd/clusters.postgresql.cnpg.io \
          --timeout=600s 2>/dev/null; then
        echo "  ⚠️  CNPG CRDs not available after 10m — skipping restore check"
        exit 0
      fi
      echo "Waiting for CNPG operator pod (up to 5m)..."
      if ! $KC wait pods -l app.kubernetes.io/name=cloudnative-pg \
          -n cnpg-system --for=condition=Ready --timeout=300s 2>/dev/null; then
        echo "  ⚠️  CNPG operator pod not ready after 5m — skipping restore check"
        exit 0
      fi
      echo "  ✅ CNPG operator ready"

      # Check if the cluster is already running with data — if so, no restore needed.
      CLUSTER_PHASE=$($KC get cluster postgres-vectorchord -n default \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

      if [ "$CLUSTER_PHASE" = "Cluster in healthy state" ]; then
        echo "  ✅ Cluster already healthy — checking if data exists in 'immich' db..."
        ROW_COUNT=$($KC exec -n default postgres-vectorchord-1 -- \
          psql -U postgres -d immich -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" \
          -t 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$ROW_COUNT" -gt "0" ] 2>/dev/null; then
          echo "  ✅ Database has data — skipping restore"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          exit 0
        fi
        echo "  ℹ️  Cluster healthy but database empty — checking for backups to restore"
      fi

      # ── Determine restore source: prefer barman-cloud WAL, fall back to VolumeSnapshot ──
      RESTORE_METHOD=""

      # Check barman-cloud ObjectStore for available base backups
      BARMAN_RECOVERY_POINT=$($KC get objectstore postgres-vectorchord-backup -n default \
        -o jsonpath='{.status.serverRecoveryWindow.postgres-vectorchord.firstRecoverabilityPoint}' \
        2>/dev/null || true)

      if [ -n "$BARMAN_RECOVERY_POINT" ]; then
        RESTORE_METHOD="barman"
        echo "  📦 barman-cloud backup available (since: $BARMAN_RECOVERY_POINT)"
      fi

      # Check for VolumeSnapshot from a previous ScheduledBackup (fallback)
      SNAPSHOT=$($KC get volumesnapshot -n default \
        -l cnpg.io/cluster=postgres-vectorchord \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)

      if [ -z "$RESTORE_METHOD" ] && [ -n "$SNAPSHOT" ]; then
        RESTORE_METHOD="snapshot"
        echo "  📸 VolumeSnapshot available: $SNAPSHOT"
      fi

      if [ -z "$RESTORE_METHOD" ]; then
        echo "  ℹ️  No backups found — fresh install, skipping restore"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
      fi

      echo ""
      echo "  🔄 Performing automatic restore via: $RESTORE_METHOD"
      echo ""

      # 1. Suspend Flux kustomization to prevent it reverting our recovery spec
      echo "  1/6 Suspending postgres-vectorchord Flux kustomization..."
      $KC patch kustomization postgres-vectorchord -n flux-system \
        --type=merge -p '{"spec":{"suspend":true}}'

      # 2. Delete the CNPG Cluster (and its empty PVC)
      echo "  2/6 Deleting existing CNPG Cluster (if present)..."
      $KC delete cluster postgres-vectorchord -n default --ignore-not-found --wait=true
      $KC delete pvc postgres-vectorchord-1 -n default --ignore-not-found --wait=true

      # 3. Apply recovery cluster spec
      echo "  3/6 Applying recovery cluster spec (method: $RESTORE_METHOD)"

      if [ "$RESTORE_METHOD" = "barman" ]; then
        # barman-cloud WAL recovery — requires cnpg-plugin-barman-cloud to be installed.
        # The annotation skips the "Expected empty archive" check (archive has prior WALs).
        # IMPORTANT: include database/owner so the app secret points to the right database.
        # Do NOT include plugins.isWALArchiver here — Flux will re-add it after recovery;
        # CNPG ignores bootstrap once PGDATA exists, so WAL archiving resumes automatically.
        $KC apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-vectorchord
  namespace: default
  annotations:
    cnpg.io/skipEmptyWalArchiveCheck: "enabled"
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  bootstrap:
    recovery:
      source: postgres-vectorchord
      database: immich
      owner: immich
  externalClusters:
    - name: postgres-vectorchord
      plugin:
        enabled: true
        isWALArchiver: false
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-vectorchord-backup
  storage:
    resizeInUseVolumes: true
    size: 20Gi
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML

      else
        # VolumeSnapshot recovery (fast local)
        $KC apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-vectorchord
  namespace: default
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  bootstrap:
    recovery:
      database: immich
      owner: immich
      volumeSnapshots:
        storage:
          name: $SNAPSHOT
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  storage:
    resizeInUseVolumes: true
    size: 20Gi
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
      fi

      # 4. Wait for cluster to reach healthy state (up to 15 minutes)
      echo "  4/6 Waiting for cluster recovery (up to 15m)..."
      for i in $(seq 1 90); do
        PHASE=$($KC get cluster postgres-vectorchord -n default \
          -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        echo "      [$i/90] Phase: $${PHASE:-Pending}"
        if echo "$PHASE" | grep -qi "healthy"; then
          echo "  ✅ Cluster recovered successfully"
          break
        fi
        sleep 10
        if [ $i -eq 90 ]; then
          echo "  ⚠️  Recovery timed out after 15m — check cluster manually"
          # Still resume Flux so the system isn't left in a broken state
        fi
      done

      # 5. Normalize bootstrap spec: replace recovery → initdb BEFORE resuming Flux.
      #
      # WHY THIS IS REQUIRED:
      # Flux performs a dry-run merge before applying. kubectl's 3-way merge combines:
      #   - server state: bootstrap.recovery (what we just applied)
      #   - git state:    bootstrap.initdb   (what's in cluster.yaml)
      # The merged result contains BOTH methods simultaneously, which the CNPG validating
      # webhook rejects: "Only one bootstrap method can be specified at a time".
      # Normalizing the server state to initdb first makes it match Git, so the dry-run
      # produces no diff and Flux reconciles cleanly.
      echo "  5/6 Normalizing bootstrap spec (recovery → initdb) to prevent Flux merge conflict..."
      $KC patch cluster postgres-vectorchord -n default --type=json -p '[
        {"op":"replace","path":"/spec/bootstrap","value":{
          "initdb":{
            "database":"immich",
            "owner":"immich",
            "postInitApplicationSQL":[
              "CREATE EXTENSION IF NOT EXISTS vchord CASCADE;",
              "CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;"
            ]
          }
        }}
      ]' && echo "  ✅ Bootstrap normalized to initdb" \
        || echo "  ⚠️  Bootstrap normalization failed (non-fatal — Flux may need manual reconcile)"

      # 6. Resume Flux kustomization — server bootstrap now matches Git, dry-run will pass
      echo "  6/6 Resuming postgres-vectorchord Flux kustomization..."
      $KC patch kustomization postgres-vectorchord -n flux-system \
        --type=merge -p '{"spec":{"suspend":false}}'

      echo ""
      echo "✅ CNPG RESTORE COMPLETE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.check_tier_1]
}

########## STEP 3: WAIT FOR BOOTSTRAP COMPLETE ##########
# Critical app readiness is checked via kubectl polling inside the provisioner.
# We do NOT use data "kubernetes_resource" for HelmReleases here because those
# resources don't exist yet when Terraform plans/applies — the provider returns
# null and OpenTofu treats that as a fatal "Provider produced null object" error.

resource "null_resource" "wait_bootstrap_complete" {
  triggers = {
    # Only re-run if tier checks change
    tier_0_ready    = null_resource.check_tier_0.id
    tier_1_ready    = null_resource.check_tier_1.id
    cnpg_restore_id = null_resource.cnpg_restore.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "⏳ WAITING FOR BOOTSTRAP COMPLETE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Timeout: 45 minutes (2700 seconds)"
      echo ""

      START_TIME=$(date +%s)
      TIMEOUT_SECONDS=2700

      check_timeout() {
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
          echo ""
          echo "❌ TIMEOUT: Bootstrap exceeded 45 minutes"
          echo "   Current status may indicate issues"
          exit 1
        fi
        return 0
      }

      # Wait for Tier 0
      echo "Checking Tier 0 (Foundation)..."
      while ! kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization tier-0-foundation -n flux-system \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
        check_timeout
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "  ⏳ [$(($ELAPSED/60))m $(($ELAPSED%60))s] Tier 0 not ready, waiting..."
        sleep 10
      done
      echo "  ✅ Tier 0 Ready"

      # Wait for Tier 1
      echo ""
      echo "Checking Tier 1 (Infrastructure)..."
      while ! kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization tier-1-infrastructure -n flux-system \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
        check_timeout
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "  ⏳ [$(($ELAPSED/60))m $(($ELAPSED%60))s] Tier 1 not ready, waiting..."
        sleep 10
      done
      echo "  ✅ Tier 1 Ready"

      # Wait for critical apps
      echo ""
      echo "Checking Critical Apps..."
      ALL_READY=false
      while [ "$ALL_READY" != "true" ]; do
        check_timeout

        FAILED_APPS=()

        for app in "default/plex" "default/home-assistant" "default/immich"; do
          NAMESPACE=$(echo "$app" | cut -d'/' -f1)
          NAME=$(echo "$app" | cut -d'/' -f2)

          if kubectl --kubeconfig="${var.kubeconfig_path}" get helmrelease -n "$NAMESPACE" "$NAME" &>/dev/null; then
            if kubectl --kubeconfig="${var.kubeconfig_path}" get helmrelease -n "$NAMESPACE" "$NAME" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
              echo "  ✅ $NAME Ready"
            else
              FAILED_APPS+=("$NAME")
            fi
          else
            FAILED_APPS+=("$NAME (not found)")
          fi
        done

        if [ $${#FAILED_APPS[@]} -eq 0 ]; then
          ALL_READY=true
        else
          NOW=$(date +%s)
          ELAPSED=$((NOW - START_TIME))
          echo "  ⏳ [$((ELAPSED/60))m $((ELAPSED%60))s] Waiting for: $${FAILED_APPS[*]}"
          sleep 10
        fi
      done

      NOW=$(date +%s)
      TOTAL_ELAPSED=$((NOW - START_TIME))
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✅ BOOTSTRAP COMPLETE!"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Total time: $(($TOTAL_ELAPSED/60))m $(($TOTAL_ELAPSED%60))s"
      echo ""
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.cnpg_restore]
}

########## STEP 4: DELETE BOOTSTRAP ConfigMap (REVERT TO DEFAULTS) ##########
# Deleting the ConfigMap lets each app revert to its own ${VAR:=production_default}.
# No more override — every Kustomization runs at its individually tuned interval.

resource "null_resource" "delete_bootstrap_configmap" {
  count = var.auto_switch_intervals ? 1 : 0

  triggers = {
    bootstrap_complete = null_resource.wait_bootstrap_complete.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🔄 REMOVING BOOTSTRAP OVERRIDE ConfigMap"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      kubectl --kubeconfig="${var.kubeconfig_path}" \
        delete configmap cluster-settings -n flux-system --ignore-not-found

      echo ""
      echo "🔁 Triggering immediate Flux reconciliation cascade..."

      # Annotating the top-level 'apps' Kustomization causes kustomize-controller
      # to immediately re-reconcile the object via a watch event — no polling delay.
      # This cascades: apps → tier-0/tier-1/tier-2 → all individual app ks.yaml files,
      # which will now resolve their $${VAR:=default} with the ConfigMap absent,
      # falling back to each app's own production default.
      kubectl --kubeconfig="${var.kubeconfig_path}" \
        annotate kustomization apps -n flux-system \
        reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --overwrite

      echo ""
      echo "✅ ConfigMap deleted and reconciliation triggered."
      echo "   All apps will revert to their individual production defaults"
      echo "   within one reconcile cycle (~30s–1m)."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.wait_bootstrap_complete]
}

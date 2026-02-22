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
# Checks for an existing VolumeSnapshot from a previous ScheduledBackup.
# If one is found the cluster is a rebuild (disaster recovery), not a fresh install:
#   1. Suspend the postgres-vectorchord Flux kustomization so Flux doesn't fight us
#   2. Delete the CNPG Cluster (takes its PVC with it — data dir is empty anyway)
#   3. Apply a recovery cluster spec pointing at the latest snapshot
#   4. Wait for the cluster to reach Running state
#   5. Resume the kustomization — CNPG ignores spec.bootstrap changes once
#      the data directory already exists, so Flux reverting to initdb is harmless.
# On a fresh install there are no snapshots, so this is a no-op.

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

      # Wait for CNPG operator to be running (CRDs registered)
      echo "Waiting for CNPG operator..."
      for i in $(seq 1 30); do
        if $KC get crd scheduledbackups.postgresql.cnpg.io &>/dev/null; then
          echo "  ✅ CNPG operator ready"
          break
        fi
        echo "  ⏳ Attempt $i/30 — waiting for CNPG CRDs..."
        sleep 10
        if [ $i -eq 30 ]; then echo "  ⚠️  CNPG not ready after 5m — skipping restore check"; exit 0; fi
      done

      # Find the most recent VolumeSnapshot from a previous ScheduledBackup
      SNAPSHOT=$($KC get volumesnapshot -n default \
        -l cnpg.io/cluster=postgres-vectorchord \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)

      if [ -z "$SNAPSHOT" ]; then
        echo "  ℹ️  No CNPG snapshots found — fresh install, skipping restore"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
      fi

      echo "  📸 Found snapshot: $SNAPSHOT"

      # Check if the cluster is already running with data (not a fresh empty DB)
      CLUSTER_PHASE=$($KC get cluster postgres-vectorchord -n default \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

      if [ "$CLUSTER_PHASE" = "Cluster in healthy state" ]; then
        echo "  ✅ Cluster already healthy — checking if data exists..."
        # If cluster is healthy and has been running, no restore needed
        ROW_COUNT=$($KC exec -n default postgres-vectorchord-1 -- \
          psql -U postgres -d immich -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" \
          -t 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$ROW_COUNT" -gt "0" ] 2>/dev/null; then
          echo "  ✅ Database has data — skipping restore"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          exit 0
        fi
      fi

      echo ""
      echo "  🔄 Snapshot found + cluster is new — performing automatic restore"
      echo "     Snapshot: $SNAPSHOT"
      echo ""

      # 1. Suspend Flux kustomization to prevent it reverting our recovery spec
      echo "  1/5 Suspending postgres-vectorchord Flux kustomization..."
      $KC patch kustomization postgres-vectorchord -n flux-system \
        --type=merge -p '{"spec":{"suspend":true}}'

      # 2. Delete the CNPG Cluster (and its empty PVC)
      echo "  2/5 Deleting existing CNPG Cluster..."
      $KC delete cluster postgres-vectorchord -n default --ignore-not-found --wait=true
      $KC delete pvc postgres-vectorchord-1 -n default --ignore-not-found --wait=true

      # 3. Apply recovery cluster spec pointing at the snapshot
      echo "  3/5 Applying recovery cluster from snapshot: $SNAPSHOT"
      $KC apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-vectorchord
  namespace: default
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-1.1.0
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  bootstrap:
    recovery:
      volumeSnapshots:
        storage:
          name: $SNAPSHOT
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  storage:
    size: 20Gi
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML

      # 4. Wait for cluster to reach healthy state (up to 10 minutes)
      echo "  4/5 Waiting for cluster recovery (up to 10m)..."
      for i in $(seq 1 60); do
        PHASE=$($KC get cluster postgres-vectorchord -n default \
          -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        echo "      [$i/60] Phase: $${PHASE:-Pending}"
        if echo "$PHASE" | grep -qi "healthy"; then
          echo "  ✅ Cluster recovered successfully"
          break
        fi
        sleep 10
        if [ $i -eq 60 ]; then
          echo "  ⚠️  Recovery timed out after 10m — check cluster manually"
          # Still resume Flux so the system isn't left in a broken state
        fi
      done

      # 5. Resume Flux kustomization — CNPG ignores spec.bootstrap once data dir exists
      echo "  5/5 Resuming postgres-vectorchord Flux kustomization..."
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

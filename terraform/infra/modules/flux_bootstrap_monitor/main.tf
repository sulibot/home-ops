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

  # Delegates to scripts/cnpg-restore.sh — single source of truth.
  # The script can also be run manually without Terraform:
  #   ./scripts/cnpg-restore.sh --kubeconfig <path>
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "\"$(git -C \"${path.module}\" rev-parse --show-toplevel)\"/scripts/cnpg-restore.sh"
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
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

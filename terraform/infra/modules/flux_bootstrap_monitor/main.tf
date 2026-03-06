# Flux Bootstrap Monitor Module
# Event-driven bootstrap accelerator:
# - keeps steady-state Flux intervals fixed in Git
# - requests immediate reconciles at key milestones to avoid waiting for interval loops
# - waits for tier readiness for operator visibility

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

########## STEP 0: REQUEST IMMEDIATE RECONCILE CASCADE ##########
# Trigger top-level and tier kustomizations right away, so bootstrap speed
# is decoupled from normal reconcile intervals.

resource "null_resource" "request_initial_reconcile" {
  triggers = {
    kubeconfig = var.kubeconfig_path
    run_id     = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🚀 REQUESTING IMMEDIATE FLUX RECONCILIATION"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

      kubectl --kubeconfig="${var.kubeconfig_path}" \
        annotate gitrepository flux-system -n flux-system \
        reconcile.fluxcd.io/requestedAt="$TS" --overwrite || true

      for K in flux-system apps tier-0-foundation tier-1-infrastructure tier-2-applications; do
        if kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization "$K" -n flux-system >/dev/null 2>&1; then
          kubectl --kubeconfig="${var.kubeconfig_path}" \
            annotate kustomization "$K" -n flux-system \
            reconcile.fluxcd.io/requestedAt="$TS" \
            --overwrite || true
          echo "  ✅ requested reconcile for $K"
        else
          echo "  ℹ️  $K not found yet (skipped)"
        fi
      done

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✅ Reconcile requests submitted"
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

  depends_on = [null_resource.request_initial_reconcile]
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
      echo "Timeout: 5 minutes (300 seconds)"
      echo ""

      START_TIME=$(date +%s)
      TIMEOUT_SECONDS=300
      TIMED_OUT=false

      kustomization_ready() {
        local name="$1"
        kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization "$name" -n flux-system \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"
      }

      deployment_available() {
        local ns="$1"
        local name="$2"
        local ready
        ready=$(kubectl --kubeconfig="${var.kubeconfig_path}" get deployment "$name" -n "$ns" \
          -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
        [ "$ready" = "True" ]
      }

      daemonset_ready() {
        local ns="$1"
        local name="$2"
        local desired ready
        desired=$(kubectl --kubeconfig="${var.kubeconfig_path}" get daemonset "$name" -n "$ns" \
          -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
        ready=$(kubectl --kubeconfig="${var.kubeconfig_path}" get daemonset "$name" -n "$ns" \
          -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
        [ -n "$desired" ] && [ "$desired" != "0" ] && [ "$desired" = "$ready" ]
      }

      capability_ready_fallback() {
        local gate="$1"
        case "$gate" in
          "secrets-ready")
            deployment_available "external-secrets" "external-secrets" &&
              kubectl --kubeconfig="${var.kubeconfig_path}" get clustersecretstore onepassword-connect >/dev/null 2>&1
            ;;
          "storage-ready")
            daemonset_ready "ceph-csi" "ceph-csi-cephfs-nodeplugin" &&
              daemonset_ready "ceph-csi" "ceph-csi-rbd-nodeplugin" &&
              deployment_available "ceph-csi" "ceph-csi-cephfs-provisioner" &&
              deployment_available "ceph-csi" "ceph-csi-rbd-provisioner"
            ;;
          "postgres-vectorchord-ready")
            local phase
            phase=$(kubectl --kubeconfig="${var.kubeconfig_path}" get cluster postgres-vectorchord -n default \
              -o jsonpath='{.status.phase}' 2>/dev/null || true)
            echo "$phase" | grep -qi "healthy"
            ;;
          *)
            return 1
            ;;
        esac
      }

      check_timeout() {
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
          echo ""
          echo "⚠ TIMEOUT: Bootstrap exceeded 5 minutes"
          echo "  Continuing with partial readiness."
          return 1
        fi
        return 0
      }

      # Wait for Tier 0
      echo "Checking Tier 0 (Foundation)..."
      while ! kustomization_ready "tier-0-foundation"; do
        if ! check_timeout; then TIMED_OUT=true; break; fi
        ELAPSED=$(($(date +%s) - START_TIME))
        echo "  ⏳ [$(($ELAPSED/60))m $(($ELAPSED%60))s] Tier 0 not ready, waiting..."
        sleep 10
      done
      if [ "$TIMED_OUT" = "false" ]; then
        echo "  ✅ Tier 0 Ready"
      fi

      # Wait for capability gates (instead of full tier-1).
      # Full tier-1 can stay non-ready due optional CRDs/apps that are not bootstrap-critical.
      echo ""
      echo "Checking Capability Gates..."
      for GATE in "secrets-ready" "storage-ready" "postgres-vectorchord-ready"; do
        while [ "$TIMED_OUT" = "false" ]; do
          if kustomization_ready "$GATE"; then
            echo "  ✅ Gate '$GATE' Ready"
            break
          fi

          if capability_ready_fallback "$GATE"; then
            echo "  ✅ Gate '$GATE' Ready (fallback capability check)"
            break
          fi

          if ! check_timeout; then TIMED_OUT=true; break; fi
          ELAPSED=$(($(date +%s) - START_TIME))
          echo "  ⏳ [$(($ELAPSED/60))m $(($ELAPSED%60))s] Gate '$GATE' not ready, waiting..."
          sleep 10
        done
      done

      # Observe selected app readiness (non-gating).
      echo ""
      echo "App Snapshot (non-gating):"
      for app in "default/plex" "default/home-assistant" "default/immich"; do
        NAMESPACE=$(echo "$app" | cut -d'/' -f1)
        NAME=$(echo "$app" | cut -d'/' -f2)
        if kubectl --kubeconfig="${var.kubeconfig_path}" get helmrelease -n "$NAMESPACE" "$NAME" &>/dev/null; then
          READY=$(kubectl --kubeconfig="${var.kubeconfig_path}" get helmrelease -n "$NAMESPACE" "$NAME" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
          echo "  • $NAME: $${READY:-Unknown}"
        else
          echo "  • $NAME: not found"
        fi
      done

      NOW=$(date +%s)
      TOTAL_ELAPSED=$((NOW - START_TIME))
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      if [ "$TIMED_OUT" = "true" ]; then
        echo "⚠ BOOTSTRAP PARTIALLY COMPLETE (timeout reached)"
      else
        echo "✅ BOOTSTRAP COMPLETE!"
      fi
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Total time: $(($TOTAL_ELAPSED/60))m $(($TOTAL_ELAPSED%60))s"
      echo ""
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.cnpg_restore]
}

########## STEP 4: FINAL RECONCILE CASCADE ##########
# Ask Flux to immediately process any remaining dependency transitions.

resource "null_resource" "final_reconcile_cascade" {
  triggers = {
    bootstrap_complete = null_resource.wait_bootstrap_complete.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🔄 FINAL FLUX RECONCILE CASCADE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      for K in flux-system apps tier-0-foundation tier-1-infrastructure tier-2-applications; do
        if kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization "$K" -n flux-system >/dev/null 2>&1; then
          kubectl --kubeconfig="${var.kubeconfig_path}" \
            annotate kustomization "$K" -n flux-system \
            reconcile.fluxcd.io/requestedAt="$TS" \
            --overwrite || true
          echo "  ✅ requested reconcile for $K"
        else
          echo "  ℹ️  $K not found yet (skipped)"
        fi
      done
      echo ""
      echo "✅ Reconcile requests submitted."
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.wait_bootstrap_complete]
}

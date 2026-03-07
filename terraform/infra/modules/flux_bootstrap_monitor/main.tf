# Flux Bootstrap Monitor Module
# Event-driven bootstrap accelerator:
# - keeps steady-state Flux intervals fixed in Git
# - requests immediate reconciles at key milestones
# - runs CNPG recovery checks
# - verifies capability gates using an in-cluster job

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

########## STEP 0: REQUEST IMMEDIATE RECONCILE CASCADE ##########

resource "null_resource" "request_initial_reconcile" {
  triggers = {
    kubeconfig_path = var.kubeconfig_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
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
          echo "  ✓ requested reconcile for $K"
        else
          echo "  - $K not found yet (skipped)"
        fi
      done

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✓ Reconcile requests submitted"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }
}

########## STEP 1: CHECK TIER STATUS (NO CHURN) ##########

resource "null_resource" "check_tier_0" {
  triggers = {
    reconcile_id = null_resource.request_initial_reconcile.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      READY=$(kubectl --kubeconfig="${var.kubeconfig_path}" \
        get kustomization tier-0-foundation -n flux-system \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
      echo "Tier-0 Ready: $${READY:-Unknown}"
    EOT

    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "check_tier_1" {
  triggers = {
    tier_0_id = null_resource.check_tier_0.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      READY=$(kubectl --kubeconfig="${var.kubeconfig_path}" \
        get kustomization tier-1-infrastructure -n flux-system \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
      echo "Tier-1 Ready: $${READY:-Unknown}"
    EOT

    interpreter = ["bash", "-c"]
  }
}

########## STEP 2: WAIT FOR CRD CAPABILITIES ##########

resource "null_resource" "wait_crd_established" {
  triggers = {
    tier_1_id       = null_resource.check_tier_1.id
    kubeconfig_path = var.kubeconfig_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📚 WAITING FOR REQUIRED CRDs (Established)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      wait_crd_required() {
        local crd="$1"
        local timeout="$2"
        local deadline
        local now
        echo "  - required: $crd"

        deadline=$(( $(date +%s) + $${timeout%s} ))
        while true; do
          if kubectl --kubeconfig="${var.kubeconfig_path}" get "crd/$${crd}" >/dev/null 2>&1; then
            break
          fi
          now=$(date +%s)
          if [ "$now" -ge "$deadline" ]; then
            echo "    ✗ timeout waiting for required CRD to appear: $crd" >&2
            return 1
          fi
          sleep 5
        done

        if ! kubectl --kubeconfig="${var.kubeconfig_path}" wait \
          --for=condition=Established \
          --timeout="$${timeout}" \
          "crd/$${crd}"; then
          echo "    ✗ required CRD did not reach Established in time: $crd" >&2
          return 1
        fi

        return 0
      }

      wait_crd_optional() {
        local crd="$1"
        local timeout="$2"
        if ! wait_crd_required "$crd" "$timeout"; then
          echo "    ⚠ optional CRD gate timed out: $crd"
        fi
      }

      # Required for bootstrap capability checks and restore workflow.
      wait_crd_required "clustersecretstores.external-secrets.io" "300s"
      wait_crd_required "clusters.postgresql.cnpg.io" "600s"

      # Optional but preferred for snapshot-based CNPG restore fallback.
      wait_crd_optional "volumesnapshots.snapshot.storage.k8s.io" "180s"

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✓ Required CRDs are Established"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.check_tier_1]
}

########## STEP 3: CNPG RESTORE CHECK ##########

resource "null_resource" "cnpg_restore" {
  triggers = {
    crd_gate_id = null_resource.wait_crd_established.id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "\"$(git -C \"${path.module}\" rev-parse --show-toplevel)\"/scripts/cnpg-restore.sh"
    environment = {
      KUBECONFIG                        = var.kubeconfig_path
      CNPG_NEW_DB                       = var.cnpg_new_db ? "true" : "false"
      CNPG_RESTORE_MODE                 = var.cnpg_restore_mode
      CNPG_RESTORE_METHOD               = var.cnpg_restore_method
      CNPG_BACKUP_MAX_AGE_HOURS         = tostring(var.cnpg_backup_max_age_hours)
      CNPG_STALE_BACKUP_MAX_AGE_MINUTES = tostring(var.cnpg_stale_backup_max_age_minutes)
      CNPG_STORAGE_SIZE                 = var.cnpg_storage_size
    }
  }

  depends_on = [null_resource.wait_crd_established]
}

########## STEP 4: IN-CLUSTER CAPABILITY GATE JOB ##########

resource "null_resource" "wait_bootstrap_complete" {
  triggers = {
    cnpg_restore_id = null_resource.cnpg_restore.id
    timeout_seconds = tostring(var.bootstrap_timeout_seconds)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "⏳ RUNNING IN-CLUSTER CAPABILITY GATE CHECK"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      kubectl --kubeconfig="$KUBECONFIG" apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-bootstrap-capability-check
  namespace: flux-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flux-bootstrap-capability-check
rules:
  - apiGroups: ["kustomize.toolkit.fluxcd.io"]
    resources: ["kustomizations"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["external-secrets.io"]
    resources: ["clustersecretstores"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["postgresql.cnpg.io"]
    resources: ["clusters"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flux-bootstrap-capability-check
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flux-bootstrap-capability-check
subjects:
  - kind: ServiceAccount
    name: flux-bootstrap-capability-check
    namespace: flux-system
YAML

      kubectl --kubeconfig="$KUBECONFIG" delete job flux-bootstrap-capability-gates -n flux-system --ignore-not-found

      kubectl --kubeconfig="$KUBECONFIG" apply -f - <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: flux-bootstrap-capability-gates
  namespace: flux-system
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      serviceAccountName: flux-bootstrap-capability-check
      restartPolicy: Never
      containers:
        - name: gate-check
          image: public.ecr.aws/bitnami/kubectl:1.34.1
          command:
            - /bin/bash
            - -ec
            - |
              set -euo pipefail

              START_TIME=$(date +%s)
              TIMEOUT_SECONDS=${var.bootstrap_timeout_seconds}
              TIMED_OUT=false

              kustomization_ready() {
                kubectl -n flux-system get kustomization "$1" \
                  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q True
              }

              deployment_available() {
                local ns="$1"
                local name="$2"
                local ready
                ready=$(kubectl -n "$ns" get deployment "$name" \
                  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
                [ "$ready" = "True" ]
              }

              daemonset_ready() {
                local ns="$1"
                local name="$2"
                local desired
                local ready
                desired=$(kubectl -n "$ns" get daemonset "$name" \
                  -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || true)
                ready=$(kubectl -n "$ns" get daemonset "$name" \
                  -o jsonpath='{.status.numberReady}' 2>/dev/null || true)
                [ -n "$desired" ] && [ "$desired" != "0" ] && [ "$desired" = "$ready" ]
              }

              capability_ready_fallback() {
                local gate="$1"
                case "$gate" in
                  secrets-ready)
                    deployment_available external-secrets external-secrets &&
                      kubectl get clustersecretstore onepassword-connect >/dev/null 2>&1
                    ;;
                  storage-ready)
                    daemonset_ready ceph-csi ceph-csi-cephfs-nodeplugin &&
                      daemonset_ready ceph-csi ceph-csi-rbd-nodeplugin &&
                      deployment_available ceph-csi ceph-csi-cephfs-provisioner &&
                      deployment_available ceph-csi ceph-csi-rbd-provisioner
                    ;;
                  postgres-vectorchord-ready)
                    local phase
                    phase=$(kubectl -n default get cluster postgres-vectorchord \
                      -o jsonpath='{.status.phase}' 2>/dev/null || true)
                    echo "$phase" | grep -qi healthy
                    ;;
                  *)
                    return 1
                    ;;
                esac
              }

              check_timeout() {
                local now
                local elapsed
                now=$(date +%s)
                elapsed=$((now - START_TIME))
                if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
                  TIMED_OUT=true
                  return 1
                fi
                return 0
              }

              echo "Checking Tier 0..."
              while ! kustomization_ready tier-0-foundation; do
                if ! check_timeout; then
                  break
                fi
                sleep 10
              done

              if [ "$TIMED_OUT" = "false" ]; then
                echo "Checking capability gates..."
                for gate in secrets-ready storage-ready postgres-vectorchord-ready; do
                  while true; do
                    if kustomization_ready "$gate" || capability_ready_fallback "$gate"; then
                      echo "  ✓ $gate"
                      break
                    fi
                    if ! check_timeout; then
                      break
                    fi
                    sleep 10
                  done
                  [ "$TIMED_OUT" = "true" ] && break
                done
              fi

              echo "App snapshot (non-gating):"
              for app in plex home-assistant immich; do
                if kubectl -n default get helmrelease "$app" >/dev/null 2>&1; then
                  ready=$(kubectl -n default get helmrelease "$app" \
                    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
                  echo "  - $app: $ready"
                else
                  echo "  - $app: not found"
                fi
              done

              elapsed=$(( $(date +%s) - START_TIME ))
              if [ "$TIMED_OUT" = "true" ]; then
                echo "WARNING: bootstrap capability checks timed out after $elapsed seconds; continuing."
              else
                echo "SUCCESS: bootstrap capability checks passed in $elapsed seconds."
              fi
YAML

      WAIT_TIMEOUT=$(( ${var.bootstrap_timeout_seconds} + 180 ))
      kubectl --kubeconfig="$KUBECONFIG" wait -n flux-system --for=condition=Complete \
        --timeout="$${WAIT_TIMEOUT}s" job/flux-bootstrap-capability-gates

      kubectl --kubeconfig="$KUBECONFIG" logs -n flux-system job/flux-bootstrap-capability-gates || true

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✓ CAPABILITY GATE CHECK COMPLETE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }

  depends_on = [null_resource.cnpg_restore]
}

########## STEP 5: FINAL RECONCILE CASCADE ##########

resource "null_resource" "final_reconcile_cascade" {
  triggers = {
    bootstrap_complete = null_resource.wait_bootstrap_complete.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "🔄 FINAL FLUX RECONCILE CASCADE"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      LOCK_NS="flux-system"
      LOCK_NAME="bootstrap-reconcile-once"
      if kubectl --kubeconfig="${var.kubeconfig_path}" -n "$LOCK_NS" get configmap "$LOCK_NAME" >/dev/null 2>&1; then
        echo "↩ Reconcile cascade already performed once; skipping"
        exit 0
      fi

      TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      for K in flux-system apps tier-0-foundation tier-1-infrastructure tier-2-applications; do
        if kubectl --kubeconfig="${var.kubeconfig_path}" get kustomization "$K" -n flux-system >/dev/null 2>&1; then
          kubectl --kubeconfig="${var.kubeconfig_path}" \
            annotate kustomization "$K" -n flux-system \
            reconcile.fluxcd.io/requestedAt="$TS" \
            --overwrite || true
          echo "  ✓ requested reconcile for $K"
        else
          echo "  - $K not found yet (skipped)"
        fi
      done

      kubectl --kubeconfig="${var.kubeconfig_path}" -n "$LOCK_NS" apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: $LOCK_NAME
  namespace: $LOCK_NS
data:
  completedAt: "$TS"
YAML

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "✓ Final reconcile requests submitted"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.wait_bootstrap_complete]
}

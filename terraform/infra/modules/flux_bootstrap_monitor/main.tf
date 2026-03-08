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
        local established
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

        # Avoid `kubectl wait` here because CRDs can transiently exist with
        # nil status.conditions, which causes accessor errors and false negatives.
        while true; do
          established=$(kubectl --kubeconfig="${var.kubeconfig_path}" get "crd/$${crd}" \
            -o jsonpath='{range .status.conditions[?(@.type=="Established")]}{.status}{end}' 2>/dev/null || true)
          if [ "$established" = "True" ]; then
            echo "    ✓ $crd Established"
            return 0
          fi

          now=$(date +%s)
          if [ "$now" -ge "$deadline" ]; then
            echo "    ✗ required CRD did not reach Established in time: $crd" >&2
            return 1
          fi

          sleep 5
        done
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
    command     = <<-EOT
      set -euo pipefail

      KC="kubectl --kubeconfig=$KUBECONFIG"
      CLUSTER_NS="$CNPG_CLUSTER_NAMESPACE"
      CLUSTER_NAME="$CNPG_CLUSTER_NAME"
      KUSTOMIZATION_NS="$CNPG_KUSTOMIZATION_NAMESPACE"
      KUSTOMIZATION_NAME="$CNPG_KUSTOMIZATION_NAME"
      MAX_AGE_SECONDS=$((CNPG_BACKUP_MAX_AGE_HOURS * 3600))
      STALE_BACKUP_MAX_AGE_SECONDS=$((CNPG_STALE_BACKUP_MAX_AGE_MINUTES * 60))
      SECRETS_TIMEOUT_SECONDS="$CNPG_RESTORE_REQUIRED_SECRETS_TIMEOUT_SECONDS"
      FLUX_KUSTOMIZATION_TIMEOUT_SECONDS="$CNPG_RESTORE_FLUX_KUSTOMIZATION_TIMEOUT_SECONDS"
      FLUX_KUSTOMIZATION_NAMESPACE="$CNPG_RESTORE_FLUX_KUSTOMIZATION_NAMESPACE"
      FLUX_KUSTOMIZATION_NAME="$CNPG_RESTORE_FLUX_KUSTOMIZATION_NAME"
      FLUX_PRECHECK_KUSTOMIZATION_NAME="$CNPG_RESTORE_FLUX_PRECHECK_KUSTOMIZATION_NAME"
      RBD_GATE_TIMEOUT_SECONDS="$CNPG_RESTORE_RBD_GATE_TIMEOUT_SECONDS"
      RBD_SELF_HEAL_RETRIES="$CNPG_RESTORE_RBD_SELF_HEAL_RETRIES"
      RBD_SELF_HEAL_SETTLE_SECONDS="$CNPG_RESTORE_RBD_SELF_HEAL_SETTLE_SECONDS"
      RBD_NODEPLUGIN_NAMESPACE="$CNPG_RESTORE_RBD_NODEPLUGIN_NAMESPACE"
      RBD_NODEPLUGIN_DAEMONSET_NAME="$CNPG_RESTORE_RBD_NODEPLUGIN_DAEMONSET_NAME"
      CLUSTER_HEALTH_TIMEOUT_SECONDS="$CNPG_RESTORE_CLUSTER_HEALTH_TIMEOUT_SECONDS"
      DATABASE_CR_TIMEOUT_SECONDS="$CNPG_RESTORE_DATABASE_CR_TIMEOUT_SECONDS"
      PROGRESS_STALL_TIMEOUT_SECONDS="$CNPG_RESTORE_PROGRESS_STALL_TIMEOUT_SECONDS"
      RESUME_FLUX_ON_EXIT="false"
      SCHEDULED_STATE_FILE="$(mktemp)"
      RESTORE_METHOD=""

      cleanup() {
        if [ "$RESUME_FLUX_ON_EXIT" = "true" ]; then
          $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null 2>&1 || true
        fi
        if [ -f "$SCHEDULED_STATE_FILE" ]; then
          while IFS=$'\t' read -r name previous; do
            [ -z "$name" ] && continue
            [ "$previous" = "true" ] && desired="true" || desired="false"
            $KC -n "$CLUSTER_NS" patch scheduledbackup "$name" --type=merge -p "{\"spec\":{\"suspend\":$desired}}" >/dev/null 2>&1 || true
          done < "$SCHEDULED_STATE_FILE"
          rm -f "$SCHEDULED_STATE_FILE" >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT

      stage() {
        local title="$1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$title"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      }

      wait_until() {
        local timeout_seconds="$1"
        local interval_seconds="$2"
        shift 2
        local deadline=$(( $(date +%s) + timeout_seconds ))
        while true; do
          if "$@"; then
            return 0
          fi
          if [ "$(date +%s)" -ge "$deadline" ]; then
            return 1
          fi
          sleep "$interval_seconds"
        done
      }

      request_flux_reconcile() {
        local ns="$1"
        local name="$2"
        local ts
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        $KC -n "$ns" annotate kustomization "$name" reconcile.fluxcd.io/requestedAt="$ts" --overwrite >/dev/null 2>&1 || true
      }

      is_flux_kustomization_ready() {
        local ns="$1"
        local name="$2"
        local status
        status="$($KC -n "$ns" get kustomization "$name" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Ready") | .status' | head -n1 || true)"
        [ "$status" = "True" ]
      }

      wait_for_flux_kustomization_ready() {
        local timeout_seconds="$1"
        local ns="$2"
        local name="$3"
        local deadline=$(( $(date +%s) + timeout_seconds ))
        local last_reconcile_request=0
        while [ "$(date +%s)" -lt "$deadline" ]; do
          if is_flux_kustomization_ready "$ns" "$name"; then
            return 0
          fi
          now="$(date +%s)"
          if [ $((now - last_reconcile_request)) -ge 30 ]; then
            request_flux_reconcile "$ns" "$name"
            last_reconcile_request="$now"
          fi
          sleep 5
        done
        return 1
      }

      age_from_plugin_backup() {
        $KC -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | jq -r --arg cluster "$CLUSTER_NAME" '
          [ .items[]?
            | select(
                ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
                or ((.spec.cluster.name // "") == $cluster)
              )
            | select((.spec.method // "") == "plugin")
            | select((.status.phase // "" | ascii_downcase) == "completed")
            | (now - ((.status.stoppedAt // .status.completedAt // .metadata.creationTimestamp) | fromdateiso8601))
          ] | if length == 0 then "" else (min | floor | tostring) end'
      }

      age_from_snapshot() {
        $KC -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=$CLUSTER_NAME" -o json 2>/dev/null | jq -r '
          [ .items[]?
            | select((.status.readyToUse // false) == true)
            | (now - (.metadata.creationTimestamp | fromdateiso8601))
          ] | if length == 0 then "" else (min | floor | tostring) end'
      }

      wait_for_cluster_healthy() {
        local timeout_seconds="$1"
        local deadline=$(( $(date +%s) + timeout_seconds ))
        local last_progress_ts="$(date +%s)"
        local last_progress_sig=""
        while [ "$(date +%s)" -lt "$deadline" ]; do
          phase="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
          if echo "$phase" | grep -qi "healthy"; then
            return 0
          fi

          progress_sig="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o json 2>/dev/null | jq -r '
            [
              (.status.phase // ""),
              (.status.currentPrimary // ""),
              (.status.conditions[]? | select(.type=="Ready") | .reason // "")
            ] | join("|")' || true)"
          if [ -n "$progress_sig" ] && [ "$progress_sig" != "$last_progress_sig" ]; then
            last_progress_sig="$progress_sig"
            last_progress_ts="$(date +%s)"
          fi

          blocker="$(detect_restore_blocker || true)"
          if [ -n "$blocker" ]; then
            echo "ERROR: restore blocked before healthy: $blocker" >&2
            dump_restore_state
            return 1
          fi

          if [ $(( $(date +%s) - last_progress_ts )) -ge "$PROGRESS_STALL_TIMEOUT_SECONDS" ]; then
            echo "ERROR: restore progress stalled for $PROGRESS_STALL_TIMEOUT_SECONDS seconds" >&2
            dump_restore_state
            return 1
          fi

          sleep 10
        done
        echo "ERROR: cluster did not become healthy in $timeout_seconds seconds" >&2
        dump_restore_state
        return 1
      }

      wait_for_database_crs() {
        local timeout_seconds="$1"
        local deadline=$(( $(date +%s) + timeout_seconds ))
        while [ "$(date +%s)" -lt "$deadline" ]; do
          pending="$($KC -n "$CLUSTER_NS" get databases.postgresql.cnpg.io -o json 2>/dev/null | jq -r '[.items[]? | select((.status.applied // false) != true) | .metadata.name] | join(",")' || true)"
          if [ -z "$pending" ] || [ "$pending" = "null" ]; then
            return 0
          fi
          sleep 10
        done
        return 1
      }

      wait_for_secret_with_reconcile() {
        local timeout_seconds="$1"
        local secret_name="$2"
        local deadline=$(( $(date +%s) + timeout_seconds ))
        local last_reconcile_request=0
        local last_status_log=0

        while [ "$(date +%s)" -lt "$deadline" ]; do
          if $KC -n "$CLUSTER_NS" get secret "$secret_name" >/dev/null 2>&1; then
            return 0
          fi

          now="$(date +%s)"
          if [ $((now - last_reconcile_request)) -ge 20 ]; then
            request_flux_reconcile "$FLUX_KUSTOMIZATION_NAMESPACE" "$FLUX_PRECHECK_KUSTOMIZATION_NAME"
            request_flux_reconcile "$FLUX_KUSTOMIZATION_NAMESPACE" "$FLUX_KUSTOMIZATION_NAME"
            last_reconcile_request="$now"
          fi

          if [ $((now - last_status_log)) -ge 30 ]; then
            ext_ready="$($KC -n "$CLUSTER_NS" get externalsecret "$secret_name" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Ready") | "\(.status // "Unknown")/\(.reason // "Unknown")"' | head -n1 || true)"
            flux_precheck_ready="$($KC -n "$FLUX_KUSTOMIZATION_NAMESPACE" get kustomization "$FLUX_PRECHECK_KUSTOMIZATION_NAME" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Ready") | "\(.status // "Unknown")/\(.reason // "Unknown")"' | head -n1 || true)"
            flux_main_ready="$($KC -n "$FLUX_KUSTOMIZATION_NAMESPACE" get kustomization "$FLUX_KUSTOMIZATION_NAME" -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type=="Ready") | "\(.status // "Unknown")/\(.reason // "Unknown")"' | head -n1 || true)"

            [ -z "$ext_ready" ] && ext_ready="not-found-or-pending"
            [ -z "$flux_precheck_ready" ] && flux_precheck_ready="not-found-or-pending"
            [ -z "$flux_main_ready" ] && flux_main_ready="not-found-or-pending"

            echo "WAIT: secret/$secret_name is not ready yet (ExternalSecret=$ext_ready, precheck=$flux_precheck_ready, main=$flux_main_ready)"
            last_status_log="$now"
          fi

          sleep 5
        done

        return 1
      }

      workers_missing_rbd_csi() {
        local workers
        workers="$($KC get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
        [ -z "$workers" ] && return 0

        while IFS= read -r node; do
          [ -z "$node" ] && continue
          has_rbd="$($KC get csinode "$node" -o json 2>/dev/null | jq -r '[.spec.drivers[]?.name] | index("rbd.csi.ceph.com") != null' || echo false)"
          if [ "$has_rbd" != "true" ]; then
            echo "$node"
          fi
        done <<< "$workers"
      }

      restart_rbd_nodeplugin_pod_for_node() {
        local node="$1"
        local pod
        pod="$($KC -n "$RBD_NODEPLUGIN_NAMESPACE" get pods -o json 2>/dev/null | jq -r --arg node "$node" --arg ds "$RBD_NODEPLUGIN_DAEMONSET_NAME" '
          [.items[]?
            | select(.spec.nodeName == $node)
            | select(any(.metadata.ownerReferences[]?; .kind == "DaemonSet" and .name == $ds))
            | .metadata.name
          ] | first // ""' || true)"

        if [ -z "$pod" ]; then
          echo "WARN: no rbd nodeplugin pod found on node '$node'" >&2
          return 1
        fi

        echo "WARN: restarting rbd nodeplugin pod '$pod' on node '$node'" >&2
        $KC -n "$RBD_NODEPLUGIN_NAMESPACE" delete pod "$pod" --wait=false >/dev/null 2>&1 || true
        return 0
      }

      wait_for_rbd_csi_on_workers() {
        local timeout_seconds="$1"
        local deadline=$(( $(date +%s) + timeout_seconds ))
        while [ "$(date +%s)" -lt "$deadline" ]; do
          missing="$(workers_missing_rbd_csi || true)"
          if [ -z "$missing" ]; then
            return 0
          fi

          if [ -z "$($KC get nodes -l '!node-role.kubernetes.io/control-plane' -o name 2>/dev/null || true)" ]; then
            sleep 5
            continue
          fi
          sleep 5
        done
        return 1
      }

      ensure_rbd_csi_on_workers() {
        local timeout_seconds="$1"
        local retries="$2"
        local settle_seconds="$3"
        local attempt=0

        while true; do
          if wait_for_rbd_csi_on_workers "$timeout_seconds"; then
            return 0
          fi

          missing="$(workers_missing_rbd_csi || true)"
          [ -z "$missing" ] && return 0

          if [ "$attempt" -ge "$retries" ]; then
            echo "ERROR: rbd.csi.ceph.com missing on worker CSINodes after $attempt self-heal attempt(s): $(echo "$missing" | tr '\n' ',' | sed 's/,$//')" >&2
            return 1
          fi

          echo "WARN: rbd.csi.ceph.com missing on nodes: $(echo "$missing" | tr '\n' ',' | sed 's/,$//')" >&2
          while IFS= read -r node; do
            [ -z "$node" ] && continue
            restart_rbd_nodeplugin_pod_for_node "$node" || true
          done <<< "$missing"

          attempt=$((attempt + 1))
          sleep "$settle_seconds"
        done
      }

      barman_object_store_probe() {
        if [ "$CNPG_OBJECT_STORE_PROBE_MODE" = "off" ]; then
          return 0
        fi

        if ! command -v aws >/dev/null 2>&1; then
          if [ "$CNPG_OBJECT_STORE_PROBE_MODE" = "required" ]; then
            echo "ERROR: aws CLI is required for CNPG object-store probe mode=required" >&2
            return 1
          fi
          echo "WARN: aws CLI not found; skipping direct object-store probe (mode=auto)." >&2
          return 0
        fi

        secret_json="$($KC -n "$CLUSTER_NS" get secret cnpg-barman-s3 -o json 2>/dev/null || true)"
        [ -z "$secret_json" ] && return 1

        decode_key() {
          local key="$1"
          echo "$secret_json" | jq -r --arg k "$key" '.data[$k] // empty' | base64 -d 2>/dev/null || true
        }

        endpoint="$(decode_key endpoint)"
        [ -z "$endpoint" ] && endpoint="$(decode_key ENDPOINT_URL)"
        [ -z "$endpoint" ] && endpoint="$(decode_key AWS_ENDPOINT)"
        [ -z "$endpoint" ] && endpoint="$(decode_key S3_ENDPOINT)"

        bucket="$(decode_key bucket)"
        [ -z "$bucket" ] && bucket="$(decode_key BUCKET_NAME)"

        access_key="$(decode_key ACCESS_KEY_ID)"
        [ -z "$access_key" ] && access_key="$(decode_key ACCESS_KEY)"

        secret_key="$(decode_key SECRET_ACCESS_KEY)"
        [ -z "$secret_key" ] && secret_key="$(decode_key ACCESS_SECRET_KEY)"

        if [ -z "$endpoint" ] || [ -z "$bucket" ] || [ -z "$access_key" ] || [ -z "$secret_key" ]; then
          if [ "$CNPG_OBJECT_STORE_PROBE_MODE" = "required" ]; then
            echo "ERROR: CNPG object-store probe missing endpoint/bucket/credentials in cnpg-barman-s3 secret" >&2
            return 1
          fi
          echo "WARN: skipping direct object-store probe; secret keys are incomplete (mode=auto)." >&2
          return 0
        fi

        if ! timeout "$CNPG_OBJECT_STORE_PROBE_TIMEOUT_SECONDS" env \
          AWS_ACCESS_KEY_ID="$access_key" \
          AWS_SECRET_ACCESS_KEY="$secret_key" \
          AWS_EC2_METADATA_DISABLED=true \
          aws --endpoint-url "$endpoint" s3api list-objects-v2 \
            --bucket "$bucket" \
            --max-items 1 \
            --query 'length(Contents)' \
            --output text >/dev/null 2>&1; then
          if [ "$CNPG_OBJECT_STORE_PROBE_MODE" = "required" ]; then
            echo "ERROR: direct object-store probe failed for bucket '$bucket' at '$endpoint'" >&2
            return 1
          fi
          echo "WARN: direct object-store probe failed (mode=auto); continuing with in-cluster metadata logic." >&2
          return 0
        fi
        return 0
      }

      detect_restore_blocker() {
        local pods
        pods="$($KC -n "$CLUSTER_NS" get pods -o json 2>/dev/null | jq -r --arg cluster "$CLUSTER_NAME" '
          [.items[]?
            | select(
                ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
                or (.metadata.name | startswith($cluster + "-"))
              )
            | .metadata.name
          ] | .[]' || true)"
        [ -z "$pods" ] && return 1

        while IFS= read -r pod; do
          [ -z "$pod" ] && continue
          pod_phase="$($KC -n "$CLUSTER_NS" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
          if [ "$pod_phase" = "Failed" ]; then
            echo "pod/$pod entered Failed phase"
            return 0
          fi

          if [ "$pod_phase" = "Pending" ]; then
            warning="$($KC -n "$CLUSTER_NS" get events --field-selector "involvedObject.kind=Pod,involvedObject.name=$pod,type=Warning" -o json 2>/dev/null | jq -r '
              [.items[]?
                | "\(.reason // ""): \(.message // "")"
                | select(test("does not contain driver rbd.csi.ceph.com|timed out waiting for the condition"))
              ] | last // ""' || true)"
            if [ -n "$warning" ]; then
              echo "pod/$pod pending with warning: $warning"
              return 0
            fi
          fi
        done <<< "$pods"

        return 1
      }

      dump_restore_state() {
        echo "----- restore diagnostics start -----" >&2
        $KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o wide >&2 || true
        $KC -n "$CLUSTER_NS" get pods -l "cnpg.io/cluster=$CLUSTER_NAME" -o wide >&2 || true
        $KC -n "$CLUSTER_NS" get pvc "$${CLUSTER_NAME}-1" -o wide >&2 || true
        $KC -n "$CLUSTER_NS" get events --sort-by=.lastTimestamp | tail -n 20 >&2 || true
        echo "----- restore diagnostics end -----" >&2
      }

      stage "CNPG RESTORE ORCHESTRATION (INLINE)"
      echo "Mode: $CNPG_RESTORE_MODE"
      echo "Restore method preference: $CNPG_RESTORE_METHOD"

      if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required for CNPG restore orchestration" >&2
        exit 1
      fi

      stage "STAGE 1: NO-OP CHECK FOR EXISTING HEALTHY DATA"
      # If cluster is already healthy and has user data, leave it alone.
      phase="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if echo "$phase" | grep -qi "healthy"; then
        primary="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
        if [ -n "$primary" ]; then
          table_count="$($KC -n "$CLUSTER_NS" exec "$primary" -- psql -U postgres -Atqc "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null | tr -d ' ' || echo 0)"
          if [ "$${table_count:-0}" -gt 0 ] 2>/dev/null; then
            echo "Cluster already healthy with data; skipping restore."
            exit 0
          fi
        fi
      fi

      stage "STAGE 2: DETECT RESTORE SOURCE"
      plugin_age="$(age_from_plugin_backup || true)"
      snapshot_age="$(age_from_snapshot || true)"
      plugin_fresh="false"
      snapshot_fresh="false"
      if [ -n "$plugin_age" ] && [ "$plugin_age" -le "$MAX_AGE_SECONDS" ]; then
        plugin_fresh="true"
      fi
      if [ -n "$snapshot_age" ] && [ "$snapshot_age" -le "$MAX_AGE_SECONDS" ]; then
        snapshot_fresh="true"
      fi

      case "$CNPG_RESTORE_METHOD" in
        barman)
          [ "$plugin_fresh" = "true" ] && RESTORE_METHOD="barman"
          ;;
        snapshot)
          [ "$snapshot_fresh" = "true" ] && RESTORE_METHOD="snapshot"
          ;;
        auto)
          if [ "$plugin_fresh" = "true" ]; then
            RESTORE_METHOD="barman"
          elif [ "$snapshot_fresh" = "true" ]; then
            RESTORE_METHOD="snapshot"
          fi
          ;;
        *)
          echo "ERROR: invalid CNPG_RESTORE_METHOD '$CNPG_RESTORE_METHOD'" >&2
          exit 1
          ;;
      esac

      if [ -z "$RESTORE_METHOD" ]; then
        if [ "$CNPG_RESTORE_MODE" = "NEW_DB" ]; then
          echo "No fresh backup found; NEW_DB mode allows fresh bootstrap."
          exit 0
        fi

        # In RESTORE_REQUIRED mode, allow barman restore attempts when backup metadata
        # is missing from the fresh cluster but object-store backups exist in MinIO.
        if [ "$CNPG_RESTORE_METHOD" = "auto" ] || [ "$CNPG_RESTORE_METHOD" = "barman" ]; then
          echo "WARN: no fresh in-cluster backup metadata detected; forcing barman restore attempt." >&2
          echo "      plugin_age='$${plugin_age:-<none>}' snapshot_age='$${snapshot_age:-<none>}'" >&2
          RESTORE_METHOD="barman"
        else
          echo "ERROR: no fresh backup found and CNPG_RESTORE_MODE=RESTORE_REQUIRED" >&2
          exit 1
        fi
      fi

      stage "STAGE 3: PRE-READINESS GATES"
      # Nudge the precheck and CNPG kustomizations, but do not hard-gate on Ready.
      # During bootstrap/restore, the postgres kustomization can be transiently NotReady
      # due expected bootstrap drift while still producing required secrets.
      request_flux_reconcile "$FLUX_KUSTOMIZATION_NAMESPACE" "$FLUX_PRECHECK_KUSTOMIZATION_NAME"
      request_flux_reconcile "$FLUX_KUSTOMIZATION_NAMESPACE" "$FLUX_KUSTOMIZATION_NAME"

      # Prevent CNPG restore from burning timeout while PVCs cannot attach.
      if ! ensure_rbd_csi_on_workers "$RBD_GATE_TIMEOUT_SECONDS" "$RBD_SELF_HEAL_RETRIES" "$RBD_SELF_HEAL_SETTLE_SECONDS"; then
        echo "ERROR: rbd.csi.ceph.com is not registered on all worker CSINodes" >&2
        exit 1
      fi

      # Only gate restore on the backup credential when using barman restore.
      if [ "$RESTORE_METHOD" = "barman" ]; then
        if ! wait_for_secret_with_reconcile "$SECRETS_TIMEOUT_SECONDS" "cnpg-barman-s3"; then
          echo "ERROR: required CNPG secret 'cnpg-barman-s3' did not become ready in time" >&2
          exit 1
        fi
        if ! barman_object_store_probe; then
          echo "ERROR: object-store preflight failed for barman restore path" >&2
          exit 1
        fi
      fi

      current_suspend="$($KC -n "$KUSTOMIZATION_NS" get kustomization "$KUSTOMIZATION_NAME" -o jsonpath='{.spec.suspend}' 2>/dev/null || true)"
      if [ "$current_suspend" != "true" ]; then
        $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null
        RESUME_FLUX_ON_EXIT="true"
      fi

      if $KC -n "$CLUSTER_NS" get scheduledbackup >/dev/null 2>&1; then
        while IFS=$'\t' read -r name previous; do
          [ -z "$name" ] && continue
          [ -z "$previous" ] && previous="false"
          printf '%s\t%s\n' "$name" "$previous" >> "$SCHEDULED_STATE_FILE"
          if [ "$previous" != "true" ]; then
            $KC -n "$CLUSTER_NS" patch scheduledbackup "$name" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null || true
          fi
        done < <($KC -n "$CLUSTER_NS" get scheduledbackup -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.suspend}{"\n"}{end}' 2>/dev/null || true)
      fi

      # Clear stale non-completed Backup CRs before restore.
      stale_backups="$($KC -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | jq -r --arg cluster "$CLUSTER_NAME" --argjson cutoff "$STALE_BACKUP_MAX_AGE_SECONDS" '
        [.items[]?
          | select(
              ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
              or ((.spec.cluster.name // "") == $cluster)
            )
          | select((.status.phase // "" | ascii_downcase) != "completed")
          | {name: .metadata.name, ts: (.status.startedAt // .metadata.creationTimestamp // "")}
          | select(.ts != "")
          | . + {age: (now - (.ts | fromdateiso8601))}
          | select(.age > $cutoff)
          | .name
        ] | .[]' || true)"
      if [ -n "$stale_backups" ]; then
        while IFS= read -r b; do
          [ -z "$b" ] && continue
          $KC -n "$CLUSTER_NS" delete backup.postgresql.cnpg.io "$b" --ignore-not-found >/dev/null 2>&1 || true
        done <<< "$stale_backups"
      fi

      stage "STAGE 4: SUSPEND GITOPS + PREPARE CLEAN RESTORE"
      $KC -n "$CLUSTER_NS" delete cluster "$CLUSTER_NAME" --ignore-not-found --wait=true >/dev/null || true
      $KC -n "$CLUSTER_NS" delete pvc "$${CLUSTER_NAME}-1" --ignore-not-found --wait=true >/dev/null || true

      stage "STAGE 5: APPLY RECOVERY CLUSTER SPEC"
      if [ "$RESTORE_METHOD" = "barman" ]; then
        $KC -n "$CLUSTER_NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $CLUSTER_NAME
  namespace: $CLUSTER_NS
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
  backup:
    volumeSnapshot:
      className: csi-rbd-rbd-vm-snapclass
      snapshotOwnerReference: backup
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: postgres-vectorchord-backup
  bootstrap:
    recovery:
      source: postgres-vectorchord
      database: immich
      owner: immich
  externalClusters:
    - name: postgres-vectorchord
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-vectorchord-backup
  storage:
    resizeInUseVolumes: true
    size: $CNPG_STORAGE_SIZE
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
      else
        SNAP_NAME="$($KC -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=$CLUSTER_NAME" -o json | jq -r '[.items[]? | select((.status.readyToUse // false) == true)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name // ""')"
        if [ -z "$SNAP_NAME" ]; then
          echo "ERROR: snapshot restore selected but no ready snapshot is available" >&2
          exit 1
        fi
        $KC -n "$CLUSTER_NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: $CLUSTER_NAME
  namespace: $CLUSTER_NS
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  backup:
    volumeSnapshot:
      className: csi-rbd-rbd-vm-snapclass
      snapshotOwnerReference: backup
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: postgres-vectorchord-backup
  bootstrap:
    recovery:
      database: immich
      owner: immich
      volumeSnapshots:
        storage:
          name: $SNAP_NAME
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  storage:
    resizeInUseVolumes: true
    size: $CNPG_STORAGE_SIZE
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
      fi

      stage "STAGE 6: HEALTH + POST-RESTORE VALIDATION"
      if ! wait_for_cluster_healthy "$CLUSTER_HEALTH_TIMEOUT_SECONDS"; then
        echo "ERROR: CNPG restore did not become healthy in time" >&2
        exit 1
      fi

      $KC -n "$CLUSTER_NS" patch cluster "$CLUSTER_NAME" --type=json -p '[
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
      ]' >/dev/null

      if ! wait_for_database_crs "$DATABASE_CR_TIMEOUT_SECONDS"; then
        echo "ERROR: database CRs did not reach applied=true in time" >&2
        exit 1
      fi

      primary="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
      if [ -z "$primary" ]; then
        echo "ERROR: missing currentPrimary after restore" >&2
        exit 1
      fi
      $KC -n "$CLUSTER_NS" exec "$primary" -- psql -U postgres -Atqc "BEGIN; CREATE TEMP TABLE __ready_probe(id int); INSERT INTO __ready_probe VALUES (1); ROLLBACK;" >/dev/null

      if [ "$RESUME_FLUX_ON_EXIT" = "true" ]; then
        $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null
        RESUME_FLUX_ON_EXIT="false"
      fi

      echo "CNPG restore orchestration complete."
    EOT
    environment = {
      KUBECONFIG                                    = var.kubeconfig_path
      CNPG_NEW_DB                                   = var.cnpg_new_db ? "true" : "false"
      CNPG_RESTORE_MODE                             = var.cnpg_restore_mode
      CNPG_RESTORE_METHOD                           = var.cnpg_restore_method
      CNPG_BACKUP_MAX_AGE_HOURS                     = tostring(var.cnpg_backup_max_age_hours)
      CNPG_STALE_BACKUP_MAX_AGE_MINUTES             = tostring(var.cnpg_stale_backup_max_age_minutes)
      CNPG_STORAGE_SIZE                             = var.cnpg_storage_size
      CNPG_RESTORE_REQUIRED_SECRETS_TIMEOUT_SECONDS = tostring(var.cnpg_restore_required_secrets_timeout_seconds)
      CNPG_RESTORE_FLUX_KUSTOMIZATION_TIMEOUT_SECONDS = tostring(var.cnpg_restore_flux_kustomization_timeout_seconds)
      CNPG_RESTORE_FLUX_KUSTOMIZATION_NAMESPACE       = var.cnpg_restore_flux_kustomization_namespace
      CNPG_RESTORE_FLUX_KUSTOMIZATION_NAME            = var.cnpg_restore_flux_kustomization_name
      CNPG_RESTORE_FLUX_PRECHECK_KUSTOMIZATION_NAME   = var.cnpg_restore_flux_precheck_kustomization_name
      CNPG_RESTORE_RBD_GATE_TIMEOUT_SECONDS         = tostring(var.cnpg_restore_rbd_gate_timeout_seconds)
      CNPG_RESTORE_RBD_SELF_HEAL_RETRIES            = tostring(var.cnpg_restore_rbd_self_heal_retries)
      CNPG_RESTORE_RBD_SELF_HEAL_SETTLE_SECONDS     = tostring(var.cnpg_restore_rbd_self_heal_settle_seconds)
      CNPG_RESTORE_RBD_NODEPLUGIN_NAMESPACE         = var.cnpg_restore_rbd_nodeplugin_namespace
      CNPG_RESTORE_RBD_NODEPLUGIN_DAEMONSET_NAME    = var.cnpg_restore_rbd_nodeplugin_daemonset_name
      CNPG_RESTORE_CLUSTER_HEALTH_TIMEOUT_SECONDS   = tostring(var.cnpg_restore_cluster_healthy_timeout_seconds)
      CNPG_RESTORE_DATABASE_CR_TIMEOUT_SECONDS      = tostring(var.cnpg_restore_database_cr_timeout_seconds)
      CNPG_RESTORE_PROGRESS_STALL_TIMEOUT_SECONDS   = tostring(var.cnpg_restore_progress_stall_timeout_seconds)
      CNPG_OBJECT_STORE_PROBE_MODE                  = var.cnpg_object_store_probe_mode
      CNPG_OBJECT_STORE_PROBE_TIMEOUT_SECONDS       = tostring(var.cnpg_object_store_probe_timeout_seconds)
      CNPG_CLUSTER_NAME                             = "postgres-vectorchord"
      CNPG_CLUSTER_NAMESPACE                        = "default"
      CNPG_KUSTOMIZATION_NAMESPACE                  = "flux-system"
      CNPG_KUSTOMIZATION_NAME                       = "postgres-vectorchord"
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
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["nodes", "pods"]
    verbs: ["get", "list", "watch", "delete"]
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
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: gate-check
          image: public.ecr.aws/bitnami/kubectl:1.34.1
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop:
                - ALL
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

              csi_driver_registered_on_workers() {
                local driver="$1"
                local workers
                local missing=0

                workers=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
                [ -z "$workers" ] && return 1

                while IFS= read -r node; do
                  [ -z "$node" ] && continue
                  has_driver=$(kubectl get csinode "$node" -o json 2>/dev/null | jq -r --arg driver "$driver" '[.spec.drivers[]?.name] | index($driver) != null' || echo false)
                  if [ "$has_driver" != "true" ]; then
                    missing=$((missing + 1))
                  fi
                done <<< "$workers"

                [ "$missing" -eq 0 ]
              }

              workers_missing_csi_driver() {
                local driver="$1"
                local workers

                workers=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
                [ -z "$workers" ] && return 1

                while IFS= read -r node; do
                  [ -z "$node" ] && continue
                  has_driver=$(kubectl get csinode "$node" -o json 2>/dev/null | jq -r --arg driver "$driver" '[.spec.drivers[]?.name] | index($driver) != null' || echo false)
                  if [ "$has_driver" != "true" ]; then
                    echo "$node"
                  fi
                done <<< "$workers"
              }

              restart_nodeplugin_pod_for_node() {
                local ns="$1"
                local ds="$2"
                local node="$3"
                local pod

                pod=$(kubectl -n "$ns" get pods -o json 2>/dev/null | jq -r --arg node "$node" --arg ds "$ds" '
                  [.items[]?
                    | select(.spec.nodeName == $node)
                    | select(any(.metadata.ownerReferences[]?; .kind == "DaemonSet" and .name == $ds))
                    | .metadata.name
                  ] | first // ""' || true)
                if [ -z "$pod" ]; then
                  echo "WARN: no pod from $ds found on $node" >&2
                  return 1
                fi
                echo "WARN: restarting $ds pod $pod on $node" >&2
                kubectl -n "$ns" delete pod "$pod" --ignore-not-found >/dev/null
                return 0
              }

              ensure_csi_driver_on_workers() {
                local driver="$1"
                local nodeplugin_namespace="$2"
                local nodeplugin_daemonset="$3"
                local retries="$4"
                local settle_seconds="$5"
                local attempt=0

                while true; do
                  missing="$(workers_missing_csi_driver "$driver" || true)"
                  if [ -z "$missing" ]; then
                    return 0
                  fi

                  if [ "$attempt" -ge "$retries" ]; then
                    echo "ERROR: $driver missing on worker CSINodes after $attempt self-heal attempt(s): $(echo "$missing" | tr '\n' ',' | sed 's/,$//')" >&2
                    return 1
                  fi

                  attempt=$((attempt + 1))
                  echo "WARN: $driver missing on nodes: $(echo "$missing" | tr '\n' ',' | sed 's/,$//')" >&2
                  while IFS= read -r node; do
                    [ -z "$node" ] && continue
                    restart_nodeplugin_pod_for_node "$nodeplugin_namespace" "$nodeplugin_daemonset" "$node" || true
                  done <<< "$missing"

                  sleep "$settle_seconds"
                done
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
                      deployment_available ceph-csi ceph-csi-rbd-provisioner &&
                      ensure_csi_driver_on_workers cephfs.csi.ceph.com ceph-csi ceph-csi-cephfs-nodeplugin 2 15 &&
                      ensure_csi_driver_on_workers rbd.csi.ceph.com ceph-csi ceph-csi-rbd-nodeplugin 2 15
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
                    gate_ok=false
                    if [ "$gate" = "storage-ready" ]; then
                      # storage-ready must validate live CSI driver registration
                      # on workers (kustomization Ready alone is insufficient).
                      if capability_ready_fallback "$gate"; then
                        gate_ok=true
                      fi
                    else
                      if kustomization_ready "$gate" || capability_ready_fallback "$gate"; then
                        gate_ok=true
                      fi
                    fi

                    if [ "$gate_ok" = "true" ]; then
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

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
    command     = <<-EOT
      set -euo pipefail

      KC="kubectl --kubeconfig=$KUBECONFIG"
      CLUSTER_NS="$CNPG_CLUSTER_NAMESPACE"
      CLUSTER_NAME="$CNPG_CLUSTER_NAME"
      KUSTOMIZATION_NS="$CNPG_KUSTOMIZATION_NAMESPACE"
      KUSTOMIZATION_NAME="$CNPG_KUSTOMIZATION_NAME"
      MAX_AGE_SECONDS=$((CNPG_BACKUP_MAX_AGE_HOURS * 3600))
      STALE_BACKUP_MAX_AGE_SECONDS=$((CNPG_STALE_BACKUP_MAX_AGE_MINUTES * 60))
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
        local loops=$((timeout_seconds / 10))
        local i=0
        while [ "$i" -lt "$loops" ]; do
          phase="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
          if echo "$phase" | grep -qi "healthy"; then
            return 0
          fi
          sleep 10
          i=$((i + 1))
        done
        return 1
      }

      wait_for_database_crs() {
        local timeout_seconds="$1"
        local loops=$((timeout_seconds / 10))
        local i=0
        while [ "$i" -lt "$loops" ]; do
          pending="$($KC -n "$CLUSTER_NS" get databases.postgresql.cnpg.io -o json 2>/dev/null | jq -r '[.items[]? | select((.status.applied // false) != true) | .metadata.name] | join(",")' || true)"
          if [ -z "$pending" ] || [ "$pending" = "null" ]; then
            return 0
          fi
          sleep 10
          i=$((i + 1))
        done
        return 1
      }

      wait_for_required_secrets() {
        local timeout_seconds="$1"
        shift
        local loops=$((timeout_seconds / 5))
        local i=0
        while [ "$i" -lt "$loops" ]; do
          local missing=0
          for s in "$@"; do
            if ! $KC -n "$CLUSTER_NS" get secret "$s" >/dev/null 2>&1; then
              missing=$((missing + 1))
            fi
          done
          if [ "$missing" -eq 0 ]; then
            return 0
          fi
          sleep 5
          i=$((i + 1))
        done
        return 1
      }

      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "CNPG RESTORE ORCHESTRATION (INLINE)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Mode: $CNPG_RESTORE_MODE"
      echo "Restore method preference: $CNPG_RESTORE_METHOD"

      if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required for CNPG restore orchestration" >&2
        exit 1
      fi

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
        echo "ERROR: no fresh backup found and CNPG_RESTORE_MODE=RESTORE_REQUIRED" >&2
        exit 1
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

      if ! wait_for_required_secrets 300 \
        "cnpg-barman-s3" \
        "atuin-pg-password" \
        "authentik-pg-password" \
        "firefly-pg-password" \
        "paperless-pg-password"; then
        echo "ERROR: required CNPG secrets did not become ready in time" >&2
        exit 1
      fi

      $KC -n "$CLUSTER_NS" delete cluster "$CLUSTER_NAME" --ignore-not-found --wait=true >/dev/null || true
      $KC -n "$CLUSTER_NS" delete pvc "$${CLUSTER_NAME}-1" --ignore-not-found --wait=true >/dev/null || true

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
  managed:
    roles:
      - name: atuin
        login: true
        ensure: present
        passwordSecret:
          name: atuin-pg-password
      - name: authentik
        login: true
        ensure: present
        passwordSecret:
          name: authentik-pg-password
      - name: firefly
        login: true
        ensure: present
        passwordSecret:
          name: firefly-pg-password
      - name: paperless
        login: true
        ensure: present
        passwordSecret:
          name: paperless-pg-password
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
  managed:
    roles:
      - name: atuin
        login: true
        ensure: present
        passwordSecret:
          name: atuin-pg-password
      - name: authentik
        login: true
        ensure: present
        passwordSecret:
          name: authentik-pg-password
      - name: firefly
        login: true
        ensure: present
        passwordSecret:
          name: firefly-pg-password
      - name: paperless
        login: true
        ensure: present
        passwordSecret:
          name: paperless-pg-password
  storage:
    resizeInUseVolumes: true
    size: $CNPG_STORAGE_SIZE
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
      fi

      if ! wait_for_cluster_healthy 1200; then
        echo "ERROR: CNPG restore did not become healthy in 20 minutes" >&2
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

      if ! wait_for_database_crs 600; then
        echo "ERROR: database CRs did not reach applied=true in 10 minutes" >&2
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
      KUBECONFIG                        = var.kubeconfig_path
      CNPG_NEW_DB                       = var.cnpg_new_db ? "true" : "false"
      CNPG_RESTORE_MODE                 = var.cnpg_restore_mode
      CNPG_RESTORE_METHOD               = var.cnpg_restore_method
      CNPG_BACKUP_MAX_AGE_HOURS         = tostring(var.cnpg_backup_max_age_hours)
      CNPG_STALE_BACKUP_MAX_AGE_MINUTES = tostring(var.cnpg_stale_backup_max_age_minutes)
      CNPG_STORAGE_SIZE                 = var.cnpg_storage_size
      CNPG_CLUSTER_NAME                 = "postgres-vectorchord"
      CNPG_CLUSTER_NAMESPACE            = "default"
      CNPG_KUSTOMIZATION_NAMESPACE      = "flux-system"
      CNPG_KUSTOMIZATION_NAME           = "postgres-vectorchord"
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

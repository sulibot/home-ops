#!/usr/bin/env bash
# Validate Flux kustomization graph metadata and dependency hygiene.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v yq >/dev/null 2>&1; then
  echo "❌ yq is required (https://github.com/mikefarah/yq)"
  exit 1
fi

errors=0
checked_files=0
checked_docs=0

require_any_dep() {
  local file="$1"
  local doc="$2"
  local depends="$3"
  local description="$4"
  shift 4

  local match=0
  local req
  for req in "$@"; do
    if printf "%s\n" "$depends" | grep -Fqx "$req"; then
      match=1
      break
    fi
  done

  if [[ "$match" -eq 0 ]]; then
    echo "❌ $file#doc${doc}: ${description} requires dependsOn one of: $*"
    errors=$((errors + 1))
  fi
}

mapfile -t files < <(rg --files kubernetes/apps | rg '/ks\.ya?ml$' | sort)

for f in "${files[@]}"; do
  checked_files=$((checked_files + 1))

  # Evaluate each YAML document independently; some ks.yaml files are multi-doc.
  doc_indexes="$(yq e 'documentIndex' "$f" 2>/dev/null | sort -u || true)"
  if [[ -z "$doc_indexes" ]]; then
    continue
  fi

  for doc in $doc_indexes; do
    kind="$(yq e "select(documentIndex == ${doc}) | .kind // \"\"" "$f" 2>/dev/null || true)"
    if [[ "$kind" != "Kustomization" ]]; then
      continue
    fi
    checked_docs=$((checked_docs + 1))

    layer="$(yq e "select(documentIndex == ${doc}) | .metadata.labels.layer // \"\"" "$f" 2>/dev/null || true)"
    tier="$(yq e "select(documentIndex == ${doc}) | .metadata.labels.tier // \"\"" "$f" 2>/dev/null || true)"
    if [[ -z "$layer" && -z "$tier" ]]; then
      echo "❌ $f#doc${doc}: missing metadata.labels.layer or metadata.labels.tier"
      errors=$((errors + 1))
    fi

    # Ensure top-level tier kustomizations keep explicit tier labels.
    case "$f" in
      kubernetes/apps/tier-0-foundation/ks.yaml|kubernetes/apps/tier-1-infrastructure/ks.yaml|kubernetes/apps/tier-2-applications/ks.yaml)
        if [[ -z "$tier" ]]; then
          echo "❌ $f#doc${doc}: top-level tier ks must set metadata.labels.tier"
          errors=$((errors + 1))
        fi
        ;;
    esac

    # Detect duplicate dependencies in a single document.
    depends="$(yq e "select(documentIndex == ${doc}) | .spec.dependsOn[].name // \"\"" "$f" 2>/dev/null | sed '/^$/d' || true)"
    if [[ -n "$depends" ]]; then
      dups="$(printf "%s\n" "$depends" | sort | uniq -d || true)"
      if [[ -n "$dups" ]]; then
        echo "❌ $f#doc${doc}: duplicate dependsOn entries: $(echo "$dups" | tr '\n' ' ' | sed 's/ $//')"
        errors=$((errors + 1))
      fi
    fi

    # Keep tier-2 bootstrap parallel to tier-1; use capability signals instead.
    if [[ "$f" == kubernetes/apps/tier-2-applications/* ]] && [[ "$f" != kubernetes/apps/tier-2-applications/ks.yaml ]]; then
      if yq e "select(documentIndex == ${doc}) | .spec.dependsOn[].name // \"\"" "$f" 2>/dev/null | grep -qx 'tier-1-infrastructure'; then
        echo "❌ $f#doc${doc}: depends on tier-1-infrastructure; prefer capability signals (secrets/storage/db/identity-ready)."
        errors=$((errors + 1))
      fi
    fi

    # CRD dependency contract checks:
    # If an app applies CRD-backed resources, it must declare dependency on the
    # controller/CRD provider kustomization so Flux doesn't race CRD creation.
    app_path="$(yq e "select(documentIndex == ${doc}) | .spec.path // \"\"" "$f" 2>/dev/null || true)"
    app_path="${app_path#./}"
    if [[ -n "$app_path" ]] && [[ -d "$app_path" ]]; then
      case "$app_path" in
        kubernetes/apps/tier-0-foundation|kubernetes/apps/tier-1-infrastructure|kubernetes/apps/tier-2-applications)
          # Aggregate tier entrypoints are intentionally broad and not app-specific.
          ;;
        *)
          kustomization_file=""
          if [[ -f "$app_path/kustomization.yaml" ]]; then
            kustomization_file="$app_path/kustomization.yaml"
          elif [[ -f "$app_path/kustomization.yml" ]]; then
            kustomization_file="$app_path/kustomization.yml"
          fi

          uses_prometheus_rule=false
          uses_probe=false
          uses_grafana_dashboard=false

          if [[ -n "$kustomization_file" ]]; then
            mapfile -t resource_entries < <(yq e '.resources[] // ""' "$kustomization_file" 2>/dev/null | sed '/^$/d' || true)
            for entry in "${resource_entries[@]}"; do
              case "$entry" in
                http://*|https://*|git::*) continue ;;
              esac

              resource_path="$app_path/$entry"
              if [[ ! -e "$resource_path" ]]; then
                continue
              fi

              if [[ "$uses_prometheus_rule" == "false" ]] && rg --glob '*.yaml' --glob '*.yml' --quiet '^[[:space:]]*kind:[[:space:]]*PrometheusRule([[:space:]]|$)' "$resource_path"; then
                uses_prometheus_rule=true
              fi

              if [[ "$uses_probe" == "false" ]] && rg --glob '*.yaml' --glob '*.yml' --quiet '^[[:space:]]*kind:[[:space:]]*Probe([[:space:]]|$)' "$resource_path"; then
                uses_probe=true
              fi

              if [[ "$uses_grafana_dashboard" == "false" ]] && rg --glob '*.yaml' --glob '*.yml' --quiet '^[[:space:]]*kind:[[:space:]]*GrafanaDashboard([[:space:]]|$)' "$resource_path"; then
                uses_grafana_dashboard=true
              fi
            done
          fi

          if [[ "$uses_prometheus_rule" == "true" ]]; then
            require_any_dep "$f" "$doc" "$depends" "PrometheusRule resources" "kube-prometheus-stack" "monitoring-ready"
          fi

          if [[ "$uses_probe" == "true" ]]; then
            require_any_dep "$f" "$doc" "$depends" "Probe resources" "kube-prometheus-stack" "monitoring-ready"
          fi

          if [[ "$uses_grafana_dashboard" == "true" ]]; then
            require_any_dep "$f" "$doc" "$depends" "GrafanaDashboard resources" "kube-prometheus-stack" "grafana" "grafana-instance" "grafana-operator" "monitoring-ready"
          fi
          ;;
      esac
    fi
  done
done

echo "Checked ${checked_docs} Flux Kustomization documents across ${checked_files} files."

if [[ "$errors" -gt 0 ]]; then
  echo "❌ Flux graph lint failed with ${errors} issue(s)."
  exit 1
fi

echo "✅ Flux graph lint passed."
